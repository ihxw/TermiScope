import { defineStore } from 'pinia'

export const useSftpStore = defineStore('sftp', {
    state: () => ({
        clipboard: {
            hostId: null,
            paths: [],
            type: null // 'cut' | 'copy'
        }
    }),
    actions: {
        setClipboard(hostId, paths, type) {
            this.clipboard = {
                hostId,
                paths: Array.isArray(paths) ? paths : [paths],
                type
            }
        },
        clearClipboard() {
            this.clipboard = {
                hostId: null,
                paths: [],
                type: null
            }
        }
    }
})
