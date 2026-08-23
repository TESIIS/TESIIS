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

  // Zoom out a few steps to force dense clustering (default view is already
  // nationwide-zoom, but let's zoom out further via the map's scroll wheel
  // equivalent — flutter_map listens to wheel events).
  const mapCenter = { x: 640, y: 450 };
  for (let i = 0; i < 6; i++) {
    await page.mouse.move(mapCenter.x, mapCenter.y);
    await page.mouse.wheel(0, 200); // scroll down = zoom out on most map libs
    await page.waitForTimeout(400);
  }
  await page.waitForTimeout(2500);

  await page.screenshot({
    path: 'C:\\Users\\kuora\\AppData\\Local\\Temp\\claude\\c--Users-kuora-repo-2025Taipei-codefest-team30\\868e5fc4-0e27-4d2d-9176-54a03998a009\\scratchpad\\cluster_screenshot.png',
  });
  console.log('screenshot saved');
  await browser.close();
})();
