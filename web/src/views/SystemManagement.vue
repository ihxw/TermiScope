<template>
  <div class="system-management">
    <a-page-header
      :title="t('nav.system')"
      :sub-title="t('system.pageSubtitle')"
    />

    <a-layout class="system-layout">
      <a-layout-sider
        v-if="!isMobile"
        :width="200"
        class="system-sider"
        :style="{ background: themeStore.isDark ? '#1f1f1f' : '#fff' }"
      >
        <a-menu
          v-model:selectedKeys="sectionKeys"
          mode="inline"
          :items="sectionMenuItems"
          @click="onMenuClick"
        />
      </a-layout-sider>

      <a-layout-content class="system-content">
        <a-segmented
          v-if="isMobile"
          v-model:value="activeSection"
          :options="sectionOptions"
          block
          class="section-segmented"
          @change="onSectionChange"
        />

        <!-- General -->
        <section v-show="activeSection === 'general'" class="section-panel">
          <a-card :title="t('system.sectionGeneral')" :bordered="false">
            <p class="section-desc">{{ t('system.generalDesc') }}</p>
            <a-form :model="settingsForm" layout="vertical" @finish="() => handleSaveSettings('general')">
              <a-row :gutter="16">
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.timezone')" name="timezone" :extra="t('system.timezoneHelp')">
                    <a-select v-model:value="settingsForm.timezone">
                      <a-select-option value="Local">Local (Server Default)</a-select-option>
                      <a-select-option value="UTC">UTC</a-select-option>
                      <a-select-option value="Asia/Shanghai">Asia/Shanghai (CST)</a-select-option>
                      <a-select-option value="America/New_York">America/New_York (EST/EDT)</a-select-option>
                      <a-select-option value="Europe/London">Europe/London (GMT/BST)</a-select-option>
                      <a-select-option value="Asia/Tokyo">Asia/Tokyo (JST)</a-select-option>
                      <a-select-option value="Europe/Paris">Europe/Paris (CET/CEST)</a-select-option>
                    </a-select>
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.sshTimeout')" name="ssh_timeout" :extra="t('system.durationFormatHelp')">
                    <a-input v-model:value="settingsForm.ssh_timeout" placeholder="30s" />
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.idleTimeout')" name="idle_timeout" :extra="t('system.durationFormatHelp')">
                    <a-input v-model:value="settingsForm.idle_timeout" placeholder="30m" />
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.maxConnectionsPerUser')" name="max_connections_per_user">
                    <a-input-number v-model:value="settingsForm.max_connections_per_user" :min="1" style="width: 100%" />
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.loginRateLimit')" name="login_rate_limit" :extra="t('system.loginRateLimitHelp')">
                    <a-input-number v-model:value="settingsForm.login_rate_limit" :min="1" style="width: 100%" />
                  </a-form-item>
                </a-col>
              </a-row>
              <div class="form-footer">
                <a-button type="primary" :loading="settingsLoading" html-type="submit">{{ t('common.save') }}</a-button>
              </div>
            </a-form>
          </a-card>
        </section>

        <!-- Session -->
        <section v-show="activeSection === 'session'" class="section-panel">
          <a-card :title="t('system.sectionSession')" :bordered="false">
            <p class="section-desc">{{ t('system.sessionDesc') }}</p>
            <a-form :model="settingsForm" layout="vertical" @finish="() => handleSaveSettings('session')">
              <a-row :gutter="16">
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.accessExpiration')" name="access_expiration" :extra="t('system.durationFormatHelp')">
                    <a-input v-model:value="settingsForm.access_expiration" placeholder="60m" />
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.refreshExpiration')" name="refresh_expiration" :extra="t('system.durationFormatHelp')">
                    <a-input v-model:value="settingsForm.refresh_expiration" placeholder="168h" />
                  </a-form-item>
                </a-col>
              </a-row>
              <div class="form-footer">
                <a-button type="primary" :loading="settingsLoading" html-type="submit">{{ t('common.save') }}</a-button>
              </div>
            </a-form>
          </a-card>
        </section>

        <!-- Notification -->
        <section v-show="activeSection === 'notification'" class="section-panel">
          <a-card :title="t('system.sectionNotification')" :bordered="false">
            <p class="section-desc">{{ t('system.notificationDesc') }}</p>
            <a-form :model="settingsForm" layout="vertical" @finish="() => handleSaveSettings('notification')">
              <a-form-item :label="t('system.systemNotifyChannels')" name="system_notify_channels">
                <a-checkbox-group v-model:value="systemNotifyChannelList">
                  <a-checkbox value="email">{{ t('system.notifyChannelEmail') }}</a-checkbox>
                  <a-checkbox value="telegram">{{ t('system.notifyChannelTelegram') }}</a-checkbox>
                </a-checkbox-group>
                <div class="field-hint">{{ t('system.systemNotifyChannelsHelp') }}</div>
              </a-form-item>

              <a-collapse v-model:activeKey="notifyCollapseKeys" :bordered="false" class="notify-collapse">
                <a-collapse-panel key="email" :header="t('system.notifyChannelEmail')" :disabled="!emailChannelEnabled">
                  <a-row :gutter="16">
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.smtpServer')" name="smtp_server">
                        <a-input v-model:value="settingsForm.smtp_server" placeholder="smtp.example.com" :disabled="!emailChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.smtpPort')" name="smtp_port">
                        <a-input v-model:value="settingsForm.smtp_port" placeholder="587" :disabled="!emailChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.smtpUser')" name="smtp_user">
                        <a-input v-model:value="settingsForm.smtp_user" :disabled="!emailChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.smtpPassword')" name="smtp_password" :extra="t('system.smtpPasswordKeep')">
                        <a-input-password v-model:value="settingsForm.smtp_password" :disabled="!emailChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.smtpFrom')" name="smtp_from">
                        <a-input v-model:value="settingsForm.smtp_from" placeholder="noreply@example.com" :disabled="!emailChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.smtpTo')" name="smtp_to">
                        <a-input v-model:value="settingsForm.smtp_to" :placeholder="t('system.smtpToPlaceholder')" :disabled="!emailChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :span="24">
                      <a-form-item name="smtp_tls_skip_verify">
                        <a-checkbox v-model:checked="settingsForm.smtp_tls_skip_verify" :disabled="!emailChannelEnabled">
                          {{ t('system.smtpTlsSkipVerify') }}
                        </a-checkbox>
                      </a-form-item>
                    </a-col>
                  </a-row>
                  <a-button type="dashed" :loading="sendingTestEmail" :disabled="!emailChannelEnabled" @click="handleTestEmail">
                    {{ t('system.testEmail') }}
                  </a-button>
                </a-collapse-panel>

                <a-collapse-panel key="telegram" :header="t('system.notifyChannelTelegram')" :disabled="!telegramChannelEnabled">
                  <a-row :gutter="16">
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.telegramToken')" name="telegram_bot_token" :extra="t('system.smtpPasswordKeep')">
                        <a-input-password v-model:value="settingsForm.telegram_bot_token" :disabled="!telegramChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.telegramChatId')" name="telegram_chat_id">
                        <a-input v-model:value="settingsForm.telegram_chat_id" :disabled="!telegramChannelEnabled" />
                      </a-form-item>
                    </a-col>
                  </a-row>
                  <a-button type="dashed" :loading="sendingTestTelegram" :disabled="!telegramChannelEnabled" @click="handleTestTelegram">
                    {{ t('system.testTelegram') }}
                  </a-button>
                </a-collapse-panel>
              </a-collapse>

              <a-form-item :label="t('system.notificationTemplate')" name="notification_template" style="margin-top: 16px">
                <a-textarea v-model:value="settingsForm.notification_template" :rows="6" />
                <div class="template-actions">
                  <a-button size="small" @click="resetNotificationTemplate">{{ t('system.resetTemplate') }}</a-button>
                  <span class="field-hint">
                    {{ t('system.templateHelp') }}:
                    <span v-pre>{{emoji}}, {{event}}, {{client}}, {{message}}, {{time}}</span>
                  </span>
                </div>
              </a-form-item>

              <div class="form-footer">
                <a-button type="primary" :loading="settingsLoading" html-type="submit">{{ t('common.save') }}</a-button>
              </div>
            </a-form>
          </a-card>
        </section>

        <!-- Data: backup + restore -->
        <section v-show="activeSection === 'data'" class="section-panel">
          <a-card :title="t('system.sectionData')" :bordered="false">
            <p class="section-desc">{{ t('system.dataDesc') }}</p>
            <a-row :gutter="[16, 16]">
              <a-col :xs="24" :lg="12">
                <a-card size="small" :title="t('system.backupTitle')">
                  <p class="card-desc">{{ t('system.backupDesc') }}</p>
                  <a-button type="primary" :loading="backupLoading" @click="handleBackup">
                    <template #icon><DownloadOutlined /></template>
                    {{ t('system.startBackup') }}
                  </a-button>
                </a-card>
              </a-col>
              <a-col :xs="24" :lg="12">
                <a-card size="small" :title="t('system.restoreTitle')" class="danger-card">
                  <a-alert
                    :message="t('system.restoreWarningTitle')"
                    :description="t('system.restoreWarningDesc')"
                    type="error"
                    show-icon
                    style="margin-bottom: 16px"
                  />
                  <p class="card-desc">{{ t('system.restoreDesc') }}</p>
                  <a-upload
                    name="file"
                    :multiple="false"
                    :show-upload-list="false"
                    :before-upload="beforeRestoreUpload"
                    :disabled="restoreLoading"
                    @change="handleRestoreChange"
                  >
                    <a-button danger :loading="restoreLoading" :disabled="restoreLoading">
                      <template #icon><UploadOutlined /></template>
                      {{ t('system.startRestore') }}
                    </a-button>
                  </a-upload>
                  <div v-if="restoreLoading" class="restore-progress">
                    <a-progress
                      :percent="uploadPercent"
                      :status="restorePhase === 'restarting' ? 'success' : 'active'"
                      :stroke-color="restorePhase === 'restarting' ? '#52c41a' : '#1890ff'"
                    />
                    <div class="field-hint">
                      <template v-if="restorePhase === 'uploading'">{{ t('system.restoreUploading', { percent: uploadPercent }) }}</template>
                      <template v-else-if="restorePhase === 'processing'">{{ t('system.restoreProcessing') }}</template>
                      <template v-else-if="restorePhase === 'restarting'">{{ t('system.restoreRestarting') }}</template>
                    </div>
                  </div>
                </a-card>
              </a-col>
            </a-row>
          </a-card>
        </section>

        <!-- Maintenance -->
        <section v-show="activeSection === 'maintenance'" class="section-panel">
          <a-card :title="t('system.sectionMaintenance')" :bordered="false">
            <a-alert
              v-if="dbStats.over_threshold"
              type="error"
              show-icon
              :message="t('system.dbOverThresholdTitle')"
              :description="t('system.dbOverThresholdDesc')"
              style="margin-bottom: 16px"
            />
            <p class="section-desc">{{ t('system.dbMaintenanceDesc') }}</p>
            <a-spin :spinning="dbStatsLoading">
              <a-row :gutter="16" class="stats-row">
                <a-col :xs="24" :sm="8">
                  <a-statistic
                    :title="t('system.networkMonitorRows')"
                    :value="dbStats.network_monitor_results_count ?? 0"
                    :value-style="dbStats.over_threshold ? { color: '#cf1322' } : undefined"
                  />
                </a-col>
                <a-col :xs="24" :sm="8">
                  <a-statistic :title="t('system.alertThreshold')" :value="dbStats.alert_threshold ?? 500000" />
                </a-col>
                <a-col :xs="24" :sm="8">
                  <a-statistic :title="t('system.retentionHoursLabel')" :value="dbStats.retention_hours ?? 24" />
                </a-col>
              </a-row>
              <a-space>
                <a-button :loading="dbStatsLoading" @click="fetchDbStats">{{ t('common.refresh') }}</a-button>
                <a-button type="primary" danger :loading="pruneLoading" @click="confirmPruneMonitorData">
                  {{ t('system.pruneMonitorData') }}
                </a-button>
              </a-space>
            </a-spin>
            <a-divider />
            <p class="section-desc">
              {{ t('system.templatesMovedHint') }}
              <a-button type="link" size="small" @click="router.push({ name: 'MonitorTemplates' })">
                {{ t('network.templates') }}
              </a-button>
            </p>
          </a-card>
        </section>
      </a-layout-content>
    </a-layout>

    <a-modal
      v-model:open="backupPasswordModalVisible"
      :title="t('system.backupPasswordTitle')"
      @ok="executeBackup"
      @cancel="backupPasswordModalVisible = false"
    >
      <p>{{ t('system.backupPasswordDesc') }}</p>
      <a-input-password v-model:value="backupPassword" :placeholder="t('system.passwordPlaceholder')" />
    </a-modal>

    <a-modal
      v-model:open="restorePasswordModalVisible"
      :title="t('system.restorePasswordTitle')"
      @ok="executeRestore"
      @cancel="closeRestoreModal"
    >
      <p>{{ t('system.restorePasswordDesc') }}</p>
      <a-input-password v-model:value="restorePassword" :placeholder="t('system.passwordPlaceholder')" />
    </a-modal>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { message, Modal } from 'ant-design-vue'
import { DownloadOutlined, UploadOutlined } from '@ant-design/icons-vue'
import { useThemeStore } from '../stores/theme'
import api from '../api'

defineOptions({ name: 'SystemManagement' })

const VALID_SECTIONS = ['general', 'session', 'notification', 'data', 'maintenance']

const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const themeStore = useThemeStore()

const isMobile = ref(false)
const checkMobile = () => {
  isMobile.value = window.innerWidth <= 768
}

const activeSection = ref(
  VALID_SECTIONS.includes(route.query.section) ? route.query.section : 'general',
)
const sectionKeys = ref([activeSection.value])

const sectionOptions = computed(() =>
  VALID_SECTIONS.map((key) => ({
    value: key,
    label: t(`system.section${key.charAt(0).toUpperCase()}${key.slice(1)}`),
  })),
)

const sectionMenuItems = computed(() =>
  VALID_SECTIONS.map((key) => ({
    key,
    label: t(`system.section${key.charAt(0).toUpperCase()}${key.slice(1)}`),
  })),
)

const syncRouteSection = (section) => {
  if (route.query.section !== section) {
    router.replace({ name: 'SystemManagement', query: { section } })
  }
}

const onMenuClick = ({ key }) => {
  activeSection.value = key
  sectionKeys.value = [key]
  syncRouteSection(key)
  if (key === 'maintenance') fetchDbStats()
}

const onSectionChange = (val) => {
  sectionKeys.value = [val]
  syncRouteSection(val)
  if (val === 'maintenance') fetchDbStats()
}

watch(
  () => route.query.section,
  (section) => {
    if (section && VALID_SECTIONS.includes(section) && section !== activeSection.value) {
      activeSection.value = section
      sectionKeys.value = [section]
      if (section === 'maintenance') fetchDbStats()
    }
  },
)

const backupLoading = ref(false)
const restoreLoading = ref(false)
const settingsLoading = ref(false)
const uploadPercent = ref(0)
const restorePhase = ref('')

const backupPasswordModalVisible = ref(false)
const backupPassword = ref('')
const restorePasswordModalVisible = ref(false)
const restorePassword = ref('')
const restoreFile = ref(null)

const dbStatsLoading = ref(false)
const pruneLoading = ref(false)
const dbStats = reactive({
  network_monitor_results_count: 0,
  alert_threshold: 500000,
  retention_hours: 24,
  over_threshold: false,
})

const settingsForm = reactive({
  timezone: 'Local',
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
  smtp_tls_skip_verify: false,
  telegram_bot_token: '',
  telegram_chat_id: '',
  notification_template: '',
  system_notify_channels: 'email,telegram',
})

const initialTimezone = ref('Local')

const systemNotifyChannelList = computed({
  get() {
    const raw = settingsForm.system_notify_channels || ''
    return raw.split(',').map((s) => s.trim()).filter(Boolean)
  },
  set(values) {
    settingsForm.system_notify_channels = values.join(',')
  },
})

const emailChannelEnabled = computed(() => systemNotifyChannelList.value.includes('email'))
const telegramChannelEnabled = computed(() => systemNotifyChannelList.value.includes('telegram'))

const notifyCollapseKeys = ref(['email', 'telegram'])

watch(emailChannelEnabled, (on) => {
  if (on && !notifyCollapseKeys.value.includes('email')) {
    notifyCollapseKeys.value = [...notifyCollapseKeys.value, 'email']
  }
})
watch(telegramChannelEnabled, (on) => {
  if (on && !notifyCollapseKeys.value.includes('telegram')) {
    notifyCollapseKeys.value = [...notifyCollapseKeys.value, 'telegram']
  }
})

const sendingTestEmail = ref(false)
const sendingTestTelegram = ref(false)

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
    initialTimezone.value = settingsForm.timezone || 'Local'
    if (!settingsForm.notification_template) {
      settingsForm.notification_template = DefaultNotificationTemplate
    }
  } catch (err) {
    message.error(t('system.fetchSettingsFailed'))
  }
}

const fetchDbStats = async () => {
  dbStatsLoading.value = true
  try {
    const data = await api.get('/system/db-stats')
    Object.assign(dbStats, data)
  } catch (err) {
    message.error(err.response?.data?.error || t('system.fetchDbStatsFailed'))
  } finally {
    dbStatsLoading.value = false
  }
}

const confirmPruneMonitorData = () => {
  Modal.confirm({
    title: t('system.pruneConfirmTitle'),
    content: t('system.pruneConfirmContent'),
    okText: t('common.confirm'),
    cancelText: t('common.cancel'),
    okType: 'danger',
    onOk: async () => {
      pruneLoading.value = true
      try {
        const res = await api.post('/system/db-maintenance/prune')
        message.success(
          t('system.pruneSuccess', {
            deleted: res.deleted ?? 0,
            remaining: res.remaining ?? 0,
          }),
        )
        await fetchDbStats()
      } catch (err) {
        message.error(err.response?.data?.error || t('system.pruneFailed'))
      } finally {
        pruneLoading.value = false
      }
    },
  })
}

const handleSaveSettings = async () => {
  settingsLoading.value = true
  const timezoneChanged = settingsForm.timezone !== initialTimezone.value
  try {
    await api.put('/system/settings', settingsForm)
    if (settingsForm.timezone) {
      localStorage.setItem('system_timezone', settingsForm.timezone)
    }
    initialTimezone.value = settingsForm.timezone
    message.success(t('system.saveSettingsSuccess'))
    if (timezoneChanged) {
      message.info(t('system.timezoneReloadHint'), 4)
    }
  } catch (err) {
    message.error(err.response?.data?.error || t('system.saveSettingsFailed'))
  } finally {
    settingsLoading.value = false
  }
}

const handleTestEmail = async () => {
  sendingTestEmail.value = true
  try {
    await api.post('/system/settings/test-email', {
      smtp_server: settingsForm.smtp_server,
      smtp_port: settingsForm.smtp_port,
      smtp_user: settingsForm.smtp_user,
      smtp_password: settingsForm.smtp_password,
      smtp_from: settingsForm.smtp_from,
      smtp_to: settingsForm.smtp_to,
      smtp_tls_skip_verify: settingsForm.smtp_tls_skip_verify,
    })
    message.success(t('system.testEmailSuccess'))
  } catch (err) {
    message.error(t('system.testEmailFailed') + ': ' + (err.response?.data?.error || err.message))
  } finally {
    sendingTestEmail.value = false
  }
}

const handleTestTelegram = async () => {
  sendingTestTelegram.value = true
  try {
    await api.post('/system/settings/test-telegram', {
      telegram_bot_token: settingsForm.telegram_bot_token,
      telegram_chat_id: settingsForm.telegram_chat_id,
    })
    message.success(t('system.testTelegramSuccess'))
  } catch (err) {
    message.error(t('system.testTelegramFailed') + ': ' + (err.response?.data?.error || err.message))
  } finally {
    sendingTestTelegram.value = false
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
    const response = await api.post('/system/backup', { password: backupPassword.value })
    if (response?.filename && response?.ticket) {
      const downloadUrl = `${window.location.protocol}//${window.location.host}/api/system/backup/download?file=${response.filename}&token=${response.ticket}`
      window.location.href = downloadUrl
      message.success(t('system.backupSuccess'))
    } else {
      throw new Error('No filename or ticket returned')
    }
  } catch (err) {
    message.error(t('system.backupFailed') + ': ' + (err.message || err.response?.data?.error))
  } finally {
    backupLoading.value = false
  }
}

const beforeRestoreUpload = (file) => {
  const isValid = file.name.endsWith('.db') || file.name.endsWith('.db.enc') || file.name.endsWith('.enc')
  if (!isValid) message.error(t('system.invalidFileType'))
  return isValid
}

const handleRestoreChange = (info) => {
  if (info.file.status === 'uploading') return
  restoreFile.value = info.file.originFileObj
  restorePassword.value = ''
  const isEncrypted = restoreFile.value.name.endsWith('.enc')
  if (!isEncrypted) {
    Modal.warning({
      title: t('system.restoreUnencryptedWarningTitle'),
      content: t('system.restoreUnencryptedWarning'),
    })
  }
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
      },
    })
  }
}

const performRestore = async (file, password) => {
  restoreLoading.value = true
  uploadPercent.value = 0
  restorePhase.value = 'uploading'
  const formData = new FormData()
  formData.append('file', file)
  if (password) formData.append('password', password)
  try {
    await api.post('/system/restore', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
      onUploadProgress: (progressEvent) => {
        if (progressEvent.total) {
          const percent = Math.round((progressEvent.loaded / progressEvent.total) * 100)
          uploadPercent.value = percent
          if (percent >= 100) restorePhase.value = 'processing'
        }
      },
    })
    restorePhase.value = 'restarting'
    uploadPercent.value = 100
    message.success(t('system.restoreSuccess'))
    restoreFile.value = null
    setTimeout(() => window.location.reload(), 2000)
  } catch (err) {
    if (err.response?.status === 403 || err.response?.data?.error === 'incorrect password') {
      message.error(t('system.incorrectPassword'))
      restorePasswordModalVisible.value = true
    } else {
      message.error(err.response?.data?.error || t('system.restoreFailed'))
      restoreFile.value = null
    }
  } finally {
    if (restorePhase.value !== 'restarting') {
      restoreLoading.value = false
      restorePhase.value = ''
      uploadPercent.value = 0
    }
  }
}

onMounted(() => {
  checkMobile()
  window.addEventListener('resize', checkMobile)
  fetchSettings()
  if (activeSection.value === 'maintenance') fetchDbStats()
})

onUnmounted(() => {
  window.removeEventListener('resize', checkMobile)
})
</script>

<style scoped>
.system-management {
  padding: 24px;
  max-width: 1100px;
  margin: 0 auto;
}
.system-layout {
  background: transparent;
  margin-top: 8px;
}
.system-sider {
  border-radius: 8px;
  margin-right: 16px;
}
.system-content {
  min-height: 400px;
}
.section-segmented {
  margin-bottom: 16px;
}
.section-panel {
  width: 100%;
}
.section-desc,
.card-desc {
  color: #8c8c8c;
  margin-bottom: 16px;
}
.field-hint {
  font-size: 12px;
  color: #888;
  margin-top: 4px;
}
.form-footer {
  margin-top: 8px;
  padding-top: 16px;
  border-top: 1px solid v-bind('themeStore.isDark ? "#303030" : "#f0f0f0"');
}
.notify-collapse {
  background: v-bind('themeStore.isDark ? "#141414" : "#fafafa"');
  border-radius: 8px;
  padding: 8px;
}
.template-actions {
  margin-top: 8px;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}
.danger-card {
  border: 1px solid #ff4d4f;
}
.danger-card :deep(.ant-card-head) {
  border-bottom-color: rgba(255, 77, 79, 0.3);
}
.restore-progress {
  margin-top: 16px;
  max-width: 400px;
}
.stats-row {
  margin-bottom: 16px;
}
@media (max-width: 768px) {
  .system-management {
    padding: 8px;
  }
  .system-sider {
    display: none;
  }
}
</style>
