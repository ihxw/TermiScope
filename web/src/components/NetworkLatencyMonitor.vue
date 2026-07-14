<template>
  <a-card :title="t('network.latencyTitle')" :bordered="false" size="small" style="margin-top: 12px">
    <template #extra>
       <a-space>
         <a-button 
            size="small" 
            @click="fetchChartData({ allowEmpty: true })"
            :loading="chartLoading"
         >
            <template #icon><ReloadOutlined /></template>
            {{ t('common.refresh') }}
         </a-button>
         <a-button 
            size="small" 
            :type="isSmooth ? 'primary' : 'default'"
            @click="toggleSmooth"
         >
            <template #icon><LineChartOutlined /></template>
            {{ isSmooth ? t('network.smooth') : t('network.sharp') }}
         </a-button>
         <a-select v-model:value="timeRange" size="small" style="width: 100px" @change="fetchChartData({ allowEmpty: true })">
             <a-select-option value="1h">1h</a-select-option>
             <a-select-option value="8h">8h</a-select-option>
             <a-select-option value="16h">16h</a-select-option>
             <a-select-option value="24h">24h</a-select-option>
             <a-select-option value="7d">7d</a-select-option>
         </a-select>
       </a-space>
    </template>

    <a-spin :spinning="chartLoading">
      <a-empty
        v-if="!chartLoading && tasks.length === 0"
        :description="t('network.noLatencyTasks')"
        style="padding: 48px 0"
      />
      <div v-show="tasks.length > 0" ref="chartRef" style="width: 100%; height: 400px;"></div>
    </a-spin>
  </a-card>
</template>

<script setup>
import { ref, onMounted, onUnmounted, nextTick, watch } from 'vue'
import echarts from '../utils/echarts'
import { useI18n } from 'vue-i18n'
import { getHostLatencyStats } from '../api/networkMonitor'
import { startVisibilityPoll } from '../utils/visibilityPoll'
import { LineChartOutlined, ReloadOutlined } from '@ant-design/icons-vue'

const props = defineProps({
  hostId: {
    type: Number,
    required: true
  }
})

const { t } = useI18n()
const tasks = ref([])
const chartLoading = ref(false)
const timeRange = ref('24h')
const chartRef = ref(null)
let chartInstance = null
let refreshTimer = null
let requestSeq = 0

const rawSeriesData = ref([])
const chartWindow = ref(getTimeWindow(timeRange.value))

onMounted(async () => {
   await fetchTasks()
   window.addEventListener('resize', handleResize)
   refreshTimer = startVisibilityPoll(() => {
      if (tasks.value.length > 0) fetchChartData()
   }, 60_000, { immediate: false })
})

watch(() => props.hostId, async () => {
   await fetchTasks()
})

onUnmounted(() => {
   requestSeq++
   window.removeEventListener('resize', handleResize)
   if (refreshTimer) refreshTimer()
   if (chartInstance) {
      chartInstance.dispose()
      chartInstance = null
   }
})

const isSmooth = ref(true)

const toggleSmooth = () => {
    isSmooth.value = !isSmooth.value
    updateChart()
}

const handleResize = () => {
   chartInstance?.resize()
}

const fetchTasks = async () => {
   await fetchChartData({ allowEmpty: true })
}

/** Map API rows to ECharts points: [time, latency|null, originalTime] */
const toChartPoints = (rows) => {
   if (!Array.isArray(rows)) return []
   return rows
      .map((item) => {
         const ts = new Date(item.created_at)
         if (Number.isNaN(ts.getTime())) return null
         const failed = item.success === false || (typeof item.latency === 'number' && item.latency < 0)
         const val = failed ? null : (item.latency ?? null)
         return [ts, val, ts]
      })
      .filter(Boolean)
      .sort((a, b) => a[0] - b[0])
}

const calculateEWMA = (data, alpha = 0.2) => {
    const ema = []
    let previousEma = null

    for (const point of data) {
        const val = point[1]
        if (val === null || val === undefined) {
             ema.push(point)
             previousEma = null
             continue
        }

        if (previousEma === null) {
            previousEma = val
            ema.push(point)
        } else {
            const newEma = (val * alpha) + (previousEma * (1 - alpha))
            previousEma = newEma
            ema.push([point[0], newEma, point[2]])
        }
    }
    return ema
}

function parseTimeRangeMs(range) {
   const match = /^(\d+)([hd])$/.exec(range || '')
   if (!match) return 24 * 60 * 60 * 1000

   const value = Number(match[1])
   if (!Number.isFinite(value) || value <= 0) return 24 * 60 * 60 * 1000

   return match[2] === 'd'
      ? value * 24 * 60 * 60 * 1000
      : value * 60 * 60 * 1000
}

function getTimeWindow(range, end = new Date()) {
   const max = end instanceof Date ? end : new Date(end)
   return {
      min: new Date(max.getTime() - parseTimeRangeMs(range)),
      max,
   }
}

const fetchChartData = async (options = {}) => {
   const allowEmpty = options?.allowEmpty === true
   if (!allowEmpty && tasks.value.length === 0) {
      rawSeriesData.value = []
      if (chartInstance) chartInstance.clear()
      return
   }

   const seq = ++requestSeq
   const hostId = props.hostId
   const range = timeRange.value
   const requestedWindow = getTimeWindow(range)
   chartLoading.value = true
   try {
      const res = await getHostLatencyStats(hostId, range)
      if (seq !== requestSeq || hostId !== props.hostId || range !== timeRange.value) return

      chartWindow.value = requestedWindow
      const taskList = res?.tasks || []
      const series = res?.series || []
      tasks.value = taskList.map((t) => ({
         id: t.id,
         label: t.label || t.target,
         target: t.target,
         color: t.color || '#1890ff',
      }))
      rawSeriesData.value = series.map((s) => toChartPoints(s.data || []))
      if (tasks.value.length === 0) {
         chartInstance?.clear()
         return
      }
      await nextTick()
      if (seq === requestSeq) updateChart()
   } catch (e) {
      if (seq !== requestSeq) return
      console.error(e)
   } finally {
      if (seq === requestSeq) {
         chartLoading.value = false
      }
   }
}

const formatLatency = (v) => {
   if (v === null || v === undefined) return t('network.probeFailed')
   return `${Number(v).toFixed(1)} ms`
}

const updateChart = () => {
   if (!chartRef.value || tasks.value.length === 0) return

   if (!chartInstance) {
      chartInstance = echarts.init(chartRef.value)
   }

   const displayData = rawSeriesData.value.map((sData) => {
       if (isSmooth.value) {
           return calculateEWMA(sData, 0.2)
       }
       return sData
   })

   const series = tasks.value.map((task, index) => ({
         name: task.label || task.target,
         type: 'line',
         showSymbol: false,
         connectNulls: false,
         data: displayData[index] || [],
         smooth: isSmooth.value,
         itemStyle: {
            color: task.color || '#1890ff'
         }
   }))

   const option = {
      tooltip: {
         trigger: 'axis',
         formatter: (params) => {
             if (!params?.length) return ''
             let result = params[0].axisValueLabel + '<br/>'
             params.forEach((param) => {
                 const originalTime = param.data?.[2]
                 const timeStr = originalTime instanceof Date
                     ? originalTime.toLocaleTimeString([], { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })
                     : ''
                 const value = formatLatency(param.data?.[1])
                 result += `${param.marker} ${param.seriesName}: <b>${value}</b>`
                 if (timeStr) {
                     result += ` <span style="color:#888;font-size:12px;margin-left:8px">(${timeStr})</span>`
                 }
                 result += '<br/>'
             })
             return result
         }
      },
      legend: {
         data: series.map(s => s.name),
         bottom: 0
      },
      grid: {
         left: '3%',
         right: '4%',
         bottom: '15%',
         top: '8%',
         containLabel: true
      },
      dataZoom: [
         {
            type: 'inside',
            start: 0,
            end: 100,
            zoomOnMouseWheel: true,
            moveOnMouseMove: true,
            moveOnMouseWheel: false
         },
         {
            type: 'slider',
            start: 0,
            end: 100,
            height: 20,
            bottom: 25,
            handleSize: '80%',
            textStyle: { fontSize: 10 }
         }
      ],
      xAxis: {
         type: 'time',
         boundaryGap: false,
         min: chartWindow.value.min.getTime(),
         max: chartWindow.value.max.getTime()
      },
      yAxis: {
         type: 'value',
         name: 'Latency (ms)',
         min: 0,
         scale: true
      },
      series
   }

   chartInstance.setOption(option, true)
   chartInstance.resize()
}

</script>
