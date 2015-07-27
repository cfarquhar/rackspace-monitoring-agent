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
local HostInfo = require('../hostinfo')
local json = require('json')
local upper = require('string').upper

local function run(...)
  local argv, typeName, klass
  argv = require("options")
    .usage('Usage: -x [Host Info Type]')
    .describe("x", "host info type to run")
    .argv("x:")

  if not argv.args.x then
    print(argv._usage)
    process:exit(0)
  end

  typeName = upper(argv.args.x)
  klass = HostInfo.create(typeName)
  klass:run(function(err, callback)
    if err then
      print(json.stringify({error = err}))
    else
      print(json.stringify(klass:serialize()))
    end
  end)
end

return { run = run }
