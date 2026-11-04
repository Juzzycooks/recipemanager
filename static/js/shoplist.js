/* Shopping list page, household only: notice changes made by the others.
   Polls the version every 15 s while the page is visible. The page is rendered on the server,
   so a change reloads it, but never while something is being typed into the add box. */
(function () {
  'use strict';
  var host = document.querySelector('[data-shop-version]');
  if (!host || !window.fetch) return;
  var url = host.dataset.shopVersionUrl;
  var version = host.dataset.shopVersion;
  var input = document.getElementById('item-name');
  var INTERVAL = 15000;
  var timer = null, pending = false;

  function typing() {
    return !!input && (document.activeElement === input || input.value.trim() !== '');
  }

  function reloadWhenFree() {
    if (typing()) { pending = true; return; }
    location.reload();
  }

  function check() {
    if (document.visibilityState !== 'visible') return;
    if (pending) { reloadWhenFree(); return; }
    fetch(url, { credentials: 'same-origin', cache: 'no-store', headers: { 'Accept': 'application/json' } })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (data) {
        if (data && data.version && data.version !== version) reloadWhenFree();
      })
      .catch(function () {});
  }

  function start() { if (!timer) timer = setInterval(check, INTERVAL); }
  function stop() { if (timer) { clearInterval(timer); timer = null; } }

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') { check(); start(); } else stop();
  });
  if (input) input.addEventListener('blur', function () { if (pending && !typing()) location.reload(); });
  if (document.visibilityState === 'visible') start();
})();
