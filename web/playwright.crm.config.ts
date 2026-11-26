import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/crm', outputDir: '../output/crm-evidence/test-results', timeout: 30000,
  use: {
    baseURL: 'http://127.0.0.1:5181',
    launchOptions: { executablePath: process.env.CHROME_PATH || (process.platform === 'win32' ? 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe' : undefined) },
  },
  webServer: { command: 'npm run dev -- --port 5181 --strictPort', url: 'http://127.0.0.1:5181/crm', env: { VITE_CRM_ENABLED: 'true' }, reuseExistingServer: false },
  reporter: 'list',
});
