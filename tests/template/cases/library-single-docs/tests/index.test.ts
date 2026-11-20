import { expect, test } from 'vitest'
import { slug } from '../src/index.ts'

test('slug joins the words of a title with dashes', () => {
  expect(slug(' Getting Started ')).toBe('getting-started')
})
