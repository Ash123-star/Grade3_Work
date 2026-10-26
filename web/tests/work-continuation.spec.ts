import {test,expect,type Page} from '@playwright/test';
import {parseWorkItem,parseWorkPage,parseWorkCapabilities,parseWorkDeletion,WorkContractError} from '../src/workContract';
import {workFixture,workPage,workCapabilities} from './workFixtures';

const initial=()=>workFixture({id:'shared-work',title:'整理成本表',state:'WAITING_CONFIRMATION',version:3,planVersion:1,planHash:'hash-1',confirmationId:'confirm-1',planValid:true,messages:[{id:'m1',body:{text:'私人材料'}}],plan:{answer:'请核对后创建',questions:[],actions:[{type:'CREATE_TASK',label:'给李明创建成本表任务',payload:{deadline:'2026-11-01T09:00:00+08:00'}}]},steps:[{step_key:'action-1',state:'WAITING'}]});
async function session(page:Page){await page.addInitScript(()=>sessionStorage.setItem('workpanel-token','test-token'));}
const json=(body:unknown,status=200)=>({status,contentType:'application/json',body:JSON.stringify(body)});

test('v1 contract rejects incompatible identity versions and broken results without a success fallback',()=>{
  const valid=initial();
  const corrupt=[null,[],{...valid,contractVersion:2},{...valid,id:''},{...valid,state:'FINISHED'},{...valid,version:1.5},{...valid,planVersion:-1},{...valid,eventsCursor:NaN},{...valid,messages:[{id:'m',body:{text:'hello',attachmentIds:'wrong'}}]},{...valid,receipts:[{step_key:'a',result:{report:{findings:'wrong'}}}]},{...valid,steps:[{state:'WAITING'}]},{...valid,plan:{actions:[{type:'CREATE_TASK',label:'任务',payload:[]}]}}];
  for(const value of corrupt)expect(()=>parseWorkItem(value)).toThrow(WorkContractError);
  expect(()=>parseWorkItem(valid,{id:'other-work'})).toThrow(WorkContractError);
  expect(()=>parseWorkPage({...workPage(),nextCursor:0.5})).toThrow(WorkContractError);
  expect(()=>parseWorkPage(workPage([valid,valid]))).toThrow(WorkContractError);
  expect(()=>parseWorkCapabilities({...workCapabilities,limits:{}})).toThrow(WorkContractError);
  expect(()=>parseWorkDeletion({id:'other-work',state:'CANCELLED'},valid.id)).toThrow(WorkContractError);
  const accepted=parseWorkItem(valid);expect(Object.isFrozen(accepted)).toBe(true);expect(Object.isFrozen(accepted.messages[0].body.attachmentIds)).toBe(true);
});

test('history follows server pagination and keeps the newest duplicate when pages move',async({page})=>{
  await session(page);let badCursor=false;const cursors:string[]=[];
  const newest={...initial(),version:8,result:{summary:'最新结果'}};
  await page.route('**/api/**',async route=>{
    const url=new URL(route.request().url());let body:unknown={};
    if(url.pathname==='/api/auth/me')body={role:'ADMIN',must_change_password:false};
    else if(url.pathname==='/api/admin/workspace/ai-maps/development')body={scopes:[],analysis:{}};
    else if(url.pathname==='/api/admin/workspace/ai/work-items'){
      const cursor=url.searchParams.get('cursor')!;cursors.push(cursor);
      body=cursor==='0'?workPage([newest],30):workPage([{...newest,version:2},{...newest,id:'older-work',title:'上周的材料',version:1}],badCursor?30:-1);
    }
    await route.fulfill(json(body));
  });
  await page.goto('/legacy');await expect(page.getByRole('button',{name:'查看更多事项'})).toBeVisible();
  badCursor=true;await page.getByRole('button',{name:'查看更多事项'}).click();
  await expect(page.getByRole('alert')).toContainText('暂时无法确认');
  await expect(page.locator('.work-entry')).toHaveCount(1);
  badCursor=false;await page.getByRole('button',{name:'查看更多事项'}).click();
  await expect(page.locator('.work-entry')).toHaveCount(2);await expect(page.getByRole('button',{name:/上周的材料/})).toBeVisible();
  await page.getByRole('button',{name:'刷新',exact:true}).click();
  await expect.poll(()=>cursors.length).toBe(7);expect(cursors).toEqual(['0','0','30','0','30','0','30']);
  await expect(page.locator('.work-entry')).toHaveCount(2);
});

test('conflicting continuation immediately restores the current version and keeps text and materials',async({page})=>{
  await session(page);let item=initial(),attempts=0;const keys:string[]=[],versions:number[]=[];
  await page.route('**/api/**',async route=>{
    const request=route.request(),path=new URL(request.url()).pathname;let body:unknown={},status=200;
    if(path.endsWith('/stream')){await route.fulfill({contentType:'text/event-stream',body:': connected\n\n'});return;}
    if(path==='/api/auth/me')body={role:'ADMIN',must_change_password:false};
    else if(path==='/api/admin/workspace/ai-maps/development')body={scopes:[],analysis:{}};
    else if(path==='/api/admin/workspace/ai/work-capabilities')body=workCapabilities;
    else if(path==='/api/admin/workspace/attachments')body={id:'file-1',filename:'成本.pdf',size:4};
    else if(path==='/api/admin/workspace/ai/work-items')body=workPage([item]);
    else if(path.endsWith('/messages')){
      attempts++;keys.push(request.headers()['idempotency-key']);versions.push(request.postDataJSON().version);
      expect(request.postDataJSON().attachmentIds).toEqual(['file-1']);
      if(attempts===1){item={...item,version:5,plan:{...item.plan,answer:'另一端已更新，请核对'}};status=409;body={code:'VERSION_CONFLICT'};}
      else if(attempts===2){status=503;body={code:'INTERNAL',message:'private provider exception'};}
      else{item={...item,version:6,state:'WAITING_INPUT',result:{summary:'补充已收到'}};body=item;}
    }else if(path==='/api/admin/workspace/ai/work-items/shared-work')body=item;
    await route.fulfill(json(body,status));
  });
  await page.goto('/legacy');await page.getByRole('button',{name:/整理成本表/}).click();
  await page.getByRole('textbox',{name:'要办什么'}).fill('请使用新成本表');
  await page.locator('input[type=file]').setInputFiles({name:'成本.pdf',mimeType:'application/pdf',buffer:Buffer.from('data')});
  await expect(page.getByRole('button',{name:'移除成本.pdf'})).toBeVisible();
  await page.getByRole('button',{name:'发送',exact:true}).click();
  await expect(page.getByText('另一端已更新，请核对',{exact:true})).toBeVisible();
  await expect(page.getByRole('textbox',{name:'要办什么'})).toHaveValue('请使用新成本表');
  await expect(page.getByRole('button',{name:'移除成本.pdf'})).toBeVisible();
  await page.getByRole('button',{name:'发送',exact:true}).click();await expect(page.getByRole('alert')).toContainText('内容已保留');
  await expect(page.getByText('private provider exception')).toHaveCount(0);
  await page.getByRole('button',{name:'发送',exact:true}).click();await expect(page.getByText('补充已收到',{exact:true})).toBeVisible();
  expect(versions).toEqual([3,5,5]);expect(keys[0]).not.toBe(keys[1]);expect(keys[1]).toBe(keys[2]);
  await expect(page.getByRole('textbox',{name:'要办什么'})).toHaveValue('');
});

test('malformed write or delete responses retain private input and cannot appear completed',async({page})=>{
  await session(page);let item=initial(),badCreate=true,deleteCalls=0;const keys:string[]=[];
  await page.route('**/api/**',async route=>{
    const req=route.request(),path=new URL(req.url()).pathname;let body:unknown={};
    if(path.endsWith('/stream')){await route.fulfill({contentType:'text/event-stream',body:': connected\n\n'});return;}
    if(path==='/api/auth/me')body={role:'ADMIN',must_change_password:false};
    else if(path==='/api/admin/workspace/ai-maps/development')body={scopes:[],analysis:{}};
    else if(path==='/api/admin/workspace/ai/work-capabilities')body=workCapabilities;
    else if(path==='/api/admin/workspace/ai/work-items'&&req.method()==='POST'){keys.push(req.headers()['idempotency-key']);body=badCreate?{...item,state:'UNKNOWN_DONE'}:item;}
    else if(path==='/api/admin/workspace/ai/work-items')body=workPage();
    else if(path==='/api/admin/workspace/ai/work-items/shared-work'&&req.method()==='DELETE'){deleteCalls++;body={id:'wrong-work',state:'CANCELLED'};}
    else if(path==='/api/admin/workspace/ai/work-items/shared-work')body=item;
    await route.fulfill(json(body));
  });
  await page.goto('/legacy');await page.getByRole('textbox',{name:'要办什么'}).fill('保留这条交代');
  await page.getByRole('button',{name:'发送',exact:true}).click();await expect(page.getByRole('alert')).toContainText('暂时无法确认');
  await expect(page.getByRole('textbox',{name:'要办什么'})).toHaveValue('保留这条交代');
  badCreate=false;await page.getByRole('button',{name:'发送',exact:true}).click();await expect(page.getByText('私人材料',{exact:true})).toBeVisible();
  expect(keys[0]).toBe(keys[1]);page.once('dialog',d=>d.accept());await page.getByRole('button',{name:'清除私人记录'}).click();
  await expect(page.getByRole('alert')).toContainText('暂时无法确认');await expect(page.getByText('私人材料',{exact:true})).toBeVisible();expect(deleteCalls).toBe(1);
});

test('non JSON access denial clears private content while a capability failure preserves drafts',async({page})=>{
  await session(page);let deny=false,capabilityDown=true,posts=0;
  await page.route('**/api/**',async route=>{
    const path=new URL(route.request().url()).pathname;
    if(path.endsWith('/stream')){await route.fulfill({contentType:'text/event-stream',body:': connected\n\n'});return;}
    if(path==='/api/admin/workspace/ai/work-items/shared-work'&&deny){await route.fulfill({status:403,contentType:'text/plain',body:'Forbidden'});return;}
    if(path==='/api/admin/workspace/ai/work-capabilities'&&capabilityDown){await route.abort('connectionfailed');return;}
    let body:unknown=path==='/api/admin/workspace/ai-maps/development'?{scopes:[],analysis:{}}:path==='/api/auth/me'?{role:'ADMIN',must_change_password:false}:path==='/api/admin/workspace/ai/work-items'?workPage([initial()]):path==='/api/admin/workspace/ai/work-capabilities'?workCapabilities:path==='/api/admin/workspace/ai/work-items/shared-work'?initial():{};
    if(route.request().method()==='POST')posts++;
    await route.fulfill(json(body));
  });
  await page.goto('/legacy');await page.getByRole('button',{name:/整理成本表/}).click();
  await page.getByRole('textbox',{name:'要办什么'}).fill('尚未发送');await page.getByRole('button',{name:'发送',exact:true}).click();
  await expect(page.getByRole('alert')).toContainText('内容已保留');await expect(page.getByRole('textbox',{name:'要办什么'})).toHaveValue('尚未发送');expect(posts).toBe(0);
  capabilityDown=false;deny=true;await page.getByRole('button',{name:'刷新',exact:true}).click();
  await expect(page.getByText('私人材料',{exact:true})).toHaveCount(0);await expect(page.locator('.work-entry')).toHaveCount(0);await expect(page.getByRole('textbox',{name:'要办什么'})).toHaveValue('');
});

test('two open clients reconcile a concurrent confirmation without resubmitting the old plan',async({page,context})=>{
  await session(page);let item=initial(),confirmations=0;const versions:number[]=[];
  await context.route('**/api/**',async route=>{
    const req=route.request(),path=new URL(req.url()).pathname;let body:unknown={},status=200;
    if(path.endsWith('/stream')){await route.fulfill({contentType:'text/event-stream',body:': connected\n\n'});return;}
    if(path==='/api/auth/me')body={role:'ADMIN',must_change_password:false};
    else if(path==='/api/admin/workspace/ai-maps/development')body={scopes:[],analysis:{}};
    else if(path==='/api/admin/workspace/ai/work-items')body=workPage([item]);
    else if(path==='/api/admin/workspace/ai/work-items/shared-work')body=item;
    else if(path.endsWith('/confirm')){
      confirmations++;versions.push(req.postDataJSON().version);
      if(confirmations===1){item={...item,state:'SUCCEEDED',version:4,steps:[],receipts:[{step_key:'action-1',result:{summary:'唯一的任务已创建'}}]};body=item;}
      else{status=409;body={code:'VERSION_CONFLICT'};}
    }
    await route.fulfill(json(body,status));
  });
  const second=await context.newPage();await session(second);
  for(const client of [page,second]){await client.goto('/legacy');await client.getByRole('button',{name:/整理成本表/}).click();await expect(client.getByRole('button',{name:'创建任务',exact:true})).toBeVisible();}
  await page.getByRole('button',{name:'创建任务',exact:true}).click();await expect(page.getByText('唯一的任务已创建',{exact:true})).toBeVisible();
  await second.getByRole('button',{name:'创建任务',exact:true}).focus();await second.getByRole('button',{name:'创建任务',exact:true}).press('Enter');await expect(second.getByText('唯一的任务已创建',{exact:true})).toBeVisible();
  await expect(second.getByRole('button',{name:'创建任务',exact:true})).toHaveCount(0);await expect(second.locator('.work-result [role=status]')).toBeFocused();expect(confirmations).toBe(2);expect(versions).toEqual([3,3]);await second.close();
});
