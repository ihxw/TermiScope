<template>
  <a-config-provider 
    :theme="{ algorithm: themeStore.themeAlgorithm, token: themeStore.themeToken }"
    :locale="antdLocale"
  >
    <div :class="[themeStore.isDark ? 'dark-theme' : 'light-theme', 'app-shell']">
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
  const cachedTz = sessionStorage.getItem('system_timezone')
  if (cachedTz) {
    localStorage.setItem('system_timezone', cachedTz)
  } else {
    try {
      const response = await api.get('/system/settings')
      if (response && response.timezone) {
        localStorage.setItem('system_timezone', response.timezone)
        sessionStorage.setItem('system_timezone', response.timezone)
      }
    } catch (err) {
      console.error('Failed to load system settings for timezone', err)
    }
  }
  try {
    const response = await api.get('/system/client-settings')
    if (response?.terminal_cursor_style) {
      localStorage.setItem('system_terminal_cursor_style', response.terminal_cursor_style)
      sessionStorage.setItem('system_terminal_cursor_style', response.terminal_cursor_style)
      window.dispatchEvent(new CustomEvent('system-terminal-cursor-style', { detail: response.terminal_cursor_style }))
    }
  } catch (err) {
    console.error('Failed to load terminal cursor style', err)
  }
})
</script>

<style>
/* Global styles are in style.css */
</style>
