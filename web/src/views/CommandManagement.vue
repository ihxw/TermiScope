<template>
  <div class="command-management">
    <a-card :title="t('command.title')" :bordered="false" size="small">
      <template #extra>
        <a-button type="primary" size="small" @click="showAddModal">
          <template #icon><PlusOutlined /></template>
          {{ t('command.addTemplate') }}
        </a-button>
      </template>

      <DataLoadError
        v-if="loadError"
        :message="t('command.loadFailed')"
        :loading="loading"
        @retry="loadTemplates"
      />
      <a-table
        v-else
        :columns="columns"
        :data-source="templates"
        :loading="loading"
        :scroll="{ x: 760 }"
        size="small"
        row-key="id"
      >
        <template #bodyCell="{ column, record }">
          <template v-if="column.key === 'command'">
            <a-tooltip :title="record.command">
              <code class="command-code">{{ record.command }}</code>
            </a-tooltip>
          </template>
          <template v-else-if="column.key === 'auto_enter'">
            <a-tag :color="record.auto_enter ? 'green' : 'default'">
              {{ record.auto_enter ? t('command.autoEnterOn') : t('command.autoEnterOff') }}
            </a-tag>
          </template>
          <template v-else-if="column.key === 'description'">
            <span class="muted-text">{{ record.description || '-' }}</span>
          </template>
          <template v-else-if="column.key === 'action'">
            <a-space size="small">
              <a-button size="small" type="link" @click="editTemplate(record)">{{ t('common.edit') }}</a-button>
              <a-popconfirm
                :title="t('command.deleteConfirm')"
                @confirm="handleDelete(record.id)"
              >
                <a-button size="small" type="link" danger>{{ t('common.delete') }}</a-button>
              </a-popconfirm>
            </a-space>
          </template>
        </template>
      </a-table>
    </a-card>

    <!-- Add/Edit Modal -->
    <a-modal
      v-model:open="modalVisible"
      :title="editingId ? t('command.editTemplate') : t('command.addTemplate')"
      @ok="handleModalOk"
      :confirmLoading="modalLoading"
      size="small"
    >
      <a-form layout="vertical" :model="formState">
        <a-form-item :label="t('command.name')" required>
          <a-input v-model:value="formState.name" :placeholder="t('command.namePlaceholder')" />
        </a-form-item>
        <a-form-item :label="t('command.command')" required>
          <a-textarea
            v-model:value="formState.command"
            :placeholder="t('command.commandPlaceholder')"
            :rows="4"
            auto-size
          />
        </a-form-item>
        <a-form-item :label="t('command.autoEnter')" :extra="t('command.autoEnterHelp')">
          <a-switch v-model:checked="formState.auto_enter" />
        </a-form-item>
        <a-form-item :label="t('command.description')">
          <a-input v-model:value="formState.description" :placeholder="t('command.descriptionPlaceholder')" />
        </a-form-item>
      </a-form>
    </a-modal>
  </div>
</template>

<script setup>
defineOptions({ name: 'CommandManagement' })
import { ref, reactive, onMounted, computed } from 'vue'
import { message } from 'ant-design-vue'
import { PlusOutlined } from '@ant-design/icons-vue'
import { listCommandTemplates, createCommandTemplate, updateCommandTemplate, deleteCommandTemplate } from '../api/command'
import { useI18n } from 'vue-i18n'
import DataLoadError from '../components/DataLoadError.vue'

const { t } = useI18n()

const templates = ref([])
const loading = ref(false)
const loadError = ref(false)
const modalVisible = ref(false)
const modalLoading = ref(false)
const editingId = ref(null)

const formState = reactive({
  name: '',
  command: '',
  description: '',
  auto_enter: false
})

const columns = computed(() => [
  { title: t('command.name'), dataIndex: 'name', key: 'name', sorter: (a, b) => a.name.localeCompare(b.name) },
  { title: t('command.command'), dataIndex: 'command', key: 'command' },
  { title: t('command.autoEnter'), dataIndex: 'auto_enter', key: 'auto_enter', width: 120, filters: [
    { text: t('command.autoEnterOn'), value: true },
    { text: t('command.autoEnterOff'), value: false }
  ], onFilter: (value, record) => Boolean(record.auto_enter) === value },
  { title: t('command.description'), dataIndex: 'description', key: 'description' },
  { title: t('common.actions'), key: 'action', width: 120 }
])

const loadTemplates = async () => {
  loading.value = true
  loadError.value = false
  try {
    const data = await listCommandTemplates()
    templates.value = data || []
  } catch (error) {
    console.error('Failed to load templates:', error)
    loadError.value = true
  } finally {
    loading.value = false
  }
}

const showAddModal = () => {
  editingId.value = null
  formState.name = ''
  formState.command = ''
  formState.description = ''
  formState.auto_enter = false
  modalVisible.value = true
}

const editTemplate = (record) => {
  editingId.value = record.id
  formState.name = record.name
  formState.command = record.command
  formState.description = record.description
  formState.auto_enter = Boolean(record.auto_enter)
  modalVisible.value = true
}

const handleModalOk = async () => {
  if (!formState.name || !formState.command) {
    message.error(t('command.nameRequired'))
    return
  }

  modalLoading.value = true
  try {
    if (editingId.value) {
      await updateCommandTemplate(editingId.value, { ...formState })
      message.success(t('command.templateUpdated'))
    } else {
      await createCommandTemplate({ ...formState })
      message.success(t('command.templateCreated'))
    }
    modalVisible.value = false
    loadTemplates()
  } catch (error) {
    console.error('Failed to save template:', error)
    message.error(t('command.saveFailed'))
  } finally {
    modalLoading.value = false
  }
}

const handleDelete = async (id) => {
  try {
    await deleteCommandTemplate(id)
    message.success(t('command.templateDeleted'))
    loadTemplates()
  } catch (error) {
    console.error('Failed to delete template:', error)
    message.error(t('command.deleteFailed'))
  }
}

onMounted(loadTemplates)
</script>

<style scoped>
.command-management {
  padding: 0;
}

.command-code {
  display: inline-block;
  max-width: min(520px, 46vw);
  padding: 2px 6px;
  border-radius: 4px;
  font-family: 'Courier New', Courier, monospace;
  font-size: 13px;
  overflow: hidden;
  text-overflow: ellipsis;
  vertical-align: middle;
  white-space: nowrap;
}

.muted-text {
  color: #8c8c8c;
}

/* Light theme code style */
.light-theme .command-code {
  background: #f0f0f0;
  color: #c41d7f; /* Standard code color in light mode */
}

/* Dark theme code style */
.dark-theme .command-code {
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
  
  .command-code {
    max-width: 42vw;
    font-size: 11px;
    word-break: break-all;
  }
}
</style>
