import { createI18n } from 'vue-i18n'
import zhCN from './zh-CN'
import enUS from './en-US'

// Get saved locale from localStorage or detect from browser
const savedLocale = localStorage.getItem('locale')
const browserLocale = navigator.language || navigator.userLanguage
const defaultLocale = savedLocale || (browserLocale.startsWith('zh') ? 'zh-CN' : 'en-US')

const i18n = createI18n({
    legacy: false, // Use Composition API mode
    locale: defaultLocale,
    fallbackLocale: 'en-US',
    messages: {
        'zh-CN': zhCN,
        'en-US': enUS
    }
})

export default i18n
