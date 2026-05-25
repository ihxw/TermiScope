/** Run callback on interval only while the document tab is visible. */
export function startVisibilityPoll(callback, intervalMs) {
  const tick = () => {
    if (document.visibilityState === 'visible') {
      callback()
    }
  }
  tick()
  const id = setInterval(tick, intervalMs)
  return () => clearInterval(id)
}
