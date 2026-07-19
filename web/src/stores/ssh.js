import { defineStore } from 'pinia'
import { getHosts, getHost, createHost, updateHost, deleteHost, permanentDeleteHost as apiPermanentDeleteHost, testConnection, reorderHosts as apiReorderHosts } from '../api/ssh'
import { useAuthStore } from './auth'

function unwrapHosts(res) {
    if (Array.isArray(res)) return res
    if (res && Array.isArray(res.data)) return res.data
    return []
}

function hostOrderKey(userId) {
    return 'termScope_host_order_' + userId
}

function hostOrderPendingKey(userId) {
    return 'termScope_host_order_pending_' + userId
}

function normalizeOrderForHosts(order, hosts) {
    const hostIds = hosts.map(h => h.id)
    const hostIdSet = new Set(hostIds)
    const seen = new Set()
    const normalized = []

    for (const id of Array.isArray(order) ? order : []) {
        if (hostIdSet.has(id) && !seen.has(id)) {
            seen.add(id)
            normalized.push(id)
        }
    }

    for (const id of hostIds) {
        if (!seen.has(id)) {
            normalized.push(id)
        }
    }

    return normalized
}

function isPermanentReorderError(error) {
    const status = error?.response?.status
    return status >= 400 && status < 500
}

export const useSSHStore = defineStore('ssh', {
    state: () => ({
        hosts: [],
        hostsFetchedAt: 0,
        hostsFetchTTL: 60_000,
        hostsFetchPromise: null,
        terminals: new Map(),
        currentTerminalId: null,
        loading: false,
    }),

    getters: {
        currentTerminal: (state) => {
            return state.currentTerminalId ? state.terminals.get(state.currentTerminalId) : null
        },
        terminalList: (state) => {
            return Array.from(state.terminals.values())
        },
        hostNameMap: (state) => {
            const map = {}
            for (const h of state.hosts) {
                map[h.id] = h.name
            }
            return map
        },
    },

    actions: {
        async fetchHosts(filters = {}, { force = false } = {}) {
            if (
                !force &&
                this.hosts.length > 0 &&
                Date.now() - this.hostsFetchedAt < this.hostsFetchTTL
            ) {
                return this.hosts
            }
            if (this.hostsFetchPromise) {
                return this.hostsFetchPromise
            }

            this.loading = true
            this.hostsFetchPromise = (async () => {
                try {
                    const res = await getHosts(filters)
                    let fetchedHosts = unwrapHosts(res)

                    const authStore = useAuthStore()
                    const userId = authStore.user?.id
                    if (userId) {
                        const orderKey = hostOrderKey(userId)
                        const pendingKey = hostOrderPendingKey(userId)
                        const localOrderStr = localStorage.getItem(orderKey)
                        if (localOrderStr) {
                            try {
                                const localOrder = normalizeOrderForHosts(JSON.parse(localOrderStr), fetchedHosts)
                                localStorage.setItem(orderKey, JSON.stringify(localOrder))
                                const idToIndex = {}
                                localOrder.forEach((id, index) => {
                                    idToIndex[id] = index
                                })
                                fetchedHosts.sort((a, b) => {
                                    const aIndex = idToIndex[a.id]
                                    const bIndex = idToIndex[b.id]
                                    const aHas = aIndex !== undefined
                                    const bHas = bIndex !== undefined
                                    if (aHas && bHas) {
                                        return aIndex - bIndex
                                    }
                                    if (aHas) return -1
                                    if (bHas) return 1
                                    return (a.sort_order || 0) - (b.sort_order || 0)
                                })
                            } catch (e) {
                                console.error('Failed to parse local host order:', e)
                                localStorage.removeItem(orderKey)
                                localStorage.removeItem(pendingKey)
                            }
                        }

                        if (Object.keys(filters).length === 0 && localStorage.getItem(pendingKey) === 'true') {
                            if (localOrderStr) {
                                try {
                                    const localOrder = normalizeOrderForHosts(JSON.parse(localOrderStr), fetchedHosts)
                                    localStorage.setItem(orderKey, JSON.stringify(localOrder))
                                    apiReorderHosts(localOrder).then(() => {
                                        localStorage.removeItem(pendingKey)
                                    }).catch(syncErr => {
                                        if (isPermanentReorderError(syncErr)) {
                                            localStorage.removeItem(pendingKey)
                                            localStorage.removeItem(orderKey)
                                        }
                                        console.error('Background sync of host order failed:', syncErr)
                                    })
                                } catch (e) {
                                    console.error('Failed to parse local host order for background sync:', e)
                                    localStorage.removeItem(orderKey)
                                    localStorage.removeItem(pendingKey)
                                }
                            }
                        }
                    }

                    this.hosts = fetchedHosts
                    this.hostsFetchedAt = Date.now()
                    return this.hosts
                } catch (error) {
                    console.error('Failed to fetch hosts:', error)
                    throw error
                } finally {
                    this.loading = false
                    this.hostsFetchPromise = null
                }
            })()
            return this.hostsFetchPromise
        },

        invalidateHostsCache() {
            this.hostsFetchedAt = 0
        },

        async fetchHost(id, options = {}) {
            try {
                const host = await getHost(id, options)
                return host
            } catch (error) {
                console.error('Failed to fetch host:', error)
                throw error
            }
        },

        async addHost(hostData) {
            try {
                const host = await createHost(hostData)
                this.hosts.push(host)
                this.invalidateHostsCache()
                return host
            } catch (error) {
                console.error('Failed to create host:', error)
                throw error
            }
        },

        async modifyHost(id, hostData) {
            try {
                const host = await updateHost(id, hostData)
                const index = this.hosts.findIndex(h => h.id === id)
                if (index !== -1) {
                    this.hosts[index] = host
                }
                return host
            } catch (error) {
                console.error('Failed to update host:', error)
                throw error
            }
        },

        async removeHost(id) {
            try {
                await deleteHost(id)
                this.hosts = this.hosts.filter(h => h.id !== id)
            } catch (error) {
                console.error('Failed to delete host:', error)
                throw error
            }
        },

        async permanentDeleteHost(id) {
            try {
                await apiPermanentDeleteHost(id)
                this.hosts = this.hosts.filter(h => h.id !== id)
            } catch (error) {
                console.error('Failed to permanently delete host:', error)
                throw error
            }
        },

        async reorderHosts(ids) {
            const authStore = useAuthStore()
            const userId = authStore.user?.id
            const normalizedIds = normalizeOrderForHosts(ids, this.hosts)
            if (userId) {
                localStorage.setItem(hostOrderKey(userId), JSON.stringify(normalizedIds))
            }
            try {
                await apiReorderHosts(normalizedIds)
                if (userId) {
                    localStorage.removeItem(hostOrderPendingKey(userId))
                }
            } catch (error) {
                if (userId && !isPermanentReorderError(error)) {
                    localStorage.setItem(hostOrderPendingKey(userId), 'true')
                } else if (userId) {
                    localStorage.removeItem(hostOrderKey(userId))
                    localStorage.removeItem(hostOrderPendingKey(userId))
                }
                console.error('Failed to reorder hosts:', error)
                throw error
            }
        },

        async testHostConnection(id) {
            try {
                return await testConnection(id)
            } catch (error) {
                console.error('Failed to test host connection:', error)
                throw error
            }
        },

        addTerminal(terminalData) {
            const id = Date.now().toString()
            this.terminals.set(id, {
                id,
                record: false,
                ...terminalData,
                createdAt: new Date()
            })
            this.currentTerminalId = id
            return id
        },

        removeTerminal(id) {
            this.terminals.delete(id)
            if (this.currentTerminalId === id) {
                const terminalIds = Array.from(this.terminals.keys())
                this.currentTerminalId = terminalIds.length > 0 ? terminalIds[terminalIds.length - 1] : null
            }
        },

        setCurrentTerminal(id) {
            if (this.terminals.has(id)) {
                this.currentTerminalId = id
            }
        },

        updateTerminal(id, data) {
            const terminal = this.terminals.get(id)
            if (terminal) {
                this.terminals.set(id, { ...terminal, ...data })
            }
        },

        clearTerminals() {
            this.terminals.clear()
            this.currentTerminalId = null
        }
    }
})
