import axios from 'axios'
import { message } from 'ant-design-vue'
import authSession from './authSession'

// Create axios instance
const api = axios.create({
    baseURL: '/api',
    timeout: 60000,  // 1 minute
    withCredentials: true,
})

// Request interceptor
api.interceptors.request.use(
    (config) => {
        const token = authSession.getAccessToken()
        if (token) {
            config.headers.set('Authorization', `Bearer ${token}`)
        }
        const csrfToken = authSession.getCsrfToken()
        if (csrfToken) {
            config.headers.set('X-CSRF-Token', csrfToken)
        }
        return config
    },
    (error) => {
        return Promise.reject(error)
    }
)

const isLoginPage = () => window.location.pathname === '/login'

const clearStoredAuth = () => {
    authSession.clearAccessToken()
    delete api.defaults.headers.common.Authorization
}

const redirectToLogin = (errorMessage) => {
    clearStoredAuth()
    if (isLoginPage()) {
        return
    }
    if (errorMessage) {
        message.error(errorMessage)
    }
    window.location.href = '/login'
}

api.interceptors.response.use(
    (response) => {
        // Return data directly if success
        if (response.data && response.data.success) {
            return response.data.data
        }
        return response.data
    },
    async (error) => {
        // 忽略主动取消的请求，不弹框报错
        if (axios.isCancel(error) || error.name === 'CanceledError' || error.code === 'ERR_CANCELED' || error.message === 'canceled') {
            return Promise.reject(error)
        }

        const silentError = !!error.config?._silentError

        // Extract error message
        let errorMessage = 'Request failed'
        if (error.response && error.response.data && error.response.data.error) {
            errorMessage = error.response.data.error
        } else if (error.message) {
            errorMessage = error.message
        }

        const originalRequest = error.config

        // Handle errors
        if (error.response) {
            const { status } = error.response

            // 401 Unauthorized
            if (status === 401 && !originalRequest._retry) {
                if (originalRequest.url.includes('/auth/login') || originalRequest.url.includes('/auth/refresh')) {
                    // Login failed or Refresh failed -> Logout
                    console.error('[Auth] Login or refresh failed:', errorMessage)
                    redirectToLogin('Session expired, please login again')
                    return Promise.reject(error)
                }

                originalRequest._retry = true

                try {
                    const newToken = await authSession.refreshAccessToken()
                    api.defaults.headers.common.Authorization = `Bearer ${newToken}`
                    originalRequest.headers.set('Authorization', `Bearer ${newToken}`)
                    return api(originalRequest)
                } catch (refreshError) {
                    redirectToLogin('Your session has expired, please login again')
                    return Promise.reject(refreshError)
                }
            } else if (!silentError) {
                message.error(errorMessage)
            }
        } else if (error.request && !silentError) {
            message.error(errorMessage || 'Network error, please check your connection')
        } else if (!silentError) {
            message.error(errorMessage)
        }

        return Promise.reject(error)
    }
)

export default api
