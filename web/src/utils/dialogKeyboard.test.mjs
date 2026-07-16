import test from 'node:test'
import assert from 'node:assert/strict'
import {
  createDialogKeydownHandler,
  findActiveDialogActions,
  installDialogKeyboardShortcuts,
} from './dialogKeyboard.js'

const createButton = ({ disabled = false } = {}) => ({
  disabled,
  clicks: 0,
  getAttribute(name) {
    return name === 'aria-disabled' ? String(disabled) : null
  },
  click() {
    this.clicks += 1
  },
})

const createEvent = (key, target = { tagName: 'INPUT' }, overrides = {}) => ({
  key,
  target,
  defaultPrevented: false,
  propagationStopped: false,
  preventDefault() {
    this.defaultPrevented = true
  },
  stopImmediatePropagation() {
    this.propagationStopped = true
  },
  ...overrides,
})

test('Enter confirms the active dialog from a single-line input', () => {
  const confirmButton = createButton()
  const event = createEvent('Enter')
  const handler = createDialogKeydownHandler(() => ({ confirmButton }))

  handler(event)

  assert.equal(confirmButton.clicks, 1)
  assert.equal(event.defaultPrevented, true)
  assert.equal(event.propagationStopped, true)
})

test('Escape cancels the active dialog', () => {
  const cancelButton = createButton()
  const event = createEvent('Escape')
  const handler = createDialogKeydownHandler(() => ({ cancelButton }))

  handler(event)

  assert.equal(cancelButton.clicks, 1)
  assert.equal(event.defaultPrevented, true)
  assert.equal(event.propagationStopped, true)
})

test('Enter preserves controls that own the key interaction', () => {
  const targets = [
    { tagName: 'TEXTAREA' },
    { tagName: 'BUTTON' },
    { tagName: 'INPUT', getAttribute: (name) => name === 'role' ? 'combobox' : null },
    { tagName: 'DIV', isContentEditable: true },
  ]

  for (const target of targets) {
    const confirmButton = createButton()
    createDialogKeydownHandler(() => ({ confirmButton }))(createEvent('Enter', target))
    assert.equal(confirmButton.clicks, 0)
  }
})

test('Enter confirms a Popconfirm while focus remains on its external trigger', () => {
  const trigger = { tagName: 'BUTTON' }
  const confirmButton = createButton()
  const surface = { contains: (element) => element !== trigger }
  const handler = createDialogKeydownHandler(() => ({ confirmButton, surface }))

  handler(createEvent('Enter', trigger))

  assert.equal(confirmButton.clicks, 1)
})

test('shortcuts ignore composition, modifiers, repeats, and disabled actions', () => {
  const confirmButton = createButton({ disabled: true })
  const cancelButton = createButton()
  const handler = createDialogKeydownHandler(() => ({ confirmButton, cancelButton }))

  handler(createEvent('Enter', undefined, { isComposing: true }))
  handler(createEvent('Enter', undefined, { ctrlKey: true }))
  handler(createEvent('Enter', undefined, { repeat: true }))
  const disabledEvent = createEvent('Enter')
  handler(disabledEvent)

  assert.equal(confirmButton.clicks, 0)
  assert.equal(cancelButton.clicks, 0)
  assert.equal(disabledEvent.defaultPrevented, true)
})

test('installer registers and removes one capturing keydown listener', () => {
  const calls = []
  const documentRef = {
    addEventListener: (...args) => calls.push(['add', ...args]),
    removeEventListener: (...args) => calls.push(['remove', ...args]),
  }

  const uninstall = installDialogKeyboardShortcuts(documentRef)
  uninstall()

  assert.equal(calls.length, 2)
  assert.equal(calls[0][0], 'add')
  assert.equal(calls[0][1], 'keydown')
  assert.equal(calls[0][3], true)
  assert.deepEqual(calls[1], ['remove', 'keydown', calls[0][2], true])
})

test('DOM adapter chooses the buttons from the topmost visible dialog', () => {
  const createElement = (properties = {}) => ({
    hidden: false,
    getAttribute: () => null,
    getClientRects: () => [{}],
    ...properties,
  })
  const lowConfirm = createButton()
  lowConfirm.classList = { contains: () => true }
  lowConfirm.getClientRects = () => [{}]
  const highCancel = createButton()
  highCancel.classList = { contains: () => false }
  highCancel.getClientRects = () => [{}]
  const highConfirm = createButton()
  highConfirm.classList = { contains: (name) => name === 'ant-btn-primary' }
  highConfirm.getClientRects = () => [{}]
  const createSurface = (zIndex, selector, buttons) => {
    const group = createElement({ querySelectorAll: () => buttons })
    return createElement({
      zIndex,
      querySelector: (candidate) => candidate === selector ? group : null,
    })
  }
  const lowSurface = createSurface(1000, '.ant-modal-footer', [lowConfirm])
  const highSurface = createSurface(1100, '.ant-popconfirm-buttons', [highCancel, highConfirm])
  const documentRef = {
    querySelectorAll: () => [lowSurface, highSurface],
    defaultView: {
      getComputedStyle: (element) => ({
        display: 'block',
        visibility: 'visible',
        zIndex: String(element.zIndex || 0),
      }),
    },
  }

  const actions = findActiveDialogActions(documentRef)

  assert.equal(actions.surface, highSurface)
  assert.equal(actions.confirmButton, highConfirm)
  assert.equal(actions.cancelButton, highCancel)
})
