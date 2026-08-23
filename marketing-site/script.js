// All In One POS — marketing site interactions:
// scroll-reveal, parallax blobs, sticky-nav shadow, and the footer year.

const yearEl = document.getElementById('year');
if (yearEl) yearEl.textContent = new Date().getFullYear();

// Language toggle — every translatable element carries its authored
// Myanmar markup as normal content plus a data-i18n-en attribute (an HTML
// string, so inline tags like <strong> survive translation). The Myanmar
// version is cached from the live DOM on first run rather than duplicated
// in markup, so authoring a page only means adding the English string.
(function i18n() {
  const STORAGE_KEY = 'aiopos-lang';
  const nodes = document.querySelectorAll('[data-i18n-en]');
  nodes.forEach((el) => {
    if (!el.dataset.i18nMy) el.dataset.i18nMy = el.innerHTML;
  });

  function apply(lang) {
    document.documentElement.setAttribute('lang', lang);
    nodes.forEach((el) => {
      el.innerHTML = lang === 'en' ? el.dataset.i18nEn : el.dataset.i18nMy;
    });
    document.querySelectorAll('.lang-toggle').forEach((btn) => {
      btn.textContent = lang === 'en' ? 'မြန်မာ' : 'English';
      btn.setAttribute('aria-label', lang === 'en' ? 'မြန်မာဘာသာသို့ ပြောင်းရန်' : 'Switch to English');
    });
  }

  let current = 'my';
  try {
    current = localStorage.getItem(STORAGE_KEY) || 'my';
  } catch (_) {}
  apply(current);

  document.querySelectorAll('.lang-toggle').forEach((btn) => {
    btn.addEventListener('click', () => {
      current = current === 'en' ? 'my' : 'en';
      apply(current);
      try {
        localStorage.setItem(STORAGE_KEY, current);
      } catch (_) {}
    });
  });
})();

// Feature-tutorial screenshot placeholders: a .phone-shot whose <img> 404s
// (screenshot not dropped into assets/screenshots/ yet) falls back to a
// dashed placeholder via CSS instead of showing a broken-image icon.
document.querySelectorAll('.phone-shot img').forEach((img) => {
  img.addEventListener('error', () => img.closest('.phone-shot')?.classList.add('img-missing'));
  // <img> starts loading during HTML parsing, before this script (loaded at
  // the end of body) runs — so a 404 may fire its 'error' event before the
  // listener above ever attaches. Catch that already-failed case here: a
  // fully "complete" image with naturalWidth 0 failed to load.
  if (img.complete && img.naturalWidth === 0) {
    img.closest('.phone-shot')?.classList.add('img-missing');
  }
});

const nav = document.getElementById('nav');
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

window.addEventListener(
  'scroll',
  () => nav.classList.toggle('scrolled', window.scrollY > 8),
  { passive: true },
);

// Reveal-on-scroll
const revealEls = document.querySelectorAll('.reveal');
const revealObserver = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('in-view');
        revealObserver.unobserve(entry.target);
      }
    }
  },
  { threshold: 0.15, rootMargin: '0px 0px -60px 0px' },
);
revealEls.forEach((el) => revealObserver.observe(el));

// Parallax: elements with [data-speed] drift vertically relative to scroll
// position, at a rate proportional to their own distance from the viewport
// center — cheap enough to run every frame without a scroll-jank problem.
if (!reduceMotion) {
  const parallaxEls = Array.from(document.querySelectorAll('[data-speed]'));
  let ticking = false;

  function updateParallax() {
    const vh = window.innerHeight;
    for (const el of parallaxEls) {
      const speed = parseFloat(el.dataset.speed) || 0;
      const rect = el.getBoundingClientRect();
      const center = rect.top + rect.height / 2 - vh / 2;
      el.style.transform = `translateY(${(-center * speed).toFixed(2)}px)`;
    }
    ticking = false;
  }

  window.addEventListener(
    'scroll',
    () => {
      if (!ticking) {
        window.requestAnimationFrame(updateParallax);
        ticking = true;
      }
    },
    { passive: true },
  );
  window.addEventListener('resize', updateParallax);
  updateParallax();
}
