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
function renderCompanyEntry() {
  const pendingCustomers = customers.filter(c => c.pending > 0).length;
  return `<div class="company-heading"><div><p class="eyebrow">PANDORA WORKSPACE</p><h3>一起，把事情做好。</h3></div><img src="../assets/generated_ui/sunshine/mascots/welcome.png" alt=""></div>
    <section class="customer-hub" aria-labelledby="hub-title">
      <div class="hub-heading"><img src="${asset('members')}" alt=""><div class="grow"><h3 id="hub-title">客户与业务</h3><p class="small">客户、会员和每一次服务</p></div></div>
      <div class="hub-actions"><button class="primary" data-action="directory">客户目录 <span aria-hidden="true">›</span></button>${canManage()?'<button class="secondary" data-action="new-customer">＋ 新增客户</button>':''}</div>
      <button class="hub-pending" data-action="pending-customers"><span>待完成服务的客户</span><b>${pendingCustomers} 位 <span aria-hidden="true">›</span></b></button>
    </section>
    <div class="section-title"><h3>工作视图</h3><span class="small">11 月 · 工作安排示意</span></div>
    <section class="company-work"><div class="work-week" aria-label="本周日期示意">${['一|23','二|24','三|25','四|26','五|27','六|28','日|29'].map(v=>{const [day,n]=v.split('|');return `<span class="${n==='26'?'today':''}"><small>${day}</small><b>${n}</b></span>`;}).join('')}</div>
    <div class="work-row"><span class="work-dot"></span><div><b>沙龙会后资料整理</b><p class="small">今天 15:00 · 许禾</p></div></div><div class="work-row"><span class="work-dot blue"></span><div><b>冬日活动筹备沟通</b><p class="small">今天 16:30 · 陈晨</p></div></div></section>
    <p class="small company-caption">客户入口置于工作视图上方；正式工作月历沿用现有页面。</p>`;
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
  if(action==='new-customer'){startEditor('new');return true;}
  if(action==='edit-customer'){startEditor('edit');return true;}
  if(action==='company-back'){transition(()=>{state.page='company';state.feedback='normal';},true);return true;}
  if(action==='pending-customers'){transition(()=>{state.page='directory';state.query='';state.owner='全部';state.type='全部';state.pending=true;state.listPage=0;});return true;}
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
