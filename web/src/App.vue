<template>
  <a-config-provider :theme="{ algorithm: themeStore.themeAlgorithm, token: themeStore.themeToken }">
    <div :class="[themeStore.isDark ? 'dark-theme' : 'light-theme']" style="min-height: 100vh">
      <router-view />
    </div>
  </a-config-provider>
</template>

<script setup>
import { onMounted } from 'vue'
import { useThemeStore } from './stores/theme'

const themeStore = useThemeStore()

onMounted(() => {
  themeStore.initTheme()
})
</script>

<style>
/* Global styles are in style.css */
</style>
