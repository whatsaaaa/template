import { expect, test } from '@playwright/test'

test('the playground shows its heading', async ({ page }) => {
  await page.goto(new URL('../../playground/index.html', import.meta.url).href)
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('The demo-retrofit playground')
})
