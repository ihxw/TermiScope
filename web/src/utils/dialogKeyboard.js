const DIALOG_SURFACE_SELECTOR = '.ant-modal-wrap, .ant-popover'
const MODAL_SURFACE_SELECTOR = '.ant-modal-wrap'
const AUTOFOCUS_INPUT_SELECTOR = [
  'input:not([type])[autofocus]',
  'input[type="text"][autofocus]',
  'input[type="password"][autofocus]',
  'input[type="email"][autofocus]',
  'input[type="number"][autofocus]',
  'input[type="search"][autofocus]',
  'input[type="tel"][autofocus]',
  'input[type="url"][autofocus]',
  'input[type="date"][autofocus]',
  'input[type="datetime-local"][autofocus]',
  'input[type="month"][autofocus]',
  'input[type="time"][autofocus]',
  'input[type="week"][autofocus]',
  'textarea[autofocus]',
  '[contenteditable="true"][autofocus]',
].join(', ')
const EDITABLE_INPUT_SELECTOR = [
  'input:not([type])',
  'input[type="text"]',
  'input[type="password"]',
  'input[type="email"]',
  'input[type="number"]',
  'input[type="search"]',
  'input[type="tel"]',
  'input[type="url"]',
  'input[type="date"]',
  'input[type="datetime-local"]',
  'input[type="month"]',
  'input[type="time"]',
  'input[type="week"]',
  'textarea',
  '[contenteditable="true"]',
].join(', ')
const ACTION_GROUP_SELECTORS = [
  '.ant-popconfirm-buttons',
  '.ant-modal-confirm-btns',
  '.ant-modal-footer',
]

const installedDocuments = new WeakMap()
const installedFocusObservers = new WeakMap()

const isVisible = (element, documentRef) => {
  if (!element || element.hidden || element.getAttribute?.('aria-hidden') === 'true') {
    return false
  }

  const view = documentRef?.defaultView
  const style = view?.getComputedStyle?.(element)
  if (style?.display === 'none' || style?.visibility === 'hidden') {
    return false
  }

  return typeof element.getClientRects !== 'function' || element.getClientRects().length > 0
}

const getZIndex = (element, documentRef) => {
  const value = documentRef?.defaultView?.getComputedStyle?.(element)?.zIndex
  const parsed = Number.parseInt(value, 10)
  return Number.isFinite(parsed) ? parsed : 0
}

const getVisibleSurfaces = (selector, documentRef) => [...documentRef.querySelectorAll(selector)]
  .map((surface, index) => ({
    surface,
    index,
    zIndex: getZIndex(surface, documentRef),
  }))
  .filter(({ surface }) => isVisible(surface, documentRef))
  .sort((left, right) => left.zIndex - right.zIndex || left.index - right.index)

const isUnavailable = (button) => (
  !button
  || button.disabled
  || button.getAttribute?.('aria-disabled') === 'true'
  || button.classList?.contains('ant-btn-loading')
)

const findButtons = (surface, documentRef) => {
  const actionGroup = ACTION_GROUP_SELECTORS
    .map((selector) => surface.querySelector?.(selector))
    .find((element) => isVisible(element, documentRef))

  if (!actionGroup) return null

  const buttons = [...(actionGroup.querySelectorAll?.('button') || [])]
    .filter((button) => isVisible(button, documentRef))
  const confirmButton = buttons.find((button) => button.classList?.contains('ant-btn-primary'))
    || buttons.at(-1)
  const cancelButton = buttons.find((button) => button !== confirmButton)

  return { confirmButton, cancelButton, surface }
}

export const findActiveDialogActions = (documentRef = document) => {
  const surfaces = getVisibleSurfaces(DIALOG_SURFACE_SELECTOR, documentRef)

  for (let index = surfaces.length - 1; index >= 0; index -= 1) {
    const actions = findButtons(surfaces[index].surface, documentRef)
    if (actions) return actions
  }

  return null
}

const isEditableInput = (element, documentRef) => (
  isVisible(element, documentRef)
  && !element.disabled
  && !element.readOnly
  && element.getAttribute?.('aria-disabled') !== 'true'
  && element.getAttribute?.('tabindex') !== '-1'
)

const findEditableInput = (surface, documentRef) => {
  const autofocusInput = [...(surface.querySelectorAll?.(AUTOFOCUS_INPUT_SELECTOR) || [])]
    .find((element) => isEditableInput(element, documentRef))
  if (autofocusInput) return autofocusInput

  return [...(surface.querySelectorAll?.(EDITABLE_INPUT_SELECTOR) || [])]
    .find((element) => isEditableInput(element, documentRef)) || null
}

export const findActiveDialogInput = (documentRef = document) => {
  const surfaces = getVisibleSurfaces(MODAL_SURFACE_SELECTOR, documentRef)
  const activeSurface = surfaces.at(-1)?.surface
  if (!activeSurface) return null

  const input = findEditableInput(activeSurface, documentRef)
  return input ? { input, surface: activeSurface } : null
}

const targetOwnsEnter = (target, surface) => {
  if (!target) return false

  const tagName = target.tagName?.toUpperCase()
  if (tagName === 'TEXTAREA' || tagName === 'SELECT' || target.isContentEditable) {
    return true
  }

  if (['BUTTON', 'A'].includes(tagName)) {
    return !surface || surface.contains?.(target)
  }

  const role = target.getAttribute?.('role')
  if (['button', 'combobox', 'menuitem', 'option'].includes(role)) {
    return true
  }

  return Boolean(target.closest?.(
    '.ant-select, .ant-picker, .ant-cascader, .ant-mentions, .monaco-editor',
  ))
}

const consumeAndClick = (event, button) => {
  if (!button) return

  event.preventDefault()
  if (typeof event.stopImmediatePropagation === 'function') {
    event.stopImmediatePropagation()
  } else {
    event.stopPropagation?.()
  }
  if (!isUnavailable(button)) {
    button.click()
  }
}

export const createDialogKeydownHandler = (findActions) => (event) => {
  if (
    event.defaultPrevented
    || event.isComposing
    || event.keyCode === 229
    || event.repeat
    || event.ctrlKey
    || event.metaKey
    || event.altKey
  ) {
    return
  }

  if (event.key === 'Enter') {
    const actions = findActions()
    if (targetOwnsEnter(event.target, actions?.surface)) return
    consumeAndClick(event, actions?.confirmButton)
    return
  }

  if (event.key === 'Escape' || event.key === 'Esc') {
    consumeAndClick(event, findActions()?.cancelButton)
  }
}

export const installDialogKeyboardShortcuts = (documentRef = document) => {
  const existingHandler = installedDocuments.get(documentRef)
  if (existingHandler) return () => {}

  const handler = createDialogKeydownHandler(() => findActiveDialogActions(documentRef))
  installedDocuments.set(documentRef, handler)
  documentRef.addEventListener('keydown', handler, true)

  return () => {
    if (installedDocuments.get(documentRef) !== handler) return
    documentRef.removeEventListener('keydown', handler, true)
    installedDocuments.delete(documentRef)
  }
}

export const installDialogAutoFocus = (documentRef = document) => {
  if (installedFocusObservers.has(documentRef)) return () => {}

  const view = documentRef.defaultView
  const Observer = view?.MutationObserver || globalThis.MutationObserver
  const root = documentRef.body || documentRef.documentElement
  if (!Observer || !root) return () => {}

  const focusedSurfaces = new WeakSet()
  let visibleSurfaces = new Set()
  let frameId = null
  let installed = true

  const scan = () => {
    const currentVisibleSurfaces = new Set(
      getVisibleSurfaces(MODAL_SURFACE_SELECTOR, documentRef).map(({ surface }) => surface),
    )
    for (const surface of visibleSurfaces) {
      if (!currentVisibleSurfaces.has(surface)) focusedSurfaces.delete(surface)
    }
    visibleSurfaces = currentVisibleSurfaces

    const active = findActiveDialogInput(documentRef)
    if (!active || focusedSurfaces.has(active.surface)) return

    if (documentRef.activeElement !== active.input) {
      active.input.focus?.({ preventScroll: true })
    }
    focusedSurfaces.add(active.surface)
  }

  const scheduleScan = () => {
    if (!installed || frameId !== null) return
    const requestFrame = view?.requestAnimationFrame?.bind(view)
      || ((callback) => setTimeout(callback, 0))
    frameId = requestFrame(() => {
      frameId = null
      if (installed) scan()
    })
  }

  const observer = new Observer(scheduleScan)
  observer.observe(root, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ['aria-disabled', 'aria-hidden', 'class', 'disabled', 'readonly', 'style'],
  })
  installedFocusObservers.set(documentRef, observer)
  scheduleScan()

  return () => {
    if (installedFocusObservers.get(documentRef) !== observer) return
    installed = false
    observer.disconnect()
    if (frameId !== null) {
      const cancelFrame = view?.cancelAnimationFrame?.bind(view) || clearTimeout
      cancelFrame(frameId)
    }
    installedFocusObservers.delete(documentRef)
  }
}
