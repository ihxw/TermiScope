import { ref, onMounted, onUnmounted } from 'vue'
import { getWSTicket } from '../api/auth'
import { buildWebSocketUrl } from '../utils/ws'
import { useMonitorStore } from '../stores/monitor'

const connected = ref(false)
const listeners = new Set()
let streamPaused = false
let socket = null
let refCount = 0
let reconnectTimer = null
let connecting = false

/** Pause WS message dispatch (e.g. when MonitorDashboard is keep-alive hidden). */
export function setMonitorStreamPaused(paused) {
  streamPaused = paused
  useMonitorStore().setStreamPaused(paused)
}

function dispatch(msg) {
  if (!streamPaused) {
    useMonitorStore().handleStreamMessage(msg)
  }
  listeners.forEach((fn) => {
    try {
      fn(msg)
    } catch (e) {
      console.error('[monitor-stream]', e)
    }
  })
}

function scheduleReconnect(delayMs) {
  if (reconnectTimer || refCount <= 0) return
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null
    connect()
  }, delayMs)
}

async function connect() {
  if (refCount <= 0 || connecting) return
  if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
    return
  }

  connecting = true
  try {
    const res = await getWSTicket()
    const ticket = res.ticket
    const wsUrl = buildWebSocketUrl(`/api/monitor/stream?token=${encodeURIComponent(ticket)}`)
    socket = new WebSocket(wsUrl)

    socket.onopen = () => {
      connected.value = true
      useMonitorStore().setConnected(true)
      connecting = false
    }

    socket.onmessage = (event) => {
      try {
        dispatch(JSON.parse(event.data))
      } catch (e) {
        console.error(e)
      }
    }

    socket.onclose = () => {
      connected.value = false
      useMonitorStore().setConnected(false)
      connecting = false
      socket = null
      scheduleReconnect(3000)
    }

    socket.onerror = () => {
      connecting = false
    }
  } catch (err) {
    console.error('Failed to connect monitor stream:', err)
    connecting = false
    scheduleReconnect(5000)
  }
}

function teardown() {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer)
    reconnectTimer = null
  }
  if (socket) {
    socket.onclose = null
    socket.close()
    socket = null
  }
  connected.value = false
  useMonitorStore().setConnected(false)
  connecting = false
}

/**
 * Shared monitor WebSocket — one connection per app, multiple subscribers.
 * Messages are applied to monitorStore automatically.
 * @param {{ onMessage?: (msg: object) => void }} [options]
 */
export function useMonitorStream(options = {}) {
  const { onMessage } = options
  let handler = onMessage

  onMounted(() => {
    refCount++
    if (handler) listeners.add(handler)
    connect()
  })

  onUnmounted(() => {
    if (handler) listeners.delete(handler)
    refCount--
    if (refCount <= 0) teardown()
  })

  return { connected }
}
