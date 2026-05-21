<template>
  <Teleport to="body">
    <div
      v-if="tasks.length"
      class="upload-progress-dock"
      :class="{ 'upload-progress-dock--dark': themeStore.isDark }"
      :style="{ '--upload-ring-size': `${ringSize}px` }"
    >
      <div v-if="panelExpanded" class="upload-panel upload-panel-list">
        <div class="upload-panel-header">
          <span class="upload-panel-title">{{ panelTitle }}</span>
          <a-button type="link" size="small" class="upload-hide-btn" @click="hidePanel">
            {{ t('common.hide') }}
          </a-button>
        </div>
        <div class="upload-task-list" :class="{ 'is-scrollable': tasks.length > 3 }">
          <div v-for="task in tasks" :key="task.id" class="upload-task-item">
            <div class="upload-task-item-head">
              <span class="upload-file-name" :title="task.name">{{ task.name }}</span>
              <span class="upload-task-item-right">
                <span v-if="task.speed && isRunning(task)" class="upload-speed">{{ task.speed }}</span>
              </span>
            </div>
            <div v-if="task.sourceHost && task.destHost" class="upload-task-subtitle">
              {{ task.sourceHost }} → {{ task.destHost }}
            </div>
            <div v-if="task.status === 'success'" class="upload-panel-done">{{ t('sftp.transferComplete') }}</div>
            <div v-else-if="task.status === 'error'" class="upload-panel-error">{{ t('sftp.transferFailed') }}</div>
            <div v-else-if="task.status === 'paused'" class="upload-panel-paused">{{ t('sftp.paused') }}</div>
            <a-progress
              v-else
              :percent="task.percent || 0"
              :status="progressBarStatus(task)"
              size="small"
              :show-info="false"
            />
            <div v-if="task.written > 0 && task.total > 0" class="upload-panel-bytes">
              {{ formatSize(task.written) }} / {{ formatSize(task.total) }}
            </div>
            <div v-else-if="task.eta && isRunning(task)" class="upload-panel-bytes">{{ task.eta }}</div>
          </div>
        </div>
      </div>

      <a-tooltip v-else :title="circleTooltip" placement="left">
        <button
          type="button"
          class="upload-circle-btn"
          :aria-label="t('sftp.uploadProgress')"
          @click="showPanel"
        >
          <span class="upload-ring-wrap">
            <svg
              class="upload-ring-svg"
              :width="ringSize"
              :height="ringSize"
              :viewBox="`0 0 ${ringSize} ${ringSize}`"
              aria-hidden="true"
            >
              <circle
                class="upload-ring-track"
                :cx="ringCenter"
                :cy="ringCenter"
                :r="ringRadius"
                fill="none"
                stroke-width="3"
              />
              <circle
                class="upload-ring-progress"
                :class="`is-${aggregateStatus}`"
                :cx="ringCenter"
                :cy="ringCenter"
                :r="ringRadius"
                fill="none"
                stroke-width="3"
                stroke-linecap="round"
                :stroke-dasharray="ringCircumference"
                :stroke-dashoffset="ringDashOffset"
                :transform="`rotate(-90 ${ringCenter} ${ringCenter})`"
              />
            </svg>
            <span class="upload-circle-center upload-circle-percent">
              {{ aggregate.percent }}<span class="upload-circle-percent-suffix">%</span>
            </span>
          </span>
          <span v-if="tasks.length > 1" class="upload-circle-badge">{{ tasks.length }}</span>
        </button>
      </a-tooltip>
    </div>
  </Teleport>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useThemeStore } from '../stores/theme'
import '../styles/sftp-progress-dock.css'

const { t } = useI18n()
const themeStore = useThemeStore()

const tasks = ref([])
const panelExpanded = ref(false)
const dismissTimers = new Map()

const controlSize = computed(() => themeStore.themeToken.controlHeightSM || 24)
const ringSize = computed(() => controlSize.value * 2)
const ringRadius = computed(() => ringSize.value / 2 - 2)
const ringCenter = computed(() => ringSize.value / 2)
const ringCircumference = computed(() => 2 * Math.PI * ringRadius.value)

const isRunning = (task) => task.status === 'active' || task.status === 'paused'

const formatSize = (bytes) => {
  if (!bytes || bytes <= 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return `${parseFloat((bytes / k ** i).toFixed(2))} ${sizes[i]}`
}

const aggregate = computed(() => {
  let written = 0
  let total = 0
  let fallbackPercentSum = 0
  let fallbackCount = 0

  for (const task of tasks.value) {
    const taskTotal = task.total || 0
    if (taskTotal > 0) {
      if (task.status === 'success') {
        written += taskTotal
        total += taskTotal
      } else {
        written += task.transferred ?? Math.round((task.percent || 0) * taskTotal / 100)
        total += taskTotal
      }
    } else if (isRunning(task) && (task.percent || 0) > 0) {
      fallbackPercentSum += task.percent
      fallbackCount += 1
    }
  }

  let percent = 0
  if (total > 0) {
    percent = Math.min(100, Math.round((written * 100) / total))
  } else if (fallbackCount > 0) {
    percent = Math.min(99, Math.round(fallbackPercentSum / fallbackCount))
  }

  const hasActive = tasks.value.some((task) => task.status === 'active')
  if (hasActive && percent >= 100) {
    percent = 99
  }

  return { written, total, percent }
})

const aggregateStatus = computed(() => {
  if (tasks.value.some((task) => task.status === 'error')) {
    return 'exception'
  }
  if (tasks.value.length && tasks.value.every((task) => task.status === 'success')) {
    return 'success'
  }
  return 'active'
})

const ringDashOffset = computed(() => {
  const pct = Math.min(100, Math.max(0, aggregate.value.percent))
  return ringCircumference.value * (1 - pct / 100)
})

const panelTitle = computed(() => {
  const count = tasks.value.length
  if (count <= 1) {
    return tasks.value[0]?.name
      ? `${t('sftp.transferring')}: ${tasks.value[0].name}`
      : t('sftp.transferring')
  }
  return t('sftp.transferringCount', { count })
})

const circleTooltip = computed(() => {
  const { percent, written, total } = aggregate.value
  if (written > 0 && total > 0) {
    return `${percent}% · ${formatSize(written)} / ${formatSize(total)}`
  }
  return t('sftp.expandUploadDetail')
})

const showPanel = () => {
  panelExpanded.value = true
}

const hidePanel = () => {
  panelExpanded.value = false
}

const progressBarStatus = (task) => {
  if (task.status === 'success') return 'success'
  if (task.status === 'error') return 'exception'
  return 'active'
}

const calculateETA = (task) => {
  if (!isRunning(task) || task.status !== 'active' || !task.speed || task.percent >= 100 || !task.total) {
    return null
  }

  let bytesPerSec = 0
  const speedMatch = task.speed.match(/([\d,.]+)\s*([KMGT]?B)\/s/i)
  if (speedMatch) {
    const value = parseFloat(speedMatch[1].replace(',', ''))
    const unit = speedMatch[2].toUpperCase()
    const mult = { B: 1, KB: 1024, MB: 1024 ** 2, GB: 1024 ** 3, TB: 1024 ** 4 }
    bytesPerSec = value * (mult[unit] || 1)
  }

  if (bytesPerSec <= 0) return null

  const remainingBytes = task.total - (task.transferred ?? (task.total * task.percent) / 100)
  const remainingSeconds = remainingBytes / bytesPerSec
  if (remainingSeconds <= 0) return null

  if (remainingSeconds < 60) {
    return t('sftp.etaSeconds', { seconds: Math.round(remainingSeconds) })
  }
  if (remainingSeconds < 3600) {
    return t('sftp.etaMinutes', { minutes: Math.round(remainingSeconds / 60) })
  }
  return t('sftp.etaHours', { hours: Math.round(remainingSeconds / 3600) })
}

const scheduleDismiss = (taskId, delayMs = 3000) => {
  const existing = dismissTimers.get(taskId)
  if (existing) clearTimeout(existing)
  const timer = setTimeout(() => {
    tasks.value = tasks.value.filter((t) => t.id !== taskId)
    dismissTimers.delete(taskId)
    if (!tasks.value.length) {
      panelExpanded.value = false
    }
  }, delayMs)
  dismissTimers.set(taskId, timer)
}

defineExpose({
  addTask: (task) => {
    const taskId = task.id || `transfer-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
    panelExpanded.value = true
    tasks.value.push({
      ...task,
      id: taskId,
      status: task.status || 'active',
      percent: task.percent ?? 0,
      transferred: task.transferred ?? 0,
      total: task.total || 0,
      speed: task.speed || '',
      createdAt: Date.now(),
    })
    return taskId
  },
  updateTask: (taskId, updates) => {
    const task = tasks.value.find((t) => t.id === taskId)
    if (!task) return

    Object.assign(task, updates)

    if (task.transferred !== undefined) {
      task.written = task.transferred
    } else if (task.total > 0 && task.percent !== undefined) {
      task.written = Math.round((task.percent * task.total) / 100)
    }

    if ((updates.speed !== undefined || updates.percent !== undefined) && task.status === 'active') {
      task.eta = task.percent >= 100 ? null : calculateETA(task)
    }

    if (updates.status === 'success') {
      task.percent = 100
      scheduleDismiss(taskId)
    } else if (updates.status === 'error') {
      scheduleDismiss(taskId, 5000)
    }
  },
  removeTask: (taskId) => {
    const timer = dismissTimers.get(taskId)
    if (timer) clearTimeout(timer)
    dismissTimers.delete(taskId)
    tasks.value = tasks.value.filter((t) => t.id !== taskId)
    if (!tasks.value.length) {
      panelExpanded.value = false
    }
  },
  getTasks: () => tasks.value,
})
</script>
