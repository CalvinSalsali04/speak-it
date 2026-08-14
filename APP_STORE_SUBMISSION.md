# App Store Submission

Working document for the first Speak It release. Status values: **Done**,
**Blocked** (needs an Apple account or a hosted page), **Todo**.

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
  - `com.calvinwak.SpeakIt.pro.monthly` — $1.99 / month
  - `com.calvinwak.SpeakIt.pro.annual` — $14.99 / year
  App Store Connect is the source of truth for live localized prices. The app
  renders `product.displayPrice`, so whatever is configured there is shown.
  Each subscription also needs a localized display name, description, and a
  review screenshot before it can be submitted.

## 2. Build configuration — done

- **Done:** `MARKETING_VERSION` is `1.0` across the app, Live Activity
  extension, Share extension, and UI tests. Verified in the built product:
  `SpeakIt.app`, `SpeakItLiveActivity.appex`, and `SpeakItShareExtension.appex`
  all report `1.0`. Build number stays at `10`.
- **Done:** `ITSAppUsesNonExemptEncryption` is `false` in `SpeakIt/Info.plist`,
  so uploads no longer stall on the export-compliance question. Verified correct:
  the app uses only HTTPS and Apple data protection. There is no CryptoKit,
  CommonCrypto, or custom cryptography anywhere in the source.
- **Done:** `SpeakIt/SpeakIt.storekit` defines both subscriptions and is wired
  into the shared scheme's Run action. It is a project file reference only, in
  no build phase, and was confirmed absent from the built `.app` bundle.
- **Done:** `SPEAKIT_ANALYTICS_KEY` defaults to empty in Debug and Release, so
  no build transmits analytics unless a key is deliberately injected.
- **Done:** External capture text is clamped to `CaptureTextLimit`
  (20,000 characters) at all three untrusted boundaries: the Share extension,
  the Save Thought App Intent, and the shared-inbox import.
- **Done:** Security sweep of the shipping binary — no secrets, no debug
  logging, no developer paywall override, no ATS exceptions, no WebView.
- **Done:** 104 unit tests and 9 UI tests passing; Release build clean.

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
| Purchase History | No | No | Analytics |

Answer **No** to "Do you or your third-party partners use data for tracking?"
The client sets `$geoip_disable` and `$process_person_profile: false`, and the
identifier is a locally generated install UUID, not IDFA.

## 4. Privacy policy — draft

**Todo:** host this at a public URL and enter it in App Store Connect. A support
URL is required too; a single page can carry both. Replace the contact address
before publishing.

---

### Speak It Privacy Policy

_Last updated: [DATE]_

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
your payment details.

**Tracking.** We do not track you across apps or websites, sell your data, or
use advertising SDKs.

**Children.** Speak It is not directed to children under 13.

**Contact.** [YOUR SUPPORT EMAIL]

---

## 5. Open decision: the word "account"

`AccountSettingsView` says "Create your account" / "Create Account" in four
places, but Speak It has no accounts — the profile is a name and email in
`UserDefaults` that never leaves the device.

Apple's Guideline 5.1.1(v) requires in-app account **deletion** for apps that
support account creation. "Remove profile from this iPhone" almost certainly
satisfies a reviewer, so this is a low risk rather than a blocker. Renaming the
four strings to "profile" removes the ambiguity entirely and costs nothing.

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
> Back Tap is an optional convenience, not a requirement. iOS does not allow an
> app to assign Back Tap itself, so the app guides the user to add the included
> "Speak It Capture" shortcut and select it under Settings → Accessibility →
> Touch → Back Tap → Double Tap. All capture methods work without it.
>
> Speech transcription uses Apple's Speech framework and requires microphone and
> speech recognition permission, both requested in context with explanation.

## 7. Device QA before submitting — todo

Automated tests cover the repository and organization logic. These cannot be
automated and remain outstanding (see `CAPTURE_STRESS_TEST_PLAN.md`):

- Microphone quality, speech accuracy, call interruptions, AirPods, locked device
- Back Tap end to end — iOS does not expose the gesture to automated tests
- VoiceOver and the largest Dynamic Type sizes; full dark-mode pass
- Sandbox purchase of both plans, plus Restore Purchases on a second device
