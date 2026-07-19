<template>
  <div class="browser-header">
    <div class="toolbar-row toolbar-main">
      <a-button-group size="small" class="nav-actions">
        <a-tooltip :title="t('sftp.navBack')">
          <a-button :aria-label="t('sftp.navBack')" :disabled="!canGoBack" @click="$emit('back')">
            <template #icon><LeftOutlined /></template>
          </a-button>
        </a-tooltip>
        <a-tooltip :title="t('sftp.navForward')">
          <a-button :aria-label="t('sftp.navForward')" :disabled="!canGoForward" @click="$emit('forward')">
            <template #icon><RightOutlined /></template>
          </a-button>
        </a-tooltip>
        <a-tooltip :title="t('sftp.navUp')">
          <a-button :aria-label="t('sftp.navUp')" :disabled="!canGoUp" @click="$emit('up')">
            <template #icon><ArrowUpOutlined /></template>
          </a-button>
        </a-tooltip>
      </a-button-group>

      <div class="quick-tools">
        <a-tooltip :title="t('common.refresh')">
          <a-button size="small" :aria-label="t('common.refresh')" :disabled="loading" @click="$emit('refresh')">
            <template #icon><ReloadOutlined /></template>
          </a-button>
        </a-tooltip>

        <a-dropdown :trigger="['hover']">
          <a-button size="small" :aria-label="t('sftp.pathSuggestionHistory')">
            <template #icon><HistoryOutlined /></template>
          </a-button>
          <template #overlay>
            <a-menu @click="(e) => $emit('click-history', e.key)">
              <a-menu-item v-if="historyList.length === 0" disabled>
                {{ t('sftp.noHistory') }}
              </a-menu-item>
              <a-menu-item v-for="path in historyList" :key="path">
                {{ path }}
              </a-menu-item>
              <a-menu-divider v-if="historyList.length > 0" />
              <a-menu-item v-if="historyList.length > 0" key="clear_history">
                <DeleteOutlined /> {{ t('sftp.clearHistory') }}
              </a-menu-item>
            </a-menu>
          </template>
        </a-dropdown>

        <a-dropdown :trigger="['hover']">
          <a-button size="small" :aria-label="t('sftp.favorites')">
            <template #icon><StarOutlined /></template>
          </a-button>
          <template #overlay>
            <a-menu @click="(e) => { if (e.key !== 'add_favorite') $emit('click-favorite', e.key) }">
              <a-menu-item v-if="favoritesList.length === 0" disabled>
                {{ t('sftp.noFavorites') }}
              </a-menu-item>
              <a-menu-item v-for="path in favoritesList" :key="path">
                <div class="favorite-menu-item">
                  <span>{{ path }}</span>
                  <CloseOutlined class="favorite-remove" @click.stop="$emit('remove-favorite', path)" />
                </div>
              </a-menu-item>
              <a-menu-divider />
              <a-menu-item key="add_favorite" @click="$emit('add-favorite')">
                <StarFilled style="color: #faad14" /> {{ t('sftp.addFavorite') }}
              </a-menu-item>
            </a-menu>
          </template>
        </a-dropdown>
      </div>

      <template v-if="!pathInputVisible">
        <div class="breadcrumb-container" @click="$emit('show-path-input')">
          <a-tooltip :title="t('sftp.goToPath')">
            <a-button size="small" type="text" class="path-toggle-btn" :aria-label="t('sftp.goToPath')" @click.stop="$emit('show-path-input')">
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
            @pressEnter="$emit('path-enter')"
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
              :aria-label="t('sftp.pathGo')"
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

    <div class="toolbar-row toolbar-actions" :class="{ 'has-selection': selectedCount > 0 }">
      <div class="file-actions">
        <a-tooltip :title="clipboardCount ? t('sftp.paste') : ''">
          <a-button size="small" :disabled="!clipboardCount" @click="$emit('paste')">
            <template #icon><SnippetsOutlined /></template>
            <span class="action-text">{{ t('sftp.paste') }}</span>
            <span v-if="clipboardCount" class="clipboard-count">{{ clipboardCount }}</span>
          </a-button>
        </a-tooltip>
        <a-dropdown>
          <a-button size="small">
            <template #icon><PlusOutlined /></template>
            <span class="action-text">{{ t('sftp.new') }}</span>
            <DownOutlined />
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
            <span class="action-text">{{ t('sftp.upload') }}</span>
          </a-button>
        </a-upload>
      </div>

      <div class="selection-actions">
        <template v-if="selectedCount > 0">
          <a-tag color="blue" class="selection-count">
            {{ t('sftp.selected', { count: selectedCount }) }}
          </a-tag>
          <a-button-group size="small">
            <a-tooltip :title="t('sftp.downloadSelected')">
              <a-button :aria-label="t('sftp.downloadSelected')" @click="$emit('bulk-download')">
                <template #icon><DownloadOutlined /></template>
              </a-button>
            </a-tooltip>
            <a-tooltip :title="t('sftp.cutSelected')">
              <a-button :aria-label="t('sftp.cutSelected')" @click="$emit('bulk-cut')">
                <template #icon><ScissorOutlined /></template>
              </a-button>
            </a-tooltip>
            <a-tooltip :title="t('sftp.copySelected')">
              <a-button :aria-label="t('sftp.copySelected')" @click="$emit('bulk-copy')">
                <template #icon><CopyOutlined /></template>
              </a-button>
            </a-tooltip>
            <a-tooltip :title="t('sftp.deleteSelected')">
              <a-button danger :aria-label="t('sftp.deleteSelected')" @click="$emit('bulk-delete')">
                <template #icon><DeleteOutlined /></template>
              </a-button>
            </a-tooltip>
          </a-button-group>
          <a-dropdown>
            <a-button size="small">
              {{ t('common.more') }}
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
                <a-menu-item key="properties" @click="$emit('properties')">
                  <InfoCircleOutlined /> {{ t('sftp.properties') }}
                </a-menu-item>
              </a-menu>
            </template>
          </a-dropdown>
        </template>
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
  HistoryOutlined,
  StarOutlined,
  StarFilled,
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
  historyList: { type: Array, default: () => [] },
  favoritesList: { type: Array, default: () => [] },
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
  'click-history',
  'click-favorite',
  'add-favorite',
  'remove-favorite',
])

const { t } = useI18n()
const pathInputRef = ref(null)
defineExpose({ pathInputRef })
</script>

<style scoped>
.browser-header {
  display: flex;
  flex-direction: column;
  margin-bottom: 10px;
  padding: 6px 0;
  gap: 6px;
}

.toolbar-row {
  display: flex;
  align-items: center;
  width: 100%;
  min-width: 0;
  gap: 8px;
}

.toolbar-main {
  flex-wrap: nowrap;
}

.toolbar-actions {
  justify-content: flex-start;
  flex-wrap: wrap;
  min-height: 28px;
}

.toolbar-actions.has-selection {
  padding: 4px 6px;
  border: 1px solid rgba(22, 119, 255, 0.18);
  border-radius: 6px;
  background: rgba(22, 119, 255, 0.06);
}

.nav-actions {
  flex-shrink: 0;
}

.quick-tools,
.file-actions,
.selection-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
  flex-wrap: wrap;
}

.selection-actions {
  min-width: 0;
}

.selection-count {
  margin-right: 0;
  max-width: 160px;
  overflow: hidden;
  text-overflow: ellipsis;
}

.clipboard-count {
  margin-left: 4px;
  padding: 0 5px;
  border-radius: 9px;
  font-size: 11px;
  line-height: 16px;
  background: rgba(0, 0, 0, 0.08);
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
  border: 1px solid transparent;
}

.breadcrumb-container:hover {
  background: rgba(0, 0, 0, 0.04);
  border-color: rgba(0, 0, 0, 0.06);
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

.favorite-menu-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.favorite-menu-item span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
}

.favorite-remove {
  color: #ff4d4f;
  font-size: 10px;
  flex-shrink: 0;
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

@media (max-width: 900px) {
  .toolbar-main {
    flex-wrap: wrap;
  }

  .breadcrumb-container,
  .path-input-wrapper {
    order: 3;
    flex-basis: 100%;
  }

  .quick-tools {
    margin-left: auto;
  }
}

@media (max-width: 640px) {
  .toolbar-actions {
    align-items: center;
  }

  .selection-actions,
  .file-actions {
    width: auto;
  }

  .action-text {
    display: none;
  }
}
</style>
