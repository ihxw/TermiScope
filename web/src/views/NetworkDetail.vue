<template>
  <div style="padding: 12px">
    <a-page-header 
        @back="$router.back()" 
        :title="t('network.title')" 
        :sub-title="host?.name || t('host.name')"
        style="padding: 0 0 12px 0"
    >
      <template #extra>
         <a-tag color="blue" v-if="connected">{{ t('terminal.connected') }}</a-tag>
         <a-tag color="red" v-else>{{ t('terminal.disconnected') }}</a-tag>
      </template>
    </a-page-header>
    
    <div v-if="!host" style="text-align: center; margin-top: 48px">
        <a-spin /> {{ t('common.loading') }}
    </div>

    <a-card v-else :bordered="false" :bodyStyle="{ padding: '12px' }">
      <a-tabs v-model:activeKey="activeTab">
        <!-- Network Connectivity Tab -->
        <a-tab-pane key="connectivity" :tab="t('network.connectivity')">
          <NetworkLatencyMonitor :hostId="hostId" v-if="hostId" />
        </a-tab-pane>

        <!-- Configuration Tab -->
        <a-tab-pane key="config" :tab="t('network.configuration')">
          <a-row :gutter="12">
            <!-- Config -->
            <a-col :xs="24" :lg="8" style="margin-bottom: 12px">
              <a-card :title="t('network.configuration')" :bordered="false" size="small">
                  <a-form layout="vertical" style="margin-bottom: 0">
                      <a-form-item :label="t('network.primaryInterface')" :help="t('network.primaryInterfaceHelp')" style="margin-bottom: 12px">
                          <a-select v-model:value="config.net_interface_list" mode="multiple" :placeholder="t('network.selectInterfaces')" size="small">
                              <a-select-option value="auto">{{ t('network.autoTotal') }}</a-select-option>
                              <a-select-option v-for="iface in interfaces" :key="iface.name" :value="iface.name">{{ iface.name }}</a-select-option>
                          </a-select>
                      </a-form-item>
                      <a-form-item :label="t('network.resetDay')" :help="t('network.resetDayHelp')" style="margin-bottom: 12px">
                          <a-select v-model:value="config.net_reset_day" size="small">
                              <a-select-option v-for="n in 31" :key="n" :value="n">{{ n }}</a-select-option>
                          </a-select>
                      </a-form-item>

                      <a-divider style="margin: 12px 0">{{ t('network.trafficLimit') }}</a-divider>

                      <a-form-item :label="t('network.monthlyLimit')" :help="t('network.unlimitedHelp')" style="margin-bottom: 12px">
                          <a-input-number v-model:value="config.limit_gb" :min="0" style="width: 100%" size="small" />
                      </a-form-item>
                       <a-form-item :label="t('network.alreadyUsed')" :help="t('network.adjustmentHelp')" style="margin-bottom: 12px">
                          <a-input-number v-model:value="config.adjustment_gb" :min="0" style="width: 100%" size="small" />
                      </a-form-item>
                       <a-form-item :label="t('network.counterMode')" :help="t('network.counterModeHelp')" style="margin-bottom: 12px">
                          <a-select v-model:value="config.net_traffic_counter_mode" size="small">
                              <a-select-option value="total">{{ t('network.modeTotal') }}</a-select-option>
                              <a-select-option value="tx">{{ t('network.modeTx') }}</a-select-option>
                              <a-select-option value="rx">{{ t('network.modeRx') }}</a-select-option>
                          </a-select>
                      </a-form-item>

                      <a-button type="primary" @click="saveConfig" :loading="saving" block size="small">{{ t('network.saveConfig') }}</a-button>
                  </a-form>
              </a-card>
              
              <a-card :title="t('network.monthlyTraffic')" :bordered="false" size="small" style="margin-top: 12px">
                  <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px">
                      <a-statistic :title="t('network.inbound')" :value="formatBytes(monthlyRx)" :valueStyle="{ color: '#3f8600', fontSize: '16px' }">
                          <template #prefix><ArrowDownOutlined /></template>
                      </a-statistic>
                      <a-statistic :title="t('network.outbound')" :value="formatBytes(monthlyTx)" :valueStyle="{ color: '#cf1322', fontSize: '16px' }">
                           <template #prefix><ArrowUpOutlined /></template>
                      </a-statistic>
                  </div>
                  
                  <div v-if="config.limit_gb > 0" style="margin-top: 12px">
                      <div style="display: flex; justify-content: space-between; margin-bottom: 4px; font-size: 12px">
                          <span>{{ t('network.usage') }} ({{ usagePercentage }}%)</span>
                          <span>{{ formatBytes(totalUsedBytes) }} / {{ config.limit_gb }} GB</span>
                      </div>
                      <a-progress :percent="usagePercentage" :status="usageStatus" size="small" />
                      <div style="margin-top: 4px; font-size: 12px; color: #8c8c8c">
                          {{ t('network.remaining') }}: {{ formatBytes(remainingBytes) }}
                      </div>
                  </div>

                   <a-alert :message="t('network.calcInfo')" type="info" show-icon style="font-size: 12px; margin-top: 12px" />
              </a-card>
            </a-col>

            <!-- Interface List -->
            <a-col :xs="24" :lg="16">
              <a-card :title="t('network.interfaces')" :bordered="false" size="small">
                 <a-table :dataSource="interfaces" :columns="columns" :pagination="false" rowKey="name" size="small">
                      <template #bodyCell="{ column, record }">
                          <template v-if="column.key === 'name'">
                              <span style="font-weight: bold">{{ record.name }}</span>
                               <a-tag v-if="config.net_interface_list.includes(record.name) || (config.net_interface_list.includes('auto') && record.name)" color="blue" style="margin-left: 8px">Primary</a-tag>
                          </template>
                          <template v-if="column.key === 'speed'">
                              <div style="white-space: nowrap">
                                  <span style="color: #52c41a"><ArrowDownOutlined/> {{formatSpeed(record.rx_rate || 0)}}</span>
                                  <a-divider type="vertical" />
                                  <span style="color: #1890ff"><ArrowUpOutlined/> {{formatSpeed(record.tx_rate || 0)}}</span>
                              </div>
                          </template>
                          <template v-if="column.key === 'ip'">
                              <div v-for="ip in record.ips" :key="ip">{{ ip }}</div>
                          </template>
                          <template v-if="column.key === 'mac'">
                              <span style="font-family: monospace">{{ record.mac }}</span>
                          </template>
                          <template v-else-if="column.key === 'total'">
                               <div style="white-space: nowrap">
                                  <div>Rx: {{ formatBytes(record.rx) }}</div>
                                  <div>Tx: {{ formatBytes(record.tx) }}</div>
                               </div>
                          </template>
                      </template>
                 </a-table>
              </a-card>
            </a-col>
          </a-row>
        </a-tab-pane>
      </a-tabs>
    </a-card>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { useRoute } from 'vue-router'
import { useSSHStore } from '../stores/ssh'
import { ArrowDownOutlined, ArrowUpOutlined } from '@ant-design/icons-vue'
import { message } from 'ant-design-vue'
import { useI18n } from 'vue-i18n'
import { getWSTicket } from '../api/auth'
import NetworkLatencyMonitor from '../components/NetworkLatencyMonitor.vue'

const { t } = useI18n()
const route = useRoute()
const sshStore = useSSHStore()
const hostId = parseInt(route.params.id)

const host = computed(() => sshStore.hosts.find(h => h.id === hostId))
const connected = ref(false)
const activeTab = ref('connectivity') // Default to connectivity tab
const socket = ref(null)
const interfaces = ref([])
const monthlyRx = ref(0)
const monthlyTx = ref(0)

const saving = ref(false)

const config = ref({
    net_interface: 'auto',
    net_interface_list: ['auto'],
    net_reset_day: 1,
    limit_gb: 0,
    adjustment_gb: 0,
    net_traffic_counter_mode: 'total'
})

// Initialize config from host when loaded
const initConfig = () => {
    if (host.value) {
        config.value.net_interface = host.value.net_interface || 'auto'
        if (config.value.net_interface.includes(',')) {
            config.value.net_interface_list = config.value.net_interface.split(',')
        } else {
            config.value.net_interface_list = [config.value.net_interface]
        }
        
        config.value.net_reset_day = host.value.net_reset_day || 1
        
        // Convert bytes to GB for display
        config.value.limit_gb = parseFloat(( (host.value.net_traffic_limit || 0) / (1024*1024*1024) ).toFixed(2))
        config.value.net_traffic_counter_mode = host.value.net_traffic_counter_mode || 'total'

        // Calculate current measured traffic based on mode to display Total Used in input
        let measured = 0
        if (config.value.net_traffic_counter_mode === 'total') {
            measured = (host.value.net_monthly_rx || 0) + (host.value.net_monthly_tx || 0)
        } else if (config.value.net_traffic_counter_mode === 'rx') {
            measured = host.value.net_monthly_rx || 0
        } else if (config.value.net_traffic_counter_mode === 'tx') {
            measured = host.value.net_monthly_tx || 0
        }
        
        // Initial value in input should be Total Used (Measured + Adjustment)
        const totalUsed = measured + (host.value.net_traffic_used_adjustment || 0)
        config.value.adjustment_gb = parseFloat((totalUsed / (1024*1024*1024)).toFixed(2))
    }
}

onMounted(async () => {
    if (sshStore.hosts.length === 0) {
        await sshStore.fetchHosts()
    }
    initConfig()
    connect()
})

// Computed Usage logic
const totalUsedBytes = computed(() => {
    let measured = 0
    if (config.value.net_traffic_counter_mode === 'total') {
        measured = monthlyRx.value + monthlyTx.value
    } else if (config.value.net_traffic_counter_mode === 'rx') {
        measured = monthlyRx.value
    } else if (config.value.net_traffic_counter_mode === 'tx') {
        measured = monthlyTx.value
    }
    
    // Add adjustment (GB -> Bytes)
    const adjustmentBytes = (config.value.adjustment_gb || 0) * 1024 * 1024 * 1024
    return measured + adjustmentBytes
})

const limitBytes = computed(() => {
    return (config.value.limit_gb || 0) * 1024 * 1024 * 1024
})

const remainingBytes = computed(() => {
    const rem = limitBytes.value - totalUsedBytes.value
    return rem > 0 ? rem : 0
})

const usagePercentage = computed(() => {
    if (limitBytes.value === 0) return 0
    const pct = Math.round((totalUsedBytes.value / limitBytes.value) * 100)
    return pct > 100 ? 100 : pct
})

const usageStatus = computed(() => {
    if (usagePercentage.value >= 90) return 'exception'
    if (usagePercentage.value >= 80) return 'active'
    return 'normal'
})


const columns = computed(() => [
    { title: t('network.interfaceName'), key: 'name', dataIndex: 'name' },
    { title: 'IP Address', key: 'ip' },
    { title: 'MAC Address', key: 'mac' },
    { title: t('network.realTimeSpeed'), key: 'speed' },
    { title: t('network.totalTraffic'), key: 'total' },
])

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

const connect = async () => {
  try {
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
        const dataList = msg.type === 'init' || msg.type === 'update' ? msg.data : []
        if (!Array.isArray(dataList)) return

        const myData = dataList.find(h => h.host_id === hostId)
        if (myData) {
            interfaces.value = myData.interfaces || []
            monthlyRx.value = myData.net_monthly_rx || 0
            monthlyTx.value = myData.net_monthly_tx || 0
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
    console.error('Failed to connect network monitor:', err)
    setTimeout(connect, 5000)
  }
}

const saveConfig = async () => {
    saving.value = true
    try {
        // Convert GB back to Bytes
        const trafficLimit = Math.floor(config.value.limit_gb * 1024 * 1024 * 1024)
        // Calculate new adjustment: User Input (Total) - Measured
        // We need to re-calculate measured because mode might have changed
        let measured = 0
        if (config.value.net_traffic_counter_mode === 'total') {
            measured = monthlyRx.value + monthlyTx.value
        } else if (config.value.net_traffic_counter_mode === 'rx') {
            measured = monthlyRx.value
        } else if (config.value.net_traffic_counter_mode === 'tx') {
            measured = monthlyTx.value
        }

        const userTotalBytes = Math.floor(config.value.adjustment_gb * 1024 * 1024 * 1024)
        // Adjustment can be negative if user enters less than measured? 
        // Typically adjustment is positive to ADD to measured.
        // If user enters less than measured, it implies measured is wrong or reset needed. (But we can't decrease measured easily without reset).
        // Let's assume adjustment allows negative? Backend uses uint64 so negative might be tricky.
        // Backend logic: total = measured + adjustment.
        // models.SSHHost adjustment is uint64. 
        // If user wants Total < Measured, we can't support it with uint64 adjustment unless we support negative adjustment.
        // But let's assume valid case is Calibration > Measured.
        let trafficAdj = userTotalBytes - measured
        if (trafficAdj < 0) trafficAdj = 0 // Prevent underflow/negative for now
        
        // Join list to string
        const interfaceStr = config.value.net_interface_list.join(',')
        
        await sshStore.modifyHost(hostId, {
            net_interface: interfaceStr,
            net_reset_day: config.value.net_reset_day,
            net_traffic_limit: trafficLimit,
            net_traffic_used_adjustment: trafficAdj,
            net_traffic_counter_mode: config.value.net_traffic_counter_mode
        })
        message.success('Configuration saved')
    } catch (e) {
        message.error('Failed to save configuration')
        console.error(e)
    } finally {
        saving.value = false
    }
}

onUnmounted(() => {
  if (socket.value) socket.value.close()
})
</script>
