<template>
  <div class="file-transfer-page">
    <div class="transfer-container">
      <!-- Left Panel -->
      <div class="transfer-panel">
        <div class="panel-header">
          <a-select
            v-model:value="leftHostId"
            :placeholder="t('sftp.selectHost')"
            style="width: 100%"
            show-search
            :filter-option="filterOption"
            @change="onLeftHostChange"
          >
            <a-select-option v-for="host in hosts" :key="host.id" :value="host.id">
              <span>{{ host.name }}</span>
              <span style="color: #8c8c8c; margin-left: 8px; font-size: 12px">{{ host.host }}</span>
            </a-select-option>
          </a-select>
        </div>
        <div class="panel-body">
          <SftpBrowser
            v-if="leftHostId"
            ref="leftBrowserRef"
            :host-id="leftHostId"
            :visible="!!leftHostId"
            :enable-transfer="!!rightHostId"
            :transfer-target-label="rightHostName"
            @transfer="(data) => handleTransfer('left', data)"
          />
          <div v-else class="panel-placeholder">
            <SwapOutlined style="font-size: 48px; color: #d9d9d9" />
            <p style="color: #8c8c8c; margin-top: 16px">{{ t('sftp.selectHost') }}</p>
          </div>
        </div>
      </div>

      <!-- Divider -->
      <div class="transfer-divider">
        <SwapOutlined style="font-size: 20px; color: #8c8c8c" />
      </div>

      <!-- Right Panel -->
      <div class="transfer-panel">
        <div class="panel-header">
          <a-select
            v-model:value="rightHostId"
            :placeholder="t('sftp.selectHost')"
            style="width: 100%"
            show-search
            :filter-option="filterOption"
            @change="onRightHostChange"
          >
            <a-select-option v-for="host in hosts" :key="host.id" :value="host.id">
              <span>{{ host.name }}</span>
              <span style="color: #8c8c8c; margin-left: 8px; font-size: 12px">{{ host.host }}</span>
            </a-select-option>
          </a-select>
        </div>
        <div class="panel-body">
          <SftpBrowser
            v-if="rightHostId"
            ref="rightBrowserRef"
            :host-id="rightHostId"
            :visible="!!rightHostId"
            :enable-transfer="!!leftHostId"
            :transfer-target-label="leftHostName"
            @transfer="(data) => handleTransfer('right', data)"
          />
          <div v-else class="panel-placeholder">
            <SwapOutlined style="font-size: 48px; color: #d9d9d9" />
            <p style="color: #8c8c8c; margin-top: 16px">{{ t('sftp.selectHost') }}</p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, h } from 'vue'
import { useI18n } from 'vue-i18n'
import { notification, Progress, Spin } from 'ant-design-vue'
import { SwapOutlined } from '@ant-design/icons-vue'
import SftpBrowser from '../components/SftpBrowser.vue'
import { getHosts } from '../api/ssh'
import { transferFile } from '../api/sftp'

const { t } = useI18n()

const hosts = ref([])
const leftHostId = ref(null)
const rightHostId = ref(null)
const leftBrowserRef = ref(null)
const rightBrowserRef = ref(null)

const leftHostName = computed(() => {
  const host = hosts.value.find(h => h.id === leftHostId.value)
  return host ? host.name : ''
})

const rightHostName = computed(() => {
  const host = hosts.value.find(h => h.id === rightHostId.value)
  return host ? host.name : ''
})

const filterOption = (input, option) => {
  const host = hosts.value.find(h => h.id === option.value)
  if (!host) return false
  const search = input.toLowerCase()
  return host.name.toLowerCase().includes(search) || host.host.toLowerCase().includes(search)
}

const loadHosts = async () => {
  try {
    const data = await getHosts({ type: 'control' })
    hosts.value = Array.isArray(data) ? data : (data?.hosts || [])
  } catch (error) {
    console.error('Failed to load hosts:', error)
  }
}

const onLeftHostChange = () => {
  // Will trigger SftpBrowser to mount with new hostId
}

const onRightHostChange = () => {
  // Will trigger SftpBrowser to mount with new hostId
}

const handleTransfer = async (side, data) => {
  const sourceHostId = side === 'left' ? leftHostId.value : rightHostId.value
  const destHostId = side === 'left' ? rightHostId.value : leftHostId.value
  const destBrowser = side === 'left' ? rightBrowserRef.value : leftBrowserRef.value
  const destHostName = side === 'left' ? rightHostName.value : leftHostName.value

  if (!sourceHostId || !destHostId) {
    notification.warning({
      message: t('sftp.selectBothHosts'),
      duration: 3,
      placement: 'bottomRight'
    })
    return
  }

  const destPath = destBrowser?.currentPath || '.'
  const key = `transfer-${Date.now()}`

  notification.open({
    key,
    message: t('sftp.transferring'),
    description: h('div', [
      h(Progress, { percent: 0, status: 'active', size: 'small' }),
      h('div', { style: 'display: flex; justify-content: space-between; align-items: center; margin-top: 8px' }, [
        h('span', { style: 'color: #8c8c8c; font-size: 12px' }, `${data.name} → ${destHostName}`),
        h(Spin, { size: 'small' })
      ])
    ]),
    duration: 0,
    placement: 'bottomRight'
  })

  try {
    await transferFile(sourceHostId, destHostId, data.fullPath, destPath, (event) => {
      if (event.type === 'progress') {
        notification.open({
          key,
          message: t('sftp.transferring'),
          description: h('div', [
            h(Progress, { percent: event.percent || 0, status: 'active', size: 'small' }),
            h('div', { style: 'display: flex; justify-content: space-between; align-items: center; margin-top: 8px' }, [
              h('span', { style: 'color: #8c8c8c; font-size: 12px' }, `${data.name} → ${destHostName}`),
              h('span', { style: 'color: #1890ff; font-weight: 500; font-size: 12px' }, event.speed || '')
            ])
          ]),
          duration: 0,
          placement: 'bottomRight'
        })
      }
    })

    notification.success({
      key,
      message: t('sftp.transferComplete'),
      description: t('sftp.transferSuccess', { name: data.name }),
      duration: 3,
      placement: 'bottomRight'
    })

    if (destBrowser) {
      destBrowser.refresh()
    }
  } catch (error) {
    notification.error({
      key,
      message: t('sftp.transferFailed'),
      description: error.message || t('sftp.transferFailed'),
      duration: 4.5,
      placement: 'bottomRight'
    })
  }
}

onMounted(() => {
  loadHosts()
})
</script>

<style scoped>
.file-transfer-page {
  height: calc(100vh - 48px);
  padding: 12px;
  box-sizing: border-box;
}

.transfer-container {
  display: flex;
  height: 100%;
  gap: 0;
  border-radius: 8px;
  overflow: hidden;
}

.transfer-panel {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
  border: 1px solid var(--border-color, #f0f0f0);
  border-radius: 8px;
}

.panel-header {
  padding: 12px;
  border-bottom: 1px solid var(--border-color, #f0f0f0);
}

.panel-body {
  flex: 1;
  overflow: hidden;
  padding: 8px;
}

.panel-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
}

.transfer-divider {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  flex-shrink: 0;
}

/* Dark theme support */
:global(.dark-theme) .transfer-panel {
  border-color: #303030;
}

:global(.dark-theme) .panel-header {
  border-color: #303030;
}
</style>
