import { defineConfig } from 'vitepress'

// Built into apps/docs/dist, which pages.yml deploys
export default defineConfig({
  title: 'demo-docs',
  description: 'The docs of demo-docs',
  base: '/demo-docs/',
  outDir: 'dist',
})
