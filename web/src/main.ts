import { createApp } from 'vue';
import { initializeProductAssets } from './assets';
void initializeProductAssets();

const path = window.location.pathname;
if (path === '/commerce' || path === '/commerce/') {
  void Promise.all([import('./commerce/CommerceApp.vue'), import('pinia')]).then(([{ default: CommerceApp }, { createPinia }]) => {
    createApp(CommerceApp).use(createPinia()).mount('#app');
  });
} else if (path.startsWith('/admin/') || path === '/legacy') {
  void import('./management');
} else {
  void Promise.all([import('./AdminConsole.vue'), import('./admin.css')]).then(([{ default: AdminConsole }]) => {
    createApp(AdminConsole).mount('#app');
  });
}
