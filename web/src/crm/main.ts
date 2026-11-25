import { createApp } from 'vue';
import { createRouter, createWebHistory } from 'vue-router';
import CrmWorkspace from './CrmWorkspace.vue';
import './crm.css';

// Lightweight route records; the workspace owns the view and request lifecycle.
const routeView = { render: () => null };
const router = createRouter({ history: createWebHistory(), routes: [
  { path: '/crm', name: 'crm-list', component: routeView },
  { path: '/crm/customers/:customerId', name: 'crm-customer', component: routeView },
  { path: '/crm/customers/:customerId/records/:kind/:recordId', name: 'crm-record', component: routeView },
  { path: '/crm/:unmatched(.*)*', name: 'crm-missing', component: routeView },
] });
if (import.meta.env.VITE_CRM_ENABLED !== 'true') {
  document.title = '客户工作台 · 潘多拉';
  const main = document.createElement('main');
  main.className = 'crm crm-off';
  const heading = document.createElement('h1');
  heading.textContent = '客户工作台尚未开放';
  const link = document.createElement('a');
  link.href = '/'; link.textContent = '返回管理员后台入口';
  main.append(heading, link);
  document.querySelector('#app')?.replaceChildren(main);
} else {
  createApp(CrmWorkspace).use(router).mount('#app');
}
