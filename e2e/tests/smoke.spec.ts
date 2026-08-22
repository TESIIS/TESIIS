import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';

// Flutter Web (CanvasKit/Skwasm) paints everything to a single <canvas> —
// there is no queryable DOM for individual widgets until Flutter's
// accessibility/semantics tree is turned on. It injects an
// `Enable accessibility` button for exactly this; clicking it once per page
// makes `getByText`/`getByRole` locators work against anything the app gives
// a Text or Semantics/tooltip label.
async function enableSemantics(page: Page) {
  const enableButton = page.getByRole('button', { name: 'Enable accessibility' });
  await enableButton.waitFor({ state: 'attached', timeout: 30_000 });
  // The placeholder is deliberately positioned off-screen until interacted
  // with, so a normal `.click()` fails Playwright's "in viewport"
  // actionability check even with `force`. Dispatching the event directly
  // skips that check, which is exactly what this element expects.
  await enableButton.dispatchEvent('click');
}

// The navigate button only renders once the app has a known position
// (`ShelterDetailSheet`'s `canNavigate` check) — grant geolocation so the
// suite exercises the same path a real user with location enabled would.
test.use({
  permissions: ['geolocation'],
  geolocation: { latitude: 25.0478, longitude: 121.517 },
});

test.describe('shelter web smoke', () => {
  test('homepage loads and the map renders', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveTitle('臺北市避難設施資訊整合系統');
    await enableSemantics(page);

    await expect(page.getByText('臺北避難設施地圖')).toBeVisible();
  });

  test('search returns results for a known shelter', async ({ page }) => {
    await page.goto('/');
    await enableSemantics(page);

    await page.getByRole('button', { name: '搜尋' }).click();
    await page.getByRole('textbox').fill('螢橋');

    await expect(page.getByText('螢橋國民中學', { exact: false }).first()).toBeVisible({
      timeout: 15_000,
    });
  });

  test('opening a shelter shows the navigation button', async ({ page }) => {
    await page.goto('/');
    await enableSemantics(page);

    await page.getByRole('button', { name: '搜尋' }).click();
    await page.getByRole('textbox').fill('螢橋');
    await page.getByText('螢橋國民中學', { exact: false }).first().click();

    await expect(page.getByText('開始導航', { exact: false })).toBeVisible({
      timeout: 15_000,
    });
  });
});
