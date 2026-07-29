<template>
  <span
    v-if="code"
    :class="flagClass"
    :style="{ display: 'inline-block', lineHeight: '1em' }"
  ></span>
  <span v-else :style="{ width: size + 'px', height: size + 'px', display: 'inline-block' }"></span>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  code: { type: String, default: '' },
  size: { type: Number, default: 16 }
})

const flagClass = computed(() => {
  const c = (props.code || '').trim().toLowerCase()
  if (c.length !== 2) return ''
  return `fi fi-${c}`
})
</script>
