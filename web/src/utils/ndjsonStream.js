const abortError = () => new DOMException('Aborted', 'AbortError')

export const consumeNDJSON = async (body, { signal, onEvent, onInvalidLine } = {}) => {
  if (!body?.getReader) throw new Error('Response body is not a readable stream')
  const reader = body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  let eventCount = 0

  const consumeLine = (line) => {
    const value = line.trim()
    if (!value) return
    try {
      onEvent?.(JSON.parse(value))
      eventCount += 1
    } catch (error) {
      onInvalidLine?.(value, error)
    }
  }

  try {
    while (true) {
      if (signal?.aborted) throw abortError()
      const { done, value } = await reader.read()
      if (done) break
      buffer += decoder.decode(value, { stream: true })
      const lines = buffer.split('\n')
      buffer = lines.pop() || ''
      lines.forEach(consumeLine)
    }
    buffer += decoder.decode()
    consumeLine(buffer)
    return eventCount
  } catch (error) {
    if (signal?.aborted) {
      await reader.cancel().catch(() => {})
      throw abortError()
    }
    throw error
  } finally {
    reader.releaseLock?.()
  }
}
