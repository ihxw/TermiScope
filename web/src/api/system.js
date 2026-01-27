import api from './index'

export const getSystemInfo = () => {
    return api.get('/system/info')
}

export const checkUpdate = () => {
    return api.post('/system/check-update')
}

export const performUpdate = (downloadUrl) => {
    return api.post('/system/upgrade', { download_url: downloadUrl })
}
