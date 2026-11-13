import { expect, test, Page } from '@playwright/test';

const admin = { id: 'admin', name: '林管理员', role: 'ADMIN', status: 'ACTIVE', must_change_password: false };
const employee = { id: 'person', name: '陈小雨', account: 'chen.xy', phone: '13912345678', department_id: 'product', department: '产品部', role: 'EMPLOYEE', status: 'ACTIVE', version: 1 };
async function fixture(page: Page, options: { role?: string; createError?: boolean; expired?: boolean; empty?: boolean; mustChange?: boolean } = {}) {
  const commands: any[] = [];
  await page.route('**/api/**', async route => {
    const request = route.request(), path = new URL(request.url()).pathname;
    const json = (data: unknown, status = 200) => route.fulfill({ status, json: data });
    if (path === '/api/auth/login') return json({ token: 'fixture-token', user: { ...admin, role: options.role || 'ADMIN' } });
    if (path === '/api/auth/me') return json({ ...admin, must_change_password: options.mustChange || false });
    if (path === '/api/auth/logout' || path === '/api/auth/password') return json({ ok: true });
    if (options.expired && path.includes('/employees')) return route.fulfill({ status: 403, contentType: 'text/plain', body: 'Forbidden' });
    if (path.endsWith('/departments')) return json([{ id: 'product', name: '产品部' }]);
    if (request.method() === 'POST') {
      commands.push(request.postDataJSON());
      if (options.createError && path.endsWith('/employees')) return json({ message: '账号或手机号已被使用' }, 409);
      if (path.endsWith('/employees')) return json({ id: 'new-person', ...request.postDataJSON(), role: 'EMPLOYEE' });
      return json({ id: 'request', status: 'PENDING' });
    }
    if (path.endsWith('/employees')) return json({ items: options.empty ? [] : [employee], total: options.empty ? 0 : 1, nextCursor: '1' });
    if (path.endsWith('/priorities')) return json({ items: [{ id: 'priority', title: '<img src=x onerror=alert(1)>', body: { text: '公司重要事项说明' }, pinned: true, archived: false, position: 1, version: 1 }], total: 1, nextCursor: '1' });
    if (path.endsWith('/reviews')) return json({ items: [{ id: 'request', kind: 'COMPANY_ITEM', applicant_name: '林管理员', status: 'PENDING', reason: '更新公司重点', reviewer_configured: false }], total: 1, nextCursor: '1' });
    if (path.endsWith('/reviews/request')) return json({ id: 'request', applicant_id: 'admin', applicant_name: '林管理员', status: 'PENDING', candidate: { title: '新事项' }, steps: [], reason: '更新公司重点' });
    return json({ message: 'unexpected path' }, 404);
  });
  await page.goto('/');
  return commands;
}
async function login(page: Page) { await page.getByLabel('管理员账号').fill('admin.test'); await page.getByLabel('登录密码').fill('Test-password-2026'); await page.getByRole('button', { name: '登录后台' }).click(); }
async function fillEmployee(page: Page) {
  await page.getByRole('button', { name: '录入员工并开通账号' }).click();
  await page.getByLabel('员工姓名').fill('新同事'); await page.getByLabel('登录账号').fill('new.employee');
  await page.getByLabel('手机号', { exact: true }).fill('13812345678'); await page.getByLabel('初始密码').fill('Initial-password-2026'); await page.getByLabel('所属部门').selectOption('product');
}
test('管理员进入简易目录，窄屏无页面横向溢出', async ({ page }, info) => {
  await fixture(page); await login(page); await expect(page.getByText('陈小雨')).toBeVisible();
  await expect(page.getByRole('navigation')).not.toContainText('AI');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: `../output/admin-console/${info.project.name}-employees.png`, fullPage: true });
});
test('员工和创始人不能登录后台', async ({ page }) => { await fixture(page, { role: 'FOUNDER' }); await login(page); await expect(page.getByRole('alert')).toContainText('仅供管理员'); await expect(page.getByText('陈小雨')).toHaveCount(0); });
test('创建账号仅发送员工必填资料并清除密码', async ({ page }) => {
  const commands = await fixture(page); await login(page); await fillEmployee(page); await page.getByRole('button', { name: '开通员工账号', exact: true }).click();
  await expect(page.locator('.alert.success')).toContainText('已开通'); expect(commands[0].role).toBeUndefined(); expect(commands[0].companyId).toBeUndefined();
  await page.getByRole('button', { name: '录入员工并开通账号' }).click(); await expect(page.getByLabel('初始密码')).toHaveValue('');
});
test('重复账号保留表单且不自动重试', async ({ page }) => {
  const commands = await fixture(page, { createError: true }); await login(page); await fillEmployee(page); await page.getByRole('button', { name: '开通员工账号', exact: true }).click();
  await expect(page.getByRole('dialog').getByRole('alert')).toContainText('已被使用'); await expect(page.getByLabel('登录账号')).toHaveValue('new.employee'); expect(commands).toHaveLength(1);
});
test('事项文本转义，提交只提示待审', async ({ page }, info) => {
  const commands = await fixture(page); await login(page); await page.getByRole('button', { name: '公司重要事项', exact: true }).click();
  await expect(page.getByText('<img src=x onerror=alert(1)>', { exact: true })).toBeVisible(); await expect(page.locator('tbody img')).toHaveCount(0);
  await page.getByRole('button', { name: '编辑事项' }).click(); await page.getByLabel('事项名称').fill('更新后的重点'); await page.getByLabel('修改原因').fill('本周计划调整');
  await page.screenshot({ path: `../output/admin-console/${info.project.name}-priority.png`, fullPage: true });
  await page.getByRole('button', { name: '提交修改申请' }).click(); await expect(page.locator('.alert.success')).toContainText('审核通过前'); expect(commands[0].version).toBe(1);
});
test('已有员工修改携带版本和原因', async ({ page }) => {
  const commands = await fixture(page); await login(page); await page.getByRole('button', { name: '编辑资料' }).click(); await page.getByLabel('员工姓名').fill('新姓名'); await page.getByLabel('账号状态').selectOption('DISABLED'); await page.getByLabel('修改原因').fill('员工离职'); await page.getByRole('button', { name: '提交修改申请' }).click();
  await expect(page.locator('.alert.success')).toContainText('修改申请已提交'); expect(commands[0]).toMatchObject({ name: '新姓名', status: 'DISABLED', version: 1 });
});
test('本人申请无自审按钮，无审核人明确提示', async ({ page }) => {
  await fixture(page); await login(page); await page.getByRole('button', { name: '修改记录', exact: true }).click(); await page.getByRole('button', { name: '查看详情' }).click();
  await expect(page.getByRole('dialog')).toContainText('尚未分配审核人'); await expect(page.getByRole('button', { name: '通过审核' })).toHaveCount(0);
});
test('非JSON失权错误清空后台', async ({ page }) => { await fixture(page, { expired: true }); await login(page); await expect(page.getByLabel('管理员账号')).toBeVisible(); await expect(page.getByRole('alert')).toContainText('403'); expect(await page.evaluate(() => sessionStorage.getItem('workpanel-token'))).toBeNull(); });
test('空目录与首次改密入口', async ({ page }) => { await fixture(page, { empty: true }); await login(page); await expect(page.getByRole('heading', { name: '暂无记录' })).toBeVisible(); });
test('首次登录必须改密后重新登录', async ({ page }) => { await fixture(page, { mustChange: true }); await login(page); await expect(page.getByRole('heading', { name: '设置新的登录密码' })).toBeVisible(); await expect(page.getByRole('navigation')).toHaveCount(0); await page.getByLabel('原密码').fill('Old-password-2026'); await page.getByLabel('新密码').fill('New-password-2026'); await page.getByRole('button', { name: '修改并重新登录' }).click(); await expect(page.locator('.alert.success')).toContainText('请使用新密码登录'); });
