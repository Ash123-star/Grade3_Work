import { test, expect } from '@playwright/test';

test('single development map shows authorized analysis and evidence', async ({ page }, testInfo) => {
  test.skip(!process.env.PREVIEW_ACCOUNT || !process.env.PREVIEW_PASSWORD, 'Set preview credentials for live API checks');
  await page.goto('/');
  await page.getByLabel('账号').fill(process.env.PREVIEW_ACCOUNT!);
  await page.getByLabel('密码', { exact: true }).fill(process.env.PREVIEW_PASSWORD!);
  await page.getByRole('button', { name: '登录', exact: true }).click();
  await expect(page.getByRole('heading', { name: '成长与发展地图' })).toBeVisible();
  await expect(page.getByRole('button', { name: '更新分析' })).toBeVisible();
  await expect(page.getByRole('heading', { name: '经历与成果' })).toBeVisible();
  if (testInfo.project.name === 'mobile') await expect(page.getByRole('heading', { name: '发展路径' })).toBeVisible();
  else await expect(page.locator('.vue-flow__node').first()).toBeVisible();
  await page.getByRole('button', { name: '管理记忆' }).click();
  await expect(page.getByRole('heading', { name: '记忆知识库' })).toBeVisible();
  await page.getByRole('button', { name: '关闭' }).click();
  await page.getByRole('button', { name: '查看 RAG 分析依据' }).click();
  await expect(page.getByRole('heading', { name: 'RAG 分析依据' })).toBeVisible();
  await expect(page.locator('.drawer article').first()).toBeVisible();
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
  expect(overflow).toBeLessThanOrEqual(1);
  await page.screenshot({ path: testInfo.outputPath('development-map.png'), fullPage: true });
});

test('knowledge status and forget job reach a clear terminal state', async ({ page }) => {
  let forgotten = false;
  let jobReads = 0;
  await page.addInitScript(() => sessionStorage.setItem('workpanel-token', 'browser-test-token'));
  await page.route('**/api/**', async route => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    let body: unknown;
    let status = 200;
    if (path === '/api/auth/me') body = {role: 'ADMIN', must_change_password: false};
    else if (path === '/api/admin/workspace/ai-maps/development') body = {
      scopes: [{domain: 'PERSONAL', scopeType: 'SELF', scopeId: 'self', label: '个人'}],
      analysis: {},
    };
    else if (path === '/api/admin/workspace/ai-memories/knowledge-status') body = {
      memories: forgotten ? 0 : 1, indexedMemories: 0,
      indexingMemories: forgotten ? 0 : 1, candidates: 1,
    };
    else if (path === '/api/admin/workspace/ai-memories/preferences/me') body = {version: 1, explicit_goals: '', response_preferences: ''};
    else if (path === '/api/admin/workspace/ai-memories' && request.method() === 'GET') body = {
      items: forgotten ? [] : [{id: 'memory-1', version: 2, content: '完成模块评审', claim_type: 'FACT', provenance: 'SELF_REPORTED', status: 'ACTIVE', source_version: 1}],
    };
    else if (path === '/api/admin/workspace/ai-memories/memory-1' && request.method() === 'DELETE') {
      expect(request.headers()['if-match']).toBe('2');
      forgotten = true;
      status = 202;
      body = {id: 'forget-1', state: 'PENDING'};
    } else if (path === '/api/admin/workspace/ai-memories/forget-jobs/forget-1') {
      body = {id: 'forget-1', state: ++jobReads === 1 ? 'PENDING' : 'SUCCEEDED'};
    } else throw new Error(`Unexpected API request: ${request.method()} ${path}`);
    await route.fulfill({status, contentType: 'application/json', body: JSON.stringify(body)});
  });

  await page.goto('/');
  await expect(page.getByText('有效记忆 1 条 · 已索引 0 条 · 更新中 1 条 · 待确认 1 条')).toBeVisible();
  await page.getByRole('button', {name: '管理记忆'}).click();
  await expect(page.getByText('完成模块评审')).toBeVisible();
  page.once('dialog', dialog => dialog.accept());
  await page.getByRole('button', {name: '停止记忆'}).click();
  await expect(page.getByText('有效记忆 0 条 · 已索引 0 条 · 更新中 0 条 · 待确认 1 条')).toBeVisible();
  await expect(page.getByText('记忆及关联索引已清理')).toBeVisible({timeout: 8000});
  expect(jobReads).toBe(2);
});

test('analysis failures and missing evidence never reveal a sample conclusion', async ({ page }) => {
  let state = 'NO_HIT';
  await page.addInitScript(() => sessionStorage.setItem('workpanel-token', 'browser-test-token'));
  await page.route('**/api/**', async route => {
    const path = new URL(route.request().url()).pathname;
    let status = 200;
    let body: unknown;
    if (path === '/api/auth/me') body = {role: 'ADMIN', must_change_password: false};
    else if (path === '/api/admin/workspace/ai-maps/development') {
      if (state === 'DENIED') {status = 403; body = {code: 'FORBIDDEN', message: '你没有访问这项内容的权限'};}
      else body = {
        scopes: [{domain: 'PERSONAL', scopeType: 'SELF', scopeId: 'self', label: '个人'}],
        analysis: state === 'NO_HIT' ? {
          id: 'analysis-1', state: 'SUCCEEDED', output: {
            summary: '本次没有检索到相关有效证据', basisQuality: 'INSUFFICIENT', generatedAt: '2026-10-09',
            retrieval: {degradedReason: '图谱暂不可用，使用文本证据'}, facts: [], directions: [], suggestions: [], gaps: ['缺少相关成果'],
          },
        } : {id: 'analysis-1', state, error: state === 'FAILED' ? 'DeepSeek 尚未配置' : '来源已变化，请更新分析'},
      };
    } else if (path === '/api/admin/workspace/ai-memories/knowledge-status') body = {memories: 1, indexedMemories: 0, indexingMemories: 1, candidates: 0};
    else if (path === '/api/admin/workspace/ai-memories/preferences/me') body = {version: 1, explicit_goals: '', response_preferences: ''};
    else throw new Error(`Unexpected API request: ${path}`);
    await route.fulfill({status, contentType: 'application/json', body: JSON.stringify(body)});
  });
  await page.goto('/');
  await expect(page.getByText('本次没有检索到相关有效证据')).toBeVisible();
  await expect(page.getByText('图谱暂不可用，使用文本证据')).toBeVisible();
  await expect(page.getByText('有效记忆 1 条 · 已索引 0 条 · 更新中 1 条 · 待确认 0 条')).toBeVisible();
  for (const [next, text] of [['FAILED', 'DeepSeek 尚未配置'], ['STALE', '来源已变化，请更新分析'], ['DENIED', '你没有访问这项内容的权限']]) {
    state = next;
    await page.reload();
    await expect(page.getByText(text)).toBeVisible();
    await expect(page.getByText('从执行任务，走向独立推进')).toHaveCount(0);
  }
});
