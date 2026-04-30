<template>
  <div class="terminal-wrapper" :style="{ 
    background: themeStore.isDark ? '#1e1e1e' : '#ffffff', 
    color: themeStore.isDark ? '#fff' : '#000',
    height: '100%', 
    display: 'flex', 
    flexDirection: 'column', 
    overflow: 'hidden'
  }">
    <!-- 终端/分屏区域 -->
    <div class="split-container" :class="{ 'full-screen': !showSftp }">
      <!-- 左侧：终端 -->
      <div class="split-left" :style="{ width: showSftp ? `${splitRatio * 100}%` : '100%' }">
        <div ref="terminalRef" class="terminal-container" :style="{ 
          background: containerBackground,
          flex: 1,
          overflow: 'hidden'
        }"></div>
      </div>
      
      <!-- 分隔条（仅在分屏时显示） -->
      <div 
        v-show="showSftp"
        class="split-divider"
        :class="{ 'split-divider-dark': themeStore.isDark }"
        @mousedown="startDrag"
      >
        <div class="split-divider-line"></div>
      </div>
      
      <!-- 右侧：SFTP浏览器（仅在分屏时显示） -->
      <div v-show="showSftp" class="split-right" :style="{ width: `${(1 - splitRatio) * 100}%` }">
        <SftpBrowser :host-id="hostId" :host-label="hostLabel" :visible="showSftp" />
      </div>
    </div>
    
    <!-- Mobile Virtual Keyboard Toolbar -->
    <div v-if="isMobileDevice" class="mobile-keyboard-toolbar" :style="{
      background: themeStore.isDark ? '#2d2d2d' : '#f0f0f0',
      borderTop: themeStore.isDark ? '1px solid #404040' : '1px solid #d9d9d9'
    }">
      <div class="keyboard-row">
        <!-- Modifier Keys -->
        <button
          class="key-btn modifier"
          :class="{ active: modifiers.ctrl, 'dark-mode': themeStore.isDark }"
          @click="toggleModifier('ctrl')"
        >Ctrl</button>
        <button
          class="key-btn modifier"
          :class="{ active: modifiers.alt, 'dark-mode': themeStore.isDark }"
          @click="toggleModifier('alt')"
        >Alt</button>
        <button
          class="key-btn modifier"
          :class="{ active: modifiers.shift, 'dark-mode': themeStore.isDark }"
          @click="toggleModifier('shift')"
        >Shift</button>
        
        <span class="key-separator"></span>
        
        <!-- Common Keys -->
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendKey('Escape')">Esc</button>
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendKey('Tab')">Tab</button>
        
        <span class="key-separator"></span>
        
        <!-- Arrow Keys -->
        <button class="key-btn arrow" :class="{ 'dark-mode': themeStore.isDark }" @click="sendKey('ArrowUp')">↑</button>
        <button class="key-btn arrow" :class="{ 'dark-mode': themeStore.isDark }" @click="sendKey('ArrowDown')">↓</button>
        <button class="key-btn arrow" :class="{ 'dark-mode': themeStore.isDark }" @click="sendKey('ArrowLeft')">←</button>
        <button class="key-btn arrow" :class="{ 'dark-mode': themeStore.isDark }" @click="sendKey('ArrowRight')">→</button>
        
        <span class="key-separator"></span>
        
        <!-- Control Keys -->
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('c')">^C</button>
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('d')">^D</button>
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('z')">^Z</button>
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('l')">^L</button>
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('a')">^A</button>
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('e')">^E</button>
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('u')">^U</button>
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('r')">^R</button>
        
        <span class="key-separator"></span>
        
        <!-- Special Characters -->
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendChar('|')">|</button>
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendChar('&')">&amp;</button>
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendChar('~')">~</button>
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendChar('/')">/</button>
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendChar('-')">-</button>
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendChar('_')">_</button>
        
        <span class="key-separator"></span>
        
        <!-- Copy/Paste Buttons -->
        <button class="key-btn action" :class="{ 'dark-mode': themeStore.isDark }" @click="copySelection">Copy</button>
        <button class="key-btn action" :class="{ 'dark-mode': themeStore.isDark }" @click="pasteFromClipboard">Paste</button>
      </div>
    </div>
    
    <div v-if="connectionStatus" class="terminal-status" :style="{ 
      background: themeStore.isDark ? '#1f1f1f' : '#f0f0f0', 
      borderTop: themeStore.isDark ? '1px solid #303030' : '1px solid #d9d9d9' 
    }">
      <div style="display: flex; align-items: center">
        <a-space size="small">
          <a-button class="status-btn" :class="{ 'light-mode': !themeStore.isDark }" size="small" type="text" @click="reconnect" v-if="connectionStatus === 'Disconnected'">
            <template #icon><ReloadOutlined /></template>
            {{ t('terminal.reconnect') }}
          </a-button>
          <a-button class="status-btn danger" :class="{ 'light-mode': !themeStore.isDark }" size="small" type="text" danger @click="disconnect" v-if="connectionStatus === 'Connected'">
            <template #icon><DisconnectOutlined /></template>
            {{ t('terminal.disconnect') }}
          </a-button>
        </a-space>
        <a-divider type="vertical" class="status-divider" :style="{ background: themeStore.isDark ? 'rgba(255, 255, 255, 0.2)' : 'rgba(0, 0, 0, 0.1)' }" />
        
        <!-- Theme Settings -->
        <a-dropdown 
          trigger="click" 
          placement="topRight" 
          :overlayClassName="`terminal-theme-dropdown ${themeStore.isDark ? 'dark' : ''}`"
        >
          <template #overlay>
            <a-menu
              :selectedKeys="[currentTerminalTheme]"
              style="max-height: 400px; overflow-y: auto;"
            >
              <a-menu-item 
                v-for="(theme, key) in availableThemes" 
                :key="key"
                @click="handleThemeChange(key)"
              >
                {{ theme.name }}
                <span v-if="currentTerminalTheme === key" style="float: right; color: #1890ff">✓</span>
              </a-menu-item>
            </a-menu>
          </template>
          <a-button class="status-btn" :class="{ 'light-mode': !themeStore.isDark }" size="small" type="text">
            <template #icon><BgColorsOutlined /></template>
            {{ t('terminal.theme') }}
          </a-button>
        </a-dropdown>

        <a-divider type="vertical" class="status-divider" :style="{ background: themeStore.isDark ? 'rgba(255, 255, 255, 0.2)' : 'rgba(0, 0, 0, 0.1)' }" />

        <!-- Font Settings -->
        <a-popover trigger="click" placement="topRight" overlayClassName="terminal-settings-popover">
          <template #content>
            <div style="width: 280px; padding: 4px;">
              <div style="margin-bottom: 12px">
                <div style="margin-bottom: 4px; font-size: 12px; color: #888">{{ t('terminal.fontFamily') }}</div>
                <a-select v-model:value="fontSettings.family" style="width: 100%" size="small" @change="updateFont">
                  <a-select-option value="'Alibaba PuHuiTi', monospace">Alibaba PuHuiTi</a-select-option>
                  <a-select-option value="'Courier New', monospace">Courier New</a-select-option>
                  <a-select-option value="'Consolas', monospace">Consolas</a-select-option>
                  <a-select-option value="'Fira Code', monospace">Fira Code</a-select-option>
                  <a-select-option value="'JetBrains Mono', monospace">JetBrains Mono</a-select-option>
                  <a-select-option value="'Source Code Pro', monospace">Source Code Pro</a-select-option>
                  <a-select-option value="'Menlo', 'Monaco', monospace">Menlo / Monaco</a-select-option>
                </a-select>
              </div>
              <div>
                <div style="margin-bottom: 4px; font-size: 12px; color: #888">{{ t('terminal.fontSize') }} ({{ fontSettings.size }}px)</div>
                <a-row :gutter="8">
                  <a-col :span="16">
                     <a-slider v-model:value="fontSettings.size" :min="10" :max="32" @change="updateFont" />
                  </a-col>
                  <a-col :span="8">
                     <a-input-number v-model:value="fontSettings.size" :min="10" :max="32" size="small" @change="updateFont" style="width: 100%" />
                  </a-col>
                </a-row>
              </div>
            </div>
          </template>
          <a-button class="status-btn" :class="{ 'light-mode': !themeStore.isDark }" size="small" type="text">
            <template #icon><FontSizeOutlined /></template>
            {{ t('terminal.font') }}
          </a-button>
        </a-popover>

        <a-divider type="vertical" class="status-divider" :style="{ background: themeStore.isDark ? 'rgba(255, 255, 255, 0.2)' : 'rgba(0, 0, 0, 0.1)' }" />
        <a-button class="status-btn" :class="{ 'light-mode': !themeStore.isDark, 'sftp-active': showSftp }" size="small" type="text" @click="showSftp = !showSftp" :disabled="connectionStatus !== 'Connected'">
          <template #icon><FolderOpenOutlined /></template>
          {{ t('terminal.sftp') }}
        </a-button>
        <a-divider type="vertical" class="status-divider" :style="{ background: themeStore.isDark ? 'rgba(255, 255, 255, 0.2)' : 'rgba(0, 0, 0, 0.1)' }" />
        <a-divider type="vertical" class="status-divider" :style="{ background: themeStore.isDark ? 'rgba(255, 255, 255, 0.2)' : 'rgba(0, 0, 0, 0.1)' }" />
        <a-dropdown :disabled="connectionStatus !== 'Connected'" placement="topRight">
          <a-button class="status-btn" :class="{ 'light-mode': !themeStore.isDark }" size="small" type="text">
            <template #icon><ThunderboltOutlined /></template>
            {{ t('terminal.commands') }}
          </a-button>
          <template #overlay>
            <a-menu @click="handleQuickCommand">
              <a-menu-item v-for="cmd in commandTemplates" :key="cmd.command">
                {{ cmd.name }}
              </a-menu-item>
              <a-menu-divider v-if="commandTemplates.length > 0" />
              <a-menu-item @click="$router.push({ name: 'CommandManagement' })">
                {{ t('terminal.manageTemplates') }}
              </a-menu-item>
            </a-menu>
          </template>
        </a-dropdown>
      </div>
      <div style="display: flex; align-items: center">
        <a-tag :color="statusColor" size="small" style="font-size: 10px; line-height: 14px; height: 16px; margin-right: 8px">{{ connectionStatus }}</a-tag>
        <span :style="{ color: themeStore.isDark ? '#bbb' : '#666', fontSize: '11px', marginRight: '8px' }">{{ terminalSize }}</span>
        <div v-if="record" :style="{borderLeft: themeStore.isDark ? '1px solid #444' : '1px solid #ccc'}" style="display: flex; align-items: center; gap: 4px; padding-left: 8px; margin-left: 0">
          <span class="recording-dot"></span>
          <span style="color: #ff4d4f; font-size: 11px; font-weight: bold; letter-spacing: 0.5px">RECORDING</span>
        </div>
      </div>
    </div>


  </div>
</template>

<script setup>
import { ref, shallowRef, reactive, onMounted, onUnmounted, onActivated, nextTick, watch, h, computed } from 'vue'
import { Terminal } from 'xterm'
import { FitAddon } from 'xterm-addon-fit'
import { WebLinksAddon } from 'xterm-addon-web-links'
import { message, Modal } from 'ant-design-vue'
import { ReloadOutlined, DisconnectOutlined, FolderOpenOutlined, ThunderboltOutlined, FontSizeOutlined, BgColorsOutlined } from '@ant-design/icons-vue'
import { getWSTicket } from '../api/auth'
import { listCommandTemplates } from '../api/command'
import { updateHostFingerprint } from '../api/ssh'
import SftpBrowser from './SftpBrowser.vue'
import 'xterm/css/xterm.css'
import { useI18n } from 'vue-i18n'

import { useThemeStore } from '../stores/theme'
import { terminalThemes } from '../utils/terminalThemes'

const { t } = useI18n()
const themeStore = useThemeStore()

const props = defineProps({
  hostId: {
    type: [String, Number],
    required: true
  },
  active: {
    type: Boolean,
    default: false
  },
  record: {
    type: Boolean,
    default: false
  },
  hostLabel: {
    type: String,
    default: ''
  }
})

const emit = defineEmits(['close'])

const terminalRef = ref(null)
const terminal = shallowRef(null)
const fitAddon = shallowRef(null)
const ws = ref(null)
const connectionStatus = ref('Connecting...')
const terminalSize = ref('80x24')
const showSftp = ref(false)
const splitRatio = ref(parseFloat(localStorage.getItem('terminal_split_ratio')) || 0.5)
const commandTemplates = ref([])

// Current terminal theme (local state for popover)
const currentTerminalTheme = ref(themeStore.terminalTheme || 'auto')

// Available themes list
const availableThemes = computed(() => {
  const themes = {}
  for (const [key, value] of Object.entries(terminalThemes)) {
    if (key !== 'auto') {
      themes[key] = value
    }
  }
  // Add auto as first option
  return {
    auto: terminalThemes.auto,
    ...themes
  }
})

// Mobile device detection
const isMobileDevice = ref(false)
const modifiers = reactive({
  ctrl: false,
  alt: false,
  shift: false
})

// Detect mobile/tablet devices
const detectMobileDevice = () => {
  const ua = navigator.userAgent || navigator.vendor || window.opera
  const isMobile = /android|webos|iphone|ipad|ipod|blackberry|iemobile|opera mini|mobile|tablet/i.test(ua)
  const isSmallScreen = window.innerWidth <= 1024
  const hasTouchScreen = 'ontouchstart' in window || navigator.maxTouchPoints > 0
  
  // Detect iPad in desktop mode (MacIntel + Touch)
  const isIpadDesktop = /Macintosh/i.test(navigator.userAgent) && navigator.maxTouchPoints && navigator.maxTouchPoints > 1

  isMobileDevice.value = isMobile || (hasTouchScreen && isSmallScreen) || isIpadDesktop
}

const statusColor = ref('processing')
const containerBackground = ref(themeStore.isDark ? '#1e1e1e' : '#ffffff')

// Font Settings
const fontSettings = reactive({
  size: parseInt(localStorage.getItem('termScope_fontSize')) || 14,
  family: localStorage.getItem('termScope_fontFamily') || "'Menlo', 'Monaco', monospace"
})

const updateFont = () => {
  if (terminal.value) {
    terminal.value.options.fontSize = fontSettings.size
    terminal.value.options.fontFamily = fontSettings.family
    
    // Persist
    localStorage.setItem('termScope_fontSize', fontSettings.size)
    localStorage.setItem('termScope_fontFamily', fontSettings.family)
    
    // Refit after resize
    nextTick(() => {
      handleResize()
    })
  }
}

watch([() => themeStore.isDark, () => themeStore.terminalTheme], ([isDark, terminalTheme]) => {
  if (terminal.value) {
    updateTerminalTheme(isDark, terminalTheme)
  }
  // Sync local state with store
  currentTerminalTheme.value = terminalTheme || 'auto'
})

// ... watchers for active/status ...

const updateTerminalTheme = (isDark, terminalTheme = null) => {
  if (!terminal.value) return

  const themeName = terminalTheme || themeStore.terminalTheme || 'auto'
  let themeConfig

  if (themeName !== 'auto' && terminalThemes[themeName]) {
    themeConfig = { ...terminalThemes[themeName].colors }
  } else {
    // Auto mode - follow system theme
    themeConfig = isDark 
      ? { ...terminalThemes.vscodeDark.colors }
      : { ...terminalThemes.vscodeLight.colors }
  }

  terminal.value.options.theme = themeConfig
  
  // Sync container background with terminal background to remove visual gaps
  if (themeConfig.background) {
    containerBackground.value = themeConfig.background
  } else {
    containerBackground.value = isDark ? '#1e1e1e' : '#ffffff'
  }
}

const handleQuickCommand = ({ key }) => {
  if (key && ws.value && ws.value.readyState === WebSocket.OPEN) {
    ws.value.send(JSON.stringify({ type: 'input', data: key + '\n' }))
  }
}

const handleThemeChange = (themeName) => {
  themeStore.setTerminalTheme(themeName)
}

const loadCommands = async () => {
  try {
    const data = await listCommandTemplates()
    commandTemplates.value = data || []
  } catch (error) {
    console.error('Failed to load command templates:', error)
  }
}

const initTerminal = () => {
  // Create terminal instance
  terminal.value = new Terminal({
    cursorBlink: true,
    fontSize: fontSettings.size,
    fontFamily: fontSettings.family,
    theme: {}, // Will be set by updateTerminalTheme
    allowProposedApi: true,
    logLevel: 'info'
  })
  
  updateTerminalTheme(themeStore.isDark, themeStore.terminalTheme)

  // ... rest of init ...

  // Add fit addon
  fitAddon.value = new FitAddon()
  terminal.value.loadAddon(fitAddon.value)

  // Add web links addon
  const webLinksAddon = new WebLinksAddon()
  terminal.value.loadAddon(webLinksAddon)

  // Open terminal in DOM
  terminal.value.open(terminalRef.value)

  // Fit terminal to container
  const resizeObserver = new ResizeObserver(() => {
    if (fitAddon.value && terminal.value) {
      // Ensure container has dimensions
      if (terminalRef.value && (terminalRef.value.clientWidth > 0 || terminalRef.value.clientHeight > 0)) {
         try {
           fitAddon.value.fit()
           updateTerminalSize()
           sendResize()
         } catch (e) {
           console.error('Fit error:', e)
         }
      }
    }
  })
  
  if (terminalRef.value) {
    resizeObserver.observe(terminalRef.value)
  }
  
  // Store observer to cleanup
  terminal.value._resizeObserver = resizeObserver

  // Handle window resize as backup
  window.addEventListener('resize', handleResize)

  // Handle terminal data input
  terminal.value.onData((data) => {
    if (ws.value && ws.value.readyState === WebSocket.OPEN) {
      ws.value.send(JSON.stringify({ type: 'input', data }))
    }
  })
}

const connectWebSocket = async () => {
  try {
    // 1. Get one-time ticket
    const response = await getWSTicket()
    const ticket = response.ticket

    // 2. Connect via WebSocket with ticket
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const host = window.location.host
    const wsUrl = `${protocol}//${host}/api/ws/ssh/${props.hostId}?ticket=${ticket}${props.record ? '&record=true' : ''}`
    
    ws.value = new WebSocket(wsUrl)

    ws.value.binaryType = 'arraybuffer'

    ws.value.onopen = () => {
      connectionStatus.value = 'Connected'
      message.success('SSH connection established')
      // Send initial resize
      sendResize()
      // Auto focus
      terminal.value.focus()
    }

    ws.value.onmessage = (event) => {
      // Handle binary data (SSH output)
      if (event.data instanceof ArrayBuffer) {
        if (terminal.value) {
            terminal.value.write(new Uint8Array(event.data))
        }
        return
      }

      // Handle text data (Control messages: JSON)
      if (!terminal.value) return
      try {
        const msg = JSON.parse(event.data)
        // Only treat as structured message if it's an object with a 'type' field
        if (msg && typeof msg === 'object' && msg.type) {
          if (msg.type === 'error') {
            if (msg.code === 'fingerprint_mismatch') {
              Modal.confirm({
                title: t('terminal.fingerprintMismatchTitle'),
                content: h('div', [
                  h('p', t('terminal.fingerprintMismatchWarning1')),
                  h('p', t('terminal.fingerprintMismatchWarning2')),
                  h('p', { style: 'font-weight: bold; margin-top: 8px;' }, `${t('terminal.fingerprintNew')}: ${msg.meta.new_fingerprint}`),
                  h('p', { style: 'margin-top: 8px; color: #faad14;' }, t('terminal.fingerprintAcceptPrompt'))
                ]),
                okText: t('terminal.fingerprintAccept'),
                cancelText: t('common.cancel'),
                onOk: async () => {
                  try {
                    await updateHostFingerprint(props.hostId, msg.meta.new_fingerprint)
                    message.success(t('terminal.fingerprintUpdated'))
                    reconnect()
                  } catch (err) {
                    message.error(t('terminal.fingerprintUpdateFailed') + ': ' + err.message)
                  }
                },
                onCancel: () => {
                  terminal.value.writeln('\r\n\x1b[31m' + t('terminal.fingerprintRejected') + '\x1b[0m\r\n')
                }
              })
              connectionStatus.value = 'Error'
            } else {
              terminal.value.writeln(`\r\n\x1b[31mError: ${msg.data}\x1b[0m\r\n`)
              connectionStatus.value = 'Error'
            }
          } else if (msg.type === 'connected') {
            terminal.value.writeln(`\r\n\x1b[32m${msg.data}\x1b[0m\r\n`)
          }
        } else {
          // If it's valid JSON but not our structured message (e.g. a single number '1')
          // write it as raw data
          terminal.value.write(event.data)
        }
      } catch (e) {
        // Not valid JSON, must be raw terminal output (fallback)
        terminal.value.write(event.data)
      }
    }

    ws.value.onerror = (error) => {
      console.error('WebSocket error:', error)
      connectionStatus.value = 'Error'
      message.error('Connection error')
    }

    ws.value.onclose = () => {
      connectionStatus.value = 'Disconnected'
      if (terminal.value) {
        terminal.value.writeln('\r\n\x1b[33mConnection closed\x1b[0m\r\n')
      }
    }
  } catch (error) {
    console.error('Failed to get WS ticket:', error)
    connectionStatus.value = 'Error'
    message.error('Failed to authenticate WebSocket')
  }
}

const handleResize = () => {
  if (fitAddon.value && terminal.value) {
    try {
      fitAddon.value.fit()
      updateTerminalSize()
      sendResize()
    } catch (e) {
      console.error('Fit error:', e)
    }
  }
}

const updateTerminalSize = () => {
  if (terminal.value) {
    terminalSize.value = `${terminal.value.cols}x${terminal.value.rows}`
  }
}

const sendResize = () => {
  if (ws.value && ws.value.readyState === WebSocket.OPEN && terminal.value) {
    ws.value.send(JSON.stringify({
      type: 'resize',
      data: {
        cols: terminal.value.cols,
        rows: terminal.value.rows
      }
    }))
  }
}

const reconnect = async () => {
  cleanup()
  initTerminal()
  await connectWebSocket()
}

onMounted(async () => {
  detectMobileDevice()
  window.addEventListener('resize', detectMobileDevice)
  initTerminal()
  await connectWebSocket()
  loadCommands()
})

const disconnect = () => {
  if (ws.value) {
    ws.value.close()
  }
}

const cleanup = () => {
  window.removeEventListener('resize', handleResize)
  window.removeEventListener('resize', detectMobileDevice)

  if (terminal.value && terminal.value._resizeObserver) {
    terminal.value._resizeObserver.disconnect()
  }

  if (ws.value) {
    ws.value.close()
    ws.value = null
  }

  if (terminal.value) {
    terminal.value.dispose()
    terminal.value = null
  }
}

// Mobile keyboard functions
const toggleModifier = (key) => {
  modifiers[key] = !modifiers[key]
}

const clearModifiers = () => {
  modifiers.ctrl = false
  modifiers.alt = false
  modifiers.shift = false
}

const sendKey = (key) => {
  if (!ws.value || ws.value.readyState !== WebSocket.OPEN) return
  
  let data = ''
  
  // Map keys to terminal escape sequences
  switch (key) {
    case 'Escape':
      data = '\x1b'
      break
    case 'Tab':
      data = '\t'
      break
    case 'ArrowUp':
      data = '\x1b[A'
      break
    case 'ArrowDown':
      data = '\x1b[B'
      break
    case 'ArrowRight':
      data = '\x1b[C'
      break
    case 'ArrowLeft':
      data = '\x1b[D'
      break
    default:
      data = key
  }
  
  // Apply modifiers if active
  if (modifiers.ctrl && data.length === 1) {
    // Convert to control character
    const charCode = data.toUpperCase().charCodeAt(0)
    if (charCode >= 65 && charCode <= 90) {
      data = String.fromCharCode(charCode - 64)
    }
  }
  
  ws.value.send(JSON.stringify({ type: 'input', data }))
  clearModifiers()
  
  // Refocus terminal
  if (terminal.value) {
    terminal.value.focus()
  }
}

const sendCtrlKey = (char) => {
  if (!ws.value || ws.value.readyState !== WebSocket.OPEN) return
  
  const charCode = char.toUpperCase().charCodeAt(0)
  const ctrlChar = String.fromCharCode(charCode - 64)
  
  ws.value.send(JSON.stringify({ type: 'input', data: ctrlChar }))
  
  if (terminal.value) {
    terminal.value.focus()
  }
}

const sendChar = (char) => {
  if (!ws.value || ws.value.readyState !== WebSocket.OPEN) return
  
  let data = char
  
  // Apply modifiers
  if (modifiers.ctrl) {
    const charCode = char.toUpperCase().charCodeAt(0)
    if (charCode >= 65 && charCode <= 90) {
      data = String.fromCharCode(charCode - 64)
    }
  }
  
  ws.value.send(JSON.stringify({ type: 'input', data }))
  clearModifiers()
  
  if (terminal.value) {
    terminal.value.focus()
  }
}

// Copy selected text to clipboard (for mobile)
const copySelection = async () => {
  if (!terminal.value) return
  const selection = terminal.value.getSelection()
  if (!selection) {
    message.warning('No text selected')
    return
  }
  try {
    await navigator.clipboard.writeText(selection)
    message.success('Copied to clipboard')
  } catch (err) {
    message.error('Failed to copy')
  }
}

// Paste from clipboard to terminal (for mobile)
const pasteFromClipboard = async () => {
  if (!ws.value || ws.value.readyState !== WebSocket.OPEN) return
  
  try {
    const text = await navigator.clipboard.readText()
    if (text) {
      ws.value.send(JSON.stringify({ type: 'input', data: text }))
      if (terminal.value) {
        terminal.value.focus()
      }
    }
  } catch (err) {
    console.error('Failed to paste:', err)
    message.error('Failed to read from clipboard')
  }
}

// Split screen drag functionality
const startDrag = (e) => {
  e.preventDefault()
  
  const terminalWrapper = e.currentTarget.parentElement
  
  const onMouseMove = (e) => {
    const containerWidth = terminalWrapper.offsetWidth
    const newRatio = e.clientX / containerWidth
    
    // 限制比例在0.3-0.7之间
    splitRatio.value = Math.max(0.3, Math.min(0.7, newRatio))
  }
  
  const onMouseUp = () => {
    localStorage.setItem('terminal_split_ratio', splitRatio.value.toString())
    document.removeEventListener('mousemove', onMouseMove)
    document.removeEventListener('mouseup', onMouseUp)
    
    // Trigger terminal resize after drag ends
    nextTick(() => {
      handleResize()
    })
  }
  
  document.addEventListener('mousemove', onMouseMove)
  document.addEventListener('mouseup', onMouseUp)
}

// Watch splitRatio to trigger terminal resize
watch(splitRatio, () => {
  nextTick(() => {
    handleResize()
  })
})

// Watch showSftp to trigger terminal resize
watch(showSftp, () => {
  nextTick(() => {
    handleResize()
  })
})
</script>

<style scoped>
.terminal-wrapper {
  /* background managed by inline style */
}

/* Split screen styles */
.split-container {
  display: flex;
  flex: 1;
  overflow: hidden;
}

.split-container.full-screen {
  /* 全屏模式下，只显示终端 */
}

.split-left,
.split-right {
  flex-shrink: 0;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.split-divider {
  width: 4px;
  background: #ddd;
  cursor: col-resize;
  flex-shrink: 0;
  position: relative;
  transition: background 0.2s;
  user-select: none;
}

.split-divider:hover {
  background: #1890ff;
}

.split-divider-dark {
  background: #444;
}

.split-divider-dark:hover {
  background: #1890ff;
}

.split-divider-line {
  position: absolute;
  left: 50%;
  top: 50%;
  transform: translate(-50%, -50%);
  width: 2px;
  height: 40px;
  background: #999;
  border-radius: 1px;
}

.split-divider-dark .split-divider-line {
  background: #666;
}


.terminal-status {
  height: 28px;
  padding: 0 8px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  z-index: 10;
}

.terminal-container {
  padding: 0 0 0 4px;
  margin: 0;
}

:deep(.xterm) {
  padding: 0;
}

.sftp-active {
  color: #1890ff !important;
  background: rgba(24, 144, 255, 0.1) !important;
}

.status-btn {
  padding: 0 7px !important;
  height: 24px !important;
  font-size: 14px !important;
  color: rgba(255, 255, 255, 0.85) !important;
  display: flex !important;
  align-items: center !important;
}

.status-btn:hover {
  color: #fff !important;
  background: rgba(255, 255, 255, 0.08) !important;
}

.status-btn.danger {
  color: #ff4d4f !important;
}

.status-btn.danger:hover {
  color: #ff7875 !important;
  background: rgba(255, 77, 79, 0.1) !important;
}

:deep(.status-btn .anticon) {
  font-size: 12px !important;
}

.status-divider {
  margin: 0 4px !important;
}

.status-btn.light-mode {
  color: rgba(0, 0, 0, 0.65) !important;
}

.status-btn.light-mode:hover {
  color: #000 !important;
  background: rgba(0, 0, 0, 0.05) !important;
}

.status-btn.danger.light-mode:hover {
  color: #ff4d4f !important;
  background: rgba(255, 77, 79, 0.1) !important;
}

/* Mobile Virtual Keyboard Styles */
.mobile-keyboard-toolbar {
  padding: 6px 8px;
  flex-shrink: 0;
  overflow-x: auto;
  overflow-y: hidden;
  -webkit-overflow-scrolling: touch;
}

.keyboard-row {
  display: flex;
  gap: 4px;
  flex-wrap: nowrap;
  align-items: center;
  width: max-content;
}

.key-btn {
  min-width: 36px;
  height: 32px;
  padding: 0 8px;
  border: 1px solid #555;
  border-radius: 4px;
  background: #3c3c3c;
  color: #e0e0e0;
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  user-select: none;
  transition: all 0.15s ease;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.key-btn:active {
  transform: scale(0.95);
}

.key-btn.dark-mode {
  background: #3c3c3c;
  border-color: #555;
  color: #e0e0e0;
}

.key-btn.dark-mode:hover {
  background: #4a4a4a;
}

.key-btn.dark-mode:active {
  background: #555;
}

.key-btn:not(.dark-mode) {
  background: #ffffff;
  border-color: #d9d9d9;
  color: #333;
}

.key-btn:not(.dark-mode):hover {
  background: #f0f0f0;
}

.key-btn:not(.dark-mode):active {
  background: #e0e0e0;
}

.key-btn.modifier {
  min-width: 44px;
  font-weight: 600;
}

.key-btn.modifier.active {
  background: #1890ff !important;
  border-color: #1890ff !important;
  color: #fff !important;
}

.key-btn.action {
  background: #52c41a;
  color: #fff;
  border-color: #52c41a;
  font-weight: 500;
}

.key-btn.action:active {
  background: #389e0d;
  border-color: #389e0d;
}

.key-btn.action.dark-mode {
  background: #237804;
  border-color: #237804;
}

.key-btn.action.dark-mode:active {
  background: #135200;
  border-color: #135200;
}

.key-btn.arrow {
  min-width: 32px;
  font-size: 14px;
}

.key-btn.small {
  min-width: 32px;
  font-size: 11px;
  font-family: monospace;
}

.key-separator {
  width: 1px;
  height: 20px;
  background: rgba(128, 128, 128, 0.4);
  margin: 0 4px;
  flex-shrink: 0;
}

/* Theme Dropdown Styles */
:deep(.terminal-theme-dropdown .ant-dropdown-menu-item) {
  padding: 8px 16px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

:deep(.terminal-theme-dropdown .ant-dropdown-menu-item-selected) {
  background-color: rgba(24, 144, 255, 0.1);
  color: #1890ff;
}

:deep(.terminal-theme-dropdown .ant-dropdown-menu-item:hover) {
  background-color: rgba(0, 0, 0, 0.05);
}

:deep(.terminal-theme-dropdown .ant-dropdown-menu-item-active) {
  background-color: rgba(0, 0, 0, 0.05);
}

/* Dark mode adjustments */
:deep(.terminal-theme-dropdown.dark .ant-dropdown-menu-item:hover),
:deep(.terminal-theme-dropdown.dark .ant-dropdown-menu-item-active) {
  background-color: rgba(255, 255, 255, 0.08);
}

:deep(.terminal-theme-dropdown.dark .ant-dropdown-menu-item-selected) {
  background-color: rgba(24, 144, 255, 0.15);
  color: #40a9ff;
}
</style>
