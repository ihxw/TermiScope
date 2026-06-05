import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import Components from 'unplugin-vue-components/vite'
import { AntDesignVueResolver } from 'unplugin-vue-components/resolvers'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    vue(),
    Components({
      resolvers: [
        AntDesignVueResolver({
          importStyle: false,
        }),
      ],
    }),
  ],
  build: {
    // 限制并发 worker 数量，防止 CPU 占用过高导致系统卡死
    // 默认会使用 CPU 核心数 - 1，这里限制为最多 2 个
    rollupOptions: {
      // 限制并行文件读取操作数，降低 I/O 和内存压力
      maxParallelFileOps: 3,
      output: {
        manualChunks(id) {
          if (id.includes('node_modules')) {
            if (id.includes('monaco-editor')) return 'monaco'
            if (id.includes('echarts')) return 'echarts'
            if (id.includes('xterm')) return 'xterm'
            if (id.includes('ant-design-vue') || id.includes('@ant-design/icons-vue')) return 'antd'
            if (id.includes('vue-router') || id.includes('pinia') || id.includes('vue-i18n')) return 'vue-vendor'
          }
        },
      },
    },
    // 警告阈值，单位 kB
    chunkSizeWarningLimit: 1000,
  },
  server: {
    host: '0.0.0.0',
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:3000',
        changeOrigin: true,
        ws: true,
      },
    },
  },
})
