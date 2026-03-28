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
      
      <div style="margin-bottom: 24px; text-align: center">
        <h3>{{ t('auth.resetPassword') }}</h3>
      </div>

      <a-form
        :model="formState"
        @finish="handleResetPassword"
        layout="vertical"
      >
        <a-form-item
          :label="t('auth.newPassword')"
          name="password"
          :rules="[
            { required: true, message: t('auth.passwordRequired') },
            { min: 6, message: t('auth.passwordMinLength', { length: 6 }) }
          ]"
        >
          <a-input-password
            v-model:value="formState.password"
            :placeholder="t('auth.newPasswordPlaceholder')"
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
            { required: true, message: t('auth.passwordRequired') },
            { validator: validateConfirmPassword }
          ]"
        >
          <a-input-password
            v-model:value="formState.confirmPassword"
            :placeholder="t('auth.confirmPasswordPlaceholder')"
            size="middle"
          >
            <template #prefix>
              <LockOutlined />
            </template>
          </a-input-password>
        </a-form-item>

        <a-form-item>
          <a-space style="width: 100%; display: flex; justify-content: space-between">
            <a-button
              type="primary"
              html-type="submit"
              :loading="loading"
              style="flex: 1"
            >
              {{ t('auth.resetPassword') }}
            </a-button>
            <a-button
              style="flex: 1"
              @click="router.push('/login')"
            >
              {{ t('common.cancel') }}
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
    </div>
  </div>
</template>

<script setup>
import { reactive, ref, h } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { message } from 'ant-design-vue'
import { 
  LockOutlined, 
  CodeOutlined, 
  BulbOutlined,
  BulbFilled
} from '@ant-design/icons-vue'
import { useThemeStore } from '../stores/theme'
import { useLocaleStore } from '../stores/locale'
import { useI18n } from 'vue-i18n'
import api from '../api'

const { t } = useI18n()
const router = useRouter()
const route = useRoute()
const themeStore = useThemeStore()
const localeStore = useLocaleStore()

const token = route.query.token

const formState = reactive({
  password: '',
  confirmPassword: ''
})

const loading = ref(false)
const error = ref('')

const validateConfirmPassword = async (_rule, value) => {
  if (value === '') {
    return Promise.reject(t('auth.passwordRequired'))
  } else if (value !== formState.password) {
    return Promise.reject(t('auth.passwordMismatch'))
  }
  return Promise.resolve()
}

const handleResetPassword = async () => {
  if (!token) {
    error.value = t('auth.invalidToken') || 'Invalid token'
    return
  }

  loading.value = true
  error.value = ''

  try {
    await api.post('/auth/reset-password', {
      token: token,
      password: formState.password
    })
    message.success(t('auth.passwordResetSuccess') || 'Password reset successfully')
    router.push('/login')
  } catch (err) {
    error.value = err.response?.data?.error || t('common.error')
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
/* Inherits styling from Login.vue implicitly if common CSS is global, 
   but just in case let's define them identically to Login.vue */
.login-container {
  height: 100vh;
  display: flex;
  justify-content: center;
  align-items: center;
  background-color: var(--ant-layout-body-background);
}

.login-box {
  width: 100%;
  max-width: 400px;
  padding: 40px;
  background-color: var(--ant-component-background);
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.login-title {
  text-align: center;
  margin-bottom: 24px;
}

.login-title :deep(div) {
  font-size: 24px;
  font-weight: 600;
  color: var(--ant-text-color);
}
</style>
