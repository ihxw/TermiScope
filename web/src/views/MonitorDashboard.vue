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

    <div style="display: flex; align-items: center; margin-bottom: 5px; gap: 16px">
      <a-radio-group v-model:value="viewMode" button-style="solid">
        <a-radio-button value="card">
          <AppstoreOutlined />
        </a-radio-button>
        <a-radio-button value="list">
          <UnorderedListOutlined />
        </a-radio-button>
      </a-radio-group>

      <div style="font-size: 13px; color: #8c8c8c">
        <span style="font-weight: 500">{{ t('monitor.total') }}: {{ totalHosts }}</span>
        <a-divider type="vertical" />
        <span style="color: #52c41a">{{ t('monitor.online') }}: {{ onlineHosts }}</span>
      </div>

      <a-button size="small" @click="showResetLogs">
        <template #icon><FileTextOutlined /></template>
        {{ t('monitor.trafficResetLogs') }}
      </a-button>
    </div>

    <!-- Card View -->
    <a-row :gutter="[5, 5]" v-if="viewMode === 'card'">
      <a-col :xs="24" :sm="12" :md="8" class="col-5" v-for="host in sortedHosts" :key="host.host_id">
        <a-card hoverable class="monitor-card" :class="{ offline: isOffline(host) }" :style="{ borderLeft: host.flag ? `5px solid ${getFlagColor(host.flag)}` : '' }">
          <template #title>
            <div style="display: flex; align-items: center; overflow: hidden;">
              <component :is="getOsIcon(host.os)" :style="{ fontSize: '20px', marginRight: '8px', flexShrink: 0 }" />
              <div style="overflow: hidden; white-space: nowrap; text-overflow: ellipsis; flex: 1;" :title="getHostName(host.host_id) + ' (' + host.hostname + ')'">
                <span>{{ getHostName(host.host_id) }}</span>
                <span style="color: #8c8c8c; font-size: 12px; margin-left: 4px;">({{ host.hostname }})</span>
              </div>
            </div>
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
             <a-tooltip :title="t('common.settings')">
                <a-button type="text" shape="circle" @click="$router.push({ name: 'NetworkDetail', params: { id: host.host_id }, query: { tab: 'config' } })">
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
                <div style="color: #8c8c8c">{{ t('monitor.total') }}: {{ formatBytes(host.net_monthly_rx) }}</div>
              </div>
              <div style="text-align: center">
                <div style="color: #1890ff"><ArrowUpOutlined /> {{ formatSpeed(host.net_tx_rate || 0) }}</div>
                <div style="color: #8c8c8c">{{ t('monitor.total') }}: {{ formatBytes(host.net_monthly_tx) }}</div>
              </div>
            </div>
            
            <!-- Traffic Usage (If Limit Set) -->
            <div v-if="host.net_traffic_limit > 0" style="margin-top: 8px; border-top: 1px solid #f0f0f0; padding-top: 8px">
               <div style="display: flex; justify-content: space-between; font-size: 12px; margin-bottom: 2px">
                  <span>
                    {{ t('network.usage') }} ({{ getTrafficUsagePct(host) }}%)
                    <span v-if="host.net_reset_day" style="color: #bfbfbf; font-size: 10px; margin-left: 4px">
                        {{ t('network.nextReset') }}: {{ getNextResetDate(host) }}
                    </span>
                  </span>
                  <span>{{ formatTrafficUsage(host) }}</span>
               </div>
               <a-progress :percent="getTrafficUsagePct(host)" :status="getStatus(getTrafficUsagePct(host))" :show-info="false" stroke-linecap="square" size="small" />
            </div>

            <!-- Financial Info (If Available) -->
            <div v-if="host.expiration_date || host.billing_amount" style="margin-top: 8px; border-top: 1px dashed #f0f0f0; padding-top: 8px; font-size: 11px; color: #8c8c8c">
              <div style="display: flex; justify-content: space-between; align-items: center">
                <!-- Left: Expiration Date -->
                <span style="display: flex; align-items: center; gap: 4px">
                  <InfoCircleOutlined style="font-size: 10px" />
                  <template v-if="host.expiration_date">
                    <span>{{ t('host.expirationDate') }}:</span>
                    <span :style="{ color: getDaysUntilExpiration(host.expiration_date) < 0 ? '#f5222d' : (getDaysUntilExpiration(host.expiration_date) <= 7 ? '#faad14' : undefined) }">
                      {{ dayjs(host.expiration_date).format('YYYY-MM-DD') }}({{ t('host.remainingDays', { days: getDaysUntilExpiration(host.expiration_date) }) }})
                    </span>
                  </template>
                  <template v-else>-</template>
                </span>
                
                <!-- Right: Billing & Value -->
                <span v-if="host.billing_period || host.billing_amount">
                  {{ formatBillingPeriod(host.billing_period) }}:{{ getCurrencySymbol(host.currency) }}{{ host.billing_amount }} 
                  <template v-if="host.expiration_date && host.billing_period && host.billing_amount">
                    ({{ t('host.remainingValueLong') }}:{{ formatRemainingValueOnly(host.expiration_date, host.billing_period, host.billing_amount, host.currency) }})
                  </template>
                </span>
              </div>
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
                <span style="color: #8c8c8c; font-size: 10px">{{ formatBytes(record.net_monthly_rx) }}</span>
            </div>
            <div style="display: flex; justify-content: space-between; align-items: center;">
                <span style="color: #1890ff"><ArrowUpOutlined /> {{ formatSpeed(record.net_tx_rate || 0) }}</span>
                <span style="color: #8c8c8c; font-size: 10px">{{ formatBytes(record.net_monthly_tx) }}</span>
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
                <div style="text-align: right; font-size: 9px; color: #ccc;" v-if="record.net_reset_day">
                   {{ t('network.nextReset') }}: {{ getNextResetDate(record) }}
                </div>
            </div>
            <div v-else style="font-size: 10px; color: #ccc; text-align: center">-</div>
        </template>

        <template v-if="column.key === 'financial'">
          <div v-if="record.expiration_date || record.billing_amount" style="font-size: 11px;">
            <div v-if="record.expiration_date">
               <span :style="{ color: getDaysUntilExpiration(record.expiration_date) < 0 ? '#f5222d' : (getDaysUntilExpiration(record.expiration_date) <= 7 ? '#faad14' : undefined) }">
                 {{ dayjs(record.expiration_date).format('YYYY-MM-DD') }}
               </span>
               <span style="color: #8c8c8c; margin-left: 4px; font-size: 10px">({{ t('host.remainingDays', { days: getDaysUntilExpiration(record.expiration_date) }) }})</span>
            </div>
            <div v-if="record.billing_period || record.billing_amount" style="color: #8c8c8c; font-size: 10px">
              {{ formatBillingPeriod(record.billing_period) }}:{{ getCurrencySymbol(record.currency) }}{{ record.billing_amount }}
              <template v-if="record.expiration_date && record.billing_period && record.billing_amount">
                ({{ t('host.remainingValueLong') }}:{{ formatRemainingValueOnly(record.expiration_date, record.billing_period, record.billing_amount, record.currency) }})
              </template>
            </div>
          </div>
          <div v-else style="color: #ccc; text-align: center">-</div>
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
             <a-tooltip :title="t('common.settings')">
                <a-button type="text" size="small" @click="$router.push({ name: 'NetworkDetail', params: { id: record.host_id }, query: { tab: 'config' } })">
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

    <!-- Traffic Reset Logs Modal -->
    <a-modal v-model:open="resetLogsVisible" :title="t('monitor.trafficResetLogsTitle')" :footer="null" width="700px">
        <a-table :dataSource="resetLogs" :columns="resetLogColumns" :pagination="resetLogPagination" :loading="resetLogLoading" size="small" rowKey="id" @change="handleResetLogTableChange">
            <template #bodyCell="{ column, record }">
                <template v-if="column.key === 'host_name'">
                    {{ record.host_name || 'Host #' + record.host_id }}
                </template>
                <template v-if="column.key === 'reset_date'">
                    {{ record.reset_date }}
                </template>
                <template v-if="column.key === 'status'">
                    <a-tag :color="record.status === 'success' ? 'green' : 'red'">{{ record.status.toUpperCase() }}</a-tag>
                </template>
                <template v-if="column.key === 'created_at'">
                    {{ new Date(record.created_at).toLocaleString() }}
                </template>
            </template>
        </a-table>
    </a-modal>


  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, computed, h, watch, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { useSSHStore } from '../stores/ssh'
import { ArrowDownOutlined, ArrowUpOutlined, AppleOutlined, WindowsOutlined, DesktopOutlined, LineChartOutlined, HistoryOutlined, SettingOutlined, CodeOutlined, AppstoreOutlined, UnorderedListOutlined, InfoCircleOutlined, FileTextOutlined } from '@ant-design/icons-vue'
import { useI18n } from 'vue-i18n'
import { getWSTicket } from '../api/auth'
import { getMonitorLogs, getTrafficResetLogs } from '../api/ssh'
import { message } from 'ant-design-vue'
import api from '../api/index'
import dayjs from 'dayjs'
import 'dayjs/locale/zh-cn'

const { t, locale: i18nLocale } = useI18n()
const sshStore = useSSHStore()
const router = useRouter()

// Configure dayjs locale based on current language
watch(i18nLocale, (newLocale) => {
  dayjs.locale(newLocale === 'zh-CN' ? 'zh-cn' : 'en')
}, { immediate: true })

const hosts = ref([])
const connected = ref(true)
const socket = ref(null)
const serverAgentVersion = ref(null)

const viewMode = ref(localStorage.getItem('monitor_view_mode') || 'card')
const listColumns = computed(() => [
  { title: t('host.host'), key: 'host', width: 220 },
  { title: t('monitor.status'), key: 'status', width: 100 },
  { title: t('monitor.cpu'), key: 'cpu' },
  { title: t('monitor.ram'), key: 'ram' },
  { title: t('monitor.disk'), key: 'disk' },
  { title: t('common.network'), key: 'network', width: 140 },
  { title: t('monitor.usage'), key: 'traffic', width: 120 },
  { title: t('host.financialManagement'), key: 'financial', width: 180 },
  { title: t('common.actions'), key: 'actions', width: 160, fixed: 'right' }
])

watch(viewMode, (val) => {
    localStorage.setItem('monitor_view_mode', val)
})

// Fetch server agent version
const fetchServerAgentVersion = async () => {
  try {
    const data = await api.get('/system/agent-version')
    if (data && data.version) {
      serverAgentVersion.value = data.version
    }
  } catch (error) {
    console.error('Failed to fetch agent version:', error)
  }
}

// Helper to clean version strings for comparison
const cleanVersion = (v) => {
  if (!v) return ''
  return v.toString().replace(/^v/, '').trim()
}

// Check if agent version is outdated
const isAgentOutdated = (host) => {
  if (!host.agent_version || !serverAgentVersion.value) {
    return false
  }
  return cleanVersion(host.agent_version) !== cleanVersion(serverAgentVersion.value)
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
      // Update financial info
      existing.expiration_date = sh.expiration_date
      existing.billing_period = sh.billing_period
      existing.billing_amount = sh.billing_amount
      existing.billing_amount = sh.billing_amount
      existing.currency = sh.currency
      existing.flag = sh.flag
      // Update network config
      existing.net_reset_day = sh.net_reset_day
      existing.net_last_reset_date = sh.net_last_reset_date
      
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
        net_monthly_rx: 0,
        net_monthly_tx: 0,
        net_traffic_limit: sh.net_traffic_limit,
        net_traffic_used_adjustment: sh.net_traffic_used_adjustment,
        net_traffic_counter_mode: sh.net_traffic_counter_mode,
        net_reset_day: sh.net_reset_day,
        net_last_reset_date: sh.net_last_reset_date,
        _clientLastUpdated: 0, // Will be set when first WebSocket update arrives
        // Financial logic
        expiration_date: sh.expiration_date,
        billing_period: sh.billing_period,
        billing_amount: sh.billing_amount,
        currency: sh.currency,
        flag: sh.flag
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
  if (!host._clientLastUpdated) return true
  return (Date.now() - host._clientLastUpdated) > 15000 // 15 seconds in ms
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

const getNextResetDate = (host) => {
    if (!host.net_reset_day) return ''
    const now = dayjs()
    let resetDay = host.net_reset_day
    // Ensure valid day (1-31)
    if (resetDay < 1) resetDay = 1
    if (resetDay > 31) resetDay = 31

    let target = now.date(resetDay)
    // If target is today or in past, next reset is next month
    if (target.isBefore(now, 'day') || target.isSame(now, 'day')) {
        target = target.add(1, 'month').date(resetDay)
    }
    return target.format('YYYY-MM-DD')
}

// Financial calculation helpers
const getDaysUntilExpiration = (expirationDate) => {
  if (!expirationDate) return 0
  const now = dayjs()
  const expDate = dayjs(expirationDate)
  return expDate.diff(now, 'day')
}

const calculateRemainingValue = (expirationDate, billingPeriod, billingAmount, currency = 'CNY') => {
  const daysRemaining = getDaysUntilExpiration(expirationDate)
  if (daysRemaining < 0) return t('host.expired')
  
  // Days per billing period
  const periodDays = {
    'monthly': 30,
    'quarterly': 90,
    'semiannually': 180,
    'annually': 365,
    'biennial': 730,
    'triennial': 1095
  }
  
  // Currency symbols
  const currencySymbols = {
    'CNY': '¥',
    'USD': '$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥'
  }
  
  const days = periodDays[billingPeriod] || 30
  const dailyRate = billingAmount / days
  const remaining = (dailyRate * daysRemaining).toFixed(2)
  const symbol = currencySymbols[currency] || '¥'
  
  return `${symbol}${remaining} (${daysRemaining}${t('host.daysRemaining')})`
}

const formatRemainingValueOnly = (expirationDate, billingPeriod, billingAmount, currency = 'CNY') => {
  const daysRemaining = getDaysUntilExpiration(expirationDate)
  if (daysRemaining < 0) return t('host.expired')
  
  const periodDays = {
    'monthly': 30, 'quarterly': 90, 'semiannually': 180, 'annually': 365, 'biennial': 730, 'triennial': 1095
  }
  
  const currencySymbols = { 'CNY': '¥', 'USD': '$', 'EUR': '€', 'GBP': '£', 'JPY': '¥' }
  const days = periodDays[billingPeriod] || 30
  const dailyRate = billingAmount / days
  const remaining = (dailyRate * daysRemaining).toFixed(2)
  const symbol = currencySymbols[currency] || '¥'
  
  return `${symbol}${remaining}`
}

const formatBillingPeriod = (period) => {
  if (!period) return ''
  return t(`host.billing${period.charAt(0).toUpperCase() + period.slice(1)}`)
}

const getCurrencySymbol = (currency) => {
  const currencySymbols = { 'CNY': '¥', 'USD': '$', 'EUR': '€', 'GBP': '£', 'JPY': '¥' }
  return currencySymbols[currency] || '¥'
}

const sortedHosts = computed(() => {
    // Return hosts as is (already sorted by syncHostsFromStore matching sshStore.hosts order)
    return hosts.value
})

const totalHosts = computed(() => sortedHosts.value.length)
const onlineHosts = computed(() => sortedHosts.value.filter(h => !isOffline(h)).length)

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
  const now = Date.now()
  updates.forEach(update => {
    update._clientLastUpdated = now // Use client-side timestamp to avoid server/client clock skew
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
    
const getFlagColor = (flag) => {
  const colors = {
    red: '#FF3B30',
    orange: '#FF9500',
    yellow: '#FFCC00',
    green: '#4CD964',
    blue: '#007AFF',
    purple: '#5856D6',
    gray: '#8E8E93'
  }
  return colors[flag] || 'transparent'
}

// Traffic Reset Logs Logic
const resetLogsVisible = ref(false)
const resetLogs = ref([])
const resetLogLoading = ref(false)
const resetLogPagination = ref({
    current: 1,
    pageSize: 10,
    total: 0
})

const resetLogColumns = computed(() => [
    { title: t('monitor.hostName'), key: 'host_name' },
    { title: t('monitor.resetDate'), key: 'reset_date' },
    { title: t('monitor.resetStatus'), key: 'status', width: 100 },
    { title: t('monitor.resetTime'), key: 'created_at' }
])

const loadResetLogs = async (page = 1) => {
    resetLogLoading.value = true
    try {
        const res = await getTrafficResetLogs(page, resetLogPagination.value.pageSize)
        resetLogs.value = res.data || []
        resetLogPagination.value.current = page
        resetLogPagination.value.total = res.total
    } catch (e) {
        console.error(e)
    } finally {
        resetLogLoading.value = false
    }
}

const showResetLogs = () => {
    resetLogsVisible.value = true
    loadResetLogs(1)
}

const handleResetLogTableChange = (pag) => {
    loadResetLogs(pag.current)
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
