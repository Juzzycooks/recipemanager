/* Recipe shelf: filter toggle, favorite hearts, quick-tour dismissal. */
(function () {
    'use strict';
    document.documentElement.classList.add('shelf-js');

    // Filters toggle (phones): open by default only when a filter is already active
    var g = document.getElementById('filter-groups');
    var b = document.querySelector('.filters-toggle');
    if (g && b) {
        var small = window.matchMedia('(max-width: 640px)');
        var sync = function () {
            var open = !small.matches || b.dataset.active !== '0';
            g.hidden = !open;
            b.setAttribute('aria-expanded', open);
        };
        b.addEventListener('click', function () {
            var o = g.hidden;
            g.hidden = !o;
            b.setAttribute('aria-expanded', o);
        });
        sync();
        small.addEventListener('change', sync);
    }

    // Quick tour: remember dismissal
    var KEY = 'shelfTourDismissed';
    var tours = document.querySelectorAll('[data-tour]');
    var dismissed = false;
    try { dismissed = localStorage.getItem(KEY) === '1'; } catch (e) {}
    tours.forEach(function (t) {
        if (dismissed) { t.hidden = true; return; }
        var btn = t.querySelector('[data-tour-dismiss]');
        if (btn) btn.addEventListener('click', function () {
            try { localStorage.setItem(KEY, '1'); } catch (e) {}
            t.hidden = true;
        });
    });

    // Favorite hearts: optimistic toggle over fetch, with rollback
    var live = document.getElementById('shelf-live');
    var meta = document.querySelector('meta[name="csrf-token"]');
    var csrf = meta ? meta.content : '';
    function paint(btn, on) {
        var t = btn.dataset.title || 'this recipe';
        btn.setAttribute('aria-pressed', on ? 'true' : 'false');
        btn.setAttribute('aria-label', (on ? 'Remove ' : 'Add ') + t + (on ? ' from favorites' : ' to favorites'));
    }
    document.querySelectorAll('.fav-form').forEach(function (form) {
        var btn = form.querySelector('.fav-btn');
        if (!btn || !window.fetch) return;
        form.addEventListener('submit', function (e) {
            e.preventDefault();
            if (btn.getAttribute('aria-busy') === 'true') return;
            var before = btn.getAttribute('aria-pressed') === 'true';
            paint(btn, !before);
            btn.setAttribute('aria-busy', 'true');
            if (live) live.textContent = '';
            fetch(form.action, {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'X-CSRFToken': csrf, 'X-Requested-With': 'fetch', 'Accept': 'application/json' }
            }).then(function (r) {
                if (!r.ok) throw new Error('bad status');
                return r.json();
            }).then(function (d) {
                paint(btn, !!d.favorited);
            }).catch(function () {
                paint(btn, before);
                if (live) live.textContent = 'Couldn’t update favorites for “' + (btn.dataset.title || 'that recipe') + '”. Check your connection and try the heart again.';
            }).then(function () {
                btn.removeAttribute('aria-busy');
            });
        });
    });
})();
