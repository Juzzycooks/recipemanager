/* App-wide behaviour: keyboard shortcuts, install hint, offline notice, service-worker housekeeping.
   Loaded with `defer` from base.html. Everything is wrapped so a failure here never breaks a page. */
(function () {
  'use strict';
  var body = document.body;
  function url(key) { return body.getAttribute('data-url-' + key) || ''; }
  function store(get, key, value) {
    try { if (get) return localStorage.getItem(key); localStorage.setItem(key, value); } catch (e) {}
    return null;
  }
  function typing(el) {
    return el && (/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName) || el.isContentEditable);
  }

  /* ── Keyboard shortcuts ── */
  var help = document.getElementById('shortcuts-dialog');
  var chord = false, chordTimer = null;
  function openHelp() {
    if (!help) return;
    if (help.showModal) help.showModal(); else help.setAttribute('open', '');
  }
  document.addEventListener('keydown', function (e) {
    if (e.ctrlKey || e.metaKey || e.altKey || typing(e.target)) return;
    if (help && help.open) return;
    var k = e.key;
    if (chord) {
      chord = false; clearTimeout(chordTimer);
      var dest = { r: 'recipes', c: 'collections', p: 'plan', s: 'shop' }[k.toLowerCase()];
      if (dest && url(dest)) { e.preventDefault(); location.href = url(dest); }
      return;
    }
    if (k === '/') {
      var box = document.querySelector('input[type="search"], #shelf-q');
      if (box) { e.preventDefault(); box.focus(); box.select(); }
    } else if (k === 'n' && url('new')) {
      e.preventDefault(); location.href = url('new');
    } else if (k === 'g') {
      chord = true; chordTimer = setTimeout(function () { chord = false; }, 1200);
    } else if (k === '?') {
      e.preventDefault(); openHelp();
    }
  });
  document.querySelectorAll('[data-open-shortcuts]').forEach(function (b) {
    b.addEventListener('click', function () {
      document.querySelectorAll('details.menu[open]').forEach(function (d) { d.removeAttribute('open'); });
      openHelp();
    });
  });
  if (help) {
    help.addEventListener('click', function (e) { if (e.target === help) help.close(); });
    help.querySelectorAll('[data-close]').forEach(function (b) { b.addEventListener('click', function () { help.close(); }); });
  }

  /* ── Service worker housekeeping: forget cached pages when signing out ── */
  function tellSW(msg) {
    if ('serviceWorker' in navigator && navigator.serviceWorker.controller) navigator.serviceWorker.controller.postMessage(msg);
  }
  document.querySelectorAll('a[href$="/logout"], a[href*="/logout?"]').forEach(function (a) {
    a.addEventListener('click', function () { tellSW('clear-pages'); });
  });
  if (/\/(login|setup|forgot-password)\/?$/.test(location.pathname)) tellSW('clear-pages');

  /* ── Offline notice ── */
  var offline = document.getElementById('offline-notice');
  function syncOnline() { if (offline) offline.hidden = navigator.onLine !== false; }
  window.addEventListener('online', syncOnline);
  window.addEventListener('offline', syncOnline);
  syncOnline();

  /* ── "Add to home screen" hint (phones only, after a second visit, dismissible for 30 days) ── */
  try {
    var standalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone;
    var small = window.matchMedia('(max-width: 860px)').matches;
    var visits = (parseInt(store(true, 'rm-visits'), 10) || 0) + 1;
    store(false, 'rm-visits', String(visits));
    var dismissedAt = parseInt(store(true, 'rm-install-dismissed'), 10) || 0;
    var recentlyDismissed = Date.now() - dismissedAt < 30 * 24 * 3600 * 1000;
    var hint = document.getElementById('install-hint');
    if (hint && small && !standalone && visits >= 2 && !recentlyDismissed) {
      var deferred = null;
      var isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent) && !window.MSStream;
      var text = hint.querySelector('[data-install-text]');
      var action = hint.querySelector('[data-install-action]');
      function show() { hint.hidden = false; }
      window.addEventListener('beforeinstallprompt', function (e) {
        e.preventDefault(); deferred = e;
        text.textContent = 'Install this app for quick access in the kitchen.';
        action.hidden = false; show();
      });
      if (isIOS) {
        text.textContent = 'Install this app: tap Share, then “Add to Home Screen”.';
        action.hidden = true; show();
      }
      action.addEventListener('click', function () {
        if (!deferred) return;
        deferred.prompt();
        deferred.userChoice.finally(function () { hint.hidden = true; deferred = null; });
      });
      hint.querySelector('[data-install-dismiss]').addEventListener('click', function () {
        hint.hidden = true; store(false, 'rm-install-dismissed', String(Date.now()));
      });
    }
  } catch (e) {}
})();
