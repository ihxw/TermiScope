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
        <p style="color: #666; font-size: 13px">{{ t('auth.resetPasswordDesc') }}</p>
      </div>

      <a-form
        :model="formState"
        @finish="handleSubmit"
        layout="vertical"
      >
        <a-form-item
          :label="t('auth.email')"
          name="email"
          :rules="[
            { required: true, message: t('auth.emailRequired') },
            { type: 'email', message: t('auth.emailInvalid') }
          ]"
        >
          <a-input
            v-model:value="formState.email"
            placeholder="example@email.com"
            size="middle"
          >
            <template #prefix>
              <MailOutlined />
            </template>
          </a-input>
        </a-form-item>

        <a-form-item>
          <a-button
            type="primary"
            html-type="submit"
            size="middle"
            block
            :loading="loading"
          >
            {{ t('auth.sendResetEmail') }}
          </a-button>
        </a-form-item>
        
        <div style="text-align: center">
           <a-button type="link" size="small" @click="router.push('/login')">
              {{ t('common.backToLogin') }}
            </a-button>
        </div>
      </a-form>

      <a-alert
        v-if="successMsg"
        :message="successMsg"
        type="success"
        show-icon
        closable
        style="margin-top: 16px"
      />

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
  CodeOutlined, 
  MailOutlined,
  BulbOutlined,
  BulbFilled
} from '@ant-design/icons-vue'
import { useThemeStore } from '../stores/theme'
import { useLocaleStore } from '../stores/locale'
import { useI18n } from 'vue-i18n'
import axios from 'axios'
import api from '../api' // Ensure we use configured axios instance if possible, or direct axios if no auth needed

const { t } = useI18n()
const router = useRouter()
const themeStore = useThemeStore()
const localeStore = useLocaleStore()

const formState = reactive({
  email: ''
})

const loading = ref(false)
const error = ref('')
const successMsg = ref('')

const handleSubmit = async () => {
  loading.value = true
  error.value = ''
  successMsg.value = ''

  try {
    // We use the configured api instance but this endpoint is public
    await api.post('/auth/forgot-password', {
      email: formState.email
    })
    
    successMsg.value = t('auth.resetEmailSent')
    formState.email = '' // clear input
  } catch (err) {
    console.error('Reset error:', err)
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
/* Reuse login styles if global, or copy them */
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
