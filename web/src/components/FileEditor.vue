<template>
  <Teleport to="body">
    <div
      v-if="tabs.length > 0"
      v-show="panelVisible"
      class="file-editor-float"
      :class="{
        'file-editor-float--dark': themeStore.isDark,
        'file-editor-float--minimized': panelMinimized,
        'file-editor-float--maximized': panelMaximized,
      }"
      :style="panelStyle"
      @mousedown="bringToFront"
    >
      <div class="editor-tabs-row">
        <div class="editor-tabs" @mousedown.stop>
          <div
            v-for="tab in tabs"
            :key="tab.key"
            class="editor-tab"
            :class="{ active: tab.key === activeKey, dirty: tab.dirty }"
            @click="switchTab(tab.key)"
          >
            <span class="editor-tab-label" :title="tab.name">{{ tabLabel(tab) }}</span>
            <span class="editor-tab-close" @click.stop="closeTab(tab.key)">
              <CloseOutlined />
            </span>
          </div>
        </div>
        <a-space class="editor-tabs-actions" @mousedown.stop>
          <div
            class="editor-drag-handle"
            :title="t('sftp.editorDrag')"
            @mousedown="startDragHandle"
          >
            <HolderOutlined />
          </div>
          <a-button
            size="small"
            type="text"
            :title="t('sftp.searchReplace')"
            @click="triggerFindReplace"
          >
            <template #icon><SearchOutlined /></template>
          </a-button>
          <a-button
            size="small"
            type="text"
            :title="t('sftp.refreshFile')"
            :loading="activeTab?.loading"
            :disabled="!activeTab"
            @click="refreshActiveFile"
          >
            <template #icon><ReloadOutlined /></template>
          </a-button>
          <a-button
            v-if="activeTab?.dirty"
            size="small"
            type="primary"
            :title="t('sftp.saveShortcut')"
            :loading="activeTab?.saving"
            @click="saveActiveFile"
          >
            {{ t('common.save') }}
          </a-button>
          <a-button
            size="small"
            type="text"
            :title="panelMinimized ? t('sftp.editorRestore') : t('sftp.editorMinimize')"
            @click="toggleMinimize"
          >
            <template #icon><MinusOutlined /></template>
          </a-button>
          <a-button
            size="small"
            type="text"
            :title="panelMaximized ? t('sftp.editorRestore') : t('sftp.editorMaximize')"
            @click="toggleMaximize"
          >
            <template #icon>
              <CompressOutlined v-if="panelMaximized" />
              <BorderOutlined v-else />
            </template>
          </a-button>
          <a-button size="small" type="text" :title="t('sftp.editorClose')" @click="handleCloseAll">
            <template #icon><CloseOutlined /></template>
          </a-button>
        </a-space>
      </div>
      <div v-show="!panelMinimized" class="editor-body">
        <div v-if="activeTab?.loading" class="editor-loading">
          <a-spin />
        </div>
        <div ref="editorRef" class="editor-instance"></div>
      </div>
      <div v-if="activeTab && !panelMinimized" class="editor-path-row" @mousedown="startDrag">
        <span v-if="activeTab.fileSize" class="file-info">{{ formatSize(activeTab.fileSize) }}</span>
        <span class="editor-path-text" :title="activeTab.path">{{ activeTab.path }}</span>
      </div>
      <div
        v-if="!panelMinimized && !panelMaximized"
        class="editor-resize-handle"
        title="Resize"
        @mousedown.stop="startResize"
      />
    </div>
  </Teleport>
</template>

<script setup>
import { ref, shallowRef, markRaw, onBeforeUnmount, watch, nextTick, computed } from 'vue'
import * as monaco from 'monaco-editor'
import { message, Modal } from 'ant-design-vue'
import {
  SearchOutlined,
  CloseOutlined,
  ReloadOutlined,
  HolderOutlined,
  MinusOutlined,
  BorderOutlined,
  CompressOutlined,
} from '@ant-design/icons-vue'
import { listFiles, downloadFile, uploadFile } from '../api/sftp'
import { useI18n } from 'vue-i18n'
import { useThemeStore } from '../stores/theme'

import editorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker'
import jsonWorker from 'monaco-editor/esm/vs/language/json/json.worker?worker'
import cssWorker from 'monaco-editor/esm/vs/language/css/css.worker?worker'
import htmlWorker from 'monaco-editor/esm/vs/language/html/html.worker?worker'
import tsWorker from 'monaco-editor/esm/vs/language/typescript/ts.worker?worker'

self.MonacoEnvironment = {
  getWorker(_, label) {
    if (label === 'json') return new jsonWorker()
    if (label === 'css' || label === 'scss' || label === 'less') return new cssWorker()
    if (label === 'html' || label === 'handlebars' || label === 'razor') return new htmlWorker()
    if (label === 'typescript' || label === 'javascript') return new tsWorker()
    return new editorWorker()
  }
}

const props = defineProps({
  hostId: {
    type: [String, Number],
    required: true,
  },
  /** Hide floating panel without closing tabs (e.g. left SFTP/terminal view). */
  panelVisible: {
    type: Boolean,
    default: true,
  },
})

const emit = defineEmits(['saved'])
const { t } = useI18n()
const themeStore = useThemeStore()

/** @typedef {{ key: string, path: string, name: string, dirty: boolean, loading: boolean, saving: boolean, savedContent: string, fileSize: number, model: import('monaco-editor').editor.ITextModel | null, changeDisposable: import('monaco-editor').IDisposable | null }} EditorTab */

/** Tab list is shallow to avoid Vue proxying Monaco models (causes UI freeze). */
const tabs = shallowRef([])
const activeKey = ref(null)

const editorRef = ref(null)
const editorInstance = shallowRef(null)
let saveCommandDisposable = null

const MIN_PANEL_W = 480
const MIN_PANEL_H = 280
const TAB_ROW_HEIGHT = 33
const panelWidth = ref(800)
const panelHeight = ref(540)
const panelX = ref(80)
const panelY = ref(80)
const zIndex = ref(1100)
const panelMinimized = ref(false)
const panelMaximized = ref(false)
const savedPanelGeometry = ref(null)
const heightBeforeMinimize = ref(null)
let panelGeometryInitialized = false

const activeTab = computed(() => tabs.value.find((tab) => tab.key === activeKey.value) ?? null)

const panelStyle = computed(() => {
  if (panelMaximized.value) {
    return {
      left: '0',
      top: '0',
      width: '100vw',
      height: '100vh',
      zIndex: zIndex.value,
    }
  }
  if (panelMinimized.value) {
    return {
      left: `${panelX.value}px`,
      top: `${panelY.value}px`,
      width: `${panelWidth.value}px`,
      height: `${TAB_ROW_HEIGHT}px`,
      zIndex: zIndex.value,
    }
  }
  return {
    left: `${panelX.value}px`,
    top: `${panelY.value}px`,
    width: `${panelWidth.value}px`,
    height: `${panelHeight.value}px`,
    zIndex: zIndex.value,
  }
})

let dragState = null
let resizeState = null

const tabLabel = (tab) => (tab.dirty ? `● ${tab.name}` : tab.name)

const layoutEditor = () => {
  nextTick(() => editorInstance.value?.layout())
}

const beginPanelDrag = (e) => {
  dragState = {
    startX: e.clientX,
    startY: e.clientY,
    originX: panelX.value,
    originY: panelY.value,
  }
  document.addEventListener('mousemove', onDrag)
  document.addEventListener('mouseup', stopDrag)
}

const startDragHandle = (e) => {
  if (e.button !== 0) return
  e.preventDefault()
  e.stopPropagation()
  beginPanelDrag(e)
}

const canStartPanelDrag = (e) => {
  if (e.button !== 0) return false
  if (e.target.closest('button, .ant-btn, .editor-tab, .editor-tab-close, .editor-tabs-actions, .editor-resize-handle, .editor-tabs')) {
    return false
  }
  return true
}

const startDrag = (e) => {
  if (!canStartPanelDrag(e)) return
  e.preventDefault()
  beginPanelDrag(e)
}

const onDrag = (e) => {
  if (!dragState) return
  const dx = e.clientX - dragState.startX
  const dy = e.clientY - dragState.startY
  const maxX = Math.max(0, window.innerWidth - panelWidth.value)
  const maxY = Math.max(0, window.innerHeight - 48)
  panelX.value = Math.min(maxX, Math.max(0, dragState.originX + dx))
  panelY.value = Math.min(maxY, Math.max(0, dragState.originY + dy))
}

const stopDrag = () => {
  dragState = null
  document.removeEventListener('mousemove', onDrag)
  document.removeEventListener('mouseup', stopDrag)
}

const restoreFromMinimize = () => {
  if (!panelMinimized.value) return
  panelMinimized.value = false
  panelHeight.value = heightBeforeMinimize.value ?? 540
  heightBeforeMinimize.value = null
  layoutEditor()
}

const toggleMinimize = () => {
  if (panelMinimized.value) {
    restoreFromMinimize()
    return
  }
  hideFindWidget()
  heightBeforeMinimize.value = panelHeight.value
  if (panelMaximized.value) {
    panelMaximized.value = false
    savedPanelGeometry.value = null
  }
  panelMinimized.value = true
}

const toggleMaximize = () => {
  if (panelMaximized.value) {
    const g = savedPanelGeometry.value
    if (g) {
      panelX.value = g.x
      panelY.value = g.y
      panelWidth.value = g.w
      panelHeight.value = g.h
    }
    panelMaximized.value = false
    savedPanelGeometry.value = null
    layoutEditor()
    return
  }
  hideFindWidget()
  if (!panelMinimized.value) {
    savedPanelGeometry.value = {
      x: panelX.value,
      y: panelY.value,
      w: panelWidth.value,
      h: panelHeight.value,
    }
  } else {
    restoreFromMinimize()
    savedPanelGeometry.value = {
      x: panelX.value,
      y: panelY.value,
      w: panelWidth.value,
      h: heightBeforeMinimize.value ?? panelHeight.value,
    }
    heightBeforeMinimize.value = null
  }
  panelMaximized.value = true
}

const startResize = (e) => {
  if (panelMinimized.value || panelMaximized.value) return
  if (e.button !== 0) return
  e.preventDefault()
  resizeState = {
    startX: e.clientX,
    startY: e.clientY,
    originW: panelWidth.value,
    originH: panelHeight.value,
  }
  document.addEventListener('mousemove', onResize)
  document.addEventListener('mouseup', stopResize)
}

const onResize = (e) => {
  if (!resizeState) return
  const maxW = window.innerWidth - panelX.value - 8
  const maxH = window.innerHeight - panelY.value - 8
  panelWidth.value = Math.min(
    maxW,
    Math.max(MIN_PANEL_W, resizeState.originW + e.clientX - resizeState.startX),
  )
  panelHeight.value = Math.min(
    maxH,
    Math.max(MIN_PANEL_H, resizeState.originH + e.clientY - resizeState.startY),
  )
  layoutEditor()
}

const stopResize = () => {
  resizeState = null
  document.removeEventListener('mousemove', onResize)
  document.removeEventListener('mouseup', stopResize)
}

const bringToFront = () => {
  zIndex.value = Date.now()
}

const centerPanel = () => {
  panelX.value = Math.max(24, Math.round((window.innerWidth - panelWidth.value) / 2))
  panelY.value = Math.max(24, Math.round((window.innerHeight - panelHeight.value) / 2))
  panelGeometryInitialized = true
}

const getParentDir = (filePath) => {
  const lastSlash = filePath.lastIndexOf('/')
  if (lastSlash > 0) return filePath.slice(0, lastSlash)
  if (filePath.startsWith('/')) return '/'
  return '.'
}

const fetchRemoteFileMeta = async (filePath, fileName) => {
  const data = await listFiles(props.hostId, getParentDir(filePath))
  const files = data?.files ?? (Array.isArray(data) ? data : [])
  const entry = files.find((f) => f.name === fileName && !f.is_dir)
  if (!entry?.mod_time) return null
  const modTime = new Date(entry.mod_time).getTime()
  if (Number.isNaN(modTime)) return null
  return { modTime, size: entry.size ?? 0 }
}

const isRemoteNewerThanTab = (tab, remote) => {
  if (!remote?.modTime || !tab?.remoteModTime) return false
  return remote.modTime > tab.remoteModTime + 500
}

const confirmModal = ({ title, content, okText, cancelText, onOk, onCancel }) => {
  Modal.confirm({
    title,
    content,
    okText: okText ?? t('common.ok'),
    cancelText: cancelText ?? t('common.cancel'),
    onOk: () => Promise.resolve(onOk?.()),
    onCancel: () => Promise.resolve(onCancel?.()),
  })
}

const promptReloadIfRemoteNewer = async (tab) => {
  let remoteMeta = null
  try {
    remoteMeta = await fetchRemoteFileMeta(tab.path, tab.name)
  } catch {
    return true
  }
  if (!remoteMeta || !isRemoteNewerThanTab(tab, remoteMeta)) return true
  return new Promise((resolve) => {
    Modal.confirm({
      title: t('sftp.diskChangedTitle'),
      content: t('sftp.diskChangedReload'),
      okText: t('sftp.reloadFromDisk'),
      cancelText: t('common.cancel'),
      onOk: () => resolve(true),
      onCancel: () => resolve(false),
    })
  })
}

const hideFindWidget = () => {
  editorInstance.value?.getAction('editor.action.closeFindWidget')?.run()
}

const getLanguage = (filename) => {
  const ext = filename.split('.').pop().toLowerCase()
  const map = {
    js: 'javascript',
    ts: 'typescript',
    py: 'python',
    html: 'html',
    css: 'css',
    json: 'json',
    md: 'markdown',
    sql: 'sql',
    xml: 'xml',
    yaml: 'yaml',
    yml: 'yaml',
    sh: 'shell',
    bash: 'shell',
    go: 'go',
    java: 'java',
    c: 'c',
    cpp: 'cpp',
    rs: 'rust',
    php: 'php',
    rb: 'ruby',
    lua: 'lua',
    ini: 'ini',
    conf: 'ini',
    vue: 'html',
    dockerfile: 'dockerfile',
  }
  return map[ext] || 'plaintext'
}

const modelUri = (filePath) => monaco.Uri.parse(`termiscope://${encodeURIComponent(filePath)}`)

const notifyTabsChanged = () => {
  tabs.value = [...tabs.value]
}

const patchTab = (key, patch) => {
  const idx = tabs.value.findIndex((t) => t.key === key)
  if (idx === -1) return
  tabs.value[idx] = { ...tabs.value[idx], ...patch }
  notifyTabsChanged()
}

const updateTabDirty = (tab) => {
  if (!tab.model) {
    if (tab.dirty) patchTab(tab.key, { dirty: false })
    return
  }
  const dirty = tab.model.getValue() !== tab.savedContent
  if (tab.dirty !== dirty) patchTab(tab.key, { dirty })
}

const waitForEditorEl = async () => {
  for (let i = 0; i < 30; i++) {
    await nextTick()
    if (editorRef.value) return true
    await new Promise((r) => requestAnimationFrame(r))
  }
  return false
}

const ensureEditor = async () => {
  if (editorInstance.value) return true
  if (!(await waitForEditorEl())) return false

  editorInstance.value = markRaw(
    monaco.editor.create(editorRef.value, {
      value: '',
      language: 'plaintext',
      theme: themeStore.isDark ? 'vs-dark' : 'vs-light',
      automaticLayout: true,
      minimap: { enabled: false },
      scrollBeyondLastLine: false,
      fixedOverflowWidgets: true,
      fontSize: 14,
      scrollbar: {
        vertical: 'auto',
        horizontal: 'auto',
        verticalScrollbarSize: 10,
        horizontalScrollbarSize: 10,
        verticalHasArrows: false,
        horizontalHasArrows: false,
        useShadows: false,
        alwaysConsumeMouseWheel: false,
      },
    })
  )

  saveCommandDisposable = editorInstance.value.addCommand(
    monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS,
    () => {
      if (activeTab.value?.dirty) saveActiveFile()
    }
  )
  setupFindWidgetHoverPin()
  return true
}

const attachModelToEditor = (tab) => {
  if (!tab?.model || !editorInstance.value) return
  if (editorInstance.value.getModel() !== tab.model) {
    editorInstance.value.setModel(tab.model)
  }
}

const switchTab = async (key) => {
  if (activeKey.value === key) {
    await initEditorIfNeeded()
    return
  }
  activeKey.value = key
  await nextTick()
  await initEditorIfNeeded()
  attachModelToEditor(activeTab.value)
}

const initEditorIfNeeded = async () => {
  if (!(await ensureEditor())) return
  attachModelToEditor(activeTab.value)
  layoutEditor()
}

const loadTabContent = async (key) => {
  const meta = tabs.value.find((t) => t.key === key)
  if (!props.hostId || !meta?.path) return

  let remoteMeta = null
  try {
    remoteMeta = await fetchRemoteFileMeta(meta.path, meta.name)
  } catch {
    remoteMeta = null
  }

  patchTab(key, { loading: true, dirty: false })
  try {
    const response = await downloadFile(props.hostId, meta.path)
    const text = await response.text()

    const prev = tabs.value.find((t) => t.key === key)
    if (prev?.model) {
      prev.changeDisposable?.dispose()
      prev.model.dispose()
    }

    const model = markRaw(
      monaco.editor.createModel(text, getLanguage(meta.name), modelUri(meta.path))
    )
    const changeDisposable = markRaw(
      model.onDidChangeContent(() => {
        const t = tabs.value.find((x) => x.key === key)
        if (t) updateTabDirty(t)
      })
    )

    if (!remoteMeta) {
      try {
        remoteMeta = await fetchRemoteFileMeta(meta.path, meta.name)
      } catch {
        remoteMeta = null
      }
    }

    patchTab(key, {
      savedContent: text,
      fileSize: response.size,
      remoteModTime: remoteMeta?.modTime ?? Date.now(),
      model,
      changeDisposable,
    })

    const updated = tabs.value.find((t) => t.key === key)
    if (updated) updateTabDirty(updated)

    if (activeKey.value === key) {
      await initEditorIfNeeded()
      attachModelToEditor(tabs.value.find((t) => t.key === key))
    }
  } catch (error) {
    message.error(t('sftp.downloadFailed') + ': ' + (error.message || 'Unknown error'))
    await removeTab(key, true)
  } finally {
    patchTab(key, { loading: false })
  }
}

const openFile = async (filePath, fileName) => {
  const key = filePath
  const existing = tabs.value.find((tab) => tab.key === key)
  if (existing) {
    bringToFront()
    await switchTab(key)
    return
  }

  if (panelMinimized.value) {
    restoreFromMinimize()
  }
  if (!panelGeometryInitialized) {
    centerPanel()
  }
  bringToFront()

  const tab = {
    key,
    path: filePath,
    name: fileName,
    dirty: false,
    loading: true,
    saving: false,
    savedContent: '',
    fileSize: 0,
    remoteModTime: 0,
    model: null,
    changeDisposable: null,
  }
  tabs.value = [...tabs.value, tab]
  activeKey.value = key
  await loadTabContent(key)
}

const disposeTab = (tab) => {
  if (!tab) return
  tab.changeDisposable?.dispose()
  if (tab.model) {
    if (editorInstance.value?.getModel() === tab.model) {
      const fallback = tabs.value.find((t) => t.key !== tab.key && t.model)
      if (fallback?.model) {
        editorInstance.value.setModel(fallback.model)
      }
    }
    tab.model.dispose()
  }
}

const removeTab = async (key, force = false) => {
  const idx = tabs.value.findIndex((tab) => tab.key === key)
  if (idx === -1) return

  const tab = tabs.value[idx]
  disposeTab(tab)
  const nextTabs = tabs.value.filter((t) => t.key !== key)
  tabs.value = nextTabs

  if (nextTabs.length === 0) {
    activeKey.value = null
    disposeEditor()
    return
  }

  if (activeKey.value === key || force) {
    const next = nextTabs[Math.min(idx, nextTabs.length - 1)]
    await switchTab(next.key)
  }
}

const confirmCloseTab = (tab, onClosed) => {
  if (!tab.dirty) {
    void onClosed()
    return
  }
  Modal.confirm({
    title: t('sftp.unsavedTitle'),
    content: t('sftp.unsavedTabContent', { name: tab.name }),
    okText: t('sftp.unsavedSave'),
    cancelText: t('sftp.unsavedDiscard'),
    maskClosable: false,
    onOk: async () => {
      const ok = await saveTab(tab)
      const latest = tabs.value.find((t) => t.key === tab.key)
      if (ok && latest && !latest.dirty) {
        await onClosed()
      }
    },
    onCancel: () => {
      void onClosed()
    },
  })
}

const closeTab = (key) => {
  const tab = tabs.value.find((t) => t.key === key)
  if (!tab) return
  confirmCloseTab(tab, () => removeTab(key))
}

const closeAllTabs = () => {
  hideFindWidget()
  const snapshot = [...tabs.value]
  tabs.value = []
  activeKey.value = null
  panelGeometryInitialized = false
  panelMinimized.value = false
  panelMaximized.value = false
  savedPanelGeometry.value = null
  heightBeforeMinimize.value = null
  disposeEditor()
  snapshot.forEach(disposeTab)
}

const handleCloseAll = () => {
  const dirtyTabs = tabs.value.filter((tab) => tab.dirty)
  if (dirtyTabs.length === 0) {
    closeAllTabs()
    return
  }
  Modal.confirm({
    title: t('sftp.closeEditorUnsavedTitle'),
    content: t('sftp.closeEditorUnsavedContent', { count: dirtyTabs.length }),
    okText: t('sftp.closeEditorSaveAll'),
    cancelText: t('sftp.closeEditorDiscard'),
    maskClosable: false,
    onOk: async () => {
      for (const tab of dirtyTabs) {
        const latest = tabs.value.find((t) => t.key === tab.key)
        if (latest?.dirty) {
          const ok = await saveTab(latest)
          if (!ok) return
        }
      }
      if (!tabs.value.some((t) => t.dirty)) {
        closeAllTabs()
      }
    },
    onCancel: () => {
      closeAllTabs()
    },
  })
}

const performUpload = async (tab) => {
  const tabKey = tab.key
  const newContent = tab.model.getValue()
  const blob = new Blob([newContent], { type: 'text/plain' })
  const file = new File([blob], tab.name, { type: 'text/plain' })

  const lastSlashIndex = tab.path.lastIndexOf('/')
  let targetDir = lastSlashIndex !== -1 ? tab.path.substring(0, lastSlashIndex) : '.'
  if (tab.path.startsWith('/') && targetDir === '') {
    targetDir = '/'
  }

  await uploadFile(props.hostId, targetDir, file)
  message.success(t('sftp.uploadComplete'))

  let remoteMeta = null
  try {
    remoteMeta = await fetchRemoteFileMeta(tab.path, tab.name)
  } catch {
    remoteMeta = null
  }

  patchTab(tabKey, {
    savedContent: newContent,
    fileSize: blob.size,
    remoteModTime: remoteMeta?.modTime ?? Date.now(),
  })
  const updated = tabs.value.find((t) => t.key === tabKey)
  if (updated) updateTabDirty(updated)
  emit('saved')
}

const saveTab = async (tab) => {
  if (!tab?.model || !tab.dirty || tab.saving) return true
  const tabKey = tab.key

  let remoteMeta = null
  try {
    remoteMeta = await fetchRemoteFileMeta(tab.path, tab.name)
  } catch {
    remoteMeta = null
  }

  if (remoteMeta && isRemoteNewerThanTab(tab, remoteMeta)) {
    return new Promise((resolve) => {
      Modal.confirm({
        title: t('sftp.diskChangedTitle'),
        content: t('sftp.diskChangedOnSave'),
        okText: t('sftp.reloadFromDisk'),
        cancelText: t('sftp.saveAnyway'),
        maskClosable: false,
        onOk: async () => {
          hideFindWidget()
          await loadTabContent(tabKey)
          resolve(false)
        },
        onCancel: async () => {
          patchTab(tabKey, { saving: true })
          try {
            const current = tabs.value.find((t) => t.key === tabKey) ?? tab
            await performUpload(current)
            resolve(true)
          } catch (error) {
            message.error(t('sftp.uploadFailed') + ': ' + (error.message || 'Unknown error'))
            resolve(false)
          } finally {
            patchTab(tabKey, { saving: false })
          }
        },
      })
    })
  }

  patchTab(tabKey, { saving: true })
  try {
    await performUpload(tab)
    return true
  } catch (error) {
    message.error(t('sftp.uploadFailed') + ': ' + (error.message || 'Unknown error'))
    return false
  } finally {
    patchTab(tabKey, { saving: false })
  }
}

const saveActiveFile = async () => {
  const tab = activeTab.value
  if (!tab) return
  await saveTab(tab)
}

const refreshActiveFile = async () => {
  const tab = activeTab.value
  if (!tab || tab.loading) return

  const runReload = async () => {
    hideFindWidget()
    const latest = tabs.value.find((t) => t.key === tab.key)
    if (!latest) return
    if (!(await promptReloadIfRemoteNewer(latest))) return
    await loadTabContent(latest.key)
  }

  if (tab.dirty) {
    confirmModal({
      title: t('sftp.refreshUnsavedTitle'),
      content: t('sftp.refreshUnsavedContent'),
      okText: t('sftp.refreshSaveAndReload'),
      cancelText: t('common.cancel'),
      onOk: async () => {
        await saveActiveFile()
        const latest = tabs.value.find((t) => t.key === tab.key)
        if (latest && !latest.dirty) {
          await runReload()
        }
      },
    })
    return
  }

  await runReload()
}

const triggerFindReplace = () => {
  editorInstance.value?.getAction('editor.action.startFindReplaceAction')?.run()
}

const formatSize = (bytes) => {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

const onGlobalKeyDown = (e) => {
  if (tabs.value.length === 0 || !activeTab.value?.dirty) return
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
    e.preventDefault()
    saveActiveFile()
  }
}

/** Pin find-widget tooltips below buttons so they do not overlap the hover target (flicker). */
const FIND_HOVER_PIN_CLASS = 'termiscope-find-hover-below'
const FIND_HOVER_CONTROL_SEL =
  '.find-widget .button, .find-widget .monaco-custom-toggle, .find-widget .codicon-widget-close, .find-widget [custom-hover="true"]'
let findHoverPinRefs = 0
let findHoverPinObserver = null
let findHoverPinScheduleRaf = 0
let findHoverPinLoopRaf = 0
let findHoverPinLoopActive = false
let lastFindHoverControl = null
let findHoverPinMouseCleanup = null

const getVisibleFindWidget = () =>
  document.querySelector('.monaco-editor .find-widget.visible')

const resolveFindHoverControl = (target) => {
  const widget = getVisibleFindWidget()
  if (!widget || !(target instanceof Element)) return null
  const control = target.closest(FIND_HOVER_CONTROL_SEL)
  return control && widget.contains(control) ? control : null
}

const getFindHoverControl = () => {
  const widget = getVisibleFindWidget()
  if (!widget) return null
  if (lastFindHoverControl && widget.contains(lastFindHoverControl)) {
    return lastFindHoverControl
  }
  return widget.querySelector(`${FIND_HOVER_CONTROL_SEL}:hover`)
}

const pinFindHoverBelow = (contextView, control) => {
  if (!contextView.querySelector('.monaco-hover.workbench-hover.compact')) return false
  const btn = control.getBoundingClientRect()
  const gap = 6
  const viewW = contextView.offsetWidth
  const viewH = contextView.offsetHeight
  let left = btn.left + (btn.width - viewW) / 2
  const top = btn.bottom + gap
  left = Math.max(4, Math.min(left, window.innerWidth - viewW - 4))
  contextView.style.setProperty('position', 'fixed', 'important')
  contextView.style.setProperty('left', `${left}px`, 'important')
  contextView.style.setProperty('top', `${top}px`, 'important')
  contextView.style.setProperty('margin', '0', 'important')
  contextView.style.setProperty('padding', '0', 'important')
  contextView.style.setProperty('transform', 'none', 'important')
  contextView.classList.add(FIND_HOVER_PIN_CLASS)
  return true
}

const clearFindHoverPins = () => {
  document.querySelectorAll(`.context-view.${FIND_HOVER_PIN_CLASS}`).forEach((view) => {
    view.classList.remove(FIND_HOVER_PIN_CLASS)
    view.style.removeProperty('position')
    view.style.removeProperty('left')
    view.style.removeProperty('top')
    view.style.removeProperty('margin')
    view.style.removeProperty('padding')
    view.style.removeProperty('transform')
  })
}

const applyFindHoverPins = () => {
  const control = getFindHoverControl()
  if (!control) return false
  let pinned = false
  document.querySelectorAll('.context-view').forEach((view) => {
    if (pinFindHoverBelow(view, control)) pinned = true
  })
  return pinned
}

const stopFindHoverPinLoop = () => {
  findHoverPinLoopActive = false
  cancelAnimationFrame(findHoverPinLoopRaf)
  findHoverPinLoopRaf = 0
}

const startFindHoverPinLoop = () => {
  if (findHoverPinLoopActive) return
  findHoverPinLoopActive = true
  const tick = () => {
    if (!findHoverPinLoopActive) return
    const hovering = document.querySelector('.context-view .monaco-hover.workbench-hover.compact')
    if (hovering && getFindHoverControl()) {
      applyFindHoverPins()
      findHoverPinLoopRaf = requestAnimationFrame(tick)
    } else {
      stopFindHoverPinLoop()
      if (!hovering) clearFindHoverPins()
    }
  }
  findHoverPinLoopRaf = requestAnimationFrame(tick)
}

const scheduleFindHoverPin = () => {
  cancelAnimationFrame(findHoverPinScheduleRaf)
  findHoverPinScheduleRaf = requestAnimationFrame(() => {
    if (applyFindHoverPins()) startFindHoverPinLoop()
    else clearFindHoverPins()
  })
}

const setupFindWidgetHoverPin = () => {
  findHoverPinRefs += 1
  if (findHoverPinRefs > 1) return

  const onMouseOver = (e) => {
    const control = resolveFindHoverControl(e.target)
    if (!control) return
    lastFindHoverControl = control
    scheduleFindHoverPin()
  }

  const onMouseOut = (e) => {
    const widget = getVisibleFindWidget()
    if (!widget) return
    const related = e.relatedTarget
    if (related instanceof Element && widget.contains(related)) return
    if (resolveFindHoverControl(e.target) === lastFindHoverControl) {
      lastFindHoverControl = null
    }
  }

  document.addEventListener('mouseover', onMouseOver, true)
  document.addEventListener('mouseout', onMouseOut, true)
  findHoverPinMouseCleanup = () => {
    document.removeEventListener('mouseover', onMouseOver, true)
    document.removeEventListener('mouseout', onMouseOut, true)
  }

  findHoverPinObserver = new MutationObserver(scheduleFindHoverPin)
  findHoverPinObserver.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'style'] })
}

const teardownFindWidgetHoverPin = () => {
  findHoverPinRefs = Math.max(0, findHoverPinRefs - 1)
  if (findHoverPinRefs > 0) return
  findHoverPinObserver?.disconnect()
  findHoverPinObserver = null
  findHoverPinMouseCleanup?.()
  findHoverPinMouseCleanup = null
  lastFindHoverControl = null
  cancelAnimationFrame(findHoverPinScheduleRaf)
  findHoverPinScheduleRaf = 0
  stopFindHoverPinLoop()
  clearFindHoverPins()
}

const disposeEditor = () => {
  teardownFindWidgetHoverPin()
  saveCommandDisposable = null
  if (editorInstance.value) {
    editorInstance.value.dispose()
    editorInstance.value = null
  }
}

watch(
  () => props.panelVisible,
  (visible) => {
    if (!visible) {
      hideFindWidget()
      return
    }
    layoutEditor()
  }
)

watch(() => themeStore.isDark, (isDark) => {
  if (editorInstance.value) {
    monaco.editor.setTheme(isDark ? 'vs-dark' : 'vs-light')
  }
})

watch(
  () => props.hostId,
  () => {
    closeAllTabs()
  }
)

watch(
  () => tabs.value.length,
  (len, prevLen) => {
    if (len > 0 && (prevLen === undefined || prevLen === 0)) {
      window.addEventListener('keydown', onGlobalKeyDown, true)
    } else if (len === 0) {
      window.removeEventListener('keydown', onGlobalKeyDown, true)
      disposeEditor()
    }
  }
)

watch([panelWidth, panelHeight], () => layoutEditor())

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onGlobalKeyDown, true)
  stopDrag()
  stopResize()
  closeAllTabs()
  disposeEditor()
})

defineExpose({ openFile, closeAllTabs: handleCloseAll, forceCloseAllTabs: closeAllTabs })
</script>

<style scoped>
.file-editor-float--minimized {
  border-radius: 6px;
}

.file-editor-float--minimized .editor-tabs-row {
  border-bottom: none;
}

.file-editor-float--maximized {
  border-radius: 0;
}

.file-editor-float {
  position: fixed;
  display: flex;
  flex-direction: column;
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.18);
  border: 1px solid var(--editor-border, #d9d9d9);
  background: var(--editor-bg, #fff);
  --mac-scrollbar-thumb: rgba(0, 0, 0, 0.28);
  --mac-scrollbar-thumb-hover: rgba(0, 0, 0, 0.42);
}

.editor-tabs-row {
  display: flex;
  align-items: stretch;
  flex-shrink: 0;
  min-height: 32px;
  background: var(--editor-tabs-bg, #f0f0f0);
  border-bottom: 1px solid var(--editor-border, #d9d9d9);
  user-select: none;
}

.editor-tabs-actions .editor-drag-handle {
  flex-shrink: 0;
  width: 18px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: move;
  color: #8c8c8c;
  border-radius: 4px;
  background: transparent;
}

.editor-tabs-actions .editor-drag-handle:hover {
  color: #595959;
  background: rgba(0, 0, 0, 0.06);
}

.editor-tabs-actions .editor-drag-handle :deep(.anticon) {
  font-size: 14px;
  opacity: 0.75;
}

.editor-tabs-actions .editor-drag-handle:hover :deep(.anticon) {
  opacity: 1;
}

.editor-tabs {
  display: flex;
  flex: 1;
  min-width: 0;
  overflow-x: auto;
  overflow-y: hidden;
  scrollbar-width: thin;
  scrollbar-color: var(--mac-scrollbar-thumb) transparent;
}

.editor-tabs::-webkit-scrollbar {
  height: 6px;
}

.editor-tabs::-webkit-scrollbar-track {
  background: transparent;
}

.editor-tabs::-webkit-scrollbar-thumb {
  border-radius: 999px;
  background: var(--mac-scrollbar-thumb);
}

.editor-tabs::-webkit-scrollbar-thumb:hover {
  background: var(--mac-scrollbar-thumb-hover);
}

.editor-tabs-actions {
  display: flex;
  align-items: center;
  flex-shrink: 0;
  padding: 0 4px;
  gap: 2px;
  border-left: 1px solid var(--editor-border, #d9d9d9);
  background: var(--editor-header-bg, #fafafa);
  cursor: default;
}

.editor-tab {
  display: flex;
  align-items: center;
  gap: 4px;
  max-width: 180px;
  padding: 6px 8px 6px 12px;
  font-size: 12px;
  cursor: pointer;
  border-right: 1px solid var(--editor-border, #d9d9d9);
  color: #595959;
  flex-shrink: 0;
  user-select: none;
}

.editor-tab:hover {
  background: rgba(0, 0, 0, 0.04);
}

.editor-tab.active {
  background: var(--editor-bg, #fff);
  color: #1677ff;
  border-bottom: 2px solid #1677ff;
  margin-bottom: -1px;
}

.editor-tab.dirty .editor-tab-label {
  font-style: italic;
}

.editor-tab-label {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  flex: 1;
  min-width: 0;
}

.editor-tab-close {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  border-radius: 4px;
  flex-shrink: 0;
  font-size: 10px;
  opacity: 0.6;
}

.editor-tab-close:hover {
  opacity: 1;
  background: rgba(0, 0, 0, 0.08);
}

.editor-path-row {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-shrink: 0;
  padding: 3px 28px 4px 10px;
  min-height: 22px;
  background: var(--editor-bg, #fff);
  border-top: 1px solid var(--editor-border, #d9d9d9);
  cursor: move;
  user-select: none;
  overflow: hidden;
}

.editor-path-text {
  flex: 1;
  min-width: 0;
  font-size: 11px;
  line-height: 1.4;
  color: #8c8c8c;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.editor-body {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  position: relative;
}

.editor-loading {
  position: absolute;
  inset: 0;
  display: flex;
  justify-content: center;
  align-items: center;
  background: rgba(255, 255, 255, 0.6);
  z-index: 10;
}

.editor-instance {
  width: 100%;
  height: 100%;
}

.file-info {
  flex-shrink: 0;
  color: #8c8c8c;
  font-size: 11px;
  white-space: nowrap;
}

/* Find widget uses fixedOverflowWidgets (rendered on body); keep above editor chrome */
.file-editor-float :deep(.overflowingContentWidgets),
.file-editor-float :deep(.overlayWidgets) {
  z-index: 40 !important;
}

/* Monaco: macOS-style thin rounded scrollbars; track must not steal clicks from find widget */
.file-editor-float :deep(.monaco-scrollable-element > .scrollbar) {
  background: transparent !important;
  border-radius: 999px;
  pointer-events: none;
}

.file-editor-float :deep(.monaco-scrollable-element > .scrollbar.vertical) {
  width: 10px !important;
}

.file-editor-float :deep(.monaco-scrollable-element > .scrollbar.horizontal) {
  height: 10px !important;
}

.file-editor-float :deep(.monaco-scrollable-element > .scrollbar > .slider) {
  border-radius: 999px !important;
  background: var(--mac-scrollbar-thumb) !important;
  pointer-events: auto;
}

.file-editor-float :deep(.monaco-scrollable-element > .scrollbar:hover > .slider) {
  background: var(--mac-scrollbar-thumb-hover) !important;
}

.editor-resize-handle {
  position: absolute;
  right: 0;
  bottom: 0;
  width: 14px;
  height: 14px;
  cursor: nwse-resize;
  z-index: 5;
  pointer-events: auto;
  background: linear-gradient(135deg, transparent 50%, rgba(0, 0, 0, 0.18) 50%);
}

.file-editor-float--dark .editor-resize-handle {
  background: linear-gradient(135deg, transparent 50%, rgba(255, 255, 255, 0.25) 50%);
}

.file-editor-float--dark .editor-tabs-actions {
  background: var(--editor-header-bg, #141414);
}

.file-editor-float--dark {
  --editor-border: #434343;
  --editor-bg: #1f1f1f;
  --editor-header-bg: #141414;
  --editor-tabs-bg: #262626;
  --mac-scrollbar-thumb: rgba(255, 255, 255, 0.28);
  --mac-scrollbar-thumb-hover: rgba(255, 255, 255, 0.45);
}

.file-editor-float--dark .editor-tab {
  color: #a6a6a6;
}

.file-editor-float--dark .editor-tab.active {
  background: var(--editor-bg, #1f1f1f);
  color: #69b1ff;
}

.file-editor-float--dark .editor-tab:hover {
  background: rgba(255, 255, 255, 0.06);
}

.file-editor-float--dark .editor-path-row {
  background: var(--editor-bg, #1f1f1f);
}

.file-editor-float--dark .editor-path-text {
  color: #8c8c8c;
}

.file-editor-float--dark .editor-loading {
  background: rgba(0, 0, 0, 0.5);
}
</style>

<style>
/* fixedOverflowWidgets renders find/replace on document.body */
.monaco-editor .find-widget {
  z-index: 12000 !important;
}

/* Find-widget button hovers pinned below via JS (termiscope-find-hover-below). */
.context-view.termiscope-find-hover-below {
  pointer-events: none !important;
  z-index: 12001 !important;
}

.context-view.termiscope-find-hover-below .workbench-hover-pointer {
  display: none !important;
}
</style>
