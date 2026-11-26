import { expect, test, type Page } from '@playwright/test';

const receipt = {
  id: 'batch-demo',
  sha256: 'a'.repeat(64),
  importedAt: '2026-11-24T09:30:00+08:00',
  members: { applied: 1, unchanged: 0, stale: 0 },
  orders: { applied: 1, unchanged: 0, stale: 0 },
};
const sample = {
  externalOrderId: 'OVERVIEW-DEMO-20261125-O23',
  externalMemberId: 'OVERVIEW-DEMO-20261125-M01',
  status: 'PAID',
  currency: 'CNY',
  amount: '12345.6789',
  orderedAt: '2026-11-24T09:20:00+08:00',
  sourceUpdatedAt: '2026-11-24T09:30:00+08:00',
  importId: receipt.id,
  sourceRow: 1,
};
const admin = { id: 'admin', name: '管理员', role: 'ADMIN', status: 'ACTIVE', must_change_password: false };

async function fillLogin(page: Page, account: string, password: string, path = '/commerce') {
  await page.goto(path);
  await page.getByLabel('管理员账号').fill(account);
  await page.getByLabel('登录密码').fill(password);
  await page.getByRole('button', { name: '登录后台' }).click();
}

async function mockCommerce(page: Page, forbidden = false) {
  let imported = 0;
  const requests: URL[] = [];
  await page.route('**/api/**', async route => {
    const url = new URL(route.request().url());
    if (url.pathname === '/api/auth/login') {
      await route.fulfill({ json: { token: 'test-session', user: admin } });
    } else if (url.pathname === '/api/auth/me') {
      await route.fulfill({ json: admin });
    } else if (url.pathname.startsWith('/api/admin/console/')) {
      const list = /\/(?:employees|priorities|history|reviews)$/.test(url.pathname);
      await route.fulfill({ json: list ? { items: [], total: 0, nextCursor: 0 } : [] });
    } else if (forbidden) {
      await route.fulfill({ status: 403, json: { message: '不在授权范围内', traceId: 'test-scope' } });
    } else if (url.pathname === '/api/commerce/overview') {
      await route.fulfill({ json: { orderCount: imported ? 1 : 0, groups: imported
        ? [{ orderCount: 1, status: 'PAID', currency: 'CNY', amount: sample.amount }] : [] } });
    } else if (url.pathname === '/api/commerce/orders') {
      requests.push(url);
      await route.fulfill({ json: { items: imported ? [sample] : [], total: imported ? 1 : 0, nextCursor: null } });
    } else if (url.pathname === '/api/commerce/members') {
      await route.fulfill({ json: { items: [{ externalMemberId: sample.externalMemberId, level: '金卡',
        status: 'ACTIVE', joinedAt: '2026-11-01', expiresAt: '2027-10-31' }], total: 1, nextCursor: null } });
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
  await page.getByLabel('商城文件', { exact: true }).setInputFiles('public/commerce-import-example.json');
  const submit = page.getByRole('button', { name: '开始导入' });
  await submit.click();
  await expect(page.getByRole('heading', { name: '导入完成' })).toBeVisible();
  await submit.click();
  await expect(page.getByRole('heading', { name: '此文件此前已导入' })).toBeVisible();

  await page.getByRole('button', { name: '查看经营概览' }).click();
  const from = page.getByRole('combobox', { name: '开始日期' });
  const to = page.getByRole('combobox', { name: '结束日期' });
  await expect(from).toHaveAttribute('placeholder', '选择开始日期');
  await expect(to).toHaveAttribute('placeholder', '选择结束日期');
  await to.fill('2026-11-24');
  await to.press('Enter');
  await from.fill('2026-11-25');
  await from.press('Enter');
  await expect(page.getByRole('alert')).toHaveText('结束日期不能早于开始日期。');
  const previousOrderRequests = requests.length;
  await page.getByRole('button', { name: '查询', exact: true }).click();
  expect(requests).toHaveLength(previousOrderRequests);
  await from.fill('2026-11-24');
  await from.press('Enter');
  await expect(page.getByRole('alert')).toHaveCount(0);
  await page.getByLabel('订单原编号').fill(sample.externalOrderId);
  await page.getByRole('button', { name: '查询', exact: true }).click();
  await page.getByRole('button', { name: '查看 1 笔明细' }).press('Enter');
  await expect(page.getByRole('heading', { name: '订单明细' })).toBeFocused();
  expect(requests.at(-1)?.searchParams.get('from')).toBe('2026-11-24');
  expect(requests.at(-1)?.searchParams.get('to')).toBe('2026-11-24');
  expect(requests.at(-1)?.searchParams.get('externalOrderId')).toBe(sample.externalOrderId);
  expect(requests.at(-1)?.searchParams.get('status')).toBe('PAID');
  expect(requests.at(-1)?.searchParams.get('currency')).toBe('CNY');
  await expect(page.getByRole('cell', { name: /人民币 12,345\.6789/ })).toBeVisible();
  const order = page.getByRole('rowheader').filter({ hasText: '演示订单 20261125-23' });
  await expect(order.getByText(sample.externalOrderId, { exact: true })).not.toBeVisible();
  await order.getByText('演示订单 20261125-23', { exact: true }).press('Enter');
  await expect(order.getByText(sample.externalOrderId, { exact: true })).toBeVisible();
  await page.getByRole('button', { name: '批次 · 第 1 条' }).click();
  await expect(page.getByText(receipt.sha256)).toBeVisible();
});

test('订单切换等待期间保留表格，返回全部订单恢复原页', async ({ page }) => {
  await mockCommerce(page);
  const allOrders = Array.from({ length: 24 }, (_, index) => ({
    ...sample,
    externalOrderId: '商城订单-' + (index + 1),
    status: index >= 22 ? 'CANCELLED' : 'PAID',
    sourceRow: index + 1,
  }));
  let finishDrill!: () => void;
  const waitForDrill = new Promise<void>(resolve => { finishDrill = resolve; });
  let failNextDrill = false;
  await page.route(/\/api\/commerce\/(?:overview|orders)(?:\?|$)/, async route => {
    const url = new URL(route.request().url());
    if (url.pathname.endsWith('/overview')) {
      await route.fulfill({ json: { orderCount: allOrders.length, groups: [
        { orderCount: 2, status: 'CANCELLED', currency: 'CNY', amount: '99.00' },
        { orderCount: 22, status: 'PAID', currency: 'CNY', amount: '690.00' },
      ] } });
      return;
    }
    const status = url.searchParams.get('status');
    if (status) await waitForDrill;
    if (status && failNextDrill) {
      failNextDrill = false;
      await route.fulfill({ status: 503, json: { message: '商城明细暂时无法加载' } });
      return;
    }
    const items = status ? allOrders.filter(order => order.status === status) : allOrders;
    const offset = Number(url.searchParams.get('cursor') ?? 0);
    const end = offset + Number(url.searchParams.get('limit'));
    await route.fulfill({ json: {
      items: items.slice(offset, end), total: items.length, nextCursor: end < items.length ? String(end) : null,
    } });
  });

  await fillLogin(page, 'admin', 'test-password', '/commerce?customerId=crm-customer');
  const pager = page.getByRole('navigation', { name: '订单分页' });
  const rows = page.getByRole('region', { name: '商城订单' }).getByRole('rowheader');
  const heading = page.getByRole('heading', { name: '订单明细' });
  await expect(pager).toContainText('共 24 笔 · 第 1/3 页');
  await expect(rows).toHaveCount(10);
  await expect(pager.getByRole('button', { name: '上一页' })).toBeDisabled();
  await pager.getByRole('button', { name: '下一页' }).click();
  await expect(pager).toContainText('第 2/3 页');
  await expect(rows.first()).toHaveText('商城订单-11');

  const sectionTop = () => heading.evaluate(element => element.getBoundingClientRect().top + window.scrollY);
  const originalTop = await sectionTop();
  const drill = page.getByRole('button', { name: '查看 2 笔明细' });
  const started = page.waitForRequest(request => {
    const url = new URL(request.url());
    return url.pathname === '/api/commerce/orders' && url.searchParams.get('status') === 'CANCELLED';
  });
  try {
    await drill.click();
    const params = new URL((await started).url()).searchParams;
    expect(params.get('currency')).toBe('CNY');
    expect(params.get('customerId')).toBe('crm-customer');
    expect(params.get('limit')).toBe('10');
    await expect(rows).toHaveCount(10);
    await expect(rows.first()).toHaveText('商城订单-11');
    await expect(drill).toHaveAttribute('aria-pressed', 'false');
    expect(await sectionTop()).toBeCloseTo(originalTop, 1);
  } finally {
    finishDrill();
  }

  await expect(rows).toHaveCount(2);
  await expect(heading).toBeFocused();
  await expect(drill).toHaveAttribute('aria-pressed', 'true');
  const back = page.getByRole('button', { name: '返回全部订单' });
  await expect(back).toBeInViewport({ ratio: 0.95 });
  await back.click();
  await expect(pager).toContainText('共 24 笔 · 第 2/3 页');
  await expect(rows.first()).toHaveText('商城订单-11');
  await expect(drill).toHaveAttribute('aria-pressed', 'false');
  await pager.getByRole('button', { name: '下一页' }).click();
  await expect(pager).toContainText('第 3/3 页');
  await expect(rows).toHaveCount(4);
  await expect(pager.getByRole('button', { name: '下一页' })).toBeDisabled();

  failNextDrill = true;
  await drill.click();
  await expect(page.getByRole('alert')).toHaveText('商城明细暂时无法加载');
  await expect(pager).toContainText('第 3/3 页');
  await expect(rows).toHaveCount(4);
  await page.getByRole('button', { name: '重试' }).click();
  await expect(rows).toHaveCount(2);
});

test('商城会员用中文显示示例编号，原号可展开', async ({ page }) => {
  await mockCommerce(page);
  await fillLogin(page, 'admin', 'test-password');
  await page.getByRole('button', { name: '商城会员', exact: true }).click();
  const member = page.getByRole('rowheader').filter({ hasText: '演示会员 01' });
  await expect(member).toBeVisible();
  await expect(member.getByText(sample.externalMemberId, { exact: true })).not.toBeVisible();
  await member.getByText('演示会员 01', { exact: true }).click();
  await expect(member.getByText(sample.externalMemberId, { exact: true })).toBeVisible();
});

test('商城沿用后台布局与登录，可往返全部既有栏目', async ({ page }) => {
  await mockCommerce(page);
  await fillLogin(page, 'admin', 'test-password', '/');
  await expect(page.getByRole('heading', { name: '员工与账号', exact: true })).toBeVisible();

  const nav = page.getByRole('navigation', { name: '后台导航' });
  const commerce = nav.getByRole('link', { name: '商城经营' });
  for (const section of ['公司重要事项', '修改记录', '申请与审核', '员工与账号']) {
    await commerce.click();
    await expect(page).toHaveURL(/\/commerce$/);
    await expect(commerce).toHaveAttribute('aria-current', 'page');
    await expect(page.getByRole('heading', { name: '经营概览' })).toBeVisible();
    await nav.getByRole('button', { name: section, exact: true }).click();
    await expect(page.getByRole('heading', { name: section, exact: true })).toBeVisible();
    await expect(nav.getByRole('button', { name: section, exact: true })).toHaveAttribute('aria-current', 'page');
  }
  expect(await page.evaluate(() => sessionStorage.getItem('workpanel-token'))).toBe('test-session');
});

test('商城导入异常可定位且 320px 页面无横向溢出', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 700 });
  await mockCommerce(page);
  await fillLogin(page, 'admin', 'test-password');
  await page.getByRole('button', { name: '文件导入', exact: true }).click();
  await page.getByLabel('商城文件', { exact: true }).setInputFiles({
    name: 'invalid.json', mimeType: 'application/json', buffer: Buffer.from('invalid'),
  });
  await page.getByRole('button', { name: '开始导入' }).click();
  await expect(page.getByRole('alert')).toContainText('订单列表 · 第 2 条 · 金额');
  await expect(page.getByRole('alert')).toContainText('test-row');
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(320);
});

test('商城授权失效时清理业务界面并回到登录', async ({ page }) => {
  await mockCommerce(page, true);
  await fillLogin(page, 'admin', 'test-password');
  await expect(page.getByRole('heading', { name: '欢迎回来' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('不在授权范围内');
  await expect(page.getByRole('navigation', { name: '商城经营' })).toHaveCount(0);
  await expect(page.getByRole('navigation', { name: '后台导航' })).toHaveCount(0);
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
  await page.getByLabel('商城文件', { exact: true }).setInputFiles({
    name: 'live.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(data)),
  });
  await page.getByRole('button', { name: '开始导入' }).click();
  await expect(page.getByRole('heading', { name: '导入完成' })).toBeVisible();
  await page.getByRole('button', { name: '开始导入' }).click();
  await expect(page.getByRole('heading', { name: '此文件此前已导入' })).toBeVisible();
  await page.getByRole('button', { name: '查看经营概览' }).click();
  await page.getByLabel('客户编号').fill(customerId);
  await page.getByRole('button', { name: '查询', exact: true }).click();
  await page.getByRole('button', { name: '查看 1 笔明细' }).click();
  await expect(page.getByRole('rowheader', { name: new RegExp(orderId) })).toBeVisible();
  await expect(page.getByRole('cell', { name: /人民币 12\.34/ })).toBeVisible();
  await page.getByRole('button', { name: '批次 · 第 1 条' }).click();
  await expect(page.getByRole('heading', { name: '导入来源' })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(page.viewportSize()?.width);
  await page.screenshot({ path: testInfo.outputPath('commerce-overview.png'), fullPage: true });
});
