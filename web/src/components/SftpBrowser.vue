<template>
  <div class="sftp-browser" @drop="handleDrop" @dragover="handleDragOver" @dragleave="handleDragLeave">
    <div class="browser-header">
      <a-button-group size="small" class="nav-actions">
        <a-tooltip :title="t('sftp.navBack')">
          <a-button :disabled="!canGoBack" @click="goBack">
            <template #icon><LeftOutlined /></template>
          </a-button>
        </a-tooltip>
        <a-tooltip :title="t('sftp.navForward')">
          <a-button :disabled="!canGoForward" @click="goForward">
            <template #icon><RightOutlined /></template>
          </a-button>
        </a-tooltip>
        <a-tooltip :title="t('sftp.navUp')">
          <a-button :disabled="!canGoUp" @click="goUp">
            <template #icon><ArrowUpOutlined /></template>
          </a-button>
        </a-tooltip>
        <a-tooltip :title="t('common.refresh')">
          <a-button :disabled="loading" @click="refresh">
            <template #icon><ReloadOutlined /></template>
          </a-button>
        </a-tooltip>
      </a-button-group>
      <div class="header-actions">
        <a-button size="small" :disabled="!sftpStore.clipboard.paths.length" @click="paste">
          <template #icon><SnippetsOutlined /></template>
          {{ t('sftp.paste') }}
        </a-button>
        <a-button-group size="small">
          <a-button :disabled="!selectedRowKeys.length" @click="handleBulkCut">
            <template #icon><ScissorOutlined /></template>
            {{ t('sftp.cut') }}
          </a-button>
          <a-button :disabled="!selectedRowKeys.length" @click="handleBulkCopy">
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
              <a-menu-item key="folder" @click="openCreate('folder')">
                <FolderAddOutlined /> {{ t('sftp.newFolder') }}
              </a-menu-item>
              <a-menu-item key="file" @click="openCreate('file')">
                <FileAddOutlined /> {{ t('sftp.newFile') }}
              </a-menu-item>
            </a-menu>
          </template>
        </a-dropdown>
        <a-upload
          :custom-request="handleUpload"
          :show-upload-list="false"
          accept="*"
          multiple
        >
          <a-button size="small" type="primary">
            <template #icon><UploadOutlined /></template>
            {{ t('sftp.upload') }}
          </a-button>
        </a-upload>
        <a-dropdown v-if="selectedRowKeys.length > 0">
          <a-button size="small">
            {{ t('sftp.selected', { count: selectedRowKeys.length }) }}
            <DownOutlined />
          </a-button>
          <template #overlay>
            <a-menu>
              <a-menu-item key="select-all" @click="selectAll">
                <CheckSquareOutlined /> {{ t('sftp.selectAll') }}
              </a-menu-item>
              <a-menu-item key="invert-selection" @click="invertSelection">
                <SwapOutlined /> {{ t('sftp.invertSelection') }}
              </a-menu-item>
              <a-menu-item key="clear-selection" @click="clearSelection">
                <CloseOutlined /> {{ t('sftp.clearSelection') }}
              </a-menu-item>
              <a-menu-divider />
              <a-menu-item key="cut-selected" @click="handleBulkCut">
                <ScissorOutlined /> {{ t('sftp.cutSelected') }}
              </a-menu-item>
              <a-menu-item key="copy-selected" @click="handleBulkCopy">
                <CopyOutlined /> {{ t('sftp.copySelected') }}
              </a-menu-item>
              <a-menu-item
                key="paste-selected"
                @click="paste"
                :disabled="!sftpStore.clipboard.paths.length"
              >
                <SnippetsOutlined /> {{ t('sftp.paste') }}
              </a-menu-item>
              <a-menu-divider />
              <a-menu-item key="download-selected" @click="handleBulkDownload">
                <DownloadOutlined /> {{ t('sftp.downloadSelected') }}
              </a-menu-item>
              <a-menu-item key="delete-selected" @click="handleBulkDelete" danger>
                <DeleteOutlined /> {{ t('sftp.deleteSelected') }}
              </a-menu-item>
              <a-menu-divider />
              <a-menu-item key="properties" @click="showProperties">
                <InfoCircleOutlined /> {{ t('sftp.properties') }}
              </a-menu-item>
            </a-menu>
          </template>
        </a-dropdown>
      </div>
      <!-- 面包屑 / 路径输入框 切换 -->
      <template v-if="!pathInputVisible">
        <div class="breadcrumb-container" @click="showPathInput">
          <a-tooltip :title="t('sftp.goToPath')">
            <a-button size="small" type="text" @click.stop="showPathInput" class="path-toggle-btn">
              <template #icon><EditOutlined /></template>
            </a-button>
          </a-tooltip>
          <a-breadcrumb separator=">" size="small" class="path-breadcrumb">
            <a-breadcrumb-item v-for="(part, index) in pathParts" :key="index">
              <a @click.stop="navigateTo(index)">{{ part || '/' }}</a>
            </a-breadcrumb-item>
          </a-breadcrumb>
        </div>
      </template>
      <div v-else class="path-input-wrapper">
        <a-input
          ref="pathInputRef"
          v-model:value="pathInputValue"
          size="small"
          :placeholder="t('sftp.pathPlaceholder')"
          @pressEnter="goToPath"
          @keydown.esc="hidePathInput"
          @blur="hidePathInput"
        />
      </div>
    </div>

    <!-- 文件列表 -->
    <div ref="browserContentRef" class="browser-content" @drop="handleDrop" @dragover="handleDragOver" @dragleave="handleDragLeave" @contextmenu.prevent.stop="handleContainerContextMenu">
      <a-table
        :loading="loading"
        :columns="columns"
        :data-source="files"
        :pagination="false"
        size="small"
        :scroll="{ y: tableScrollY }"
        :row-selection="rowSelection"
        row-key="name"
        :customRow="customRow"
      >
        <template #bodyCell="{ column, record }">
          <template v-if="column.key === 'name'">
            <a v-if="record.is_dir" @click="enterDir(record.name)">
              <FolderFilled style="color: #faad14; margin-right: 8px" />
              {{ record.name }}
            </a>
            <a v-else @click="openFile(record)">
              <FileOutlined style="color: #8c8c8c; margin-right: 8px" />
              {{ record.name }}
            </a>
          </template>
          <template v-else-if="column.key === 'size'">
            <a-spin v-if="record.is_dir && record.size === null" size="small" />
            <span v-else-if="record.size === -1" style="color: #ff4d4f; font-size: 12px;">{{ t('sftp.calcFailed') }}</span>
            <span v-else>{{ formatSize(record.size) }}</span>
          </template>
          <template v-else-if="column.key === 'mod_time'">
            <span style="font-size: 12px; color: #8c8c8c;">{{ formatModTime(record.mod_time) }}</span>
          </template>
          <template v-else-if="column.key === 'action'">
            <a-space size="small">
              <!-- 文件夹显示打开按钮,文件显示下载按钮 -->
              <a-button size="small" type="text" v-if="record.is_dir" @click="download(record.name)">
                <template #icon><CloudDownloadOutlined /></template>
              </a-button>
              <a-button size="small" type="text" v-if="record.is_dir" @click="enterDir(record.name)">
                <template #icon><FolderOpenOutlined /></template>
              </a-button>
              <a-button size="small" type="text" v-else @click="download(record.name)">
                <template #icon><DownloadOutlined /></template>
              </a-button>
              
              <!-- Media Preview or Edit -->
              <a-button size="small" type="text" v-if="!record.is_dir && isMedia(record.name)" @click="handlePreview(record)">
                <template #icon><EyeOutlined /></template>
              </a-button>
              <a-button size="small" type="text" v-if="!record.is_dir && !isMedia(record.name)" @click="openEditor(record)">
                <template #icon><EditOutlined /></template>
              </a-button>

              <a-tooltip v-if="enableTransfer" :title="t('sftp.sendTo', { name: transferTargetLabel })">
                <a-button size="small" type="text" style="color: #1890ff" @click="handleTransfer(record)">
                  <template #icon><SwapOutlined /></template>
                </a-button>
              </a-tooltip>
              <a-popconfirm
                :title="t('sftp.deleteConfirm')"
                @confirm="remove(record.name)"
              >
                <a-button size="small" type="text" danger>
                  <template #icon><DeleteOutlined /></template>
                </a-button>
              </a-popconfirm>
              <a-dropdown>
                <a-button size="small" type="text">
                  <template #icon><MoreOutlined /></template>
                </a-button>
                <template #overlay>
                    <a-menu>
                        <a-menu-item key="rename" @click="openRename(record)">
                            <EditOutlined /> {{ t('sftp.rename') }}
                        </a-menu-item>
                        <a-menu-divider />
                        <a-menu-item key="cut" @click="cut(record.name)">
                            <ScissorOutlined /> {{ t('sftp.cut') }}
                        </a-menu-item>
                        <a-menu-item key="copy" @click="copy(record.name)">
                            <CopyOutlined /> {{ t('sftp.copy') }}
                        </a-menu-item>
                    </a-menu>
                </template>
              </a-dropdown>
            </a-space>
          </template>
        </template>
      </a-table>
    </div>

    <FileEditor
      v-model:open="editorVisible"
      :host-id="hostId"
      :file-path="editingFile.path"
      :file-name="editingFile.name"
      @saved="onEditorSaved"
    />

    <a-modal
      v-model:open="renameVisible"
      :title="t('sftp.rename')"
      @ok="handleRename"
    >
      <a-input v-model:value="renameName" :placeholder="t('sftp.newName')" />
    </a-modal>

    <a-modal
      v-model:open="createVisible"
      :title="createType === 'folder' ? t('sftp.newFolder') : t('sftp.newFile')"
      @ok="handleCreate"
    >
      <a-input v-model:value="createName" :placeholder="createType === 'folder' ? t('sftp.folderName') : t('sftp.fileName')" />
    </a-modal>

    <a-modal
      v-model:open="uploadConflictOpen"
      :title="t('sftp.uploadConflictTitle')"
      :footer="null"
      :mask-closable="false"
      width="400px"
      :wrap-class-name="uploadConflictWrapClass"
      @cancel="onUploadConflictCancel"
    >
      <div
        class="upload-conflict-body"
        :class="{ 'upload-conflict-body--dark': themeStore.isDark }"
      >
        <p class="upload-conflict-text">{{ t('sftp.uploadConflictContent', { name: uploadConflictName }) }}</p>
        <p v-if="uploadConflictIsDir" class="upload-conflict-hint">{{ t('sftp.uploadConflictDirHint') }}</p>
        <div class="upload-conflict-actions">
          <a-button @click="onUploadConflictCancel">{{ t('common.cancel') }}</a-button>
          <a-button @click="onUploadConflictKeepBoth">{{ t('sftp.uploadKeepBoth') }}</a-button>
          <a-button type="primary" :disabled="uploadConflictIsDir" @click="onUploadConflictOverwrite">
            {{ t('sftp.uploadOverwrite') }}
          </a-button>
        </div>
      </div>
    </a-modal>

    <!-- Video Preview Modal -->
    <a-modal
      v-model:open="previewVisible"
      :title="previewName"
      :footer="null"
      width="800px"
      @cancel="closePreview"
      centered
    >
      <div v-if="previewLoading" style="text-align: center; padding: 40px">
        <a-spin tip="Loading media..." />
      </div>
      <div v-else style="display: flex; justify-content: center; align-items: center; background: #000; min-height: 300px; border-radius: 4px; overflow: hidden;">
        <video v-if="previewType === 'video'" :src="previewSrc" controls style="max-width: 100%; max-height: 70vh;" autoplay></video>
      </div>
    </a-modal>

    <!-- Hidden Image for Ant Design Preview (Supports Rotate, Zoom, etc.) -->
    <div style="display: none;">
        <a-image
            :src="previewSrc"
            :preview="{
                visible: imagePreviewVisible,
                onVisibleChange: (vis) => {
                    imagePreviewVisible = vis;
                    if (!vis) closePreview();
                }
            }"
        />
    </div>

    <!-- Right-click Context Menu -->
    <div
      v-if="contextMenuVisible && contextMenuRecord"
      ref="contextMenuRef"
      class="sftp-context-menu"
      :style="{ left: contextMenuPosition.x + 'px', top: contextMenuPosition.y + 'px' }"
    >
      <a-menu @click="closeContextMenu">
        <!-- Container Menu -->
        <template v-if="contextMenuRecord.is_container">
          <a-menu-item key="refresh" @click="refresh">
            <ReloadOutlined /> {{ t('common.refresh') }}
          </a-menu-item>
          <a-menu-divider />
          <a-menu-item key="new-folder" @click="openCreate('folder')">
            <FolderAddOutlined /> {{ t('sftp.newFolder') }}
          </a-menu-item>
          <a-menu-item key="new-file" @click="openCreate('file')">
            <FileAddOutlined /> {{ t('sftp.newFile') }}
          </a-menu-item>
          <a-menu-divider />
          <a-menu-item key="paste" @click="paste" :disabled="!sftpStore.clipboard.paths.length">
            <SnippetsOutlined /> {{ t('sftp.paste') }}
          </a-menu-item>
        </template>
        <!-- File/Folder Menu -->
        <template v-else>
          <a-menu-item key="open" @click="handleContextMenuOpen">
            <FolderOpenOutlined v-if="contextMenuRecord.is_dir" />
            <EditOutlined v-else />
            {{ contextMenuRecord.is_dir ? t('sftp.openDir') || t('common.open') : t('sftp.edit') || t('common.edit') }}
          </a-menu-item>
          <a-menu-item key="download" @click="download(contextMenuRecord.name)">
            <DownloadOutlined /> {{ t('sftp.download') || t('common.download') }}
          </a-menu-item>
          <a-menu-item key="transfer" v-if="enableTransfer" @click="handleTransfer(contextMenuRecord)">
            <SwapOutlined /> {{ t('sftp.sendTo', { name: transferTargetLabel }) }}
          </a-menu-item>
          <a-menu-divider />
          <a-menu-item key="cut" @click="cut(contextMenuRecord.name)">
            <ScissorOutlined /> {{ t('sftp.cut') }}
          </a-menu-item>
          <a-menu-item key="copy" @click="copy(contextMenuRecord.name)">
            <CopyOutlined /> {{ t('sftp.copy') }}
          </a-menu-item>
          <a-menu-item key="rename" @click="openRename(contextMenuRecord)">
            <EditOutlined /> {{ t('sftp.rename') }}
          </a-menu-item>
          <a-menu-divider />
          <a-menu-item key="delete" @click="remove(contextMenuRecord.name)" danger>
            <DeleteOutlined /> {{ t('sftp.delete') || t('common.delete') }}
          </a-menu-item>
        </template>
      </a-menu>
    </div>

    <Teleport to="body">
      <div
        v-if="uploadTaskList.length"
        class="upload-progress-dock"
        :class="{ 'upload-progress-dock--dark': themeStore.isDark }"
        :style="{ '--upload-ring-size': `${uploadRingSize}px` }"
      >
        <div v-if="uploadPanelExpanded" class="upload-panel upload-panel-list">
          <div class="upload-panel-header">
            <span class="upload-panel-title">{{ uploadPanelTitle }}</span>
            <a-button type="link" size="small" class="upload-hide-btn" @click="hideUploadPanel">
              {{ t('common.hide') }}
            </a-button>
          </div>
          <div
            class="upload-task-list"
            :class="{ 'is-scrollable': uploadTaskList.length > 3 }"
          >
            <div v-for="task in uploadTaskList" :key="task.key" class="upload-task-item">
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
                    @click="cancelUpload(task.key)"
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
                :status="uploadProgressBarStatus(task)"
                size="small"
                :show-info="false"
              />
              <div v-if="task.errorMessage" class="upload-panel-error">{{ task.errorMessage }}</div>
            </div>
          </div>
        </div>

        <a-tooltip v-else :title="uploadCircleTooltip" placement="left">
          <button
            type="button"
            class="upload-circle-btn"
            :aria-label="t('sftp.uploadProgress')"
            @click="showUploadPanel"
          >
            <span class="upload-ring-wrap">
              <svg
                class="upload-ring-svg"
                :width="uploadRingSize"
                :height="uploadRingSize"
                :viewBox="`0 0 ${uploadRingSize} ${uploadRingSize}`"
                aria-hidden="true"
              >
                <circle
                  class="upload-ring-track"
                  :cx="uploadRingCenter"
                  :cy="uploadRingCenter"
                  :r="uploadRingRadius"
                  fill="none"
                  stroke-width="3"
                />
                <circle
                  class="upload-ring-progress"
                  :class="`is-${aggregateUploadStatus}`"
                  :cx="uploadRingCenter"
                  :cy="uploadRingCenter"
                  :r="uploadRingRadius"
                  fill="none"
                  stroke-width="3"
                  stroke-linecap="round"
                  :stroke-dasharray="uploadRingCircumference"
                  :stroke-dashoffset="uploadRingDashOffset"
                  :transform="`rotate(-90 ${uploadRingCenter} ${uploadRingCenter})`"
                />
              </svg>
              <span
                v-if="aggregateUpload.connecting && aggregateUpload.percent === 0"
                class="upload-circle-center upload-circle-icon"
              >
                <LoadingOutlined />
              </span>
              <span v-else class="upload-circle-center upload-circle-percent">
                {{ aggregateUpload.percent }}<span class="upload-circle-percent-suffix">%</span>
              </span>
            </span>
            <span v-if="uploadTaskList.length > 1" class="upload-circle-badge">{{ uploadTaskList.length }}</span>
          </button>
        </a-tooltip>
      </div>
    </Teleport>

  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch, h, reactive, nextTick } from 'vue'
import { message, notification, Progress, Button, Spin, Modal } from 'ant-design-vue'
import { 
  FolderFilled, 
  FileOutlined, 
  ReloadOutlined, 
  UploadOutlined, 
  DownloadOutlined, 
  DeleteOutlined,
  EditOutlined,
  ScissorOutlined,
  CopyOutlined,
  SnippetsOutlined,
  MoreOutlined,
  PlusOutlined,
  FolderAddOutlined,
  FileAddOutlined,
  FolderOpenOutlined,
  CloudDownloadOutlined,
  EyeOutlined,
  SwapOutlined,
  AimOutlined,
  DownOutlined,
  CheckSquareOutlined,
  CloseOutlined,
  LoadingOutlined,
  InfoCircleOutlined,
  LeftOutlined,
  RightOutlined,
  ArrowUpOutlined
} from '@ant-design/icons-vue'
import { listFiles, uploadFile, downloadFile, deleteFile, renameFile, pasteFile, createDirectory, createFile, getDirSize, transferFile } from '../api/sftp'
import { useI18n } from 'vue-i18n'
import FileEditor from './FileEditor.vue'
import { useSftpStore } from '../stores/sftp'
import { useThemeStore } from '../stores/theme'
import '../styles/sftp-progress-dock.css'
import { hasNameConflict, generateKeepBothName as makeKeepBothName } from '../utils/sftpConflict'
import { buildRemotePath } from '../utils/sftpPath'
import dayjs from 'dayjs'

const { t } = useI18n()
const sftpStore = useSftpStore()
const themeStore = useThemeStore()
const props = defineProps({
  hostId: {
    type: [String, Number],
    required: true
  },
  visible: {
    type: Boolean,
    default: false
  },
  enableTransfer: {
    type: Boolean,
    default: false
  },
  transferTargetLabel: {
    type: String,
    default: ''
  },
  hostLabel: {
    type: String,
    default: ''
  }
})

const emit = defineEmits(['transfer', 'selection-change'])

const currentPath = ref('.')
const files = ref([])
const loading = ref(false)

// Directory listing vs background folder-size jobs (separate so sizes never block navigation).
let listGeneration = 0
let listAbortController = null
let dirSizeSessionId = 0
let dirSizeAbortController = null
const DIR_SIZE_CONCURRENCY = 2

const cancelDirSizeJobs = () => {
  dirSizeSessionId += 1
  if (dirSizeAbortController) {
    dirSizeAbortController.abort()
    dirSizeAbortController = null
  }
}

const applyDirSize = (dirName, size, sessionId, cwd) => {
  if (sessionId !== dirSizeSessionId) return
  const file = files.value.find((f) => f.name === dirName && f.is_dir)
  if (!file) return
  if (currentPath.value !== cwd) return
  file.size = size
}

const fetchDirSizesInBackground = (hostId, cwd, dirNames, sessionId, signal) => {
  const queue = [...dirNames]
  const workerCount = Math.min(DIR_SIZE_CONCURRENCY, queue.length)
  if (workerCount === 0) return

  const worker = async () => {
    while (queue.length > 0) {
      if (signal.aborted || sessionId !== dirSizeSessionId) return
      const dirName = queue.shift()
      const path = cwd === '.' ? dirName : `${cwd}/${dirName}`
      try {
        const res = await getDirSize(hostId, path, { signal })
        if (signal.aborted || sessionId !== dirSizeSessionId) return
        const size = res && res.size !== undefined ? res.size : -1
        applyDirSize(dirName, size, sessionId, cwd)
      } catch (error) {
        if (error?.code === 'ERR_CANCELED' || error?.name === 'CanceledError') return
        applyDirSize(dirName, -1, sessionId, cwd)
      }
    }
  }

  void Promise.all(Array.from({ length: workerCount }, () => worker()))
}

// Path navigation history (back / forward)
const pathHistoryStack = ref([])
const pathHistoryIndex = ref(-1)
const skipHistoryRecord = ref(false)

const canGoBack = computed(() => pathHistoryIndex.value > 0)
const canGoForward = computed(() => pathHistoryIndex.value < pathHistoryStack.value.length - 1)
const canGoUp = computed(() => {
  const p = currentPath.value
  return p !== '.' && p !== '/' && p !== ''
})

const getParentPath = (path) => {
  if (!path || path === '.' || path === '/') return path
  const normalized = path.replace(/\/+$/, '') || '/'
  if (normalized === '/') return '/'
  const lastSlash = normalized.lastIndexOf('/')
  if (lastSlash <= 0) return '/'
  return normalized.slice(0, lastSlash) || '/'
}

const resetPathHistory = () => {
  pathHistoryStack.value = []
  pathHistoryIndex.value = -1
}

const navigateToPath = (path, { recordHistory = true } = {}) => {
  if (loading.value) return
  const target = path || '/'
  if (target === currentPath.value) return
  if (recordHistory && !skipHistoryRecord.value) {
    let stack = [...pathHistoryStack.value]
    const idx = pathHistoryIndex.value
    if (idx >= 0 && idx < stack.length - 1) {
      stack = stack.slice(0, idx + 1)
    }
    if (stack.length === 0 || stack[stack.length - 1] !== target) {
      stack.push(target)
    }
    pathHistoryStack.value = stack
    pathHistoryIndex.value = stack.length - 1
  }
  currentPath.value = target
  loadFiles()
}

const goBack = () => {
  if (!canGoBack.value || loading.value) return
  skipHistoryRecord.value = true
  pathHistoryIndex.value -= 1
  currentPath.value = pathHistoryStack.value[pathHistoryIndex.value]
  loadFiles().finally(() => {
    skipHistoryRecord.value = false
  })
}

const goForward = () => {
  if (!canGoForward.value || loading.value) return
  skipHistoryRecord.value = true
  pathHistoryIndex.value += 1
  currentPath.value = pathHistoryStack.value[pathHistoryIndex.value]
  loadFiles().finally(() => {
    skipHistoryRecord.value = false
  })
}

const goUp = () => {
  if (!canGoUp.value || loading.value) return
  navigateToPath(getParentPath(currentPath.value))
}

// 直达路径
const pathInputVisible = ref(false)
const pathInputValue = ref('')
const pathInputRef = ref(null)

const showPathInput = () => {
  pathInputValue.value = currentPath.value === '.' ? '/' : currentPath.value
  pathInputVisible.value = true
  nextTick(() => {
    if (pathInputRef.value) {
      pathInputRef.value.focus()
      pathInputRef.value.select && pathInputRef.value.select()
    }
  })
}

const hidePathInput = () => {
  pathInputVisible.value = false
}

const goToPath = () => {
  const target = pathInputValue.value.trim()
  if (!target) return
  pathInputVisible.value = false
  navigateToPath(target)
}

// Row Selection
const selectedRowKeys = ref([])
const onSelectChange = (keys) => {
  selectedRowKeys.value = keys
  emit('selection-change', keys)
}
const rowSelection = computed(() => ({
  selectedRowKeys: selectedRowKeys.value,
  onChange: onSelectChange,
}))

// 动态计算表格滚动高度
const browserContentRef = ref(null)
const tableScrollY = ref('calc(100vh - 150px)')

const updateTableScrollY = () => {
  nextTick(() => {
    if (browserContentRef.value) {
      // 表头高度大约 39px，留出余量
      const contentHeight = browserContentRef.value.clientHeight
      const headerOffset = 39
      if (contentHeight > 0) {
        tableScrollY.value = `${contentHeight - headerOffset}px`
      }
    }
  })
}

let resizeObserver = null
onMounted(() => {
  resizeObserver = new ResizeObserver(() => {
    updateTableScrollY()
  })
  nextTick(() => {
    if (browserContentRef.value) {
      resizeObserver.observe(browserContentRef.value)
    }
  })
})

onUnmounted(() => {
  if (resizeObserver) {
    resizeObserver.disconnect()
  }
})
const renameVisible = ref(false)
const renameName = ref('')
const renamingFile = ref(null)

const createVisible = ref(false)
const createType = ref('folder') // 'folder' or 'file'
const createName = ref('')

const editorVisible = ref(false)
const editingFile = ref({
    path: '',
    name: ''
})

// Right-click Context Menu Logic
const contextMenuVisible = ref(false)
const contextMenuRecord = ref(null)
const contextMenuPosition = ref({ x: 0, y: 0 })
const contextMenuRef = ref(null)

const closeContextMenu = () => {
  contextMenuVisible.value = false
}

const onDocumentClick = (e) => {
  if (contextMenuVisible.value && contextMenuRef.value && !contextMenuRef.value.contains(e.target)) {
    closeContextMenu()
  }
}

onMounted(() => {
  document.addEventListener('click', onDocumentClick)
  document.addEventListener('contextmenu', onDocumentClick)
})

onUnmounted(() => {
  document.removeEventListener('click', onDocumentClick)
  document.removeEventListener('contextmenu', onDocumentClick)
})

const handleContainerContextMenu = (e) => {
  contextMenuRecord.value = { is_container: true }
  
  const menuWidth = 200
  const menuHeight = 200 // Approx height for new file/folder menu
  const x = e.clientX + menuWidth > window.innerWidth ? e.clientX - menuWidth : e.clientX
  const y = e.clientY + menuHeight > window.innerHeight ? e.clientY - menuHeight : e.clientY
  contextMenuPosition.value = { x: Math.max(0, x), y: Math.max(0, y) }
  contextMenuVisible.value = true
}

const customRow = (record) => {
  return {
    onContextmenu: (e) => {
      e.preventDefault()
      e.stopPropagation()
      if (!selectedRowKeys.value.includes(record.name)) {
         selectedRowKeys.value = [record.name]
      }
      contextMenuRecord.value = record
      // Adjust position to keep menu within viewport
      const menuWidth = 200
      const menuHeight = 300
      const x = e.clientX + menuWidth > window.innerWidth ? e.clientX - menuWidth : e.clientX
      const y = e.clientY + menuHeight > window.innerHeight ? e.clientY - menuHeight : e.clientY
      contextMenuPosition.value = { x: Math.max(0, x), y: Math.max(0, y) }
      contextMenuVisible.value = true
    }
  }
}

const handleContextMenuOpen = () => {
  if (!contextMenuRecord.value) return
  const record = contextMenuRecord.value
  if (record.is_dir) {
    enterDir(record.name)
  } else if (isMedia(record.name)) {
    handlePreview(record)
  } else {
    openEditor(record)
  }
}

// Preview State
const previewVisible = ref(false) // For Videos
const imagePreviewVisible = ref(false) // For Images
const previewLoading = ref(false)
const previewType = ref('image') // 'image' | 'video'
const previewSrc = ref('')
const previewName = ref('')

const isMedia = (filename) => {
    const ext = filename.split('.').pop().toLowerCase()
    const images = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico']
    const videos = ['mp4', 'webm', 'ogg', 'mov', 'avi', 'mkv']
    return images.includes(ext) || videos.includes(ext)
}

const getMediaType = (filename) => {
    const ext = filename.split('.').pop().toLowerCase()
    const videos = ['mp4', 'webm', 'ogg', 'mov', 'avi', 'mkv']
    return videos.includes(ext) ? 'video' : 'image'
}

const openFile = (record) => {
    if (isMedia(record.name)) {
        handlePreview(record)
    } else {
        openEditor(record)
    }
}

const handlePreview = async (record) => {
    const name = record.name
    const fullPath = currentPath.value === '.' ? name : `${currentPath.value}/${name}`
    
    previewName.value = name
    const type = getMediaType(name)
    previewType.value = type
    
    // Start loading state
    previewLoading.value = true
    
    // Reset src just in case
    if (previewSrc.value) {
        if (previewSrc.value.startsWith('blob:')) {
            window.URL.revokeObjectURL(previewSrc.value)
        }
        previewSrc.value = ''
    }

    try {
        // Use JWT Token from localStorage for streaming
        // To avoid exposing token in URL (security risk), we use a temporary Cookie.
        // The backend AuthMiddleware checks for 'access_token' cookie.
        const token = localStorage.getItem('token')
        
        if (!token) {
            throw new Error("No authentication token found")
        }
        
        // Set temporary cookie (valid for 5 minutes)
        document.cookie = `access_token=${token}; path=/api/sftp/download; max-age=300; SameSite=Strict`
        
        const encodedPath = encodeURIComponent(fullPath)
        // Clean URL without token
        const streamingUrl = `/api/sftp/download/${props.hostId}?path=${encodedPath}`
        
        previewSrc.value = streamingUrl
        
        if (type === 'image') {
            imagePreviewVisible.value = true
        } else {
            previewVisible.value = true
        }
    } catch (e) {
        message.error(t('sftp.downloadFailed') + ': ' + e.message)
        previewVisible.value = false
        imagePreviewVisible.value = false
    } finally {
        previewLoading.value = false
    }
}

const closePreview = () => {
    previewVisible.value = false
    imagePreviewVisible.value = false
    
    // Clear access_token cookie
    document.cookie = `access_token=; path=/api/sftp/download; max-age=0`
    
    // Delay revoke to avoid blink or error if image is closing
    setTimeout(() => {
        // Only revoke if neither is open (though logic implies one at a time)
       if (!previewVisible.value && !imagePreviewVisible.value && previewSrc.value) {
            if (previewSrc.value.startsWith('blob:')) {
                window.URL.revokeObjectURL(previewSrc.value)
            }
           previewSrc.value = ''
       }
    }, 300)
}

const pathParts = computed(() => {
  if (currentPath.value === '.') return ['']
  // Handle root directory
  if (currentPath.value === '/') return ['']
  
  const parts = currentPath.value.split('/').filter(p => p !== '')
  // If absolute path (starts with /), the split logic removes the empty string at start (filter).
  // We add '' at the beginning to represent the Root breadcrumb item.
  // If path is '/home', parts=['home']. returns ['', 'home'].
  // If path is 'home' (relative), parts=['home']. returns ['', 'home'] (index 0 is relative root?)
  // Actually if we receive absolute path, logic is consistent.
  return ['', ...parts]
})

const columns = computed(() => [
  { title: t('sftp.action'), key: 'action', width: 150, align: 'center' },
  { title: t('sftp.name'), key: 'name', sorter: (a, b) => a.name.localeCompare(b.name), defaultSortOrder: 'ascend' },
  { title: t('sftp.size'), key: 'size', align: 'right', width: 100, sorter: (a, b) => (a.size ?? 0) - (b.size ?? 0) },
  {
    title: t('sftp.modified'),
    key: 'mod_time',
    width: 160,
    sorter: (a, b) => dayjs(a.mod_time).valueOf() - dayjs(b.mod_time).valueOf(),
  },
])

const loadFiles = async () => {
  if (!props.hostId) return

  cancelDirSizeJobs()
  if (listAbortController) {
    listAbortController.abort()
  }
  listAbortController = new AbortController()
  const listSignal = listAbortController.signal
  const gen = ++listGeneration

  loading.value = true
  selectedRowKeys.value = [] // Reset selection on path change
  const cwdAtStart = currentPath.value

  try {
    const data = await listFiles(props.hostId, cwdAtStart, { signal: listSignal })
    if (listSignal.aborted || gen !== listGeneration) return

    // Handle new response format { files: [], cwd: '/...' }
    let resolvedCwd = cwdAtStart
    if (data && data.files) {
        files.value = data.files.map(f => ({ ...f, size: f.is_dir ? null : f.size }))
        if (data.cwd) {
            resolvedCwd = data.cwd
            currentPath.value = data.cwd
            if (pathHistoryStack.value.length === 0) {
              pathHistoryStack.value = [data.cwd]
              pathHistoryIndex.value = 0
            }
        }
    } else if (Array.isArray(data)) {
        files.value = data.map(f => ({ ...f, size: f.is_dir ? null : f.size }))
    } else {
        files.value = []
    }

    const dirNames = files.value.filter((f) => f.is_dir).map((f) => f.name)
    if (dirNames.length > 0) {
      const sessionId = ++dirSizeSessionId
      dirSizeAbortController = new AbortController()
      fetchDirSizesInBackground(
        props.hostId,
        resolvedCwd,
        dirNames,
        sessionId,
        dirSizeAbortController.signal,
      )
    }
  } catch (error) {
    if (error?.code === 'ERR_CANCELED' || error?.name === 'CanceledError') return
    console.error('Failed to list files:', error)
  } finally {
    if (gen === listGeneration) {
      loading.value = false
    }
  }
}

const refresh = () => {
  if (loading.value) return
  loadFiles()
}

const enterDir = (name) => {
  if (loading.value) return
  let newPath
  if (currentPath.value === '.') {
    newPath = name
  } else {
    newPath = currentPath.value.endsWith('/')
      ? currentPath.value + name
      : currentPath.value + '/' + name
  }
  navigateToPath(newPath)
}

const navigateTo = (index) => {
  if (loading.value) return

  let newPath
  if (index === 0) {
    newPath = currentPath.value.startsWith('/') ? '/' : '.'
  } else {
    const parts = pathParts.value.slice(0, index + 1)
    newPath = parts.join('/')
    if (newPath === '') newPath = '/'
  }
  navigateToPath(newPath)
}

const uploadControllers = new Map()
const cancelledUploads = new Set()
const uploadTasks = reactive({})
const uploadDismissTimers = new Map()
const uploadPanelExpanded = ref(false)
/** Match Ant Design `size="small"` buttons (theme controlHeightSM). */
const uploadControlSize = computed(() => themeStore.themeToken.controlHeightSM || 24)
const uploadRingSize = computed(() => uploadControlSize.value * 2)
const uploadRingRadius = computed(() => uploadRingSize.value / 2 - 2)
const uploadRingCenter = computed(() => uploadRingSize.value / 2)
const uploadRingCircumference = computed(() => 2 * Math.PI * uploadRingRadius.value)

const uploadTaskList = computed(() => Object.values(uploadTasks))

const aggregateUpload = computed(() => {
  const tasks = uploadTaskList.value
  let written = 0
  let total = 0
  let connecting = false
  let fallbackPercentSum = 0
  let fallbackCount = 0

  for (const task of tasks) {
    if (task.status === 'connecting') {
      connecting = true
    }
    if (task.total > 0) {
      if (task.status === 'done') {
        written += task.total
        total += task.total
      } else {
        written += task.written || 0
        total += task.total
      }
    } else if (task.status === 'uploading' && task.percent > 0) {
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

  const hasActive = tasks.some((t) => t.status === 'connecting' || t.status === 'uploading')
  if (hasActive && percent >= 100) {
    percent = 99
  }

  return { written, total, percent, connecting, hasActive }
})

const aggregateUploadStatus = computed(() => {
  const tasks = uploadTaskList.value
  if (tasks.some((t) => t.status === 'error' || t.status === 'cancelled')) {
    return 'exception'
  }
  if (tasks.length && tasks.every((t) => t.status === 'done')) {
    return 'success'
  }
  return 'active'
})

const uploadRingDashOffset = computed(() => {
  const pct = Math.min(100, Math.max(0, aggregateUpload.value.percent))
  return uploadRingCircumference.value * (1 - pct / 100)
})

const uploadPanelTitle = computed(() => {
  const count = uploadTaskList.value.length
  if (count <= 1) {
    return uploadTaskList.value[0]?.title || t('sftp.uploading')
  }
  return t('sftp.uploadingCount', { count })
})

const uploadCircleTooltip = computed(() => {
  const { percent, written, total } = aggregateUpload.value
  if (written > 0 && total > 0) {
    return `${percent}% · ${formatSize(written)} / ${formatSize(total)}`
  }
  return t('sftp.expandUploadDetail')
})

const showUploadPanel = () => {
  uploadPanelExpanded.value = true
}

const hideUploadPanel = () => {
  uploadPanelExpanded.value = false
}

const createUploadTask = (key, { title, fileName }) => {
  uploadPanelExpanded.value = true
  uploadTasks[key] = {
    key,
    title,
    fileName,
    percent: 0,
    speed: '',
    written: 0,
    total: 0,
    status: 'connecting',
    errorMessage: '',
  }
}

const updateUploadTask = (key, patch) => {
  const task = uploadTasks[key]
  if (task) Object.assign(task, patch)
}

const dismissUploadTask = (key, delayMs = 3000) => {
  const existing = uploadDismissTimers.get(key)
  if (existing) clearTimeout(existing)
  const timer = setTimeout(() => {
    delete uploadTasks[key]
    uploadDismissTimers.delete(key)
    if (!uploadTaskList.value.length) {
      uploadPanelExpanded.value = false
    }
  }, delayMs)
  uploadDismissTimers.set(key, timer)
}

const uploadProgressBarStatus = (task) => {
  if (task.status === 'done') return 'success'
  if (task.status === 'error' || task.status === 'cancelled') return 'exception'
  return 'active'
}

/** Ant Design Upload wraps the real File in originFileObj; drag-drop provides a native File. */
const resolveUploadFile = (file) => {
  if (!file) return null
  if (file instanceof File || file instanceof Blob) return file
  if (file.originFileObj instanceof File || file.originFileObj instanceof Blob) {
    return file.originFileObj
  }
  return null
}

const cancelUpload = (key) => {
    const controller = uploadControllers.get(key)
    if (controller) {
        cancelledUploads.add(key)
        controller.abort()
        uploadControllers.delete(key)
    }
}

const uploadConflictOpen = ref(false)
const uploadConflictName = ref('')
const uploadConflictIsDir = ref(false)
let uploadConflictResolver = null

const uploadConflictWrapClass = computed(() =>
  themeStore.isDark
    ? 'upload-conflict-modal-wrap upload-conflict-modal-wrap--dark'
    : 'upload-conflict-modal-wrap'
)

const findDirEntry = (name) => files.value.find((f) => f.name === name)

const hasUploadNameConflict = (name) => hasNameConflict(files.value, name)

const generateKeepBothName = (name) => makeKeepBothName(files.value, name)

const promptUploadConflict = (name) => {
  const entry = findDirEntry(name)
  return new Promise((resolve) => {
    uploadConflictName.value = name
    uploadConflictIsDir.value = !!entry?.is_dir
    uploadConflictResolver = resolve
    uploadConflictOpen.value = true
  })
}

const finishUploadConflict = (action) => {
  uploadConflictOpen.value = false
  uploadConflictResolver?.(action)
  uploadConflictResolver = null
}

const onUploadConflictCancel = () => finishUploadConflict('cancel')
const onUploadConflictOverwrite = () => finishUploadConflict('overwrite')
const onUploadConflictKeepBoth = () => finishUploadConflict('keepBoth')

const resolveRemoteUploadName = async (displayName) => {
  if (!hasUploadNameConflict(displayName)) {
    return displayName
  }
  const action = await promptUploadConflict(displayName)
  if (action === 'cancel') {
    throw new Error('UPLOAD_CANCELLED_BY_USER')
  }
  if (action === 'keepBoth') {
    return generateKeepBothName(displayName)
  }
  return displayName
}

const handleUpload = async ({ file: uploadItem, onSuccess, onError }) => {
  const file = resolveUploadFile(uploadItem)
  if (!file) {
    message.error(t('sftp.uploadFailed'))
    if (typeof onError === 'function') onError(new Error('Invalid file'))
    return
  }

  const displayName = file.name || uploadItem?.name || 'upload'

  let remoteFileName
  try {
    remoteFileName = await resolveRemoteUploadName(displayName)
  } catch (err) {
    if (err.message === 'UPLOAD_CANCELLED_BY_USER') {
      if (typeof onError === 'function') onError(err)
      return
    }
    throw err
  }

  const key = `upload-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
  const controller = new AbortController()
  uploadControllers.set(key, controller)

  const uploadTitle = props.hostLabel
    ? `${t('sftp.uploading')} → ${props.hostLabel}`
    : t('sftp.uploading')

  createUploadTask(key, { title: uploadTitle, fileName: remoteFileName })

  try {
    await uploadFile(props.hostId, currentPath.value, file, (event) => {
        if (cancelledUploads.has(key)) return

        if (event.type === 'complete') {
          updateUploadTask(key, { status: 'done', percent: 100, speed: '' })
          return
        }

        updateUploadTask(key, {
          status: 'uploading',
          percent: event.percent || 0,
          speed: event.speed || '',
          written: event.written || 0,
          total: event.total || 0,
        })
    }, controller.signal, { fileName: remoteFileName })
    
    uploadControllers.delete(key)
    cancelledUploads.delete(key)
    updateUploadTask(key, { status: 'done', percent: 100, speed: '' })
    message.success(t('sftp.uploadSuccess', { name: remoteFileName }))
    dismissUploadTask(key)

    loadFiles()
    // 安全调用回调函数
    if (typeof onSuccess === 'function') {
      onSuccess()
    }
  } catch (error) {
    uploadControllers.delete(key)
    // Check for abort/cancel (native fetch throws AbortError)
    if (
      cancelledUploads.has(key)
      || error.name === 'AbortError'
      || error.name === 'CanceledError'
      || error.code === 'ERR_CANCELED'
      || error.message === 'UPLOAD_CANCELLED_BY_USER'
    ) {
        cancelledUploads.delete(key)
        if (error.message !== 'UPLOAD_CANCELLED_BY_USER') {
          updateUploadTask(key, { status: 'cancelled', errorMessage: '' })
          dismissUploadTask(key)
        }
        if (typeof onError === 'function') {
          onError(error)
        }
        return
    }
    updateUploadTask(key, {
      status: 'error',
      errorMessage: error.message || t('sftp.uploadFailed'),
    })
    message.error(error.message || t('sftp.uploadFailed'))
    dismissUploadTask(key, 5000)
    if (typeof onError === 'function') {
      onError(error)
    }
  }
}


const download = async (name) => {
  const fullPath = currentPath.value === '.' ? name : `${currentPath.value}/${name}`
  const key = `download-${Date.now()}`
  
  try {
     notification.open({
        key,
        message: 'Downloading...',
        description: h('div', [
            h(Progress, { percent: 0, status: 'active', size: 'small' }),
            h('div', { style: 'margin-top: 8px' }, name)
        ]),
        duration: 0,
        placement: 'bottomRight'
    })

    const startTime = Date.now()
    const fileRecord = files.value.find(f => f.name === name)
    const fileSize = fileRecord ? fileRecord.size : 0

    const response = await downloadFile(props.hostId, fullPath, (percent) => {
        const elapsed = (Date.now() - startTime) / 1000
        let speedStr = ''
        if (elapsed > 0 && fileSize > 0) {
            const downloaded = (percent / 100) * fileSize
            const speed = downloaded / elapsed
            speedStr = speed > 1024 * 1024 
                ? (speed / (1024 * 1024)).toFixed(2) + ' MB/s' 
                : (speed / 1024).toFixed(2) + ' KB/s'
        }
        
        notification.open({
            key,
            message: t('sftp.downloading'),
            description: h('div', [
                h(Progress, { percent: percent, status: 'active', size: 'small' }),
                h('div', { style: 'display: flex; justify-content: space-between; margin-top: 8px' }, [
                    h('span', { style: 'color: #8c8c8c; font-size: 12px' }, name),
                    h('span', { style: 'color: #1890ff; font-weight: 500; font-size: 12px' }, speedStr)
                ])
            ]),
            duration: 0,
            placement: 'bottomRight'
        })
    })

    // Create blobs and trigger downloads
    const url = window.URL.createObjectURL(response)
    const link = document.createElement('a')
    link.href = url
    link.setAttribute('download', name)
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    window.URL.revokeObjectURL(url)

    notification.success({
        key,
        message: t('sftp.downloadComplete'),
        description: t('sftp.downloadSuccess', { name }),
        duration: 3,
        placement: 'bottomRight'
    })
  } catch (error) {
      console.error(error)
      notification.error({
        key,
        message: t('sftp.downloadFailed'),
        description: t('sftp.downloadFailed'),
        duration: 4.5,
        placement: 'bottomRight'
    })
  }
}

const remove = async (name) => {
  const fullPath = currentPath.value === '.' ? name : `${currentPath.value}/${name}`
  try {
    await deleteFile(props.hostId, fullPath)
    message.success(t('sftp.deleted'))
    loadFiles()
  } catch (error) {
    console.error('Failed to delete:', error)
  }
}

// Clipboard Actions
const handleBulkCut = () => {
  const paths = selectedRowKeys.value.map(name => currentPath.value === '.' ? name : `${currentPath.value}/${name}`)
  sftpStore.setClipboard(props.hostId, paths, 'cut')
  message.info(t('sftp.cutCount', { count: paths.length }))
}

const handleBulkCopy = () => {
  const paths = selectedRowKeys.value.map(name => currentPath.value === '.' ? name : `${currentPath.value}/${name}`)
  sftpStore.setClipboard(props.hostId, paths, 'copy')
  message.info(t('sftp.copyCount', { count: paths.length }))
}

const cut = (name) => {
    const fullPath = currentPath.value === '.' ? name : `${currentPath.value}/${name}`
    sftpStore.setClipboard(props.hostId, [fullPath], 'cut')
    message.info(t('sftp.cutMsg', { name }))
}

const copy = (name) => {
    const fullPath = currentPath.value === '.' ? name : `${currentPath.value}/${name}`
    sftpStore.setClipboard(props.hostId, [fullPath], 'copy')
    message.info(t('sftp.copyMsg', { name }))
}

const paste = async () => {
    const { hostId: srcHostId, paths, type } = sftpStore.clipboard
    if (!paths.length) return

    try {
        if (srcHostId === props.hostId) {
            // Same host: use pasteFile API (rename or local recursive copy)
            for (const source of paths) {
                await pasteFile(props.hostId, source, currentPath.value, type)
            }
        } else {
            // Cross host: use transferFile API
            for (const source of paths) {
                const name = source.split('/').pop()
                let destFileName = name
                try {
                    destFileName = await resolveRemoteUploadName(name)
                } catch (err) {
                    if (err.message === 'UPLOAD_CANCELLED_BY_USER') {
                        continue
                    }
                    throw err
                }
                const transferOpts = { destFileName }
                const key = `transfer-${Date.now()}`
                
                notification.open({
                    key,
                    message: t('sftp.transferring'),
                    description: h('div', [
                        h(Progress, { percent: 0, status: 'active', size: 'small' }),
                        h('div', { style: 'display: flex; justify-content: space-between; align-items: center; margin-top: 8px' }, [
                            h('span', { style: 'color: #8c8c8c; font-size: 12px' }, name),
                            h(Spin, { size: 'small' })
                        ])
                    ]),
                    duration: 0,
                    placement: 'bottomRight'
                })

                try {
                    await transferFile(srcHostId, props.hostId, source, currentPath.value, (event) => {
                        if (event.type === 'progress') {
                            notification.open({
                                key,
                                message: t('sftp.transferring'),
                                description: h('div', [
                                    h(Progress, { percent: event.percent || 0, status: 'active', size: 'small' }),
                                    h('div', { style: 'display: flex; justify-content: space-between; align-items: center; margin-top: 8px' }, [
                                        h('span', { style: 'color: #8c8c8c; font-size: 12px' }, name),
                                        h('span', { style: 'color: #1890ff; font-weight: 500; font-size: 12px' }, event.speed || '')
                                    ])
                                ]),
                                duration: 0,
                                placement: 'bottomRight'
                            })
                        }
                    }, type, transferOpts)
                    notification.success({
                        key,
                        message: t('sftp.transferComplete'),
                        description: t('sftp.transferSuccess', { name: destFileName }),
                        duration: 3,
                        placement: 'bottomRight'
                    })
                } catch (err) {
                   notification.error({
                       key,
                       message: t('sftp.transferFailed'),
                       description: err.message,
                       duration: 4.5,
                       placement: 'bottomRight'
                   })
                   throw err // Stop bulk paste if one fails? Or continue? For now stop.
                }
            }
        }
        
        message.success(t('sftp.pasted'))
        loadFiles()
        if (type === 'cut') {
            sftpStore.clearClipboard()
        }
    } catch (error) {
        message.error(t('sftp.failedToPaste') + ': ' + (error.response?.data?.error || error.message))
    }
}

const openRename = (record) => {
    renamingFile.value = record
    renameName.value = record.name
    renameVisible.value = true
}

const handleRename = async () => {
    if (!renameName.value) return
    const oldPath = currentPath.value === '.' ? renamingFile.value.name : `${currentPath.value}/${renamingFile.value.name}`
    const newPath = currentPath.value === '.' ? renameName.value : `${currentPath.value}/${renameName.value}`
    
    try {
        await renameFile(props.hostId, oldPath, newPath)
        message.success(t('sftp.renamed'))
        renameVisible.value = false
        loadFiles()
    } catch (error) {
        message.error(t('sftp.failedToRename') + ': ' + (error.response?.data?.error || error.message))
    }
}

const openCreate = (type) => {
    createType.value = type
    createName.value = ''
    createVisible.value = true
}

const handleCreate = async () => {
    if (!createName.value) return
    const fullPath = currentPath.value === '.' ? createName.value : `${currentPath.value}/${createName.value}`
    
    try {
        if (createType.value === 'folder') {
            await createDirectory(props.hostId, fullPath)
        } else {
            await createFile(props.hostId, fullPath)
        }
        message.success(t('sftp.created', { type: createType.value }))
        createVisible.value = false
        loadFiles()
    } catch (error) {
        message.error(t('sftp.failedToCreate', { type: createType.value }) + ': ' + (error.response?.data?.error || error.message))
    }
}

const openEditor = (record) => {
    const fullPath = currentPath.value === '.' ? record.name : `${currentPath.value}/${record.name}`
    editingFile.value = {
        path: fullPath,
        name: record.name
    }
    editorVisible.value = true
}

const onEditorSaved = () => {
    loadFiles()
}

const formatSize = (bytes) => {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

const formatModTime = (modTime) => {
  if (!modTime) return '-'
  const d = dayjs(modTime)
  if (!d.isValid() || d.year() <= 1970) return '-'
  return d.format('YYYY-MM-DD HH:mm:ss')
}

watch(() => props.hostId, () => {
  resetPathHistory()
  currentPath.value = '.'
  selectedRowKeys.value = []
  if (props.visible) {
    loadFiles()
  }
})

watch(() => props.visible, (newVal) => {
  if (newVal && files.value.length === 0) {
    loadFiles()
  }
})

onMounted(() => {
  if (props.visible) {
    loadFiles()
  }
  // Add keyboard event listener
  window.addEventListener('keydown', handleKeyDown)
})

onUnmounted(() => {
  window.removeEventListener('keydown', handleKeyDown)
  uploadDismissTimers.forEach((timer) => clearTimeout(timer))
  uploadDismissTimers.clear()
  cancelDirSizeJobs()
  if (listAbortController) {
    listAbortController.abort()
    listAbortController = null
  }
})

const handleTransfer = (record) => {
    const fullPath = buildRemotePath(currentPath.value, record.name)
    emit('transfer', {
        name: record.name,
        fullPath,
        isDir: record.is_dir,
        size: record.is_dir ? null : record.size
    })
}

// Selection Management Functions
const selectAll = () => {
  selectedRowKeys.value = files.value.map(f => f.name)
}

const invertSelection = () => {
  const allKeys = files.value.map(f => f.name)
  selectedRowKeys.value = allKeys.filter(key => !selectedRowKeys.value.includes(key))
}

const clearSelection = () => {
  selectedRowKeys.value = []
}

// Bulk Download
const handleBulkDownload = async () => {
  if (selectedRowKeys.value.length === 0) return
  
  // For multiple files, download as zip would be better
  // For now, download sequentially with notifications
  for (const name of selectedRowKeys.value) {
    const record = files.value.find(f => f.name === name)
    if (record) {
      await download(record.name)
    }
  }
}

// Bulk Delete
const handleBulkDelete = async () => {
  if (selectedRowKeys.value.length === 0) return
  
  Modal.confirm({
    title: t('sftp.deleteConfirm'),
    content: t('sftp.deleteSelectedConfirm', { count: selectedRowKeys.value.length }),
    okText: t('common.ok'),
    cancelText: t('common.cancel'),
    onOk: async () => {
      try {
        for (const name of selectedRowKeys.value) {
          const fullPath = currentPath.value === '.' ? name : `${currentPath.value}/${name}`
          await deleteFile(props.hostId, fullPath)
        }
        message.success(t('sftp.deleted'))
        selectedRowKeys.value = []
        loadFiles()
      } catch (error) {
        message.error(t('sftp.failedToDelete') + ': ' + (error.response?.data?.error || error.message))
      }
    }
  })
}

// Show Properties
const showProperties = async () => {
  if (selectedRowKeys.value.length === 0) return
  
  // Calculate total size and count
  let totalSize = 0
  let fileCount = 0
  let dirCount = 0
  
  for (const name of selectedRowKeys.value) {
    const record = files.value.find(f => f.name === name)
    if (record) {
      if (record.is_dir) {
        dirCount++
        if (record.size && record.size > 0) {
          totalSize += record.size
        }
      } else {
        fileCount++
        totalSize += record.size || 0
      }
    }
  }
  
  const selectedNames = selectedRowKeys.value.join(', ')
  
  Modal.info({
    title: t('sftp.properties'),
    content: h('div', { style: 'line-height: 2' }, [
      h('div', [h('strong', t('sftp.selectedFiles')), h('span', `: ${selectedRowKeys.value.length}`)]),
      h('div', [h('strong', t('sftp.files')), h('span', `: ${fileCount}`)]),
      h('div', [h('strong', t('sftp.directories')), h('span', `: ${dirCount}`)]),
      h('div', [h('strong', t('sftp.totalSize')), h('span', `: ${formatSize(totalSize)}`)]),
      h('div', { style: 'margin-top: 12px, font-size: 12px, color: #888' }, [
        h('div', { style: 'max-height: 100px, overflow-y: auto' }, [
          selectedNames.split(', ').map(name => h('div', name))
        ])
      ])
    ]),
    okText: t('common.ok'),
    width: 500
  })
}

// Drag and Drop Upload Support
const dragOverTimer = ref(null)

const handleDrop = async (e) => {
  e.preventDefault()
  e.stopPropagation()
  
  // Remove drag over style
  const browser = e.currentTarget
  browser.classList.remove('drag-over')
  
  const files = e.dataTransfer.files
  if (files.length === 0) return
  
  // Upload all dropped files
  for (let i = 0; i < files.length; i++) {
    await handleUpload({
      file: files[i],
      onProgress: (percent) => {
        console.log(`Upload progress: ${percent}%`)
      }
    })
  }
}

const handleDragOver = (e) => {
  e.preventDefault()
  e.stopPropagation()
  
  // Add drag over style
  const browser = e.currentTarget
  browser.classList.add('drag-over')
  
  // Clear any existing timer
  if (dragOverTimer.value) {
    clearTimeout(dragOverTimer.value)
  }
  
  // Remove drag over style after a delay
  dragOverTimer.value = setTimeout(() => {
    browser.classList.remove('drag-over')
  }, 500)
}

const handleDragLeave = (e) => {
  e.preventDefault()
  e.stopPropagation()
  
  const browser = e.currentTarget
  browser.classList.remove('drag-over')
  
  if (dragOverTimer.value) {
    clearTimeout(dragOverTimer.value)
  }
}

// Keyboard Shortcuts
const handleKeyDown = (e) => {
  // Only handle shortcuts when not in input/edit mode
  if (pathInputVisible.value || renameVisible.value || createVisible.value) {
    return
  }
  
  // Ctrl/Cmd + A: Select All
  if ((e.ctrlKey || e.metaKey) && e.key === 'a') {
    e.preventDefault()
    selectAll()
  }
  
  // Ctrl/Cmd + C: Copy
  if ((e.ctrlKey || e.metaKey) && e.key === 'c' && selectedRowKeys.value.length > 0) {
    e.preventDefault()
    handleBulkCopy()
  }
  
  // Ctrl/Cmd + X: Cut
  if ((e.ctrlKey || e.metaKey) && e.key === 'x' && selectedRowKeys.value.length > 0) {
    e.preventDefault()
    handleBulkCut()
  }
  
  // Ctrl/Cmd + V: Paste
  if ((e.ctrlKey || e.metaKey) && e.key === 'v' && sftpStore.clipboard.paths.length > 0) {
    e.preventDefault()
    paste()
  }
  
  // Delete: Delete selected files
  if (e.key === 'Delete' && selectedRowKeys.value.length > 0) {
    e.preventDefault()
    handleBulkDelete()
  }
  
  // Escape: Clear selection
  if (e.key === 'Escape' && selectedRowKeys.value.length > 0) {
    e.preventDefault()
    clearSelection()
  }

  // Alt + Left: Back
  if (e.altKey && e.key === 'ArrowLeft') {
    e.preventDefault()
    goBack()
  }

  // Alt + Right: Forward
  if (e.altKey && e.key === 'ArrowRight') {
    e.preventDefault()
    goForward()
  }

  // Alt + Up: Parent directory
  if (e.altKey && e.key === 'ArrowUp') {
    e.preventDefault()
    goUp()
  }

  // Backspace: Back (when nothing selected)
  if (e.key === 'Backspace' && selectedRowKeys.value.length === 0 && canGoBack.value) {
    e.preventDefault()
    goBack()
  }
}

defineExpose({
    refresh: loadFiles,
    currentPath,
    getCurrentPath: () => currentPath.value,
    getFiles: () => files.value,
})
</script>

<style scoped>
.sftp-browser {
  display: flex;
  flex-direction: column;
  height: 100%;
  transition: all 0.3s ease;
}

.sftp-browser.drag-over {
  background: rgba(24, 144, 255, 0.1);
  border: 2px dashed #1890ff;
}

.sftp-browser.drag-over .browser-content {
  pointer-events: none;
}

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
  flex: 1;
  min-width: 0;
}

.browser-content {
  flex: 1;
  overflow: hidden;
  min-height: 0; /* 关键：允许 flex 子元素收缩以正确显示滚动条 */
  position: relative;
}

.browser-content.drag-over::after {
  content: attr(data-drag-text);
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(24, 144, 255, 0.1);
  border: 2px dashed #1890ff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  color: #1890ff;
  font-weight: 500;
  z-index: 10;
  pointer-events: none;
}

:deep(.ant-table-cell) {
  padding: 4px 8px !important;
}

/* Force hide horizontal scrollbar */
:deep(.ant-table-body) {
  overflow-x: hidden !important;
}
:deep(.ant-table-content) {
  overflow-x: hidden !important;
}

.sftp-context-menu {
  position: fixed;
  z-index: 9999;
  background: #fff;
  border-radius: 8px;
  box-shadow: 0 6px 16px 0 rgba(0, 0, 0, 0.08), 0 3px 6px -4px rgba(0, 0, 0, 0.12), 0 9px 28px 8px rgba(0, 0, 0, 0.05);
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
/* Modal teleports to body — dark styles must be global */
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
