<template>
  <div class="system-management">
    <a-page-header
      :title="t('nav.system')"
      :sub-title="t('system.pageSubtitle')"
    />

    <a-layout class="system-layout">
      <a-layout-sider
        v-if="!isMobile"
        :width="200"
        class="system-sider"
        :style="{ background: themeStore.isDark ? '#1f1f1f' : '#fff' }"
      >
        <a-menu
          v-model:selectedKeys="sectionKeys"
          mode="inline"
          :items="sectionMenuItems"
          @click="onMenuClick"
        />
      </a-layout-sider>

      <a-layout-content class="system-content">
        <a-segmented
          v-if="isMobile"
          v-model:value="activeSection"
          :options="sectionOptions"
          block
          class="section-segmented"
          @change="onSectionChange"
        />

        <!-- General -->
        <section v-show="activeSection === 'general'" class="section-panel">
          <a-card :title="t('system.sectionGeneral')" :bordered="false">
            <p class="section-desc">{{ t('system.generalDesc') }}</p>
            <a-form :model="settingsForm" layout="vertical" @finish="() => handleSaveSettings('general')">
              <a-row :gutter="16">
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.timezone')" name="timezone" :extra="t('system.timezoneHelp')">
                    <a-select v-model:value="settingsForm.timezone">
                      <a-select-option value="Local">Local (Server Default)</a-select-option>
                      <a-select-option value="UTC">UTC</a-select-option>
                      <a-select-option value="Asia/Shanghai">Asia/Shanghai (CST)</a-select-option>
                      <a-select-option value="America/New_York">America/New_York (EST/EDT)</a-select-option>
                      <a-select-option value="Europe/London">Europe/London (GMT/BST)</a-select-option>
                      <a-select-option value="Asia/Tokyo">Asia/Tokyo (JST)</a-select-option>
                      <a-select-option value="Europe/Paris">Europe/Paris (CET/CEST)</a-select-option>
                    </a-select>
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.terminalCursorStyle')" name="terminal_cursor_style" :extra="t('system.terminalCursorStyleHelp')">
                    <a-select v-model:value="settingsForm.terminal_cursor_style">
                      <a-select-option value="bar">{{ t('system.terminalCursorBar') }}</a-select-option>
                      <a-select-option value="block">{{ t('system.terminalCursorBlock') }}</a-select-option>
                      <a-select-option value="underline">{{ t('system.terminalCursorUnderline') }}</a-select-option>
                    </a-select>
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.sshTimeout')" name="ssh_timeout" :extra="t('system.durationFormatHelp')">
                    <a-input v-model:value="settingsForm.ssh_timeout" placeholder="30s" />
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.idleTimeout')" name="idle_timeout" :extra="t('system.durationFormatHelp')">
                    <a-input v-model:value="settingsForm.idle_timeout" placeholder="30m" />
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.maxConnectionsPerUser')" name="max_connections_per_user">
                    <a-input-number v-model:value="settingsForm.max_connections_per_user" :min="1" style="width: 100%" />
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.loginRateLimit')" name="login_rate_limit" :extra="t('system.loginRateLimitHelp')">
                    <a-input-number v-model:value="settingsForm.login_rate_limit" :min="1" style="width: 100%" />
                  </a-form-item>
                </a-col>
              </a-row>
              <div class="form-footer">
                <a-button type="primary" :loading="settingsLoading" html-type="submit">{{ t('common.save') }}</a-button>
              </div>
            </a-form>
          </a-card>
        </section>

        <!-- Session -->
        <section v-show="activeSection === 'session'" class="section-panel">
          <a-card :title="t('system.sectionSession')" :bordered="false">
            <p class="section-desc">{{ t('system.sessionDesc') }}</p>
            <a-form :model="settingsForm" layout="vertical" @finish="() => handleSaveSettings('session')">
              <a-row :gutter="16">
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.accessExpiration')" name="access_expiration" :extra="t('system.durationFormatHelp')">
                    <a-input v-model:value="settingsForm.access_expiration" placeholder="60m" />
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :md="12">
                  <a-form-item :label="t('system.refreshExpiration')" name="refresh_expiration" :extra="t('system.durationFormatHelp')">
                    <a-input v-model:value="settingsForm.refresh_expiration" placeholder="168h" />
                  </a-form-item>
                </a-col>
              </a-row>
              <div class="form-footer">
                <a-button type="primary" :loading="settingsLoading" html-type="submit">{{ t('common.save') }}</a-button>
              </div>
            </a-form>
          </a-card>
        </section>

        <!-- Notification -->
        <section v-show="activeSection === 'notification'" class="section-panel">
          <a-card :title="t('system.sectionNotification')" :bordered="false">
            <p class="section-desc">{{ t('system.notificationDesc') }}</p>
            <a-form :model="settingsForm" layout="vertical" @finish="() => handleSaveSettings('notification')">
              <a-form-item :label="t('system.systemNotifyChannels')" name="system_notify_channels">
                <a-checkbox-group v-model:value="systemNotifyChannelList">
                  <a-checkbox value="email">{{ t('system.notifyChannelEmail') }}</a-checkbox>
                  <a-checkbox value="telegram">{{ t('system.notifyChannelTelegram') }}</a-checkbox>
                </a-checkbox-group>
                <div class="field-hint">{{ t('system.systemNotifyChannelsHelp') }}</div>
              </a-form-item>

              <a-collapse v-model:activeKey="notifyCollapseKeys" :bordered="false" class="notify-collapse">
                <a-collapse-panel key="email" :header="t('system.notifyChannelEmail')" :disabled="!emailChannelEnabled">
                  <a-row :gutter="16">
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.smtpServer')" name="smtp_server">
                        <a-input v-model:value="settingsForm.smtp_server" placeholder="smtp.example.com" :disabled="!emailChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.smtpPort')" name="smtp_port">
                        <a-input v-model:value="settingsForm.smtp_port" placeholder="587" :disabled="!emailChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.smtpUser')" name="smtp_user">
                        <a-input v-model:value="settingsForm.smtp_user" :disabled="!emailChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.smtpPassword')" name="smtp_password" :extra="t('system.smtpPasswordKeep')">
                        <a-input-password v-model:value="settingsForm.smtp_password" :disabled="!emailChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.smtpFrom')" name="smtp_from">
                        <a-input v-model:value="settingsForm.smtp_from" placeholder="noreply@example.com" :disabled="!emailChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.smtpTo')" name="smtp_to">
                        <a-input v-model:value="settingsForm.smtp_to" :placeholder="t('system.smtpToPlaceholder')" :disabled="!emailChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :span="24">
                      <a-form-item name="smtp_tls_skip_verify">
                        <a-checkbox v-model:checked="settingsForm.smtp_tls_skip_verify" :disabled="!emailChannelEnabled">
                          {{ t('system.smtpTlsSkipVerify') }}
                        </a-checkbox>
                      </a-form-item>
                    </a-col>
                  </a-row>
                  <a-button type="dashed" :loading="sendingTestEmail" :disabled="!emailChannelEnabled" @click="handleTestEmail">
                    {{ t('system.testEmail') }}
                  </a-button>
                </a-collapse-panel>

                <a-collapse-panel key="telegram" :header="t('system.notifyChannelTelegram')" :disabled="!telegramChannelEnabled">
                  <a-row :gutter="16">
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.telegramToken')" name="telegram_bot_token" :extra="t('system.smtpPasswordKeep')">
                        <a-input-password v-model:value="settingsForm.telegram_bot_token" :disabled="!telegramChannelEnabled" />
                      </a-form-item>
                    </a-col>
                    <a-col :xs="24" :md="12">
                      <a-form-item :label="t('system.telegramChatId')" name="telegram_chat_id">
                        <a-input v-model:value="settingsForm.telegram_chat_id" :disabled="!telegramChannelEnabled" />
                      </a-form-item>
                    </a-col>
                  </a-row>
                  <a-button type="dashed" :loading="sendingTestTelegram" :disabled="!telegramChannelEnabled" @click="handleTestTelegram">
                    {{ t('system.testTelegram') }}
                  </a-button>
                </a-collapse-panel>
              </a-collapse>

              <a-form-item :label="t('system.notificationTemplate')" name="notification_template" style="margin-top: 16px">
                <a-textarea v-model:value="settingsForm.notification_template" :rows="6" />
                <div class="template-actions">
                  <a-button size="small" @click="resetNotificationTemplate">{{ t('system.resetTemplate') }}</a-button>
                  <span class="field-hint">
                    {{ t('system.templateHelp') }}:
                    <span v-pre>{{emoji}}, {{event}}, {{client}}, {{message}}, {{time}}</span>
                  </span>
                </div>
              </a-form-item>

              <div class="form-footer">
                <a-button type="primary" :loading="settingsLoading" html-type="submit">{{ t('common.save') }}</a-button>
              </div>
            </a-form>
          </a-card>
        </section>

        <!-- Data: backup + restore -->
        <section v-show="activeSection === 'data'" class="section-panel">
          <a-card :title="t('system.sectionData')" :bordered="false">
            <p class="section-desc">{{ t('system.dataDesc') }}</p>
            <a-row :gutter="[16, 16]">
              <a-col :xs="24" :lg="12">
                <a-card size="small" :title="t('system.backupTitle')">
                  <p class="card-desc">{{ t('system.backupDesc') }}</p>
                  <a-button type="primary" :loading="backupLoading" @click="handleBackup">
                    <template #icon><DownloadOutlined /></template>
                    {{ t('system.startBackup') }}
                  </a-button>
                </a-card>
              </a-col>
              <a-col :xs="24" :lg="12">
                <a-card size="small" :title="t('system.restoreTitle')" class="danger-card">
                  <a-alert
                    :message="t('system.restoreWarningTitle')"
                    :description="t('system.restoreWarningDesc')"
                    type="error"
                    show-icon
                    style="margin-bottom: 16px"
                  />
                  <p class="card-desc">{{ t('system.restoreDesc') }}</p>
                  <a-upload
                    name="file"
                    :multiple="false"
                    :show-upload-list="false"
                    :before-upload="beforeRestoreUpload"
                    :disabled="restoreLoading"
                    @change="handleRestoreChange"
                  >
                    <a-button danger :loading="restoreLoading" :disabled="restoreLoading">
                      <template #icon><UploadOutlined /></template>
                      {{ t('system.startRestore') }}
                    </a-button>
                  </a-upload>
                  <div v-if="restoreLoading" class="restore-progress">
                    <a-progress
                      :percent="uploadPercent"
                      :status="restorePhase === 'restarting' ? 'success' : 'active'"
                      :stroke-color="restorePhase === 'restarting' ? '#52c41a' : '#1890ff'"
                    />
                    <div class="field-hint">
                      <template v-if="restorePhase === 'uploading'">{{ t('system.restoreUploading', { percent: uploadPercent }) }}</template>
                      <template v-else-if="restorePhase === 'processing'">{{ t('system.restoreProcessing') }}</template>
                      <template v-else-if="restorePhase === 'restarting'">{{ t('system.restoreRestarting') }}</template>
                    </div>
                  </div>
                </a-card>
              </a-col>
            </a-row>
          </a-card>
        </section>

        <!-- Maintenance -->
        <section v-show="activeSection === 'maintenance'" class="section-panel">
          <a-card :title="t('system.sectionMaintenance')" :bordered="false">
            <a-alert
              v-if="dbStats.over_threshold"
              type="error"
              show-icon
              :message="t('system.dbOverThresholdTitle')"
              :description="t('system.dbOverThresholdDesc')"
              style="margin-bottom: 16px"
            />
            <p class="section-desc">{{ t('system.dbMaintenanceDesc') }}</p>
            <a-spin :spinning="dbStatsLoading">
              <a-row :gutter="16" class="stats-row">
                <a-col :xs="24" :sm="8">
                  <a-statistic
                    :title="t('system.networkMonitorRows')"
                    :value="dbStats.network_monitor_results_count ?? 0"
                    :value-style="dbStats.over_threshold ? { color: '#cf1322' } : undefined"
                  />
                </a-col>
                <a-col :xs="24" :sm="8">
                  <a-statistic :title="t('system.alertThreshold')" :value="dbStats.alert_threshold ?? 500000" />
                </a-col>
                <a-col :xs="24" :sm="8">
                  <a-statistic :title="t('system.retentionHoursLabel')" :value="dbStats.retention_hours ?? 24" />
                </a-col>
              </a-row>
              <a-space>
                <a-button :loading="dbStatsLoading" @click="fetchDbStats">{{ t('common.refresh') }}</a-button>
                <a-button type="primary" danger :loading="pruneLoading" @click="confirmPruneMonitorData">
                  {{ t('system.pruneMonitorData') }}
                </a-button>
              </a-space>
            </a-spin>
            <a-divider />
            <h4 class="subsection-title">{{ t('system.orphanAgentsTitle') }}</h4>
            <p class="section-desc">{{ t('system.orphanAgentsDesc') }}</p>
            <a-spin :spinning="orphanLoading">
              <a-table
                v-if="orphanAgents.length"
                :columns="orphanColumns"
                :data-source="orphanAgents"
                row-key="host_id"
                size="small"
                :pagination="{ pageSize: 10 }"
                style="margin-bottom: 12px"
              >
                <template #bodyCell="{ column, record }">
                  <template v-if="column.key === 'client_ips'">
                    {{ (record.client_ips || []).join(', ') }}
                  </template>
                  <template v-else-if="column.key === 'hostnames'">
                    {{ (record.hostnames || []).join(', ') }}
                  </template>
                  <template v-else-if="column.key === 'macs'">
                    {{ (record.macs || []).join(', ') }}
                  </template>
                  <template v-else-if="column.key === 'last_seen_at'">
                    {{ formatOrphanTime(record.last_seen_at) }}
                  </template>
                  <template v-else-if="column.key === 'actions'">
                    <a-space>
                      <a-button type="link" size="small" @click="openOrphanCleanupModal(record)">
                        {{ t('system.orphanCleanupScript') }}
                      </a-button>
                      <a-button type="link" size="small" @click="dismissOrphan(record)">
                        {{ t('system.orphanDismiss') }}
                      </a-button>
                    </a-space>
                  </template>
                </template>
              </a-table>
              <a-empty v-else :description="t('system.orphanNoAgents')" />
              <a-button :loading="orphanLoading" @click="fetchOrphanAgents">{{ t('common.refresh') }}</a-button>
            </a-spin>
            <a-divider />
            <p class="section-desc">
              {{ t('system.templatesMovedHint') }}
              <a-button type="link" size="small" @click="router.push({ name: 'MonitorTemplates' })">
                {{ t('network.templates') }}
              </a-button>
            </p>
          </a-card>
        </section>

        <!-- Firewall -->
        <section v-show="activeSection === 'firewall'" class="section-panel">
          <a-card :title="t('system.sectionFirewall')" :bordered="false">
            <p class="section-desc">{{ t('system.firewallDesc') }}</p>
            <a-alert
              v-if="kvmCompat.libvirt_active"
              type="info"
              show-icon
              :message="t('system.firewallKvmCompatTitle')"
              style="margin-bottom: 16px"
            >
              <template #description>
                <p class="firewall-alert-line">{{ t('system.firewallKvmCompatDesc') }}</p>
                <ul v-if="kvmCompatRecommendations.length" class="kvm-rec-list">
                  <li v-for="(line, idx) in kvmCompatRecommendations" :key="idx">{{ line }}</li>
                </ul>
                <a-button
                  size="small"
                  type="primary"
                  :loading="firewallActionLoading"
                  style="margin-top: 8px"
                  @click="applyKvmCompat"
                >
                  {{ t('system.firewallKvmCompatApply') }}
                </a-button>
              </template>
            </a-alert>
            <a-alert
              v-if="firewallStatus.platform !== 'windows'"
              type="warning"
              show-icon
              :message="t('system.firewallLockoutRecoveryTitle')"
              :description="t('system.firewallLockoutRecoveryDesc')"
              style="margin-bottom: 16px"
            />
            <a-alert
              v-if="firewallStatus.platform === 'windows'"
              type="warning"
              show-icon
              :message="t('system.firewallWindowsGlobalTitle')"
              :description="t('system.firewallWindowsGlobalDesc')"
              style="margin-bottom: 16px"
            />
            <a-alert
              v-if="firewallStatus.warning"
              type="warning"
              show-icon
              :message="firewallStatus.warning"
              style="margin-bottom: 16px"
            />
            <a-alert
              v-if="firewallStatus.migrated && firewallStatus.previous_backend"
              type="info"
              show-icon
              :message="t('system.firewallMigratedTitle')"
              :description="t('system.firewallMigratedDesc', { backend: firewallStatus.previous_backend })"
              style="margin-bottom: 16px"
            />
            <a-alert
              v-if="!firewallStatus.available"
              type="warning"
              show-icon
              :message="t('system.firewallUnavailableTitle')"
              style="margin-bottom: 16px"
            >
              <template #description>
                <p v-if="firewallStatus.message" class="firewall-alert-line">{{ firewallStatus.message }}</p>
                <p v-else class="firewall-alert-line">{{ t('system.firewallUnavailableDesc') }}</p>
                <p v-if="firewallPrivilegeHintText" class="firewall-alert-line firewall-alert-hint">
                  {{ firewallPrivilegeHintText }}
                </p>
                <p v-if="firewallStatus.platform || firewallStatus.backend" class="firewall-alert-meta">
                  {{ t('system.firewallDiagMeta', {
                    platform: firewallStatus.platform || '-',
                    backend: firewallStatus.backend || '-',
                    privileged: firewallStatus.privileged ? t('system.firewallPrivilegedYes') : t('system.firewallPrivilegedNo'),
                  }) }}
                </p>
              </template>
            </a-alert>
            <a-spin :spinning="firewallLoading">
              <a-row :gutter="16" class="stats-row">
                <a-col :xs="24" :sm="8">
                  <a-statistic :title="t('system.firewallBackend')" :value="firewallStatus.backend || '-'" />
                </a-col>
                <a-col :xs="24" :sm="8">
                  <a-statistic
                    :title="t('system.firewallState')"
                    :value="firewallStatus.available ? (firewallStatus.enabled ? t('system.firewallEnabled') : t('system.firewallDisabled')) : t('system.firewallUnavailable')"
                    :value-style="firewallStateStyle"
                  />
                </a-col>
              </a-row>
              <a-card size="small" :title="t('system.firewallDiagnosticsTitle')" style="margin-bottom: 16px">
                <a-descriptions size="small" :column="{ xs: 1, sm: 2, md: 3 }">
                  <a-descriptions-item :label="t('system.firewallDiagPlatform')">{{ platformLabel }}</a-descriptions-item>
                  <a-descriptions-item :label="t('system.firewallBackend')">{{ backendLabel }}</a-descriptions-item>
                  <a-descriptions-item :label="t('system.firewallDiagPrivileged')">
                    {{ firewallStatus.privileged ? t('system.firewallPrivilegedYes') : t('system.firewallPrivilegedNo') }}
                  </a-descriptions-item>
                  <a-descriptions-item :label="t('system.firewallDiagPersisted')">
                    {{ firewallStatus.persisted ? t('common.enabled') : t('common.disabled') }}
                  </a-descriptions-item>
                  <a-descriptions-item :label="t('system.firewallDiagBootLoaded')">
                    {{ firewallStatus.boot_loaded ? t('common.enabled') : t('common.disabled') }}
                  </a-descriptions-item>
                  <a-descriptions-item :label="t('system.firewallPfKernelState')">
                    IPv4 {{ portForwardSettings.ipv4_ip_forward ? t('common.enabled') : t('common.disabled') }} /
                    IPv6 {{ portForwardSettings.ipv6_ip_forward ? t('common.enabled') : t('common.disabled') }}
                  </a-descriptions-item>
                </a-descriptions>
                <div v-if="firewallStatus.persistence_message" class="field-hint">
                  {{ firewallStatus.persistence_message }}
                </div>
              </a-card>
              <a-space wrap style="margin-bottom: 16px">
                <a-button :loading="firewallLoading" @click="fetchFirewall">{{ t('common.refresh') }}</a-button>
                <a-button
                  :disabled="!firewallStatus.available"
                  :loading="firewallInitializeLoading"
                  @click="initializeFirewall"
                >
                  {{ t('system.firewallInitialize') }}
                </a-button>
                <a-button
                  type="primary"
                  :disabled="!firewallStatus.available || firewallStatus.enabled"
                  :loading="firewallActionLoading"
                  @click="handleEnableFirewall"
                >
                  {{ t('system.firewallEnable') }}
                </a-button>
                <a-button
                  danger
                  :disabled="!firewallStatus.available || !firewallStatus.enabled"
                  :loading="firewallActionLoading"
                  @click="handleDisableFirewall"
                >
                  {{ t('system.firewallDisable') }}
                </a-button>
              </a-space>
              <a-tabs v-model:activeKey="firewallTab">
                <a-tab-pane key="filter" :tab="t('system.firewallTabFilter')">
                  <a-space wrap style="margin-bottom: 12px">
                    <a-button
                      type="dashed"
                      :disabled="!firewallStatus.available"
                      @click="openAddFirewallRule"
                    >
                      {{ t('system.firewallAddRule') }}
                    </a-button>
                  </a-space>
                  <a-table
                    :columns="firewallColumns"
                    :data-source="firewallRules"
                    :loading="firewallLoading"
                    :pagination="{ pageSize: 10, showSizeChanger: true }"
                    row-key="number"
                    size="small"
                    :scroll="{ x: 'max-content' }"
                  >
                    <template #bodyCell="{ column, record }">
                      <template v-if="column.key === 'action'">
                        <a-tag :color="record.action === 'allow' ? 'green' : 'red'">{{ firewallActionLabel(record.action) }}</a-tag>
                      </template>
                      <template v-else-if="column.key === 'direction'">
                        {{ firewallDirectionLabel(record.direction) }}
                      </template>
                      <template v-else-if="column.key === 'source'">
                        <a-tooltip :title="firewallDisplayText(record.source, 'any')">
                          <span class="firewall-cell-ellipsis">{{ firewallDisplayText(record.source, 'any') }}</span>
                        </a-tooltip>
                      </template>
                      <template v-else-if="column.key === 'comment'">
                        <a-tooltip :title="firewallDisplayText(record.comment)">
                          <span class="firewall-cell-ellipsis">{{ firewallDisplayText(record.comment) }}</span>
                        </a-tooltip>
                      </template>
                      <template v-else-if="column.key === 'port'">
                        <a-tooltip :title="firewallDisplayText(record.port, '*')">
                          <span class="firewall-cell-ellipsis">{{ firewallDisplayText(record.port, '*') }}</span>
                        </a-tooltip>
                      </template>
                      <template v-else-if="column.key === 'ops'">
                        <a-space>
                          <a-button
                            type="link"
                            size="small"
                            :disabled="!firewallStatus.available || (firewallCapabilities.lists_system_rules && !record.managed)"
                            @click="openEditFirewallRule(record)"
                          >
                            {{ t('common.edit') }}
                          </a-button>
                          <a-button
                            type="link"
                            danger
                            size="small"
                            :disabled="!firewallStatus.available || (firewallCapabilities.lists_system_rules && !record.managed)"
                            @click="confirmDeleteFirewallRule(record)"
                          >
                            {{ t('common.delete') }}
                          </a-button>
                        </a-space>
                      </template>
                    </template>
                  </a-table>
                </a-tab-pane>
                <a-tab-pane key="forward" :tab="t('system.firewallTabForward')">
                  <p class="section-desc">{{ t('system.firewallForwardDesc') }}</p>
                  <a-space wrap style="margin-bottom: 12px">
                    <a-button
                      type="primary"
                      :disabled="!firewallStatus.available"
                      @click="openAddPortForward"
                    >
                      {{ t('system.firewallAddPortForward') }}
                    </a-button>
                    <a-divider type="vertical" />
                    <span class="pf-setting-inline">
                      <a-switch
                        size="small"
                        v-model:checked="portForwardSettings.ipv4_enabled"
                        :disabled="!firewallStatus.available || pfSettingsSaving"
                        :loading="pfSettingsSaving"
                        @change="(checked) => savePortForwardSettings('ipv4', checked)"
                      />
                      <span style="margin-left: 6px; font-size: 13px">IPv4</span>
                    </span>
                    <span class="pf-setting-inline">
                      <a-switch
                        size="small"
                        v-model:checked="portForwardSettings.ipv6_enabled"
                        :disabled="!firewallStatus.available || pfSettingsSaving"
                        :loading="pfSettingsSaving"
                        @change="(checked) => savePortForwardSettings('ipv6', checked)"
                      />
                      <span style="margin-left: 6px; font-size: 13px">IPv6</span>
                    </span>
                  </a-space>
                  <a-table
                    :columns="portForwardColumns"
                    :data-source="portForwardRules"
                    :loading="firewallLoading"
                    :pagination="{ pageSize: 10, showSizeChanger: true }"
                    row-key="number"
                    size="small"
                    :scroll="{ x: 'max-content' }"
                  >
                    <template #bodyCell="{ column, record }">
                      <template v-if="column.key === 'listen'">
                        <a-tooltip :title="formatListenEndpoint(record)">
                          <span class="firewall-cell-ellipsis">{{ formatListenEndpoint(record) }}</span>
                        </a-tooltip>
                      </template>
                      <template v-else-if="column.key === 'target'">
                        <a-tooltip :title="formatTargetEndpoint(record)">
                          <span class="firewall-cell-ellipsis">{{ formatTargetEndpoint(record) }}</span>
                        </a-tooltip>
                      </template>
                      <template v-else-if="column.key === 'source'">
                        <a-tooltip :title="firewallDisplayText(record.source, 'any')">
                          <span class="firewall-cell-ellipsis">{{ firewallDisplayText(record.source, 'any') }}</span>
                        </a-tooltip>
                      </template>
                      <template v-else-if="column.key === 'comment'">
                        <a-tooltip :title="firewallDisplayText(record.comment)">
                          <span class="firewall-cell-ellipsis">{{ firewallDisplayText(record.comment) }}</span>
                        </a-tooltip>
                      </template>
                      <template v-else-if="column.key === 'forward'">
                        <a-tooltip :title="formatPortForward(record)">
                          <span class="firewall-cell-ellipsis">{{ formatPortForward(record) }}</span>
                        </a-tooltip>
                      </template>
                      <template v-else-if="column.key === 'ops'">
                        <a-space>
                          <a-button
                            type="link"
                            size="small"
                            :disabled="!firewallStatus.available"
                            @click="openEditPortForward(record)"
                          >
                            {{ t('common.edit') }}
                          </a-button>
                          <a-button
                            type="link"
                            danger
                            size="small"
                            :disabled="!firewallStatus.available"
                            @click="confirmDeletePortForward(record)"
                          >
                            {{ t('common.delete') }}
                          </a-button>
                        </a-space>
                      </template>
                    </template>
                  </a-table>
                </a-tab-pane>
              </a-tabs>
            </a-spin>
          </a-card>
        </section>
      </a-layout-content>
    </a-layout>

    <a-modal
      v-model:open="enableFirewallModalVisible"
      :title="t('system.firewallEnablePortsTitle')"
      :confirm-loading="firewallActionLoading"
      width="720px"
      @ok="confirmEnableFirewall"
      @cancel="enableFirewallModalVisible = false"
    >
      <p class="section-desc">{{ t('system.firewallEnablePortsDesc') }}</p>
      <a-space style="margin-bottom: 12px">
        <a-button size="small" @click="selectAllEnablePorts">{{ t('system.firewallEnablePortsSelectAll') }}</a-button>
        <a-button size="small" @click="clearEnablePortSelection">{{ t('system.firewallEnablePortsClear') }}</a-button>
      </a-space>
      <a-checkbox-group v-model:value="enableSelectedPortKeys" style="width: 100%">
        <a-table
          :columns="enablePortColumns"
          :data-source="enablePortCandidates"
          :pagination="false"
          row-key="key"
          size="small"
          :scroll="{ y: 320 }"
        >
          <template #bodyCell="{ column, record }">
            <template v-if="column.key === 'select'">
              <a-checkbox
                :value="record.key"
                :disabled="record.required"
              />
            </template>
            <template v-else-if="column.key === 'type'">
              <a-tag v-if="record.required" color="red">{{ t('system.firewallEnablePortsRequired') }}</a-tag>
              <span>{{ enablePortTypeLabel(record) }}</span>
            </template>
          </template>
        </a-table>
      </a-checkbox-group>
    </a-modal>

    <a-modal
      v-model:open="firewallRuleModalVisible"
      :title="editingFirewallRuleNumber ? t('system.firewallEditRule') : t('system.firewallAddRule')"
      :confirm-loading="firewallActionLoading"
      @ok="submitFirewallRule"
      @cancel="firewallRuleModalVisible = false"
    >
      <a-form :model="firewallRuleForm" layout="vertical">
        <a-form-item :label="t('system.firewallRuleAction')" required>
          <a-select v-model:value="firewallRuleForm.action">
            <a-select-option value="allow">{{ t('system.firewallActionAllow') }}</a-select-option>
            <a-select-option value="deny">{{ t('system.firewallActionDeny') }}</a-select-option>
            <a-select-option value="reject" :disabled="!firewallCapabilities.can_reject">{{ t('system.firewallActionReject') }}</a-select-option>
          </a-select>
          <div v-if="!firewallCapabilities.can_reject" class="field-hint">{{ t('system.firewallRejectUnsupported') }}</div>
        </a-form-item>
        <a-form-item :label="t('system.firewallRuleDirection')" required>
          <a-radio-group v-model:value="firewallRuleForm.direction">
            <a-radio-button value="in">{{ t('system.firewallRuleDirectionIn') }}</a-radio-button>
            <a-radio-button value="out">{{ t('system.firewallRuleDirectionOut') }}</a-radio-button>
          </a-radio-group>
        </a-form-item>
        <a-form-item :label="t('system.firewallRulePort')" :extra="t('system.firewallRulePortHelp')">
          <a-input v-model:value="firewallRuleForm.port" placeholder="22,80,443" />
        </a-form-item>
        <a-form-item :label="t('system.firewallRuleProtocol')">
          <a-select v-model:value="firewallRuleForm.protocol" allow-clear>
            <a-select-option value="tcp">TCP</a-select-option>
            <a-select-option value="udp">UDP</a-select-option>
            <a-select-option value="tcp+udp">{{ t('system.firewallProtocolBoth') }}</a-select-option>
          </a-select>
        </a-form-item>
        <a-form-item :label="t('system.firewallRuleSource')" :extra="t('system.firewallRuleSourceHelp')">
          <a-input v-model:value="firewallRuleForm.source" placeholder="0.0.0.0/0" />
        </a-form-item>
        <a-form-item :label="t('system.firewallRuleComment')">
          <a-input v-model:value="firewallRuleForm.comment" />
        </a-form-item>
      </a-form>
    </a-modal>

    <a-modal
      v-model:open="portForwardModalVisible"
      :title="editingPortForwardNumber ? t('system.firewallEditPortForward') : t('system.firewallAddPortForward')"
      :confirm-loading="firewallActionLoading"
      @ok="submitPortForward"
      @cancel="portForwardModalVisible = false"
    >
      <a-form :model="portForwardForm" layout="vertical">
        <a-form-item :label="t('system.firewallPfIPVersion')" required>
          <a-radio-group v-model:value="portForwardForm.ip_version" @change="onPortForwardVersionChange">
            <a-radio-button value="ipv4">IPv4</a-radio-button>
            <a-radio-button value="ipv6">IPv6</a-radio-button>
          </a-radio-group>
        </a-form-item>
        <a-form-item :label="t('system.firewallPfProtocol')" required>
          <a-select v-model:value="portForwardForm.protocol">
            <a-select-option value="tcp">TCP</a-select-option>
            <a-select-option value="udp" :disabled="!firewallCapabilities.can_port_forward_udp">UDP</a-select-option>
          </a-select>
          <div v-if="!firewallCapabilities.can_port_forward_udp" class="field-hint">{{ t('system.firewallUdpForwardUnsupported') }}</div>
        </a-form-item>
        <a-row :gutter="16">
          <a-col :span="12">
            <a-form-item :label="t('system.firewallPfListenAddr')" :extra="portForwardListenAddrHelp">
              <a-input
                v-model:value="portForwardForm.listen_address"
                :placeholder="portForwardForm.ip_version === 'ipv6' ? '::' : '0.0.0.0'"
              />
            </a-form-item>
          </a-col>
          <a-col :span="12">
            <a-form-item :label="t('system.firewallPfListenPort')" required>
              <a-input v-model:value="portForwardForm.listen_port" placeholder="8080" />
            </a-form-item>
          </a-col>
        </a-row>
        <a-row :gutter="16">
          <a-col :span="12">
            <a-form-item :label="t('system.firewallPfTargetIP')" required>
              <a-input
                v-model:value="portForwardForm.target_ip"
                :placeholder="portForwardForm.ip_version === 'ipv6' ? '2001:db8::1' : '192.168.1.10'"
              />
            </a-form-item>
          </a-col>
          <a-col :span="12">
            <a-form-item :label="t('system.firewallPfTargetPort')" required>
              <a-input v-model:value="portForwardForm.target_port" placeholder="80" />
            </a-form-item>
          </a-col>
        </a-row>
        <a-form-item :label="t('system.firewallRuleSource')" :extra="t('system.firewallPfSourceHelp')">
          <a-input v-model:value="portForwardForm.source" placeholder="10.0.0.0/8" />
        </a-form-item>
        <a-form-item :label="t('system.firewallRuleComment')">
          <a-input v-model:value="portForwardForm.comment" />
        </a-form-item>
      </a-form>
    </a-modal>

    <a-modal
      v-model:open="backupPasswordModalVisible"
      :title="t('system.backupPasswordTitle')"
      @ok="executeBackup"
      @cancel="backupPasswordModalVisible = false"
    >
      <p>{{ t('system.backupPasswordDesc') }}</p>
      <a-input-password v-model:value="backupPassword" :placeholder="t('system.passwordPlaceholder')" />
    </a-modal>

    <a-modal
      v-model:open="restorePasswordModalVisible"
      :title="t('system.restorePasswordTitle')"
      @ok="executeRestore"
      @cancel="closeRestoreModal"
    >
      <p>{{ t('system.restorePasswordDesc') }}</p>
      <a-input-password v-model:value="restorePassword" :placeholder="t('system.passwordPlaceholder')" />
    </a-modal>

    <a-modal
      v-model:open="orphanCleanupVisible"
      :title="orphanCleanupTitle"
      width="720px"
      :footer="null"
    >
      <a-alert
        type="warning"
        show-icon
        :message="t('system.orphanCleanupHint')"
        style="margin-bottom: 16px"
      />
      <div style="position: relative">
        <pre class="orphan-script-pre">{{ orphanCleanupScript }}</pre>
        <a-button
          type="primary"
          size="small"
          class="orphan-copy-btn"
          :disabled="!orphanCleanupScript"
          @click="copyOrphanScript"
        >
          {{ t('system.orphanCopyScript') }}
        </a-button>
      </div>
    </a-modal>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { message, Modal } from 'ant-design-vue'
import { DownloadOutlined, UploadOutlined } from '@ant-design/icons-vue'
import { useThemeStore } from '../stores/theme'
import api from '../api'
import { getOrphanAgents, dismissOrphanAgent, fetchOrphanCleanupScript } from '../api/monitor'
import dayjs from 'dayjs'

defineOptions({ name: 'SystemManagement' })

const VALID_SECTIONS = ['general', 'session', 'notification', 'data', 'maintenance']

const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const themeStore = useThemeStore()

const isMobile = ref(false)
const checkMobile = () => {
  isMobile.value = window.innerWidth <= 768
}

const activeSection = ref(
  VALID_SECTIONS.includes(route.query.section) ? route.query.section : 'general',
)
const sectionKeys = ref([activeSection.value])

const sectionOptions = computed(() =>
  VALID_SECTIONS.map((key) => ({
    value: key,
    label: t(`system.section${key.charAt(0).toUpperCase()}${key.slice(1)}`),
  })),
)

const sectionMenuItems = computed(() =>
  VALID_SECTIONS.map((key) => ({
    key,
    label: t(`system.section${key.charAt(0).toUpperCase()}${key.slice(1)}`),
  })),
)

const syncRouteSection = (section) => {
  if (route.query.section !== section) {
    router.replace({ name: 'SystemManagement', query: { section } })
  }
}

const onMenuClick = ({ key }) => {
  activeSection.value = key
  sectionKeys.value = [key]
  syncRouteSection(key)
  if (key === 'maintenance') {
    fetchDbStats()
    fetchOrphanAgents()
  }
}

const onSectionChange = (val) => {
  sectionKeys.value = [val]
  syncRouteSection(val)
  if (val === 'maintenance') {
    fetchDbStats()
    fetchOrphanAgents()
  }
}

watch(
  () => route.query.section,
  (section) => {
    if (section && VALID_SECTIONS.includes(section) && section !== activeSection.value) {
      activeSection.value = section
      sectionKeys.value = [section]
      if (section === 'maintenance') {
        fetchDbStats()
        fetchOrphanAgents()
      }
    }
  },
)

const backupLoading = ref(false)
const restoreLoading = ref(false)
const settingsLoading = ref(false)
const uploadPercent = ref(0)
const restorePhase = ref('')

const backupPasswordModalVisible = ref(false)
const backupPassword = ref('')
const restorePasswordModalVisible = ref(false)
const restorePassword = ref('')
const restoreFile = ref(null)

const dbStatsLoading = ref(false)
const pruneLoading = ref(false)
const dbStats = reactive({
  network_monitor_results_count: 0,
  alert_threshold: 500000,
  retention_hours: 24,
  over_threshold: false,
})

const orphanLoading = ref(false)
const orphanAgents = ref([])
const orphanCleanupVisible = ref(false)
const orphanCleanupScript = ref('')
const orphanCleanupHostId = ref(null)

const orphanColumns = computed(() => [
  { title: t('system.orphanHostId'), dataIndex: 'host_id', key: 'host_id', width: 90 },
  { title: t('system.orphanClientIPs'), key: 'client_ips', width: 130 },
  { title: t('system.orphanHostnames'), key: 'hostnames', width: 130 },
  { title: t('system.orphanMacs'), key: 'macs' },
  { title: t('system.orphanHitCount'), dataIndex: 'hit_count', key: 'hit_count', width: 100 },
  { title: t('system.orphanLastSeen'), key: 'last_seen_at', width: 170 },
  { title: t('common.actions'), key: 'actions', width: 200 },
])

const orphanCleanupTitle = computed(() =>
  orphanCleanupHostId.value
    ? t('system.orphanCleanupModalTitle', { id: orphanCleanupHostId.value })
    : t('system.orphanCleanupScript'),
)

const formatOrphanTime = (value) => {
  if (!value) return '-'
  return dayjs(value).format('YYYY-MM-DD HH:mm:ss')
}

const fetchOrphanAgents = async () => {
  orphanLoading.value = true
  try {
    orphanAgents.value = await getOrphanAgents()
  } catch {
    message.error(t('system.orphanFetchFailed'))
  } finally {
    orphanLoading.value = false
  }
}

const openOrphanCleanupModal = async (record) => {
  orphanCleanupHostId.value = record.host_id
  orphanCleanupScript.value = ''
  orphanCleanupVisible.value = true
  try {
    orphanCleanupScript.value = await fetchOrphanCleanupScript(record.host_id)
  } catch {
    message.error(t('system.orphanFetchFailed'))
    orphanCleanupVisible.value = false
  }
}

const copyOrphanScript = async () => {
  try {
    await navigator.clipboard.writeText(orphanCleanupScript.value)
    message.success(t('monitor.commandCopied'))
  } catch {
    message.error(t('common.copyFailed'))
  }
}

const dismissOrphan = async (record) => {
  try {
    await dismissOrphanAgent(record.host_id)
    message.success(t('system.orphanDismissed'))
    await fetchOrphanAgents()
  } catch {
    message.error(t('common.error'))
  }
}

const firewallLoading = ref(false)
const firewallActionLoading = ref(false)
const firewallInitializeLoading = ref(false)
const firewallTab = ref('filter')
const firewallRuleModalVisible = ref(false)
const editingFirewallRuleNumber = ref(null)
const enableFirewallModalVisible = ref(false)
const enablePortCandidates = ref([])
const enableSelectedPortKeys = ref([])
const portForwardModalVisible = ref(false)
const editingPortForwardNumber = ref(null)
const firewallStatus = reactive({
  available: false,
  enabled: false,
  backend: '',
  message: '',
  previous_backend: '',
  migrated: false,
  privileged: false,
  privilege_hint: '',
  platform: '',
  persisted: false,
  boot_loaded: false,
  persistence_message: '',
  warning: '',
  capabilities: {},
})
const kvmCompat = reactive({
  libvirt_active: false,
  bridges: [],
  ipv4_ip_forward: true,
  firewalld_active: false,
  ufw_active: false,
  termiscope_libvirt_rules: false,
  termiscope_forward_chain: false,
  recommendations: [],
})
const kvmRecKeyToText = {
  enable_ipv4_forward: 'system.firewallKvmRecEnableForward',
  start_firewalld_or_ufw: 'system.firewallKvmRecFirewalld',
  apply_termiscope_libvirt_rules: 'system.firewallKvmRecApplyRules',
  apply_termiscope_forward_chain: 'system.firewallKvmRecForwardChain',
  restart_libvirt_default_net: 'system.firewallKvmRecRestartNet',
}
const kvmCompatRecommendations = computed(() =>
  (kvmCompat.recommendations || [])
    .filter((k) => k !== 'restart_libvirt_default_net' || !kvmCompat.termiscope_libvirt_rules)
    .map((k) => t(kvmRecKeyToText[k] || k)),
)
const firewallRules = ref([])
const pfSettingsSaving = ref(false)
const portForwardSettings = reactive({
  ipv4_enabled: false,
  ipv6_enabled: false,
  ipv4_ip_forward: false,
  ipv6_ip_forward: false,
})
const portForwardRules = ref([])
const firewallRuleForm = reactive({
  action: 'allow',
  port: '',
  protocol: 'tcp',
  direction: 'in',
  source: '0.0.0.0/0', // any source; backend treats /0 as any
  comment: '',
})

const enablePortKey = (item) => `${item.protocol}/${item.port}`

const enablePortColumns = computed(() => [
  { title: '', key: 'select', width: 48 },
  { title: t('system.firewallEnablePortsColPort'), dataIndex: 'port', key: 'port', width: 90 },
  { title: t('system.firewallEnablePortsColProto'), dataIndex: 'protocol', key: 'protocol', width: 80 },
  { title: t('system.firewallEnablePortsColRemote'), dataIndex: 'remote_ip', key: 'remote_ip', ellipsis: true },
  { title: t('system.firewallEnablePortsColType'), key: 'type', width: 140 },
])

const enablePortTypeLabel = (record) => {
  if (record.label === 'current_session') return t('system.firewallEnablePortsSession')
  if (record.label === 'baseline') return t('system.firewallEnablePortsBaseline')
  return t('system.firewallEnablePortsExternal')
}

const selectAllEnablePorts = () => {
  enableSelectedPortKeys.value = enablePortCandidates.value.map((p) => p.key)
}

const clearEnablePortSelection = () => {
  enableSelectedPortKeys.value = enablePortCandidates.value.filter((p) => p.required).map((p) => p.key)
}

const portForwardForm = reactive({
  ip_version: 'ipv4',
  protocol: 'tcp',
  listen_address: '0.0.0.0',
  listen_port: '',
  target_ip: '',
  target_port: '',
  source: '',
  comment: '',
})

const firewallCapabilities = computed(() => ({
  can_reject: true,
  can_port_forward_udp: true,
  can_source_port_forward: true,
  global_disable: false,
  lists_system_rules: false,
  supports_kvm_compat: false,
  supports_boot_persistence: false,
  ...(firewallStatus.capabilities || {}),
}))

const firewallStateStyle = computed(() => {
  if (!firewallStatus.available) return { color: '#ff4d4f' }
  return firewallStatus.enabled ? { color: '#52c41a' } : { color: '#faad14' }
})

const platformLabel = computed(() => {
  if (firewallStatus.platform === 'linux') return t('system.platformLinux')
  if (firewallStatus.platform === 'windows') return t('system.platformWindows')
  return firewallStatus.platform || '-'
})

const backendLabel = computed(() => {
  if (firewallStatus.backend === 'nftables') return t('system.backendNftables')
  if (firewallStatus.backend === 'netsh') return t('system.backendNetsh')
  return firewallStatus.backend || '-'
})

const portForwardListenAddrHelp = computed(() =>
  portForwardForm.ip_version === 'ipv6'
    ? t('system.firewallPfListenAddrHelpIPv6')
    : t('system.firewallPfListenAddrHelp'),
)

const firewallActionLabel = (action) => {
  if (action === 'allow') return t('system.firewallActionAllow')
  if (action === 'deny') return t('system.firewallActionDeny')
  if (action === 'reject') return t('system.firewallActionReject')
  return action || '-'
}

const firewallDirectionLabel = (direction) => {
  if (direction === 'in') return t('system.firewallRuleDirectionIn')
  if (direction === 'out') return t('system.firewallRuleDirectionOut')
  return direction || '-'
}

const formatPortForward = (record) => {
  const listenAddr = record.listen_address || (record.ip_version === 'ipv6' ? '::' : '0.0.0.0')
  return `[${record.ip_version?.toUpperCase() || '-'}] ${listenAddr}:${record.listen_port} -> ${record.target_ip}:${record.target_port}`
}

const formatListenEndpoint = (record) => {
  const listenAddr = record.listen_address || (record.ip_version === 'ipv6' ? '::' : '0.0.0.0')
  return `${listenAddr}:${record.listen_port}`
}

const formatTargetEndpoint = (record) => `${record.target_ip}:${record.target_port}`

const firewallDisplayText = (value, fallback = '-') => {
  if (value === undefined || value === null || value === '') return fallback
  return String(value)
}

const formatFirewallRule = (record) => [
  firewallActionLabel(record.action),
  firewallDirectionLabel(record.direction),
  record.protocol || '-',
  record.port || '*',
  record.source || 'any',
].join(' / ')

const firewallPrivilegeHintText = computed(() => {
  if (firewallStatus.privilege_hint) {
    return firewallStatus.privilege_hint
  }
  if (!firewallStatus.privileged && firewallStatus.platform === 'linux') {
    return t('system.firewallPrivilegeHintLinux')
  }
  if (!firewallStatus.privileged && firewallStatus.platform === 'windows') {
    return t('system.firewallPrivilegeHintWindows')
  }
  if (!firewallStatus.available && firewallStatus.platform && firewallStatus.platform !== 'linux' && firewallStatus.platform !== 'windows') {
    return t('system.firewallPrivilegeHintUnsupported')
  }
  return ''
})

const firewallColumns = computed(() => [
  { title: '#', dataIndex: 'number', key: 'number', width: 56, fixed: 'left' },
  { title: t('system.firewallColAction'), key: 'action', dataIndex: 'action', width: 88 },
  { title: t('system.firewallColPort'), dataIndex: 'port', key: 'port', width: 96 },
  { title: t('system.firewallColProtocol'), dataIndex: 'protocol', key: 'protocol', width: 88 },
  { title: t('system.firewallColSource'), dataIndex: 'source', key: 'source', minWidth: 140, ellipsis: true },
  { title: t('system.firewallColDirection'), dataIndex: 'direction', key: 'direction', width: 88 },
  { title: t('system.firewallColComment'), dataIndex: 'comment', key: 'comment', minWidth: 160, ellipsis: true },
  { title: t('common.actions'), key: 'ops', width: 132, fixed: 'right' },
])

const portForwardColumns = computed(() => [
  { title: '#', dataIndex: 'number', key: 'number', width: 56, fixed: 'left' },
  { title: t('system.firewallPfColListen'), key: 'listen', minWidth: 180, ellipsis: true },
  { title: t('system.firewallPfColTarget'), key: 'target', minWidth: 180, ellipsis: true },
  { title: t('system.firewallColProtocol'), dataIndex: 'protocol', key: 'protocol', width: 72 },
  { title: t('system.firewallColSource'), dataIndex: 'source', key: 'source', minWidth: 140, ellipsis: true },
  { title: t('system.firewallColComment'), dataIndex: 'comment', key: 'comment', minWidth: 160, ellipsis: true },
  { title: t('common.actions'), key: 'ops', width: 132, fixed: 'right' },
])

const settingsForm = reactive({
  timezone: 'Local',
  terminal_cursor_style: 'bar',
  ssh_timeout: '30s',
  idle_timeout: '30m',
  max_connections_per_user: 10,
  login_rate_limit: 20,
  access_expiration: '60m',
  refresh_expiration: '168h',
  smtp_server: '',
  smtp_port: '',
  smtp_user: '',
  smtp_password: '',
  smtp_from: '',
  smtp_to: '',
  smtp_tls_skip_verify: false,
  telegram_bot_token: '',
  telegram_chat_id: '',
  notification_template: '',
  system_notify_channels: 'email,telegram',
})

const initialTimezone = ref('Local')

const systemNotifyChannelList = computed({
  get() {
    const raw = settingsForm.system_notify_channels || ''
    return raw.split(',').map((s) => s.trim()).filter(Boolean)
  },
  set(values) {
    settingsForm.system_notify_channels = values.join(',')
  },
})

const emailChannelEnabled = computed(() => systemNotifyChannelList.value.includes('email'))
const telegramChannelEnabled = computed(() => systemNotifyChannelList.value.includes('telegram'))

const notifyCollapseKeys = ref(['email', 'telegram'])

watch(emailChannelEnabled, (on) => {
  if (on && !notifyCollapseKeys.value.includes('email')) {
    notifyCollapseKeys.value = [...notifyCollapseKeys.value, 'email']
  }
})
watch(telegramChannelEnabled, (on) => {
  if (on && !notifyCollapseKeys.value.includes('telegram')) {
    notifyCollapseKeys.value = [...notifyCollapseKeys.value, 'telegram']
  }
})

const sendingTestEmail = ref(false)
const sendingTestTelegram = ref(false)

const DefaultNotificationTemplate = `{{emoji}}{{emoji}}{{emoji}}
Event: {{event}}
Clients: {{client}}
Message: {{message}}
Time: {{time}}`

const resetNotificationTemplate = () => {
  settingsForm.notification_template = DefaultNotificationTemplate
}

const normalizeBooleanSetting = (value) => {
  if (typeof value === 'boolean') return value
  if (typeof value === 'string') return value.trim().toLowerCase() === 'true'
  return Boolean(value)
}

const fetchSettings = async () => {
  try {
    const response = await api.get('/system/settings')
    Object.assign(settingsForm, response)
    settingsForm.smtp_tls_skip_verify = normalizeBooleanSetting(settingsForm.smtp_tls_skip_verify)
    initialTimezone.value = settingsForm.timezone || 'Local'
    if (!settingsForm.notification_template) {
      settingsForm.notification_template = DefaultNotificationTemplate
    }
  } catch (err) {
    message.error(t('system.fetchSettingsFailed'))
  }
}

const fetchDbStats = async () => {
  dbStatsLoading.value = true
  try {
    const data = await api.get('/system/db-stats')
    Object.assign(dbStats, data)
  } catch (err) {
    message.error(err.response?.data?.error || t('system.fetchDbStatsFailed'))
  } finally {
    dbStatsLoading.value = false
  }
}

const applyKvmCompat = async () => {
  Modal.confirm({
    title: t('system.firewallKvmCompatConfirmTitle'),
    content: kvmCompatRecommendations.value.join('\n') || t('system.firewallKvmCompatDesc'),
    okText: t('common.confirm'),
    cancelText: t('common.cancel'),
    onOk: async () => {
      firewallActionLoading.value = true
      try {
        const data = await api.post('/system/firewall/kvm-compat/apply')
        Object.assign(kvmCompat, data)
        message.success(t('system.firewallKvmCompatApplied'))
        await fetchFirewall()
      } catch (err) {
        message.error(err.response?.data?.error || t('system.firewallKvmCompatFailed'))
        throw err
      } finally {
        firewallActionLoading.value = false
      }
    },
  })
}

const fetchFirewall = async () => {
  firewallLoading.value = true
  try {
    const status = await api.get('/system/firewall/status')
    Object.assign(firewallStatus, status)
    try {
      const kvm = await api.get('/system/firewall/kvm-compat')
      Object.assign(kvmCompat, kvm)
    } catch {
      kvmCompat.libvirt_active = false
      kvmCompat.recommendations = []
    }
    const [rules, forwards, pfSettings] = await Promise.all([
      api.get('/system/firewall/rules'),
      api.get('/system/firewall/port-forwards'),
      api.get('/system/firewall/port-forward/settings'),
    ])
    firewallRules.value = rules || []
    portForwardRules.value = forwards || []
    Object.assign(portForwardSettings, pfSettings)
  } catch (err) {
    message.error(err.response?.data?.error || t('system.fetchFirewallFailed'))
  } finally {
    firewallLoading.value = false
  }
}

const initializeFirewall = async () => {
  firewallInitializeLoading.value = true
  try {
    await api.post('/system/firewall/initialize')
    message.success(t('system.firewallInitialized'))
    await fetchFirewall()
  } catch (err) {
    message.error(err.response?.data?.error || t('system.firewallInitializeFailed'))
  } finally {
    firewallInitializeLoading.value = false
  }
}

const openAddFirewallRule = () => {
  editingFirewallRuleNumber.value = null
  firewallRuleForm.action = 'allow'
  firewallRuleForm.port = ''
  firewallRuleForm.protocol = 'tcp'
  firewallRuleForm.direction = 'in'
  firewallRuleForm.source = '0.0.0.0/0'
  firewallRuleForm.comment = ''
  firewallRuleModalVisible.value = true
}

const openEditFirewallRule = (record) => {
  editingFirewallRuleNumber.value = record.number
  firewallRuleForm.action = record.action || 'allow'
  firewallRuleForm.port = record.port || ''
  firewallRuleForm.protocol = record.protocol || 'tcp'
  firewallRuleForm.direction = record.direction || 'in'
  firewallRuleForm.source = record.source || '0.0.0.0/0'
  firewallRuleForm.comment = record.comment || ''
  firewallRuleModalVisible.value = true
}

const openAddPortForward = () => {
  editingPortForwardNumber.value = null
  portForwardForm.ip_version = portForwardSettings.ipv4_enabled || !portForwardSettings.ipv6_enabled ? 'ipv4' : 'ipv6'
  portForwardForm.protocol = 'tcp'
  portForwardForm.listen_address = portForwardForm.ip_version === 'ipv6' ? '::' : '0.0.0.0'
  portForwardForm.listen_port = ''
  portForwardForm.target_ip = ''
  portForwardForm.target_port = ''
  portForwardForm.source = ''
  portForwardForm.comment = ''
  portForwardModalVisible.value = true
}

const openEditPortForward = (record) => {
  editingPortForwardNumber.value = record.number
  portForwardForm.ip_version = record.ip_version || 'ipv4'
  portForwardForm.protocol = record.protocol || 'tcp'
  portForwardForm.listen_address = record.listen_address || (record.ip_version === 'ipv6' ? '::' : '0.0.0.0')
  portForwardForm.listen_port = record.listen_port || ''
  portForwardForm.target_ip = record.target_ip || ''
  portForwardForm.target_port = record.target_port || ''
  portForwardForm.source = record.source || ''
  portForwardForm.comment = record.comment || ''
  portForwardModalVisible.value = true
}

const onPortForwardVersionChange = () => {
  portForwardForm.listen_address = portForwardForm.ip_version === 'ipv6' ? '::' : '0.0.0.0'
}

const persistPortForwardSettings = async () => {
  pfSettingsSaving.value = true
  try {
    const data = await api.put('/system/firewall/port-forward/settings', {
      ipv4_enabled: portForwardSettings.ipv4_enabled,
      ipv6_enabled: portForwardSettings.ipv6_enabled,
    })
    Object.assign(portForwardSettings, data)
    message.success(t('system.firewallPfSettingsSaved'))
  } catch (err) {
    message.error(err.response?.data?.error || t('system.firewallPfSettingsFailed'))
    await fetchFirewall()
  } finally {
    pfSettingsSaving.value = false
  }
}

const savePortForwardSettings = async (family, checked) => {
  const hasRules = portForwardRules.value.some((rule) => rule.ip_version === family)
  if (!checked && hasRules) {
    Modal.confirm({
      title: t('system.firewallPfDisableConfirmTitle'),
      content: t('system.firewallPfDisableConfirmContent', { family: family.toUpperCase() }),
      okText: t('common.confirm'),
      cancelText: t('common.cancel'),
      okType: 'danger',
      onOk: persistPortForwardSettings,
      onCancel: () => {
        portForwardSettings[`${family}_enabled`] = true
      },
    })
    return
  }
  await persistPortForwardSettings()
}

const isValidPort = (value) => {
  const text = String(value || '').trim()
  if (!/^\d{1,5}(:\d{1,5})?$/.test(text)) return false
  return text.split(':').every((part) => {
    const n = Number(part)
    return Number.isInteger(n) && n >= 1 && n <= 65535
  })
}

const isValidIPv4 = (value) => /^(\d{1,3}\.){3}\d{1,3}$/.test(value)
  && value.split('.').every((part) => Number(part) >= 0 && Number(part) <= 255)

const isLikelyIPv6 = (value) => String(value || '').includes(':')

const validateFirewallRuleForm = () => {
  if (!firewallRuleForm.port && !firewallRuleForm.protocol) {
    message.error(t('system.firewallValidationPortOrProtocol'))
    return false
  }
  if (firewallRuleForm.comment.length > 128) {
    message.error(t('system.firewallValidationCommentLength'))
    return false
  }
  return true
}

const validatePortForwardForm = () => {
  if (!isValidPort(portForwardForm.listen_port) || !isValidPort(portForwardForm.target_port)) {
    message.error(t('system.firewallValidationPort'))
    return false
  }
  if (portForwardForm.comment.length > 128) {
    message.error(t('system.firewallValidationCommentLength'))
    return false
  }
  if (portForwardForm.ip_version === 'ipv4') {
    if (!isValidIPv4(portForwardForm.target_ip)) {
      message.error(t('system.firewallValidationIPv4'))
      return false
    }
    if (portForwardForm.listen_address && portForwardForm.listen_address !== '0.0.0.0' && !isValidIPv4(portForwardForm.listen_address)) {
      message.error(t('system.firewallValidationIPv4'))
      return false
    }
  } else if (!isLikelyIPv6(portForwardForm.target_ip)) {
    message.error(t('system.firewallValidationIPv6'))
    return false
  }
  if (portForwardForm.protocol === 'udp' && !firewallCapabilities.value.can_port_forward_udp) {
    message.error(t('system.firewallUdpForwardUnsupported'))
    return false
  }
  return true
}

const submitPortForward = async () => {
  if (!validatePortForwardForm()) return Promise.reject(new Error('validation failed'))
  firewallActionLoading.value = true
  const payload = {
    ip_version: portForwardForm.ip_version,
    protocol: portForwardForm.protocol,
    listen_address: portForwardForm.listen_address,
    listen_port: portForwardForm.listen_port,
    target_ip: portForwardForm.target_ip,
    target_port: portForwardForm.target_port,
    source: portForwardForm.source,
    comment: portForwardForm.comment,
  }
  try {
    if (editingPortForwardNumber.value) {
      await api.put(`/system/firewall/port-forwards/${editingPortForwardNumber.value}`, payload)
      message.success(t('system.firewallPortForwardUpdated'))
    } else {
      await api.post('/system/firewall/port-forwards', payload)
      message.success(t('system.firewallPortForwardAdded'))
    }
    portForwardModalVisible.value = false
    editingPortForwardNumber.value = null
    await fetchFirewall()
  } catch (err) {
    message.error(err.response?.data?.error || (editingPortForwardNumber.value ? t('system.firewallPortForwardUpdateFailed') : t('system.firewallPortForwardAddFailed')))
    throw err
  } finally {
    firewallActionLoading.value = false
  }
}

const confirmDeletePortForward = (record) => {
  Modal.confirm({
    title: t('system.firewallPfDeleteConfirmTitle'),
    content: t('system.firewallPfDeleteConfirmContent', {
      number: record.number,
      summary: formatPortForward(record),
    }),
    okText: t('common.confirm'),
    cancelText: t('common.cancel'),
    okType: 'danger',
    onOk: async () => {
      firewallActionLoading.value = true
      try {
        await api.delete(`/system/firewall/port-forwards/${record.number}`)
        message.success(t('system.firewallPortForwardDeleted'))
        await fetchFirewall()
      } catch (err) {
        message.error(err.response?.data?.error || t('system.firewallPortForwardDeleteFailed'))
      } finally {
        firewallActionLoading.value = false
      }
    },
  })
}

const submitFirewallRule = async () => {
  if (!validateFirewallRuleForm()) return Promise.reject(new Error('validation failed'))
  firewallActionLoading.value = true
  const payload = {
    action: firewallRuleForm.action,
    port: firewallRuleForm.port,
    protocol: firewallRuleForm.protocol || '',
    direction: firewallRuleForm.direction,
    source: firewallRuleForm.source,
    comment: firewallRuleForm.comment,
  }
  try {
    if (editingFirewallRuleNumber.value) {
      await api.put(`/system/firewall/rules/${editingFirewallRuleNumber.value}`, payload)
      message.success(t('system.firewallRuleUpdated'))
    } else {
      await api.post('/system/firewall/rules', payload)
      message.success(t('system.firewallRuleAdded'))
    }
    firewallRuleModalVisible.value = false
    editingFirewallRuleNumber.value = null
    await fetchFirewall()
  } catch (err) {
    message.error(err.response?.data?.error || (editingFirewallRuleNumber.value ? t('system.firewallRuleUpdateFailed') : t('system.firewallRuleAddFailed')))
    throw err
  } finally {
    firewallActionLoading.value = false
  }
}

const confirmDeleteFirewallRule = (record) => {
  Modal.confirm({
    title: t('system.firewallDeleteConfirmTitle'),
    content: t('system.firewallDeleteConfirmContent', {
      number: record.number,
      summary: formatFirewallRule(record),
    }),
    okText: t('common.confirm'),
    cancelText: t('common.cancel'),
    okType: 'danger',
    onOk: async () => {
      firewallActionLoading.value = true
      try {
        await api.delete(`/system/firewall/rules/${record.number}`)
        message.success(t('system.firewallRuleDeleted'))
        await fetchFirewall()
      } catch (err) {
        message.error(err.response?.data?.error || t('system.firewallRuleDeleteFailed'))
      } finally {
        firewallActionLoading.value = false
      }
    },
  })
}

const handleEnableFirewall = async () => {
  firewallActionLoading.value = true
  try {
    const ports = await api.get('/system/firewall/external-ports')
    enablePortCandidates.value = (ports || []).map((p) => ({
      ...p,
      key: enablePortKey(p),
    }))
    enableSelectedPortKeys.value = enablePortCandidates.value.map((p) => p.key)
    enableFirewallModalVisible.value = true
  } catch (err) {
    message.error(err.response?.data?.error || t('system.firewallEnableFailed'))
  } finally {
    firewallActionLoading.value = false
  }
}

const confirmEnableFirewall = async () => {
  Modal.confirm({
    title: t('system.firewallEnableConfirmTitle'),
    content: firewallStatus.platform === 'windows'
      ? t('system.firewallEnableConfirmContentWindows')
      : t('system.firewallEnableConfirmContent'),
    okText: t('common.confirm'),
    cancelText: t('common.cancel'),
    okType: 'danger',
    onOk: async () => {
      firewallActionLoading.value = true
      try {
        const allow = enablePortCandidates.value
          .filter((p) => enableSelectedPortKeys.value.includes(p.key))
          .map((p) => ({ port: p.port, protocol: p.protocol }))
        await api.post('/system/firewall/enable', { allow })
        message.success(t('system.firewallEnableSuccess'))
        enableFirewallModalVisible.value = false
        await fetchFirewall()
      } catch (err) {
        message.error(err.response?.data?.error || t('system.firewallEnableFailed'))
        throw err
      } finally {
        firewallActionLoading.value = false
      }
    },
  })
}

const handleDisableFirewall = () => {
  Modal.confirm({
    title: t('system.firewallDisableConfirmTitle'),
    content: firewallCapabilities.value.global_disable
      ? t('system.firewallDisableConfirmContentWindows')
      : t('system.firewallDisableConfirmContent'),
    okText: t('common.confirm'),
    cancelText: t('common.cancel'),
    okType: 'danger',
    onOk: async () => {
      firewallActionLoading.value = true
      try {
        await api.post('/system/firewall/disable')
        message.success(t('system.firewallDisableSuccess'))
        await fetchFirewall()
      } catch (err) {
        message.error(err.response?.data?.error || t('system.firewallDisableFailed'))
      } finally {
        firewallActionLoading.value = false
      }
    },
  })
}

const confirmPruneMonitorData = () => {
  Modal.confirm({
    title: t('system.pruneConfirmTitle'),
    content: t('system.pruneConfirmContent'),
    okText: t('common.confirm'),
    cancelText: t('common.cancel'),
    okType: 'danger',
    onOk: async () => {
      pruneLoading.value = true
      try {
        const res = await api.post('/system/db-maintenance/prune')
        message.success(
          t('system.pruneSuccess', {
            deleted: res.deleted ?? 0,
            remaining: res.remaining ?? 0,
          }),
        )
        await fetchDbStats()
      } catch (err) {
        message.error(err.response?.data?.error || t('system.pruneFailed'))
      } finally {
        pruneLoading.value = false
      }
    },
  })
}

const handleSaveSettings = async () => {
  settingsLoading.value = true
  const timezoneChanged = settingsForm.timezone !== initialTimezone.value
  try {
    await api.put('/system/settings', settingsForm)
    if (settingsForm.timezone) {
      localStorage.setItem('system_timezone', settingsForm.timezone)
    }
    localStorage.setItem('system_terminal_cursor_style', settingsForm.terminal_cursor_style || 'bar')
    sessionStorage.setItem('system_terminal_cursor_style', settingsForm.terminal_cursor_style || 'bar')
    window.dispatchEvent(new CustomEvent('system-terminal-cursor-style', { detail: settingsForm.terminal_cursor_style || 'bar' }))
    initialTimezone.value = settingsForm.timezone
    message.success(t('system.saveSettingsSuccess'))
    if (timezoneChanged) {
      message.info(t('system.timezoneReloadHint'), 4)
    }
  } catch (err) {
    message.error(err.response?.data?.error || t('system.saveSettingsFailed'))
  } finally {
    settingsLoading.value = false
  }
}

const handleTestEmail = async () => {
  sendingTestEmail.value = true
  try {
    await api.post('/system/settings/test-email', {
      smtp_server: settingsForm.smtp_server,
      smtp_port: settingsForm.smtp_port,
      smtp_user: settingsForm.smtp_user,
      smtp_password: settingsForm.smtp_password,
      smtp_from: settingsForm.smtp_from,
      smtp_to: settingsForm.smtp_to,
      smtp_tls_skip_verify: settingsForm.smtp_tls_skip_verify,
    })
    message.success(t('system.testEmailSuccess'))
  } catch (err) {
    message.error(t('system.testEmailFailed') + ': ' + (err.response?.data?.error || err.message))
  } finally {
    sendingTestEmail.value = false
  }
}

const handleTestTelegram = async () => {
  sendingTestTelegram.value = true
  try {
    await api.post('/system/settings/test-telegram', {
      telegram_bot_token: settingsForm.telegram_bot_token,
      telegram_chat_id: settingsForm.telegram_chat_id,
    })
    message.success(t('system.testTelegramSuccess'))
  } catch (err) {
    message.error(t('system.testTelegramFailed') + ': ' + (err.response?.data?.error || err.message))
  } finally {
    sendingTestTelegram.value = false
  }
}

const handleBackup = () => {
  backupPassword.value = ''
  backupPasswordModalVisible.value = true
}

const executeBackup = async () => {
  backupPasswordModalVisible.value = false
  backupLoading.value = true
  try {
    const response = await api.post('/system/backup', { password: backupPassword.value })
    if (response?.filename && response?.ticket) {
      const downloadUrl = `${window.location.protocol}//${window.location.host}/api/system/backup/download?file=${response.filename}&token=${response.ticket}`
      window.location.href = downloadUrl
      message.success(t('system.backupSuccess'))
    } else {
      throw new Error('No filename or ticket returned')
    }
  } catch (err) {
    message.error(t('system.backupFailed') + ': ' + (err.message || err.response?.data?.error))
  } finally {
    backupLoading.value = false
  }
}

const beforeRestoreUpload = (file) => {
  const isValid = file.name.endsWith('.db') || file.name.endsWith('.db.enc') || file.name.endsWith('.enc')
  if (!isValid) message.error(t('system.invalidFileType'))
  return isValid
}

const handleRestoreChange = (info) => {
  if (info.file.status === 'uploading') return
  restoreFile.value = info.file.originFileObj
  restorePassword.value = ''
  const isEncrypted = restoreFile.value.name.endsWith('.enc')
  if (!isEncrypted) {
    Modal.warning({
      title: t('system.restoreUnencryptedWarningTitle'),
      content: t('system.restoreUnencryptedWarning'),
    })
  }
  restorePasswordModalVisible.value = true
}

const closeRestoreModal = () => {
  restorePasswordModalVisible.value = false
  restoreFile.value = null
}

const executeRestore = () => {
  restorePasswordModalVisible.value = false
  if (restoreFile.value) {
    Modal.confirm({
      title: t('system.restoreConfirmTitle'),
      content: t('system.restoreConfirmContent'),
      okText: t('common.confirm'),
      cancelText: t('common.cancel'),
      onOk: () => performRestore(restoreFile.value, restorePassword.value),
      onCancel: () => {
        restoreFile.value = null
      },
    })
  }
}

const performRestore = async (file, password) => {
  restoreLoading.value = true
  uploadPercent.value = 0
  restorePhase.value = 'uploading'
  const formData = new FormData()
  formData.append('file', file)
  if (password) formData.append('password', password)
  try {
    await api.post('/system/restore', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
      onUploadProgress: (progressEvent) => {
        if (progressEvent.total) {
          const percent = Math.round((progressEvent.loaded / progressEvent.total) * 100)
          uploadPercent.value = percent
          if (percent >= 100) restorePhase.value = 'processing'
        }
      },
    })
    restorePhase.value = 'restarting'
    uploadPercent.value = 100
    message.success(t('system.restoreSuccess'))
    restoreFile.value = null
    setTimeout(() => window.location.reload(), 2000)
  } catch (err) {
    if (err.response?.status === 403 || err.response?.data?.error === 'incorrect password') {
      message.error(t('system.incorrectPassword'))
      restorePasswordModalVisible.value = true
    } else {
      message.error(err.response?.data?.error || t('system.restoreFailed'))
      restoreFile.value = null
    }
  } finally {
    if (restorePhase.value !== 'restarting') {
      restoreLoading.value = false
      restorePhase.value = ''
      uploadPercent.value = 0
    }
  }
}

onMounted(() => {
  checkMobile()
  window.addEventListener('resize', checkMobile)
  fetchSettings()
  if (activeSection.value === 'maintenance') {
    fetchDbStats()
    fetchOrphanAgents()
  }
  if (activeSection.value === 'firewall') fetchFirewall()
})

onUnmounted(() => {
  window.removeEventListener('resize', checkMobile)
})
</script>

<style scoped>
.system-management {
  padding: 24px;
  max-width: 1100px;
  margin: 0 auto;
}
.system-layout {
  background: transparent;
  margin-top: 8px;
}
.system-sider {
  border-radius: 8px;
  margin-right: 16px;
}
.system-content {
  min-height: 400px;
}
.section-segmented {
  margin-bottom: 16px;
}
.section-panel {
  width: 100%;
}
.section-desc,
.card-desc {
  color: #8c8c8c;
  margin-bottom: 16px;
}
.field-hint {
  font-size: 12px;
  color: #888;
  margin-top: 4px;
}
.form-footer {
  margin-top: 8px;
  padding-top: 16px;
  border-top: 1px solid v-bind('themeStore.isDark ? "#303030" : "#f0f0f0"');
}
.notify-collapse {
  background: v-bind('themeStore.isDark ? "#141414" : "#fafafa"');
  border-radius: 8px;
  padding: 8px;
}
.template-actions {
  margin-top: 8px;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}
.danger-card {
  border: 1px solid #ff4d4f;
}
.danger-card :deep(.ant-card-head) {
  border-bottom-color: rgba(255, 77, 79, 0.3);
}
.restore-progress {
  margin-top: 16px;
  max-width: 400px;
}
.stats-row {
  margin-bottom: 16px;
}
.subsection-title {
  margin: 8px 0 4px;
  font-weight: 600;
}
.orphan-script-pre {
  background: v-bind('themeStore.isDark ? "#141414" : "#f5f5f5"');
  color: v-bind('themeStore.isDark ? "rgba(255, 255, 255, 0.85)" : "rgba(0, 0, 0, 0.85)"');
  border: 1px solid v-bind('themeStore.isDark ? "#303030" : "#e8e8e8"');
  padding: 16px 100px 16px 16px;
  border-radius: 4px;
  font-size: 12px;
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
  max-height: 420px;
  overflow: auto;
  white-space: pre-wrap;
  word-break: break-all;
}
.orphan-copy-btn {
  position: absolute;
  top: 12px;
  right: 12px;
}
.firewall-alert-line {
  margin: 0 0 8px;
}
.firewall-alert-line:last-child {
  margin-bottom: 0;
}
.firewall-alert-hint {
  color: v-bind('themeStore.isDark ? "rgba(255, 255, 255, 0.75)" : "rgba(0, 0, 0, 0.65)"');
}
.firewall-alert-meta {
  margin: 8px 0 0;
  font-size: 12px;
  color: v-bind('themeStore.isDark ? "rgba(255, 255, 255, 0.55)" : "rgba(0, 0, 0, 0.45)"');
}
.pf-setting-inline {
  display: inline-flex;
  align-items: center;
  white-space: nowrap;
}
.firewall-cell-ellipsis {
  display: inline-block;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  vertical-align: bottom;
}
@media (max-width: 768px) {
  .system-management {
    padding: 8px;
  }
  .system-sider {
    display: none;
  }
}
</style>
