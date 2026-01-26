import api from './index'

export const getHosts = async (filters = {}) => {
    const params = new URLSearchParams(filters).toString()
    return await api.get(`/ssh-hosts${params ? '?' + params : ''}`)
}

export const getHost = async (id) => {
    return await api.get(`/ssh-hosts/${id}`)
}

export const createHost = async (hostData) => {
    return await api.post('/ssh-hosts', hostData)
}

export const updateHost = async (id, hostData) => {
    return await api.put(`/ssh-hosts/${id}`, hostData)
}

export const deleteHost = async (id) => {
    return await api.delete(`/ssh-hosts/${id}`)
}

export const testConnection = async (id) => {
    return await api.post(`/ssh-hosts/${id}/test`)
}

export const deployMonitor = async (id, insecure = false) => {
    return await api.post(`/ssh-hosts/${id}/monitor/deploy`, { insecure })
}

export const stopMonitor = async (id) => {
    return await api.post(`/ssh-hosts/${id}/monitor/stop`)
}

export const updateHostFingerprint = async (id, fingerprint) => {
    return await api.put(`/ssh-hosts/${id}/fingerprint`, { fingerprint })
}

export const getMonitorLogs = async (id, page = 1, pageSize = 20) => {
    return await api.get(`/ssh-hosts/${id}/monitor/logs?page=${page}&page_size=${pageSize}`)
}

export const reorderHosts = async (ids) => {
    return await api.put('/ssh-hosts/reorder', { device_ids: ids })
}

export const batchDeployMonitor = async (hostIds, insecure = false, onResult) => {
    const token = localStorage.getItem('token')
    const response = await fetch('/api/ssh-hosts/monitor/batch-deploy', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
            host_ids: hostIds,
            insecure: insecure
        })
    })

    if (!response.ok) {
        let errorMsg = 'Request failed'
        try {
            const errorData = await response.json()
            errorMsg = errorData.error || errorMsg
        } catch (e) { }
        throw new Error(errorMsg)
    }

    const reader = response.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ''

    while (true) {
        const { done, value } = await reader.read()
        if (done) break

        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n')
        buffer = lines.pop()

        for (const line of lines) {
            if (line.trim()) {
                try {
                    const result = JSON.parse(line)
                    if (onResult) onResult(result)
                } catch (e) {
                    console.error('JSON parse error:', e)
                }
            }
        }
    }
}

export const batchStopMonitor = async (hostIds, onResult) => {
    const token = localStorage.getItem('token')
    const response = await fetch('/api/ssh-hosts/monitor/batch-stop', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
            host_ids: hostIds
        })
    })

    if (!response.ok) {
        let errorMsg = 'Request failed'
        try {
            const errorData = await response.json()
            errorMsg = errorData.error || errorMsg
        } catch (e) { }
        throw new Error(errorMsg)
    }

    const reader = response.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ''

    while (true) {
        const { done, value } = await reader.read()
        if (done) break

        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n')
        buffer = lines.pop()

        for (const line of lines) {
            if (line.trim()) {
                try {
                    const result = JSON.parse(line)
                    if (onResult) onResult(result)
                } catch (e) {
                    console.error('JSON parse error:', e)
                }
            }
        }
    }
}
