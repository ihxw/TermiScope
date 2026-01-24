import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const routes = [
    {
        path: '/login',
        name: 'Login',
        component: () => import('../views/Login.vue'),
        meta: { requiresAuth: false }
    },
    {
        path: '/',
        redirect: '/dashboard/monitor'
    },
    {
        path: '/dashboard',
        name: 'Dashboard',
        component: () => import('../views/Dashboard.vue'),
        meta: { requiresAuth: true },
        children: [
            {
                path: 'terminal',
                name: 'Terminal',
                component: () => import('../views/Terminal.vue'),
                meta: { requiresAuth: true }
            },
            {
                path: 'hosts',
                name: 'HostManagement',
                component: () => import('../views/HostManagement.vue'),
                meta: { requiresAuth: true }
            },
            {
                path: 'monitor',
                name: 'MonitorDashboard',
                component: () => import('../views/MonitorDashboard.vue'),
                meta: { requiresAuth: true }
            },
            {
                path: 'monitor/:id/network',
                name: 'NetworkDetail',
                component: () => import('../views/NetworkDetail.vue'),
                meta: { requiresAuth: true }
            },
            {
                path: 'history',
                name: 'ConnectionHistory',
                component: () => import('../views/ConnectionHistory.vue'),
                meta: { requiresAuth: true }
            },
            {
                path: 'commands',
                name: 'CommandManagement',
                component: () => import('../views/CommandManagement.vue'),
                meta: { requiresAuth: true }
            },
            {
                path: 'recordings',
                name: 'RecordingManagement',
                component: () => import('../views/RecordingManagement.vue'),
                meta: { requiresAuth: true }
            },
            {
                path: 'users',
                name: 'UserManagement',
                component: () => import('../views/UserManagement.vue'),
                meta: { requiresAuth: true, requiresAdmin: true }
            },
            {
                path: 'profile',
                name: 'Profile',
                component: () => import('../views/Profile.vue'),
                meta: { requiresAuth: true }
            },
            {
                path: 'system',
                name: 'SystemManagement',
                component: () => import('../views/SystemManagement.vue'),
                meta: { requiresAuth: true, requiresAdmin: true }
            }
        ]
    }
]

const router = createRouter({
    history: createWebHistory(),
    routes
})

// Navigation guard
router.beforeEach(async (to, from, next) => {
    const authStore = useAuthStore()

    // Check if route requires authentication
    if (to.meta.requiresAuth) {
        if (!authStore.isAuthenticated) {
            // Try to restore session from localStorage
            const token = localStorage.getItem('token')
            if (token) {
                authStore.token = token
                try {
                    await authStore.fetchCurrentUser()

                    // Check admin requirement
                    if (to.meta.requiresAdmin && authStore.user?.role !== 'admin') {
                        next({ name: 'MonitorDashboard' })
                        return
                    }

                    next()
                } catch (error) {
                    // Token invalid, redirect to login
                    authStore.logout()
                    next({ name: 'Login', query: { redirect: to.fullPath } })
                }
            } else {
                next({ name: 'Login', query: { redirect: to.fullPath } })
            }
        } else {
            // Check admin requirement
            if (to.meta.requiresAdmin && authStore.user?.role !== 'admin') {
                next({ name: 'MonitorDashboard' })
                return
            }
            next()
        }
    } else {
        // Public route
        if (to.name === 'Login' && authStore.isAuthenticated) {
            next({ name: 'MonitorDashboard' })
        } else {
            next()
        }
    }
})

export default router
