import api from './index'

export const getConnectionLogs = async (filters = {}) => {
    return await api.get('/connection-logs', { params: filters })
}

export const getServerLogs = async (params = {}) => {
    return await api.get('/system/logs', { params })
}
