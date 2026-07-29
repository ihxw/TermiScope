import test from 'node:test'
import assert from 'node:assert/strict'
import {
  createDialogKeydownHandler,
  findActiveDialogActions,
  findActiveDialogInput,
  installDialogAutoFocus,
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

test('DOM adapter chooses the first editable input from the topmost modal', () => {
  const createInput = (properties = {}) => ({
    disabled: false,
    readOnly: false,
    getAttribute: () => null,
    getClientRects: () => [{}],
    ...properties,
  })
  const disabledInput = createInput({ disabled: true })
  const readonlyInput = createInput({ readOnly: true })
  const editableInput = createInput()
  const lowerInput = createInput()
  const createSurface = (zIndex, inputs) => ({
    zIndex,
    hidden: false,
    getAttribute: () => null,
    getClientRects: () => [{}],
    querySelectorAll: (selector) => selector.includes('[autofocus]') ? [] : inputs,
  })
  const lowerSurface = createSurface(1000, [lowerInput])
  const higherSurface = createSurface(1100, [disabledInput, readonlyInput, editableInput])
  const documentRef = {
    querySelectorAll: () => [lowerSurface, higherSurface],
    defaultView: {
      getComputedStyle: (element) => ({
        display: 'block',
        visibility: 'visible',
        zIndex: String(element.zIndex || 0),
      }),
    },
  }

  const active = findActiveDialogInput(documentRef)

  assert.equal(active.surface, higherSurface)
  assert.equal(active.input, editableInput)
})

test('DOM adapter does not focus through a topmost modal without inputs', () => {
  const lowerInput = {
    getAttribute: () => null,
    getClientRects: () => [{}],
  }
  const createSurface = (zIndex, inputs) => ({
    zIndex,
    getAttribute: () => null,
    getClientRects: () => [{}],
    querySelectorAll: () => inputs,
  })
  const documentRef = {
    querySelectorAll: () => [createSurface(1000, [lowerInput]), createSurface(1100, [])],
    defaultView: {
      getComputedStyle: (element) => ({
        display: 'block',
        visibility: 'visible',
        zIndex: String(element.zIndex),
      }),
    },
  }

  assert.equal(findActiveDialogInput(documentRef), null)
})

test('auto focus runs once per modal opening and resets after close', () => {
  const animationFrames = []
  let mutationCallback
  let visible = true
  let disconnected = false
  const input = {
    disabled: false,
    readOnly: false,
    focusCalls: 0,
    getAttribute: () => null,
    getClientRects: () => [{}],
    focus() {
      this.focusCalls += 1
      documentRef.activeElement = this
    },
  }
  const surface = {
    hidden: false,
    getAttribute: () => null,
    getClientRects: () => visible ? [{}] : [],
    querySelectorAll: (selector) => selector.includes('[autofocus]') ? [] : [input],
  }
  class MutationObserver {
    constructor(callback) {
      mutationCallback = callback
    }

    observe() {}

    disconnect() {
      disconnected = true
    }
  }
  const documentRef = {
    body: {},
    activeElement: null,
    querySelectorAll: () => [surface],
    defaultView: {
      MutationObserver,
      getComputedStyle: () => ({ display: 'block', visibility: 'visible', zIndex: '1000' }),
      requestAnimationFrame: (callback) => {
        animationFrames.push(callback)
        return animationFrames.length
      },
      cancelAnimationFrame: () => {},
    },
  }
  const flushFrame = () => animationFrames.shift()?.()

  const uninstall = installDialogAutoFocus(documentRef)
  flushFrame()
  mutationCallback()
  flushFrame()
  assert.equal(input.focusCalls, 1)

  visible = false
  documentRef.activeElement = null
  mutationCallback()
  flushFrame()
  visible = true
  mutationCallback()
  flushFrame()
  assert.equal(input.focusCalls, 2)

  uninstall()
  assert.equal(disconnected, true)
})
