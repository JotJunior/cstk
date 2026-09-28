/* cstk presentation: comportamento do deck (template fixo da skill).
   Sem dependencias, sem rede. Sem JS o documento continua legivel no modo
   relatorio. Teclas: setas/espaco navegam, R alterna relatorio/slides,
   T alterna tema, F tela cheia, P imprime. */
(function () {
  'use strict';

  var root = document.documentElement;
  var deck = document.getElementById('deck');
  if (!deck) { return; }

  var slides = Array.prototype.slice.call(deck.querySelectorAll('.slide'));
  var total = slides.length;
  var current = 0;
  var mode = 'report';
  var CANVAS_W = 1600;
  var CANVAS_H = 900;
  var STORE_KEY = 'cstk-presentation:' + (document.title || 'deck');

  var counterCurrent = document.querySelector('.hud__current');
  var counterTotal = document.querySelector('.hud__total');
  var modeButton = document.querySelector('[data-action="mode"]');
  var tocList = document.querySelector('.toc__list');
  var tocLinks = [];

  root.classList.add('js');

  function readStore(key) {
    try { return window.localStorage.getItem(STORE_KEY + ':' + key); } catch (e) { return null; }
  }

  function writeStore(key, value) {
    try { window.localStorage.setItem(STORE_KEY + ':' + key, value); } catch (e) { /* sem storage */ }
  }

  function clamp(i) { return Math.max(0, Math.min(total - 1, i)); }

  function fit() {
    var scale = Math.min(window.innerWidth / CANVAS_W, window.innerHeight / CANVAS_H);
    root.style.setProperty('--scale', String(scale));
  }

  function setProgress(fraction) {
    root.style.setProperty('--progress', (Math.max(0, Math.min(1, fraction)) * 100).toFixed(2) + '%');
  }

  function indexFromHash() {
    var m = /^#slide-(\d+)$/.exec(window.location.hash || '');
    if (!m) { return null; }
    var n = parseInt(m[1], 10) - 1;
    return (n >= 0 && n < total) ? n : null;
  }

  function markActive(i) {
    for (var k = 0; k < tocLinks.length; k++) {
      tocLinks[k].parentNode.classList.toggle('is-active', k === i);
    }
    if (counterCurrent) { counterCurrent.textContent = String(i + 1); }
  }

  function show(i, updateHash) {
    if (!total) { return; }
    i = clamp(i);
    slides[current].classList.remove('is-current');
    current = i;
    slides[current].classList.add('is-current');
    if (mode === 'slides') {
      for (var k = 0; k < total; k++) {
        slides[k].setAttribute('aria-hidden', k === current ? 'false' : 'true');
      }
      setProgress(total > 1 ? current / (total - 1) : 1);
    }
    markActive(current);
    if (updateHash !== false && window.history && window.history.replaceState) {
      window.history.replaceState(null, '', '#slide-' + (current + 1));
    }
  }

  function setMode(next, persist) {
    mode = next === 'slides' ? 'slides' : 'report';
    root.classList.toggle('is-slides', mode === 'slides');
    root.classList.toggle('is-report', mode === 'report');
    if (modeButton) {
      modeButton.textContent = mode === 'slides'
        ? modeButton.getAttribute('data-label-report')
        : modeButton.getAttribute('data-label-slides');
    }
    if (mode === 'slides') {
      fit();
      if (!fitted) { fitSlides(); }
      show(current, false);
    } else {
      for (var k = 0; k < total; k++) { slides[k].removeAttribute('aria-hidden'); }
      slides[current].scrollIntoView({ block: 'start' });
      onScroll();
    }
    if (persist) { writeStore('mode', mode); }
  }

  /* Reduz a tipografia de cada slide (--fit) ate o conteudo caber no
     canvas 1600x900. Mede no layout de slides; o valor fica inline e vale
     tambem para a impressao. */
  var fitted = false;
  function fitSlides() {
    var wasSlides = root.classList.contains('is-slides');
    if (!wasSlides) { root.classList.add('is-slides'); }
    for (var i = 0; i < total; i++) {
      var s = slides[i];
      var body = s.querySelector('.slide__body');
      if (!body) { continue; }
      var fit = 1;
      s.style.setProperty('--fit', '1');
      while (body.scrollHeight > body.clientHeight + 1 && fit > 0.62) {
        fit = Math.round((fit - 0.04) * 100) / 100;
        s.style.setProperty('--fit', String(fit));
      }
    }
    if (!wasSlides) { root.classList.remove('is-slides'); }
    fitted = true;
  }

  function effectiveTheme() {
    var forced = root.getAttribute('data-theme');
    if (forced) { return forced; }
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function toggleTheme() {
    var next = effectiveTheme() === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    writeStore('theme', next);
  }

  function toggleFullscreen() {
    var el = document.documentElement;
    if (document.fullscreenElement) {
      if (document.exitFullscreen) { document.exitFullscreen(); }
    } else if (el.requestFullscreen) {
      el.requestFullscreen().catch(function () { /* recusado pelo navegador */ });
    }
  }

  function buildToc() {
    if (!tocList) { return; }
    for (var i = 0; i < total; i++) {
      var s = slides[i];
      var type = s.getAttribute('data-type') || '';
      var li = document.createElement('li');
      var a = document.createElement('a');
      a.href = '#' + s.id;
      a.textContent = s.getAttribute('data-title') || ('#' + (i + 1));
      if (type === 'cover' || type === 'chapter' || type === 'sources') { li.className = 'is-major'; }
      if (type === 'spec') { li.className = 'is-spec'; }
      li.appendChild(a);
      tocList.appendChild(li);
      tocLinks.push(a);
    }
  }

  function onScroll() {
    if (mode !== 'report') { return; }
    var doc = document.documentElement;
    var max = doc.scrollHeight - window.innerHeight;
    setProgress(max > 0 ? window.scrollY / max : 1);
    var line = window.innerHeight * 0.3;
    var found = 0;
    for (var i = 0; i < total; i++) {
      if (slides[i].getBoundingClientRect().top <= line) { found = i; } else { break; }
    }
    if (found !== current) {
      slides[current].classList.remove('is-current');
      current = found;
      slides[current].classList.add('is-current');
      markActive(current);
    }
  }

  function onKey(e) {
    if (e.defaultPrevented || e.altKey || e.ctrlKey || e.metaKey) { return; }
    var tag = (e.target && e.target.tagName) || '';
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') { return; }
    var key = e.key;
    if (key === 'r' || key === 'R') { setMode(mode === 'slides' ? 'report' : 'slides', true); e.preventDefault(); return; }
    if (key === 't' || key === 'T') { toggleTheme(); e.preventDefault(); return; }
    if (key === 'p' || key === 'P') { window.print(); e.preventDefault(); return; }
    if (key === 'f' || key === 'F') { toggleFullscreen(); e.preventDefault(); return; }
    if (mode !== 'slides') { return; }
    if (key === 'ArrowRight' || key === 'PageDown' || key === ' ' || key === 'Enter' || key === 'ArrowDown') {
      show(current + 1); e.preventDefault();
    } else if (key === 'ArrowLeft' || key === 'PageUp' || key === 'Backspace' || key === 'ArrowUp') {
      show(current - 1); e.preventDefault();
    } else if (key === 'Home') {
      show(0); e.preventDefault();
    } else if (key === 'End') {
      show(total - 1); e.preventDefault();
    }
  }

  var touchX = null;
  function onTouchStart(e) { if (mode === 'slides' && e.touches.length === 1) { touchX = e.touches[0].clientX; } }
  function onTouchEnd(e) {
    if (touchX === null || mode !== 'slides') { return; }
    var dx = e.changedTouches[0].clientX - touchX;
    touchX = null;
    if (Math.abs(dx) > 50) { show(current + (dx < 0 ? 1 : -1)); }
  }

  function onHud(e) {
    var btn = e.target.closest ? e.target.closest('[data-action]') : null;
    if (!btn) { return; }
    var action = btn.getAttribute('data-action');
    if (action === 'prev') { show(current - 1); }
    else if (action === 'next') { show(current + 1); }
    else if (action === 'mode') { setMode(mode === 'slides' ? 'report' : 'slides', true); }
    else if (action === 'theme') { toggleTheme(); }
    else if (action === 'print') { window.print(); }
  }

  /* ---- inicializacao ---- */

  var storedTheme = readStore('theme');
  if (storedTheme === 'dark' || storedTheme === 'light') { root.setAttribute('data-theme', storedTheme); }

  if (counterTotal) { counterTotal.textContent = String(total); }
  buildToc();

  var params = /[?&]mode=(slides|report)\b/.exec(window.location.search || '');
  var initial = params ? params[1] : readStore('mode');
  if (initial !== 'slides' && initial !== 'report') {
    initial = window.innerWidth >= 900 && window.innerHeight >= 500 ? 'slides' : 'report';
  }

  var fromHash = indexFromHash();
  current = fromHash === null ? 0 : fromHash;
  if (total) { slides[current].classList.add('is-current'); }
  setMode(initial, false);

  window.addEventListener('resize', function () { if (mode === 'slides') { fit(); } });
  window.addEventListener('beforeprint', function () { if (!fitted) { fitSlides(); } });
  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('hashchange', function () {
    var i = indexFromHash();
    if (i !== null && mode === 'slides') { show(i, false); }
  });
  document.addEventListener('keydown', onKey);
  document.addEventListener('touchstart', onTouchStart, { passive: true });
  document.addEventListener('touchend', onTouchEnd, { passive: true });
  var hud = document.querySelector('.hud');
  if (hud) { hud.addEventListener('click', onHud); }
  if (tocList) {
    tocList.addEventListener('click', function (e) {
      var a = e.target.closest ? e.target.closest('a') : null;
      if (!a) { return; }
      var i = slides.indexOf(document.getElementById(a.getAttribute('href').slice(1)));
      if (i >= 0 && mode === 'slides') { e.preventDefault(); show(i); }
    });
  }
}());
