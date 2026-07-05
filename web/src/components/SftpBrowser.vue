<template>
  <div
    ref="browserRootRef"
    class="sftp-browser"
    tabindex="0"
    @mousedown="focusBrowserForShortcuts"
    @drop="handleDrop"
    @dragover="handleDragOver"
    @dragleave="handleDragLeave"
  >
    <SftpBrowserHeader
      ref="browserHeaderRef"
      :can-go-back="canGoBack"
      :can-go-forward="canGoForward"
      :can-go-up="canGoUp"
      :loading="loading"
      :clipboard-count="sftpStore.clipboard.paths.length"
      :selected-count="selectedRowKeys.length"
      :path-input-visible="pathInputVisible"
      :path-parts="pathParts"
      v-model:path-input-value="pathInputValue"
      :path-autocomplete-options="pathAutocompleteOptions"
      :path-input-loading="pathInputLoading"
      :path-input-error="pathInputError"
      :is-dark="themeStore.isDark"
      :history-list="historyList"
      :favorites-list="favoritesList"
      @back="goBack"
      @forward="goForward"
      @up="goUp"
      @refresh="refresh"
      @paste="paste"
      @bulk-cut="handleBulkCut"
      @bulk-copy="handleBulkCopy"
      @open-create="openCreate"
      @upload="handleUpload"
      @select-all="selectAll"
      @invert-selection="invertSelection"
      @clear-selection="clearSelection"
      @bulk-download="handleBulkDownload"
      @bulk-delete="handleBulkDelete"
      @properties="showProperties"
      @show-path-input="showPathInput"
      @navigate="navigateTo"
      @path-search="onPathInputSearch"
      @path-select="onPathAutocompleteSelect"
      @path-enter="goToPath"
      @path-esc="hidePathInput"
      @path-blur="onPathInputBlur"
      @click-history="handleHistoryClick"
      @click-favorite="handleFavoriteClick"
      @add-favorite="addCurrentToFavorites"
      @remove-favorite="removeFavorite"
    />

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
      v-if="editorMounted"
      ref="fileEditorRef"
      :host-id="hostId"
      :panel-visible="editorPanelVisible"
      @saved="onEditorSaved"
    />

    <SftpBrowserOverlays
      ref="browserOverlaysRef"
      v-model:rename-visible="renameVisible"
      v-model:rename-name="renameName"
      v-model:create-visible="createVisible"
      v-model:create-name="createName"
      :create-type="createType"
      v-model:upload-conflict-open="uploadConflictOpen"
      :upload-conflict-name="uploadConflictName"
      :upload-conflict-is-dir="uploadConflictIsDir"
      :upload-conflict-wrap-class="uploadConflictWrapClass"
      v-model:preview-visible="previewVisible"
      :preview-name="previewName"
      :preview-loading="previewLoading"
      :preview-type="previewType"
      :preview-src="previewSrc"
      :image-preview-visible="imagePreviewVisible"
      :context-menu-visible="contextMenuVisible"
      :context-menu-record="contextMenuRecord"
      :context-menu-position="contextMenuPosition"
      :clipboard-count="sftpStore.clipboard.paths.length"
      :enable-transfer="enableTransfer"
      :transfer-target-label="transferTargetLabel"
      :is-dark="themeStore.isDark"
      @rename-ok="handleRename"
      @create-ok="handleCreate"
      @upload-conflict-cancel="onUploadConflictCancel"
      @upload-conflict-keep-both="onUploadConflictKeepBoth"
      @upload-conflict-overwrite="onUploadConflictOverwrite"
      @preview-close="closePreview"
      @image-preview-visible="onImagePreviewVisible"
      @context-menu-close="closeContextMenu"
      @refresh="refresh"
      @open-create="openCreate"
      @paste="paste"
      @context-open="handleContextMenuOpen"
      @context-download="download"
      @context-transfer="handleTransfer"
      @context-cut="cut"
      @context-copy="copy"
      @context-rename="openRename"
      @context-delete="remove"
    />

    <SftpUploadProgressDock
      :tasks="uploadTaskList"
      :expanded="uploadPanelExpanded"
      :panel-title="uploadPanelTitle"
      :circle-tooltip="uploadCircleTooltip"
      :aggregate="aggregateUpload"
      :aggregate-status="aggregateUploadStatus"
      :ring-size="uploadRingSize"
      :ring-radius="uploadRingRadius"
      :ring-center="uploadRingCenter"
      :ring-circumference="uploadRingCircumference"
      :ring-dash-offset="uploadRingDashOffset"
      :is-dark="themeStore.isDark"
      @hide-panel="hideUploadPanel"
      @show-panel="showUploadPanel"
      @cancel="cancelUpload"
    />

  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch, h, reactive, nextTick, defineAsyncComponent } from 'vue'
import { useRoute } from 'vue-router'
import { message, notification, Progress, Button, Spin, Modal } from 'ant-design-vue'
import { 
  FolderFilled, 
  FileOutlined, 
  DownloadOutlined, 
  DeleteOutlined,
  EditOutlined,
  MoreOutlined,
  FolderOpenOutlined,
  CloudDownloadOutlined,
  EyeOutlined,
  SwapOutlined,
  AimOutlined
} from '@ant-design/icons-vue'
import { listFiles, uploadFile, downloadFile, deleteFile, renameFile, pasteFile, createDirectory, createFile, getDirSizes, transferFile, getPathBookmarks, savePathBookmarks } from '../api/sftp'
import { fetchWithAuth } from '../api/fetchWithAuth'
import { apiUrl } from '../utils/apiBase'
import { useI18n } from 'vue-i18n'
const FileEditor = defineAsyncComponent(() => import('./FileEditor.vue'))
import SftpBrowserHeader from './SftpBrowserHeader.vue'
import SftpBrowserOverlays from './SftpBrowserOverlays.vue'
import SftpUploadProgressDock from './SftpUploadProgressDock.vue'
import { useSftpStore } from '../stores/sftp'
import { useSSHStore } from '../stores/ssh'
import { useThemeStore } from '../stores/theme'
import '../styles/sftp-progress-dock.css'
import { hasNameConflict, generateKeepBothName as makeKeepBothName } from '../utils/sftpConflict'
import { buildRemotePath, splitPathForCompletion, listAncestorPaths, normalizeRemotePathInput } from '../utils/sftpPath'
import dayjs from 'dayjs'

const { t } = useI18n()
const route = useRoute()
const sftpStore = useSftpStore()
const sshStore = useSSHStore()
const themeStore = useThemeStore()
const browserRootRef = ref(null)
const props = defineProps({
  hostId: {
    type: [String, Number],
    required: true
  },
  visible: {
    type: Boolean,
    default: false
  },
  /** Terminal tab id (Terminal view); editor only shows for the active tab. */
  terminalId: {
    type: String,
    default: null,
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
  },
  /** Where this browser lives: terminal SFTP vs file-transfer page (editors are isolated per scope). */
  editorScope: {
    type: String,
    default: 'terminal',
    validator: (v) => v === 'terminal' || v === 'transfer',
  },
})

const emit = defineEmits(['transfer', 'selection-change', 'upload-busy-change'])

const editorPanelVisible = computed(() => {
  if (!props.visible) return false
  if (props.editorScope === 'transfer') {
    return route.name === 'FileTransfer'
  }
  if (route.name !== 'Terminal') return false
  if (!props.terminalId) return false
  return String(sshStore.currentTerminalId) === String(props.terminalId)
})

const browserInteractionActive = computed(() => {
  if (!props.visible) return false
  if (props.editorScope === 'transfer') {
    return route.name === 'FileTransfer'
  }
  if (route.name !== 'Terminal') return false
  if (!props.terminalId) return false
  return String(sshStore.currentTerminalId) === String(props.terminalId)
})

/** Load Monaco editor chunk only when SFTP panel is shown or a file is opened. */
const editorMounted = ref(false)
watch(editorPanelVisible, (v) => {
  if (v) editorMounted.value = true
}, { immediate: true })

const waitForFileEditor = async () => {
  editorMounted.value = true
  for (let i = 0; i < 60; i++) {
    await nextTick()
    if (fileEditorRef.value?.openFile) return true
    await new Promise((r) => setTimeout(r, 50))
  }
  return false
}

const currentPath = ref('.')
const files = ref([])
const loading = ref(false)
const historyList = ref([])
const favoritesList = ref([])
let bookmarksRequestId = 0
let bookmarksSaveTimer = null

const currentPathStorageKey = computed(() => {
  if (!props.hostId) return ''
  const scopeKey = props.editorScope === 'terminal' && props.terminalId
    ? `terminal_${props.terminalId}`
    : props.editorScope
  return `sftp_current_path_${scopeKey}_${props.hostId}`
})

const rememberCurrentPath = (path) => {
  if (!currentPathStorageKey.value || !path || path === '.') return
  sessionStorage.setItem(currentPathStorageKey.value, path)
}

const restoreRememberedPath = () => {
  if (!currentPathStorageKey.value) return '.'
  return sessionStorage.getItem(currentPathStorageKey.value) || '.'
}

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
  const queue = [...dirNames].map((name) => ({
    name,
    path: buildRemotePath(cwd, name),
  }))
  const workerCount = Math.min(DIR_SIZE_CONCURRENCY, queue.length)
  if (workerCount === 0) return

  const worker = async () => {
    while (queue.length > 0) {
      if (signal.aborted || sessionId !== dirSizeSessionId) return
      const batch = queue.splice(0, 20)
      try {
        const res = await getDirSizes(hostId, batch.map((item) => item.path), { signal })
        if (signal.aborted || sessionId !== dirSizeSessionId) return
        const sizes = res?.sizes || {}
        for (const item of batch) {
          const result = sizes[item.path]
          const size = result && result.size !== undefined ? result.size : -1
          applyDirSize(item.name, size, sessionId, cwd)
        }
      } catch (error) {
        if (error?.code === 'ERR_CANCELED' || error?.name === 'CanceledError') return
        for (const item of batch) {
          applyDirSize(item.name, -1, sessionId, cwd)
        }
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

const navigateToPath = async (path, { recordHistory = true } = {}) => {
  if (loading.value) return false
  const target = normalizeRemotePathInput(path || '/', '/')
  if (target === currentPath.value) return true
  const previousPath = currentPath.value
  currentPath.value = target
  const loaded = await loadFiles()
  if (!loaded) {
    currentPath.value = previousPath
    return false
  }
  if (recordHistory && !skipHistoryRecord.value) {
    const historyTarget = currentPath.value
    let stack = [...pathHistoryStack.value]
    const idx = pathHistoryIndex.value
    if (idx >= 0 && idx < stack.length - 1) {
      stack = stack.slice(0, idx + 1)
    }
    if (stack.length === 0 || stack[stack.length - 1] !== historyTarget) {
      stack.push(historyTarget)
    }
    pathHistoryStack.value = stack
    pathHistoryIndex.value = stack.length - 1
  }
  return true
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

// 直达路径（带路径补全）
const pathInputVisible = ref(false)
const pathInputValue = ref('')
const browserHeaderRef = ref(null)
const browserOverlaysRef = ref(null)
const pathAutocompleteOptions = ref([])
const pathInputLoading = ref(false)
const pathInputError = ref('')
const pathCompleteCache = new Map()
let pathCompleteTimer = null
let pathCompleteAbort = null
let pathCompleteRequestId = 0

const normalizeListCwd = (path) => {
  if (!path || path === '.') return '.'
  return path
}

const normalizeResolvedCwd = (requestedPath, resolvedPath) => {
  const resolved = (resolvedPath || '').trim()
  if (!resolved) return requestedPath || '.'
  if (!requestedPath?.startsWith('/')) return resolved
  if (resolved === '/') return '/'
  if (resolved === '.') return requestedPath.replace(/\/+$/, '') || '/'
  if (resolved.startsWith('/')) return resolved
  return `/${resolved.replace(/^\/+/, '')}`
}

const extractDirNamesFromList = (data) => {
  const entries = data?.files ?? (Array.isArray(data) ? data : [])
  return entries.filter((f) => f.is_dir).map((f) => f.name)
}

const isSameListParent = (parent, cwd) => {
  const p = normalizeListCwd(parent)
  const c = normalizeListCwd(cwd)
  return p === c
}

const makePathOption = (path, kind, hint) => ({
  value: path,
  label: path,
  kind,
  hint,
})

const buildStaticPathSuggestions = (typed) => {
  const needle = normalizeRemotePathInput(typed, '').toLowerCase()
  const seen = new Set()
  const out = []

  const add = (path, kind, hint) => {
    if (!path || seen.has(path)) return
    if (needle && !path.toLowerCase().startsWith(needle)) return
    seen.add(path)
    out.push(makePathOption(path, kind, hint))
  }

  for (const p of pathHistoryStack.value) {
    add(p, 'history', t('sftp.pathSuggestionHistory'))
  }
  for (const p of listAncestorPaths(currentPath.value)) {
    const displayPath = p === '.' ? '/' : p
    const kind = displayPath === (currentPath.value === '.' ? '/' : currentPath.value)
      ? 'current'
      : 'ancestor'
    add(displayPath, kind, kind === 'current' ? t('sftp.pathSuggestionCurrent') : t('sftp.pathSuggestionAncestor'))
  }

  return out
}

const buildDirSuggestions = (parent, prefix, dirNames) => {
  const lowerPrefix = prefix.toLowerCase()
  const seen = new Set()
  const out = []

  for (const name of dirNames) {
    if (prefix && !name.toLowerCase().startsWith(lowerPrefix)) continue
    const full = buildRemotePath(parent, name)
    if (seen.has(full)) continue
    seen.add(full)
    out.push(makePathOption(full, 'directory', t('sftp.pathSuggestionDirectory')))
  }

  if (!prefix) {
    const parentDisplay = parent === '.' ? '/' : parent
    if (!seen.has(parentDisplay)) {
      out.unshift(makePathOption(parentDisplay, 'current', t('sftp.pathSuggestionCurrent')))
    }
  }

  return out
}

const mergePathOptions = (...groups) => {
  const seen = new Set()
  const merged = []
  for (const group of groups) {
    for (const opt of group) {
      if (!opt?.value || seen.has(opt.value)) continue
      seen.add(opt.value)
      merged.push(opt)
    }
  }
  return merged.slice(0, 30)
}

const fetchDirNamesForParent = async (parent, requestId) => {
  const listPath = normalizeListCwd(parent)
  const cached = pathCompleteCache.get(listPath)
  if (cached) return cached

  if (pathCompleteAbort) {
    pathCompleteAbort.abort()
  }
  pathCompleteAbort = new AbortController()
  const data = await listFiles(props.hostId, listPath, { signal: pathCompleteAbort.signal })
  if (requestId !== pathCompleteRequestId) return []

  const names = extractDirNamesFromList(data)
  pathCompleteCache.set(listPath, names)
  return names
}

const refreshPathAutocomplete = async (input) => {
  if (!pathInputVisible.value || !props.hostId) return

  const typed = (input ?? pathInputValue.value).trim()
  pathInputError.value = ''
  const requestId = ++pathCompleteRequestId
  const staticOpts = buildStaticPathSuggestions(typed)
  const { parent, prefix } = splitPathForCompletion(
    typed || (currentPath.value === '.' ? '/' : currentPath.value),
    currentPath.value,
  )

  let dirOpts = []
  if (isSameListParent(parent, currentPath.value)) {
    if (pathCompleteAbort) {
      pathCompleteAbort.abort()
      pathCompleteAbort = null
    }
    pathInputLoading.value = false
    const dirNames = files.value.filter((f) => f.is_dir).map((f) => f.name)
    dirOpts = buildDirSuggestions(parent, prefix, dirNames)
  } else {
    pathInputLoading.value = true
    try {
      const dirNames = await fetchDirNamesForParent(parent, requestId)
      if (requestId === pathCompleteRequestId) {
        dirOpts = buildDirSuggestions(parent, prefix, dirNames)
      }
    } catch (error) {
      if (error?.code === 'ERR_CANCELED' || error?.name === 'CanceledError') return
      pathInputError.value = t('sftp.pathAutocompleteFailed')
      console.warn('Path autocomplete list failed:', error)
    } finally {
      if (requestId === pathCompleteRequestId) {
        pathInputLoading.value = false
      }
    }
  }

  pathAutocompleteOptions.value = mergePathOptions(staticOpts, dirOpts)
}

const onPathInputSearch = (value) => {
  pathInputError.value = ''
  if (pathCompleteTimer) clearTimeout(pathCompleteTimer)
  pathCompleteTimer = setTimeout(() => {
    refreshPathAutocomplete(value)
  }, 200)
}

const isFocusInsidePathInput = () => {
  const active = document.activeElement
  if (!active) return false
  const wrapper = document.querySelector('.path-input-wrapper')
  if (wrapper && wrapper.contains(active)) return true
  // Clicking an option inside the autocomplete dropdown also counts as "still interacting".
  if (typeof active.closest === 'function' && active.closest('.ant-select-dropdown')) return true
  return false
}

const onPathInputBlur = () => {
  // Defer so any synchronous `select` from the dropdown can refocus the input first.
  setTimeout(() => {
    if (!pathInputVisible.value) return
    if (isFocusInsidePathInput()) return
    hidePathInput()
  }, 150)
}

const isEditableEventTarget = (target) => {
  const tag = target?.tagName?.toLowerCase()
  return tag === 'input' || tag === 'textarea' || tag === 'select' || target?.isContentEditable
}

const focusBrowserForShortcuts = (event) => {
  if (!browserInteractionActive.value) return
  if (isEditableEventTarget(event.target)) return
  browserRootRef.value?.focus?.({ preventScroll: true })
}

const isShortcutTargetInsideBrowser = (target) => {
  const root = browserRootRef.value
  if (!root) return false
  if (target && root.contains(target)) return true
  const active = document.activeElement
  return !!active && root.contains(active)
}

const focusPathInput = () => {
  const el = browserHeaderRef.value?.pathInputRef
  if (el && typeof el.focus === 'function') {
    el.focus()
  }
  const wrapper = document.querySelector('.path-input-wrapper')
  const input = wrapper?.querySelector?.('input')
  input?.select?.()
}

const showPathInput = () => {
  pathInputError.value = ''
  pathInputValue.value = currentPath.value === '.' ? '/' : currentPath.value
  pathInputVisible.value = true
  nextTick(() => {
    focusPathInput()
    refreshPathAutocomplete(pathInputValue.value)
  })
}

const hidePathInput = () => {
  pathInputVisible.value = false
  pathAutocompleteOptions.value = []
  pathInputError.value = ''
  pathInputLoading.value = false
  if (pathCompleteTimer) {
    clearTimeout(pathCompleteTimer)
    pathCompleteTimer = null
  }
  if (pathCompleteAbort) {
    pathCompleteAbort.abort()
    pathCompleteAbort = null
  }
}

const navigateFromPathInput = async (value = pathInputValue.value) => {
  const target = normalizeRemotePathInput(value, '')
  if (!target) return
  const previousPath = currentPath.value
  pathInputError.value = ''
  pathInputLoading.value = true
  const ok = await navigateToPath(target)
  pathInputLoading.value = false
  if (ok) {
    hidePathInput()
    return
  }
  currentPath.value = previousPath
  pathInputValue.value = target
  pathInputVisible.value = true
  pathInputError.value = t('sftp.pathNavigateFailed')
  message.error(t('sftp.pathNavigateFailed'))
}

const onPathAutocompleteSelect = (value) => {
  pathInputValue.value = value
  navigateFromPathInput(value)
}

const goToPath = () => {
  navigateFromPathInput()
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

const fileEditorRef = ref(null)

// Right-click Context Menu Logic
const contextMenuVisible = ref(false)
const contextMenuRecord = ref(null)
const contextMenuPosition = ref({ x: 0, y: 0 })
const closeContextMenu = () => {
  contextMenuVisible.value = false
}

const onDocumentClick = (e) => {
  const menuEl = browserOverlaysRef.value?.contextMenuRef
  if (contextMenuVisible.value && menuEl && !menuEl.contains(e.target)) {
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
         onSelectChange([record.name])
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
let previewAbortController = null

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
    const fullPath = buildRemotePath(currentPath.value, name)
    
    previewName.value = name
    const type = getMediaType(name)
    previewType.value = type
    
    previewLoading.value = true
    if (previewAbortController) {
        previewAbortController.abort()
    }
    previewAbortController = new AbortController()
    
    // Reset src just in case
    if (previewSrc.value) {
        if (previewSrc.value.startsWith('blob:')) {
            window.URL.revokeObjectURL(previewSrc.value)
        }
        previewSrc.value = ''
    }

    try {
        const encodedPath = encodeURIComponent(fullPath)
        const response = await fetchWithAuth(apiUrl(`/sftp/download/${props.hostId}?path=${encodedPath}`), {
            signal: previewAbortController.signal,
        })
        if (!response.ok) {
            let errorMsg = t('sftp.downloadFailed')
            try {
                const data = await response.json()
                errorMsg = data.error || errorMsg
            } catch (err) {}
            throw new Error(errorMsg)
        }
        const blob = await response.blob()
        previewSrc.value = window.URL.createObjectURL(blob)
        
        if (type === 'image') {
            imagePreviewVisible.value = true
        } else {
            previewVisible.value = true
        }
    } catch (e) {
        if (e.name !== 'AbortError') {
            message.error(t('sftp.downloadFailed') + ': ' + e.message)
        }
        previewVisible.value = false
        imagePreviewVisible.value = false
    } finally {
        previewLoading.value = false
    }
}

const onImagePreviewVisible = (vis) => {
  imagePreviewVisible.value = vis
  if (!vis) closePreview()
}

const closePreview = () => {
    if (previewAbortController) {
        previewAbortController.abort()
        previewAbortController = null
    }
    previewVisible.value = false
    imagePreviewVisible.value = false
    
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
  if (!props.hostId) return false

  cancelDirSizeJobs()
  if (listAbortController) {
    listAbortController.abort()
  }
  listAbortController = new AbortController()
  const listSignal = listAbortController.signal
  const gen = ++listGeneration

  loading.value = true
  onSelectChange([]) // Reset selection on path change
  const cwdAtStart = currentPath.value

  try {
    const data = await listFiles(props.hostId, cwdAtStart, { signal: listSignal })
    if (listSignal.aborted || gen !== listGeneration) return false
    if (currentPath.value !== cwdAtStart) return false

    // Check if the path is a file
    if (data && data.is_file) {
      const filePath = data.cwd
      const parentPath = getParentPath(filePath)
      currentPath.value = parentPath
      
      // Load parent directory
      await loadFiles()
      
      const fileName = filePath.split('/').pop()
      const fileRecord = {
        name: fileName,
        is_dir: false,
        size: 0,
      }
      openFile(fileRecord)
      return true
    }

    // Handle new response format { files: [], cwd: '/...' }
    let resolvedCwd = cwdAtStart
    if (data && data.files) {
        files.value = data.files.map(f => ({ ...f, size: f.is_dir ? null : f.size }))
        if (data.cwd) {
            resolvedCwd = normalizeResolvedCwd(cwdAtStart, data.cwd)
            if (currentPath.value !== cwdAtStart) return false
            currentPath.value = resolvedCwd
            rememberCurrentPath(resolvedCwd)
            addToHistory(resolvedCwd)
            if (pathHistoryStack.value.length === 0) {
              pathHistoryStack.value = [resolvedCwd]
              pathHistoryIndex.value = 0
            }
        }
    } else if (Array.isArray(data)) {
        files.value = data.map(f => ({ ...f, size: f.is_dir ? null : f.size }))
        addToHistory(resolvedCwd)
    } else {
        files.value = []
    }

    // Refresh autocomplete cache for the freshly-loaded directory so newly
    // created / deleted / renamed entries show up in path suggestions.
    pathCompleteCache.set(
      resolvedCwd || '.',
      files.value.filter((f) => f.is_dir).map((f) => f.name),
    )

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
    return true
  } catch (error) {
    if (error?.code === 'ERR_CANCELED' || error?.name === 'CanceledError') return false
    console.error('Failed to list files:', error)
    return false
  } finally {
    if (gen === listGeneration) {
      loading.value = false
    }
  }
}

const loadFilesWithRememberedPath = async () => {
  const rememberedPath = restoreRememberedPath()
  currentPath.value = rememberedPath
  const loaded = await loadFiles()
  if (loaded || rememberedPath === '.') return loaded

  currentPath.value = '.'
  resetPathHistory()
  return loadFiles()
}

const refresh = () => {
  if (loading.value) return
  loadFiles()
}

const enterDir = (name) => {
  if (loading.value) return
  navigateToPath(buildRemotePath(currentPath.value, name))
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

const isUploadBusy = () =>
  uploadTaskList.value.some((t) => t.status === 'connecting' || t.status === 'uploading')

watch(
  () => uploadTaskList.value.map((t) => `${t.key}:${t.status}`).join(','),
  () => emit('upload-busy-change', isUploadBusy()),
  { immediate: true },
)

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

const createUploadTask = (key, { title, fileName, hostId, hostLabel }) => {
  uploadPanelExpanded.value = true
  uploadTasks[key] = {
    key,
    title,
    fileName,
    hostId,
    hostLabel,
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

const conflictQueue = []
let processingConflict = false

const processNextConflict = () => {
  if (processingConflict || conflictQueue.length === 0) return
  processingConflict = true
  const { name, resolve } = conflictQueue.shift()
  const entry = findDirEntry(name)
  uploadConflictName.value = name
  uploadConflictIsDir.value = !!entry?.is_dir
  uploadConflictResolver = (action) => {
    resolve(action)
    uploadConflictOpen.value = false
    processingConflict = false
    setTimeout(processNextConflict, 100)
  }
  uploadConflictOpen.value = true
}

const promptUploadConflict = (name) => {
  return new Promise((resolve) => {
    conflictQueue.push({ name, resolve })
    processNextConflict()
  })
}

const finishUploadConflict = (action) => {
  uploadConflictResolver?.(action)
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

const resolveRemoteConflictTarget = async (displayName) => {
  if (!hasUploadNameConflict(displayName)) {
    return { destFileName: displayName, overwrite: false }
  }
  const action = await promptUploadConflict(displayName)
  if (action === 'cancel') {
    throw new Error('UPLOAD_CANCELLED_BY_USER')
  }
  if (action === 'keepBoth') {
    return { destFileName: generateKeepBothName(displayName), overwrite: false }
  }
  return { destFileName: displayName, overwrite: true }
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

  createUploadTask(key, {
    title: uploadTitle,
    fileName: remoteFileName,
    hostId: props.hostId,
    hostLabel: props.hostLabel || `Host ${props.hostId}`,
  })

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
  const fullPath = buildRemotePath(currentPath.value, name)
  const key = `download-${Date.now()}`
  const controller = new AbortController()
  const fileRecord = files.value.find(f => f.name === name)
  const isDirectory = !!fileRecord?.is_dir
  const downloadName = isDirectory ? `${name}.tar` : name
  const openDownloadNotification = (percent = 0, speedStr = '', indeterminate = false) => {
    notification.open({
      key,
      message: isDirectory ? t('sftp.downloadingArchive') : t('sftp.downloading'),
      description: h('div', [
        h(Progress, {
          percent: indeterminate ? undefined : percent,
          status: 'active',
          size: 'small',
          showInfo: !indeterminate,
        }),
        h('div', { style: 'display: flex; justify-content: space-between; align-items: center; gap: 8px; margin-top: 8px' }, [
          h('span', { style: 'color: #8c8c8c; font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap' }, downloadName),
          h('span', { style: 'color: #1890ff; font-weight: 500; font-size: 12px; white-space: nowrap' }, speedStr),
        ]),
        h('div', { style: 'display: flex; justify-content: flex-end; margin-top: 8px' }, [
          h(Button, {
            size: 'small',
            onClick: () => controller.abort(),
          }, () => t('common.cancel')),
        ]),
      ]),
      duration: 0,
      placement: 'bottomRight'
    })
  }
  
  try {
    openDownloadNotification(0, '', isDirectory)

    const startTime = Date.now()
    const fileSize = !isDirectory && fileRecord ? fileRecord.size : 0

    const response = await downloadFile(props.hostId, fullPath, (percent, progress = {}) => {
        const elapsed = (Date.now() - startTime) / 1000
        let speedStr = ''
        if (elapsed > 0) {
            const downloaded = progress.loaded || ((percent / 100) * fileSize)
            const speed = downloaded / elapsed
            if (speed > 0) {
                speedStr = speed > 1024 * 1024 
                    ? (speed / (1024 * 1024)).toFixed(2) + ' MB/s' 
                    : (speed / 1024).toFixed(2) + ' KB/s'
            }
        }
        openDownloadNotification(percent, speedStr, !progress.computable)
    }, { signal: controller.signal })

    // Create blobs and trigger downloads
    const url = window.URL.createObjectURL(response)
    const link = document.createElement('a')
    link.href = url
    link.setAttribute('download', downloadName)
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    window.URL.revokeObjectURL(url)

    notification.success({
        key,
        message: t('sftp.downloadComplete'),
        description: t('sftp.downloadSuccess', { name: downloadName }),
        duration: 3,
        placement: 'bottomRight'
    })
  } catch (error) {
      if (error?.code === 'ERR_CANCELED' || error?.name === 'CanceledError' || error?.message === 'canceled') {
        notification.info({
          key,
          message: t('sftp.downloadCancelled'),
          description: downloadName,
          duration: 3,
          placement: 'bottomRight'
        })
        return
      }
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
  const fullPath = buildRemotePath(currentPath.value, name)
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
  const paths = selectedRowKeys.value.map(name => buildRemotePath(currentPath.value, name))
  sftpStore.setClipboard(props.hostId, paths, 'cut')
  message.info(t('sftp.cutCount', { count: paths.length }))
}

const handleBulkCopy = () => {
  const paths = selectedRowKeys.value.map(name => buildRemotePath(currentPath.value, name))
  sftpStore.setClipboard(props.hostId, paths, 'copy')
  message.info(t('sftp.copyCount', { count: paths.length }))
}

const cut = (name) => {
    const fullPath = buildRemotePath(currentPath.value, name)
    sftpStore.setClipboard(props.hostId, [fullPath], 'cut')
    message.info(t('sftp.cutMsg', { name }))
}

const copy = (name) => {
    const fullPath = buildRemotePath(currentPath.value, name)
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
                const name = source.split('/').pop()
                let target
                try {
                    target = await resolveRemoteConflictTarget(name)
                } catch (err) {
                    if (err.message === 'UPLOAD_CANCELLED_BY_USER') {
                        continue
                    }
                    throw err
                }
                await pasteFile(props.hostId, source, currentPath.value, type, target)
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
    const oldPath = buildRemotePath(currentPath.value, renamingFile.value.name)
    const newPath = buildRemotePath(currentPath.value, renameName.value)
    
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
    const fullPath = buildRemotePath(currentPath.value, createName.value)
    
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

const openEditor = async (record) => {
    const fullPath = buildRemotePath(currentPath.value, record.name)
    if (!(await waitForFileEditor())) {
        message.error(t('common.error'))
        return
    }
    try {
        await fileEditorRef.value.openFile(fullPath, record.name)
    } catch (e) {
        console.error(e)
        message.error(t('sftp.downloadFailed'))
    }
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

const readLocalBookmarkList = (key) => {
  try {
    const value = localStorage.getItem(key)
    const parsed = value ? JSON.parse(value) : []
    return Array.isArray(parsed) ? parsed.filter((p) => typeof p === 'string') : []
  } catch (error) {
    console.warn('Failed to parse local SFTP bookmarks:', error)
    return []
  }
}

const normalizeBookmarkList = (paths, limit) => {
  const seen = new Set()
  const out = []
  for (const item of paths || []) {
    const path = typeof item === 'string' ? item.trim() : ''
    if (!path || path === '.' || seen.has(path)) continue
    seen.add(path)
    out.push(path)
    if (out.length >= limit) break
  }
  return out
}

const localBookmarkKeys = () => ({
  history: `sftp_history_${props.hostId}`,
  favorites: `sftp_favorites_${props.hostId}`,
})

const localBookmarks = () => {
  const keys = localBookmarkKeys()
  return {
    history: normalizeBookmarkList(readLocalBookmarkList(keys.history), 15),
    favorites: normalizeBookmarkList(readLocalBookmarkList(keys.favorites), 100),
  }
}

const clearLocalBookmarks = () => {
  const keys = localBookmarkKeys()
  localStorage.removeItem(keys.history)
  localStorage.removeItem(keys.favorites)
}

const persistBookmarks = async (history = historyList.value, favorites = favoritesList.value) => {
  if (!props.hostId) return null
  return savePathBookmarks(props.hostId, {
    history: normalizeBookmarkList(history, 15),
    favorites: normalizeBookmarkList(favorites, 100),
  })
}

const schedulePersistBookmarks = () => {
  if (!props.hostId) return
  if (bookmarksSaveTimer) clearTimeout(bookmarksSaveTimer)
  bookmarksSaveTimer = setTimeout(() => {
    bookmarksSaveTimer = null
    persistBookmarks().catch((error) => {
      console.warn('Failed to save SFTP bookmarks:', error)
    })
  }, 250)
}

const loadHistoryAndFavorites = async () => {
  if (!props.hostId) return
  const requestId = ++bookmarksRequestId
  const local = localBookmarks()

  try {
    const remote = await getPathBookmarks(props.hostId)
    if (requestId !== bookmarksRequestId) return

    const remoteHistory = normalizeBookmarkList(remote?.history, 15)
    const remoteFavorites = normalizeBookmarkList(remote?.favorites, 100)
    const mergedHistory = normalizeBookmarkList([...remoteHistory, ...local.history], 15)
    const mergedFavorites = normalizeBookmarkList([...remoteFavorites, ...local.favorites], 100)

    historyList.value = mergedHistory
    favoritesList.value = mergedFavorites

    if (local.history.length > 0 || local.favorites.length > 0) {
      try {
        await persistBookmarks(mergedHistory, mergedFavorites)
        clearLocalBookmarks()
      } catch (error) {
        console.warn('Failed to migrate local SFTP bookmarks:', error)
      }
    }
  } catch (error) {
    if (requestId !== bookmarksRequestId) return
    console.warn('Failed to load server SFTP bookmarks, using local fallback:', error)
    historyList.value = local.history
    favoritesList.value = local.favorites
  }
}

const addToHistory = (path) => {
  if (!path || path === '.' || !props.hostId) return
  let list = [path, ...historyList.value.filter(p => p !== path)]
  if (list.length > 15) list = list.slice(0, 15)
  historyList.value = list
  schedulePersistBookmarks()
}

const clearHistory = () => {
  historyList.value = []
  schedulePersistBookmarks()
  message.success(t('sftp.historyCleared'))
}

const addCurrentToFavorites = () => {
  const path = currentPath.value
  if (!path || !props.hostId) return
  if (favoritesList.value.includes(path)) {
    message.warning(t('sftp.favoriteAlreadyExists'))
    return
  }
  const list = [...favoritesList.value, path]
  favoritesList.value = list
  schedulePersistBookmarks()
  message.success(t('sftp.favoriteAdded'))
}

const removeFavorite = (path) => {
  if (!path || !props.hostId) return
  const list = favoritesList.value.filter(p => p !== path)
  favoritesList.value = list
  schedulePersistBookmarks()
  message.success(t('sftp.favoriteRemoved'))
}

const handleHistoryClick = (key) => {
  if (key === 'clear_history') {
    clearHistory()
  } else {
    navigateToPath(key)
  }
}

const handleFavoriteClick = (path) => {
  navigateToPath(path)
}

let lastLoadedHostId = props.hostId

watch(() => props.hostId, (newVal) => {
  if (!newVal) return
  if (String(newVal) === String(lastLoadedHostId)) return
  lastLoadedHostId = newVal

  resetPathHistory()
  onSelectChange([])
  pathCompleteCache.clear()
  fileEditorRef.value?.forceCloseAllTabs()
  void loadHistoryAndFavorites()
  if (props.visible) {
    loadFilesWithRememberedPath()
  }
})

watch(() => props.visible, (newVal) => {
  if (newVal && files.value.length === 0) {
    loadFilesWithRememberedPath()
  }
})

onMounted(() => {
  void loadHistoryAndFavorites()
  if (props.visible) {
    loadFilesWithRememberedPath()
  }
  // Add keyboard event listener
  window.addEventListener('keydown', handleKeyDown)
})

onUnmounted(() => {
  window.removeEventListener('keydown', handleKeyDown)
  if (bookmarksSaveTimer) {
    clearTimeout(bookmarksSaveTimer)
    bookmarksSaveTimer = null
    persistBookmarks().catch((error) => {
      console.warn('Failed to save SFTP bookmarks before unmount:', error)
    })
  }
  bookmarksRequestId += 1
  uploadDismissTimers.forEach((timer) => clearTimeout(timer))
  uploadDismissTimers.clear()
  uploadControllers.forEach((controller, key) => {
    cancelledUploads.add(key)
    controller.abort()
  })
  uploadControllers.clear()
  closePreview()
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
  onSelectChange(files.value.map(f => f.name))
}

const invertSelection = () => {
  const allKeys = files.value.map(f => f.name)
  onSelectChange(allKeys.filter(key => !selectedRowKeys.value.includes(key)))
}

const clearSelection = () => {
  onSelectChange([])
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
          const fullPath = buildRemotePath(currentPath.value, name)
          await deleteFile(props.hostId, fullPath)
        }
        message.success(t('sftp.deleted'))
        onSelectChange([])
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
      h('div', { style: 'margin-top: 12px; font-size: 12px; color: #888' }, [
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
  if (!browserInteractionActive.value) return
  if (!isShortcutTargetInsideBrowser(e.target)) return
  if (isEditableEventTarget(e.target)) return
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
    hasActiveUploads: isUploadBusy,
})
</script>

<style scoped>
.sftp-browser {
  display: flex;
  flex-direction: column;
  height: 100%;
  transition: all 0.3s ease;
  outline: none;
}

.sftp-browser.drag-over {
  background: rgba(24, 144, 255, 0.1);
  border: 2px dashed #1890ff;
}

.sftp-browser.drag-over .browser-content {
  pointer-events: none;
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

:deep(.ant-table-body) {
  overflow-x: hidden !important;
}

:deep(.ant-table-content) {
  overflow-x: hidden !important;
}

:deep(.ant-table-cell a) {
  min-width: 0;
}

@media (max-width: 640px) {
  .browser-content {
    overflow: hidden;
  }

  :deep(.ant-table) {
    font-size: 12px;
  }

  :deep(.ant-table-cell) {
    padding: 5px 6px !important;
  }

  :deep(.ant-table-selection-column) {
    width: 36px !important;
    min-width: 36px !important;
  }

  :deep(.ant-table-thead > tr > th:nth-child(4)),
  :deep(.ant-table-tbody > tr > td:nth-child(4)),
  :deep(.ant-table-thead > tr > th:nth-child(5)),
  :deep(.ant-table-tbody > tr > td:nth-child(5)) {
    display: none;
  }

  :deep(.ant-table-tbody > tr > td:nth-child(3) a) {
    display: inline-flex;
    max-width: 100%;
    align-items: center;
    overflow: hidden;
    text-overflow: ellipsis;
    vertical-align: top;
    white-space: nowrap;
  }

  :deep(.ant-table-tbody > tr > td:nth-child(2) .ant-space) {
    gap: 0 !important;
  }

  :deep(.ant-table-tbody > tr > td:nth-child(2) .ant-btn-sm) {
    width: 28px;
    min-width: 28px;
    padding: 0 !important;
  }
}

</style>
