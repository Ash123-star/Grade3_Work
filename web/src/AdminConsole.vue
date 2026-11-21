<script setup lang="ts">
import { computed, nextTick, onMounted, ref } from 'vue';
import { nameError, phoneError } from './employee-input';
type Row = Record<string, any>;
const user = ref<Row | null>(null), token = ref(sessionStorage.getItem('workpanel-token') || '');
const loginAccount = ref(''), loginPassword = ref(''), oldPassword = ref(''), newPassword = ref('');
const tab = ref('employees'), rows = ref<Row[]>([]), departments = ref<Row[]>([]), teams = ref<Row[]>([]), managers = ref<Row[]>([]), departmentFilter = ref('');
const busy = ref(false), loading = ref(false), error = ref(''), notice = ref('');
const search = ref(''), cursor = ref(0), nextCursor = ref(0), total = ref(0);
const editor = ref(''), form = ref<Row>({}), detail = ref<Row | null>(null), decisionReason = ref(''), editingPending = ref(false);
const fieldErrors = ref<Record<string,string>>({});
const positionName: Record<string,string> = { NONE:'普通岗位', GENERAL_MANAGER:'总经理', DEPUTY_GENERAL_MANAGER:'分管副总' };
function managerLabel(row: Row): string { return row.manager_name ? `${row.manager_name}（${positionName[row.manager_business_position] && row.manager_business_position !== 'NONE' ? positionName[row.manager_business_position] : stateName[row.manager_role] || '管理人员'}）` : '未指定'; }
const companyLevel = computed(() => form.value.role === 'DIRECTOR' || (form.value.businessPosition && form.value.businessPosition !== 'NONE'));
let generation = 0, pageGeneration = 0;
const titles: Record<string, string> = { employees: '员工与账号', priorities: '公司重要事项', history: '修改记录', reviews: '申请与审核' };
const auditName: Record<string,string> = { EMPLOYEE_PROVISIONED:'录入员工', ADMIN_EMPLOYEE_UPDATED:'修改员工资料', ADMIN_COMPANY_ITEM_UPDATED:'修改公司事项' };
const auditFieldName: Record<string,string> = { name:'姓名',role:'角色',status:'账号状态',departmentId:'部门',teamId:'组',managerId:'直接上级',businessPosition:'业务职位',title:'事项名称',text:'事项说明',gender:'性别',idCardUpdated:'身份证号已更新',pinned:'置顶',archived:'撤下',position:'内部排序' };
const stateName: Record<string, string> = { ACTIVE: '已启用', DISABLED: '已停用', PENDING: '待确认', APPROVED: '已通过', REJECTED: '已驳回', SUPERSEDED: '已由管理员处理', EMPLOYEE: '员工', ADMIN: '管理员', FOUNDER: '创始人', DIRECTOR: '部门负责人', LEADER: '团队长' };
const kindName: Record<string, string> = { USER: '员工资料', COMPANY_ITEM: '公司事项', MEMBERSHIP: '成员确认', DEPARTMENT: '部门', TEAM: '团队' };
const canDecide = computed(() => detail.value?.status === 'PENDING' && !detail.value?.stale && detail.value?.applicant_id !== user.value?.id && detail.value?.steps?.some((s: Row) => s.state === 'PENDING' && s.reviewer_id === user.value?.id));
const availableTeams = computed(() => teams.value.filter(t => t.department_id === form.value.departmentId));
const availableManagers = computed(() => managers.value.filter(m => m.id !== form.value.id && (companyLevel.value
  ? m.role === 'FOUNDER' || ['GENERAL_MANAGER','DEPUTY_GENERAL_MANAGER'].includes(m.business_position)
  : m.department_id === form.value.departmentId && (['LEADER','DIRECTOR','FOUNDER'].includes(m.role) || ['GENERAL_MANAGER','DEPUTY_GENERAL_MANAGER'].includes(m.business_position)))));
function changeDepartment() { form.value.teamId = ''; form.value.managerId = ''; }
function ageFromIdCard(value: unknown): number | null {
  if (typeof value !== 'string' || !/^[0-9]{17}[0-9Xx]$/.test(value)) return null;
  value=value.trim().toUpperCase();
  const weights=[7,9,10,5,8,4,2,1,6,3,7,9,10,5,8,4,2];
  const card=value as string;
  if(card[17]!=='10X98765432'[weights.reduce((sum,w,i)=>sum+Number(card[i])*w,0)%11]) return null;
  const year=Number(card.slice(6,10)), month=Number(card.slice(10,12)), day=Number(card.slice(12,14));
  const birth=new Date(Date.UTC(year,month-1,day));
  if (birth.getUTCFullYear()!==year || birth.getUTCMonth()+1!==month || birth.getUTCDate()!==day) return null;
  const parts=Object.fromEntries(new Intl.DateTimeFormat('en-US',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date()).map(part=>[part.type,part.value]));
  const nowYear=Number(parts.year),nowMonth=Number(parts.month),nowDay=Number(parts.day);
  if(year<1900 || year>nowYear || year===nowYear && (month>nowMonth || month===nowMonth && day>nowDay)) return null;
  return nowYear-year-(nowMonth<month || nowMonth===month && nowDay<day ? 1 : 0);
}
function clearSession() {
  generation++; pageGeneration++; token.value = ''; sessionStorage.removeItem('workpanel-token'); user.value = null;
  rows.value = []; departments.value = []; teams.value = []; managers.value = []; departmentFilter.value = ''; form.value = {}; fieldErrors.value = {}; editor.value = ''; detail.value = null;
  oldPassword.value = ''; newPassword.value = ''; loginPassword.value = ''; search.value = ''; total.value = 0;
}
async function api(path: string, method = 'GET', body?: Row): Promise<any> {
  const ticket = generation;
  const response = await fetch(path, { method, headers: { Authorization: `Bearer ${token.value}`, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const data = await response.json().catch(() => null);
  if (ticket !== generation) throw new Error('会话已切换，请重新操作');
  if (!response.ok) {
    if ((response.status === 401 || response.status === 403) && !path.endsWith('/auth/login')) { clearSession(); error.value = data?.message || `访问已失效（${response.status}），请重新登录`; }
    if (path.startsWith('/api/admin/console/employees') && method === 'POST') {
      fieldErrors.value = data?.fieldErrors || {};
      const key: Record<string,string> = { INVALID_NAME:'name', INVALID_ACCOUNT:'account', INVALID_PHONE:'phone', INVALID_PHONE_PREFIX:'phone', INVALID_ID_CARD:'idCardNumber', INVALID_ID_ADDRESS:'idCardNumber', IDENTITY_GENDER_MISMATCH:'gender', ACCOUNT_EXISTS:'account', PHONE_EXISTS:'phone', ID_CARD_EXISTS:'idCardNumber', INVALID_MANAGER:'managerId' };
      if (key[data?.code]) fieldErrors.value[key[data.code]] = data.message;
    }
    throw new Error(data?.message || `请求未完成（${response.status}），请稍后重试`);
  }
  if (!data || typeof data !== 'object') throw new Error('服务响应异常，请刷新重试');
  return data;
}
async function run(action: () => Promise<void>) {
  if (busy.value) return;
  busy.value = true; error.value = ''; notice.value = '';
  try { await action(); } catch (e) { error.value = e instanceof Error ? e.message : '操作未完成，请重试'; }
  finally { busy.value = false; await nextTick(); document.querySelector<HTMLElement>('.drawer [aria-invalid="true"]')?.focus(); }
}
async function load(offset = 0) {
  const ticket = ++pageGeneration, selectedTab = tab.value; loading.value = true; error.value = '';
  try {
    const query = new URLSearchParams({ cursor: String(offset), limit: '20', ...(selectedTab === 'employees' ? { search: search.value.trim(), departmentId: departmentFilter.value } : {}) });
    const data = await api(`/api/admin/console/${selectedTab}?${query}`);
    if (ticket !== pageGeneration) return;
    if (!Array.isArray(data.items) || !Number.isFinite(Number(data.total)) || !Number.isFinite(Number(data.nextCursor))) throw new Error('列表响应异常，请重试');
    rows.value = data.items; total.value = Number(data.total); cursor.value = offset; nextCursor.value = Number(data.nextCursor);
  } catch (e) { if (ticket === pageGeneration) error.value = e instanceof Error ? e.message : '加载失败'; }
  finally { if (ticket === pageGeneration) loading.value = false; }
}
async function enter() {
  const me = await api('/api/auth/me');
  if (me.role !== 'ADMIN' || me.status !== 'ACTIVE') { clearSession(); throw new Error('此后台仅供管理员使用'); }
  user.value = me;
  if (!me.must_change_password) { [departments.value, teams.value, managers.value] = await Promise.all(['/api/admin/console/departments','/api/admin/console/teams','/api/admin/console/managers'].map(path => api(path))); await load(); }
}
function login() { void run(async () => {
  const data = await api('/api/auth/login', 'POST', { account: loginAccount.value, password: loginPassword.value });
  if (data.user?.role !== 'ADMIN' || data.user?.status !== 'ACTIVE') { loginPassword.value = ''; throw new Error('此后台仅供管理员使用，请使用移动端'); }
  token.value = data.token; sessionStorage.setItem('workpanel-token', token.value); loginPassword.value = ''; await enter();
}); }
function changePassword() { void run(async () => { await api('/api/auth/password', 'POST', { oldPassword: oldPassword.value, newPassword: newPassword.value }); clearSession(); notice.value = '密码已更新，请使用新密码登录'; }); }
function logout() { void run(async () => { try { await api('/api/auth/logout', 'POST'); } finally { clearSession(); } }); }
async function selectTab(value: string) { if (busy.value) return; tab.value = value; rows.value = []; total.value = 0; search.value = ''; await load(); }
async function openEditor(type: string, row?: Row) {
  editor.value = type; detail.value = null; fieldErrors.value = {}; error.value = '';
  editingPending.value = type === 'employee' && row?.status === 'PENDING';
  if (type === 'create') form.value = { account: '', password: '', phone: '', name: '', businessPosition: 'NONE', gender: '', idCardNumber: '', departmentId: '', teamId: '', managerId: '' };
  if (type === 'employee' && row) form.value = { id: row.id, name: row.name, role: row.role, businessPosition: row.business_position || 'NONE', gender: row.gender || '', idCardNumber: '', hasIdCard: row.has_id_card, age: row.age, departmentId: row.department_id || '', teamId: row.team_id || '', managerId: row.manager_id || '', status: row.status, version: row.version, reason: '' };
  if (type === 'priority') form.value = { id: row?.id || '', title: row?.title || '', text: row?.body?.text || '', pinned: row?.pinned ?? true, archived: row?.archived ?? false, position: row?.position ?? 0, version: row?.version ?? 0, reason: '' };
  await nextTick(); document.querySelector<HTMLInputElement>('.drawer input')?.focus();
}
function closeEditor() { if (busy.value) return; editor.value = ''; form.value = {}; detail.value = null; fieldErrors.value = {}; error.value = ''; }
async function viewEmployee(row: Row) { detail.value = row; editor.value = 'person'; fieldErrors.value = {}; error.value = ''; await nextTick(); document.querySelector<HTMLElement>('.drawer button')?.focus(); }
function changePosition() { form.value.managerId = ''; }
function keepDialogFocus(event: KeyboardEvent) {
  if (event.key !== 'Tab') return;
  const elements = Array.from(document.querySelectorAll<HTMLElement>('.drawer button:not(:disabled), .drawer input:not(:disabled), .drawer select:not(:disabled), .drawer textarea:not(:disabled)'));
  const first = elements[0], last = elements[elements.length - 1];
  if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
  else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
}
function save() { void run(async () => {
  fieldErrors.value = {};
  if (editor.value === 'create' || editor.value === 'employee') {
    const invalidName = nameError(form.value.name);
    if (!invalidName) form.value.name = form.value.name.normalize('NFC').trim(); if (invalidName) fieldErrors.value.name = invalidName;
    if (editor.value === 'create') { const invalidPhone = phoneError(form.value.phone); if (invalidPhone) fieldErrors.value.phone = invalidPhone; }
    if (Object.keys(fieldErrors.value).length) throw new Error('请检查标出的资料后重新提交');
  }
  let result: Row;
  if (editor.value === 'create') result = await api('/api/admin/console/employees', 'POST', form.value);
  else if (editor.value === 'employee') { const { id, hasIdCard, age, role, ...body } = form.value; if (body.status === 'PENDING') delete body.status; if (!body.gender) delete body.gender; if (!body.idCardNumber) delete body.idCardNumber; result = await api(`/api/admin/console/employees/${encodeURIComponent(id)}/revisions`, 'POST', body); }
  else result = await api('/api/admin/console/priorities/revisions', 'POST', form.value);
  const created = editor.value === 'create';
  editor.value = ''; form.value = {};
  notice.value = created ? `员工账号 ${result.account} 已开通，首次登录须修改密码` : '修改已保存并立即生效，操作记录已保留。';
  await load(cursor.value);
}); }
function viewReview(row: Row) { void run(async () => { detail.value = await api(`/api/admin/console/reviews/${encodeURIComponent(row.id)}`); editor.value = 'review'; decisionReason.value = ''; }); }
async function handleStaleMembership() { const name=detail.value?.target_name || detail.value?.applicant_name || ''; editor.value=''; detail.value=null; tab.value='employees'; departmentFilter.value=''; search.value=name; await load(0); }
function viewAudit(row: Row) { detail.value=row; editor.value='audit'; }
function auditValue(key: string, value: unknown): string {
  if (key === 'businessPosition') return positionName[String(value)] || String(value ?? '—');
  if (key === 'departmentId') return departments.value.find(d => d.id === value)?.name || String(value ?? '未分配');
  if (key === 'teamId') return teams.value.find(t => t.id === value)?.name || String(value ?? '未分配');
  if (key === 'managerId') return managers.value.find(m => m.id === value)?.name || String(value ?? '未指定');
  if (typeof value === 'boolean') return value ? '是' : '否';
  return stateName[String(value)] || String(value ?? '—');
}
function decide(approve: boolean) { void run(async () => {
  if (!approve && !decisionReason.value.trim()) throw new Error('请填写驳回原因');
  const result = await api(`/api/admin/console/reviews/${encodeURIComponent(detail.value!.id)}/decision`, 'POST', { approve, reason: decisionReason.value, expectedVersion: detail.value!.expected_version });
  detail.value = result; notice.value = approve ? '审核已通过' : '申请已驳回'; await load(cursor.value);
}); }
onMounted(() => { if (token.value) void run(enter); });
</script>

<template>
  <div class="admin-app">
    <main v-if="!user || user.must_change_password" class="login-layout">
      <section class="welcome"><div class="brand-mark">P</div><p class="eyebrow">PANDORA · ADMIN</p><h1>让重要的事，<br>井然有序。</h1><p>员工资料、账号开通与公司重点，<br>在这里统一维护。</p><span class="welcome-note">企业协作 · 管理员后台</span></section>
      <section class="login-card">
        <p class="eyebrow">管理入口</p><h2>{{ user ? '设置新的登录密码' : '欢迎回来' }}</h2><p class="muted">{{ user ? '首次登录需要修改初始密码。' : '请使用管理员账号登录。' }}</p>
        <p v-if="error" role="alert" class="alert error">{{ error }}</p><p v-if="notice" role="status" class="alert success">{{ notice }}</p>
        <form v-if="!user" @submit.prevent="login">
          <label>管理员账号<input v-model="loginAccount" autocomplete="username" required maxlength="64" placeholder="请输入账号"></label>
          <label>登录密码<input v-model="loginPassword" type="password" autocomplete="current-password" required placeholder="请输入密码"></label>
          <button class="primary wide" :disabled="busy">{{ busy ? '正在登录…' : '登录后台' }} <span aria-hidden="true">→</span></button>
        </form>
        <form v-else @submit.prevent="changePassword"><label>原密码<input v-model="oldPassword" type="password" autocomplete="current-password" required></label><label>新密码<input v-model="newPassword" type="password" minlength="12" autocomplete="new-password" required></label><p class="muted">至少12个字符，UTF-8编码不超过72字节。</p><button class="primary wide" :disabled="busy">修改并重新登录</button><button type="button" class="wide" :disabled="busy" @click="clearSession">返回登录</button></form>
        <p class="login-footnote">仅授权管理员可访问 · 员工请使用移动端</p>
      </section>
    </main>
    <div v-else class="console-layout">
      <aside class="sidebar"><a href="#" class="brand" @click.prevent="selectTab('employees')"><span class="brand-mark small">P</span><span>潘多拉<small>企业管理后台</small></span></a><p class="nav-caption">日常管理</p>
        <nav aria-label="后台导航"><button v-for="(title, key) in titles" :key="key" :class="{ active: tab === key }" :aria-current="tab === key ? 'page' : undefined" :disabled="busy" @click="selectTab(key)"><span aria-hidden="true">{{ key === 'employees' ? '◎' : key === 'priorities' ? '◇' : '▤' }}</span>{{ title }}</button></nav>
        <div class="sidebar-bottom"><span class="avatar">{{ user.name?.slice(0, 1) }}</span><div>{{ user.name }}<small>管理员</small></div><button class="logout" :disabled="busy" @click="logout">退出</button></div>
      </aside>
      <main class="console-main" :aria-busy="loading"><header class="topbar"><span>管理后台 <span class="separator">/</span> {{ titles[tab] }}</span><span class="admin-badge">管理员专属</span></header>
        <section class="page-content"><div class="page-heading"><div><p class="eyebrow">{{ tab === 'employees' ? 'PEOPLE & ACCOUNTS' : tab === 'priorities' ? 'COMPANY PRIORITIES' : tab === 'history' ? 'CHANGE HISTORY' : 'REQUESTS & REVIEWS' }}</p><h1>{{ titles[tab] }}</h1><p class="muted">{{ tab === 'employees' ? '维护员工资料，为新同事开通工作账号。' : tab === 'priorities' ? '维护移动端展示的公司重点，让全员看见重要的事。' : tab === 'history' ? '查看管理员直接生效的员工和事项修改。' : '只显示当前有效的待审申请。历史决定保留在后台审计中。' }}</p></div><button v-if="tab === 'employees' || tab === 'priorities'" class="primary" :disabled="busy" @click="openEditor(tab === 'employees' ? 'create' : 'priority')">＋ {{ tab === 'employees' ? '录入员工并开通账号' : '新增重要事项' }}</button></div>
          <p v-if="error" role="alert" class="alert error">{{ error }}</p><p v-if="notice" role="status" class="alert success">{{ notice }}</p>
          <div class="info-strip"><span aria-hidden="true">i</span>{{ tab === 'employees' ? '新建账号默认为员工，首次登录须改密。管理员在此修改资料与停用会立即生效并留痕。' : tab === 'priorities' ? '管理员在此新增和修改事项会立即生效并留痕。' : tab === 'history' ? '这里展示管理员直接创建和修改的记录；当前待审申请请到申请与审核查看。' : '这里是其他入口提交后分配给当前管理员的有效审核待办；Web 管理员直接修改不进入此处。' }}</div>
          <section class="data-panel"><div class="panel-toolbar"><h2>{{ tab === 'employees' ? '员工目录' : tab === 'priorities' ? '事项列表' : tab === 'history' ? '管理员操作记录' : '申请与审核' }} <span class="count">{{ total }}</span></h2><form v-if="tab === 'employees'" class="search-form" @submit.prevent="load()"><select v-model="departmentFilter" aria-label="按部门筛选" @change="load()"><option value="">全部部门</option><option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option></select><input v-model="search" aria-label="搜索员工" placeholder="搜索姓名、账号或手机号" maxlength="100"><button :disabled="busy || loading">搜索</button></form><button v-else :disabled="busy || loading" @click="load(cursor)">刷新列表</button></div>
            <div v-if="loading" role="status" class="empty-state">正在加载…</div>
            <div v-else-if="!rows.length" class="empty-state"><span aria-hidden="true">{{ error ? '!' : '◇' }}</span><h3>{{ error ? '暂时无法加载' : tab === 'reviews' ? '暂无待审申请' : '暂无记录' }}</h3><p>{{ error ? '请检查服务连接后重试。' : tab === 'employees' ? '点击上方按钮，为第一位同事开通账号。' : tab === 'priorities' ? '从一件重要的事开始。' : tab === 'reviews' ? '当前没有需要你审核的有效申请。' : '管理员直接修改后，记录会出现在这里。' }}</p><button v-if="error" @click="load(cursor)">重试加载</button></div>
            <div v-else class="table-scroll" :class="{ 'employee-directory': tab === 'employees' }"><table role="table"><thead><tr v-if="tab === 'employees'"><th>员工 / 账号</th><th>组织归属</th><th>角色 / 职位</th><th>直属上级</th><th>账号状态</th><th>操作</th></tr><tr v-else-if="tab === 'priorities'"><th>事项名称</th><th>操作</th></tr><tr v-else-if="tab === 'history'"><th>操作</th><th>对象</th><th>管理员</th><th>原因</th><th>时间</th><th>详情</th></tr><tr v-else><th>修改类型</th><th>申请人</th><th>申请原因</th><th>审核状态</th><th>操作</th></tr></thead>
              <tbody><tr v-for="row in rows" :key="row.id"><template v-if="tab === 'employees'">
                  <td data-label="员工 / 账号"><button class="text-button person-name" :disabled="busy" @click="viewEmployee(row)">{{ row.name }}</button><small class="cell-note">{{ row.account }}</small></td>
                  <td data-label="组织归属">{{ row.department || '未分配' }}<small class="cell-note">{{ row.team_name || '未分配组' }}</small></td>
                  <td data-label="角色 / 职位">{{ stateName[row.role] || row.role }}<small v-if="row.business_position && row.business_position !== 'NONE'" class="cell-note">{{ positionName[row.business_position] }}</small></td>
                  <td data-label="直属上级">{{ managerLabel(row) }}</td>
                  <td data-label="账号状态"><span class="badge" :class="{ inactive: row.status !== 'ACTIVE' }">{{ stateName[row.status] || row.status }}</span><small v-if="row.must_change_password" class="cell-note">首次登录待改密</small><small v-if="row.status === 'PENDING'" class="cell-note">编辑资料可确认启用</small></td>
                  <td data-label="操作" class="employee-actions"><button class="text-button" :disabled="busy" @click="viewEmployee(row)">查看详情</button><button class="text-button" :disabled="busy" @click="openEditor('employee', row)">编辑资料</button></td>
                </template>
                <template v-else-if="tab === 'priorities'"><td class="title-cell"><strong>{{ row.title }}</strong><small>{{ row.body?.text }}</small></td><td><button class="text-button" :disabled="busy" @click="openEditor('priority', row)">编辑事项</button></td></template>
                <template v-else-if="tab === 'history'"><td>{{ auditName[row.type] || row.type }}</td><td>{{ row.target_name }}</td><td>{{ row.actor_name || '—' }}</td><td>{{ row.reason }}</td><td>{{ row.created_at ? new Date(row.created_at).toLocaleString('zh-CN') : '—' }}</td><td><button class="text-button" :disabled="busy" @click="viewAudit(row)">查看详情</button></td></template>
                <template v-else><td>{{ kindName[row.kind] || row.kind }}</td><td>{{ row.applicant_name || '—' }}</td><td class="title-cell">{{ row.reason }}</td><td><span class="badge" :class="{ inactive: row.status !== 'APPROVED' }">{{ stateName[row.status] || row.status }}</span><small v-if="row.status === 'PENDING'" class="cell-note">{{ row.reviewer_configured ? `审核人：${row.reviewer_name}` : '尚未分配审核人' }}</small></td><td><button class="text-button" :disabled="busy" @click="viewReview(row)">查看详情</button></td></template></tr></tbody></table></div>
            <footer class="pagination"><span>共 {{ total }} 条<span v-if="rows.length"> · 当前 {{ cursor + 1 }}–{{ cursor + rows.length }}</span></span><div><button :disabled="loading || busy || cursor === 0" @click="load(Math.max(0, cursor - 20))">上一页</button><button :disabled="loading || busy || nextCursor >= total || nextCursor <= cursor" @click="load(nextCursor)">下一页</button></div></footer>
          </section><p class="page-footnote">潘多拉 · 企业协作管理</p>
        </section>
      </main>
      <div v-if="editor" class="drawer-shade" @click.self="closeEditor" @keydown.esc="closeEditor" @keydown="keepDialogFocus"><section class="drawer" role="dialog" aria-modal="true" aria-labelledby="editor-title"><div class="drawer-heading"><div><p class="eyebrow">{{ editor === 'create' ? 'NEW EMPLOYEE' : 'MANAGE' }}</p><h2 id="editor-title">{{ editor === 'create' ? '录入员工并开通账号' : editor === 'employee' ? '编辑员工资料' : editor === 'priority' ? '维护公司重要事项' : editor === 'person' ? '员工详情' : editor === 'audit' ? '管理员操作详情' : '修改申请详情' }}</h2></div><button aria-label="关闭面板" :disabled="busy" @click="closeEditor">×</button></div>
        <p v-if="error" role="alert" class="alert error">{{ error }}</p>
        <form v-if="editor !== 'review' && editor !== 'audit' && editor !== 'person'" @submit.prevent="save"><template v-if="editor === 'create'"><label>员工姓名<input v-model="form.name" aria-label="员工姓名" required :aria-invalid="!!fieldErrors.name" aria-describedby="name-error" @input="delete fieldErrors.name" autocomplete="off"></label><label>登录账号<input v-model="form.account" :aria-invalid="!!fieldErrors.account" aria-describedby="account-error" @input="delete fieldErrors.account" required pattern="[a-zA-Z0-9_.\-]{3,64}" maxlength="64" autocomplete="off" placeholder="3–64位字母、数字或 _ . -"></label><p v-if="fieldErrors.account" id="account-error" class="field-error">{{ fieldErrors.account }}</p><label>手机号<input v-model="form.phone" :aria-invalid="!!fieldErrors.phone" aria-describedby="phone-error" @input="delete fieldErrors.phone" type="tel" required maxlength="11"></label><p v-if="fieldErrors.phone" id="phone-error" class="field-error">{{ fieldErrors.phone }}</p><label>初始密码<input v-model="form.password" type="password" required minlength="12" autocomplete="new-password"></label><p class="muted">至少12个字符，不超过72字节。请通过安全渠道交给员工，首次登录须改密。</p></template>
          <p v-if="fieldErrors.name" id="name-error" class="field-error">{{ fieldErrors.name }}</p><p v-if="editor === 'create' || editor === 'employee'" class="muted">姓名2–50个字符，支持汉字、字母和姓名内部的 ·、空格、连字符或撇号。</p>
          <label v-if="editor === 'employee'">员工姓名<input v-model="form.name" aria-label="员工姓名" required :aria-invalid="!!fieldErrors.name" aria-describedby="name-error" @input="delete fieldErrors.name"></label>
          <label v-if="editor === 'create' || editor === 'employee'">性别<select v-model="form.gender" :required="editor === 'create'"><option value="" disabled>请选择性别</option><option value="男">男</option><option value="女">女</option></select></label>
          <label v-if="editor === 'create' || editor === 'employee'">身份证号<input v-model="form.idCardNumber" :aria-invalid="!!fieldErrors.idCardNumber" aria-describedby="id-error" @input="delete fieldErrors.idCardNumber" :required="editor === 'create'" pattern="[0-9]{17}[0-9Xx]" maxlength="18" autocomplete="off" :placeholder="editor === 'employee' && form.hasIdCard ? '已录入，留空保持原号码' : '18位身份证号'"><small v-if="editor === 'employee'" class="muted">{{ form.hasIdCard ? '已录入，留空不修改' : '尚未录入' }}</small></label>
          <p v-if="fieldErrors.idCardNumber" id="id-error" class="field-error">{{ fieldErrors.idCardNumber }}</p><p v-if="fieldErrors.gender" class="field-error">{{ fieldErrors.gender }}</p>
          <label v-if="editor === 'create' || editor === 'employee'">年龄<input aria-label="年龄" :value="form.idCardNumber ? (ageFromIdCard(form.idCardNumber) ?? '') : (form.age ?? '')" readonly placeholder="从身份证号自动计算"></label>
          <label v-if="editor === 'create' || editor === 'employee'">所属部门<select v-model="form.departmentId" required @change="changeDepartment"><option value="" disabled>请选择部门</option><option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option></select></label>
          <label v-if="editor === 'create' || editor === 'employee'">所属组<select v-model="form.teamId" :required="editor === 'create' || editingPending && form.status === 'ACTIVE'"><option value="" disabled>请选择组</option><option v-for="t in availableTeams" :key="t.id" :value="t.id">{{ t.name }}</option></select></label>
          <label v-if="editor === 'create' || editor === 'employee'">业务职位<select v-model="form.businessPosition" @change="changePosition"><option v-for="(label,key) in positionName" :key="key" :value="key">{{ label }}</option></select><small class="muted">按实际任职设置。此项不改变账号的系统权限。</small></label>
          <label v-if="editor === 'create' || editor === 'employee'">直接上级<select v-model="form.managerId" :aria-invalid="!!fieldErrors.managerId" aria-describedby="manager-error" @change="delete fieldErrors.managerId" :required="editor === 'create' || editingPending && form.status === 'ACTIVE'"><option value="">{{ companyLevel ? '请选择本公司创始人、总经理或分管副总' : '请选择同部门业务管理人员' }}</option><option v-for="m in availableManagers" :key="m.id" :value="m.id">{{ m.name }}（{{ m.business_position && m.business_position !== 'NONE' ? positionName[m.business_position] : stateName[m.role] || m.role }}）</option></select></label>
          <p v-if="fieldErrors.managerId" id="manager-error" class="field-error">{{ fieldErrors.managerId }}</p><label v-if="editor === 'employee'">账号状态<select v-model="form.status" :required="editingPending"><option v-if="form.status === 'PENDING'" value="PENDING" disabled>待确认（请选择启用或停用）</option><option value="ACTIVE">启用</option><option value="DISABLED">停用</option></select></label>
          <template v-if="editor === 'priority'"><label>事项名称<input v-model="form.title" required maxlength="200"></label><label>事项说明<textarea v-model="form.text" rows="6" maxlength="20000"></textarea></label></template>
          <label v-if="editor !== 'create'">修改原因<textarea v-model="form.reason" required rows="3" maxlength="2000" placeholder="请说明此次修改的原因"></textarea></label>
          <div class="form-actions"><button type="button" :disabled="busy" @click="closeEditor">取消</button><button class="primary" :disabled="busy">{{ busy ? '正在提交…' : editor === 'create' ? '开通员工账号' : '保存并立即生效' }}</button></div>
        </form>
        <div v-else-if="editor === 'person' && detail" class="employee-detail">
          <p class="muted">员工基本资料与组织关系</p><dl>
            <dt>姓名</dt><dd>{{ detail.name }}</dd><dt>登录账号</dt><dd>{{ detail.account }}</dd>
            <dt>手机号</dt><dd>{{ detail.phone }}</dd><dt>性别</dt><dd>{{ detail.gender || '未录入' }}</dd>
            <dt>身份证号</dt><dd>{{ detail.has_id_card ? '已录入' : '未录入' }}</dd><dt>年龄</dt><dd>{{ detail.age == null ? '未录入' : `${detail.age} 岁` }}</dd>
            <dt>部门</dt><dd>{{ detail.department || '未分配' }}</dd><dt>组</dt><dd>{{ detail.team_name || '未分配' }}</dd>
            <dt>系统角色</dt><dd>{{ stateName[detail.role] || detail.role }}</dd><dt>业务职位</dt><dd>{{ positionName[detail.business_position || 'NONE'] }}</dd>
            <dt>直属上级</dt><dd>{{ managerLabel(detail) }}</dd><dt>账号状态</dt><dd>{{ stateName[detail.status] || detail.status }}</dd>
          </dl><div class="form-actions"><button type="button" @click="closeEditor">关闭</button><button class="primary" @click="openEditor('employee', detail)">编辑资料</button></div>
        </div>
        <div v-else-if="editor === 'audit' && detail" class="review-detail"><p>操作：{{ auditName[detail.type] || detail.type }}</p><p>对象：{{ detail.target_name }}</p><p>管理员：{{ detail.actor_name || '—' }}</p><p>原因：{{ detail.reason }}</p><h3>修改前</h3><dl><template v-for="(value, key) in detail.before_value" :key="key"><dt>{{ auditFieldName[String(key)] || key }}</dt><dd>{{ auditValue(String(key), value) }}</dd></template></dl><p v-if="!Object.keys(detail.before_value || {}).length" class="muted">新建记录，无修改前内容</p><h3>修改后</h3><dl><template v-for="(value, key) in detail.after_value" :key="key"><dt>{{ auditFieldName[String(key)] || key }}</dt><dd>{{ auditValue(String(key), value) }}</dd></template></dl></div>
        <div v-else-if="detail" class="review-detail"><p>申请人：{{ detail.applicant_name }}</p><p>状态：{{ stateName[detail.status] || detail.status }}</p><p>原因：{{ detail.reason }}</p><p v-if="detail.stale" class="alert error">员工资料已更新（申请时版本 {{ detail.expected_version }}，当前版本 {{ detail.target_version }}），此旧申请不能通过。请在员工目录编辑并启用，旧申请会自动关闭。</p><button v-if="detail.stale && detail.kind === 'MEMBERSHIP'" @click="handleStaleMembership">到员工目录处理</button><h3>拟修改内容</h3><dl><template v-for="(value, key) in detail.candidate" :key="key"><dt>{{ ({ name:'姓名',departmentId:'部门',teamId:'组',managerId:'直接上级',businessPosition:'业务职位',title:'事项名称',text:'说明',pinned:'置顶',archived:'撤下',position:'排序',status:'账号状态',role:'角色' } as Record<string,string>)[key] || key }}</dt><dd>{{ String(key) === 'departmentId' ? departments.find(d => d.id === value)?.name || value : String(key) === 'teamId' ? teams.find(t => t.id === value)?.name || '未分配' : String(key) === 'managerId' ? managers.find(m => m.id === value)?.name || '未指定' : stateName[String(value)] || String(value ?? '—') }}</dd></template></dl><h3>审核记录</h3><p v-if="!detail.steps?.length" class="muted">尚未分配有效审核人；请配置另一名具有审核资格的人员。申请人不能自审。</p><p v-for="step in detail.steps" :key="step.id">{{ step.reviewer_name || '审核人' }} · {{ stateName[step.state] || step.state }} {{ step.reason }}</p><template v-if="canDecide"><label>审核意见<textarea v-model="decisionReason" rows="3" maxlength="2000" placeholder="驳回时必填"></textarea></label><div class="form-actions"><button :disabled="busy" @click="decide(false)">驳回申请</button><button class="primary" :disabled="busy" @click="decide(true)">通过审核</button></div></template></div>
      </section></div>
    </div>
  </div>
</template>
