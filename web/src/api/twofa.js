import api from './index'

export const setup2FA = () => {
    return api.post('/auth/2fa/setup')
}

export const verifySetup2FA = (code, secret) => {
    return api.post('/auth/2fa/verify-setup', { code }, {
        headers: {
            'X-2FA-Secret': secret
        }
    })
}

export const disable2FA = (code) => {
    return api.post('/auth/2fa/disable', { code })
}

export const verify2FA = (code) => {
    return api.post('/auth/2fa/verify', { code })
}

export const regenerateBackupCodes = () => {
    return api.post('/auth/2fa/backup-codes')
}
