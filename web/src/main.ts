import { createApp } from 'vue';
import { initializeProductAssets } from './assets';
void initializeProductAssets();

// Keep existing management and AI deep links alongside the new employee console.
if (window.location.pathname.startsWith('/admin/') || window.location.pathname === '/legacy') {
  void import('./management');
} else {
  void Promise.all([import('./AdminConsole.vue'), import('./admin.css')]).then(([{ default: AdminConsole }]) => {
    createApp(AdminConsole).mount('#app');
  });
}
