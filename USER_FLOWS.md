# User Flows

## First launch

1. See the promise, the three-beat **Speak → Organized → Remembered** model, and that no account is required.
2. Complete one in-app capture so microphone and speech permission are requested only when needed.
3. After the first successful save, choose one capture-anywhere method. Speak It recommends Action Button on supported iPhones and the Lock Screen widget everywhere else.
4. Follow only the instructions for the selected method.
5. Start a real outside-the-app test capture. Setup becomes complete only after Speak It detects that the thought was saved.

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

## In-app voice capture

1. Tap the central waveform control.
2. Tap the animated pulse to begin listening.
3. Grant microphone and speech-recognition permission when first requested.
4. Speak while the pulse responds to audio level and live text appears.
5. Pause naturally to finish, or tap the pulse to finish immediately.
6. Finalize the transcription, separate independent intentions, save them under one untouched capture, play success haptics, and show the Remembered animation.
7. If recognition fails after producing text, move that text into the typing interface instead of discarding it.

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
