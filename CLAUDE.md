# Speak It — Claude Code guide

## Product contract

- Speak It is a calm, voice-first, local-first iPhone app for capturing thoughts without losing the user's original words.
- **Today** is for action: tasks, reminders, overdue items, upcoming items, and things to do when there is time.
- **Memory** is for knowledge worth finding later: pinned items, ideas, people, notes, and reference/context. Do not blur these two destinations.
- Keep the interface minimal, professional, and predictable. Prefer clarity over adding controls or decoration.
- The current business model is 10 free captures in total (a one-time lifetime allowance that never renews), then StoreKit Pro. Product IDs are `com.calvinwak.SpeakIt.pro.monthly` and `com.calvinwak.SpeakIt.pro.annual`. The intended monthly price is $1.99; App Store Connect remains the source of truth for live localized prices.

## Start every task this way

1. Run `git status --short` and treat every existing file, including untracked files, as user-owned work.
2. Read the relevant source and the smallest relevant design document before editing. Useful references include `ARCHITECTURE.md`, `DECISIONS.md`, `KNOWN_ISSUES.md`, `DATA_MODEL.md`, `USER_FLOWS.md`, `TEST_CASES.md`, and `CAPTURE_STRESS_TEST_PLAN.md`.
3. Reproduce or explain the observed behavior before changing broad UI or architecture. For multi-file work, state a short plan.
4. Implement the root-cause fix, add or update tests, then run the checks appropriate to the risk.
5. Report what changed, exact verification evidence, and anything that still requires physical-device or human QA.

## Architecture and code rules

- The app targets iOS 17+ and uses SwiftUI, SwiftData, Speech, AVFoundation, App Intents, ActivityKit, UserNotifications, and StoreKit. The iOS app has no third-party package dependency.
- Persistent mutations belong in `ThoughtRepository` / `SwiftDataThoughtRepository`. Views may use `@Query` for presentation, but must not directly insert, delete, or save SwiftData models.
- Every capture keeps its immutable original transcript in `CaptureSession`. Professionalized titles and extracted metadata must never overwrite or destroy the original wording.
- Capture durability is more important than convenience: do not clear text/audio until persistence succeeds, and preserve interrupted drafts unless the user explicitly discards them.
- Persistent model changes require a new versioned SwiftData schema and explicit migration. Never “fix” storage by deleting or resetting the user's store.
- Keep UI work on `@MainActor`; keep async tasks cancellable and avoid blocking the main thread.
- Use stable model identifiers in lists. When fixing disclosure or swipe bugs, close/reset row interaction state before changing section membership, and avoid animating the entire scroll hierarchy.
- A button's full visible shape must be tappable, have at least a 44x44 pt target where practical, and expose a useful accessibility label/hint. Test text wrapping, Dynamic Type, dark mode, keyboard dismissal, Reduce Motion, and empty/large lists for touched screens.
- Use semantic system colors and the shared tokens in `SpeakIt/Components/SpeakItTheme.swift`. Preserve the restrained visual language.
- The Xcode project uses manual PBX groups/file references. Adding a Swift file on disk is insufficient: also add it to `SpeakIt.xcodeproj/project.pbxproj` and the correct target's Sources phase.
- Keep build/version values aligned across the app, Live Activity extension, Share extension, and UI tests when changing versions.

## Privacy and external effects

- Never send recordings, transcripts, task or memory text, names, email addresses, contacts, search terms, or other user-authored content to analytics.
- Analytics events must use the closed, content-free vocabulary in `SpeakIt/App/AnalyticsService.swift`; keep `PrivacyInfo.xcprivacy` and its tests aligned with changes.
- Analytics is off unless the `SPEAKIT_ANALYTICS_KEY` build setting holds a real PostHog project key. It defaults to empty in both Debug and Release, so no build transmits anything by accident. Inject it per build (`xcodebuild SPEAKIT_ANALYTICS_KEY=phc_...`) and never commit the key.
- Speak It is local-first. Accounts are lightweight settings today; optional iCloud behavior must degrade safely on personal-team Debug signing.
- Use Apple's StoreKit flow for iOS purchases, not Stripe or Apple Pay buttons inside the app.
- Apple does not allow silent scheduled Messages sending. Preserve the current reminder + user-confirmed Messages composer model.
- Do not install to a physical phone, publish the founder dashboard, push code, create purchases, change App Store Connect, or mutate an external service unless the user explicitly asks in that task.

## Repository safety

- The parent repository currently has no tracked baseline and most/all project files appear untracked. They are not disposable.
- Never run `git clean`, destructive reset/checkout, broad `rm`, or delete generated-looking folders without resolving the exact target and getting approval when needed.
- Do not initialize, stage, commit, branch, or push the parent repository unless asked.
- `FounderDashboard/` is a separate nested repository and web app. When working there, follow its nested `CLAUDE.md` and do not mix its Git operations with the parent iOS workspace.

## Key locations

- App lifecycle and navigation: `SpeakIt/App/SpeakItApp.swift`, `SpeakIt/App/RootView.swift`
- Persistence: `SpeakIt/App/PersistenceController.swift`, `SpeakIt/Repositories/SwiftDataThoughtRepository.swift`
- Today: `SpeakIt/Features/Today/TodayView.swift`
- Memory: `SpeakIt/Features/Library/LibraryView.swift`
- Capture and speech: `SpeakIt/Features/Capture/`
- Account and Pro: `SpeakIt/Features/Setup/`
- Models: `SpeakIt/Models/`
- Unit tests: `SpeakItTests/SwiftDataThoughtRepositoryTests.swift`
- UI tests: `SpeakItUITests/SpeakItUITests.swift`

## Commands on this Mac

The active `xcode-select` may point at Command Line Tools, so prefix Xcode CLI commands with:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Discover available destinations before assuming a simulator UUID:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SpeakIt.xcodeproj -scheme SpeakIt -showdestinations
```

Current unit-suite command (use a currently available simulator ID if this one changes):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet \
  -project SpeakIt.xcodeproj -scheme SpeakIt \
  -destination 'platform=iOS Simulator,id=E5892B9B-DB3E-4102-AB62-E1598FCC3F7E' \
  -derivedDataPath /tmp/SpeakItClaudeTests \
  -only-testing:SpeakItTests CODE_SIGNING_ALLOWED=NO
```

Release compile check:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -quiet \
  -project SpeakIt.xcodeproj -scheme SpeakIt -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/SpeakItClaudeRelease CODE_SIGNING_ALLOWED=NO
```

For a narrow change, run focused tests first. Before declaring app-level work done, run the full unit suite and a compile check. Run UI tests and inspect simulator screenshots for changed interaction/layout flows. Physical Back Tap, microphone quality, interruptions, AirPods, lock-screen behavior, notifications, purchases, and device-only animation quality still require hands-on iPhone QA.

## Definition of done

- The behavior matches the Today/Memory product contract and preserves existing user data.
- New logic has regression coverage where practical.
- Relevant tests and build checks pass without suppressing warnings or weakening assertions.
- Changed UI has been exercised as a first-time user and with populated, empty, long-text, keyboard, dark-mode, and accessibility scenarios appropriate to the change.
- Documentation is updated when architecture, product behavior, privacy declarations, pricing assumptions, or known limitations change.
