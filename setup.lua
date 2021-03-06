--[[
Copyright 2015 Rackspace

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--]]

local JSON = require('json')
local MachineIdentity = require('virgo/machineidentity').MachineIdentity
local Object = require('core').Object
local ask = require('virgo/util/prompt').ask
local async = require('async')
local constants = require('./constants')
local errors = require('virgo/errors')
local fmt = require('string').format
local fs = require('fs')
local hostname = require('./hostname')
local los = require('los')
local maas = require('rackspace-monitoring-client')
local sigar = require('sigar')
local table = require('table')
local timer = require('timer')

local Setup = Object:extend()
function Setup:initialize(argv, configFile, agent)
  self._configFile = configFile
  self._agent = agent
  self._receivedPromotion = false
  self._username = argv.args.U
  self._apikey = argv.args.K
  self._autoCreateEntity = argv.args.A
  self._noEntityCreate = argv.args.N
  self._agent:on('promote', function()
    self._receivedPromotion = true
  end)
  self._addresses = {}

  -- disable upgrades on setup
  self._agent:disableUpgrades()

  -- build a "set" (table keyed by address) of local IP addresses
  local sigarCtx = sigar:new()
  local netifs = sigarCtx:netifs()

  for i=1,#netifs do
    local info = netifs[i]:info()
    if info['address'] then
      self._addresses[info['address']] = true
    end
    if info['addres6'] then
      self._addresses[info['address6']] = true
    end
  end
end

function Setup:saveTest(callback)
  fs.open(self._configFile, 'a', "0644", function(err)
    if err then
      process.stdout:write(fmt('Error: cannot open config file: %s\n', self._configFile))
      callback(err)
      return
    end
    callback()
  end)
end

function Setup:save(token, agent_id, write_agent_id, callback)
  process.stdout:write(fmt('Writing token to %s: ', self._configFile))

  local data = fmt('monitoring_token %s\n', token)
  local proxy = process.env.HTTP_PROXY or process.env.HTTPS_PROXY

  if write_agent_id then
    data = data .. fmt('monitoring_id %s\n', agent_id)
  end

  if proxy then
    data = data .. fmt('monitoring_proxy_url %s\n', proxy)
  end

  --[[
  1. We are using an environment variable because we thought adding special hidden
  command line arguments logic may make it too complex.

  2. this feature will be ran by such a small set of people who are very
  technically minded anyways so setting an environment variable is OK.
  ]]--
  local _, err = fs.writeFileSync(self._configFile, data)
  if err then
    process.stdout:write(string.format('failed writing config file : %s\n', err))
    return callback(err)
  end
  callback()
end

function Setup:_out(msg)
  process.stdout:write(msg .. '\n')
end

function Setup:_getOsStartString()
  if los.type() == "win32" then
    return 'This agent is controlled by the Windows Service Manager.'
  else
    return 'service rackspace-monitoring-agent start'
  end
end

function Setup:_isLocalEntity(agentId, entity)
  if entity.label == agentId then
    return true
  end

  if entity.ip_addresses then
    for k, address in pairs(entity.ip_addresses) do
      -- TODO: we should really translate all v6 addresses to a standard form
      -- for this comparison, currently there is a good chance of us missing a
      -- v6 match
      if self._addresses[address] then
        return true
      end
    end
  end

  return false
end

function Setup:_buildLocalEntity(agentId)
  local addresses = {}
  local ctx = sigar:new()
  local netifs = ctx:netifs()

  for i=1,#netifs do
    local info = netifs[i]:info()
    if info.type ~= 'Local Loopback' then
      if info['address'] then
        addresses[info['name'] .. '_v4'] = info['address']
      end
      if info['address6'] then
        addresses[info['name'] .. '_v6'] = info['address6']
      end
    end
  end

  return {
    label = agentId,
    agent_id = agentId,
    ip_addresses = addresses
  }
end

function Setup:run(callback)
  local username, token
  local agentToken, client, agentId
  local writeAgentId = false

  local function createToken(label, callback)
    client.agent_tokens.create({ ['label'] = label }, function(err, token)
      if err then
        callback(err)
        return
      end
      self._agent:setConfig({ ['token'] = token, ['id'] = agentId })
      self:save(token, agentId, writeAgentId, callback)
    end)
  end

  async.waterfall({
    function(callback)
      local machid = MachineIdentity:new({})
      machid:get(function(err, results)
        if err then
          return callback()
        end
        if results.id then
          agentId = results.id
          writeAgentId = false
        end
        callback()
      end)
    end,
    function(callback)
      if not agentId then
        agentId = hostname()
        writeAgentId = true
      end
      callback()
    end,
    function(callback)
      self:_out('')
      self:_out('Setup Settings:')
      self:_out(fmt('  Agent ID: %s', agentId))
      self:_out(fmt('  Config File: %s', self._configFile))
      self:_out('')
      callback()
    end,
    function(callback)
      self:saveTest(callback)
    end,
    function(callback)
      if (self._username == nil and self._apikey ~= nil)
         or (self._username ~= nil and self._apikey == nil) then
        callback(errors.UserResponseError:new('Username and password/apikey must be provided together.'))
      else
        callback()
      end
    end,
    function(callback)
      if self._username == nil then
        ask('Username:', callback)
      else
        callback(nil, self._username)
      end
    end,
    function(_username, callback)
      if self._apikey == nil then
        ask('API Key or Password:', function(err, _token)
          username = _username
          token = _token
          callback(err, username, token)
        end)
      else
        callback(nil, self._username, self._apikey)
      end
    end,
    -- fetch all tokens
    function(username, token, callback)
      local options = {}
      options.user_agent = fmt('rackspace-monitoring-agent/%s:%s; %s', virgo.virgo_version, virgo.bundle_version, username)
      client = maas.Client:new(username, token, options)
      client:setMFACallback(function(callback)
        ask('MFA Token:', callback)
      end)
      client.agent_tokens.get(callback)
    end,
    -- is there a token for the host
    function(tokens, callback)
      for i, v in ipairs(tokens.values) do
        if v.label == agentId then
          agentToken = v.token
          break
        end
      end
      callback(nil, agentToken, tokens)
    end,
    function(agentToken, tokens, callback)
      -- save the token if we found it
      if agentToken then
        self:_out('')
        self:_out(fmt('Found existing Agent Token for %s', agentId))
        self:_out('')
        self._agent:setConfig({ ['token'] = agentToken, ['id'] = agentId })
        self:save(agentToken, agentId, writeAgentId, callback)
        -- display a list of tokens
      elseif self._username and self._apikey then
         createToken(agentId, callback)
      elseif #tokens.values > 0 then
        self:_out('')
        self:_out('The Monitoring Agent uses an authentication token to communicate with the Cloud Monitoring Service.')
        self:_out('')
        self:_out('Please select from an existing token, or create a new token:')
        for i, v in ipairs(tokens.values) do
          if v.label then
            self:_out(fmt('  %i. %s - %s', i, v.label, v.id))
          else
            self:_out(fmt('  %i. %s', i, v.id))
          end
        end
        self:_out(fmt('  %i. Create New Token', #tokens.values + 1))
        self:_out('')

        ask('Select Option:', function(err, index)
          if err then
            callback(err)
            return
          end
          self:_out('')
          local validatedIndex = tonumber(index) -- validate response
          if validatedIndex >= 1 and validatedIndex <= #tokens.values then
            self._agent:setConfig({ ['token'] = tokens.values[validatedIndex].id, ['id'] = agentId })
            self:save(tokens.values[validatedIndex].id, agentId, writeAgentId, callback)
          elseif validatedIndex == (#tokens.values + 1) then
            createToken(agentId, callback)
          else
            callback(errors.UserResponseError:new('User input is not valid. Expected integer.'))
          end
        end)
        -- create a token and save it
      else
        createToken(agentId, callback)
      end
    end,
    -- test connectivity
    function(callback)
      self:_out('')
      self:_out('Testing Agent connectivity to Cloud Monitoring Service...')
      self:_out('')
      async.series({
        function(callback)
          self._agent:loadEndpoints(callback)
        end,
        function(callback)
          self._agent:_preConfig(callback)
        end,
        function(callback)
          self._agent:connect()
          callback()
        end,
        function(callback)
          local function timeout()
            callback(errors.AuthTimeoutError:new('Authentication timed out.'))
          end

          local authTimer = timer.setTimeout(constants:get('SETUP_AUTH_TIMEOUT'), timeout)

          local function testAuth()
            timer.clearTimer(authTimer)
            if self._receivedPromotion then
              self:_out('')
              self:_out('Agent successfully connected!')
              callback()
            else
              authTimer = timer.setTimeout(constants:get('SETUP_AUTH_TIMEOUT'), timeout)
              timer.setTimeout(constants:get('SETUP_AUTH_CHECK_INTERVAL'), testAuth)
            end
          end

          timer.setTimeout(constants:get('SETUP_AUTH_CHECK_INTERVAL'), testAuth)
        end
      }, callback)
    end,

    -- Bind to an entity
    function(connections, callback)
      self:_out('')
      self:_out('In order to execute checks, the agent must be associated with a Cloud Monitoring Entity.')
      self:_out('')
      async.waterfall({
        function(callback)
          client.entities.list(callback)
        end,
        function(entities, callback)
          local localEntities = {}

          local function displayEntities()
            for i, entity in ipairs(localEntities) do
              if entity.label then
                self:_out(fmt('  %i. %s - %s', i, entity.label, entity.id))
              else
                self:_out(fmt('  %i. %s', i, entity.id))
              end
              if entity.ip_addresses then
                for k, address in pairs(entity.ip_addresses) do
                  self:_out(fmt('       %s: %s', k, address))
                end
              end
            end
          end

          for i, entity in ipairs(entities.values) do
            if entity.agent_id == agentId then
              self:_out(fmt('Agent already associated Entity with id=%s and label=%s', entity.id, entity.label))
              return callback()
            end
            if self:_isLocalEntity(agentId, entity) then
              table.insert(localEntities, entity)
            end
          end

          local function entitySelection()

            local function createEntity(callback)
              local function onCreate(err, entity)
                if err then return callback(err) end
                self:_out('')
                self:_out(fmt('New Entity Created: %s', entity))
                callback(nil, entity)
              end
              client.entities.create(self:_buildLocalEntity(agentId), onCreate)
            end

            if self._autoCreateEntity then
              return createEntity(callback)
            end

            if self._noEntityCreate then
              return callback()
            end

            self:_out('Please select the Entity that corresponds to this server:')
            displayEntities()
            self:_out(fmt('  %i. Create a new Entity for this server (Entities can be viewed within Rackspace Intelligence - https://intelligence.rackspace.com)', #localEntities + 1))
            self:_out(fmt('  %i. Do not associate with an Entity', #localEntities + 2))
            self:_out('')

            ask('Select Option (e.g., 1, 2):', function(err, index)
              if err then
                return callback(err)
              end
              local validatedIndex = tonumber(index)
              if validatedIndex == #localEntities + 1 then
                createEntity(callback)
              elseif validatedIndex == #localEntities + 2 then
                callback()
              elseif validatedIndex >= 1 and validatedIndex <= #localEntities then
                client.entities.update(localEntities[validatedIndex].id, { agent_id = agentId }, callback)
              else
                self:_out('')
                self:_out('Invalid selection')
                entitySelection()
              end
            end)
          end

          entitySelection()
        end
      }, callback)
    end
  }, function(err)
    if err then
      local msg = nil
      if type(err) == 'string' then
        msg = err
      elseif err.message then
        msg = err.message
      elseif err.data then
        pcall(function() msg = JSON.parse(err.data).message end)
      end
      if not msg then
        msg = JSON.stringify(err)
      end
      process.stdout:write(fmt('Error: %s\n', msg))
    else
      -- TODO: detect Platform, iniit.d system, etc
      self:_out('')
      self:_out('Your Agent configuration is now complete.')
      self:_out('')
      self:_out('To start the Agent on your server, now run:')
      self:_out('')
      self:_out(fmt('    %s', self:_getOsStartString()))
      self:_out('')
      self:_out('')
    end
    process.nextTick(function()
      process:exit(0)
    end)
  end)

end

exports.Setup = Setup
