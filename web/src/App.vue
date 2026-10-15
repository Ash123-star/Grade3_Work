<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from 'vue';
import { VueFlow } from '@vue-flow/core';
type Data = Record<string, any>;
const token = ref(sessionStorage.getItem('workpanel-token') ?? '');
const account = ref(''), password = ref(''), error = ref(''), message = ref(''), busy = ref(false);
const needsPassword = ref(false), oldPassword = ref(''), newPassword = ref('');
const scopes = ref<Data[]>([]), scope = ref<Data>({domain: 'PERSONAL'}), preferences = ref<Data>({}), knowledge = ref<Data>({}), analysis = ref<Data>({});
const memories = ref<Data[]>([]), evidence = ref<Data[]>([]), panel = ref('');
let timer: ReturnType<typeof setTimeout> | undefined, forgetTimer: ReturnType<typeof setTimeout> | undefined, generation = 0;
const output = computed<Data>(() => analysis.value.output ?? {});
const personal = computed(() => scope.value.domain === 'PERSONAL');
const working = computed(() => ['QUEUED','RUNNING'].includes(analysis.value.state));
const qualityLabel = (value: string) => ({ LIMITED: '证据有限', INSUFFICIENT: '信息不足' }[value] ?? value);
const claimLabel = (value: string, provenance: string) => value === 'FACT' && provenance === 'SELF_REPORTED' ? '本人记录' : ({ FACT: '业务记录', OBSERVATION: '待核实观察', HYPOTHESIS: '待验证方向' }[value] ?? value);
const sourceLabel = (value: string) => ({ SELF_REPORTED: '本人提供', BUSINESS_EVENT: '业务事件', AI_EXTRACTED: 'AI 候选' }[value] ?? value);
async function api(method: string, path: string, body?: Data, query?: Data, headers: Record<string,string> = {}) {
  const url = `/api${path}${query ? '?' + new URLSearchParams(query).toString() : ''}`;
  const response = await fetch(url, {method, headers: {'Authorization': `Bearer ${token.value}`, ...(body ? {'Content-Type':'application/json'} : {}), ...headers}, body: body ? JSON.stringify(body) : undefined});
  const data = await response.json();
  if (!response.ok) throw new Error(data.message ?? `请求失败：${response.status}`);
  return data;
}
async function action(work: () => Promise<void>) { error.value = ''; try { await work(); } catch(e) { error.value = String(e); } }
async function login() { await action(async () => {
  const result = await api('POST','/auth/login',{account:account.value,password:password.value});
  token.value = result.token;oldPassword.value=password.value;password.value = ''; sessionStorage.setItem('workpanel-token', token.value);
  needsPassword.value=Boolean(result.user.must_change_password);
  if (!needsPassword.value) {oldPassword.value='';await load();}
}); }
async function changePassword() {await action(async()=>{await api('POST','/auth/password',{oldPassword:oldPassword.value,newPassword:newPassword.value});logout();message.value='密码已更新，请重新登录';});}
function logout() { generation++; clearTimeout(timer); clearTimeout(forgetTimer); token.value='';sessionStorage.removeItem('workpanel-token');analysis.value={};preferences.value={};knowledge.value={};scopes.value=[];memories.value=[];evidence.value=[];panel.value='';needsPassword.value=false;oldPassword.value='';newPassword.value=''; }
async function load() {
  const ticket = ++generation; clearTimeout(timer); busy.value=true;analysis.value={};memories.value=[];evidence.value=[];panel.value='';
  try {
    const result = await api('GET','/ai-maps/development',undefined,scope.value);
    const status = await api('GET','/ai-memories/knowledge-status',undefined,scope.value);
    const prefs = personal.value ? await api('GET','/ai-memories/preferences/me') : {};
    if(ticket!==generation) return;
    scopes.value=result.scopes;analysis.value=result.analysis;knowledge.value=status;preferences.value=prefs;memories.value=[];evidence.value=[];panel.value='';
    if(working.value) poll(result.analysis.id,ticket);
  } finally { if(ticket===generation) busy.value=false; }
}
function poll(id: string,ticket: number) {
  clearTimeout(timer);timer=setTimeout(() => action(async()=>{
    const result = await api('GET',`/ai-maps/development/jobs/${id}`);if(ticket!==generation) return;analysis.value=result;if(working.value) poll(id,ticket);
  }),1500);
}
async function generate() { await action(async()=>{
  const result=await api('POST','/ai-maps/development/jobs',scope.value,undefined,{'Idempotency-Key':crypto.randomUUID()});analysis.value=result;poll(result.id,generation);
}); }
async function saveGoal() { await action(async()=>{
  await api('PUT','/ai-memories/preferences/me',{version:preferences.value.version ?? 0,explicitGoals:preferences.value.explicit_goals ?? '',responsePreferences:preferences.value.response_preferences ?? ''});message.value='目标已保存，旧分析已失效';await load();
}); }
async function manage() { await action(async()=>{const result=await api('GET','/ai-memories',undefined,scope.value);memories.value=result.items;panel.value='memory';}); }
async function sources() { await action(async()=>{const result=await api('GET',`/ai-maps/development/${analysis.value.id}/evidence`);evidence.value=result.items;panel.value='evidence';}); }
async function edit(item?: Data) { const content=prompt(item ? '纠正经历或观察；正式业务事实请在原记录修订' : '补充经历与成果',item?.content ?? '');if(!content?.trim()) return;const reason=personal.value?'本人补充或纠正':prompt('组织变更理由（提交独立审核）') ?? '';await action(async()=>{
  const result = item ? await api('POST',`/ai-memories/${item.id}/revisions`,{version:item.version,reason,candidate:{content}}) : await api('POST','/ai-memories',{...scope.value,content,category:'EXPERIENCE',claimType:'FACT',reason});
  message.value=result.status==='PENDING'?'已提交审核，尚未生效':result.message ?? '记忆已更新';await load();await manage();
}); }
async function confirmMemory(item: Data) { await action(async()=>{const result=await api('POST',`/ai-memories/${item.id}/confirm`,{version:item.version,reason:'确认候选观察'});message.value=result.status==='PENDING'?'等待独立审核':'已确认，仍保留观察类别';await load();await manage();}); }
async function forget(item: Data) { if(!confirm('停止当前范围使用这条来源的记忆？原始业务记录保留。')) return;await action(async()=>{
  const job=await api('DELETE',`/ai-memories/${item.id}`,undefined,undefined,{'If-Match':String(item.version)});message.value='已停止使用，后台正在清理索引与图谱';await load();await manage();watchForget(job.id,generation);
}); }
function watchForget(id: string,ticket: number) {
  clearTimeout(forgetTimer); forgetTimer=setTimeout(async()=>{
    try {
      const job=await api('GET',`/ai-memories/forget-jobs/${id}`);
      if(ticket!==generation) return;
      if(job.state==='SUCCEEDED') message.value='记忆及关联索引已清理';
      else if(job.state==='FAILED') error.value=job.error ?? '记忆清理失败，请稍后重试';
      else watchForget(id,ticket);
    } catch(e) { if(ticket===generation) error.value=String(e); }
  },1800);
}
async function feedback(item: Data) { await action(async()=>{await api('POST',`/ai-maps/development/${analysis.value.id}/feedback`,{itemKey:item.key,type:'UNHELPFUL',comment:''},undefined,{'Idempotency-Key':crypto.randomUUID()});message.value='反馈已记录，可调整目标后重新分析';}); }
const nodes = computed(() => [
  ...(output.value.facts ?? []).map((f:Data,i:number)=>({id:`fact-${i}`,position:{x:0,y:i*110},data:{label:f.text}})),
  ...(output.value.directions ?? []).map((d:Data,i:number)=>({id:`direction-${i}`,position:{x:450,y:i*150},data:{label:`待验证方向：${d.text}`}}))
]);
const edges = computed(()=> (output.value.facts ?? []).flatMap((f:Data,i:number)=>(output.value.directions ?? []).flatMap((d:Data,j:number)=> d.sourceIds?.some((id:string)=>f.sourceIds?.includes(id)) ? [{id:`e-${i}-${j}`,source:`fact-${i}`,target:`direction-${j}`,label:'参考证据'}] : [])));
onBeforeUnmount(()=>{generation++;clearTimeout(timer);clearTimeout(forgetTimer);});
if(token.value) action(async()=>{const user=await api('GET','/auth/me');needsPassword.value=Boolean(user.must_change_password);if(!needsPassword.value) await load();});
</script>

<template>
  <main>
    <header><div><small>AI 地图</small><h1>成长与发展地图</h1></div><button v-if="token" @click="logout">退出</button></header>
    <p v-if="error" class="error" role="alert">{{error}}</p><p v-if="message" role="status">{{message}}</p>
    <form v-if="!token" class="card login" @submit.prevent="login"><h2>登录企业服务</h2><label>账号<input v-model="account" autocomplete="username" required></label><label>密码<input v-model="password" type="password" autocomplete="current-password" required></label><button class="primary">登录</button></form>
    <form v-else-if="needsPassword" class="card login" @submit.prevent="changePassword"><h2>首次登录修改密码</h2><label>原密码<input v-model="oldPassword" type="password" autocomplete="current-password" required></label><label>新密码<input v-model="newPassword" type="password" autocomplete="new-password" minlength="12" required></label><button class="primary">修改并重新登录</button></form>
    <template v-else>
      <nav aria-label="分析数据范围"><button v-for="s in scopes" :key="s.domain+s.scopeId" :class="{primary:scope.domain===s.domain && (!scope.scopeId || scope.scopeId===s.scopeId)}" @click="scope={domain:s.domain,scopeType:s.scopeType,scopeId:s.scopeId};action(load)">{{s.label}}</button><button @click="manage">管理记忆</button></nav>
      <section v-if="personal" class="card"><h2>我的目标与偏好</h2><p>仅本人可见；保存后下一次分析使用新目标。</p><label>希望发展的方向<textarea v-model="preferences.explicit_goals" maxlength="2000"></textarea></label><label>建议偏好与可投入时间<textarea v-model="preferences.response_preferences" maxlength="2000"></textarea></label><button @click="saveGoal">保存目标</button></section>
      <section class="card"><p>有效记忆 {{knowledge.memories ?? 0}} 条 · 已索引 {{knowledge.indexedMemories ?? 0}} 条 · 更新中 {{knowledge.indexingMemories ?? 0}} 条 · 待确认 {{knowledge.candidates ?? 0}} 条</p><button class="primary" :disabled="busy || working" @click="generate">{{working?'正在检索证据并生成分析…':'更新分析'}}</button><button v-if="working" @click="action(async()=>{await api('DELETE',`/ai-maps/development/jobs/${analysis.id}`);await load()})">取消</button></section>
      <p v-if="['STALE','FAILED','CANCELLED'].includes(analysis.state)" class="error">{{analysis.error ?? '分析已取消，可重新生成'}}</p>
      <template v-if="output.summary">
        <section class="card"><h2>{{output.summary}}</h2><p>生成于 {{output.generatedAt}} · {{qualityLabel(output.basisQuality)}}</p><p v-if="output.retrieval?.degradedReason">{{output.retrieval.degradedReason}}</p><button @click="sources">查看 RAG 分析依据</button></section>
        <section v-if="nodes.length" class="card graph"><VueFlow :nodes="nodes" :edges="edges" fit-view-on-init :nodes-connectable="false" @node-click="sources" /><div class="mobile-path"><h2>发展路径</h2><p v-for="f in output.facts" :key="f.text">{{f.text}}</p><p v-for="d in output.directions" :key="d.text">→ {{d.text}}</p></div></section>
        <section class="card"><h2>经历与成果</h2><article v-for="f in output.facts" :key="f.text"><p>{{f.text}}</p><small>{{claimLabel(f.claimType,f.provenance)}} · {{sourceLabel(f.provenance)}}</small></article></section>
        <section class="card"><h2>可以验证的方向</h2><article v-for="d in output.directions" :key="d.text"><h3>{{d.text}}</h3><p>方向推测 · {{d.conditions?.join('；')}}</p></article><h3>还缺哪些信息</h3><ul><li v-for="gap in output.gaps" :key="gap">{{gap}}</li></ul></section>
        <section class="card"><h2>下一步实践建议</h2><article v-for="s in output.suggestions" :key="s.key"><h3>{{s.text}}</h3><p>验证方式：{{s.validation}}</p><button @click="feedback(s)">这条建议不合适</button></article></section>
      </template>
      <section v-else-if="!busy && !working" class="card"><h2>从有效工作记录开始</h2><p>提交日志、补充成果与目标，再更新分析。证据不足时会说明信息缺口。</p></section>
      <aside v-if="panel" class="drawer" aria-label="记忆与证据"><button @click="panel=''">关闭</button><template v-if="panel==='memory'"><h2>记忆知识库</h2><button @click="edit()">补充经历</button><p>前 30 条；原始记录不会因停止记忆被删除。</p><article v-for="m in memories" :key="m.id"><p>{{m.content}}</p><small>{{claimLabel(m.claim_type,m.provenance)}} · {{m.status==='CANDIDATE'?'待确认':'已生效'}} · 来源版本 {{m.source_version}}</small><div><button @click="edit(m)">纠正</button><button v-if="m.status==='CANDIDATE'" @click="confirmMemory(m)">确认观察</button><button @click="forget(m)">停止记忆</button></div></article></template><template v-else><h2>RAG 分析依据</h2><article v-for="e in evidence" :key="e.chunkId"><p>{{e.text}}</p><small>{{sourceLabel(e.provenance)}} · 来源版本 {{e.version}}</small></article></template></aside>
    </template>
  </main>
</template>
