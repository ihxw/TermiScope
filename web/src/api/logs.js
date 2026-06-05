import api from './index'

export const getConnectionLogs = async (filters = {}) => {
    return await api.get('/connection-logs', { params: filters })
}
