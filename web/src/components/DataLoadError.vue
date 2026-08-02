<template>
  <a-alert
    type="error"
    show-icon
    :message="message || t('common.loadFailed')"
    :description="t('common.loadFailedDescription')"
    class="data-load-error"
  >
    <template #action>
      <a-button size="small" :loading="loading" @click="$emit('retry')">
        {{ t('common.retry') }}
      </a-button>
    </template>
  </a-alert>
</template>

<script setup>
import { useI18n } from 'vue-i18n'

defineProps({
  message: String,
  loading: Boolean,
})

defineEmits(['retry'])

const { t } = useI18n()
</script>

<style scoped>
.data-load-error {
  margin-bottom: 12px;
}
</style>
