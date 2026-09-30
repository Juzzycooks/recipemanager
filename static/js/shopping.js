/* Shopping-list picker on the recipe page.
   Progressive enhancement: without JS the menu item posts the add-all form. */
(function () {
  'use strict';
  var trigger = document.querySelector('[data-pick-trigger]');
  var dialog = document.getElementById('pick-dialog');
  var source = document.getElementById('ingredient-list');
  if (!trigger || !dialog || !source || typeof dialog.showModal !== 'function') return;

  var list = dialog.querySelector('[data-pick-list]');
  var submit = dialog.querySelector('[data-pick-submit]');
  var status = dialog.querySelector('[data-pick-status]');
  var returnFocus = null;

  function plural(n) { return n + (n === 1 ? ' item' : ' items'); }

  function checkboxes() { return list.querySelectorAll('input[type="checkbox"]'); }

  function update() {
    var boxes = checkboxes();
    var n = 0;
    boxes.forEach(function (b) { if (b.checked) n++; });
    submit.textContent = n ? 'Add ' + plural(n) : 'Add items';
    submit.disabled = n === 0;
    status.textContent = n + ' of ' + boxes.length + ' selected';
  }

  function build() {
    list.textContent = '';
    var group = null;
    var uid = 0;
    function newGroup(title) {
      group = document.createElement('fieldset');
      group.className = 'pick-group';
      if (title) {
        var lg = document.createElement('legend');
        lg.textContent = title;
        group.appendChild(lg);
      }
      list.appendChild(group);
    }
    Array.prototype.forEach.call(source.children, function (li) {
      var text = li.textContent.trim();
      if (!text) return;
      if (li.classList.contains('list-section')) { newGroup(text); return; }
      if (!group) newGroup('');
      var row = document.createElement('label');
      row.className = 'pick-row';
      var box = document.createElement('input');
      box.type = 'checkbox';
      box.name = 'items';
      box.value = text;
      box.checked = true;
      box.id = 'pick-' + (uid++);
      var span = document.createElement('span');
      span.textContent = text;
      row.appendChild(box);
      row.appendChild(span);
      group.appendChild(row);
    });
    update();
  }

  function setAll(state) {
    checkboxes().forEach(function (b) { b.checked = state; });
    update();
  }

  trigger.addEventListener('submit', function (e) {
    e.preventDefault();
    var menu = trigger.closest('details');
    returnFocus = menu ? menu.querySelector('summary') : null;
    if (menu) menu.open = false;
    build();
    if (!checkboxes().length) { trigger.submit(); return; }
    dialog.showModal();
    var first = list.querySelector('input');
    if (first) first.focus();
  });

  list.addEventListener('change', update);
  dialog.querySelector('[data-pick-all]').addEventListener('click', function () { setAll(true); });
  dialog.querySelector('[data-pick-none]').addEventListener('click', function () { setAll(false); });
  dialog.querySelector('[data-pick-cancel]').addEventListener('click', function () { dialog.close(); });
  dialog.addEventListener('click', function (e) { if (e.target === dialog) dialog.close(); });
  dialog.addEventListener('close', function () {
    if (returnFocus && document.contains(returnFocus)) returnFocus.focus();
  });
})();
