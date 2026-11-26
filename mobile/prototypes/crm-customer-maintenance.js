/* Customer maintenance design only. All mutations are in-memory, reset on refresh. */
'use strict';
let draft = null;
let contactDraft = null;
let pendingLeave = null;
let contactClosing = false;
let notice = '';
let nextCustomer = 1;
customers.forEach(c => {
  c.version = 1;
  c.source = c.members.includes('club') ? '商城关联' : '线下建档';
  c.contacts = c.id === 'heyu' ? [
    {name:'顾言',role:'项目联系人',phone:c.contact},
    {name:'叶青',role:'行政对接',phone:'021 **** 0916'},
  ] : [];
});
function canManage() {
  return state.permission === 'manage' && !['forbidden','expired'].includes(state.feedback);
}
function canContact() { return canManage() && state.access === 'full'; }
function localDate() {
  return new Intl.DateTimeFormat('sv-SE', {timeZone:'Asia/Shanghai'}).format(new Date()).replaceAll('-', '.');
}
// Calendar scaffolding mirrors the existing DateControls and month timeline.
// It is only an entry-placement preview; production calendar/dispatch stays unchanged.
function companyToday(){const [y,m,d]=localDate().split('.').map(Number);return new Date(y,m-1,d);}
const companyCalendar={date:companyToday(),period:'月'};
const companySamples=[{a:2,b:6,title:'首页视觉评审',tone:''},{a:10,b:13,title:'接口联调',tone:'blue'},
  {a:16,b:19,title:'组件交付',tone:'blue'},{a:23,b:27,title:'冬日活动筹备',tone:''},
  {a:26,b:26,title:'沙龙资料整理',tone:'coral'},{a:30,b:30,title:'月末复盘',tone:'blue'}];
function companyItems(){return companyCalendar.date.getFullYear()===2026&&companyCalendar.date.getMonth()===10?companySamples:[];}
function renderCompanyHeader(){
  const d=companyCalendar.date;
  $('#app-header').innerHTML=`<div class="company-datebar" aria-label="公司日期导航"><button class="calendar-arrow" data-action="calendar-move" data-value="-1" aria-label="上一个${companyCalendar.period}">‹</button><button class="calendar-month" data-action="calendar-picker" aria-label="选择年月"><span class="calendar-month-label"><span>${d.getFullYear()}年</span><span>${d.getMonth()+1}月</span></span><span aria-hidden="true">⌄</span></button><button class="calendar-arrow" data-action="calendar-move" data-value="1" aria-label="下一个${companyCalendar.period}">›</button><button class="calendar-today" data-action="calendar-today" aria-label="回到今天"><span>今天</span></button></div>`;
}
function companyMonth(){
  const d=companyCalendar.date,y=d.getFullYear(),m=d.getMonth(),first=(new Date(y,m,1).getDay()+6)%7,days=new Date(y,m+1,0).getDate(),weeks=Math.ceil((first+days)/7),today=companyToday();
  let html=`<section class="company-month-grid" aria-label="公司月视图"><div class="company-weekdays">${['一','二','三','四','五','六','日'].map(x=>`<span>${x}</span>`).join('')}</div><div class="company-weeks">`;
  for(let w=0;w<weeks;w++){
    const start=w*7-first+1,end=start+6;
    html+='<div class="company-week"><div class="company-dates">';
    for(let i=0;i<7;i++){
      const n=start+i,other=n<1||n>days,isToday=!other&&y===today.getFullYear()&&m===today.getMonth()&&n===today.getDate();
      html+=other?'<span class="calendar-outside" aria-hidden="true"></span>':`<button data-action="calendar-day" data-value="${n}" class="calendar-day ${n===d.getDate()?'selected':''} ${isToday?'is-today':''}" aria-pressed="${n===d.getDate()}" aria-label="${m+1}月${n}日${isToday?'，今天':''}"><span>${n}</span></button>`;
    }
    html+='</div><div class="company-bars">';
    companyItems().filter(item=>item.a<=end&&item.b>=start).forEach(item=>{
      const a=Math.max(start,item.a)-start,b=Math.min(end,item.b)-start;
      html+=`<div class="calendar-bar ${item.tone}" style="grid-column:${a+1}/${b+2}" title="${item.title}">${item.title}</div>`;
    });
    html+='</div></div>';
  }
  return html+'</div></section>';
}
function companyAgenda(){
  const d=companyCalendar.date;
  let week='';
  if(companyCalendar.period==='周'){
    const start=new Date(d.getFullYear(),d.getMonth(),d.getDate()-(d.getDay()+6)%7);
    week=`<div class="company-agenda-week">${Array.from({length:7},(_,i)=>{const day=new Date(start.getFullYear(),start.getMonth(),start.getDate()+i);return `<span class="${day.getTime()===d.getTime()?'selected':''}"><small>${['一','二','三','四','五','六','日'][i]}</small><b>${day.getDate()}</b></span>`;}).join('')}</div>`;
  }
  const items=companyItems().filter(item=>item.a<=d.getDate()&&item.b>=d.getDate());
  return `<section class="company-agenda" aria-label="公司${companyCalendar.period}视图">${week}<h3>${d.getMonth()+1}月${d.getDate()}日 · 公司安排</h3>${items.length?items.map(item=>`<div class="company-agenda-item"><span class="calendar-bar ${item.tone}">${item.title}</span><p class="small">工作安排示例</p></div>`).join(''):'<p class="small">当前日期暂无示例安排</p>'}</section>`;
}
function renderCompanyEntry() {
  return `<div class="company-view-controls">${sections(['日','周','月'].map(x=>[x,x]),companyCalendar.period,'calendar-period')}<div class="company-action-row"><button class="secondary" data-action="company-dispatch"><img src="${asset('task')}" alt="">派发任务</button><button class="secondary customer-directory-entry" data-action="directory"><img src="${asset('members')}" alt="">客户目录</button></div></div>${companyCalendar.period==='月'?companyMonth():companyAgenda()}`;
}
function companyAction(action,value){
  if(action==='calendar-today'){companyCalendar.date=companyToday();render();return true;}
  if(action==='calendar-period'){companyCalendar.period=value;render();return true;}
  if(action==='calendar-day'){companyCalendar.date.setDate(Number(value));render({restore:true});return true;}
  if(action==='calendar-move'){
    const d=companyCalendar.date,step=Number(value);
    const next=companyCalendar.period==='月'?new Date(d.getFullYear(),d.getMonth()+step,1):new Date(d.getFullYear(),d.getMonth(),d.getDate()+step*(companyCalendar.period==='周'?7:1));
    if(next.getFullYear()>=1900&&next.getFullYear()<=2100)companyCalendar.date=next;
    render();return true;
  }
  if(action==='calendar-picker'){
    const d=companyCalendar.date;
    openSheet('选择年月',`<form id="company-month-form"><label for="company-month">跳转到月份</label><input id="company-month" type="month" min="1900-01" max="2100-12" required value="${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}"><div class="actions"><button type="button" class="secondary" data-action="close">取消</button><button type="submit" class="primary">确定</button></div></form>`);return true;
  }
  if(action==='company-dispatch'){
    openSheet('派发任务','<p class="small">沿用现有移动端派发任务入口。本原型仅预览客户目录入口的位置。</p><button class="primary wide" data-action="close">返回公司视图</button>');return true;
  }
  return false;
}
function renderEditableProfile() {
  const c=customer();
  const contacts=c.contacts.map((person,index)=>`<div class="contact"><div class="contact-heading"><strong>${esc(person.name)}${person.role?' · '+esc(person.role):''}</strong>${canContact()?`<button class="link-button" data-action="edit-contact" data-value="${index}" aria-label="编辑联系人${esc(person.name)}">编辑</button>`:''}</div><p class="small">${esc(person.phone||'未填写联系方式')}</p></div>`);
  return `<div class="section-title"><h3>基本资料</h3>${canManage()?'<button class="link-button" data-action="edit-customer">编辑资料</button>':'<span class="small">仅可查看</span>'}</div>
    ${fields([['客户类型',c.type+'客户'],['业务负责人',c.owner],['建档日期',c.since],['资料来源',c.source]])}
    <div class="section-title"><h3>${c.type==='企业'?'企业联系人':'联系信息'}</h3>${c.type==='企业'&&canContact()?'<button class="link-button" data-action="add-contact">＋ 添加</button>':''}</div>
    ${state.access==='limited'?'<div class="hint">联系信息未授权。可继续查看获准的会员与业务记录。</div>':c.type==='企业'?(contacts.length?`<div class="paper">${contacts.slice(0,2).join('')}</div>${contacts.length>2?`<details><summary>更多联系人 · ${contacts.length-2} 位</summary><div>${contacts.slice(2).join('')}</div></details>`:''}`:'<div class="hint">暂无联系人，可先添加一位日常对接人。</div>'):`<div class="paper"><div class="contact"><strong>${esc(c.name)}</strong><p class="small">${esc(c.contact||'未填写联系方式')}</p></div></div>`}
    <details><summary>补充说明</summary><p>${esc(c.note||'暂无补充说明。')}</p></details>`;
}
function startEditor(mode) {
  if(!canManage()) return;
  saveScroll();
  const c=mode==='edit'?customer():null;
  const fields={type:c?.type||'个人',name:c?.name||'',owner:c?.owner||'陈晨',phone:'',contactName:'',note:c?.note||''};
  draft={mode,fields,original:JSON.stringify(fields),returnPage:state.page,returnKey:key(),customerId:c?.id,version:c?.version,errors:{},message:'',conflict:false};
  state.page='editor';state.feedback='normal';render({focus:true});
}
function captureEditor() {
  if(!draft||!$('#customer-form'))return;
  for(const key of ['name','owner','phone','contactName','note']) {
    const el=$('#edit-'+key);if(el)draft.fields[key]=el.value;
  }
}
function formField(key,label,{required=false,phone=false,note=false,hint=''}={}) {
  const error=draft.errors[key];
  const attributes=`id="edit-${key}" name="${key}" ${required?'aria-required="true"':''} ${error?'aria-invalid="true"':''} aria-describedby="edit-${key}-hint edit-${key}-error"`;
  let control=key==='owner'?`<select ${attributes}>${['陈晨','许禾'].map(name=>`<option ${draft.fields[key]===name?'selected':''}>${name}</option>`).join('')}</select>`:note?`<textarea ${attributes} maxlength="500" rows="3">${esc(draft.fields[key])}</textarea>`:`<input ${attributes} value="${esc(draft.fields[key])}" ${phone?'type="tel" inputmode="tel" autocomplete="off"':'type="text" autocomplete="off"'} maxlength="${phone?30:100}" placeholder="${phone?'可后补，支持区号或国际号码':key==='contactName'?'主要对接人，可后补':''}">`;
  return `<div class="edit-field"><label for="edit-${key}">${label}${required?'<span class="required"> *</span>':'<span class="optional">可选</span>'}</label>${control}<p class="field-help" id="edit-${key}-hint">${hint}</p><p class="field-error" id="edit-${key}-error">${error?esc(error):''}</p></div>`;
}
function renderEditorHeader() {
  $('#app-header').innerHTML=`<button class="icon-button" data-action="cancel-edit" aria-label="返回并取消编辑">‹</button><div class="grow"><h2>${draft?.mode==='edit'?'编辑客户':'新增客户'}</h2><p>先记基本资料，其余可慢慢补齐</p></div>`;
}
function renderEditor() {
  if(!draft)return '';
  const f=draft.fields,existing=customers.find(c=>c.id===draft.customerId);
  const contactAllowed=state.access==='full';
  return `<div class="local-note">原型试填 · 仅当前页面有效，刷新后重置</div>
    <form id="customer-form" novalidate>
    ${draft.mode==='new'?`<div class="customer-type" aria-label="客户类型">${sections([['个人','个人客户'],['企业','企业客户']],f.type,'edit-type')}</div>`:`<p class="small edit-type-label">${esc(f.type)}客户 · ${esc(existing.source)} · 类型不可在此修改</p>`}
    <div id="editor-message" ${draft.message?'role="alert"':''}>${draft.message?`<div class="form-alert">${esc(draft.message)}${draft.conflict?'<button class="link-button" type="button" data-action="reload-edit">重新载入资料</button>':''}</div>`:''}</div>
    ${!canManage()?'<div class="form-alert">当前仅可查看，暂时不能保存修改。</div>':''}
    <div class="form-paper">${formField('name',f.type==='企业'?'企业名称':'客户姓名',{required:true})}
    ${contactAllowed&&f.type==='企业'&&draft.mode==='new'?formField('contactName','主要联系人'):''}
    ${contactAllowed&&(f.type==='个人'||draft.mode==='new')?formField('phone',f.type==='企业'?'联系人电话':'联系电话',{phone:true,hint:draft.mode==='edit'?(existing.contact?'当前 '+existing.contact+'；留空保留原号码。':'留空保留当前联系方式。'):''}):''}
    ${formField('owner','业务负责人',{required:true})}</div>
    ${!contactAllowed?'<p class="small">联系字段未授权，本次编辑不会改动这些字段。</p>':''}
    <details ${draft.errors.note?'open':''}><summary>补充信息 · 备注</summary><div>${formField('note','客户备注',{note:true})}</div></details>
    <p class="small">会员资格、权益和订单由对应业务记录维护。</p>
    </form>`;
}
function renderEditorDock() {
  $('#dock').innerHTML=`<div class="edit-actions"><button class="secondary" data-action="cancel-edit">取消</button><button class="primary" form="customer-form" type="submit" ${!canManage()||draft?.conflict?'disabled':''}>${draft?.mode==='edit'?'保存修改':'保存客户'}</button></div>`;
}
function afterMaintenanceRender() {
  if(state.page==='editor'&&state.access==='limited'&&draft){draft.fields.phone='';draft.fields.contactName='';}
  if(notice){const n=document.createElement('div');n.className='save-notice';n.setAttribute('role','status');n.textContent=notice;$('#content').prepend(n);notice='';}
}
function validPhone(value) {
  if(!value.trim())return true;
  return /^\+?[\d ()-]+$/.test(value)&&value.replace(/\D/g,'').length>=6&&value.replace(/\D/g,'').length<=20;
}
function validateCustomer() {
  const f=draft.fields,e={};
  if(!f.name.trim())e.name=f.type==='企业'?'请输入企业名称':'请输入客户姓名';
  else if(/[<>\x00-\x1f]/.test(f.name)||[...f.name.trim()].length>100)e.name='名称请使用 1–100 个文字字符，不包含尖括号或控制字符';
  if(state.access==='full'&&!validPhone(f.phone))e.phone='请填写有效电话，可含 +、区号、空格或连字符';
  if(f.type==='企业'&&f.phone.trim()&&!f.contactName.trim()&&draft.mode==='new')e.contactName='填写联系人电话时，请同时填写联系人姓名';
  if(!['陈晨','许禾'].includes(f.owner))e.owner='请选择可用的业务负责人';
  return e;
}
function normalizeName(s){return s.trim().replace(/\s+/g,' ').toLocaleLowerCase();}
function findDuplicates() {
  const f=draft.fields;
  return customers.filter(c=>c.id!==draft.customerId&&(normalizeName(c.name)===normalizeName(f.name)||(state.access==='full'&&f.phone.trim()&&[c.contact,...c.contacts.map(p=>p.phone)].some(p=>p&&!p.includes('*')&&p.replace(/\D/g,'')===f.phone.replace(/\D/g,'')))));
}
function submitCustomer(confirmed=false) {
  captureEditor();if(!draft||!canManage())return;
  draft.errors=validateCustomer();draft.message='';
  if(Object.keys(draft.errors).length){render();$('#edit-'+Object.keys(draft.errors)[0]).focus();return;}
  if(draft.conflict)return;
  const duplicates=findDuplicates();
  if(duplicates.length&&!confirmed){
    openSheet('先核对，避免重复建档',`<p class="small">获准查看的客户中有相同名称或联系方式。请先核对；系统不会自动合并。</p>${duplicates.map(c=>`<button class="duplicate-row" data-action="peek-duplicate" data-value="${c.id}"><strong>${esc(c.name)}</strong><span class="small">${c.type}客户 · ${esc(c.owner)} ›</span></button>`).join('')}<div class="actions"><button class="secondary" data-action="close">返回修改</button><button class="primary" data-action="confirm-duplicate">${draft.mode==='new'?'确认不同，仍新建':'确认无误，保存'}</button></div>`);return;
  }
  const existing=customers.find(c=>c.id===draft.customerId);
  if(state.saveResult==='conflict'||(existing&&existing.version!==draft.version)){
    draft.conflict=true;draft.message='资料已有更新，本次尚未保存。请重新载入后核对并编辑。';state.saveResult='success';render();$('#editor-message').scrollIntoView({block:'nearest'});return;
  }
  if(state.saveResult==='error'){
    draft.message='保存未成功，填写内容已保留，请重试。';state.saveResult='success';render();$('#editor-message').scrollIntoView({block:'nearest'});return;
  }
  const f=draft.fields;
  if(draft.mode==='new'){
    const id='local-'+nextCustomer++;
    const c={id,name:f.name.trim(),type:f.type,initial:[...f.name.trim()][0],subtitle:f.type==='企业'?'企业客户 · 新建档案':'个人客户 · 新建档案',owner:f.owner,since:localDate(),pending:0,contact:state.access==='full'?f.phone.trim():'',note:f.note.trim(),members:[],contacts:[],source:'手工建档',version:1};
    if(f.type==='企业'&&state.access==='full'&&f.contactName.trim())c.contacts.push({name:f.contactName.trim(),role:'主要联系人',phone:f.phone.trim()});
    customers.unshift(c);state.customer=id;state.tab='profile';state.member=0;state.businessPage=0;state.kind='services';
  }else{
    existing.name=f.name.trim();existing.initial=[...existing.name][0];existing.owner=f.owner;existing.note=f.note.trim();existing.version++;
    if(state.access==='full'&&f.type==='个人'&&f.phone.trim())existing.contact=f.phone.trim();
    state.customer=existing.id;state.tab='profile';
  }
  const restore=draft.mode==='edit';draft=null;state.page='customer';notice='已保存至原型示例 · 刷新后重置';render({restore,focus:true});
}
function isDirty(){captureEditor();return draft&&JSON.stringify(draft.fields)!==draft.original;}
function askLeave(fn) {
  if(!isDirty()){draft=null;fn();return;}
  pendingLeave=fn;
  openSheet('有尚未保存的内容','<p class="small">离开后，这次填写的内容不会保存。</p><div class="actions"><button class="secondary" data-action="discard-edit">放弃修改</button><button class="primary" data-action="keep-edit">继续编辑</button></div>');
}
function cancelEditor(){const page=draft?.returnPage||'directory';askLeave(()=>{state.page=page;render({restore:true,focus:true});});}
function guardSceneChange(scene){if(state.page!=='editor')return false;askLeave(()=>{state.page=scene==='entry'?'company':'directory';state.feedback='normal';render({focus:true});});return true;}
function contactInput(key,label,value,hint='') {
  return `<div class="edit-field"><label for="contact-${key}">${label}${key==='name'?'<span class="required"> *</span>':'<span class="optional">可选</span>'}</label><input id="contact-${key}" ${key==='phone'?'type="tel" inputmode="tel"':'type="text"'} value="${esc(value)}" maxlength="${key==='phone'?30:60}" aria-describedby="contact-${key}-error"><p class="field-help">${esc(hint)}</p><p class="field-error" id="contact-${key}-error"></p></div>`;
}
function showContact() {
  const d=contactDraft;
  openSheet(d.index===null?'添加联系人':'编辑联系人',`<form id="contact-form" novalidate><div class="local-note">${esc(customer().name)} · 原型示例</div><div id="contact-error" role="alert"></div>${contactInput('name','联系人姓名',d.fields.name)}${contactInput('role','对接职责',d.fields.role)}${contactInput('phone','联系电话',d.fields.phone,d.oldPhone?'当前 '+d.oldPhone+'；留空保留。':'可后补，支持区号或国际号码')}<div class="actions"><button type="button" class="secondary" data-action="close">取消</button><button type="submit" class="primary">保存联系人</button></div></form>`);
}
function captureContact(){if(!contactDraft||!$('#contact-form'))return;for(const key of ['name','role','phone'])contactDraft.fields[key]=$('#contact-'+key).value;}
function guardContactClose(){
  if(!contactDraft)return false;
  captureContact();
  if(JSON.stringify(contactDraft.fields)===contactDraft.original){contactDraft=null;return false;}
  if(contactClosing){showContact();contactClosing=false;return true;}
  contactClosing=true;
  openSheet('放弃联系人修改？','<p class="small">联系人还没有保存，是否继续填写？</p><div class="actions"><button class="secondary" data-action="discard-contact">放弃修改</button><button class="primary" data-action="keep-contact">继续编辑</button></div>');return true;
}
function saveContact(){
  captureContact();if(!contactDraft||!canContact())return;
  const d=contactDraft,f=d.fields,errors={};
  if(!f.name.trim())errors.name='请输入联系人姓名';
  if(!validPhone(f.phone))errors.phone='请填写有效电话';
  for(const key of ['name','role','phone']){const el=$('#contact-'+key);el.setAttribute('aria-invalid',String(Boolean(errors[key])));$('#contact-'+key+'-error').textContent=errors[key]||'';}
  if(Object.keys(errors).length){$('#contact-'+Object.keys(errors)[0]).focus();return;}
  if(state.saveResult!=='success'){
    const conflict=state.saveResult==='conflict';state.saveResult='success';syncTools();
    d.conflict=conflict;
    $('#contact-error').innerHTML=`<div class="form-alert">${conflict?'联系人资料已有更新，请重新打开并编辑。':'保存失败，内容已保留，请重试。'}${conflict?'<button type="button" class="link-button" data-action="reload-contact">重新载入联系人</button>':''}</div>`;return;
  }
  if(d.conflict)return;
  const c=customer();const person={name:f.name.trim(),role:f.role.trim(),phone:f.phone.trim()||d.oldPhone};
  if(d.index===null)c.contacts.push(person);else c.contacts[d.index]=person;
  c.version++;contactDraft=null;contactClosing=false;closeSheet(true);notice='联系人已保存至原型示例';render({restore:true,focus:true});
}
function maintenanceAction(action,value) {
  if(companyAction(action,value))return true;
  if(action==='new-customer'){startEditor('new');return true;}
  if(action==='edit-customer'){startEditor('edit');return true;}
  if(action==='company-back'){transition(()=>{state.page='company';state.feedback='normal';},true);return true;}
  if(action==='cancel-edit'||(action==='back'&&state.page==='editor')){cancelEditor();return true;}
  if(action==='edit-type'){captureEditor();draft.fields.type=value;draft.errors={};render();return true;}
  if(action==='discard-edit'){const fn=pendingLeave;pendingLeave=null;draft=null;closeSheet(true);fn?.();return true;}
  if(action==='keep-edit'){pendingLeave=null;closeSheet(true);return true;}
  if(action==='confirm-duplicate'){closeSheet(true);submitCustomer(true);return true;}
  if(action==='peek-duplicate'){
    const c=customers.find(c=>c.id===value);
    openSheet('已有客户 · 核对资料',`${fields([['客户名称',c.name],['客户类型',c.type],['负责人',c.owner],['联系方式',state.access==='full'?(c.contact||'未填写'):'未授权']])}<p class="small">这里只核对已有档案；本次填写仍保留在表单中。</p><button class="primary wide" data-action="duplicate-back">返回核对选择</button>`);return true;
  }
  if(action==='duplicate-back'){closeSheet(true);submitCustomer();return true;}
  if(action==='reload-edit'){
    const mode=draft.mode,returnPage=draft.returnPage;askLeave(()=>{state.page=returnPage;startEditor(mode);});return true;
  }
  if(action==='add-contact'||action==='edit-contact'){
    if(!canContact())return true;saveScroll();
    const index=action==='add-contact'?null:Number(value),old=index===null?null:customer().contacts[index];
    const fields={name:old?.name||'',role:old?.role||'',phone:''};
    contactDraft={index,fields,original:JSON.stringify(fields),oldPhone:old?.phone||'',conflict:false};contactClosing=false;showContact();return true;
  }
  if(action==='discard-contact'){contactDraft=null;contactClosing=false;closeSheet(true);return true;}
  if(action==='keep-contact'){contactClosing=false;showContact();return true;}
  if(action==='reload-contact'){const index=contactDraft.index;contactDraft=null;closeSheet(true);maintenanceAction(index===null?'add-contact':'edit-contact',String(index));return true;}
  return false;
}
document.addEventListener('submit',e=>{
  if(e.target.id==='company-month-form'){
    e.preventDefault();const value=$('#company-month').value;
    if(!/^(19\d{2}|20\d{2}|2100)-(0[1-9]|1[0-2])$/.test(value))return;
    const [y,m]=value.split('-').map(Number);companyCalendar.date=new Date(y,m-1,1);closeSheet();render();
  }
  if(e.target.id==='customer-form'){e.preventDefault();submitCustomer();}
  if(e.target.id==='contact-form'){e.preventDefault();saveContact();}
});
document.addEventListener('input',e=>{
  if(e.target.closest('#customer-form'))captureEditor();
  if(e.target.closest('#contact-form'))captureContact();
});
window.addEventListener('beforeunload',e=>{if(isDirty()||(contactDraft&&JSON.stringify(contactDraft.fields)!==contactDraft.original)){e.preventDefault();e.returnValue='';}});
$('#preview-permission').onchange=e=>{captureEditor();state.permission=e.target.value;render();};
$('#preview-save').onchange=e=>{state.saveResult=e.target.value;};
render();
