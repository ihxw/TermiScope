<template>
  <a-modal
    v-model:open="visible"
    :title="title"
    width="80%"
    :footer="null"
    :maskClosable="false"
    :destroyOnClose="true"
    @cancel="handleCancel"
    class="file-editor-modal"
  >
    <a-spin :spinning="loading">
      <div class="editor-container">
        <div ref="editorRef" class="editor-instance"></div>
      </div>
    </a-spin>
    <div class="editor-footer">
      <a-space>
        <span class="file-info" v-if="fileSize">{{ formatSize(fileSize) }}</span>
      </a-space>
      <a-space>
        <a-button @click="handleCancel">{{ t('common.cancel') }}</a-button>
        <a-button type="primary" :loading="saving" @click="saveFile">
          {{ t('common.save') }}
        </a-button>
      </a-space>
    </div>
  </a-modal>
</template>

<script setup>
import { ref, shallowRef, onMounted, onBeforeUnmount, watch, nextTick, computed } from 'vue'
import * as monaco from 'monaco-editor'
import { message } from 'ant-design-vue'
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
        automaticLayout: false, // automaticLayout can cause freezes with modals/destroyOnClose
        minimap: { enabled: true },
        scrollBeyondLastLine: false,
        fontSize: 14
    })
    
    // Manual layout handling
    window.addEventListener('resize', handleResize)
}

// Watch theme changes
watch(() => themeStore.isDark, (isDark) => {
    if (editorInstance.value) {
        monaco.editor.setTheme(isDark ? 'vs-dark' : 'vs-light')
    }
})

const handleResize = () => {
    if (editorInstance.value) {
        editorInstance.value.layout()
    }
}

const loadFileContent = async () => {
    if (!props.hostId || !props.filePath) return
    loading.value = true
    try {
        // Download as blob
        const response = await downloadFile(props.hostId, props.filePath)
        
        // Convert blob to text
        const text = await response.text()
        content.value = text
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
        emit('saved')
        handleCancel() // Close on save? Or keep open? User preference usually keep open, but modal style implies close.
        // Let's close for now to be safe.
    } catch (error) {
        message.error(t('sftp.uploadFailed') + ': ' + (error.message || 'Unknown error'))
    } finally {
        saving.value = false
    }
}

const handleCancel = () => {
    visible.value = false
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
        window.removeEventListener('resize', handleResize)
    }
})

onBeforeUnmount(() => {
    if (editorInstance.value) {
        editorInstance.value.dispose()
    }
    window.removeEventListener('resize', handleResize)
})
</script>

<style scoped>
.editor-container {
    height: 70vh;
    border: 1px solid #d9d9d9;
    border-radius: 4px;
    margin-bottom: 16px;
    overflow: hidden;
}

.editor-instance {
    width: 100%;
    height: 100%;
}

.editor-footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.file-info {
    color: #8c8c8c;
    font-size: 12px;
}
</style>
