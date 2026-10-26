import { createRouter, createWebHistory } from 'vue-router';
export const router = createRouter({ history: createWebHistory(), routes: [
  { path: '/', redirect: '/admin/accounts' },
  { path: '/admin/accounts', component: () => import('./AccountsView.vue') },
  { path: '/admin/company-items', component: () => import('./CompanyItemsView.vue') },
  { path: '/legacy', component: () => import('../App.vue') },
  { path: '/:pathMatch(.*)*', redirect: '/admin/accounts' },
] });
