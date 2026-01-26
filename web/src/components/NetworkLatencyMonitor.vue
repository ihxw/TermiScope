<template>
  <a-card :title="t('network.latencyTitle')" :bordered="false" size="small" style="margin-top: 12px">
    <template #extra>
       <a-space>
         <a-button 
            size="small" 
            :type="isSmooth ? 'primary' : 'default'"
            @click="toggleSmooth"
         >
            <template #icon><LineChartOutlined /></template>
            {{ isSmooth ? 'Smooth' : 'Sharp' }}
         </a-button>
         <a-select v-model:value="timeRange" size="small" style="width: 100px" @change="fetchChartData">
             <a-select-option value="1h">1h</a-select-option>
             <a-select-option value="8h">8h</a-select-option>
             <a-select-option value="16h">16h</a-select-option>
             <a-select-option value="24h">24h</a-select-option>
         </a-select>
       </a-space>
    </template>

    <!-- Chart Only -->
    <div ref="chartRef" style="width: 100%; height: 400px;"></div>
  </a-card>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { message } from 'ant-design-vue'
import * as echarts from 'echarts'
import { useI18n } from 'vue-i18n'
import { getNetworkTasks, getTaskStats } from '../api/networkMonitor'
import { LineChartOutlined } from '@ant-design/icons-vue'

const props = defineProps({
  hostId: {
    type: Number,
    required: true
  }
})

const { t } = useI18n()
const tasks = ref([])
const loading = ref(false)
const timeRange = ref('24h')
const chartRef = ref(null)
let chartInstance = null
let refreshInterval = null // Store interval ID

// Store raw aligned data for recalculation on toggle
const rawSeriesData = ref([])

onMounted(() => {
   fetchTasks()
   window.addEventListener('resize', handleResize)
   
   // Auto refresh chart every minute
   refreshInterval = setInterval(() => {
       if (tasks.value.length > 0) fetchChartData()
   }, 60000)
})

onUnmounted(() => {
   window.removeEventListener('resize', handleResize)
   if (chartInstance) chartInstance.dispose()
   if (refreshInterval) clearInterval(refreshInterval) // Clean up interval
})

const isSmooth = ref(true)

const toggleSmooth = () => {
    isSmooth.value = !isSmooth.value
    updateChart()
}

const handleResize = () => {
   if (chartInstance) chartInstance.resize()
}

const fetchTasks = async () => {
   loading.value = true
   try {
      const res = await getNetworkTasks(props.hostId)
      tasks.value = res.tasks || []
      // Load chart data
      fetchChartData()
   } catch (e) {
      console.error(e)
   } finally {
      loading.value = false
   }
}

// EMA Algorithm
// alpha = 2 / (N + 1), where N is the smoothing factor (e.g. 10 points)
const calculateEWMA = (data, alpha = 0.3) => {
    let ema = []
    let previousEma = null

    for (let point of data) {
        // point format: [Time, Value, OriginalTime]
        const val = point[1]
        
        if (val === null || val === undefined) {
             ema.push(point)
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

const fetchChartData = async () => {
   if (tasks.value.length === 0) {
      if (chartInstance) chartInstance.clear()
      return
   }
   
   try {
      const promises = tasks.value.map(task => getTaskStats(task.id, timeRange.value))
      const rawResults = await Promise.all(promises)
      
      // Align timestamps logic
      // Flatten all points
      let allPoints = []
      rawResults.forEach((data, sIdx) => {
          if(!data) return
          data.forEach(item => {
              allPoints.push({
                  t: new Date(item.created_at).getTime(),
                  val: item.latency,
                  sIdx
              })
          })
      })
      
      // Sort by time
      allPoints.sort((a, b) => a.t - b.t)
      
      // Cluster within tolerance (10 seconds)
      const tolerance = 10000 
      const alignedSeriesData = new Array(tasks.value.length).fill(0).map(() => [])
      
      if (allPoints.length > 0) {
          let currentRefT = allPoints[0].t
          let currentClusterSeries = new Set()
          
          allPoints.forEach(p => {
              // Start new cluster if:
              // 1. Point is too far from reference
              // 2. OR this series already has a point in the current cluster
              if ((p.t - currentRefT > tolerance) || currentClusterSeries.has(p.sIdx)) {
                  currentRefT = p.t
                  currentClusterSeries.clear()
              }
              
              alignedSeriesData[p.sIdx].push([
                  new Date(currentRefT), 
                  p.val, 
                  new Date(p.t) // Store original timestamp at index 2
              ])
              currentClusterSeries.add(p.sIdx)
          })
      }
      
      // Store globally
      rawSeriesData.value = alignedSeriesData
      updateChart()

   } catch(e) {
      console.error(e)
   }
}

const updateChart = () => {
   if (!chartRef.value) return
   if (!chartInstance) {
      chartInstance = echarts.init(chartRef.value)
   }

   const series = []
   
   // Process data based on mode
   const displayData = rawSeriesData.value.map(sData => {
       if (isSmooth.value) {
           return calculateEWMA(sData, 0.2) // Alpha 0.2 gives decent smoothing
       }
       return sData
   })

   tasks.value.forEach((task, index) => {
      series.push({
         name: task.label || task.target,
         type: 'line',
         showSymbol: false,
         data: displayData[index],
         smooth: true, // Keep visual smoothing on top of data smoothing for best look
         itemStyle: {
            color: task.color || '#1890ff'
         }
      })
   })
   
   const option = {
      tooltip: {
         trigger: 'axis',
         formatter: (params) => {
             let result = params[0].axisValueLabel + '<br/>'
             params.forEach(param => {
                 const originalTime = param.data[2]
                 const timeStr = originalTime 
                     ? originalTime.toLocaleTimeString([], { hour12: false, hour: '2-digit', minute:'2-digit', second:'2-digit' }) 
                     : ''
                 
                 const marker = param.marker
                 const seriesName = param.seriesName
                 const value = param.value[1] ? param.value[1].toFixed(1) : ''
                 
                 result += `${marker} ${seriesName}: <b>${value} ms</b> <span style="color:#888; font-size:12px; margin-left:8px">(${timeStr})</span><br/>`
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
         bottom: '10%',
         containLabel: true
      },
      xAxis: {
         type: 'time',
         boundaryGap: false
      },
      yAxis: {
         type: 'value',
         name: 'Latency (ms)'
      },
      series: series
   }
   
   chartInstance.setOption(option, true)
}

</script>
