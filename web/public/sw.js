/**
 * MeishiVault のサービスワーカー(オフライン対応の最小実装)。
 *
 * - ナビゲーション(HTML)= network-first → オフライン時はキャッシュした index を返す。
 * - その他の同一オリジン GET(JS/WASM/OCR 資産/画像 API 応答)= stale-while-revalidate。
 * プライバシー方針どおり、外部オリジンへは一切介入しない(Drive API 等は素通し)。
 */
const CACHE = 'meishivault-v1';

self.addEventListener('install', () => { self.skipWaiting(); });

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // 旧バージョンのキャッシュを掃除する。
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // 外部(Drive/GIS 等)は介入しない

  if (req.mode === 'navigate') {
    event.respondWith(networkFirst(req));
    return;
  }
  event.respondWith(staleWhileRevalidate(req));
});

async function networkFirst(req) {
  const cache = await caches.open(CACHE);
  try {
    const res = await fetch(req);
    if (res.ok) cache.put(req, res.clone());
    return res;
  } catch (err) {
    const scope = self.registration.scope; // base path 配下にデプロイされてもここから解決する
    const cached = (await cache.match(req)) || (await cache.match(`${scope}index.html`)) || (await cache.match(scope));
    if (cached) return cached;
    throw err;
  }
}

async function staleWhileRevalidate(req) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(req);
  const network = fetch(req).then((res) => {
    if (res.ok) cache.put(req, res.clone());
    return res;
  }).catch(() => cached);
  return cached || network;
}
