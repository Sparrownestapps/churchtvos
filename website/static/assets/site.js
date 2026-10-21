// Mobile menu toggle. Everything else on the site works without JavaScript.
(function () {
  var b = document.querySelector('.menu-btn'), n = document.getElementById('nav');
  if (!b || !n) return;
  b.addEventListener('click', function () {
    var open = n.classList.toggle('open');
    b.setAttribute('aria-expanded', open ? 'true' : 'false');
    b.textContent = open ? 'Close' : 'Menu';
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && n.classList.contains('open')) { b.click(); b.focus(); }
  });
})();
