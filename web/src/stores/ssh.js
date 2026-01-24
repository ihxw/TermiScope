import { defineStore } from 'pinia'
import { getHosts, getHost, createHost, updateHost, deleteHost, testConnection, reorderHosts } from '../api/ssh'

export const useSSHStore = defineStore('ssh', {
    state: () => ({
        hosts: [],
        terminals: new Map(), // Map of terminal ID to terminal data
        currentTerminalId: null,
        loading: false,
    }),

    getters: {
        currentTerminal: (state) => {
            return state.currentTerminalId ? state.terminals.get(state.currentTerminalId) : null
        },
        terminalList: (state) => {
            return Array.from(state.terminals.values())
        }
    },

    actions: {
        async fetchHosts(filters = {}) {
            this.loading = true
            try {
                const hosts = await getHosts(filters)
                this.hosts = hosts
                return hosts
            } catch (error) {
                console.error('Failed to fetch hosts:', error)
                throw error
            } finally {
                this.loading = false
            }
        },

        async fetchHost(id) {
            try {
                const host = await getHost(id)
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

        async reorderHosts(ids) {
            try {
                // We need to import reorderHosts first, but let's assume it's imported at top
                // Wait, I missed adding the import in the previous step or this file.
                // Let me check imports first.
                // Actually I can adding it now.
                // But I should fixing the tool call first.
                // The previous tool call failed, so no changes made. 
                // Using the available reorderHosts from api.
                await reorderHosts(ids)
            } catch (error) {
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
                record: false, // Default
                ...terminalData,
                createdAt: new Date()
            })
            this.currentTerminalId = id
            return id
        },

        removeTerminal(id) {
            this.terminals.delete(id)
            if (this.currentTerminalId === id) {
                // Set current to the last terminal or null
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
