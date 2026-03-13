<template>
  <div v-if="visible" class="file-editor-inline">
    <div class="editor-header">
      <div class="editor-header-left">
        <a-button size="small" @click="handleCancel">
          <template #icon><ArrowLeftOutlined /></template>
          {{ t('sftp.backToList') }}
        </a-button>
        <span class="editor-title">{{ title }}</span>
        <span class="file-info" v-if="fileSize">{{ formatSize(fileSize) }}</span>
      </div>
      <a-space>
        <a-tooltip :title="t('sftp.searchReplace')">
          <a-button size="small" @click="triggerFindReplace">
            <template #icon><SearchOutlined /></template>
          </a-button>
        </a-tooltip>
        <a-button size="small" type="primary" :loading="saving" @click="saveFile">
          {{ t('common.save') }}
        </a-button>
        <a-button size="small" @click="handleClose">
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
</template>

<script setup>
import { ref, shallowRef, onBeforeUnmount, watch, nextTick, computed } from 'vue'
import * as monaco from 'monaco-editor'
import { message, Modal } from 'ant-design-vue'
import { ArrowLeftOutlined, SearchOutlined, CloseOutlined } from '@ant-design/icons-vue'
import { downloadFile, uploadFile } from '../api/sftp'
import { useI18n } from 'vue-i18n'
import { useThemeStore } from '../stores/theme'

// Since we are using Vite, we might need to configure workers.
// For simplicity in this step, we will rely on basic setup. 
// If it fails, we might need a worker loader.
import editorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker'
import jsonWorker from 'monaco-editor/esm/vs/language/json/json.worker?worker'
import cssWorker from 'monaco-editor/esm/vs/language/css/css.worker?worker'
import htmlWorker from 'monaco-editor/esm/vs/language/html/html.worker?worker'
import tsWorker from 'monaco-editor/esm/vs/language/typescript/ts.worker?worker'

self.MonacoEnvironment = {
  getWorker(_, label) {
    if (label === 'json') {
      return new jsonWorker()
    }
    if (label === 'css' || label === 'scss' || label === 'less') {
      return new cssWorker()
    }
    if (label === 'html' || label === 'handlebars' || label === 'razor') {
      return new htmlWorker()
    }
    if (label === 'typescript' || label === 'javascript') {
      return new tsWorker()
    }
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
const loading = ref(false)
const saving = ref(false)
const content = ref('')
const savedContent = ref('') // baseline for dirty check
const fileSize = ref(0) // bytes

const title = computed(() => `${t('sftp.edit')}: ${props.fileName}`)

// Language detection
const getLanguage = (filename) => {
  const ext = filename.split('.').pop().toLowerCase()
  const map = {
    'js': 'javascript',
    'ts': 'typescript',
    'py': 'python',
    'html': 'html',
    'css': 'css',
    'json': 'json',
    'md': 'markdown',
    'sql': 'sql',
    'xml': 'xml',
    'yaml': 'yaml',
    'yml': 'yaml',
    'sh': 'shell',
    'bash': 'shell',
    'go': 'go',
    'java': 'java',
    'c': 'c',
    'cpp': 'cpp',
    'rs': 'rust',
    'php': 'php',
    'rb': 'ruby',
    'lua': 'lua',
    'ini': 'ini',
    'conf': 'ini',
    'vue': 'html', // Highlight as HTML for now
    'dockerfile': 'dockerfile'
  }
  return map[ext] || 'plaintext'
}

const initEditor = () => {
    if (editorInstance.value) return;
    
    editorInstance.value = monaco.editor.create(editorRef.value, {
        value: content.value,
        language: getLanguage(props.fileName),
        theme: themeStore.isDark ? 'vs-dark' : 'vs-light',
        automaticLayout: true,
        minimap: { enabled: true },
        scrollBeyondLastLine: false,
        fontSize: 14
    })
}

// Watch theme changes
watch(() => themeStore.isDark, (isDark) => {
    if (editorInstance.value) {
        monaco.editor.setTheme(isDark ? 'vs-dark' : 'vs-light')
    }
})

const loadFileContent = async () => {
    if (!props.hostId || !props.filePath) return
    loading.value = true
    try {
        // Download as blob
        const response = await downloadFile(props.hostId, props.filePath)
        
        // Convert blob to text
        const text = await response.text()
        content.value = text
        savedContent.value = text
        fileSize.value = response.size
        
        if (editorInstance.value) {
            editorInstance.value.setValue(text)
            monaco.editor.setModelLanguage(editorInstance.value.getModel(), getLanguage(props.fileName))
        } else {
            initEditor()
        }
    } catch (error) {
        message.error(t('sftp.downloadFailed') + ': ' + (error.message || 'Unknown error'))
        handleCancel()
    } finally {
        loading.value = false
    }
}

const saveFile = async () => {
    if (!editorInstance.value) return
    saving.value = true
    const newContent = editorInstance.value.getValue()
    const blob = new Blob([newContent], { type: 'text/plain' })
    const file = new File([blob], props.fileName, { type: 'text/plain' }) // Mock file object
    
    // We need parent path. file path is full path?
    // props.filePath includes filename? Yes likely.
    // Wait, uploadFile takes `path` as directory path?
    // Let's check api/sftp.js: formData.append('path', path); formData.append('file', file)
    // backend: filepath.Join(remotePath, header.Filename)
    // So if props.filePath is "/home/user/foo.txt", we need to pass "/home/user" as path, and file.name="foo.txt"
    
    const lastSlashIndex = props.filePath.lastIndexOf('/')
    const dirPath = lastSlashIndex !== -1 ? props.filePath.substring(0, lastSlashIndex) : '.'
    // If root file "/foo.txt", lastSlash is 0. substring(0,0) is empty. Should be "/"?
    // If path is "/opt", last is 0. sub is "".
    // If path is "foo.txt", last is -1. sub is ".".
    
    let targetDir = dirPath
    if (props.filePath.startsWith('/') && targetDir === '') {
        targetDir = '/'
    }
    
    try {
        await uploadFile(props.hostId, targetDir, file)
        message.success(t('sftp.uploadComplete'))
        // Update saved baseline so dirty check works correctly
        savedContent.value = newContent
        emit('saved')
    } catch (error) {
        message.error(t('sftp.uploadFailed') + ': ' + (error.message || 'Unknown error'))
    } finally {
        saving.value = false
    }
}

const isDirty = () => {
    if (!editorInstance.value) return false
    return editorInstance.value.getValue() !== savedContent.value
}

const confirmClose = () => {
    if (isDirty()) {
        Modal.confirm({
            title: t('sftp.unsavedTitle'),
            content: t('sftp.unsavedContent'),
            okText: t('sftp.unsavedLeave'),
            cancelText: t('common.cancel'),
            onOk() {
                visible.value = false
            }
        })
    } else {
        visible.value = false
    }
}

const handleCancel = () => {
    confirmClose()
}

const handleClose = () => {
    confirmClose()
}

const triggerFindReplace = () => {
    if (editorInstance.value) {
        editorInstance.value.getAction('editor.action.startFindReplaceAction').run()
    }
}

const formatSize = (bytes) => {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

watch(() => props.open, (val) => {
    if (val) {
        nextTick(() => {
            loadFileContent()
        })
    } else {
        if (editorInstance.value) {
            editorInstance.value.dispose()
            editorInstance.value = null
        }
    }
}, { immediate: true })

onBeforeUnmount(() => {
    if (editorInstance.value) {
        editorInstance.value.dispose()
    }
})
</script>

<style scoped>
.file-editor-inline {
    display: flex;
    flex-direction: column;
    height: 100%;
    overflow: hidden;
}

.editor-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 6px 8px;
    border-bottom: 1px solid #d9d9d9;
    flex-shrink: 0;
}

.editor-header-left {
    display: flex;
    align-items: center;
    gap: 10px;
    overflow: hidden;
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
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
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
</style>
