# Capture Reliability Stress Plan

This is the release gate for every outside-the-app capture route: Back Tap,
Action Button, Control Center, Lock Screen, Back Tap, Siri/Shortcuts, and the
in-app capture pulse.

## Automated evidence — 2026-08-11

| Check | Result |
| --- | --- |
| Complete simulator suite | 95/95 passed |
| Seven capture reliability tests repeated 25 times | 175/175 passed |
| Rapid-trigger load inside those repetitions | 12,500 triggers without a duplicate start |
| Interrupted-draft load inside those repetitions | 2,500 drafts recovered independently |
| Xcode static analyzer | Passed with no findings |
| Address Sanitizer, complete suite | 93/93 passed with no memory finding |
| Thread Sanitizer, complete suite | 93/93 passed with no race finding |
| Signed iPhone 13 build, install, and launch | Passed; existing 12 sessions and 15 items remained intact |

The automated suite covers duplicate triggers while preparing, listening,
finalizing, and recovering; bounded microphone retries; stale async startup
completions; recognizer failure with recovery audio; lost audio routes; and
interrupted-draft durability.

## What the user should see

1. The gesture is received.
2. iOS foregrounds Speak It directly into the capture screen.
3. **Listening** appears only after the audio engine is actually running. The
   person can begin speaking without a second onscreen tap.
4. Live transcription replaces the prompt.
5. A natural pause ends the thought automatically.
6. **Remembered** remains visible long enough to read before returning to Today.

There is no supported way to keep the microphone permanently warm while the
app is closed. iOS must foreground the App Intent and activate a privacy-sensitive
audio session. Speak It measures the real delay from intent receipt to
audio-engine readiness and never presents “Listening” early.

## Physical iPhone matrix

Run every row after installing a release-like build. In Speak It, open
**Capture anywhere**, choose the route, tap **test now**, and note the displayed
“Microphone ready in …s” result.

| ID | Starting condition | Action | Pass condition |
| --- | --- | --- | --- |
| P-01 | App open | Trigger capture | Capture opens, listens, and saves once |
| P-02 | Home Screen, app warm | Trigger capture | Listening appears once; transcript and Remembered follow |
| P-03 | Home Screen, app force-quit | Trigger capture | Cold launch opens directly into capture and begins listening once |
| P-04 | Lock Screen, phone locked | Trigger capture | Capture starts if iOS permits the route; no unlock loop |
| P-05 | Lock Screen, just unlocked | Trigger immediately | One trigger produces one listening session |
| P-06 | Another app open | Trigger capture | Speak It foregrounds directly into capture and begins listening once |
| P-07 | Video/Reel playing | Trigger capture | Playback is interrupted and is not transcribed into the thought |
| P-08 | Music/podcast playing | Trigger capture | Playback pauses; voice capture remains intelligible |
| P-09 | AirPods already connected | Trigger and speak | The selected microphone works and the thought saves |
| P-10 | Disconnect AirPods while speaking | Continue speaking | Recording is safely recovered or a clear recoverable error appears |
| P-11 | Connect a Bluetooth route while speaking | Continue speaking | No crash or silent data loss |
| P-12 | Incoming call/Siri interruption | Interrupt capture | Partial audio is recovered or a useful error receipt appears |
| P-13 | Double trigger rapidly 10 times | Speak once | Exactly one capture starts and exactly one thought saves |
| P-14 | Trigger again while Listening | Continue speaking | Existing session remains intact; no transcript reset |
| P-15 | Trigger while Organizing | Wait | No duplicate save and no overlapping capture state |
| P-16 | Trigger while Remembered is visible | Speak a new thought | New capture starts; old delayed cleanup cannot end it |
| P-17 | Speak immediately after triggering | Say a full sentence | Beginning is captured once Listening appears; no false early promise |
| P-18 | Wait for Listening, then stay silent | Say nothing | Clean timeout; no empty memory is created |
| P-19 | Very short thought | Say one meaningful word | It saves or gives a helpful retry, never crashes |
| P-20 | Several thoughts | Speak 3 independent items | One original session is preserved and items are separated |
| P-21 | Long capture | Speak for 60 seconds | Bounded finalization; transcript or recovery audio is retained |
| P-22 | Reminder | Say “Remind me in 10 seconds to get the laundry” | Organized reminder saves and notification arrives |
| P-23 | Speech permission revoked | Trigger | Clear access message; app does not loop or crash |
| P-24 | Microphone permission revoked | Trigger | Clear access message; app does not claim to be Listening |
| P-25 | Dictation unavailable | Trigger | Clear failure/fallback behavior; typed capture remains available |
| P-26 | Airplane mode | Trigger and speak | Supported recognition works or recording is recoverable |
| P-27 | Low Power Mode | Trigger and speak | Same one-trigger/one-save contract is preserved |
| P-28 | Restart iPhone | First trigger after reboot | Setup remains connected and capture starts once |
| P-29 | Install an app update | First trigger after update | Existing shortcut still resolves to Speak It Capture |
| P-30 | Thirty normal captures in succession | Alternate short and multi-item thoughts | 30/30 start, save once, and leave no stuck Live Activity |

## Performance acceptance

- Record both warm and cold “Microphone ready” values; do not time from the
  physical tap because iOS owns Back Tap recognition.
- Warm unlocked runs should ordinarily be ready within 2 seconds; any run over
  the 4-second attempt watchdog is a failure to investigate.
- Thirty-cycle endurance must have zero crashes, duplicate thoughts, lost
  drafts, or capture screens stuck in Starting/Listening.
- A lost route or speech-recognizer interruption may end capture, but words
  already recorded must remain recoverable.

## Regression rule

Any physical failure must be turned into a deterministic unit/state-machine
test before its fix is accepted. Rerun the current complete suite, 25 repeated capture
iterations, static analysis, Address Sanitizer, and Thread Sanitizer after a
change to capture, App Intents, ActivityKit, AVAudioSession, or draft recovery.
