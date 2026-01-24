import axios from 'axios'
import { message } from 'ant-design-vue'

// Create axios instance
const api = axios.create({
    baseURL: '/api',
    timeout: 30000,
})

// Request interceptor
api.interceptors.request.use(
    (config) => {
        // Add token to headers
        const token = localStorage.getItem('token')
        if (token) {
            config.headers.Authorization = `Bearer ${token}`
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
        if (response.data.success) {
            return response.data.data
        }
        return response.data
    },
    async (error) => {
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
                    localStorage.removeItem('refresh_token')
                    if (!window.location.pathname.includes('/login')) {
                        message.error('Session expired, please login again')
                        window.location.href = '/login'
                    }
                    return Promise.reject(error)
                }

                // Try to refresh token
                const refreshToken = localStorage.getItem('refresh_token')
                console.log('[Auth] Attempting token refresh, refresh_token exists:', !!refreshToken)

                if (refreshToken) {
                    if (isRefreshing) {
                        // If already refreshing, queue this request
                        console.log('[Auth] Token refresh in progress, queuing request')
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
                        console.log('[Auth] Starting token refresh request')
                        // Call refresh directly using axios to avoid circular dependency or interceptor loops
                        // But we want to use the same baseURL
                        const response = await axios.post('/api/auth/refresh', { refresh_token: refreshToken })

                        if (response.data.success) {
                            const newToken = response.data.data.token
                            localStorage.setItem('token', newToken)
                            console.log('[Auth] Token refresh successful, new token saved')

                            // Also update store if possible, but here we just update localStorage
                            // The store will read from localStorage on reload, or we rely on the fact that we use localStorage in requests
                            // Ideally we'd access the store, but preventing circular deps is safer here.
                            // Since the header is set from localStorage in request interceptor:
                            // const token = localStorage.getItem('token') <- this will pick up new token next time
                            // But for THIS retry, we must set it manually

                            api.defaults.headers.common['Authorization'] = `Bearer ${newToken}`
                            originalRequest.headers.Authorization = `Bearer ${newToken}`

                            processQueue(null, newToken)
                            return api(originalRequest)
                        } else {
                            throw new Error('Refresh failed')
                        }
                    } catch (refreshError) {
                        console.error('[Auth] Token refresh failed:', refreshError.response?.data || refreshError.message)
                        console.error('[Auth] Refresh token may be expired or invalid, logging out')
                        processQueue(refreshError, null)
                        localStorage.removeItem('token')
                        localStorage.removeItem('refresh_token')
                        message.error('Your session has expired, please login again')
                        window.location.href = '/login'
                        return Promise.reject(refreshError)
                    } finally {
                        isRefreshing = false
                    }
                } else {
                    // No refresh token -> Logout
                    console.warn('[Auth] No refresh token found in localStorage, redirecting to login')
                    localStorage.removeItem('token')
                    if (!window.location.pathname.includes('/login')) {
                        message.error('Session expired, please login again')
                        window.location.href = '/login'
                    }
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
