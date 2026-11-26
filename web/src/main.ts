import { createApp } from 'vue';
import { initializeProductAssets } from './assets';
void initializeProductAssets();

const { pathname } = window.location;
if (pathname === '/crm' || pathname.startsWith('/crm/')) {
  void import('./crm/main');
} else if (pathname === '/hr' || pathname.startsWith('/hr/')) {
  void Promise.all([import('./HrConsole.vue'), import('./admin.css')]).then(([{ default: HrConsole }]) => {
    createApp(HrConsole).mount('#app');
  });
} else if (pathname.startsWith('/admin/') || pathname === '/legacy') {
  void import('./management');
} else {
  void Promise.all([import('./AdminConsole.vue'), import('./admin.css')]).then(([{ default: AdminConsole }]) => {
    createApp(AdminConsole).mount('#app');
  });
}
