/* ==========================================================================
   Speak It — marketing site behaviour
   Four jobs: scatter and collect the spoken thoughts, keep the indicator over
   the gap in the headline, start the "what happens" sequence when it is
   reached, and run the capture demo.
   No dependencies.
   ========================================================================== */

(function () {
  'use strict';

  /* Said before anything else can fail. The "what happens" section is authored
     in its finished state and the sheet only holds it back for pages that can
     run the sequence, so this class is what gives the stylesheet permission to
     hide anything at all. A page whose script never loads keeps the assembled
     composition. */
  document.documentElement.classList.add('js');

  /* Speak It's own domain, which is also the host the app trusts for invite
     links (`ReferralService.swift`). It is what the QR encodes and what the
     download buttons open until there is a public App Store listing to point
     at — a QR that resolves to nothing is worse than one that resolves to the
     page the reader is already on. Swap both this and `tools/make_qr.py`'s
     output for the apps.apple.com URL the day the listing goes live. */
  var APP_STORE_URL = 'https://speakitapp.ca';

  /* The launch discount on Pro — half off both plans, $3.99 → $1.99 a month
     and $29.99 → $14.99 a year. `SUMMER_SALE_ENABLED` must not be true unless
     App Store Connect really is charging the sale prices — the page prints
     the numbers, and a page that disagrees with the sheet is a refund. No end
     date is published: the site states the discount, not a deadline, so the
     offer can be ended or extended without the page having lied. */
  var SUMMER_SALE_ENABLED = true;
  var REFERRALS_ENABLED = false;

  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  var RAD = Math.PI / 180;

  function clamp(n, lo, hi) { return n < lo ? lo : n > hi ? hi : n; }

  /* Progress from `a` to `b`, clamped to 0…1. */
  function ramp(p, a, b) { return clamp((p - a) / (b - a), 0, 1); }

  function easeOut(t) { return 1 - Math.pow(1 - t, 3); }

  /* A small overshoot at the end of the flight, so a bubble arrives the way a
     thought does — slightly past where it settles, then back. */
  function outBack(t) {
    var c1 = 1.24, c3 = c1 + 1;
    return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
  }

  function num(style, name, fallback) {
    var v = parseFloat(style.getPropertyValue(name));
    return isNaN(v) ? fallback : v;
  }

  /* ------------------------------------------------------------- links --- */

  document.querySelectorAll('[data-appstore]').forEach(function (el) {
    el.href = APP_STORE_URL;
  });
  document.querySelectorAll('[data-appstore-url]').forEach(function (el) {
    el.textContent = APP_STORE_URL.replace(/^https?:\/\//, '');
  });
  document.querySelectorAll('[data-sale-only]').forEach(function (el) {
    el.hidden = !SUMMER_SALE_ENABLED;
  });
  document.querySelectorAll('[data-sale-price]').forEach(function (el) {
    el.hidden = !SUMMER_SALE_ENABLED;
  });
  document.querySelectorAll('[data-after-sale]').forEach(function (el) {
    el.hidden = SUMMER_SALE_ENABLED;
  });
  document.querySelectorAll('[data-referrals]').forEach(function (el) {
    el.hidden = !REFERRALS_ENABLED;
  });

  /* ========================== the download sheet ========================== */

  /* The bar's Download opens the sheet — QR on one side, App Store on the
     other — instead of scrolling to the offer. The <dialog> does the modal
     work itself (focus, Escape, inertness of the page); this only opens it,
     closes it on a backdrop click, and keeps the page from scrolling under
     it. A browser without showModal() keeps the link's own href. */
  var dlSheet = document.querySelector('[data-download]');

  if (dlSheet && typeof dlSheet.showModal === 'function') {
    var dlOpen = function (event) {
      event.preventDefault();
      dlSheet.showModal();
      document.documentElement.classList.add('is-dl-open');
      window.requestAnimationFrame(function () { dlSheet.classList.add('is-in'); });
    };
    var dlSettle = function () {
      dlSheet.classList.remove('is-in');
      document.documentElement.classList.remove('is-dl-open');
    };
    var dlClose = function () {
      dlSettle();
      if (dlSheet.open) dlSheet.close();
    };

    document.querySelectorAll('[data-download-open]').forEach(function (el) {
      el.addEventListener('click', dlOpen);
    });
    document.querySelectorAll('[data-download-close]').forEach(function (el) {
      el.addEventListener('click', dlClose);
    });
    /* a click on the dimmed page, not on the sheet's own contents */
    dlSheet.addEventListener('click', function (event) {
      if (event.target === dlSheet) dlClose();
    });
    /* Escape arrives as `cancel` and then `close`; both end here */
    dlSheet.addEventListener('cancel', dlSettle);
    dlSheet.addEventListener('close', dlSettle);
  }

  /* ========================== the spoken thoughts ========================= */

  var opening = document.querySelector('[data-opening]');
  var field   = document.querySelector('[data-field]');
  var stage   = document.querySelector('[data-stage]');
  var orb     = document.querySelector('[data-orb]');
  var gapEl   = document.querySelector('[data-gap]');
  var heroGet = document.querySelector('[data-hero-get]');

  /* ms for the cloud to come all the way round */
  var TURN = 36000;
  /* the entrance: a beat of stillness, then one bubble every STEP ms */
  var HOLD = 240, STEP = 62, FLIGHT = 920;

  /* `collapse` is 1 while the thoughts are out and 0 once the indicator has
     swallowed them. It is a pure function of scroll position, so the whole
     sequence scrubs in both directions with no state to get out of sync. */
  var collapse = 1;
  var born = 0;
  var RX = 0, RY = 0, CY = 0, turnScale = 1;

  /* Each bubble is read once from its authored custom properties and then
     positioned from a single transform per frame — the entrance scatter, the
     idle drift and the scroll collapse compose into one write instead of
     fighting over separate properties. */
  var bubbles = Array.prototype.slice.call(
    document.querySelectorAll('.bubble')
  ).map(function (el, n) {
    var cs = getComputedStyle(el);
    var i = num(cs, '--i', n);
    /* deterministic per-bubble character: no two bob, sway, tilt or spin the
       same way, so the cloud never falls into step with itself */
    var seed = Math.sin(i * 12.9898 + n * 78.233) * 43758.5453;
    var rnd = seed - Math.floor(seed);
    var alt = i % 2 ? 1 : -1;

    return {
      el: el,
      a:  num(cs, '--a', 0),
      rr: num(cs, '--rr', 1),
      s:  num(cs, '--s', 1),
      i:  i,
      bobA:  7 + rnd * 6,           /* how far it bobs */
      bobS:  0.5 + rnd * 0.45,      /* how fast */
      bobP:  rnd * 6.28,            /* where in the bob it starts */
      swayA: 4 + (1 - rnd) * 5,
      swayS: 0.32 + rnd * 0.3,
      swayP: (1 - rnd) * 6.28,
      tilt:  alt * (0.8 + rnd * 1.9),
      spin:  alt * (26 + rnd * 30)  /* how much it turns on the way out */
    };
  });

  /* The indicator is fixed to the viewport, so it has to be moved to wherever
     the gap in the headline happens to be — the type decides, and no viewport
     can leave it sitting on a line of copy. The cloud rides with it. */
  function dockStage() {
    if (!stage || !gapEl) return;
    var r = gapEl.getBoundingClientRect();
    CY = r.top + r.height / 2 - window.innerHeight / 2;
    stage.style.setProperty('--gap-y', CY.toFixed(1) + 'px');
  }

  /* The bar's height, published for anything that has to sit clear of it. It is
     measured rather than written down because it changes with the pointer (a
     touch target is taller than a cursor's), with the safe area on an installed
     page, and with the reader's text size. */
  var topbar = document.querySelector('.topbar');

  function measureBar() {
    if (!topbar) return;
    document.documentElement.style
      .setProperty('--bar', Math.round(topbar.getBoundingClientRect().height) + 'px');
  }

  /* The widest the cloud can be drawn and still have every thought on it
     readable — the point at which the one nearest three o'clock would touch the
     edge of the screen. A thought is a sentence somebody said, and half a
     sentence is not one, so on a narrow screen this is what decides the width
     rather than a fraction of the viewport.

     It is asked of the bubbles rather than assumed: their widths come from
     their own text at whatever size the tier is drawing them, `--rr` moves each
     one in or out, and a bubble near twelve needs no horizontal room at all,
     which is what the cosine is for. `offsetWidth` is the laid-out width, so it
     is not disturbed by the transform paintField writes every frame. */
  function cloudBounds(halfWidth, margin) {
    /* the outermost ring, at the spacing .orb__ring is given: .73 of the
       indicator across, scaled by .84 + .13 per ring plus a little breath */
    var ring = orb ? (orb.offsetWidth * 0.73 / 2) * 1.22 : 0;

    var readable = Infinity, clear = 0;

    for (var n = 0; n < bubbles.length; n++) {
      var b = bubbles[n];
      /* the narrow tiers hide every other one; a bubble that is not drawn has
         no opinion about how wide the cloud may be */
      if (b.el.offsetParent === null) continue;

      /* Every one of them, wherever it was authored: the cloud turns all the
         way round every 36 seconds, so each bubble takes its turn at the widest
         point of the ellipse and each has to hold up when it gets there.
         `offsetWidth` is the laid-out width, so it is not disturbed by the
         transform paintField writes every frame. */
      var half = (b.el.offsetWidth * b.s) / 2;

      readable = Math.min(readable, (halfWidth - half - margin) / b.rr);
      clear    = Math.max(clear, (ring + half + 6) / b.rr);
    }

    return { readable: readable, clear: clear };
  }

  function measure() {
    measureBar();

    if (!field) return;
    var w = field.clientWidth || window.innerWidth;
    var h = field.clientHeight || window.innerHeight;

    /* An ellipse, not a circle: the viewport is wide and the headline is wide
       with it, so a circle big enough to clear the type at three and nine
       o'clock would be taller than the screen. On a phone it gets taller
       rather than wider, and carries the thoughts under the second headline
       line instead of through it. */
    if (w < 900) {
      /* and it comes in far enough to keep the thoughts whole. At 60% of the
         width the ones at three and nine o'clock hung as much as 126px off a
         402pt screen: the cloud read as a row of shapes cut in half rather than
         as things somebody had said, which is the whole point of them.

         So the width is asked of the content instead. `readable` is as wide as
         it can be drawn with every thought still ending on the screen; `clear`
         is as narrow as it can be drawn without a thought crossing the
         indicator's outer ring. The larger the type and the narrower the phone,
         the closer those two come, and on the narrowest they cross — there is
         no radius that satisfies both once a sentence is wider than the space
         beside the indicator. Where they do, keeping clear of the indicator
         wins and the last word or two of the longest thought runs past the
         edge, which reads as a cloud continuing past the frame rather than as a
         broken layout. 60% stays as the ceiling, so nothing here can push the
         cloud wider than it used to be. */
      var fit = cloudBounds(w / 2, 12);
      RX = Math.min(Math.max(fit.readable, fit.clear), w * 0.60);
      RY = h * 0.31;
    } else {
      RX = Math.min(w * 0.40, 660);
      RY = Math.min(h * 0.30, 265);
    }

    /* A bubble is the same size on a phone as on a desktop but the screen is a
       third of the width, so the same angle of tilt reads as a much bigger
       gesture. It is dialled back rather than dropped — the turn is the point. */
    turnScale = w < 900 ? 0.45 : 1;
  }

  function paintField(now) {
    if (!field || !bubbles.length) return;

    /* The clock starts on the first painted frame rather than at load, so a
       page opened in a background tab still plays its entrance when somebody
       finally looks at it instead of having quietly finished without them. */
    if (!born) born = now;

    var t = now / 1000;
    var turn = (now % TURN) / TURN * -360;
    var elapsed = now - born;

    for (var n = 0; n < bubbles.length; n++) {
      var b = bubbles[n];

      /* out of the indicator, one after another */
      var e = outBack(clamp((elapsed - HOLD - b.i * STEP) / FLIGHT, 0, 1));

      var ang = (b.a + turn) * RAD;
      var r = b.rr * collapse * e;

      var bob  = Math.sin(t * b.bobS + b.bobP);
      var sway = Math.sin(t * b.swayS + b.swayP);
      /* the drift belongs to the bubble, not to the ring, so it keeps breathing
         even once the ring has closed */
      var drift = collapse;

      var x = RX * r * Math.cos(ang) + sway * b.swayA * drift;
      var y = RY * r * Math.sin(ang) + bob * b.bobA * drift + CY * collapse;

      /* it turns on the way out and again on the way back in */
      var rot = (b.tilt + sway * 1.4
              + (1 - e) * b.spin
              + (1 - collapse) * b.spin * 0.55) * turnScale;

      var sc = b.s * (0.06 + 0.94 * e) * (0.52 + 0.48 * collapse);

      b.el.style.transform =
        'translate(' + x.toFixed(1) + 'px,' + y.toFixed(1) + 'px)' +
        ' rotate(' + rot.toFixed(2) + 'deg)' +
        ' scale(' + sc.toFixed(3) + ')';
      b.el.style.opacity = Math.min(1, e * 2.6).toFixed(3);
    }
  }

  /* All the scroll does is close the cloud and trade the scroll hint for the
     download block. Every part of it is finished by `--gone` reaching 1, which
     is the moment the pinned frame lets go — so there is no stretch of scroll
     after the sequence where nothing is happening. */
  function paintOpening(p) {
    if (!opening) return;

    collapse = Math.pow(1 - ramp(p, .02, .84), 1.5);

    var show = easeOut(ramp(p, .44, .76));

    opening.style.setProperty('--p', p.toFixed(4));
    opening.style.setProperty('--fade', (1 - ramp(p, .58, .88)).toFixed(4));
    opening.style.setProperty('--tell', (1 - ramp(p, .02, .18)).toFixed(4));
    opening.style.setProperty('--show', show.toFixed(4));

    if (stage) stage.style.setProperty('--gone', ramp(p, .82, 1).toFixed(4));
    if (heroGet) heroGet.classList.toggle('is-ready', show > .5);
  }

  /* The finished state of the sequence: nothing left in orbit, no hint, and the
     download block already in place. It is also the whole of the opening when
     motion is reduced — there the indicator stays, because the gap in the
     headline is cut for it and an empty hole is not a calmer hero. */
  function settleOpening() {
    if (!opening) return;
    collapse = 0;
    opening.style.setProperty('--fade', '0');
    opening.style.setProperty('--tell', '0');
    opening.style.setProperty('--show', '1');
    if (heroGet) heroGet.classList.add('is-ready');
  }

  function restOpening() {
    settleOpening();
    if (stage) stage.style.setProperty('--gone', '1');
  }

  /* Reads the opening's position and paints the matching frame. Called from
     the animation loop and from scroll, so the page is correct even when it is
     opened straight at an anchor and no frame has run yet. */
  function syncOpening() {
    if (!opening) return;

    var box = opening.getBoundingClientRect();
    var span = opening.offsetHeight - window.innerHeight;

    document.body.classList.toggle('is-past-opening', box.bottom <= 0);

    if (box.bottom > 0 && box.top < window.innerHeight) {
      dockStage();
      if (reduceMotion.matches) {
        settleOpening();
        if (stage) stage.style.setProperty('--gone', '0');
      } else {
        paintOpening(span > 0 ? clamp(-box.top / span, 0, 1) : 1);
      }
    } else if (box.bottom <= 0) {
      restOpening();
    }
  }

  /* ============================== what happens ============================ */

  /* The sequence is entirely in the stylesheet — every element carries its own
     animation, paused on its opening frame. All this does is let them run,
     once, the first time the composition is on screen. Playing it on arrival
     rather than on a scroll fraction means it is never half-finished: it either
     has not started or it is telling its story at the pace it was authored at.

     Nothing here re-runs it. A section that replays every time it is scrolled
     past is a section that cannot be re-read. */
  var scene = document.querySelector('[data-scene]');

  if (scene) {
    if (reduceMotion.matches || !('IntersectionObserver' in window)) {
      scene.classList.add('is-live');
    } else {
      var sceneWatch = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add('is-live');
          sceneWatch.unobserve(entry.target);
        });
      }, { threshold: 0.28 });
      sceneWatch.observe(scene);
    }
  }

  /* The two dates on the cards are the app's own formats, resolved against the
     reader's clock and locale rather than written into the markup. A marketing
     page showing a reminder for a date eight months ago is the one thing that
     would make the composition read as a mock-up. The HTML carries a plausible
     value so the cards are never empty if this does not run. */
  function appDate(date, withTime) {
    var day = date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    if (!withTime) return day;
    return day + ', ' + date.toLocaleTimeString(undefined, {
      hour: 'numeric', minute: '2-digit'
    });
  }

  var tomorrowAtFive = new Date();
  tomorrowAtFive.setDate(tomorrowAtFive.getDate() + 1);
  tomorrowAtFive.setHours(17, 0, 0, 0);

  document.querySelectorAll('[data-tomorrow]').forEach(function (el) {
    el.textContent = appDate(tomorrowAtFive, true);
  });
  document.querySelectorAll('[data-today-date]').forEach(function (el) {
    el.textContent = appDate(new Date(), false);
  });

  /* ============================== two screens ============================= */

  /* A few pixels of drift between the two devices as the section passes, so the
     pair has depth without anything appearing to move. The travel is small on
     purpose: at more than about twenty pixels it stops reading as depth and
     starts reading as the page being uneven. */
  var floats = Array.prototype.slice.call(document.querySelectorAll('[data-parallax]'));

  function paintFloats() {
    if (!floats.length || reduceMotion.matches) return;
    var mid = window.innerHeight / 2;

    for (var n = 0; n < floats.length; n++) {
      var el = floats[n];
      var box = el.getBoundingClientRect();
      if (box.bottom < 0 || box.top > window.innerHeight) continue;
      /* -1 … 1 across the approach and the exit */
      var t = clamp((box.top + box.height / 2 - mid) / (window.innerHeight), -1, 1);
      el.style.setProperty('--py',
        (t * 18 * parseFloat(el.dataset.parallax || 1)).toFixed(1) + 'px');
    }
  }

  /* -------------------------------------------------- the indicator ------ */

  /* It breathes on its own and reacts to how hard the page is being scrolled,
     the same way it reacts to input level inside the app. Energy is eased
     rather than tracked directly so a flick of the wheel reads as a swell,
     not a jolt. */
  function animate() {
    var lastY = window.scrollY;
    var energy = 0;

    function frame(now) {
      var y = window.scrollY;
      var delta = Math.min(Math.abs(y - lastY) / 26, 1);
      lastY = y;

      energy += (delta - energy) * (delta > energy ? 0.22 : 0.055);

      if (orb) {
        var breath = (Math.sin(now / 1500) + 1) / 2;
        orb.style.setProperty('--spread', (0.05 * breath + energy * 0.1).toFixed(4));
        orb.style.setProperty('--cs', (1 + breath * 0.03 + energy * 0.1).toFixed(4));
        orb.style.setProperty('--level', energy.toFixed(3));
      }

      syncOpening();
      paintField(now);
      paintMic(now);

      window.requestAnimationFrame(frame);
    }

    window.requestAnimationFrame(frame);
  }

  function still() {
    if (orb) {
      orb.style.setProperty('--spread', '0.045');
      orb.style.setProperty('--cs', '1');
      orb.style.setProperty('--level', '0');
    }
    dockStage();
    syncOpening();
  }

  var running = false;
  function applyMotion() {
    if (reduceMotion.matches) { still(); return; }
    if (running) return;
    running = true;
    measure();
    animate();
  }

  /* --------------------------------------------------------------- sync --- */

  var docEl = document.documentElement;

  function sync() {
    var span = docEl.scrollHeight - window.innerHeight;
    docEl.style.setProperty('--sp', span > 0 ? (window.scrollY / span).toFixed(4) : '1');

    syncOpening();
    /* Scroll and resize repaint the cloud themselves. A frame loop that is
       paused — a background tab, a throttled device — must not be the only
       thing that can place a bubble. */
    if (!reduceMotion.matches) paintField(performance.now());
    paintFloats();
  }

  window.addEventListener('scroll', sync, { passive: true });
  window.addEventListener('resize', function () { measure(); sync(); });
  /* an anchored URL can land the page after the first paint */
  window.addEventListener('load', function () { measure(); sync(); });

  measure();
  applyMotion();
  reduceMotion.addEventListener('change', applyMotion);
  sync();

  /* ========================== reading a thought =========================== */

  /* A cut-down stand-in for the on-device classifier: enough rules to show the
     Today / Memory split honestly, and few enough to read in one sitting.
     Everything here is string matching in the page. */

  /* A sentence can name a time more than once — “Thursday at six”, “tomorrow
     morning” — so the source is written out once and compiled twice: `WHEN` to
     ask the question and quote the answer, `WHEN_ALL` to take every mention of
     it out of the row's title, where the time has its own column. */
  var WHEN_SRC =
    '\\b(today|tonight|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday' +
    '|next week|this week|this weekend|weekend|morning|afternoon|evening' +
    '|at (one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)' +
    '|at \\d{1,2}(:\\d{2})?\\s?(am|pm)?|\\d{1,2}:\\d{2}|\\d{1,2}\\s?(am|pm)' +
    '|before the \\d{1,2}(st|nd|rd|th)|on the \\d{1,2}(st|nd|rd|th)' +
    '|by \\w+day|in an hour|later)\\b';
  var WHEN = new RegExp(WHEN_SRC, 'i');
  var WHEN_ALL = new RegExp(WHEN_SRC, 'gi');

  var DOING = /\b(call|book|buy|email|send|pay|renew|chase|collect|pick up|cancel|move|ask|tell|check|fix|order|return|post|drop off|reply|confirm|reschedule|remind me)\b/i;
  var IDEA = /\b(idea|what if|we should|pitch|concept|maybe we|it would be good if)\b/i;
  var REF = /(\+?\d[\d\s().-]{6,}\d|\b[\w.+-]+@[\w-]+\.[\w.]+\b|\bcode\b|\bcodes\b|\bpassword\b|\bfloor\b|\blevel \d|\brow [a-z]\b|\bterminal \d)/i;
  /* The last alternative is a plain fact about a named person — "Daniel prefers
     oat milk" carries no possessive and no pronoun, and without it the demo
     filed the page's own example as an uncategorised note. */
  var PERSON = /(\b[A-Z][a-z]+['’]s\b|\bDr\.?\s[A-Z]|\bhis\b|\bher\b|\btheir\b|\bthey\b|\bpartner\b|\bbirthday\b|^[A-Z][a-z]+\s+(?:prefers|likes|loves|hates|avoids|drinks|works|lives|studies|is|was|has|used to)\b)/;

  /* A place instead of a time. The app parses arrivals and departures against
     the saved Home and Work places, so the demo has to answer "when I get
     home" with a place trigger rather than filing it as an undated note —
     which is what it used to do, and it is the one thing on the page most
     likely to be typed in to test. */
  var WHERE = new RegExp(
    '\\bwhen (?:i|we) (?:get|getting|arrive|arriving|reach|am|\'m) ' +
    '(?:to |at |in )?(home|the house|work|the office)\\b' +
    '|\\bwhen (?:i|we) (?:leave|leaving|get out of) (?:the )?(home|house|work|office)\\b', 'i');

  var FILLER = /^(please\s+)?(remind me( to| that)?|remember( that| to)?|note to self[,:]?|make a note( that| of)?|i need to|i should|make sure( i| to)?|don'?t forget( to| that)?|jot down)\s+/i;

  /* The app's own category · type pairs, taken from `ItemCategory` and
     `ItemType` — there is no Health, Travel or Errand in either, and a row that
     prints one is describing an app the reader is not about to download. A row
     whose category and type are the same word prints the word once, which is
     what CapturedItemRow.secondaryText does. */
  var KINDS = [
    { re: /\b(buy|shop|shopping|milk|groceries|order|pick up|collect)\b/i,             meta: 'Shopping' },
    { re: /\b(call|text|email|reply|message|ask|tell)\b/i,                             meta: 'People · Person follow-up' },
    { re: /\b(invoice|deck|q[1-4]|meeting|standup|client|report|deadline)\b/i,         meta: 'Work · Task' },
    { re: /\b(doctor|dentist|pharmacy|prescription|surgery|clinic|gp|appointment)\b/i, meta: 'Personal · Task' }
  ];

  function kindFor(said) {
    for (var n = 0; n < KINDS.length; n++) {
      if (KINDS[n].re.test(said)) return KINDS[n].meta;
    }
    return 'Personal · Task';
  }

  var HOURS = {
    one: 1, two: 2, three: 3, four: 4, five: 5, six: 6,
    seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12
  };
  var DAYS = {
    monday: 'Mon', tuesday: 'Tue', wednesday: 'Wed', thursday: 'Thu',
    friday: 'Fri', saturday: 'Sat', sunday: 'Sun'
  };

  /* The row's time column, from the way the sentence already put it. */
  function timeLabel(said) {
    var parts = [];

    var day = said.match(/\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/i);
    var date = said.match(/\b(before|on|by)\s+the\s+(\d{1,2})(st|nd|rd|th)\b/i);
    if (day) parts.push(DAYS[day[1].toLowerCase()]);
    else if (date) parts.push((/before/i.test(date[1]) ? 'By the ' : 'On the ') + date[2] + date[3]);
    else if (/\btomorrow\b/i.test(said)) parts.push('Tomorrow');
    else if (/\btonight\b/i.test(said)) parts.push('Tonight');

    var clock = said.match(/\b(\d{1,2}):(\d{2})\b/);
    var ampm = said.match(/\b(\d{1,2})\s?(am|pm)\b/i);
    var spoken = said.match(/\bat\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d{1,2})\b/i);

    if (clock) {
      var h = parseInt(clock[1], 10);
      var suffix = h >= 12 ? 'PM' : 'AM';
      parts.push(((h % 12) || 12) + ':' + clock[2] + ' ' + suffix);
    } else if (ampm) {
      parts.push(parseInt(ampm[1], 10) + ':00 ' + ampm[2].toUpperCase());
    } else if (spoken) {
      var word = spoken[1].toLowerCase();
      var hour = HOURS[word] || parseInt(word, 10);
      if (hour) parts.push(hour + ':00 ' + (hour >= 8 && hour < 12 ? 'AM' : 'PM'));
    } else if (/\bmorning\b/i.test(said)) parts.push('9:00 AM');
    else if (/\bafternoon\b/i.test(said)) parts.push('2:00 PM');
    else if (/\bevening\b/i.test(said)) parts.push('6:00 PM');

    /* "Tomorrow, 5:00 PM" — the app's own row separates the day from the hour
       with a comma, and the two halves run together without it. */
    return parts.length ? parts.join(', ') : 'Today';
  }

  function shortDate() {
    return new Date().toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  }

  /* "home" and "the house" are the same saved place; so are "work" and "the
     office". The app resolves both to the one the person configured. */
  function placeName(match) {
    var word = (match[1] || match[2] || '').toLowerCase();
    return /work|office/.test(word) ? 'Work' : 'Home';
  }

  function classify(said) {
    var where = said.match(WHERE);
    if (where) {
      var place = placeName(where);
      var leaving = /\bleav|\bget out of\b/i.test(where[0]);
      return {
        today: true,
        dest: 'Today',
        section: 'Now',
        meta: kindFor(said),
        time: place,
        why: 'You named a place rather than a time, so it waits for the place: '
           + 'next time you ' + (leaving ? 'leave ' : 'arrive at ') + place
           + '. Set Home and Work once and every reminder that mentions them follows.'
      };
    }

    if (WHEN.test(said) && (DOING.test(said) || !IDEA.test(said))) {
      return {
        today: true,
        dest: 'Today',
        section: 'Now',
        meta: kindFor(said),
        time: timeLabel(said),
        why: 'You named a time — “' + said.match(WHEN)[0] + '” — so it becomes a dated task with a reminder.'
      };
    }
    if (DOING.test(said)) {
      return {
        today: true,
        dest: 'Today',
        section: 'When you have time',
        meta: kindFor(said),
        time: 'No date',
        why: 'It is something to do rather than something to know, so it waits in Today until you have a spare moment.'
      };
    }
    if (IDEA.test(said)) {
      return {
        today: false, dest: 'Memory · Ideas', section: 'Recently added',
        meta: 'Ideas · Idea', time: shortDate(),
        why: 'Nothing to act on, but worth keeping. Ideas stay in Memory until you go looking.'
      };
    }
    if (REF.test(said)) {
      return {
        today: false, dest: 'Memory · Reference', section: 'Recently added',
        meta: 'Note', time: shortDate(),
        why: 'A detail you will want to look up rather than do: numbers, codes and places live in Reference.'
      };
    }
    if (PERSON.test(said)) {
      return {
        today: false, dest: 'Memory · People', section: 'Recently added',
        meta: 'People · Note', time: shortDate(),
        why: 'Something about someone. It is filed under People so it surfaces next time they come up.'
      };
    }
    return {
      today: false, dest: 'Memory', section: 'Recently added',
      meta: 'Note', time: shortDate(),
      why: 'No action and no date, so it is kept as a note and stays searchable by these exact words.'
    };
  }

  function titleFor(text) {
    var title = text.trim()
      .replace(FILLER, '')
      .replace(/\s+/g, ' ')
      .replace(/[.\s]+$/, '');

    /* The date belongs on the row's time, not in its title — every mention of
       it, or “Thursday at six” leaves “at six” behind. A named place is the
       same: it is the trigger, it is already in the trailing column, and
       leaving it in gives the row the title “Take the bins out when I get
       home” beside a column reading “Home”. */
    title = title.replace(WHEN_ALL, '').replace(/\s+(about|for|at|on|by)\s*$/i, '').trim();
    title = title.replace(WHERE, '').replace(/\s*,\s*$/, '').trim();
    title = title.replace(/\s{2,}/g, ' ').replace(/[,\s]+$/, '');

    if (!title) title = text.trim();
    if (title.length > 52) title = title.slice(0, 51).replace(/\s\S*$/, '') + '…';

    return title.charAt(0).toUpperCase() + title.slice(1);
  }

  /* ============================== the demo =============================== */

  var demo      = document.querySelector('[data-demo]');
  var micBtn    = document.querySelector('[data-mic]');
  var micOrb    = document.querySelector('[data-mic-orb]');
  var micLabel  = document.querySelector('[data-mic-label]');
  var stateEl   = document.querySelector('[data-demo-state]');
  var hintEl    = document.querySelector('[data-demo-hint]');
  var liveEl    = document.querySelector('[data-demo-live]');
  var typeBtn   = document.querySelector('[data-demo-type]');
  var stopBtn   = document.querySelector('[data-demo-stop]');
  var demoForm  = document.querySelector('[data-demo-form]');
  var demoInput = document.querySelector('[data-demo-input]');
  var demoOut   = document.querySelector('[data-demo-out]');

  var Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  var canListen = !!Recognition && window.isSecureContext !== false;

  var listening = false;
  var recogniser = null;
  var waiting = [];
  var failed = false;
  var finalText = '';
  var voice = 0;     /* eased "something is being said", drives the indicator */
  var lastLen = 0;

  /* The demo's own indicator: still while it waits, breathing while it listens,
     swelling as words arrive. It never claims a level it does not have — the
     energy comes from the transcript, which is the one signal the page gets. */
  function paintMic(now) {
    if (!micOrb) return;

    var breath = (Math.sin(now / 1400) + 1) / 2;
    var target = listening ? 0.28 + voice : 0;
    voice *= 0.94;

    micOrb.style.setProperty('--spread', (0.03 + breath * 0.03 + target * 0.13).toFixed(4));
    micOrb.style.setProperty('--cs', (1 + breath * 0.02 + target * 0.12).toFixed(4));
    micOrb.style.setProperty('--level', clamp(target, 0, 1).toFixed(3));
  }

  function setStage(title, hint) {
    if (stateEl) stateEl.textContent = title;
    if (hintEl) hintEl.textContent = hint;
  }

  function setLive(finalPart, interimPart) {
    if (!liveEl) return;
    liveEl.textContent = '';
    if (finalPart) liveEl.appendChild(document.createTextNode(finalPart));
    if (interimPart) {
      var span = document.createElement('span');
      span.className = 'is-interim';
      span.textContent = (finalPart ? ' ' : '') + interimPart;
      liveEl.appendChild(span);
    }
  }

  function showForm(focus) {
    if (!demoForm) return;
    demoForm.hidden = false;
    if (typeBtn) typeBtn.hidden = true;
    if (focus && demoInput) demoInput.focus();
  }

  /* Putting the controls back is a separate job from saying why: `onerror`
     explains the failure and `onend` follows immediately after it, so the two
     must not both write the copy or the explanation never survives long enough
     to be read. */
  function idleControls() {
    listening = false;
    if (demo) demo.classList.remove('is-listening');
    if (micOrb) micOrb.dataset.state = 'calm';
    if (micLabel) micLabel.textContent = 'Start listening';
    if (stopBtn) stopBtn.hidden = true;
  }

  function idle(title, hint) {
    idleControls();
    setStage(title || 'Tap to speak', hint || 'Say anything you don’t want to forget.');
  }

  /* -------------------------------------------------------- the verdict -- */

  var NOTE_GLYPH =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" ' +
    'stroke-linecap="round"><rect x="4" y="3.5" width="16" height="17" rx="3"/>' +
    '<path d="M8 9h8M8 13h8M8 17h5"/></svg>';

  function capture(text) {
    if (!demoOut) return;

    var said = (text || '').trim();
    if (!said) { if (demoInput) demoInput.focus(); return; }

    var verdict = classify(said);

    /* textContent throughout: whatever is said or typed is shown as words,
       never parsed as markup. */
    demoOut.querySelector('[data-out-section]').textContent = verdict.section;
    demoOut.querySelector('[data-out-title]').textContent = titleFor(said);
    demoOut.querySelector('[data-out-meta]').textContent = verdict.meta;
    demoOut.querySelector('[data-out-time]').textContent = verdict.time;
    demoOut.querySelector('[data-out-dest]').textContent = verdict.dest;
    demoOut.querySelector('[data-out-why]').textContent = verdict.why;
    demoOut.querySelector('[data-out-said]').textContent = '“' + said + '”';

    /* a task gets a circle to tick; a memory gets the app's note mark */
    var mark = demoOut.querySelector('[data-out-check]');
    mark.className = verdict.today ? 'approw__check' : 'approw__mark';
    mark.innerHTML = verdict.today ? '' : NOTE_GLYPH;

    demoOut.hidden = false;
    demoOut.classList.remove('is-new');
    /* restart the entrance without waiting a frame for the class to settle */
    void demoOut.offsetWidth;
    demoOut.classList.add('is-new');
  }

  /* -------------------------------------------------------- listening ---- */

  function clearWaiting() {
    waiting.forEach(clearTimeout);
    waiting = [];
  }

  function stopListening() {
    clearWaiting();
    if (!recogniser) return;

    /* `stop()` finishes what it heard; `abort()` throws it away. Which one is
       right depends on whether it ever started — calling `stop()` on a
       recogniser still waiting for permission leaves it with no `onend` and
       the page stuck mid-capture. */
    try {
      if (listening) { recogniser.stop(); return; }
      recogniser.abort();
    } catch (e) { /* already stopping */ }

    recogniser = null;
    idle();
  }

  /* `start()` is not a promise and does not always fail loudly: a permission
     prompt left unanswered, a policy that blocks capture, or an embedded frame
     can all leave the page with no `onstart` and no `onerror` at all. Rather
     than sit there looking broken, it says what it is waiting for and then
     gives up into the typed version. */
  function watchForStart() {
    clearWaiting();
    waiting.push(setTimeout(function () {
      if (!listening) setStage('Waiting for the microphone', 'Allow access in your browser, or type it instead.');
    }, 800));
    waiting.push(setTimeout(function () {
      if (listening) return;
      try { if (recogniser) recogniser.abort(); } catch (e) { /* nothing to stop */ }
      recogniser = null;
      idle('Can’t listen here', 'This browser is not letting the page use the microphone. Type it instead.');
      showForm(false);
    }, 9000));
  }

  function startListening() {
    if (listening) { stopListening(); return; }

    finalText = '';
    lastLen = 0;
    failed = false;
    setLive('', '');

    recogniser = new Recognition();
    recogniser.lang = navigator.language || 'en-US';
    recogniser.interimResults = true;
    recogniser.continuous = false;
    recogniser.maxAlternatives = 1;

    recogniser.onstart = function () {
      clearWaiting();
      listening = true;
      if (demo) demo.classList.add('is-listening');
      if (micOrb) micOrb.dataset.state = 'live';
      if (micLabel) micLabel.textContent = 'Stop listening';
      if (stopBtn) stopBtn.hidden = false;
      setStage('Listening', 'Say it the way you would say it out loud.');
    };

    recogniser.onresult = function (event) {
      var interim = '';
      for (var n = event.resultIndex; n < event.results.length; n++) {
        var result = event.results[n];
        if (result.isFinal) finalText += result[0].transcript;
        else interim += result[0].transcript;
      }
      var whole = finalText + interim;
      /* new characters are the only measure of level the page is given */
      if (whole.length > lastLen) voice = Math.min(0.72, voice + (whole.length - lastLen) * 0.05);
      lastLen = whole.length;
      setLive(finalText.trim(), interim.trim());
    };

    recogniser.onerror = function (event) {
      clearWaiting();
      failed = true;
      if (event.error === 'not-allowed' || event.error === 'service-not-allowed') {
        idle('Microphone blocked', 'Your browser is not letting this page listen. Type it instead.');
        showForm(true);
      } else if (event.error === 'no-speech') {
        idle('Nothing heard', 'Tap again and speak, or type it instead.');
      } else if (event.error === 'aborted') {
        failed = false;
      } else {
        idle('That did not work', 'Speech is not available here. Type it instead.');
        showForm(false);
      }
    };

    recogniser.onend = function () {
      clearWaiting();
      var said = finalText.trim();
      var wasListening = listening;
      recogniser = null;

      if (said) {
        idle('Captured', 'Tap to say another one.');
        setLive(said, '');
        capture(said);
      } else if (failed) {
        idleControls();          /* onerror has already said why */
      } else if (wasListening) {
        idle('Nothing heard', 'Tap again and speak, or type it instead.');
      } else {
        idle();
      }
    };

    try {
      recogniser.start();
      watchForStart();
    } catch (e) {
      recogniser = null;
      idle('That did not work', 'Speech is not available here. Type it instead.');
      showForm(false);
    }
  }

  if (micBtn) {
    if (canListen) {
      micBtn.addEventListener('click', startListening);
    } else {
      /* No speech in this browser: the indicator becomes the way into the
         typed version rather than a button that does nothing. */
      setStage('Type to capture', 'This browser can’t listen — the app listens on your iPhone.');
      micBtn.addEventListener('click', function () { showForm(true); });
    }
  }

  if (stopBtn) stopBtn.addEventListener('click', stopListening);
  if (typeBtn) typeBtn.addEventListener('click', function () { stopListening(); showForm(true); });

  /* A typed or picked sentence lands the same way a spoken one does, and the
     screen has to say so — otherwise the result card appears under copy still
     inviting you to start. */
  function captured(text) {
    var said = (text || '').trim();
    if (!said) { if (demoInput) demoInput.focus(); return; }
    setLive(said, '');
    setStage('Captured', 'Say or type another one.');
    capture(said);
  }

  if (demoForm) {
    demoForm.addEventListener('submit', function (event) {
      event.preventDefault();
      captured(demoInput ? demoInput.value : '');
    });
  }

  document.querySelectorAll('[data-demo-example]').forEach(function (button) {
    button.addEventListener('click', function () {
      stopListening();
      var text = button.dataset.demoExample;
      if (demoInput) demoInput.value = text;
      captured(text);
    });
  });

  /* ============================== reveals ================================ */

  var reveals = Array.prototype.slice.call(document.querySelectorAll('.reveal'));

  if (!reveals.length) return;

  if (reduceMotion.matches || !('IntersectionObserver' in window)) {
    reveals.forEach(function (el) { el.classList.add('is-in'); });
    return;
  }

  /* Titles that settle a word at a time. Only headings that are plain text
     are split — one with markup inside is left whole rather than guessed at —
     and the split happens here, after the reduced-motion exit, so a reader
     who has asked for stillness gets the heading exactly as it was written.
     The words are separated by ordinary spaces in the DOM, so nothing changes
     for a screen reader or for find-in-page. */
  document.querySelectorAll('[data-words]').forEach(function (el) {
    if (el.children.length) return;
    var words = el.textContent.trim().split(/\s+/);
    if (words.length < 2) return;
    el.textContent = '';
    words.forEach(function (word, n) {
      if (n) el.appendChild(document.createTextNode(' '));
      var span = document.createElement('span');
      span.className = 'w';
      span.style.setProperty('--w', n);
      span.textContent = word;
      el.appendChild(span);
    });
  });

  var appear = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-in');
      appear.unobserve(entry.target);
    });
  }, { rootMargin: '0px 0px -10% 0px', threshold: 0.1 });

  reveals.forEach(function (el) { appear.observe(el); });
}());
