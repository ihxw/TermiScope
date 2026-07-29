<template>
  <main class="not-found-page">
    <a-result
      status="404"
      :title="t('common.notFoundTitle')"
      :sub-title="t('common.notFoundDescription')"
    >
      <template #extra>
        <a-button type="primary" @click="returnToApp">
          {{ authStore.isAuthenticated ? t('common.backToWorkspace') : t('common.backToLogin') }}
        </a-button>
      </template>
    </a-result>
  </main>
</template>

<script setup>
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'

const router = useRouter()
const authStore = useAuthStore()
const { t } = useI18n()

const returnToApp = () => {
  router.push(authStore.isAuthenticated ? { name: 'Terminal' } : { name: 'Login' })
}
</script>

<style scoped>
.not-found-page {
  min-height: 100vh;
  min-height: 100dvh;
  display: grid;
  place-items: center;
  padding: 24px;
  background: var(--bg-secondary);
}
</style>
