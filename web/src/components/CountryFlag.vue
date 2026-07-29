<template>
  <span
    v-if="normalizedCode"
    :class="flagClass"
    :style="{ display: 'inline-block', fontSize: size + 'px', lineHeight: '1em' }"
    aria-hidden="true"
  ></span>
  <span v-else :style="{ width: size + 'px', height: size + 'px', display: 'inline-block' }"></span>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  code: { type: String, default: '' },
  size: { type: Number, default: 16 }
})

const normalizedCode = computed(() => {
  const c = (props.code || '').trim().toLowerCase()
  return /^[a-z]{2}$/.test(c) ? c : ''
})

const flagClass = computed(() => `fi fi-${normalizedCode.value}`)
</script>
