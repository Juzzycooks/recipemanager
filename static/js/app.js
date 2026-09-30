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

  /* ── "Add to home screen" hint ──
     Quiet by design: phones only, only after you've come back on three separate days-of-use sessions,
     never once installed, and it always goes away (Not now, Install, or a 20 second timeout). */
  try {
    var DAY = 24 * 3600 * 1000;
    var hint = $('install-hint');
    var standalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone;
    var phone = window.matchMedia('(max-width: 860px)').matches && window.matchMedia('(pointer: coarse)').matches;
    var until = parseInt(store(true, 'rm-install-snooze'), 10) || 0;   // don't show again before this time
    function snooze(days) { store(false, 'rm-install-snooze', String(Date.now() + days * DAY)); }

    // Count sessions, not page loads
    var counted = false;
    try { counted = sessionStorage.getItem('rm-session-counted') === '1'; sessionStorage.setItem('rm-session-counted', '1'); } catch (e) {}
    var sessions = parseInt(store(true, 'rm-sessions'), 10) || 0;
    if (!counted) { sessions += 1; store(false, 'rm-sessions', String(sessions)); }

    if (hint && phone && !standalone && sessions >= 3 && Date.now() > until) {
      var deferred = null, timer = null;
      var text = hint.querySelector('[data-install-text]');
      var action = hint.querySelector('[data-install-action]');
      var isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent) && !window.MSStream;
      function close(days) { hint.hidden = true; clearTimeout(timer); snooze(days); }
      function show() { hint.hidden = false; clearTimeout(timer); timer = setTimeout(function () { close(7); }, 20000); }
      action.hidden = true;                                   // no button unless installing will actually work
      window.addEventListener('beforeinstallprompt', function (e) {
        e.preventDefault(); deferred = e;
        text.textContent = 'Install this app for quick access in the kitchen.';
        action.hidden = false; show();
      });
      window.addEventListener('appinstalled', function () { close(3650); });
      if (isIOS) { text.textContent = 'To install: tap Share, then “Add to Home Screen”.'; show(); }
      action.addEventListener('click', function () {
        var d = deferred; deferred = null;
        if (!d) return close(30);
        d.prompt();
        d.userChoice.then(function (c) { close(c && c.outcome === 'accepted' ? 3650 : 30); }, function () { close(30); });
      });
      hint.querySelector('[data-install-dismiss]').addEventListener('click', function () { close(30); });
    }
  } catch (e) {}
})();
