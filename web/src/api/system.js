import api from './index'

export const getSystemInfo = () => {
    return api.get('/system/info')
}
