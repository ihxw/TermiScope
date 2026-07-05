<template>
  <div class="monitor-templates">
    <a-page-header
      :title="t('network.templates')"
      :sub-title="t('network.templatesPageDesc')"
      @back="() => router.push({ name: 'MonitorDashboard' })"
    />
    <a-card :bordered="false">
      <div class="toolbar">
        <a-button type="primary" @click="openTemplateModal">
          <template #icon><PlusOutlined /></template>
          {{ t('common.add') }}
        </a-button>
      </div>

      <a-table
        :data-source="templates"
        :columns="templateColumns"
        :loading="loadingTemplates"
        row-key="id"
        :scroll="{ x: 600 }"
      >
        <template #bodyCell="{ column, record }">
          <template v-if="column.key === 'actions'">
            <a-space>
              <a-button type="link" size="small" @click="openEditModal(record)">{{ t('common.edit') }}</a-button>
              <a-button type="link" size="small" @click="openApplyModal(record)">{{ t('common.deploy') }}</a-button>
              <a-popconfirm :title="t('common.confirmDelete')" @confirm="deleteTemplate(record.id)">
                <a-button type="link" danger size="small">{{ t('common.delete') }}</a-button>
              </a-popconfirm>
            </a-space>
          </template>
          <template v-else-if="column.key === 'type'">
            <a-tag color="blue">{{ record.type.toUpperCase() }}</a-tag>
          </template>
        </template>
      </a-table>
    </a-card>

    <a-modal
      v-model:open="templateModalVisible"
      :title="templateForm.id ? t('network.editTemplate') : t('network.addTemplate')"
      @ok="handleSaveTemplate"
      :confirm-loading="savingTemplate"
    >
      <a-form layout="vertical">
        <a-form-item :label="t('common.name')" required>
          <a-input v-model:value="templateForm.name" placeholder="e.g. Google DNS" />
        </a-form-item>
        <a-form-item :label="t('network.targetType')" required>
          <a-select v-model:value="templateForm.type">
            <a-select-option value="ping">Ping (ICMP)</a-select-option>
            <a-select-option value="tcping">TCPing (Port)</a-select-option>
          </a-select>
        </a-form-item>
        <a-form-item :label="t('network.targetAddress')" required>
          <a-input v-model:value="templateForm.target" placeholder="e.g. 8.8.8.8" />
        </a-form-item>
        <a-form-item v-if="templateForm.type === 'tcping'" :label="t('network.targetPort')" required>
          <a-input-number v-model:value="templateForm.port" :min="1" :max="65535" style="width: 100%" />
        </a-form-item>
        <a-form-item :label="t('common.label')">
          <a-input v-model:value="templateForm.label" placeholder="Optional label for task" />
        </a-form-item>
        <a-form-item :label="t('network.frequency')">
          <a-input-number v-model:value="templateForm.frequency" :min="10" :max="3600" addon-after="s" />
        </a-form-item>
        <a-form-item :label="t('system.chartColor')">
          <div class="color-picker">
            <div class="color-presets">
              <div
                v-for="color in materialColors"
                :key="color"
                class="color-swatch"
                :class="{ active: templateForm.color === color }"
                :style="{ backgroundColor: color }"
                :title="color"
                @click="templateForm.color = color"
              />
            </div>
            <div class="color-custom">
              <a-input v-model:value="templateForm.color" type="color" class="color-input" />
              <a-input v-model:value="templateForm.color" placeholder="#1890ff" />
            </div>
          </div>
        </a-form-item>
      </a-form>
    </a-modal>

    <a-modal
      v-model:open="applyModalVisible"
      :title="t('network.deployTemplate')"
      @ok="handleApplyTemplate"
      :confirm-loading="applyingTemplate"
    >
      <p>{{ t('network.selectHostsToDeploy') }} <b>{{ currentTemplate?.name }}</b></p>
      <a-table
        :data-source="hosts"
        :columns="hostColumns"
        :row-selection="hostRowSelection"
        row-key="id"
        size="small"
        :pagination="false"
        :scroll="{ y: 300 }"
      />
    </a-modal>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { message } from 'ant-design-vue'
import { PlusOutlined } from '@ant-design/icons-vue'
import {
  getNetworkTemplates,
  createNetworkTemplate,
  updateNetworkTemplate,
  deleteNetworkTemplate,
  batchApplyTemplate,
  getTemplateAssignments,
} from '../../api/networkMonitor'
import { useSSHStore } from '../../stores/ssh'

defineOptions({ name: 'MonitorTemplates' })

const { t } = useI18n()
const router = useRouter()
const sshStore = useSSHStore()

const templates = ref([])
const loadingTemplates = ref(false)
const templateModalVisible = ref(false)
const savingTemplate = ref(false)
const applyModalVisible = ref(false)
const applyingTemplate = ref(false)
const currentTemplate = ref(null)
const hosts = ref([])
const selectedHostKeys = ref([])

const materialColors = [
  '#F44336', '#E91E63', '#9C27B0', '#673AB7', '#3F51B5', '#2196F3',
  '#03A9F4', '#00BCD4', '#009688', '#4CAF50', '#8BC34A', '#CDDC39',
  '#FFEB3B', '#FFC107', '#FF9800', '#FF5722',
]

const templateForm = reactive({
  id: null,
  name: '',
  type: 'ping',
  target: '',
  port: 80,
  label: '',
  frequency: 60,
  color: '#1890ff',
})

const isMobile = ref(false)
const checkMobile = () => {
  isMobile.value = window.innerWidth <= 768
}

const templateColumns = computed(() => {
  const cols = [
    { title: t('common.name'), key: 'name', dataIndex: 'name', width: 120, ellipsis: true },
    { title: t('network.targetType'), key: 'type', dataIndex: 'type', width: 80 },
    { title: t('network.targetAddress'), key: 'target', dataIndex: 'target', width: 150, ellipsis: true },
    { title: t('network.frequency'), key: 'frequency', dataIndex: 'frequency', customRender: ({ text }) => `${text}s`, width: 80 },
    { title: t('common.actions'), key: 'actions', width: 160, fixed: isMobile.value ? 'right' : undefined },
  ]
  if (isMobile.value) {
    return cols.filter((c) => c.key !== 'frequency')
  }
  return cols
})

const hostColumns = computed(() => [
  { title: t('common.name'), dataIndex: 'name' },
  { title: t('host.host'), dataIndex: 'host' },
])

const hostRowSelection = {
  selectedRowKeys: selectedHostKeys,
  onChange: (keys) => {
    selectedHostKeys.value = keys
  },
}

const fetchTemplates = async () => {
  loadingTemplates.value = true
  try {
    const res = await getNetworkTemplates()
    templates.value = res || []
  } catch (e) {
    message.error(t('network.loadFailed', 'Failed to load templates'))
    console.error(e)
  } finally {
    loadingTemplates.value = false
  }
}

const openTemplateModal = () => {
  templateForm.id = null
  templateForm.name = ''
  templateForm.type = 'ping'
  templateForm.target = ''
  templateForm.port = 80
  templateForm.label = ''
  templateForm.frequency = 60
  templateForm.color = '#1890ff'
  templateModalVisible.value = true
}

const openEditModal = (record) => {
  templateForm.id = record.id
  templateForm.name = record.name
  templateForm.type = record.type
  templateForm.target = record.target
  templateForm.port = record.port || 80
  templateForm.label = record.label || ''
  templateForm.frequency = record.frequency || 60
  templateForm.color = record.color || '#1890ff'
  templateModalVisible.value = true
}

const handleSaveTemplate = async () => {
  if (!templateForm.name || !templateForm.target) {
    return message.error(t('network.requiredNameAndTarget', 'Name and Target are required'))
  }
  savingTemplate.value = true
  try {
    const data = { ...templateForm }
    if (templateForm.id) {
      await updateNetworkTemplate(templateForm.id, data)
      message.success(t('common.updateSuccess', 'Updated successfully'))
    } else {
      await createNetworkTemplate(data)
      message.success(t('common.addSuccess'))
    }
    templateModalVisible.value = false
    fetchTemplates()
  } catch (e) {
    message.error(templateForm.id ? t('common.updateFailed', 'Failed to update') : t('common.addFailed', 'Failed to add'))
    console.error(e)
  } finally {
    savingTemplate.value = false
  }
}

const deleteTemplate = async (id) => {
  try {
    await deleteNetworkTemplate(id)
    message.success(t('common.deleteSuccess'))
    fetchTemplates()
  } catch (e) {
    message.error(t('common.deleteFailed'))
  }
}

const openApplyModal = async (tmpl) => {
  currentTemplate.value = tmpl
  selectedHostKeys.value = []
  if (sshStore.hosts.length === 0) await sshStore.fetchHosts()
  hosts.value = sshStore.hosts
  applyModalVisible.value = true
  try {
    const assignedIds = await getTemplateAssignments(tmpl.id)
    if (assignedIds && Array.isArray(assignedIds)) {
      selectedHostKeys.value = assignedIds
    }
  } catch (e) {
    console.error('Failed to load assignments', e)
  }
}

const handleApplyTemplate = async () => {
  applyingTemplate.value = true
  try {
    await batchApplyTemplate({
      template_id: currentTemplate.value.id,
      host_ids: selectedHostKeys.value,
    })
    message.success(t('network.deploySuccess', 'Template deployed successfully'))
    applyModalVisible.value = false
  } catch (e) {
    message.error(t('network.deployFailed', 'Failed to deploy template'))
    console.error(e)
  } finally {
    applyingTemplate.value = false
  }
}

onMounted(() => {
  checkMobile()
  window.addEventListener('resize', checkMobile)
  fetchTemplates()
})

onUnmounted(() => {
  window.removeEventListener('resize', checkMobile)
})
</script>

<style scoped>
.monitor-templates {
  padding: 24px;
  max-width: 1200px;
  margin: 0 auto;
}
.toolbar {
  margin-bottom: 16px;
}
.color-picker {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.color-presets {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.color-swatch {
  width: 32px;
  height: 32px;
  border-radius: 4px;
  cursor: pointer;
  border: 1px solid #d9d9d9;
}
.color-swatch.active {
  border: 3px solid #000;
  box-shadow: 0 0 0 2px #fff, 0 0 0 4px currentColor;
}
.color-custom {
  display: flex;
  align-items: center;
  gap: 12px;
}
.color-input {
  width: 60px;
  height: 40px;
  cursor: pointer;
  padding: 4px;
}
@media (max-width: 768px) {
  .monitor-templates {
    padding: 8px;
  }
}
</style>
