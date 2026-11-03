/* Recipe ingredient scaling engine.
   Usage:
     RecipeUnits.attach({
       items: '#ingredient-list li',   // elements whose text is one ingredient line
       scaleBtns: '.scale-btn',        // optional: buttons with data-scale
     });
   Scales the leading quantity of each ingredient line by the chosen factor. */
(function () {
  const FRACTIONS = { '½': 0.5, '¼': 0.25, '¾': 0.75, '⅓': 1 / 3, '⅔': 2 / 3, '⅛': 0.125 };
  const FRAC_OUT = [[0.25, '¼'], [1 / 3, '⅓'], [0.5, '½'], [2 / 3, '⅔'], [0.75, '¾']];
  // One amount: "1 1/2", "1/2", "1,000" or "1,000.5" (thousands: groups of exactly three), "1.5" or "1,5", "1½", "2", "½".
  const QTY = '(?:\\d+\\s+\\d+/\\d+|\\d+/\\d+|\\d{1,3}(?:,\\d{3})+(?:\\.\\d+)?(?![\\d,])|\\d*[.,]\\d+|\\d+\\s*[½¼¾⅓⅔⅛]|\\d+|[½¼¾⅓⅔⅛])';
  // A leading amount, or a range of two ("1-2", "1–2", "1 to 2"); the separator is kept as written.
  const QTY_RE = new RegExp('^(\\s*)(' + QTY + ')(?:(\\s*[-–—]\\s*|\\s+to\\s+)(' + QTY + '))?\\s*');

  function parseNum(num) {
    num = num.trim();
    if (FRACTIONS[num] !== undefined) return FRACTIONS[num];
    if (/^\d+\s*[½¼¾⅓⅔⅛]$/.test(num)) return parseInt(num) + FRACTIONS[num.slice(-1)];
    if (num.includes('/')) {
      const parts = num.split(/\s+/);
      if (parts.length === 2) { const [n, d] = parts[1].split('/'); return parseInt(parts[0]) + parseInt(n) / parseInt(d); }
      const [n, d] = num.split('/'); return parseInt(n) / parseInt(d);
    }
    if (/^\d{1,3}(,\d{3})+(\.\d+)?$/.test(num)) return parseFloat(num.replace(/,/g, ''));   // 1,000
    return parseFloat(num.replace(',', '.'));                                           // 1.5 or 1,5
  }

  function fmtFrac(n) {
    const whole = Math.floor(n), frac = n - whole;
    if (frac < 0.05) return String(whole || Math.round(n * 100) / 100);
    for (const [v, sym] of FRAC_OUT) if (Math.abs(frac - v) < 0.05) return (whole ? whole + ' ' : '') + sym;
    return String(Math.round(n * 100) / 100);
  }

  function scaleLine(line, factor) {
    if (factor === 1) return line;
    const m = line.match(QTY_RE);
    if (!m) return line;
    const value = parseNum(m[2]), upper = m[4] === undefined ? null : parseNum(m[4]);
    if (!isFinite(value) || (upper !== null && !isFinite(upper))) return line;
    const rest = line.slice(m[0].length);
    const amount = fmtFrac(value * factor) + (upper === null ? '' : m[3] + fmtFrac(upper * factor));
    return m[1] + amount + (rest ? ' ' + rest : '');
  }

  function attach(opts) {
    const items = document.querySelectorAll(opts.items);
    items.forEach(function (el) {
      if (!el.dataset.original) el.dataset.original = el.textContent.trim();
    });

    let factor = 1;

    function render() {
      if (opts.scaleBtns) document.querySelectorAll(opts.scaleBtns).forEach(function (b) {
        b.classList.toggle('active', parseFloat(b.dataset.scale) === factor);
      });
      items.forEach(function (el) {
        var text = factor === 1 ? el.dataset.original : scaleLine(el.dataset.original, factor);
        // Metric / US display preference (unitconv.js); the scaled amount is converted, never the saved recipe.
        el.textContent = window.UnitConv ? window.UnitConv.convert(text, window.UnitConv.get()) : text;
      });
    }

    if (opts.scaleBtns) document.querySelectorAll(opts.scaleBtns).forEach(function (btn) {
      btn.addEventListener('click', function () { factor = parseFloat(btn.dataset.scale); render(); });
    });
    document.addEventListener('unitsystemchange', render);
    render();
  }

  window.RecipeUnits = { scaleLine: scaleLine, attach: attach };
})();
