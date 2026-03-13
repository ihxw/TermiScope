<template>
  <div class="command-management">
    <a-card title="Command Templates" :bordered="false" size="small">
      <template #extra>
        <a-button type="primary" size="small" @click="showAddModal">
          <template #icon><PlusOutlined /></template>
          Add Template
        </a-button>
      </template>

      <a-table
        :columns="columns"
        :data-source="templates"
        :loading="loading"
        size="small"
        row-key="id"
      >
        <template #bodyCell="{ column, record }">
          <template v-if="column.key === 'command'">
            <code>{{ record.command }}</code>
          </template>
          <template v-else-if="column.key === 'action'">
            <a-space size="small">
              <a-button size="small" type="link" @click="editTemplate(record)">Edit</a-button>
              <a-popconfirm
                title="Are you sure to delete this template?"
                @confirm="handleDelete(record.id)"
              >
                <a-button size="small" type="link" danger>Delete</a-button>
              </a-popconfirm>
            </a-space>
          </template>
        </template>
      </a-table>
    </a-card>

    <!-- Add/Edit Modal -->
    <a-modal
      v-model:open="modalVisible"
      :title="editingId ? 'Edit Template' : 'Add Template'"
      @ok="handleModalOk"
      :confirmLoading="modalLoading"
      size="small"
    >
      <a-form layout="vertical" :model="formState">
        <a-form-item label="Name" required>
          <a-input v-model:value="formState.name" placeholder="e.g. Check Disk Space" />
        </a-form-item>
        <a-form-item label="Command" required>
          <a-textarea v-model:value="formState.command" placeholder="df -h" :rows="3" />
        </a-form-item>
        <a-form-item label="Description">
          <a-input v-model:value="formState.description" placeholder="Optional description" />
        </a-form-item>
      </a-form>
    </a-modal>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from 'vue'
import { message } from 'ant-design-vue'
import { PlusOutlined } from '@ant-design/icons-vue'
import { listCommandTemplates, createCommandTemplate, updateCommandTemplate, deleteCommandTemplate } from '../api/command'

const templates = ref([])
const loading = ref(false)
const modalVisible = ref(false)
const modalLoading = ref(false)
const editingId = ref(null)

const formState = reactive({
  name: '',
  command: '',
  description: ''
})

const columns = [
  { title: 'Name', dataIndex: 'name', key: 'name', sorter: (a, b) => a.name.localeCompare(b.name) },
  { title: 'Command', dataIndex: 'command', key: 'command' },
  { title: 'Description', dataIndex: 'description', key: 'description' },
  { title: 'Action', key: 'action', width: 120 }
]

const loadTemplates = async () => {
  loading.value = true
  try {
    const data = await listCommandTemplates()
    templates.value = data || []
  } catch (error) {
    console.error('Failed to load templates:', error)
  } finally {
    loading.value = false
  }
}

const showAddModal = () => {
  editingId.value = null
  formState.name = ''
  formState.command = ''
  formState.description = ''
  modalVisible.value = true
}

const editTemplate = (record) => {
  editingId.value = record.id
  formState.name = record.name
  formState.command = record.command
  formState.description = record.description
  modalVisible.value = true
}

const handleModalOk = async () => {
  if (!formState.name || !formState.command) {
    message.error('Name and Command are required')
    return
  }

  modalLoading.value = true
  try {
    if (editingId.value) {
      await updateCommandTemplate(editingId.value, formState)
      message.success('Template updated')
    } else {
      await createCommandTemplate(formState)
      message.success('Template created')
    }
    modalVisible.value = false
    loadTemplates()
  } catch (error) {
    console.error('Failed to save template:', error)
  } finally {
    modalLoading.value = false
  }
}

const handleDelete = async (id) => {
  try {
    await deleteCommandTemplate(id)
    message.success('Template deleted')
    loadTemplates()
  } catch (error) {
    console.error('Failed to delete template:', error)
  }
}

onMounted(loadTemplates)
</script>

<style scoped>
.command-management {
  padding: 0;
}

code {
  padding: 2px 6px;
  border-radius: 4px;
  font-family: 'Courier New', Courier, monospace;
  font-size: 13px;
}

/* Light theme code style */
.light-theme code {
  background: #f0f0f0;
  color: #c41d7f; /* Standard code color in light mode */
}

/* Dark theme code style */
.dark-theme code {
  background: #262626;
  color: #ff7875; /* Brighter color for visibility in dark mode */
  border: 1px solid #434343;
}

/* Mobile responsive */
@media (max-width: 768px) {
  .command-management {
    padding: 8px;
  }
  
  .command-management :deep(.ant-card-head) {
    padding: 0 12px;
  }
  
  .command-management :deep(.ant-table) {
    font-size: 12px;
  }
  
  .command-management :deep(.ant-table-thead > tr > th),
  .command-management :deep(.ant-table-tbody > tr > td) {
    padding: 8px 6px !important;
  }
  
  code {
    font-size: 11px;
    word-break: break-all;
  }
}
</style>
