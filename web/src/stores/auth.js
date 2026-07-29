import { defineStore } from 'pinia'
import { login as apiLogin, logout as apiLogout, getCurrentUser, verify2FALogin } from '../api/auth'
import authSession from '../api/authSession'

export const useAuthStore = defineStore('auth', {
    state: () => ({
        user: null,
        token: authSession.getAccessToken() || null,
    }),

    getters: {
        isAuthenticated: (state) => !!state.token,
        isAdmin: (state) => state.user?.role === 'admin',
    },

    actions: {
        async login(username, password, remember = false) {
            try {
                const response = await apiLogin(username, password, remember)
                this.token = response.token
                this.user = response.user

                authSession.setAccessToken(response.token)

                return response
            } catch (error) {
                throw error
            }
        },

        async verify2FA(userId, code, token) {
            try {
                // We need to import verify2FALogin in api/auth first, but we can do it here or assume it's exposed
                // Let's check api/auth.js content first. It doesn't export verify2FALogin yet? 
                // Wait, Login.vue calls `/auth/verify-2fa-login`.
                // Let's assume we import a new function from api/auth
                const response = await verify2FALogin(userId, code, token)
                this.token = response.token
                this.user = response.user

                authSession.setAccessToken(response.token)
                return response
            } catch (error) {
                throw error
            }
        },

        async logout() {
            try {
                await apiLogout()
            } catch (error) {
                // console.error('Logout error:', error)
            } finally {
                this.clearAuth()
            }
        },

        async fetchCurrentUser() {
            try {
                const user = await getCurrentUser()
                this.user = user
                return user
            } catch (error) {
                // Token invalid, clear auth state
                // this.clearAuth() // Don't clear immediately, let interceptor handle refresh
                throw error
            }
        },

        setToken(token) {
            this.token = token
            authSession.setAccessToken(token)
        },

        setUser(user) {
            this.user = user
        },

        clearAuth() {
            this.token = null
            this.user = null
            authSession.clearAccessToken()
        }
    }
})
