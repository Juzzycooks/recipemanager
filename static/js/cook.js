/* Cook mode logic, shared by recipes/cook.html and collections/shared_cook.html.
   Pure helpers (duration + ingredient matching) are exported for tests/test_cook_js.js. */
(function (root) {
  'use strict';

  /* ───────────────────────── Pure helpers ───────────────────────── */

  var FRACTIONS = { '½': 0.5, '¼': 0.25, '¾': 0.75 };
  var NUM = '(?:\\d+\\s+\\d\\/\\d|\\d+\\/\\d+|\\d+(?:[.,]\\d+)?[½¼¾]?|[½¼¾])';
  var UNIT = '(hours?|hrs?|minutes?|mins?|seconds?|secs?)';
  var UNIT_NC = '(?:hours?|hrs?|minutes?|mins?|seconds?|secs?)';
  var DURATION_RE = new RegExp(
    '(?:\\b(?:an?|one)\\s+' + UNIT_NC + '\\b)|(' + NUM + ')(?:\\s*(?:-|–|—|to)\\s*(' + NUM + '))?[\\s-]*' + UNIT + '\\b', 'gi');

  function parseNum(s) {
    s = String(s).trim().replace(',', '.');
    var m;
    if ((m = s.match(/^(\d+)\s+(\d)\/(\d)$/))) return +m[1] + m[2] / m[3];
    if ((m = s.match(/^(\d)\/(\d)$/))) return m[1] / m[2];
    if ((m = s.match(/^(\d+(?:\.\d+)?)([½¼¾])$/))) return parseFloat(m[1]) + FRACTIONS[m[2]];
    if (FRACTIONS[s] !== undefined) return FRACTIONS[s];
    return parseFloat(s);
  }
  function unitMinutes(u) {
    u = u.toLowerCase();
    if (u[0] === 'h') return 60;
    if (u[0] === 'm') return 1;
    return 1 / 60;
  }
  function unitRank(u) { u = u.toLowerCase(); return u[0] === 'h' ? 3 : u[0] === 'm' ? 2 : 1; }

  /* "simmer for 10 minutes", "marinate 3-4 hrs", "1 hour 30 minutes" -> [{minutes, maxMinutes, text}] */
  function findDurations(text) {
    var found = [], m;
    DURATION_RE.lastIndex = 0;
    while ((m = DURATION_RE.exec(text))) {
      var lo, hi, unit;
      if (m[3] === undefined && m[1] === undefined) { // "an hour" / "a minute"
        unit = m[0].match(new RegExp(UNIT, 'i'))[1]; lo = hi = 1;
      } else {
        unit = m[3]; lo = parseNum(m[1]); hi = m[2] !== undefined ? parseNum(m[2]) : lo;
      }
      if (!isFinite(lo) || !isFinite(hi) || lo <= 0) continue;
      var prev = found[found.length - 1];
      var gap = prev ? text.slice(prev.end, m.index).trim().toLowerCase() : null;
      if (prev && (gap === '' || gap === 'and' || gap === ',' || gap === '&') && unitRank(unit) < prev.rank) {
        prev.minutes += lo * unitMinutes(unit); prev.maxMinutes = prev.minutes;
        prev.end = m.index + m[0].length; prev.rank = unitRank(unit);
        prev.text = text.slice(prev.start, prev.end);
        continue;
      }
      found.push({
        minutes: lo * unitMinutes(unit), maxMinutes: hi * unitMinutes(unit),
        start: m.index, end: m.index + m[0].length, rank: unitRank(unit), text: m[0].trim()
      });
    }
    return found.filter(function (d) { return d.minutes > 0 && d.minutes <= 72 * 60; })
      .map(function (d) { return { minutes: d.minutes, maxMinutes: d.maxMinutes, text: d.text }; });
  }

  function fmtMinutes(m) {
    if (m < 1) return Math.round(m * 60) + ' sec';
    if (m < 60) return (Math.round(m * 10) / 10) + ' min';
    var h = Math.floor(m / 60), r = Math.round(m - h * 60);
    return h + ' hr' + (r ? ' ' + r + ' min' : '');
  }

  var STOP = ('fresh large small medium big ripe chopped diced sliced minced grated ground cold warm hot boiling plain extra virgin ' +
    'dried whole skinless boneless finely roughly coarsely thinly freshly to taste for serving optional and or of the a an plus more ' +
    'about approximately a few some good quality your favourite favorite each into in with at').split(' ');
  var UNITS = ('g kg mg ml l oz lb lbs cup cups tbsp tsp tablespoon tablespoons teaspoon teaspoons clove cloves pinch pinches handful ' +
    'handfuls can cans tin tins slice slices stick sticks sprig sprigs bunch bunches piece pieces dash splash knob head heads').split(' ');

  function stem(w) {
    w = w.toLowerCase();
    if (w.length > 4 && w.slice(-3) === 'ies') return w.slice(0, -3) + 'y';
    if (w.length > 4 && /(oes|ches|shes|sses|xes)$/.test(w)) return w.slice(0, -2);
    if (w.length > 3 && w.slice(-1) === 's' && w.slice(-2) !== 'ss') return w.slice(0, -1);
    return w;
  }
  function tokens(s) { return (s.toLowerCase().match(/[a-zà-ÿ]+/g) || []); }

  /* "250 g bread flour, sifted" -> { head: 'flour', words: ['bread','flour'] } */
  function ingredientKeys(text) {
    var t = String(text).replace(/\([^)]*\)/g, ' ').split(',')[0];
    var words = tokens(t).filter(function (w) {
      return w.length > 1 && STOP.indexOf(w) === -1 && UNITS.indexOf(w) === -1;
    });
    if (!words.length) return null;
    return { head: stem(words[words.length - 1]), words: words.map(stem) };
  }

  /* Which ingredients does this step mention? Prefers ingredients from the same "# Section". */
  function matchIngredients(stepText, ingredients, section) {
    var stepStems = {};
    tokens(stepText).forEach(function (w) { stepStems[stem(w)] = true; });
    function run(list) {
      return list.filter(function (ing) {
        var k = ing.keys || (ing.keys = ingredientKeys(ing.text));
        return k && k.head.length >= 3 && stepStems[k.head];
      });
    }
    var out = [];
    if (section) {
      var sec = ingredients.filter(function (i) { return i.section && i.section.toLowerCase() === section.toLowerCase(); });
      out = run(sec);
    }
    return out.length ? out : run(ingredients);
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { findDurations: findDurations, fmtMinutes: fmtMinutes, ingredientKeys: ingredientKeys, matchIngredients: matchIngredients };
  }
  if (typeof document === 'undefined' || !document.getElementById('instructions-tab')) return;

  /* ───────────────────────── Page behaviour ───────────────────────── */

  var $ = function (id) { return document.getElementById(id); };
  var steps = Array.prototype.slice.call(document.querySelectorAll('.instruction-step'));
  var totalSteps = steps.length;
  var hasTimers = !!$('timers-tab');
  var currentStep = 1, mode = 'ingredients';
  var wide = window.matchMedia('(min-width: 900px)');
  var storeKey = 'cook:' + location.pathname;

  function save() {
    try {
      var checked = [];
      document.querySelectorAll('.ingredient-item input').forEach(function (c, i) { if (c.checked) checked.push(i); });
      sessionStorage.setItem(storeKey, JSON.stringify({ step: currentStep, checked: checked }));
    } catch (e) {}
  }

  /* Ingredients (read live so the chosen scale is reflected) */
  function collectIngredients() {
    var out = [], section = '';
    Array.prototype.forEach.call($('ingredients-tab').children, function (el) {
      if (el.classList.contains('cook-section')) section = el.textContent.trim();
      else if (el.classList.contains('ingredient-item')) {
        var t = el.querySelector('.ing-text');
        out.push({ el: el, text: (t ? t.textContent : el.textContent).trim(), section: section });
      }
    });
    return out;
  }

  function renderStepExtras(stepEl) {
    var text = stepEl.querySelector('.step-text').textContent;
    var chips = stepEl.querySelector('[data-chips]'), needs = stepEl.querySelector('[data-needs]');
    var n = stepEl.dataset.step;

    if (chips && hasTimers) {
      chips.textContent = '';
      findDurations(text).forEach(function (d) {
        var b = document.createElement('button');
        b.type = 'button'; b.className = 'timer-chip';
        b.innerHTML = '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="13" r="7.5"/><path d="M12 9v4l2.5 1.5M9.5 3h5"/></svg>';
        var label = document.createElement('span');
        label.textContent = 'Start ' + fmtMinutes(d.minutes) + ' timer';
        b.appendChild(label);
        if (d.maxMinutes > d.minutes) b.title = 'The recipe says ' + d.text + '; this starts the shorter time';
        b.addEventListener('click', function () {
          window.startTimer(d.minutes, 'Step ' + n + ': ' + fmtMinutes(d.minutes));
          announce('Timer started for ' + fmtMinutes(d.minutes) + '.');
        });
        chips.appendChild(b);
      });
      chips.hidden = !chips.children.length;
    }
    if (needs) {
      var matches = matchIngredients(text, collectIngredients(), stepEl.dataset.section || '');
      needs.textContent = '';
      if (matches.length) {
        var h = document.createElement('p'); h.className = 'needs-heading'; h.textContent = 'You’ll need';
        var ul = document.createElement('ul'); ul.className = 'needs-list';
        matches.forEach(function (m) {
          var li = document.createElement('li');
          li.textContent = m.text;
          if (m.el.classList.contains('checked')) li.className = 'is-checked';
          ul.appendChild(li);
        });
        needs.appendChild(h); needs.appendChild(ul);
      }
      needs.hidden = !matches.length;
    }
  }

  /* Live region for quiet confirmations */
  function announce(msg) {
    var r = $('cook-live'); if (!r) return;
    r.textContent = ''; setTimeout(function () { r.textContent = msg; }, 30);
  }

  /* Tabs and steps */
  function setTabs(active) {
    var names = ['ingredients', 'instructions'].concat(hasTimers ? ['timers'] : []);
    document.querySelectorAll('.tab').forEach(function (t, i) {
      var on = names[i] === active;
      t.classList.toggle('active', on); t.setAttribute('aria-selected', on ? 'true' : 'false');
    });
  }
  window.showTab = function (tab) {
    if (tab === 'ingredients' && wide.matches) tab = 'instructions';
    mode = tab;
    document.querySelectorAll('.step').forEach(function (s) { s.classList.remove('active'); });
    var panel = $(tab + '-tab'); if (panel) panel.classList.add('active');
    setTabs(tab === 'finish' ? '' : tab);
    document.body.dataset.mode = tab;
    $('step-nav').style.display = tab === 'instructions' ? 'flex' : 'none';
    if (tab === 'instructions') window.showStep(currentStep);
  };
  window.showStep = function (n) {
    if (n > totalSteps) return showFinish();
    if (mode === 'finish') { mode = 'instructions'; window.showTab('instructions'); }
    currentStep = Math.max(1, Math.min(n, totalSteps));
    steps.forEach(function (s) { s.style.display = +s.dataset.step === currentStep ? 'block' : 'none'; });
    renderStepExtras(steps[currentStep - 1]);
    $('step-cur').textContent = currentStep; $('step-total').textContent = totalSteps;
    $('progress').style.transform = 'scaleX(' + (currentStep / totalSteps) + ')';
    document.querySelector('.nav-btn.prev').disabled = currentStep === 1;
    var last = currentStep === totalSteps;
    document.querySelector('.next-label').textContent = last ? 'Finish' : 'Next';
    window.scrollTo(0, 0);
    save();
  };
  window.prevStep = function () { window.showStep(currentStep - 1); };
  window.nextStep = function () { window.showStep(currentStep + 1); };

  function showFinish() {
    mode = 'finish';
    document.querySelectorAll('.step').forEach(function (s) { s.classList.remove('active'); });
    $('finish-tab').classList.add('active');
    setTabs(''); document.body.dataset.mode = 'finish';
    $('step-nav').style.display = 'none';
    $('progress').style.transform = 'scaleX(1)';
    window.scrollTo(0, 0);
    var f = $('finish-tab').querySelector('button, a'); if (f) f.focus({ preventScroll: true });
  }

  /* Timers */
  var timers = [], timerId = 0;
  window.startTimer = function (minutes, label) {
    var t = { id: ++timerId, label: label, endTime: Date.now() + minutes * 60000, interval: null, done: false };
    t.interval = setInterval(function () { tick(t); }, 250);
    timers.push(t); renderTimers(); updatePill();
  };
  window.startCustomTimer = function () {
    var h = parseInt($('custom-hr').value, 10) || 0, m = parseInt($('custom-min').value, 10) || 0, s = parseInt($('custom-sec').value, 10) || 0;
    var total = h * 60 + m + s / 60; if (total <= 0) return;
    var p = []; if (h) p.push(h + 'h'); if (m) p.push(m + 'm'); if (s) p.push(s + 's');
    window.startTimer(total, p.join(' '));
  };
  window.removeTimer = function (id) {
    var i = timers.findIndex(function (t) { return t.id === id; });
    if (i >= 0) { clearInterval(timers[i].interval); timers.splice(i, 1); }
    renderTimers(); updatePill();
  };
  function tick(t) {
    if (t.endTime - Date.now() <= 0 && !t.done) {
      t.done = true; clearInterval(t.interval);
      try { if ('Notification' in window && Notification.permission === 'granted') new Notification('Timer done', { body: t.label + ' is complete' }); } catch (e) {}
      try {
        var ctx = new (window.AudioContext || window.webkitAudioContext)();
        for (var i = 0; i < 3; i++) {
          var o = ctx.createOscillator(); o.connect(ctx.destination); o.frequency.value = 880;
          o.start(ctx.currentTime + i * 0.3); o.stop(ctx.currentTime + i * 0.3 + 0.15);
        }
      } catch (e) {}
      try { if (navigator.vibrate) navigator.vibrate([200, 100, 200]); } catch (e) {}
    }
    renderTimers(); updatePill();
  }
  function clock(ms) {
    var sec = Math.ceil(Math.max(0, ms) / 1000), h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    var mm = String(m).padStart(2, '0'), ss = String(s).padStart(2, '0');
    return h > 0 ? h + ':' + mm + ':' + ss : mm + ':' + ss;
  }
  function renderTimers() {
    var c = $('active-timers'); if (!c) return;
    if (!timers.length) { c.textContent = ''; return; }
    c.innerHTML = '';
    timers.forEach(function (t) {
      var card = document.createElement('div'); card.className = 'timer-card' + (t.done ? ' done' : '');
      var info = document.createElement('div');
      var time = document.createElement('div'); time.className = 'timer-time'; time.textContent = t.done ? 'Done' : clock(t.endTime - Date.now());
      var lab = document.createElement('div'); lab.className = 'timer-label'; lab.textContent = t.label;
      info.appendChild(time); info.appendChild(lab);
      var rm = document.createElement('button'); rm.type = 'button'; rm.className = 'timer-remove'; rm.textContent = 'Remove';
      rm.setAttribute('aria-label', 'Remove timer ' + t.label);
      rm.addEventListener('click', function () { window.removeTimer(t.id); });
      card.appendChild(info); card.appendChild(rm); c.appendChild(card);
    });
  }
  function updatePill() {
    var pill = $('timer-pill'); if (!pill) return;
    if (!timers.length) { pill.hidden = true; return; }
    var doneOne = timers.filter(function (t) { return t.done; })[0];
    var running = timers.filter(function (t) { return !t.done; }).sort(function (a, b) { return a.endTime - b.endTime; })[0];
    pill.hidden = false;
    pill.classList.toggle('is-done', !!doneOne);
    pill.querySelector('[data-pill-text]').textContent = doneOne ? 'Timer done' : clock(running.endTime - Date.now());
  }
  if ($('timer-pill')) $('timer-pill').addEventListener('click', function () { window.showTab('timers'); });

  /* Screen awake, with an honest badge */
  var wakeLock = null;
  function setWake(ok) {
    var b = $('wake-badge'); if (!b) return;
    b.classList.toggle('is-off', !ok);
    b.querySelector('[data-wake-text]').textContent = ok ? 'Screen stays on' : 'Screen may sleep';
  }
  function acquireWake() {
    if (!('wakeLock' in navigator)) return setWake(false);
    navigator.wakeLock.request('screen').then(function (l) {
      wakeLock = l; setWake(true);
      l.addEventListener('release', function () { setWake(false); });
    }).catch(function () { setWake(false); });
  }
  document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') acquireWake(); });
  acquireWake();

  /* Swipe between steps + arrow keys */
  var sx = 0, sy = 0, tracking = false;
  var panel = $('instructions-tab');
  panel.addEventListener('touchstart', function (e) {
    if (e.touches.length !== 1 || e.target.closest('button, a, input, label')) { tracking = false; return; }
    tracking = true; sx = e.touches[0].clientX; sy = e.touches[0].clientY;
  }, { passive: true });
  panel.addEventListener('touchend', function (e) {
    if (!tracking) return; tracking = false;
    var dx = e.changedTouches[0].clientX - sx, dy = e.changedTouches[0].clientY - sy;
    if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.5) { if (dx < 0) window.nextStep(); else window.prevStep(); }
  }, { passive: true });
  document.addEventListener('keydown', function (e) {
    if (mode !== 'instructions' || e.ctrlKey || e.metaKey || e.altKey || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)) return;
    if (e.key === 'ArrowRight' || e.key === 'PageDown') { e.preventDefault(); window.nextStep(); }
    else if (e.key === 'ArrowLeft' || e.key === 'PageUp') { e.preventDefault(); window.prevStep(); }
  });

  /* Finish screen: log the cook and rate it (signed-in cook mode only) */
  var fin = $('finish-tab');
  function csrf() { var m = document.querySelector('meta[name="csrf-token"]'); return m ? m.content : ''; }
  function post(url, body) {
    return fetch(url, { method: 'POST', credentials: 'same-origin', headers: { 'X-CSRFToken': csrf() }, body: body || null });
  }
  var made = fin && fin.querySelector('[data-made]');
  if (made) made.addEventListener('click', function () {
    made.disabled = true;
    post(fin.dataset.madeUrl).then(function (r) {
      if (!r.ok) throw new Error(); made.textContent = 'Logged'; announce('Logged. Enjoy!');
    }).catch(function () { made.disabled = false; announce('Couldn’t log that. Check your connection and try again.'); });
  });
  fin && fin.querySelectorAll('[data-score]').forEach(function (b) {
    b.addEventListener('click', function () {
      var fd = new FormData(); fd.append('score', b.dataset.score);
      post(fin.dataset.rateUrl, fd).then(function (r) {
        if (!r.ok) throw new Error();
        fin.querySelectorAll('[data-score]').forEach(function (x) { x.setAttribute('aria-pressed', +x.dataset.score <= +b.dataset.score ? 'true' : 'false'); });
        announce('Rated ' + b.dataset.score + ' out of 5.');
      }).catch(function () { announce('Couldn’t save the rating. Try again.'); });
    });
  });
  fin && fin.querySelectorAll('[data-restart]').forEach(function (b) {
    b.addEventListener('click', function () {
      document.querySelectorAll('.ingredient-item input').forEach(function (c) { c.checked = false; c.parentElement.classList.remove('checked'); });
      currentStep = 1; window.showTab('instructions'); save();
    });
  });

  /* Ingredient ticks persist through an accidental refresh */
  document.querySelectorAll('.ingredient-item input').forEach(function (c) {
    c.addEventListener('change', function () { c.parentElement.classList.toggle('checked', c.checked); save(); if (mode === 'instructions') renderStepExtras(steps[currentStep - 1]); });
  });

  /* Start */
  document.querySelector('.nav-btn.prev').addEventListener('click', window.prevStep);
  document.querySelector('.nav-btn.next').addEventListener('click', window.nextStep);
  $('step-total').textContent = totalSteps;
  var startTab = wide.matches ? 'instructions' : 'ingredients';
  try {
    var saved = JSON.parse(sessionStorage.getItem(storeKey) || 'null');
    if (saved) {
      (saved.checked || []).forEach(function (i) {
        var c = document.querySelectorAll('.ingredient-item input')[i]; if (c) { c.checked = true; c.parentElement.classList.add('checked'); }
      });
      if (saved.step > 1 && saved.step <= totalSteps) { currentStep = saved.step; startTab = 'instructions'; }
    }
  } catch (e) {}
  // Deep links: #step-3, #timers, #finish
  var hash = location.hash.match(/^#(step-(\d+)|timers|finish)$/);
  if (hash) {
    if (hash[2] && +hash[2] >= 1 && +hash[2] <= totalSteps) { currentStep = +hash[2]; startTab = 'instructions'; }
    else if (hash[1] === 'timers' && hasTimers) startTab = 'timers';
  }
  window.showTab(startTab);
  if (hash && hash[1] === 'finish') showFinish();
  wide.addEventListener('change', function () { if (wide.matches && mode === 'ingredients') window.showTab('instructions'); });
  if (hasTimers && 'Notification' in window && Notification.permission === 'default') {
    document.addEventListener('click', function ask() { Notification.requestPermission(); document.removeEventListener('click', ask); }, { once: true });
  }
  if (root.RecipeUnits) {
    root.RecipeUnits.attach({ items: '.ingredient-item .ing-text', scaleBtns: '.scale-btn' });
    document.querySelectorAll('.scale-btn').forEach(function (b) {
      b.addEventListener('click', function () { setTimeout(function () { if (mode === 'instructions') renderStepExtras(steps[currentStep - 1]); }, 0); });
    });
  }
})(typeof window !== 'undefined' ? window : this);
