import { expect, test, type Page } from '@playwright/test';

const personal = { id: 'person-1', name: '示例客户林一', type: 'PERSONAL', updatedAt: '2026-11-21T16:30:00Z' };
const company = { id: 'company-1', name: '示例企业·山茶文化', type: 'COMPANY', ownerName: '示例运营', updatedAt: '2026-11-21' };
const second = { id: 'company-2', name: `示例企业·${'非常长的企业名称'.repeat(9)}`, type: 'COMPANY', ownerName: '示例运营' };
const entries = <T>(...items: T[]) => ({ state: 'AVAILABLE', items });
const pageResult = (items: unknown[], total = items.length, nextCursor: string | null = null, previousCursor: string | null = null) => ({ items, total, nextCursor, previousCursor });
const order = { id: 'order-1', title: '商城订单 M-001', status: '已支付', amountText: '¥1,680.00', businessDate: '2026-11-20', canOpen: true };
const membership = { id: 'pass-1', title: '演出年卡', status: '有效', validFrom: '2026-04-01', validTo: '2027-03-31', usageText: '已用 1 / 3 次', canOpen: true };
const benefit = { id: 'use-1', title: '活动权益使用', status: '已使用', canOpen: true };
const activity = { id: 'event-1', title: '企业参访·山茶文化', status: '已结束', businessDate: '2026-11-20', canOpen: true };
const service = { id: 'service-1', title: '会后资料交付', status: '待履约', canOpen: true };
const identity = { id: 'actor-1', name: '示例运营账号', role: 'EMPLOYEE', status: 'ACTIVE', must_change_password: false };

type Options = { role?: 'EMPLOYEE' | 'FINANCE'; mustChange?: boolean; pending?: boolean; denyList?: boolean; failList?: boolean; revokeOrder?: boolean; badRecord?: boolean; logoutOnRecord?: boolean; };
async function fixture(page: Page, options: Options = {}) {
  const requests: URL[] = [];
  let failed = false;
  const finance = options.role === 'FINANCE';
  const account = { ...identity, role: options.role ?? 'EMPLOYEE', must_change_password: !!options.mustChange, status: options.pending ? 'PENDING' : 'ACTIVE' };
  await page.route('**/api/**', async route => {
    const url = new URL(route.request().url()); requests.push(url);
    const respond = (json: unknown, status = 200) => route.fulfill({ status, json });
    if (url.pathname === '/api/auth/login') return respond({ token: 'crm-fixture-token', user: account });
    if (url.pathname === '/api/auth/me') return respond(account);
    if (url.pathname === '/api/auth/logout') return respond({ ok: true });
    if (route.request().headers().authorization !== 'Bearer crm-fixture-token') return respond({}, 401);
    if (url.pathname === '/api/crm/customers') {
      if (options.denyList) return respond({ message: '内部客户名称不应回显' }, 403);
      if (options.failList && !failed) { failed = true; return respond({}, 503); }
      const search = url.searchParams.get('search'), type = url.searchParams.get('type');
      if (search === '无结果') return respond(pageResult([]));
      if (search === '示例') return respond(pageResult(type === 'PERSONAL' ? [personal] : [company]));
      if (type === 'COMPANY') return respond(url.searchParams.has('cursor') ? pageResult([second], 2, null, 'begin') : pageResult([company], 2, 'after-company'));
      return respond(pageResult([personal, company]));
    }
    if (url.pathname === '/api/crm/customers/company-1') return respond({
      ...company, contactName: '示例联络人', ...(finance ? { contactPhone: '138****0000' } : {}),
      sections: { memberships: entries(membership), benefits: entries(benefit, { id: 'use-summary', title: '权益汇总', canOpen: false }),
        orders: finance ? entries(order) : { state: 'RESTRICTED', items: [order] }, activities: entries(activity), services: entries(service) },
    });
    if (url.pathname === '/api/crm/customers/person-1') return respond({ ...personal, sections: { memberships: entries(), benefits: { state: 'UNAVAILABLE' } } });
    if (url.pathname === '/api/crm/customers/company-2') return respond(second);
    if (url.pathname.endsWith('/orders/order-1') && (!finance || options.revokeOrder)) return respond({ message: order.amountText }, 403);
    const child = [order, activity, membership, benefit, service].find(item => url.pathname.endsWith(`/${item.id}`));
    if (url.pathname.includes('/company-1/records/') && child) {
      if (options.logoutOnRecord) return respond({}, 401);
      return respond({ ...child, kind: url.pathname.split('/').at(-2), customerId: options.badRecord ? 'wrong-company' : company.id,
        ...(child === activity ? { ownerName: '示例运营', participantNames: ['示例同事甲', '示例同事乙'] } : {}),
      });
    }
    return respond({ message: '内部不可显示' }, 404);
  });
  return requests;
}
async function logIn(page: Page, path = '/crm') {
  await page.goto(path);
  await page.getByLabel('账号', { exact: true }).fill('fixture.account');
  await page.getByLabel('密码', { exact: true }).fill('Fixture-password');
  await page.getByRole('button', { name: '登录', exact: true }).click();
}

test('可分页的客户目录返回时保留类型和游标', async ({ page }) => {
  const calls = await fixture(page); await logIn(page);
  await expect(page.getByRole('link', { name: /示例客户林一/ })).toBeVisible();
  await page.getByLabel('客户类型').selectOption('COMPANY');
  await page.getByRole('button', { name: '搜索' }).click();
  await expect(page.getByText('共 2 位客户')).toBeVisible();
  await page.getByRole('link', { name: '下一页' }).click();
  await page.getByRole('link', { name: /非常长的企业名称/ }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(second.name);
  await page.getByRole('link', { name: /返回客户目录/ }).click();
  await expect(page.getByLabel('客户类型')).toHaveValue('COMPANY');
  await expect(page.getByRole('link', { name: /非常长的企业名称/ })).toBeVisible();
  expect(calls.some(url => url.searchParams.get('cursor') === 'after-company' && url.searchParams.get('limit') === '20')).toBe(true);
});

test('有权限的五类关联信息可查看，已授权记录可深链', async ({ page }) => {
  await fixture(page, { role: 'FINANCE' }); await logIn(page);
  await page.getByLabel('关键词').fill('示例');
  await page.getByRole('button', { name: '搜索' }).click();
  await page.getByRole('link', { name: /山茶文化/ }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(company.name);
  for (const name of ['会员资格', '权益记录', '商城订单', '活动记录', '服务进度']) await expect(page.getByRole('heading', { name, exact: true })).toBeVisible();
  await expect(page.getByText('到期 2027-03-31')).toBeVisible();
  await expect(page.getByText('已用 1 / 3 次')).toBeVisible();
  await expect(page.getByText('待履约')).toBeVisible();
  await expect(page.getByText('138****0000')).toBeVisible();
  await expect(page.getByRole('link', { name: /查看权益记录：权益汇总/ })).toHaveCount(0);
  await page.getByRole('link', { name: `查看商城订单：${order.title}` }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(order.title);
  await expect(page.getByText(order.amountText, { exact: true })).toBeVisible();
  await page.reload(); await expect(page.getByRole('heading', { level: 1 })).toHaveText(order.title);
  await page.getByRole('link', { name: /返回客户详情/ }).click();
  await page.getByRole('link', { name: `查看活动记录：${activity.title}` }).click();
  await expect(page.getByText('示例同事甲、示例同事乙')).toBeVisible();
  for (const [label, item] of [['会员资格', membership], ['权益记录', benefit], ['服务进度', service]] as const) {
    await page.getByRole('link', { name: /返回客户详情/ }).click();
    await page.getByRole('link', { name: `查看${label}：${item.title}` }).click();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(item.title);
  }
  await page.getByRole('link', { name: /返回客户详情/ }).click();
  await page.getByRole('link', { name: /返回客户目录/ }).click();
  await expect(page.getByLabel('关键词')).toHaveValue('示例');
});

test('普通运营不展示受限信息，手动直达受限订单也不会渲染金额', async ({ page }) => {
  await fixture(page); await logIn(page, '/crm/customers/company-1');
  await expect(page.getByText('此类别未获授权。')).toBeVisible();
  await expect(page.getByText(order.title)).toHaveCount(0);
  await expect(page.getByText('联系电话')).toHaveCount(0);
  await page.goto('/crm/customers/company-1/records/orders/order-1');
  await expect(page.getByRole('heading', { name: '无权查看此内容' })).toBeVisible();
  await expect(page.getByText(order.amountText)).toHaveCount(0);
});

test('空结果、空记录、未接入和请求失败的提示各不相同', async ({ page }) => {
  await fixture(page, { failList: true }); await logIn(page);
  await expect(page.getByRole('heading', { name: '暂时无法读取' })).toBeVisible();
  await page.getByRole('button', { name: '重试' }).click();
  await page.getByLabel('关键词').fill('无结果');
  await page.getByRole('button', { name: '搜索' }).click();
  await expect(page.getByRole('heading', { name: '没有符合条件的客户' })).toBeVisible();
  await page.getByRole('button', { name: '查看全部客户' }).click();
  await page.getByRole('link', { name: /示例客户林一/ }).click();
  await expect(page.getByText('暂无记录。')).toBeVisible();
  await expect(page.getByText('此来源暂不可用。').first()).toBeVisible();
});

test('打开时撤销权限、会话失效、不匹配的记录均不保留旧资料', async ({ page }) => {
  const options: Options = { role: 'FINANCE', revokeOrder: true };
  await fixture(page, options); await logIn(page, '/crm/customers/company-1');
  await expect(page.getByText(/订单金额 ¥/)).toBeVisible();
  await page.getByRole('link', { name: /查看商城订单/ }).click();
  await expect(page.getByRole('heading', { name: '无权查看此内容' })).toBeVisible();
  await expect(page.getByText(order.amountText)).toHaveCount(0);
  options.revokeOrder = false; options.badRecord = true;
  await page.reload(); await expect(page.getByRole('heading', { name: '暂时无法读取' })).toBeVisible();
  await expect(page.getByText(order.title)).toHaveCount(0);
  options.badRecord = false; options.logoutOnRecord = true;
  await page.getByRole('button', { name: '重试' }).click();
  await expect(page.getByRole('alert')).toContainText('登录已失效');
  expect(await page.evaluate(() => sessionStorage.getItem('workpanel-crm-token'))).toBeNull();
});

test('待确认、首次改密及目录无权访问时不显示业务数据', async ({ page }) => {
  const options: Options = { pending: true, denyList: true };
  const calls = await fixture(page, options); await logIn(page);
  await expect(page.getByRole('alert')).toContainText('归属未确认');
  expect(calls.some(url => url.pathname.startsWith('/api/crm'))).toBe(false);
  // Use a new response with the new identity instead of modifying the old fixture.
  await page.unroute('**/api/**'); await fixture(page, { mustChange: true }); await logIn(page);
  await expect(page.getByRole('alert')).toContainText('首次密码修改');
  await page.unroute('**/api/**'); await fixture(page, { denyList: true }); await logIn(page);
  await expect(page.getByRole('heading', { name: '无权查看此内容' })).toBeVisible();
  await expect(page.getByText('内部客户名称不应回显')).toHaveCount(0);
});

test('慢响应不会盖住后提交的筛选结果', async ({ page }) => {
  await fixture(page); await logIn(page);
  let release!: () => void;
  const wait = new Promise<void>(resolve => { release = resolve; });
  await page.route('**/api/crm/customers?**', async route => {
    const search = new URL(route.request().url()).searchParams.get('search');
    if (search === '旧条件') { await wait; await route.fulfill({ json: pageResult([personal]) }).catch(() => {}); }
    else await route.fallback();
  });
  await page.getByLabel('关键词').fill('旧条件');
  await page.getByRole('button', { name: '搜索' }).click();
  await expect(page.getByText('正在读取客户目录…')).toBeVisible();
  await page.getByLabel('关键词').fill('无结果');
  await page.getByRole('button', { name: '搜索' }).click();
  await expect(page.getByRole('heading', { name: '没有符合条件的客户' })).toBeVisible();
  release();
  await expect(page.getByRole('link', { name: /示例客户林一/ })).toHaveCount(0);
});

for (const width of [1440, 390, 320]) test(`${width}px 可用键盘搜索和查看详情，无页面横向溢出`, async ({ page }) => {
  await page.setViewportSize({ width, height: 900 });
  await fixture(page, { role: 'FINANCE' }); await logIn(page);
  const fit = async () => expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await expect(page.getByRole('heading', { name: '客户目录' })).toBeVisible();
  await page.getByLabel('关键词').fill('示例'); await page.keyboard.press('Enter');
  const link = page.getByRole('link', { name: /山茶文化/ }); await link.focus();
  await expect(link).toBeFocused(); await fit();
  await page.screenshot({ path: `../output/crm-evidence/客户目录-${width}.png`, fullPage: true });
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(company.name);
  await fit(); await page.screenshot({ path: `../output/crm-evidence/客户详情-${width}.png`, fullPage: true });
});
