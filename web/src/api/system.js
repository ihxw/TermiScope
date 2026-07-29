import api from './index'

export const getSystemInfo = () => {
    return api.get('/system/info')
}

export const checkUpdate = () => {
    return api.post('/system/check-update')
}

export const performUpdate = () => {
    return api.post('/system/upgrade', {})
}

export const sendTestEmail = (data) => {
    return api.post('/system/settings/test-email', data)
}

export const sendTestTelegram = (data) => {
    return api.post('/system/settings/test-telegram', data)
}

export const getUpdateStatus = () => {
    return api.get(`/system/update-status?_t=${Date.now()}`)
}
