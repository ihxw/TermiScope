<template>
  <Teleport to="body">
    <div
      v-if="tabs.length > 0"
      class="file-editor-float"
      :class="{ 'file-editor-float--dark': themeStore.isDark }"
      :style="panelStyle"
      @mousedown="bringToFront"
    >
      <div class="editor-toolbar" @mousedown="startDrag">
        <span v-if="activeTab?.fileSize" class="file-info">{{ formatSize(activeTab.fileSize) }}</span>
        <a-space class="editor-toolbar-actions">
          <a-tooltip :title="t('sftp.searchReplace')">
            <a-button size="small" @mousedown.stop @click="triggerFindReplace">
              <template #icon><SearchOutlined /></template>
            </a-button>
          </a-tooltip>
          <a-tooltip v-if="activeTab?.dirty" :title="t('sftp.saveShortcut')">
            <a-button size="small" type="primary" :loading="activeTab?.saving" @mousedown.stop @click="saveActiveFile">
              {{ t('common.save') }}
            </a-button>
          </a-tooltip>
          <a-button size="small" @mousedown.stop @click="handleCloseAll">
            <template #icon><CloseOutlined /></template>
          </a-button>
        </a-space>
      </div>
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
      <div v-if="activeTab" class="editor-path-bar" :title="activeTab.path">
        {{ activeTab.path }}
      </div>
      <div class="editor-body">
        <div v-if="activeTab?.loading" class="editor-loading">
          <a-spin />
        </div>
        <div ref="editorRef" class="editor-instance"></div>
      </div>
    </div>
  </Teleport>
</template>

<script setup>
import { ref, shallowRef, onBeforeUnmount, watch, nextTick, computed } from 'vue'
import * as monaco from 'monaco-editor'
import { message, Modal } from 'ant-design-vue'
import { SearchOutlined, CloseOutlined } from '@ant-design/icons-vue'
import { downloadFile, uploadFile } from '../api/sftp'
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
})

const emit = defineEmits(['saved'])
const { t } = useI18n()
const themeStore = useThemeStore()

/** @typedef {{ key: string, path: string, name: string, dirty: boolean, loading: boolean, saving: boolean, savedContent: string, fileSize: number, model: import('monaco-editor').editor.ITextModel | null, changeDisposable: import('monaco-editor').IDisposable | null }} EditorTab */

/** @type {import('vue').Ref<EditorTab[]>} */
const tabs = ref([])
const activeKey = ref(null)

const editorRef = ref(null)
const editorInstance = shallowRef(null)
let saveCommandDisposable = null

const panelW = 800
const panelH = 540
const panelX = ref(80)
const panelY = ref(80)
const zIndex = ref(1100)

const activeTab = computed(() => tabs.value.find((tab) => tab.key === activeKey.value) ?? null)

const panelStyle = computed(() => ({
  left: `${panelX.value}px`,
  top: `${panelY.value}px`,
  width: `${panelW}px`,
  height: `${panelH}px`,
  zIndex: zIndex.value,
}))

let dragState = null

const tabLabel = (tab) => (tab.dirty ? `● ${tab.name}` : tab.name)

const startDrag = (e) => {
  if (e.button !== 0) return
  if (e.target.closest('button') || e.target.closest('.ant-btn')) return
  e.preventDefault()
  dragState = {
    startX: e.clientX,
    startY: e.clientY,
    originX: panelX.value,
    originY: panelY.value,
  }
  document.addEventListener('mousemove', onDrag)
  document.addEventListener('mouseup', stopDrag)
}

const onDrag = (e) => {
  if (!dragState) return
  const dx = e.clientX - dragState.startX
  const dy = e.clientY - dragState.startY
  const maxX = Math.max(0, window.innerWidth - 200)
  const maxY = Math.max(0, window.innerHeight - 80)
  panelX.value = Math.min(maxX, Math.max(0, dragState.originX + dx))
  panelY.value = Math.min(maxY, Math.max(0, dragState.originY + dy))
}

const stopDrag = () => {
  dragState = null
  document.removeEventListener('mousemove', onDrag)
  document.removeEventListener('mouseup', stopDrag)
}

const bringToFront = () => {
  zIndex.value = Date.now()
}

const centerPanel = () => {
  panelX.value = Math.max(24, Math.round((window.innerWidth - panelW) / 2))
  panelY.value = Math.max(24, Math.round((window.innerHeight - panelH) / 2))
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

const updateTabDirty = (tab) => {
  if (!tab.model) {
    tab.dirty = false
    return
  }
  tab.dirty = tab.model.getValue() !== tab.savedContent
}

const ensureEditor = () => {
  if (editorInstance.value) return

  editorInstance.value = monaco.editor.create(editorRef.value, {
    value: '',
    language: 'plaintext',
    theme: themeStore.isDark ? 'vs-dark' : 'vs-light',
    automaticLayout: true,
    minimap: { enabled: true },
    scrollBeyondLastLine: false,
    fontSize: 14,
  })

  saveCommandDisposable = editorInstance.value.addCommand(
    monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS,
    () => {
      if (activeTab.value?.dirty) saveActiveFile()
    }
  )
}

const attachModelToEditor = (tab) => {
  if (!tab?.model || !editorInstance.value) return
  if (editorInstance.value.getModel() !== tab.model) {
    editorInstance.value.setModel(tab.model)
  }
}

const switchTab = async (key) => {
  if (activeKey.value === key) return
  activeKey.value = key
  await nextTick()
  attachModelToEditor(activeTab.value)
}

const initEditorIfNeeded = async () => {
  await nextTick()
  ensureEditor()
  attachModelToEditor(activeTab.value)
}

const loadTabContent = async (tab) => {
  if (!props.hostId || !tab.path) return
  tab.loading = true
  tab.dirty = false
  try {
    const response = await downloadFile(props.hostId, tab.path)
    const text = await response.text()
    tab.savedContent = text
    tab.fileSize = response.size

    if (tab.model) {
      tab.changeDisposable?.dispose()
      tab.model.dispose()
    }

    tab.model = monaco.editor.createModel(text, getLanguage(tab.name), modelUri(tab.path))
    tab.changeDisposable = tab.model.onDidChangeContent(() => updateTabDirty(tab))
    updateTabDirty(tab)

    if (activeKey.value === tab.key) {
      await initEditorIfNeeded()
    }
  } catch (error) {
    message.error(t('sftp.downloadFailed') + ': ' + (error.message || 'Unknown error'))
    removeTab(tab.key, true)
  } finally {
    tab.loading = false
  }
}

const openFile = async (filePath, fileName) => {
  const key = filePath
  const existing = tabs.value.find((tab) => tab.key === key)
  if (existing) {
    if (tabs.value.length === 1) centerPanel()
    bringToFront()
    await switchTab(key)
    return
  }

  if (tabs.value.length === 0) centerPanel()
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
    model: null,
    changeDisposable: null,
  }
  tabs.value.push(tab)
  activeKey.value = key
  await initEditorIfNeeded()
  await loadTabContent(tab)
}

const disposeTab = (tab) => {
  tab.changeDisposable?.dispose()
  tab.changeDisposable = null
  if (tab.model) {
    if (editorInstance.value?.getModel() === tab.model) {
      editorInstance.value.setModel(null)
    }
    tab.model.dispose()
    tab.model = null
  }
}

const removeTab = (key, force = false) => {
  const idx = tabs.value.findIndex((tab) => tab.key === key)
  if (idx === -1) return

  const tab = tabs.value[idx]
  disposeTab(tab)
  tabs.value.splice(idx, 1)

  if (tabs.value.length === 0) {
    activeKey.value = null
    return
  }

  if (activeKey.value === key || force) {
    const next = tabs.value[Math.min(idx, tabs.value.length - 1)]
    switchTab(next.key)
  }
}

const confirmDiscard = (content, onOk) => {
  Modal.confirm({
    title: t('sftp.unsavedTitle'),
    content,
    okText: t('sftp.unsavedLeave'),
    cancelText: t('common.cancel'),
    onOk,
  })
}

const closeTab = (key) => {
  const tab = tabs.value.find((t) => t.key === key)
  if (!tab) return
  if (tab.dirty) {
    confirmDiscard(t('sftp.unsavedContent'), () => removeTab(key))
  } else {
    removeTab(key)
  }
}

const hasDirtyTabs = () => tabs.value.some((tab) => tab.dirty)

const closeAllTabs = () => {
  tabs.value.forEach(disposeTab)
  tabs.value = []
  activeKey.value = null
}

const handleCloseAll = () => {
  if (hasDirtyTabs()) {
    confirmDiscard(t('sftp.unsavedCloseAll'), closeAllTabs)
  } else {
    closeAllTabs()
  }
}

const saveActiveFile = async () => {
  const tab = activeTab.value
  if (!tab?.model || !tab.dirty || tab.saving) return

  tab.saving = true
  const newContent = tab.model.getValue()
  const blob = new Blob([newContent], { type: 'text/plain' })
  const file = new File([blob], tab.name, { type: 'text/plain' })

  const lastSlashIndex = tab.path.lastIndexOf('/')
  let targetDir = lastSlashIndex !== -1 ? tab.path.substring(0, lastSlashIndex) : '.'
  if (tab.path.startsWith('/') && targetDir === '') {
    targetDir = '/'
  }

  try {
    await uploadFile(props.hostId, targetDir, file)
    message.success(t('sftp.uploadComplete'))
    tab.savedContent = newContent
    tab.fileSize = blob.size
    updateTabDirty(tab)
    emit('saved')
  } catch (error) {
    message.error(t('sftp.uploadFailed') + ': ' + (error.message || 'Unknown error'))
  } finally {
    tab.saving = false
  }
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

const disposeEditor = () => {
  saveCommandDisposable = null
  if (editorInstance.value) {
    editorInstance.value.dispose()
    editorInstance.value = null
  }
}

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

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onGlobalKeyDown, true)
  stopDrag()
  closeAllTabs()
  disposeEditor()
})

defineExpose({ openFile, closeAllTabs })
</script>

<style scoped>
.file-editor-float {
  position: fixed;
  display: flex;
  flex-direction: column;
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.18);
  border: 1px solid var(--editor-border, #d9d9d9);
  background: var(--editor-bg, #fff);
}

.editor-toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 4px 8px;
  border-bottom: 1px solid var(--editor-border, #d9d9d9);
  flex-shrink: 0;
  cursor: move;
  user-select: none;
  background: var(--editor-header-bg, #fafafa);
  min-height: 36px;
}

.editor-toolbar-actions {
  margin-left: auto;
}

.editor-tabs {
  display: flex;
  flex-shrink: 0;
  overflow-x: auto;
  overflow-y: hidden;
  background: var(--editor-tabs-bg, #f0f0f0);
  border-bottom: 1px solid var(--editor-border, #d9d9d9);
  scrollbar-width: thin;
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

.editor-path-bar {
  flex-shrink: 0;
  padding: 2px 12px 4px;
  font-size: 11px;
  line-height: 1.4;
  color: #8c8c8c;
  background: var(--editor-bg, #fff);
  border-bottom: 1px solid var(--editor-border, #d9d9d9);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  user-select: text;
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
  color: #8c8c8c;
  font-size: 12px;
  white-space: nowrap;
}

.file-editor-float--dark {
  --editor-border: #434343;
  --editor-bg: #1f1f1f;
  --editor-header-bg: #141414;
  --editor-tabs-bg: #262626;
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

.file-editor-float--dark .editor-path-bar {
  color: #8c8c8c;
  background: var(--editor-bg, #1f1f1f);
}

.file-editor-float--dark .editor-loading {
  background: rgba(0, 0, 0, 0.5);
}
</style>
