import { test, expect, type Page, type BrowserContext } from '@playwright/test';

test.use({actionTimeout: 30_000});
const errors = new WeakMap<BrowserContext, string[]>();
test.beforeEach(async ({page, context}) => {
  const messages: string[] = [];
  errors.set(context, messages);
  page.on('pageerror', (error) => messages.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error' && /Exception|RenderFlex|overflowed/.test(message.text())) messages.push(message.text());
  });
});
test.afterEach(async ({context}) => expect(errors.get(context)).toEqual([]));

/// Flutter Web paints to a canvas and exposes buttons as `flt-semantics`
/// nodes over it. A normal `.click()` works for most, but when a node sits over
/// the map canvas Playwright's hit-target check can hang. Try the normal click
/// briefly, then fall back to a raw mouse click at the node's centre.
async function tap(page: Page, name: string, {exact = false, timeout = 30_000}: {exact?: boolean; timeout?: number} = {}) {
  const target = page.getByRole('button', {name, exact});
  await target.waitFor({state: 'attached', timeout});
  try {
    await target.click({timeout: 5_000});
  } catch {
    const box = await target.boundingBox();
    if (!box) throw new Error(`tap: "${name}" has no bounding box`);
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  }
}

/// Enables Flutter's semantics tree. The `Enable accessibility` placeholder
/// can be clicked before Flutter has wired up its handler, silently losing the
/// event, so retry until a known semantic node actually appears.
async function enableSemantics(page: Page) {
  const enable = page.getByRole('button', {name: 'Enable accessibility'});
  await enable.waitFor({state: 'attached', timeout: 60_000});
  const ready = page.getByRole('button', {name: '我的避難準備'});
  for (let attempt = 0; attempt < 6; attempt++) {
    await enable.dispatchEvent('click').catch(() => {});
    try {
      await ready.waitFor({state: 'attached', timeout: 10_000});
      return;
    } catch {
      // Semantics not up yet (still loading CanvasKit/font, or the click was
      // dropped). Try again.
    }
  }
  throw new Error('Flutter semantics did not become available');
}

async function openAlerts(page: Page) {
  await page.goto('/app/');
  await enableSemantics(page);
  await tap(page, '區域災害警報', {timeout: 60_000});
}

function fixture() {
  const now = Date.now();
  const iso = (minutes: number) => new Date(now + minutes * 60_000).toISOString();
  const current = {
    id: 'fixture-current', messageId: 'fixture-current', event: '降雨', headline: '測試用中正區降雨公告',
    senderName: '測試發布單位', description: '這是端對端測試資料，不是真實警報。', instruction: '請閱讀發布單位說明。',
    state: 'active', messageType: 'Alert', severity: 'Severe', sentAt: iso(-5), effectiveAt: iso(-5), expiresAt: iso(60),
    areas: ['臺北市中正區'], regions: [{city: '臺北市', township: '中正區'}], regionMatch: 'exact',
    sourceUrl: 'https://alerts.ncdr.nat.gov.tw/Capstorage/fixture.cap', webUrl: 'https://alerts.ncdr.nat.gov.tw/',
  };
  const expired = {...current, id: 'fixture-expired', headline: '測試用已到期公告', state: 'expired', expiresAt: iso(-1)};
  const cancelled = {...current, id: 'fixture-cancel', headline: '測試用解除公告', state: 'cancelled', messageType: 'Cancel'};
  return {current, expired, cancelled, fetchedAt: iso(0)};
}

test('mobile region following, history and shelter handoff', async ({page}) => {
  test.setTimeout(180_000);
  const f = fixture();
  await page.setViewportSize({width: 390, height: 844});
  await page.route('**/api/alerts?*', async (route) => {
    const params = new URL(route.request().url()).searchParams;
    const data = params.get('history') === 'true' ? [f.current, f.expired, f.cancelled] : [f.current];
    await route.fulfill({json: {available: true, success: true, freshness: 'fresh', fetchedAt: f.fetchedAt, sourceUpdatedAt: f.fetchedAt, refreshAfterSeconds: 120, partial: false, data, total: data.length}});
  });
  await openAlerts(page);
  await expect(page.getByRole('group', {name: /測試用中正區降雨公告/})).toBeVisible();
  await expect(page.getByRole('checkbox', {name: '發布期間內', exact: true})).toBeVisible();
  const regions = page.waitForResponse((r) => new URL(r.url()).pathname === '/api/regions');
  await tap(page, '全國', {exact: true});
  await regions;
  await page.getByRole('button', {name: '縣市 選擇縣市'}).press('Enter');
  const towns = page.waitForResponse((r) => new URL(r.url()).pathname === '/api/regions' && new URL(r.url()).searchParams.get('city') === '臺北市');
  await page.getByRole('menuitem', {name: '臺北市', exact: true}).click();
  await towns;
  await page.getByRole('button', {name: '鄉鎮市區 全縣市'}).press('Enter');
  await page.getByRole('menuitem', {name: '中正區', exact: true}).click();
  const scoped = page.waitForRequest((r) => r.url().includes('/api/alerts') && new URL(r.url()).searchParams.get('township') === '中正區');
  await tap(page, '套用');
  await scoped;
  await tap(page, '關注這個區域');
  await expect.poll(() => page.evaluate(async () => JSON.parse(await (window as any).tesiis.readLibrary()).alertRegions?.[0]?.township)).toBe('中正區');
  await page.getByRole('switch', {name: /^包含近期歷史公告/}).click();
  // Cards are built lazily by Flutter; scroll before locating the older cards.
  await page.mouse.move(190, 680);
  await page.mouse.wheel(0, 650);
  await expect(page.getByRole('group', {name: /測試用已到期公告/})).toBeVisible();
  await page.mouse.wheel(0, 500);
  await expect(page.getByRole('group', {name: /測試用解除公告/})).toBeVisible();
  await openAlerts(page);
  await expect(page.getByRole('button', {name: '取消關注', exact: true})).toBeVisible();
  const shelterQuery = page.waitForRequest((r) => {
    const url = new URL(r.url());
    return url.pathname === '/api/shelters' && url.searchParams.get('city') === '臺北市' && url.searchParams.get('township') === '中正區';
  });
  await tap(page, '查詢此區避難所');
  await shelterQuery;
  await expect(page.getByRole('textbox', {name: '搜尋地點、避難所...'})).toBeVisible();
  await page.screenshot({path: test.info().outputPath('alert-to-shelters.png')});
});

test('network failure uses explicitly unverified device cache with original fetch time', async ({page}) => {
  test.setTimeout(180_000);
  const f = fixture();
  let fail = false;
  await page.route('**/api/alerts?*', (route) => fail ? route.fulfill({status: 503, json: {available: false}}) : route.fulfill({json: {available: true, data: [f.current], freshness: 'fresh', fetchedAt: f.fetchedAt, refreshAfterSeconds: 120, total: 1}}));
  await openAlerts(page);
  await expect(page.getByRole('checkbox', {name: '發布期間內', exact: true})).toBeVisible();
  fail = true;
  await tap(page, '重新整理警報');
  await expect(page.getByText(/裝置快取：目前無法取得新公告/)).toBeVisible();
  await expect(page.getByRole('checkbox', {name: '最新狀態待確認', exact: true})).toBeVisible();
  await expect(page.getByRole('checkbox', {name: '發布期間內', exact: true})).toHaveCount(0);
  await page.screenshot({path: test.info().outputPath('cached-alert.png')});
});

test('unavailable and fresh empty results have distinct messages', async ({page}) => {
  test.setTimeout(180_000);
  let healthy = false;
  await page.route('**/api/alerts?*', (route) => healthy ? route.fulfill({json: {available: true, data: [], freshness: 'fresh', fetchedAt: new Date().toISOString(), refreshAfterSeconds: 120, total: 0}}) : route.fulfill({status: 503, json: {available: false}}));
  await openAlerts(page);
  await expect(page.getByText('目前無法取得警報資料，請重試或查看官方平台。', {exact: true})).toBeVisible();
  await expect(page.getByText('本次來源清單沒有符合條件的公告。', {exact: true})).toHaveCount(0);
  healthy = true;
  await tap(page, '重新整理警報');
  await expect(page.getByText('本次來源清單沒有符合條件的公告。', {exact: true})).toBeVisible();
});
