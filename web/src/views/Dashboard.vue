<template>
  <a-config-provider :theme="{ algorithm: themeStore.themeAlgorithm, token: themeStore.themeToken }">
    <a-layout class="compact-layout" style="min-height: 100vh">
      <a-layout-header :style="{ background: themeStore.isDark ? '#1f1f1f' : '#fff', padding: '0 24px', borderBottom: themeStore.isDark ? '1px solid #303030' : '1px solid #f0f0f0', lineHeight: '48px', height: '48px' }" class="dashboard-header">
        <div style="display: flex; align-items: center; justify-content: space-between; height: 100%">
          <!-- Left Section: Logo & Menu Toggle -->
          <div style="display: flex; align-items: center; gap: 12px">
            <!-- Mobile Menu Toggle -->
            <a-button 
              v-if="isMobile" 
              type="text" 
              @click="menuDrawerVisible = true"
              :style="{ color: themeStore.isDark ? '#fff' : '#001529' }"
            >
              <MenuOutlined />
            </a-button>
            
            <div :style="{ color: themeStore.isDark ? '#fff' : '#001529', fontSize: isMobile ? '16px' : '18px', fontWeight: 'bold', display: 'flex', alignItems: 'center' }">
              <CodeOutlined style="margin-right: 8px" />
              <span v-if="!isMobile">TermiScope</span>
            </div>
          </div>
          
          <!-- Desktop Menu -->
          <a-menu
            v-if="!isMobile"
            v-model:selectedKeys="selectedKeys"
            mode="horizontal"
            :theme="themeStore.isDark ? 'dark' : 'light'"
            :style="{ background: 'transparent', border: 'none', lineHeight: '48px', flex: 1, marginLeft: '24px' }"
            @select="handleMenuSelect"
            :keyboard="false"
          >
            <a-menu-item key="Terminal">
              <CodeOutlined />
              {{ t('nav.terminal') }}
            </a-menu-item>
            <a-menu-item key="MonitorDashboard">
              <DashboardOutlined />
              {{ t('nav.monitor') }}
            </a-menu-item>
            <a-menu-item key="FileTransfer">
              <SwapOutlined />
              {{ t('nav.fileTransfer') }}
            </a-menu-item>
            <a-menu-item key="HostManagement">
              <DatabaseOutlined />
              {{ t('nav.hosts') }}
            </a-menu-item>
            <a-menu-item key="ConnectionHistory">
              <HistoryOutlined />
              {{ t('nav.history') }}
            </a-menu-item>
            <a-menu-item key="CommandManagement">
              <ThunderboltOutlined />
              {{ t('nav.commands') }}
            </a-menu-item>
            <a-menu-item key="RecordingManagement">
              <VideoCameraOutlined />
              {{ t('nav.recordings') }}
            </a-menu-item>
            <a-menu-item v-if="authStore.user?.role === 'admin'" key="UserManagement">
              <TeamOutlined />
              {{ t('nav.users') }}
            </a-menu-item>
            <a-menu-item v-if="authStore.user?.role === 'admin'" key="SystemManagement">
              <SettingOutlined />
              {{ t('nav.system') }}
            </a-menu-item>
          </a-menu>

          <!-- Right Section: Actions -->
          <div style="display: flex; align-items: center; gap: 8px" class="header-actions">
            <!-- Version (desktop only) -->
            <div v-if="!isMobile" style="font-size: 12px; color: #8c8c8c; display: flex; align-items: center; gap: 8px">
              v{{ backendVersion }}
              <a-button 
                v-if="updateAvailable" 
                type="primary" 
                size="small" 
                :loading="updateLoading"
                @click="handleUpdateClick"
                style="font-size: 12px; height: 20px; padding: 0 8px;"
              >
                {{ t('common.update') }}
              </a-button>
            </div>
            
            <!-- Language Toggle -->
            <a-button size="small" @click="localeStore.toggleLocale">
              {{ localeStore.isZhCN ? 'EN' : '中' }}
            </a-button>
            
            <!-- Theme Toggle -->
            <a-button size="small" @click="themeStore.toggleTheme" :icon="themeStore.isDark ? h(BulbOutlined) : h(BulbFilled)">
              <template v-if="!isMobile">{{ t(themeStore.isDark ? 'theme.light' : 'theme.dark') }}</template>
            </a-button>

            <!-- User Dropdown -->
            <a-dropdown>
              <a class="ant-dropdown-link" @click.prevent :style="{ color: themeStore.isDark ? '#fff' : '#001529' }">
                <UserOutlined style="margin-right: 4px" />
                <span v-if="!isMobile">{{ authStore.user?.username }}</span>
                <DownOutlined style="margin-left: 4px" />
              </a>
              <template #overlay>
                <a-menu>
                  <a-menu-item key="profile" @click="router.push('/dashboard/profile')">
                    <UserOutlined />
                    {{ t('nav.profile') }}
                  </a-menu-item>
                  <a-menu-divider />
                  <a-menu-item key="logout" @click="handleLogout">
                    <LogoutOutlined />
                    {{ t('nav.logout') }}
                  </a-menu-item>
                </a-menu>
              </template>
            </a-dropdown>
          </div>
        </div>
      </a-layout-header>

      <a-layout-content :style="{ background: themeStore.isDark ? '#141414' : '#f0f2f5' }">
        <router-view v-slot="{ Component }">
          <keep-alive include="Terminal">
            <component :is="Component" />
          </keep-alive>
        </router-view>
      </a-layout-content>
      
      <!-- Mobile Menu Drawer -->
      <a-drawer
        v-model:open="menuDrawerVisible"
        placement="left"
        :closable="false"
        :width="280"
        :body-style="{ padding: 0 }"
      >
        <div :style="{ padding: '12px 16px', borderBottom: themeStore.isDark ? '1px solid #303030' : '1px solid #f0f0f0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', background: themeStore.isDark ? '#1f1f1f' : '#fff' }">
          <div style="display: flex; align-items: center; gap: 8px">
            <CodeOutlined :style="{ fontSize: '20px', color: themeStore.isDark ? '#fff' : '#001529' }" />
            <span :style="{ fontSize: '18px', fontWeight: 'bold', color: themeStore.isDark ? '#fff' : '#001529' }">TermiScope</span>
          </div>
          <a-button type="text" @click="menuDrawerVisible = false" :style="{ color: themeStore.isDark ? '#fff' : '#000' }">
            <CloseOutlined />
          </a-button>
        </div>
        <a-menu
          v-model:selectedKeys="selectedKeys"
          mode="inline"
          :theme="themeStore.isDark ? 'dark' : 'light'"
          @select="handleMobileMenuSelect"
        >
          <a-menu-item key="Terminal">
            <CodeOutlined />
            <span>{{ t('nav.terminal') }}</span>
          </a-menu-item>
          <a-menu-item key="MonitorDashboard">
            <DashboardOutlined />
            <span>{{ t('nav.monitor') }}</span>
          </a-menu-item>
          <a-menu-item key="FileTransfer">
            <SwapOutlined />
            <span>{{ t('nav.fileTransfer') }}</span>
          </a-menu-item>
          <a-menu-item key="HostManagement">
            <DatabaseOutlined />
            <span>{{ t('nav.hosts') }}</span>
          </a-menu-item>
          <a-menu-item key="ConnectionHistory">
            <HistoryOutlined />
            <span>{{ t('nav.history') }}</span>
          </a-menu-item>
          <a-menu-item key="CommandManagement">
            <ThunderboltOutlined />
            <span>{{ t('nav.commands') }}</span>
          </a-menu-item>
          <a-menu-item key="RecordingManagement">
            <VideoCameraOutlined />
            <span>{{ t('nav.recordings') }}</span>
          </a-menu-item>
          <a-menu-item v-if="authStore.user?.role === 'admin'" key="UserManagement">
            <TeamOutlined />
            <span>{{ t('nav.users') }}</span>
          </a-menu-item>
          <a-menu-item v-if="authStore.user?.role === 'admin'" key="SystemManagement">
            <SettingOutlined />
            <span>{{ t('nav.system') }}</span>
          </a-menu-item>
        </a-menu>
        <div :style="{ padding: '16px', fontSize: '12px', color: '#8c8c8c', borderTop: '1px solid #f0f0f0', marginTop: '16px' }">
          {{ t('common.version') }}: v{{ frontendVersion }}
        </div>
      </a-drawer>
      <!-- Server Update Progress Modal -->
      <a-modal
        v-model:open="updateProgressVisible"
        :title="t('system.updating')"
        :footer="null"
        :closable="false"
        :maskClosable="false"
        centered
      >
        <div style="text-align: center; padding: 20px 0;">
          <a-spin size="large" v-if="serverUpdateStatus !== 'error' && serverUpdateStatus !== 'finished'" />
          <div style="margin-top: 16px; font-size: 16px; font-weight: 500;">
            <span v-if="serverUpdateStatus === 'downloading'">{{ t('system.downloading', '正在下载更新...') }}</span>
            <span v-else-if="serverUpdateStatus === 'extracting'">{{ t('system.extracting', '正在解压文件...') }}</span>
            <span v-else-if="serverUpdateStatus === 'installing'">{{ t('system.installing', '正在安装...') }}</span>
            <span v-else-if="serverUpdateStatus === 'restarting'">{{ t('system.restarting', '正在重启服务...') }}</span>
            <span v-else-if="serverUpdateStatus === 'finished'" style="color: #52c41a;">
              <check-circle-outlined style="margin-right: 8px" />{{ t('system.updateSuccess', '更新完成！') }}
            </span>
            <span v-else-if="serverUpdateStatus === 'error'" style="color: #f5222d;">
              <close-circle-outlined style="margin-right: 8px" />{{ t('system.updateFailed', '更新失败') }}
            </span>
            <span v-else>{{ t('system.starting', '准备更新...') }}</span>
          </div>
          <div v-if="serverUpdateError" style="margin-top: 8px; color: #f5222d; font-size: 14px;">
            {{ serverUpdateError }}
          </div>
        </div>
      </a-modal>
    </a-layout>
  </a-config-provider>
</template>

<script setup>
import { ref, watch, h, onMounted, onUnmounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import {
  CodeOutlined,
  DatabaseOutlined,
  DashboardOutlined,
  HistoryOutlined,
  TeamOutlined,
  UserOutlined,
  DownOutlined,
  LogoutOutlined,
  ThunderboltOutlined,
  VideoCameraOutlined,
  BulbOutlined,
  BulbFilled,
  SettingOutlined,
  MenuOutlined,
  CloseOutlined,
  SwapOutlined,
  CheckCircleOutlined,
  CloseCircleOutlined
} from '@ant-design/icons-vue'
import { useAuthStore } from '../stores/auth'
import { useThemeStore } from '../stores/theme'
import { useLocaleStore } from '../stores/locale'
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

const selectedKeys = ref(['Terminal'])
const menuDrawerVisible = ref(false)
const isMobile = ref(false)

// Detect mobile device
const checkMobile = () => {
  isMobile.value = window.innerWidth <= 768
}

const handleLogout = async () => {
  await authStore.logout()
  router.push('/login')
}

// Update Logic
import { checkUpdate, performUpdate, getUpdateStatus } from '../api/system'
import { Modal, message } from 'ant-design-vue'

const updateAvailable = ref(false)
const updateInfo = ref(null)
const updateLoading = ref(false)

const checkForUpdates = async () => {
  if (isMobile.value) return 
  try {
    const res = await checkUpdate()
    if (res.update_available) {
      updateAvailable.value = true
      updateInfo.value = res
    }
  } catch (err) {
    console.error('Failed to check updates:', err)
  }
}

const updateProgressVisible = ref(false)
const serverUpdateStatus = ref('')
const serverUpdateError = ref('')
let pollInterval = null

const startPollingUpdateStatus = () => {
  if (pollInterval) clearInterval(pollInterval)
  pollInterval = setInterval(async () => {
    try {
      if (serverUpdateStatus.value === 'restarting') {
        // Ping system info to check if server is back
        try {
           await getSystemInfo()
           // If we get here, server is back online
           clearInterval(pollInterval)
           serverUpdateStatus.value = 'finished'
           setTimeout(() => {
             window.location.reload()
           }, 1500)
        } catch (e) {
           // Still restarting...
        }
        return
      }

      const res = await getUpdateStatus()
      if (res && res.status) {
        serverUpdateStatus.value = res.status
        if (res.error) {
           serverUpdateError.value = res.error
           clearInterval(pollInterval)
        }
        if (res.status === 'restarting') {
           // On restart, slow down polling to wait for server to come back
           clearInterval(pollInterval)
           pollInterval = setInterval(async () => {
              try {
                await getSystemInfo()
                clearInterval(pollInterval)
                serverUpdateStatus.value = 'finished'
                setTimeout(() => window.location.reload(), 1500)
              } catch (e) {
                // Keep waiting
              }
           }, 5000) // 5s interval for restart check
        }
      }
    } catch (e) {
       console.error('Failed to poll status', e)
    }
  }, 1000)
}

const handleUpdateClick = () => {
  Modal.confirm({
    title: t('system.updateAvailable', { version: updateInfo.value.version }),
    content: h('div', [
      h('p', t('system.updateDesc')),
      h('div', { 
        style: {
          maxHeight: '200px', 
          overflowY: 'auto', 
          background: themeStore.isDark ? '#303030' : '#f5f5f5', 
          color: themeStore.isDark ? '#e0e0e0' : '#000000',
          padding: '10px', 
          borderRadius: '4px', 
          whiteSpace: 'pre-wrap',
          marginTop: '8px'
        }
      }, updateInfo.value.body)
    ]),
    okText: t('common.updateNow'),
    cancelText: t('common.cancel'),
    onOk: async () => {
      try {
        updateLoading.value = true
        serverUpdateStatus.value = 'starting'
        serverUpdateError.value = ''
        updateProgressVisible.value = true
        startPollingUpdateStatus()
        
        await performUpdate(updateInfo.value.download_url)
      } catch (err) {
        serverUpdateStatus.value = 'error'
        serverUpdateError.value = err.response?.data?.error || err.message
        if (pollInterval) clearInterval(pollInterval)
      } finally {
        updateLoading.value = false
      }
    }
  })
}

onUnmounted(() => {
  window.removeEventListener('resize', checkMobile)
  if (pollInterval) clearInterval(pollInterval)
})

// Update selected menu based on route name
watch(() => route.name, (name) => {
  if (name) {
    selectedKeys.value = [name]
  }
}, { immediate: true })

const handleMenuSelect = ({ key }) => {
  router.push({ name: key })
}

const handleMobileMenuSelect = ({ key }) => {
  menuDrawerVisible.value = false
  router.push({ name: key })
}


onMounted(() => {
  themeStore.initTheme()
  checkMobile()
  window.addEventListener('resize', checkMobile)
  
  // Fetch backend version
  getSystemInfo().then(info => {
    backendVersion.value = info.version
    // Check for updates after getting version
    checkForUpdates()
  }).catch(err => {
     console.error('Failed to fetch backend version:', err)
     backendVersion.value = 'unknown'
  })
  
  // Ensure user info is loaded
  if (authStore.isAuthenticated && !authStore.user) {
    authStore.fetchCurrentUser().catch((error) => {
      console.error('Failed to fetch user info:', error)
      router.push('/login')
    })
  }
})
</script>

<style scoped>
.dashboard-header {
  position: sticky;
  top: 0;
  z-index: 100;
}

@media (max-width: 768px) {
  .header-actions {
    gap: 4px !important;
  }
  
  .header-actions .ant-btn {
    padding: 4px 8px !important;
  }
}
</style>

