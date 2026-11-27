<script setup lang="ts">
import {nextTick,ref,onMounted,onBeforeUnmount} from 'vue';
import {FolderOpened, Refresh, SwitchButton} from '@element-plus/icons-vue';
type Row=Record<string,any>;
const token=ref(sessionStorage.getItem('hr-token')??''), account=ref(''), password=ref(''), error=ref(''), message=ref(''), busy=ref(false);
const capability=ref<Row|null>(null), people=ref<Row[]>([]), contracts=ref<Row[]>([]), total=ref(0), cursor=ref(0);
const uploadKey=ref(0);
const reminders=ref<Row[]>([]), selected=ref<Row|null>(null), history=ref<Row[]>([]);
const detailHeading=ref<HTMLElement|null>(null), formHeading=ref<HTMLElement|null>(null);
const form=ref<Row>({employeeId:'',title:'',startsOn:'',endsOn:'',attachmentId:'',recipients:[],version:0}), editing=ref('');
let operation: AbortController | undefined;
let detailTrigger: HTMLElement | undefined;
let editTrigger: HTMLElement | undefined;
let mounted = true;
function clearPrivate(){capability.value=null;people.value=[];contracts.value=[];reminders.value=[];selected.value=null;history.value=[];detailTrigger=undefined;cursor.value=0;total.value=0;reset();}
function clearSession(){token.value='';password.value='';sessionStorage.removeItem('hr-token');clearPrivate();}
async function request<T>(path:string, init:RequestInit, decode:(response:Response)=>Promise<T>):Promise<T>{
  const signal=operation!.signal;
  const headers=new Headers(init.headers);
  if(token.value)headers.set('Authorization','Bearer '+token.value);
  const response=await fetch('/api'+path,{...init,headers,signal,cache:'no-store'});
  signal.throwIfAborted();
  if(!response.ok){
    const data=await response.json().catch(()=>null);
    signal.throwIfAborted();
    if(response.status===401||response.status===403)clearSession();
    throw new Error(data?.message ?? (response.status===403 ? '人事权限已撤销或不足' : '企业服务返回异常，请稍后重试'));
  }
  const data=await decode(response);
  signal.throwIfAborted();
  return data;
}
function api(path:string,method='GET',body?:unknown){
  return request(path,{method,headers:body?{'Content-Type':'application/json'}:undefined,body:body?JSON.stringify(body):undefined},r=>r.json());
}
async function act(fn:()=>Promise<void>){
  if(busy.value)return;
  const current=operation=new AbortController();
  busy.value=true;error.value='';message.value='';
  try{await fn();}catch(e){if(mounted&&!current.signal.aborted)error.value=e instanceof Error?e.message:'请求失败';}
  finally{if(operation===current){operation=undefined;busy.value=false;}}
}
async function load(next=cursor.value){
  const access=await api('/hr/me');
  if((capability.value?.manage&&!access.manage)||(capability.value?.admin&&!access.admin))clearPrivate();
  const staff:Row[]=[];
  for(let offset=0;;offset+=100){const batch=await api('/hr/employees?cursor='+offset+'&limit=100');staff.push(...batch);if(batch.length<100)break;}
  const notifications=await api('/hr/reminders');
  const list=await api('/hr/contracts?cursor='+next+'&limit=20');
  capability.value=access;people.value=staff;reminders.value=notifications;contracts.value=list.items;total.value=list.total;cursor.value=next;
}
async function login(){await act(async()=>{const data=await api('/auth/login','POST',{account:account.value,password:password.value});password.value='';token.value=data.token;sessionStorage.setItem('hr-token',token.value);await load();});}
function logout(){
  const previous=token.value;
  operation?.abort();operation=undefined;busy.value=false;
  clearSession();error.value='';message.value='';
  if(previous)void fetch('/api/auth/logout',{method:'POST',headers:{Authorization:'Bearer '+previous},cache:'no-store'}).catch(()=>{});
}
function reset(){editTrigger=undefined;uploadKey.value++;editing.value='';form.value={employeeId:'',title:'',startsOn:'',endsOn:'',attachmentId:'',recipients:[],version:0};}
async function cancelEdit(){
  const trigger=editTrigger;
  reset();
  await nextTick();
  if(trigger?.isConnected)trigger.focus();
}
function reveal(heading:HTMLElement|null){
  heading?.focus({preventScroll:true});
  heading?.scrollIntoView({block:'start'});
}
async function upload(event:Event){const file=(event.target as HTMLInputElement).files?.[0];if(!file)return;await act(async()=>{form.value.attachmentId='';const b=new FormData();b.append('file',file);const data=await request('/attachments',{method:'POST',body:b},r=>r.json());form.value.attachmentId=data.id;message.value='附件已上传，请保存合同完成归档';});}
async function save(){await act(async()=>{await api('/hr/contracts'+(editing.value?'/'+editing.value:''),editing.value?'PUT':'POST',form.value);reset();await load();message.value='合同已归档';});}
async function view(id:string,event:MouseEvent){
  const trigger=event.currentTarget as HTMLElement;
  await act(async()=>{
    selected.value=null;history.value=[];detailTrigger=undefined;
    const contract=await api('/hr/contracts/'+id);
    const revisions=await api('/hr/contracts/'+id+'/history');
    selected.value=contract;history.value=revisions;detailTrigger=trigger;
    await nextTick();
    if(mounted&&token.value)reveal(detailHeading.value);
  });
}
async function closeDetail(){
  const trigger=detailTrigger;
  selected.value=null;history.value=[];detailTrigger=undefined;
  await nextTick();
  if(trigger?.isConnected)trigger.focus();
}
async function edit(row:Row,event:MouseEvent){
  const trigger=event.currentTarget as HTMLElement;
  await act(async()=>{
    const d=await api('/hr/contracts/'+row.id);
    editing.value=d.id;editTrigger=trigger;
    form.value={employeeId:d.employee_id,title:d.title,startsOn:String(d.starts_on).slice(0,10),endsOn:String(d.ends_on).slice(0,10),attachmentId:d.attachment_id,recipients:d.recipients,version:d.version};
    await nextTick();
    if(mounted&&token.value)reveal(formHeading.value);
  });
}
async function download(row:Row){await act(async()=>{const blob=await request('/attachments/'+row.attachment_id,{},r=>r.blob());const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='合同附件';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});}
async function grant(person:Row,event:Event){const level=(event.target as HTMLSelectElement).value;await act(async()=>{await api('/hr/grants/'+person.id,'PUT',{access:level,version:person.grant_version});await load();message.value='授权已更新';});}
async function duties(person:Row){await act(async()=>{await api('/hr/employees/'+person.id+'/duties','PUT',{duties:person.duties,version:person.duties_version});await load();message.value='职责已保存';});}
async function page(delta:number){await act(()=>load(Math.max(0,cursor.value+delta)));}
onMounted(()=>{if(token.value)void act(load);});
onBeforeUnmount(()=>{mounted=false;operation?.abort();});
</script>
<template><main class="hr-shell" :aria-busy="busy"><header class="hr-header"><div><div class="hr-category"><FolderOpened aria-hidden="true"/>人事管理</div><h1>员工档案与合同</h1></div><div v-if="token" class="hr-actions"><a v-if="capability?.admin" href="/">管理员后台</a><button aria-label="刷新" title="刷新" :disabled="busy" @click="act(load)"><Refresh aria-hidden="true"/></button><button aria-label="退出" title="退出" @click="logout"><SwitchButton aria-hidden="true"/></button></div></header>
<p v-if="error" role="alert">{{error}}</p><p v-if="message" role="status">{{message}}</p>
<form v-if="!token" @submit.prevent="login"><label>账号<input v-model="account" autocomplete="username" required></label><label>密码<input v-model="password" type="password" autocomplete="current-password" required></label><button :disabled="busy">登录人事入口</button></form>
<template v-else-if="capability">
<section><h2>我的合同提醒</h2><p v-if="!reminders.length">暂无到期提醒</p><p v-for="n in reminders" :key="n.id"><button :disabled="busy" @click="view(n.object_id,$event)">{{n.title}} · 到期日 <time>{{String(n.ends_on).slice(0,10)}}</time></button></p></section>
<section>
  <h2>员工档案</h2>
  <p v-if="!people.length">暂无员工</p>
  <article v-for="p in people" :key="p.id">
    <h3>{{ p.name }}</h3>
    <p>部门：{{ p.department_name || '未分配' }} · 岗位：{{ ({NONE:'未设置',GENERAL_MANAGER:'总经理',DEPUTY_GENERAL_MANAGER:'副总经理'} as Record<string,string>)[p.business_position] ?? p.business_position }}</p>
    <label>工作职责<textarea v-model="p.duties" :readonly="!capability.manage || busy" maxlength="4000"/></label>
    <button v-if="capability.manage" :disabled="busy" @click="duties(p)">保存职责</button>
    <template v-if="capability.admin">
      <p v-if="p.is_admin">合同权限：{{ p.status === 'ACTIVE' ? '管理员（角色授权）' : '管理员（账号未启用）' }}</p>
      <label v-else>合同权限
        <select :value="p.access" :disabled="busy" @change="grant(p,$event)">
          <option value="NONE">无授权</option>
          <option value="READ">只读</option>
          <option value="MANAGE">管理</option>
        </select>
      </label>
    </template>
  </article>
</section>
<section v-if="capability.manage">
  <h2 ref="formHeading" tabindex="-1">{{ editing ? '修订合同' : '归档合同' }}</h2>
  <form @submit.prevent="save">
    <fieldset :disabled="busy">
      <label>员工<select v-model="form.employeeId" aria-label="员工" required>
        <option value="">请选择</option>
        <option v-for="p in people" :key="p.id" :value="p.id">{{ p.name }}</option>
      </select></label>
      <label>合同名称<input v-model="form.title" maxlength="200" required></label>
      <label>开始日期<input v-model="form.startsOn" type="date" required></label>
      <label>到期日期<input v-model="form.endsOn" type="date" :min="form.startsOn" required></label>
      <label v-if="!editing">合同专用附件<input :key="uploadKey" type="file" @change="upload"></label>
      <p v-if="form.attachmentId">附件已就绪</p>
      <label>提醒接收人（可多选）<select v-model="form.recipients" multiple required>
        <option v-for="p in people.filter(p => p.status === 'ACTIVE' && (p.access !== 'NONE' || p.is_admin))"
          :key="p.id" :value="p.id">{{ p.name }}</option>
      </select></label>
      <p>接收人必须拥有合同访问权限，服务器会再次检查。</p>
      <button :disabled="!form.attachmentId">保存合同</button>
      <button type="button" @click="cancelEdit">取消</button>
    </fieldset>
  </form>
</section>
<section v-if="selected"><h2 ref="detailHeading" tabindex="-1">合同详情：{{selected.title}}</h2><p>{{selected.starts_on}} 至 {{selected.ends_on}}</p><button :disabled="busy" @click="download(selected)">下载此合同</button><h3>修订记录</h3><p v-for="v in history" :key="v.version">版本 {{v.version}} · {{v.snapshot.title}} · {{v.snapshot.starts_on}} 至 {{v.snapshot.ends_on}}</p><button :disabled="busy" @click="closeDetail">关闭详情</button></section>
<section><h2>已归档合同（{{total}}）</h2><p v-if="!contracts.length">暂无合同</p><article v-for="c in contracts" :key="c.id"><h3>{{c.title}}</h3><p>{{c.employee_name}} · {{String(c.starts_on).slice(0,10)}} 至 {{String(c.ends_on).slice(0,10)}}</p><button :disabled="busy" @click="view(c.id,$event)">查看详情</button><button :disabled="busy" @click="download(c)">下载合同</button><button v-if="capability.manage" :disabled="busy" @click="edit(c,$event)">修订</button></article><button :disabled="busy||cursor===0" @click="page(-20)">上一页</button><button :disabled="busy||cursor+20>=total" @click="page(20)">下一页</button></section>
</template></main></template>
<style scoped>
.hr-shell{max-width:1080px;margin:auto;padding:24px;color:#243b35;overflow-wrap:anywhere}
.hr-header,.hr-actions,.hr-category{display:flex;align-items:center;gap:12px;flex-wrap:wrap}
.hr-header{justify-content:space-between;border-bottom:2px solid #b8c9bd;padding:0 0 18px}
.hr-header h1{margin:6px 0 0;font-size:26px}.hr-category{font-size:14px;color:#3d6050}.hr-category svg,.hr-actions svg{width:18px;height:18px}
.hr-actions button{display:inline-grid;place-items:center;width:44px;height:44px;padding:0}
.hr-actions a{display:inline-flex;align-items:center;min-height:44px;color:#285746;text-underline-offset:3px}
.hr-shell section{margin-top:24px;padding:16px 0;border-top:1px solid #cbd6cd}.hr-shell section h2{margin:0 0 12px;font-size:19px}
.hr-shell h2[tabindex]{scroll-margin-top:16px}.hr-shell time{white-space:nowrap}
.hr-shell article{padding:14px 16px;background:#fff;border:1px solid #cbd6cd;border-radius:8px;margin:12px 0}.hr-shell article h3{margin:0}
.hr-shell form{max-width:540px}.hr-shell fieldset{border:0;margin:0;padding:0;min-width:0}.hr-shell label{display:flex;flex-direction:column;gap:6px;margin:12px 0}
.hr-shell input,.hr-shell select,.hr-shell textarea{box-sizing:border-box;min-height:44px;width:100%;min-width:0;padding:9px;border:1px solid #aebfb6;border-radius:6px;background:#fff;color:inherit;font:inherit}
.hr-shell button{min-height:44px;border:1px solid #aebfb6;border-radius:6px;background:#f4f8f4;color:inherit;margin:0 8px 8px 0;padding:8px 14px;cursor:pointer}
.hr-shell button:disabled{opacity:.6;cursor:default}.hr-shell button[type=submit],.hr-shell form button:not([type]){background:#285746;color:#fff}
.hr-shell [role=alert]{color:#942a26;background:#fff0eb}.hr-shell [role=status]{background:#e5f1e8}.hr-shell [role=alert],.hr-shell [role=status]{padding:12px;border-radius:6px}
.hr-shell textarea{min-height:70px;resize:vertical}.hr-shell :focus-visible{outline:2px solid #376b57;outline-offset:2px}
@media(max-width:480px){.hr-shell{padding:16px}.hr-header h1{font-size:22px}.hr-shell article{padding:12px}}
</style>
