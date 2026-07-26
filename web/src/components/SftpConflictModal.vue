<template>
  <a-modal
    :open="open"
    :title="t('sftp.uploadConflictTitle')"
    :footer="null"
    :mask-closable="false"
    width="400px"
    :wrap-class-name="wrapClass"
    @cancel="$emit('cancel')"
    @update:open="$emit('update:open', $event)"
  >
    <div
      class="upload-conflict-body"
      :class="{ 'upload-conflict-body--dark': isDark }"
    >
      <p class="upload-conflict-text">{{ t('sftp.uploadConflictContent', { name }) }}</p>
      <p v-if="isDir" class="upload-conflict-hint">{{ t('sftp.uploadConflictDirHint') }}</p>
      <a-checkbox
        v-if="showApplyToAll"
        :checked="applyToAll"
        class="upload-conflict-apply-all"
        @change="$emit('update:applyToAll', $event.target.checked)"
      >
        {{ t('sftp.conflictApplyToAll') }}
      </a-checkbox>
      <div class="upload-conflict-actions">
        <a-button @click="$emit('cancel')">{{ t('common.cancel') }}</a-button>
        <a-button @click="$emit('keepBoth')">{{ t('sftp.uploadKeepBoth') }}</a-button>
        <a-button type="primary" :disabled="isDir" @click="$emit('overwrite')">
          {{ t('sftp.uploadOverwrite') }}
        </a-button>
      </div>
    </div>
  </a-modal>
</template>

<script setup>
import { useI18n } from 'vue-i18n'

defineProps({
  open: { type: Boolean, default: false },
  name: { type: String, default: '' },
  isDir: { type: Boolean, default: false },
  showApplyToAll: { type: Boolean, default: false },
  applyToAll: { type: Boolean, default: false },
  wrapClass: { type: String, default: '' },
  isDark: { type: Boolean, default: false },
})

defineEmits(['update:open', 'update:applyToAll', 'cancel', 'overwrite', 'keepBoth'])

const { t } = useI18n()
</script>

<style scoped>
.upload-conflict-body {
  --upload-conflict-text: rgba(0, 0, 0, 0.88);
  --upload-conflict-hint: #d48806;
}

.upload-conflict-body--dark {
  --upload-conflict-text: rgba(255, 255, 255, 0.85);
  --upload-conflict-hint: #faad14;
}

.upload-conflict-text {
  margin: 0 0 8px;
  color: var(--upload-conflict-text);
  word-break: break-all;
}

.upload-conflict-hint {
  margin: 0 0 12px;
  font-size: 12px;
  color: var(--upload-conflict-hint);
}

.upload-conflict-apply-all {
  display: block;
  margin: 0 0 16px;
}

.upload-conflict-actions {
  display: flex;
  justify-content: flex-end;
  flex-wrap: wrap;
  gap: 8px;
}
</style>

<style>
.upload-conflict-modal-wrap--dark .ant-modal-content {
  background-color: #1f1f1f;
  color: rgba(255, 255, 255, 0.85);
}

.upload-conflict-modal-wrap--dark .ant-modal-header {
  background-color: #1f1f1f;
  border-bottom: 1px solid #303030;
}

.upload-conflict-modal-wrap--dark .ant-modal-title {
  color: rgba(255, 255, 255, 0.85);
}

.upload-conflict-modal-wrap--dark .ant-modal-close {
  color: rgba(255, 255, 255, 0.45);
}

.upload-conflict-modal-wrap--dark .ant-modal-close:hover {
  color: rgba(255, 255, 255, 0.85);
}
</style>
