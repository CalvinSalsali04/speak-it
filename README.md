# Speak It

**Say it. Save it.**

Speak It is a local-first SwiftUI iPhone app for capturing thoughts before they disappear. It includes voice capture, interruption-safe recovery, multi-thought organization, reminders and alarms, SwiftData persistence, Lock Screen capture, one-action Back Tap and Action Button flows, Home Screen quick actions, approval-based message preparation, and native Calendar event handoff.

## Requirements

- macOS with Xcode 15 or newer
- iOS 17 or newer simulator/device
- No account is required for the iPhone app

## Run the app

1. Open `SpeakIt.xcodeproj` in Xcode.
2. Select the shared `SpeakIt` scheme.
3. Choose an iPhone simulator running iOS 17 or newer.
4. Press **Run** (`⌘R`).

SwiftData creates the local store automatically. To test a clean first launch, delete the app from the simulator and run it again.

The first time you tap the central waveform and begin speaking, iOS asks for microphone and speech-recognition permission. Real microphone behaviour should be validated on an iPhone; simulator audio input varies by Mac configuration.

## Run the tests

In Xcode, select **Product → Test** or press `⌘U`. Tests use an in-memory SwiftData container and do not modify app data.

From a configured command line:

```sh
xcodebuild test \
  -project SpeakIt.xcodeproj \
  -scheme SpeakIt \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Use any installed iOS 17+ simulator name if `iPhone 16` is unavailable.

## Capture from anywhere

1. Run Speak It on an iPhone once so iOS registers its App Shortcut.
2. Open Speak It and choose **Capture anywhere** from the Today menu.
3. Add the ready-made one-action **Speak It Capture** shortcut.
4. In Speak It, open **Capture anywhere** and choose the recommended method for that iPhone: Lock Screen, Action Button, or Back Tap. The guide remains incomplete until a real outside-the-app capture has been saved successfully.

To capture quickly from the Home Screen, touch and hold the Speak It icon and choose **Start speaking** or **Type a thought**. Speak It Capture is also available through Siri, Spotlight, the Action Button, Back Tap, the Lock Screen widget, and the iOS 18 Control Center control. Capture, organization, reminders, and the user's library remain local-first and require no Speak It account or backend. Optional encrypted synchronization uses the user's Apple iCloud account in properly entitled Release builds. The separately deployed `ReferralService` handles only anonymous, Apple-verified referral and reward records.
