/* Metric / US unit conversion for ingredient lines and method steps (display only).
   Port of IOS/RecipeManager/Core/UnitConversion.swift: keep the two in step.
   Anything it can't read confidently is left exactly as written. */
(function (root) {
  var KEY = 'unitSystem';

  var LIQUIDS = ['milk', 'cream', 'water', 'stock', 'broth', 'juice', 'oil', 'wine', 'beer', 'vinegar', 'syrup', 'liqueur', 'rum',
    'vodka', 'whisky', 'whiskey', 'brandy', 'cider', 'coffee', 'tea', 'yogurt drink', 'buttermilk', 'passata'];

  function isLiquid(remainder) {
    var nearby = remainder.slice(0, 40).toLowerCase();
    return LIQUIDS.some(function (w) { return nearby.indexOf(w) !== -1; });
  }

  function unit(raw, remainder) {
    var k = raw.toLowerCase().replace(/\./g, '').replace(/\s+/g, '');
    switch (k) {
      case 'lb': case 'lbs': case 'pound': case 'pounds': return { kind: 'w', base: 453.592, metric: false };
      case 'oz': case 'ounce': case 'ounces':
        return isLiquid(remainder) ? { kind: 'v', base: 29.5735, metric: false } : { kind: 'w', base: 28.3495, metric: false };
      case 'floz': case 'fluidounce': case 'fluidounces': return { kind: 'v', base: 29.5735, metric: false };
      case 'cup': case 'cups': return { kind: 'v', base: 236.588, metric: false };
      case 'tbsp': case 'tbsps': case 'tbs': case 'tablespoon': case 'tablespoons': return { kind: 'v', base: 14.7868, metric: false };
      case 'tsp': case 'tsps': case 'teaspoon': case 'teaspoons': return { kind: 'v', base: 4.92892, metric: false };
      case 'pint': case 'pints': case 'pt': return { kind: 'v', base: 473.176, metric: false };
      case 'quart': case 'quarts': case 'qt': return { kind: 'v', base: 946.353, metric: false };
      case 'gallon': case 'gallons': return { kind: 'v', base: 3785.41, metric: false };
      case 'g': case 'gram': case 'grams': return { kind: 'w', base: 1, metric: true };
      case 'kg': case 'kilo': case 'kilos': case 'kilogram': case 'kilograms': return { kind: 'w', base: 1000, metric: true };
      case 'ml': case 'milliliter': case 'milliliters': case 'millilitre': case 'millilitres': return { kind: 'v', base: 1, metric: true };
      case 'l': case 'liter': case 'liters': case 'litre': case 'litres': return { kind: 'v', base: 1000, metric: true };
    }
    return null;
  }

  var FRAC = '[¼½¾⅓⅔⅛⅜⅝⅞]';
  var QTY = '(?:\\d+\\s+\\d+/\\d+|\\d+\\s*' + FRAC + '|\\d+/\\d+|\\d+(?:[.,]\\d+)?|' + FRAC + ')';
  var UNITS = 'fluid\\s+ounces?|fl\\.?\\s?oz|pounds?|lbs?|ounces?|oz|cups?|tablespoons?|tbsps?|tbs|teaspoons?|tsps?|pints?|pt|quarts?|qt|gallons?|kilograms?|kilos?|kg|grams?|g|milliliters?|millilitres?|ml|liters?|litres?|l';
  var AMOUNT = '(^|[^\\w/.,])(' + QTY + ')(?:\\s*(?:-|–|—|to)\\s*(' + QTY + '))?\\s*(' + UNITS + ')\\b(?:\\.(?=\\s+[a-z]))?';
  var PAREN = /^\s*\(\s*([^()]*?)\s*\)/;
  var GLYPH = { '¼': 0.25, '½': 0.5, '¾': 0.75, '⅓': 1 / 3, '⅔': 2 / 3, '⅛': 0.125, '⅜': 0.375, '⅝': 0.625, '⅞': 0.875 };

  function num(raw) {
    var s = raw.trim(), last = s.charAt(s.length - 1);
    if (GLYPH[last] !== undefined) return (parseFloat(s.slice(0, -1)) || 0) + GLYPH[last];
    if (s.indexOf('/') !== -1) {
      var p = s.split(/[\s/]+/).map(parseFloat);
      if (p.length === 3 && p[2]) return p[0] + p[1] / p[2];
      if (p.length === 2 && p[1]) return p[0] / p[1];
      return NaN;
    }
    return parseFloat(s.replace(',', '.'));
  }

  function snap(v, step) { return Math.round(v / step) * step; }

  function plain(v) {
    var t = v.toFixed(2);
    while (t.indexOf('.') !== -1 && (t.slice(-1) === '0' || t.slice(-1) === '.')) t = t.slice(0, -1);
    return t;
  }

  function fractional(value, step) {
    var v = Math.max(snap(value, step), step), whole = Math.floor(v), rest = v - whole, g;
    if (rest >= 0.99) return String(whole + 1);
    if (rest >= 0.87) g = '⅞'; else if (rest >= 0.7) g = '¾'; else if (rest >= 0.6) g = '⅝'; else if (rest >= 0.45) g = '½';
    else if (rest >= 0.35) g = '⅜'; else if (rest >= 0.3) g = '⅓'; else if (rest >= 0.2) g = '¼'; else if (rest >= 0.1) g = '⅛';
    else return String(whole);
    return whole === 0 ? g : whole + ' ' + g;
  }

  /* An amount in grams or millilitres, written the way a cook in that system would. */
  function render(base, kind, metric) {
    if (metric) {
      var v = base < 5 ? snap(base, 0.5) : base < 10 ? snap(base, 1) : base < 100 ? snap(base, 5) : snap(base, 10);
      if (v >= 1000) return { value: plain(snap(v / 1000, 0.05)), unit: kind === 'w' ? 'kg' : 'L' };
      return { value: plain(Math.max(v, 0.5)), unit: kind === 'w' ? 'g' : 'ml' };
    }
    if (kind === 'w') {
      var oz = base / 28.3495;
      if (base < 450) return { value: oz < 1 ? fractional(oz, 0.25) : fractional(oz, oz < 10 ? 0.5 : 1), unit: 'oz' };
      return { value: fractional(base / 453.592, 0.25), unit: 'lb' };
    }
    if (base < 15) return { value: fractional(base / 4.92892, 0.25), unit: 'tsp' };
    if (base < 60) return { value: fractional(base / 14.7868, 0.5), unit: 'tbsp' };
    if (base < 950) { var cups = base / 236.588; return { value: fractional(cups, 0.25), unit: cups > 1.12 ? 'cups' : 'cup' }; }
    return { value: fractional(base / 946.353, 0.25), unit: 'qt' };
  }

  /* A manual scan (not String.replace) so a matching parenthetical like "(450 g)" can be swallowed along with the amount. */
  function convertAmounts(text, system) {
    var wantMetric = system === 'metric', re = new RegExp(AMOUNT, 'gi'), out = '', last = 0, m;
    while ((m = re.exec(text)) !== null) {
      var pre = m[1], from = unit(m[4], text.slice(m.index + m[0].length)), low = num(m[2]);
      out += text.slice(last, m.index);
      last = m.index + m[0].length;
      if (!from || from.metric === wantMetric || !isFinite(low)) { out += m[0]; continue; }
      var after = text.slice(last), paren = after.match(PAREN), used = false;
      if (paren) {
        var inner = new RegExp('^' + AMOUNT.replace('(^|[^\\w/.,])', '()') + '$', 'i').exec(paren[1]);
        var theirs = inner && unit(inner[4], '');
        if (theirs && theirs.metric === wantMetric) { out += pre + paren[1]; last += paren[0].length; re.lastIndex = last; used = true; }
      }
      if (used) continue;
      var a = render(low * from.base, from.kind, wantMetric);
      if (m[3]) {
        var hiBase = num(m[3]) * from.base, b = render(hiBase, from.kind, wantMetric);
        if (wantMetric && a.unit !== b.unit) {   // a range that crosses 1 kg / 1 L reads best in the bigger unit for both ends
          a = { value: plain(snap(low * from.base / 1000, 0.05)), unit: b.unit }; b = { value: plain(snap(hiBase / 1000, 0.05)), unit: b.unit };
        }
        out += pre + (a.unit === b.unit ? a.value + '–' + b.value + ' ' + a.unit : a.value + ' ' + a.unit + '–' + b.value + ' ' + b.unit);
      } else {
        out += pre + a.value + ' ' + a.unit;
      }
    }
    return out + text.slice(last);
  }

  var DEG = '(?:°|º|˚)';
  var F_RE = '(^|[^\\d.])(\\d{2,3})(?:\\s*' + DEG + '\\s*|\\s+degrees?\\s+|(?=F\\b))F(?:ahrenheit)?\\b(?:\\s*\\(\\s*(\\d{2,3})\\s*' + DEG + '?\\s*C(?:elsius)?\\s*\\))?';
  var C_RE = '(^|[^\\d.])(\\d{2,3})(?:\\s*' + DEG + '\\s*|\\s+degrees?\\s+)C(?:elsius)?\\b(?:\\s*\\(\\s*(\\d{2,3})\\s*' + DEG + '?\\s*F(?:ahrenheit)?\\s*\\))?';

  function temperatures(text, system) {
    var metric = system === 'metric';
    return text.replace(new RegExp(metric ? F_RE : C_RE, 'g'), function (whole, pre, value, given) {
      var out = given || String(snap(metric ? (parseFloat(value) - 32) * 5 / 9 : parseFloat(value) * 9 / 5 + 32, 5));
      return pre + out + '°' + (metric ? 'C' : 'F');
    });
  }

  function convert(text, system) {
    if (!text || (system !== 'metric' && system !== 'imperial')) return text;
    return convertAmounts(temperatures(text, system), system);
  }

  /* Preference (shared by every page on this device) and the elements that follow it. */
  function get() {
    try { var s = localStorage.getItem(KEY); if (s === 'metric' || s === 'imperial') return s; } catch (e) {}
    return 'original';
  }

  function set(system) {
    try { localStorage.setItem(KEY, system); } catch (e) {}
    sync();
    document.dispatchEvent(new CustomEvent('unitsystemchange', { detail: system }));
  }

  function sync() {
    var current = get();
    document.querySelectorAll('[data-unit]').forEach(function (b) {
      var on = b.dataset.unit === current;
      b.classList.toggle('active', on);
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
  }

  /* Method text is plain; ingredient lists are redrawn by units.js (which also scales them). */
  function paint() {
    var system = get();
    document.querySelectorAll('.instruction-list li:not(.list-section) > span, .step-text').forEach(function (el) {
      if (el.dataset.unitOriginal === undefined) el.dataset.unitOriginal = el.textContent;
      el.textContent = convert(el.dataset.unitOriginal, system);
    });
  }

  function init() {
    sync();
    paint();
    document.querySelectorAll('[data-unit]').forEach(function (b) { b.addEventListener('click', function () { set(b.dataset.unit); }); });
    document.addEventListener('unitsystemchange', paint);
  }

  var api = { convert: convert, get: get, set: set };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof document !== 'undefined') {
    root.UnitConv = api;
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
  }
})(typeof window !== 'undefined' ? window : this);
