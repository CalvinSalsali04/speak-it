# App Store Submission

Working document for the first Speak It release. Status values: **Done**,
**Blocked** (needs an Apple account or a hosted page), **Todo**.

## Current verdict — August 24, 2026

**The code is a release candidate; the app is not ready to click Submit yet.**
No known code failure blocks TestFlight, but distribution still depends on the
account, commerce, hosted-policy, listing, and physical-iPhone gates below.

Current automated evidence from the working tree:

- Unsigned Release build (Sept 3, 2026): passed with zero compiler warnings.
- Release static analyzer: passed with no findings or compiler warnings.
- Unit/integration suite (Sept 3, 2026): 709 passed, 6 environment-specific
  tests skipped, 6 failed on an iPhone 17 / iOS 26.5 simulator — the six
  failures are the recurring-reminder wall-clock cases that shift by exactly
  the host-to-Toronto UTC offset when the Mac is not in North America (this
  run was on Asia/Bangkok), identical before and after the day's changes.
  Re-run on a Toronto-zoned Mac before submission to record a clean count.
- UI suite (Sept 3, 2026): 23 tests, 19 passed, 4 failed on an iPhone 17 /
  iOS 26.5 simulator; one of the four passed on an isolated re-run. The three
  that stay red are not the day's changes: `testFirstSavePersistsOnboarding…`
  types "Buy toothpaste" into a first mission that now asks for a person and a
  task (the in-flight tutorial work rejects it with "Almost — one more go"),
  and the two shopping-card tests wait six seconds for the sixth seeded
  example while the simulator's on-device model takes roughly nine seconds
  for the six. Update the first-save test to the new mission, and either
  lengthen the seed wait or seed the shopping row first, before re-baselining.
- Complete first-run practice journey: passed on both iPhone 17 Pro and iPhone
  SE (3rd generation) simulators. The SE pass includes the full example copy,
  the scrollable typed-input escape route, live Today/People/Ideas coaching,
  readiness, cleanup, and all ten free captures remaining.
- The first-run UI test preserves 16 named screenshots and has a matching
  screen recording, including the Capture Anywhere method and setup branch.

Do not submit until every one of these external gates is closed:

1. Complete the DSA trader declaration.
2. Switch every target to the paid team and verify the app group and iCloud
   container in a signed archive installed through TestFlight.
3. Create and approve the monthly, annual, and code-only lifetime products;
   verify the annual price schedule and all localized sale copy in App Store
   Connect.
4. Deploy the privacy and support pages, confirm the support mailbox is
   monitored, and make App Store privacy answers match the privacy manifest.
5. Finish the store listing, age rating, review notes, and required screenshots.
6. Pass the physical-iPhone voice/route, locked-device, notification/alarm,
   purchase/restore, iCloud, accessibility, and geofence matrices in section 7.

## 1. Account and agreements

- **Done:** Apple Developer Program membership ($99/year) is paid.
- **Done (Aug 11, 2026):** Paid Apps and Free Apps agreements are Active, the
  Canadian bank account "Speak It (0267)" is Active, and the three tax forms
  (Canadian GST/HST 506, Certificate of Foreign Status, W-8BEN) are Active.
- **Todo:** Complete the Digital Services Act trader declaration. App Store
  Connect → Business still shows "Complete Compliance Requirements"; without it
  the app cannot be distributed in the European Union.
- **Todo:** Switch signing from personal team `LZZT2A38SD` to the paid team on
  all five targets. `SpeakIt/SpeakItRelease.entitlements` declares iCloud
  entitlements a personal team cannot sign, so Release distribution depends on
  this. The identifiers that must exist under the paid team are
  `com.calvinwak.SpeakIt`, `com.calvinwak.SpeakIt.LiveActivity`,
  `com.calvinwak.SpeakIt.ShareExtension`, app group
  `group.com.calvinwak.SpeakIt`, and iCloud container
  `iCloud.com.calvinwak.SpeakIt`.
- **Todo:** Create both products in one subscription group:
  - `com.calvinwak.SpeakIt.pro.monthly` — $2.99 / month, not discounted
  - `com.calvinwak.SpeakIt.pro.annual` — summer launch price $14.99 / year,
    regularly $29.99
  Monthly carries no sale price. It is $2.99 before and after the cutoff, and
  the paywall never strikes a monthly regular price through. **Annual must stay
  below twelve months of monthly** — $29.99 against $35.88 — or the plan the
  paywall pre-selects and badges `BEST VALUE` is the more expensive one, which
  is a guideline 3.1.2 claim a reviewer can check. See
  `Docs/DECISIONS.md` (2026-09-07).
  App Store Connect is the source of truth for live localized prices. The app
  renders `product.displayPrice`, so whatever is configured there is shown.
  Each subscription also needs a localized display name, description, and a
  review screenshot before it can be submitted.
- **Todo — exact summer price schedule:** Use the United States storefront as
  the reference price, then schedule the annual product to move from $14.99 to
  $29.99 at the start of **October 22, 2026**. Preserve the $14.99 price for
  existing subscribers; $29.99 applies to subscriptions begun after the cutoff.
  Configure equivalent localized tiers in every territory before enabling any
  sale copy. The app cutoff is `2026-10-22T04:00:00Z`, which is midnight in
  Toronto while EDT is active.
- **Launch gate:** Only after that schedule is visible in App Store Connect,
  build Release with `SPEAKIT_SUMMER_SALE_ENABLED=YES` and set
  `SUMMER_SALE_ENABLED = true` in `Website/assets/stage.js`. Before the cutoff,
  the USD storefront then truthfully shows $14.99, regularly $29.99, 50% off,
  and Best Value. The time gate removes sale language automatically at cutoff.
- **Todo:** Create `com.calvinwak.SpeakIt.pro.lifetime` as a non-consumable
  purchase for complimentary permanent Pro only. Do not merchandise it in the
  app. Keep permanent grants separate from subscription referrals; the app
  recognizes only Apple's verified transaction and contains no hardcoded
  entitlement bypass.
- **Todo — founder subscription codes:** Create two free subscription Offer Code
  configurations and their custom codes:
  - `CALVINMONTH` — one month free, with only the intended new/existing/expired
    subscriber eligibility enabled.
  - `CALVINYEAR` — one year free, with only the intended eligibility enabled.
  Both use the existing App Store redemption sheet reached from Account &
  Settings → Speak It Pro → Redeem Code. Do not add either string to app source.

## 2. Build configuration — done

- **Done:** `MARKETING_VERSION` is `1.0` across the app, Live Activity
  extension, Share extension, and UI tests. Verified in the built product:
  `SpeakIt.app`, `SpeakItLiveActivity.appex`, and `SpeakItShareExtension.appex`
  all report `1.0`. The current build number is `13`.
- **Done:** `ITSAppUsesNonExemptEncryption` is `false` in `SpeakIt/Info.plist`,
  so uploads no longer stall on the export-compliance question. Verified correct:
  the iOS binary uses only HTTPS and Apple data protection. It contains no
  CryptoKit, CommonCrypto, or custom cryptography. The separately deployed
  referral server uses standard Node AES-256-GCM to protect one-time Apple code
  inventory at rest; that code is not part of the app binary.
- **Done:** `SpeakIt/SpeakIt.storekit` defines both subscriptions plus the
  code-only lifetime non-consumable and is wired
  into the shared scheme's Run action. It is a project file reference only, in
  no build phase, and was confirmed absent from the built `.app` bundle.
- **Done:** `SPEAKIT_ANALYTICS_KEY` defaults to empty in Debug and Release, so
  no build transmits analytics unless a key is deliberately injected.
- **Done:** External capture text is clamped to `CaptureTextLimit`
  (20,000 characters) at all three untrusted boundaries: the Share extension,
  the Save Thought App Intent, and the shared-inbox import.
- **Done:** Security sweep of the shipping binary — no secrets, no debug
  logging, no developer paywall override, no ATS exceptions, no WebView.
- **Done (Aug 24, 2026):** 524 unit/integration tests passing with 6
  environment-specific cases skipped, all 22 UI tests passing, the complete
  onboarding passing on Pro and SE simulator sizes, the unsigned Release build
  clean, and Release static analysis clean.

## 2A. Verified referral program — implemented, externally gated

The iOS client and `ReferralService` now implement the complete reward path.
The public promise remains off until the following account/hosting work passes:

1. Create Offer Code `speakit_referral_friend_month`, one month free, new
   subscribers only, with custom code `SPEAKITFRIEND`.
2. Create Offer Code `speakit_referral_reward_month`, one month free for new,
   existing, and expired subscribers. Generate a pool of one-time-use codes and
   import them through the service's private admin endpoint.
3. Create one-month-free Promotional Offers
   `speakit_referral_reward_monthly` and
   `speakit_referral_reward_annual` on their matching products.
4. Create the Apple In-App Purchase signing key and mount its `.p8` file plus
   Apple's current root certificates into the service. Never add them to the
   app, repository, container image, or website.
5. Deploy `ReferralService` behind TLS on a single instance with an encrypted,
   backed-up persistent volume. Follow `ReferralService/README.md`, including
   host-level rate limits and code-inventory monitoring.
6. Run the Sandbox journey on a physical iPhone: accept invite → redeem friend
   month → open app → Apple transaction verifies → referrer sees one reward →
   redeem reward → kill/relaunch → entitlement and ledger persist. Repeat the
   cancelled, pending, revoked, duplicate, self-referral, reinstall, and Restore
   Purchases cases.
7. Inject the verified base URL as `SPEAKIT_REFERRAL_API_URL` in Release, then
   set `REFERRALS_ENABLED = true` on the website. With no URL, the app keeps the
   honest non-reward “Share Speak It” row.

The backend binds purchases with StoreKit `appAccountToken`, verifies Apple's
signed transaction JWS, and records the referrer, referred identity, referral,
transaction, and reward in a replay-resistant ledger. It rejects revoked,
expired, wrong-offer, pre-invite, self-owned, and duplicate transactions and
caps rewards at 12 per calendar year. Rewards are Apple one-time offer codes or
server-signed Apple promotional offers; no local expiration date is edited.

## 3. Analytics — connected, decision made

PostHog project `553459` (US Cloud) is live and receiving events. The pipeline is
verified end to end: app → PostHog → founder dashboard.

**The release build must be built with the key or it will send nothing**, since
`SPEAKIT_ANALYTICS_KEY` defaults to empty:

```bash
xcodebuild ... SPEAKIT_ANALYTICS_KEY=phc_your_project_key
```

Analytics defaults to enabled when a key is present
(`SpeakItAnalytics.configuration` writes `true` when the preference is unset),
with a user-facing off switch in Account & Settings.

Your App Privacy answers must match
`SpeakIt/PrivacyInfo.xcprivacy`, which already declares:

| Data type | Linked to user | Used for tracking | Purpose |
| --- | --- | --- | --- |
| Product Interaction | No | No | Analytics |
| Device ID | No | No | Analytics |
| Purchase History | Yes | No | Analytics; App Functionality |
| User ID | Yes | No | App Functionality |

Answer **No** to "Do you or your third-party partners use data for tracking?"
The client sets `$geoip_disable` and `$process_person_profile: false`, and the
identifier is a locally generated install UUID, not IDFA.

## 4. Privacy policy — draft

**Todo:** deploy `Website/privacy/` at
`https://speakitapp.ca/privacy/` and `Website/support/` at
`https://speakitapp.ca/support/`, confirm that `support@speakitapp.ca` is a real
monitored mailbox, and enter those URLs in App Store Connect. The canonical
policy copy lives in `Website/privacy/index.html`; the draft below must remain
consistent with it.

---

### Speak It Privacy Policy

_Last updated: August 17, 2026_

Speak It is designed to keep what you say on your iPhone.

**No account.** Speak It does not require a profile, email address, or sign-in.
We do not operate a server that stores your thoughts.

**Your library.** Thoughts, tasks, and preferences are stored on your device. If
you turn on iCloud Sync, a copy is kept in your own private iCloud container,
encrypted by Apple. We cannot read it.

**Recordings.** While you speak, a protected recording is held on your device so
capture can be recovered if it is interrupted. It is deleted as soon as your
thought is saved, and you can delete an interrupted recording yourself from
Capture history. Recordings are never uploaded to us.

**Speech recognition.** Transcription uses Apple's Speech framework. Depending
on your device and language, Apple may process audio over an internet
connection. That processing is governed by Apple's privacy policy, not ours.

**Analytics.** If analytics is enabled, Speak It records anonymous product
events — for example that a capture was saved, a task was completed, or a
subscription screen was viewed. Events are identified by a random identifier
generated on your device, not by any account or advertising identifier. Location
lookup is disabled and no user profile is built.

Speak It never transmits recordings, transcripts, task titles, memory text,
names, email addresses, or search terms. The set of events and properties the
app can send is fixed in the app's source code; there is no mechanism for your
own words to be attached to an event. Analytics can be turned off at any time in
Settings. Analytics data is processed by PostHog in the United States.

**Purchases.** Subscriptions are handled entirely by Apple. Speak It never sees
your payment details. The app receives Apple-signed entitlement information so
it can unlock Pro.

**Referrals.** If you choose Give a month. Get a month., Speak It creates a
random referral identifier and credential. The referral service stores that
identifier, referral codes, Apple transaction identifiers and status, product
and offer identifiers, and the minimum reward ledger required to verify rewards
and prevent self-referral, replay, or duplicate claims. It never receives your
thoughts, recordings, tasks, memories, profile fields, contacts, places, or
analytics events. One-time Apple reward codes are encrypted at rest.

Referral records are kept while the program operates and as reasonably needed
to restore rewards, prevent duplicate claims, meet accounting obligations, and
resolve support. A deletion request can be sent to `support@speakitapp.ca`; the
minimum transaction or anti-fraud record needed to prevent the same reward from
being claimed again may be retained.

**Tracking.** We do not track you across apps or websites, sell your data, or
use advertising SDKs.

**Children.** Speak It is not directed to children under 13.

**Contact.** support@speakitapp.ca

---

## 5. Profile naming — done

The optional name and email stored locally in `UserDefaults` are consistently
called a profile. Speak It no longer offers to “Create account,” so the UI
matches the no-account product and avoids implying server-side account creation
or deletion requirements that do not apply.

## 6. Store listing — todo

- Screenshots. The app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), so the
  6.9" set is the one App Store Connect requires; confirm the current required
  sizes there before uploading, since Apple changes them.
- Description, keywords, promotional text, subtitle
- Age rating questionnaire
- Category is already set: `public.app-category.productivity`

### Review notes — draft

> Speak It captures spoken thoughts and sorts them into Today (actions) and
> Memory (things worth finding later). No account is required; all features are
> reachable on first launch.
>
> To test the free tier, capture by tapping the microphone on the Today screen.
> The tenth capture on the account triggers the Pro paywall. The free allowance is a one-time total, not a monthly one.
>
> **Referral testing.** The “Give a month. Get a month.” row is present only in
> the connected Release build. The friend receives Apple's one-month Offer
> Code. Speak It's server awards the referrer only after verifying the App
> Store-signed transaction; sharing or cancelling does not create a reward. No
> entitlement is granted locally. Use the review invite/code supplied in the
> submission notes and the attached Sandbox test account.
>
> Back Tap is an optional convenience, not a requirement. iOS does not allow an
> app to assign Back Tap itself, so the app guides the user to add the included
> "Speak It Capture" shortcut and select it under Settings → Accessibility →
> Touch → Back Tap → Double Tap. All capture methods work without it.
>
> Speech transcription uses Apple's Speech framework and requires microphone and
> speech recognition permission, both requested in context with explanation.
>
> **Why the app requests Always location access.** Speak It supports place
> reminders: a user can say "remind me to take the bins out when I get home" and
> be reminded on arrival. This is region monitoring for places the user chose
> themselves, and a reminder that only worked while the app was open would not
> be a reminder at all — which is why Always is needed rather than While Using.
>
> The permission is requested only at the moment a user creates a place reminder,
> never at launch and never during onboarding, and it is asked for in two steps:
> While Using first, then Always with an in-app explanation of why a reminder has
> to reach the user when the app is closed. Declining leaves the reminder intact
> and simply marked as not currently active — nothing is deleted or disabled. A
> user who never creates a place reminder is never asked for Always at all, and
> setting a Home or Work address needs only While Using.
>
> Speak It does not track the user's movement. It registers a geofence per
> reminder (at most 18 at once) and reacts to crossings; it never requests
> continuous location updates, `allowsBackgroundLocationUpdates` is off, and no
> location history is recorded. Location is processed entirely on device and no
> coordinate, address, or place name is ever transmitted to us or to analytics.
>
> To test: Settings → Capture & reminders → Places → set Home, then capture
> "remind me to take the bins out when I get home". The reminder appears with the
> permission it still needs; granting Always arms it.

## 7. Device QA before submitting — todo

Automated tests cover the repository and organization logic. These cannot be
automated and remain outstanding (see `CAPTURE_STRESS_TEST_PLAN.md`):

- Microphone quality, speech accuracy, call interruptions, AirPods, locked device
- Back Tap end to end — iOS does not expose the gesture to automated tests
- VoiceOver and the largest Dynamic Type sizes; full dark-mode pass
- Sandbox purchase of both plans, Restore Purchases on a second device, and the
  complete friend/referrer offer flow described in section 2A
