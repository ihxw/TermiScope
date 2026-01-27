import api from './index'

export const login = async (username, password, remember = false) => {
    return await api.post('/auth/login', { username, password, remember })
}

export const logout = async () => {
    return await api.post('/auth/logout')
}

export const getCurrentUser = async () => {
    return await api.get('/auth/me')
}

export const getWSTicket = async () => {
    return await api.post('/auth/ws-ticket')
}

export const changePassword = async (currentPassword, newPassword) => {
    return await api.post('/auth/change-password', { current_password: currentPassword, new_password: newPassword })
}

export const refreshToken = async (token) => {
    return await api.post('/auth/refresh', { refresh_token: token })
}

export const verify2FALogin = async (userId, code, token) => {
    return await api.post('/auth/verify-2fa-login', { user_id: userId, code, token })
}
