# Speak It

**Say it. Save it.**

[![CI](https://github.com/CalvinSalsali04/speak-it/actions/workflows/ci.yml/badge.svg)](https://github.com/CalvinSalsali04/speak-it/actions/workflows/ci.yml)

Speak It is a calm, voice-first, local-first iPhone app for capturing thoughts
before they disappear, without losing the person's original words. **Today** holds
what needs doing; **Memory** holds what is worth finding again. Capture works from
the Lock Screen, the Action Button, Back Tap, Siri, Spotlight, Control Center, and
the Home Screen, and everything stays on the phone.

This is the private monorepo for the app and the things around it.

## What is here

| Path | What it is |
| --- | --- |
| `SpeakIt/` | The iOS app: SwiftUI, SwiftData, Speech, App Intents, ActivityKit, StoreKit. No third-party packages |
| `SpeakItLiveActivity/`, `SpeakItShareExtension/`, `Shared/` | Lock Screen widget and Live Activity, the Share extension, and the code they share with the app |
| `SpeakItTests/`, `SpeakItUITests/` | The XCTest unit suite (including the semantic corpus) and the XCUITest suite |
| `Tools/CorpusRunner/`, `Tools/PipelineProbe/` | Host-side replays of the understanding pipeline: the full corpus in ~20 s, or one sentence |
| `Tools/CI/` | The check scripts CI and humans both run |
| `Tools/Brand/` | Generator for the mark and wordmark |
| `Website/` | The static marketing site, privacy policy, and support page |
| `FounderDashboard/` | Private founder analytics site (React 19, vinext, Cloudflare). Node 22 |
| `ReferralService/` | Apple-verified referral service (TypeScript, SQLite). Node 22 |
| `Design/`, `Demo/`, `Marketing/` | Brand assets, screenshots, the product demo's frames, and marketing sources |
| `Docs/` | Architecture, decisions, known issues, QA plans, and audits. Start at [`Docs/README.md`](Docs/README.md) |

`CLAUDE.md` is the working guide for automated agents and a good summary of the
engineering rules; `CONTRIBUTING.md` covers branches, checks, CI, and releases.

## Requirements

- macOS with Xcode 26.6 (the app uses iOS 26 speech and alarm APIs behind
  availability checks; the deployment target is iOS 17)
- An iOS 17 or newer simulator or iPhone
- Node 22 for `FounderDashboard/` and `ReferralService/`
- No account is required for the iPhone app

## Run the app

1. Open `SpeakIt.xcodeproj` in Xcode.
2. Select the shared `SpeakIt` scheme.
3. Choose an iPhone simulator running iOS 17 or newer.
4. Press **Run** (`⌘R`).

SwiftData creates the local store automatically. To test a clean first launch,
delete the app from the simulator and run it again.

The first time you tap the central waveform and begin speaking, iOS asks for
microphone and speech-recognition permission. Real microphone behaviour should be
validated on an iPhone; simulator audio input varies by Mac configuration.

## Run the checks

```bash
./Tools/CI/corpus-gate.sh        # replays the semantic corpus on the host; no simulator
./Tools/CI/unit-tests.sh         # the unit suite on a simulator (~9 minutes)
./Tools/CI/release-build.sh      # Release compile for a generic iOS device
```

In Xcode, **Product → Test** (`⌘U`) runs the same suites. Tests use an in-memory
SwiftData container and do not modify app data. See `Tools/CI/README.md` for the
environment variables each script honours.

For the Node projects:

```bash
cd FounderDashboard && npm ci && npm run lint && npm test
```

```bash
cd ReferralService && npm ci && npm test
```

## Continuous integration

Every pull request runs the Linux jobs (secret scan, workflow and shell lint, the
two Node projects). The iOS job runs on a self-hosted Mac when one is registered,
or on GitHub-hosted macOS when dispatched by hand, because macOS minutes on a
private Free-plan repository are scarce. `CONTRIBUTING.md` has the runner setup.

## Capture from anywhere

1. Run Speak It on an iPhone once so iOS registers its App Shortcut.
2. Open Speak It and choose **Capture anywhere** from the Today menu.
3. Add the ready-made one-action **Speak It Capture** shortcut.
4. In Speak It, open **Capture anywhere** and choose the recommended method for
   that iPhone: Lock Screen, Action Button, or Back Tap. The guide remains
   incomplete until a real outside-the-app capture has been saved successfully.

To capture quickly from the Home Screen, touch and hold the Speak It icon and
choose **Start speaking** or **Type a thought**.

## Privacy

Capture, organization, reminders, and the person's library are local-first and
need no Speak It account or backend. Optional encrypted synchronization uses the
person's own iCloud account in properly entitled Release builds. Analytics is off
unless a build is given a PostHog key, and even then it carries a closed,
content-free event vocabulary: no recordings, transcripts, titles, names, or
search terms ever leave the phone. The separately deployed `ReferralService`
handles only anonymous, Apple-verified referral and reward records.
