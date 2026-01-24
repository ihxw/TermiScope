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
      <a-breadcrumb size="small" style="flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
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
            <span v-else>
              <FileOutlined style="color: #8c8c8c; margin-right: 8px" />
              {{ record.name }}
            </span>
          </template>
          <template v-else-if="column.key === 'size'">
            {{ record.is_dir ? '-' : formatSize(record.size) }}
          </template>
          <template v-else-if="column.key === 'action'">
            <a-space size="small">
              <a-button size="small" type="text" v-if="!record.is_dir" @click="download(record.name)">
                <template #icon><DownloadOutlined /></template>
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
  FileAddOutlined
} from '@ant-design/icons-vue'
import { listFiles, uploadFile, downloadFile, deleteFile, renameFile, pasteFile, createDirectory, createFile } from '../api/sftp'
import { useI18n } from 'vue-i18n'

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
  { title: t('sftp.name'), key: 'name', sorter: (a, b) => a.name.localeCompare(b.name) },
  { title: t('sftp.size'), key: 'size', align: 'right', sorter: (a, b) => a.size - b.size },
  { title: t('sftp.action'), key: 'action', width: 80, align: 'center' }
])

const loadFiles = async () => {
  if (!props.hostId) return
  loading.value = true
  try {
    const data = await listFiles(props.hostId, currentPath.value)
    // Handle new response format { files: [], cwd: '/...' }
    if (data && data.files) {
        files.value = data.files
        if (data.cwd) {
            currentPath.value = data.cwd
        }
    } else if (Array.isArray(data)) {
        // Fallback for old API response (if cached or something)
        files.value = data
    } else {
        files.value = []
    }
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

    await uploadFile(props.hostId, currentPath.value, file, (percent) => {
        notification.open({
            key,
            message: t('sftp.uploading'),
            description: h('div', [
                h(Progress, { percent: percent, status: 'active', size: 'small' }),
                h('div', { style: 'margin-top: 8px' }, file.name)
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

    const response = await downloadFile(props.hostId, fullPath, (percent) => {
         notification.open({
            key,
            message: t('sftp.downloading'),
            description: h('div', [
                h(Progress, { percent: percent, status: 'active', size: 'small' }),
                h('div', { style: 'margin-top: 8px' }, name)
            ]),
            duration: 0,
            placement: 'bottomRight'
        })
    })

    // Create blobs and trigger downloads
    const url = window.URL.createObjectURL(new Blob([response.data]))
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
