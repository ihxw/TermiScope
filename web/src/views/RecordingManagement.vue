<template>
  <div class="recording-management">
    <a-card title="Terminal Recordings" :bordered="false" size="small">
      <a-table
        :columns="columns"
        :data-source="recordings"
        :loading="loading"
        size="small"
        row-key="id"
      >
        <template #bodyCell="{ column, record }">
          <template v-if="column.key === 'start_time'">
            {{ formatDateTime(record.start_time) }}
          </template>
          <template v-else-if="column.key === 'duration'">
            {{ formatDuration(record.duration) }}
          </template>
          <template v-else-if="column.key === 'action'">
            <a-space size="small">
              <a-button size="small" type="link" @click="playRecording(record)">
                <template #icon><PlayCircleOutlined /></template>
                Play
              </a-button>
              <a-popconfirm
                title="Are you sure to delete this recording?"
                @confirm="handleDelete(record.id)"
              >
                <a-button size="small" type="link" danger>Delete</a-button>
              </a-popconfirm>
            </a-space>
          </template>
        </template>
      </a-table>
    </a-card>

    <!-- Player Modal -->
    <a-modal
      v-model:open="playerVisible"
      title="Recording Player"
      :footer="null"
      :width="850"
      @cancel="stopPlayer"
      destroyOnClose
    >
      <div ref="playerRef" class="player-container"></div>
      <div class="player-controls" v-if="isPlaying">
        <a-button size="small" @click="togglePlay">
          <template #icon>
            <PauseOutlined v-if="playing" />
            <PlayCircleOutlined v-else />
          </template>
        </a-button>
        <a-slider
          v-model:value="currentTime"
          :max="totalTime"
          :tip-formatter="formatDuration"
          style="flex: 1"
          @change="seek"
        />
        <span class="time-display">{{ formatDuration(currentTime) }} / {{ formatDuration(totalTime) }}</span>
      </div>
    </a-modal>
  </div>
</template>

<script setup>
import { ref, shallowRef, onMounted, nextTick } from 'vue'
import { message } from 'ant-design-vue'
import { PlayCircleOutlined, PauseOutlined } from '@ant-design/icons-vue'
import { Terminal } from 'xterm'
import { FitAddon } from 'xterm-addon-fit'
import { listRecordings, deleteRecording, getRecordingStreamUrl } from '../api/recording'
import 'xterm/css/xterm.css'

const recordings = ref([])
const loading = ref(false)
const playerVisible = ref(false)
const playerRef = ref(null)
const terminal = shallowRef(null)
const fitAddon = shallowRef(null)

const playing = ref(false)
const currentTime = ref(0)
const totalTime = ref(0)
const isPlaying = ref(false)

let recordingData = []
let playInterval = null

const columns = [
  { title: 'Host', dataIndex: 'host', key: 'host' },
  { title: 'User', dataIndex: 'username', key: 'username' },
  { title: 'Start Time', dataIndex: 'start_time', key: 'start_time', sorter: (a, b) => new Date(a.start_time) - new Date(b.start_time) },
  { title: 'Duration', dataIndex: 'duration', key: 'duration' },
  { title: 'Action', key: 'action', width: 140 }
]

const loadRecordings = async () => {
  loading.value = true
  try {
    const data = await listRecordings()
    recordings.value = data || []
  } catch (error) {
    console.error('Failed to load recordings:', error)
  } finally {
    loading.value = false
  }
}

const playRecording = async (record) => {
  playerVisible.value = true
  isPlaying.value = true
  totalTime.value = record.duration
  currentTime.value = 0
  
  await nextTick()
  initPlayer()
  
  try {
    const url = await getRecordingStreamUrl(record.id)
    const response = await fetch(url)
    const text = await response.text()
    recordingData = text.split('\n')
      .filter(line => line.trim() !== '')
      .map(line => JSON.parse(line))
    
    startPlayback()
  } catch (error) {
    message.error('Failed to load recording data')
    console.error(error)
  }
}

const initPlayer = () => {
  terminal.value = new Terminal({
    cursorBlink: false,
    fontSize: 14,
    theme: { background: '#1e1e1e' },
    disableStdin: true
  })
  fitAddon.value = new FitAddon()
  terminal.value.loadAddon(fitAddon.value)
  terminal.value.open(playerRef.value)
  fitAddon.value.fit()
}

const startPlayback = () => {
  playing.value = true
  let dataIndex = 0
  const startTime = Date.now()
  
  playInterval = setInterval(() => {
    if (!playing.value) return
    
    const elapsed = (Date.now() - startTime) / 1000
    currentTime.value = Math.min(elapsed, totalTime.value)
    
    while (dataIndex < recordingData.length && recordingData[dataIndex][0] <= elapsed) {
      const [,, data] = recordingData[dataIndex]
      terminal.value.write(data)
      dataIndex++
    }
    
    if (elapsed >= totalTime.value || dataIndex >= recordingData.length) {
      stopPlayer()
    }
  }, 100)
}

const togglePlay = () => {
  playing.value = !playing.value
}

const stopPlayer = () => {
  playing.value = false
  isPlaying.value = false
  if (playInterval) clearInterval(playInterval)
  if (terminal.value) {
    terminal.value.dispose()
    terminal.value = null
  }
}

const seek = (val) => {
  // Simple seek: clear terminal and replay from start to val
  if (!terminal.value) return
  terminal.value.clear()
  terminal.value.write('\x1b[H\x1b[2J') // Clear and home
  
  let dataIndex = 0
  while (dataIndex < recordingData.length && recordingData[dataIndex][0] <= val) {
    const [,, data] = recordingData[dataIndex]
    terminal.value.write(data)
    dataIndex++
  }
}

const handleDelete = async (id) => {
  try {
    await deleteRecording(id)
    message.success('Recording deleted')
    loadRecordings()
  } catch (error) {
    console.error('Failed to delete recording:', error)
  }
}

const formatDateTime = (dateStr) => {
  if (!dateStr) return '-'
  return new Date(dateStr).toLocaleString()
}

const formatDuration = (seconds) => {
  if (!seconds) return '0s'
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = Math.floor(seconds % 60)
  return [h, m, s].map(v => v > 0 ? v.toString().padStart(2, '0') : '00').join(':').replace(/^00:/, '')
}

onMounted(loadRecordings)
</script>

<style scoped>
.player-container {
  height: 480px;
  background: #1e1e1e;
  padding: 8px;
  border-radius: 4px;
}

.player-controls {
  display: flex;
  align-items: center;
  gap: 16px;
  margin-top: 16px;
  padding: 0 8px;
}

.time-display {
  font-family: monospace;
  font-size: 12px;
  color: #8c8c8c;
  min-width: 80px;
  text-align: right;
}

.dark-theme .time-display {
  color: #bbb;
}

:deep(.xterm-viewport) {
    overflow-y: hidden !important;
}

/* Mobile responsive */
@media (max-width: 768px) {
  .recording-management {
    padding: 8px;
  }
  
  .recording-management :deep(.ant-card-head) {
    padding: 0 12px;
  }
  
  .recording-management :deep(.ant-table) {
    font-size: 12px;
  }
  
  .recording-management :deep(.ant-table-thead > tr > th),
  .recording-management :deep(.ant-table-tbody > tr > td) {
    padding: 8px 6px !important;
  }
  
  .player-container {
    height: 300px;
  }
  
  .player-controls {
    gap: 8px;
  }
  
  .time-display {
    font-size: 10px;
    min-width: 60px;
  }
}
</style>
