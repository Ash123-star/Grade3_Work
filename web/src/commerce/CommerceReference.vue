<script setup lang="ts">
import { computed } from 'vue';

const props = defineProps<{ value: string }>();
const label = computed(() => {
  const overview = /^OVERVIEW-DEMO-(\d{8})-([MO])(\d+)$/.exec(props.value);
  if (overview) {
    const [, date, kind, number] = overview;
    return kind === 'M' ? '演示会员 ' + number : '演示订单 ' + date + '-' + number;
  }
  const demo = /^DEMO-(MEMBER|ORDER)-(\d+)$/.exec(props.value);
  if (demo) return (demo[1] === 'MEMBER' ? '演示会员 ' : '演示订单 ') + demo[2];

  return props.value;
});
</script>

<template>
  <details v-if="label !== value" class="commerce-reference">
    <summary>{{ label }}</summary>
    <p class="muted">原始编号 <code>{{ value }}</code></p>
  </details>
  <span v-else>{{ value }}</span>
</template>
