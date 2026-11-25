<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { api, errorMessage } from '../admin/api';
import { useSession } from '../admin/session';
import CommerceView from './CommerceView.vue';
import './commerce.css';

const session = useSession();
const account = ref('');
const password = ref('');
const oldPassword = ref('');
const newPassword = ref('');
const busy = ref(false);
const error = ref('');
const notice = ref('');

async function run(action: () => Promise<void>) {
  if (busy.value) return;
  error.value = '';
  notice.value = '';
  busy.value = true;
  try {
    await action();
  } catch (failure) {
    error.value = errorMessage(failure);
  } finally {
    busy.value = false;
  }
}

function login() {
  void run(async () => {
    await session.login(account.value.trim(), password.value);
    password.value = '';
  });
}

function changePassword() {
  void run(async () => {
    await api('/auth/password', { method: 'POST', body: { oldPassword: oldPassword.value, newPassword: newPassword.value } });
    oldPassword.value = '';
    newPassword.value = '';
    session.clear();
    notice.value = '密码已更新，请重新登录';
  });
}

onMounted(() => void session.restore());
</script>

<template>
  <header class="commerce-header">
    <div class="commerce-container commerce-topbar">
      <a href="/commerce" class="commerce-brand">潘多拉<span>商城经营</span></a>
      <div v-if="session.user" class="commerce-user">
        <span>{{ session.user.name }}</span>
        <button type="button" :disabled="busy" @click="run(session.logout)">退出登录</button>
      </div>
    </div>
  </header>
  <main class="commerce-container commerce-main">
    <p v-if="!session.ready" role="status">正在验证会话…</p>
    <template v-else-if="!session.user || session.user.must_change_password">
      <section class="commerce-card commerce-login">
        <h1>{{ session.user ? '修改初始密码' : '登录商城经营' }}</h1>
        <p v-if="error || session.error" class="commerce-error" role="alert">{{ error || session.error }}</p>
        <p v-if="notice" role="status">{{ notice }}</p>
        <form v-if="!session.user" @submit.prevent="login">
          <label>账号<input v-model="account" autocomplete="username" required></label>
          <label>密码<input v-model="password" type="password" autocomplete="current-password" required></label>
          <button class="commerce-primary" :disabled="busy">{{ busy ? '登录中…' : '登录' }}</button>
        </form>
        <form v-else @submit.prevent="changePassword">
          <label>初始密码<input v-model="oldPassword" type="password" autocomplete="current-password" required></label>
          <label>新密码<input v-model="newPassword" type="password" autocomplete="new-password" minlength="12" required></label>
          <button class="commerce-primary" :disabled="busy">修改并重新登录</button>
        </form>
      </section>
    </template>
    <CommerceView v-else :key="session.user.id" @access-lost="session.clear" />
  </main>
</template>
