import { test, expect } from '@playwright/test';

for (const role of ['EMPLOYEE', 'FOUNDER']) {
  test(`restored ${role} session cannot open administrator workspace`, async ({ page }) => {
    let businessRequests = 0;
    await page.addInitScript(() => sessionStorage.setItem('workpanel-token', 'test-session'));
    await page.route('**/api/**', async route => {
      if (new URL(route.request().url()).pathname !== '/api/auth/me') businessRequests++;
      await route.fulfill({ json: { role, must_change_password: false } });
    });
    await page.goto('/legacy');
    await expect(page.getByRole('alert')).toContainText('仅供管理员');
    await expect(page.getByRole('button', { name: '登录', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: '更新分析' })).toHaveCount(0);
    expect(businessRequests).toBe(0);
    expect(await page.evaluate(() => sessionStorage.getItem('workpanel-token'))).toBeNull();
  });
}

test('revoked administrator clears workspace on protected API denial', async ({ page }) => {
  await page.addInitScript(() => sessionStorage.setItem('workpanel-token', 'revoked-session'));
  await page.route('**/api/**', async route => {
    if (new URL(route.request().url()).pathname === '/api/auth/me') {
      await route.fulfill({ json: { role: 'ADMIN', must_change_password: false } });
    } else {
      expect(new URL(route.request().url()).pathname).toMatch(/^\/api\/admin\/workspace\//);
      await route.fulfill({ status: 403, json: { code: 'FORBIDDEN', message: '管理权限已撤销' } });
    }
  });
  await page.goto('/legacy');
  await expect(page.getByRole('alert')).toContainText('管理权限已撤销');
  await expect(page.getByRole('button', { name: '登录', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '更新分析' })).toHaveCount(0);
});

test('real employee rejected and real admin enters without mock requests', async ({ page }, testInfo) => {
  test.skip(!process.env.WEEK6_ADMIN_ACCOUNT || !process.env.WEEK6_ADMIN_PASSWORD || !process.env.WEEK6_EMPLOYEE_ACCOUNT || !process.env.WEEK6_EMPLOYEE_PASSWORD, 'Requires isolated real backend credentials');
  await page.goto('/legacy');
  await page.getByLabel('账号').fill(process.env.WEEK6_EMPLOYEE_ACCOUNT!);
  await page.getByLabel('密码', { exact: true }).fill(process.env.WEEK6_EMPLOYEE_PASSWORD!);
  await page.getByRole('button', { name: '登录', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('仅供管理员');
  await expect(page.getByRole('button', { name: '更新分析' })).toHaveCount(0);
  await page.getByLabel('账号').fill(process.env.WEEK6_ADMIN_ACCOUNT!);
  await page.getByLabel('密码', { exact: true }).fill(process.env.WEEK6_ADMIN_PASSWORD!);
  const response = page.waitForResponse(r => r.url().includes('/api/admin/workspace/ai-maps/development'));
  await page.getByRole('button', { name: '登录', exact: true }).click();
  expect((await response).status()).toBe(200);
  await expect(page.getByRole('button', { name: '更新分析' })).toBeVisible();
  await expect(page.getByRole('button', { name: '登录', exact: true })).toHaveCount(0);
  const auditResponse = page.waitForResponse(r => r.url().includes('/api/admin/workspace/organization/task-audit'));
  await page.getByRole('button', { name: '任务审计', exact: true }).click();
  expect((await auditResponse).status()).toBe(200);
  await expect(page.getByRole('region', { name: '任务审计记录' })).toBeVisible();
  await expect(page.getByText(/共 \d+ 条记录/)).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('week6-admin-real.png'), fullPage: true });
});

test('task audit supports pages empty errors and safe content', async ({ page }) => {
  await page.addInitScript(() => sessionStorage.setItem('workpanel-token', 'audit-test'));
  await page.route('**/api/**', async route => {
    const url = new URL(route.request().url());
    if(url.pathname === '/api/auth/me') return route.fulfill({json:{role:'ADMIN'}});
    if(url.pathname.endsWith('/task-audit')) {
      if(url.searchParams.get('taskId') === 'error') return route.fulfill({status:503,json:{message:'审计暂不可用'}});
      if(url.searchParams.has('taskId')) return route.fulfill({json:{items:[],total:0,nextCursor:'0'}});
      const cursor=Number(url.searchParams.get('cursor'));
      return route.fulfill({json:{items:[{id:cursor+1,type:'TASK_EVENT',actor_name:'任务参与者',task_id:'task-1',created_at:'2026-10-19T08:00:00Z',reason:'进展说明',before_value:{phase:'DISPATCHED'},after_value:{note:'<script>alert(1)</script>'}}],total:21,nextCursor:String(cursor+1)}});
    }
    return route.fulfill({json:{scopes:[],analysis:{},memories:0}});
  });
  await page.goto('/legacy');
  await page.getByRole('button',{name:'任务审计',exact:true}).click();
  await expect(page.getByText('共 21 条记录')).toBeVisible();
  await page.getByText('查看变更前后内容').click();
  await expect(page.locator('pre').last()).toContainText('<script>alert(1)</script>');
  await page.getByRole('button',{name:'下一页'}).click();
  await expect(page.getByText('第 2 页')).toBeVisible();
  await expect(page.getByRole('button',{name:'下一页'})).toBeDisabled();
  await page.getByLabel('任务 ID（可选）').fill('unknown');
  await page.getByRole('button',{name:'查询记录'}).click();
  await expect(page.getByText('暂无匹配的任务审计记录')).toBeVisible();
  await page.getByLabel('任务 ID（可选）').fill('error');
  await page.getByRole('button',{name:'查询记录'}).click();
  await expect(page.getByRole('alert')).toContainText('审计暂不可用');
  expect(await page.evaluate(() => document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(1);
});
