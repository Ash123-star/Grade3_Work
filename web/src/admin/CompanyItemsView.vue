<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { ElButton, ElInput, ElSelect, ElOption, ElTable, ElTableColumn, ElTag, ElPagination, ElDrawer, ElForm, ElFormItem, ElSwitch, ElInputNumber, ElAlert, ElEmpty, ElIcon, ElMessage, type FormInstance } from 'element-plus';
import { Plus, Search, Refresh, Clock, EditPen, Top, View, OfficeBuilding } from '@element-plus/icons-vue';
import { api, errorMessage, type CompanyItem, type Page } from './api';
import ReviewDrawer from './ReviewDrawer.vue';
const rows = ref<CompanyItem[]>([]), preview = ref<CompanyItem[]>([]), pinnedCount = ref(0), total = ref(0), page = ref(1), search = ref(''), archived = ref('false'), loading = ref(false), saving = ref(false), error = ref(''), editError = ref('');
const drawer = ref(false), records = ref(false), formRef = ref<FormInstance>(), reason = ref(''), detailLoading = ref(false), detailFailed = ref(false);
const blank = (): CompanyItem => ({ title: '', text: '', pinned: false, archived: false, position: 0, version: 0 });
const form = ref<CompanyItem>(blank());
let generation = 0, detailGeneration = 0;
async function load() {
  const ticket = ++generation; loading.value = true; error.value = '';
  try { const result = await api<Page<CompanyItem> & { pinnedCount: number; preview: CompanyItem[] }>('/items', { query: { search: search.value, archived: archived.value, cursor: (page.value - 1) * 20, limit: 20 } }); if (ticket === generation) { rows.value = result.items; total.value = result.total; pinnedCount.value = result.pinnedCount; preview.value = result.preview; } }
  catch (e) { if (ticket === generation) error.value = errorMessage(e); } finally { if (ticket === generation) loading.value = false; }
}
function filter() { page.value = 1; void load(); }
async function edit(row?: Pick<CompanyItem, 'id'> | Record<string, unknown>) {
  const ticket = ++detailGeneration; editError.value = ''; reason.value = ''; form.value = blank(); detailFailed.value = false; detailLoading.value = false; drawer.value = true;
  if (!row?.id) return;
  detailLoading.value = true;
  try { const result = await api<CompanyItem>(`/items/${row.id}`); if (ticket === detailGeneration && drawer.value) form.value = result; }
  catch (e) { if (ticket === detailGeneration) { editError.value = errorMessage(e); detailFailed.value = true; } }
  finally { if (ticket === detailGeneration) detailLoading.value = false; }
}
async function save() {
  if (saving.value || detailLoading.value || detailFailed.value || !await formRef.value?.validate().catch(() => false)) return;
  if (!reason.value.trim()) { editError.value = '请填写修改理由'; return; }
  saving.value = true; editError.value = '';
  try { await api('/items/revisions', { method: 'POST', body: { ...form.value, title: form.value.title.trim(), reason: reason.value.trim() } }); ElMessage.success('事项已提交审核，审核通过后更新公司展示'); drawer.value = false; await load(); }
  catch (e) { editError.value = errorMessage(e); } finally { saving.value = false; }
}
onMounted(load); onBeforeUnmount(() => { generation++; detailGeneration++; });
</script>
<template>
  <section class="management-page">
    <div class="page-heading"><div><p class="eyebrow">COMPANY / PRIORITIES</p><h1>公司十大重要事项</h1><p class="muted">让重要的事情被看见，让公司的方向始终清晰。</p></div><div class="heading-actions"><ElButton :icon="Clock" @click="records = true">修改与审核记录</ElButton><ElButton type="primary" :icon="Plus" @click="edit()">新增事项</ElButton></div></div>
    <div class="section-banner priorities-banner"><div class="banner-icon"><ElIcon><OfficeBuilding /></ElIcon></div><div><strong>公司的重要事项，统一维护</strong><p>最多置顶 10 项，审核通过后同步到员工端</p></div><div class="banner-total"><strong>{{ pinnedCount }}<small> / 10</small></strong><span>已置顶事项</span></div></div>
    <ElAlert v-if="error" :title="error" type="error" :closable="false" show-icon role="alert" class="page-alert" />
    <div class="items-layout"><div class="data-panel"><form class="filter-toolbar" @submit.prevent="filter"><ElInput v-model="search" :prefix-icon="Search" placeholder="搜索事项标题或内容" aria-label="搜索公司事项" maxlength="100" clearable class="search-field" @clear="filter" /><ElSelect v-model="archived" aria-label="事项归档筛选" @change="filter"><ElOption label="生效事项" value="false" /><ElOption label="已归档" value="true" /><ElOption label="全部事项" value="all" /></ElSelect><ElButton type="primary" native-type="submit" :icon="Search" :loading="loading">查询</ElButton><ElButton :icon="Refresh" aria-label="刷新事项列表" :disabled="loading" @click="load" /></form>
      <ElTable :data="rows" row-key="id" stripe :aria-busy="loading"><ElTableColumn label="事项" min-width="245"><template #default="{ row }"><div class="item-title"><ElIcon v-if="row.pinned" class="pin-icon"><Top /></ElIcon><strong>{{ row.title }}</strong></div><p class="item-excerpt">{{ row.text || '暂无说明' }}</p></template></ElTableColumn><ElTableColumn label="排序" prop="position" width="75" /><ElTableColumn label="展示" width="100"><template #default="{ row }"><ElTag :type="row.archived ? 'info' : row.pinned ? 'warning' : 'success'" effect="light">{{ row.archived ? '已归档' : row.pinned ? '已置顶' : '普通展示' }}</ElTag></template></ElTableColumn><ElTableColumn label="操作" width="95" fixed="right"><template #default="{ row }"><ElButton type="primary" link :icon="EditPen" :disabled="row.archived" @click="edit(row)">编辑</ElButton></template></ElTableColumn><template #empty><ElEmpty :image-size="80" :description="loading ? '正在读取公司事项…' : error ? '读取失败，请刷新重试' : '暂无事项，点击新增开始维护'" /></template></ElTable><div class="table-footer"><span>共 {{ total }} 条事项</span><ElPagination v-model:current-page="page" :total="total" :page-size="20" layout="prev, pager, next" @current-change="load" /></div></div>
      <aside class="preview-panel"><div class="preview-heading"><ElIcon><View /></ElIcon><h2>员工端展示预览</h2><span>生效版本</span></div><p class="muted preview-caption">按置顶和排序位置展示前十项</p><ol v-if="preview.length" class="priority-preview"><li v-for="(item, index) in preview" :key="item.id"><span class="priority-index">{{ String(index + 1).padStart(2, '0') }}</span><div><strong>{{ item.title }}</strong><p>{{ item.text || '暂无说明' }}</p></div></li></ol><ElEmpty v-else description="尚无生效事项" :image-size="70" /><div class="preview-foot"><span class="online-dot" />与员工端使用相同的已发布内容</div></aside>
    </div><p class="page-note"><ElIcon><Clock /></ElIcon>修改先生成候选版本，审核前员工看到的内容保持不变。</p>
    <ElDrawer v-model="drawer" :title="form.id ? '编辑公司重要事项' : '新增公司重要事项'" size="min(620px, 100%)" class="management-drawer" :close-on-click-modal="!saving" :close-on-press-escape="!saving" :show-close="!saving" @closed="detailGeneration++">
      <ElAlert v-if="editError" :title="editError" type="error" show-icon :closable="false" role="alert" /><ElAlert title="保存后提交独立审核，审核通过后才更新展示。" type="info" show-icon :closable="false" />
      <p v-if="detailLoading" role="status">正在读取事项详情…</p>
      <ElForm ref="formRef" :model="form" label-position="top" :disabled="saving || detailLoading || detailFailed" @submit.prevent="save"><ElFormItem label="事项标题" prop="title" :rules="[{ required: true, whitespace: true, message: '请填写事项标题', trigger: 'blur' }]"><ElInput v-model="form.title" maxlength="200" show-word-limit placeholder="简洁描述这件重要的事" /></ElFormItem><ElFormItem label="事项内容"><ElInput v-model="form.text" type="textarea" :rows="7" maxlength="20000" show-word-limit placeholder="填写目标、关键内容或需要全员知晓的信息" /></ElFormItem><div class="form-grid"><ElFormItem label="排序位置"><ElInputNumber v-model="form.position" :min="0" :max="10000" :precision="0" /></ElFormItem><ElFormItem label="置顶展示"><ElSwitch v-model="form.pinned" active-text="置顶" aria-label="置顶展示" /><small class="muted">当前 {{ pinnedCount }}/10 项置顶</small></ElFormItem></div><div v-if="form.id" class="switch-field archive-field"><div><strong>归档事项</strong><small>审核通过后从员工端展示中移除，保留历史</small></div><ElSwitch v-model="form.archived" aria-label="归档事项" /></div><ElFormItem label="修改理由" required><ElInput v-model="reason" type="textarea" :rows="3" maxlength="2000" show-word-limit placeholder="说明新增或调整的原因" /></ElFormItem></ElForm>
      <template #footer><ElButton :disabled="saving" @click="drawer = false">取消</ElButton><ElButton type="primary" :loading="saving" :disabled="detailLoading || detailFailed" @click="save">提交事项审核</ElButton></template>
    </ElDrawer><ReviewDrawer v-model="records" category="items" @changed="load" />
  </section>
</template>
