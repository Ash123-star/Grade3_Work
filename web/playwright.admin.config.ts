import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests/admin', timeout: 30000,
  use: { baseURL: 'http://127.0.0.1:5177', launchOptions: { executablePath: process.env.CHROME_PATH || (process.platform === 'win32' ? 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe' : undefined) } },
  webServer: { command: 'npm run dev -- --port 5177 --strictPort', url: 'http://127.0.0.1:5177', reuseExistingServer: !process.env.CI },
  projects: [{ name: 'desktop', use: { viewport: { width: 1440, height: 1000 } } }, { name: 'mobile', use: { viewport: { width: 390, height: 844 } } }],
  reporter: 'list',
});
