import { expect, test, type Page } from '@playwright/test';

const receipt = {
  id: 'batch-demo',
  sha256: 'a'.repeat(64),
  importedAt: '2026-11-24T09:30:00+08:00',
  members: { applied: 1, unchanged: 0, stale: 0 },
  orders: { applied: 1, unchanged: 0, stale: 0 },
};
const sample = {
  externalOrderId: 'order-demo',
  externalMemberId: 'member-demo',
  status: 'PAID',
  currency: 'CNY',
  amount: '139.5000',
  orderedAt: '2026-11-24T09:20:00+08:00',
  sourceUpdatedAt: '2026-11-24T09:30:00+08:00',
  importId: receipt.id,
  sourceRow: 1,
};

async function fillLogin(page: Page, account: string, password: string) {
  await page.goto('/commerce');
  await page.getByLabel('账号').fill(account);
  await page.getByLabel('密码', { exact: true }).fill(password);
  await page.getByRole('button', { name: '登录', exact: true }).click();
}

async function mockCommerce(page: Page, forbidden = false) {
  let imported = 0;
  const requests: URL[] = [];
  await page.route('**/api/**', async route => {
    const url = new URL(route.request().url());
    if (url.pathname === '/api/auth/login') {
      await route.fulfill({ json: { token: 'test-session', user: { id: 'admin', name: '管理员', role: 'ADMIN',
        status: 'ACTIVE', must_change_password: false } } });
    } else if (forbidden) {
      await route.fulfill({ status: 403, json: { message: '不在授权范围内', traceId: 'test-scope' } });
    } else if (url.pathname === '/api/commerce/overview') {
      await route.fulfill({ json: { orderCount: imported ? 1 : 0, groups: imported
        ? [{ orderCount: 1, status: 'PAID', currency: 'CNY', amount: sample.amount }] : [] } });
    } else if (url.pathname === '/api/commerce/orders') {
      requests.push(url);
      await route.fulfill({ json: { items: imported ? [sample] : [], total: imported ? 1 : 0, nextCursor: null } });
    } else if (url.pathname === '/api/commerce/imports') {
      if (route.request().postData()?.includes('invalid')) {
        await route.fulfill({ status: 400, json: { message: '金额须为非负十进制字符串', section: 'orders',
          row: 2, field: 'amount', traceId: 'test-row' } });
      } else {
        await route.fulfill({ json: { ...receipt, replayed: imported++ > 0 } });
      }
    } else if (url.pathname === '/api/commerce/imports/' + receipt.id) {
      await route.fulfill({ json: { ...receipt, replayed: false } });
    } else {
      await route.fulfill({ status: 404, json: { message: '测试地址不存在' } });
    }
  });
  return requests;
}

test('商城导入回执、条件保留和金额来源', async ({ page }) => {
  const requests = await mockCommerce(page);
  await fillLogin(page, 'admin', 'test-password');
  await expect(page.getByText('没有符合条件的订单。')).toBeVisible();

  await page.getByRole('button', { name: '文件导入', exact: true }).click();
  await page.getByLabel('商城文件').setInputFiles('public/commerce-import-example.json');
  const submit = page.getByRole('button', { name: '开始导入' });
  await submit.click();
  await expect(page.getByRole('heading', { name: '导入完成' })).toBeVisible();
  await submit.click();
  await expect(page.getByRole('heading', { name: '此文件此前已导入' })).toBeVisible();

  await page.getByRole('button', { name: '查看经营概览' }).click();
  await page.getByLabel('开始日期').fill('2026-11-24');
  await page.getByLabel('结束日期').fill('2026-11-24');
  await page.getByLabel('订单 ID').fill('order-demo');
  await page.getByRole('button', { name: '查询', exact: true }).click();
  await page.getByRole('button', { name: '查看 1 笔明细' }).press('Enter');
  await expect(page.getByRole('heading', { name: '订单明细' })).toBeFocused();
  expect(requests.at(-1)?.searchParams.get('from')).toBe('2026-11-24');
  expect(requests.at(-1)?.searchParams.get('to')).toBe('2026-11-24');
  expect(requests.at(-1)?.searchParams.get('externalOrderId')).toBe('order-demo');
  expect(requests.at(-1)?.searchParams.get('status')).toBe('PAID');
  expect(requests.at(-1)?.searchParams.get('currency')).toBe('CNY');
  await expect(page.getByRole('cell', { name: /CNY 139\.5000/ })).toBeVisible();
  await page.getByRole('button', { name: '批次 · 第 1 条' }).click();
  await expect(page.getByText(receipt.sha256)).toBeVisible();
});

test('商城导入异常可定位且 320px 页面无横向溢出', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 700 });
  await mockCommerce(page);
  await fillLogin(page, 'admin', 'test-password');
  await page.getByRole('button', { name: '文件导入', exact: true }).click();
  await page.getByLabel('商城文件').setInputFiles({
    name: 'invalid.json', mimeType: 'application/json', buffer: Buffer.from('invalid'),
  });
  await page.getByRole('button', { name: '开始导入' }).click();
  await expect(page.getByRole('alert')).toContainText('订单列表 · 第 2 条 · amount');
  await expect(page.getByRole('alert')).toContainText('test-row');
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(320);
});

test('商城授权失效时清理业务界面并回到登录', async ({ page }) => {
  await mockCommerce(page, true);
  await fillLogin(page, 'admin', 'test-password');
  await expect(page.getByRole('heading', { name: '登录商城经营' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('不在授权范围内');
  await expect(page.getByRole('navigation', { name: '商城经营' })).toHaveCount(0);
  expect(await page.evaluate(() => sessionStorage.getItem('workpanel-token'))).toBeNull();
});

test('商城真实 HTTP 导入、重放和钻取 @commerce-live', async ({ page }, testInfo) => {
  const account = process.env.COMMERCE_E2E_ACCOUNT;
  const secret = process.env.COMMERCE_E2E_PASSWORD;
  const localTarget = /^http:\/\/127\.0\.0\.1:\d+$/.test(process.env.VITE_API_TARGET ?? '');
  test.skip(!account || !secret || !localTarget, '需要隔离本地 API 的管理员账号及已修改的密码');
  await fillLogin(page, account!, secret!);
  await expect(page.getByRole('heading', { name: '经营概览' })).toBeVisible();
  const orderId = 'live-' + Date.now() + '-' + testInfo.project.name;
  const memberId = 'member-' + orderId;
  const token = await page.evaluate(() => sessionStorage.getItem('workpanel-token'));
  const headers = { Authorization: `Bearer ${token}` };
  const created = await page.request.post('/api/customers', {
    headers, data: { kind: 'INDIVIDUAL', name: '商城联调样例' },
  });
  expect(created.status()).toBe(201);
  const customerId = (await created.json()).id as string;
  const binding = await page.request.put('/api/customers/' + customerId + '/membership', {
    headers, data: { mallMemberId: memberId, version: 0 },
  });
  expect(binding.ok()).toBe(true);

  await page.getByRole('button', { name: '文件导入', exact: true }).click();
  const data = {
    members: [{ externalMemberId: memberId, status: 'ACTIVE', sourceUpdatedAt: '2026-11-24T01:00:00+08:00' }],
    orders: [{ externalOrderId: orderId, externalMemberId: memberId, status: 'PAID', currency: 'CNY',
      amount: '12.34', orderedAt: '2026-11-24T00:00:00+08:00', sourceUpdatedAt: '2026-11-24T01:00:00+08:00' }],
  };
  await page.getByLabel('商城文件').setInputFiles({
    name: 'live.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(data)),
  });
  await page.getByRole('button', { name: '开始导入' }).click();
  await expect(page.getByRole('heading', { name: '导入完成' })).toBeVisible();
  await page.getByRole('button', { name: '开始导入' }).click();
  await expect(page.getByRole('heading', { name: '此文件此前已导入' })).toBeVisible();
  await page.getByRole('button', { name: '查看经营概览' }).click();
  await page.getByLabel('客户 ID').fill(customerId);
  await page.getByRole('button', { name: '查询', exact: true }).click();
  await page.getByRole('button', { name: '查看 1 笔明细' }).click();
  await expect(page.getByRole('rowheader', { name: new RegExp(orderId) })).toBeVisible();
  await expect(page.getByRole('cell', { name: /CNY 12\.3400/ })).toBeVisible();
  await page.getByRole('button', { name: '批次 · 第 1 条' }).click();
  await expect(page.getByRole('heading', { name: '导入来源' })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(page.viewportSize()?.width);
  await page.screenshot({ path: testInfo.outputPath('commerce-overview.png'), fullPage: true });
});
