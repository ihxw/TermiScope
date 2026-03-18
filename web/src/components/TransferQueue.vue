<template>
  <div class="transfer-queue-panel">
    <div class="panel-header">
      <h3>{{ t('sftp.transferQueue') }}</h3>
      <a-space>
        <a-button size="small" @click="clearCompleted">
          {{ t('sftp.clearCompleted') }}
        </a-button>
        <a-button size="small" @click="togglePanel">
          <template #icon><CloseOutlined /></template>
        </a-button>
      </a-space>
    </div>
    
    <div class="panel-body">
      <div v-if="tasks.length === 0" class="empty-tip">
        <p>{{ t('sftp.transferQueue') }}为空</p>
      </div>
      
      <div v-else class="task-list">
        <div v-for="task in tasks" :key="task.id" class="task-item">
          <div class="task-info">
            <div class="task-name">{{ task.name }}</div>
            <div class="task-meta">
              <span>{{ task.sourceHost }} → {{ task.destHost }}</span>
              <span v-if="task.speed" class="task-speed">{{ task.speed }}</span>
            </div>
          </div>
          
          <div class="task-progress">
            <a-progress 
              :percent="task.percent" 
              :status="task.status"
              :strokeColor="getProgressColor(task.status)"
            />
          </div>
          
          <div class="task-actions">
            <a-space size="small">
              <a-button 
                v-if="task.status === 'active'" 
                size="small" 
                type="text" 
                @click="pauseTask(task.id)"
              >
                {{ t('sftp.pause') }}
              </a-button>
              <a-button 
                v-if="task.status === 'paused'" 
                size="small" 
                type="text" 
                @click="resumeTask(task.id)"
              >
                {{ t('sftp.resume') }}
              </a-button>
              <a-button 
                v-if="task.status === 'error'" 
                size="small" 
                type="text" 
                @click="retryTask(task.id)"
              >
                {{ t('sftp.retry') }}
              </a-button>
              <a-button 
                size="small" 
                type="text" 
                danger
                @click="cancelTask(task.id)"
              >
                {{ t('sftp.cancel') }}
              </a-button>
            </a-space>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { CloseOutlined } from '@ant-design/icons-vue'

const { t } = useI18n()

const props = defineProps({
  visible: {
    type: Boolean,
    default: true
  }
})

const emit = defineEmits(['close', 'pause', 'resume', 'cancel', 'retry'])

// 模拟任务数据 - 实际应该从父组件传入
const tasks = ref([
  // {
  //   id: '1',
  //   name: 'test.txt',
  //   sourceHost: 'Server A',
  //   destHost: 'Server B',
  //   percent: 45,
  //   status: 'active', // active, paused, success, error
  //   speed: '1.2 MB/s'
  // }
])

const getProgressColor = (status) => {
  switch(status) {
    case 'success': return '#52c41a'
    case 'error': return '#ff4d4f'
    case 'paused': return '#faad14'
    default: return '#1890ff'
  }
}

const clearCompleted = () => {
  tasks.value = tasks.value.filter(t => t.status === 'active' || t.status === 'paused')
}

const togglePanel = () => {
  emit('close')
}

const pauseTask = (taskId) => {
  emit('pause', taskId)
}

const resumeTask = (taskId) => {
  emit('resume', taskId)
}

const cancelTask = (taskId) => {
  emit('cancel', taskId)
}

const retryTask = (taskId) => {
  emit('retry', taskId)
}

// 暴露方法给父组件
defineExpose({
  addTask: (task) => {
    tasks.value.push({
      ...task,
      id: `task-${Date.now()}-${Math.random()}`,
      status: 'active'
    })
  },
  updateTask: (taskId, updates) => {
    const task = tasks.value.find(t => t.id === taskId)
    if (task) {
      Object.assign(task, updates)
    }
  },
  removeTask: (taskId) => {
    tasks.value = tasks.value.filter(t => t.id !== taskId)
  }
})
</script>

<style scoped>
.transfer-queue-panel {
  position: fixed;
  bottom: 20px;
  right: 20px;
  width: 400px;
  max-height: 500px;
  background: white;
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  display: flex;
  flex-direction: column;
  z-index: 1000;
}

.dark-theme .transfer-queue-panel {
  background: #1f1f1f;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
}

.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px 16px;
  border-bottom: 1px solid #f0f0f0;
  border-radius: 8px 8px 0 0;
}

.dark-theme .panel-header {
  border-color: #303030;
}

.panel-header h3 {
  margin: 0;
  font-size: 14px;
  font-weight: 500;
}

.panel-body {
  flex: 1;
  overflow-y: auto;
  padding: 12px 16px;
}

.empty-tip {
  text-align: center;
  padding: 40px 20px;
  color: #8c8c8c;
}

.task-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.task-item {
  padding: 12px;
  border: 1px solid #f0f0f0;
  border-radius: 6px;
  background: #fafafa;
}

.dark-theme .task-item {
  border-color: #303030;
  background: #141414;
}

.task-info {
  margin-bottom: 8px;
}

.task-name {
  font-size: 13px;
  font-weight: 500;
  margin-bottom: 4px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.task-meta {
  display: flex;
  justify-content: space-between;
  font-size: 12px;
  color: #8c8c8c;
}

.task-speed {
  color: #1890ff;
  font-weight: 500;
}

.task-progress {
  margin-bottom: 8px;
}

.task-actions {
  text-align: right;
}
</style>
