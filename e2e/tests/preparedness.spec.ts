import { test, expect, type Page, type APIRequestContext, type BrowserContext } from '@playwright/test';

test.use({actionTimeout: 30_000});
const errors = new WeakMap<BrowserContext, string[]>();
test.beforeEach(async ({page, context}) => {
  const messages: string[] = [];
  errors.set(context, messages);
  const listen = (p: Page) => {
    p.on('pageerror', (error) => messages.push(error.message));
    p.on('console', (message) => {
      if (message.type() === 'error' && /Exception|RenderFlex|overflowed/.test(message.text())) messages.push(message.text());
    });
  };
  listen(page);
  context.on('page', listen);
});
test.afterEach(async ({context}) => expect(errors.get(context)).toEqual([]));

/// Enables Flutter's semantics tree, retrying the placeholder click until a
/// known semantic node appears — it can be clicked before Flutter wires up its
/// handler, silently losing the event.
async function semantics(page: Page) {
  const enable = page.getByRole('button', {name: 'Enable accessibility'});
  await enable.waitFor({state: 'attached', timeout: 60_000});
  // `我的避難準備` is in the toolbar in both map and list mode (the search
  // button is replaced once list mode opens search), so it is a stable probe
  // for "semantics is on AND the app has mounted".
  const ready = page.getByRole('button', {name: '我的避難準備'});
  for (let attempt = 0; attempt < 6; attempt++) {
    await enable.dispatchEvent('click').catch(() => {});
    try {
      await ready.waitFor({state: 'attached', timeout: 10_000});
      return;
    } catch {
      // Not up yet; retry.
    }
  }
  throw new Error('Flutter semantics did not become available');
}

/// Flutter Web renders to a canvas with transparent `flt-semantics` nodes over
/// it. A normal `.click()` works for most of them, but when the node sits over
/// the map canvas Playwright's hit-target check can hang indefinitely. Try the
/// normal click briefly, then fall back to a raw mouse click at the node's
/// centre (still a real pointer event, just without the hit-target wait).
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
async function sample(request: APIRequestContext, city = '臺北市') {
  const response = await request.get(`/api/shelters/package?city=${encodeURIComponent(city)}`);
  expect(response.ok()).toBeTruthy();
  return response.json();
}
async function stored(page: Page) {
  return page.evaluate(async () => JSON.parse(await (window as any).tesiis.readLibrary() ?? '{}'));
}

/// Flutter Web can drop a programmatic `fill()` that lands while a field is
/// still animating in (the input event never reaches the framework), so the
/// value silently stays at its default. Click, fill, and confirm the value
/// actually stuck — retyping once if it did not.
async function fillFlutter(page: Page, name: string, value: string) {
  const field = page.getByRole('textbox', {name});
  await field.waitFor({state: 'visible', timeout: 10_000});
  await field.click({timeout: 10_000});
  for (let attempt = 0; attempt < 2; attempt++) {
    await field.fill(value, {timeout: 10_000});
    const ok = await field.inputValue().then((v) => v === value).catch(() => false);
    if (ok) return;
  }
  await expect(field).toHaveValue(value);
}

test('mobile deep link, bookmark editing, QR share and reload persistence', async ({page, context, request}) => {
  test.setTimeout(120_000);
  const body = await sample(request);
  const shelter = body.data[0];
  await page.setViewportSize({width: 390, height: 844});
  await page.goto(`/app/?shelter=${encodeURIComponent(shelter['收容所編號'])}`);
  await semantics(page);
  await tap(page, '收藏', {exact: true});
  await fillFlutter(page, '分組', '父母家');
  await fillFlutter(page, '私人備註', '先到東側入口集合');
  await tap(page, '儲存收藏');
  await expect.poll(async () => (await stored(page)).favorites?.[0]?.group).toBe('父母家');
  await tap(page, '分享', {exact: true});
  await expect(page.getByText('分享避難所', {exact: true})).toBeVisible();
  await expect(page.getByRole('img', {name: /避難所分享連結 QR Code/})).toBeVisible();
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await tap(page, '複製連結');
  const link = await page.evaluate(() => navigator.clipboard.readText());
  expect(new URL(link).searchParams.get('shelter')).toBe(shelter['收容所編號']);
  await page.reload();
  await semantics(page);
  await expect(page.getByRole('button', {name: '編輯收藏'})).toBeVisible({timeout: 15_000});
  await tap(page, '關閉詳情');
  await tap(page, '我的避難準備');
  await expect(page.getByRole('button', {name: /先到東側入口集合/})).toBeVisible();
  await page.screenshot({path: test.info().outputPath('mobile-favorites.png'), fullPage: true});
});

test('download through UI, cold offline restart and never-before-used search', async ({page, context, request}) => {
  test.setTimeout(180_000);
  const body = await sample(request, '連江縣');
  const shelter = body.data[1];
  await page.goto('/app/');
  await semantics(page);
  await tap(page, '我的避難準備');
  await page.getByRole('tab', {name: '離線資料'}).click();
  const regionResponse = page.waitForResponse((response) => new URL(response.url()).pathname === '/api/regions');
  await tap(page, '下載區域');
  await regionResponse;
  await page.getByRole('button', {name: '縣市 選擇縣市', exact: true}).press('Enter');
  await expect(page.getByRole('menu')).toBeVisible();
  await page.getByRole('menu').hover();
  await page.mouse.wheel(0, 1800);
  await page.getByRole('menuitem', {name: '連江縣', exact: true}).click();
  await tap(page, '下載', {exact: true});
  await expect.poll(async () => (await stored(page)).packages?.[0]?.coverage?.city, {timeout: 30_000}).toBe('連江縣');
  await expect(page.getByText('✓ 已備妥離線啟動資源')).toBeVisible({timeout: 120_000});
  // Remove HTTP cache: startup must come from the service worker, not luck.
  const cdp = await context.newCDPSession(page);
  await cdp.send('Network.clearBrowserCache');
  await context.setOffline(true);
  await page.close();
  const offlinePage = await context.newPage();
  await offlinePage.goto('/app/');
  await semantics(offlinePage);
  await expect(offlinePage.getByText(/離線資料範圍：連江縣/)).toBeVisible();
  await tap(offlinePage, '搜尋', {exact: true});
  const field = offlinePage.getByRole('textbox');
  await field.click();
  await field.fill(shelter['名稱']);
  const result = offlinePage.getByRole('button', {name: new RegExp(shelter['名稱'])}).last();
  await expect(result).toBeVisible({timeout: 15_000});
  await result.click();
  await expect(offlinePage.getByRole('button', {name: '收藏', exact: true})).toBeVisible();
  await offlinePage.screenshot({path: test.info().outputPath('offline-detail.png'), fullPage: true});
});

test('family plan saves independently of favorites and exports an offline card', async ({page, request}) => {
  test.setTimeout(120_000);
  const body = await sample(request);
  const first = body.data[0], second = body.data[1];
  await page.goto('/app/');
  await semantics(page);
  await page.evaluate(async (shelters) => {
    await (window as any).tesiis.writeLibrary(JSON.stringify({schemaVersion: 1, favorites: shelters.map((s: any) => ({shelter: s, savedAt: new Date().toISOString(), group: '住家', note: ''}))}));
  }, [first, second]);
  await page.reload();
  await semantics(page);
  await tap(page, '我的避難準備');
  await page.getByRole('tab', {name: '家庭計畫'}).click();
  await fillFlutter(page, '計畫名稱', '我們家的集合計畫');
  await page.getByRole('button', {name: '主要集合點 尚未設定', exact: true}).press('Enter');
  await page.getByRole('menuitem', {name: `${first['名稱']}（${first['縣市']}）`, exact: true}).click();
  await tap(page, '備用集合點 尚未設定', {exact: true});
  await page.getByRole('menuitem', {name: `${second['名稱']}（${second['縣市']}）`, exact: true}).click();
  await fillFlutter(page, '緊急聯絡人與電話', '家人 02-12345678');
  await tap(page, '儲存計畫');
  await expect.poll(async () => (await stored(page)).plan?.primary?.['收容所編號']).toBe(first['收容所編號']);
  expect((await stored(page)).plan.title).toBe('我們家的集合計畫');
  expect((await stored(page)).plan.contact).toBe('家人 02-12345678');
  const download = page.waitForEvent('download');
  await tap(page, '下載避難卡');
  const file = await download;
  expect(file.suggestedFilename()).toBe('TESIIS-family-card.html');
  const stream = await file.createReadStream();
  const chunks: Buffer[] = [];
  for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
  const html = Buffer.concat(chunks).toString('utf8');
  const cardText = html.replace(/<svg[\s\S]*?<\/svg>/g, '[QR]');
  expect(cardText).toContain('我們家的集合計畫');
  expect(html.includes('<svg')).toBe(true);
  expect(cardText).toContain(first['名稱']);
  await page.reload();
  await semantics(page);
  await tap(page, '我的避難準備');
  await page.getByRole('tab', {name: '家庭計畫'}).click();
  await page.getByRole('textbox', {name: '計畫名稱'}).click();
  await expect(page.getByRole('textbox', {name: '計畫名稱'})).toHaveValue('我們家的集合計畫');
});

test('manual origin and hazard/space filters reach both nearby query surfaces', async ({page, request}) => {
  test.setTimeout(120_000);
  const body = await sample(request);
  await page.goto(`/app/?shelter=${body.data[0]['收容所編號']}`);
  await semantics(page);
  await tap(page, '關閉詳情');
  await tap(page, '指定查詢地點');
  const nearby = page.waitForRequest((req) => new URL(req.url()).pathname === '/api/shelters/nearby');
  await page.mouse.click(700, 400);
  const origin = new URL((await nearby).url());
  expect(Number(origin.searchParams.get('radius'))).toBe(3000);
  const flood = page.waitForRequest((req) => req.url().includes('/shelters/nearby') && new URL(req.url()).searchParams.get('disasters') === 'flood');
  await tap(page, '水災', {exact: true});
  await flood;
  const indoor = page.waitForRequest((req) => req.url().includes('/shelters/nearby') && new URL(req.url()).searchParams.get('spaces') === 'indoor');
  await tap(page, '室內', {exact: true});
  const filtered = new URL((await indoor).url());
  expect(filtered.searchParams.get('disasters')).toBe('flood');
  expect(filtered.searchParams.get('lat')).toBe(origin.searchParams.get('lat'));
  expect(filtered.searchParams.get('lng')).toBe(origin.searchParams.get('lng'));
});

test('large text, dark theme and list mode persist and query downloaded data', async ({page, request}) => {
  test.setTimeout(120_000);
  const body = await sample(request);
  await page.setViewportSize({width: 390, height: 844});
  await page.goto('/app/');
  await semantics(page);
  await page.evaluate(async (pack) => {
    await (window as any).tesiis.writeLibrary(JSON.stringify({schemaVersion: 1, offlineMode: true, packages: [{...pack, downloadedAt: new Date().toISOString()}]}));
  }, body);
  await page.reload();
  await semantics(page);
  await tap(page, '我的避難準備');
  await page.getByRole('tab', {name: '設定'}).click();
  await page.getByRole('switch', {name: '大字模式', exact: true}).click();
  await page.getByRole('switch', {name: /^精簡清單模式/}).click();
  await page.getByRole('button', {name: '主題 淺色'}).press('Enter');
  await page.getByRole('menuitem', {name: '深色', exact: true}).click();
  await expect.poll(async () => (await stored(page)).theme).toBe('dark');
  expect((await stored(page)).largeText).toBe(true);
  expect((await stored(page)).listMode).toBe(true);
  await page.reload();
  await semantics(page);
  // Wait for the store to load and the map page to mount before touching the
  // toolbar; the accessibility button attaches while the app is still on its
  // loading spinner.
  await expect(page.getByRole('button', {name: '我的避難準備'})).toBeVisible({timeout: 15_000});
  await expect(page.getByRole('button', {name: '切換地圖模式'})).toBeVisible({timeout: 15_000});
  const field = page.getByRole('textbox', {name: '搜尋地點、避難所...'});
  await field.click();
  await field.fill(body.data[0]['名稱']);
  await expect(page.getByRole('button', {name: new RegExp(body.data[0]['名稱'])}).last()).toBeVisible();
  await tap(page, '清除搜尋');
  await expect(page.getByRole('textbox', {name: '搜尋地點、避難所...'})).toBeVisible();
  await page.screenshot({path: test.info().outputPath('large-dark-list.png')});
});

test('a stale browser tab cannot overwrite a newer family plan', async ({page, context}) => {
  test.setTimeout(90_000);
  await page.goto('/app/');
  await semantics(page);
  await page.evaluate(async () => (window as any).tesiis.writeLibrary(JSON.stringify({schemaVersion: 1, _revision: 1, plan: {title: '原計畫'}})));
  const second = await context.newPage();
  await second.goto('/app/');
  await semantics(second);
  const stale = await stored(second);
  await page.evaluate(async () => (window as any).tesiis.writeLibrary(JSON.stringify({schemaVersion: 1, _revision: 2, plan: {title: '最新計畫'}})));
  const rejected = await second.evaluate(async (state) => {
    try { await (window as any).tesiis.writeLibrary(JSON.stringify({...state, _revision: state._revision + 1, plan: {title: '舊分頁修改'}})); return false; }
    catch (_) { return true; }
  }, stale);
  expect(rejected).toBe(true);
  expect((await stored(page)).plan.title).toBe('最新計畫');
});
