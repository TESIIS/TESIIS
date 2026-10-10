import { defineConfig, devices } from '@playwright/test';

// Runs against the real docker-compose stack (Nginx + API + Flutter Web),
// matching the README's documented `docker compose up --build` run path —
// not a mocked or standalone Flutter build.
export default defineConfig({
  webServer: process.env.LOCAL_STACK === '1' ? {
    command: 'node serve-local.mjs',
    url: 'http://127.0.0.1:18088/healthz',
    timeout: 120_000,
    reuseExistingServer: false,
  } : undefined,
  testDir: './tests',
  fullyParallel: true,
  // Each spec can pull a ~53 MB Flutter web build (CanvasKit, main.dart.js and
  // the bundled CJK font). Running many at once saturates the origin and starves
  // app startup, which shows up as spurious test timeouts rather than real
  // product failures, so cap concurrency well below the CPU count.
  workers: process.env.CI ? 2 : 2,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: process.env.BASE_URL ?? (process.env.LOCAL_STACK === '1' ? 'http://127.0.0.1:18088' : 'http://localhost:8080'),
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
