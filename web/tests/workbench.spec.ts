import {workFixture, workPage, workCapabilities} from './workFixtures';
import { test, expect } from '@playwright/test';

test('AI upload uses capability limits and shows the server file error', async ({page}) => {
  let uploads=0;
  await page.addInitScript(() => sessionStorage.setItem('workpanel-token','test-token'));
  await page.route('**/api/**', async route => {
    const url=new URL(route.request().url());let status=200;let body:any={};
    if(url.pathname==='/api/auth/me')body={role:'ADMIN',must_change_password:false};
    else if(url.pathname==='/api/admin/workspace/ai-maps/development')body={scopes:[],analysis:{}};
    else if(url.pathname==='/api/admin/workspace/ai/work-items')body=workPage();
    else if(url.pathname==='/api/admin/workspace/ai/work-capabilities')body=workCapabilities;
    else if(url.pathname==='/api/admin/workspace/attachments'){uploads++;expect(url.searchParams.get('purpose')).toBe('AI_WORK');status=415;body={code:'FILE_TYPE_MISMATCH',message:'文件格式与名称不一致，请重新导出后添加'};}
    await route.fulfill({status,contentType:'application/json',body:JSON.stringify(body)});
  });
  await page.goto('/legacy');
  await page.locator('input[type=file]').setInputFiles({name:'旧.xls',mimeType:'application/octet-stream',buffer:Buffer.from('data')});
  await expect(page.getByRole('alert')).toContainText('请添加图片、PDF、Word或Excel文件');expect(uploads).toBe(0);
  await page.locator('input[type=file]').setInputFiles({name:'伪装.pdf',mimeType:'application/pdf',buffer:Buffer.from('data')});
  await expect(page.getByRole('alert')).toContainText('文件格式与名称不一致');expect(uploads).toBe(1);
});

test('workbench preserves failed input, confirms a concrete action and clears lost access', async ({ page }, info) => {
  let attempts = 0, denied = false;
  const keys: string[] = [];
  let item: any = {
    id: 'work-1', title: '整理交付任务', state: 'WAITING_CONFIRMATION', version: 3,
    planVersion: 1, planHash: 'plan-hash', confirmationId: 'confirmation-1', planValid: true,
    messages: [{ id: 'message-1', body: { text: '请整理交付任务' } }],
    plan: { questions: [], sources: [], actions: [{ type: 'CREATE_TASK', label: '给小李创建「交付成本表」', payload: { deadline: '2026-11-01T17:00:00+08:00' } }] },
    steps: [{ step_key: 'action-1', state: 'WAITING' }], receipts: [],
  };
  await page.addInitScript(() => sessionStorage.setItem('workpanel-token', 'test-token'));
  await page.route('**/api/**', async route => {
    const request = route.request(), path = new URL(request.url()).pathname;
    if (path.endsWith('/stream')) { await route.fulfill({contentType:'text/event-stream',body:': connected\n\n'}); return; }
    let status = 200, body: any = {};
    if (path === '/api/auth/me') body = {role: 'ADMIN', must_change_password: false};
    else if (path === '/api/admin/workspace/ai-maps/development') body = {scopes: [], analysis: {}};
    else if(path === '/api/admin/workspace/ai/work-capabilities')body=workCapabilities;
    else if (path === '/api/admin/workspace/ai-memories/knowledge-status' || path === '/api/admin/workspace/ai-memories/preferences/me') body = {};
    else if (path === '/api/admin/workspace/ai/work-items' && request.method() === 'POST') {
      keys.push(request.headers()['idempotency-key']);
      if (++attempts < 3) {status = 503;body = {code: 'AI_PROVIDER_FAILED'};}
      else {status = 202;body = workFixture(item);}
    } else if (path === '/api/admin/workspace/ai/work-items') body = workPage(attempts >= 3 ? [item] : []);
    else if (path === '/api/admin/workspace/ai/work-items/work-1/confirm') {
      expect(request.postDataJSON()).toEqual({version: 3, planVersion: 1, planHash: 'plan-hash', confirmationId: 'confirmation-1', actions: ['action-1']});
      item = {...item, version: 4, state: 'SUCCEEDED', steps: [], receipts: [{step_key: 'action-1', result: {summary: '任务已创建'}}]};
      body = workFixture(item);
    } else if (path === '/api/admin/workspace/ai/work-items/work-1') {
      if (denied) {status = 404;body = {code: 'NOT_FOUND'};} else body = workFixture(item);
    } else throw new Error(`Unexpected ${request.method()} ${path}`);
    await route.fulfill({status, contentType: 'application/json', body: JSON.stringify(body)});
  });
  await page.goto('/legacy');
  await page.getByRole('textbox', {name: '要办什么'}).fill('请整理交付任务');
  for (let i = 0; i < 2; i++) {
    await page.getByRole('button', {name: '发送', exact: true}).click();
    await expect(page.getByRole('alert')).toContainText('内容已保留');
    await expect(page.getByRole('textbox', {name: '要办什么'})).toHaveValue('请整理交付任务');
  }
  expect(keys[0]).toBe(keys[1]);
  await page.getByRole('button', {name: '发送', exact: true}).click();
  await expect(page.getByRole('button', {name: '创建任务', exact: true})).toBeVisible();
  await expect(page.getByText('任务已创建', {exact: true})).toHaveCount(0);
  await page.getByRole('button', {name: '创建任务', exact: true}).click();
  await expect(page.getByText('任务已创建', {exact: true})).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1);
  await page.screenshot({path: info.outputPath('workbench-result.png'), fullPage: true});
  denied = true;
  await page.getByRole('button', {name: '刷新', exact: true}).click();
  await expect(page.getByText('任务已创建', {exact: true})).toHaveCount(0);
  await expect(page.getByRole('heading', {name: '把事情交给我'})).toBeVisible();
});

test('private deletion uses current version and retains formal result semantics', async ({ page }) => {
  const item = {id: 'work-2', title: '已提交交付', state: 'SUCCEEDED', version: 9, messages: [], plan: {}, steps: [], receipts: [{step_key: 'a', result: {summary: '已提交，等待验收'}}]};
  let deleted = false;
  await page.addInitScript(() => sessionStorage.setItem('workpanel-token', 'test-token'));
  await page.route('**/api/**', async route => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/stream')) { await route.fulfill({contentType:'text/event-stream',body:': connected\n\n'}); return; }
    let body: any = {};
    if (path === '/api/auth/me') body = {role: 'ADMIN', must_change_password: false};
    else if (path === '/api/admin/workspace/ai-maps/development') body = {scopes: [], analysis: {}};
    else if (path === '/api/admin/workspace/ai/work-items') body = workPage(deleted ? [] : [item]);
    else if (path === '/api/admin/workspace/ai/work-items/work-2' && route.request().method() === 'DELETE') {
      expect(route.request().headers()['if-match']).toBe('9');deleted = true;body={id:item.id,state:'CANCELLED'};
    } else if (path === '/api/admin/workspace/ai/work-items/work-2') body = workFixture(item);
    await route.fulfill({contentType: 'application/json', body: JSON.stringify(body)});
  });
  await page.goto('/legacy');
  await page.getByRole('button', {name: /已提交交付/}).click();
  await expect(page.getByText('已提交，等待验收', {exact: true})).toBeVisible();
  page.once('dialog', dialog => dialog.accept());
  await page.getByRole('button', {name: '清除私人记录'}).click();
  await expect(page.getByText('已提交，等待验收', {exact: true})).toHaveCount(0);
  expect(deleted).toBe(true);
});

test('long work results remain readable above the composer', async ({page}) => {
  const answer='请补充报价单和成本明细，核对数量后再提交。'.repeat(35);
  const item={id:'long-work',title:'核对报价材料',state:'WAITING_INPUT',version:3,messages:[],plan:{answer,questions:['请补充成本明细'],sources:[],actions:[]},steps:[],receipts:[]};
  await page.emulateMedia({reducedMotion:'reduce'});
  await page.addInitScript(()=>sessionStorage.setItem('workpanel-token','test-token'));
  await page.route('**/api/**',async route=>{
    const url=new URL(route.request().url());let body:any={};
    if(url.pathname.endsWith('/stream')){await route.fulfill({contentType:'text/event-stream',body:': connected\n\n'});return;}
    if(url.pathname==='/api/auth/me')body={role:'ADMIN',must_change_password:false};
    else if(url.pathname==='/api/admin/workspace/ai/work-items')body=workPage([item]);
    else if(url.pathname==='/api/admin/workspace/ai/work-items/long-work')body=workFixture(item);
    else if(url.pathname==='/api/admin/workspace/ai-maps/development')body={scopes:[],analysis:{}};
    await route.fulfill({contentType:'application/json',body:JSON.stringify(body)});
  });
  await page.goto('/legacy');await page.getByRole('button',{name:/核对报价材料/}).click();
  await expect(page.getByText(answer,{exact:true})).toBeVisible();
  const bounds=await page.evaluate(()=>({result:document.querySelector('.work-result')!.getBoundingClientRect().bottom,composer:document.querySelector('.work-composer')!.getBoundingClientRect().top}));
  expect(bounds.composer).toBeGreaterThanOrEqual(bounds.result);
  await page.getByRole('textbox',{name:'要办什么'}).fill('已补充成本明细');
  await expect(page.getByRole('textbox',{name:'要办什么'})).toBeFocused();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(1);
});

test('completed check displays missing material rather than handled success', async ({page}) => {
  const item={id:'checked-work',title:'检查交付材料',state:'SUCCEEDED',version:3,messages:[],plan:{actions:[],questions:[]},result:{kind:'DELIVERY_CHECKED',summary:'有几处材料需要补充',report:{state:'NEEDS_FIX'}},steps:[],receipts:[]};
  await page.addInitScript(()=>sessionStorage.setItem('workpanel-token','test-token'));
  await page.route('**/api/**',async route=>{
    const path=new URL(route.request().url()).pathname;
    if(path.endsWith('/stream')){await route.fulfill({contentType:'text/event-stream',body:': connected\n\n'});return;}
    const body=path==='/api/auth/me'?{role:'ADMIN',must_change_password:false}:path==='/api/admin/workspace/ai/work-items'?workPage([item]):path==='/api/admin/workspace/ai/work-items/checked-work'?workFixture(item):{};
    await route.fulfill({contentType:'application/json',body:JSON.stringify(body)});
  });
  await page.goto('/legacy');await page.getByRole('button',{name:/检查交付材料/}).click();
  await expect(page.getByRole('status')).toHaveText('需要补充材料');
  await expect(page.getByText('已办妥',{exact:true})).toHaveCount(0);
  await expect(page.getByText('有几处材料需要补充',{exact:true})).toBeVisible();
});
