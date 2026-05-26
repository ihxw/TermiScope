<template>
  <div class="browser-header">
    <a-button-group size="small" class="nav-actions">
      <a-tooltip :title="t('sftp.navBack')">
        <a-button :disabled="!canGoBack" @click="$emit('back')">
          <template #icon><LeftOutlined /></template>
        </a-button>
      </a-tooltip>
      <a-tooltip :title="t('sftp.navForward')">
        <a-button :disabled="!canGoForward" @click="$emit('forward')">
          <template #icon><RightOutlined /></template>
        </a-button>
      </a-tooltip>
      <a-tooltip :title="t('sftp.navUp')">
        <a-button :disabled="!canGoUp" @click="$emit('up')">
          <template #icon><ArrowUpOutlined /></template>
        </a-button>
      </a-tooltip>
      <a-tooltip :title="t('common.refresh')">
        <a-button :disabled="loading" @click="$emit('refresh')">
          <template #icon><ReloadOutlined /></template>
        </a-button>
      </a-tooltip>
    </a-button-group>
    <div class="header-actions">
      <a-button size="small" :disabled="!clipboardCount" @click="$emit('paste')">
        <template #icon><SnippetsOutlined /></template>
        {{ t('sftp.paste') }}
      </a-button>
      <a-button-group size="small">
        <a-button :disabled="!selectedCount" @click="$emit('bulk-cut')">
          <template #icon><ScissorOutlined /></template>
          {{ t('sftp.cut') }}
        </a-button>
        <a-button :disabled="!selectedCount" @click="$emit('bulk-copy')">
          <template #icon><CopyOutlined /></template>
          {{ t('sftp.copy') }}
        </a-button>
      </a-button-group>
      <a-dropdown>
        <a-button size="small">
          <template #icon><PlusOutlined /></template>
          {{ t('sftp.new') }}
        </a-button>
        <template #overlay>
          <a-menu>
            <a-menu-item key="file" @click="$emit('open-create', 'file')">
              <FileAddOutlined /> {{ t('sftp.newFile') }}
            </a-menu-item>
            <a-menu-item key="folder" @click="$emit('open-create', 'folder')">
              <FolderAddOutlined /> {{ t('sftp.newFolder') }}
            </a-menu-item>
          </a-menu>
        </template>
      </a-dropdown>
      <a-upload :custom-request="(opts) => $emit('upload', opts)" :show-upload-list="false" accept="*" multiple>
        <a-button size="small" type="primary">
          <template #icon><UploadOutlined /></template>
          {{ t('sftp.upload') }}
        </a-button>
      </a-upload>
      <a-dropdown v-if="selectedCount > 0">
        <a-button size="small">
          {{ t('sftp.selected', { count: selectedCount }) }}
          <DownOutlined />
        </a-button>
        <template #overlay>
          <a-menu>
            <a-menu-item key="select-all" @click="$emit('select-all')">
              <CheckSquareOutlined /> {{ t('sftp.selectAll') }}
            </a-menu-item>
            <a-menu-item key="invert-selection" @click="$emit('invert-selection')">
              <SwapOutlined /> {{ t('sftp.invertSelection') }}
            </a-menu-item>
            <a-menu-item key="clear-selection" @click="$emit('clear-selection')">
              <CloseOutlined /> {{ t('sftp.clearSelection') }}
            </a-menu-item>
            <a-menu-divider />
            <a-menu-item key="cut-selected" @click="$emit('bulk-cut')">
              <ScissorOutlined /> {{ t('sftp.cutSelected') }}
            </a-menu-item>
            <a-menu-item key="copy-selected" @click="$emit('bulk-copy')">
              <CopyOutlined /> {{ t('sftp.copySelected') }}
            </a-menu-item>
            <a-menu-item key="paste-selected" @click="$emit('paste')" :disabled="!clipboardCount">
              <SnippetsOutlined /> {{ t('sftp.paste') }}
            </a-menu-item>
            <a-menu-divider />
            <a-menu-item key="download-selected" @click="$emit('bulk-download')">
              <DownloadOutlined /> {{ t('sftp.downloadSelected') }}
            </a-menu-item>
            <a-menu-item key="delete-selected" @click="$emit('bulk-delete')" danger>
              <DeleteOutlined /> {{ t('sftp.deleteSelected') }}
            </a-menu-item>
            <a-menu-divider />
            <a-menu-item key="properties" @click="$emit('properties')">
              <InfoCircleOutlined /> {{ t('sftp.properties') }}
            </a-menu-item>
          </a-menu>
        </template>
      </a-dropdown>
    </div>
    <template v-if="!pathInputVisible">
      <div class="breadcrumb-container" @click="$emit('show-path-input')">
        <a-tooltip :title="t('sftp.goToPath')">
          <a-button size="small" type="text" class="path-toggle-btn" @click.stop="$emit('show-path-input')">
            <template #icon><EditOutlined /></template>
          </a-button>
        </a-tooltip>
        <a-breadcrumb separator=">" size="small" class="path-breadcrumb">
          <a-breadcrumb-item v-for="(part, index) in pathParts" :key="index">
            <a @click.stop="$emit('navigate', index)">{{ part || '/' }}</a>
          </a-breadcrumb-item>
        </a-breadcrumb>
      </div>
    </template>
    <div v-else class="path-input-wrapper" :class="{ 'path-input-wrapper--dark': isDark }">
      <div class="path-input-row">
        <a-auto-complete
          ref="pathInputRef"
          class="path-autocomplete"
          :popup-class-name="isDark ? 'sftp-path-autocomplete-dropdown sftp-path-autocomplete-dropdown--dark' : 'sftp-path-autocomplete-dropdown'"
          :value="pathInputValue"
          size="small"
          :options="pathAutocompleteOptions"
          :placeholder="t('sftp.pathPlaceholder')"
          :status="pathInputError ? 'error' : ''"
          :not-found-content="pathInputLoading ? t('sftp.pathLoading') : t('sftp.pathNoMatches')"
          :filter-option="false"
          :default-active-first-option="true"
          @update:value="$emit('update:pathInputValue', $event)"
          @search="$emit('path-search', $event)"
          @select="$emit('path-select', $event)"
          @keydown.enter.prevent="$emit('path-enter')"
          @keydown.esc="$emit('path-esc')"
          @blur="(e) => $emit('path-blur', e)"
        >
          <template #option="{ value, label, hint }">
            <div class="path-option">
              <span class="path-option-value">{{ label || value }}</span>
              <span v-if="hint" class="path-option-hint">{{ hint }}</span>
            </div>
          </template>
        </a-auto-complete>
        <a-tooltip :title="t('sftp.pathGo')">
          <a-button
            class="path-go-btn"
            size="small"
            type="primary"
            :loading="pathInputLoading"
            :disabled="!pathInputValue || !pathInputValue.trim()"
            @mousedown.prevent
            @click="$emit('path-enter')"
          >
            <template #icon><RightOutlined /></template>
          </a-button>
        </a-tooltip>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  LeftOutlined,
  RightOutlined,
  ArrowUpOutlined,
  ReloadOutlined,
  SnippetsOutlined,
  ScissorOutlined,
  CopyOutlined,
  PlusOutlined,
  FileAddOutlined,
  FolderAddOutlined,
  UploadOutlined,
  DownOutlined,
  CheckSquareOutlined,
  SwapOutlined,
  CloseOutlined,
  DownloadOutlined,
  DeleteOutlined,
  InfoCircleOutlined,
  EditOutlined,
} from '@ant-design/icons-vue'

defineProps({
  canGoBack: Boolean,
  canGoForward: Boolean,
  canGoUp: Boolean,
  loading: Boolean,
  clipboardCount: { type: Number, default: 0 },
  selectedCount: { type: Number, default: 0 },
  pathInputVisible: Boolean,
  pathParts: { type: Array, default: () => [] },
  pathInputValue: String,
  pathAutocompleteOptions: { type: Array, default: () => [] },
  pathInputLoading: Boolean,
  pathInputError: { type: String, default: '' },
  isDark: Boolean,
})

defineEmits([
  'back',
  'forward',
  'up',
  'refresh',
  'paste',
  'bulk-cut',
  'bulk-copy',
  'open-create',
  'upload',
  'select-all',
  'invert-selection',
  'clear-selection',
  'bulk-download',
  'bulk-delete',
  'properties',
  'show-path-input',
  'navigate',
  'update:pathInputValue',
  'path-search',
  'path-select',
  'path-enter',
  'path-esc',
  'path-blur',
])

const { t } = useI18n()
const pathInputRef = ref(null)
defineExpose({ pathInputRef })
</script>

<style scoped>
.browser-header {
  display: flex;
  justify-content: flex-start;
  align-items: center;
  margin-bottom: 8px;
  padding: 4px 0;
  gap: 8px;
  flex-wrap: wrap;
}

.nav-actions {
  flex-shrink: 0;
}

.header-actions {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
  flex-wrap: wrap;
}

.breadcrumb-container {
  flex: 1;
  min-width: 120px;
  display: flex;
  align-items: center;
  cursor: text;
  padding: 2px 8px;
  border-radius: 4px;
  transition: background 0.2s;
}

.breadcrumb-container:hover {
  background: rgba(0, 0, 0, 0.04);
}

.path-breadcrumb {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.path-toggle-btn {
  flex-shrink: 0;
  margin-right: 4px;
  height: 20px;
  padding: 0 4px;
}

.path-input-wrapper {
  flex: 1 1 0;
  min-width: 0;
}

.path-input-row {
  display: flex;
  align-items: center;
  gap: 4px;
  min-width: 0;
}

.path-autocomplete {
  width: 100%;
  min-width: 0;
}

.path-go-btn {
  flex-shrink: 0;
}

.path-input-wrapper :deep(.ant-select-selector) {
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
}

.path-option {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  min-width: 0;
}

.path-option-value {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
}

.path-option-hint {
  flex-shrink: 0;
  font-size: 12px;
  color: #8c8c8c;
}

.path-input-wrapper--dark :deep(.ant-select-selector) {
  background: #141414 !important;
  border-color: #434343 !important;
}

.path-input-wrapper--dark :deep(.ant-select-selection-search-input),
.path-input-wrapper--dark :deep(.ant-select-selection-item) {
  color: rgba(255, 255, 255, 0.92) !important;
}

.path-input-wrapper--dark :deep(.ant-select-selection-placeholder) {
  color: rgba(255, 255, 255, 0.45) !important;
}

.path-input-wrapper--dark .path-option-hint {
  color: rgba(255, 255, 255, 0.45);
}

.path-input-wrapper--dark :deep(.ant-select-focused .ant-select-selector),
.path-input-wrapper--dark :deep(.ant-select-selector:focus),
.path-input-wrapper--dark :deep(.ant-select-selector:active) {
  border-color: #4096ff !important;
  box-shadow: 0 0 0 2px rgba(24, 144, 255, 0.2) !important;
}

:global(.sftp-path-autocomplete-dropdown--dark) {
  background: #1f1f1f;
}

:global(.sftp-path-autocomplete-dropdown--dark .ant-select-item) {
  color: rgba(255, 255, 255, 0.88);
}

:global(.sftp-path-autocomplete-dropdown--dark .ant-select-item-option-active),
:global(.sftp-path-autocomplete-dropdown--dark .ant-select-item-option-selected) {
  background: rgba(64, 150, 255, 0.22);
}
</style>
