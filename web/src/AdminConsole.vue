<script setup lang="ts">
import { computed, nextTick, onMounted, ref } from 'vue';
type Row = Record<string, any>;
const user = ref<Row | null>(null), token = ref(sessionStorage.getItem('workpanel-token') || '');
const loginAccount = ref(''), loginPassword = ref(''), oldPassword = ref(''), newPassword = ref('');
const tab = ref('employees'), rows = ref<Row[]>([]), departments = ref<Row[]>([]);
const busy = ref(false), loading = ref(false), error = ref(''), notice = ref('');
const search = ref(''), cursor = ref(0), nextCursor = ref(0), total = ref(0);
const editor = ref(''), form = ref<Row>({}), detail = ref<Row | null>(null), decisionReason = ref('');
let generation = 0, pageGeneration = 0;
const titles: Record<string, string> = { employees: '员工与账号', priorities: '公司重要事项', reviews: '修改记录' };
const stateName: Record<string, string> = { ACTIVE: '已启用', DISABLED: '已停用', PENDING: '待审核', APPROVED: '已通过', REJECTED: '已驳回', EMPLOYEE: '员工', ADMIN: '管理员', FOUNDER: '创始人', DIRECTOR: '部门负责人', LEADER: '团队长' };
const kindName: Record<string, string> = { USER: '员工资料', COMPANY_ITEM: '公司事项', MEMBERSHIP: '成员确认', DEPARTMENT: '部门', TEAM: '团队' };
const canDecide = computed(() => detail.value?.status === 'PENDING' && detail.value?.applicant_id !== user.value?.id && detail.value?.steps?.some((s: Row) => s.state === 'PENDING' && s.reviewer_id === user.value?.id));
function clearSession() {
  generation++; pageGeneration++; token.value = ''; sessionStorage.removeItem('workpanel-token'); user.value = null;
  rows.value = []; departments.value = []; form.value = {}; editor.value = ''; detail.value = null;
  oldPassword.value = ''; newPassword.value = ''; loginPassword.value = ''; search.value = ''; total.value = 0;
}
async function api(path: string, method = 'GET', body?: Row): Promise<any> {
  const ticket = generation;
  const response = await fetch(path, { method, headers: { Authorization: `Bearer ${token.value}`, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const data = await response.json().catch(() => null);
  if (ticket !== generation) throw new Error('会话已切换，请重新操作');
  if (!response.ok) {
    if ((response.status === 401 || response.status === 403) && !path.endsWith('/auth/login')) { clearSession(); error.value = data?.message || `访问已失效（${response.status}），请重新登录`; }
    throw new Error(data?.message || `请求未完成（${response.status}），请稍后重试`);
  }
  if (!data || typeof data !== 'object') throw new Error('服务响应异常，请刷新重试');
  return data;
}
async function run(action: () => Promise<void>) {
  if (busy.value) return;
  busy.value = true; error.value = ''; notice.value = '';
  try { await action(); } catch (e) { error.value = e instanceof Error ? e.message : '操作未完成，请重试'; }
  finally { busy.value = false; }
}
async function load(offset = 0) {
  const ticket = ++pageGeneration, selectedTab = tab.value; loading.value = true; error.value = '';
  try {
    const query = new URLSearchParams({ cursor: String(offset), limit: '20', ...(selectedTab === 'employees' ? { search: search.value.trim() } : {}) });
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
  if (!me.must_change_password) { departments.value = await api('/api/admin/console/departments'); await load(); }
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
  editor.value = type; detail.value = null;
  if (type === 'create') form.value = { account: '', password: '', phone: '', name: '', departmentId: '' };
  if (type === 'employee' && row) form.value = { id: row.id, name: row.name, departmentId: row.department_id || '', status: row.status, version: row.version, reason: '' };
  if (type === 'priority') form.value = { id: row?.id || '', title: row?.title || '', text: row?.body?.text || '', pinned: row?.pinned ?? true, archived: row?.archived ?? false, position: row?.position ?? 0, version: row?.version ?? 0, reason: '' };
  await nextTick(); document.querySelector<HTMLInputElement>('.drawer input')?.focus();
}
function closeEditor() { if (busy.value) return; editor.value = ''; form.value = {}; detail.value = null; }
function keepDialogFocus(event: KeyboardEvent) {
  if (event.key !== 'Tab') return;
  const elements = Array.from(document.querySelectorAll<HTMLElement>('.drawer button:not(:disabled), .drawer input:not(:disabled), .drawer select:not(:disabled), .drawer textarea:not(:disabled)'));
  const first = elements[0], last = elements[elements.length - 1];
  if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
  else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
}
function save() { void run(async () => {
  let result: Row;
  if (editor.value === 'create') result = await api('/api/admin/console/employees', 'POST', form.value);
  else if (editor.value === 'employee') { const { id, ...body } = form.value; if (body.status === 'PENDING') delete body.status; result = await api(`/api/admin/console/employees/${encodeURIComponent(id)}/revisions`, 'POST', body); }
  else result = await api('/api/admin/console/priorities/revisions', 'POST', form.value);
  const created = editor.value === 'create';
  editor.value = ''; form.value = {};
  notice.value = created ? `员工账号 ${result.account} 已开通，首次登录须修改密码` : result.status === 'APPROVED' ? '修改已通过审核并生效' : '修改申请已提交，审核通过前原内容保持不变。可在修改记录查看进展。';
  await load(cursor.value);
}); }
function viewReview(row: Row) { void run(async () => { detail.value = await api(`/api/admin/console/reviews/${encodeURIComponent(row.id)}`); editor.value = 'review'; decisionReason.value = ''; }); }
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
        <section class="page-content"><div class="page-heading"><div><p class="eyebrow">{{ tab === 'employees' ? 'PEOPLE & ACCOUNTS' : tab === 'priorities' ? 'COMPANY PRIORITIES' : 'CHANGE HISTORY' }}</p><h1>{{ titles[tab] }}</h1><p class="muted">{{ tab === 'employees' ? '维护员工资料，为新同事开通工作账号。' : tab === 'priorities' ? '维护移动端展示的公司重点，让全员看见重要的事。' : '查看申请进度，处理分配给你的审核。' }}</p></div><button v-if="tab !== 'reviews'" class="primary" :disabled="busy" @click="openEditor(tab === 'employees' ? 'create' : 'priority')">＋ {{ tab === 'employees' ? '录入员工并开通账号' : '新增重要事项' }}</button></div>
          <p v-if="error" role="alert" class="alert error">{{ error }}</p><p v-if="notice" role="status" class="alert success">{{ notice }}</p>
          <div class="info-strip"><span aria-hidden="true">i</span>{{ tab === 'employees' ? '新建账号默认为员工，首次登录须改密。资料变更与停用将在审核通过后生效。' : tab === 'priorities' ? '最多置顶10项。新增、修改和撤下均保留审核记录，审核前原内容保持不变。' : '无有效审核人时申请保持待审，请联系组织管理员补齐直属关系；申请人不能自审。' }}</div>
          <section class="data-panel"><div class="panel-toolbar"><h2>{{ tab === 'employees' ? '员工目录' : tab === 'priorities' ? '事项列表' : '申请与审核' }} <span class="count">{{ total }}</span></h2><form v-if="tab === 'employees'" class="search-form" @submit.prevent="load()"><input v-model="search" aria-label="搜索员工" placeholder="搜索姓名、账号或手机号" maxlength="100"><button :disabled="busy || loading">搜索</button></form><button v-else :disabled="busy || loading" @click="load(cursor)">刷新列表</button></div>
            <div v-if="loading" role="status" class="empty-state">正在加载…</div>
            <div v-else-if="!rows.length" class="empty-state"><span aria-hidden="true">{{ error ? '!' : '◇' }}</span><h3>{{ error ? '暂时无法加载' : '暂无记录' }}</h3><p>{{ error ? '请检查服务连接后重试。' : tab === 'employees' ? '点击上方按钮，为第一位同事开通账号。' : tab === 'priorities' ? '从一件重要的事开始。' : '提交修改后，可以在这里查看进展。' }}</p><button v-if="error" @click="load(cursor)">重试加载</button></div>
            <div v-else class="table-scroll"><table><thead><tr v-if="tab === 'employees'"><th>员工</th><th>账号</th><th>手机号</th><th>部门</th><th>角色</th><th>账号状态</th><th>操作</th></tr><tr v-else-if="tab === 'priorities'"><th>事项名称</th><th>排序</th><th>展示设置</th><th>版本</th><th>操作</th></tr><tr v-else><th>修改类型</th><th>申请人</th><th>申请原因</th><th>审核状态</th><th>操作</th></tr></thead>
              <tbody><tr v-for="row in rows" :key="row.id"><template v-if="tab === 'employees'"><td><span class="person-name">{{ row.name }}</span></td><td>{{ row.account }}</td><td>{{ row.phone }}</td><td>{{ row.department || '未分配' }}</td><td>{{ stateName[row.role] || row.role }}</td><td><span class="badge" :class="{ inactive: row.status !== 'ACTIVE' }">{{ stateName[row.status] || row.status }}</span><small v-if="row.must_change_password" class="cell-note">首次登录待改密</small></td><td><button class="text-button" :disabled="busy" @click="openEditor('employee', row)">编辑资料</button></td></template>
                <template v-else-if="tab === 'priorities'"><td class="title-cell"><strong>{{ row.title }}</strong><small>{{ row.body?.text }}</small></td><td>{{ row.position }}</td><td><span class="badge" :class="{ inactive: row.archived }">{{ row.archived ? '已撤下' : row.pinned ? '置顶展示' : '普通展示' }}</span></td><td>v{{ row.version }}</td><td><button class="text-button" :disabled="busy" @click="openEditor('priority', row)">编辑事项</button></td></template>
                <template v-else><td>{{ kindName[row.kind] || row.kind }}</td><td>{{ row.applicant_name || '—' }}</td><td class="title-cell">{{ row.reason }}</td><td><span class="badge" :class="{ inactive: row.status !== 'APPROVED' }">{{ stateName[row.status] || row.status }}</span><small v-if="row.status === 'PENDING'" class="cell-note">{{ row.reviewer_configured ? `审核人：${row.reviewer_name}` : '尚未分配审核人' }}</small></td><td><button class="text-button" :disabled="busy" @click="viewReview(row)">查看详情</button></td></template></tr></tbody></table></div>
            <footer class="pagination"><span>共 {{ total }} 条<span v-if="rows.length"> · 当前 {{ cursor + 1 }}–{{ cursor + rows.length }}</span></span><div><button :disabled="loading || busy || cursor === 0" @click="load(Math.max(0, cursor - 20))">上一页</button><button :disabled="loading || busy || nextCursor >= total || nextCursor <= cursor" @click="load(nextCursor)">下一页</button></div></footer>
          </section><p class="page-footnote">潘多拉 · 企业协作管理</p>
        </section>
      </main>
      <div v-if="editor" class="drawer-shade" @click.self="closeEditor" @keydown.esc="closeEditor" @keydown="keepDialogFocus"><section class="drawer" role="dialog" aria-modal="true" aria-labelledby="editor-title"><div class="drawer-heading"><div><p class="eyebrow">{{ editor === 'create' ? 'NEW EMPLOYEE' : 'MANAGE' }}</p><h2 id="editor-title">{{ editor === 'create' ? '录入员工并开通账号' : editor === 'employee' ? '编辑员工资料' : editor === 'priority' ? '维护公司重要事项' : '修改申请详情' }}</h2></div><button aria-label="关闭面板" :disabled="busy" @click="closeEditor">×</button></div>
        <p v-if="error" role="alert" class="alert error">{{ error }}</p>
        <form v-if="editor !== 'review'" @submit.prevent="save"><template v-if="editor === 'create'"><label>员工姓名<input v-model="form.name" required maxlength="100" autocomplete="off"></label><label>登录账号<input v-model="form.account" required pattern="[a-zA-Z0-9_.\-]{3,64}" maxlength="64" autocomplete="off" placeholder="3–64位字母、数字或 _ . -"></label><label>手机号<input v-model="form.phone" type="tel" required pattern="1[3-9][0-9]{9}" maxlength="11"></label><label>初始密码<input v-model="form.password" type="password" required minlength="12" autocomplete="new-password"></label><p class="muted">至少12个字符，不超过72字节。请通过安全渠道交给员工，首次登录须改密。</p></template>
          <label v-if="editor === 'employee'">员工姓名<input v-model="form.name" required maxlength="100"></label>
          <label v-if="editor === 'create' || editor === 'employee'">所属部门<select v-model="form.departmentId" required><option value="" disabled>请选择部门</option><option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option></select></label>
          <label v-if="editor === 'employee'">账号状态<select v-model="form.status"><option v-if="form.status === 'PENDING'" value="PENDING" disabled>待确认（请使用成员审核）</option><option value="ACTIVE">启用</option><option value="DISABLED">停用</option></select></label>
          <template v-if="editor === 'priority'"><label>事项名称<input v-model="form.title" required maxlength="200"></label><label>事项说明<textarea v-model="form.text" rows="6" maxlength="20000"></textarea></label><label>排序位置<input v-model.number="form.position" type="number" min="0" max="10000" step="1" required></label><p class="muted">同类事项按数字从小到大排列。</p><label class="check-label"><input v-model="form.pinned" type="checkbox">置顶展示</label><label class="check-label"><input v-model="form.archived" type="checkbox">撤下此事项</label></template>
          <label v-if="editor !== 'create'">修改原因<textarea v-model="form.reason" required rows="3" maxlength="2000" placeholder="请说明此次修改的原因"></textarea></label>
          <div class="form-actions"><button type="button" :disabled="busy" @click="closeEditor">取消</button><button class="primary" :disabled="busy">{{ busy ? '正在提交…' : editor === 'create' ? '开通员工账号' : '提交修改申请' }}</button></div>
        </form>
        <div v-else-if="detail" class="review-detail"><p>申请人：{{ detail.applicant_name }}</p><p>状态：{{ stateName[detail.status] || detail.status }}</p><p>原因：{{ detail.reason }}</p><h3>拟修改内容</h3><dl><template v-for="(value, key) in detail.candidate" :key="key"><dt>{{ ({ name:'姓名',departmentId:'部门',title:'事项名称',text:'说明',pinned:'置顶',archived:'撤下',position:'排序',status:'账号状态',role:'角色' } as Record<string,string>)[key] || key }}</dt><dd>{{ String(key) === 'departmentId' ? departments.find(d => d.id === value)?.name || value : stateName[String(value)] || String(value ?? '—') }}</dd></template></dl><h3>审核记录</h3><p v-if="!detail.steps?.length" class="muted">尚未分配审核人，请补齐申请人的直属关系。</p><p v-for="step in detail.steps" :key="step.id">{{ step.reviewer_name || '审核人' }} · {{ stateName[step.state] || step.state }} {{ step.reason }}</p><template v-if="canDecide"><label>审核意见<textarea v-model="decisionReason" rows="3" maxlength="2000" placeholder="驳回时必填"></textarea></label><div class="form-actions"><button :disabled="busy" @click="decide(false)">驳回申请</button><button class="primary" :disabled="busy" @click="decide(true)">通过审核</button></div></template></div>
      </section></div>
    </div>
  </div>
</template>
