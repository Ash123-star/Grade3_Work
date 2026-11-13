import { createApp } from 'vue';
import AdminConsole from './AdminConsole.vue';
import './admin.css';
import { initializeProductAssets } from './assets';
void initializeProductAssets();
createApp(AdminConsole).mount('#app');
