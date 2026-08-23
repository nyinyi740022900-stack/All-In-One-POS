// All In One POS — marketing site interactions:
// scroll-reveal, parallax blobs, sticky-nav shadow, and the footer year.

document.getElementById('year').textContent = new Date().getFullYear();

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
