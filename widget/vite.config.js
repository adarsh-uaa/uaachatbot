import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],            // *.ce.vue files compile to custom elements (styles live in the shadow DOM)
  define: { 'process.env.NODE_ENV': '"production"' },
  build: {
    lib: { entry: 'src/main.js', name: 'UaaChat', formats: ['iife'], fileName: () => 'uaa-widget.js' },
    minify: true
  }
})
