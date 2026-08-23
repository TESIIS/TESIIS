const { chromium } = require('@playwright/test');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await page.goto('http://localhost:8098/', { waitUntil: 'load' });
  await page.waitForTimeout(4000);

  const enableButton = page.getByRole('button', { name: 'Enable accessibility' });
  await enableButton.waitFor({ state: 'attached', timeout: 30000 });
  await enableButton.dispatchEvent('click');
  await page.waitForTimeout(1500);

  await page.getByRole('button', { name: '搜尋' }).click();
  await page.waitForTimeout(500);
  const field = page.getByRole('textbox');
  await field.click();
  await field.fill('國小');
  await page.waitForTimeout(3000);
  await page.keyboard.press('Escape').catch(() => {});
  await page.waitForTimeout(500);

  for (let i = 0; i < 3; i++) {
    await page.mouse.move(640, 500);
    await page.mouse.wheel(0, 200);
    await page.waitForTimeout(500);
  }
  await page.waitForTimeout(2000);

  // Crop to just the cluster area for a close-up look.
  await page.screenshot({
    path: 'C:\\Users\\kuora\\AppData\\Local\\Temp\\claude\\c--Users-kuora-repo-2025Taipei-codefest-team30\\868e5fc4-0e27-4d2d-9176-54a03998a009\\scratchpad\\cluster_closeup.png',
    clip: { x: 540, y: 380, width: 220, height: 220 },
  });
  console.log('closeup saved');
  await browser.close();
})();
