# User Flows

## First launch

1. See the promise, the explicit **Tap → Speak → Pause** interaction, and that no account is required or command vocabulary has to be learned.
2. Start in Light appearance. System and Dark remain explicit choices in Account & Settings and persist once chosen.
3. Choose **Try it now** to enter a resumable practice journey, or **Skip for now** to enter the empty real product. The journey is eight numbered steps, and every tutorial surface carries the same **TUTORIAL** badge, the same **Step N of 8** count, and the same eight-segment bar: the two practice captures, the four teaching cards on the real Today and Memory screens, Capture Anywhere, and the readiness centre. While a step is happening inside the real app, a tutorial bar stays pinned above Today and Memory so a teaching card next to the person's own rows can never be mistaken for the app itself, and **Exit** is always in the same place. Practice provides one concrete action example and always leaves **Type this example** available; microphone and speech permission are requested only if the person actually starts listening. Every practice capture uses a visible **End tutorial** action instead of an ambiguous X, and ending enters the empty real product without consuming a capture.
4. A practice capture is checked against the step it belongs to before the journey advances. Each step has one definition of what it needs — a task naming a person for the first, an idea for the second — and the person's own wording satisfies it: "ask Maya about the proposal" passes without a time. When the capture cannot carry the step, the confirmation reads **Almost — one more go**, shows what their words actually became, names what the step needs, and offers **Try again** and **Use this example**. The attempt is deleted rather than left in the real library, and it spends no free capture. Nothing advances on a capture that would send a teaching card to a screen its row is not on, which is what used to end the journey at step 2 with only Exit on screen.
5. Save “Tomorrow at 9, ask Maya about the proposal” through the real capture pipeline. Mark its session as tutorial data, schedule no real interruption, and spend none of the ten free captures.
6. Route to the live Today screen and pulse a fully inset border around that exact row under Coming up. Each teaching card states what its own button will do—which surface it opens and that closing it continues the tutorial—because every one of them opens something real. Explain why it landed there, then open the real item editor with the title field visibly highlighted and the type, timing, and person controls named. The person may edit and save or choose **Not now** without getting stuck.
7. Route to Memory › People › Maya and highlight the same thought in Maya’s real profile. Explain that this is a connected view of one item rather than a duplicate.
8. Run a second real practice capture using natural speech: “I had an idea for weekly planning to read itself back to me.” Exact wording is not required. Route to Memory › Ideas, highlight the exact row, and open the real stage picker with Promising identified as a concrete practice choice.
9. Present **Make Speak It ready**, one optional setup center with live status, a short reason, and the real system-owned action for microphone and speech, notifications, Home, location reminders, alarms, and Capture Anywhere. **Set up next recommended** advances one unfinished capability at a time; **Finish for now** never blocks core use. Denied system permissions open Settings rather than displaying a switch the app cannot control.
10. Capture Anywhere puts the selected or recommended route and its setup first. **Choose a different way** expands the other routes only on request, then collapses again after a choice. The routes are Action Button, Back Tap, Lock Screen widget, Control Center (iOS 18+), Home Screen Capture widget, and Siri (“Capture with Speak It”, zero setup). Recommend the Action Button when the iPhone has one, otherwise Back Tap. **Done for now** is always visible because setup is optional. Unsupported routes remain visible with the reason. Each setup card shows numbered, animated navigation steps and can run a real outside-the-app test; a successful practice test is also tutorial data and costs no free capture. The Action Button and Back Tap cards open Settings for the person rather than asking them to find it: Back Tap uses the Accessibility deep link on iOS 26, and Action Button uses the app-settings link, since iOS publishes no link to the Action Button pane. The Action Button card also states the whole trip on one line — Action Button › Shortcut › Speak It Capture — before the steps, and shows the shortcut picker being searched rather than scrolled.
11. On finish or **End practice**, delete only tutorial sessions and their reminders, recurrence, location, pin, stage, shopping, and pending-operation metadata. Tutorial data never enters iCloud and its deletion creates no cloud tombstone. Preserve all real user data.
12. Show **Practice examples removed** and the actual remaining free-capture count. A fresh install therefore finishes with all ten free captures. Enter an empty real Today/Memory experience when the person continues.
13. Persist the phase and exact tutorial item identifiers so a relaunch resumes the current live step. If tutorial data is missing, restart only the affected practice mission instead of showing a broken spotlight.

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
2. Task names stay hidden until the user turns on **Show task names on the Lock Screen** in Account & Settings, so a locked iPhone shows only a count. The rectangular slot then lists the next three tasks under its header, each on its own marked row. The first row is the soonest due: it is set in bold and shows its clock time. The other two are lighter names only. The inline slot shows the next task, and the count still carries everything beyond the three.
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
