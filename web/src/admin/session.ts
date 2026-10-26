import { defineStore } from 'pinia';
import { ref } from 'vue';
import { api, cancelRequests, errorMessage } from './api';

interface User { id: string; name: string; role: string; status: string; must_change_password: boolean }
export const useSession = defineStore('management-session', () => {
  const user = ref<User | null>(null), ready = ref(false), error = ref('');
  function clear(message = '') { cancelRequests(); sessionStorage.removeItem('workpanel-token'); user.value = null; error.value = message; }
  function accept(value: User) {
    if (value.role !== 'ADMIN' || value.status !== 'ACTIVE') { clear('此工作台仅供已启用的管理员使用'); return; }
    user.value = value;
  }
  async function restore() {
    try { if (sessionStorage.getItem('workpanel-token')) accept(await api<User>('/auth/me')); }
    catch (e) { clear(errorMessage(e)); }
    finally { ready.value = true; }
  }
  async function login(account: string, password: string) {
    error.value = '';
    const result = await api<{ token: string; user: User }>('/auth/login', { method: 'POST', body: { account, password } });
    sessionStorage.setItem('workpanel-token', result.token); accept(result.user);
  }
  async function logout() { try { await api('/auth/logout', { method: 'POST' }); } finally { clear(); } }
  window.addEventListener('management-access-lost', event => clear((event as CustomEvent<string>).detail));
  return { user, ready, error, clear, restore, login, logout };
});
