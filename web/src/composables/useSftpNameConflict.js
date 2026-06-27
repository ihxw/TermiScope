import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useThemeStore } from '../stores/theme'
import { hasNameConflict, generateKeepBothName } from '../utils/sftpConflict'

/**
 * Prompt when a file/folder name already exists in the destination directory.
 * Returns: 'overwrite' | 'keepBoth' | 'cancel', plus optional applyToAll for batch ops.
 */
export function useSftpNameConflict() {
  const { t } = useI18n()
  const themeStore = useThemeStore()

  const conflictOpen = ref(false)
  const conflictName = ref('')
  const conflictIsDir = ref(false)
  const showApplyToAll = ref(false)
  const applyToAll = ref(false)
  let conflictResolver = null
  let batchPolicy = null

  const wrapClass = computed(() =>
    themeStore.isDark
      ? 'upload-conflict-modal-wrap upload-conflict-modal-wrap--dark'
      : 'upload-conflict-modal-wrap'
  )

  const promptConflict = (name, isDir, forBatch = false) => {
    if (batchPolicy === 'skip') return Promise.resolve('cancel')
    if (batchPolicy === 'overwrite') return Promise.resolve('overwrite')
    if (batchPolicy === 'keepBoth') return Promise.resolve('keepBoth')

    return new Promise((resolve) => {
      conflictName.value = name
      conflictIsDir.value = !!isDir
      showApplyToAll.value = forBatch
      applyToAll.value = false
      conflictResolver = resolve
      conflictOpen.value = true
    })
  }

  const finishConflict = (action) => {
    if (applyToAll.value && showApplyToAll.value) {
      batchPolicy = action === 'cancel' ? 'skip' : action
    }
    conflictOpen.value = false
    conflictResolver?.(action)
    conflictResolver = null
  }

  const resetBatchPolicy = () => {
    batchPolicy = null
  }

  const resolveDestName = async (fileName, destFiles, { batch = false } = {}) => {
    if (!hasNameConflict(destFiles, fileName)) {
      return { destFileName: fileName, cancelled: false }
    }

    const entry = destFiles.find((f) => f.name === fileName)
    const action = await promptConflict(fileName, !!entry?.is_dir, batch)

    if (action === 'cancel') {
      return { destFileName: fileName, cancelled: true }
    }
    if (action === 'keepBoth') {
      return {
        destFileName: generateKeepBothName(destFiles, fileName),
        cancelled: false,
      }
    }
    return { destFileName: fileName, cancelled: false }
  }

  return {
    conflictOpen,
    conflictName,
    conflictIsDir,
    showApplyToAll,
    applyToAll,
    wrapClass,
    t,
    onConflictCancel: () => finishConflict('cancel'),
    onConflictOverwrite: () => finishConflict('overwrite'),
    onConflictKeepBoth: () => finishConflict('keepBoth'),
    resolveDestName,
    resetBatchPolicy,
  }
}
