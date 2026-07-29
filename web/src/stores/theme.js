import { defineStore } from 'pinia'
import { theme } from 'ant-design-vue'

export const useThemeStore = defineStore('theme', {
    state: () => ({
        isDark: false, // Default to light theme
        terminalTheme: 'auto',
    }),

    getters: {
        themeAlgorithm: (state) => {
            const algorithms = [state.isDark ? theme.darkAlgorithm : theme.defaultAlgorithm]
            algorithms.push(theme.compactAlgorithm)
            return algorithms
        },
        themeToken: (state) => ({
            colorPrimary: '#1890ff',
            colorBgContainer: state.isDark ? '#1f1f1f' : '#ffffff',
            colorBgElevated: state.isDark ? '#1f1f1f' : '#ffffff',
            colorBorder: state.isDark ? '#303030' : '#d9d9d9',
            borderRadius: 2, // Slightly more square for compact feel
            // Override compact algorithm for small buttons to match official standard
            controlHeightSM: 24,
            fontSizeSM: 14,
        })
    },

    actions: {
        toggleTheme() {
            this.isDark = !this.isDark
            localStorage.setItem('theme', this.isDark ? 'dark' : 'light')
        },

        initTheme() {
            const savedTheme = localStorage.getItem('theme')
            if (savedTheme) {
                this.isDark = savedTheme === 'dark'
            }
            const savedTerminalTheme = localStorage.getItem('terminalTheme')
            if (savedTerminalTheme) {
                this.terminalTheme = savedTerminalTheme
            }
        },

        setTerminalTheme(themeName) {
            this.terminalTheme = themeName
            localStorage.setItem('terminalTheme', themeName)
        }
    }
})
