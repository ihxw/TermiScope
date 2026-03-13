import api from './index'

export const listRecordings = async () => {
    return await api.get('/recordings')
}

export const deleteRecording = async (id) => {
    return await api.delete(`/recordings/${id}`)
}

import { getWSTicket } from './auth'

export const getRecordingStreamUrl = async (id) => {
    const res = await getWSTicket()
    return `/api/recordings/${id}/stream?token=${res.ticket}`
}
