<template>
  <Teleport to="body">
    <div
      v-if="tasks.length"
      class="upload-progress-dock"
      :class="{ 'upload-progress-dock--dark': isDark }"
      :style="{ '--upload-ring-size': `${ringSize}px` }"
    >
      <div v-if="expanded" class="upload-panel upload-panel-list">
        <div class="upload-panel-header">
          <span class="upload-panel-title">{{ panelTitle }}</span>
          <a-button type="link" size="small" class="upload-hide-btn" @click="$emit('hide-panel')">
            {{ t('common.hide') }}
          </a-button>
        </div>
        <div class="upload-task-list" :class="{ 'is-scrollable': tasks.length > 3 }">
          <div v-for="(groupTasks, hostName) in groupedTasks" :key="hostName" class="upload-host-group">
            <div class="upload-host-group-header">
              <span class="upload-host-group-title">
                <span class="upload-host-icon">📡</span>{{ hostName }}
              </span>
              <a-button
                v-if="hasUploadingInGroup(groupTasks)"
                type="link"
                size="small"
                danger
                class="upload-cancel-group-btn"
                @click="cancelGroup(groupTasks)"
              >
                {{ t('sftp.cancelAll') }}
              </a-button>
            </div>
            <div class="upload-host-group-tasks">
              <div v-for="task in groupTasks" :key="task.key" class="upload-task-item">
                <div class="upload-task-item-head">
                  <span class="upload-file-name" :title="task.fileName">{{ task.fileName }}</span>
                  <span class="upload-task-item-right">
                    <span v-if="task.speed && task.status === 'uploading'" class="upload-speed">{{ task.speed }}</span>
                    <a-button
                      v-if="task.status === 'uploading' || task.status === 'connecting'"
                      type="link"
                      size="small"
                      danger
                      class="upload-cancel-link"
                      @click="$emit('cancel', task.key)"
                    >
                      {{ t('common.cancel') }}
                    </a-button>
                  </span>
                </div>
                <div v-if="task.status === 'connecting'" class="upload-panel-connecting">
                  <a-spin size="small" />
                  <span>{{ t('terminal.connecting') }}</span>
                </div>
                <div v-else-if="task.status === 'done'" class="upload-panel-done">{{ t('sftp.uploadComplete') }}</div>
                <a-progress
                  v-else
                  :percent="task.percent"
                  :status="progressStatus(task)"
                  size="small"
                  :show-info="false"
                />
                <div v-if="task.errorMessage" class="upload-panel-error">{{ task.errorMessage }}</div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <a-tooltip v-else :title="circleTooltip" placement="left">
        <button
          type="button"
          class="upload-circle-btn"
          :aria-label="t('sftp.uploadProgress')"
          @click="$emit('show-panel')"
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
            <span
              v-if="aggregate.connecting && aggregate.percent === 0"
              class="upload-circle-center upload-circle-icon"
            >
              <LoadingOutlined />
            </span>
            <span v-else class="upload-circle-center upload-circle-percent">
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
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { LoadingOutlined } from '@ant-design/icons-vue'

const props = defineProps({
  tasks: { type: Array, default: () => [] },
  expanded: { type: Boolean, default: false },
  panelTitle: { type: String, default: '' },
  circleTooltip: { type: String, default: '' },
  aggregate: { type: Object, default: () => ({ percent: 0, connecting: false }) },
  aggregateStatus: { type: String, default: 'active' },
  ringSize: { type: Number, default: 48 },
  ringRadius: { type: Number, default: 22 },
  ringCenter: { type: Number, default: 24 },
  ringCircumference: { type: Number, default: 0 },
  ringDashOffset: { type: Number, default: 0 },
  isDark: { type: Boolean, default: false },
})

const emit = defineEmits(['hide-panel', 'show-panel', 'cancel'])

const { t } = useI18n()

const groupedTasks = computed(() => {
  const groups = {}
  for (const task of props.tasks) {
    const hostKey = task.hostLabel || t('sftp.unknownHost') || 'Unknown Server'
    if (!groups[hostKey]) {
      groups[hostKey] = []
    }
    groups[hostKey].push(task)
  }
  return groups
})

const hasUploadingInGroup = (groupTasks) => {
  return groupTasks.some((t) => t.status === 'uploading' || t.status === 'connecting')
}

const cancelGroup = (groupTasks) => {
  for (const task of groupTasks) {
    if (task.status === 'uploading' || task.status === 'connecting') {
      emit('cancel', task.key)
    }
  }
}

const progressStatus = (task) => {
  if (task.status === 'done') return 'success'
  if (task.status === 'error' || task.status === 'cancelled') return 'exception'
  return 'active'
}
</script>

<style scoped>
.upload-task-item :deep(.ant-progress-line) {
  margin-bottom: 0;
  line-height: 0;
}

.upload-cancel-link {
  height: auto;
  padding: 0 4px;
  font-size: 12px;
  line-height: 1.2;
}
</style>
