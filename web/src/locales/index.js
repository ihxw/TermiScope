import { createI18n } from 'vue-i18n'

const savedLocale = localStorage.getItem('locale')
const browserLocale = navigator.language || navigator.userLanguage
const defaultLocale = savedLocale || (browserLocale.startsWith('zh') ? 'zh-CN' : 'en-US')

const i18n = createI18n({
    legacy: false,
    locale: defaultLocale,
    fallbackLocale: 'en-US',
    messages: {},
})

const loadedLocales = new Set()

export async function loadLocale(locale) {
    if (loadedLocales.has(locale)) {
        return
    }
    const mod = locale === 'zh-CN'
        ? await import('./zh-CN.js')
        : await import('./en-US.js')
    i18n.global.setLocaleMessage(locale, mod.default)
    loadedLocales.add(locale)
}

export async function setAppLocale(locale) {
    await loadLocale(locale)
    if (!loadedLocales.has(i18n.global.fallbackLocale.value)) {
        await loadLocale(i18n.global.fallbackLocale.value)
    }
    i18n.global.locale.value = locale
    localStorage.setItem('locale', locale)
}

// Bootstrap default + fallback
await loadLocale(defaultLocale)
if (defaultLocale !== 'en-US') {
    await loadLocale('en-US')
}

export default i18n
