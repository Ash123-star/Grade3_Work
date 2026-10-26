<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { ElDrawer, ElTable, ElTableColumn, ElTag, ElButton, ElAlert, ElInput, ElFormItem, ElSteps, ElStep, ElEmpty, ElPagination } from 'element-plus';
import { api, errorMessage, statuses, type Page, type Review } from './api';
import { useSession } from './session';
const props = defineProps<{ modelValue: boolean; category: 'accounts' | 'items' }>();
const emit = defineEmits<{ 'update:modelValue': [boolean]; changed: [] }>();
const session = useSession(), rows = ref<Review[]>([]), detail = ref<Review | null>(null), error = ref(''), busy = ref(false), reason = ref(''), page = ref(1), total = ref(0);
const reviewStatuses: Record<string, string> = { ...statuses, PENDING: '待审核' };
let generation = 0;
const labels: Record<string, string> = { name: '姓名', departmentId: '部门', teamId: '团队', managerId: '直属上级', role: '角色', status: '状态', dispatchEnabled: '派发资格', companyReviewer: '公司复核人', title: '标题', text: '正文', pinned: '置顶', archived: '归档', position: '排序位置' };
const changes = computed(() => {
  const before = detail.value?.before_value ?? {};
  const body = typeof before.body === 'object' && before.body !== null ? before.body as Record<string, unknown> : {};
  const sourceKeys: Record<string, string> = { departmentId: 'department_id', teamId: 'team_id', managerId: 'manager_id', dispatchEnabled: 'dispatch_enabled', companyReviewer: 'company_reviewer' };
  return Object.entries(detail.value?.candidate ?? {}).map(([key, value]) => ({ key: labels[key] ?? key, before: before[key] ?? before[sourceKeys[key] ?? key] ?? (key === 'text' ? body.text : undefined), after: value }));
});
const nextStep = computed(() => detail.value?.steps?.find(step => step.state === 'PENDING'));
const canDecide = computed(() => detail.value?.status === 'PENDING' && detail.value.applicant_id !== session.user?.id && nextStep.value?.reviewer_id === session.user?.id);
const canReroute = computed(() => detail.value?.status === 'PENDING' && detail.value.applicant_id === session.user?.id && detail.value.steps?.every(step => step.state === 'PENDING'));
function display(value: unknown): string { if (value === undefined || value === null || value === '') return '—'; if (typeof value === 'boolean') return value ? '是' : '否'; return typeof value === 'object' ? JSON.stringify(value) : statuses[String(value)] ?? String(value); }
async function load() {
  const ticket = ++generation; busy.value = true; error.value = ''; detail.value = null;
  try { const result = await api<Page<Review>>('/reviews', { query: { category: props.category, cursor: (page.value - 1) * 20, limit: 20 } }); if (ticket === generation && props.modelValue) { rows.value = result.items; total.value = result.total; } }
  catch (e) { if (ticket === generation) error.value = errorMessage(e); } finally { if (ticket === generation) busy.value = false; }
}
async function open(row: Pick<Review, 'id'> | Record<string, unknown>) { error.value = ''; busy.value = true; const ticket = ++generation; try { const result = await api<Review>(`/reviews/${row.id}`); if (ticket === generation && props.modelValue) { detail.value = result; reason.value = ''; } } catch (e) { if (ticket === generation) error.value = errorMessage(e); } finally { if (ticket === generation) busy.value = false; } }
async function decide(approve: boolean) {
  if (!detail.value) return;
  if (!approve && !reason.value.trim()) { error.value = '驳回时请填写原因'; return; }
  busy.value = true; error.value = '';
  try { await api(`/reviews/${detail.value.id}/decision`, { method: 'POST', body: { approve, reason: reason.value } }); emit('changed'); await load(); }
  catch (e) { error.value = errorMessage(e); } finally { busy.value = false; }
}
async function reroute() { if (!detail.value) return; busy.value = true; error.value = ''; try { detail.value = await api<Review>(`/reviews/${detail.value.id}/reroute`, { method: 'POST' }); } catch (e) { error.value = errorMessage(e); } finally { busy.value = false; } }
watch(() => props.modelValue, value => { if (value) { page.value = 1; rows.value = []; void load(); } else { generation++; detail.value = null; rows.value = []; } });
</script>
<template>
  <ElDrawer :model-value="modelValue" title="修改与审核记录" size="min(780px, 100%)" @update:model-value="emit('update:modelValue', $event)" class="management-drawer">
    <ElAlert v-if="error" :title="error" type="error" show-icon :closable="false" role="alert" />
    <div v-if="detail" class="review-detail">
      <ElButton @click="load" :disabled="busy">返回记录</ElButton><h2>{{ detail.reason }}</h2><ElTag>{{ reviewStatuses[detail.status] ?? detail.status }}</ElTag>
      <p class="muted">申请号 {{ detail.id }} · 基于业务版本 {{ detail.expected_version ?? '—' }}</p>
      <ElTable :data="changes" border><ElTableColumn prop="key" label="字段" width="115" /><ElTableColumn label="修改前"><template #default="{ row }"><span class="wrap-content">{{ display(row.before) }}</span></template></ElTableColumn><ElTableColumn label="候选内容"><template #default="{ row }"><span class="wrap-content">{{ display(row.after) }}</span></template></ElTableColumn></ElTable>
      <h3>审核流程</h3><ElSteps direction="vertical" :active="detail.steps?.filter(s => s.state === 'APPROVED').length ?? 0"><ElStep v-for="step in detail.steps" :key="step.position" :title="`第 ${step.position} 级复核 · ${statuses[step.state] ?? step.state}`" :description="step.reason || '等待独立复核'" /></ElSteps>
      <ElAlert v-if="!detail.steps?.length && detail.status === 'PENDING'" title="尚无独立复核人，申请保持待审，当前生效内容不变。" type="warning" :closable="false" />
      <template v-if="canDecide"><ElFormItem label="审核意见"><ElInput v-model="reason" type="textarea" :rows="3" maxlength="2000" placeholder="驳回时必须填写原因" /></ElFormItem><ElButton type="primary" :loading="busy" @click="decide(true)">通过审核</ElButton><ElButton type="danger" plain :disabled="busy" @click="decide(false)">驳回</ElButton></template>
      <ElButton v-if="canReroute" :loading="busy" @click="reroute">重新匹配复核人</ElButton>
    </div>
    <template v-else><p class="muted">查看我的申请与分配给我的审核</p><ElButton :loading="busy" @click="load">刷新记录</ElButton><ElTable :data="rows" @row-click="open" class="clickable-table"><ElTableColumn prop="reason" label="修改理由" min-width="200" /><ElTableColumn label="状态" width="100"><template #default="{ row }"><ElTag :type="row.status === 'PENDING' ? 'warning' : row.status === 'APPROVED' ? 'success' : 'danger'">{{ statuses[row.status] }}</ElTag></template></ElTableColumn><ElTableColumn label="操作" width="90"><template #default="{ row }"><ElButton link type="primary" @click.stop="open(row)">查看详情</ElButton></template></ElTableColumn><template #empty><ElEmpty :description="busy ? '正在读取…' : '暂无相关修改记录'" :image-size="70" /></template></ElTable><ElPagination v-model:current-page="page" :total="total" :page-size="20" layout="prev, pager, next" @current-change="load" /></template>
  </ElDrawer>
</template>
