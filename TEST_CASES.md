# Test Cases

## Automated repository tests

| ID | Behaviour | Expected result |
| --- | --- | --- |
| R-01 | Create a trimmed text capture | One session and one linked item persist |
| R-02 | Submit whitespace only | `emptyCapture` is returned; nothing persists |
| R-03 | Edit structured fields | Changes persist; original capture is unchanged |
| R-04 | Complete then undo | `completedAt` is set, then cleared |
| R-05 | Archive then restore | Archive state and timestamp are set, then cleared |
| R-06 | Delete a single-item capture | Item and orphaned session are removed |
| R-07 | Fetch from a new context | Saved item is present, simulating relaunch visibility |
| R-08 | Save an external capture | Shortcut source and original wording persist |
| R-09 | Capture multiple independent actions | One session persists with one child per action |
| R-10 | Apply one reminder command to multiple actions | Each action receives the shared time |
| R-11 | Correct a spoken item | Only the final corrected intent remains |
| R-12 | Speak multiple alarm times | One alarm item is produced per time |
| R-13 | Merge, split, undo, and reorganize | Item structure changes; original transcript never changes |
| R-14 | Start a capture after an interrupted one | Both text checkpoints remain recoverable |
| R-15 | Repeat 100 action pairs | Every pair separates predictably |
| R-16 | Repeat 50 negated commands | No automatic actions or reminders are created |
| R-17 | Route the Home Screen typing action | Text capture is requested once and consumed once |
| R-18 | Group representative memories | Every memory belongs to exactly one visible group |
| R-19 | Fire 500 triggers while capture is preparing | One start occurs; every duplicate is ignored |
| R-20 | Re-trigger while listening, finalizing, or recovering | Listening refreshes without restart; other phases ignore duplicates |
| R-21 | Return from a stale microphone startup | It cannot cancel or advance its replacement attempt |
| R-22 | Fail recognition with partial text and recovery audio | Protected audio recovery wins over silently saving a partial result |
| R-23 | Change audio routes | Only loss of a usable input stops capture |
| R-24 | Stall microphone startup | Three bounded attempts use short backoff, then fail clearly |
| R-25 | Create 100 interrupted drafts | All 100 remain independently recoverable |

## Manual UI checks

- Capture button is disabled for empty input.
- Successful capture clears text only after save and returns to Today.
- Today orders higher priority before earlier due time.
- Completed and archived items leave Today.
- A future-dated action appears under Coming up; an undated action appears under When you have time.
- An unscheduled idea appears in Memory under Ideas, not in Today.
- Memory never displays action tasks; those stay in Today.
- Memory groups saved context into Ideas, People, or Reference, with a separate Pinned shortcut.
- Memory Ideas can be filtered by New, Promising, Exploring, or Parked and remain ordered by pin, priority, then recency.
- Memory rows switch between compact and comfortable density without losing their sort or filter.
- Memory filter controls remain single-line at accessibility text sizes.
- Every edit can be checked against the unchanged original thought.
- Permanent delete requires confirmation.
- Empty states have a working capture action.
- Learn Speak It lessons open with the lesson title in the navigation bar and return to the guide list in the expected direction.
- Plan settings provide a simple Share Speak It action beside subscription status without advertising an unavailable referral reward.
- The Pro screen shows plans and a purchase action before the longer benefit detail, never advertises an unconfigured free trial or unsupported price comparison, and keeps the annual Best Value badge untruncated.
- Persistence errors leave the draft available.
- Swiping a Today row reveals Done without interfering with vertical scrolling.
- Swiping a Memory row reveals Archive; archived rows reveal Restore.
- Completing or archiving presents a working five-second Undo.
- Memory’s dock hides after downward travel and returns after upward travel.
- Expanding or collapsing Today sections does not resize the viewport, jump the scroll position, or move the bottom dock.
- Finishing typed capture dismisses the keyboard; the text editor is not left onscreen after save.
- Switching Today and Memory never animates the previous screen's completion controls into the destination.
- A vertical swipe scrolls the list wherever it starts, including on a row's title, its completion control, a card, or a section header.
- A scheduled-message phrase becomes a person follow-up with a notification at the requested time.
- Canceling the system message composer leaves the task open; a confirmed send completes it.
- Adding a timed task to Calendar always presents Apple's event editor for confirmation.
- Touching and holding the Home Screen icon exposes Type a thought and focuses the keyboard.

## Accessibility checks

- Complete/incomplete controls announce the item title and intended action.
- Capture, clear, edit, archive, restore, and delete are reachable with VoiceOver.
- Text remains legible at accessibility Dynamic Type sizes.
- Light and dark appearances retain contrast.

## Voice and system-capture checks

- First voice capture asks for microphone and speech permission only after tapping the pulse.
- The pulse reacts to audio input and partial transcription updates while speaking.
- Pausing naturally saves one capture session that may contain several organized items.
- Tapping **Type instead** while listening preserves partial text and stops the audio engine.
- Denied permissions expose both Open Settings and Type Instead.
- Save Thought appears under Speak It in the Shortcuts action library.
- The one-action Speak It Capture shortcut opens Speak It already listening.
- Back Tap invokes the configured shortcut and requires no second onscreen tap to listen.
- The capture screen shows live transcription, organizing state, and a visible Remembered check before returning to Today.
- Starting another capture while success is visible does not let the old dismissal end the new capture.
- Multiple reminders at the same moment from one capture are grouped into one notification; alarms remain separate.

The complete physical-device release matrix and current stress evidence live in
[`CAPTURE_STRESS_TEST_PLAN.md`](CAPTURE_STRESS_TEST_PLAN.md).
