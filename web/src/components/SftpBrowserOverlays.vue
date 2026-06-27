<template>
  <a-modal :open="renameVisible" @update:open="$emit('update:renameVisible', $event)" :title="t('sftp.rename')" @ok="$emit('rename-ok')">
    <a-input :value="renameName" @update:value="$emit('update:renameName', $event)" :placeholder="t('sftp.newName')" />
  </a-modal>

  <a-modal
    :open="createVisible"
    @update:open="$emit('update:createVisible', $event)"
    :title="createType === 'folder' ? t('sftp.newFolder') : t('sftp.newFile')"
    @ok="$emit('create-ok')"
  >
    <a-input
      :value="createName"
      @update:value="$emit('update:createName', $event)"
      :placeholder="createType === 'folder' ? t('sftp.folderName') : t('sftp.fileName')"
    />
  </a-modal>

  <a-modal
    :open="uploadConflictOpen"
    @update:open="$emit('update:uploadConflictOpen', $event)"
    :title="t('sftp.uploadConflictTitle')"
    :footer="null"
    :mask-closable="false"
    width="400px"
    :wrap-class-name="uploadConflictWrapClass"
    @cancel="$emit('upload-conflict-cancel')"
  >
    <div class="upload-conflict-body" :class="{ 'upload-conflict-body--dark': isDark }">
      <p class="upload-conflict-text">{{ t('sftp.uploadConflictContent', { name: uploadConflictName }) }}</p>
      <p v-if="uploadConflictIsDir" class="upload-conflict-hint">{{ t('sftp.uploadConflictDirHint') }}</p>
      <div class="upload-conflict-actions">
        <a-button @click="$emit('upload-conflict-cancel')">{{ t('common.cancel') }}</a-button>
        <a-button @click="$emit('upload-conflict-keep-both')">{{ t('sftp.uploadKeepBoth') }}</a-button>
        <a-button type="primary" :disabled="uploadConflictIsDir" @click="$emit('upload-conflict-overwrite')">
          {{ t('sftp.uploadOverwrite') }}
        </a-button>
      </div>
    </div>
  </a-modal>

  <a-modal
    :open="previewVisible"
    @update:open="$emit('update:previewVisible', $event)"
    :title="previewName"
    :footer="null"
    width="800px"
    centered
    @cancel="$emit('preview-close')"
  >
    <div v-if="previewLoading" style="text-align: center; padding: 40px">
      <a-spin tip="Loading media..." />
    </div>
    <div
      v-else
      style="display: flex; justify-content: center; align-items: center; background: #000; min-height: 300px; border-radius: 4px; overflow: hidden;"
    >
      <video
        v-if="previewType === 'video'"
        :src="previewSrc"
        controls
        style="max-width: 100%; max-height: 70vh;"
        autoplay
      />
    </div>
  </a-modal>

  <div style="display: none;">
    <a-image
      :src="previewSrc"
      :preview="{
        visible: imagePreviewVisible,
        onVisibleChange: (vis) => $emit('image-preview-visible', vis),
      }"
    />
  </div>

  <div
    v-if="contextMenuVisible && contextMenuRecord"
    ref="contextMenuRef"
    class="sftp-context-menu"
    :style="{ left: contextMenuPosition.x + 'px', top: contextMenuPosition.y + 'px' }"
  >
    <a-menu @click="$emit('context-menu-close')">
      <template v-if="contextMenuRecord.is_container">
        <a-menu-item key="refresh" @click="$emit('refresh')">
          <ReloadOutlined /> {{ t('common.refresh') }}
        </a-menu-item>
        <a-menu-divider />
        <a-menu-item key="new-file" @click="$emit('open-create', 'file')">
          <FileAddOutlined /> {{ t('sftp.newFile') }}
        </a-menu-item>
        <a-menu-item key="new-folder" @click="$emit('open-create', 'folder')">
          <FolderAddOutlined /> {{ t('sftp.newFolder') }}
        </a-menu-item>
        <a-menu-divider />
        <a-menu-item key="paste" @click="$emit('paste')" :disabled="!clipboardCount">
          <SnippetsOutlined /> {{ t('sftp.paste') }}
        </a-menu-item>
      </template>
      <template v-else>
        <a-menu-item key="open" @click="$emit('context-open')">
          <FolderOpenOutlined v-if="contextMenuRecord.is_dir" />
          <EditOutlined v-else />
          {{ contextMenuRecord.is_dir ? t('sftp.openDir') || t('common.open') : t('sftp.edit') || t('common.edit') }}
        </a-menu-item>
        <a-menu-item key="download" @click="$emit('context-download', contextMenuRecord.name)">
          <DownloadOutlined /> {{ t('sftp.download') || t('common.download') }}
        </a-menu-item>
        <a-menu-item v-if="enableTransfer" key="transfer" @click="$emit('context-transfer', contextMenuRecord)">
          <SwapOutlined /> {{ t('sftp.sendTo', { name: transferTargetLabel }) }}
        </a-menu-item>
        <a-menu-divider />
        <a-menu-item key="cut" @click="$emit('context-cut', contextMenuRecord.name)">
          <ScissorOutlined /> {{ t('sftp.cut') }}
        </a-menu-item>
        <a-menu-item key="copy" @click="$emit('context-copy', contextMenuRecord.name)">
          <CopyOutlined /> {{ t('sftp.copy') }}
        </a-menu-item>
        <a-menu-item key="rename" @click="$emit('context-rename', contextMenuRecord)">
          <EditOutlined /> {{ t('sftp.rename') }}
        </a-menu-item>
        <a-menu-divider />
        <a-menu-item key="delete" @click="$emit('context-delete', contextMenuRecord.name)" danger>
          <DeleteOutlined /> {{ t('sftp.delete') || t('common.delete') }}
        </a-menu-item>
      </template>
    </a-menu>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  ReloadOutlined,
  FileAddOutlined,
  FolderAddOutlined,
  SnippetsOutlined,
  FolderOpenOutlined,
  EditOutlined,
  DownloadOutlined,
  SwapOutlined,
  ScissorOutlined,
  CopyOutlined,
  DeleteOutlined,
} from '@ant-design/icons-vue'

defineProps({
  renameVisible: Boolean,
  renameName: String,
  createVisible: Boolean,
  createName: String,
  createType: String,
  uploadConflictOpen: Boolean,
  uploadConflictName: String,
  uploadConflictIsDir: Boolean,
  uploadConflictWrapClass: String,
  previewVisible: Boolean,
  previewName: String,
  previewLoading: Boolean,
  previewType: String,
  previewSrc: String,
  imagePreviewVisible: Boolean,
  contextMenuVisible: Boolean,
  contextMenuRecord: Object,
  contextMenuPosition: { type: Object, default: () => ({ x: 0, y: 0 }) },
  clipboardCount: { type: Number, default: 0 },
  enableTransfer: Boolean,
  transferTargetLabel: String,
  isDark: Boolean,
})

defineEmits([
  'rename-ok',
  'update:renameVisible',
  'update:renameName',
  'create-ok',
  'update:createVisible',
  'update:createName',
  'update:uploadConflictOpen',
  'update:previewVisible',
  'upload-conflict-cancel',
  'upload-conflict-keep-both',
  'upload-conflict-overwrite',
  'preview-close',
  'image-preview-visible',
  'context-menu-close',
  'refresh',
  'open-create',
  'paste',
  'context-open',
  'context-download',
  'context-transfer',
  'context-cut',
  'context-copy',
  'context-rename',
  'context-delete',
])

const { t } = useI18n()
const contextMenuRef = ref(null)
defineExpose({ contextMenuRef })
</script>

<style scoped>
.sftp-context-menu {
  position: fixed;
  z-index: 9999;
  background: #fff;
  border-radius: 8px;
  box-shadow: 0 6px 16px 0 rgba(0, 0, 0, 0.08), 0 3px 6px -4px rgba(0, 0, 0, 0.12),
    0 9px 28px 8px rgba(0, 0, 0, 0.05);
  overflow: hidden;
  min-width: 160px;
}

.sftp-context-menu :deep(.ant-menu) {
  border-inline-end: none !important;
  box-shadow: none;
  border-radius: 8px;
}

.sftp-context-menu :deep(.ant-menu-item) {
  margin: 2px 4px;
  border-radius: 4px;
  height: 32px;
  line-height: 32px;
}

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
