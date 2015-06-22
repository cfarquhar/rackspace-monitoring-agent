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

local const = require('virgo/util/constants_ctx')
local path = require('path')

local SNET_REGIONS = {
  'dfw',
  'ord',
  'lon',
  'syd',
  'hkg',
  'iad'
}

local constants = const.ConstantsCtx:new()
constants:setGlobal('DEFAULT_CUSTOM_PLUGINS_PATH', path.join(const.LIBRARY_DIR, 'plugins'))
constants:setGlobal('DEFAULT_PLUGIN_TIMEOUT', 60 * 1000)
constants:setGlobal('PLUGIN_TYPE_MAP', {string = 'string', int = 'int64', float = 'double', gauge = 'gauge'})
constants:setGlobal('CRASH_REPORT_URL', 'https://monitoring.api.rackspacecloud.com/agent-crash-report')
constants:setGlobal('DEFAULT_PID_FILE_PATH', '/var/run/rackspace-monitoring-agent.pid')
constants:setGlobal('DEFAULT_LOCK_FILE_PATH', '/var/run/rackspace-monitoring-agent.lock')
constants:setGlobal('DEFAULT_CONFD_PATH', '/etc/rackspace-monitoring-agent.conf.d')
constants:setGlobal('VALID_SNET_REGION_NAMES', SNET_REGIONS)
constants:setGlobal('SETUP_AUTH_CHECK_INTERVAL', 1000)
constants:setGlobal('SETUP_AUTH_TIMEOUT', 10000)

constants:setGlobal('DEFAULT_MONITORING_SRV_QUERIES_STAGING', {
  '_monitoringagent._tcp.dfw1.stage.monitoring.api.rackspacecloud.com',
  '_monitoringagent._tcp.ord1.stage.monitoring.api.rackspacecloud.com',
  '_monitoringagent._tcp.lon3.stage.monitoring.api.rackspacecloud.com'
})

constants:setGlobal('SNET_MONITORING_TEMPLATE_SRV_QUERIES_STAGING', {
  '_monitoringagent._tcp.snet-${region}-region0.stage.monitoring.api.rackspacecloud.com',
  '_monitoringagent._tcp.snet-${region}-region1.stage.monitoring.api.rackspacecloud.com',
  '_monitoringagent._tcp.snet-${region}-region2.stage.monitoring.api.rackspacecloud.com'
})

constants:setGlobal('DEFAULT_MONITORING_SRV_QUERIES', {
  '_monitoringagent._tcp.dfw1.prod.monitoring.api.rackspacecloud.com',
  '_monitoringagent._tcp.ord1.prod.monitoring.api.rackspacecloud.com',
  '_monitoringagent._tcp.lon3.prod.monitoring.api.rackspacecloud.com'
})

constants:setGlobal('SNET_MONITORING_TEMPLATE_SRV_QUERIES', {
  '_monitoringagent._tcp.snet-${region}-region0.prod.monitoring.api.rackspacecloud.com',
  '_monitoringagent._tcp.snet-${region}-region1.prod.monitoring.api.rackspacecloud.com',
  '_monitoringagent._tcp.snet-${region}-region2.prod.monitoring.api.rackspacecloud.com'
})

constants:setGlobal('METRIC_STATUS_MAX_LENGTH', 256)

constants:setGlobal('MAX_CHECK_PERIOD', 1800000) -- 30 minute check period (milliseconds)
constants:setGlobal('CHECK_SCHEDULE_JITTER', 15000) -- milliseconds

return constants
