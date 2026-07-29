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
