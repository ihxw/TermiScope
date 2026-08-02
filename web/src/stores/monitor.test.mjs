import test from 'node:test'
import assert from 'node:assert/strict'
import { createPinia, setActivePinia } from 'pinia'
import { useMonitorStore } from './monitor.js'

const createStore = () => {
  setActivePinia(createPinia())
  return useMonitorStore()
}

test('空的监控上报不会覆盖主机配置中的国家代码', () => {
  const store = createStore()
  store.syncConfigFromSSH([{ id: 1, monitor_enabled: true, country_code: 'CN' }])

  store.applyUpdates({ host_id: 1, country_code: '', cpu: 10 })

  assert.equal(store.hostsById[1].country_code, 'CN')
})

test('监控上报的有效国家代码可补充到主机数据', () => {
  const store = createStore()
  store.syncConfigFromSSH([{ id: 1, monitor_enabled: true, country_code: '' }])

  store.applyUpdates({ host_id: 1, country_code: 'US' })

  assert.equal(store.hostsById[1].country_code, 'US')
})

test('主机配置可清除已有的国家代码', () => {
  const store = createStore()
  store.syncConfigFromSSH([{ id: 1, monitor_enabled: true, country_code: 'JP' }])

  store.syncConfigFromSSH([{ id: 1, monitor_enabled: true, country_code: '' }])

  assert.equal(store.hostsById[1].country_code, '')
})

test('Agent 尚未上报系统信息时使用主机配置的系统类型', () => {
  const store = createStore()
  store.syncConfigFromSSH([{ id: 1, monitor_enabled: true, os_type: 'windows' }])

  assert.equal(store.hostsById[1].os, 'windows')

  store.applyUpdates({ host_id: 1, os: '' })
  assert.equal(store.hostsById[1].os, 'windows')

  store.applyUpdates({ host_id: 1, os: 'windows Microsoft Windows Server' })
  assert.equal(store.hostsById[1].os, 'windows Microsoft Windows Server')
})

test('Agent 更新终态会清除进度且其他事件不会污染更新状态', () => {
  const store = createStore()
  store.syncConfigFromSSH([{ id: 1, monitor_enabled: true, os_type: 'linux' }])

  store.handleStreamMessage({
    type: 'agent_event',
    data: { host_id: 1, event: 'command', message: 'updating' },
  })
  assert.equal(store.hostsById[1].agent_update_status, 'updating')

  store.handleStreamMessage({
    type: 'agent_event',
    data: { host_id: 1, event: 'transfer_port_updated', message: 'changed' },
  })
  assert.equal(store.hostsById[1].agent_update_status, 'updating')

  store.handleStreamMessage({
    type: 'agent_event',
    data: { host_id: 1, event: 'update_failed', message: '更新失败' },
  })
  assert.equal(store.hostsById[1].agent_update_status, null)
})
