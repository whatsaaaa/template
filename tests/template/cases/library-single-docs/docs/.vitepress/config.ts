import { defineConfig } from 'vitepress'

// Built into docs/.vitepress/dist, which pages.yml deploys
export default defineConfig({
  title: 'demo-single-docs',
  description: 'The docs of demo-single-docs',
  // GitHub Pages serves the docs from https://whatsaaaa.github.io/demo-single-docs/
  base: '/demo-single-docs/',
})
