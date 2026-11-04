import { test, expect, type Page } from '@playwright/test';

// Supply a dedicated company and two independent reviewers; never edit demo users.
const fixture = process.env.MANAGEMENT_REAL_FIXTURE ? JSON.parse(process.env.MANAGEMENT_REAL_FIXTURE) : null;
const password = process.env.MANAGEMENT_REAL_PASSWORD;
test('real management confirms membership and publishes company items through independent review', async ({ browser }, testInfo) => {
  test.skip(!fixture || !password, 'Requires isolated real-backend management fixture and password');
  test.skip(testInfo.project.name !== 'desktop', 'Run the real data workflow once; responsive states have separate coverage');
  test.setTimeout(120000);
  const first = await browser.newContext(), second = await browser.newContext();
  const author = await first.newPage(), reviewer = await second.newPage();
  author.setDefaultTimeout(10000); reviewer.setDefaultTimeout(10000);
  const failures: string[] = [];
  for (const page of [author, reviewer]) page.on('pageerror', e => failures.push(e.message));
  async function login(page: Page, account: string) {
    await page.goto('http://127.0.0.1:5173/admin/accounts');
    await page.getByLabel('账号', { exact: true }).fill(account);
    await page.getByLabel('密码', { exact: true }).fill(password!);
    await page.getByRole('button', { name: '登录工作台' }).click();
    await expect(page.getByRole('heading', { name: '账号管理' })).toBeVisible();
  }
  async function approve(reason: string) {
    await reviewer.getByRole('button', { name: '修改与审核记录' }).click();
    await reviewer.getByRole('row').filter({ hasText: reason }).getByRole('button', { name: '查看' }).click();
    await reviewer.getByRole('button', { name: '通过审核', exact: true }).click();
    await expect(reviewer.getByRole('row').filter({ hasText: reason })).toContainText('已通过');
    await reviewer.getByRole('button', { name: 'Close this dialog' }).click();
  }
  async function submitAccount(reason: string) {
    await author.getByLabel('修改理由', { exact: true }).fill(reason);
    await author.getByRole('button', { name: '提交修改审核' }).click();
    await expect(author.getByText('修改已提交审核，审核通过前当前信息保持不变')).toBeVisible();
  }
  try {
    await login(author, fixture.author);
    await login(reviewer, fixture.reviewer);
    await expect(author.getByRole('navigation', { name: '管理导航' }).getByRole('link')).toHaveCount(2);
    const targetRow = () => author.getByRole('row').filter({ hasText: fixture.employee });
    await targetRow().getByRole('button', { name: '编辑' }).click();
    await author.getByLabel('所属部门', { exact: true }).click();
    await author.getByRole('option', { name: '验收部门', exact: true }).click();
    await author.getByLabel('姓名', { exact: true }).fill('待确认验收成员');
    await submitAccount('系统验收：确认成员归属');
    await expect(targetRow()).toContainText('待确认');
    await approve('系统验收：确认成员归属');
    await author.getByRole('button', { name: '刷新账号列表' }).click();
    await expect(targetRow()).toContainText('已启用');
    await expect(targetRow()).toContainText('验收部门');
    const employeeLogin = await first.request.post('http://127.0.0.1:5173/api/auth/login', { data: { account: fixture.employee, password } });
    expect(employeeLogin.ok()).toBeTruthy();
    const employeeToken = (await employeeLogin.json()).token;
    const scope = await first.request.get('http://127.0.0.1:5173/api/organization/people', { headers: { Authorization: `Bearer ${employeeToken}` } });
    expect(scope.ok()).toBeTruthy();

    await author.getByRole('link', { name: '公司十大重要事项' }).click();
    await reviewer.getByRole('link', { name: '公司十大重要事项' }).click();
    await author.getByRole('button', { name: '新增事项' }).click();
    await author.getByLabel('事项标题', { exact: true }).fill('系统验收：年度重点');
    await author.getByLabel('事项内容', { exact: true }).fill('明确目标，持续推进。<script>window.xss=true</script>');
    await author.locator('.el-switch').filter({ has: author.getByRole('switch', { name: '置顶展示', exact: true }) }).click();
    await author.getByLabel('修改理由', { exact: true }).fill('系统验收：新增年度重点');
    await author.getByRole('button', { name: '提交事项审核' }).click();
    await expect(author.getByText('事项已提交审核，审核通过后更新公司展示')).toBeVisible();
    await expect(author.locator('.priority-preview')).toHaveCount(0);
    await approve('系统验收：新增年度重点');
    await author.getByRole('button', { name: '刷新事项列表' }).click();
    await expect(author.locator('.priority-preview')).toContainText('系统验收：年度重点');
    const publicItems = await first.request.get('http://127.0.0.1:5173/api/dashboard/company', { headers: { Authorization: `Bearer ${employeeToken}` } });
    expect(publicItems.ok()).toBeTruthy();
    expect((await publicItems.json()).items[0].title).toBe('系统验收：年度重点');
    expect(await author.evaluate(() => (window as unknown as { xss?: boolean }).xss)).toBeUndefined();
    await expect(author.locator('.el-message')).toHaveCount(0);
    for (const size of [{ width: 1440, height: 900 }, { width: 1024, height: 768 }, { width: 768, height: 1024 }]) {
      await author.setViewportSize(size);
      await author.screenshot({ path: testInfo.outputPath(`items-${size.width}.png`), fullPage: true });
      expect(await author.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1);
    }
    await author.getByRole('row').filter({ hasText: '系统验收：年度重点' }).getByRole('button', { name: '编辑' }).click();
    await author.getByLabel('事项标题', { exact: true }).fill('系统验收：更新年度重点');
    await author.getByLabel('修改理由', { exact: true }).fill('系统验收：修订年度重点');
    await author.getByRole('button', { name: '提交事项审核' }).click();
    await expect(author.getByText('事项已提交审核，审核通过后更新公司展示')).toBeVisible();
    await approve('系统验收：修订年度重点');
    await author.getByRole('button', { name: '刷新事项列表' }).click();
    await expect(author.locator('.priority-preview')).toContainText('系统验收：更新年度重点');
    await author.getByRole('row').filter({ hasText: '系统验收：更新年度重点' }).getByRole('button', { name: '编辑' }).click();
    await author.locator('.el-switch').filter({ has: author.getByRole('switch', { name: '归档事项', exact: true }) }).click();
    await author.getByLabel('修改理由', { exact: true }).fill('系统验收：归档年度重点');
    await author.getByRole('button', { name: '提交事项审核' }).click();
    await expect(author.getByText('事项已提交审核，审核通过后更新公司展示')).toBeVisible();
    await approve('系统验收：归档年度重点');
    const archivedItems = await first.request.get('http://127.0.0.1:5173/api/dashboard/company', { headers: { Authorization: `Bearer ${employeeToken}` } });
    expect((await archivedItems.json()).total).toBe(0);
    await author.getByRole('link', { name: '账号管理' }).click();
    await author.setViewportSize({ width: 1440, height: 900 });
    await expect(author.locator('.el-message')).toHaveCount(0);
    await author.screenshot({ path: testInfo.outputPath('accounts-1440.png'), fullPage: true });
    await author.evaluate(() => { document.documentElement.style.zoom = '2'; });
    await author.screenshot({ path: testInfo.outputPath('accounts-200-percent.png'), fullPage: true });
    expect(await author.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1);
    await author.evaluate(() => { document.documentElement.style.zoom = ''; });
    await targetRow().getByRole('button', { name: '编辑' }).click();
    await author.getByLabel('姓名', { exact: true }).focus();
    await author.keyboard.press('Tab');
    expect(await author.evaluate(() => document.activeElement?.closest('.el-dialog, .el-drawer') !== null)).toBeTruthy();
    await author.locator('.el-select').filter({ has: author.getByRole('combobox', { name: '账号状态', exact: true }) }).click();
    await author.getByRole('option', { name: '已停用' }).click();
    await submitAccount('系统验收：停用测试账号');
    await reviewer.getByRole('link', { name: '账号管理' }).click();
    await approve('系统验收：停用测试账号');
    const revoked = await first.request.get('http://127.0.0.1:5173/api/organization/people', { headers: { Authorization: `Bearer ${employeeToken}` } });
    expect([401, 403]).toContain(revoked.status());
    expect(failures).toEqual([]);
  } finally {
    for (const page of [author, reviewer]) await page.evaluate(async () => { const token = sessionStorage.getItem('workpanel-token'); if (token) await fetch('/api/auth/logout', { method: 'POST', headers: { Authorization: `Bearer ${token}` } }); }).catch(() => {});
    await first.close(); await second.close();
  }
});
