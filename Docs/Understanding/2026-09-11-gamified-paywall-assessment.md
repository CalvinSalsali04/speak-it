# Gambling-style discount reveals in the paywall — assessment

Question: e-commerce brands make you match three cards or spin a wheel to reveal
a discount. The reward is guaranteed, so it is not really gambling, but winning
feels better than being given. Should Speak It put that on the paywall and the
win-back screen?

Researched 2026-09-10/11 across six dimensions with adversarial verification of
every load-bearing claim. Verification of the Apple-rules, age-rating, StoreKit
and consumer-law dimensions completed; verification of the efficacy and
alternatives dimensions was cut short by a usage limit, so claims from those two
are marked where they are unverified.

## Verdict

Three separate answers, and they point the same way for different reasons.

**Is it allowed?** Mostly yes, and more than expected. No App Store Review
Guideline prohibits it by name — a re-scrape of the guidelines (98,874 characters
of visible text, "Last Updated: June 8, 2026") returns zero hits for
"simulated", "spin", "wheel", "scratch" and "gamif". The loot-box clause in 3.1.1
does not reach a free reveal, because its items must be "for purchase" and a
subscription discount is not a "randomized virtual item". And YAZIO ships a
spin-the-wheel 75%-off reveal on the App Store today, which is an existence proof
that this passes review.

**Can it be built?** Not on the screen you want it on. This is the hard blocker,
and it is specific to Speak It.

**Is it the right thing to work on?** No, and not close. Revenue is $0 because
the app has never been submitted, not because the paywall lacks a card game.

## What you are right about

Worth stating plainly, because three of the four premises hold.

- **It is not gambling.** No stake is paid to play and the reward is guaranteed,
  so the prize-plus-chance-plus-consideration test that defines an illegal
  lottery never engages. Verified across EU, UK, US and Canadian analysis.
- **Everyone really is doing it, and it clears review.** See YAZIO above.
- **Gamified reveals can beat a plain offer.** The best randomized field
  experiment on the mechanic (Adam, Reinelt and Roethke, *Information Systems
  Journal* 33(6), 2023, N=651 field plus N=330 online) found both gamified arms
  beat the non-gamified arm.
- **Win-back is a real, under-used surface.** Speak It has no win-back screen at
  all, and Apple added a first-party mechanism for exactly this in iOS 18.

## Where it breaks

**Your dopamine premise is inverted, by the same study.** Adam et al. found
chance-based rewards produced the *highest* registration likelihood — higher than
gamified-but-certain. The ordering is guaranteed < gamified-certain <
gamified-chance. That is the opposite of "the reward is guaranteed, so it is not
gambling, but the dopamine is the same". Dopamine responds to prediction error, so
a reward the user knows is certain generates no signal. The mechanic delivers the
feeling you are describing only to the extent the user believes the outcome is
uncertain. That belief is the product being sold, and it is false.

**The strongest sales evidence favours the plain coupon.** On actual purchases
rather than sign-ups, the comparison runs the other way: a plain coupon at +31.7%
against gamified variants at +21.5% and +22.5%. Purchase-level effects for
chance-based promotions do exist elsewhere (Hock, Bagchi and Anderson, *Journal
of Consumer Research* 2020, seven studies including a 1,073-customer field
experiment; Mazar, Shampanier and Ariely, *Management Science* 63(1), 2017), so
the literature is genuinely mixed rather than against you. It is not the
one-way bet the social-media version implies. *(Efficacy dimension — verification
incomplete.)*

**Every headline number you have seen is vendor marketing.** The 3.5% vs 2.0%,
8.67% vs 3.70%, 9.25% vs 3.53% and 10.15% figures circulating for these widgets
are observational data published by the companies selling the widget, measuring
**email capture on cold traffic for a one-off purchase**. Speak It asks an
activated user for a recurring subscription. One of those sources does not define
"conversion" or disclose a sample size. There is no published A/B test of a
gamified discount reveal on a mobile subscription paywall at all.

**StoreKit will not supply the randomness — on the exact screen you want.** This
is the blocker that decides it. `Product.purchase(options:)`, the API Speak It
uses, has no option that carries a price, a percentage or a discount amount.
Every price-varying option takes an identifier for an offer already configured in
App Store Connect. Then each offer type excludes your target user:

| offer type | who is eligible |
|---|---|
| introductory offer | one per subscription group, per customer, for life |
| promotional offer | current or previously subscribed only |
| win-back offer | churned, lapsed at least a month |

A never-subscribed person who has just burned ten free captures — the person your
paywall is for — cannot be dealt a randomized discount by any of them. Apple does
have a runtime-price API (`AdvancedCommerceProduct.purchase(compactJWS:)`, iOS
18.4+), but it needs a server to sign the request, requires Apple eligibility
Speak It does not have, and contradicts the no-backend, local-first architecture.

So the wheel can only ever land on a small fixed set of offers you pre-created,
identical for everyone. The part that creates the feeling is the part the
platform will not give you.

**The win-back variant has the one documented rejection pattern in this space.**
Apple has rejected apps under Guideline 5.6 with the words "your app still
displayed an additional discount offer when we attempted to exit the subscription
page." An exit-intent discount is precisely the shape you described.

**If the outcome is fixed but presented as chance, it is a false price.**
Guideline 2.3.1 prohibits promoting a false price, and the stated consequence
reaches removal and developer-account termination. On a first submission with
zero review history, that is a bad trade for a dopamine hit.

**In the EU the deception analysis is per se, with nothing to argue.** Annex I of
the Unfair Commercial Practices Directive — points 19 and 31, mirrored in the UK
Digital Markets, Competition and Consumers Act 2024, Schedule 20 — blacklists
creating a false impression of winning. The CJEU held in C-428/11 *Purely
Creative* that clear disclosure does not cure it. And in November 2024 the
European Commission and the CPC Network formally notified Temu that "forced
gamification: forcing consumers to play a 'spin the fortune wheel' game ... while
hiding essential information" infringes EU consumer law. Caveat, from
verification: that finding is about *forced* gamification combined with hidden
reward conditions, not about gamification as such, and it is the network's
assessment rather than a final ruling.

**In Canada there is a specific provision.** Competition Act s.74.06 reaches
anyone disposing of a benefit "by any mode of chance", requires adequate and fair
disclosure of anything materially affecting the chances of winning, and requires
distribution "on the basis of skill or on a random basis" — which a predetermined
outcome is neither. Quebec's contest registration regime was repealed by Bill 17
on 27 October 2023, so the filing burden is gone; liability under the Consumer
Protection Act's general-impression test (*Richard v. Time Inc.*) is not.

**It costs the 4+ rating, or it costs the honesty.** Readiness item 8 plans to
answer every age-rating question None and expect 4+. App Store Connect has a
Chance-Based Activities category, and answering it honestly for a genuinely random
mechanic risks moving Speak It off 4+. Apple's July 2025 update *added* 13+, 16+
and 18+ to the existing 4+ and 9+; verifiers disagreed on which tier an
"infrequent" answer lands in, so treat the exact tier as unsettled and the
direction as certain. A calm productivity app does not want this conversation on
its first submission.

## The fact that settles the sequencing

You said you are missing out on thousands of dollars. The paywall has never been
shown to a paying customer. Both subscription products and the group sit in
Prepare for Submission; nothing has been submitted and no purchase has ever been
made. Every paywall mechanic is currently worth its effect multiplied by zero.

Three consequences:

1. **The win-back screen has an audience of zero, and keeps it for over a
   month.** Win-back offers cannot be created until App Review approves the
   subscription, and then a subscriber has to churn and stay lapsed a month.
2. **You could not tell whether it worked.** Detecting a 20% relative lift on a
   2–5% paywall conversion base needs roughly 16,000–40,000 paywall views.
   *(Unverified.)*
3. **A dated deadline is blocked behind submission.** The annual price schedule
   of $14.99 to $29.99 on 2026-10-22 cannot be set while the subscription is in
   Prepare for Submission. That is readiness item 14.

Also relevant: the three highest-value paywall fixes the September research
identified have already shipped. Monthly moved to $2.99, and the `firstCapture`
and `runningLow` presentation contexts now put a dismissible offer on Day 0 and
before the wall rather than only at the wall. The remaining in-app conversion
headroom is genuinely thin.

For scale, from the alternatives research *(unverified)*: at a realistic 2,500
first-year installs, a welcome-offer-grade paywall win is worth roughly $151–226,
against roughly $1,509 for simply doubling installs. The thousands of dollars you
are naming live in install volume, not in a reveal animation.

## The legitimate version of what you want

Apple built it. **Win-Back Offers** (iOS 18) let you merchandise a real discount
to genuinely lapsed subscribers, and `eligibleWinBackOfferIDs` lets you present
it on your own screen rather than only on the App Store. That is your win-back
idea, sanctioned, with the discount honoured by StoreKit. It is readiness-adjacent
work that becomes possible the moment the subscription is approved.

Offer codes are the other sanctioned path, and the referral service already
models both offer codes and promotional offers, with `offerCodeRedemption` wired
into the paywall.

## What to do instead, ranked

1. **Finish the remaining hand items and submit.** Device QA including smoke case
   E8, Sandbox purchase testing, screenshots, the listing and privacy entries, the
   DSA trader declaration, then Submit. This unblocks win-back offers and the
   October 22 price schedule.
2. **Install volume.** App Store search is roughly 65% of iOS discovery and ASO is
   the only channel a zero-budget indie has. This is where the thousands of
   dollars are.
3. **Split the two back-to-back permission alerts in `WelcomeView`.** For a voice
   app a microphone denial is a 100% revenue loss, and this is the one lever in
   the whole assessment with peer-reviewed support.
4. **Configure win-back offers** once approved.
5. **Then** test paywall variants, once there is traffic to measure them with.

## If you still want the mechanic, here is the compliant shape

Not on the first-purchase paywall — StoreKit cannot honour it there. On the
win-back screen, after approval, backed by real Apple win-back offers:

- Everyone eligible gets the **same** offer. No weighting, no tiers.
- Frame it as a reveal, not a wager: "tap to reveal your welcome-back offer".
- No wheel, no cards, no odds, no "you won", no near-miss animation.
- State that the offer is the same for everyone, which is what keeps it clear of
  UCPD Annex I and Competition Act s.74.06.
- Answer the age-rating questionnaire None, honestly, because with a fixed
  disclosed outcome there is no chance-based activity to declare.
- Never show it on subscription-cancellation exit, which is the Guideline 5.6
  rejection pattern.

That keeps the suspense and drops the deception. Be clear-eyed about the trade:
Adam et al. is the same study that says the certain-reward version underperforms
the chance version, so this variant keeps the compliance and gives up most of the
claimed effect. Which is the honest summary of the whole idea.

## Consistency with a call you already made

`Docs/GAMIFICATION_PROPOSAL.md` settled this question once, for habit mechanics:
"Do not copy Duolingo. Copy the two things that make Duolingo work ... and refuse
the rest," because "a streak that punishes silence contradicts the product it is
decorating." A rigged slot machine in front of the price contradicts "minimal,
professional, and predictable" in the same way, and this time the platform and
consumer law agree with the brand.
