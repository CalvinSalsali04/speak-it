# App Store readiness pass — 2026-09-09 (build 18)

This is the completeness record for the readiness pass run on 2026-09-09. It lists what was verified and how, what was fixed, what was deferred, and exactly what still has to be done by hand before Submit. Numbers are the ones reported by the individual stages; where a check was not run, it says "not run".

Companion documents produced today (both untracked, new):

- `Docs/APP_STORE_LISTING.md` — the store listing copy (name, subtitle, promotional text, description, keywords, What's New, URLs, categories, subscription group and product names/descriptions, promotional image spec, six screenshot captions).
- `Docs/APP_STORE_REVIEW_PACKAGE.md` — Review Notes, age-rating answers, App Privacy table, export compliance, Content Rights, DSA steps, App Store Connect field checklist, human pre-submission checklist.

## 1. What was verified today, and how

### Listing copy (`Docs/APP_STORE_LISTING.md`)

Character limits validated by script, then re-checked by the critic stage:

| Field | Count / limit |
| --- | --- |
| App name | 8 / 30 ("Speak It") |
| Subtitle | 28 / 30 ("Say it before you forget it.") |
| Promotional text | 156 / 170 |
| Description | 3,682 / 4,000 |
| Keywords | 95 / 100, 14 terms, no spaces, no duplicates, no name/subtitle words |
| Subscription group | 12 / 30 ("Speak It Pro") |
| Monthly product name / description | 20 / 30, 35 / 45 |
| Annual product name / description | 19 / 30, 34 / 45 |
| Screenshot captions (6) | 28–36 / 40 each |

Content checks on the description: contains the verbatim sentence "Live dictation may be processed by Apple's speech service.", the Apple standard EULA link, and `https://speakitapp.ca/privacy`; no price, no emoji, no "coming soon", no competitor names, no referral promise. Every feature claim in the description was checked against source by the critic (AlarmKit, EventKit editor, Messages composer, ControlWidget on iOS 18, accessory widgets, Live Activity, share extension, App Shortcuts, iCloud ubiquity container, idea stages, Lock Screen names toggle, shopping split, undo, tutorial captures free, 10-capture ledger).

Total word count of the listing file: 1,958.

### Review package (`Docs/APP_STORE_REVIEW_PACKAGE.md`)

- Review Notes measured at 3,936 characters after the critic's corrections (limit 4,000; first draft was 3,862).
- Facts in the Review Notes were checked against `SubscriptionStore`, `SpeakItProView`, `RootView`, `Info.plist`, `SpeechTranscriber`, `LocationReminderMonitor`, `ItemEditorView`, `CurrentLocationProvider`, `WelcomeView`, `ReferralService`, `ThoughtRepository` (tutorial captures do not consume the free allowance), `CapturedItemRow` (completion is by tapping the circle, not swipe), and `LocationIntent.listLabel` ("Needs location permission").
- The "Maya" walkthrough step was corrected using the pipeline probe: the sentence lands in Today as a person follow-up due tomorrow at 09:00 with no reminder delivery.
- App Privacy table cross-checked against `PrivacyInfo.xcprivacy` (ProductInteraction, DeviceID, PerformanceData, OtherDiagnosticData not linked; PurchaseHistory, UserID linked; tracking false) and against `requiresOnDeviceRecognition = false` on the live `SFSpeechRecognizer` path / `true` in `CaptureAudioRecovery`.
- `UIBackgroundModes = [audio]` confirmed in `SpeakIt/Info.plist`, with audio-session activation only in `start()` and deactivation in `resetRecognitionResources()`.
- Location prompts confirmed to originate only from `CurrentLocationProvider` (When In Use) and `LocationReminderMonitor` (When In Use, then Always once); none in `WelcomeView`.

### Screenshots (`output/app-store-screenshots/`, gitignored)

- 14 PNGs (7 light, 7 dark), every one verified 1320x2868 with `sips -g pixelWidth -g pixelHeight`.
- 10 of the 14 were visually inspected (light 01, 02, 03, 04, 05, 06, 07; dark 03, 04, 05): real app content, no blank frames, no permission dialogs. The other 4 (dark 01, 02, 06, 07) were size-checked only.
- Produced by `Tools/Screenshots/capture.sh` (new) on simulator `51F14279-8FCD-4292-A24E-959F498BD9C3`, Debug build with `CODE_SIGNING_ALLOWED=NO`, status bar overridden to 9:41 / full battery / 4 bars / 3 Wi-Fi bars and cleared afterwards (`status_bar list` empty). Screens 01/03/04/07 via `simctl launch` + `simctl io screenshot`; screens 02/05/06 via the new UI test `SpeakItUITests/AppStoreScreenshotTests.testCapturesAppStoreScreenshots`. The final end-to-end run of the script exited 0 and the UI test passed.
- 07-pro rendered real App Store plan cards on the simulator (annual $14.99 with $29.99 struck through, monthly $2.99, "SUMMER LAUNCH SALE"); no purchase was made.
- `output/app-store-screenshots/README.md` records the six-image upload order: 03 Today, 02 Capture, 04 Memory, 05 Person, 06 Reminder setting, 01 Welcome (07 kept for the record).

### UI test suite

- Final run on a clean simulator (iPhone 17 Pro `D7B5E33A-2D4B-44F3-A423-408D9A142EF9`, iOS 26.5, derived data `/tmp/SpeakItClaudeUITests`): 26 total / 25 passed / 0 failed / 1 skipped / 475.8 s / `xcodebuild` exit 0. Bundle `/tmp/SpeakItClaudeUITests/ui-run-2.xcresult`.
- The skip is `AppStoreScreenshotTests.testCapturesAppStoreScreenshots` (`XCTSkip` because `SPEAKIT_SCREENSHOT_DIR` is unset); intentional.
- First run was 24 passed / 1 failed / 1 skipped: `testFirstInstallAppearanceDefaultsToLight` (`SpeakItUITests.swift:612`). Reproduced deterministically on rerun, then traced to a stale simulator-user-level plist (`~/Library/Developer/CoreSimulator/Devices/D7B5…/data/Library/Preferences/com.calvinwak.SpeakIt.plist`, dated 2026-09-03) holding `SpeakIt.appearance = dark`, which `--ui-testing-reset` cannot clear because it only removes `UserDefaults.standard` keys. Environment fix applied on that simulator (`simctl spawn … defaults delete com.calvinwak.SpeakIt SpeakIt.appearance`; plist backed up in the session scratchpad); the test then passed alone and in the full suite. No repository change. Not an app defect.
- No contention kills occurred although three `SpeakIt-Slim-*` simulators were booted by other sessions.

### Build checks

Run after the fixes and the doc edits, in sequence on an otherwise idle Mac (evening of 2026-09-09):

| Check | Result |
| --- | --- |
| `./Tools/CI/corpus-gate.sh` | 1,381 cases, 0 failing, 0 blocking |
| `./Tools/CI/unit-tests.sh` (full, stock iPhone 17 simulator) | 806 tests: 805 passed, 0 failed, 1 skipped (`/tmp/SpeakItClaudeTests/Logs/Test/Test-SpeakIt-2026.09.09_19-14-31-+0800.xcresult`) |
| Focused reruns of the five touched classes | `SwiftDataThoughtRepositoryTests` 300, `DurabilityTests` 34, `ReleaseReadinessTests` 11, `LocationReminderTests` 67, `ActionabilityTests` 18: all passed |
| `./Tools/CI/release-build.sh` (unsigned, generic iOS) | passed |
| `xcodebuild -exportArchive` with `Tools/CI/ExportOptions.plist` (destination upload) | `Upload succeeded`, `EXPORT SUCCEEDED`; build 1.0 (18) processing in App Store Connect |
| `xcodebuild archive` (Release, automatic signing, team LZZT2A38SD) | `/tmp/SpeakItArchive18/SpeakIt.xcarchive`: `CFBundleVersion` 18, `1.0`; entitlements carry `group.com.calvinwak.SpeakIt`, `iCloud.com.calvinwak.SpeakIt`, ubiquity container and KV store; both `.appex` bundles embedded. Not exported, not uploaded. |
| Debug build for the screenshot run and for the UI suite | passed (part of `capture.sh` and `unit-tests.sh SpeakItUITests`) |

## 2. Fixes applied today (working tree, uncommitted)

1. `SpeakIt/Repositories/Actionability.swift` — `withoutFrontedCondition` guarded against a backwards closed range on "every time I sneeze" / "as soon as I can", which trapped at save time on every capture path; regression test `testAFrontedConditionWithNoBodyIsLeftAlone` added to `SpeakItTests/ActionabilityTests.swift`.
2. `SpeakIt/Repositories/SwiftDataThoughtRepository.swift` — launch recovery counts attempts per capture (`CaptureRecoveryAttemptLedger` in `UserDefaults`); after two lost launches a capture is quarantined as its durable Needs-review row instead of being re-read, for unorganized sessions and interrupted drafts; three tests in `SpeakItTests/SwiftDataThoughtRepositoryTests.swift`.
3. `SpeakIt/Features/Setup/WelcomeView.swift` — onboarding permissions page and readiness view no longer offer the Location card; When In Use → Always is only requested from the place-reminder editor.
4. `SpeakIt/Features/Capture/SpeechTranscriber.swift`, `CaptureDraftStore.swift`, `SpeechRecognitionBackend.swift` — audio recovery of a protected recording requires on-device recognition and refuses with alert kind `onDeviceRecognitionUnavailable` when the locale has no local model; test added in `SpeakItTests/DurabilityTests.swift`.
5. `SpeakIt/PrivacyInfo.xcprivacy` — declares Performance Data and Other Diagnostic Data (not linked, not tracking, purpose Analytics) to match `capture_performance` / `speech_capture_quality` / `capture_failed`; `SpeakItTests/ReleaseReadinessTests.swift` reads the built manifest.
6. `SpeakIt.xcodeproj/project.pbxproj` — removed the inert `INFOPLIST_KEY_*` settings (including a "location" background mode that never shipped) so `SpeakIt/Info.plist` is the only Info.plist source, declaring `UIBackgroundModes = [audio]`; `SpeakItTests/LocationReminderTests.swift` asserts the built bundle.
7. `SpeakIt.xcodeproj/project.pbxproj` — 4 lines added for `SpeakItUITests/AppStoreScreenshotTests.swift` (build file `AA0000000000000000000002`, file reference `AB0000000000000000000003`, group child, Sources entry); both IDs verified 24 hex chars, `plutil -lint` OK.
8. `Tools/Screenshots/capture.sh` (new, executable) and `SpeakItUITests/AppStoreScreenshotTests.swift` (new) — repeatable App Store screenshot pipeline.
9. `Docs/APP_STORE_LISTING.md` and `Docs/APP_STORE_REVIEW_PACKAGE.md` (new) — listing and review package, with the critic's corrections applied (bare-host URLs, Maya step, Plan/Restore wording, "Needs location permission" label and Places settings path, subtitle placeholder, Precise Location citation).

## 3. Findings deferred to a human or blocked by a locked file

Locked files were off-limits to every stage of this pass because another agent is editing the tree concurrently.

| Finding | Where it belongs | Why deferred |
| --- | --- | --- |
| Build number reads 13; it is 18. | `Docs/APP_STORE_SUBMISSION.md` | Done later the same day: the file now says 18. |
| Review Notes draft says the tenth capture triggers the paywall; it is the eleventh attempt, with dismissible Pro sheets after the first counted capture and at three remaining. | `Docs/APP_STORE_SUBMISSION.md` §6 | Done later the same day: the draft now states the eleventh attempt and the two dismissible sheets, and §6 points at the package as the superseding text. |
| Review Notes need the audio background-mode justification. | `Docs/APP_STORE_SUBMISSION.md` | Done later the same day: paragraph added, with the E8 caveat. |
| Review Notes must not claim location is never asked during onboarding; the readiness step still offers "Home location — Add Home" (`WelcomeView.swift` ~line 1585), whose "Use my current location" button requests When In Use. Correct wording: never at launch or by onboarding itself; When In Use only if the person taps that button. | `Docs/APP_STORE_SUBMISSION.md`, App Store Connect Review Notes | Done later the same day in the submission doc; paste the package wording into App Store Connect. |
| Store listing todo line "Description, keywords, promotional text, subtitle" can point at `Docs/APP_STORE_LISTING.md`. | `Docs/APP_STORE_SUBMISSION.md` §6 | Done later the same day. |
| Index rows for `APP_STORE_LISTING.md`, `APP_STORE_REVIEW_PACKAGE.md`, and this file. | `Docs/README.md` | Done later the same day, plus the pricing-status doc. |
| Metadata checklist needs the EULA link (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`) and privacy policy link (`https://speakitapp.ca/privacy`). | `Docs/APP_STORE_SUBMISSION.md`, App Store Connect | Checklist item added to the submission doc later the same day; App Store Connect still needs the values entered. |
| App Privacy must add Performance Data and Other Diagnostic Data. | App Store Connect | External service; not mutated by this pass. |
| Share-inbox retry in `RootView.swift` still retries on every foreground with no attempt ledger (unlike the capture recovery fix). | `SpeakIt/App/RootView.swift` | File locked; reported for the owner. |
| Smoke case E8 (capture continues after swipe-home / lock) is unverified. If it fails, remove the `audio` background mode and the matching Review Notes paragraph. | Physical iPhone | Device-only. |
| `Website/support/index.html` and `Website/privacy/index.html` must be live at the bare host `speakitapp.ca`; `www` should redirect or not be advertised. The listing and the app (`SpeakItProView.privacyPolicy`) both use the bare host. | Website deploy | Outside the app; deploy not authorized in this task. |
| 01-welcome showed the Debug-only "Load test examples" row (`WelcomeView.swift`, `#if DEBUG`). | Screenshot set | Done later the same day: the row is hidden under a `--screenshots` launch argument that `capture.sh` passes for the welcome shot; the full set was re-shot (14 files, all 1320x2868) and both welcome images inspected. |
| The stale simulator-user-level plist on `D7B5…` still carries `hasCompletedWelcome=1`, `captureAnywhereMethod=backTap`, `firstCaptureTutorialStep=2`, `shouldResumeFirstCaptureGuide=0`; a future first-install assertion on any of these would be shadowed the same way. | Simulator environment / `Docs/KNOWN_ISSUES.md` | Only the `appearance` key was deleted; the shadowing is now recorded in `KNOWN_ISSUES.md` (UI validation) together with the share-inbox retry gap. |
| Package §7/§8 contain $2.99 / $14.99 / $29.99 as internal ASC checklist values. | `Docs/APP_STORE_REVIEW_PACKAGE.md` | Not public copy; left as is. ASC remains the price source of truth. |

## 4. Screenshot set status

- Set: 14 PNGs, 7 per appearance, all 1320x2868 (6.9" class). README with per-file descriptions and upload order present.
- Ready to upload: 02, 03, 04, 05, 06 in both appearances (10 files inspected or size-checked as above).
- Not ready: 01-welcome (Debug-only row visible; re-shoot from Release or crop). 07-pro is for the record; it shows sale pricing that expires 2026-10-22 and should not be uploaded as a permanent listing image.
- Other device sizes (6.5", iPad) and localized sets: not produced.
- Captions live in `Docs/APP_STORE_LISTING.md`; they are not rendered into the images.

## 5. UI suite status

- `SpeakItUITests`: 25 passed / 0 failed / 1 intentional skip out of 26, on a clean iPhone 17 Pro simulator, 475.8 s. The one first-run failure was simulator-state pollution, fixed in the environment, documented above, no code change.
- The unit suite and corpus gate were not run in this pass; see §7.

## 6. What Calvin must still do by hand, in order, before Submit

1. (Done later the same day: `Docs/APP_STORE_SUBMISSION.md`, `Docs/README.md`, `CHANGELOG.md` and `Docs/KNOWN_ISSUES.md` carry the edits listed in section 3.)
2. (Done later the same day: corpus gate, full unit suite, Release compile and a signed archive all passed; see section 1, Build checks.)
3. Physical-iPhone QA per `Docs/CAPTURE_STRESS_TEST_PLAN.md`, plus smoke case E8 (start a capture, swipe home, lock; confirm it continues and saves). If E8 fails, remove `audio` from `UIBackgroundModes` in `SpeakIt/Info.plist`, drop the audio paragraph from the Review Notes, and re-run `LocationReminderTests`. Also cover mic quality, Back Tap, notifications, AirPods, the permission ladder (mic/speech, notifications, When In Use → Always only from the place-reminder editor), the eleventh-attempt wall and both dismissible Pro sheets.
4. Sandbox purchases on a device with a Sandbox tester: buy Monthly, buy Annual (confirm the $14.99 sale price and the $29.99 strike-through come from App Store Connect), Manage Subscription, Redeem Code, and Restore Purchases on a second device signed in to the same Sandbox account.
5. Upload the six screenshots per `output/app-store-screenshots/README.md` (03, 02, 04, 05, 06, 01) for the 6.9" size, light set first; add the 6.5" set if App Store Connect requires it for the supported devices.
6. Confirm `https://speakitapp.ca/privacy` and `https://speakitapp.ca/support` resolve (and `www` redirects) before pasting URLs.
7. In App Store Connect, paste from `Docs/APP_STORE_LISTING.md`: name, subtitle, promotional text, description, keywords, What's New, Support URL, Marketing URL, Privacy Policy URL, copyright, Productivity primary (Utilities secondary), subscription group and both product names/descriptions, and the 1024x1024 promotional image once produced at `Design/Brand/AppStore/pro-promotional-1024.png`.
8. Paste the Review Notes from `Docs/APP_STORE_REVIEW_PACKAGE.md` §1 (3,936 characters) and answer age rating (all None/No, expected 4+), Content Rights (No), and export compliance (`ITSAppUsesNonExemptEncryption = false`).
9. App Privacy: enter the table from the package §3, including the two new types Performance Data and Other Diagnostic Data (not linked, not tracking, Analytics), and Audio Data as not collected by the developer.
10. Choose the Standard EULA (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`) and set the Privacy Policy URL on the version page.
11. Complete the DSA trader declaration in App Store Connect (package §6; note the public-contact caveat).
12. (Done later the same day: build 1.0 (18) was archived from the merged branch and uploaded through `xcodebuild -exportArchive` with Xcode's signed-in account at 23:10 Hong Kong time; App Store Connect answered "Uploaded package is processing". Attach the build to the version once processed.)
13. Review the whole version page against the package §7 field checklist, then Submit.
14. After approval, in App Store Connect schedule the annual price change $14.99 → $29.99 effective 2026-10-22, preserving existing subscribers (cannot be done while the subscription is in Prepare for Submission).

## 7. What is missing?

Claims asserted without evidence handed to this pass:

- (Resolved later the same day: the Release compile, the full unit suite and the focused reruns in section 1 cover every code fix and every new test.)
- The listing's "validated by script" counts: the script and its output were not attached; the critic re-checked the counts, which is the only corroboration.
- The Review Notes count of 3,936 was measured with Python by the critic; no other measurement.
- "No purchase was made" on the 07-pro shot: stated, not shown by a StoreKit transaction log.
- Dark screenshots 01, 02, 06, 07 were never visually inspected.
- Website pages at the bare host: stated as required, not checked to resolve.

Modalities not run:

- Physical-iPhone QA (E8, mic, Back Tap, interruptions, AirPods, lock screen, notifications, purchases, Restore).
- Sandbox StoreKit purchase and Restore.
- Dynamic Type / VoiceOver pass on the changed `WelcomeView` permissions page (the Location card removal changes layout).
- Localized listing review (English only).

Files changed today that no test run has compiled: none. Every app-target and test-target file changed today was compiled by the full unit suite, the Release compile and the archive listed in section 1. The pbxproj still carries the other session's uncommitted diff, which this pass did not review beyond building it.

Everything in this file describes the uncommitted working tree as of 2026-09-09; nothing was committed, pushed, installed on a phone, or changed in App Store Connect.
