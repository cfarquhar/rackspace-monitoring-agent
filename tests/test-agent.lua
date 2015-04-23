--[[
Copyright 2014 Rackspace

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

require('tap')(function(test)
  local async = require('async')
  local Agent = require('../agent').Agent

  test('test endpoints', function()
    async.series({
      function(callback)
        -- Test Service Net
        local serviceNets = {
          'dfw',
          'ord',
          'lon',
          'syd',
          'hkg',
          'iad'
        }
        local function iter(location, callback)
          local options = {
            ['config'] = { ['snet_region'] = location }
          }
          local ag = Agent:new(options)
          ag:loadEndpoints(function(err, endpoints)
            assert(not err)
            assert(#endpoints == 3)
            for i, _ in ipairs(endpoints) do
              assert(endpoints[i]['srv_query']:find('snet%-'..location) ~= nil)
            end
            callback()
          end)
        end
        async.forEach(serviceNets, iter, callback)
      end,
      function(callback)
        -- Test 1 Custom Endpoints
        local options = {
          ['config'] = { ['endpoints'] = '127.0.0.1:5040', }
        }
        local ag = Agent:new(options)
        ag:loadEndpoints(function(err, endpoints)
          assert(not err)
          assert(#endpoints == 1)
          assert(endpoints[1].host == '127.0.0.1')
          assert(endpoints[1].port == 5040)
          callback()
        end)
      end,
      function(callback)
        -- Test 3 Custom Endpoints
        local options = {
          ['config'] = { ['endpoints'] = '127.0.0.1:5040,127.0.0.1:5041,127.0.0.1:5042', }
        }
        local ag = Agent:new(options)
        ag:loadEndpoints(function(err, endpoints)
          assert(err == nil)
          assert(#endpoints == 3)
          assert(endpoints[1].host == '127.0.0.1')
          assert(endpoints[1].port== 5040)
          assert(endpoints[2].host == '127.0.0.1')
          assert(endpoints[2].port== 5041)
          assert(endpoints[3].host == '127.0.0.1')
          assert(endpoints[3].port== 5042)
          callback()
        end)
      end,
      function(callback)
        -- Test query_endpoints
        local options = {
          ['config'] = { ['query_endpoints'] = 'srv1,srv2,srv3', }
        }
        local ag = Agent:new(options)
        ag:loadEndpoints(function(err, endpoints)
          assert(not err)
          assert(#endpoints == 3)
          for i, _ in ipairs(endpoints) do
            assert(endpoints[i]['srv_query']:find('srv'..i) ~= nil)
          end
          callback()
        end)
      end,
      function(callback)
        -- Add nil case with no selections
        --   This is the default use case
        local options = { ['config'] = {} }
        local ag = Agent:new(options)
        ag:loadEndpoints(function(err, endpoints)
          assert(not err)
          assert(#endpoints == 3)
          for i, _ in ipairs(endpoints) do
            assert(endpoints[i]['srv_query'])
          end
          callback()
        end)
      end
    })
  end)
end)
