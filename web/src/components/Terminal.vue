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
      <div ref="splitLeftRef" class="split-left" :style="splitLeftStyle">
        <div ref="terminalRef" class="terminal-container" :style="{ 
          background: containerBackground,
        }" @contextmenu="handleTerminalContextMenu"></div>
        <div
          v-if="terminalContextMenu.visible"
          class="terminal-context-menu"
          :class="{ 'terminal-context-menu-dark': themeStore.isDark }"
          :style="{ left: `${terminalContextMenu.x}px`, top: `${terminalContextMenu.y}px` }"
          @click.stop
          @mousedown.stop
          @contextmenu.prevent.stop
        >
          <button
            class="terminal-context-menu-item"
            :disabled="!terminalContextMenu.canCopy"
            @click="copySelectionFromContext"
          >
            {{ t('terminal.copy') }}
          </button>
          <button
            class="terminal-context-menu-item"
            :disabled="!terminalContextMenu.canPaste"
            @click="pasteFromContext"
          >
            {{ t('terminal.paste') }}
          </button>
        </div>
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
      <div v-show="showSftp" class="split-right" :style="splitRightStyle">
        <SftpBrowser
          :host-id="hostId"
          :host-label="hostLabel"
          :terminal-id="terminalId"
          :visible="showSftp"
          editor-scope="terminal"
          :initial-path="terminalCwd || ''"
        />
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
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('x')">^X</button>
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('o')">^O</button>
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('w')">^W</button>
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('k')">^K</button>
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('p')">^P</button>
        <button class="key-btn small" :class="{ 'dark-mode': themeStore.isDark }" @click="sendCtrlKey('n')">^N</button>
        
        <span class="key-separator"></span>
        
        <!-- Special Characters -->
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendChar('|')">|</button>
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendChar('&')">&amp;</button>
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendChar('~')">~</button>
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendChar('/')">/</button>
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendChar('-')">-</button>
        <button class="key-btn" :class="{ 'dark-mode': themeStore.isDark }" @click="sendChar('_')">_</button>
        
        <span class="key-separator"></span>
        
        <!-- Selection Mode Button -->
        <button 
          class="key-btn action" 
          :class="{ 'dark-mode': themeStore.isDark, 'active': isSelectionMode }" 
          @click="toggleSelectionMode"
          :style="{ background: isSelectionMode ? '#faad14' : '', borderColor: isSelectionMode ? '#faad14' : '' }"
        >
          {{ isSelectionMode ? '取消选择' : '👆 选择文字' }}
        </button>
        
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
          <a-button class="status-btn" :class="{ 'light-mode': !themeStore.isDark }" size="small" type="text" @click="reconnect" v-if="connectionStatus === 'Disconnected' || connectionStatus === 'Error'">
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
                  <a-select-option value="'TermiScope Mono', monospace">TermiScope Mono</a-select-option>
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
        <a-dropdown
          v-model:open="commandsDropdownOpen"
          :disabled="connectionStatus !== 'Connected'"
          placement="topRight"
          @openChange="onCommandsDropdownOpen"
        >
          <a-button class="status-btn" :class="{ 'light-mode': !themeStore.isDark }" size="small" type="text">
            <template #icon><ThunderboltOutlined /></template>
            {{ t('terminal.commands') }}
            <span class="status-shortcut-hint">Alt+K</span>
          </a-button>
          <template #overlay>
            <a-menu @click="handleQuickCommand">
              <a-menu-item v-if="commandTemplates.length === 0" key="__empty" disabled>
                {{ t('terminal.noCommandTemplates') }}
              </a-menu-item>
              <a-menu-item v-for="(cmd, index) in commandTemplates" :key="String(cmd.id)">
                <div class="quick-command-item">
                  <span class="quick-command-main">
                    <span class="quick-command-name">{{ cmd.name }}</span>
                    <span class="quick-command-text">{{ cmd.command }}</span>
                  </span>
                  <span v-if="index < 9" class="quick-command-shortcut">{{ index + 1 }}</span>
                  <a-tag :color="cmd.auto_enter ? 'green' : 'default'" class="quick-command-tag">
                    {{ cmd.auto_enter ? t('terminal.quickCommandRun') : t('terminal.quickCommandInsert') }}
                  </a-tag>
                </div>
              </a-menu-item>
              <a-menu-divider v-if="commandTemplates.length > 0" />
              <a-menu-item key="__manage">
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
import { ref, shallowRef, reactive, onMounted, onUnmounted, onActivated, inject, nextTick, watch, h, computed } from 'vue'
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
import { useRouter } from 'vue-router'

import { useThemeStore } from '../stores/theme'
import { terminalThemes } from '../utils/terminalThemes'
import { buildWebSocketUrl } from '../utils/ws'
import {
  TERMINAL_IDLE_TIMEOUT_CLOSE_CODE,
  createTerminalSessionState,
} from '../utils/terminalSessionState'

const { t } = useI18n()
const router = useRouter()
const themeStore = useThemeStore()

const props = defineProps({
  terminalId: {
    type: String,
    required: true,
  },
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
const splitLeftRef = ref(null)
const terminal = shallowRef(null)
const fitAddon = shallowRef(null)
const ws = ref(null)
const connectionStatus = ref('Connecting...')
const terminalSize = ref('80x24')
const showSftp = ref(false)
const terminalCwd = ref(null)
let commandBuffer = ''
const splitRatio = ref(parseFloat(localStorage.getItem('terminal_split_ratio')) || 0.5)
const commandTemplates = ref([])
const commandsDropdownOpen = ref(false)
const sessionState = createTerminalSessionState()
const terminalErrorWritten = ref(false)
const terminalContextMenu = reactive({
  visible: false,
  x: 0,
  y: 0,
  canCopy: false,
  canPaste: false,
})

const splitLeftStyle = computed(() => {
  if (!showSftp.value) {
    return { flex: '1 1 0%', minWidth: 0, minHeight: 0 }
  }
  return {
    flexGrow: splitRatio.value,
    flexShrink: 1,
    flexBasis: 0,
    minWidth: 0,
    minHeight: 0,
  }
})

const splitRightStyle = computed(() => ({
  flexGrow: 1 - splitRatio.value,
  flexShrink: 1,
  flexBasis: 0,
  minWidth: 0,
  minHeight: 0,
}))

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
// Mobile text selection mode
const isSelectionMode = ref(false)
const toggleSelectionMode = () => {
  isSelectionMode.value = !isSelectionMode.value
  if (isSelectionMode.value) {
    message.success('已开启文字选择模式：在终端滑动以选中文字')
  } else {
    message.info('已恢复滑动滚动模式')
  }
}

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
let terminalViewport = null
let terminalElement = null
let lastMeasuredTerminalSize = { width: 0, height: 0 }
let touchStartHandler = null
let touchMoveHandler = null
let touchEndHandler = null
let pointerFocusHandler = null
let reconnectTimer = null

const getDefaultTerminalFontFamily = () => {
  return "'TermiScope Mono', monospace"
}

const getSystemTerminalCursorStyle = () => {
  const style = localStorage.getItem('system_terminal_cursor_style')
  return ['bar', 'block', 'underline'].includes(style) ? style : 'bar'
}

const handleSystemTerminalCursorStyleChange = (event) => {
  const style = event.detail
  if (terminal.value && ['bar', 'block', 'underline'].includes(style)) {
    terminal.value.options.cursorStyle = style
    terminal.value.options.cursorWidth = 1
  }
}

// Font Settings — must stay monospace; lineHeight/letterSpacing are fixed at 1/0 for selection alignment
const fontSettings = reactive({
  size: parseInt(localStorage.getItem('termScope_fontSize'), 10) || 14,
  family: localStorage.getItem('termScope_fontFamily') || getDefaultTerminalFontFamily(),
})

const TERMINAL_LAYOUT_OPTIONS = {
  lineHeight: 1,
  letterSpacing: 0,
  windowsMode: typeof navigator !== 'undefined' && /Windows/i.test(navigator.userAgent),
  customGlyphs: false,
}

const updateFont = () => {
  if (terminal.value) {
    terminal.value.options.fontSize = fontSettings.size
    terminal.value.options.fontFamily = fontSettings.family
    terminal.value.options.lineHeight = TERMINAL_LAYOUT_OPTIONS.lineHeight
    terminal.value.options.letterSpacing = TERMINAL_LAYOUT_OPTIONS.letterSpacing
    
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
  if (key === '__manage') {
    commandsDropdownOpen.value = false
    router.push({ name: 'CommandManagement' })
    return
  }
  if (key === '__empty') return

  const command = commandTemplates.value.find((item) => String(item.id) === String(key))
  runQuickCommand(command)
}

const runQuickCommand = (command) => {
  if (command && ws.value && ws.value.readyState === WebSocket.OPEN) {
    const data = command.command + (command.auto_enter ? '\r' : '')
    ws.value.send(JSON.stringify({ type: 'input', data }))
    commandsDropdownOpen.value = false
    terminal.value?.focus()
  }
}

const runQuickCommandByIndex = (index) => {
  runQuickCommand(commandTemplates.value[index])
}

const handleThemeChange = (themeName) => {
  themeStore.setTerminalTheme(themeName)
}

const loadCommands = async () => {
  try {
    const data = await listCommandTemplates()
    commandTemplates.value = data || []
    return commandTemplates.value
  } catch (error) {
    console.error('Failed to load command templates:', error)
    return commandTemplates.value
  }
}

const onCommandsDropdownOpen = (open) => {
  if (open) loadCommands()
}

const showCommandsDropdown = async () => {
  if (!props.active) return
  if (connectionStatus.value !== 'Connected') return
  await loadCommands()
  commandsDropdownOpen.value = true
}

const isTerminalEventTarget = (target) => {
  return Boolean(terminalElement && target instanceof Node && terminalElement.contains(target))
}

const isEditableShortcutTarget = (target) => {
  if (isTerminalEventTarget(target)) return false
  const tagName = target?.tagName?.toLowerCase()
  return tagName === 'input' || tagName === 'textarea' || tagName === 'select' || target?.isContentEditable
}

const handleCommandShortcutKey = (event) => {
  const key = event.key?.toLowerCase()
  if (event.altKey && key === 'k') {
    event.preventDefault()
    event.stopPropagation()
    showCommandsDropdown()
    return true
  }

  if (!commandsDropdownOpen.value) return false
  if (event.ctrlKey || event.metaKey || event.altKey) return false
  if (!/^[1-9]$/.test(event.key)) return false

  const index = Number(event.key) - 1
  if (index >= commandTemplates.value.length) return false

  event.preventDefault()
  event.stopPropagation()
  runQuickCommandByIndex(index)
  return true
}

const handleGlobalCommandShortcut = (event) => {
  if (!props.active) return
  if (isEditableShortcutTarget(event.target)) return
  handleCommandShortcutKey(event)
}

const handleTerminalKeyEvent = (event) => {
  if (!props.active) return true
  if (event.type === 'keydown' && handleCommandShortcutKey(event)) {
    return false
  }
  return true
}

const commandsRefreshTick = inject('commandsRefreshTick', null)
if (commandsRefreshTick) {
  watch(commandsRefreshTick, () => loadCommands())
}

const initTerminal = () => {
  const container = terminalRef.value
  if (!container) {
    return false
  }

  // Create terminal instance
  terminal.value = new Terminal({
    cursorBlink: true,
    cursorStyle: getSystemTerminalCursorStyle(),
    cursorWidth: 1,
    cursorInactiveStyle: 'outline',
    fontSize: fontSettings.size,
    fontFamily: fontSettings.family,
    ...TERMINAL_LAYOUT_OPTIONS,
    theme: {}, // Will be set by updateTerminalTheme
    allowProposedApi: true,
    logLevel: 'info',
    scrollback: 10000,
    scrollOnUserInput: true,
  })
  terminal.value.attachCustomKeyEventHandler(handleTerminalKeyEvent)
  
  updateTerminalTheme(themeStore.isDark, themeStore.terminalTheme)

  // ... rest of init ...

  // Add fit addon
  fitAddon.value = new FitAddon()
  terminal.value.loadAddon(fitAddon.value)

  // Add web links addon
  const webLinksAddon = new WebLinksAddon()
  terminal.value.loadAddon(webLinksAddon)

  // Open terminal in DOM
  terminal.value.open(container)
  terminalElement = terminal.value.element
  terminalViewport = container.querySelector('.xterm-viewport')
  pointerFocusHandler = () => terminal.value?.focus()
  container.addEventListener('pointerdown', pointerFocusHandler)

  // Mobile Text Selection (Touch-to-Mouse Proxy)
  const touchToMouse = (e, mouseEventType) => {
    if (!isSelectionMode.value) return
    if (e.cancelable) e.preventDefault()
    const touch = e.touches[0] || e.changedTouches[0]
    if (!touch) return
    const mouseEvent = new MouseEvent(mouseEventType, {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX: touch.clientX,
      clientY: touch.clientY,
      button: 0
    })
    touch.target.dispatchEvent(mouseEvent)
  }

  touchStartHandler = (e) => touchToMouse(e, 'mousedown')
  touchMoveHandler = (e) => touchToMouse(e, 'mousemove')
  touchEndHandler = (e) => touchToMouse(e, 'mouseup')

  terminalElement.addEventListener('touchstart', touchStartHandler, { passive: false })
  terminalElement.addEventListener('touchmove', touchMoveHandler, { passive: false })
  terminalElement.addEventListener('touchend', touchEndHandler, { passive: false })

  // Fit terminal to container when split pane or window size changes
  const resizeObserver = new ResizeObserver(() => {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => handleResize())
    })
  })

  resizeObserver.observe(container)
  if (splitLeftRef.value) {
    resizeObserver.observe(splitLeftRef.value)
  }
  
  // Store observer to cleanup
  terminal.value._resizeObserver = resizeObserver

  // Handle window resize as backup
  window.addEventListener('resize', handleResize)

  // Handle terminal data input
  terminal.value.onData((data) => {
    trackCdCommand(data)
    if (ws.value && ws.value.readyState === WebSocket.OPEN) {
      trackUserExitInput(data)
      ws.value.send(JSON.stringify({ type: 'input', data }))
    }
  })
  return true
}

const trackUserExitInput = (data) => {
  sessionState.recordInput(data)
}

const resolveCdPath = (cwd, segment) => {
  if (!segment || segment === '~') return null
  if (segment.startsWith('/')) return segment.replace(/\/+/g, '/').replace(/\/+$/, '') || '/'
  const base = cwd ? cwd.replace(/\/+$/, '') : '/'
  const parts = (base + '/' + segment).replace(/\/+/g, '/').split('/').filter(Boolean)
  const resolved = []
  for (const part of parts) {
    if (part === '..') {
      resolved.pop()
    } else if (part !== '.') {
      resolved.push(part)
    }
  }
  return '/' + resolved.join('/')
}

const trackCdCommand = (data) => {
  for (let i = 0; i < data.length; i++) {
    const ch = data[i]
    if (ch === '\r') {
      const cmd = commandBuffer.trim()
      commandBuffer = ''
      if (!cmd) continue
      const mainCmd = cmd.split(/[;&|]/)[0].trim()
      if (mainCmd === 'cd') {
        terminalCwd.value = null
      } else if (/^cd\s+/.test(mainCmd)) {
        let pathArg = mainCmd.substring(3).trim()
        if ((pathArg.startsWith('"') && pathArg.endsWith('"')) ||
            (pathArg.startsWith("'") && pathArg.endsWith("'"))) {
          pathArg = pathArg.slice(1, -1)
        }
        if (!pathArg || pathArg === '~' || pathArg === '') {
          terminalCwd.value = null
        } else if (pathArg !== '-' && pathArg.indexOf('$') === -1) {
          terminalCwd.value = resolveCdPath(terminalCwd.value, pathArg)
        }
      }
    } else if (ch === '\x7f' || ch === '\b') {
      commandBuffer = commandBuffer.slice(0, -1)
    } else if (ch === '\x03' || ch === '\x15') {
      commandBuffer = ''
    } else if (ch >= ' ' && ch !== '\x7f') {
      commandBuffer += ch
    }
  }
}

let wsConnectInFlight = false

const describeWebSocketClose = (event) => {
  if (event.code === TERMINAL_IDLE_TIMEOUT_CLOSE_CODE || event.reason === 'idle timeout') {
    return t('terminal.idleTimeoutReconnect')
  }
  if (event.code === 1000) return null
  const reason = event.reason?.trim()
  if (reason) return reason
  // 1006: abnormal closure — often HTTP 401/404/403 before upgrade (check Network → WS)
  if (event.code === 1006) {
    return t('terminal.wsAbnormalClose')
  }
  return t('terminal.wsClosedWithCode', { code: event.code })
}

const writeTerminalError = (text) => {
  if (!text) return
  terminalErrorWritten.value = true
  terminal.value?.writeln(`\r\n\x1b[31m${text}\x1b[0m\r\n`)
}

const connectWebSocket = async () => {
  if (wsConnectInFlight) return
  wsConnectInFlight = true
  clearReconnectTimer()
  sessionState.beginConnect()
  terminalErrorWritten.value = false

  if (ws.value) {
    ws.value.onopen = null
    ws.value.onmessage = null
    ws.value.onerror = null
    ws.value.onclose = null
    ws.value.close()
    ws.value = null
  }

  try {
    const response = await getWSTicket()
    const ticket = response?.ticket
    if (!ticket) {
      throw new Error(t('terminal.wsNoTicket'))
    }

    const recordQuery = props.record ? '&record=true' : ''
    const wsUrl = buildWebSocketUrl(
      `/api/ws/ssh/${props.hostId}?ticket=${encodeURIComponent(ticket)}${recordQuery}`
    )
    const socket = new WebSocket(wsUrl)
    ws.value = socket
    socket.binaryType = 'arraybuffer'

    socket.onopen = () => {
      connectionStatus.value = 'Connected'
      sessionState.connected()
      message.success(t('terminal.connected'))
      sendResize()
      terminal.value?.focus()
    }

    socket.onmessage = (event) => {
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
            sessionState.markError()
            if (msg.code === 'fingerprint_mismatch') {
              writeTerminalError(msg.data)
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
              writeTerminalError(`Error: ${msg.data}`)
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

    socket.onerror = (error) => {
      console.error('WebSocket error:', error)
      const state = sessionState.snapshot()
      if (state.manualDisconnected || state.sessionEnded) {
        connectionStatus.value = 'Disconnected'
        return
      }
      sessionState.markError()
      connectionStatus.value = 'Error'
      message.error(t('terminal.connectionFailed'))
    }

    socket.onclose = (event) => {
      const detail = describeWebSocketClose(event)
      const close = sessionState.closed(event)
      const { shouldReconnect, endedQuietly, connectionErrorSeen, manualDisconnected } = close

      if (shouldReconnect) {
        connectionStatus.value = 'Disconnected'
        if (detail) {
          terminal.value?.writeln(`\r\n\x1b[33m${detail}\x1b[0m\r\n`)
        }
        message.info(t('terminal.reconnecting'))
      } else if (connectionErrorSeen && terminalErrorWritten.value) {
        connectionStatus.value = 'Error'
      } else if (detail && !endedQuietly) {
        connectionStatus.value = 'Error'
        console.warn('[Terminal] WebSocket closed:', event.code, event.reason || detail)
        message.error(detail)
        writeTerminalError(detail)
      } else if (connectionErrorSeen) {
        connectionStatus.value = 'Error'
      } else if (terminal.value && !manualDisconnected) {
        connectionStatus.value = 'Disconnected'
        terminal.value.writeln(`\r\n\x1b[33m${t('terminal.disconnected')}\x1b[0m\r\n`)
      } else {
        connectionStatus.value = 'Disconnected'
      }

      if (ws.value === socket) {
        ws.value = null
      }
      if (shouldReconnect) {
        scheduleReconnect()
      }
    }
  } catch (error) {
    console.error('Failed to connect WebSocket:', error)
    sessionState.markError()
    connectionStatus.value = 'Error'
    const msg = error.response?.data?.error || error.message || t('terminal.connectionFailed')
    message.error(msg)
    writeTerminalError(msg)
  } finally {
    wsConnectInFlight = false
  }
}

const handleResize = ({ force = false } = {}) => {
  if (!fitAddon.value || !terminal.value || !terminalRef.value) return
  const { clientWidth, clientHeight } = terminalRef.value
  if (clientWidth <= 0 || clientHeight <= 0) return
  if (!force && clientWidth === lastMeasuredTerminalSize.width && clientHeight === lastMeasuredTerminalSize.height) {
    return
  }

  try {
    const viewport = terminalViewport || terminalRef.value.querySelector('.xterm-viewport')
    const prevScrollTop = viewport?.scrollTop ?? 0
    const wasPinnedToBottom = viewport
      ? viewport.scrollTop + viewport.clientHeight >= viewport.scrollHeight - 4
      : true

    fitAddon.value.fit()
    lastMeasuredTerminalSize = { width: clientWidth, height: clientHeight }

    if (viewport) {
      viewport.scrollLeft = 0
      if (wasPinnedToBottom) {
        viewport.scrollTop = viewport.scrollHeight
      } else {
        viewport.scrollTop = Math.min(prevScrollTop, Math.max(0, viewport.scrollHeight - viewport.clientHeight))
      }
    }
    // Re-sync glyph/selection layers after layout (fixes drag-select offset after resize or heavy TUI output)
    terminal.value.refresh(0, terminal.value.rows - 1)
    if (typeof terminal.value.clearTextureAtlas === 'function') {
      terminal.value.clearTextureAtlas()
    }
    updateTerminalSize()
    sendResize()
  } catch (e) {
    console.error('Fit error:', e)
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

const clearReconnectTimer = () => {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer)
    reconnectTimer = null
  }
}

const scheduleReconnect = () => {
  clearReconnectTimer()
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null
    if (sessionState.canReconnect(connectionStatus.value)) {
      reconnect()
    }
  }, 3000)
}

const reconnect = async () => {
  clearReconnectTimer()
  terminalCwd.value = null
  commandBuffer = ''
  sessionState.beginConnect()
  terminalErrorWritten.value = false
  connectionStatus.value = 'Connecting...'
  if (ws.value) {
    ws.value.onopen = null
    ws.value.onmessage = null
    ws.value.onerror = null
    ws.value.onclose = null
    ws.value.close()
    ws.value = null
  }
  await nextTick()
  if (!terminal.value && !initTerminal()) return
  handleResize()
  await connectWebSocket()
}

const handleVisibilityChange = () => {
  if (document.visibilityState !== 'visible') return
  nextTick(() => {
    handleResize()
  })
}

const waitForTerminalContainer = async () => {
  for (let i = 0; i < 40; i++) {
    await nextTick()
    if (terminalRef.value) return true
    await new Promise((r) => requestAnimationFrame(r))
  }
  return false
}

const ensureInitialized = async () => {
  if (terminal.value) {
    nextTick(() => handleResize({ force: true }))
    return
  }
  if (!(await waitForTerminalContainer())) return

  detectMobileDevice()
  window.addEventListener('resize', detectMobileDevice)
  window.addEventListener('resize', hideTerminalContextMenu)
  document.addEventListener('click', hideTerminalContextMenu)
  document.addEventListener('keydown', handleContextMenuKeydown)
  document.addEventListener('keydown', handleGlobalCommandShortcut)
  document.addEventListener('visibilitychange', handleVisibilityChange)
  if (!initTerminal()) return
  await connectWebSocket()
  loadCommands()
  nextTick(() => handleResize({ force: true }))
}

watch(() => props.active, async (isActive) => {
  if (!isActive) return
  await ensureInitialized()
})

onMounted(async () => {
  window.addEventListener('system-terminal-cursor-style', handleSystemTerminalCursorStyleChange)
  if (props.active) {
    await ensureInitialized()
  }
})

onActivated(async () => {
  if (props.active) {
    await ensureInitialized()
  }
})

onUnmounted(() => {
  window.removeEventListener('system-terminal-cursor-style', handleSystemTerminalCursorStyleChange)
  cleanup()
})

const disconnect = () => {
  terminalCwd.value = null
  commandBuffer = ''
  sessionState.manualDisconnect()
  if (ws.value) {
    ws.value.close(1000, 'user disconnected')
  }
}

const cleanup = () => {
  clearReconnectTimer()
  sessionState.dispose()
  terminalErrorWritten.value = false
  window.removeEventListener('resize', handleResize)
  window.removeEventListener('resize', detectMobileDevice)
  window.removeEventListener('resize', hideTerminalContextMenu)
  document.removeEventListener('click', hideTerminalContextMenu)
  document.removeEventListener('keydown', handleContextMenuKeydown)
  document.removeEventListener('keydown', handleGlobalCommandShortcut)
  document.removeEventListener('visibilitychange', handleVisibilityChange)

  if (terminal.value && terminal.value._resizeObserver) {
    terminal.value._resizeObserver.disconnect()
  }

  if (ws.value) {
    ws.value.onopen = null
    ws.value.onmessage = null
    ws.value.onerror = null
    ws.value.onclose = null
    ws.value.close(1000, 'terminal closed')
    ws.value = null
  }

  if (terminal.value) {
    if (terminalElement && touchStartHandler && touchMoveHandler && touchEndHandler) {
      terminalElement.removeEventListener('touchstart', touchStartHandler)
      terminalElement.removeEventListener('touchmove', touchMoveHandler)
      terminalElement.removeEventListener('touchend', touchEndHandler)
    }
    terminal.value.dispose()
    terminal.value = null
  }

  if (pointerFocusHandler && terminalRef.value) {
    terminalRef.value.removeEventListener('pointerdown', pointerFocusHandler)
  }
  pointerFocusHandler = null
  terminalElement = null
  terminalViewport = null
  touchStartHandler = null
  touchMoveHandler = null
  touchEndHandler = null
  lastMeasuredTerminalSize = { width: 0, height: 0 }
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
    message.warning(t('terminal.noTextSelected'))
    return
  }
  try {
    await navigator.clipboard.writeText(selection)
    message.success(t('terminal.copiedToClipboard'))
  } catch (err) {
    message.error(t('terminal.copyFailed'))
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
    message.error(t('terminal.clipboardReadFailed'))
  }
}

const hideTerminalContextMenu = () => {
  terminalContextMenu.visible = false
}

const handleContextMenuKeydown = (e) => {
  if (e.key === 'Escape') {
    hideTerminalContextMenu()
  }
}

const handleTerminalContextMenu = (e) => {
  if (isMobileDevice.value || !terminal.value) return
  e.preventDefault()
  terminalContextMenu.canCopy = Boolean(terminal.value.getSelection())
  terminalContextMenu.canPaste = connectionStatus.value === 'Connected'
  terminalContextMenu.x = Math.max(8, Math.min(e.clientX, window.innerWidth - 148))
  terminalContextMenu.y = Math.max(8, Math.min(e.clientY, window.innerHeight - 86))
  terminalContextMenu.visible = true
}

const copySelectionFromContext = async () => {
  await copySelection()
  hideTerminalContextMenu()
  terminal.value?.focus()
}

const pasteFromContext = async () => {
  await pasteFromClipboard()
  hideTerminalContextMenu()
}

// Split screen drag functionality
const startDrag = (e) => {
  e.preventDefault()
  
  const terminalWrapper = e.currentTarget.parentElement
  
  const onMouseMove = (moveEvent) => {
    const rect = terminalWrapper.getBoundingClientRect()
    if (rect.width <= 0) return
    const newRatio = (moveEvent.clientX - rect.left) / rect.width

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
  min-height: 0;
  min-width: 0;
  overflow: hidden;
}

.split-container.full-screen {
  /* 全屏模式下，只显示终端 */
}

.split-left,
.split-right {
  overflow: hidden;
  display: flex;
  flex-direction: column;
  min-width: 0;
  min-height: 0;
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
  gap: 8px;
  z-index: 10;
  min-width: 0;
}

.terminal-container {
  position: relative;
  flex: 1;
  width: 100%;
  height: 100%;
  min-width: 0;
  min-height: 0;
  padding: 0;
  margin: 0;
  overflow: hidden;
}

/* Do not force 100% w/h on .xterm — FitAddon sets pixel size; stretching breaks mouse selection coords */
:deep(.xterm) {
  padding: 0;
  line-height: 1 !important;
  letter-spacing: 0 !important;
}

:deep(.xterm .xterm-screen),
:deep(.xterm .xterm-rows),
:deep(.xterm .xterm-row) {
  line-height: 1 !important;
  letter-spacing: 0 !important;
}

:deep(.xterm .xterm-helper-textarea) {
  line-height: 1 !important;
  letter-spacing: 0 !important;
  position: fixed !important;
}

:deep(.xterm-viewport) {
  overflow-x: hidden !important;
  overflow-y: auto !important;
  overscroll-behavior: contain;
  scrollbar-gutter: stable;
}

:deep(.xterm .xterm-viewport::-webkit-scrollbar) {
  width: 10px;
}

:deep(.xterm .xterm-viewport::-webkit-scrollbar-thumb) {
  border-radius: 999px;
}

:deep(.xterm-selection) {
  /* Selection layer must align with cell grid */
  pointer-events: none;
}

.terminal-context-menu {
  position: fixed;
  z-index: 3000;
  min-width: 140px;
  padding: 4px;
  background: #ffffff;
  border: 1px solid rgba(0, 0, 0, 0.12);
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.18);
}

.terminal-context-menu-dark {
  background: #252525;
  border-color: rgba(255, 255, 255, 0.14);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.45);
}

.terminal-context-menu-item {
  display: block;
  width: 100%;
  height: 30px;
  padding: 0 10px;
  border: 0;
  border-radius: 4px;
  background: transparent;
  color: #222;
  font-size: 13px;
  line-height: 30px;
  text-align: left;
  cursor: pointer;
}

.terminal-context-menu-dark .terminal-context-menu-item {
  color: rgba(255, 255, 255, 0.88);
}

.terminal-context-menu-item:hover:not(:disabled) {
  background: rgba(24, 144, 255, 0.12);
}

.terminal-context-menu-item:disabled {
  color: rgba(0, 0, 0, 0.32);
  cursor: not-allowed;
}

.terminal-context-menu-dark .terminal-context-menu-item:disabled {
  color: rgba(255, 255, 255, 0.3);
}

.quick-command-item {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 260px;
  max-width: 420px;
}

.quick-command-main {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-width: 0;
}

.quick-command-name,
.quick-command-text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.quick-command-name {
  font-weight: 500;
}

.quick-command-text {
  color: #8c8c8c;
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 11px;
  line-height: 16px;
}

.quick-command-shortcut,
.status-shortcut-hint {
  border: 1px solid rgba(140, 140, 140, 0.45);
  border-radius: 4px;
  color: #8c8c8c;
  flex-shrink: 0;
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 10px;
  line-height: 14px;
}

.quick-command-shortcut {
  min-width: 18px;
  padding: 0 5px;
  text-align: center;
}

.quick-command-tag {
  flex-shrink: 0;
  margin-right: 0;
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

.status-shortcut-hint {
  margin-left: 6px;
  padding: 0 4px;
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

@media (max-width: 768px) {
  .split-container {
    flex-direction: column;
  }

  .split-left,
  .split-right {
    flex: 1 1 0 !important;
    min-height: 0;
  }

  .split-divider {
    width: 100%;
    height: 6px;
    cursor: row-resize;
  }

  .split-divider-line {
    width: 40px;
    height: 2px;
  }

  .terminal-status {
    height: 34px;
    overflow-x: auto;
    overflow-y: hidden;
    justify-content: flex-start;
    -webkit-overflow-scrolling: touch;
  }

  .terminal-status > div {
    flex-shrink: 0;
  }

  .status-btn {
    height: 28px !important;
    padding: 0 8px !important;
    font-size: 12px !important;
  }

  .status-divider {
    margin: 0 2px !important;
  }

  .quick-command-item {
    min-width: min(260px, calc(100vw - 56px));
    max-width: calc(100vw - 56px);
  }
}

@media (max-width: 480px) {
  .split-right {
    min-height: 42%;
  }
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

@media (max-width: 480px) {
  .mobile-keyboard-toolbar {
    padding: 5px 6px;
  }

  .key-btn {
    height: 34px;
    min-width: 34px;
    padding: 0 7px;
  }

  .key-btn.modifier {
    min-width: 42px;
  }
}
</style>
