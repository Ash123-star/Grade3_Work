<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { readWorkEvents, WorkEventCursor } from './workEvents';
import { parseWorkItem, parseWorkPage, parseWorkCapabilities, parseWorkDeletion, parseWorkAttachment, WorkContractError, type WorkItem } from './workContract';
type Data = Record<string, any>;
const props = defineProps<{ token: string }>();
const selectedTask=ref<Data|null>(null), authorizationPolicy=ref<Data|null>(null);
const requestKey=()=>crypto.randomUUID();
const displayDate=(value:string)=>value?new Intl.DateTimeFormat('zh-CN',{timeZone:'Asia/Shanghai',dateStyle:'long',timeStyle:'short'}).format(new Date(value)):'';
const items=ref<WorkItem[]>([]), current=ref<WorkItem|null>(null), text=ref(''), files=ref<Data[]>([]), error=ref(''), busy=ref(false), settings=ref(false), grants=ref<Data[]>([]);
const nextCursor=ref(-1), pageCount=ref(1), listLoading=ref(false), listLoaded=ref(false);
const resultHeading=ref<HTMLElement|null>(null), composerInput=ref<HTMLTextAreaElement|null>(null);
const grantAction=ref('CREATE_TASK'), grantTarget=ref(''), grantDays=ref(7), grantSearch=ref(''), options=ref<Data[]>([]);
const confirmationLabel=computed(()=>{const actions=current.value?.plan?.actions??[];if(actions.some((a:Data)=>a.similarTasks?.length))return '仍然创建任务';return actions.length===1?({CREATE_TASK:'创建任务',SUBMIT_DELIVERY:'提交反馈',CHECK_DELIVERY:'检查材料',REQUEST_RESCHEDULE:'提交改期申请',REQUEST_REASSIGNMENT:'提交转派申请'} as Record<string,string>)[actions[0].type]??'确认办理':`确认办理 ${actions.length} 项`;});
let generation=0, detailSerial=0, key=requestKey(), signature='', alive=true, refreshing=false, refreshAgain=false;
let timer:ReturnType<typeof setInterval>|undefined, reconnect:ReturnType<typeof setTimeout>|undefined, stream:AbortController|undefined;
const requests=new Set<AbortController>();
const labels:Record<string,string>={QUEUED:'正在整理',PREPARING:'正在整理',READY:'准备办理',EXECUTING:'正在办理',RECONCILING:'正在核对结果',CANCEL_REQUESTED:'正在停止',WAITING_INPUT:'需要补充',WAITING_CONFIRMATION:'请你核对',WAITING_REVIEW:'等待复核',SUCCEEDED:'已办妥',PARTIAL:'还有事项待处理',FAILED:'暂时未能处理',CANCELLED:'已停止'};
function stateLabel(item:Data){if(item.state!=='SUCCEEDED')return labels[item.state]??'办理中';const result=item.result??{};return ({NEEDS_FIX:'需要补充材料',UNVERIFIABLE:'有些内容需核对',STALE:'需要重新检查',PASS:'材料已核对'} as Record<string,string>)[result.report?.state]??(result.kind==='TASK_CREATED'?'任务已创建':result.summary==='已提交，等待验收'?'已提交反馈':'已处理');}
class StaleResponse extends Error {}
class WorkError extends Error {constructor(message:string,readonly status=0,readonly code=''){super(message);}}
const errorMessage=(error:unknown)=>error instanceof WorkError||error instanceof WorkContractError?error.message:'暂时没能处理，内容已保留，请稍后重试';
function stopStream(){clearTimeout(reconnect);stream?.abort();stream=undefined;}
function resetView(){generation++;detailSerial++;stopStream();for(const request of requests)request.abort();requests.clear();refreshing=false;refreshAgain=false;listLoading.value=false;busy.value=false;current.value=null;selectedTask.value=null;text.value='';files.value=[];signature='';key=requestKey();}
function clearPrivate(message=''){resetView();items.value=[];nextCursor.value=-1;pageCount.value=1;listLoading.value=false;listLoaded.value=false;grants.value=[];options.value=[];authorizationPolicy.value=null;grantTarget.value='';grantSearch.value='';settings.value=false;error.value=message;}
function loseAccess(status:number){clearPrivate(status===401?'登录已失效，请重新登录':status===404?'这件事已被清除或无法查看':'你目前无法查看这些内容，请返回后重试');}
async function transport(path:string, init:RequestInit={}){
  const ticket=generation, token=props.token, controller=new AbortController();requests.add(controller);
  try{
    const response=await fetch(`/api/admin/workspace${path}`,{...init,headers:{...init.headers,Authorization:`Bearer ${token}`},signal:controller.signal});
    let data:any;try{data=await response.json();}catch{/* 鉴权失败即使无 JSON 正文，也必须清理私人内容。 */}
    if(!alive||ticket!==generation||token!==props.token)throw new StaleResponse();
    if(!response.ok){if([401,403,404].includes(response.status))loseAccess(response.status);throw new WorkError(({UNSUPPORTED_FILE:'请添加图片、PDF、Word或Excel文件',FILE_TYPE_MISMATCH:'文件格式与名称不一致，请重新导出后添加',FILE_LIMIT:'材料超出处理范围，请缩小或拆分后重试',FILE_TOO_LARGE:'文件过大，请缩小后重试',FILE_UNSAFE:'材料含有宏、外部链接或嵌入对象，请移除后重新导出',FILE_UNREADABLE:'材料暂时无法读取，请换一份完整文件',FILE_ENCRYPTED:'请先解除文件加密，再添加材料',OUTCOME_PENDING:'正在核对办理结果，请稍候再补充，也可以停止后续办理'} as Record<string,string>)[data?.code]??(response.status===409?'内容已更新，已为你重新读取，请核对后再试':response.status===403?'你目前无法办理这项操作':'暂时没能处理，内容已保留'),response.status,data?.code);}
    if(data===undefined)throw new WorkContractError();
    return data;
  }catch(e){if(!alive||ticket!==generation||controller.signal.aborted)throw new StaleResponse();throw e;}
  finally{requests.delete(controller);}
}
async function request(method:string,path:string,body?:Data,idem?:string){return transport(path,{method,headers:{...(body?{'Content-Type':'application/json'}:{}),...(idem?{'Idempotency-Key':idem}:{})},body:body?JSON.stringify(body):undefined});}
async function perform(action:()=>Promise<void>){if(busy.value)return;const ticket=generation,focused=document.activeElement,resultFocus=focused instanceof HTMLElement&&focused.closest('.work-result');busy.value=true;error.value='';try{await action();}catch(e){if(ticket===generation&&!(e instanceof StaleResponse))error.value=errorMessage(e);}finally{if(ticket===generation){busy.value=false;if(resultFocus)void nextTick(()=>{if(document.activeElement===document.body){if(focused.isConnected)focused.focus({preventScroll:true});else resultHeading.value?.focus({preventScroll:true});}});}}}
function accept(item:WorkItem){if(!current.value||item.id!==current.value.id||item.version>=current.value.version){const focused=document.activeElement,hadResultFocus=focused instanceof HTMLElement&&focused.closest('.work-result');current.value=item;if(hadResultFocus)void nextTick(()=>{if(!focused.isConnected&&document.activeElement===document.body)resultHeading.value?.focus({preventScroll:true});});}}
async function refreshDetail(){
  const id=current.value?.id;if(!id)return;const serial=++detailSerial, ticket=generation;
  try{const next=parseWorkItem(await request('GET',`/ai/work-items/${encodeURIComponent(id)}`),{id});if(serial===detailSerial&&ticket===generation&&current.value?.id===id)accept(next);}
  catch(e){if(ticket===generation&&!(e instanceof StaleResponse))error.value=errorMessage(e);}
}
async function refresh(count=pageCount.value){
  if(refreshing){refreshAgain=true;return;}refreshing=true;listLoading.value=true;const ticket=generation;
  try{const byId=new Map<string,WorkItem>();let cursor=0,next=-1;
    for(let page=0;page<count;page++){
      const list=parseWorkPage(await request('GET',`/ai/work-items?cursor=${cursor}&limit=30`));
      if(ticket!==generation)return;
      if(list.nextCursor!==-1&&list.nextCursor<=cursor)throw new WorkContractError();
      for(const item of list.items){const old=byId.get(item.id)??items.value.find(i=>i.id===item.id);byId.set(item.id,old&&old.version>item.version?old:item);}
      next=list.nextCursor;if(next<0)break;cursor=next;
    }
    items.value=Array.from(byId.values());nextCursor.value=next;pageCount.value=count;listLoaded.value=true;await refreshDetail();
  }catch(e){if(ticket===generation&&!(e instanceof StaleResponse))error.value=errorMessage(e);}
  finally{if(ticket===generation){refreshing=false;listLoading.value=false;if(refreshAgain){refreshAgain=false;void refresh();}}}
}
async function recoverConflict(error:unknown){if(error instanceof WorkError&&error.status===409)await refreshDetail();throw error;}
async function capabilities(){const value=parseWorkCapabilities(await request('GET','/ai/work-capabilities'));if(!value.enabled)throw new WorkError('办事助手暂时休息，内容已保留，请稍后再试');if(!value.configured)throw new WorkError('办事助手暂时无法连接，内容已保留，请稍后再试');return value;}
function startStream(){
  stopStream();const id=current.value?.id;if(!id||!props.token||document.hidden||!alive)return;
  const cursor=new WorkEventCursor(), ticket=generation, token=props.token;
  const connect=async()=>{
    if(ticket!==generation||current.value?.id!==id||document.hidden||!alive)return;
    const controller=new AbortController();stream=controller;
    try{
      const response=await fetch(`/api/admin/workspace/ai/work-items/${encodeURIComponent(id)}/stream`,{headers:{Authorization:`Bearer ${token}`,Accept:'text/event-stream','Last-Event-ID':cursor.value},signal:controller.signal});
      if(ticket!==generation||controller.signal.aborted)return;
      if([401,403,404].includes(response.status)){loseAccess(response.status);return;}
      if(response.status===400)cursor.value='0';
      if(!response.ok)throw new Error('STREAM_UNAVAILABLE');
      void refreshDetail();
      await readWorkEvents(response,controller.signal,event=>{
        if(ticket!==generation||current.value?.id!==id)return;
        if(event.event==='access-lost'){try{loseAccess(JSON.parse(event.data).status);}catch{loseAccess(403);}return;}
        if(event.event==='refresh'||cursor.accept(event))void refreshDetail();
      });
    }catch{/* 失联由 GET 与重连恢复，不把连接状态冒充业务结果。 */}
    finally{if(stream===controller)stream=undefined;if(ticket===generation&&current.value?.id===id&&!controller.signal.aborted&&!document.hidden&&alive)reconnect=setTimeout(connect,3000);}
  };
  void connect();
}
async function open(item:Data){if(busy.value)return;resetView();await perform(async()=>{accept(parseWorkItem(await request('GET',`/ai/work-items/${encodeURIComponent(item.id)}`),{id:item.id}));});}
function newItem(){if(busy.value)return;resetView();error.value='';void nextTick(()=>composerInput.value?.focus());}
async function upload(event:Event){const input=event.target as HTMLInputElement;const selected=Array.from(input.files??[]);await perform(async()=>{
  const limits=(await capabilities()).limits;
  if(selected.some(f=>!limits.formats.includes(f.name.split('.').pop()?.toLowerCase())))throw new WorkError('请添加图片、PDF、Word或Excel文件');
  if(selected.length+files.value.length>limits.files||selected.some(f=>f.size<1||f.size>limits.fileBytes)||selected.reduce((n,f)=>n+f.size,files.value.reduce((n,f)=>n+f.size,0))>limits.totalBytes)throw new WorkError(`一次最多${limits.files}份材料，每份不超过${limits.fileBytes/1048576}MB，总大小不超过${limits.totalBytes/1048576}MB`);
  for(const file of selected){const form=new FormData();form.append('file',file);files.value.push(parseWorkAttachment(await transport('/attachments?purpose=AI_WORK',{method:'POST',body:form})));}
});input.value='';}
async function send(){if(!text.value.trim()&&!files.value.length)return;await perform(async()=>{const limits=(await capabilities()).limits;if(text.value.trim().length>limits.text)throw new WorkError(`这次最多填写${limits.text}个字，请分开交代`);detailSerial++;const id=current.value?.id,body:Data={text:text.value.trim(),attachmentIds:files.value.map(f=>f.id)};if(selectedTask.value)Object.assign(body,{taskId:selectedTask.value.id,taskVersion:selectedTask.value.version});if(current.value)body.version=current.value.version;const nextSignature=JSON.stringify([id,body]);if(signature!==nextSignature){signature=nextSignature;key=requestKey();}
  try{accept(parseWorkItem(await request('POST',id?`/ai/work-items/${encodeURIComponent(id)}/messages`:'/ai/work-items',body,key),{id}));}catch(e){await recoverConflict(e);}
  selectedTask.value=null;text.value='';files.value=[];signature='';await refresh();});}
async function command(action:string){if(!current.value)return;await perform(async()=>{detailSerial++;const item=current.value!,body:Data={version:item.version};if(action==='confirm')Object.assign(body,{planVersion:item.planVersion,planHash:item.planHash,confirmationId:item.confirmationId,actions:item.steps.filter((s:Data)=>s.state==='WAITING').map((s:Data)=>s.step_key)});try{accept(parseWorkItem(await request('POST',`/ai/work-items/${encodeURIComponent(item.id)}/${action}`,body,`web-${item.id}-${action}-${item.version}`),{id:item.id}));}catch(e){await recoverConflict(e);}await refresh();});}
async function loadOptions(){const action=grantAction.value, search=grantSearch.value;const result=await request('GET',`/ai/work-authorization-options?action=${action}&search=${encodeURIComponent(search)}`);if(action===grantAction.value&&search===grantSearch.value){options.value=result.items;grantTarget.value='';}}
async function manage(){settings.value=!settings.value;if(settings.value)await perform(async()=>{grants.value=await request('GET','/ai/work-authorizations');authorizationPolicy.value=await request('GET','/ai/work-authorization-policy');grantAction.value=authorizationPolicy.value?.canCreate?'CREATE_TASK':'SUBMIT_DELIVERY';grantDays.value=Math.min(grantDays.value,authorizationPolicy.value?.maxDays??30);if(authorizationPolicy.value?.canCreate||authorizationPolicy.value?.canSubmit)await loadOptions();});}
async function remove(){if(!current.value||!window.confirm('清除这件事的私人对话和材料？已经办理的任务与交付会保留。'))return;await perform(async()=>{const item=current.value!;try{parseWorkDeletion(await transport(`/ai/work-items/${encodeURIComponent(item.id)}`,{method:'DELETE',headers:{'If-Match':String(item.version),'Idempotency-Key':`web-delete-${item.id}-${item.version}`}}),item.id);}catch(e){await recoverConflict(e);}resetView();await refresh();void nextTick(()=>composerInput.value?.focus());});}
async function authorize(){await perform(async()=>{if(!grantTarget.value.trim())throw new WorkError('请选择具体人员或任务');await request('POST','/ai/work-authorizations',{action:grantAction.value,scope:{[grantAction.value==='CREATE_TASK'?'ownerIds':'taskIds']:[grantTarget.value.trim()]},expiresAt:new Date(Date.now()+grantDays.value*86400000).toISOString()},requestKey());grants.value=await request('GET','/ai/work-authorizations');grantTarget.value='';});}
async function showDocument(id:string){const doc=await request('GET',`/procedures/${id}`);window.alert(`${doc.title}\n\n${doc.content}`);}
function visibility(){if(document.hidden)stopStream();else{void refresh();startStream();}}
watch(()=>current.value?.id,startStream);
watch(()=>props.token,()=>{clearPrivate();if(props.token)void refresh();});
onMounted(()=>{void refresh();timer=setInterval(()=>{if(!document.hidden&&!busy.value)void refresh();},15000);document.addEventListener('visibilitychange',visibility);});
onBeforeUnmount(()=>{alive=false;clearInterval(timer);document.removeEventListener('visibilitychange',visibility);clearPrivate();});
</script>

<template>
  <div class="workbench">
    <aside class="work-list card" aria-label="我的事项"><div class="work-actions"><h2>我的事项</h2><button :disabled="busy" @click="newItem">新建</button></div><button @click="refresh()" :disabled="busy||listLoading">刷新</button><p v-if="listLoading" role="status">正在读取事项…</p><p v-else-if="listLoaded&&!items.length">把事情交给我</p><button v-for="item in items" :key="item.id" class="work-entry" :disabled="busy" :aria-current="current?.id===item.id?'true':undefined" @click="open(item)"><strong>{{item.title}}</strong><span>{{stateLabel(item)}}</span></button><button v-if="nextCursor>=0" :disabled="busy||listLoading" @click="refresh(pageCount+1)">查看更多事项</button><button :disabled="busy" @click="manage">自动授权</button></aside>
    <section class="work-main">
      <p v-if="error" class="error" role="alert">{{error}}</p>
      <div v-if="settings" class="card"><h2>自动授权</h2><p>只办理指定人员或任务，到期自动停止，随时可撤回。</p><p v-if="authorizationPolicy&&!authorizationPolicy.canCreate&&!authorizationPolicy.canSubmit">公司暂未开放自动授权，你仍可逐次交代办理。</p><form v-else @submit.prevent="authorize"><label>操作<select v-model="grantAction" @change="perform(loadOptions)"><option v-if="authorizationPolicy?.canCreate" value="CREATE_TASK">创建任务</option><option v-if="authorizationPolicy?.canSubmit" value="SUBMIT_DELIVERY">检查通过后提交反馈</option></select></label><label>搜索<input v-model="grantSearch" @input="perform(loadOptions)" placeholder="输入姓名或任务名称"></label><label>{{grantAction==='CREATE_TASK'?'指定同事':'指定任务'}}<select v-model="grantTarget" required><option disabled value="">请选择</option><option v-for="option in options" :key="option.id" :value="option.id">{{option.label}}{{option.team||option.department?` · ${option.team||option.department}`:''}}</option></select></label><label>有效天数<input v-model.number="grantDays" type="number" min="1" :max="authorizationPolicy?.maxDays??30"></label><button :disabled="busy">开启授权</button></form><article v-for="grant in grants" :key="grant.id"><p>{{grant.action==='CREATE_TASK'?'创建任务':'提交反馈'}} · {{displayDate(grant.expires_at)}}到期</p><p>{{grant.scopeLabels?.join('、')}}</p><p v-if="grant.effective===false&&!grant.revoked_at">已失效，需要重新开启授权</p><button v-if="!grant.revoked_at" :disabled="busy" @click="perform(async()=>{await request('POST',`/ai/work-authorizations/${grant.id}/revoke`,{version:grant.version},requestKey());grants=await request('GET','/ai/work-authorizations')})">撤回授权</button><span v-else>已撤回</span></article></div>
      <div v-if="!current" class="card work-empty"><h2>把事情交给我</h2><div class="work-actions"><button @click="text='请根据材料整理任务'">截图建任务</button><button @click="text='请帮我检查交付材料'">检查交付</button><button @click="text='请帮我查找公司制度与模板'">找制度和模板</button></div></div>
      <template v-else>
        <article v-for="message in current.messages" :key="message.id" class="card"><p>{{message.body.text}}</p><p v-if="message.body.attachmentIds?.length">已添加 {{message.body.attachmentIds.length}} 份材料</p></article>
        <article class="card work-result" :key="current.state"><h2 ref="resultHeading" role="status" tabindex="-1">{{stateLabel(current)}}</h2><p>{{current.result?.summary}}</p><p>{{current.plan?.answer}}</p><p v-for="question in current.plan?.questions" :key="question">{{question}}</p><div v-if="current.state==='WAITING_CONFIRMATION'"><p v-for="action in current.plan?.actions" :key="action.label">{{action.label}}<br v-if="action.payload.deadline">{{action.payload.deadline}}</p><div v-for="action in current.plan?.actions" :key="action.label"><template v-if="action.similarTasks?.length"><p>已有相似任务，要继续处理原任务吗？</p><button v-for="task in action.similarTasks" :key="task.id" @click="perform(async()=>{const data=await request('GET',`/tasks/${task.id}`);selectedTask=data;text=`继续处理任务「${data.title}」`;})">{{task.title}}</button></template></div><button class="primary" :disabled="busy||current.planValid===false" @click="command('confirm')">{{confirmationLabel}}</button></div><button v-if="['FAILED','PARTIAL'].includes(current.state)||(current.state==='WAITING_CONFIRMATION'&&current.planValid===false)" :disabled="busy" @click="command('retry')">继续处理</button><button v-if="!['SUCCEEDED','CANCELLED'].includes(current.state)" :disabled="busy" @click="command('cancel')">停止后续办理</button><button :disabled="busy" @click="remove">清除私人记录</button><details v-if="current.plan?.sources?.length"><summary>查看依据</summary><button v-for="source in current.plan.sources" :key="source.id" @click="perform(()=>showDocument(source.id))">{{source.title}} · 第{{source.version}}版<span v-for="part in source.excerpts" :key="part.locator"> · {{part.locator}}</span></button></details></article>
        <article v-for="receipt in current.receipts" :key="receipt.step_key" class="card"><h3>{{receipt.result.summary}}</h3><p v-for="finding in receipt.result.report?.findings" :key="finding.id">{{finding.title}}：{{finding.message}} {{finding.locator}}</p></article>
      </template>
      <form class="card work-composer" @submit.prevent="send"><div class="work-actions"><span v-for="file in files" :key="file.id">{{file.filename}} <button type="button" :disabled="busy" :aria-label="`移除${file.filename}`" @click="files=files.filter(f=>f.id!==file.id)">移除</button></span></div><label class="work-input">要办什么<textarea ref="composerInput" v-model="text" placeholder="说说要办什么…" maxlength="10000" :disabled="busy" rows="3"></textarea></label><div class="work-actions"><label class="work-file">添加图片或文件<input type="file" multiple accept=".png,.jpg,.jpeg,.pdf,.docx,.xlsx" :disabled="busy" @change="upload"></label><button class="primary" :disabled="busy">{{busy?'正在发送…':'发送'}}</button></div></form>
    </section>
  </div>
</template>

<style scoped>
.workbench{display:grid;grid-template-columns:260px minmax(0,1fr);gap:24px;align-items:start}.work-list{position:sticky;top:20px}.work-actions{display:flex;gap:12px;flex-wrap:wrap;align-items:center;justify-content:space-between}.work-actions h2{margin:0}.work-entry{display:flex;width:100%;text-align:left;flex-direction:column;gap:10px;margin:12px 0}.work-entry span{font-size:15px}.work-main{min-width:0}.work-main .card{margin-bottom:18px}.work-empty{min-height:220px;display:grid;place-content:center;gap:24px}.work-result{background:#f1e7ff}.work-composer{background:#fffdf4;box-shadow:0 -4px 24px #43514b12}.work-input{display:block}.work-input textarea{width:100%;box-sizing:border-box;scroll-margin-block:24px}.work-file{display:block;max-width:100%}.work-file input{max-width:240px;display:block}button{min-height:48px}select{min-height:48px;width:100%}@media(max-width:760px){.workbench{grid-template-columns:1fr}.work-list{position:static}}@media(prefers-reduced-motion:no-preference){.work-result{animation:appear .22s ease-out}@keyframes appear{from{opacity:.4;transform:translateY(4px)}to{opacity:1;transform:none}}}
</style>
