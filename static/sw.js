/* Service worker: PWA install, share target, and offline reading.
   - Static files and uploads: cached, served offline.
   - Recipe pages, cook mode, shopping list, meal plan and the shelf: network-first, saved as you
     visit them so they open in a kitchen with no signal. Cleared on sign-out (see static/js/app.js).
   Other pages (admin, login, edit forms, POSTs) are never cached. */
const STATIC = 'rm-static-v3';
const PAGES = 'rm-pages-v3';
const MAX_STATIC = 300;
const MAX_PAGES = 80;
const OFFLINE_URL = '/static/offline.html';

// Pages worth having offline (no query string, so searches are never cached)
const CACHEABLE_PAGE = /^\/(recipe\/\d+(\/cook)?\/?|shopping\/?|mealplan\/?|)$/;

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(STATIC).then((c) => c.add(OFFLINE_URL)).catch(() => {}).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== STATIC && k !== PAGES).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'clear-pages') event.waitUntil(caches.delete(PAGES));
});

async function trim(cache, max) {
  const keys = await cache.keys();
  if (keys.length > max) await Promise.all(keys.slice(0, keys.length - max).map((k) => cache.delete(k)));
}

async function putPage(request, response) {
  const cache = await caches.open(PAGES);
  await cache.put(request, response);
  await trim(cache, MAX_PAGES);
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  const path = url.pathname;
  const isUpload = path.startsWith('/admin/uploads/');
  const isStatic = path.startsWith('/static/');
  if ((path.startsWith('/admin') && !isUpload) || path.startsWith('/login') || path.startsWith('/logout')
      || path.startsWith('/profile') || path.includes('reset-password') || path === '/sw.js') return;

  // Uploads have random, never-reused filenames: cache first
  if (isUpload) {
    event.respondWith(
      caches.match(req).then((hit) => hit || fetch(req).then((resp) => {
        if (resp.ok) {
          const clone = resp.clone();
          event.waitUntil(caches.open(STATIC).then(async (c) => { await c.put(req, clone); await trim(c, MAX_STATIC); }));
        }
        return resp;
      }))
    );
    return;
  }

  // Static assets: network first (fresh CSS/JS after a deploy), cached copy when offline
  if (isStatic) {
    event.respondWith(
      fetch(req).then((resp) => {
        if (resp.ok) { const clone = resp.clone(); event.waitUntil(caches.open(STATIC).then((c) => c.put(req, clone))); }
        return resp;
      }).catch(() => caches.match(req))
    );
    return;
  }

  // Pages: network first; remember the ones worth having offline; fall back to the saved copy
  const isPage = req.mode === 'navigate' || (req.headers.get('accept') || '').includes('text/html');
  if (!isPage) return;
  const cacheable = CACHEABLE_PAGE.test(path) && !url.search;
  event.respondWith(
    fetch(req).then((resp) => {
      // A redirect (e.g. to the login page) must never be stored as if it were the real page
      if (cacheable && resp.ok && !resp.redirected && resp.type === 'basic') {
        const clone = resp.clone();
        event.waitUntil((async () => {
          await putPage(req, clone);
          // Recipe opened online: also keep its cook mode for the kitchen
          const m = path.match(/^\/recipe\/(\d+)\/?$/);
          if (m) {
            try {
              const cookReq = new Request(`/recipe/${m[1]}/cook`, { credentials: 'same-origin' });
              const cookResp = await fetch(cookReq);
              if (cookResp.ok && !cookResp.redirected) await putPage(cookReq, cookResp);
            } catch (e) { /* offline or blocked: fine */ }
          }
        })());
      }
      return resp;
    }).catch(async () => {
      const hit = await caches.match(req, { cacheName: PAGES });
      if (hit) return hit;
      const offline = await caches.match(OFFLINE_URL);
      return offline || new Response('You are offline.', { status: 503, headers: { 'Content-Type': 'text/plain' } });
    })
  );
});
