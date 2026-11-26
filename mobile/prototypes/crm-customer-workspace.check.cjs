// Run from repo root: node mobile/prototypes/crm-customer-workspace.check.cjs
// Uses local files only; screenshots and result JSON go to ignored output/.
const { chromium } = require('../../web/node_modules/playwright');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '../..');
const out = path.join(root, 'output/crm-mobile-prototype');
fs.mkdirSync(out, { recursive: true });
const url = pathToFileURL(path.join(__dirname, 'crm-customer-workspace.html')).href;
(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || (process.platform === 'win32' ? 'C:/Program Files/Google/Chrome/Application/chrome.exe' : undefined) });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const errors = []; const results = [];
  page.on('pageerror', e => errors.push(e.message));
  const click = (action, value) => page.locator(`[data-action="${action}"]${value === undefined ? '' : `[data-value="${value}"]`}`).first().click();
  const text = () => page.locator('#content').innerText();
  async function shot(name) { await page.screenshot({ path: path.join(out, name + '.png') }); }
  async function check(name, run) { await run(); results.push(name); console.log('PASS ' + name); }
  async function tools(values) {
    await page.locator('#tools-open').click();
    for (const [name, value] of Object.entries(values)) await page.locator('#sheet-' + name).selectOption(value);
    await click('apply-tools');
  }
  try {
    await page.goto(url); await click('directory'); await page.evaluate(() => document.fonts.ready);
    await check('客户搜索、空结果与清空恢复', async () => {
      await page.locator('#search').fill('不存在的客户'); await page.locator('#search').press('Enter');
      assert.match(await text(), /没有找到匹配客户/); await click('clear');
      await page.locator('#search').fill('禾屿'); await page.locator('#search').press('Enter');
      assert.equal(await page.locator('.customer').count(), 1);
      await click('customer', 'heyu'); await click('directory');
      assert.equal(await page.locator('#search').inputValue(), '禾屿');
      await page.locator('#search').fill(''); await page.locator('#search').press('Enter');
      await shot('01-directory-390');
    });
    await check('客户分页与详情返回保持页码', async () => {
      await click('list-page', '1'); assert.match(await text(), /沈予安/);
      await click('customer', 'shen'); await click('directory'); assert.match(await text(), /沈予安/);
      assert.equal(await page.locator('#dock .pager span').innerText(), '2 / 2'); await click('list-page', '-1');
    });
    await check('筛选弹层、键盘关闭与焦点恢复', async () => {
      await click('filters'); await page.keyboard.press('Escape');
      assert.equal(await page.locator('#sheet').evaluate(e => e.open), false);
      assert.equal(await page.evaluate(() => document.activeElement.dataset.action), 'filters');
      await click('filters'); await page.locator('#filter-owner').selectOption('许禾');
      await page.locator('#filter-pending').check(); await click('apply-filters');
      assert.equal(await page.locator('.customer').count(), 1); assert.match(await text(), /禾屿/);
      await click('filters'); await click('reset-filters'); await click('apply-filters');
    });
    await check('客户档案、会员资格、年卡与权益使用', async () => {
      await click('customer', 'lin'); await shot('02-profile-390');
      assert.doesNotMatch(await text(), /秋日会员精选礼盒/);
      await click('tab', 'member'); assert.match(await text(), /拾光商城会员/);
      await click('member', '1'); assert.match(await text(), /余 2 次/);
      await shot('03-membership-390');
      await page.getByText('权益使用记录 · 4 条', { exact: true }).click();
      assert.match(await text(), /城市之声/);
      await click('directory'); await click('customer', 'zhou'); await click('tab', 'member');
      assert.match(await text(), /该资格已到期/);
    });
    await check('企业联系人、活动分类与负责人参与人', async () => {
      await click('directory'); await click('customer', 'heyu'); assert.match(await text(), /顾言/);
      await click('tab', 'member'); assert.match(await text(), /暂无会员资格/);
      await click('go-business'); await click('kind', 'activities'); await shot('04-business-390');
      assert.match(await text(), /企业参访/); await click('record', 'a3');
      assert.match(await text(), /许禾、陈晨、周舟/); await shot('05-activity-detail-390');
      await click('back'); assert.equal(await page.locator('[data-action="kind"][data-value="activities"]').getAttribute('aria-pressed'), 'true');
      await click('business-page', '1'); assert.match(await text(), /秋季工坊参访/);
      await click('record', 'a6'); await click('back'); assert.match(await text(), /秋季工坊参访/);
    });
    await check('服务进度、订单金额与退款分别展示', async () => {
      await click('directory'); await click('customer', 'lin'); await click('tab', 'business');
      assert.match(await text(), /待完成服务 · 2/); await click('service-status');
      assert.match(await text(), /已完成/); await click('business-page', '1'); assert.match(await text(), /已取消/);
      await click('kind', 'activities'); assert.match(await text(), /赛演/); assert.match(await text(), /私宴/);
      await click('kind', 'orders'); await click('record', 'o3');
      assert.match(await text(), /原实付金额/); assert.match(await text(), /已退款金额/);
      await shot('06-order-detail-390'); await click('back');
    });
    await check('受限示例不渲染联系方式与订单金额', async () => {
      await tools({ access: 'limited' }); assert.doesNotMatch(await text(), /¥/);
      await click('record', 'o1'); assert.doesNotMatch(await text(), /268/); assert.match(await text(), /未授权/);
      await click('back'); await click('tab', 'profile'); assert.doesNotMatch(await text(), /138/);
      assert.match(await text(), /联系信息未授权/); await shot('07-restricted-390');
      await tools({ access: 'full' });
    });
    await check('空、加载、失败、来源不可用、失权与过期反馈', async () => {
      for (const feedback of ['empty', 'loading', 'error', 'unavailable', 'forbidden', 'expired']) {
        await tools({ state: feedback });
        assert.equal(await page.locator('.state-panel').count(), 1);
        if (['forbidden', 'expired'].includes(feedback)) assert.doesNotMatch(await page.locator('#device').innerText(), /林小满|138|¥/);
        if (feedback === 'error') await shot('08-error-390');
        await click('recover'); assert.equal(await page.locator('.state-panel').count(), 0);
      }
    });
    await check('320/390/412px、1.5 倍字、底部操作与横向布局', async () => {
      for (const [width, height] of [[320, 568], [390, 844], [412, 915]]) {
        await page.setViewportSize({ width, height }); await page.goto(url); await click('directory');
        for (const font of ['1', '1.5']) {
          await tools({ font });
          for (const tab of ['directory', 'profile', 'member', 'business', 'record']) {
            if (tab === 'profile') await click('customer', 'lin');
            if (['member', 'business'].includes(tab)) await click('tab', tab);
            if (tab === 'record') await click('record', 's1');
            const geometry = await page.evaluate(() => {
              const content = document.querySelector('#content'), dock = document.querySelector('#dock');
              return { body: document.documentElement.scrollWidth, width: innerWidth, content: content.scrollWidth, cw: content.clientWidth, bottom: dock.getBoundingClientRect().bottom, height: innerHeight,
                smallTargets: [...document.querySelectorAll('#content button,#dock button,#content summary')].filter(e => e.getClientRects().length && e.getBoundingClientRect().height < 47.9).map(e => e.textContent),
                broken: [...document.images].filter(i => !i.complete || !i.naturalWidth).length };
            });
            assert(geometry.body <= geometry.width + 1, JSON.stringify(geometry));
            assert(geometry.content <= geometry.cw + 1, JSON.stringify(geometry));
            assert(geometry.bottom <= geometry.height + 1, JSON.stringify(geometry));
            assert.deepEqual(geometry.smallTargets, []); assert.equal(geometry.broken, 0);
            if (font === '1.5' && tab === 'member') await shot(`09-large-${width}`);
          }
          await click('back'); await click('directory');
        }
      }
    });
    await check('公司入口与键盘主链路', async () => {
      await page.setViewportSize({ width: 390, height: 844 }); await page.goto(url); await click('directory');
      await click('company-back'); await shot('10-company-entry-390'); await click('directory');
      await page.locator('#search').focus(); await page.keyboard.type(''); await page.keyboard.insertText('林小满'); await page.keyboard.press('Enter');
      await page.locator('[data-action="customer"]').focus(); await page.keyboard.press('Enter');
      assert.match(await text(), /基本资料/);
      await page.locator('#tab-member').focus(); await page.keyboard.press('Enter'); assert.match(await text(), /拾光商城会员/);
      await page.keyboard.press('Tab');
      await page.locator('#tab-member').focus(); await page.keyboard.press('ArrowRight');
      assert.equal(await page.locator('#tab-business').getAttribute('aria-selected'), 'true');
    });
    await check('公司原操作排入口、年月与今天、返回恢复日期视图', async () => {
      await page.goto(url);
      assert.equal(await page.locator('.customer-hub,[data-action="new-customer"]').count(),0);
      assert.equal(await page.locator('.company-action-row button').count(),2);
      assert.match(await page.locator('.company-action-row').innerText(), /派发任务[\s\S]*客户目录/);
      const geometry=await page.evaluate(()=>{const entry=document.querySelector('.customer-directory-entry').getBoundingClientRect(),today=document.querySelector('.calendar-today').getBoundingClientRect(),month=document.querySelector('.calendar-month').getBoundingClientRect(),grid=document.querySelector('.company-month-grid').getBoundingClientRect();return {entry:entry.bottom,today:today.y,month:month.y,right:today.x>month.x,grid:grid.height,visible:entry.bottom<innerHeight};});
      assert(geometry.visible&&geometry.right&&Math.abs(geometry.today-geometry.month)<2&&geometry.grid>390,JSON.stringify(geometry));
      await shot('12-company-entry');
      await click('calendar-picker'); await page.locator('#company-month').fill('2026-12'); await page.locator('#company-month-form [type="submit"]').click();
      assert.match(await page.locator('.calendar-month').textContent(),/2026年12月/);
      assert.equal(await page.locator('.calendar-bar').count(),0);
      await click('calendar-period','周'); await click('directory'); await click('new-customer'); await click('cancel-edit'); await click('company-back');
      assert.match(await page.locator('.calendar-month').textContent(),/2026年12月/);
      assert.equal(await page.locator('[data-action="calendar-period"][aria-pressed="true"]').innerText(),'周');
      await click('calendar-today');
      const expected=await page.evaluate(()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Shanghai'}).format(new Date()));
      const [y,m]=expected.split('-').map(Number);
      assert.match(await page.locator('.calendar-month').textContent(),new RegExp(`${y}年${m}月`));
      await click('calendar-period','月'); assert.equal(await page.locator('.calendar-day.selected.is-today').count(),1);
      await click('calendar-move','-1'); await click('calendar-move','1'); assert.match(await page.locator('.calendar-month').textContent(),new RegExp(`${y}年${m}月`));
      await click('calendar-period','日'); assert.equal(await page.locator('.company-agenda').count(),1); await click('calendar-period','月');
      await click('directory'); await click('filters'); await page.locator('#filter-pending').check(); await click('apply-filters');
      assert.equal(await page.locator('.customer').count(),2);
    });
    await check('公司日历主体及日期快捷栏的小屏大字布局', async () => {
      for(const [width,height] of [[320,568],[390,844],[412,915]]) {
        await page.setViewportSize({width,height}); await page.goto(url);
        for(const font of ['1','1.5']) {
          await tools({font});
          const fit=await page.evaluate(()=>{const header=document.querySelector('#app-header'),content=document.querySelector('#content'),today=document.querySelector('.calendar-today'),month=document.querySelector('.calendar-month');return {overflow:document.documentElement.scrollWidth>innerWidth||header.scrollWidth>header.clientWidth||content.scrollWidth>content.clientWidth,clipped:month.scrollWidth>month.clientWidth,touch:today.getBoundingClientRect().height,entry:document.querySelector('.customer-directory-entry').getBoundingClientRect().bottom,h:innerHeight,dock:document.querySelector('#dock').getBoundingClientRect().top};});
          assert(!fit.overflow&&!fit.clipped&&fit.touch>=48&&fit.entry<fit.dock,JSON.stringify(fit));
          await shot(`19-company-${width}-${font}`);
        }
      }
      await page.setViewportSize({width:320,height:568}); await page.goto(url);
      await page.locator('#content').evaluate(e=>e.scrollTop=100);
      const scroll=await page.locator('#content').evaluate(e=>e.scrollTop);
      await page.locator('.customer-directory-entry').evaluate(e=>e.click());
      await click('customer','heyu'); await click('tab','business'); await click('directory'); await click('company-back');
      assert.equal(await page.locator('#content').evaluate(e=>e.scrollTop),scroll);
      await page.setViewportSize({width:390,height:844});
    });
    await check('新建个人、字段错误聚焦和成功后查询', async () => {
      await page.goto(url); await click('directory'); await click('new-customer'); await shot('13-new-person');
      await page.locator('[form="customer-form"]').click();
      assert.equal(await page.evaluate(()=>document.activeElement.id),'edit-name');
      await page.locator('#edit-name').fill('原型测试客户'); await page.locator('#edit-phone').fill('abc');
      await page.locator('[form="customer-form"]').click(); assert.equal(await page.evaluate(()=>document.activeElement.id),'edit-phone');
      await page.locator('#edit-phone').fill('+86 100-000-0000');
      await page.locator('[form="customer-form"]').click(); assert.match(await text(), /已保存至原型示例/);
      assert.match(await text(), /原型测试客户/); await click('directory');
      await page.locator('#search').fill('原型测试客户'); await page.locator('#search').press('Enter');
      assert.equal(await page.locator('.customer').count(),1); await page.locator('.customer').click();
    });
    await check('编辑不改会员订单、取消保护、失败保留并重试', async () => {
      await click('edit-customer'); await page.locator('#edit-name').fill('修改后客户');
      await click('cancel-edit'); assert.match(await page.locator('#sheet').innerText(),/尚未保存/);
      await click('keep-edit'); assert.equal(await page.locator('#edit-name').inputValue(),'修改后客户');
      await tools({ save:'error' }); await page.locator('[form="customer-form"]').click();
      assert.match(await text(),/保存未成功/); assert.equal(await page.locator('#edit-name').inputValue(),'修改后客户');
      await shot('14-save-error'); await page.locator('[form="customer-form"]').click();
      assert.match(await text(),/修改后客户/); await click('directory');
      assert.equal(await page.locator('#search').inputValue(),'原型测试客户');
      await click('clear'); await click('customer','lin'); await click('edit-customer');
      assert.equal(await page.locator('#edit-phone').inputValue(),'');
      assert.doesNotMatch(await text(), /余 2 次|订单金额/);
      await page.locator('#edit-name').fill('不会保存'); await click('cancel-edit'); await click('discard-edit');
      assert.match(await text(), /林小满/); assert.doesNotMatch(await text(), /不会保存/);
    });
    await check('疑似重复核对、保留草稿与明确新建', async () => {
      await click('directory'); await click('new-customer'); await page.locator('#edit-name').fill('林小满');
      await page.locator('[form="customer-form"]').click(); assert.match(await page.locator('#sheet').innerText(),/避免重复/);
      await shot('15-duplicate'); await click('peek-duplicate','lin'); assert.match(await page.locator('#sheet').innerText(),/已有客户/);
      await click('duplicate-back'); await click('close'); assert.equal(await page.locator('#edit-name').inputValue(),'林小满');
      await page.locator('[form="customer-form"]').click(); await click('confirm-duplicate');
      assert.match(await text(), /已保存至原型示例/);
    });
    await check('企业新建及联系人添加、编辑、取消保护', async () => {
      await page.goto(url); await click('directory'); await click('new-customer'); await click('edit-type','企业');
      assert.equal(await page.locator('#sheet').evaluate(e=>e.open),false);
      await page.locator('#edit-name').fill('原型演示企业'); await page.locator('#edit-contactName').fill('示例对接人');
      await shot('16-new-company'); await page.locator('[form="customer-form"]').click(); assert.match(await text(), /示例对接人/);
      await click('add-contact'); await page.locator('#contact-name').fill('示例乙'); await page.locator('#contact-role').fill('行政对接');
      await page.keyboard.press('Escape'); assert.match(await page.locator('#sheet').innerText(), /放弃联系人修改/);
      await click('keep-contact'); assert.equal(await page.locator('#contact-name').inputValue(),'示例乙');
      await shot('17-contact-sheet'); await page.locator('#contact-form [type="submit"]').click();
      assert.match(await text(),/示例乙/); await click('edit-contact','1'); await page.locator('#contact-role').fill('资料对接');
      await page.locator('#contact-form [type="submit"]').click(); assert.match(await text(),/资料对接/);
      await click('add-contact'); await page.locator('#contact-name').fill('不保存联系人');
      await page.locator('#sheet-close').click(); assert.match(await page.locator('#sheet').innerText(), /放弃联系人修改/);
      await click('discard-contact'); assert.doesNotMatch(await text(), /不保存联系人/);
    });
    await check('版本冲突不能直接覆盖，重载后重新编辑', async () => {
      await click('edit-customer'); await page.locator('#edit-name').fill('冲突中的名称'); await tools({save:'conflict'});
      await page.locator('[form="customer-form"]').click(); assert.match(await text(),/资料已有更新/);
      assert(await page.locator('[form="customer-form"]').isDisabled());
      await click('reload-edit'); await click('discard-edit'); assert.equal(await page.locator('#edit-name').inputValue(),'原型演示企业');
      await click('cancel-edit');
    });
    await check('维护与字段权限分开，受限编辑保留旧号码', async () => {
      await page.goto(url); await click('directory'); await click('customer','lin');
      await tools({permission:'readonly'}); assert.equal(await page.locator('[data-action="edit-customer"]').count(),0);
      await click('directory'); assert.equal(await page.locator('[data-action="new-customer"]').count(),0);
      await tools({permission:'manage',access:'limited'}); await click('customer','lin'); await click('edit-customer');
      assert.equal(await page.locator('#edit-phone').count(),0); assert.doesNotMatch(await text(),/138/);
      await page.locator('#edit-owner').selectOption('许禾'); await page.locator('[form="customer-form"]').click();
      await tools({access:'full'}); assert.match(await text(),/138 \*\*\*\* 0268/); assert.match(await text(),/许禾/);
      await click('edit-customer'); await page.locator('#edit-name').fill('未保存'); await tools({permission:'readonly'});
      assert(await page.locator('[form="customer-form"]').isDisabled()); await click('cancel-edit'); await click('discard-edit');
    });
    await check('新增编辑页面与联系人弹层的小屏大字布局', async () => {
      for(const [width,height] of [[320,568],[390,844],[412,915]]) {
        await page.setViewportSize({width,height}); await page.goto(url); await click('directory'); await click('new-customer');
        await tools({font:'1.5'}); await click('edit-type','企业');
        const fit=async()=>{const g=await page.evaluate(()=>({w:innerWidth,sw:document.documentElement.scrollWidth,cw:document.querySelector('#content').clientWidth,cs:document.querySelector('#content').scrollWidth,dock:document.querySelector('#dock').getBoundingClientRect().bottom,h:innerHeight}));assert(g.sw<=g.w+1&&g.cs<=g.cw+1&&g.dock<=g.h+1,JSON.stringify(g));};
        await fit(); await shot(`18-editor-large-${width}`); await click('cancel-edit'); await click('discard-edit');
        await click('customer','heyu'); await click('add-contact');
        assert(await page.locator('#contact-form [type="submit"]').isVisible());
        assert(await page.locator('#sheet').evaluate(e=>e.scrollWidth<=e.clientWidth+1));
        await page.keyboard.press('Escape');
      }
    });
    await page.setViewportSize({ width: 1366, height: 980 }); await page.goto(url); await shot('11-desktop-studio');
    assert.deepEqual(errors, []);
    fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify({ passed: results.length, tests: results, pageErrors: errors, time: new Date().toISOString() }, null, 2));
    console.log(`${results.length} checks passed; screenshots: ${out}`);
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
