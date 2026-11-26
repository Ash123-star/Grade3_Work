<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter, type LocationQueryRaw } from 'vue-router';
import * as api from './api';
import { displayDate, isCursor, isId, isKind, isType, kinds, labels, searchLimit, typeLabels,
  type CustomerDetail, type CustomerPage, type CustomerType, type RelatedRecord } from './contract';
import CrmSection from './CrmSection.vue';

const route = useRoute(), router = useRouter();
const token = ref<string | null>(null), user = ref<Awaited<ReturnType<typeof api.currentUser>> | null>(null);
const ready = ref(false), signingIn = ref(false), authError = ref('');
const account = ref(''), password = ref('');
const search = ref(''), type = ref<CustomerType | ''>('');
const page = ref<CustomerPage | null>(null), customer = ref<CustomerDetail | null>(null), record = ref<RelatedRecord | null>(null);
const loading = ref(false), problem = ref<'denied' | 'missing' | 'failed' | null>(null);
const main = ref<HTMLElement | null>(null);
let authRequest: AbortController | undefined, dataRequest: AbortController | undefined;

const readSearch = (value: unknown) => typeof value === 'string' ? value.trim().slice(0, searchLimit) : '';
const filters = computed<{ search: string; type: CustomerType | ''; cursor?: string }>(() => ({ search: readSearch(route.query.search), type: isType(route.query.type) ? route.query.type : '', cursor: isCursor(route.query.cursor) ? route.query.cursor : undefined }));
const queryFor = (terms: { search: string; type: CustomerType | ''; cursor?: string | null }): LocationQueryRaw => ({
  ...(terms.search ? { search: terms.search } : {}), ...(terms.type ? { type: terms.type } : {}), ...(terms.cursor ? { cursor: terms.cursor } : {}),
});
const currentQuery = computed(() => queryFor(filters.value));
const sectionKind = computed(() => isKind(route.params.kind) ? route.params.kind : null);
const showList = computed(() => route.name === 'crm-list');
const listLink = computed(() => ({ name: 'crm-list', query: currentQuery.value }));
const backLink = computed(() => route.name === 'crm-record' && isId(route.params.customerId)
  ? { name: 'crm-customer', params: { customerId: route.params.customerId }, query: currentQuery.value }
  : listLink.value);
const hasFilters = computed(() => !!(filters.value.search || filters.value.type));
const credentialsRequired = (value: Awaited<ReturnType<typeof api.currentUser>>) => value.status !== 'ACTIVE'
  ? '账号尚未启用或归属未确认，请联系管理员。'
  : value.mustChange ? '请先在 App 完成首次密码修改，再登录客户工作台。' : '';

function clearData() {
  dataRequest?.abort(); dataRequest = undefined;
  page.value = null; customer.value = null; record.value = null;
  loading.value = false; problem.value = null;
}
function clearSession(message = '') {
  clearData(); token.value = null; user.value = null; password.value = '';
  sessionStorage.removeItem(api.tokenKey); authError.value = message;
}
function accept(session: string, identity: Awaited<ReturnType<typeof api.currentUser>>) {
  const blocked = credentialsRequired(identity);
  if (blocked) { clearSession(blocked); return; }
  sessionStorage.setItem(api.tokenKey, session);
  user.value = identity; token.value = session; authError.value = '';
}
async function restore() {
  document.title = '客户工作台 · 潘多拉';
  const saved = sessionStorage.getItem(api.tokenKey);
  if (!saved) { ready.value = true; return; }
  const controller = new AbortController(); authRequest = controller;
  try {
    const identity = await api.currentUser(saved, controller.signal);
    if (!controller.signal.aborted) accept(saved, identity);
  } catch (error) {
    if (!controller.signal.aborted) clearSession(error instanceof api.RequestError && error.status === 401 ? '登录已失效，请重新登录。' : '无法恢复会话，请重新登录。');
  } finally { if (!controller.signal.aborted) ready.value = true; }
}
async function signIn() {
  if (signingIn.value) return;
  authRequest?.abort(); const controller = new AbortController(); authRequest = controller;
  signingIn.value = true; authError.value = '';
  try {
    const session = await api.login(account.value.trim(), password.value, controller.signal);
    if (!controller.signal.aborted) accept(session.token, session.user);
  } catch (error) {
    if (!controller.signal.aborted) authError.value = error instanceof api.RequestError && [400, 401, 403].includes(error.status)
      ? '无法登录，请检查账号、密码和账号状态。' : '暂时无法登录，请稍后重试。';
  } finally { if (!controller.signal.aborted) { signingIn.value = false; password.value = ''; } }
}
async function signOut() {
  const session = token.value;
  authRequest?.abort(); clearSession(); account.value = '';
  if (!session) return;
  try { await api.logout(session, AbortSignal.timeout(8000)); } catch { /* Local credentials and customer data are already gone. */ }
}
async function load() {
  clearData();
  const session = token.value;
  if (!session || route.name == null) return;
  const customerId = route.params.customerId, kind = sectionKind.value, recordId = route.params.recordId;
  if (!showList.value && (!isId(customerId) || (route.name === 'crm-record' && (!kind || !isId(recordId))))) { problem.value = 'missing'; return; }
  const controller = new AbortController(); dataRequest = controller; loading.value = true;
  const current = () => dataRequest === controller && token.value === session && !controller.signal.aborted;
  try {
    if (showList.value) {
      const value = await api.customers(session, { ...filters.value, type: filters.value.type || undefined }, controller.signal);
      if (current()) page.value = value;
    } else if (route.name === 'crm-record' && isId(customerId) && kind && isId(recordId)) {
      const value = await api.relatedRecord(session, customerId, kind, recordId, controller.signal);
      if (current()) record.value = value;
    } else if (route.name === 'crm-customer' && isId(customerId)) {
      const value = await api.customer(session, customerId, controller.signal);
      if (current()) customer.value = value;
    } else if (current()) problem.value = 'missing';
  } catch (error) {
    if (!current()) return;
    const status = error instanceof api.RequestError ? error.status : 0;
    if (status === 401) clearSession('登录已失效，请重新登录。');
    else problem.value = status === 403 ? 'denied' : status === 404 && !showList.value ? 'missing' : 'failed';
  } finally { if (current()) { loading.value = false; dataRequest = undefined; } }
}
function applyFilters() {
  const query = queryFor({ search: readSearch(search.value), type: type.value });
  search.value = readSearch(search.value);
  const target = { name: 'crm-list', query };
  if (router.resolve(target).fullPath === route.fullPath) void load();
  else void router.push(target);
}
function resetFilters() {
  search.value = ''; type.value = '';
  void router.push({ name: 'crm-list' });
}
watch(() => [route.fullPath, token.value], () => {
  search.value = filters.value.search; type.value = filters.value.type;
  void load();
}, { immediate: true });
watch(() => route.path, async () => { await nextTick(); main.value?.focus(); });
onMounted(() => { void restore(); });
onBeforeUnmount(() => { authRequest?.abort(); dataRequest?.abort(); });
</script>

<template>
  <div class="crm">
    <a class="crm-skip" href="#crm-content">跳到主要内容</a>
    <header class="crm-header">
      <div class="crm-container crm-header-inner">
        <RouterLink :to="listLink" class="crm-brand" aria-label="客户工作台首页">
          <span class="crm-mark" aria-hidden="true">P</span>
          <span><span class="crm-brand-name">潘多拉</span><span class="crm-brand-sub">客户工作台</span></span>
        </RouterLink>
        <div v-if="user" class="crm-account"><span>{{ user.name }}</span><button type="button" class="crm-button crm-button-quiet" @click="signOut">退出登录</button></div>
      </div>
    </header>
    <main id="crm-content" ref="main" tabindex="-1" class="crm-container crm-main">
      <p v-if="!ready" class="crm-panel crm-state" role="status">正在恢复登录…</p>
      <section v-else-if="!user" class="crm-panel crm-login" aria-labelledby="crm-login-title">
        <p class="crm-kicker">客户资料与关联业务</p>
        <h1 id="crm-login-title">登录客户工作台</h1>
        <p>使用企业账号登录，查看已授权的客户与服务记录。</p>
        <form class="crm-login-form" @submit.prevent="signIn">
          <label for="crm-account">账号</label><input id="crm-account" v-model="account" required maxlength="64" autocomplete="username" :disabled="signingIn">
          <label for="crm-password">密码</label><input id="crm-password" v-model="password" required type="password" autocomplete="current-password" :disabled="signingIn">
          <p v-if="authError" class="crm-error" role="alert">{{ authError }}</p>
          <button type="submit" class="crm-button crm-button-primary" :disabled="signingIn">{{ signingIn ? '正在登录…' : '登录' }}</button>
        </form>
        <a href="/">返回管理员后台入口</a>
      </section>
      <template v-else>
        <nav v-if="!showList" aria-label="返回路径" class="crm-breadcrumb">
          <RouterLink :to="backLink">← {{ route.name === 'crm-record' ? '返回客户详情' : '返回客户目录' }}</RouterLink>
        </nav>
        <section v-if="showList" aria-labelledby="crm-list-title" class="crm-heading">
          <p class="crm-kicker">客户管理</p><h1 id="crm-list-title">客户目录</h1><p>按客户名称与类型查找，查看相关会员、活动和服务。</p>
        </section>
        <form v-if="showList" class="crm-panel crm-filters" aria-label="筛选客户" @submit.prevent="applyFilters">
          <div><label for="crm-search">关键词</label><input id="crm-search" v-model="search" type="search" :maxlength="searchLimit" placeholder="搜索客户名称"></div>
          <div><label for="crm-type">客户类型</label><select id="crm-type" v-model="type"><option value="">全部类型</option><option v-for="(label, value) in typeLabels" :key="value" :value="value">{{ label }}</option></select></div>
          <div class="crm-actions"><button type="submit" class="crm-button crm-button-primary">搜索</button><button type="button" class="crm-button crm-button-quiet" @click="resetFilters">清空条件</button></div>
        </form>
        <p v-if="loading" class="crm-panel crm-state" role="status">正在读取{{ showList ? '客户目录' : '资料' }}…</p>
        <section v-else-if="problem" class="crm-panel crm-state" role="alert">
          <h2>{{ problem === 'denied' ? '无权查看此内容' : problem === 'missing' ? '找不到此记录' : '暂时无法读取' }}</h2>
          <p>{{ problem === 'denied' ? '如需访问，请联系业务管理员确认授权。' : problem === 'missing' ? '记录可能已移除或未向你开放。' : '客户服务可能暂未接入或暂不可用，请稍后重试。' }}</p>
          <button v-if="problem === 'failed'" type="button" class="crm-button crm-button-primary" @click="load">重试</button>
        </section>
        <section v-else-if="page" class="crm-panel crm-customer-list" aria-labelledby="crm-results">
          <div class="crm-section-head"><h2 id="crm-results">查询结果</h2><p class="crm-count" role="status">共 {{ page.total }} 位客户</p></div>
          <div v-if="!page.items.length" class="crm-state"><h3>{{ hasFilters ? '没有符合条件的客户' : '暂无可查看的客户' }}</h3>
            <p>{{ hasFilters ? '试试更短的关键词，或清空筛选条件。' : '可访问的客户资料会出现在这里。' }}</p>
            <button v-if="hasFilters" type="button" class="crm-button crm-button-quiet" @click="resetFilters">查看全部客户</button>
          </div>
          <ul v-else class="crm-list">
            <li v-for="item in page.items" :key="item.id">
              <RouterLink class="crm-person" :to="{ name: 'crm-customer', params: { customerId: item.id }, query: currentQuery }">
                <span class="crm-person-icon" :class="{ 'crm-enterprise': item.type === 'COMPANY' }" aria-hidden="true">{{ item.type === 'COMPANY' ? '企' : '人' }}</span>
                <span class="crm-person-main"><strong>{{ item.name }}</strong><span>{{ typeLabels[item.type] }}<template v-if="item.ownerName"> · 负责人：{{ item.ownerName }}</template></span></span>
                <span v-if="displayDate(item.updatedAt)" class="crm-person-date">更新于 {{ displayDate(item.updatedAt) }}</span>
                <span class="crm-arrow" aria-hidden="true">›</span>
              </RouterLink>
            </li>
          </ul>
          <nav v-if="page.previousCursor || page.nextCursor" class="crm-pagination" aria-label="客户分页">
            <RouterLink v-if="page.previousCursor" class="crm-button crm-button-quiet" :to="{ name: 'crm-list', query: queryFor({ ...filters, cursor: page.previousCursor }) }">上一页</RouterLink>
            <RouterLink v-if="page.nextCursor" class="crm-button crm-button-quiet" :to="{ name: 'crm-list', query: queryFor({ ...filters, cursor: page.nextCursor }) }">下一页</RouterLink>
          </nav>
        </section>
        <template v-else-if="customer">
          <section class="crm-panel crm-profile" aria-labelledby="crm-customer-title">
            <p class="crm-kicker">{{ typeLabels[customer.type] }}</p><h1 id="crm-customer-title">{{ customer.name }}</h1>
            <dl v-if="customer.ownerName || customer.contactName || customer.contactPhone || customer.contactEmail || displayDate(customer.updatedAt)" class="crm-facts">
              <div v-if="customer.ownerName"><dt>负责人</dt><dd>{{ customer.ownerName }}</dd></div>
              <div v-if="customer.contactName"><dt>联系人</dt><dd>{{ customer.contactName }}</dd></div>
              <div v-if="customer.contactPhone"><dt>联系电话</dt><dd>{{ customer.contactPhone }}</dd></div>
              <div v-if="customer.contactEmail"><dt>联系邮箱</dt><dd>{{ customer.contactEmail }}</dd></div>
              <div v-if="displayDate(customer.updatedAt)"><dt>最近更新</dt><dd>{{ displayDate(customer.updatedAt) }}</dd></div>
            </dl>
          </section>
          <div class="crm-detail-grid">
            <CrmSection v-for="kind in kinds" :key="kind" :kind="kind" :section="customer.sections[kind]" :customer-id="customer.id" :query="currentQuery" />
          </div>
        </template>
        <section v-else-if="record && sectionKind" class="crm-panel crm-profile" aria-labelledby="crm-record-title">
          <p class="crm-kicker">{{ labels[sectionKind] }}</p><h1 id="crm-record-title">{{ record.title }}</h1>
          <dl class="crm-facts">
            <div v-if="record.status"><dt>状态</dt><dd>{{ record.status }}</dd></div>
            <div v-if="displayDate(record.businessDate)"><dt>业务日期</dt><dd>{{ displayDate(record.businessDate) }}</dd></div>
            <div v-if="displayDate(record.validFrom)"><dt>生效日期</dt><dd>{{ displayDate(record.validFrom) }}</dd></div>
            <div v-if="displayDate(record.validTo)"><dt>到期日期</dt><dd>{{ displayDate(record.validTo) }}</dd></div>
            <div v-if="record.usageText"><dt>使用情况</dt><dd>{{ record.usageText }}</dd></div>
            <div v-if="record.amountText"><dt>订单金额</dt><dd>{{ record.amountText }}</dd></div>
            <div v-if="record.ownerName"><dt>负责人</dt><dd>{{ record.ownerName }}</dd></div>
            <div v-if="record.participantNames?.length"><dt>参与人员</dt><dd>{{ record.participantNames.join('、') }}</dd></div>
          </dl>
          <div v-if="record.description" class="crm-description"><h2>记录说明</h2><p>{{ record.description }}</p></div>
        </section>
      </template>
    </main>
  </div>
</template>
