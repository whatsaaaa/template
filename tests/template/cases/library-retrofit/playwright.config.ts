import { defineConfig, devices } from '@playwright/test'

/**
 * Browser tests of the project's own pages, such as its playgrounds, which "pnpm test:browser"
 * builds first. A webServer here serves them, and use.baseURL points at it.
 */
export default defineConfig({
  testDir: 'tests/browser',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    ...devices['Desktop Chrome'],
    colorScheme: 'dark',
  },
})
