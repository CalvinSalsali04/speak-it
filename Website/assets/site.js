/* ==========================================================================
   Speak It — site behaviour
   Plain ES2020, no dependencies. Everything here is progressive: with
   JavaScript disabled the page still reads and the download links still work.
   ========================================================================== */

(function () {
  'use strict';

  /* --------------------------------------------------------------------------
     THE ONE VALUE TO CHANGE AT LAUNCH.
     Speak It has no public App Store listing yet, so this points at the site's
     own download page. Replace it with the real product URL and then regenerate
     the QR code so the two never disagree:

         python3 tools/make_qr.py "<the same URL>" assets/img/qr.svg

     See Website/README.md.
     -------------------------------------------------------------------------- */
  const APP_STORE_URL = 'https://speakit.app';

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ------------------------------------------------------------ download --- */

  document.querySelectorAll('[data-appstore]').forEach((el) => {
    el.href = APP_STORE_URL;
  });
  document.querySelectorAll('[data-appstore-url]').forEach((el) => {
    el.textContent = APP_STORE_URL.replace(/^https?:\/\//, '');
  });

  /* ----------------------------------------------------------------- nav --- */

  const nav = document.getElementById('nav');
  const onScroll = () => nav.classList.toggle('is-scrolled', window.scrollY > 8);
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  /* --------------------------------------------------------------- modal --- */

  const modal = document.getElementById('download');
  const panel = modal.querySelector('.modal__panel');
  let lastFocused = null;

  const focusables = () =>
    Array.from(
      panel.querySelectorAll('a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])')
    ).filter((el) => el.offsetParent !== null);

  function openModal() {
    lastFocused = document.activeElement;
    modal.hidden = false;
    document.body.classList.add('is-locked');
    const first = focusables()[0];
    if (first) first.focus();
  }

  function closeModal() {
    modal.hidden = true;
    document.body.classList.remove('is-locked');
    if (lastFocused) lastFocused.focus();
  }

  document.querySelectorAll('[data-open-download]').forEach((el) => {
    el.addEventListener('click', openModal);
  });
  document.querySelectorAll('[data-close-download]').forEach((el) => {
    el.addEventListener('click', closeModal);
  });

  document.addEventListener('keydown', (event) => {
    if (modal.hidden) return;

    if (event.key === 'Escape') {
      closeModal();
      return;
    }

    // Keep focus inside the dialog while it is open.
    if (event.key === 'Tab') {
      const items = focusables();
      if (!items.length) return;
      const first = items[0];
      const last = items[items.length - 1];

      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
  });

  /* ------------------------------------------------------------ showcase --- */
  /* Crossfades the phone screenshot to match whichever chapter is in view.
     The mobile layout drops the sticky column, so this only runs above 860px. */

  const chapters = Array.from(document.querySelectorAll('[data-chapter]'));
  const shots = Array.from(document.querySelectorAll('[data-shot]'));
  const wide = window.matchMedia('(min-width: 861px)');

  // The three crossfade shots are stacked on top of each other, so all but the
  // visible one are hidden from assistive tech as well as from the eye.
  function setChapter(index) {
    chapters.forEach((el, i) => el.classList.toggle('is-active', i === index));
    shots.forEach((el, i) => {
      const active = i === index;
      el.classList.toggle('is-active', active);
      if (active) {
        el.removeAttribute('aria-hidden');
      } else {
        el.setAttribute('aria-hidden', 'true');
      }
    });
  }

  if (chapters.length && 'IntersectionObserver' in window) {
    const observer = new IntersectionObserver(
      (entries) => {
        if (!wide.matches) return;
        entries
          .filter((entry) => entry.isIntersecting)
          .forEach((entry) => setChapter(Number(entry.target.dataset.chapter)));
      },
      { rootMargin: '-45% 0px -45% 0px', threshold: 0 }
    );
    chapters.forEach((el) => observer.observe(el));
  }

  // Below the sticky breakpoint every chapter reads as active and every
  // screenshot is shown in sequence.
  function syncLayout() {
    if (wide.matches) {
      setChapter(0);
    } else {
      // Stacked layout: every chapter reads as active and shows its own
      // screenshot, so the crossfade stack is hidden entirely.
      chapters.forEach((el) => el.classList.add('is-active'));
      shots.forEach((el) => {
        el.classList.remove('is-active');
        el.setAttribute('aria-hidden', 'true');
      });
    }
  }
  syncLayout();
  wide.addEventListener('change', syncLayout);

  /* -------------------------------------------------- hero capture demo --- */
  /* Loops the app's real sequence: listening, the words appearing as you say
     them, then the finished row in Today. */

  const demo = document.querySelector('[data-demo]');
  if (demo) {
    const listening = demo.querySelector('[data-stage="listening"]');
    const saved = demo.querySelector('[data-stage="saved"]');
    const transcript = demo.querySelector('[data-transcript]');
    const hint = demo.querySelector('[data-hint]');

    const SENTENCE = 'Remind me to call the pharmacy before six';
    const WORDS = SENTENCE.split(' ');

    // A single timer plus a generation counter. Bumping the generation abandons
    // the pending step, so pausing and resuming never leaves a loop running.
    let generation = 0;
    let timer = null;

    function show(stage) {
      listening.hidden = stage !== 'listening';
      saved.hidden = stage !== 'saved';
    }

    // Each step returns the delay before the next one, keeping the whole
    // sequence in one readable place.
    function step(index) {
      if (index === 0) {
        show('listening');
        hint.textContent = 'Listening…';
        transcript.textContent = '';
        return 1100;
      }
      if (index <= WORDS.length) {
        transcript.textContent = WORDS.slice(0, index).join(' ');
        return 150;
      }
      if (index === WORDS.length + 1) return 700;
      if (index === WORDS.length + 2) {
        hint.textContent = 'Saving…';
        return 700;
      }
      show('saved');
      return 3400;
    }

    const TOTAL = WORDS.length + 4;

    function run(index, token) {
      if (token !== generation) return;
      const delay = step(index % TOTAL);
      timer = setTimeout(() => run(index + 1, token), delay);
    }

    function start() {
      generation += 1;
      run(0, generation);
    }

    function stop() {
      generation += 1;
      clearTimeout(timer);
    }

    if (reduceMotion) {
      // No looping animation: show the finished, most informative state.
      show('saved');
    } else {
      show('listening');
      // Only animate while the hero is actually on screen.
      const heroObserver = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => (entry.isIntersecting ? start() : stop()));
        },
        { threshold: 0.2 }
      );
      heroObserver.observe(demo);
    }
  }
})();
