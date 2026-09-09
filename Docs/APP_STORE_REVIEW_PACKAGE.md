# App Store Review Package — Speak It 1.0 (build 18)

Prepared 2026-09-09 from the working tree. Every claim below was checked against
the file named beside it. Companion documents: the working checklist in
[APP_STORE_SUBMISSION.md](APP_STORE_SUBMISSION.md), the September 9 evidence in
[CONTINUATION_REVIEW_2026-09-09.md](CONTINUATION_REVIEW_2026-09-09.md), and the
pricing status in [APP_STORE_PRICING_STATUS_2026-09-09.md](APP_STORE_PRICING_STATUS_2026-09-09.md).

Sources of truth used:

- Free tier and Pro moments: `SpeakIt/Features/Setup/SubscriptionStore.swift`
  (`FreePlanAllowance.lifetimeCaptureLimit = 10`, `ProMoment.firstCapture`,
  `ProMoment.runningLowThreshold = 3`) and `SpeakIt/App/RootView.swift`
  (`presentCapture` shows `SpeakItProView(context: .freeLimit)` when
  `canCreateCapture` is false). Tutorial practice is complimentary at the
  source: `CaptureCreationResult.consumesFreeCapture` returns `false` for
  `captureSource == .tutorial` (`SpeakIt/Repositories/ThoughtRepository.swift`).
- Pro screen controls: `SpeakIt/Features/Setup/SpeakItProView.swift` — "Not
  now" at the wall (`dismissTitle`), "Restore Purchases", "Privacy Policy"
  (`https://speakitapp.ca/privacy`), "Terms" (Apple's standard EULA), "Manage
  Subscription", "Redeem Code", purchase detail "Auto-renews until cancelled."
- Audio background mode: `SpeakIt/Info.plist` (`UIBackgroundModes = [audio]`)
  and `SpeechTranscriber.configureAudioSession` (session category set and
  activated only inside `start()` after microphone and speech permission are
  granted; deactivated in `resetRecognitionResources()` when the capture ends).
- Location: `SpeakIt/Repositories/LocationReminderMonitor.swift`
  (`authorizationStep`: When In Use first, then Always, once),
  `SpeakIt/Features/ItemEditor/ItemEditorView.swift` (the only Always button),
  `SpeakIt/Features/Places/CurrentLocationProvider.swift` (When In Use only,
  and only when the person taps "Use my current location"), and
  `SpeakIt/Features/Setup/WelcomeView.swift` (no location permission card).
- Privacy: `SpeakIt/PrivacyInfo.xcprivacy`, `SpeakIt/App/AnalyticsService.swift`,
  `SpeakIt/Features/Capture/SpeechRecognitionBackend.swift`
  (`requiresOnDeviceRecognition = false` on the live `SFSpeechRecognizer`
  path), `SpeechTranscriber.swift` (`CaptureAudioRecovery` sets
  `requiresOnDeviceRecognition = true` and throws
  `onDeviceRecognitionUnavailable` otherwise).
- Referral state: `ReferralProgramConfiguration.isEnabled` is false unless
  `SPEAKIT_REFERRAL_API_URL` is injected; the Plan section then shows the plain
  "Share Speak It" share sheet (`AccountSettingsView.swift`).

---

## 1. Review Notes (paste into App Review Information → Notes)

Character count of the block between the rules: 3,936 (limit 4,000).

---

Speak It is a voice-first notebook. You speak (or type) a thought, and it saves your exact words and files them into one of two places: TODAY, for things to act on (tasks, reminders, overdue and upcoming items, and a "When you have time" list), or MEMORY, for things worth finding later (Pinned, Ideas, People, Reference, Archive). No account or sign-in exists; everything is reachable on first launch and data stays on the device.

FIVE-MINUTE WALKTHROUGH
1. Launch. Tap "Start speaking" for the guided first capture, or "Explore first" to skip it. The tutorial practice captures are free and do not count toward the allowance.
2. Capture by voice: tap the round waveform button at the bottom centre. iOS asks for Microphone and Speech Recognition (both requested in context). Say "Tomorrow at 9, ask Maya about the proposal." Stop speaking; it is saved and lands in Today, due tomorrow at 9, under Maya's name.
3. Capture by typing: open capture and tap "Type instead" (keyboard icon), type "I had an idea for weekly planning to read itself back to me", tap Done. It lands in Memory > Ideas.
4. Tap "Today" and "Memory" in the bottom dock to switch destinations. Tap the circle on a Today row to complete it; tap the row to see the original words.

FREE ALLOWANCE AND PRO
- Ten captures are free in total (a one-time lifetime allowance, not monthly). Practice, completing, cancelling and editing existing items never spend a capture.
- After the first counted capture, a dismissible "Speak It Pro" sheet appears once ("Continue using Speak It free" keeps the free plan). It appears once more when three free captures remain.
- The eleventh capture attempt shows the Pro screen with the plan cards, "Not now", "Restore Purchases", "Privacy Policy" and "Terms" (Apple's standard EULA). "Not now" returns to the app; everything saved stays readable and editable.
- Speak It Pro is a standard auto-renewable subscription in one group: Monthly (com.calvinwak.SpeakIt.pro.monthly) and Annual (com.calvinwak.SpeakIt.pro.annual). Prices come from StoreKit. Account & Settings > Plan opens the same Pro screen, which also offers "Manage Subscription" (Apple's subscriptions page) and "Redeem Code" (Apple's redemption sheet). No Speak It server is involved in purchases.

BACKGROUND MODE: AUDIO
The audio background mode exists for one reason: a capture the person started keeps recording and transcribing if they swipe home or lock the phone mid-sentence, so their words are not cut off. The audio session is active only during a capture. Speak It plays no audio and records nothing outside a capture the person began.

LOCATION
Location is never requested at launch or by onboarding. When In Use is requested only if the person taps "Use my current location" while setting a Home or Work place (dragging the map or searching an address needs no permission). Always is requested only inside a place reminder ("remind me when I get home") after When In Use, with an in-app explanation, because a geofence must fire while the app is closed. Declining keeps the reminder; its row reads "Needs location permission" and the editor offers the way to Settings. No location is transmitted to us. To test: Account & Settings > Capture & reminders > Places, set Home by dragging the map, then capture "remind me to take the bins out when I get home".

OTHER NOTES
- Back Tap is optional: the app cannot assign it and only guides the person to Settings > Accessibility > Touch > Back Tap using the included "Speak It Capture" shortcut.
- Live transcription uses Apple's Speech framework and may be processed by Apple; the app's own interrupted-capture recovery runs on-device only.
- The referral program ("Give a month. Get a month.") is not live in this build; the Plan section shows a plain "Share Speak It" share sheet instead.
- Anonymous analytics are opt-out in Account & Settings > Data & privacy and never contain what the person said or typed.

---

Notes for the person pasting it:

- Replace nothing; the notes describe build 18 as it is in the working tree.
- If smoke case E8 (`Docs/BUILD_14_DEVICE_SMOKE.md`) shows the capture does not
  continue after swipe-home or lock on a physical iPhone, either fix the
  behaviour or remove `audio` from `UIBackgroundModes` and delete the
  "BACKGROUND MODE: AUDIO" paragraph before submitting. The paragraph must not
  describe a behaviour the reviewer cannot reproduce.
- If `SPEAKIT_REFERRAL_API_URL` is injected into the submitted build, replace
  the referral sentence with the section 2A copy from
  `APP_STORE_SUBMISSION.md` and attach the Sandbox invite.

## 2. Age rating questionnaire

App Store Connect's questionnaire was revised in 2025 (ratings 4+, 9+, 13+,
16+, 18+; existing apps had to re-answer by January 31, 2026). Answer every
question below; if App Store Connect shows a question not listed here, the
same reasoning applies — Speak It contains only what the person says or types
to themselves, and no supplied content.

| Question | Answer | Why |
| --- | --- | --- |
| Cartoon or Fantasy Violence | None | No characters, stories, or imagery. |
| Realistic Violence | None | No depictions of any kind. |
| Prolonged Graphic or Sadistic Realistic Violence | None | Same. |
| Violent Themes | None | Same. |
| Profanity or Crude Humor | None | The app supplies no language; the person's own words are private to their device. |
| Mature or Suggestive Themes | None | No supplied content. |
| Horror or Fear Themes | None | No supplied content. |
| Sexual Content or Nudity | None | No supplied content. |
| Graphic Sexual Content and Nudity | None | No supplied content. |
| Alcohol, Tobacco, or Drug Use or References | None | No supplied content. |
| Medical or Treatment Information | None | A notebook; no health guidance. |
| Gambling (simulated) | None | No games or chance mechanics. |
| Contests | No | None offered. |
| Gambling (real money) | No | None. |
| Unrestricted Web Access | No | No web view or browser; the only links open Safari to the privacy policy, Apple's EULA, and Apple's subscription pages. |
| Loot Boxes | No | None. |
| In-App Advertising | No | No ads or ad SDKs. |
| User-Generated Content (shared with others) | No | Captures stay on the person's device; there is no feed, sharing to other users, or server. The share sheet only invokes iOS sharing of an app link. |
| Messaging and Chat | No | No user-to-user communication. Reminder texts open the iOS Messages composer for the person to send themselves. |
| Parental Controls | No | None built in. |
| Age Assurance | No | None; the app is not directed to children and has no age gate. |
| Made for Kids | No | Not directed to children under 13 (privacy policy says so). |

Expected result: **4+** in every territory, with no age-assurance or
parental-control declarations.

## 3. App Privacy answers

Source of truth: `SpeakIt/PrivacyInfo.xcprivacy` (`NSPrivacyTracking = false`,
no tracking domains). Analytics is entirely off unless the build was made with
`SPEAKIT_ANALYTICS_KEY=phc_...`; the key defaults to empty in Debug and Release.
The declarations below describe the connected Release build so that App Store
Connect matches the manifest whether or not a key is injected.

First question — "Do you or your third-party partners collect data from this
app?" — **Yes.** "Do you or your third-party partners use data for tracking?"
— **No.** The client sets `$geoip_disable = true` and
`$process_person_profile = false`, and the identifier is a random install UUID
generated on device (`SpeakItAnalytics.anonymousInstallID`), never IDFA. There
is no third-party SDK; the app posts JSON to PostHog with `URLSession` and the
property keys are a closed allowlist (`allowedPropertyKeys`).

| Apple data type | Collected? | Linked to identity? | Used for tracking? | Purpose and evidence |
| --- | --- | --- | --- | --- |
| Contact Info — Name | Not collected | — | — | The optional profile name lives in `UserDefaults` on device and is never sent. |
| Contact Info — Email Address | Not collected | — | — | Same as name. |
| Contact Info — Phone Number | Not collected | — | — | Never requested. |
| Contact Info — Physical Address | Not collected | — | — | Home/Work places stay on device; Apple Maps search is Apple's processing, not ours. |
| Contact Info — Other User Contact Info | Not collected | — | — | — |
| Health & Fitness — Health / Fitness | Not collected | — | — | Not requested. |
| Financial Info — Payment Info / Credit Info / Other | Not collected | — | — | Apple handles payment; the app never sees payment details. |
| Location — Precise Location | Not collected | — | — | Geofences are evaluated on device; the closed vocabulary in `AnalyticsService.swift` has no location event or property. |
| Location — Coarse Location | Not collected | — | — | Same; `$geoip_disable` prevents server-side IP location. |
| Sensitive Info | Not collected | — | — | — |
| Contacts | Not collected | — | — | Contacts framework is not used. |
| User Content — Emails or Text Messages | Not collected | — | — | Messages are composed by the person in iOS Messages; the app sends nothing. |
| User Content — Photos or Videos | Not collected | — | — | Not accessed. |
| User Content — Audio Data | **Not collected by the developer** | — | — | Recordings never leave the phone to us. Live dictation may be processed by Apple's Speech service (`SpeechRecognitionBackend.swift` sets `requiresOnDeviceRecognition = false` on the `SFSpeechRecognizer` path; the iOS 26 `SpeechAnalyzer` path is on-device). The app's own recovery of an interrupted capture (`CaptureAudioRecovery`) requires on-device recognition and refuses otherwise. Apple's processing is disclosed in the privacy policy under Apple's terms and is not developer collection. |
| User Content — Gameplay Content | Not collected | — | — | — |
| User Content — Customer Support | Not collected | — | — | Support is by email outside the app. |
| User Content — Other User Content | Not collected | — | — | Transcripts, titles, memory text, and search terms are never transmitted; the analytics vocabulary cannot carry free text. |
| Browsing History | Not collected | — | — | No web view. |
| Search History | Not collected | — | — | Memory search reports only a result-count bucket (`memory_search_performed`), never the query. |
| Identifiers — User ID | **Collected** | **Yes** | No | App Functionality. The referral program mints a random `appAccountToken` UUID and credential that the referral service uses to verify Apple-signed rewards (`ReferralService.swift`). It is transmitted only when the program is configured; it is declared because the manifest declares it. |
| Identifiers — Device ID | **Collected** | No | No | Analytics. The random install UUID (`distinct_id`), not IDFA or IDFV. Declared as Device ID because it identifies an install. |
| Purchases — Purchase History | **Collected** | **Yes** | No | Analytics and App Functionality. Content-free purchase events (`purchase_started`, `purchase_completed`, `purchases_restored` with `plan` / `has_pro`) and, when the referral service is configured, Apple transaction identifiers bound to the `appAccountToken`. |
| Usage Data — Product Interaction | **Collected** | No | No | Analytics. Screen views, capture started/saved counts, task completion, collection opened, onboarding steps — all from the closed event list in `AnalyticsService.swift`. |
| Usage Data — Advertising Data | Not collected | — | — | No ads. |
| Usage Data — Other Usage Data | Not collected | — | — | Everything sent is covered by Product Interaction. |
| Diagnostics — Crash Data | Not collected | — | — | No crash reporter; Apple's opt-in crash reports are Apple's collection. |
| Diagnostics — Performance Data | **Collected** | No | No | Analytics. `capture_performance` latency buckets (`capture_ready_ms`, `transcription_ms`, `persistence_ms`, and so on) and `speech_capture_quality` audio-level buckets (`rms_bucket`, `peak_bucket`, `clipping_bucket`, `duration_bucket`). No audio content. |
| Diagnostics — Other Diagnostic Data | **Collected** | No | No | Analytics. `capture_failed` with a closed `error_category` (`storage`, `organization`, `speech`, `network`, `unknown`). |
| Surroundings — Environment Scanning | Not collected | — | — | — |
| Body — Hands / Head | Not collected | — | — | — |
| Other Data | Not collected | — | — | — |

Two rows are new for this build and must be added in App Store Connect →
App Privacy: **Performance Data** and **Other Diagnostic Data** (both
Analytics, not linked, not tracking). `ReleaseReadinessTests` reads the built
manifest, so the ASC answers and the manifest are checked against each other.

Optional-collection note: App Store Connect lets each type be marked "optional
collection" when the person can decline. Analytics is opt-out in Account &
Settings, so Product Interaction, Device ID, Performance Data, Other Diagnostic
Data, and the analytics half of Purchase History may be marked optional; User
ID is only created when the person opens the referral flow.

## 4. Export compliance

`SpeakIt/Info.plist` sets `ITSAppUsesNonExemptEncryption = false`, so App
Store Connect will not ask the encryption questions for each build. This is the
correct answer because:

- The only network traffic is HTTPS through `URLSession` (PostHog analytics
  when a key is injected; the referral service when configured; Apple Maps
  search through MapKit; StoreKit through Apple). Standard TLS provided by the
  operating system is exempt.
- Local storage uses Apple data protection and the Keychain (the free-capture
  ledger). The binary links no CryptoKit, CommonCrypto, or custom cipher code
  (verified in `APP_STORE_SUBMISSION.md`, section 2).
- The separately deployed referral server encrypts Apple offer codes at rest
  with Node's AES-256-GCM; that code is not part of the iOS binary and does
  not affect the app's classification.

If App Store Connect ever prompts anyway, the answers are: "Does your app use
encryption?" Yes; "Does it qualify for any of the exemptions?" Yes — it only
uses encryption provided by the OS (HTTPS) and does not implement proprietary
cryptography. No French import declaration or annual self-classification report
is required for exempt use.

## 5. Content Rights

App Store Connect → App Information → Content Rights: **"Does your app contain,
show, or access third-party content?" — No.** Every piece of content is
written or spoken by the person using the app and stays on their device. The
tutorial example sentences, onboarding copy, and icons are original or Apple SF
Symbols under Apple's license. No licensed music, video, news, or third-party
text is displayed.

## 6. EU Digital Services Act trader declaration

Because Speak It sells auto-renewable subscriptions, Calvin is a **trader** under
the DSA and must declare it before the app can be offered on EU storefronts.
Apple removed undeclared paid apps from the EU App Store in February 2025, and
a new app cannot be made available in the EU until the status is verified.

Where: App Store Connect → **Business** (or Agreements, Tax, and Banking →
"Complete Compliance Requirements") → Digital Services Act → Trader Status.
Then in the app's **App Information** page confirm the trader contact shown
for the EU.

What to enter (as the sole proprietor behind the Apple Developer account):

1. Trader status: **I am a trader.**
2. Legal name exactly as on the developer account and bank record.
3. Business address — this is **published on the EU product page**, so use a
   business or mailing address you are willing to make public, not necessarily
   a home address.
4. Phone number and email address, both verified through the codes Apple sends.
   These are also published for EU customers.
5. Optionally the Canadian business/tax registration number if Apple asks for a
   trade register identifier.

Once verified, set EU territories to available in Pricing and Availability. If
Calvin prefers not to publish contact details, the alternative is to exclude the
27 EU countries from availability, which the notes in
`APP_STORE_SUBMISSION.md` do not currently plan for.

## 7. App Store Connect field-by-field checklist

App Information

- [ ] Name: Speak It. Subtitle (28 / 30): "Say it before you forget it." — the same line as `APP_STORE_LISTING.md` and the website headline.
- [ ] Primary category: Productivity (`LSApplicationCategoryType` already matches). Secondary: Utilities (optional).
- [ ] Content Rights: No third-party content (section 5).
- [ ] Age Rating: questionnaire from section 2 → 4+.
- [ ] License Agreement: keep **Apple's Standard EULA**. The app's "Terms" link already points to `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`; do not upload a custom EULA or the in-app link becomes wrong.
- [ ] Privacy Policy URL: `https://speakitapp.ca/privacy` (the app links this exact URL from the Pro screen and the Privacy explainer; `Website/privacy/index.html` must be deployed there first).
- [ ] Privacy Choices URL: leave blank (no sell/share choices; analytics opt-out is in-app).
- [ ] Bundle ID: `com.calvinwak.SpeakIt` on the paid team, with `com.calvinwak.SpeakIt.LiveActivity`, `com.calvinwak.SpeakIt.ShareExtension`, app group `group.com.calvinwak.SpeakIt`, iCloud container `iCloud.com.calvinwak.SpeakIt`.

App Privacy

- [ ] "Collect data": Yes. "Tracking": No.
- [ ] Product Interaction — Analytics, not linked, not tracking.
- [ ] Device ID — Analytics, not linked, not tracking.
- [ ] **Performance Data — Analytics, not linked, not tracking (new).**
- [ ] **Other Diagnostic Data — Analytics, not linked, not tracking (new).**
- [ ] Purchase History — Analytics + App Functionality, linked, not tracking.
- [ ] User ID — App Functionality, linked, not tracking.
- [ ] Every other type: Not collected. Audio Data: not collected (section 3).
- [ ] Publish the privacy answers before submitting the build.

Pricing and Availability

- [ ] App price: Free.
- [ ] Availability: all territories, EU only after the DSA declaration (section 6).
- [ ] Pre-orders: none.

Subscriptions (Features → Subscriptions)

- [ ] One subscription group ("Speak It Pro") containing `com.calvinwak.SpeakIt.pro.monthly` ($2.99, no introductory or sale price, ever) and `com.calvinwak.SpeakIt.pro.annual` ($14.99 launch price; $29.99 standard, scheduled after approval — section 8).
- [ ] Each product: localized display name, description, review screenshot, and status "Ready to Submit"; both attached to the 1.0 version under "In-App Purchases and Subscriptions" (a first submission must ship them with the binary).
- [ ] `com.calvinwak.SpeakIt.pro.lifetime` non-consumable exists for offer codes only; it is not merchandised and need not be attached to the version.
- [ ] Offer codes `CALVINMONTH` / `CALVINYEAR` are optional and must not appear in the notes.
- [ ] Do not create the referral offer codes or promotional offers for this submission; the program is off (section 2A of `APP_STORE_SUBMISSION.md`).

Version 1.0 page

- [ ] Screenshots: 6.9-inch iPhone set (the app is iPhone-only, `TARGETED_DEVICE_FAMILY = 1`); confirm the required sizes in ASC on the day. Show Today, Memory, capture, and the Pro screen with the real StoreKit price.
- [ ] Promotional text, description, keywords (100 chars), what's new (not shown for 1.0).
- [ ] Support URL: `https://speakitapp.ca/support` (deploy `Website/support/index.html`; `support@speakitapp.ca` must be a monitored mailbox).
- [ ] Marketing URL: `https://speakitapp.ca`.
- [ ] Version: 1.0. Copyright: "2026 Calvin Salsali".
- [ ] Build: 18 (`CURRENT_PROJECT_VERSION = 18` on all targets; `APP_STORE_SUBMISSION.md` still says 13 and needs its owner to update it).
- [ ] App Review Information: contact first/last name, phone, email; **Sign-in required: No**; Notes: section 1 text; attachment: none required (add the E8 screen recording if available).
- [ ] Version release: Manually release this version (so the annual price schedule can be entered before customers see it).
- [ ] Advertising Identifier (IDFA): No.
- [ ] Export compliance: handled by the plist key (section 4); nothing to answer.
- [ ] Routing app coverage file: none.
- [ ] Game Center, Sign in with Apple: not applicable.

Agreements, Tax, and Banking

- [ ] Paid Apps agreement Active (done August 11, 2026), bank and tax forms Active (done).
- [ ] DSA trader declaration completed and verified (section 6).

TestFlight

- [ ] Beta App Review approved for an external group before the App Store submission so the notes and the paywall have been seen by a reviewer once.

## 8. Pre-submission checklist — needs a human

Everything below is outside what automation on this Mac can verify.

- [ ] **Sandbox purchase of both plans** on a physical iPhone with a Sandbox Apple Account: Monthly and Annual each purchase, show "Speak It Pro" in Plan, remove the free counter, and survive kill/relaunch. Confirm the annual card shows Apple's localized price and that the "BEST VALUE" badge sits on annual only.
- [ ] **Restore Purchases on a second device** signed into the same Sandbox account restores Pro without a purchase; also test on the first device after deleting and reinstalling the app.
- [ ] **Eleventh-attempt wall**: spend ten counted captures (tutorial practice does not count), confirm the two Pro moments appeared once each (after capture one and at three remaining), then confirm the eleventh attempt shows the Pro screen with "Not now" and that "Not now" leaves every saved item readable.
- [ ] **Physical-iPhone microphone QA**: quiet room, noisy room, AirPods, a phone call interrupting a capture, and a capture that is stopped by a Siri or alarm interruption; the transcript must survive or the interrupted draft must appear in Capture history.
- [ ] **Back Tap**: add the "Speak It Capture" shortcut under Settings → Accessibility → Touch → Back Tap and confirm capture opens from the Home Screen and from another app; iOS does not expose this to automated tests.
- [ ] **Notifications and alarms**: a "remind me tomorrow at 9" reminder fires on a locked device; a "set an alarm" request creates an AlarmKit alarm on iOS 26; the Lock Screen task-name toggle hides names when off.
- [ ] **Smoke case E8** (`Docs/BUILD_14_DEVICE_SMOKE.md`): start a capture, swipe home mid-sentence, keep talking, return — the words must still be there; repeat with the lock button. If the capture does not continue, remove `audio` from `UIBackgroundModes` and the background-mode paragraph from the notes before submitting.
- [ ] **Place reminder permission ladder** on a device: set Home by dragging the map (no prompt), capture "remind me when I get home", confirm the editor offers "Allow location access" (When In Use) and then "Allow background location" (Always), and that declining leaves the reminder present, labelled "Needs location permission".
- [ ] **TestFlight external build**: archive on the paid team, upload build 18, pass Beta App Review, install through TestFlight, and confirm the app group (Live Activity, share extension) and iCloud container work in the signed build.
- [ ] **DSA trader declaration** completed and verified in App Store Connect (section 6) before selecting EU availability.
- [ ] **App Privacy** in App Store Connect updated with Performance Data and Other Diagnostic Data, then republished.
- [ ] **Metadata**: Privacy Policy URL, Support URL, EULA choice, screenshots, and the 4+ rating entered as in section 7; the privacy and support pages actually resolve over HTTPS.
- [ ] **October 22 annual price schedule — after approval only**: once the annual subscription is live, schedule `com.calvinwak.SpeakIt.pro.annual` from $14.99 to $29.99 starting October 22, 2026 (the app cutoff is `2026-10-22T04:00:00Z`), preserving the current price for existing subscribers; App Store Connect refuses the schedule while the product is still in "Prepare for Submission". Only then build Release with `SPEAKIT_SUMMER_SALE_ENABLED=YES` and set `SUMMER_SALE_ENABLED = true` in `Website/assets/stage.js`.
- [ ] **Owner-locked documents** (not edited by this package): update `Docs/APP_STORE_SUBMISSION.md` build number to 18, correct its draft notes ("tenth capture triggers the paywall" → the eleventh attempt, with dismissible Pro sheets after the first counted capture and at three remaining), add the audio background-mode justification, add the EULA and privacy links to its checklist, and add `APP_STORE_REVIEW_PACKAGE.md` to the `Docs/README.md` index.
