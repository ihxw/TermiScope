<template>
  <span class="os-icon-wrapper" :style="{ display: 'inline-flex', alignItems: 'center', width: size + 'px', height: size + 'px', justifyContent: 'center' }">
    <img
      v-if="osSvgSrc"
      :src="osSvgSrc"
      :width="size"
      :height="size"
      :alt="osName"
      :style="{ display: 'inline-block' }"
      @error="onSvgError"
    />
    <component v-else-if="fallbackIcon" :is="fallbackIcon" :style="{ fontSize: size + 'px' }" />
    <span v-else :style="{ width: size + 'px', height: size + 'px', display: 'inline-block' }"></span>
  </span>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { AppleOutlined, WindowsOutlined, DesktopOutlined } from '@ant-design/icons-vue'

const props = defineProps({
  os: { type: String, default: '' },
  size: { type: Number, default: 18 }
})

const svgError = ref(false)

watch(() => props.os, () => {
  svgError.value = false
})

const osLower = computed(() => (props.os || '').toLowerCase())

const osName = computed(() => {
  const o = osLower.value
  if (o.includes('ubuntu')) return 'Ubuntu'
  if (o.includes('debian')) return 'Debian'
  if (o.includes('almalinux') || o.includes('alma linux')) return 'AlmaLinux'
  if (o.includes('rocky')) return 'Rocky Linux'
  if (o.includes('centos')) return 'CentOS'
  if (o.includes('rhel') || o.includes('red hat')) return 'Red Hat Enterprise Linux'
  if (o.includes('fedora')) return 'Fedora'
  if (o.includes('arch')) return 'Arch Linux'
  if (o.includes('alpine')) return 'Alpine Linux'
  if (o.includes('opensuse') || o.includes('suse')) return 'openSUSE'
  if (o.includes('openwrt')) return 'OpenWrt'
  if (o.includes('freebsd')) return 'FreeBSD'
  if (o.includes('raspbian') || o.includes('raspberry')) return 'Raspberry Pi'
  if (o.includes('darwin') || o.includes('mac')) return 'macOS'
  if (o.includes('win')) return 'Windows'
  return 'Linux'
})

const osSvgSrc = computed(() => {
  if (svgError.value) return ''
  const o = osLower.value
  if (o.includes('ubuntu')) return '/icons/os/ubuntu.svg'
  if (o.includes('debian')) return '/icons/os/debian.svg'
  if (o.includes('almalinux') || o.includes('alma linux')) return '/icons/os/almalinux.svg'
  if (o.includes('rocky')) return '/icons/os/rocky_linux.svg'
  if (o.includes('centos')) return '/icons/os/centos.svg'
  if (o.includes('rhel') || o.includes('red hat')) return '/icons/os/red_hat.svg'
  if (o.includes('fedora')) return '/icons/os/fedora.svg'
  if (o.includes('arch')) return '/icons/os/arch_linux.svg'
  if (o.includes('alpine')) return '/icons/os/alpine_linux.svg'
  if (o.includes('opensuse') || o.includes('suse')) return '/icons/os/opensuse.svg'
  if (o.includes('openwrt')) return '/icons/os/openwrt.svg'
  if (o.includes('freebsd')) return '/icons/os/freebsd.svg'
  if (o.includes('raspbian') || o.includes('raspberry')) return '/icons/os/raspberry_pi.svg'
  if (o.includes('darwin') || o.includes('mac')) return '/icons/os/apple.svg'
  if (o.includes('win')) return '/icons/os/windows.svg'
  if (o.includes('linux')) return '/icons/os/linux.svg'
  return ''
})

const fallbackIcon = computed(() => {
  if (osSvgSrc.value && !svgError.value) return null
  const o = osLower.value
  if (o.includes('win')) return WindowsOutlined
  if (o.includes('mac') || o.includes('darwin')) return AppleOutlined
  return DesktopOutlined
})

function onSvgError() {
  svgError.value = true
}
</script>
