import { createApp } from 'vue'
import { createPinia } from 'pinia'
import Antd from 'ant-design-vue'
import router from './router'
import i18n from './locales'
import App from './App.vue'
import dayjs from 'dayjs'
import utc from 'dayjs/plugin/utc'
import timezone from 'dayjs/plugin/timezone'

dayjs.extend(utc)
dayjs.extend(timezone)

// Patch dayjs.prototype.format globally to support custom system timezone
const originalFormat = dayjs.prototype.format;
dayjs.prototype.format = function (template) {
    const tz = localStorage.getItem('system_timezone');
    if (tz && tz !== 'Local') {
        return originalFormat.call(this.tz(tz), template);
    }
    return originalFormat.call(this, template);
};

import 'ant-design-vue/dist/reset.css'
import './style.css'
import './assets/fonts.css'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)
app.use(i18n)
app.use(Antd)

app.mount('#app')
