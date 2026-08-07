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
  const QTY_RE = /^(\s*)(\d+\s+\d+\/\d+|\d+\/\d+|\d*[.,]\d+|\d+\s*[½¼¾⅓⅔⅛]|\d+|[½¼¾⅓⅔⅛])\s*/;

  function parseNum(num) {
    num = num.trim();
    if (FRACTIONS[num] !== undefined) return FRACTIONS[num];
    if (/^\d+\s*[½¼¾⅓⅔⅛]$/.test(num)) return parseInt(num) + FRACTIONS[num.slice(-1)];
    if (num.includes('/')) {
      const parts = num.split(/\s+/);
      if (parts.length === 2) { const [n, d] = parts[1].split('/'); return parseInt(parts[0]) + parseInt(n) / parseInt(d); }
      const [n, d] = num.split('/'); return parseInt(n) / parseInt(d);
    }
    return parseFloat(num.replace(',', '.'));
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
    let value = parseNum(m[2]);
    if (!isFinite(value)) return line;
    value *= factor;
    const rest = line.slice(m[0].length);
    return m[1] + fmtFrac(value) + (rest ? ' ' + rest : '');
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
        el.textContent = factor === 1 ? el.dataset.original : scaleLine(el.dataset.original, factor);
      });
    }

    if (opts.scaleBtns) document.querySelectorAll(opts.scaleBtns).forEach(function (btn) {
      btn.addEventListener('click', function () { factor = parseFloat(btn.dataset.scale); render(); });
    });
    render();
  }

  window.RecipeUnits = { scaleLine: scaleLine, attach: attach };
})();
