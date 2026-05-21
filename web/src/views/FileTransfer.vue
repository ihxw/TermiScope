<template>
  <div class="file-transfer-page">
    <div class="transfer-container">
      <!-- Left Panel -->
      <div class="transfer-panel">
        <div class="panel-header">
          <div class="header-content">
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
            <a-button 
              size="small" 
              type="primary" 
              :disabled="!leftHostId || !rightHostId || leftSelectedKeys.length === 0"
              @click="handleBulkTransfer('left')"
            >
              {{ t('sftp.bulkTransfer') }} ({{ leftSelectedKeys.length }})
            </a-button>
          </div>
        </div>
        <div class="panel-body">
          <SftpBrowser
            v-if="leftHostId"
            ref="leftBrowserRef"
            :host-id="leftHostId"
            :host-label="leftHostName"
            :visible="!!leftHostId"
            :enable-transfer="!!rightHostId"
            :transfer-target-label="rightHostName"
            @transfer="(data) => handleTransfer('left', data)"
            @selection-change="(keys) => handleSelectionChange('left', keys)"
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
          <div class="header-content">
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
            <a-button 
              size="small" 
              type="primary" 
              :disabled="!leftHostId || !rightHostId || rightSelectedKeys.length === 0"
              @click="handleBulkTransfer('right')"
            >
              {{ t('sftp.bulkTransfer') }} ({{ rightSelectedKeys.length }})
            </a-button>
          </div>
        </div>
        <div class="panel-body">
          <SftpBrowser
            v-if="rightHostId"
            ref="rightBrowserRef"
            :host-id="rightHostId"
            :host-label="rightHostName"
            :visible="!!rightHostId"
            :enable-transfer="!!leftHostId"
            :transfer-target-label="leftHostName"
            @transfer="(data) => handleTransfer('right', data)"
            @selection-change="(keys) => handleSelectionChange('right', keys)"
          />
          <div v-else class="panel-placeholder">
            <SwapOutlined style="font-size: 48px; color: #d9d9d9" />
            <p style="color: #8c8c8c; margin-top: 16px">{{ t('sftp.selectHost') }}</p>
          </div>
        </div>
      </div>
    </div>

    <TransferQueue ref="transferQueueRef" />

    <SftpConflictModal
      :open="conflictOpen"
      :name="conflictName"
      :is-dir="conflictIsDir"
      :show-apply-to-all="showApplyToAll"
      :apply-to-all="applyToAll"
      :wrap-class="wrapClass"
      :is-dark="themeStore.isDark"
      @update:open="(v) => { if (!v) onConflictCancel() }"
      @update:apply-to-all="(v) => { applyToAll.value = v }"
      @cancel="onConflictCancel"
      @overwrite="onConflictOverwrite"
      @keep-both="onConflictKeepBoth"
    />
  </div>
</template>

<script setup>
defineOptions({ name: 'FileTransfer' })
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { message, Modal } from 'ant-design-vue'
import { SwapOutlined } from '@ant-design/icons-vue'
import SftpBrowser from '../components/SftpBrowser.vue'
import TransferQueue from '../components/TransferQueue.vue'
import SftpConflictModal from '../components/SftpConflictModal.vue'
import { getHosts } from '../api/ssh'
import { transferFile } from '../api/sftp'
import { useThemeStore } from '../stores/theme'
import { useSftpNameConflict } from '../composables/useSftpNameConflict'
import { buildRemotePath } from '../utils/sftpPath'

const { t } = useI18n()
const themeStore = useThemeStore()
const {
  conflictOpen,
  conflictName,
  conflictIsDir,
  showApplyToAll,
  applyToAll,
  wrapClass,
  onConflictCancel,
  onConflictOverwrite,
  onConflictKeepBoth,
  resolveDestName,
  resetBatchPolicy,
} = useSftpNameConflict()

const hosts = ref([])
const leftHostId = ref(null)
const rightHostId = ref(null)
const leftBrowserRef = ref(null)
const rightBrowserRef = ref(null)
const leftSelectedKeys = ref([])
const rightSelectedKeys = ref([])
const transferQueueRef = ref(null)
const activeTransfers = ref(new Map())

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

const getDestFiles = (destBrowser) => destBrowser?.getFiles?.() ?? []

const getBrowserPath = (browser) => {
  if (!browser) return '.'
  if (typeof browser.getCurrentPath === 'function') {
    return browser.getCurrentPath()
  }
  const p = browser.currentPath
  return typeof p === 'string' ? p : (p?.value ?? '.')
}

const getDestPath = (destBrowser) => getBrowserPath(destBrowser)

const buildSourcePath = (sourceBrowser, fileName) =>
  buildRemotePath(getBrowserPath(sourceBrowser), fileName)

const runTransfer = async ({
  sourceHostId,
  destHostId,
  sourcePath,
  destPath,
  displayName,
  destFileName,
  destHostName,
  side,
  data,
  taskId,
}) => {
  await transferFile(
    sourceHostId,
    destHostId,
    sourcePath,
    destPath,
    (event) => {
      if (event.type === 'start') {
        if (transferQueueRef.value && taskId) {
          transferQueueRef.value.updateTask(taskId, {
            total: event.total_size || 0,
            isDir: event.is_dir,
          })
        }
      } else if (event.type === 'progress') {
        if (transferQueueRef.value && taskId) {
          transferQueueRef.value.updateTask(taskId, {
            percent: event.percent || 0,
            speed: event.speed || '',
            transferred: event.transferred,
            total: event.total,
          })
        }
      }
    },
    'copy',
    { destFileName }
  )

  if (transferQueueRef.value && taskId) {
    transferQueueRef.value.updateTask(taskId, {
      status: 'success',
      percent: 100,
    })
  }

  message.success(t('sftp.transferSuccess', { name: destFileName }))
}

const handleTransfer = async (side, data) => {
  const sourceHostId = side === 'left' ? leftHostId.value : rightHostId.value
  const destHostId = side === 'left' ? rightHostId.value : leftHostId.value
  const destBrowser = side === 'left' ? rightBrowserRef.value : leftBrowserRef.value
  const destHostName = side === 'left' ? rightHostName.value : leftHostName.value

  if (!sourceHostId || !destHostId) {
    message.warning(t('sftp.selectBothHosts'))
    return
  }

  const destPath = getDestPath(destBrowser)
  const { destFileName, cancelled } = await resolveDestName(data.name, getDestFiles(destBrowser))
  if (cancelled) {
    return
  }

  // Add to queue with initial state and get taskId
  let taskId = null
  if (transferQueueRef.value) {
    taskId = transferQueueRef.value.addTask({
      name: destFileName,
      sourceHost: side === 'left' ? leftHostName.value : rightHostName.value,
      destHost: destHostName,
      percent: 0,
      status: 'active',
      speed: '',
      total: data.size || 0,
      isDir: data.isDir
    })
  }

  try {
    if (transferQueueRef.value && taskId) {
      transferQueueRef.value.updateTask(taskId, { percent: 0, speed: '' })
    }
    await runTransfer({
      sourceHostId,
      destHostId,
      sourcePath: data.fullPath,
      destPath,
      displayName: data.name,
      destFileName,
      destHostName,
      side,
      data,
      taskId,
    })

    if (destBrowser) {
      destBrowser.refresh()
    }
  } catch (error) {
    console.error('Transfer error:', error)
    
    if (transferQueueRef.value) {
      transferQueueRef.value.updateTask(taskId, {
        status: 'error'
      })
    }
    
    message.error(error.message || t('sftp.transferFailed'))
  }
}

// 批量传输处理
const handleBulkTransfer = async (side) => {
  const sourceHostId = side === 'left' ? leftHostId.value : rightHostId.value
  const destHostId = side === 'left' ? rightHostId.value : leftHostId.value
  const sourceBrowser = side === 'left' ? leftBrowserRef.value : rightBrowserRef.value
  const destBrowser = side === 'left' ? rightBrowserRef.value : leftBrowserRef.value
  const selectedKeys = side === 'left' ? leftSelectedKeys.value : rightSelectedKeys.value
  const destHostName = side === 'left' ? rightHostName.value : leftHostName.value

  if (!sourceHostId || !destHostId || selectedKeys.length === 0) {
    return
  }

  // 确认批量传输
  Modal.confirm({
    title: t('sftp.bulkTransfer'),
    content: t('sftp.confirmBulkTransfer', { count: selectedKeys.length }),
    okText: t('common.ok'),
    cancelText: t('common.cancel'),
    onOk: async () => {
      resetBatchPolicy()
      const destPath = getDestPath(destBrowser)
      const pendingDestNames = new Set(getDestFiles(destBrowser).map((f) => f.name))
      const destFilesSnapshot = () => {
        const listed = getDestFiles(destBrowser)
        const extras = [...pendingDestNames]
          .filter((n) => !listed.some((f) => f.name === n))
          .map((n) => ({ name: n }))
        return [...listed, ...extras]
      }

      const concurrencyLimit = 3
      const runningTransfers = ref(0)
      const transferPromises = []

      for (const key of selectedKeys) {
        const fileName = key.split('/').pop()
        const fullPath = buildSourcePath(sourceBrowser, fileName)
        const fileRecord = sourceBrowser?.getFiles?.()?.find((f) => f.name === fileName)

        const { destFileName, cancelled } = await resolveDestName(
          fileName,
          destFilesSnapshot(),
          { batch: true }
        )
        if (cancelled) {
          message.info(t('sftp.transferSkippedDuplicate', { name: fileName }))
          continue
        }
        pendingDestNames.add(destFileName)

        while (runningTransfers.value >= concurrencyLimit) {
          await new Promise((resolve) => setTimeout(resolve, 100))
        }

        runningTransfers.value++

        let taskId = null
        if (transferQueueRef.value) {
          taskId = transferQueueRef.value.addTask({
            name: destFileName,
            sourceHost: side === 'left' ? leftHostName.value : rightHostName.value,
            destHost: destHostName,
            percent: 0,
            status: 'active',
            speed: '',
            total: fileRecord?.size || 0,
            isDir: fileRecord?.is_dir || false,
          })
        }

        const promise = runTransfer({
          sourceHostId,
          destHostId,
          sourcePath: fullPath,
          destPath,
          displayName: fileName,
          destFileName,
          destHostName,
          side,
          data: { name: fileName },
          taskId,
        })
          .then(() => {
            if (destBrowser) {
              destBrowser.refresh()
            }
          })
          .catch((error) => {
            console.error(`Bulk transfer [${fileName}] error:`, error)
            if (transferQueueRef.value && taskId) {
              transferQueueRef.value.updateTask(taskId, { status: 'error' })
            }
            message.error(error.message || t('sftp.transferFailed'))
          })
          .finally(() => {
            runningTransfers.value--
          })

        transferPromises.push(promise)
      }

      // 清空选择
      if (side === 'left') {
        leftSelectedKeys.value = []
      } else {
        rightSelectedKeys.value = []
      }
      
      // 等待所有传输完成
      await Promise.all(transferPromises)
    }
  })
}

const handleSelectionChange = (side, keys) => {
  if (side === 'left') {
    leftSelectedKeys.value = keys
  } else {
    rightSelectedKeys.value = keys
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

.header-content {
  display: flex;
  gap: 8px;
  align-items: center;
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
