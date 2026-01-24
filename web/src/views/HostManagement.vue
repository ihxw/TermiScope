<template>
  <div class="host-management-container">
    <a-card :title="t('nav.hosts')" :bordered="false" class="host-card">
      <template #extra>
          <div class="header-actions">
          <a-input-search
            v-model:value="searchText"
            :placeholder="t('host.searchPlaceholder')"
            class="search-input"
            size="small"
            @search="handleSearch"
          />
          <a-button 
            v-if="selectedRowKeys.length > 0"
            type="primary"
            size="small"
            @click="openBatchDeployModal"
            class="action-btn"
          >
            <CloudUploadOutlined />
            <span v-if="!isMobile" class="btn-text">{{ t('monitor.batchDeploy') }} ({{ selectedRowKeys.length }})</span>
          </a-button>
          <a-button 
            v-if="selectedRowKeys.length > 0"
            danger
            size="small"
            @click="openBatchStopModal"
            class="action-btn"
          >
            <StopOutlined />
            <span v-if="!isMobile" class="btn-text">{{ t('monitor.batchStop') }} ({{ selectedRowKeys.length }})</span>
          </a-button>
          <a-button type="primary" size="small" @click="handleAdd" class="action-btn">
            <span v-if="isMobile" style="display: flex; align-items: center; justify-content: center; width: 100%; height: 100%;">
              <svg viewBox="64 64 896 896" focusable="false" data-icon="plus" width="1em" height="1em" fill="white" aria-hidden="true" style="font-size: 18px;">
                <path d="M482 152h60q8 0 8 8v704q0 8-8 8h-60q-8 0-8-8V160q0-8 8-8z"></path>
                <path d="M176 474h672q8 0 8 8v60q0 8-8 8H176q-8 0-8-8v-60q0-8 8-8z"></path>
              </svg>
            </span>
            <template v-else>
              <PlusOutlined />
              <span class="btn-text">{{ t('host.addHost') }}</span>
            </template>
          </a-button>
        </div>
      </template>

      <div class="table-wrapper">
        <a-table
          :row-selection="rowSelection"
          :columns="columns"
          :data-source="sshStore.hosts"
          :loading="loading"
          row-key="id"
          :pagination="false"
          :scroll="{ x: isMobile ? 600 : undefined, y: 'calc(100vh - 280px)' }"
        >
        <template #bodyCell="{ column, record }">
          <template v-if="column.key === 'drag'">
            <div class="drag-handle" style="cursor: move; color: #999; display: flex; justify-content: center; align-items: center; height: 100%;">
               <HolderOutlined />
            </div>
          </template>
          <template v-if="column.key === 'status'">
            <div style="display: flex; align-items: center">
              <a-tooltip :title="hostStatuses[record.id]?.status === 'online' ? t('monitor.online') : (hostStatuses[record.id]?.error || t('monitor.checking'))">
                <a-tag v-if="hostStatuses[record.id]?.status === 'online'" color="success">
                  {{ hostStatuses[record.id]?.latency }}ms
                </a-tag>
                <a-tag v-else-if="hostStatuses[record.id]?.status === 'offline'" color="error">
                  {{ t('monitor.offline') }}
                </a-tag>
                <a-tag v-else color="processing">
                  <template #icon><LoadingOutlined /></template>
                  {{ t('monitor.checking') }}
                </a-tag>
              </a-tooltip>
            </div>
          </template>
          <template v-if="column.key === 'monitor'">
             <div style="display: flex; align-items: center">
                <a-tag v-if="record.monitor_enabled" color="processing">
                  <template #icon><DashboardOutlined /></template>
                  {{ t('monitor.enabled') }}
                </a-tag>
                <a-tag v-else color="default">
                  {{ t('monitor.disabled') }}
                </a-tag>
             </div>
          </template>
          <template v-if="column.key === 'description'">
            <a-tooltip :title="record.description" placement="topLeft">
              <div style="max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                {{ record.description || '-' }}
              </div>
            </a-tooltip>
          </template>
          <template v-if="column.key === 'type'">
            <a-tag v-if="record.host_type === 'monitor_only'" color="blue">
              {{ t('host.monitorOnly') }}
            </a-tag>
            <a-tag v-else color="green">
              {{ t('host.controlAndMonitor') }}
            </a-tag>
          </template>
          <template v-if="column.key === 'action'">
            <!-- Mobile: Use dropdown menu for all actions -->
            <template v-if="isMobile">
              <a-dropdown :trigger="['click']">
                <a-button size="small">
                  <MoreOutlined />
                </a-button>
                <template #overlay>
                  <a-menu>
                    <!-- Deploy/Stop Monitor -->
                    <template v-if="!record.monitor_enabled">
                      <a-menu-item 
                        key="auto-deploy" 
                        @click="openDeployModal(record)" 
                        :disabled="record.host_type === 'monitor_only'"
                      >
                        <CloudUploadOutlined /> {{ t('monitor.autoDeploy') }}
                      </a-menu-item>
                      <a-menu-item key="manual-install" @click="openInstallCommandModal(record)">
                        <CopyOutlined /> {{ t('monitor.manualInstall') }}
                      </a-menu-item>
                    </template>
                    <template v-else>
                      <a-menu-item 
                        v-if="record.host_type === 'monitor_only'"
                        key="uninstall" 
                        @click="openUninstallCommandModal(record)"
                        style="color: #ff4d4f"
                      >
                        <DeleteOutlined /> {{ t('monitor.manualUninstall') }}
                      </a-menu-item>
                      <a-menu-item 
                        v-else
                        key="stop" 
                        @click="handleStopMonitor(record)"
                        style="color: #ff4d4f"
                      >
                        <StopOutlined /> {{ t('monitor.stop') }}
                      </a-menu-item>
                    </template>
                    <a-menu-divider />
                    <!-- Connect -->
                    <a-menu-item 
                      key="connect" 
                      @click="handleConnect(record)"
                      :disabled="record.host_type === 'monitor_only'"
                    >
                      <LinkOutlined /> {{ t('terminal.connect') }}
                    </a-menu-item>
                    <!-- Edit -->
                    <a-menu-item key="edit" @click="handleEdit(record)">
                      <EditOutlined /> {{ t('common.edit') }}
                    </a-menu-item>
                    <a-menu-divider />
                    <!-- Delete -->
                    <a-menu-item key="delete" @click="confirmDelete(record.id)" style="color: #ff4d4f">
                      <DeleteOutlined /> {{ t('common.delete') }}
                    </a-menu-item>
                  </a-menu>
                </template>
              </a-dropdown>
            </template>
            
            <!-- Desktop: Show all buttons -->
            <a-space v-else>
              <!-- 监控部署下拉菜单 -->
              <a-dropdown v-if="!record.monitor_enabled" :trigger="['hover']">
                <a-button size="small" :loading="monitorLoading[record.id]">
                  <DashboardOutlined />
                  {{ t('monitor.deployAgent') }}
                  <DownOutlined style="font-size: 10px; margin-left: 4px" />
                </a-button>
                <template #overlay>
                  <a-menu>
                    <a-menu-item key="auto" @click="openDeployModal(record)" :disabled="record.host_type === 'monitor_only'">
                      <CloudUploadOutlined />
                      {{ t('monitor.autoDeploy') }}
                    </a-menu-item>
                    <a-menu-item key="manual" @click="openInstallCommandModal(record)">
                      <CopyOutlined />
                      {{ t('monitor.manualInstall') }}
                    </a-menu-item>
                    <a-menu-item key="uninstall" @click="openUninstallCommandModal(record)">
                      <DeleteOutlined />
                      {{ t('monitor.manualUninstall') }}
                    </a-menu-item>
                  </a-menu>
                </template>
              </a-dropdown>
              <template v-else>
                <!-- 仅监控主机：显示手动卸载按钮 -->
                <a-button 
                  v-if="record.host_type === 'monitor_only'"
                  size="small" 
                  danger 
                  @click="openUninstallCommandModal(record)"
                >
                  <DeleteOutlined />
                  {{ t('monitor.manualUninstall') }}
                </a-button>

                <!-- 控制+监控主机：显示远程停止按钮 -->
                <a-popconfirm
                  v-else
                  :title="t('monitor.disableConfirm')"
                  @confirm="handleStopMonitor(record)"
                >
                   <a-button size="small" danger :loading="monitorLoading[record.id]">
                     <StopOutlined />
                     {{ t('monitor.stop') }}
                   </a-button>
                </a-popconfirm>
              </template>
              
              <!-- 连接按钮 -->
              <a-tooltip :title="record.host_type === 'monitor_only' ? t('host.monitorOnlyNoConnect') : ''">
                <a-button 
                  size="small" 
                  @click="handleConnect(record)" 
                  :disabled="record.host_type === 'monitor_only'"
                >
                  <LinkOutlined />
                  {{ t('terminal.connect') }}
                </a-button>
              </a-tooltip>

              <a-button size="small" @click="handleEdit(record)">
                <EditOutlined />
                {{ t('common.edit') }}
              </a-button>
              <a-popconfirm
                :title="t('host.deleteConfirm')"
                @confirm="handleDelete(record.id)"
              >
                <a-button size="small" danger>
                  <DeleteOutlined />
                  {{ t('common.delete') }}
                </a-button>
              </a-popconfirm>
            </a-space>
          </template>
        </template>
      </a-table>
      </div>
    </a-card>

    <!-- Edit/Add Host Modal -->
    <a-modal
      v-model:open="showModal"
      :title="editingHost ? t('host.editHost') : t('host.addHost')"
      @ok="handleSave"
      :confirmLoading="saving"
    >
      <a-form :model="hostForm" layout="vertical">
        <!-- 第一项：主机类型 -->
        <a-form-item :label="t('host.type')" required>
          <a-radio-group v-model:value="hostForm.host_type">
            <a-radio value="control_monitor">{{ t('host.controlAndMonitor') }}</a-radio>
            <a-radio value="monitor_only">{{ t('host.monitorOnly') }}</a-radio>
          </a-radio-group>
          <div style="margin-top: 8px; font-size: 12px; color: #666">
            <div v-if="hostForm.host_type === 'control_monitor'">{{ t('host.controlAndMonitorDesc') }}</div>
            <div v-else>{{ t('host.monitorOnlyDesc') }}</div>
          </div>
        </a-form-item>

        <!-- 主机名称 - 始终显示 -->
        <a-form-item :label="t('host.name')" required>
          <a-input v-model:value="hostForm.name" :placeholder="t('host.placeholderName')" />
        </a-form-item>

        <!-- SSH 相关字段 - 仅在"控制+监控"模式下显示 -->
        <template v-if="hostForm.host_type === 'control_monitor'">
          <a-form-item :label="t('host.host')" required>
            <a-input v-model:value="hostForm.host" :placeholder="t('host.placeholderHost')" />
          </a-form-item>

          <a-form-item :label="t('host.port')">
            <a-input-number v-model:value="hostForm.port" :min="1" :max="65535" style="width: 100%" />
          </a-form-item>

          <a-form-item :label="t('host.username')" required>
            <a-input v-model:value="hostForm.username" :placeholder="t('host.placeholderUsername')" />
          </a-form-item>

          <a-form-item :label="t('host.authMethod')" required>
            <a-radio-group v-model:value="hostForm.auth_type">
              <a-radio value="password">{{ t('host.authPassword') }}</a-radio>
              <a-radio value="key">{{ t('host.authKey') }}</a-radio>
            </a-radio-group>
          </a-form-item>

          <a-form-item v-if="hostForm.auth_type === 'password'" :label="t('host.password')" :required="!editingHost">
            <a-input-password v-model:value="hostForm.password" :placeholder="editingHost ? t('host.placeholderKeepPassword') : t('host.placeholderPassword')" />
          </a-form-item>

          <a-form-item v-if="hostForm.auth_type === 'key'" :label="t('host.privateKey')" :required="!editingHost">
            <a-textarea
              v-model:value="hostForm.private_key"
              :placeholder="editingHost ? t('host.placeholderKeepKey') : t('host.placeholderPrivateKey')"
              :rows="6"
            />
          </a-form-item>
        </template>

        <!-- 分组和描述 - 始终显示 -->
        <a-form-item :label="t('host.group')">
          <a-input v-model:value="hostForm.group_name" :placeholder="t('host.placeholderGroup')" />
        </a-form-item>

        <a-form-item :label="t('host.description')">
          <a-textarea v-model:value="hostForm.description" :rows="3" />
        </a-form-item>
      </a-form>
    </a-modal>

    <!-- Deploy Monitor Modal -->
    <a-modal
      v-model:open="deployVisible"
      :title="t('monitor.deployAgent')"
      @ok="handleDeploy"
      :confirmLoading="deploying"
    >
      <p>{{ t('monitor.deployConfirm', { name: deployHost?.name }) }}</p>
      <a-checkbox v-model:checked="deployInsecure">
        {{ t('monitor.deployInsecure') }}
      </a-checkbox>
      <p style="margin-top: 8px; font-size: 12px; color: #faad14;" v-if="deployInsecure">
        {{ t('monitor.deployInsecureWarning') }}
      </p>
    </a-modal>

    <!-- Batch Deploy Modal -->
    <a-modal
      v-model:open="batchDeployVisible"
      :title="t('monitor.batchDeploy')"
      @ok="handleBatchDeploy"
      :confirmLoading="batchDeploying"
      width="600px"
    >
      <div style="margin-bottom: 16px">
        <p>{{ t('monitor.batchDeployConfirm', { count: selectedHosts.length }) }}</p>
        <a-list size="small" :data-source="selectedHosts">
          <template #renderItem="{ item }">
            <a-list-item>
              <div style="width: 100%">
                <a-space style="justify-content: space-between; width: 100%">
                  <span>{{ item.name }} ({{ item.host }})</span>
                  <a-tag v-if="item.monitor_enabled" color="blue">
                    {{ t('monitor.willRedeploy') }}
                  </a-tag>
                </a-space>
                <div v-if="deployStatus[item.id]" style="margin-top: 8px">
                  <a-progress
                    v-if="deployStatus[item.id].status === 'deploying'"
                    :percent="50"
                    status="active"
                    size="small"
                  />
                  <a-alert
                    v-else-if="deployStatus[item.id].status === 'success'"
                    :message="deployStatus[item.id].message"
                    type="success"
                    size="small"
                    show-icon
                  />
                  <a-alert
                    v-else-if="deployStatus[item.id].status === 'error'"
                    :message="deployStatus[item.id].message"
                    type="error"
                    size="small"
                    show-icon
                  />
                </div>
              </div>
            </a-list-item>
          </template>
        </a-list>
      </div>
      
      <a-checkbox v-model:checked="batchDeployInsecure">
        {{ t('monitor.deployInsecure') }}
      </a-checkbox>
    </a-modal>

    <!-- Batch Stop Modal -->
    <a-modal
      v-model:open="batchStopVisible"
      :title="t('monitor.batchStop')"
      @ok="handleBatchStop"
      :confirmLoading="batchStopping"
      width="600px"
    >
      <div style="margin-bottom: 16px">
        <p>{{ t('monitor.batchStopConfirm', { count: selectedHosts.length }) }}</p>
        <a-list size="small" :data-source="selectedHosts">
          <template #renderItem="{ item }">
            <a-list-item>
              <div style="width: 100%">
                <span>{{ item.name }} ({{ item.host }})</span>
                <div v-if="stopStatus[item.id]" style="margin-top: 8px">
                  <a-progress
                    v-if="stopStatus[item.id].status === 'stopping'"
                    :percent="50"
                    status="active"
                    size="small"
                  />
                  <a-alert
                    v-else-if="stopStatus[item.id].status === 'success'"
                    :message="stopStatus[item.id].message"
                    type="success"
                    size="small"
                    show-icon
                  />
                  <a-alert
                    v-else-if="stopStatus[item.id].status === 'error'"
                    :message="stopStatus[item.id].message"
                    type="error"
                    size="small"
                    show-icon
                  />
                </div>
              </div>
            </a-list-item>
          </template>
        </a-list>
      </div>
    </a-modal>

    <!-- Install Command Modal -->
    <a-modal
      v-model:open="installCommandVisible"
      :title="t('monitor.installCommandTitle')"
      width="650px"
      :footer="null"
    >
      <a-alert
        :message="t('monitor.manualInstallNotice')"
        type="info"
        show-icon
        style="margin-bottom: 16px"
      />
      
      <div v-if="installCommandHost">
        <p style="margin-bottom: 12px; font-weight: 500">
          {{ t('host.host') }}: {{ installCommandHost.name }}
        </p>
        
        <p style="margin-bottom: 8px; color: #666; font-size: 13px">
          {{ t('monitor.installSupport') }}
        </p>
        
        <div style="position: relative; margin-bottom: 16px">
          <pre style="background: #f5f5f5; padding: 16px; padding-right: 90px; border-radius: 4px; font-size: 13px; overflow: auto; word-break: break-all; white-space: pre-wrap">{{ getInstallCommand() }}</pre>
          <a-button
            type="primary"
            size="small"
            style="position: absolute; top: 12px; right: 12px"
            @click="copyInstallCommand()"
          >
            <CopyOutlined /> {{ t('common.copy') }}
          </a-button>
        </div>
        
        <a-alert
          :message="t('monitor.installNote')"
          type="warning"
          show-icon
          style="font-size: 12px"
        />
      </div>
    </a-modal>

    <!-- Uninstall Command Modal -->
    <a-modal
      v-model:open="uninstallCommandVisible"
      :title="t('monitor.uninstallCommandTitle')"
      width="650px"
      :footer="null"
    >
      <a-alert
        :message="t('monitor.manualUninstallNotice')"
        type="warning"
        show-icon
        style="margin-bottom: 16px"
      />
      
      <div>        
        <p style="margin-bottom: 8px; color: #666; font-size: 13px">
          {{ t('monitor.uninstallSupport') }}
        </p>
        
        <div style="position: relative; margin-bottom: 16px">
          <pre style="background: #f5f5f5; padding: 16px; padding-right: 90px; border-radius: 4px; font-size: 13px; overflow: auto; word-break: break-all; white-space: pre-wrap">{{ getUninstallCommand() }}</pre>
          <a-button
            type="primary"
            size="small"
            style="position: absolute; top: 12px; right: 12px"
            @click="copyUninstallCommand()"
          >
            <CopyOutlined /> {{ t('common.copy') }}
          </a-button>
        </div>
      </div>
    </a-modal>
  </div>
</template>

<script setup>
import { ref, onMounted, computed, onUnmounted, watch, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { message, Modal } from 'ant-design-vue'
import {
  DashboardOutlined,
  CloudUploadOutlined,
  CopyOutlined,
  AppstoreOutlined,
  LinkOutlined,
  StopOutlined,
  DeleteOutlined,
  ThunderboltOutlined,
  SafetyOutlined,
  EditOutlined,
  DownOutlined,
  MoreOutlined,
  PlusOutlined,
  LoadingOutlined,
  HolderOutlined
} from '@ant-design/icons-vue'
import { useSSHStore } from '../stores/ssh'
import { useI18n } from 'vue-i18n'
import { deployMonitor, stopMonitor, batchDeployMonitor, batchStopMonitor } from '../api/ssh'
import Sortable from 'sortablejs'

const router = useRouter()
const sshStore = useSSHStore()
const { t } = useI18n()

const loading = ref(false)
const searchText = ref('')
const showModal = ref(false)
const saving = ref(false)
const editingHost = ref(null)

const deployVisible = ref(false)
const deployInsecure = ref(false)
const deployHost = ref(null)
const deploying = ref(false)

const selectedRowKeys = ref([])
const batchDeployVisible = ref(false)
const batchDeploying = ref(false)
const batchDeployInsecure = ref(false)
const deployStatus = ref({})

const batchStopVisible = ref(false)
const batchStopping = ref(false)
const stopStatus = ref({})

const installCommandVisible = ref(false)
const installCommandHost = ref(null)

const hostForm = ref({
  name: '',
  host: '',
  port: 22,
  username: '',
  auth_type: 'password',
  password: '',
  private_key: '',
  group_name: '',
  description: '',
  host_type: 'control_monitor'
})

// Mobile detection
const isMobile = ref(false)
const checkMobile = () => {
  isMobile.value = window.innerWidth <= 768
}

const columns = computed(() => {
  const baseColumns = [
    { title: '', key: 'drag', width: 30, align: 'center', fixed: isMobile.value ? undefined : undefined },
    { title: t('host.name'), dataIndex: 'name', key: 'name', width: 120, ellipsis: true },
    { title: t('host.host'), dataIndex: 'host', key: 'host', width: 120, ellipsis: true },
    { title: t('monitor.status'), key: 'status', width: 80 },
    { title: t('monitor.monitoring'), key: 'monitor', width: 80 },
    { title: t('host.type'), key: 'type', width: 100 },
  ]
  
  // Only show these columns on desktop
  if (!isMobile.value) {
    baseColumns.push(
      { title: t('host.port'), dataIndex: 'port', key: 'port', width: 60 },
      { title: t('host.username'), dataIndex: 'username', key: 'username', width: 100 },
      { title: t('host.group'), dataIndex: 'group_name', key: 'group_name', width: 100 },
      { title: t('host.description'), key: 'description', width: 150, ellipsis: true },
    )
  }
  
  baseColumns.push({ title: t('common.edit'), key: 'action', width: isMobile.value ? 60 : 320, fixed: 'right' })
  
  return baseColumns
})

const monitorLoading = ref({})

const rowSelection = {
  selectedRowKeys: selectedRowKeys,
  onChange: (keys) => {
    selectedRowKeys.value = keys
  }
}

const selectedHosts = computed(() => {
  return sshStore.hosts.filter(h => selectedRowKeys.value.includes(h.id))
})

const openDeployModal = (host) => {
    deployHost.value = host
    deployInsecure.value = false
    deployVisible.value = true
}

const handleDeploy = async () => {
    if (!deployHost.value) return
    deploying.value = true
    monitorLoading.value[deployHost.value.id] = true
    
    try {
        await deployMonitor(deployHost.value.id, deployInsecure.value)
        message.success(t('monitor.deploySuccess'))
        deployHost.value.monitor_enabled = true
        deployVisible.value = false
    } catch (error) {
        message.error(t('monitor.deployFailed') + ': ' + (error.response?.data?.error || error.message))
    } finally {
        deploying.value = false
        monitorLoading.value[deployHost.value.id] = false
    }
}

const handleStopMonitor = async (host) => {
  monitorLoading.value[host.id] = true
  try {
    await stopMonitor(host.id)
    message.success(t('monitor.monitorDisabled'))
    host.monitor_enabled = false
  } catch (error) {
    message.error(t('monitor.stopFailed'))
  } finally {
    monitorLoading.value[host.id] = false
  }
}

const hostStatuses = ref({})
const checkingStatus = ref(false)



const initSortable = () => {
  const tableWithBody = document.querySelector('.ant-table-tbody')
  if (tableWithBody && !tableWithBody._sortable) {
    tableWithBody._sortable = Sortable.create(tableWithBody, {
      handle: '.drag-handle',
      draggable: '.ant-table-row',
      animation: 150,
      onStart: () => {},
      onEnd: async (evt) => {
        const { oldIndex, newIndex } = evt
        if (oldIndex === newIndex) return

        // Calculate offset (account for hidden rows like measure-row)
        const tbody = document.querySelector('.ant-table-tbody')
        const rows = Array.from(tbody.children)
        const firstRowIndex = rows.findIndex(row => row.classList.contains('ant-table-row'))
        const offset = firstRowIndex >= 0 ? firstRowIndex : 0
        
        const realOldIndex = oldIndex - offset
        const realNewIndex = newIndex - offset

        // Safety check with REAL indices
        if (realOldIndex < 0 || realOldIndex >= sshStore.hosts.length || realNewIndex < 0 || realNewIndex >= sshStore.hosts.length) {
            return
        }

        const item = sshStore.hosts[realOldIndex]
        if (!item) {
             console.error('Sortable: item not found at index', realOldIndex)
             return
        }

        // Move item locally
        sshStore.hosts.splice(realOldIndex, 1)
        sshStore.hosts.splice(realNewIndex, 0, item)
        
        const ids = sshStore.hosts.map(h => h.id)
        try {
            await sshStore.reorderHosts(ids)
            message.success(t('host.orderUpdated'))
        } catch (e) {
            message.error(t('host.failUpdateOrder'))
             await loadHosts() 
        }
      }
    })
  }
}

watch(() => sshStore.hosts, () => {
  nextTick(() => {
    initSortable()
  })
}, { deep: true })

onMounted(async () => {
  checkMobile()
  window.addEventListener('resize', checkMobile)
  await loadHosts()
  checkAllStatuses()
})

const checkAllStatuses = async () => {
  if (checkingStatus.value || sshStore.hosts.length === 0) return
  
  checkingStatus.value = true
  // Check in batches or parallel? Parallel is fine for small numbers.
  const checks = sshStore.hosts.map(async (host) => {
    hostStatuses.value[host.id] = { status: 'loading' }
    try {
      const result = await sshStore.testHostConnection(host.id)
      hostStatuses.value[host.id] = result
    } catch (e) {
      hostStatuses.value[host.id] = { status: 'offline', error: 'Failed to check' }
    }
  })
  
  await Promise.allSettled(checks)
  checkingStatus.value = false
}

const loadHosts = async () => {
  loading.value = true
  try {
    await sshStore.fetchHosts()
    checkAllStatuses()
  } catch (error) {
    message.error(t('host.failLoad'))
  } finally {
    loading.value = false
  }
}

const handleSearch = () => {
  loadHosts()
}

const handleAdd = () => {
  editingHost.value = null
  showModal.value = true
  hostForm.value = {
    name: '',
    host: '',
    port: 22,
    username: '',
    auth_type: 'password',
    password: '',
    private_key: '',
    group_name: '',
    description: '',
    host_type: 'control_monitor'
  }
}

const handleConnect = (host) => {
  sshStore.addTerminal({
    hostId: host.id,
    name: host.name,
    host: host.host,
    port: host.port
  })
  router.push('/dashboard/terminal')
}

const handleEdit = async (host) => {
  editingHost.value = host
  showModal.value = true
  
  // Load full host details
  try {
    const fullHost = await sshStore.fetchHost(host.id)
    hostForm.value = {
      name: fullHost.name,
      host: fullHost.host,
      port: fullHost.port,
      username: fullHost.username,
      auth_type: fullHost.auth_type,
      password: '',
      private_key: '',
      group_name: fullHost.group_name || '',
      description: fullHost.description || '',
      host_type: fullHost.host_type || 'control_monitor'
    }
  } catch (error) {
    message.error(t('host.failLoad'))
  }
}

const handleSave = async () => {
  // 基本验证：名称必填
  if (!hostForm.value.name) {
    message.error(t('host.validationRequired'))
    return
  }

  // 对于"控制+监控"类型，需要验证 SSH 相关字段
  if (hostForm.value.host_type === 'control_monitor') {
    if (!hostForm.value.host || !hostForm.value.username) {
      message.error(t('host.validationRequired'))
      return
    }

    if (!editingHost.value) {
      if (hostForm.value.auth_type === 'password' && !hostForm.value.password) {
        message.error(t('host.validationPassword'))
        return
      }
      if (hostForm.value.auth_type === 'key' && !hostForm.value.private_key) {
        message.error(t('host.validationKey'))
        return
      }
    }
  }

  saving.value = true
  try {
    if (editingHost.value) {
      const updateData = { ...hostForm.value }
      if (!updateData.password) delete updateData.password
      if (!updateData.private_key) delete updateData.private_key
      
      await sshStore.modifyHost(editingHost.value.id, updateData)
      message.success(t('host.successUpdate'))
    } else {
      await sshStore.addHost(hostForm.value)
      message.success(t('host.successAdd'))
    }
    showModal.value = false
    await loadHosts()
  } catch (error) {
    message.error(editingHost.value ? t('host.failUpdate') : t('host.failAdd'))
  } finally {
    saving.value = false
  }
}

const confirmDelete = (id) => {
  Modal.confirm({
    title: t('host.deleteConfirm'),
    okText: t('common.confirm'),
    cancelText: t('common.cancel'),
    okType: 'danger',
    onOk: () => handleDelete(id)
  })
}

const handleDelete = async (id) => {
  try {
    await sshStore.removeHost(id)
    message.success(t('host.hostDeleted'))
  } catch (error) {
    message.error(t('common.error'))
  }
}

const openBatchDeployModal = () => {
  deployStatus.value = {}
  batchDeployVisible.value = true
}

const handleBatchDeploy = async () => {
  batchDeploying.value = true
  
  // 初始化状态
  selectedRowKeys.value.forEach(id => {
    deployStatus.value[id] = { status: 'deploying', message: t('monitor.deploying') }
  })
  
  try {
    // 使用API函数确保认证token被正确传递
    const response = await batchDeployMonitor(selectedRowKeys.value, batchDeployInsecure.value)
    
    console.log('批量部署完整响应:', response)
    console.log('response.data:', response.data)
    
    // 检查响应数据 - axios返回的数据在response.data中
    let results = []
    
    if (response.data && response.data.results) {
      // 标准格式: { results: [...] }
      results = response.data.results
    } else if (Array.isArray(response.data)) {
      // 直接是数组
      results = response.data
    } else if (response.results) {
      // 数据直接在response中
      results = response.results
    } else {
      console.error('无法解析响应数据:', response)
      throw new Error('服务端返回数据格式错误')
    }
    
    console.log('解析的results:', results)
    
    if (results.length === 0) {
      message.warning('未收到部署结果')
      return
    }
    
    // 更新每个主机的部署状态
    results.forEach(result => {
      console.log('更新主机状态:', result)
      deployStatus.value[result.host_id] = {
        status: result.success ? 'success' : 'error',
        message: result.message
      }
    })
    
    console.log('更新后的deployStatus:', deployStatus.value)
    
    // 统计结果
    const successCount = results.filter(r => r.success).length
    const failCount = results.length - successCount
    
    if (failCount === 0) {
      message.success(t('monitor.batchDeploySuccess', { count: successCount }))
      setTimeout(() => {
        batchDeployVisible.value = false
        selectedRowKeys.value = []
        loadHosts()
      }, 2000)
    } else {
      message.warning(t('monitor.batchDeployPartial', { success: successCount, fail: failCount }))
    }
  } catch (error) {
    console.error('批量部署错误:', error)
    console.error('错误详情:', error.response)
    
    // 清除部署状态
    selectedRowKeys.value.forEach(id => {
      deployStatus.value[id] = {
        status: 'error',
        message: error.response?.data?.error || error.message || '部署失败'
      }
    })
    
    message.error(t('monitor.batchDeployFailed') + ': ' + (error.response?.data?.error || error.message))
  } finally {
    batchDeploying.value = false
  }
}

const openBatchStopModal = () => {
  stopStatus.value = {}
  batchStopVisible.value = true
}

const openInstallCommandModal = (host) => {
  installCommandHost.value = host
  installCommandVisible.value = true
}

const getInstallCommand = () => {
  if (!installCommandHost.value) return ''
  
  const serverUrl = window.location.protocol + '//' + window.location.host
  const hostId = installCommandHost.value.id
  const secret = installCommandHost.value.monitor_secret || ''
  
  return `curl -fsSL "${serverUrl}/api/monitor/install?host_id=${hostId}&secret=${secret}" | bash`
}

const copyInstallCommand = async () => {
  try {
    await navigator.clipboard.writeText(getInstallCommand())
    message.success(t('monitor.commandCopied'))
  } catch (err) {
    message.error(t('common.copyFailed'))
  }
}

// 卸载命令相关
const uninstallCommandVisible = ref(false)

const openUninstallCommandModal = (host) => {
  installCommandHost.value = host
  uninstallCommandVisible.value = true
}

const getUninstallCommand = () => {
  if (!installCommandHost.value) return ''
  
  const serverUrl = window.location.protocol + '//' + window.location.host
  const hostId = installCommandHost.value.id
  const secret = installCommandHost.value.monitor_secret || ''
  
  return `curl -fsSL "${serverUrl}/api/monitor/uninstall?host_id=${hostId}&secret=${secret}" | bash`
}

const copyUninstallCommand = async () => {
  try {
    await navigator.clipboard.writeText(getUninstallCommand())
    message.success(t('monitor.commandCopied'))
  } catch (err) {
    message.error(t('common.copyFailed'))
  }
}

const handleBatchStop = async () => {
  batchStopping.value = true
  
  // 初始化状态
  selectedRowKeys.value.forEach(id => {
    stopStatus.value[id] = { status: 'stopping', message: t('monitor.stopping') }
  })
  
  try {
    const response = await batchStopMonitor(selectedRowKeys.value)
    
    console.log('批量停止响应:', response)
    
    let results = []
    
    if (response.data && response.data.results) {
      results = response.data.results
    } else if (Array.isArray(response.data)) {
      results = response.data
    } else if (response.results) {
      results = response.results
    } else {
      console.error('无法解析响应数据:', response)
      throw new Error('服务端返回数据格式错误')
    }
    
    if (results.length === 0) {
      message.warning('未收到停止结果')
      return
    }
    
    // 更新每个主机的停止状态
    results.forEach(result => {
      stopStatus.value[result.host_id] = {
        status: result.success ? 'success' : 'error',
        message: result.message
      }
    })
    
    // 统计结果
    const successCount = results.filter(r => r.success).length
    const failCount = results.length - successCount
    
    if (failCount === 0) {
      message.success(t('monitor.batchStopSuccess', { count: successCount }))
      setTimeout(() => {
        batchStopVisible.value = false
        selectedRowKeys.value = []
        loadHosts()
      }, 2000)
    } else {
      message.warning(t('monitor.batchStopPartial', { success: successCount, fail: failCount }))
    }
  } catch (error) {
    console.error('批量停止错误:', error)
    
    selectedRowKeys.value.forEach(id => {
      stopStatus.value[id] = {
        status: 'error',
        message: error.response?.data?.error || error.message || '停止失败'
      }
    })
    
    message.error(t('monitor.batchStopFailed') + ': ' + (error.response?.data?.error || error.message))
  } finally {
    batchStopping.value = false
  }
}

onUnmounted(() => {
  window.removeEventListener('resize', checkMobile)
})
</script>

<style scoped>
.host-management-container {
  padding: 16px;
}

.host-card :deep(.ant-card-head) {
  padding: 0 16px;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.search-input {
  width: 180px;
}

.table-wrapper {
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}

@media (max-width: 768px) {
  .host-management-container {
    padding: 8px;
  }
  
  .host-card :deep(.ant-card-head) {
    padding: 0 12px;
    min-height: 46px;
  }

  .host-card :deep(.ant-card-head-wrapper) {
    align-items: center;
  }
  
  .host-card :deep(.ant-card-head-title) {
    font-size: 14px;
    padding: 12px 0;
    flex: 0 0 auto;
    margin-right: 4px;
  }

  .host-card :deep(.ant-card-extra) {
    flex: 1;
    padding: 12px 0;
    margin-left: 0; 
    overflow: hidden; /* 防止溢出 */
  }
  
  .header-actions {
    display: flex;
    justify-content: flex-end;
    align-items: center;
    gap: 8px;
    width: 100%;
    height: 32px; /* 强制高度 */
  }
  
  .search-input {
    width: auto;
    flex: 1;
    min-width: 60px;
    height: 32px;
  }

  /* 强制搜索框内部高度，确保与按钮对其 */
  .search-input :deep(.ant-input-wrapper),
  .search-input :deep(.ant-input),
  .search-input :deep(.ant-input-group-addon),
  .search-input :deep(.ant-btn) {
    height: 32px !important;
    line-height: 1.5; /* 正常行高 */
    padding-top: 4px;
    padding-bottom: 4px;
    box-sizing: border-box;
  }
  
  /* 修复搜索按钮图标位置 */
  .search-input :deep(.ant-btn > span) {
    display: flex;
    align-items: center;
    justify-content: center;
  }
  
  .action-btn .btn-text {
    display: none;
  }
  
  /* 纯图标按钮样式 */
  .action-btn {
    padding: 0 !important;
    width: 32px !important;
    min-width: 32px !important;
    height: 32px !important;
    display: inline-flex !important; /* 改为 inline-flex */
    align-items: center;
    justify-content: center;
    border-radius: 4px;
    vertical-align: middle;
  }

  /* 强制显示图标并调整样式 */
  .action-btn :deep(.anticon) {
    font-size: 18px !important;
    margin: 0 !important;
    color: #fff !important;
    display: inline-block !important;
    line-height: 1;
  }
  
  /* 确保按钮内部的 span 不会干扰布局 */
  .action-btn > span {
    display: flex;
    align-items: center;
    justify-content: center;
  }
  
  .host-card :deep(.ant-table) {
    font-size: 12px;
  }
  
  .host-card :deep(.ant-table-thead > tr > th),
  .host-card :deep(.ant-table-tbody > tr > td) {
    padding: 8px 4px !important;
  }
  
  .host-card :deep(.ant-btn) {
    padding: 2px 4px;
    font-size: 11px;
  }
  
  /* 修复表格内操作栏下拉按钮 */
  .host-card :deep(.ant-table-tbody .ant-dropdown-trigger) {
    width: 24px;
    height: 24px;
    padding: 0;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }
  
  .host-card :deep(.ant-tag) {
    font-size: 10px;
    padding: 0 4px;
    margin: 0;
  }
}

@media (max-width: 480px) {
  .header-actions {
    gap: 6px;
  }
}
</style>
