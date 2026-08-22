import { defineConfig, devices } from '@playwright/test';

// Runs against the real docker-compose stack (Nginx + API + Flutter Web),
// matching the README's documented `docker compose up --build` run path —
// not a mocked or standalone Flutter build.
export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: process.env.BASE_URL ?? 'http://localhost:8080',
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
