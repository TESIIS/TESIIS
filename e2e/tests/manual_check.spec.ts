import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';

const SHOT_DIR =
  'C:/Users/kuora/AppData/Local/Temp/claude/c--Users-kuora-repo-2025Taipei-codefest-team30/dbca95e2-c607-424d-82fe-88c8310be6cc/scratchpad';

async function enableSemantics(page: Page) {
  const enableButton = page.getByRole('button', { name: 'Enable accessibility' });
  await enableButton.waitFor({ state: 'attached', timeout: 30_000 });
  await enableButton.dispatchEvent('click');
}

test.use({
  viewport: { width: 1440, height: 900 },
  permissions: ['geolocation'],
  geolocation: { latitude: 25.0478, longitude: 121.517 },
});

test('nationwide stats card shows in the top-right corner on desktop', async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto('/');
  await enableSemantics(page);

  await expect(page.getByText('全國資料統計')).toBeVisible({ timeout: 20_000 });
  await expect(page.getByText('避難所總數')).toBeVisible();
  await expect(page.getByText('涵蓋縣市')).toBeVisible();
  await expect(page.getByText('座標完整度')).toBeVisible();
  await page.waitForTimeout(500);
  await page.screenshot({ path: `${SHOT_DIR}/opt_3_stats_card.png` });
});

test('stats card hides when the shelter detail sidebar takes that corner', async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto('/');
  await enableSemantics(page);
  await expect(page.getByText('全國資料統計')).toBeVisible({ timeout: 20_000 });

  const detailBtn = page.getByRole('button', { name: '詳情' });
  await detailBtn.waitFor({ state: 'visible', timeout: 20_000 });
  await detailBtn.click();
  await page.waitForTimeout(500);
  await page.screenshot({ path: `${SHOT_DIR}/opt_3_stats_card_detail_open.png` });
  await expect(page.getByText('全國資料統計')).toHaveCount(0);
});
