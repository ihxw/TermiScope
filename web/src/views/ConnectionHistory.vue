<template>
  <div class="connection-history-container">
    <a-card :bordered="false">
      <a-tabs v-model:activeKey="activeTab">
        <a-tab-pane key="ssh" :tab="$t('history.sshTitle')">
          <a-table
            :columns="sshColumns"
            :data-source="sshLogs"
            :loading="sshLoading"
            :pagination="sshPagination"
            @change="handleSSHTableChange"
            row-key="id"
            size="small"
            :scroll="{ x: 600 }"
          >
            <template #bodyCell="{ column, record }">
              <template v-if="column.key === 'status'">
                <a-tag :color="getStatusColor(record.status)">
                  {{ record.status }}
                </a-tag>
              </template>
              <template v-if="column.key === 'connected_at'">
                {{ formatDate(record.connected_at) }}
              </template>
              <template v-if="column.key === 'duration'">
                {{ formatDuration(record.duration) }}
              </template>
            </template>
          </a-table>
        </a-tab-pane>
        
        <a-tab-pane key="web" :tab="$t('history.webTitle')">
          <a-table
            :columns="webColumns"
            :data-source="webLogs"
            :loading="webLoading"
            :pagination="webPagination"
            @change="handleWebTableChange"
            row-key="id"
            size="small"
            :scroll="{ x: 800 }"
          >
            <template #bodyCell="{ column, record }">
              <template v-if="column.key === 'status'">
                <a-tag :color="getWebStatusColor(record.status)">
                  {{ record.status }}
                </a-tag>
              </template>
              <template v-if="column.key === 'login_at'">
                {{ formatDate(record.login_at) }}
              </template>
              <template v-if="column.key === 'device_info'">
                <span>{{ record.user_agent }}</span> 
                <!-- TODO: Parse UA string for better display if needed -->
              </template>
              <template v-if="column.key === 'action'">
                <span v-if="record.is_current">
                  <a-tag color="blue">{{ $t('history.currentSession') }}</a-tag>
                </span>
                <a-popconfirm
                  v-else-if="record.status !== 'Revoked' && record.status !== 'Expired'"
                  :title="$t('history.forceLogoutConfirm')"
                  :ok-text="$t('common.confirm')"
                  :cancel-text="$t('common.cancel')"
                  @confirm="revokeSession(record.jti)"
                >
                  <a-button type="link" danger size="small">{{ $t('history.forceLogout') }}</a-button>
                </a-popconfirm>
                <span v-else>-</span>
              </template>
            </template>
          </a-table>
        </a-tab-pane>

        <a-tab-pane key="server" :tab="$t('history.serverLogsTitle')">
          <div class="log-toolbar">
            <a-segmented v-model:value="serverLogType" :options="serverLogTypeOptions" @change="loadServerLogs" />
            <a-select v-model:value="serverLogLines" class="log-lines-select" @change="loadServerLogs">
              <a-select-option :value="100">100</a-select-option>
              <a-select-option :value="300">300</a-select-option>
              <a-select-option :value="1000">1000</a-select-option>
              <a-select-option :value="2000">2000</a-select-option>
            </a-select>
            <a-input-search
              v-model:value="serverLogSearch"
              class="log-search"
              :placeholder="$t('history.searchLogs')"
              allow-clear
            />
            <a-button @click="loadServerLogs" :loading="serverLogLoading">{{ $t('common.refresh') }}</a-button>
            <a-button @click="downloadServerLogs" :disabled="!filteredServerLogLines.length">{{ $t('common.download') }}</a-button>
          </div>
          <a-alert
            v-if="serverLogMeta.truncated"
            class="log-alert"
            type="info"
            show-icon
            :message="$t('history.serverLogsTruncated', { lines: serverLogLines })"
          />
          <a-spin :spinning="serverLogLoading">
            <pre class="server-log-view">{{ formattedServerLogs }}</pre>
          </a-spin>
        </a-tab-pane>
      </a-tabs>
    </a-card>
  </div>
</template>

<script setup>
defineOptions({ name: 'ConnectionHistory' })
import { ref, onMounted, computed } from 'vue'
import { message } from 'ant-design-vue'
import { useI18n } from 'vue-i18n'
import { getConnectionLogs, getServerLogs } from '../api/logs'
import api from '../api'

const { t } = useI18n()
const activeTab = ref('ssh')

// SSH Logs State
const sshLoading = ref(false)
const sshLogs = ref([])
const sshPagination = ref({
  current: 1,
  pageSize: 20,
  total: 0
})

const sshColumns = computed(() => [
  { title: t('host.host'), dataIndex: 'host', key: 'host', width: 120, ellipsis: true },
  { title: t('host.port'), dataIndex: 'port', key: 'port', width: 60 },
  { title: t('host.username'), dataIndex: 'username', key: 'username', width: 100 },
  { title: t('history.status'), dataIndex: 'status', key: 'status', width: 80 },
  { title: t('history.connectedAt'), dataIndex: 'connected_at', key: 'connected_at', width: 150 },
  { title: t('history.duration'), dataIndex: 'duration', key: 'duration', width: 100 }
])

// Web Logs State
const webLoading = ref(false)
const webLogs = ref([])
const webPagination = ref({
  current: 1,
  pageSize: 20,
  total: 0
})

const webColumns = computed(() => [
  { title: t('history.loginTime'), dataIndex: 'login_at', key: 'login_at', width: 150 },
  { title: t('history.ipAddress'), dataIndex: 'ip_address', key: 'ip_address', width: 120 },
  { title: t('history.deviceInfo'), dataIndex: 'user_agent', key: 'device_info', ellipsis: true },
  { title: t('history.status'), dataIndex: 'status', key: 'status', width: 80 },
  { title: t('history.action'), key: 'action', width: 150, fixed: 'right' }
])

onMounted(() => {
  loadSSHLogs()
  loadWebLogs()
  loadServerLogs()
})

// SSH Functions
const loadSSHLogs = async () => {
  sshLoading.value = true
  try {
    const response = await getConnectionLogs({
      page: sshPagination.value.current,
      page_size: sshPagination.value.pageSize
    })
    sshLogs.value = response.data || response
    if (response.pagination) {
      sshPagination.value.total = response.pagination.total
    }
  } catch (error) {
    message.error(t('history.loadSshFailed'))
  } finally {
    sshLoading.value = false
  }
}

const handleSSHTableChange = (pag) => {
  sshPagination.value.current = pag.current
  sshPagination.value.pageSize = pag.pageSize
  loadSSHLogs()
}

const getStatusColor = (status) => {
  const colors = {
    success: 'success',
    failed: 'error',
    disconnected: 'default',
    connecting: 'processing'
  }
  return colors[status] || 'default'
}

// Web Functions
const loadWebLogs = async () => {
  webLoading.value = true
  try {
    const response = await api.get('/auth/login-history', {
      params: {
        page: webPagination.value.current,
        page_size: webPagination.value.pageSize
      }
    })
    // API returns { data: [...], pagination: {...} }
    webLogs.value = response.data || []
    if (response.pagination) {
      webPagination.value.total = response.pagination.total
    }
  } catch (error) {
    message.error(t('history.loadWebFailed'))
  } finally {
    webLoading.value = false
  }
}

const handleWebTableChange = (pag) => {
  webPagination.value.current = pag.current
  webPagination.value.pageSize = pag.pageSize
  loadWebLogs()
}

const getWebStatusColor = (status) => {
  if (status === 'Active') return 'success'
  if (status === 'Revoked') return 'error'
  if (status === 'Expired') return 'warning'
  return 'default'
}

const revokeSession = async (jti) => {
  try {
    await api.post('/auth/sessions/revoke', { jti })
    message.success(t('history.revokeSuccess'))
    loadWebLogs() // Refresh list
  } catch (error) {
    message.error(t('history.revokeFailed'))
  }
}

// Server Log Functions
const serverLogLoading = ref(false)
const serverLogType = ref('server')
const serverLogLines = ref(300)
const serverLogSearch = ref('')
const serverLogMeta = ref({ truncated: false, path: '' })
const serverLogEntries = ref([])

const serverLogTypeOptions = computed(() => [
  { label: t('history.serverLogTypeServer'), value: 'server' },
  { label: t('history.serverLogTypeError'), value: 'error' }
])

const filteredServerLogLines = computed(() => {
  const query = serverLogSearch.value.trim().toLowerCase()
  if (!query) return serverLogEntries.value
  return serverLogEntries.value.filter(line => line.toLowerCase().includes(query))
})

const formattedServerLogs = computed(() => {
  if (!filteredServerLogLines.value.length) {
    return t('history.noServerLogs')
  }
  return filteredServerLogLines.value.join('\n')
})

const loadServerLogs = async () => {
  serverLogLoading.value = true
  try {
    const response = await getServerLogs({
      type: serverLogType.value,
      lines: serverLogLines.value
    })
    serverLogEntries.value = response.lines || []
    serverLogMeta.value = {
      truncated: Boolean(response.truncated),
      path: response.path || ''
    }
  } catch (error) {
    message.error(t('history.loadServerLogsFailed'))
  } finally {
    serverLogLoading.value = false
  }
}

const downloadServerLogs = () => {
  const blob = new Blob([filteredServerLogLines.value.join('\n')], { type: 'text/plain;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `termiscope-${serverLogType.value}-logs.txt`
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}

// Common Utils
const formatDate = (dateString) => {
  if (!dateString) return '-'
  return new Date(dateString).toLocaleString()
}

const formatDuration = (seconds) => {
  if (!seconds) return '-'
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  const secs = seconds % 60
  return `${hours}h ${minutes}m ${secs}s`
}
</script>

<style scoped>
.connection-history-container {
  padding: 16px;
}

.log-toolbar {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
  margin-bottom: 12px;
}

.log-lines-select {
  width: 96px;
}

.log-search {
  width: min(320px, 100%);
}

.log-alert {
  margin-bottom: 12px;
}

.server-log-view {
  min-height: 420px;
  max-height: 62vh;
  margin: 0;
  padding: 12px;
  overflow: auto;
  border: 1px solid #d9d9d9;
  border-radius: 6px;
  background: #111827;
  color: #d1d5db;
  font-size: 12px;
  line-height: 1.6;
  white-space: pre-wrap;
  word-break: break-word;
}

@media (max-width: 768px) {
  .connection-history-container {
    padding: 8px;
  }
  
  .connection-history-container :deep(.ant-card-head) {
    padding: 0 12px;
  }
  
  .connection-history-container :deep(.ant-table) {
    font-size: 12px;
  }
  
  .connection-history-container :deep(.ant-table-thead > tr > th),
  .connection-history-container :deep(.ant-table-tbody > tr > td) {
    padding: 8px 6px !important;
  }
  
  .connection-history-container :deep(.ant-tag) {
    font-size: 10px;
    padding: 0 4px;
  }

  .log-toolbar > * {
    width: 100%;
  }
}
</style>
