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
          
          <!-- Show/Hide Deleted Button -->
          <a-tooltip :title="showDeleted ? t('host.hideDeleted') : t('host.showDeleted')">
            <a-button 
              size="small"
              :type="showDeleted ? 'primary' : 'default'"
              @click="toggleShowDeleted"
              class="action-btn"
            >
              <DeleteOutlined />
              <span v-if="!isMobile" class="btn-text">{{ showDeleted ? t('host.hideDeleted') : t('host.showDeleted') }}</span>
            </a-button>
          </a-tooltip>
          
          <!-- Quick Filter Buttons -->
          <a-radio-group 
            v-model:value="quickFilter" 
            button-style="solid" 
            size="small"
            @change="handleQuickFilterChange"
            class="quick-filter-group"
          >
            <a-radio-button value="all">{{ t('host.filterAll') }}</a-radio-button>
            <a-radio-button value="online">{{ t('host.filterOnline') }}</a-radio-button>
            <a-radio-button value="offline">{{ t('host.filterOffline') }}</a-radio-button>
            <a-radio-button value="expiring">{{ t('host.filterExpiring') }}</a-radio-button>
            <a-radio-button value="expired">{{ t('host.filterExpired') }}</a-radio-button>
            <a-radio-button value="deleted">{{ t('host.filterDeleted') }}</a-radio-button>
          </a-radio-group>
          
          <a-button 
            v-if="hasSelected"
            type="primary"
            size="small"
            @click="openBatchDeployModal"
            class="action-btn"
          >
            <CloudUploadOutlined />
            <span v-if="!isMobile" class="btn-text">{{ t('monitor.batchDeploy') }} ({{ selectedRowKeys.length }})</span>
          </a-button>

          <!-- Batch Traffic Notification -->
          <a-dropdown v-if="hasSelected">
            <template #overlay>
              <a-menu @click="handleBatchNotifyTraffic">
                <a-menu-item key="enable">
                  <CheckCircleOutlined style="color: #52c41a" /> {{ t('monitor.enable') }}
                </a-menu-item>
                <a-menu-item key="disable">
                  <StopOutlined style="color: #ff4d4f" /> {{ t('monitor.disable') }}
                </a-menu-item>
              </a-menu>
            </template>
            <a-button size="small" class="action-btn">
              <BellOutlined /> 
              <span v-if="!isMobile" class="btn-text">{{ t('monitor.batchTrafficNotify') }}</span>
              <DownOutlined />
            </a-button>
          </a-dropdown>

          <!-- Batch Offline Notification -->
           <a-dropdown v-if="hasSelected">
            <template #overlay>
              <a-menu @click="handleBatchNotifyOffline">
                <a-menu-item key="enable">
                  <CheckCircleOutlined style="color: #52c41a" /> {{ t('monitor.enable') }}
                </a-menu-item>
                <a-menu-item key="disable">
                  <StopOutlined style="color: #ff4d4f" /> {{ t('monitor.disable') }}
                </a-menu-item>
              </a-menu>
            </template>
            <a-button size="small" class="action-btn">
              <WifiOutlined /> 
              <span v-if="!isMobile" class="btn-text">{{ t('monitor.batchOfflineNotify') }}</span>
              <DownOutlined />
            </a-button>
          </a-dropdown>
          <a-button 
            v-if="hasSelected"
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
          :data-source="filteredHosts"
          :loading="loading"
          row-key="id"
          :pagination="false"
          :scroll="{ x: isMobile ? 600 : undefined, y: 'calc(100vh - 280px)' }"
          :row-class-name="(record) => record.deleted_at ? 'deleted-row' : ''"
          @change="handleTableChange"
        >
        <template #bodyCell="{ column, record }">
          <template v-if="column.key === 'drag'">
            <div class="drag-handle" style="cursor: move; color: #999; display: flex; justify-content: center; align-items: center; height: 100%;">
               <HolderOutlined />
            </div>
          </template>
          <template v-if="column.key === 'name'">
            <span style="display: flex; align-items: center;">
              <span v-if="record.flag" :style="{
                display: 'inline-block',
                width: '8px',
                height: '8px',
                borderRadius: '50%',
                backgroundColor: flagColorsMap[record.flag],
                marginRight: '6px'
              }"></span>
              {{ record.name }}
            </span>
          </template>
          <template v-if="column.key === 'status'">
            <div style="display: flex; align-items: center">
              <!-- Show "Deleted" tag for deleted hosts -->
              <a-tag v-if="record.deleted_at" color="default">
                {{ t('host.deleted') }}
              </a-tag>
              <!-- Show connection status for active hosts -->
              <a-tooltip v-else :title="hostStatuses[record.id]?.status === 'online' ? t('monitor.online') : (hostStatuses[record.id]?.error || t('monitor.checking'))">
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
          <template v-if="column.key === 'expiration_date'">
            <span v-if="record.expiration_date" :style="{ color: getDaysUntilExpiration(record.expiration_date) < 0 ? '#f5222d' : (getDaysUntilExpiration(record.expiration_date) <= 7 ? '#faad14' : undefined) }">
              {{ dayjs(record.expiration_date).format('YYYY-MM-DD') }}
            </span>
            <span v-else style="color: #999">-</span>
          </template>
          <template v-if="column.key === 'billing_period'">
            <a-tag v-if="record.billing_period" size="small">
              {{ t(`host.billing${record.billing_period.charAt(0).toUpperCase() + record.billing_period.slice(1)}`) }}
            </a-tag>
            <span v-else style="color: #999">-</span>
          </template>
          <template v-if="column.key === 'remaining_value'">
            <span v-if="record.expiration_date && record.billing_period && record.billing_amount">
              {{ calculateRemainingValue(record.expiration_date, record.billing_period, record.billing_amount, record.currency) }}
            </span>
            <span v-else style="color: #999">-</span>
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
                    <!-- Monitor Actions -->
                    <a-menu-item key="auto" @click="openDeployModal(record)" :disabled="record.host_type === 'monitor_only'">
                       <CloudUploadOutlined /> {{ t('monitor.autoDeploy') }}
                    </a-menu-item>
                    <a-menu-item key="manual" @click="openInstallCommandModal(record)">
                       <CopyOutlined /> {{ t('monitor.manualInstall') }}
                    </a-menu-item>
                    <a-menu-item key="stop" @click="confirmStopMonitor(record)" :disabled="record.host_type === 'monitor_only'" style="color: #ff4d4f">
                       <StopOutlined /> {{ t('monitor.stop') }}
                    </a-menu-item>
                    <a-menu-item key="uninstall" @click="openUninstallCommandModal(record)" style="color: #ff4d4f">
                       <DeleteOutlined /> {{ t('monitor.manualUninstall') }}
                    </a-menu-item>
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
                    <a-menu-item 
                      v-if="!record.deleted_at"
                      key="delete" 
                      @click="confirmDelete(record.id)" 
                      style="color: #ff4d4f"
                    >
                      <DeleteOutlined /> {{ t('common.delete') }}
                    </a-menu-item>
                    <a-menu-item 
                      v-else
                      key="permanent-delete" 
                      @click="handlePermanentDelete(record.id)"
                      style="color: #ff4d4f"
                    >
                      <DeleteOutlined /> {{ t('host.permanentDelete') }}
                    </a-menu-item>
                  </a-menu>
                </template>
              </a-dropdown>
            </template>
            
            <!-- Desktop: Show all buttons -->
            <a-space v-else>
              
              <!-- 监控管理下拉菜单 -->
              <a-dropdown :trigger="['click']">
                 <a-button size="small" :loading="monitorLoading[record.id]">
                   <DashboardOutlined />
                   {{ t('host.monitor') }}
                   <DownOutlined style="font-size: 10px; margin-left: 4px" />
                 </a-button>
                 <template #overlay>
                   <a-menu>
                     <!-- Auto Deploy -->
                     <a-menu-item key="auto" @click="openDeployModal(record)" :disabled="record.host_type === 'monitor_only'">
                       <CloudUploadOutlined />
                       {{ t('monitor.autoDeploy') }}
                     </a-menu-item>
                     
                     <!-- Manual Install -->
                     <a-menu-item key="manual" @click="openInstallCommandModal(record)">
                        <CopyOutlined />
                        {{ t('monitor.manualInstall') }}
                     </a-menu-item>
                     
                     <a-menu-divider />
                     
                     <!-- Stop Monitor -->
                     <a-menu-item key="stop" @click="confirmStopMonitor(record)" :disabled="record.host_type === 'monitor_only'" style="color: #ff4d4f">
                        <StopOutlined />
                        {{ t('monitor.stop') }}
                     </a-menu-item>
                     
                     <!-- Manual Uninstall -->
                      <a-menu-item key="uninstall" @click="openUninstallCommandModal(record)" style="color: #ff4d4f">
                        <DeleteOutlined />
                        {{ t('monitor.manualUninstall') }}
                     </a-menu-item>
                   </a-menu>
                 </template>
              </a-dropdown>
              
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
              
              <!-- Delete button for active hosts -->
              <a-popconfirm
                v-if="!record.deleted_at"
                :title="t('host.deleteConfirm')"
                @confirm="handleDelete(record.id)"
              >
                <a-button size="small" danger>
                  <DeleteOutlined />
                  {{ t('common.delete') }}
                </a-button>
              </a-popconfirm>
              
              <!-- Permanent delete for deleted hosts -->
              <a-popconfirm
                v-else
                :title="t('host.permanentDeleteConfirm')"
                @confirm="handlePermanentDelete(record.id)"
              >
                <a-button size="small" danger>
                  <DeleteOutlined />
                  {{ t('host.permanentDelete') }}
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
            <a-input v-model:value="hostForm.host" :placeholder="t('host.placeholderHost')" autocomplete="new-password" />
          </a-form-item>

          <a-form-item :label="t('host.port')">
            <a-input-number v-model:value="hostForm.port" :min="1" :max="65535" style="width: 100%" />
          </a-form-item>

          <a-form-item :label="t('host.username')" required>
            <a-input v-model:value="hostForm.username" :placeholder="t('host.placeholderUsername')" autocomplete="new-password" />
          </a-form-item>

          <a-form-item :label="t('host.authMethod')" required>
            <a-radio-group v-model:value="hostForm.auth_type">
              <a-radio value="password">{{ t('host.authPassword') }}</a-radio>
              <a-radio value="key">{{ t('host.authKey') }}</a-radio>
            </a-radio-group>
          </a-form-item>

          <a-form-item v-if="hostForm.auth_type === 'password'" :label="t('host.password')" :required="!editingHost">
            <a-input-password v-model:value="hostForm.password" :placeholder="editingHost ? t('host.placeholderKeepPassword') : t('host.placeholderPassword')" autocomplete="new-password" />
          </a-form-item>

          <a-form-item v-if="hostForm.auth_type === 'key'" :label="t('host.privateKey')" :required="!editingHost">
            <a-textarea
              v-model:value="hostForm.private_key"
              :placeholder="editingHost ? t('host.placeholderKeepKey') : t('host.placeholderPrivateKey')"
              :rows="6"
            />
            <div style="margin-top: 4px; font-size: 12px; color: #888;">
              {{ t('host.privateKeyHelp') }}
            </div>
          </a-form-item>
        </template>

        <!-- 分组和描述 - 始终显示 -->
        <a-form-item :label="t('host.group')">
          <a-input v-model:value="hostForm.group_name" :placeholder="t('host.placeholderGroup')" />
        </a-form-item>

        <a-form-item :label="t('host.description')">
          <a-textarea v-model:value="hostForm.description" :rows="3" />
        </a-form-item>

        <!-- Host Flag Selection -->
        <a-form-item :label="t('host.flag')">
          <a-radio-group v-model:value="hostForm.flag">
            <a-radio-button value="">
              <span style="color: #666; font-size: 12px">{{ t('host.flagNone') }}</span>
            </a-radio-button>
            <a-radio-button v-for="color in flagColors" :key="color.value" :value="color.value">
              <span :style="{ 
                display: 'inline-block', 
                width: '12px', 
                height: '12px', 
                borderRadius: '50%', 
                backgroundColor: color.code,
                border: '1px solid rgba(0,0,0,0.1)' 
              }"></span>
            </a-radio-button>
          </a-radio-group>
        </a-form-item>

        <!-- Financial Management Section -->
        <a-divider style="margin: 12px 0">{{ t('host.financialManagement') }}</a-divider>
        
        <a-form-item :label="t('host.expirationDate')">
          <a-date-picker 
            v-model:value="hostForm.expiration_date" 
            style="width: 100%" 
            :placeholder="t('host.placeholderExpirationDate')"
            format="YYYY-MM-DD"
            :locale="locale"
          />
        </a-form-item>

        <a-row :gutter="16">
          <a-col :span="12">
            <a-form-item :label="t('host.billingPeriod')">
              <a-select v-model:value="hostForm.billing_period" :placeholder="t('host.placeholderBillingPeriod')">
                <a-select-option value="">{{ t('host.billingNone') }}</a-select-option>
                <a-select-option value="monthly">{{ t('host.billingMonthly') }}</a-select-option>
                <a-select-option value="quarterly">{{ t('host.billingQuarterly') }}</a-select-option>
                <a-select-option value="semiannually">{{ t('host.billingSemiannually') }}</a-select-option>
                <a-select-option value="annually">{{ t('host.billingAnnually') }}</a-select-option>
                <a-select-option value="biennial">{{ t('host.billingBiennial') }}</a-select-option>
                <a-select-option value="triennial">{{ t('host.billingTriennial') }}</a-select-option>
                <a-select-option value="4year">{{ t('host.billing4Year') }}</a-select-option>
                <a-select-option value="5year">{{ t('host.billing5Year') }}</a-select-option>
                <a-select-option value="6year">{{ t('host.billing6Year') }}</a-select-option>
                <a-select-option value="7year">{{ t('host.billing7Year') }}</a-select-option>
                <a-select-option value="8year">{{ t('host.billing8Year') }}</a-select-option>
                <a-select-option value="9year">{{ t('host.billing9Year') }}</a-select-option>
                <a-select-option value="10year">{{ t('host.billing10Year') }}</a-select-option>
              </a-select>
            </a-form-item>
          </a-col>
          <a-col :span="12">
            <a-form-item :label="t('host.billingAmount')">
              <a-input-group compact>
                <a-select v-model:value="hostForm.currency" style="width: 30%">
                  <a-select-option value="CNY">¥ CNY</a-select-option>
                  <a-select-option value="USD">$ USD</a-select-option>
                  <a-select-option value="EUR">€ EUR</a-select-option>
                  <a-select-option value="GBP">£ GBP</a-select-option>
                  <a-select-option value="JPY">¥ JPY</a-select-option>
                </a-select>
                <a-input-number 
                  v-model:value="hostForm.billing_amount" 
                  :min="0" 
                  :precision="2"
                  style="width: 70%" 
                  :placeholder="t('host.placeholderBillingAmount')"
                />
              </a-input-group>
            </a-form-item>
          </a-col>
        </a-row>
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
              <div style="width: 100%" :style="{ opacity: item.host_type === 'monitor_only' ? 0.5 : 1, filter: item.host_type === 'monitor_only' ? 'grayscale(100%)' : 'none' }">
                <a-space style="justify-content: space-between; width: 100%">
                  <span>{{ item.name }} ({{ item.host }})</span>
                  <!-- Dynamic Status Tags -->
                  <template v-if="deployStatus[item.id]?.status === 'success'">
                     <a-tag color="green">{{ t('monitor.deployed') }}</a-tag>
                  </template>
                  <template v-else-if="deployStatus[item.id]?.status === 'error'">
                     <a-tag color="red">{{ t('monitor.redeploy') }}</a-tag>
                  </template>
                  <template v-else>
                      <a-tag v-if="item.host_type === 'monitor_only'" color="blue">
                        {{ t('host.monitorOnly') }}
                      </a-tag>
                      <a-tag v-else-if="item.monitor_enabled" color="blue">
                        {{ t('monitor.willRedeploy') }}
                      </a-tag>
                  </template>
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
        
        <!-- Platform selector -->
        <a-radio-group v-model:value="installPlatform" style="margin-bottom: 12px">
          <a-radio-button value="linux">Linux</a-radio-button>
          <a-radio-button value="windows">Windows</a-radio-button>
        </a-radio-group>
        
        <p style="margin-bottom: 8px; color: #666; font-size: 13px">
          {{ installPlatform === 'linux' ? t('monitor.installSupport') : t('monitor.windowsInstallSupport') }}
        </p>
        
        <div style="position: relative; margin-bottom: 16px">
          <pre :style="{
            background: themeStore.isDark ? '#1f1f1f' : '#f5f5f5',
            color: themeStore.isDark ? '#d4d4d4' : '#24292e',
            padding: '16px',
            paddingRight: '90px',
            borderRadius: '4px',
            fontSize: '13px',
            overflow: 'auto',
            wordBreak: 'break-all',
            whiteSpace: 'pre-wrap',
            border: themeStore.isDark ? '1px solid #3f3f3f' : 'none'
          }">{{ getInstallCommand() }}</pre>
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
defineOptions({ name: 'HostManagement' })
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
  HolderOutlined,
  BellOutlined,
  WifiOutlined,
  CheckCircleOutlined
} from '@ant-design/icons-vue'
import { useSSHStore } from '../stores/ssh'
import { useThemeStore } from '../stores/theme'
import { useI18n } from 'vue-i18n'
import { deployMonitor, stopMonitor, batchDeployMonitor, batchStopMonitor } from '../api/ssh'
import Sortable from 'sortablejs'
import dayjs from 'dayjs'
import 'dayjs/locale/zh-cn'
import zhCN from 'ant-design-vue/es/locale/zh_CN'
import enUS from 'ant-design-vue/es/locale/en_US'

const router = useRouter()
const sshStore = useSSHStore()
const themeStore = useThemeStore()
const { t, locale: i18nLocale } = useI18n()

// Configure dayjs locale based on current language
watch(i18nLocale, (newLocale) => {
  dayjs.locale(newLocale === 'zh-CN' ? 'zh-cn' : 'en')
}, { immediate: true })

// DatePicker locale based on current language
const locale = computed(() => {
  return i18nLocale.value === 'zh-CN' ? zhCN : enUS
})

const loading = ref(false)
const searchText = ref('')
const showDeleted = ref(false) // Show deleted hosts toggle
const quickFilter = ref('all') // Quick filter: all, online, offline, expiring, expired
const sortedInfo = ref({})
const filteredInfo = ref({})
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
const hasSelected = computed(() => selectedRowKeys.value.length > 0)

const batchStopVisible = ref(false)
const batchStopping = ref(false)
const stopStatus = ref({})

const installCommandVisible = ref(false)
const installCommandHost = ref(null)
const installPlatform = ref('linux')

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
  host_type: 'control_monitor',
  expiration_date: null,
  billing_period: '',
  billing_amount: 0,
  currency: 'CNY',
  flag: ''
})

const flagColors = [
  { value: 'red', code: '#FF3B30', label: 'Red' },
  { value: 'orange', code: '#FF9500', label: 'Orange' },
  { value: 'yellow', code: '#FFCC00', label: 'Yellow' },
  { value: 'green', code: '#4CD964', label: 'Green' },
  { value: 'blue', code: '#007AFF', label: 'Blue' },
  { value: 'purple', code: '#5856D6', label: 'Purple' },
  { value: 'gray', code: '#8E8E93', label: 'Gray' }
]

const flagColorsMap = {
  red: '#FF3B30',
  orange: '#FF9500',
  yellow: '#FFCC00',
  green: '#4CD964',
  blue: '#007AFF',
  purple: '#5856D6',
  gray: '#8E8E93'
}

// Mobile detection
const isMobile = ref(false)
const checkMobile = () => {
  isMobile.value = window.innerWidth < 768
}

// Dynamic filter options
const uniqueGroups = computed(() => {
  const groups = [...new Set(sshStore.hosts.map(h => h.group_name).filter(Boolean))]
  return groups.map(g => ({ text: g, value: g }))
})

const uniqueBillingPeriods = computed(() => {
  const periods = [...new Set(sshStore.hosts.map(h => h.billing_period).filter(Boolean))]
  return periods.map(p => ({ text: t(`host.billing${p.charAt(0).toUpperCase() + p.slice(1)}`), value: p }))
})

const hostTypeFilters = computed(() => [
  { text: t('host.controlAndMonitor'), value: 'control_monitor' },
  { text: t('host.monitorOnly'), value: 'monitor_only' }
])

const monitorStatusFilters = computed(() => [
  { text: t('host.monitoringEnabled'), value: true },
  { text: t('host.monitoringDisabled'), value: false }
])

const columns = computed(() => {
  const baseColumns = [
    { title: '', key: 'drag', width: 30, align: 'center', fixed: isMobile.value ? undefined : undefined },
    { 
      title: t('host.name'), 
      dataIndex: 'name', 
      key: 'name', 
      width: 120, 
      ellipsis: true,
      sorter: (a, b) => a.name.localeCompare(b.name),
      sortDirections: ['ascend', 'descend'],
      sortOrder: sortedInfo.value.columnKey === 'name' ? sortedInfo.value.order : null
    },
    { 
      title: t('host.host'), 
      dataIndex: 'host', 
      key: 'host', 
      width: 120, 
      ellipsis: true,
      sorter: (a, b) => a.host.localeCompare(b.host),
      sortDirections: ['ascend', 'descend'],
      sortOrder: sortedInfo.value.columnKey === 'host' ? sortedInfo.value.order : null
    },
    { title: t('monitor.status'), key: 'status', width: 80 },
    { 
      title: t('monitor.monitoring'), 
      key: 'monitor', 
      width: 80,
      filters: monitorStatusFilters.value,
      filteredValue: filteredInfo.value.monitor || null,
      onFilter: (value, record) => record.monitor_enabled === value
    },
    { 
      title: t('host.type'), 
      key: 'type', 
      width: 100,
      filters: hostTypeFilters.value,
      filteredValue: filteredInfo.value.type || null,
      onFilter: (value, record) => record.host_type === value
    },
  ]
  
  // Only show these columns on desktop
  if (!isMobile.value) {
    baseColumns.push(
      { 
        title: t('host.port'), 
        dataIndex: 'port', 
        key: 'port', 
        width: 60,
        sorter: (a, b) => a.port - b.port,
        sortDirections: ['ascend', 'descend'],
        sortOrder: sortedInfo.value.columnKey === 'port' ? sortedInfo.value.order : null
      },
      { 
        title: t('host.username'), 
        dataIndex: 'username', 
        key: 'username', 
        width: 100,
        sorter: (a, b) => a.username.localeCompare(b.username),
        sortDirections: ['ascend', 'descend'],
        sortOrder: sortedInfo.value.columnKey === 'username' ? sortedInfo.value.order : null
      },
      { 
        title: t('host.group'), 
        dataIndex: 'group_name', 
        key: 'group_name', 
        width: 100,
        filters: uniqueGroups.value,
        filteredValue: filteredInfo.value.group_name || null,
        onFilter: (value, record) => record.group_name === value,
        sorter: (a, b) => (a.group_name || '').localeCompare(b.group_name || ''),
        sortDirections: ['ascend', 'descend'],
        sortOrder: sortedInfo.value.columnKey === 'group_name' ? sortedInfo.value.order : null
      },
      { 
        title: t('host.expirationDate'), 
        key: 'expiration_date', 
        width: 110,
        sorter: (a, b) => {
          const dateA = a.expiration_date ? new Date(a.expiration_date).getTime() : 0
          const dateB = b.expiration_date ? new Date(b.expiration_date).getTime() : 0
          return dateA - dateB
        },
        sortDirections: ['ascend', 'descend'],
        sortOrder: sortedInfo.value.columnKey === 'expiration_date' ? sortedInfo.value.order : null
      },
      { 
        title: t('host.billingPeriod'), 
        key: 'billing_period', 
        width: 90,
        filters: uniqueBillingPeriods.value,
        filteredValue: filteredInfo.value.billing_period || null,
        onFilter: (value, record) => record.billing_period === value
      },
      { title: t('host.remainingValue'), key: 'remaining_value', width: 100 },
      { title: t('host.description'), key: 'description', width: 150, ellipsis: true },
    )
  }
  
  baseColumns.push({ title: t('common.edit'), key: 'action', width: isMobile.value ? 60 : 360, fixed: 'right' })
  
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

// Quick filter logic
const filteredHosts = computed(() => {
  let hosts = sshStore.hosts
  
  if (quickFilter.value === 'online') {
    hosts = hosts.filter(h => hostStatuses.value[h.id]?.status === 'online')
  } else if (quickFilter.value === 'offline') {
    hosts = hosts.filter(h => hostStatuses.value[h.id]?.status === 'offline' || !hostStatuses.value[h.id])
  } else if (quickFilter.value === 'expiring') {
    // Hosts expiring in 7 days
    hosts = hosts.filter(h => {
      if (!h.expiration_date) return false
      const days = getDaysUntilExpiration(h.expiration_date)
      return days > 0 && days <= 7
    })
  } else if (quickFilter.value === 'expired') {
    // Hosts that have expired
    hosts = hosts.filter(h => {
      if (!h.expiration_date) return false
      const days = getDaysUntilExpiration(h.expiration_date)
      return days < 0
    })
  } else if (quickFilter.value === 'deleted') {
    // Only show deleted hosts
    hosts = hosts.filter(h => h.deleted_at)
  }
  
  return hosts
})

// Financial calculation helpers
const getDaysUntilExpiration = (expirationDate) => {
  if (!expirationDate) return 0
  const now = dayjs()
  const expDate = dayjs(expirationDate)
  return expDate.diff(now, 'day')
}

const calculateRemainingValue = (expirationDate, billingPeriod, billingAmount, currency = 'CNY') => {
  const daysRemaining = getDaysUntilExpiration(expirationDate)
  if (daysRemaining < 0) return t('host.expired')
  
  // Days per billing period
  const periodDays = {
    'monthly': 30,
    'quarterly': 90,
    'semiannually': 180,
    'annually': 365,
    'biennial': 730,
    'triennial': 1095,
    '4year': 1460,
    '5year': 1825,
    '6year': 2190,
    '7year': 2555,
    '8year': 2920,
    '9year': 3285,
    '10year': 3650
  }
  
  // Currency symbols
  const currencySymbols = {
    'CNY': '¥',
    'USD': '$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥'
  }
  
  const days = periodDays[billingPeriod] || 30
  const dailyRate = billingAmount / days
  const remaining = (dailyRate * daysRemaining).toFixed(2)
  const symbol = currencySymbols[currency] || '¥'
  
  return `${symbol}${remaining} (${daysRemaining}${t('host.daysRemaining')})`
}

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

const confirmStopMonitor = (host) => {
  Modal.confirm({
    title: t('monitor.stop'),
    content: t('monitor.disableConfirm'),
    okText: t('common.confirm'),
    cancelText: t('common.cancel'),
    onOk: () => handleStopMonitor(host)
  })
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
  
  // Filter out deleted hosts from status check
  const activeHosts = sshStore.hosts.filter(host => !host.deleted_at)
  
  const checks = activeHosts.map(async (host) => {
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
    const filters = {}
    if (showDeleted.value) {
      filters.include_deleted = 'true'
    }
    if (searchText.value) {
      filters.search = searchText.value
    }
    await sshStore.fetchHosts(filters)
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

const toggleShowDeleted = async () => {
  showDeleted.value = !showDeleted.value
  await loadHosts()
}

const handleTableChange = (pagination, filters, sorter) => {
  sortedInfo.value = sorter
  filteredInfo.value = filters
}

const handleQuickFilterChange = async () => {
  // Quick filter will be applied in computed filtered hosts
  // No need to reload, just let Vue reactivity handle it
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
    host_type: 'control_monitor',
    expiration_date: null,
    billing_period: '',
    billing_amount: 0,
    currency: 'CNY'
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
    const fullHost = await sshStore.fetchHost(host.id, { reveal: true })
    hostForm.value = {
      name: fullHost.name,
      host: fullHost.host,
      port: fullHost.port,
      username: fullHost.username,
      auth_type: fullHost.auth_type,
      password: fullHost.password || '',
      private_key: '',
      group_name: fullHost.group_name || '',
      description: fullHost.description || '',
      host_type: fullHost.host_type || 'control_monitor',
      expiration_date: fullHost.expiration_date ? dayjs(fullHost.expiration_date) : null,
      billing_period: fullHost.billing_period || '',
      billing_amount: fullHost.billing_amount || 0,
      currency: fullHost.currency || 'CNY'
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
      
      // Cleanup SSH data for monitor_only hosts (prevent browser auto-fill contamination)
      if (updateData.host_type === 'monitor_only') {
        updateData.host = ""
        updateData.port = 22
        updateData.username = ""
        updateData.auth_type = "password"
        delete updateData.password
        delete updateData.private_key
      }

      // Convert dayjs date to ISO string for backend
      if (updateData.expiration_date) {
        updateData.expiration_date = updateData.expiration_date.format('YYYY-MM-DD')
      }
      
      await sshStore.modifyHost(editingHost.value.id, updateData)
      message.success(t('host.successUpdate'))
    } else {
      const addData = { ...hostForm.value }
      
      // Cleanup SSH data for monitor_only hosts
      if (addData.host_type === 'monitor_only') {
        addData.host = ""
        addData.port = 22
        addData.username = ""
        addData.auth_type = "password"
        delete addData.password
        delete addData.private_key
      }

      // Convert dayjs date to ISO string for backend
      if (addData.expiration_date) {
        addData.expiration_date = addData.expiration_date.format('YYYY-MM-DD')
      }
      
      await sshStore.addHost(addData)
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

const handlePermanentDelete = async (id) => {
  try {
    await sshStore.permanentDeleteHost(id)
    message.success(t('host.permanentDeleteSuccess'))
  } catch (error) {
    message.error(t('host.permanentDeleteFailed'))
  }
}

const openBatchDeployModal = () => {
  deployStatus.value = {}
  batchDeployVisible.value = true
}

const handleBatchDeploy = async () => {
  batchDeploying.value = true
  
  // Filter out monitor_only hosts
  const validHostIds = selectedRowKeys.value.filter(id => {
    const host = sshStore.hosts.find(h => h.id === id)
    return host && host.host_type !== 'monitor_only'
  })
  
  // Check if all selected hosts are monitor_only
  if (validHostIds.length === 0) {
    message.warning(t('monitor.noValidHostsForDeploy'))
    batchDeploying.value = false
    return
  }
  
  // Show info if some hosts were skipped
  if (validHostIds.length < selectedRowKeys.value.length) {
    const skippedCount = selectedRowKeys.value.length - validHostIds.length
    message.info(t('monitor.skippedMonitorOnly', { count: skippedCount }))
  }
  
  // 初始化状态 (只为有效主机)
  validHostIds.forEach(id => {
    deployStatus.value[id] = { status: 'waiting', message: t('monitor.deploying') }
  })
  
  let successCount = 0
  let failCount = 0
  
  try {
    await batchDeployMonitor(validHostIds, batchDeployInsecure.value, (result) => {
        // Real-time update
        deployStatus.value[result.host_id] = {
            status: result.success ? 'success' : 'error',
            message: result.message
        }
        if (result.success) successCount++
        else failCount++
    })
    
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
    console.error('Batch deploy error:', error)
    
    // Mark remaining waiting hosts as error
    validHostIds.forEach(id => {
      if (deployStatus.value[id].status === 'waiting') {
          deployStatus.value[id] = {
            status: 'error',
            message: error.message || '部署失败'
          }
      }
    })
    
    message.error(t('monitor.batchDeployFailed') + ': ' + (error.message || 'Error'))
  } finally {
    batchDeploying.value = false
  }
}

const handleBatchNotifyTraffic = async ({ key }) => {
  const enable = key === 'enable'
  const actionText = enable ? t('monitor.enable') : t('monitor.disable')
  const hide = message.loading(t('monitor.updating'), 0)
  
  try {
    let successCount = 0
    let failCount = 0
    
    // Process sequentially (or parallelLimit) to avoid flooding backend
    for (const id of selectedRowKeys.value) {
      try {
        await sshStore.modifyHost(id, { notify_traffic_enabled: enable })
        successCount++
      } catch (e) {
        failCount++
        console.error(`Failed to update traffic notify for host ${id}:`, e)
      }
    }
    
    hide()
    if (failCount === 0) {
      message.success(`${t('monitor.batchTrafficNotify')} ${actionText}: ${t('monitor.batchUpdateSuccess')}`)
    } else {
      message.warning(t('monitor.batchUpdatePartial', { success: successCount, fail: failCount }))
    }
    
    // Refresh list to reflect changes (though ModifyHost updates store, full refresh ensures consistency)
    loadHosts()
    selectedRowKeys.value = [] // Clear selection
  } catch (error) {
    hide()
    message.error(t('monitor.batchUpdateFailed'))
  }
}

const handleBatchNotifyOffline = async ({ key }) => {
  const enable = key === 'enable'
  const actionText = enable ? t('monitor.enable') : t('monitor.disable')
  const hide = message.loading(t('monitor.updating'), 0)
  
  try {
    let successCount = 0
    let failCount = 0
    
    for (const id of selectedRowKeys.value) {
      try {
        await sshStore.modifyHost(id, { notify_offline_enabled: enable })
        successCount++
      } catch (e) {
        failCount++
        console.error(`Failed to update offline notify for host ${id}:`, e)
      }
    }
    
    hide()
    if (failCount === 0) {
      message.success(`${t('monitor.batchOfflineNotify')} ${actionText}: ${t('monitor.batchUpdateSuccess')}`)
    } else {
      message.warning(t('monitor.batchUpdatePartial', { success: successCount, fail: failCount }))
    }
    
    loadHosts()
    selectedRowKeys.value = []
  } catch (error) {
    hide()
    message.error(t('monitor.batchUpdateFailed'))
  }
}

const openBatchStopModal = () => {
  stopStatus.value = {}
  batchStopVisible.value = true
}

const openInstallCommandModal = (host) => {
  installCommandHost.value = host
  installPlatform.value = 'linux' // Reset to Linux by default
  installCommandVisible.value = true
}

const getInstallCommand = () => {
  if (!installCommandHost.value) return ''
  
  const serverUrl = window.location.protocol + '//' + window.location.host
  const hostId = installCommandHost.value.id
  const secret = installCommandHost.value.monitor_secret || ''
  
  if (installPlatform.value === 'windows') {
    // Windows PowerShell command
    return `# Run this command in PowerShell as Administrator (v5.1 or later)
$url = "${serverUrl}/api/monitor/install?host_id=${hostId}&secret=${secret}&os=windows"
Invoke-WebRequest -Uri $url -UseBasicParsing | Select-Object -ExpandProperty Content | Invoke-Expression`
  } else {
    // Linux bash command
    return `curl -fsSL "${serverUrl}/api/monitor/install?host_id=${hostId}&secret=${secret}" | bash`
  }
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
    stopStatus.value[id] = { status: 'waiting', message: t('monitor.stopping') }
  })
  
  let successCount = 0
  let failCount = 0
  
  try {
    await batchStopMonitor(selectedRowKeys.value, (result) => {
        stopStatus.value[result.host_id] = {
            status: result.success ? 'success' : 'error',
            message: result.message
        }
        if (result.success) successCount++
        else failCount++
    })
    
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
    console.error('Batch stop error:', error)
    
     selectedRowKeys.value.forEach(id => {
      if (stopStatus.value[id].status === 'waiting') {
          stopStatus.value[id] = {
            status: 'error',
            message: error.message || t('monitor.stopFailed')
          }
      }
    })
    
    message.error(t('monitor.batchStopFailed') + ': ' + (error.message || t('common.error')))
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

  .quick-filter-group {
    margin-left: 4px;
  }

  .quick-filter-group :deep(.ant-radio-button-wrapper) {
    font-size: 12px;
    padding: 0 8px;
    height: 32px;
    line-height: 30px;
  }

  @media (max-width: 768px) {
    .quick-filter-group {
      display: none; /* Hide on mobile */
    }
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
    font-size: 11px;
    padding: 0 4px;
  }
}

/* Deleted host row styling */
:deep(.deleted-row) {
  opacity: 0.6;
  background-color: #fafafa;
}

:deep(.deleted-row td) {
  text-decoration: line-through;
  color: #999 !important;
}

:deep(html.dark .deleted-row) {
  background-color: #1f1f1f;
}

@media (max-width: 480px) {
  .header-actions {
    gap: 6px;
  }
}
</style>
