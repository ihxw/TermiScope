<template>
  <a-card :title="t('network.latencyTitle')" :bordered="false" size="small" style="margin-top: 12px">
    <template #extra>
       <a-select v-model:value="timeRange" size="small" style="width: 100px" @change="fetchChartData">
           <a-select-option value="1h">1h</a-select-option>
           <a-select-option value="6h">6h</a-select-option>
           <a-select-option value="24h">24h</a-select-option>
       </a-select>
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

const fetchChartData = async () => {
   if (tasks.value.length === 0) {
      if (chartInstance) chartInstance.clear()
      return
   }
   
   // Fetch stats for all tasks concurrently?
   // Or fetch one by one.
   // We need to merge them into one chart series list.
   
   const series = []
   const now = new Date()
   
   // Prepare Chart
   if (!chartInstance) {
      chartInstance = echarts.init(chartRef.value)
   }
   
   chartInstance.showLoading()
   
   try {
      const promises = tasks.value.map(task => getTaskStats(task.id, timeRange.value))
      const results = await Promise.all(promises)
      
      results.forEach((data, index) => {
         const task = tasks.value[index]
         const processedData = (data || []).map(item => {
             return [new Date(item.created_at), item.latency]
         })
         
         series.push({
            name: task.label || task.target,
            type: 'line',
            showSymbol: false,
            data: processedData,
            smooth: true,
            itemStyle: {
               color: task.color || '#1890ff' // Use template color
            }
         })
      })
      
      const option = {
         tooltip: {
            trigger: 'axis',
            valueFormatter: (value) => value ? value.toFixed(1) + ' ms' : ''
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
      
      chartInstance.setOption(option, true) // true = not merge, replace
   } catch(e) {
      console.error(e)
   } finally {
      chartInstance.hideLoading()
   }
}

</script>

