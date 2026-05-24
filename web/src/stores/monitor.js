import { defineStore } from 'pinia'

function emptyMetrics(hostId, sh) {
    return {
        host_id: hostId,
        hostname: sh?.host || '',
        os: '',
        uptime: 0,
        cpu: 0,
        cpu_count: 0,
        cpu_model: '',
        cpu_mhz: 0,
        mem_used: 0,
        mem_total: 0,
        disk_used: 0,
        disk_total: 0,
        net_rx: 0,
        net_tx: 0,
        net_monthly_rx: 0,
        net_monthly_tx: 0,
        net_traffic_limit: sh?.net_traffic_limit ?? 0,
        net_traffic_used_adjustment: sh?.net_traffic_used_adjustment ?? 0,
        net_traffic_counter_mode: sh?.net_traffic_counter_mode || 'total',
        net_reset_day: sh?.net_reset_day ?? 1,
        net_last_reset_date: sh?.net_last_reset_date || '',
        notify_offline_enabled: sh?.notify_offline_enabled,
        notify_traffic_enabled: sh?.notify_traffic_enabled,
        notify_offline_threshold: sh?.notify_offline_threshold,
        notify_traffic_threshold: sh?.notify_traffic_threshold,
        notify_channels: sh?.notify_channels,
        expiration_date: sh?.expiration_date,
        billing_period: sh?.billing_period,
        billing_amount: sh?.billing_amount,
        currency: sh?.currency,
        flag: sh?.flag,
        agent_version: sh?.agent_version || '',
        _clientLastUpdated: 0,
    }
}

function mergeSSHConfig(existing, sh) {
    return {
        ...existing,
        hostname: sh.host,
        notify_offline_enabled: sh.notify_offline_enabled,
        notify_traffic_enabled: sh.notify_traffic_enabled,
        notify_offline_threshold: sh.notify_offline_threshold,
        notify_traffic_threshold: sh.notify_traffic_threshold,
        notify_channels: sh.notify_channels,
        expiration_date: sh.expiration_date,
        billing_period: sh.billing_period,
        billing_amount: sh.billing_amount,
        currency: sh.currency,
        flag: sh.flag,
        net_reset_day: sh.net_reset_day,
        net_last_reset_date: sh.net_last_reset_date,
        net_traffic_limit: sh.net_traffic_limit,
        net_traffic_used_adjustment: sh.net_traffic_used_adjustment,
        net_traffic_counter_mode: sh.net_traffic_counter_mode,
    }
}

/** Live monitor metrics keyed by host_id (WebSocket + SSH config). */
export const useMonitorStore = defineStore('monitor', {
    state: () => ({
        hostsById: {},
        streamPaused: false,
        connected: false,
        serverAgentVersion: null,
    }),

    getters: {
        hostsList: (state) => Object.values(state.hostsById),
    },

    actions: {
        setStreamPaused(paused) {
            this.streamPaused = paused
        },

        setConnected(v) {
            this.connected = v
        },

        setServerAgentVersion(version) {
            this.serverAgentVersion = version
        },

        syncConfigFromSSH(sshHosts) {
            if (!Array.isArray(sshHosts)) return
            const enabledIds = new Set()

            for (const sh of sshHosts) {
                if (!sh.monitor_enabled) continue
                enabledIds.add(sh.id)
                const id = sh.id
                const existing = this.hostsById[id]
                if (existing) {
                    this.hostsById[id] = mergeSSHConfig(existing, sh)
                } else {
                    this.hostsById[id] = emptyMetrics(id, sh)
                }
            }

            for (const key of Object.keys(this.hostsById)) {
                const id = Number(key)
                if (!enabledIds.has(id)) {
                    delete this.hostsById[id]
                }
            }
        },

        applyUpdates(updates) {
            if (!updates || this.streamPaused) return
            const now = Date.now()
            const clean = (v) => (v || '').toString().replace(/^v/, '').trim()
            const serverV = clean(this.serverAgentVersion)

            for (const update of updates) {
                update._clientLastUpdated = now
                const id = update.host_id
                const prev = this.hostsById[id] || { host_id: id }
                const merged = { ...prev, ...update }

                if (
                    merged.agent_update_status &&
                    serverV &&
                    clean(merged.agent_version) === serverV
                ) {
                    merged.agent_update_status = null
                }

                this.hostsById[id] = merged
            }
        },

        handleStreamMessage(msg) {
            if (this.streamPaused || !msg?.type) return
            if (msg.type === 'init' || msg.type === 'update') {
                this.applyUpdates(msg.data)
            } else if (msg.type === 'remove') {
                this.removeHost(msg.data)
            } else if (msg.type === 'agent_event') {
                this.setAgentStatus(msg.data.host_id, msg.data.message)
            }
        },

        removeHost(hostId) {
            delete this.hostsById[hostId]
        },

        setAgentStatus(hostId, message) {
            if (this.hostsById[hostId]) {
                this.hostsById[hostId] = {
                    ...this.hostsById[hostId],
                    agent_update_status: message,
                }
            }
        },

        clear() {
            this.hostsById = {}
        },
    },
})
