<template>
  <div style="height: calc(100vh - 64px)">
    <a-card :bordered="false" class="terminal-card">
      <template #title>
        <div class="terminal-toolbar">
          <a-select
            v-model:value="selectedHostId"
            :placeholder="t('terminal.selectHost')"
            class="host-select"
            size="small"
            :loading="loading"
            @change="handleHostSelect"
          >
            <a-select-option
              v-for="host in sshStore.hosts"
              :key="host.id"
              :value="host.id"
              :disabled="host.host_type === 'monitor_only'"
            >
              <DatabaseOutlined style="margin-right: 8px" :style="{ color: host.host_type === 'monitor_only' ? '#bfbfbf' : undefined }" />
              <span :style="{ color: host.host_type === 'monitor_only' ? '#bfbfbf' : undefined }">
                {{ host.name }} ({{ host.host }}:{{ host.port }})
                <span v-if="host.host_type === 'monitor_only'" style="color: #999">({{ t('host.monitorOnly') }})</span>
              </span>
            </a-select-option>
          </a-select>

          <a-tooltip :title="t('terminal.newHost')">
            <a-button type="primary" size="small" @click="handleAddHost" class="toolbar-btn">
              <PlusOutlined />
              <span class="btn-text">{{ t('terminal.newHost') }}</span>
            </a-button>
          </a-tooltip>

          <a-tooltip :title="t('terminal.quickConnect')">
            <a-button size="small" @click="handleQuickConnect" class="toolbar-btn">
              <ThunderboltOutlined />
              <span class="btn-text">{{ t('terminal.quickConnect') }}</span>
            </a-button>
          </a-tooltip>

          <a-divider type="vertical" class="toolbar-divider" />
          
          <div class="record-toggle">
            <VideoCameraOutlined :style="{ color: isRecordingEnabled ? '#ff4d4f' : '#8c8c8c' }" />
            <span class="record-text">{{ t('terminal.recordNextSession') }}</span>
            <a-switch v-model:checked="isRecordingEnabled" size="small" />
          </div>
        </div>
      </template>

      <div class="terminal-container-inner" style="height: 100%; display: flex; flex-direction: column">
        <a-tabs
          v-if="sshStore.terminalList.length > 0"
          v-model:activeKey="activeTerminalKey"
          type="editable-card"
          size="small"
          @edit="onTabEdit"
          class="terminal-tabs"
          :class="{ 'light-mode': !themeStore.isDark }"
          style="flex: 1; display: flex; flex-direction: column; overflow: hidden"
        >
          <a-tab-pane
            v-for="terminal in sshStore.terminalList"
            :key="terminal.id"
            :closable="true"
            style="flex: 1; height: 100%"
          >
            <template #tab>
              <div style="display: flex; align-items: center; gap: 6px">
                <span v-if="terminal.record" class="pulsing-dot"></span>
                {{ terminal.name }}
              </div>
            </template>
            <TerminalComponent
              :terminal-id="terminal.id"
              :host-id="terminal.hostId"
              :active="activeTerminalKey === terminal.id"
              :record="terminal.record"
              @close="() => closeTerminal(terminal.id)"
            />
          </a-tab-pane>

          <template #addIcon>
            <PlusOutlined />
          </template>
        </a-tabs>

        <div v-else style="flex: 1; display: flex; align-items: center; justify-content: center">
          <a-empty :description="t('terminal.noActiveTerminals')">
            <a-button type="primary" @click="handleQuickConnect">
              <PlusOutlined />
              {{ t('terminal.connectToHost') }}
            </a-button>
          </a-empty>
        </div>
      </div>
    </a-card>

    <!-- Host Form Modal -->
    <a-modal
      v-model:open="showHostModal"
      :title="editingHost ? t('host.editHost') : (isQuickConnect ? t('terminal.quickConnect') : t('host.addHost'))"
      @ok="handleSaveHost"
      :confirmLoading="saving"
    >
      <a-form :model="hostForm" layout="vertical">
        <a-form-item :label="t('host.name')" required>
          <a-input v-model:value="hostForm.name" :placeholder="t('host.placeholderName')" />
        </a-form-item>

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

        <a-form-item :label="t('host.group')">
          <a-input v-model:value="hostForm.group_name" :placeholder="t('host.placeholderGroup')" />
        </a-form-item>

        <a-form-item :label="t('host.description')">
          <a-textarea v-model:value="hostForm.description" :rows="3" />
        </a-form-item>
      </a-form>
    </a-modal>
  </div>
</template>

<script>
export default {
  name: 'Terminal'
}
</script>

<script setup>
import { ref, onMounted, onActivated, createVNode } from 'vue'
import { message, Modal } from 'ant-design-vue'
import {
  DatabaseOutlined,
  PlusOutlined,
  ThunderboltOutlined,
  ExclamationCircleOutlined,
  VideoCameraOutlined,
  BgColorsOutlined,
  CheckOutlined
} from '@ant-design/icons-vue'
import { useSSHStore } from '../stores/ssh'
import { useThemeStore } from '../stores/theme'
import { useI18n } from 'vue-i18n'
import TerminalComponent from '../components/Terminal.vue'
import { terminalThemes } from '../utils/terminalThemes'

const { t } = useI18n()
const sshStore = useSSHStore()
const themeStore = useThemeStore()

const selectedHostId = ref(null)
const activeTerminalKey = ref(null)
const loading = ref(false)
const showHostModal = ref(false)
const saving = ref(false)
const editingHost = ref(null)
const isRecordingEnabled = ref(false)

const isQuickConnect = ref(false)
const hostForm = ref({
  name: '',
  host: '',
  port: 22,
  username: '',
  auth_type: 'password',
  password: '',
  private_key: '',
  group_name: '',
  description: ''
})

onMounted(async () => {
  loading.value = true
  
  // Set active terminal if exists (e.g. navigating from HostManagement)
  if (sshStore.currentTerminalId) {
    activeTerminalKey.value = sshStore.currentTerminalId
  }

  try {
    await sshStore.fetchHosts()
  } catch (error) {
    message.error(t('host.failLoad'))
  } finally {
    loading.value = false
  }
})

// Using keep-alive, so rely on onActivated to sync state when switching back
onActivated(() => {
  if (sshStore.currentTerminalId) {
    activeTerminalKey.value = sshStore.currentTerminalId
  }
})

const handleHostSelect = (hostId) => {
  if (!hostId) return
  
  const host = sshStore.hosts.find(h => h.id === hostId)
  if (host) {
    // Check if host already has an open terminal
    const existingTerminal = sshStore.terminalList.find(t => t.hostId === hostId)
    
    if (existingTerminal) {
      Modal.confirm({
        title: t('terminal.hostAlreadyConnected'),
        icon: createVNode(ExclamationCircleOutlined),
        content: t('terminal.sessionAlreadyOpen', { name: host.name }),
        okText: t('host.switchToExisting'),
        cancelText: t('host.openNew'),
        onOk() {
          activeTerminalKey.value = existingTerminal.id
          selectedHostId.value = null
        },
        onCancel() {
          connectToHost(host)
          selectedHostId.value = null
        }
      })
    } else {
      connectToHost(host)
      selectedHostId.value = null
    }
  }
}

const connectToHost = (host) => {
  const terminalId = sshStore.addTerminal({
    hostId: host.id,
    name: host.name,
    host: host.host,
    port: host.port,
    record: isRecordingEnabled.value
  })
  activeTerminalKey.value = terminalId
}

const handleAddHost = () => {
  editingHost.value = null
  isQuickConnect.value = false
  showHostModal.value = true
  hostForm.value = {
    name: '',
    host: '',
    port: 22,
    username: '',
    auth_type: 'password',
    password: '',
    private_key: '',
    group_name: '',
    description: ''
  }
}

const handleQuickConnect = () => {
  editingHost.value = null
  isQuickConnect.value = true
  showHostModal.value = true
  hostForm.value = {
    name: t('terminal.quickConnectSession'),
    host: '',
    port: 22,
    username: 'root',
    auth_type: 'password',
    password: '',
    private_key: '',
    group_name: t('terminal.temporaryGroup'),
    description: t('terminal.onetimeSession')
  }
}

const handleSaveHost = async () => {
  if (!hostForm.value.name || !hostForm.value.host || !hostForm.value.username) {
    message.error(t('host.validationRequired'))
    return
  }

  if (!editingHost.value) {
    // Adding new host
    if (hostForm.value.auth_type === 'password' && !hostForm.value.password) {
      message.error(t('host.validationPassword'))
      return
    }

    if (hostForm.value.auth_type === 'key' && !hostForm.value.private_key) {
      message.error(t('host.validationKey'))
      return
    }
  }

  saving.value = true
  try {
    if (editingHost.value) {
      // Update existing host
      const updateData = { ...hostForm.value }
      // Remove empty password/key fields when editing
      if (!updateData.password) delete updateData.password
      if (!updateData.private_key) delete updateData.private_key
      
      await sshStore.modifyHost(editingHost.value.id, updateData)
      message.success(t('host.successUpdate'))
    } else {
      // Add new host
      const host = await sshStore.addHost(hostForm.value)
      message.success(t('host.successAdd'))
      
      // Connect to the newly added host
      connectToHost(host)
    }
    
    showHostModal.value = false
  } catch (error) {
    message.error(editingHost.value ? t('host.failUpdate') : t('host.failAdd'))
  } finally {
    saving.value = false
  }
}

const onTabEdit = (targetKey, action) => {
  if (action === 'add') {
    handleQuickConnect()
  } else if (action === 'remove') {
    closeTerminal(targetKey)
  }
}

const closeTerminal = (terminalId) => {
  sshStore.removeTerminal(terminalId)
  
  // Update active key
  const terminals = sshStore.terminalList
  if (terminals.length > 0) {
    activeTerminalKey.value = terminals[terminals.length - 1].id
  } else {
    activeTerminalKey.value = null
  }
}
</script>

<style scoped>
.terminal-card {
  height: 100%;
  display: flex;
  flex-direction: column;
}

:deep(.ant-card-body) {
  flex: 1;
  overflow: hidden;
  padding: 0;
  display: flex;
  flex-direction: column;
}

:deep(.terminal-tabs) {
  height: 100%;
}

/* VS Code Style Tabs Overrides */
:deep(.terminal-tabs.ant-tabs-card > .ant-tabs-nav) {
  margin-bottom: 0;
  background-color: #252526; /* VS Code Title Bar/Tabs Container Background */
  border-bottom: 1px solid #1e1e1e; /* Editor background color for separation */
}

:deep(.terminal-tabs.ant-tabs-card > .ant-tabs-nav .ant-tabs-tab) {
  border: none;
  background: #2d2d2d; /* Inactive tab background */
  margin-right: 1px;
  border-radius: 0;
  color: #969696;
  padding: 4px 12px;
  transition: none;
  height: 28px;
  line-height: 20px;
  font-family: 'Segoe WPC', 'Segoe UI', sans-serif;
  font-size: 13px;
}

:deep(.terminal-tabs.ant-tabs-card > .ant-tabs-nav .ant-tabs-tab:hover) {
  color: #e0e0e0;
}

:deep(.terminal-tabs.ant-tabs-card > .ant-tabs-nav .ant-tabs-tab-active) {
  background: #1e1e1e; /* Active tab background/Editor background */
  color: #ffffff;
  border-top: 1px solid #007acc; /* Active indicator */
}

:deep(.terminal-tabs.ant-tabs-card > .ant-tabs-nav .ant-tabs-tab-remove) {
  color: #cccccc;
  margin-left: 8px;
  font-size: 10px;
  transition: all 0.2s;
  opacity: 0; /* Hide close button by default like VS Code */
}

:deep(.terminal-tabs.ant-tabs-card > .ant-tabs-nav .ant-tabs-tab:hover .ant-tabs-tab-remove),
:deep(.terminal-tabs.ant-tabs-card > .ant-tabs-nav .ant-tabs-tab-active .ant-tabs-tab-remove) {
  opacity: 1; /* Show on hover or active */
}

:deep(.terminal-tabs.ant-tabs-card > .ant-tabs-nav .ant-tabs-tab-remove:hover) {
  color: #ffffff;
  background: rgba(255, 255, 255, 0.2);
  border-radius: 4px;
}

:deep(.terminal-tabs .ant-tabs-nav-add) {
  border: none;
  background: transparent;
  color: #cccccc;
}

:deep(.terminal-tabs .ant-tabs-nav-add:hover) {
  background: rgba(255, 255, 255, 0.1);
  color: #ffffff;
}

/* Light Mode Styles */
:deep(.terminal-tabs.light-mode.ant-tabs-card > .ant-tabs-nav) {
  background-color: #f3f3f3;
  border-bottom: 1px solid #d4d4d4;
}

:deep(.terminal-tabs.light-mode.ant-tabs-card > .ant-tabs-nav .ant-tabs-tab) {
  background: #ececec;
  color: #616161;
}

:deep(.terminal-tabs.light-mode.ant-tabs-card > .ant-tabs-nav .ant-tabs-tab:hover) {
  background: #e6e6e6;
  color: #333333;
}

:deep(.terminal-tabs.light-mode.ant-tabs-card > .ant-tabs-nav .ant-tabs-tab-active) {
  background: #ffffff;
  color: #333333;
  border-top: 1px solid #007acc;
}

:deep(.terminal-tabs.light-mode.ant-tabs-card > .ant-tabs-nav .ant-tabs-tab-remove) {
  color: #999999;
}

:deep(.terminal-tabs.light-mode.ant-tabs-card > .ant-tabs-nav .ant-tabs-tab-remove:hover) {
  color: #333333;
  background: rgba(0, 0, 0, 0.1);
}

:deep(.terminal-tabs.light-mode .ant-tabs-nav-add) {
  color: #999999;
}

:deep(.terminal-tabs.light-mode .ant-tabs-nav-add:hover) {
  background: rgba(0, 0, 0, 0.05);
  color: #333333;
}

/* Dark mode adjustment helper if needed, though specific colors above are hardcoded for dark theme concept */
/* For a true light/dark switch, we would use css variables, but requested "VS Code style" usually implies the dark look for terminals */


:deep(.ant-tabs-content) {
  flex: 1;
  height: 100%;
}

:deep(.ant-tabs-tabpane) {
  display: flex;
  flex-direction: column;
}

.pulsing-dot {
  width: 8px;
  height: 8px;
  background-color: #ff4d4f;
  border-radius: 50%;
  box-shadow: 0 0 0 rgba(255, 77, 79, 0.4);
  animation: pulse 1.5s infinite;
}

@keyframes pulse {
  0% {
    box-shadow: 0 0 0 0 rgba(255, 77, 79, 0.7);
  }
  70% {
    box-shadow: 0 0 0 6px rgba(255, 77, 79, 0);
  }
  100% {
    box-shadow: 0 0 0 0 rgba(255, 77, 79, 0);
  }
}

/* Terminal Toolbar Styles */
.terminal-toolbar {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: nowrap;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
  padding: 4px 0;
}

.host-select {
  width: 280px;
  min-width: 120px;
  flex-shrink: 1;
}

.toolbar-btn {
  display: flex;
  align-items: center;
  gap: 4px;
  flex-shrink: 0;
}

.toolbar-divider {
  flex-shrink: 0;
}

.record-toggle {
  display: flex;
  align-items: center;
  gap: 4px;
  border: 1px solid #d9d9d9;
  padding: 0 8px;
  border-radius: 4px;
  background: rgba(0,0,0,0.02);
  height: 24px;
  flex-shrink: 0;
  white-space: nowrap;
}

.record-text {
  font-size: 12px;
  color: #595959;
}

/* Mobile Responsive Styles */
@media (max-width: 768px) {
  .terminal-toolbar {
    gap: 6px;
  }
  
  .host-select {
    width: 140px;
    min-width: 100px;
  }
  
  .toolbar-btn .btn-text {
    display: none;
  }
  
  .toolbar-btn {
    padding: 4px 8px !important;
  }
  
  .record-text {
    display: none;
  }
  
  .record-toggle {
    padding: 0 6px;
  }
  
  .toolbar-divider {
    display: none;
  }
}

@media (max-width: 480px) {
  .host-select {
    width: 100px;
    min-width: 80px;
  }
}
</style>
