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

  // Close the search results panel so the map (with markers) is visible,
  // keeping the filtered result set as markers.
  await page.keyboard.press('Escape').catch(() => {});
  await page.waitForTimeout(500);

  // Zoom out a couple steps so nearby markers overlap into clusters.
  const mapCenter = { x: 640, y: 500 };
  for (let i = 0; i < 3; i++) {
    await page.mouse.move(mapCenter.x, mapCenter.y);
    await page.mouse.wheel(0, 200);
    await page.waitForTimeout(500);
  }
  await page.waitForTimeout(2500);

  await page.screenshot({
    path: 'C:\\Users\\kuora\\AppData\\Local\\Temp\\claude\\c--Users-kuora-repo-2025Taipei-codefest-team30\\868e5fc4-0e27-4d2d-9176-54a03998a009\\scratchpad\\cluster_screenshot2.png',
  });
  console.log('screenshot saved');
  await browser.close();
})();
