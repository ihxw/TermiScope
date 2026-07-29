export const TERMINAL_LOCAL_INPUT_MODE_RESET_SEQUENCE = [
  // Mouse tracking modes: X10, VT200, button-event, any-event, UTF-8, SGR, URXVT
  '\x1b[?9l',
  '\x1b[?1000l',
  '\x1b[?1002l',
  '\x1b[?1003l',
  '\x1b[?1005l',
  '\x1b[?1006l',
  '\x1b[?1015l',
  // Focus event reporting and bracketed paste are also local terminal input modes.
  '\x1b[?1004l',
  '\x1b[?2004l',
].join('')

export const STALE_POINTER_MODE_INPUT_SUPPRESS_MS = 1200

const CSI = '\x1b['

const consumeLegacyMouseReport = (data, offset) => {
  if (!data.startsWith(`${CSI}M`, offset)) return offset
  return offset + 6 <= data.length ? offset + 6 : offset
}

const consumeSgrMouseReport = (data, offset) => {
  if (!data.startsWith(`${CSI}<`, offset)) return offset
  const match = /^\x1b\[<\d+;\d+;\d+[mM]/.exec(data.slice(offset))
  return match ? offset + match[0].length : offset
}

const consumeUrxvtMouseReport = (data, offset) => {
  if (!data.startsWith(CSI, offset)) return offset
  const match = /^\x1b\[\d+;\d+;\d+M/.exec(data.slice(offset))
  return match ? offset + match[0].length : offset
}

const consumeFocusReport = (data, offset) => {
  if (data.startsWith(`${CSI}I`, offset) || data.startsWith(`${CSI}O`, offset)) {
    return offset + 3
  }
  return offset
}

const consumePointerModeReport = (data, offset) => {
  return [
    consumeLegacyMouseReport,
    consumeSgrMouseReport,
    consumeUrxvtMouseReport,
    consumeFocusReport,
  ].reduce((nextOffset, consume) => (
    nextOffset !== offset ? nextOffset : consume(data, offset)
  ), offset)
}

export const isTerminalPointerModeReport = (data) => {
  if (!data || typeof data !== 'string') return false
  let offset = 0
  while (offset < data.length) {
    const nextOffset = consumePointerModeReport(data, offset)
    if (nextOffset === offset) return false
    offset = nextOffset
  }
  return true
}
