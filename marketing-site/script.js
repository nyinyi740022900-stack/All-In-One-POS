// All In One POS — marketing site interactions:
// scroll-reveal, parallax blobs, sticky-nav shadow, and the footer year.

const yearEl = document.getElementById('year');
if (yearEl) yearEl.textContent = new Date().getFullYear();

// Language switch + Viber support FAB. Every translatable element carries
// its authored Myanmar markup as normal content plus a data-i18n-en
// attribute (an HTML string, so inline tags like <strong> survive
// translation). The Myanmar version is cached from the live DOM on first
// run rather than duplicated in markup, so authoring a page only means
// adding the English string.
(function i18n() {
  const STORAGE_KEY = 'aiopos-lang';
  const VIBER_HREF = 'viber://chat?number=959740022900';

  // Mount before we snapshot [data-i18n-en] so the FAB label is included.
  if (!document.querySelector('.viber-fab')) {
    const fab = document.createElement('a');
    fab.className = 'viber-fab';
    fab.href = VIBER_HREF;
    fab.setAttribute('aria-label', 'Viber မှ ဆက်သွယ်ရန်');
    const scriptEl = document.querySelector('script[src*="script.js"]');
    const iconSrc = scriptEl
      ? new URL('assets/viber-icon.png', scriptEl.src.replace(/script\.js(?:\?.*)?$/, '')).href
      : 'assets/viber-icon.png';
    fab.innerHTML =
      '<img class="viber-fab-icon" src="' + iconSrc + '" width="56" height="56" alt="" />' +
      '<span class="viber-fab-label" data-i18n-en="Chat on Viber">Viber မှ ဆက်သွယ်ရန်</span>';
    document.body.appendChild(fab);
  }

  if (!document.querySelector('.viber-toast')) {
    const toast = document.createElement('div');
    toast.className = 'viber-toast';
    toast.setAttribute('role', 'status');
    document.body.appendChild(toast);
  }

  const nodes = document.querySelectorAll('[data-i18n-en]');
  nodes.forEach((el) => {
    if (!el.dataset.i18nMy) el.dataset.i18nMy = el.innerHTML;
  });

  function apply(lang) {
    document.documentElement.setAttribute('lang', lang);
    nodes.forEach((el) => {
      el.innerHTML = lang === 'en' ? el.dataset.i18nEn : el.dataset.i18nMy;
    });
    document.querySelectorAll('.lang-option').forEach((btn) => {
      const on = btn.dataset.lang === lang;
      btn.classList.toggle('is-active', on);
      btn.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    document.querySelectorAll('.lang-switch').forEach((group) => {
      group.setAttribute('aria-label', lang === 'en' ? 'Language' : 'ဘာသာစကား');
    });
    document.querySelectorAll('.viber-fab').forEach((fab) => {
      fab.setAttribute(
        'aria-label',
        lang === 'en' ? 'Chat on Viber' : 'Viber မှ ဆက်သွယ်ရန်',
      );
    });
  }

  let current = 'my';
  try {
    current = localStorage.getItem(STORAGE_KEY) || 'my';
  } catch (_) {}
  apply(current);

  document.querySelectorAll('.lang-option').forEach((btn) => {
    btn.addEventListener('click', () => {
      if (btn.dataset.lang === current) return;
      current = btn.dataset.lang;
      apply(current);
      try {
        localStorage.setItem(STORAGE_KEY, current);
      } catch (_) {}
    });
  });

  // Desktop browsers (Mac Safari especially) treat viber:// as an invalid
  // address and show a blocking alert. Phones/tablets can still open Viber.
  const VIBER_NUMBER = '09740022900';

  function viberOpensNatively() {
    const ua = navigator.userAgent || '';
    if (/Android|iPhone|iPod/i.test(ua)) return true;
    if (navigator.maxTouchPoints > 1 && /Macintosh|iPad/i.test(ua)) return true;
    return false;
  }

  function copyViberNumber() {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard
        .writeText(VIBER_NUMBER)
        .then(function () {
          return true;
        })
        .catch(function () {
          return fallbackCopy();
        });
    }
    return Promise.resolve(fallbackCopy());
  }

  function fallbackCopy() {
    try {
      const ta = document.createElement('textarea');
      ta.value = VIBER_NUMBER;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      document.body.appendChild(ta);
      ta.select();
      const ok = document.execCommand('copy');
      document.body.removeChild(ta);
      return !!ok;
    } catch (_) {
      return false;
    }
  }

  function showViberToast() {
    const toast = document.querySelector('.viber-toast');
    if (!toast) return;
    const en = document.documentElement.getAttribute('lang') === 'en';
    toast.textContent = en
      ? 'Viber number copied: ' + VIBER_NUMBER
      : 'Viber နံပါတ် ကူးပြီးပါပြီ — ' + VIBER_NUMBER;
    toast.classList.add('is-on');
    clearTimeout(showViberToast._hide);
    showViberToast._hide = setTimeout(function () {
      toast.classList.remove('is-on');
    }, 2800);
  }

  document.addEventListener('click', function (e) {
    const a = e.target.closest('a[href^="viber:"]');
    if (!a || viberOpensNatively()) return;
    e.preventDefault();
    copyViberNumber().then(function (ok) {
      if (ok) showViberToast();
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

// Reveal-on-scroll — GSAP's ScrollTrigger.batch gives free staggering (a
// row of cards settles in one-after-another instead of all at once) when
// it's loaded (currently just index.html); every other page keeps this
// plain IntersectionObserver, which does the same job unstaggered. Either
// way the actual visual (opacity/transform) stays owned by the existing
// .reveal/.in-view CSS, so nothing downstream needs to know which engine
// ran — reduced-motion's CSS override in styles.css covers both.
const revealEls = document.querySelectorAll('.reveal');
if (window.gsap && window.ScrollTrigger) {
  gsap.registerPlugin(ScrollTrigger);
  // Deferred to the window 'load' event on purpose: this runs from a
  // <script> right before </body>, which fires as soon as HTML parsing
  // finishes — long before every below-the-fold photo has loaded and
  // settled its box height. Computing batch start positions against that
  // still-growing layout puts them in the wrong place (usually far too
  // early), so the trigger fires once immediately and self-destroys
  // (once: true) without ever reaching the real threshold. Waiting for
  // 'load' means every image has its final size before anything measures
  // scroll position against it.
  const setUpBatch = () => {
    ScrollTrigger.batch('.reveal', {
      start: 'top 88%',
      once: true,
      // Plain setTimeout rather than gsap.delayedCall: this is a one-shot
      // "add a class N ms later" stagger, not an interpolated tween, so it
      // has no reason to depend on GSAP's rAF-driven ticker (which a
      // backgrounded/inactive tab can pause outright, silently stalling
      // every queued delayedCall along with it).
      onEnter: (batch) => {
        batch.forEach((el, i) => {
          setTimeout(() => el.classList.add('in-view'), i * 80);
        });
      },
    });
  };
  // 'load' may have already fired by the time this script (at the end of
  // the body) runs — cached assets on a repeat visit make that the common
  // case, not the edge case — and a listener attached after the fact never
  // gets called. readyState 'complete' is the same signal after the fact.
  if (document.readyState === 'complete') {
    setUpBatch();
  } else {
    window.addEventListener('load', setUpBatch);
  }
} else {
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
}

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
