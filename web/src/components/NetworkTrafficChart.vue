<template>
  <a-card :title="t('network.trafficHistoryTitle')" :bordered="false" size="small" style="margin-top: 12px">
    <template #extra>
      <a-space>
        <a-button size="small" :loading="loading" @click="fetchData">
          <template #icon><ReloadOutlined /></template>
          {{ t('common.refresh') }}
        </a-button>
        <a-select v-model:value="timeRange" size="small" style="width: 100px" @change="fetchData">
          <a-select-option value="1h">1h</a-select-option>
          <a-select-option value="8h">8h</a-select-option>
          <a-select-option value="16h">16h</a-select-option>
          <a-select-option value="24h">24h</a-select-option>
          <a-select-option value="7d">7d</a-select-option>
        </a-select>
      </a-space>
    </template>
    <DataLoadError
      v-if="loadError"
      :message="t('network.historyLoadFailed')"
      :loading="loading"
      @retry="fetchData"
    />
    <a-spin v-else :spinning="loading">
      <a-empty
        v-if="!loading && points.length === 0"
        :description="t('network.noTrafficHistory')"
        style="padding: 48px 0"
      />
      <div v-show="points.length > 0" ref="chartRef" style="width: 100%; height: 320px" />
    </a-spin>
  </a-card>
</template>

<script setup>
import { ref, onMounted, onUnmounted, nextTick, watch } from 'vue'
import echarts from '../utils/echarts'
import { useI18n } from 'vue-i18n'
import { ReloadOutlined } from '@ant-design/icons-vue'
import { getHostTrafficHistory } from '../api/ssh'
import { startVisibilityPoll } from '../utils/visibilityPoll'
import DataLoadError from './DataLoadError.vue'

const props = defineProps({
  hostId: { type: Number, required: true }
})

const { t } = useI18n()
const timeRange = ref('24h')
const loading = ref(false)
const loadError = ref(false)
const points = ref([])
const chartRef = ref(null)
let chartInstance = null
let refreshTimer = null
let requestSeq = 0

const formatBytes = (bytes) => {
  if (!bytes) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i]
}

const fetchData = async () => {
  const seq = ++requestSeq
  const hostId = props.hostId
  const range = timeRange.value
  loading.value = true
  loadError.value = false
  try {
    const res = await getHostTrafficHistory(hostId, range)
    if (seq !== requestSeq || hostId !== props.hostId || range !== timeRange.value) return

    points.value = res?.points || []
    if (points.value.length === 0) {
      chartInstance?.clear()
    }
    await nextTick()
    if (seq === requestSeq) updateChart()
  } catch (e) {
    if (seq !== requestSeq) return
    console.error(e)
    loadError.value = true
    points.value = []
    chartInstance?.clear()
  } finally {
    if (seq === requestSeq) {
      loading.value = false
    }
  }
}

const updateChart = () => {
  if (!chartRef.value || points.value.length === 0) return
  if (!chartInstance) chartInstance = echarts.init(chartRef.value)

  const rxData = points.value.map((p) => [new Date(p.time), p.rx_rate || 0])
  const txData = points.value.map((p) => [new Date(p.time), p.tx_rate || 0])

  chartInstance.setOption({
    tooltip: {
      trigger: 'axis',
      formatter: (params) => {
        let line = `${params[0]?.axisValueLabel || ''}<br/>`
        params.forEach((p) => {
          line += `${p.marker} ${p.seriesName}: <b>${formatBytes(p.value[1])}/s</b><br/>`
        })
        return line
      }
    },
    legend: { data: [t('network.inbound'), t('network.outbound')], bottom: 0 },
    grid: { left: '3%', right: '4%', bottom: '14%', top: '10%', containLabel: true },
    dataZoom: [
      { type: 'inside', start: 0, end: 100 },
      { type: 'slider', start: 0, end: 100, height: 18, bottom: 28 }
    ],
    xAxis: { type: 'time', boundaryGap: false },
    yAxis: { type: 'value', name: t('network.rateAxis'), min: 0, scale: true },
    series: [
      {
        name: t('network.inbound'),
        type: 'line',
        showSymbol: false,
        smooth: true,
        data: rxData,
        itemStyle: { color: '#52c41a' }
      },
      {
        name: t('network.outbound'),
        type: 'line',
        showSymbol: false,
        smooth: true,
        data: txData,
        itemStyle: { color: '#1890ff' }
      }
    ]
  }, true)
  chartInstance.resize()
}

const handleResize = () => chartInstance?.resize()

watch(() => props.hostId, () => {
  points.value = []
  chartInstance?.clear()
  fetchData()
})

onMounted(() => {
  fetchData()
  window.addEventListener('resize', handleResize)
  refreshTimer = startVisibilityPoll(fetchData, 60_000, { immediate: false })
})

onUnmounted(() => {
  requestSeq++
  window.removeEventListener('resize', handleResize)
  if (refreshTimer) refreshTimer()
  chartInstance?.dispose()
  chartInstance = null
})
</script>
