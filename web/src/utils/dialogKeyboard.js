const DIALOG_SURFACE_SELECTOR = '.ant-modal-wrap, .ant-popover'
const ACTION_GROUP_SELECTORS = [
  '.ant-popconfirm-buttons',
  '.ant-modal-confirm-btns',
  '.ant-modal-footer',
]

const installedDocuments = new WeakMap()

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
  const surfaces = [...documentRef.querySelectorAll(DIALOG_SURFACE_SELECTOR)]
    .map((surface, index) => ({
      surface,
      index,
      zIndex: getZIndex(surface, documentRef),
    }))
    .filter(({ surface }) => isVisible(surface, documentRef))
    .sort((left, right) => left.zIndex - right.zIndex || left.index - right.index)

  for (let index = surfaces.length - 1; index >= 0; index -= 1) {
    const actions = findButtons(surfaces[index].surface, documentRef)
    if (actions) return actions
  }

  return null
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
