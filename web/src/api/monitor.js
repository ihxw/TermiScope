import api from './index'

export const getOrphanAgents = async () => {
  const res = await api.get('/monitor/orphan-agents')
  return res?.agents ?? []
}

export const dismissOrphanAgent = async (hostId) => {
  return await api.delete(`/monitor/orphan-agents/${hostId}`)
}

export const fetchOrphanCleanupScript = async (hostId) => {
  const data = await api.get(`/monitor/orphan-agents/${hostId}/cleanup-script`, {
    responseType: 'text',
    transformResponse: [(data) => data],
  })
  return typeof data === 'string' ? data : String(data ?? '')
}
