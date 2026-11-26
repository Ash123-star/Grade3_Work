<script setup lang="ts">
import type { LocationQueryRaw } from 'vue-router';
import { displayDate, labels, type Kind, type Section } from './contract';
defineProps<{ kind: Kind; section: Section; customerId: string; query: LocationQueryRaw }>();
</script>

<template>
  <section class="crm-panel crm-detail-section" :aria-labelledby="`crm-${kind}`">
    <div class="crm-section-head"><h2 :id="`crm-${kind}`">{{ labels[kind] }}</h2></div>
    <p v-if="section.state === 'RESTRICTED'" class="crm-section-state">此类别未获授权。</p>
    <p v-else-if="section.state === 'UNAVAILABLE'" class="crm-section-state">此来源暂不可用。</p>
    <template v-else-if="section.state === 'AVAILABLE'">
      <p v-if="!section.items.length" class="crm-section-state">暂无记录。</p>
      <ul v-else class="crm-list crm-record-list">
        <li v-for="item in section.items" :key="item.id">
          <div class="crm-record-title"><strong>{{ item.title }}</strong><span v-if="item.status" class="crm-status">{{ item.status }}</span></div>
          <div class="crm-record-meta" v-if="displayDate(item.businessDate) || displayDate(item.validFrom) || displayDate(item.validTo) || item.usageText || item.amountText">
            <span v-if="displayDate(item.businessDate)">{{ displayDate(item.businessDate) }}</span>
            <span v-if="displayDate(item.validFrom)">生效 {{ displayDate(item.validFrom) }}</span>
            <span v-if="displayDate(item.validTo)">到期 {{ displayDate(item.validTo) }}</span>
            <span v-if="item.usageText">{{ item.usageText }}</span><span v-if="item.amountText">订单金额 {{ item.amountText }}</span>
          </div>
          <RouterLink v-if="item.canOpen" :to="{ name: 'crm-record', params: { customerId, kind, recordId: item.id }, query }" :aria-label="`查看${labels[kind]}：${item.title}`">查看记录 →</RouterLink>
        </li>
      </ul>
      <p v-if="section.truncated" class="crm-section-state">这里只展示部分记录。</p>
    </template>
  </section>
</template>
