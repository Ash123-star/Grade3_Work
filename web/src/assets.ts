interface AssetEntry { path: string; hash: string; size: number; mime: string }
interface AssetManifest { release: string; items: AssetEntry[] }
const productCache = 'workpanel-public-assets-v1';
let manifest: AssetManifest | undefined;

function validManifest(value: unknown): value is AssetManifest {
  const input = value as AssetManifest;
  return !!input && /^[a-zA-Z0-9_-]{1,80}$/.test(input.release) && Array.isArray(input.items) && input.items.every(item =>
    typeof item.path === 'string' && /^(assets|native|web|fonts|packages)\//.test(item.path) &&
    !item.path.includes('\\') && !item.path.includes('%') && item.path.split('/').every(part => !!part && part !== '.' && part !== '..') &&
    /^[a-f0-9]{64}$/.test(item.hash) && Number.isSafeInteger(item.size) && item.size > 0 && item.size <= 100 * 1024 * 1024);
}

/** 公开产品素材专用，绝不向此缓存加入授权头或业务文件。 */
export async function productAsset(path: string): Promise<Blob> {
  const item = manifest?.items.find(item => item.path === path);
  if (!item || !manifest) throw new Error('Product asset unavailable');
  const url = `/api/assets/${manifest.release}/${path.split('/').map(encodeURIComponent).join('/')}`;
  const cache = 'caches' in window ? await caches.open(productCache) : undefined;
  async function verified(response: Response): Promise<Blob> {
    const bytes = await response.arrayBuffer();
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), byte => byte.toString(16).padStart(2, '0')).join('');
    if (bytes.byteLength !== item!.size || hash !== item!.hash) throw new Error('Product asset integrity error');
    return new Blob([bytes], { type: item!.mime });
  }
  const cached = await cache?.match(url);
  if (cached) {
    try { return await verified(cached); } catch { await cache?.delete(url); }
  }
  const response = await fetch(url, { credentials: 'omit', signal: AbortSignal.timeout(8000) });
  if (!response.ok) throw new Error('Product asset unavailable');
  const blob = await verified(response.clone());
  await cache?.put(url, response);
  return blob;
}

export async function initializeProductAssets(): Promise<void> {
  try {
    const cache = 'caches' in window ? await caches.open(productCache) : undefined;
    let response: Response | undefined;
    try {
      const fresh = await fetch('/api/assets/manifest', { credentials: 'omit', cache: 'no-cache', signal: AbortSignal.timeout(3000) });
      if (!fresh.ok) throw new Error('No published manifest');
      const value: unknown = await fresh.clone().json();
      if (!validManifest(value)) throw new Error('Invalid manifest');
      response = fresh;
      await cache?.put('/api/assets/manifest', fresh.clone());
    } catch { response = await cache?.match('/api/assets/manifest'); }
    if (!response) return;
    const value: unknown = await response.json();
    if (!validManifest(value)) return;
    manifest = value;
    const fontPath = 'assets/fonts/GenSenRoundedTW-B.ttf';
    if (manifest.items.some(item => item.path === fontPath)) {
      const font = new FontFace('TuantuanDisplay', await (await productAsset(fontPath)).arrayBuffer(), { weight: '700' });
      await font.load();
      document.fonts.add(font);
      document.documentElement.style.setProperty('--product-heading-font', 'TuantuanDisplay, system-ui');
    }
  } catch {
    // 素材故障不阻塞登录和业务；系统字体继续可用。
  }
}
