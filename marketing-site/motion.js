// index.html-only motion layer, built on GSAP + ScrollTrigger (script.js's
// reveal already upgrades itself when these are present — this file adds
// the two effects that need a real timeline/pointer tracking: the "How It
// Works" progress line, and magnetic/tilt hover on cards and buttons.
// Everything here is skipped under prefers-reduced-motion, and skipped
// entirely (via the guard below) if GSAP failed to load for any reason —
// the page still works, it just loses the extra motion.

if (window.gsap && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
  if (window.ScrollTrigger) gsap.registerPlugin(ScrollTrigger);

  // "How It Works" progress line — a second line layered on the existing
  // faint track, scaling in from the top as the reader scrolls past each
  // step, so the line itself narrates progress instead of just decorating.
  // The trigger itself is deferred past 'load' for the same reason as
  // script.js's reveal batch: measuring '.steps' position against a page
  // that still has below-the-fold images pending gives it the wrong
  // start/end, and a scrub trigger stays wrong for the rest of the visit
  // rather than self-destructing the way a once:true trigger does.
  const stepsLine = document.querySelector('.steps-line');
  if (stepsLine && window.ScrollTrigger) {
    const fill = document.createElement('div');
    fill.className = 'steps-line-fill';
    fill.setAttribute('aria-hidden', 'true');
    stepsLine.insertAdjacentElement('afterend', fill);
    const setUpStepsLine = () => {
      gsap.to(fill, {
        scaleY: 1,
        ease: 'none',
        scrollTrigger: {
          trigger: '.steps',
          start: 'top 70%',
          end: 'bottom 65%',
          scrub: 0.6,
        },
      });
    };
    if (document.readyState === 'complete') {
      setUpStepsLine();
    } else {
      window.addEventListener('load', setUpStepsLine);
    }
  }

  // Magnetic buttons — the primary CTAs pull toward the pointer within a
  // small radius, matching the modern site's-alive feel this pass is for.
  const magnetize = (selector, strength) => {
    document.querySelectorAll(selector).forEach((el) => {
      const xTo = gsap.quickTo(el, 'x', { duration: 0.4, ease: 'power3' });
      const yTo = gsap.quickTo(el, 'y', { duration: 0.4, ease: 'power3' });
      el.addEventListener('mousemove', (e) => {
        const r = el.getBoundingClientRect();
        xTo(((e.clientX - r.left) / r.width - 0.5) * strength);
        yTo(((e.clientY - r.top) / r.height - 0.5) * strength);
      });
      el.addEventListener('mouseleave', () => {
        xTo(0);
        yTo(0);
      });
    });
  };
  magnetize('.hero-cta .btn, .download-card a.btn', 10);

  // Tilt — hub cards and plan cards get a subtle 3D lean toward the
  // pointer, plus the lift the CSS :hover rule already used to own; once
  // this runs, GSAP's inline transform is what wins on mouse devices, so
  // the lift moves here rather than staying split across two engines.
  document.querySelectorAll('.hub-card, .plan-card').forEach((card) => {
    card.style.transformPerspective = '800px';
    const rotX = gsap.quickTo(card, 'rotationX', { duration: 0.4, ease: 'power2' });
    const rotY = gsap.quickTo(card, 'rotationY', { duration: 0.4, ease: 'power2' });
    const liftY = gsap.quickTo(card, 'y', { duration: 0.4, ease: 'power2' });
    card.addEventListener('mousemove', (e) => {
      const r = card.getBoundingClientRect();
      const px = (e.clientX - r.left) / r.width - 0.5;
      const py = (e.clientY - r.top) / r.height - 0.5;
      rotY(px * 8);
      rotX(-py * 8);
    });
    card.addEventListener('mouseenter', () => liftY(-4));
    card.addEventListener('mouseleave', () => {
      rotX(0);
      rotY(0);
      liftY(0);
    });
  });
}
