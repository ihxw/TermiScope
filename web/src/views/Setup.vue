<template>
  <div class="login-container">
    <div style="position: absolute; top: 20px; right: 20px; display: flex; gap: 12px">
      <a-button size="small" @click="localeStore.toggleLocale">
        {{ t('language.nextLanguage') }}
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

      <div style="margin-bottom: 24px; text-align: center">
        <h3>{{ t('setup.title') }}</h3>
        <p style="color: #666; font-size: 13px">{{ t('setup.description') }}</p>
      </div>

      <a-form
        :model="formState"
        @finish="handleSetup"
        layout="vertical"
      >
        <a-form-item
          :label="t('auth.username')"
          name="username"
          :rules="[{ required: true, message: t('auth.usernameRequired') }]"
        >
          <a-input
            v-model:value="formState.username"
            :placeholder="t('setup.usernamePlaceholder')"
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
          :rules="[
            { required: true, message: t('auth.passwordRequired') },
            { min: 6, message: t('auth.passwordMinLength') }
          ]"
        >
          <a-input-password
            v-model:value="formState.password"
            :placeholder="t('setup.passwordPlaceholder')"
            size="middle"
          >
            <template #prefix>
              <LockOutlined />
            </template>
          </a-input-password>
        </a-form-item>

        <a-form-item
          :label="t('auth.confirmPassword')"
          name="confirmPassword"
          :rules="[
            { required: true, message: t('setup.confirmRequired') },
            { validator: validateConfirmPassword }
          ]"
        >
          <a-input-password
            v-model:value="formState.confirmPassword"
            :placeholder="t('setup.confirmPlaceholder')"
            size="middle"
          >
            <template #prefix>
              <LockOutlined />
            </template>
          </a-input-password>
        </a-form-item>

        <a-form-item>
          <a-button
            type="primary"
            html-type="submit"
            size="middle"
            block
            :loading="loading"
          >
            {{ t('setup.submit') }}
          </a-button>
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
    </div>
  </div>
</template>

<script setup>
import { reactive, ref, h } from 'vue'
import { useRouter } from 'vue-router'
import { message } from 'ant-design-vue'
import {
  UserOutlined,
  LockOutlined,
  CodeOutlined,
  BulbOutlined,
  BulbFilled
} from '@ant-design/icons-vue'
import { useAuthStore } from '../stores/auth'
import { useThemeStore } from '../stores/theme'
import { useLocaleStore } from '../stores/locale'
import { useI18n } from 'vue-i18n'
import { initialize } from '../api/auth'

const { t } = useI18n()
const router = useRouter()
const authStore = useAuthStore()
const themeStore = useThemeStore()
const localeStore = useLocaleStore()

const formState = reactive({
  username: 'admin',
  password: '',
  confirmPassword: ''
})

const loading = ref(false)
const error = ref('')

const validateConfirmPassword = async (_rule, value) => {
  if (value && value !== formState.password) {
    throw new Error(t('auth.passwordMismatch'))
  }
}

const handleSetup = async () => {
  loading.value = true
  error.value = ''

  try {
    const response = await initialize(
      formState.username,
      formState.password
    )

    // Auto-login with returned tokens
    authStore.token = response.token
    authStore.refreshToken = response.refresh_token
    authStore.user = response.user
    localStorage.setItem('token', response.token)
    if (response.refresh_token) {
      localStorage.setItem('refresh_token', response.refresh_token)
    }

    message.success(t('setup.success'))
    router.push({ name: 'MonitorDashboard' })
  } catch (err) {
    console.error('Setup error:', err)
    if (err.response) {
      error.value = err.response.data?.error || t('common.error')
    } else {
      error.value = t('common.error')
    }
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.login-container {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 100vh;
  background-color: var(--bg-secondary);
}

.login-box {
  background-color: var(--bg-primary);
  padding: 40px;
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
  width: 100%;
  max-width: 400px;
}

.login-title {
  text-align: center;
  margin-bottom: 32px;
  font-size: 24px;
  font-weight: bold;
  color: var(--text-primary);
}
</style>
