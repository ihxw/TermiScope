<template>
  <div class="login-container">
    <div style="position: absolute; top: 20px; right: 20px; display: flex; gap: 12px">
      <a-button size="small" @click="localeStore.toggleLocale">
        {{ localeStore.isZhCN ? 'EN' : '中' }}
      </a-button>
      <a-button size="small" @click="themeStore.toggleTheme" :icon="themeStore.isDark ? h(BulbOutlined) : h(BulbFilled)">
        {{ t(themeStore.isDark ? 'theme.light' : 'theme.dark') }}
      </a-button>
    </div>

    <div class="login-box">
      <div class="login-title">
        <CodeOutlined style="font-size: 32px; margin-bottom: 8px" />
        <div>TermiScope</div>
      </div>
      
      <!-- Step 1: Username and Password -->
      <a-form
        v-if="!requires2FA"
        :model="formState"
        @finish="handleLogin"
        layout="vertical"
      >
        <a-form-item
          :label="t('auth.username')"
          name="username"
          :rules="[{ required: true, message: t('auth.usernameRequired') }]"
        >
          <a-input
            v-model:value="formState.username"
            :placeholder="t('auth.usernamePlaceholder')"
            size="middle"
          >
            <template #prefix>
              <UserOutlined />
            </template>
          </a-input>
        </a-form-item>

        <a-form-item
          :label="t('auth.password')"
          name="password"
          :rules="[{ required: true, message: t('auth.passwordRequired') }]"
        >
          <a-input-password
            v-model:value="formState.password"
            :placeholder="t('auth.passwordPlaceholder')"
            size="middle"
          >
            <template #prefix>
              <LockOutlined />
            </template>
          </a-input-password>
        </a-form-item>

        <a-form-item>
          <a-checkbox v-model:checked="formState.remember">
            {{ t('auth.rememberMe') }}
          </a-checkbox>
        </a-form-item>

        <a-form-item>
          <a-button
            type="primary"
            html-type="submit"
            size="middle"
            block
            :loading="loading"
          >
            {{ t('auth.login') }}
          </a-button>
        </a-form-item>
      </a-form>

      <!-- Step 2: 2FA Verification -->
      <a-form
        v-else
        :model="twoFAForm"
        @finish="handleVerify2FA"
        layout="vertical"
      >
        <a-alert
          :message="t('twofa.loginTitle')"
          :description="t('twofa.loginDesc')"
          type="info"
          show-icon
          style="margin-bottom: 16px"
        />
        
        <p style="color: #ff4d4f; font-size: 12px; margin-bottom: 16px">
          {{ t('twofa.backupCodesWarning') }}
        </p>

        <a-form-item
          :label="t('twofa.verificationCodeLabel')"
          name="code"
          :rules="[{ required: true, message: t('twofa.verificationCodeRequired') }]"
        >
          <a-input
            v-model:value="twoFAForm.code"
            :placeholder="t('twofa.verificationCodePlaceholder')"
            size="small"
            maxlength="39"
          >
            <template #prefix>
              <SafetyOutlined />
            </template>
          </a-input>
        </a-form-item>

        <a-form-item>
          <a-space style="width: 100%">
            <a-button
              type="primary"
              html-type="submit"
              size="small"
              :loading="loading"
            >
              {{ t('twofa.verify') }}
            </a-button>
            <a-button
              size="small"
              @click="handleBackToLogin"
            >
              {{ t('common.back') }}
            </a-button>
          </a-space>
        </a-form-item>
      </a-form>

      <a-alert
        v-if="error"
        :message="error"
        type="error"
        closable
        @close="error = ''"
        style="margin-top: 16px"
      />

      <div class="version-info" style="margin-top: 24px; text-align: center; color: #8c8c8c; font-size: 12px">
        <div>v{{ frontendVersion }}</div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref, h, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { message } from 'ant-design-vue'
import { 
  UserOutlined, 
  LockOutlined, 
  CodeOutlined, 
  SafetyOutlined,
  BulbOutlined,
  BulbFilled
} from '@ant-design/icons-vue'
import { useAuthStore } from '../stores/auth'
import { useThemeStore } from '../stores/theme'
import { useLocaleStore } from '../stores/locale'
import { useI18n } from 'vue-i18n'
import api from '../api'
import { getSystemInfo } from '../api/system'
import packageJson from '../../package.json'

const { t } = useI18n()
const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()
const themeStore = useThemeStore()
const localeStore = useLocaleStore()

const frontendVersion = packageJson.version
const backendVersion = ref('...')

onMounted(async () => {
  try {
    const info = await getSystemInfo()
    backendVersion.value = info.version
  } catch (err) {
    console.error('Failed to fetch backend version:', err)
    backendVersion.value = 'unknown'
  }
})

const formState = reactive({
  username: '',
  password: '',
  remember: false
})

const twoFAForm = reactive({
  code: ''
})

const loading = ref(false)
const error = ref('')
const requires2FA = ref(false)
const tempUserId = ref(null)

const handleLogin = async () => {
  loading.value = true
  error.value = ''

  try {
    const response = await authStore.login(
      formState.username,
      formState.password,
      formState.remember
    )

    // Check if 2FA is required (store.login returns the raw response data)
    if (response.requires_2fa) {
      requires2FA.value = true
      tempUserId.value = response.user_id
      // Store temp token for verification
      sessionStorage.setItem('2fa_temp_token', response.temp_token)
      message.info(t('twofa.enterCode'))
    } else {
      // Normal login without 2FA
      // Store already handled token setting
      message.success(t('auth.loginSuccess'))
      
      if (route.query.redirect) {
        router.push(route.query.redirect)
      } else {
        router.push({ name: 'Terminal' })
      }
    }
  } catch (err) {
    console.error('Login error:', err)
    if (err.response) {
      error.value = err.response.data?.error || t('auth.loginFailed')
    } else {
      error.value = t('common.error')
    }
  } finally {
    loading.value = false
  }
}

const handleVerify2FA = async () => {
  loading.value = true
  error.value = ''

  try {
    const token = sessionStorage.getItem('2fa_temp_token')
    await authStore.verify2FA(tempUserId.value, twoFAForm.code, token)
    
    // Clear temp token
    sessionStorage.removeItem('2fa_temp_token')
    
    message.success(t('auth.loginSuccess'))
    
    if (route.query.redirect) {
      router.push(route.query.redirect)
    } else {
      router.push({ name: 'Terminal' })
    }
  } catch (err) {
    error.value = err.response?.data?.error || t('twofa.verifyFailed')
  } finally {
    loading.value = false
  }
}

const handleBackToLogin = () => {
  requires2FA.value = false
  tempUserId.value = null
  twoFAForm.code = ''
  error.value = ''
}
</script>
