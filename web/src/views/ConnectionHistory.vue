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
                  v-else-if="record.status !== 'Revoked'"
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
      </a-tabs>
    </a-card>
  </div>
</template>

<script setup>
import { ref, onMounted, computed } from 'vue'
import { message } from 'ant-design-vue'
import { useI18n } from 'vue-i18n'
import { getConnectionLogs } from '../api/logs'
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
}
</style>

