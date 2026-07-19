import { defineStore } from 'pinia'
import i18n, { setAppLocale } from '../locales'

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
        async setLocale(locale) {
            await setAppLocale(locale)
            this.locale = locale
        },

        toggleLocale() {
            const newLocale = this.locale === 'zh-CN' ? 'en-US' : 'zh-CN'
            this.setLocale(newLocale)
        }
    }
})
