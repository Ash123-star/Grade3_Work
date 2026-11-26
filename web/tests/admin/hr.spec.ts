import {test,expect} from '@playwright/test';
test('人事入口只读与登录错误反馈',async({page})=>{
 await page.route('**/api/**',async route=>{const path=new URL(route.request().url()).pathname;let data:unknown={};if(path==='/api/auth/login')data={token:'test'};else if(path==='/api/hr/me')data={admin:false,manage:false};else if(path==='/api/hr/employees')data=[{id:'e',name:'员工甲',department_id:'产品部',business_position:'NONE',duties:'客户服务',access:'READ'}];else if(path==='/api/hr/contracts')data={items:[],total:0};else if(path==='/api/hr/reminders')data=[];await route.fulfill({json:data});});
 await page.goto('/hr');await page.getByLabel('账号',{exact:true}).fill('reader');await page.getByLabel('密码',{exact:true}).fill('test-password');await page.getByRole('button',{name:'登录人事入口'}).click();await expect(page.getByRole('heading',{name:'员工档案',exact:true})).toBeVisible();await expect(page.getByText('暂无合同',{exact:true})).toBeVisible();await expect(page.getByRole('button',{name:'保存合同'})).toHaveCount(0);await expect(page.getByLabel('工作职责')).toHaveAttribute('readonly','');await expect(page.getByRole('link',{name:'管理员后台'})).toHaveCount(0);
});
test('未授权账号收到拒绝反馈',async({page})=>{await page.route('**/api/**',async route=>{if(route.request().url().endsWith('/auth/login'))await route.fulfill({json:{token:'test'}});else await route.fulfill({status:403,json:{message:'无权访问'}});});await page.goto('/hr');await page.getByLabel('账号',{exact:true}).fill('employee');await page.getByLabel('密码',{exact:true}).fill('test');await page.getByRole('button',{name:'登录人事入口'}).click();await expect(page.getByRole('alert')).toHaveText('无权访问');await expect(page.getByRole('heading',{name:'已归档合同'})).toHaveCount(0);});

test('合同归档与提醒详情保留历史',async({page},info)=>{
 let saved:Record<string,any>|null=null;
 await page.route('**/api/**',async route=>{
  const path=new URL(route.request().url()).pathname;let data:unknown={};
  if(path==='/api/auth/login')data={token:'test'};
  else if(path==='/api/hr/me')data={admin:true,manage:true};
  else if(path==='/api/hr/employees')data=[{id:'e',name:'员工甲',department_name:'产品部',business_position:'NONE',duties:'客户服务',access:'MANAGE',status:'ACTIVE',grant_version:1}];
  else if(path==='/api/attachments')data={id:'file'};
  else if(path==='/api/hr/contracts'&&route.request().method()==='POST') {const b=route.request().postDataJSON();saved={id:'contract',title:b.title,employee_id:b.employeeId,employee_name:'员工甲',starts_on:b.startsOn,ends_on:b.endsOn,attachment_id:b.attachmentId,recipients:b.recipients,version:1};data=saved;}
  else if(path==='/api/hr/contracts')data={items:saved?[saved]:[],total:saved?1:0};
  else if(path==='/api/hr/reminders')data=saved?[{id:'notice',object_id:'contract',title:saved.title,ends_on:saved.ends_on}]:[];
  else if(path==='/api/hr/contracts/contract')data=saved;
  else if(path.endsWith('/history'))data=[{version:1,snapshot:saved}];
  await route.fulfill({json:data});
 });
 await page.goto('/hr');await page.getByLabel('账号',{exact:true}).fill('manager');await page.getByLabel('密码',{exact:true}).fill('test');await page.getByRole('button',{name:'登录人事入口'}).click();
 await page.getByLabel('员工',{exact:true}).selectOption('e');await page.getByLabel('合同名称').fill('劳动合同测试');await page.getByLabel('开始日期').fill('2026-11-01');await page.getByLabel('到期日期').fill('2027-11-01');
 await page.getByLabel('合同专用附件').setInputFiles({name:'contract.pdf',mimeType:'application/pdf',buffer:Buffer.from('test fixture')});await expect(page.getByText('附件已就绪',{exact:true})).toBeVisible();await page.getByLabel('提醒接收人（可多选）').selectOption('e');await page.getByRole('button',{name:'保存合同',exact:true}).click();await expect(page.getByRole('status')).toHaveText('合同已归档');await expect(page.getByLabel('合同专用附件')).toHaveValue('');
 await page.getByRole('button',{name:'劳动合同测试 · 到期日 2027-11-01'}).click();await expect(page.getByRole('heading',{name:'合同详情：劳动合同测试'})).toBeVisible();await expect(page.getByText('版本 1 · 劳动合同测试 · 2026-11-01 至 2027-11-01')).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:`../output/phase2-hr-${info.project.name}.png`,fullPage:true});
});

test('刷新遇到非JSON失权响应清除合同资料',async({page})=>{
 let denied=false;
 await page.route('**/api/**',async route=>{const path=new URL(route.request().url()).pathname;if(denied){await route.fulfill({status:403,contentType:'text/html',body:'Forbidden'});return;}
 let data:unknown={};if(path==='/api/auth/login')data={token:'test'};else if(path==='/api/hr/me')data={admin:false,manage:false};else if(path==='/api/hr/employees')data=[];else if(path==='/api/hr/reminders')data=[];else if(path==='/api/hr/contracts')data={items:[{id:'secret',title:'私有合同',starts_on:'2026-01-01',ends_on:'2027-01-01'}],total:1};await route.fulfill({json:data});});
 await page.goto('/hr');await page.getByLabel('账号',{exact:true}).fill('reader');await page.getByLabel('密码',{exact:true}).fill('test');await page.getByRole('button',{name:'登录人事入口'}).click();await expect(page.getByText('私有合同',{exact:true})).toBeVisible();denied=true;await page.getByRole('button',{name:'刷新',exact:true}).click();await expect(page.getByText('私有合同',{exact:true})).toHaveCount(0);await expect(page.getByRole('alert')).toBeVisible();
});
