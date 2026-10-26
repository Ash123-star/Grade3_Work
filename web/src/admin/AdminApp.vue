<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { ElButton, ElForm, ElFormItem, ElInput, ElAlert, ElIcon, ElDropdown, ElDropdownMenu, ElDropdownItem } from 'element-plus';
import { User, OfficeBuilding, ArrowRight, SwitchButton, Lock, UserFilled, ArrowDown, CircleCheck } from '@element-plus/icons-vue';
import { useSession } from './session';
import { api, errorMessage } from './api';
const session = useSession(), route = useRoute();
const account = ref(''), password = ref(''), newPassword = ref(''), oldPassword = ref(''), busy = ref(false), localError = ref('');
const isAccounts = computed(() => route.path !== '/admin/company-items');
const pageName = computed(() => isAccounts.value ? '账号管理' : '公司十大重要事项');
async function login() {
  if (!account.value.trim() || !password.value) { localError.value = '请输入账号和密码'; return; }
  busy.value = true; localError.value = '';
  try { await session.login(account.value.trim(), password.value); oldPassword.value = session.user?.must_change_password ? password.value : ''; password.value = ''; }
  catch (e) { localError.value = errorMessage(e); }
  finally { busy.value = false; }
}
async function changePassword() {
  busy.value = true; localError.value = '';
  try { await api('/auth/password', { method: 'POST', body: { oldPassword: oldPassword.value, newPassword: newPassword.value } }); session.clear('密码已更新，请重新登录'); oldPassword.value = ''; newPassword.value = ''; }
  catch (e) { localError.value = errorMessage(e); }
  finally { busy.value = false; }
}
onMounted(() => { if (route.path !== '/legacy') void session.restore(); });
</script>

<template>
  <RouterView v-if="route.path === '/legacy'" />
  <div v-else class="admin-app">
    <div v-if="!session.ready" class="initial-loading" role="status">正在连接管理工作台…</div>
    <div v-else-if="!session.user || session.user.must_change_password" class="login-screen">
      <div class="login-brand"><div class="brand-mark"><ElIcon><OfficeBuilding /></ElIcon></div><span>潘多拉<span class="brand-sub">企业管理工作台</span></span></div>
      <section class="login-panel">
        <div class="login-symbol"><ElIcon><Lock /></ElIcon></div>
        <p class="eyebrow">PANDORA / ADMIN</p><h1>{{ session.user ? '设置新密码' : '欢迎回来' }}</h1><p class="muted">{{ session.user ? '首次使用，请先完成密码设置' : '登录管理员账号，开始管理公司信息' }}</p>
        <ElAlert v-if="localError || session.error" :title="localError || session.error" type="error" :closable="false" show-icon role="alert" />
        <ElForm v-if="!session.user" label-position="top" @submit.prevent="login">
          <ElFormItem label="账号"><ElInput v-model="account" size="large" :prefix-icon="User" autocomplete="username" placeholder="请输入管理员账号" /></ElFormItem>
          <ElFormItem label="密码"><ElInput v-model="password" size="large" :prefix-icon="Lock" type="password" autocomplete="current-password" show-password placeholder="请输入密码" /></ElFormItem>
          <ElButton type="primary" size="large" native-type="submit" :loading="busy" class="login-submit">登录工作台<ElIcon><ArrowRight /></ElIcon></ElButton>
        </ElForm>
        <ElForm v-else label-position="top" @submit.prevent="changePassword">
          <ElFormItem label="原密码"><ElInput v-model="oldPassword" type="password" autocomplete="current-password" show-password /></ElFormItem>
          <ElFormItem label="新密码"><ElInput v-model="newPassword" type="password" autocomplete="new-password" show-password placeholder="至少12个字符" /></ElFormItem>
          <ElButton type="primary" native-type="submit" :loading="busy">更新密码并重新登录</ElButton>
        </ElForm>
        <p class="login-foot"><ElIcon><CircleCheck /></ElIcon> 公司数据仅对授权管理员开放</p>
      </section><div class="login-copyright">潘多拉企业协作 · 管理工作台</div>
    </div>
    <div v-else class="admin-layout">
      <aside class="admin-sidebar">
        <div class="sidebar-brand"><div class="brand-mark"><ElIcon><OfficeBuilding /></ElIcon></div><div><strong>潘多拉</strong><small>企业管理工作台</small></div></div>
        <div class="sidebar-section-label">工作空间</div>
        <nav aria-label="管理导航">
          <RouterLink to="/admin/accounts" aria-label="账号管理" :class="{ active: isAccounts }"><ElIcon><User /></ElIcon><span>账号管理</span><span class="nav-dot" /></RouterLink>
          <RouterLink to="/admin/company-items" aria-label="公司十大重要事项" :class="{ active: !isAccounts }"><ElIcon><OfficeBuilding /></ElIcon><span>公司十大重要事项</span><span class="nav-dot" /></RouterLink>
        </nav>
        <div class="sidebar-bottom"><span class="online-dot" />管理服务已连接<small>公司信息 · 统一维护</small></div>
      </aside>
      <div class="admin-workspace">
        <header class="admin-topbar"><div class="breadcrumb">管理工作台<ElIcon><ArrowRight /></ElIcon><strong>{{ pageName }}</strong></div><ElDropdown @command="session.logout"><button class="profile-button"><span class="user-avatar"><ElIcon><UserFilled /></ElIcon></span><span>{{ session.user.name }}<small>管理员</small></span><ElIcon><ArrowDown /></ElIcon></button><template #dropdown><ElDropdownMenu><ElDropdownItem command="logout" :icon="SwitchButton">退出登录</ElDropdownItem></ElDropdownMenu></template></ElDropdown></header>
        <main class="admin-main"><RouterView :key="route.path" /></main>
        <footer class="admin-footer">潘多拉企业管理工作台<span>安全访问 · 修改留痕</span></footer>
      </div>
    </div>
  </div>
</template>
