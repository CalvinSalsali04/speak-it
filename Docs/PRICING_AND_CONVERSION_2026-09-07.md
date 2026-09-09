# Pricing and conversion research — September 7, 2026

> Research correction (2026-09-08): trial-versus-direct cohort LTV is observational, not proof that trials destroy value. Changing an App Store category does not cause trial economics to change. Use the September 8 pricing decision for the current recommendation.


Question asked: should Speak It bill weekly instead of monthly, and where else is
the funnel leaking? This document records the evidence and the recommendation.
Nothing here has been implemented; no price, product, or App Store Connect value
was changed.

**Standing caveat.** Speak It has not shipped. There is no install, paywall, or
purchase data of its own, and `SPEAKIT_ANALYTICS_KEY` is empty by default, so no
funnel has ever been measured. Everything below is external benchmark data
applied to the code as it stands. Treat it as a prior to launch against, not as
a measurement.

**Source quality.** Almost all app-monetization benchmarks are published by
paywall vendors from their own customers' data (RevenueCat, Adapty, AppsFlyer).
They are the best numbers available and they are also marketing assets, biased
toward apps sophisticated enough to install a paywall SDK. Figures below are
marked where they are vendor-published, and unverifiable claims that circulate
widely have been discarded rather than repeated.

## 1. Weekly billing: no

The instinct behind the question is right — the price is wrong. The direction is
inverted. Speak It is not billing too infrequently; it is charging too little.

### What the category data says

RevenueCat, *State of Subscription Apps 2026* (115,000+ apps, $16B+ revenue,
published March 2026):

| | Weekly | Monthly | Annual |
|---|---|---|---|
| Revenue per install, D14 (apps dominated by that plan) | $0.19 | $0.18 | $0.36 |
| Revenue per install, D60 | $0.32 | $0.29 | $0.46 |
| Reference price band | $4.99–6.89 | $7.99–9.99 | $29.99–39.99 |

Weekly-dominant apps monetize an install **worse** than yearly-dominant apps
($0.32 vs $0.46 at D60). The premise that weekly extracts more money per user is
not supported by the aggregate.

Plan mix is category-structural, not a matter of taste. Gaming sells 82% weekly.
**Productivity is the monthly outlier at 77%**, and draws 77% of its revenue from
monthly plans (RevenueCat 2026, Productivity category page). Outside Gaming,
weekly rarely exceeds 30% of a category's revenue. Speak It ships as
`public.app-category.productivity` (`SpeakIt/Info.plist:37`).

Retention is worst at weekly. The 2025 edition put weekly Year-1 retention at
**3.4%**, the lowest of any duration and down from 4.2%, with **30–50% churn at
the first renewal** versus 15–40% for monthly.

### The arithmetic makes it worse, not better

Weekly only raises revenue by raising the annualized price behind a small
number. At the category's own reference band:

- $1.99/week = **$103.48/year** — 3.5× the annual plan already scheduled.
- $0.99/week = **$51.48/year** — still above the $29.99 annual plan.

There is no weekly price that is both credible next to a $29.99 annual plan and
worth the churn. The mechanism that makes weekly pay is exactly the mechanism
that produces refunds and one-star reviews.

### No comparable app does this

Prices were checked directly against the US App Store on 2026-09-07. **Not one
classic productivity or note-taking app sells a weekly plan.** Confirmed absent
from all of: Bear, Drafts, Things, Otter, Just Press Record, AudioPen,
Superwhisper, Flighty, Bezel, Day One, Structured, Sorted3, Reflect, Obsidian,
Craft, Agenda, GoodNotes, Todoist, TickTick, Fantastical, Whisper Memos,
Granola, Talknotes, Letterly.

Weekly appears in exactly one cohort — AI voice-transcription apps sold through
paid-acquisition funnels — and there it is a price multiplier, not a
convenience:

| App | Weekly | Annualized | Their own annual plan | Multiple |
|---|---|---|---|---|
| Voicenotes | $8.99/wk | ~$467/yr | $89.99 | **5.2x** |
| VOMO AI | $7.99/wk | ~$415/yr | $71.99 | **5.8x** |
| Wispr Flow | $4.49/wk | ~$233/yr | $143.99 | **1.6x** |

The dividing line is not price or product; it is how the app is sold. Weekly is
used by apps bought through ad spend, not by apps bought through reputation.
Speak It has no acquisition budget and is being launched on reputation.

### Regulatory and review exposure

Weekly pricing is the structure currently under enforcement attention, and a
solo developer with one app should not be standing near it.

- The FTC continues bringing cases under ROSCA and Section 5 after the Eighth
  Circuit vacated the click-to-cancel rule in July 2025; rulemaking reopened in
  March 2026. The Genesis Tech action targets a network of apps advertised as
  free or low-cost while obscuring auto-renewal — roughly a quarter-billion
  dollars of revenue from early 2023 to mid-2025.
- Shutterstock settled for $35M in May 2026 over hidden terms and difficult
  cancellation.
- New York's law, effective November 2025, requires advance affirmative consent
  for subscription price increases.
- App Review Guideline 3.1.2 requires price, duration and auto-renewal terms to
  be clear and prominent on the purchase screen, and a per-period breakdown to
  stay subordinate to the total charged.

### Product-contract conflict

`CLAUDE.md` commits Speak It to being calm, minimal, and predictable. A weekly
bill puts a purchase decision in front of the user 52 times a year for a product
whose promise is that they do not have to think about it.

### The strongest counter-argument

Short-duration plans do dominate units sold, and weekly paired with a free trial
is reported to deliver strong 12-month LTV in some categories. Weekly also
removes the commitment objection at the moment of sale. But that model needs a
high annualized price, paid user acquisition to keep refilling a leaky bucket,
and tolerance for refunds and bad reviews. Speak It has none of the three, and
no acquisition budget at all.

## 2. The actual pricing problem is the annual plan, not the monthly

Two evidence sets disagree here, and the disagreement is the finding.

**The aggregate says Speak It is cheap.** RevenueCat's Productivity median monthly
price is **$8** (up from $7), its reference bands are monthly $7.99–9.99 and
annual $29.99–39.99 with a $34.80 median, and its price-tier table is brutal
about being cheap:

| Price tier | D35 download→paid | Year-1 realized LTV per payer |
|---|---|---|
| High | **2.8%** | **$62.19** |
| Mid | 2.0% | $28.75 |
| Low | **1.4%** | **$10.69** |

Low-priced apps convert downloads at half the rate of high-priced apps and
realize about a sixth of the lifetime value. The discount does not buy volume.

**The comparables say Speak It is priced correctly.** That $8 median is set by
Otter, Todoist, Craft and Notion-class products with teams, sales motions and
paid acquisition. The relevant peer set is solo-developer iOS utilities, and
prices there were checked directly against the US App Store on 2026-09-07:

| App | Monthly | Annual | Annual as months of monthly | Lifetime |
|---|---|---|---|---|
| Timery | $0.99 | $9.99 | 10.1 | — |
| Callsheet | $1.00 | $9.00 | 9.0 | — |
| **Drafts Pro** | **$1.99** | **$19.99** | **10.0** | — |
| **Bear** | **$2.99** | **$29.99** | **10.0** | — |
| Play | $2.99 | $19.99 | 6.7 | $99.99 |
| Dark Noise | $2.99 | $19.99 | 6.7 | $49.99 |
| Structured | $6.99 | $29.99 | 4.3 | $99.99 |
| **Speak It today** | **$1.99** | **$14.99** | **7.5** | — |
| **Speak It after Oct 22** | **$1.99** | **$29.99** | **15.1** | — |

**$1.99/month is not underpriced.** It is exactly Drafts Pro, and just under
Bear — the two most respected indie note-taking apps on the platform. Holding
that line is defensible.

**The annual plan is the broken number, and it breaks in the direction opposite
to the aggregate advice.** The near-universal indie ratio is annual ≈ 10 months
of monthly. Speak It's scheduled $29.99 annual against a $1.99 monthly is **15.1
months** — more expensive than simply paying monthly all year, and above every
comparable in the sample.

### Recommendation

Move **monthly to $2.99** and keep **annual at $29.99**.

That is Bear's exact architecture, lands on the 10-month indie ratio, raises
revenue per monthly subscriber by 50%, keeps the annual price already scheduled
for October 22, and makes the pre-selected `BEST VALUE` badge true again
($29.99 against $35.88). Set it before the first release, while it is free to do.

The alternative, if the $1.99 monthly is non-negotiable, is to hold monthly at
$1.99 and set annual to **$19.99** — Drafts Pro exactly. What cannot ship is
$1.99 monthly alongside a $29.99 annual.

Voice-capture comparables for context: Voicenotes iOS $14.99/mo, AudioPen $99/yr
non-renewing, Superwhisper $8.49/mo with a $249.99 lifetime, Otter Pro $16.99/mo.
The AI-transcription cohort prices far above Speak It — but those products carry
per-request cloud inference costs that Speak It's on-device architecture does not
(`Docs/DECISIONS.md:1089`).

Apple's Small Business Program pays 85% immediately, with no one-year wait.

### Consider merchandising the lifetime SKU

`com.calvinwak.SpeakIt.pro.lifetime` already exists at $49.99 and is deliberately
excluded from `productIDs`, reachable only through an Apple offer code
(`SubscriptionStore.swift:113`). Lifetime unlocks are common in this exact peer
group — Dark Noise $49.99, Play $99.99, Structured $99.99, Bezel $99, Agenda $179
— and absent only from the subscription-first note apps. A local-first app that
costs nothing per capture to run is unusually well suited to selling one, and it
converts the buyers who will never subscribe to anything. This is a decision, not
a recommendation: it trades recurring revenue for conversion and goodwill, and it
is hard to reverse.

### Note on the free tier's shape

The category norm is an *ongoing* cap — minutes per week, notebooks, projects,
saved timers. Speak It's one-time lifetime allowance of ten captures is unusual;
the closest analogue found in the survey is Callsheet's 20 free searches. This is
not necessarily wrong, and §3 argues the generosity is right, but it does mean
there is no comparable to borrow conversion expectations from.

### Three pricing defects in the current build

1. **The ladder inverts on October 22.** `Docs/DECISIONS.md:54` schedules annual
   $14.99 → $29.99, and `CLAUDE.md` calls $1.99 the *intended* monthly price, not
   a promotion. If monthly stays $1.99, annual at $29.99 costs **$6.11/year more
   than paying monthly**, while the paywall pre-selects it and badges it
   `BEST VALUE` (`SpeakIt/Features/Setup/SpeakItProView.swift:485`). Under
   Guideline 3.1.2 that badge is also a claim a reviewer can check.
2. **The website assumes a monthly regular price the app never implements.**
   `Website/assets/stage.js` prints a struck-through $3.99 monthly;
   `priceColumn(product:isAnnual:alignment:)` only ever strikes through the
   annual price. Already recorded at `Docs/FINAL_RELEASE_AUDIT.md:1965`.
3. **The sale caption misdescribes what a launch price does.** "Summer launch
   price · $14.99 per year until October 22, 2026"
   (`SpeakItProView.swift:659`) reads as though the buyer's own rate expires on
   that date — the opposite of the grandfathering the website promises. This is
   a refund and one-star generator and is pinned by a UI test, so the test moves
   with the copy.

## 3. Conversion: where the funnel leaks

### Current shape

| Stage | Implementation |
|---|---|
| Welcome | `WelcomeView.swift:81` — "Start speaking" / "Explore first" |
| Tutorial | 8 steps, skippable; practice captures are free (`ThoughtRepository.swift:207`) |
| Free tier | 10 lifetime captures, Keychain-backed monotonic ledger, survives reinstall |
| Soft upsell | `ProDiscoveryCard` at ≥5 items, dismissible (`TodayView.swift:661`) |
| Countdown | Receipt says "2 / 1 / last free capture" (`CaptureView.swift:1422`) |
| Hard wall | Capture 11 opens the paywall with `context: .freeLimit` |
| Plans | Monthly and annual, annual pre-selected, `BEST VALUE` |

### Leak 1 — the paywall fires weeks after the audience has left

About **50% of paid conversions happen on Day 0**, and **over 60% within the
first week** (RevenueCat 2026). **90% of trial starts happen on Day 0**; even
Productivity, the slowest category on this measure, starts **78%** of trials on
Day 0 (Adapty 2026, 16,000 apps). AppsFlyer's 2026 marketer report puts **28% of
D60 subscription revenue on Day 1**.

A lifetime allowance of ten captures that never renews decouples the paywall
from Day 0 by construction. Someone capturing twice a week meets the wall in
week five, by which point the surviving population is a single-digit percentage
of installs. The generosity is right; the timing is not.

Adapty's placement data (install-denominated):

| Placement | Conversion |
|---|---|
| Onboarding paywall **with** trial | 1.35% |
| In-app paywall with trial | 0.89% |
| Onboarding paywall without trial | 0.82% |
| In-app paywall without trial | **0.76%** ← Speak It today |

The fix that respects the product contract: keep all ten captures, but show the
plan sheet once, dismissible, on the **receipt of the first successful real
capture** — the value moment, not app open — and move `ProDiscoveryCard` from
`allItems.count >= 5` to fire after the first real capture, with a second
prompt at capture 7 or 8 while intent is still live rather than only at 10.

### Leak 2 — there is no free trial, and the category says that may be correct

`SpeakIt.storekit` has `introductoryOffer: null` on both products, and no code
references `isEligibleForIntroOffer` or any `SubscriptionOffer`. A stranger at
capture 11 is asked to commit money cold.

The usual advice is "add a trial." The category data says to check first. Adapty's
2026 trial-versus-direct-purchase analysis, 12-month LTV premium for trial users:

| Category | Premium |
|---|---|
| Utilities | **+85.1%** |
| Health & Fitness | +63.6% |
| Education | +50.4% |
| **Productivity** | **−13.7%** ($49.13 trial vs $56.95 direct) |
| Lifestyle | −21.2% |

Productivity is one of only two categories where free trials **destroy** LTV.
Utilities is where they help most, and Utilities also shows the best first-renewal
retention of any category at 58.1%. Speak It sits exactly on that boundary — a
single-session, immediate-value voice tool that is currently filed as
Productivity.

**The App Store primary category is now a monetization decision, not just a
discovery one.** Decide it deliberately. If Speak It stays Productivity, the
current no-trial stance is the evidence-backed one and the money is better spent
on price and timing. If it moves to Utilities, add a trial.

If a trial is added: **do not use three days.** Trials of ≤4 days convert at
25.5% versus 42.5% for 17–32 days — about 70% better — and 84% of 3-day-trial
cancellations happen by the end of Day 1. Seven days minimum. Apple allows **one
introductory offer per subscription group, ever**, so there is one attempt per
customer.

### Leak 3 — no win-back offers

Apple's win-back offers (WWDC 2024, available since September 2024, iOS 18+ and
StoreKit 2) are surfaced by Apple on the App Store product page, in editorial and
personalized recommendations, and in the user's Settings → Subscriptions —
placements Speak It cannot otherwise reach — for what is mostly App Store Connect
configuration. Given that Year-1 annual churn is now 72% and 35% of annual
cancellations land in month one, lapsed subscribers arrive sooner than expected.
Configure this before there are any.

### Leak 4 — two permission alerts behind one explanation

`requestVoiceAccess()` (`WelcomeView.swift:1389`) requests speech recognition and
microphone authorization back to back. The tutorial has a `.permissions` step, so
priming exists — but the user sees **two** system alerts after one explanation,
and the second is the classic unexpected request.

This is the best-evidenced item in the whole document, and the only
peer-reviewed one: the PrivaDroid field study (Lie et al., USENIX Security 2021,
1,700+ participants, 36,000+ real permission events) found an **unexpected
permission request is more than twice as likely to be denied**, and that
**conveying why the app needs the resource halves the denial rate**. A denied
microphone is a total loss, worse than any paywall loss — and Speak It's
local-first architecture makes the rationale both strong and true.

Note the same study observed the privacy paradox directly: nearly 30% of
self-identified privacy-sensitive users granted permissions *more* often than
average. Privacy is an objection-remover, not a demand generator.

## 4. Recommended order of work

Nothing below is implemented. Ordered by expected value per unit of effort.

**Before submitting**

1. Set monthly to $2.99 and keep annual at $29.99, and resolve the three
   pricing defects in §2. Cheapest change available, and the only one that has
   to happen before the annual price change on October 22.
2. Decide Productivity versus Utilities as the primary category, knowing it
   flips the trial question from −13.7% to +85.1%.
3. Show the plan sheet once on the first successful capture receipt; move
   `ProDiscoveryCard` off the `>= 5` gate; add a prompt at capture 7–8.
4. Split the two permission alerts, with one sentence of rationale before each.
5. Configure Apple win-back offers in App Store Connect (iOS 18+ gate).

**Before the store listing is final**

6. Lead the listing with the job — "say it, it's handled" — and keep privacy as
   the trust line rather than the hook. Roughly 60–65% of App Store downloads
   begin in search, and nobody searches for private voice notes in volume.
7. Custom Product Pages and a real screenshot pass. Apple reports +2.5 percentage
   points of conversion on CPP traffic; independent measurement across 1M+ Apple
   Ads ad groups reports about +22.9% installs at equal impressions.
8. Gate `requestReview` behind a real success moment — a capture the user did not
   edit. Apple allows three prompts per user per year and may suppress them
   anyway, and apps below 3.5 stars rank lower for keywords (AppTweak 2025).

**Explicitly not worth building**

9. No personalization quiz. There is no evidence it survives for a utility, Speak
   It has no plan to personalize, visual and copy-only A/B tests win only 34.6%
   of the time (Adapty), and every onboarding screen spends the Day-0 session
   that cannot be recovered.
10. No A/B testing infrastructure yet. The 18.7× revenue gap between apps running
    50+ experiments and one experiment is real but heavily confounded by app
    size, and pre-launch volume cannot reach significance. Build the paywall so
    variants are cheap to swap later.
11. No web checkout. Web revenue is 3.2% globally, and it cuts against the
    no-account, local-first architecture.
12. Live Activities and Back Tap are product polish, not growth levers. No
    published conversion or retention data exists for either.

## 5. Sober expectations

Plan against a **1.4–2.8% install-to-paid** median, with top quartile around
4–6%. The median subscription app earns **$492/month**, and **59.3% earn under
$1,000/month** (Adapty 2026). Only **17.3%** of new apps reach $1K MRR within two
years and **4.6%** reach $10K (RevenueCat 2026). Apps launched before 2020 hold
69% of subscription revenue; apps launched in 2025 or later hold 3%.

That is not an argument against shipping. It is an argument for setting the price
correctly on day one, because at these conversion rates the revenue per payer is
the only variable with real leverage.

## Sources

- RevenueCat, *State of Subscription Apps 2026* — https://www.revenuecat.com/state-of-subscription-apps/ and https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026 (March 2026)
- RevenueCat, *State of Subscription Apps 2025* — https://www.revenuecat.com/state-of-subscription-apps-2025
- Adapty, 2026 benchmarks and trial-versus-direct analysis (March 2026)
- AppsFlyer, *State of Subscriptions for Marketers 2026*
- Lie, Austin et al., PrivaDroid, USENIX Security Symposium 2021 — the only peer-reviewed source here
- Apple, auto-renewable subscriptions and offers — https://developer.apple.com/app-store/subscriptions/
- FTC enforcement 2025–2026: Genesis Tech network; Shutterstock settlement (May 2026); New York subscription law (November 2025)
- Competitor prices, fetched 2026-09-07 from vendor pricing pages, US App Store
  listings and Apple's iTunes lookup API: Bear, Drafts, Things 3, Otter.ai, Just
  Press Record, Voicenotes, AudioPen, VOMO AI, Superwhisper, Flighty, Bezel, Day
  One, Structured, Sorted3, Reflect, Obsidian, Craft, Agenda, GoodNotes, Todoist,
  TickTick, Fantastical, Whisper Memos, Granola, Wispr Flow, Talknotes, Letterly,
  Callsheet, Timery, Play, Dark Noise, Parcel, Mela

### Numbers deliberately excluded

Several widely-quoted figures could not be traced to a primary document and are
not used above: per-category D35 conversion for Utilities (behind RevenueCat's
gated report; secondary sources quoting it are unreliable), "3-day trials convert
62.4%" (contradicts RevenueCat's own 25.5%), "permission priming lifts grants
81%", productivity D1/D30 retention targets from aggregator blogs, and win-back
conversion rates borrowed from direct-to-consumer e-commerce. One further
contradiction is unresolved: a secondary summary claims weekly plans generate
55.5% of all subscription revenue, which cannot be reconciled with the same
report's statement that weekly rarely exceeds 30% of category revenue outside
Gaming. Neither figure is relied on here.
