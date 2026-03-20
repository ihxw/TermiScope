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

    <!-- Transfer Queue Panel -->
    <TransferQueue 
      v-if="showQueuePanel" 
      ref="transferQueueRef"
      @close="showQueuePanel = false"
    />
  </div>
</template>

<script setup>
import { ref, computed, onMounted, h, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import { notification, Progress, Spin, Modal } from 'ant-design-vue'
import { SwapOutlined } from '@ant-design/icons-vue'
import SftpBrowser from '../components/SftpBrowser.vue'
import TransferQueue from '../components/TransferQueue.vue'
import { getHosts } from '../api/ssh'
import { transferFile } from '../api/sftp'

const { t } = useI18n()

const hosts = ref([])
const leftHostId = ref(null)
const rightHostId = ref(null)
const leftBrowserRef = ref(null)
const rightBrowserRef = ref(null)
const leftSelectedKeys = ref([])
const rightSelectedKeys = ref([])
const showQueuePanel = ref(false)
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

  // ✅ 确保队列面板打开
  if (!showQueuePanel.value) {
    showQueuePanel.value = true
    // 延迟一小段时间确保TransferQueue已挂载
    await nextTick()
  }
  
  // Add to queue with initial state and get taskId
  let taskId = null
  if (transferQueueRef.value) {
    taskId = transferQueueRef.value.addTask({
      name: data.name,
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
    // ✅ 立即更新进度为0，让任务立即可见
    if (transferQueueRef.value && taskId) {
      transferQueueRef.value.updateTask(taskId, {
        percent: 0,
        speed: ''
      })
    }
    await transferFile(sourceHostId, destHostId, data.fullPath, destPath, (event) => {
      console.log('💾 Transfer event:', event)
      
      if (event.type === 'start') {
        if (transferQueueRef.value && taskId) {
          transferQueueRef.value.updateTask(taskId, {
            total: event.total_size || 0,
            isDir: event.is_dir
          })
        }
      } else if (event.type === 'progress') {
        if (transferQueueRef.value && taskId) {
          transferQueueRef.value.updateTask(taskId, {
            percent: event.percent || 0,
            speed: event.speed || '',
            transferred: event.transferred,
            total: event.total
          })
        }
      } else if (event.type === 'info') {
        console.log('ℹ️ Transfer info:', event.message)
      }
    }, 'copy')

    if (transferQueueRef.value && taskId) {
      transferQueueRef.value.updateTask(taskId, {
        status: 'success',
        percent: 100
      })
    }

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
    console.error('Transfer error:', error)
    
    if (transferQueueRef.value) {
      transferQueueRef.value.updateTask(taskId, {
        status: 'error'
      })
    }
    
    notification.error({
      key,
      message: t('sftp.transferFailed'),
      description: error.message || t('sftp.transferFailed'),
      duration: 4.5,
      placement: 'bottomRight'
    })
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
      // 显示队列面板
      if (!showQueuePanel.value) {
        showQueuePanel.value = true
        await nextTick()
      }
      const destPath = destBrowser?.currentPath || '.'

      // 并发控制：最多同时传输 3 个文件
      const concurrencyLimit = 3
      const runningTransfers = ref(0)
      const transferPromises = []

      for (const key of selectedKeys) {
        const fileName = key.split('/').pop()
        const fullPath = key
        const fileRecord = sourceBrowser?.files?.find(f => f.name === fileName)

        // 等待有可用槽位
        while (runningTransfers.value >= concurrencyLimit) {
          await new Promise(resolve => setTimeout(resolve, 100))
        }

        runningTransfers.value++
        
        // 在队列中添加任务并获取 taskId
        let taskId = null
        if (transferQueueRef.value) {
          taskId = transferQueueRef.value.addTask({
            name: fileName,
            sourceHost: side === 'left' ? leftHostName.value : rightHostName.value,
            destHost: destHostName,
            percent: 0,
            status: 'active',
            speed: '',
            total: fileRecord?.size || 0,
            isDir: fileRecord?.is_dir || false
          })
        }

        // 启动传输
        const promise = transferFile(sourceHostId, destHostId, fullPath, destPath, (event) => {
          console.log(`📦 Bulk [${fileName}] event:`, event)
          
          if (event.type === 'start') {
            if (transferQueueRef.value && taskId) {
              transferQueueRef.value.updateTask(taskId, {
                total: event.total_size || 0,
                isDir: event.is_dir
              })
            }
          } else if (event.type === 'progress') {
            if (transferQueueRef.value && taskId) {
              transferQueueRef.value.updateTask(taskId, {
                percent: event.percent || 0,
                speed: event.speed || '',
                transferred: event.transferred,
                total: event.total
              })
            }
          }
        }, 'copy')
          .then(() => {
            if (transferQueueRef.value && taskId) {
              transferQueueRef.value.updateTask(taskId, {
                status: 'success',
                percent: 100
              })
            }
            if (destBrowser) {
              destBrowser.refresh()
            }
            notification.success({
              message: t('sftp.transferComplete'),
              description: t('sftp.transferSuccess', { name: fileName }),
              duration: 2,
              placement: 'bottomRight'
            })
          })
          .catch((error) => {
            console.error(`Bulk transfer [${fileName}] error:`, error)
            if (transferQueueRef.value && taskId) {
              transferQueueRef.value.updateTask(taskId, {
                status: 'error'
              })
            }
            notification.error({
              message: t('sftp.transferFailed'),
              description: error.message || t('sftp.transferFailed'),
              duration: 3,
              placement: 'bottomRight'
            })
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
