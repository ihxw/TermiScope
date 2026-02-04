<template>
  <div class="sftp-browser">
    <div class="browser-header">
      <div class="header-actions">
        <a-button size="small" @click="refresh">
          <template #icon><ReloadOutlined /></template>
        </a-button>
        <a-button size="small" :disabled="!clipboard.source" @click="paste">
          <template #icon><SnippetsOutlined /></template>
          {{ t('sftp.paste') }}
        </a-button>
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
        >
          <a-button size="small" type="primary">
            <template #icon><UploadOutlined /></template>
            {{ t('sftp.upload') }}
          </a-button>
        </a-upload>
      </div>
      <a-breadcrumb separator=">" size="small" style="flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
        <a-breadcrumb-item v-for="(part, index) in pathParts" :key="index">
          <a @click="navigateTo(index)">{{ part || '/' }}</a>
        </a-breadcrumb-item>
      </a-breadcrumb>
    </div>

    <div class="browser-content">
      <a-table
        :loading="loading"
        :columns="columns"
        :data-source="files"
        :pagination="false"
        size="small"
        :scroll="{ y: 'calc(100vh - 150px)' }"
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

    <FileEditor
        v-model:open="editorVisible"
        :host-id="hostId"
        :file-path="editingFile.path"
        :file-name="editingFile.name"
        @saved="onEditorSaved"
    />
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch, h, reactive } from 'vue'
import { message, notification, Progress } from 'ant-design-vue'
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
  EyeOutlined
} from '@ant-design/icons-vue'
import { listFiles, uploadFile, downloadFile, deleteFile, renameFile, pasteFile, createDirectory, createFile, getDirSize } from '../api/sftp'
import { useI18n } from 'vue-i18n'
import FileEditor from './FileEditor.vue'

const { t } = useI18n()
const props = defineProps({
  hostId: {
    type: [String, Number],
    required: true
  },
  visible: {
    type: Boolean,
    default: false
  }
})

const currentPath = ref('.')
const files = ref([])
const loading = ref(false)
const clipboard = reactive({
    source: null,
    type: null // 'cut' or 'copy'
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
           window.URL.revokeObjectURL(previewSrc.value)
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
  { title: t('sftp.size'), key: 'size', align: 'right', sorter: (a, b) => a.size - b.size }
])

const loadFiles = async () => {
  if (!props.hostId) return
  loading.value = true
  try {
    const data = await listFiles(props.hostId, currentPath.value)
    // Handle new response format { files: [], cwd: '/...' }
    if (data && data.files) {
        files.value = data.files.map(f => ({ ...f, size: f.is_dir ? null : f.size })) // Init dir size as null/loading
        if (data.cwd) {
            currentPath.value = data.cwd
        }
    } else if (Array.isArray(data)) {
        files.value = data.map(f => ({ ...f, size: f.is_dir ? null : f.size }))
    } else {
        files.value = []
    }
    
    // Asynchronously fetch folder sizes
    files.value.forEach(async (file, index) => {
        if (file.is_dir) {
            try {
                const res = await getDirSize(props.hostId, currentPath.value === '.' ? file.name : `${currentPath.value}/${file.name}`)
                if (res && res.size !== undefined) {
                    files.value[index].size = res.size
                }
            } catch (err) {
                console.error(`Failed to get size for ${file.name}`, err)
                files.value[index].size = -1 // Mark as failed
            }
        }
    })
  } catch (error) {
    console.error('Failed to list files:', error)
  } finally {
    loading.value = false
  }
}

const refresh = () => {
  if (loading.value) return
  loadFiles()
}

const enterDir = (name) => {
  if (loading.value) return
  if (currentPath.value === '.') {
    currentPath.value = name
  } else {
    currentPath.value = currentPath.value.endsWith('/') 
      ? currentPath.value + name 
      : currentPath.value + '/' + name
  }
  loadFiles()
}

const navigateTo = (index) => {
  if (loading.value) return
  
  if (index === 0) {
    // If absolute path (starts with /), index 0 is Root.
    if (currentPath.value.startsWith('/')) {
        currentPath.value = '/'
    } else {
        // Relative logic
        currentPath.value = '.'
    }
  } else {
    // Reconstruct path from parts
    const parts = pathParts.value.slice(0, index + 1)
    
    // If absolute, parts[0] is ''. parts.join('/') -> '/home/...'
    let newPath = parts.join('/')
    if (newPath === '') newPath = '/' // Handle root edge case
    
    // If relative, parts[0] is also '' (added in computed). 
    // Wait, relative path 'foo/bar'. pathParts=['', 'foo', 'bar'].
    // index 1 ('foo'). slice(0, 2) -> ['', 'foo']. join('/') -> '/foo'.
    // This turns relative into absolute logic?
    // If currentPath was '.', we return [''].
    
    // If we are in relative mode, maybe we strictly shouldn't show leading slash?
    // But backend now returns absolute 'cwd' always. 
    // So we will flip to absolute mode immediately after first load.
    // So 'join' works fine.
    currentPath.value = newPath
  }
  loadFiles()
}

const handleUpload = async ({ file, onSuccess, onError }) => {
  const key = `upload-${Date.now()}`
  try {
    notification.open({
        key,
        message: 'Uploading...',
        description: h('div', [
            h(Progress, { percent: 0, status: 'active', size: 'small' }),
            h('div', { style: 'margin-top: 8px' }, file.name)
        ]),
        duration: 0,
        placement: 'bottomRight'
    })

    const startTime = Date.now()
    await uploadFile(props.hostId, currentPath.value, file, (percent) => {
        const elapsed = (Date.now() - startTime) / 1000 // seconds
        const uploaded = (percent / 100) * file.size
        const speed = elapsed > 0 ? uploaded / elapsed : 0
        const speedStr = speed > 1024 * 1024 
            ? (speed / (1024 * 1024)).toFixed(2) + ' MB/s' 
            : (speed / 1024).toFixed(2) + ' KB/s'

        notification.open({
            key,
            message: t('sftp.uploading'),
            description: h('div', [
                h(Progress, { percent: percent, status: 'active', size: 'small' }),
                h('div', { style: 'display: flex; justify-content: space-between; margin-top: 8px' }, [
                    h('span', { style: 'color: #8c8c8c; font-size: 12px' }, file.name),
                    h('span', { style: 'color: #1890ff; font-weight: 500; font-size: 12px' }, speedStr)
                ])
            ]),
            duration: 0,
            placement: 'bottomRight'
        })
    })
    
    notification.success({
        key,
        message: t('sftp.uploadComplete'),
        description: t('sftp.uploadSuccess', { name: file.name }),
        duration: 3,
        placement: 'bottomRight'
    })
    
    loadFiles()
    onSuccess()
  } catch (error) {
    notification.error({
        key,
        message: t('sftp.uploadFailed'),
        description: error.message || t('sftp.uploadFailed'),
        duration: 4.5,
        placement: 'bottomRight'
    })
    onError(error)
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

const cut = (name) => {
    const fullPath = currentPath.value === '.' ? name : `${currentPath.value}/${name}`
    clipboard.source = fullPath
    clipboard.type = 'cut'
    message.info(t('sftp.cutMsg', { name }))
}

const copy = (name) => {
    const fullPath = currentPath.value === '.' ? name : `${currentPath.value}/${name}`
    clipboard.source = fullPath
    clipboard.type = 'copy'
    message.info(t('sftp.copyMsg', { name }))
}

const paste = async () => {
    if (!clipboard.source) return
    try {
        await pasteFile(props.hostId, clipboard.source, currentPath.value, clipboard.type)
        message.success(t('sftp.pasted'))
        loadFiles()
        if (clipboard.type === 'cut') {
            clipboard.source = null
            clipboard.type = null
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

watch(() => props.visible, (newVal) => {
  if (newVal && files.value.length === 0) {
    loadFiles()
  }
})

onMounted(() => {
  if (props.visible) {
    loadFiles()
  }
})
</script>

<style scoped>
.sftp-browser {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.browser-header {
  display: flex;
  justify-content: flex-start;
  align-items: center;
  margin-bottom: 8px;
  padding: 4px 0;
  gap: 16px;
}

.header-actions {
  display: flex;
  gap: 8px;
}

.browser-content {
  flex: 1;
  overflow: hidden; /* Let table handle scrolling */
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
</style>
