<template>
  <div class="system-management">
    <a-card :title="t('nav.system')" :bordered="false">
      <a-divider orientation="left">{{ t('system.backupTitle') }}</a-divider>
      <div class="management-section">
        <p>{{ t('system.backupDesc') }}</p>
        <a-button type="primary" :loading="backupLoading" @click="handleBackup">
          <template #icon><DownloadOutlined /></template>
          {{ t('system.startBackup') }}
        </a-button>
      </div>

      <a-divider orientation="left">{{ t('system.restoreTitle') }}</a-divider>
      <div class="management-section">
        <a-alert
          :message="t('system.restoreWarningTitle')"
          :description="t('system.restoreWarningDesc')"
          type="warning"
          show-icon
          style="margin-bottom: 24px"
        />
        <p>{{ t('system.restoreDesc') }}</p>
        <a-upload
          name="file"
          :multiple="false"
          :show-upload-list="false"
          :before-upload="beforeRestoreUpload"
          @change="handleRestoreChange"
        >
          <a-button :loading="restoreLoading">
            <template #icon><UploadOutlined /></template>
            {{ t('system.startRestore') }}
          </a-button>
        </a-upload>
      </div>

      <a-divider orientation="left">{{ t('system.settingsTitle') }}</a-divider>
      <div class="management-section">
        <a-tabs v-model:activeKey="activeTab">
          <a-tab-pane key="settings" :tab="t('system.settings')" force-render>
            <a-card :bordered="false">
              <a-form :model="settingsForm" layout="vertical" @finish="handleSaveSettings">
                <a-row :gutter="16">
                  <a-col :span="6">
                    <a-form-item :label="t('system.sshTimeout')" name="ssh_timeout">
                      <a-input v-model:value="settingsForm.ssh_timeout" />
                    </a-form-item>
                  </a-col>
                  <a-col :span="6">
                    <a-form-item :label="t('system.idleTimeout')" name="idle_timeout">
                      <a-input v-model:value="settingsForm.idle_timeout" />
                    </a-form-item>
                  </a-col>
                  <a-col :span="6">
                    <a-form-item :label="t('system.maxConnectionsPerUser')" name="max_connections_per_user">
                      <a-input-number v-model:value="settingsForm.max_connections_per_user" :min="1" style="width: 100%" />
                    </a-form-item>
                  </a-col>
                  <a-col :span="6">
                    <a-form-item :label="t('system.loginRateLimit')" name="login_rate_limit">
                      <a-input-number v-model:value="settingsForm.login_rate_limit" :min="1" style="width: 100%" />
                    </a-form-item>
                  </a-col>
                  <a-col :span="6">
                    <a-form-item :label="t('system.accessExpiration')" name="access_expiration">
                      <a-input v-model:value="settingsForm.access_expiration" placeholder="60m" />
                    </a-form-item>
                  </a-col>
                  <a-col :span="6">
                    <a-form-item :label="t('system.refreshExpiration')" name="refresh_expiration">
                      <a-input v-model:value="settingsForm.refresh_expiration" placeholder="168h" />
                    </a-form-item>
                  </a-col>
                </a-row>

                <a-divider orientation="left">{{ t('system.notificationTitle') }}</a-divider>
                <a-row :gutter="16">
                  <a-col :span="8">
                    <a-form-item :label="t('system.smtpServer')" name="smtp_server">
                      <a-input v-model:value="settingsForm.smtp_server" placeholder="smtp.example.com" />
                    </a-form-item>
                  </a-col>
                  <a-col :span="4">
                    <a-form-item :label="t('system.smtpPort')" name="smtp_port">
                      <a-input v-model:value="settingsForm.smtp_port" placeholder="587" />
                    </a-form-item>
                  </a-col>
                  <a-col :span="6">
                    <a-form-item :label="t('system.smtpUser')" name="smtp_user">
                      <a-input v-model:value="settingsForm.smtp_user" />
                    </a-form-item>
                  </a-col>
                  <a-col :span="6">
                    <a-form-item :label="t('system.smtpPassword')" name="smtp_password">
                      <a-input-password v-model:value="settingsForm.smtp_password" />
                    </a-form-item>
                  </a-col>
                  <a-col :span="8">
                    <a-form-item :label="t('system.smtpFrom')" name="smtp_from">
                      <a-input v-model:value="settingsForm.smtp_from" placeholder="noreply@example.com" />
                    </a-form-item>
                  </a-col>
                  <a-col :span="8">
                    <a-form-item :label="t('system.smtpTo')" name="smtp_to">
                      <a-input v-model:value="settingsForm.smtp_to" placeholder="admin@example.com" />
                    </a-form-item>
                  </a-col>
                </a-row>
                <a-row :gutter="16">
                  <a-col :span="12">
                    <a-form-item :label="t('system.telegramToken')" name="telegram_bot_token">
                      <a-input-password v-model:value="settingsForm.telegram_bot_token" />
                    </a-form-item>
                  </a-col>
                  <a-col :span="12">
                    <a-form-item :label="t('system.telegramChatId')" name="telegram_chat_id">
                      <a-input v-model:value="settingsForm.telegram_chat_id" />
                    </a-form-item>
                  </a-col>
                </a-row>
                <a-row :gutter="16">
                  <a-col :span="24">
                    <a-form-item :label="t('system.notificationTemplate')" name="notification_template">
                      <a-textarea v-model:value="settingsForm.notification_template" :rows="6" />
                      <div style="margin-top: 8px">
                        <a-button @click="resetNotificationTemplate" size="small">{{ t('system.resetTemplate') }}</a-button>
                        <span style="margin-left: 8px; font-size: 12px; color: #888">
                          {{ t('system.templateHelp') }}: <span v-pre>{{emoji}}, {{event}}, {{client}}, {{message}}, {{time}}</span>
                        </span>
                      </div>
                    </a-form-item>
                  </a-col>
                </a-row>
                <a-form-item>
                  <a-button type="primary" :loading="settingsLoading" html-type="submit">
                    {{ t('common.save') }}
                  </a-button>
                </a-form-item>
              </a-form>
            </a-card>
          </a-tab-pane>

          <!-- Network Monitor Templates -->
          <a-tab-pane key="net_templates" :tab="t('network.templates')">
            <a-card :bordered="false">
              <div style="margin-bottom: 16px">
                <a-button type="primary" @click="openTemplateModal">
                  <template #icon><PlusOutlined /></template>
                  {{ t('common.add') }}
                </a-button>
              </div>

              <a-table :dataSource="templates" :columns="getTemplateColumns()" :loading="loadingTemplates" rowKey="id" :scroll="{ x: 600 }">
                <template #bodyCell="{ column, record }">
                  <template v-if="column.key === 'actions'">
                    <a-space>
                      <a-button type="link" size="small" @click="openEditModal(record)">{{ t('common.edit') }}</a-button>
                      <a-button type="link" size="small" @click="openApplyModal(record)">{{ t('common.deploy') }}</a-button>
                      <a-popconfirm :title="t('common.confirmDelete')" @confirm="deleteTemplate(record.id)">
                        <a-button type="link" danger size="small">{{ t('common.delete') }}</a-button>
                      </a-popconfirm>
                    </a-space>
                  </template>
                  <template v-if="column.key === 'type'">
                    <a-tag color="blue">{{ record.type.toUpperCase() }}</a-tag>
                  </template>
                </template>
              </a-table>
            </a-card>
          </a-tab-pane>
        </a-tabs>
      </div>
    </a-card>

    <!-- Template Modal -->
    <a-modal v-model:open="templateModalVisible" :title="t('network.addTemplate')" @ok="handleSaveTemplate" :confirmLoading="savingTemplate">
      <a-form layout="vertical">
        <a-form-item :label="t('common.name')" required>
          <a-input v-model:value="templateForm.name" placeholder="e.g. Google DNS" />
        </a-form-item>
        <a-form-item :label="t('network.targetType')" required>
          <a-select v-model:value="templateForm.type">
            <a-select-option value="ping">Ping (ICMP)</a-select-option>
            <a-select-option value="tcping">TCPing (Port)</a-select-option>
          </a-select>
        </a-form-item>
        <a-form-item :label="t('network.targetAddress')" required>
          <a-input v-model:value="templateForm.target" placeholder="e.g. 8.8.8.8" />
        </a-form-item>
        <a-form-item :label="t('network.targetPort')" v-if="templateForm.type === 'tcping'" required>
          <a-input-number v-model:value="templateForm.port" :min="1" :max="65535" style="width: 100%" />
        </a-form-item>
        <a-form-item :label="t('common.label')">
          <a-input v-model:value="templateForm.label" placeholder="Optional label for task" />
        </a-form-item>
        <a-form-item :label="t('network.frequency')">
          <a-input-number v-model:value="templateForm.frequency" :min="10" :max="3600" addon-after="s"/>
        </a-form-item>
        <a-form-item label="图表颜色">
          <div style="display: flex; flex-direction: column; gap: 12px">
            <!-- Color Presets -->
            <div style="display: flex; flex-wrap: wrap; gap: 8px">
              <div 
                v-for="color in materialColors" 
                :key="color" 
                @click="templateForm.color = color"
                :style="{
                  width: '32px',
                  height: '32px',
                  backgroundColor: color,
                  borderRadius: '4px',
                  cursor: 'pointer',
                  border: templateForm.color === color ? '3px solid #000' : '1px solid #d9d9d9',
                  boxShadow: templateForm.color === color ? '0 0 0 2px #fff, 0 0 0 4px ' + color : 'none'
                }"
                :title="color"
              ></div>
            </div>
            <!-- Custom Color Picker -->
            <div style="display: flex; align-items: center; gap: 12px">
              <a-input v-model:value="templateForm.color" type="color" style="width: 60px; height: 40px; cursor: pointer; padding: 4px" />
              <a-input v-model:value="templateForm.color" placeholder="#1890ff" style="flex: 1" />
            </div>
          </div>
        </a-form-item>
      </a-form>
    </a-modal>

    <!-- Apply Modal -->
    <a-modal v-model:open="applyModalVisible" :title="t('network.deployTemplate')" @ok="handleApplyTemplate" :confirmLoading="applyingTemplate">
      <p>{{ t('network.selectHostsToDeploy') }} <b>{{ currentTemplate?.name }}</b></p>
      <a-table :dataSource="hosts" :columns="getHostColumns()" :row-selection="hostRowSelection" rowKey="id" size="small" :pagination="false" :scroll="{ y: 300 }" />
    </a-modal>


    <!-- Backup Password Modal -->
    <a-modal
      v-model:open="backupPasswordModalVisible"
      :title="t('system.backupPasswordTitle')"
      @ok="executeBackup"
      @cancel="backupPasswordModalVisible = false"
    >
      <p>{{ t('system.backupPasswordDesc') }}</p>
      <a-input-password
        v-model:value="backupPassword"
        :placeholder="t('system.passwordPlaceholder')"
      />
    </a-modal>

    <!-- Restore Password Modal -->
    <a-modal
      v-model:open="restorePasswordModalVisible"
      :title="t('system.restorePasswordTitle')"
      @ok="executeRestore"
      @cancel="closeRestoreModal"
    >
      <p>{{ t('system.restorePasswordDesc') }}</p>
      <a-input-password
        v-model:value="restorePassword"
        :placeholder="t('system.passwordPlaceholder')"
      />
    </a-modal>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { message, Modal } from 'ant-design-vue'
import { DownloadOutlined, UploadOutlined } from '@ant-design/icons-vue'
import { useThemeStore } from '../stores/theme'
import api from '../api'
import { getWSTicket } from '../api/auth'

const { t } = useI18n()
const themeStore = useThemeStore()
const backupLoading = ref(false)
const restoreLoading = ref(false)
const settingsLoading = ref(false)

// Backup & Restore State
const backupPasswordModalVisible = ref(false)
const backupPassword = ref('')
const restorePasswordModalVisible = ref(false)
const restorePassword = ref('')
const restoreFile = ref(null)

const settingsForm = reactive({
  ssh_timeout: '30s',
  idle_timeout: '30m',
  max_connections_per_user: 10,
  login_rate_limit: 20,
  access_expiration: '60m',

  refresh_expiration: '168h',
  smtp_server: '',
  smtp_port: '',
  smtp_user: '',
  smtp_password: '',
  smtp_from: '',
  smtp_to: '',
  smtp_to: '',
  telegram_bot_token: '',
  telegram_chat_id: '',
  notification_template: ''
})

const DefaultNotificationTemplate = `{{emoji}}{{emoji}}{{emoji}}
Event: {{event}}
Clients: {{client}}
Message: {{message}}
Time: {{time}}`

const resetNotificationTemplate = () => {
    settingsForm.notification_template = DefaultNotificationTemplate
}

const fetchSettings = async () => {
  try {
    const response = await api.get('/system/settings')
    Object.assign(settingsForm, response)
    // Auto-fill default template if empty
    if (!settingsForm.notification_template) {
        settingsForm.notification_template = DefaultNotificationTemplate
    }
  } catch (err) {
    message.error(t('system.fetchSettingsFailed'))
  }
}

onMounted(() => {
  fetchSettings()
})

const handleSaveSettings = async () => {
  settingsLoading.value = true
  try {
    await api.put('/system/settings', settingsForm)
    message.success(t('system.saveSettingsSuccess'))
  } catch (err) {
    message.error(err.response?.data?.error || t('system.saveSettingsFailed'))
  } finally {
    settingsLoading.value = false
  }
}

const handleBackup = () => {
  backupPassword.value = ''
  backupPasswordModalVisible.value = true
}

const executeBackup = async () => {
  backupPasswordModalVisible.value = false
  backupLoading.value = true
  try {
    const res = await getWSTicket()
    const ticket = res.ticket
    let downloadUrl = `/api/system/backup?token=${ticket}`
    if (backupPassword.value) {
      downloadUrl += `&password=${encodeURIComponent(backupPassword.value)}`
    }
    
    // Check if browser supports direct download via anchor
    // If we want to check for errors first, we might need fetch/blob approach, 
    // but for large files streaming via direct link is better.
    // If backend errors, it returns JSON which browser might try to download.
    // A better approach for error handling is doing a HEAD or simple check first,
    // but here we stick to simple anchor click.
    
    const link = document.createElement('a')
    link.href = downloadUrl
    // Don't set a static filename here if we want the server-provided one (from Content-Disposition)
    // But 'download' attribute is useful. We can try to guess or leave it empty to respect header.
    // However, if we set 'download', it forces download.
    // If we want to support dynamic naming from server, we should omit the filename in 'download' attribute 
    // or set it after checking headers (which requires fetch).
    // For now, let's just let it download.
    // link.setAttribute('download', '') 
    
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    
    message.success(t('system.backupSuccess'))
  } catch (err) {
    message.error(t('system.backupFailed'))
  } finally {
    backupLoading.value = false
  }
}

const beforeRestoreUpload = (file) => {
  const isDb = file.name.endsWith('.db')
  if (!isDb) {
    message.error(t('system.invalidFileType'))
  }
  return isDb
}

const handleRestoreChange = (info) => {
  if (info.file.status === 'uploading') {
    return
  }
  
  // Store file and show password modal
  restoreFile.value = info.file.originFileObj
  restorePassword.value = ''
  restorePasswordModalVisible.value = true
}

const closeRestoreModal = () => {
  restorePasswordModalVisible.value = false
  restoreFile.value = null
}

const executeRestore = () => {
  restorePasswordModalVisible.value = false
  if (restoreFile.value) {
    Modal.confirm({
      title: t('system.restoreConfirmTitle'),
      content: t('system.restoreConfirmContent'),
      okText: t('common.confirm'),
      cancelText: t('common.cancel'),
      onOk: () => performRestore(restoreFile.value, restorePassword.value),
      onCancel: () => {
        restoreFile.value = null
      }
    })
  }
}

const performRestore = async (file, password) => {
  restoreLoading.value = true
  const formData = new FormData()
  formData.append('file', file)
  if (password) {
    formData.append('password', password)
  }

  try {
    await api.post('/system/restore', formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
    })
    message.success(t('system.restoreSuccess'))
    // Advise restart if needed, or simply reload to check
    setTimeout(() => {
      window.location.reload()
    }, 2000)
    restoreFile.value = null // Clear on success
  } catch (err) {
    // Check for incorrect password (403 Forbidden or specific message)
    if (err.response?.status === 403 || err.response?.data?.error === 'incorrect password') {
        message.error(t('system.incorrectPassword'))
        // Re-open modal for retry
        restorePasswordModalVisible.value = true
        // Do NOT clear restoreFile.value so we can retry with same file
    } else {
        message.error(err.response?.data?.error || t('system.restoreFailed'))
        restoreFile.value = null // Clear on other errors
    }
  } finally {
    restoreLoading.value = false
  }
}

// --- Network Templates Logic ---
import { getNetworkTemplates, createNetworkTemplate, updateNetworkTemplate, deleteNetworkTemplate, batchApplyTemplate, getTemplateAssignments } from '../api/networkMonitor'
import { PlusOutlined } from '@ant-design/icons-vue'
import { useSSHStore } from '../stores/ssh'
import { watch } from 'vue'

const sshStore = useSSHStore()
const activeTab = ref('settings')
const templates = ref([])
const loadingTemplates = ref(false)
const templateModalVisible = ref(false)
const savingTemplate = ref(false)
const applyModalVisible = ref(false)
const applyingTemplate = ref(false)
const currentTemplate = ref(null)
const hosts = ref([])
const selectedHostKeys = ref([])

// Material Design color presets
const materialColors = [
    '#F44336', // Red
    '#E91E63', // Pink
    '#9C27B0', // Purple
    '#673AB7', // Deep Purple
    '#3F51B5', // Indigo
    '#2196F3', // Blue
    '#03A9F4', // Light Blue
    '#00BCD4', // Cyan
    '#009688', // Teal
    '#4CAF50', // Green
    '#8BC34A', // Light Green
    '#CDDC39', // Lime
    '#FFEB3B', // Yellow
    '#FFC107', // Amber
    '#FF9800', // Orange
    '#FF5722', // Deep Orange
]

const templateForm = reactive({
    name: '',
    type: 'ping',
    target: '',
    port: 80,
    label: '',
    frequency: 60
})

const isMobile = ref(false)
const checkMobile = () => {
    isMobile.value = window.innerWidth <= 768
}

onMounted(() => {
    checkMobile()
    window.addEventListener('resize', checkMobile)
})

onUnmounted(() => {
    window.removeEventListener('resize', checkMobile)
})

// Use arrow functions directly instead of computed to avoid slot warning
const getTemplateColumns = () => {
    const cols = [
        { title: t('common.name'), key: 'name', dataIndex: 'name', width: 120, ellipsis: true },
        { title: t('network.targetType'), key: 'type', dataIndex: 'type', width: 80 },
        { title: t('network.targetAddress'), key: 'target', dataIndex: 'target', width: 150, ellipsis: true },
        { title: t('network.frequency'), key: 'frequency', dataIndex: 'frequency', customRender: ({ text }) => text + 's', width: 80 },
        { title: t('common.actions'), key: 'actions', width: 160, fixed: isMobile.value ? 'right' : undefined }
    ]
    
    // 移动端隐藏部分非关键列，或者保持全部显示但依靠滚动条
    if (isMobile.value) {
        // Hide frequency on mobile
        return cols.filter(c => c.key !== 'frequency')
    }
    return cols
}

const getHostColumns = () => [
    { title: t('common.name'), dataIndex: 'name' },
    { title: t('host.host'), dataIndex: 'host' }
]

const hostRowSelection = {
  selectedRowKeys: selectedHostKeys,
  onChange: (selectedRowKeys) => {
    selectedHostKeys.value = selectedRowKeys
  }
}

const fetchTemplates = async () => {
    loadingTemplates.value = true
    try {
        const res = await getNetworkTemplates()
        // API returns Array directly or { templates: [] }? Handler returns Array directly.
        // Wait, handler code: c.JSON(http.StatusOK, tmpls) -> Array.
        templates.value = res || []
    } catch(e) {
        message.error('Failed to load templates')
        console.error(e)
    } finally {
        loadingTemplates.value = false
    }
}

const openTemplateModal = () => {
    templateForm.id = null  // Mark as new
    templateForm.name = ''
    templateForm.type = 'ping'
    templateForm.target = ''
    templateForm.port = 80
    templateForm.label = ''
    templateForm.frequency = 60
    templateForm.color = '#1890ff'
    templateModalVisible.value = true
}

const openEditModal = (record) => {
    templateForm.id = record.id  // Mark as edit
    templateForm.name = record.name
    templateForm.type = record.type
    templateForm.target = record.target
    templateForm.port = record.port || 80
    templateForm.label = record.label || ''
    templateForm.frequency = record.frequency || 60
    templateForm.color = record.color || '#1890ff'
    templateModalVisible.value = true
}

const handleSaveTemplate = async () => {
    if(!templateForm.name || !templateForm.target) return message.error('Name and Target are required')
    
    savingTemplate.value = true
    try {
        const data = { ...templateForm }
        if (templateForm.id) {
            // Edit mode
            await updateNetworkTemplate(templateForm.id, data)
            message.success('Updated successfully')
        } else {
            // Create mode
            await createNetworkTemplate(data)
            message.success(t('common.addSuccess'))
        }
        templateModalVisible.value = false
        fetchTemplates()
    } catch(e) {
        message.error(templateForm.id ? 'Failed to update' : t('common.addFailed'))
        console.error(e)
    } finally {
        savingTemplate.value = false
    }
}

const deleteTemplate = async (id) => {
    try {
        await deleteNetworkTemplate(id)
        message.success(t('common.deleteSuccess'))
        fetchTemplates()
    } catch(e) {
        message.error(t('common.deleteFailed'))
    }
}

const openApplyModal = async (tmpl) => {
    currentTemplate.value = tmpl
    selectedHostKeys.value = []
    
    // Load hosts if not loaded
    if(sshStore.hosts.length === 0) await sshStore.fetchHosts()
    hosts.value = sshStore.hosts
    
    applyModalVisible.value = true
    
    // Fetch current assignments
    try {
        const assignedIds = await getTemplateAssignments(tmpl.id)
        if (assignedIds && Array.isArray(assignedIds)) {
            selectedHostKeys.value = assignedIds
        }
    } catch (e) {
        console.error("Failed to load assignments", e)
    }
}

const handleApplyTemplate = async () => {
    if(selectedHostKeys.value.length === 0) return message.warn('Please select at least one host')
    
    applyingTemplate.value = true
    try {
        await batchApplyTemplate({
            template_id: currentTemplate.value.id,
            host_ids: selectedHostKeys.value
        })
        message.success('Template deployed successfully')
        applyModalVisible.value = false
    } catch(e) {
        message.error('Failed to deploy template')
        console.error(e)
    } finally {
        applyingTemplate.value = false
    }
}

// Watch tab change to load data
watch(activeTab, (val) => {
    if(val === 'net_templates') {
        fetchTemplates()
    }
})
</script>

<style scoped>
.system-management {
  padding: 24px;
}
.management-section {
  padding: 16px;
  background: v-bind('themeStore.isDark ? "#1f1f1f" : "#fafafa"');
  border-radius: 4px;
}
.management-section p {
  margin-bottom: 24px;
  color: #8c8c8c;
}

/* Mobile responsive */
@media (max-width: 768px) {
  .system-management {
    padding: 8px;
  }
  
  .management-section {
    padding: 12px;
  }
  
  /* Make form columns stack vertically on mobile */
  .system-management :deep(.ant-col-6),
  .system-management :deep(.ant-col-8),
  .system-management :deep(.ant-col-12),
  .system-management :deep(.ant-col-4) {
    flex: 0 0 100% !important;
    max-width: 100% !important;
  }
  
  .system-management :deep(.ant-card-head-title) {
    font-size: 14px;
  }
  
  .system-management :deep(.ant-divider-inner-text) {
    font-size: 13px;
  }
  
  .system-management :deep(.ant-form-item) {
    margin-bottom: 12px;
  }
  
  .system-management :deep(.ant-btn) {
    font-size: 12px;
  }
}
</style>
