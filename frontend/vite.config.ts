import { defineConfig } from 'vitest/config';
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  plugins: [svelte()],
  server: {
    port: 5173,
    strictPort: false
  },
  build: {
    target: 'es2022'
  },
  test: {
    environment: 'node'
  }
});
