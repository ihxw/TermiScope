<template>
  <div class="profile-container">
    <a-card :bordered="false" :body-style="{ padding: '0 24px 24px' }">
      <a-tabs v-model:activeKey="activeTab">
        <!-- Basic Info Tab -->
        <a-tab-pane key="basic" :tab="t('nav.profile')">
          <div style="padding-top: 16px">
            <a-descriptions bordered :column="1" size="small">
              <a-descriptions-item :label="t('user.username')">
                {{ authStore.user?.username }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('user.email')">
                {{ authStore.user?.email }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('user.displayName')">
                {{ authStore.user?.display_name || '-' }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('user.role')">
                <a-tag :color="authStore.user?.role === 'admin' ? 'red' : 'blue'">
                  {{ authStore.user?.role }}
                </a-tag>
              </a-descriptions-item>
              <a-descriptions-item :label="t('user.status')">
                <a-tag :color="authStore.user?.status === 'active' ? 'success' : 'default'">
                  {{ authStore.user?.status }}
                </a-tag>
              </a-descriptions-item>
              <a-descriptions-item :label="t('user.lastLogin')">
                {{ formatDate(authStore.user?.last_login_at) }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('twofa.title')">
                <a-tag :color="authStore.user?.two_factor_enabled ? 'success' : 'default'">
                  {{ authStore.user?.two_factor_enabled ? t('twofa.enabled') : t('twofa.disabled') }}
                </a-tag>
              </a-descriptions-item>
            </a-descriptions>

            <a-divider />

            <a-space>
              <a-button type="primary" size="small" @click="showPasswordModal = true">
                {{ t('auth.changePassword') }}
              </a-button>

              <a-button 
                v-if="!authStore.user?.two_factor_enabled"
                type="primary" 
                size="small" 
                @click="handleSetup2FA"
              >
                {{ t('twofa.enable') }}
              </a-button>

              <a-button 
                v-else
                danger 
                size="small" 
                @click="showDisable2FAModal = true"
              >
                {{ t('twofa.disable') }}
              </a-button>

              <a-button 
                v-if="authStore.user?.two_factor_enabled"
                size="small" 
                @click="handleRegenerateBackupCodes"
              >
                {{ t('twofa.regenerateBackupCodes') }}
              </a-button>
            </a-space>
          </div>
        </a-tab-pane>

        <!-- Login History Tab -->
        <a-tab-pane key="history" :tab="t('history.loginHistory')">
          <div style="padding-top: 16px">
            <a-table
              :columns="historyColumns"
              :data-source="loginHistory"
              :loading="historyLoading"
              :pagination="pagination"
              row-key="id"
              size="small"
              @change="handleTableChange"
            >
              <template #bodyCell="{ column, record }">
                <template v-if="column.key === 'status'">
                  <a-tag :color="getStatusColor(record.status)">
                    {{ getStatusText(record.status) }}
                  </a-tag>
                </template>
                <template v-else-if="column.key === 'login_at'">
                  {{ formatDate(record.login_at) }}
                </template>
                <template v-else-if="column.key === 'user_agent'">
                  <a-tooltip :title="record.user_agent">
                    <span class="user-agent-text">{{ record.user_agent }}</span>
                  </a-tooltip>
                </template>
                <template v-else-if="column.key === 'is_current'">
                  <a-tag v-if="record.is_current" color="green">{{ t('history.current') }}</a-tag>
                </template>
              </template>
            </a-table>
          </div>
        </a-tab-pane>

        <!-- Active Sessions Tab -->
        <a-tab-pane key="sessions" :tab="t('history.sessions')">
          <div style="padding-top: 16px">
            <a-list :data-source="activeSessions" :loading="historyLoading">
              <template #renderItem="{ item }">
                <a-list-item>
                  <a-list-item-meta
                    :title="item.is_current ? t('history.current') : item.ip_address"
                    :description="item.user_agent"
                  >
                    <template #avatar>
                      <a-avatar style="background-color: #f56a00" v-if="item.is_current">
                        <template #icon><UserOutlined /></template>
                      </a-avatar>
                      <a-avatar style="background-color: #87d068" v-else>
                        <template #icon><LaptopOutlined /></template>
                      </a-avatar>
                    </template>
                  </a-list-item-meta>
                  <template #actions>
                    <a-button 
                      v-if="!item.is_current" 
                      type="link" 
                      danger 
                      @click="confirmRevoke(item.jti)"
                    >
                      {{ t('history.revoke') }}
                    </a-button>
                    <span v-else style="color: #52c41a; font-weight: bold">{{ t('history.statusActive') }}</span>
                  </template>
                </a-list-item>
              </template>
            </a-list>
            <div v-if="activeSessions.length === 0 && !historyLoading" style="text-align: center; padding: 20px; color: #999">
              {{ t('history.noActiveSessions') }}
            </div>
          </div>
        </a-tab-pane>
      </a-tabs>
    </a-card>

    <!-- Change Password Modal -->
    <a-modal
      v-model:open="showPasswordModal"
      :title="t('auth.changePassword')"
      :confirmLoading="loading"
      @ok="handlePasswordSubmit"
    >
      <a-form layout="vertical">
        <a-form-item :label="t('auth.oldPassword')">
          <a-input-password v-model:value="passwordForm.current" />
        </a-form-item>
        <a-form-item :label="t('auth.newPassword')">
          <a-input-password v-model:value="passwordForm.new" />
        </a-form-item>
        <a-form-item :label="t('auth.confirmPassword')">
          <a-input-password v-model:value="passwordForm.confirm" />
        </a-form-item>
      </a-form>
    </a-modal>

    <!-- 2FA Setup Modal -->
    <a-modal
      v-model:open="show2FASetupModal"
      :title="t('twofa.setup')"
      :confirmLoading="loading"
      @ok="handleVerifySetup"
      width="600px"
    >
      <a-alert :message="t('twofa.setupDesc')" type="info" show-icon style="margin-bottom: 16px" />
      
      <!-- QR Code -->
      <div style="text-align: center; margin: 20px 0">
        <img v-if="qrCodeData" :src="qrCodeData" alt="QR Code" style="max-width: 256px; border: 1px solid #d9d9d9; padding: 8px; border-radius: 4px" />
      </div>
      
      <!-- Secret Key -->
      <a-form layout="vertical">
        <a-form-item :label="t('twofa.secretKey')">
          <a-input :value="secretKey" readonly>
            <template #suffix>
              <a-button size="small" @click="copySecret">{{ t('common.copy') }}</a-button>
            </template>
          </a-input>
        </a-form-item>
        
        <!-- Verification Code -->
        <a-form-item :label="t('twofa.verificationCode')">
          <a-input 
            v-model:value="verificationCode" 
            :placeholder="t('twofa.enterCode')"
            maxlength="6"
          />
        </a-form-item>
      </a-form>
    </a-modal>

    <!-- Disable 2FA Modal -->
    <a-modal
      v-model:open="showDisable2FAModal"
      :title="t('twofa.disable')"
      :confirmLoading="loading"
      @ok="handleDisable2FA"
    >
      <a-alert :message="t('twofa.disableWarning')" type="warning" show-icon style="margin-bottom: 16px" />
      <a-form layout="vertical">
        <a-form-item :label="t('twofa.verificationCode')">
          <a-input 
            v-model:value="disableVerificationCode" 
            :placeholder="t('twofa.enterCode')"
            maxlength="6"
          />
        </a-form-item>
      </a-form>
    </a-modal>

    <!-- Backup Codes Modal -->
    <a-modal
      v-model:open="showBackupCodesModal"
      :title="t('twofa.backupCodes')"
      :footer="null"
      width="600px"
    >
      <a-alert :message="t('twofa.backupCodesDesc')" type="warning" show-icon style="margin-bottom: 16px" />
      
      <div style="background: #ffffff; border: 2px solid #d9d9d9; padding: 20px; border-radius: 4px; margin-bottom: 16px">
        <ul style="list-style: none; padding: 0; margin: 0; font-family: 'Courier New', monospace; font-size: 16px">
          <li v-for="(code, index) in backupCodes" :key="index" style="padding: 8px 0; color: #262626; font-weight: 500">
            {{ code }}
          </li>
        </ul>
      </div>

      <a-space>
        <a-button type="primary" @click="downloadBackupCodes">
          {{ t('twofa.downloadBackupCodes') }}
        </a-button>
        <a-button @click="showBackupCodesModal = false">
          {{ t('common.close') }}
        </a-button>
      </a-space>
    </a-modal>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, computed, watch } from 'vue'
import { message, Modal } from 'ant-design-vue'
import { useI18n } from 'vue-i18n'
import { UserOutlined, LaptopOutlined } from '@ant-design/icons-vue'
import { useAuthStore } from '../stores/auth'
import { changePassword, getLoginHistory, revokeSession } from '../api/auth'
import { setup2FA, verifySetup2FA, disable2FA, regenerateBackupCodes } from '../api/twofa'

const { t } = useI18n()
const authStore = useAuthStore()

const activeTab = ref('basic')
const showPasswordModal = ref(false)
const show2FASetupModal = ref(false)
const showDisable2FAModal = ref(false)
const showBackupCodesModal = ref(false)
const loading = ref(false)

const loginHistory = ref([])
const historyLoading = ref(false)
const pagination = reactive({
  current: 1,
  pageSize: 10,
  total: 0,
  showSizeChanger: true
})

const historyColumns = [
  { title: t('history.ipAddress'), dataIndex: 'ip_address', key: 'ip_address' },
  { title: t('history.browser'), dataIndex: 'user_agent', key: 'user_agent', ellipsis: true },
  { title: t('history.loginTime'), dataIndex: 'login_at', key: 'login_at' },
  { title: t('history.status'), dataIndex: 'status', key: 'status' },
  { title: '', key: 'is_current', width: 80 }
]

const activeSessions = computed(() => {
  return loginHistory.value.filter(s => s.status === 'Active')
})

const passwordForm = ref({
  current: '',
  new: '',
  confirm: ''
})

const qrCodeData = ref('')
const secretKey = ref('')
const verificationCode = ref('')
const disableVerificationCode = ref('')
const backupCodes = ref([])

onMounted(() => {
  fetchHistory()
})

watch(activeTab, (val) => {
  if (val === 'history' || val === 'sessions') {
    fetchHistory()
  }
})

const fetchHistory = async () => {
  historyLoading.value = true
  try {
    const res = await getLoginHistory(pagination.current, pagination.pageSize)
    loginHistory.value = res.data
    pagination.total = res.pagination.total
  } catch (error) {
    message.error(t('history.loadWebFailed'))
  } finally {
    historyLoading.value = false
  }
}

const handleTableChange = (pag) => {
  pagination.current = pag.current
  pagination.pageSize = pag.pageSize
  fetchHistory()
}

const confirmRevoke = (jti) => {
  Modal.confirm({
    title: t('history.revokeConfirm'),
    okText: t('common.ok'),
    cancelText: t('common.cancel'),
    onOk: async () => {
      try {
        await revokeSession(jti)
        message.success(t('history.revokeSuccess'))
        fetchHistory()
      } catch (error) {
        message.error(t('history.revokeFailed'))
      }
    }
  })
}

const getStatusColor = (status) => {
  switch (status) {
    case 'Active': return 'green'
    case 'Revoked': return 'red'
    default: return 'gray'
  }
}

const getStatusText = (status) => {
  switch (status) {
    case 'Active': return t('history.statusActive')
    case 'Revoked': return t('history.statusRevoked')
    case 'Expired': return t('history.statusExpired')
    default: return status
  }
}

const formatDate = (dateString) => {
  if (!dateString) return '-'
  return new Date(dateString).toLocaleString()
}

const handlePasswordSubmit = async () => {
  if (!passwordForm.value.current || !passwordForm.value.new || !passwordForm.value.confirm) {
    message.error(t('auth.invalidCredentials'))
    return
  }

  if (passwordForm.value.new !== passwordForm.value.confirm) {
    message.error(t('auth.passwordMismatch'))
    return
  }

  if (passwordForm.value.new.length < 6) {
    message.error(t('auth.passwordMinLength'))
    return
  }

  loading.value = true
  try {
    const currentHash = passwordForm.value.current
    const newHash = passwordForm.value.new
    
    await changePassword(currentHash, newHash)
    message.success(t('auth.passwordChanged'))
    showPasswordModal.value = false
    passwordForm.value = { current: '', new: '', confirm: '' }
  } catch (error) {
    console.error('Password change failed:', error)
    if (error.response?.data?.error) {
      // Don't show generic error if there's a specific message
      message.error(error.response.data.error)
    } else {
      message.error(t('common.error'))
    }
  } finally {
    loading.value = false
  }
}

const handleSetup2FA = async () => {
  loading.value = true
  try {
    const response = await setup2FA()
    qrCodeData.value = response.qr_code
    secretKey.value = response.secret
    show2FASetupModal.value = true
  } catch (error) {
    message.error(t('twofa.setupFailed'))
  } finally {
    loading.value = false
  }
}

const handleVerifySetup = async () => {
  if (!verificationCode.value || verificationCode.value.length !== 6) {
    message.error(t('twofa.invalidCode'))
    return
  }

  loading.value = true
  try {
    const response = await verifySetup2FA(verificationCode.value, secretKey.value)
    message.success(t('twofa.setupSuccess'))
    
    // Show backup codes
    backupCodes.value = response.codes
    showBackupCodesModal.value = true
    
    // Refresh user info
    await authStore.fetchCurrentUser()
    show2FASetupModal.value = false
    verificationCode.value = ''
  } catch (error) {
    message.error(t('twofa.verifyFailed'))
  } finally {
    loading.value = false
  }
}

const handleDisable2FA = async () => {
  if (!disableVerificationCode.value || disableVerificationCode.value.length !== 6) {
    message.error(t('twofa.invalidCode'))
    return
  }

  loading.value = true
  try {
    await disable2FA(disableVerificationCode.value)
    message.success(t('twofa.disableSuccess'))
    await authStore.fetchCurrentUser()
    showDisable2FAModal.value = false
    disableVerificationCode.value = ''
  } catch (error) {
    message.error(t('twofa.verifyFailed'))
  } finally {
    loading.value = false
  }
}

const handleRegenerateBackupCodes = async () => {
  Modal.confirm({
    title: t('twofa.regenerateBackupCodes'),
    content: t('twofa.regenerateConfirm'),
    onOk: async () => {
      try {
        const response = await regenerateBackupCodes()
        backupCodes.value = response.codes
        showBackupCodesModal.value = true
        message.success(t('twofa.backupCodesRegenerated'))
      } catch (error) {
        message.error(t('twofa.regenerateFailed'))
      }
    }
  })
}

const copySecret = () => {
  navigator.clipboard.writeText(secretKey.value)
  message.success(t('twofa.secretCopied'))
}

const downloadBackupCodes = () => {
  const content = backupCodes.value.join('\n')
  const blob = new Blob([content], { type: 'text/plain' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = 'termiscope-backup-codes.txt'
  a.click()
  URL.revokeObjectURL(url)
  message.success(t('twofa.backupCodesDownloaded'))
}
</script>

<style scoped>
.profile-container {
  padding: 16px;
}

.user-agent-text {
  font-size: 12px;
  color: #888;
}

@media (max-width: 768px) {
  .profile-container {
    padding: 8px;
  }
  
  .profile-container :deep(.ant-card-head) {
    padding: 0 12px;
  }
  
  .profile-container :deep(.ant-card-body) {
    padding: 12px;
  }
  
  .profile-container :deep(.ant-descriptions-item-label),
  .profile-container :deep(.ant-descriptions-item-content) {
    padding: 8px !important;
    font-size: 12px;
  }
  
  .profile-container :deep(.ant-space) {
    flex-wrap: wrap;
    gap: 8px !important;
  }
  
  .profile-container :deep(.ant-btn) {
    font-size: 12px;
    padding: 4px 8px;
  }
}
</style>
