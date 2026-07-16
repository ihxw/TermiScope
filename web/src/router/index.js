import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import { checkInit } from '../api/auth'
import authSession from '../api/authSession'
import NProgress from 'nprogress'
import 'nprogress/nprogress.css'

NProgress.configure({ showSpinner: false })

/** Lazy loaders for dashboard child views — shared for route config and prefetch */
export const dashboardViewLoaders = {
    Terminal: () => import('../views/Terminal.vue'),
    MonitorDashboard: () => import('../views/MonitorDashboard.vue'),
    NetworkDetail: () => import('../views/NetworkDetail.vue'),
    ConnectionHistory: () => import('../views/ConnectionHistory.vue'),
    CommandManagement: () => import('../views/CommandManagement.vue'),
    RecordingManagement: () => import('../views/RecordingManagement.vue'),
    UserManagement: () => import('../views/UserManagement.vue'),
    Profile: () => import('../views/Profile.vue'),
    SystemManagement: () => import('../views/SystemManagement.vue'),
    MonitorTemplates: () => import('../views/monitor/MonitorTemplates.vue'),
    FileTransfer: () => import('../views/FileTransfer.vue'),
    HostManagement: () => import('../views/HostManagement.vue'),
}

/** Preload likely next views only (avoid loading Monaco/SFTP/heavy chunks upfront). */
const prefetchPriority = [
    'Terminal',
    'MonitorDashboard',
    'HostManagement',
    'Profile',
]

export function prefetchDashboardViews(exceptName) {
    for (const name of prefetchPriority) {
        if (name !== exceptName && dashboardViewLoaders[name]) {
            dashboardViewLoaders[name]()
        }
    }
}

const routes = [
    {
        path: '/login',
        name: 'Login',
        component: () => import('../views/Login.vue'),
        meta: { requiresAuth: false }
    },
    {
        path: '/setup',
        name: 'Setup',
        component: () => import('../views/Setup.vue'),
        meta: { requiresAuth: false }
    },
    {
        path: '/forgot-password',
        name: 'ForgotPassword',
        component: () => import('../views/ForgotPassword.vue'),
        meta: { requiresAuth: false }
    },
    {
        path: '/reset-password',
        name: 'ResetPassword',
        component: () => import('../views/ResetPassword.vue'),
        meta: { requiresAuth: false }
    },
    {
        path: '/',
        redirect: '/dashboard/terminal'
    },
    {
        path: '/dashboard',
        name: 'Dashboard',
        component: () => import('../views/Dashboard.vue'),
        redirect: { name: 'Terminal' },
        meta: { requiresAuth: true },
        children: [
            {
                path: 'terminal',
                name: 'Terminal',
                component: dashboardViewLoaders.Terminal,
                meta: { requiresAuth: true }
            },
            {
                path: 'hosts',
                name: 'HostManagement',
                component: dashboardViewLoaders.HostManagement,
                meta: { requiresAuth: true }
            },
            {
                path: 'monitor',
                name: 'MonitorDashboard',
                component: dashboardViewLoaders.MonitorDashboard,
                meta: { requiresAuth: true }
            },
            {
                path: 'monitor/templates',
                name: 'MonitorTemplates',
                component: dashboardViewLoaders.MonitorTemplates,
                meta: { requiresAuth: true, requiresAdmin: true }
            },
            {
                path: 'monitor/:id/network',
                name: 'NetworkDetail',
                component: dashboardViewLoaders.NetworkDetail,
                meta: { requiresAuth: true }
            },
            {
                path: 'history',
                name: 'ConnectionHistory',
                component: dashboardViewLoaders.ConnectionHistory,
                meta: { requiresAuth: true }
            },
            {
                path: 'commands',
                name: 'CommandManagement',
                component: dashboardViewLoaders.CommandManagement,
                meta: { requiresAuth: true }
            },
            {
                path: 'recordings',
                name: 'RecordingManagement',
                component: dashboardViewLoaders.RecordingManagement,
                meta: { requiresAuth: true }
            },
            {
                path: 'users',
                name: 'UserManagement',
                component: dashboardViewLoaders.UserManagement,
                meta: { requiresAuth: true, requiresAdmin: true }
            },
            {
                path: 'profile',
                name: 'Profile',
                component: dashboardViewLoaders.Profile,
                meta: { requiresAuth: true }
            },
            {
                path: 'system',
                name: 'SystemManagement',
                component: dashboardViewLoaders.SystemManagement,
                meta: { requiresAuth: true, requiresAdmin: true }
            },
            {
                path: 'transfer',
                name: 'FileTransfer',
                component: dashboardViewLoaders.FileTransfer,
                meta: { requiresAuth: true }
            }
        ]
    },
    {
        path: '/:pathMatch(.*)*',
        name: 'NotFound',
        component: () => import('../views/NotFound.vue'),
        meta: { requiresAuth: false }
    }
]

const router = createRouter({
    history: createWebHistory(),
    routes
})

// Navigation guard
router.beforeEach(async (to, from, next) => {
    NProgress.start()
    const authStore = useAuthStore()
    const storedToken = authSession.getAccessToken()

    if (authStore.token && !storedToken) {
        authStore.clearAuth()
    }

    // Check if route requires authentication
    if (to.meta.requiresAuth) {
        if (!authStore.isAuthenticated) {
            // Try to restore session from localStorage
            if (storedToken) {
                authStore.token = storedToken
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
        if (to.name === 'Login' || to.name === 'Setup') {
            // If already authenticated, go to dashboard
            if (authStore.isAuthenticated) {
                next({ name: 'MonitorDashboard' })
                return
            }
            // Check if system needs initialization
            try {
                const result = await checkInit()
                if (!result.initialized && to.name !== 'Setup') {
                    next({ name: 'Setup' })
                    return
                }
                if (result.initialized && to.name === 'Setup') {
                    next({ name: 'Login' })
                    return
                }
            } catch (err) {
                console.error('Failed to check init status:', err)
            }
            next()
        } else {
            next()
        }
    }
})

router.afterEach(() => {
    NProgress.done()
})

export default router
