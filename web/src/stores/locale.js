import { defineStore } from 'pinia'
import i18n from '../locales'

export const useLocaleStore = defineStore('locale', {
    state: () => ({
        locale: i18n.global.locale.value
    }),

    getters: {
        currentLocale: (state) => state.locale,
        isZhCN: (state) => state.locale === 'zh-CN',
        isEnUS: (state) => state.locale === 'en-US'
    },

    actions: {
        setLocale(locale) {
            this.locale = locale
            i18n.global.locale.value = locale
            localStorage.setItem('locale', locale)
        },

        toggleLocale() {
            const newLocale = this.locale === 'zh-CN' ? 'en-US' : 'zh-CN'
            this.setLocale(newLocale)
        }
    }
})
