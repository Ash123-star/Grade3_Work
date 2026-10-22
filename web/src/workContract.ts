// REST 边界与 Android 使用同一 v1 契约。损坏响应不能被消费为成功或空历史。
type Data = Record<string, any>;
export type WorkItem = Data & {id: string; title: string; state: string; version: number};
export class WorkContractError extends Error {
  constructor(){super('暂时无法确认办理结果，请刷新后重试');}
}
const states=new Set(['QUEUED','PREPARING','READY','EXECUTING','SUCCEEDED','WAITING_INPUT','WAITING_CONFIRMATION','WAITING_REVIEW','PARTIAL','FAILED','RECONCILING','CANCEL_REQUESTED','CANCELLED']);
function object(value:unknown):Data{
  if(value===null||typeof value!=='object'||Array.isArray(value))throw new WorkContractError();
  return value as Data;
}
function objects(value:unknown):Data[]{
  if(!Array.isArray(value))throw new WorkContractError();
  return value.map(object);
}
function text(value:unknown,empty=false):asserts value is string{
  if(typeof value!=='string'||!empty&&!value.trim())throw new WorkContractError();
}
function strings(value:unknown){
  if(!Array.isArray(value))throw new WorkContractError();
  value.forEach(v=>text(v,true));
}
function integer(value:unknown,minimum:number):asserts value is number{
  if(typeof value!=='number'||!Number.isSafeInteger(value)||value<minimum)throw new WorkContractError();
}
function contract(value:unknown){
  const data=object(value);
  if(data.contractVersion!==1)throw new WorkContractError();
  return data;
}
function freeze<T>(value:T):T{
  if(value!==null&&typeof value==='object'){
    Object.values(value).forEach(freeze);
    Object.freeze(value);
  }
  return value;
}
function result(value:unknown){
  const data=object(value);
  if(data.summary!==undefined)text(data.summary,true);
  if(data.report!==undefined)objects(object(data.report).findings);
}
export function parseWorkItem(value:unknown,{summary=false,id}:{summary?:boolean;id?:string}={}):WorkItem{
  const data=summary?object(value):contract(value);
  text(data.id);text(data.title);integer(data.version,1);
  if(id!==undefined&&data.id!==id||!states.has(data.state))throw new WorkContractError();
  integer(data.planVersion??data.plan_version,0);result(data.result);
  if(!summary){
    integer(data.eventsCursor,0);
    for(const message of objects(data.messages)){
      text(message.id);const body=object(message.body);text(body.text,true);strings(body.attachmentIds);
    }
    for(const receipt of objects(data.receipts)){text(receipt.step_key);result(receipt.result);}
    for(const step of objects(data.steps)){text(step.step_key);text(step.state);}
    if(data.planValid!==undefined&&typeof data.planValid!=='boolean')throw new WorkContractError();
    for(const field of ['planHash','confirmationId'])if(data[field]!==undefined)text(data[field],true);
    if(data.plan!==undefined){
      const plan=object(data.plan);
      if(plan.answer!==undefined)text(plan.answer,true);
      if(plan.questions!==undefined)strings(plan.questions);
      for(const field of ['people','sources','actions'])if(plan[field]!==undefined)objects(plan[field]);
      for(const action of plan.actions??[]){
        text(action.type);text(action.label);object(action.payload);
        if(action.similarTasks!==undefined)objects(action.similarTasks);
      }
    }
  }
  return freeze(data) as WorkItem;
}
export function parseWorkPage(value:unknown):{items:WorkItem[];nextCursor:number}{
  const data=contract(value);integer(data.nextCursor,-1);
  const items=objects(data.items).map(item=>parseWorkItem(item,{summary:true}));
  if(new Set(items.map(item=>item.id)).size!==items.length)throw new WorkContractError();
  return {items,nextCursor:data.nextCursor};
}
export function parseWorkCapabilities(value:unknown):Data{
  const data=contract(value);
  for(const field of ['enabled','configured','executionEnabled','imageEnabled','canCreateTask']){
    if(typeof data[field]!=='boolean')throw new WorkContractError();
  }
  strings(data.actions);const limits=object(data.limits);
  for(const field of ['text','files','fileBytes','totalBytes'])integer(limits[field],1);
  strings(limits.formats);
  return freeze(data);
}
export function parseWorkDeletion(value:unknown,id:string):void{
  const data=object(value);
  if(data.id!==id||data.state!=='CANCELLED')throw new WorkContractError();
}
export function parseWorkAttachment(value:unknown):Data{
  const data=object(value);text(data.id);text(data.filename);integer(data.size,1);
  return freeze(data);
}
