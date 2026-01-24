import api from './index'

export function getNetworkTasks(hostId) {
    return api.get(`/ssh-hosts/${hostId}/network/tasks`)
}

export function createNetworkTask(data) {
    return api.post('/monitor/network/tasks', data)
}

export function updateNetworkTask(id, data) {
    return api.put(`/monitor/network/tasks/${id}`, data)
}

export function deleteNetworkTask(id) {
    return api.delete(`/monitor/network/tasks/${id}`)
}

export function getTaskStats(taskId, range) {
    return api.get(`/monitor/network/stats/${taskId}`, {
        params: { range }
    })
}

// Templates
export function getNetworkTemplates() {
    return api.get('/monitor/network/templates')
}

export function createNetworkTemplate(data) {
    return api.post('/monitor/network/templates', data)
}

export function updateNetworkTemplate(id, data) {
    return api.put(`/monitor/network/templates/${id}`, data)
}

export function deleteNetworkTemplate(id) {
    return api.delete(`/monitor/network/templates/${id}`)
}

// Get assigned hosts for a template
export const getTemplateAssignments = async (id) => {
    const res = await api.get(`/monitor/network/templates/${id}/assignments`)
    return res
}

export function batchApplyTemplate(data) {
    return api.post('/monitor/network/apply-template', data)
}
