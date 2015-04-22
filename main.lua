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

local function start(...)
  local async = require('async')
  local fs = require('fs')
  local logging = require('logging')
  local los = require('los')
  local uv = require('uv')

  local MonitoringAgent = require('./agent').Agent
  local Setup = require('./setup').Setup
  local agentClient = require('./client/virgo_client')
  local certs = require('./certs')
  local connectionStream = require('./client/virgo_connection_stream')
  local constants = require('./constants')
  local protocolConnection = require('./protocol/virgo_connection')
  local upgrade = require('virgo/client/upgrade')

  local log_level

  local gcCollect = uv.new_prepare()
  uv.prepare_start(gcCollect, function() collectgarbage('step') end)
  uv.unref(gcCollect)

  process:on('sighup', function()
    logging.info('Received SIGHUP. Rotating logs.')
    logging.rotate()
  end)

  local argv = require('options')
    .describe("i", "use insecure tls cert")
    .describe("l", "log file path")
    .describe("e", "entry module")
    .describe("x", "runner params (eg. check or hostinfo to run)")
    .describe("s", "state directory path")
    .describe("c", "config file path")
    .describe("j", "object conf.d path")
    .describe("p", "pid file path")
    .describe("z", "lock file path")
    .describe("o", "skip automatic upgrade")
    .describe("d", "enable debug logging")
    .describe("l", "log file")
    .alias({['o'] = 'no-upgrade'})
    .alias({['p'] = 'pidfile'})
    .alias({['j'] = 'confd'})
    .alias({['l'] = 'logfile'})
    .describe("l", "logfile")
    .alias({['d'] = 'debug'})
    .describe("u", "setup")
    .alias({['u'] = 'setup'})
    .describe("U", "username")
    .alias({['U'] = 'username'})
    .describe("K", "apikey")
    .alias({['K'] = 'apikey'})
    .argv("idonhl:U:K:e:x:p:c:j:s:n:k:uz:")

  argv.usage('Usage: ' .. argv.args['$0'] .. ' [options]')

  if argv.args.h then
    argv.showUsage("idonhU:K:e:x:p:c:j:s:n:k:ul:z:")
    process:exit(0)
  end

  local function readConfig(path)
    local config, data, err
    config = {}
    data, err = fs.readFileSync(path)
    if err then return {} end
    for line in data:gmatch("[^\r\n]+") do
      local key, value = line:match("(%S+) (.*)")
      config[key] = value
    end
    return config
  end

  if argv.args.d or argv.args.u then
    log_level = logging.LEVELS['everything']
  end

  -- Setup Logging
  logging.init(logging.StdoutFileLogger:new({
    log_level = log_level,
    path = argv.args.l
  }))

  local options = {}
  options.configFile = argv.args.c or constants:get('DEFAULT_CONFIG_PATH')

  if argv.args.p then
    options.pidFile = argv.args.p
  end

  if argv.args.z then
    options.lockFile = argv.args.z
  end

  if argv.args.e then
    local mod = require('./runners/' .. argv.args.e)
    return mod.run(argv.args)
  end

  local types = {}
  types.ProtocolConnection = protocolConnection
  types.AgentClient = agentClient
  types.ConnectionStream = connectionStream

  if not argv.args.x then
    virgo.config = readConfig(options.configFile) or {}
    options.config = virgo.config
  end

  options.tls = {}
  options.tls.rejectUnauthorized = true
  options.tls.ca = certs.caCerts

  virgo.config['token'] = virgo.config['monitoring_token']
  virgo.config['endpoints'] = virgo.config['monitoring_endpoints']
  virgo.config['upgrade'] = virgo.config['monitoring_upgrade']
  virgo.config['id'] = virgo.config['monitoring_id']
  virgo.config['guid'] = virgo.config['monitoring_guid']
  virgo.config['query_endpoints'] = virgo.config['monitoring_query_endpoints']
  virgo.config['snet_region'] = virgo.config['monitoring_snet_region']
  virgo.config['proxy'] = virgo.config['monitoring_proxy_url']
  virgo.config['insecure'] = virgo.config['monitoring_insecure']
  virgo.config['debug'] = virgo.config['monitoring_debug']

  if argv.args.i or virgo.config['insecure'] == 'true' then
    options.tls.ca = certs.caCertsDebug
  end

  options.proxy = process.env.HTTP_PROXY or process.env.HTTPS_PROXY
  if virgo.config['proxy'] then
    options.proxy = virgo.config['proxy']
  end

  options.upgrades_enabled = true
  if argv.args.o or virgo.config['upgrade'] == 'disabled' then
    options.upgrades_enabled = false
  end

  async.series({
    function(callback)
      if los.type() ~= 'win32' then
        upgrade.attempt({ skip = options.upgrades_enabled == false }, function(err)
          if err then
            logging.log(logging.ERROR, string.format("Error upgrading: %s", tostring(err)))
          end
          callback()
        end)
      else
        --on windows the upgrade occurs right after the download as an external process
        callback()
      end
    end,
    function(callback)
      local agent = MonitoringAgent:new(options, types)
      if argv.args.u then
        Setup:new(argv, options.configFile, agent):run()
      else
        agent:start(options)
      end
      callback()
    end
  })
end

return require('luvit')(function(...)
  local options = {}
  options.version = require('./package').version
  options.pkg_name = "rackspace-monitoring-agent"
  options.paths = {}
  options.paths.persistent_dir = "/var/lib/rackspace-monitoring-agent"
  options.paths.exe_dir = "/var/lib/rackspace-monitoring-agent/exe"
  options.paths.config_dir = "/etc"
  options.paths.library_dir = "/usr/lib/rackspace-monitoring-agent"
  options.paths.runtime_dir = "/var/run/rackspace-monitoring-agent"
  options.paths.current_exe = args[0]
  require('virgo')(options, start)
end)
