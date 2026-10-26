<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { ElButton, ElIcon, ElInput, ElSelect, ElOption, ElTable, ElTableColumn, ElTag, ElPagination, ElDrawer, ElForm, ElFormItem, ElSwitch, ElAlert, ElEmpty, ElMessage, type FormInstance } from 'element-plus';
import { Search, Refresh, EditPen, Clock, User, ArrowRight } from '@element-plus/icons-vue';
import { api, errorMessage, roles, statuses, type Account, type Option, type Page } from './api';
import ReviewDrawer from './ReviewDrawer.vue';
const rows = ref<Account[]>([]), total = ref(0), page = ref(1), search = ref(''), status = ref(''), department = ref(''), loading = ref(false), saving = ref(false), error = ref(''), editError = ref('');
const options = ref<{ departments: Option[]; teams: Option[]; managers: Option[] }>({ departments: [], teams: [], managers: [] });
const drawer = ref(false), records = ref(false), current = ref<Account | null>(null), formRef = ref<FormInstance>();
const form = ref({ name: '', departmentId: '', teamId: '', managerId: '', role: 'EMPLOYEE', status: 'ACTIVE', dispatchEnabled: false, reason: '' });
let generation = 0, detailGeneration = 0;
const teams = computed(() => options.value.teams.filter(team => team.department_id === form.value.departmentId));
const pendingMembership = computed(() => current.value?.status === 'PENDING' && !!current.value.pendingReviews?.length);
async function load() {
  const ticket = ++generation; loading.value = true; error.value = '';
  try { const result = await api<Page<Account>>('/accounts', { query: { search: search.value, status: status.value, departmentId: department.value, cursor: (page.value - 1) * 20, limit: 20 } }); if (ticket === generation) { rows.value = result.items; total.value = result.total; } }
  catch (e) { if (ticket === generation) error.value = errorMessage(e); } finally { if (ticket === generation) loading.value = false; }
}
function filter() { page.value = 1; void load(); }
async function edit(row: Pick<Account, 'id'> | Record<string, unknown>) {
  const ticket = ++detailGeneration; editError.value = ''; current.value = null; drawer.value = true;
  try { const result = await api<Account>(`/accounts/${row.id}`); if (ticket !== detailGeneration || !drawer.value) return; current.value = result; form.value = { name: result.name, departmentId: result.department_id ?? '', teamId: result.team_id ?? '', managerId: result.manager_id ?? '', role: result.status === 'PENDING' ? 'EMPLOYEE' : result.role, status: result.status === 'PENDING' ? 'ACTIVE' : result.status, dispatchEnabled: result.dispatch_enabled, reason: '' }; }
  catch (e) { if (ticket === detailGeneration) editError.value = errorMessage(e); }
}
async function save() {
  if (!current.value || saving.value || !await formRef.value?.validate().catch(() => false)) return;
  saving.value = true; editError.value = '';
  try { await api(`/accounts/${current.value.id}/revisions`, { method: 'POST', body: { ...form.value, name: form.value.name.trim(), reason: form.value.reason.trim(), version: current.value.version } }); ElMessage.success('修改已提交审核，审核通过前当前信息保持不变'); drawer.value = false; await load(); }
  catch (e) { editError.value = errorMessage(e); } finally { saving.value = false; }
}
onMounted(async () => { void load(); try { options.value = await api('/options'); } catch (e) { error.value = errorMessage(e); } });
onBeforeUnmount(() => { generation++; detailGeneration++; });
</script>

<template>
  <section class="management-page">
    <div class="page-heading"><div><p class="eyebrow">ORGANIZATION / ACCOUNTS</p><h1>账号管理<span class="heading-chip">组织与成员</span></h1><p class="muted">集中维护公司成员信息，让每个账号各归其位。</p></div><ElButton :icon="Clock" @click="records = true">修改与审核记录</ElButton></div>
    <div class="section-banner"><div class="banner-icon"><ElIcon><User /></ElIcon></div><div><strong>全部公司账号</strong><p>包含已启用、待确认及已停用的成员</p></div><div class="banner-total"><strong>{{ total }}</strong><span>{{ search || status || department ? '个匹配账号' : '个账号' }}</span></div></div>
    <ElAlert v-if="error" :title="error" type="error" show-icon :closable="false" role="alert" class="page-alert" />
    <div class="data-panel">
      <form class="filter-toolbar" @submit.prevent="filter"><ElInput v-model="search" :prefix-icon="Search" placeholder="搜索姓名或登录账号" aria-label="搜索账号" maxlength="100" clearable class="search-field" @clear="filter" /><ElSelect v-model="department" placeholder="全部部门" aria-label="部门筛选" clearable @change="filter"><ElOption v-for="item in options.departments" :key="item.id" :label="item.name" :value="item.id" /></ElSelect><ElSelect v-model="status" placeholder="全部状态" aria-label="状态筛选" clearable @change="filter"><ElOption v-for="value in ['ACTIVE', 'PENDING', 'DISABLED']" :key="value" :label="statuses[value]" :value="value" /></ElSelect><ElButton native-type="submit" type="primary" :icon="Search" :loading="loading">查询</ElButton><ElButton :icon="Refresh" aria-label="刷新账号列表" :disabled="loading" @click="load" /></form>
      <ElTable :data="rows" row-key="id" stripe @row-click="edit" class="account-table clickable-table" :aria-busy="loading">
        <ElTableColumn label="成员" min-width="210"><template #default="{ row }"><div class="member-cell"><span class="member-avatar">{{ row.name?.slice(0, 1) }}</span><div><strong>{{ row.name }}</strong><small>{{ row.account }}</small></div></div></template></ElTableColumn>
        <ElTableColumn label="所属组织" min-width="160"><template #default="{ row }"><span>{{ row.department || '尚未分配部门' }}</span><small class="cell-subtitle">{{ row.team || '—' }}</small></template></ElTableColumn>
        <ElTableColumn label="角色" width="125"><template #default="{ row }"><span class="role-badge" :class="{ 'role-admin': row.role === 'ADMIN' }">{{ roles[row.role] ?? row.role }}</span></template></ElTableColumn>
        <ElTableColumn prop="phone" label="手机号" min-width="140" />
        <ElTableColumn label="账号状态" width="120"><template #default="{ row }"><span class="status-label" :class="row.status.toLowerCase()"><i />{{ statuses[row.status] }}</span></template></ElTableColumn>
        <ElTableColumn label="操作" width="100" fixed="right"><template #default="{ row }"><ElButton link type="primary" :icon="EditPen" @click.stop="edit(row)">编辑</ElButton></template></ElTableColumn>
        <template #empty><ElEmpty :image-size="80" :description="loading ? '正在读取公司账号…' : error ? '读取失败，请刷新重试' : '没有匹配的账号，试试调整筛选条件'" /></template>
      </ElTable>
      <div class="table-footer"><span>共 {{ total }} 个账号<span v-if="loading" role="status"> · 正在加载…</span></span><ElPagination v-model:current-page="page" :total="total" :page-size="20" layout="prev, pager, next" @current-change="load" /></div>
    </div><p class="page-note"><ElIcon><Clock /></ElIcon>组织、角色与账号状态的修改，经独立审核后生效。</p>
    <ElDrawer v-model="drawer" title="编辑账号信息" size="min(580px, 100%)" class="management-drawer" :close-on-click-modal="!saving" :close-on-press-escape="!saving" :show-close="!saving" @closed="detailGeneration++; current = null">
      <ElAlert v-if="editError" :title="editError" type="error" show-icon :closable="false" role="alert" />
      <template v-if="current"><div class="drawer-member"><span class="member-avatar large">{{ current.name.slice(0, 1) }}</span><div><h2>{{ current.name }}</h2><span class="muted">{{ current.account }} · 当前版本 {{ current.version }}</span></div></div>
        <ElAlert v-if="pendingMembership" title="该成员已有归属申请，请在修改与审核记录中处理。" type="warning" :closable="false"><ElButton link type="primary" @click="drawer = false; records = true">查看申请<ElIcon><ArrowRight /></ElIcon></ElButton></ElAlert>
        <ElForm ref="formRef" :model="form" label-position="top" @submit.prevent="save" :disabled="saving || pendingMembership">
          <div class="form-grid"><ElFormItem label="姓名" prop="name" :rules="[{ required: true, whitespace: true, message: '请填写姓名', trigger: 'blur' }]"><ElInput v-model="form.name" maxlength="100" /></ElFormItem><ElFormItem label="登录账号"><ElInput :model-value="current.account" disabled /></ElFormItem><ElFormItem label="手机号"><ElInput :model-value="current.phone" disabled /></ElFormItem><ElFormItem label="所属部门" prop="departmentId" :rules="[{ required: current.status === 'PENDING' || form.role === 'DIRECTOR', message: '请选择部门', trigger: 'change' }]"><ElSelect v-model="form.departmentId" clearable filterable @change="form.teamId = ''"><ElOption v-for="item in options.departments" :key="item.id" :label="item.name" :value="item.id" /></ElSelect></ElFormItem><ElFormItem label="所属团队"><ElSelect v-model="form.teamId" clearable filterable><ElOption v-for="item in teams" :key="item.id" :label="item.name" :value="item.id" /></ElSelect></ElFormItem><ElFormItem label="直属上级"><ElSelect v-model="form.managerId" clearable filterable><ElOption v-for="item in options.managers.filter(m => m.id !== current?.id)" :key="item.id" :label="item.name" :value="item.id" /></ElSelect></ElFormItem><ElFormItem label="角色"><ElSelect v-model="form.role" :disabled="current.status === 'PENDING'"><ElOption v-for="(label, value) in roles" :key="value" :label="label" :value="value" /></ElSelect></ElFormItem><ElFormItem label="账号状态"><ElSelect v-model="form.status" :disabled="current.status === 'PENDING'"><ElOption label="已启用" value="ACTIVE" /><ElOption label="已停用" value="DISABLED" /></ElSelect></ElFormItem></div>
          <div class="switch-field"><div><strong>任务派发资格</strong><small>沿用所选角色的组织与权限范围</small></div><ElSwitch v-model="form.dispatchEnabled" aria-label="任务派发资格" /></div><ElFormItem label="修改理由" prop="reason" :rules="[{ required: true, whitespace: true, message: '请填写修改理由', trigger: 'blur' }]"><ElInput v-model="form.reason" type="textarea" :rows="3" maxlength="2000" show-word-limit placeholder="说明本次调整的原因" /></ElFormItem>
        </ElForm>
      </template><p v-else-if="!editError" role="status">正在读取账号详情…</p>
      <template #footer><ElButton :disabled="saving" @click="drawer = false">取消</ElButton><ElButton type="primary" :loading="saving" :disabled="!current || pendingMembership" @click="save">提交修改审核</ElButton></template>
    </ElDrawer>
    <ReviewDrawer v-model="records" category="accounts" @changed="load" />
  </section>
</template>
