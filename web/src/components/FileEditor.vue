<template>
  <Teleport to="body">
    <div
      v-if="visible"
      class="file-editor-float"
      :class="{ 'file-editor-float--dark': themeStore.isDark }"
      :style="panelStyle"
      @mousedown="bringToFront"
    >
      <div
        class="editor-header"
        @mousedown="startDrag"
      >
        <div class="editor-header-left">
          <span class="editor-title">{{ displayTitle }}</span>
          <span v-if="fileSize" class="file-info">{{ formatSize(fileSize) }}</span>
        </div>
        <a-space>
          <a-tooltip :title="t('sftp.searchReplace')">
            <a-button size="small" @mousedown.stop @click="triggerFindReplace">
              <template #icon><SearchOutlined /></template>
            </a-button>
          </a-tooltip>
          <a-tooltip v-if="dirty" :title="t('sftp.saveShortcut')">
            <a-button size="small" type="primary" :loading="saving" @mousedown.stop @click="saveFile">
              {{ t('common.save') }}
            </a-button>
          </a-tooltip>
          <a-button size="small" @mousedown.stop @click="handleClose">
            <template #icon><CloseOutlined /></template>
          </a-button>
        </a-space>
      </div>
      <div class="editor-body">
        <div v-if="loading" class="editor-loading">
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
  open: {
    type: Boolean,
    default: false
  },
  hostId: {
    type: [String, Number],
    required: true
  },
  filePath: {
    type: String,
    required: true
  },
  fileName: {
    type: String,
    required: true
  }
})

const emit = defineEmits(['update:open', 'saved'])
const { t } = useI18n()
const themeStore = useThemeStore()

const visible = computed({
  get: () => props.open,
  set: (val) => emit('update:open', val)
})

const editorRef = ref(null)
const editorInstance = shallowRef(null)
let contentChangeDisposable = null
let saveCommandDisposable = null

const loading = ref(false)
const saving = ref(false)
const dirty = ref(false)
const savedContent = ref('')
const fileSize = ref(0)

const panelW = 760
const panelH = 520
const panelX = ref(80)
const panelY = ref(80)
const zIndex = ref(1100)

const displayTitle = computed(() => {
  const prefix = dirty.value ? '● ' : ''
  return `${prefix}${props.fileName}`
})

const panelStyle = computed(() => ({
  left: `${panelX.value}px`,
  top: `${panelY.value}px`,
  width: `${panelW}px`,
  height: `${panelH}px`,
  zIndex: zIndex.value,
}))

let dragState = null

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

const updateDirty = () => {
  if (!editorInstance.value) {
    dirty.value = false
    return
  }
  dirty.value = editorInstance.value.getValue() !== savedContent.value
}

const initEditor = () => {
  if (editorInstance.value) return

  editorInstance.value = monaco.editor.create(editorRef.value, {
    value: savedContent.value,
    language: getLanguage(props.fileName),
    theme: themeStore.isDark ? 'vs-dark' : 'vs-light',
    automaticLayout: true,
    minimap: { enabled: true },
    scrollBeyondLastLine: false,
    fontSize: 14,
  })

  contentChangeDisposable = editorInstance.value.onDidChangeModelContent(() => {
    updateDirty()
  })

  saveCommandDisposable = editorInstance.value.addCommand(
    monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS,
    () => {
      if (dirty.value) saveFile()
    }
  )
}

const disposeEditor = () => {
  contentChangeDisposable?.dispose()
  contentChangeDisposable = null
  saveCommandDisposable = null
  if (editorInstance.value) {
    editorInstance.value.dispose()
    editorInstance.value = null
  }
  dirty.value = false
}

watch(() => themeStore.isDark, (isDark) => {
  if (editorInstance.value) {
    monaco.editor.setTheme(isDark ? 'vs-dark' : 'vs-light')
  }
})

const loadFileContent = async () => {
  if (!props.hostId || !props.filePath) return
  loading.value = true
  dirty.value = false
  try {
    const response = await downloadFile(props.hostId, props.filePath)
    const text = await response.text()
    savedContent.value = text
    fileSize.value = response.size

    await nextTick()
    if (!editorInstance.value) {
      initEditor()
    }
    editorInstance.value.setValue(text)
    monaco.editor.setModelLanguage(editorInstance.value.getModel(), getLanguage(props.fileName))
    updateDirty()
  } catch (error) {
    message.error(t('sftp.downloadFailed') + ': ' + (error.message || 'Unknown error'))
    visible.value = false
  } finally {
    loading.value = false
  }
}

const saveFile = async () => {
  if (!editorInstance.value || !dirty.value || saving.value) return
  saving.value = true
  const newContent = editorInstance.value.getValue()
  const blob = new Blob([newContent], { type: 'text/plain' })
  const file = new File([blob], props.fileName, { type: 'text/plain' })

  const lastSlashIndex = props.filePath.lastIndexOf('/')
  let targetDir = lastSlashIndex !== -1 ? props.filePath.substring(0, lastSlashIndex) : '.'
  if (props.filePath.startsWith('/') && targetDir === '') {
    targetDir = '/'
  }

  try {
    await uploadFile(props.hostId, targetDir, file)
    message.success(t('sftp.uploadComplete'))
    savedContent.value = newContent
    fileSize.value = blob.size
    updateDirty()
    emit('saved')
  } catch (error) {
    message.error(t('sftp.uploadFailed') + ': ' + (error.message || 'Unknown error'))
  } finally {
    saving.value = false
  }
}

const confirmClose = () => {
  if (dirty.value) {
    Modal.confirm({
      title: t('sftp.unsavedTitle'),
      content: t('sftp.unsavedContent'),
      okText: t('sftp.unsavedLeave'),
      cancelText: t('common.cancel'),
      onOk() {
        visible.value = false
      },
    })
  } else {
    visible.value = false
  }
}

const handleClose = () => {
  confirmClose()
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
  if (!visible.value || !dirty.value) return
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
    e.preventDefault()
    saveFile()
  }
}

watch(
  () => props.open,
  (val) => {
    if (val) {
      centerPanel()
      bringToFront()
      nextTick(() => loadFileContent())
      window.addEventListener('keydown', onGlobalKeyDown, true)
    } else {
      window.removeEventListener('keydown', onGlobalKeyDown, true)
      disposeEditor()
    }
  },
  { immediate: true }
)

onBeforeUnmount(() => {
  window.removeEventListener('keydown', onGlobalKeyDown, true)
  stopDrag()
  disposeEditor()
})
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

.editor-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 6px 10px;
  border-bottom: 1px solid var(--editor-border, #d9d9d9);
  flex-shrink: 0;
  cursor: move;
  user-select: none;
  background: var(--editor-header-bg, #fafafa);
}

.editor-header-left {
  display: flex;
  align-items: center;
  gap: 10px;
  overflow: hidden;
  min-width: 0;
  flex: 1;
}

.editor-title {
  font-weight: 500;
  font-size: 13px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
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
  flex-shrink: 0;
}

.file-editor-float--dark {
  --editor-border: #434343;
  --editor-bg: #1f1f1f;
  --editor-header-bg: #141414;
}

.file-editor-float--dark .editor-loading {
  background: rgba(0, 0, 0, 0.5);
}
</style>
