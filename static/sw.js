/* Minimal service worker: enables PWA install + share target.
   Network-first so the app always shows fresh data; offline fallback
   for previously visited pages via a small runtime cache. */
const CACHE = 'recipemanager-v2';
const MAX_ENTRIES = 300;

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  // Only handle same-origin GETs; never cache POSTs or admin/auth pages
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  const isUpload = url.pathname.startsWith('/admin/uploads/');
  if ((url.pathname.startsWith('/admin') && !isUpload) || url.pathname.startsWith('/login')
      || url.pathname.startsWith('/logout') || url.pathname.startsWith('/profile')
      || url.pathname.includes('reset-password')) return;

  // Uploads have random, never-reused filenames: serve from cache first, fill it on a miss
  if (isUpload) {
    event.respondWith(
      caches.match(req).then((hit) => hit || fetch(req).then((resp) => {
        if (resp.ok) {
          const clone = resp.clone();
          caches.open(CACHE).then(async (c) => {
            await c.put(req, clone);
            // Keep the cache bounded: drop the oldest entries beyond the limit
            const keys = await c.keys();
            if (keys.length > MAX_ENTRIES) await Promise.all(keys.slice(0, keys.length - MAX_ENTRIES).map((k) => c.delete(k)));
          });
        }
        return resp;
      }))
    );
    return;
  }

  event.respondWith(
    fetch(req)
      .then((resp) => {
        if (resp.ok && (url.pathname.startsWith('/static/') || url.pathname.startsWith('/admin/uploads/'))) {
          const clone = resp.clone();
          caches.open(CACHE).then((c) => c.put(req, clone));
        }
        return resp;
      })
      .catch(() => caches.match(req))
  );
});
