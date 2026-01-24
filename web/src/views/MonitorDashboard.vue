<template>
  <div class="monitor-dashboard-container">
    <a-alert
      v-if="!connected"
      message="Disconnected"
      description="Connection lost. Reconnecting..."
      type="error"
      show-icon
      style="margin-bottom: 24px"
    />

    <div style="display: flex; justify-content: flex-start; margin-bottom: 5px">
      <a-radio-group v-model:value="viewMode" button-style="solid">
        <a-radio-button value="card">
          <AppstoreOutlined />
        </a-radio-button>
        <a-radio-button value="list">
          <UnorderedListOutlined />
        </a-radio-button>
      </a-radio-group>
    </div>

    <!-- Card View -->
    <a-row :gutter="[5, 5]" v-if="viewMode === 'card'">
      <a-col :xs="24" :sm="12" :md="8" class="col-5" v-for="host in sortedHosts" :key="host.host_id">
        <a-card hoverable class="monitor-card" :class="{ offline: isOffline(host) }">
          <template #title>
            <a-space>
              <component :is="getOsIcon(host.os)" :style="{ fontSize: '20px' }" />
              <span>{{ getHostName(host.host_id) }}</span>
              <span style="color: #8c8c8c; font-size: 12px">({{ host.hostname }})</span>
            </a-space>
          </template>
          <template #extra>
             <a-tooltip :title="t('network.title')">
                <a-button type="text" shape="circle" @click="$router.push({ name: 'NetworkDetail', params: { id: host.host_id } })">
                    <template #icon><LineChartOutlined /></template>
                </a-button>
             </a-tooltip>
             <a-tooltip :title="isMonitorOnly(host.host_id) ? t('host.monitorOnly') : t('terminal.connect')">
                <a-button type="text" shape="circle" @click="handleConnect(host)" :disabled="isMonitorOnly(host.host_id)">
                    <template #icon><CodeOutlined /></template>
                </a-button>
             </a-tooltip>
             <a-tooltip :title="t('monitor.history')">
                <a-button type="text" shape="circle" @click="showHistory(host.host_id)">
                    <template #icon><HistoryOutlined /></template>
                </a-button>
             </a-tooltip>
             <a-tooltip :title="t('monitor.notificationSettings')">
                <a-button type="text" shape="circle" @click="openSettings(host)">
                    <template #icon><SettingOutlined /></template>
                </a-button>
             </a-tooltip>
          </template>
          
          <div class="card-content">
            <!-- OS, Uptime & Agent Version in one line -->
            <div style="margin-bottom: 8px; font-size: 12px; color: #8c8c8c; display: flex; align-items: center; gap: 8px; flex-wrap: wrap">
              <div style="display: flex; align-items: center; gap: 4px">
                <OSIcon :os="host.os" />
                <span>{{ host.os || 'Linux' }}</span>
              </div>
              <span style="color: #d9d9d9">|</span>
              <span>{{ t('monitor.uptime') }}: {{ formatUptime(host.uptime) }}</span>
              <template v-if="host.agent_version">
                <span style="color: #d9d9d9">|</span>
                <span>Agent: v{{ host.agent_version }}</span>
                <a-tag v-if="isAgentOutdated(host)" color="warning" size="small" style="margin: 0">
                  {{ t('monitor.agentOutdated') }}
                </a-tag>
              </template>
            </div>

            <!-- CPU -->
            <div style="margin-bottom: 8px">
              <div style="display: flex; justify-content: space-between; margin-bottom: 4px">
                <span>
                  {{ t('monitor.cpu') }}
                  <span v-if="host.cpu_count" style="font-size: 11px; color: #8c8c8c; margin-left: 4px">
                     {{ host.cpu_count }}C {{ host.cpu_model }}
                     <span v-if="host.cpu_mhz > 0"> @ {{ formatMhz(host.cpu_mhz) }}</span>
                  </span>
                </span>
                <span>{{ formatCpu(host.cpu) }}%</span>
              </div>
              <a-progress :percent="host.cpu" :status="getStatus(host.cpu)" :show-info="false" stroke-linecap="square" />
            </div>

            <!-- RAM -->
            <div style="margin-bottom: 8px">
              <div style="display: flex; justify-content: space-between; margin-bottom: 4px">
                <span>
                  {{ t('monitor.ram') }}
                  <span style="font-size: 11px; color: #8c8c8c; margin-left: 4px">
                    {{ formatBytes(host.mem_used) }} / {{ formatBytes(host.mem_total) }}
                  </span>
                </span>
                <span>{{ formatPct(host.mem_used, host.mem_total) }}%</span>
              </div>
              <a-progress :percent="calcPct(host.mem_used, host.mem_total)" :status="getStatus(calcPct(host.mem_used, host.mem_total))" :show-info="false" stroke-linecap="square" />
            </div>

            <!-- Disk -->
             <div style="margin-bottom: 8px">
              <div style="display: flex; justify-content: space-between; margin-bottom: 4px">
                <span>
                  {{ t('monitor.disk') }}
                  <span style="font-size: 11px; color: #8c8c8c; margin-left: 4px">
                    {{ formatBytes(host.disk_used) }} / {{ formatBytes(host.disk_total) }}
                  </span>
                </span>
                <span>{{ formatPct(host.disk_used, host.disk_total) }}%</span>
              </div>
              <a-progress :percent="calcPct(host.disk_used, host.disk_total)" :show-info="false" stroke-linecap="square" />
            </div>

            <!-- Network -->
            <div style="margin-top: 8px; display: flex; justify-content: space-between; font-size: 12px">
              <div style="text-align: center">
                <div style="color: #52c41a"><ArrowDownOutlined /> {{ formatSpeed(host.net_rx_rate || 0) }}</div>
                <div style="color: #8c8c8c">{{ t('monitor.total') }}: {{ formatBytes(host.net_rx) }}</div>
              </div>
              <div style="text-align: center">
                <div style="color: #1890ff"><ArrowUpOutlined /> {{ formatSpeed(host.net_tx_rate || 0) }}</div>
                <div style="color: #8c8c8c">{{ t('monitor.total') }}: {{ formatBytes(host.net_tx) }}</div>
              </div>
            </div>
            
            <!-- Traffic Usage (If Limit Set) -->
            <div v-if="host.net_traffic_limit > 0" style="margin-top: 8px; border-top: 1px solid #f0f0f0; padding-top: 8px">
               <div style="display: flex; justify-content: space-between; font-size: 12px; margin-bottom: 2px">
                  <span>{{ t('network.usage') }} ({{ getTrafficUsagePct(host) }}%)</span>
                  <span>{{ formatTrafficUsage(host) }}</span>
               </div>
               <a-progress :percent="getTrafficUsagePct(host)" :status="getStatus(getTrafficUsagePct(host))" :show-info="false" stroke-linecap="square" size="small" />
            </div>
          </div>
        </a-card>
      </a-col>

      <a-col :span="24" v-if="hosts.length === 0">
        <a-empty description="No monitored hosts found" />
      </a-col>
    </a-row>

    <!-- List View -->
    <a-table 
      v-if="viewMode === 'list'" 
      :dataSource="sortedHosts" 
      :columns="listColumns" 
      :pagination="false" 
      rowKey="host_id"
      size="middle"
    >
      <template #bodyCell="{ column, record }">
        <template v-if="column.key === 'host'">
          <a-space style="padding-left: 8px">
            <component :is="getOsIcon(record.os)" :style="{ fontSize: '18px' }" />
            <div>
              <div style="font-weight: 500">{{ getHostName(record.host_id) }}</div>
              <div style="font-size: 12px; color: #8c8c8c">{{ record.hostname }}</div>
            </div>
          </a-space>
        </template>
        
        <template v-if="column.key === 'status'">
            <div style="display: flex; flex-direction: column; gap: 4px;">
                <a-tag :color="isOffline(record) ? 'red' : 'green'" style="margin: 0; width: fit-content;">
                    {{ isOffline(record) ? 'OFFLINE' : 'ONLINE' }}
                </a-tag>
                <span v-if="!isOffline(record)" style="font-size: 12px; color: #8c8c8c">{{ formatUptime(record.uptime) }}</span>
            </div>
        </template>

        <template v-if="column.key === 'cpu'">
          <a-tooltip :title="`${record.cpu_count}C ${record.cpu_model}`">
            <div style="width: 100%">
               <div style="display: flex; justify-content: space-between; font-size: 12px;">
                 <span>{{ formatCpu(record.cpu) }}%</span>
               </div>
               <a-progress :percent="record.cpu" :status="getStatus(record.cpu)" :show-info="false" stroke-linecap="square" size="small" />
            </div>
          </a-tooltip>
        </template>

        <template v-if="column.key === 'ram'">
          <div style="width: 100%">
             <div style="display: flex; justify-content: space-between; font-size: 12px;">
               <span>{{ formatPct(record.mem_used, record.mem_total) }}%</span>
               <span style="color: grey; font-size: 10px">{{ formatBytes(record.mem_used) }} / {{ formatBytes(record.mem_total) }}</span>
             </div>
             <a-progress :percent="calcPct(record.mem_used, record.mem_total)" :status="getStatus(calcPct(record.mem_used, record.mem_total))" :show-info="false" stroke-linecap="square" size="small" />
          </div>
        </template>

        <template v-if="column.key === 'disk'">
            <div style="width: 100%">
             <div style="display: flex; justify-content: space-between; font-size: 12px;">
               <span>{{ formatPct(record.disk_used, record.disk_total) }}%</span>
               <span style="color: grey; font-size: 10px">{{ formatBytes(record.disk_used) }} / {{ formatBytes(record.disk_total) }}</span>
             </div>
             <a-progress :percent="calcPct(record.disk_used, record.disk_total)" :show-info="false" stroke-linecap="square" size="small" />
          </div>
        </template>

        <template v-if="column.key === 'network'">
           <div style="font-size: 12px; width: 100%">
            <div style="display: flex; justify-content: space-between; align-items: center;">
                <span style="color: #52c41a"><ArrowDownOutlined /> {{ formatSpeed(record.net_rx_rate || 0) }}</span>
                <span style="color: #8c8c8c; font-size: 10px">{{ formatBytes(record.net_rx) }}</span>
            </div>
            <div style="display: flex; justify-content: space-between; align-items: center;">
                <span style="color: #1890ff"><ArrowUpOutlined /> {{ formatSpeed(record.net_tx_rate || 0) }}</span>
                <span style="color: #8c8c8c; font-size: 10px">{{ formatBytes(record.net_tx) }}</span>
            </div>
           </div>
        </template>

        <template v-if="column.key === 'traffic'">
            <div v-if="record.net_traffic_limit > 0" style="width: 100%">
                <div style="font-size: 10px; color: #8c8c8c; display: flex; justify-content: space-between;">
                    <span>{{ getTrafficUsagePct(record) }}%</span>
                    <span>{{ formatTrafficUsage(record) }}</span>
                </div>
                <a-progress :percent="getTrafficUsagePct(record)" :status="getStatus(getTrafficUsagePct(record))" :show-info="false" stroke-linecap="square" size="small" :stroke-width="6" />
            </div>
            <div v-else style="font-size: 10px; color: #ccc; text-align: center">-</div>
        </template>

        <template v-if="column.key === 'actions'">
          <a-space size="small">
            <a-tooltip :title="t('terminal.connect')">
               <a-button type="text" size="small" @click="handleConnect(record)" :disabled="isMonitorOnly(record.host_id)">
                   <template #icon><CodeOutlined /></template>
               </a-button>
            </a-tooltip>
            <a-tooltip :title="t('network.title')">
               <a-button type="text" size="small" @click="$router.push({ name: 'NetworkDetail', params: { id: record.host_id } })">
                   <template #icon><LineChartOutlined /></template>
               </a-button>
            </a-tooltip>
            <a-tooltip :title="t('monitor.history')">
               <a-button type="text" size="small" @click="showHistory(record.host_id)">
                   <template #icon><HistoryOutlined /></template>
               </a-button>
            </a-tooltip>
             <a-tooltip :title="t('monitor.notificationSettings')">
                <a-button type="text" size="small" @click="openSettings(record)">
                    <template #icon><SettingOutlined /></template>
                </a-button>
            </a-tooltip>
          </a-space>
        </template>
      </template>
    </a-table>

    <!-- History Logs Modal -->
    <a-modal v-model:open="historyVisible" :title="t('monitor.statusHistory')" :footer="null" width="600px">
        <a-table :dataSource="histLogs" :columns="histColumns" :pagination="histPagination" :loading="histLoading" size="small" rowKey="id" @change="handleHistTableChange">
            <template #bodyCell="{ column, record }">
                <template v-if="column.key === 'status'">
                    <a-tag :color="record.status === 'online' ? 'green' : 'red'">{{ record.status.toUpperCase() }}</a-tag>
                </template>
                <template v-if="column.key === 'created_at'">
                    {{ new Date(record.created_at).toLocaleString() }}
                </template>
            </template>
        </a-table>
    </a-modal>

    <!-- Notification Settings Modal -->
    <a-modal v-model:open="settingsVisible" :title="t('monitor.notificationSettings')" @ok="handleSaveSettings" :confirmLoading="settingsLoading">
        <a-form layout="vertical">
            <a-form-item>
                <a-switch v-model:checked="settingsForm.notify_offline_enabled" :checked-children="t('common.enabled')" :un-checked-children="t('common.disabled')" />
                <span style="margin-left: 8px">{{ t('monitor.enableOfflineNotify') }}</span>
            </a-form-item>
            <a-form-item :label="t('monitor.offlineThreshold')" v-if="settingsForm.notify_offline_enabled">
                <a-input-number v-model:value="settingsForm.notify_offline_threshold" :min="1" style="width: 100%" />
            </a-form-item>
            
            <a-divider />

            <a-form-item>
                <a-switch v-model:checked="settingsForm.notify_traffic_enabled" :checked-children="t('common.enabled')" :un-checked-children="t('common.disabled')" />
                <span style="margin-left: 8px">{{ t('monitor.enableTrafficNotify') }}</span>
            </a-form-item>
            <a-form-item :label="t('monitor.trafficThreshold')" v-if="settingsForm.notify_traffic_enabled">
                <a-input-number v-model:value="settingsForm.notify_traffic_threshold" :min="0" :max="100" style="width: 100%" />
            </a-form-item>

            <a-divider />

            <a-form-item :label="t('monitor.notifyChannels')">
                <a-checkbox-group v-model:value="settingsForm.notify_channels_list">
                    <a-row>
                        <a-col :span="12"><a-checkbox value="email">{{ t('monitor.channelEmail') }}</a-checkbox></a-col>
                        <a-col :span="12"><a-checkbox value="telegram">{{ t('monitor.channelTelegram') }}</a-checkbox></a-col>
                    </a-row>
                </a-checkbox-group>
            </a-form-item>
        </a-form>
    </a-modal>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, computed, h, watch, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { useSSHStore } from '../stores/ssh'
import { ArrowDownOutlined, ArrowUpOutlined, AppleOutlined, WindowsOutlined, DesktopOutlined, LineChartOutlined, HistoryOutlined, SettingOutlined, CodeOutlined, AppstoreOutlined, UnorderedListOutlined } from '@ant-design/icons-vue'
import { useI18n } from 'vue-i18n'
import { getWSTicket } from '../api/auth'
import { getMonitorLogs } from '../api/ssh'
import { message } from 'ant-design-vue'

const { t } = useI18n()
const sshStore = useSSHStore()
const router = useRouter()

const hosts = ref([])
const connected = ref(true)
const socket = ref(null)
const serverAgentVersion = ref(null)

const viewMode = ref(localStorage.getItem('monitor_view_mode') || 'card')
const listColumns = [
  { title: 'Host', key: 'host', width: 250 },
  { title: 'Status', key: 'status', width: 120 },
  { title: 'CPU', key: 'cpu' },
  { title: 'RAM', key: 'ram' },
  { title: 'Disk', key: 'disk' },
  { title: 'Network', key: 'network', width: 150 },
  { title: 'Usage', key: 'traffic', width: 140 },
  { title: 'Actions', key: 'actions', width: 160, fixed: 'right' }
]

watch(viewMode, (val) => {
    localStorage.setItem('monitor_view_mode', val)
})

// Fetch server agent version
const fetchServerAgentVersion = async () => {
  try {
    const response = await fetch('/api/system/agent-version', {
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('access_token')}`
      }
    })
    if (response.ok) {
      const data = await response.json()
      serverAgentVersion.value = data.data.version
    }
  } catch (error) {
    console.error('Failed to fetch agent version:', error)
  }
}

// Check if agent version is outdated
const isAgentOutdated = (host) => {
  if (!host.agent_version || !serverAgentVersion.value) {
    return false
  }
  // Simple version comparison (assumes semantic versioning)
  return host.agent_version !== serverAgentVersion.value
}

const getHostName = (hostId) => {
  const host = sshStore.hosts.find(h => h.id === hostId)
  return host ? host.name : 'Unknown Host'
}

const isMonitorOnly = (hostId) => {
  const host = sshStore.hosts.find(h => h.id === hostId)
  return host?.host_type === 'monitor_only'
}

const getOsIcon = (os) => {
  os = (os || '').toLowerCase()
  if (os.includes('win')) return WindowsOutlined
  if (os.includes('mac') || os.includes('darwin')) return AppleOutlined
  return DesktopOutlined
}

const handleConnect = (host) => {
    // Check if terminal exists
    const existingTerminal = Array.from(sshStore.terminals.values()).find(t => t.hostId === host.host_id)
    if (existingTerminal) {
        sshStore.setCurrentTerminal(existingTerminal.id)
        router.push('/dashboard/terminal')
    } else {
        const fullHost = sshStore.hosts.find(h => h.id === host.host_id)
        if (fullHost) {
             sshStore.addTerminal({
                hostId: fullHost.id,
                name: fullHost.name,
                host: fullHost.host,
                port: fullHost.port
              })
              router.push('/dashboard/terminal')
        }
    }
}

const syncHostsFromStore = () => {
  const storeHosts = sshStore.hosts.filter(h => h.monitor_enabled)
  
  // Rebuild hosts list respecting storeHosts order to ensure display order matches list order
  const newHosts = storeHosts.map(sh => {
    const existing = hosts.value.find(h => h.host_id === sh.id)
    if (existing) {
      // Update static info
      existing.hostname = sh.host
      // Update notification settings if they changed in store
      existing.notify_offline_enabled = sh.notify_offline_enabled
      existing.notify_traffic_enabled = sh.notify_traffic_enabled
      existing.notify_offline_threshold = sh.notify_offline_threshold
      existing.notify_traffic_threshold = sh.notify_traffic_threshold
      existing.notify_channels = sh.notify_channels
      return existing
    } else {
      // Add new host with default/empty metrics
      return {
        host_id: sh.id,
        hostname: sh.host,
        os: '',
        uptime: 0,
        cpu: 0,
        cpu_count: 0,
        cpu_model: '',
        cpu_mhz: 0,
        mem_used: 0,
        mem_total: 0,
        disk_used: 0,
        disk_total: 0,
        net_rx: 0,
        net_tx: 0,
        last_updated: 0
      }
    }
  })
  
  hosts.value = newHosts
}

// Watch for store changes
watch(() => sshStore.hosts, () => {
    syncHostsFromStore()
}, { deep: true })

onMounted(() => {
  sshStore.fetchHosts().then(() => {
      syncHostsFromStore()
  })
  fetchServerAgentVersion()
  connect()
})

// Mock for OSIcon component
const OSIcon = (props) => {
  const os = (props.os || '').toLowerCase()
  if (os.includes('ubuntu') || os.includes('debian') || os.includes('centos') || os.includes('linux')) return h(DesktopOutlined)
  if (os.includes('darwin') || os.includes('mac')) return h(AppleOutlined)
  if (os.includes('win')) return h(WindowsOutlined)
  return h(DesktopOutlined)
}

const isOffline = (host) => {
  const now = Date.now() / 1000
  return (now - host.last_updated) > 15
}

const formatMhz = (mhz) => {
  if (!mhz) return ''
  if (mhz >= 1000) {
    return (mhz / 1000).toFixed(2) + ' GHz'
  }
  return mhz.toFixed(0) + ' MHz'
}

const getStatus = (percent) => {
  if (percent >= 90) return 'exception'
  if (percent >= 80) return 'active'
  return 'normal'
}

const calcPct = (used, total) => {
  if (!total) return 0
  return Math.round((used / total) * 100)
}

const formatPct = (used, total) => calcPct(used, total)

const formatUptime = (seconds) => {
  const dys = Math.floor(seconds / 86400)
  const hrs = Math.floor((seconds % 86400) / 3600)
  const min = Math.floor((seconds % 3600) / 60)
  if (dys > 0) return `${dys}d ${hrs}h`
  if (hrs > 0) return `${hrs}h ${min}m`
  return `${min}m`
}

const formatBytes = (bytes) => {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i]
}

const formatSpeed = (bytesPerSec) => {
  return formatBytes(bytesPerSec) + '/s'
}

const formatCpu = (val) => {
  return (val || 0).toFixed(2)
}

const getTrafficUsagePct = (host) => {
    if (!host.net_traffic_limit) return 0
    let measured = 0
    if (host.net_traffic_counter_mode === 'rx') {
        measured = host.net_monthly_rx || 0
    } else if (host.net_traffic_counter_mode === 'tx') {
        measured = host.net_monthly_tx || 0
    } else {
        measured = (host.net_monthly_rx || 0) + (host.net_monthly_tx || 0)
    }
    const used = measured + (host.net_traffic_used_adjustment || 0)
    const pct = Math.round((used / host.net_traffic_limit) * 100)
    return pct > 100 ? 100 : pct
}

const formatTrafficUsage = (host) => {
    if (!host.net_traffic_limit) return ''
     let measured = 0
    if (host.net_traffic_counter_mode === 'rx') {
        measured = host.net_monthly_rx || 0
    } else if (host.net_traffic_counter_mode === 'tx') {
        measured = host.net_monthly_tx || 0
    } else {
        measured = (host.net_monthly_rx || 0) + (host.net_monthly_tx || 0)
    }
    const used = measured + (host.net_traffic_used_adjustment || 0)
    return formatBytes(used) + ' / ' + formatBytes(host.net_traffic_limit)
}

const sortedHosts = computed(() => {
    // Return hosts as is (already sorted by syncHostsFromStore matching sshStore.hosts order)
    return hosts.value
})

const connect = async () => {
  try {
    // Get one-time ticket for secure connection
    const res = await getWSTicket()
    const ticket = res.ticket

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/api/monitor/stream?token=${ticket}`
    
    socket.value = new WebSocket(wsUrl)

    socket.value.onopen = () => {
      connected.value = true
    }

    socket.value.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data)
        if (msg.type === 'init') {
          updateHosts(msg.data)
        } else if (msg.type === 'update') {
          updateHosts(msg.data)
        } else if (msg.type === 'remove') {
          // removeHost(msg.data)
        }
      } catch (e) {
        console.error(e)
      }
    }

    socket.value.onclose = () => {
      connected.value = false
      setTimeout(connect, 3000)
    }
  } catch (err) {
    console.error('Failed to connect to monitor stream:', err)
    setTimeout(connect, 5000)
  }
}

const enrichHost = (data) => {
  return data
}

const updateHosts = (updates) => {
  if (!updates) return
  updates.forEach(update => {
    const index = hosts.value.findIndex(h => h.host_id === update.host_id)
    if (index !== -1) {
      hosts.value[index] = { ...hosts.value[index], ...update }
    } else {
       hosts.value.push(enrichHost(update))
    }
  })
}

const removeHost = (hostId) => {
  hosts.value = hosts.value.filter(h => h.host_id !== hostId)
}

// History Logic
const historyVisible = ref(false)
const histLogs = ref([])
const histLoading = ref(false)
const currentHistHostId = ref(0)
const histPagination = ref({
    current: 1,
    pageSize: 10,
    total: 0
})

const histColumns = [
    { title: 'Status', key: 'status' },
    { title: 'Time', key: 'created_at' }
]

const loadHistory = async (page = 1) => {
    histLoading.value = true
    try {
        const res = await getMonitorLogs(currentHistHostId.value, page, histPagination.value.pageSize)
        histLogs.value = res.data
        histPagination.value.current = page
        histPagination.value.total = res.total
    } catch (e) {
        console.error(e)
    } finally {
        histLoading.value = false
    }
}

const showHistory = (hostId) => {
    currentHistHostId.value = hostId
    historyVisible.value = true
    loadHistory(1)
}

const handleHistTableChange = (pag) => {
    loadHistory(pag.current)
}

// Notification Settings Logic
const settingsVisible = ref(false)
const settingsLoading = ref(false)
const currentSettingsHostId = ref(0)
const settingsForm = reactive({
    notify_offline_enabled: true,
    notify_traffic_enabled: true,
    notify_offline_threshold: 1,
    notify_traffic_threshold: 90,
    notify_channels_list: ['email', 'telegram']
})

const openSettings = (host) => {
    currentSettingsHostId.value = host.host_id
    const originalHost = sshStore.hosts.find(h => h.id === host.host_id)
    if (originalHost) {
        settingsForm.notify_offline_enabled = originalHost.notify_offline_enabled !== undefined ? originalHost.notify_offline_enabled : true
        settingsForm.notify_traffic_enabled = originalHost.notify_traffic_enabled !== undefined ? originalHost.notify_traffic_enabled : true
        settingsForm.notify_offline_threshold = originalHost.notify_offline_threshold || 1
        settingsForm.notify_traffic_threshold = originalHost.notify_traffic_threshold || 90
        const channels = originalHost.notify_channels || 'email,telegram'
        settingsForm.notify_channels_list = channels.split(',').filter(c => c)
    }
    settingsVisible.value = true
}

const handleSaveSettings = async () => {
    settingsLoading.value = true
    try {
        const updateData = {
            notify_offline_enabled: settingsForm.notify_offline_enabled,
            notify_traffic_enabled: settingsForm.notify_traffic_enabled,
            notify_offline_threshold: settingsForm.notify_offline_threshold,
            notify_traffic_threshold: settingsForm.notify_traffic_threshold,
            notify_channels: settingsForm.notify_channels_list.join(',')
        }
        await sshStore.modifyHost(currentSettingsHostId.value, updateData)
        message.success(t('common.saveSuccess'))
        settingsVisible.value = false
    } catch (e) {
        console.error(e)
        message.error(t('common.saveFailed'))
    } finally {
        settingsLoading.value = false
    }
}

onUnmounted(() => {
  if (socket.value) socket.value.close()
})
</script>

<style scoped>
.monitor-dashboard-container {
  padding: 5px;
}

@media (max-width: 768px) {
  .monitor-dashboard-container {
    padding: 12px;
  }
}

@media (max-width: 480px) {
  .monitor-dashboard-container {
    padding: 8px;
  }
}

.monitor-card {
  transition: all 0.3s;
  height: 100%;
}
.monitor-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.15);
}
.monitor-card :deep(.ant-card-body) {
  padding: 12px;
}
.card-content {
  display: flex;
  flex-direction: column;
}
.offline {
  filter: grayscale(100%);
  opacity: 0.7;
}

@media (min-width: 1200px) {
  .col-5 {
    width: 20%;
    flex: 0 0 20%;
    max-width: 20%;
  }
}

/* Mobile optimizations */
@media (max-width: 768px) {
  .monitor-card :deep(.ant-card-head) {
    padding: 8px 12px;
  }
  
  .monitor-card :deep(.ant-card-head-title) {
    font-size: 14px;
    padding: 8px 0;
  }
  
  .monitor-card :deep(.ant-card-extra) {
    padding: 8px 0;
  }
  
  .monitor-card :deep(.ant-card-extra .ant-btn) {
    padding: 2px 6px;
  }
  
  .monitor-card :deep(.ant-card-body) {
    padding: 12px;
  }
  
  .card-content {
    font-size: 12px;
  }
}

@media (max-width: 480px) {
  .monitor-card :deep(.ant-card-head-title) {
    font-size: 13px;
  }
  
  .monitor-card :deep(.ant-card-extra .ant-btn) {
    width: 28px;
    height: 28px;
    padding: 0;
  }
}
</style>
