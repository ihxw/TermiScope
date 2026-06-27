import axios from 'axios'
import { message } from 'ant-design-vue'

// Create axios instance
const api = axios.create({
    baseURL: '/api',
    timeout: 60000,  // 1 minute
    withCredentials: true,
})

const getCookie = (name) => {
    const prefix = `${name}=`
    return document.cookie
        .split(';')
        .map(cookie => cookie.trim())
        .find(cookie => cookie.startsWith(prefix))
        ?.slice(prefix.length) || ''
}

// Request interceptor
api.interceptors.request.use(
    (config) => {
        // Add token to headers
        const token = localStorage.getItem('token')
        if (token) {
            config.headers.Authorization = `Bearer ${token}`
        }
        const csrfToken = getCookie('csrf_token')
        if (csrfToken) {
            config.headers['X-CSRF-Token'] = csrfToken
        }
        return config
    },
    (error) => {
        return Promise.reject(error)
    }
)

// Response interceptor
let isRefreshing = false
let requestsQueue = []

const processQueue = (error, token = null) => {
    requestsQueue.forEach(prom => {
        if (error) {
            prom.reject(error)
        } else {
            prom.resolve(token)
        }
    })
    requestsQueue = []
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

        // 静默错误：如果请求配置了 _silentError，跳过全局错误提示
        if (error.config && error.config._silentError) {
            return Promise.reject(error)
        }

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
                    localStorage.removeItem('token')
                    if (!window.location.pathname.includes('/login')) {
                        message.error('Session expired, please login again')
                        window.location.href = '/login'
                    }
                    return Promise.reject(error)
                }

                // Try to refresh token
                if (isRefreshing) {
                    return new Promise((resolve, reject) => {
                        requestsQueue.push({ resolve, reject })
                    }).then(token => {
                        originalRequest.headers.Authorization = `Bearer ${token}`
                        return api(originalRequest)
                    }).catch(err => {
                        return Promise.reject(err)
                    })
                }

                originalRequest._retry = true
                isRefreshing = true

                try {
                    const response = await axios.post('/api/auth/refresh', {}, { withCredentials: true })

                    if (response.data.success) {
                        const newToken = response.data.data.token
                        localStorage.setItem('token', newToken)
                        api.defaults.headers.common['Authorization'] = `Bearer ${newToken}`
                        originalRequest.headers.Authorization = `Bearer ${newToken}`
                        processQueue(null, newToken)
                        return api(originalRequest)
                    }
                    throw new Error('Refresh failed')
                } catch (refreshError) {
                    processQueue(refreshError, null)
                    localStorage.removeItem('token')
                    message.error('Your session has expired, please login again')
                    window.location.href = '/login'
                    return Promise.reject(refreshError)
                } finally {
                    isRefreshing = false
                }
            } else {
                message.error(errorMessage)
            }
        } else if (error.request) {
            message.error(errorMessage || 'Network error, please check your connection')
        } else {
            message.error(errorMessage)
        }

        return Promise.reject(error)
    }
)

export default api
