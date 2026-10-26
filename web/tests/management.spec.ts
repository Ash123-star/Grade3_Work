import { test, expect } from '@playwright/test';

const admin = { id: 'admin', name: '测试管理员', role: 'ADMIN', status: 'ACTIVE', must_change_password: false };
test('management has precisely two pages and submits a complete account candidate', async ({ page }) => {
  const mutations: unknown[] = [];
  await page.addInitScript(() => sessionStorage.setItem('workpanel-token', 'test-management'));
  await page.route('**/api/**', async route => {
    const url = new URL(route.request().url());
    if (url.pathname === '/api/auth/me') return route.fulfill({ json: admin });
    expect(url.pathname).not.toContain('/ai');
    if (url.pathname.endsWith('/revisions')) { mutations.push(route.request().postDataJSON()); return route.fulfill({ json: { id: 'review-1', status: 'PENDING' } }); }
    if (url.pathname.endsWith('/options')) return route.fulfill({ json: { departments: [{ id: 'd', name: '技术部' }], teams: [], managers: [] } });
    const account = { id: 'u', account: 'test-employee', name: '测试成员', phone: '13900000002', role: 'EMPLOYEE', status: 'ACTIVE', department_id: 'd', team_id: null, manager_id: null, department: '技术部', version: 2, dispatch_enabled: false, company_reviewer: false, pendingReviews: [] };
    if (url.pathname.endsWith('/accounts/u')) return route.fulfill({ json: account });
    if (url.pathname.endsWith('/items')) return route.fulfill({ json: { items: [], preview: [], total: 0, pinnedCount: 0, nextCursor: '0' } });
    return route.fulfill({ json: { items: [account], total: 1, nextCursor: '1' } });
  });
  await page.goto('/');
  await expect(page).toHaveURL(/\/admin\/accounts$/);
  await expect(page.getByRole('navigation', { name: '管理导航' }).getByRole('link')).toHaveCount(2);
  await expect(page.getByRole('heading', { name: '账号管理' })).toBeVisible();
  await page.getByRole('button', { name: '编辑', exact: true }).click();
  await page.getByLabel('姓名', { exact: true }).fill('修正成员姓名');
  await page.getByLabel('修改理由', { exact: true }).fill('修正姓名拼写');
  await page.getByRole('button', { name: '提交修改审核' }).click();
  await expect.poll(() => mutations.length).toBe(1);
  expect(mutations[0]).toMatchObject({ name: '修正成员姓名', version: 2, reason: '修正姓名拼写', departmentId: 'd' });
  await page.getByRole('link', { name: '公司十大重要事项' }).click();
  await expect(page.getByRole('heading', { name: '公司十大重要事项', exact: true })).toBeVisible();
  await page.reload();
  await expect(page.getByRole('heading', { name: '公司十大重要事项', exact: true })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1);
});

test('company item retains form after conflict and renders text safely', async ({ page }) => {
  await page.addInitScript(() => sessionStorage.setItem('workpanel-token', 'test-management'));
  await page.route('**/api/**', async route => {
    if (route.request().url().endsWith('/auth/me')) return route.fulfill({ json: admin });
    if (route.request().method() === 'POST') return route.fulfill({ status: 409, json: { code: 'VERSION_CONFLICT', message: '版本冲突，请刷新核对', traceId: 'trace-test' } });
    return route.fulfill({ json: { items: [], preview: [], pinnedCount: 0, total: 0, nextCursor: '0' } });
  });
  await page.goto('/admin/company-items');
  await page.getByRole('button', { name: '新增事项' }).click();
  await page.getByLabel('事项标题', { exact: true }).fill('年度公司目标');
  await page.getByLabel('事项内容', { exact: true }).fill('<script>alert(1)</script>');
  await page.getByLabel('修改理由', { exact: true }).fill('年度规划');
  await page.getByRole('button', { name: '提交事项审核' }).click();
  await expect(page.getByRole('alert').filter({ hasText: '版本冲突' })).toBeVisible();
  await expect(page.getByLabel('事项标题', { exact: true })).toHaveValue('年度公司目标');
  await expect(page.getByLabel('事项内容', { exact: true })).toHaveValue('<script>alert(1)</script>');
});

test('non admin cannot load management data', async ({ page }) => {
  let managementRequests = 0;
  await page.addInitScript(() => sessionStorage.setItem('workpanel-token', 'employee'));
  await page.route('**/api/**', async route => { if (!route.request().url().endsWith('/auth/me')) managementRequests++; await route.fulfill({ json: { ...admin, role: 'EMPLOYEE' } }); });
  await page.goto('/admin/accounts');
  await expect(page.getByRole('alert')).toContainText('仅供已启用的管理员');
  await expect(page.getByRole('button', { name: '登录工作台' })).toBeVisible();
  expect(managementRequests).toBe(0);
});

test('failed item detail cannot be submitted as a new item', async ({ page }) => {
  let writes = 0;
  await page.addInitScript(() => sessionStorage.setItem('workpanel-token', 'test-management'));
  await page.route('**/api/**', async route => {
    const url = route.request().url();
    if (url.endsWith('/auth/me')) return route.fulfill({ json: admin });
    if (route.request().method() === 'POST') { writes++; return route.fulfill({ json: {} }); }
    if (url.endsWith('/items/item-1')) return route.fulfill({ status: 503, json: { message: '详情暂时不可用' } });
    return route.fulfill({ json: { items: [{ id: 'item-1', title: '原有事项', archived: false }], total: 1, preview: [], pinnedCount: 0 } });
  });
  await page.goto('/admin/company-items');
  await page.getByRole('button', { name: '编辑', exact: true }).click();
  await expect(page.getByRole('alert').filter({ hasText: '详情暂时不可用' })).toBeVisible();
  await expect(page.getByRole('button', { name: '提交事项审核' })).toBeDisabled();
  expect(writes).toBe(0);
});
