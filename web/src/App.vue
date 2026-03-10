<template>
  <a-config-provider 
    :theme="{ algorithm: themeStore.themeAlgorithm, token: themeStore.themeToken }"
    :locale="antdLocale"
  >
    <div :class="[themeStore.isDark ? 'dark-theme' : 'light-theme']" style="min-height: 100vh">
      <router-view />
    </div>
  </a-config-provider>
</template>

<script setup>
import { onMounted, computed } from 'vue'
import { useThemeStore } from './stores/theme'
import api from './api'
import { useI18n } from 'vue-i18n'
import zhCN from 'ant-design-vue/es/locale/zh_CN'
import enUS from 'ant-design-vue/es/locale/en_US'

const themeStore = useThemeStore()
const { locale } = useI18n()

// Switch Ant Design locale based on current i18n locale
const antdLocale = computed(() => {
  return locale.value === 'zh-CN' ? zhCN : enUS
})

onMounted(async () => {
  themeStore.initTheme()
  try {
    const response = await api.get('/system/settings')
    if (response && response.timezone) {
      localStorage.setItem('system_timezone', response.timezone)
    }
  } catch (err) {
    console.error('Failed to load system settings for timezone', err)
  }
})
</script>

<style>
/* Global styles are in style.css */
</style>
