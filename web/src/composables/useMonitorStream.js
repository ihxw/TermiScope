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
let connectSeq = 0

/** Pause optional page-level listeners; central store updates keep flowing. */
export function setMonitorStreamPaused(paused) {
  streamPaused = paused
  useMonitorStore().setStreamPaused(paused)
}

function dispatch(msg) {
  useMonitorStore().handleStreamMessage(msg)
  if (streamPaused) {
    return
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
  const seq = ++connectSeq
  try {
    const res = await getWSTicket()
    if (seq !== connectSeq || refCount <= 0) {
      connecting = false
      return
    }

    const ticket = res?.ticket
    if (!ticket) {
      throw new Error('Missing monitor WebSocket ticket')
    }

    const wsUrl = buildWebSocketUrl(`/api/monitor/stream?token=${encodeURIComponent(ticket)}`)
    const nextSocket = new WebSocket(wsUrl)
    socket = nextSocket

    nextSocket.onopen = () => {
      if (socket !== nextSocket) {
        nextSocket.close()
        return
      }
      connected.value = true
      useMonitorStore().setConnected(true)
      connecting = false
    }

    nextSocket.onmessage = (event) => {
      try {
        dispatch(JSON.parse(event.data))
      } catch (e) {
        console.error(e)
      }
    }

    nextSocket.onclose = () => {
      if (socket !== nextSocket) return
      connected.value = false
      useMonitorStore().setConnected(false)
      connecting = false
      socket = null
      scheduleReconnect(3000)
    }

    nextSocket.onerror = () => {
      if (socket !== nextSocket) return
      connecting = false
    }
  } catch (err) {
    console.error('Failed to connect monitor stream:', err)
    connecting = false
    scheduleReconnect(5000)
  }
}

function teardown() {
  connectSeq++
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
