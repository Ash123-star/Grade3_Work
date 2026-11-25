<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue';
import { CommerceError, commerceApi, memberStatuses, orderStatuses } from './api';
import type { Member, Order, OrderGroup, Overview, Page, Receipt } from './api';
import './commerce.css';

const emit = defineEmits<{ accessLost: [message: string] }>();
type Tab = 'overview' | 'members' | 'imports';
const tabs: Record<Tab, string> = { overview: '经营概览', members: '商城会员', imports: '文件导入' };
const tab = ref<Tab>('overview');
const initialCustomer = new URLSearchParams(window.location.search).get('customerId') ?? '';
const filters = ref({ from: '', to: '', customerId: initialCustomer, externalOrderId: '' });
const memberFilters = ref({ customerId: initialCustomer, externalMemberId: '' });
let applied = { ...filters.value };
let appliedMember = { ...memberFilters.value };
const overview = ref<Overview | null>(null);
const orders = ref<Page<Order> | null>(null);
const members = ref<Page<Member> | null>(null);
const group = ref<OrderGroup | null>(null);
const cursor = ref('0');
const pageSize = 20;
const loading = ref(false);
const readError = ref('');
const orderHeading = ref<HTMLElement | null>(null);
let readTask: AbortController | undefined;
let retryRead: (() => void) | undefined;

const file = ref<File | null>(null);
const importing = ref(false);
const importError = ref('');
const receipt = ref<Receipt | null>(null);
const source = ref<Receipt | null>(null);
let importTask: AbortController | undefined;

const dateTime = new Intl.DateTimeFormat('zh-CN', {
  timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
});
function displayTime(value: string) { return dateTime.format(new Date(value)); }

function message(error: unknown) {
  if (!(error instanceof CommerceError)) return '无法连接服务，请稍后重试';
  const data = error.data;
  const section = data.section === 'members' ? '会员列表' : data.section === 'orders' ? '订单列表' : '';
  const row = data.row ? `第 ${data.row} 条` : '';
  const location = [section, row, data.field].filter(Boolean).join(' · ');
  const trace = data.traceId ? `（追踪号：${data.traceId}）` : '';
  return `${location ? location + '：' : ''}${error.message}${trace}`;
}

function handleError(error: unknown, target: typeof readError) {
  const detail = message(error);
  if (error instanceof CommerceError && (error.status === 401 || error.status === 403)) {
    emit('accessLost', detail);
    return;
  }
  target.value = detail;
}

async function read(action: (signal: AbortSignal) => Promise<void>, retry: () => void) {
  readTask?.abort();
  const request = new AbortController();
  readTask = request;
  retryRead = retry;
  loading.value = true;
  readError.value = '';
  try {
    await action(request.signal);
  } catch (error) {
    if (!request.signal.aborted) handleError(error, readError);
  } finally {
    if (readTask === request) loading.value = false;
  }
}

function loadOverview() {
  source.value = null;
  overview.value = null;
  orders.value = null;
  group.value = null;
  cursor.value = '0';
  void read(async signal => {
    const [summary, page] = await Promise.all([
      commerceApi<Overview>('/overview', signal, applied),
      commerceApi<Page<Order>>('/orders', signal, { ...applied, limit: String(pageSize) }),
    ]);
    if (!signal.aborted) {
      overview.value = summary;
      orders.value = page;
    }
  }, loadOverview);
}

function searchOrders() {
  applied = { ...filters.value };
  loadOverview();
}

function loadOrders(next: string, selected: OrderGroup | null = group.value) {
  source.value = null;
  orders.value = null;
  group.value = selected;
  cursor.value = next;
  const groupFilter: Record<string, string> = selected ? { status: selected.status, currency: selected.currency } : {};
  void read(async signal => {
    const result = await commerceApi<Page<Order>>('/orders', signal, {
      ...applied, ...groupFilter, cursor: next, limit: String(pageSize),
    });
    if (!signal.aborted) orders.value = result;
  }, () => loadOrders(next, selected));
}

async function drill(selected: OrderGroup) {
  loadOrders('0', selected);
  await nextTick();
  orderHeading.value?.focus();
}

function loadMembers(next = '0') {
  members.value = null;
  cursor.value = next;
  void read(async signal => {
    const result = await commerceApi<Page<Member>>('/members', signal, {
      ...appliedMember, cursor: next, limit: String(pageSize),
    });
    if (!signal.aborted) members.value = result;
  }, () => loadMembers(next));
}

function searchMembers() {
  appliedMember = { ...memberFilters.value };
  loadMembers();
}

function loadSource(id: string) {
  source.value = null;
  void read(async signal => {
    const result = await commerceApi<Receipt>('/imports/' + encodeURIComponent(id), signal);
    if (!signal.aborted) source.value = result;
  }, () => loadSource(id));
}

function selectTab(next: Tab) {
  if (tab.value === next) return;
  tab.value = next;
  readTask?.abort();
  retryRead = undefined;
  loading.value = false;
  readError.value = '';
  if (next === 'overview') loadOverview();
  if (next === 'members') loadMembers();
}

function chooseFile(event: Event) {
  file.value = (event.target as HTMLInputElement).files?.[0] ?? null;
  importError.value = '';
  receipt.value = null;
}

async function importFile() {
  if (!file.value || importing.value) return;
  receipt.value = null;
  importError.value = '';
  if (file.value.size > 1024 * 1024) {
    importError.value = '文件大小上限为 1 MiB';
    return;
  }
  const data = new FormData();
  data.append('file', file.value);
  const request = new AbortController();
  importTask = request;
  importing.value = true;
  try {
    const result = await commerceApi<Receipt>('/imports', request.signal, {}, data);
    if (!request.signal.aborted) {
      receipt.value = result;
      if (tab.value === 'overview') loadOverview();
      if (tab.value === 'members') loadMembers();
    }
  } catch (error) {
    if (!request.signal.aborted) handleError(error, importError);
  } finally {
    importing.value = false;
  }
}

function previous() { return String(Math.max(0, Number(cursor.value) - pageSize)); }
onMounted(loadOverview);
onBeforeUnmount(() => {
  readTask?.abort();
  importTask?.abort();
});
</script>

<template>
  <div class="commerce-workspace" :aria-busy="loading">
    <header class="page-heading">
      <div>
        <h1>{{ tabs[tab] }}</h1>
        <p v-if="tab === 'overview'" class="muted">按上海下单日、订单状态和币种核对原始订单金额。</p>
        <p v-else-if="tab === 'imports'" class="muted">上传 UTF-8 JSON。每批最多 500 条会员及订单记录，文件上限 1 MiB。</p>
      </div>
      <button v-if="tab === 'overview'" type="button" class="primary" @click="selectTab('imports')">导入文件</button>
    </header>

    <nav class="commerce-tabs" aria-label="商城经营">
      <button v-for="(label, key) in tabs" :key="key" type="button" :class="{ primary: tab === key }"
        :aria-pressed="tab === key" @click="selectTab(key)">{{ label }}</button>
    </nav>
    <p v-if="loading" role="status" class="muted commerce-feedback">正在加载…</p>
    <div v-if="readError" class="alert error commerce-feedback">
      <p role="alert">{{ readError }}</p>
      <button v-if="retryRead" type="button" @click="retryRead()">重试</button>
    </div>

    <template v-if="tab === 'overview'">
      <section class="data-panel commerce-panel" aria-label="订单汇总">
        <form class="commerce-filters" @submit.prevent="searchOrders">
          <label>开始日期<input v-model="filters.from" type="date"></label>
          <label>结束日期<input v-model="filters.to" type="date" :min="filters.from || undefined"></label>
          <label>客户 ID<input v-model.trim="filters.customerId" maxlength="200"></label>
          <label>订单 ID<input v-model.trim="filters.externalOrderId" maxlength="200"></label>
          <button class="primary">查询</button>
        </form>
        <div v-if="overview" class="commerce-summary">
          <p v-if="!overview.orderCount" class="empty-state commerce-empty">没有符合条件的订单。</p>
          <template v-else>
            <p class="commerce-total"><strong>{{ overview.orderCount }}</strong> 笔订单</p>
            <ul class="commerce-groups">
              <li v-for="item in overview.groups" :key="item.status + item.currency">
                <span class="muted">{{ orderStatuses[item.status] }} · {{ item.currency }}</span>
                <strong>{{ item.amount }}</strong>
                <button type="button" class="text-button"
                  :aria-pressed="group?.status === item.status && group?.currency === item.currency"
                  @click="drill(item)">查看 {{ item.orderCount }} 笔明细</button>
              </li>
            </ul>
          </template>
        </div>
      </section>

      <section v-if="overview?.orderCount" class="data-panel commerce-panel">
        <div class="panel-toolbar">
          <div>
            <h2 ref="orderHeading" tabindex="-1">订单明细</h2>
            <span v-if="group" class="muted">{{ orderStatuses[group.status] }} · {{ group.currency }}</span>
          </div>
          <button v-if="group" type="button" @click="loadOrders('0', null)">全部明细</button>
        </div>
        <template v-if="orders">
          <p v-if="!orders.items.length" class="empty-state commerce-empty">没有符合条件的订单。</p>
          <div v-else class="table-scroll commerce-table" role="region" aria-label="商城订单" tabindex="0">
            <table role="table">
              <thead><tr><th scope="col">订单</th><th scope="col">商城会员</th><th scope="col">下单时间</th>
                <th scope="col">状态</th><th scope="col">原始金额</th><th scope="col">来源</th></tr></thead>
              <tbody>
                <tr v-for="order in orders.items" :key="order.externalOrderId">
                  <th scope="row" data-label="订单">{{ order.externalOrderId }}</th>
                  <td data-label="商城会员">{{ order.externalMemberId ?? '访客' }}</td>
                  <td data-label="下单时间">{{ displayTime(order.orderedAt) }}</td>
                  <td data-label="状态"><span class="badge">{{ orderStatuses[order.status] }}</span></td>
                  <td data-label="原始金额" class="commerce-amount">{{ order.currency }} {{ order.amount }}</td>
                  <td data-label="来源"><button type="button" class="text-button" @click="loadSource(order.importId)">批次 · 第 {{ order.sourceRow }} 条</button></td>
                </tr>
              </tbody>
            </table>
          </div>
          <nav v-if="orders.total > pageSize" class="pagination" aria-label="订单分页">
            <span>共 {{ orders.total }} 条</span>
            <div>
              <button type="button" :disabled="cursor === '0'" @click="loadOrders(previous())">上一页</button>
              <button type="button" :disabled="!orders.nextCursor" @click="orders.nextCursor && loadOrders(orders.nextCursor)">下一页</button>
            </div>
          </nav>
        </template>
        <section v-if="source" class="commerce-source">
          <h3>导入来源</h3>
          <dl><dt>批次 ID</dt><dd>{{ source.id }}</dd><dt>导入时间</dt><dd>{{ displayTime(source.importedAt) }}</dd>
            <dt>文件 SHA-256</dt><dd>{{ source.sha256 }}</dd></dl>
        </section>
      </section>
    </template>

    <section v-else-if="tab === 'members'" class="data-panel commerce-panel" aria-label="商城会员">
      <form class="commerce-filters" @submit.prevent="searchMembers">
        <label>客户 ID<input v-model.trim="memberFilters.customerId" maxlength="200"></label>
        <label>外部会员 ID<input v-model.trim="memberFilters.externalMemberId" maxlength="200"></label>
        <button class="primary">查询</button>
      </form>
      <template v-if="members">
        <p v-if="!members.items.length" class="empty-state commerce-empty">没有符合条件的商城会员。</p>
        <div v-else class="table-scroll commerce-table" role="region" aria-label="商城会员列表" tabindex="0">
          <table role="table">
            <thead><tr><th scope="col">外部会员 ID</th><th scope="col">等级</th><th scope="col">状态</th>
              <th scope="col">加入日期</th><th scope="col">到期日期</th></tr></thead>
            <tbody><tr v-for="member in members.items" :key="member.externalMemberId">
              <th scope="row" data-label="外部会员 ID">{{ member.externalMemberId }}</th><td data-label="等级">{{ member.level || '—' }}</td>
              <td data-label="状态"><span class="badge" :class="{ inactive: member.status !== 'ACTIVE' }">{{ memberStatuses[member.status] }}</span></td>
              <td data-label="加入日期">{{ member.joinedAt ?? '—' }}</td><td data-label="到期日期">{{ member.expiresAt ?? '—' }}</td>
            </tr></tbody>
          </table>
        </div>
        <nav v-if="members.total > pageSize" class="pagination" aria-label="会员分页">
          <span>共 {{ members.total }} 条</span>
          <div>
            <button type="button" :disabled="cursor === '0'" @click="loadMembers(previous())">上一页</button>
            <button type="button" :disabled="!members.nextCursor" @click="members.nextCursor && loadMembers(members.nextCursor)">下一页</button>
          </div>
        </nav>
      </template>
    </section>

    <section v-else class="data-panel commerce-panel commerce-import" aria-label="商城文件导入">
      <a class="text-button" href="/commerce-import-example.json" download>下载导入示例</a>
      <form class="commerce-upload" @submit.prevent="importFile">
        <label>商城文件<input type="file" accept=".json,application/json" required :disabled="importing" @change="chooseFile"></label>
        <button class="primary" :disabled="!file || importing">{{ importing ? '正在导入…' : '开始导入' }}</button>
      </form>
      <p v-if="importError" class="alert error" role="alert">{{ importError }}</p>
      <section v-if="receipt" class="commerce-source" role="status">
        <h2>{{ receipt.replayed ? '此文件此前已导入' : '导入完成' }}</h2>
        <dl>
          <dt>批次 ID</dt><dd>{{ receipt.id }}</dd>
          <dt>会员</dt><dd>应用 {{ receipt.members.applied }} · 相同 {{ receipt.members.unchanged }} · 旧版 {{ receipt.members.stale }}</dd>
          <dt>订单</dt><dd>应用 {{ receipt.orders.applied }} · 相同 {{ receipt.orders.unchanged }} · 旧版 {{ receipt.orders.stale }}</dd>
        </dl>
        <button type="button" @click="selectTab('overview')">查看经营概览</button>
      </section>
    </section>
  </div>
</template>
