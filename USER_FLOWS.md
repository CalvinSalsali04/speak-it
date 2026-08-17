# User Flows

## First launch

1. See the promise, the three-beat **Speak → Organized → Remembered** model, and that no account is required.
2. Start in Light appearance. System and Dark remain explicit choices in Account & Settings and persist once chosen.
3. Choose **Try it now** to complete one real in-app capture, or **Explore first** to enter the product without pretending capture succeeded.
4. Request microphone and speech permission only when voice capture actually begins. Closing or abandoning the first capture returns to Welcome and does not persist onboarding completion.
5. Persist onboarding completion when the first thought is durably saved. Keep its **Remembered** receipt visible until the person explicitly continues; VoiceOver users always get the same non-expiring control.
6. Show the one-screen distinction: **Today is for action; Memory is for knowledge**.
7. After at least two successful captures, offer capture-anywhere setup as a dismissible discovery card. It never blocks initial value and remains available from Account & Settings.
8. Choose one method, follow only its instructions, and run a real outside-the-app test. Setup becomes complete only after Speak It detects that the thought was saved.

## Learn Speak It

1. Open Account & Settings and choose **Learn Speak It** at any time.
2. Browse short lessons for getting started, routing, correcting results, multi-thought captures, reminders, places, capture anywhere, Calendar handoff, privacy, recovery, and the Free/Pro boundary.
3. Use concrete example phrases without needing to repeat onboarding or reset app state.

## Lock Screen capture

1. Tap the Speak It Capture widget on the Lock Screen.
2. Speak It opens directly into listening without another tap.
3. Speak naturally and pause to finalize.
4. The thought is organized and saved, then the in-app **Remembered** confirmation appears.

## Lock Screen glance

1. The Speak It Today widget shows how many things are open, in the inline, circular, or rectangular slot.
2. Task names stay hidden until the user turns on **Show task names on the Lock Screen** in Account & Settings, so a locked iPhone shows only a count.
3. Tapping the widget opens Today. Completion is deliberately not offered on the Lock Screen; it remains on the Home Screen families.

## Manual capture

1. Open Capture from the bottom dock and choose **Type instead**, or touch and hold the Speak It Home Screen icon and choose **Type a thought**.
2. Enter one or several natural thoughts in the focused editor.
3. Tap **Save thought**.
4. The repository trims outer whitespace, creates the capture session and item, and saves them together.
5. Show **Remembered**, then return to Today.
6. If persistence fails, keep the typed text and show an error.
7. If the person taps X after entering words, offer **Save & Close**, **Discard**, and **Keep Editing**. An empty capture closes immediately; a saved capture is already safe.

## In-app voice capture

1. Tap the central waveform control.
2. Tap the animated pulse to begin listening.
3. Grant microphone and speech-recognition permission when first requested.
4. Speak while the pulse responds to audio level and live text appears.
5. Pause naturally to finish, or tap the pulse to finish immediately.
6. Finalize the transcription, separate independent intentions, save them under one untouched capture, play success haptics, and show the Remembered animation.
7. If recognition fails after producing text, move that text into the typing interface instead of discarding it.
8. Keep X visible while the keyboard is onscreen. Once speech exists, closing follows the same Save & Close / Discard rule as typing.

## Duplicate capture

1. Normalize case, accents, whitespace, and punctuation for comparison only; never alter the stored original transcript.
2. If the same source repeats the same wording within 15 seconds in app (or within the existing five-second external delivery window), return the already-saved capture instead of inserting another session or item.
3. Show **Already captured — No duplicate was added** and do not consume a free capture.
4. Keep a repeat outside that narrow window. Speak It never silently deletes or merges a later thought the person may have repeated intentionally.

## Alarm capture

1. “Remind me at 7” uses a normal notification.
2. “Wake me at 7” or “Set an alarm for 7” uses AlarmKit on iOS 26 and later.
3. Request AlarmKit authorization only when the first alarm is actually created.
4. If AlarmKit is unavailable, use the existing notification fallback; normal reminders remain notifications.

## Back Tap capture

1. Double-tap the back of the configured iPhone.
2. The one-action Speak It Capture intent opens Speak It directly into voice capture.
3. Listening starts automatically; no second onscreen tap is required.
4. A natural pause finalizes and saves through the shared repository.
5. Speak It shows a visible Remembered confirmation before returning to Today.

## Review and edit

1. Open an item from Today or Memory.
2. Review the editable title, type, category, priority, due date, person, and clarification flag.
3. Compare against the read-only original capture.
4. Tap **Save**.
5. The repository persists the changes and marks the item reviewed.

## Complete or undo

1. Tap the completion control on a Today row, or use the editor action.
2. Set or clear `completedAt`.
3. Completed items leave Today and a five-second **Undo** appears.
4. Completed history remains available from the Today menu.

## Archive and restore

1. Swipe a Memory row left and choose **Archive**, or use the editor action.
2. The item moves to the Memory **Archive** filter and a five-second **Undo** appears.
3. In Archive, swipe left and choose **Restore**.

## Memory navigation

1. Open Memory to see **Pinned**, **Ideas**, **People**, and **Reference** destinations. Action tasks remain in Today.
2. Open Ideas to filter by **New**, **Promising**, **Exploring**, or **Parked**; use priority and pinning to keep the strongest ideas first.
3. Search across people, ideas, and facts; title-prefix matches rank first.
4. Switch between compact and comfortable rows without changing the active filter or sort.
5. Scroll down and the bottom dock retracts; scroll upward and it returns without changing the viewport height.

## Delete

1. Open the item editor.
2. Tap **Delete permanently**.
3. Confirm the destructive action.
4. Delete the item. If its capture session has no other items, delete that session too.
