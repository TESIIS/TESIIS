import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';

// Flutter Web (CanvasKit/Skwasm) paints everything to a single <canvas> —
// there is no queryable DOM for individual widgets until Flutter's
// accessibility/semantics tree is turned on. It injects an
// `Enable accessibility` button for exactly this; clicking it once per page
// makes `getByText`/`getByRole` locators work against anything the app gives
// a Text or Semantics/tooltip label.
async function enableSemantics(page: Page, timeout = 30_000) {
  const enableButton = page.getByRole('button', { name: 'Enable accessibility' });
  await enableButton.waitFor({ state: 'attached', timeout });
  // The placeholder is deliberately positioned off-screen until interacted
  // with, so a normal `.click()` fails Playwright's "in viewport"
  // actionability check even with `force`. Dispatching the event directly
  // skips that check, which is exactly what this element expects.
  await enableButton.dispatchEvent('click');
}

/// Types [query] into the search field and waits until the app actually
/// fires the search request.
///
/// Flutter Web can drop a programmatic `fill()` that lands while the search
/// field is still animating in: the input event never reaches the framework,
/// the field stays empty, and no request is ever sent. So wait for the field
/// to exist, focus it first, and verify the request really went out —
/// retyping once if it did not.
async function searchShelters(page: Page, query: string) {
  const field = page.getByRole('textbox');
  await field.waitFor({ state: 'visible', timeout: 10_000 });
  await field.click({ timeout: 10_000 });

  const requestFired = () =>
    page
      .waitForRequest((request) => request.url().includes('/shelters?q='), {
        timeout: 3_000,
      })
      .then(() => true)
      .catch(() => false);

  let fired = requestFired();
  await field.fill(query, { timeout: 10_000 });
  if (!(await fired)) {
    await field.fill('', { timeout: 10_000 });
    fired = requestFired();
    await field.fill(query, { timeout: 10_000 });
    await fired;
  }
}

/// Asks the API for one real shelter instead of hardcoding a name.
///
/// A fixture that names one specific facility breaks every time upstream
/// renames or re-abbreviates it — which already happened once going
/// nationwide: Taipei OpenData wrote out "臺北市立螢橋國民中學" in full, but
/// the nationwide NFA dataset that replaced it as the primary source
/// abbreviates the same facility to "螢橋國中". Querying live sidesteps
/// that entirely.
///
/// Picks a shelter with a coordinate on record. Every row in the nationwide
/// dataset has one today — the NFA point file ships its own WGS84 columns and
/// rows failing the county bounds check are dropped — so this is a guard
/// against that changing, not a workaround for a known gap.
async function fetchSampleShelter(
  request: import('@playwright/test').APIRequestContext,
  baseURL: string,
  city: string,
) {
  const res = await request.get(
    `${baseURL}/api/shelters?city=${encodeURIComponent(city)}&limit=50`,
  );
  const body = await res.json();
  const shelters = body.data as Array<Record<string, unknown>>;
  const shelter =
    shelters.find((s) => s['座標x'] != null && s['座標y'] != null) ?? shelters[0];
  return { name: shelter['名稱'] as string, city: shelter['縣市'] as string };
}

test.describe('shelter web smoke', () => {
  test('homepage loads and the map renders', async ({ page }) => {
    // This is usually the first test to touch a fresh browser profile, so it
    // pays the one-time cost of downloading and compiling CanvasKit/WASM with
    // no HTTP cache yet warmed by an earlier test — the default 30s budget
    // is tight for that even before any assertion runs.
    test.setTimeout(60_000);

    await page.goto('/');
    await expect(page).toHaveTitle('臺灣避難收容所資訊整合系統');
    await enableSemantics(page);

    await expect(page.getByText('TESIIS 臺灣避難收容所地圖')).toBeVisible({
      timeout: 15_000,
    });
  });

  test('search returns results for a real shelter', async ({ page, request, baseURL }) => {
    test.setTimeout(60_000);

    const sample = await fetchSampleShelter(request, baseURL!, '臺北市');

    await page.goto('/');
    await enableSemantics(page);

    await page.getByRole('button', { name: '搜尋' }).click();
    // A short, unambiguous fragment of the real name — full names sometimes
    // carry punctuation/spacing quirks that don't round-trip through typing.
    const fragment = sample.name.slice(0, Math.min(4, sample.name.length));
    await searchShelters(page, fragment);

    await expect(page.getByText(fragment, { exact: false }).first()).toBeVisible({
      timeout: 15_000,
    });
  });

  test('opening a shelter shows navigation without geolocation', async ({ page, request, baseURL }) => {
    test.setTimeout(60_000);

    const sample = await fetchSampleShelter(request, baseURL!, '高雄市');

    await page.goto('/');
    await enableSemantics(page);

    await page.getByRole('button', { name: '搜尋' }).click();
    const fragment = sample.name.slice(0, Math.min(4, sample.name.length));
    await searchShelters(page, fragment);
    await page.getByText(fragment, { exact: false }).first().click();

    await expect(page.getByText('開始導航', { exact: false })).toBeVisible({
      timeout: 15_000,
    });
  });

  test('台貓署名會開啟個人網站', async ({ page }) => {
    test.setTimeout(60_000);

    await page.goto('/');
    await enableSemantics(page);
    await page.getByRole('button', { name: '關於我們' }).click();
    const twcatLink = page.getByRole('button', { name: /^台貓/ });
    await expect(twcatLink).toBeVisible();

    const popupPromise = page.waitForEvent('popup');
    await twcatLink.click();
    const popup = await popupPromise;
    await expect(popup).toHaveURL(/^https:\/\/twcat0503\.org\/?/);
    await popup.close();
  });

  test('the county picker surfaces nationwide coverage', async ({ request, baseURL }) => {
    const res = await request.get(`${baseURL}/api/regions`);
    const body = await res.json();
    expect(body.regions).toHaveLength(22);
    // Every county should have at least one shelter — a regression here
    // would mean the nationwide snapshot silently lost coverage for one.
    for (const region of body.regions) {
      expect(region.count, `${region.city} has zero shelters`).toBeGreaterThan(0);
    }
  });

  test('search shows the empty state for a query with no matches', async ({ page }) => {
    test.setTimeout(60_000);

    await page.goto('/');
    await enableSemantics(page);

    await page.getByRole('button', { name: '搜尋' }).click();
    await searchShelters(page, 'zzz這個地名不存在9999');

    await expect(page.getByText('找不到相似的結果')).toBeVisible({
      timeout: 15_000,
    });
  });

  test('the app still loads on a throttled connection', async ({ page, context }) => {
    // The Chinese search-bar text this test waits for can only paint once
    // CanvasKit *and* the bundled NotoSansTC font (~12MB, confirmed via a
    // network trace — canvaskit does its own text shaping with no
    // browser-native font fallback) are both in. nginx.conf now gives .ttf
    // an explicit MIME type and gzips it (it previously had neither — TTF
    // has no MIME type in nginx by default, so it wasn't on the gzip
    // allowlist and shipped at full size everywhere, this test included).
    // The pre-fix timeout here was measured at ~60-70s for that one file on
    // a 6Mbps/150ms throttle; kept as-is since the post-fix number hasn't
    // been re-measured, but there should be real margin to spare now.
    test.setTimeout(150_000);

    // Network.emulateNetworkConditions is Chromium-only, which matches this
    // suite's single 'chromium' project in playwright.config.ts.
    const cdp = await context.newCDPSession(page);
    await cdp.send('Network.enable');
    await cdp.send('Network.emulateNetworkConditions', {
      offline: false,
      downloadThroughput: (6 * 1024 * 1024) / 8, // ~6Mbps
      uploadThroughput: (6 * 1024 * 1024) / 8,
      latency: 150,
    });

    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('status')).toContainText('正在載入');
    await enableSemantics(page);

    await expect(page.getByText('TESIIS 臺灣避難收容所地圖')).toBeVisible({
      timeout: 120_000,
    });
  });
});
