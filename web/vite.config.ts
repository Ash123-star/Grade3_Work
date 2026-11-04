import { defineConfig, loadEnv } from 'vite';
import vue from '@vitejs/plugin-vue';
export default defineConfig(({ mode }) => ({
  plugins: [vue()],
  server: {
    proxy: {
      '/api': {
        target: loadEnv(mode, '.', 'VITE_').VITE_API_TARGET || 'https://www.panduolawork.asia',
        changeOrigin: true,
      },
    },
  },
}));
