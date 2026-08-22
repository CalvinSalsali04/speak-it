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
| R-12 | Speak multiple alarm times ("set alarms for…" or "wake me up at 9:30, 9:35, and 9:45", numerals or spoken words) | One alarm item is produced per time, at the exact spoken minute |
| R-12b | Speak an alarm-time list that dictation writes with "to" ("set an alarm for 9 to 9:30 and 9:45") | Each time with explicit minutes becomes its own alarm; spoken "10 to 9" (8:50) and purpose clauses ("7 AM to take my pills") stay one item |
| R-12c | Ask for a "today" reminder after 9 AM ("remind me to call the bank today", captured mid-afternoon or at night) | The reminder falls back to 8 PM while the day allows it; after that the item is simply due today — it never parks in review |
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
- Opening capture from the in-app dock waits for an explicit pulse or **Type instead** choice; it does not start the microphone on its own.
- Tapping **Type instead** while listening preserves partial text and stops the audio engine.
- Denied permissions expose both Open Settings and Type Instead.
- Save Thought appears under Speak It in the Shortcuts action library.
- The one-action Speak It Capture shortcut opens Speak It already listening.
- Back Tap invokes the configured shortcut and requires no second onscreen tap to listen.
- The capture screen shows live transcription, organizing state, and a visible Remembered check before returning to Today.
- Starting another capture while success is visible does not let the old dismissal end the new capture.
- Multiple reminders at the same moment from one capture are grouped into one notification; alarms remain separate.

## Named shopping list checks

- A sentence naming a place and a time ("When I go to Sobeys, remind me to get cheese, eggs, and bread in one hour") keeps the stated time as the one real trigger, never lands in "Needs review" for the combination, and still uses the place to name the list. Place-only sentences keep their place trigger unchanged. The delay may also sit inside the place clause ("When I go to Sobeys in an hour, remind me to get eggs, bread, and cheese") with the same reading.
- The shopping split and store naming apply on the Apple Intelligence path too: the refinement model keeps a spoken list together by instruction, and the shared post-pass then produces the same checkable rows and list name the rules path does. "When I get to Costco…" names the list the same way "go to Costco" does.
- On launch, items an older build parked in review for the place-and-time combination are released: the timed reading is restored from the original wording and the redundant place trigger is dropped.
- Tapping a list card on Today opens the List screen with that list expanded and the others closed.

- "Go to Costco and buy eggs, milk, and cheese" creates three checkable rows on a list named Costco and no separate "Go to Costco" task; the full sentence stays on the capture session.
- "Remind me in one hour to go to Sobeys and get chicken, eggs and milk" folds the trip clause into the list the same way: only the checkable rows exist, each carrying the one-hour reminder, and no "Go to Sobeys" task appears. A timed trip clause survives as a task only when the rows do not carry its fire moment, so no reminder is ever lost by folding.
- "Buy eggs, milk, and toothpaste" (no store) lands the rows on Groceries; clearly non-food products land on Other.
- "Remind me to get eggs, milk, and cheese in one hour" splits into three checkable rows sharing one fire moment; the scheduler coalesces them into a single notification, and each row shows the bell and time.
- A comma-less dictation splits the same way when every word is a recognized grocery ("get chicken eggs and milk" → chicken, eggs, milk), with known multi-word products like "peanut butter" kept intact; one unrecognized word (a quantity, brand, or qualifier) keeps the capture whole rather than guessing at product boundaries.
- The coalesced notification for a timed list is titled by the list and names the items in spoken order without their verbs — "Sobeys" / "Chicken · Eggs · Milk" — rather than the generic "3 reminders" copy, which remains for mixed or non-list groups.
- A recurring or place-triggered list stays one item; splitting those would register duplicate series or regions.
- Each named list appears as one card inside the Today section its earliest fire moment earns: overdue/today under Now, later under Coming up, undated under When you have time. The card shows the count and the timing.
- The List screen shows one collapsible header per named list with a remaining count; multiple lists start collapsed, a single list starts open.
- Tapping a header expands or collapses its items; each item checks off individually.
- Touch-and-hold on a header (or the Add items row inside an expanded list) opens Add to <list>; comma-separated typed entries become rows on that list, and the keyboard microphone covers speaking them.
- Adding from the sheet counts against the free-capture allowance and is blocked with a Pro message when the allowance is spent.
- Deleting an item removes its list label; completing the last item removes the list header.

The complete physical-device release matrix and current stress evidence live in
[`CAPTURE_STRESS_TEST_PLAN.md`](CAPTURE_STRESS_TEST_PLAN.md).
