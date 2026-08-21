# Speak It Build 12 — Human Bug Hunt

Target: Speak It 1.0 (Build 12) on Calvin's iPhone 13  
Installed: 2026-08-21  
Purpose: find bugs before installing Build 13

## How to test

- Talk naturally. Pause, ramble, change your mind, mumble, and use the app the way a random person would.
- Mark each case `PASS`, `FAIL`, `WEIRD`, or `BLOCKED`.
- For every problem, save a screenshot or screen recording and write down:
  - the case ID;
  - the exact words spoken or typed;
  - what happened;
  - what you expected;
  - the approximate time.
- Unless a case says otherwise, each test should create only the items clearly requested.
- Do not delete the app after the final test. The last Build 13 test needs Build 12 data to remain on the phone.

## Important: behavior that is not a bug

- A dated task without words such as “remind me” can appear in the timeline without sending a notification.
- “Buy milk tomorrow” should not alert. “Remind me to buy milk tomorrow” should alert at the default time, currently 9:00 AM.
- An ordinary reminder is not an alarm. “Wake me” or “set an alarm” asks for alarm behavior when the OS supports it; an ordinary notification is the fallback.
- Speak It cannot silently send a text. It reminds you and prepares Apple's composer; the item completes only after a confirmed send.
- Back Tap must be assigned manually in iPhone Settings after the Speak It Capture shortcut exists.
- Named businesses such as “Costco” are not geocoded yet. The item should be saved safely and ask for review instead of inventing a location.
- A place and a time in the same trigger, such as “when I get home tonight,” should ask which trigger to use rather than scheduling both.
- Today rows do not use swipe-to-complete. Use the completion circle or editor.
- Referral rewards are off in this build. Sharing can work, but no reward should be promised.

## Fast smoke test — do these first

| ID | Do this | Expected result |
|---|---|---|
| S01 | Open Speak It. | It opens without a crash, freeze, blank screen, or sign-in wall. Existing data is still present. |
| S02 | Type “Buy milk” and save it. | One action appears under Today → When you have time. No notification is scheduled. |
| S03 | Say “Remember that Sarah likes oat milk.” | One memory is saved, associated with Sarah/People rather than Today. |
| S04 | Say “Remind me in one minute to check the oven.” | One reminder is created and one notification arrives at roughly the correct time. Tapping it opens the correct item. |
| S05 | Say “Buy bananas, call Mom tomorrow, and idea: plan a weekend picnic.” | The capture is split into sensible items: actions for bananas/call and an idea in Memory. No text is lost. |
| S06 | Complete “Buy milk,” then immediately undo. | It leaves Today, then returns after Undo with its data intact. |
| S07 | Edit an item’s wording and time. | The edited fields change; the original transcript remains available and unchanged. |
| S08 | Capture the exact same wording twice within 15 seconds. | The second capture says it was already captured and does not make a duplicate. |
| S09 | Start a capture, enter some words, then close it. | Speak It offers to keep/save, type instead, or discard as appropriate; it does not silently lose the draft. |
| S10 | Force-quit and reopen the app. | The app opens normally and all saved items remain. |
| S11 | Use the Home Screen quick action to start speaking. | It opens the capture flow once and is ready quickly. |
| S12 | Switch the phone to Dark Mode while the app is open. | Every screen remains readable; no invisible text, broken contrast, or flashing light background. |

If any smoke test fails, record it before continuing. A crash, lost capture, missed basic reminder, duplicate, or lost data is a stop-ship problem.

## 1. Install, launch, and persistence

| ID | Random-human test | Expected result |
|---|---|---|
| A01 | Open and close the app five times at a normal pace. | Every launch succeeds and lands in a usable state. |
| A02 | Swipe the app away while on Today, then reopen it. | It recovers without data loss or a stuck capture state. |
| A03 | Reboot the iPhone, unlock it, and reopen Speak It. | Saved content remains and scheduled reminders are still present. |
| A04 | Leave the app in the background for 30 minutes, then return. | The screen refreshes correctly and accepts input. |
| A05 | Rotate the phone while capture and edit screens are open. | The app stays usable in its supported orientation and does not corrupt the draft. |
| A06 | Lock the phone with an unfinished typed draft, unlock, and return. | The draft is preserved or the app gives a clear recovery choice. It is never silently discarded. |

## 2. Capture input and messy speech

| ID | Say or do this | Expected result |
|---|---|---|
| C01 | Type only spaces and tap Save. | No empty thought is created; the UI explains what is needed. |
| C02 | Say only “Milk.” | A usable item is saved or Speak It asks for clarification; it does not crash or invent details. |
| C03 | Tap Speak and immediately start talking: “Call the dentist tomorrow.” | The opening words are captured; “Call” is not clipped. |
| C04 | Start Speak and remain silent. | The session ends gracefully with a retry/type option and creates no garbage item. |
| C05 | Say “Um, okay, I guess I need to, uh, buy coffee filters sometime.” | Filler is handled sensibly and one coffee-filter action is created without invented dates. |
| C06 | Say “Call Mom at five—no, wait—make that six tomorrow.” | One item is created for tomorrow at 6:00 PM, not separate 5:00 and 6:00 items. |
| C07 | Speak continuously for about 60 seconds with five unrelated thoughts. | Capture remains stable, all meaningful thoughts are preserved, and splitting is sensible. |
| C08 | Say “Buy bread and milk and eggs.” | Prefer one shopping action/list, not three noisy unrelated reminders, unless the UI clearly shows a sensible split. |
| C09 | Say “Buy bread. Call Alex. Remember Alex is allergic to peanuts. Idea: host brunch.” | Actions go to Today, the fact goes to Memory/People, and the idea goes to Ideas. |
| C10 | Type a paragraph with punctuation, emoji, accented names, and apostrophes: “Café with Zoë ☕️ — don’t forget Sam’s book.” | Text is preserved correctly and no mojibake, truncation, or duplicate punctuation appears. |
| C11 | Start speaking, then switch to Type Instead and finish the thought. | Existing useful text is preserved and the final item reflects the typed correction. |
| C12 | Start capture, tap its trigger repeatedly ten times, and speak once. | Only one capture session and one saved result appear. |
| C13 | Trigger capture while it says Starting. | It does not open a second recorder or lose the first session. |
| C14 | Trigger capture while it is Listening. | It keeps one coherent recording instead of stacking sessions. |
| C15 | Trigger capture while it is Organizing or Remembered. | It transitions predictably, with no duplicate and no lost prior result. |
| C16 | Capture the same phrase twice within 15 seconds, then repeat it again after more than 15 seconds. | The immediate repeat is blocked as a duplicate; the later intentional repeat is kept as a new thought. |
| C17 | Paste a very long note into typed capture. | The app enforces any length limit clearly, stays responsive, and does not save a corrupt partial item. |

## 3. Understanding normal human intent

| ID | Say this | Expected result |
|---|---|---|
| U01 | “Buy milk.” | One undated action under Today → When you have time; no alert. |
| U02 | “Buy milk tomorrow.” | A task due tomorrow under Coming up; no alert merely because it has a date. |
| U03 | “Remind me to buy milk tomorrow.” | A task due tomorrow with an alert at the default time, currently 9:00 AM. |
| U04 | “I need to call John.” | One outstanding action, not a completed memory. |
| U05 | “Maybe I could learn guitar.” | An idea, not a firm action or notification. |
| U06 | “Idea: a tiny app that plans leftovers.” | A new Idea in Memory. |
| U07 | “Remember that Maya’s birthday is May 13.” | A fact in Memory/People, not an action due May 13. |
| U08 | “The Wi-Fi password for the studio is maple-482.” | A reference memory, stored locally; no task or reminder. Delete it after the test if it is real. |
| U09 | “I bought milk yesterday.” | A past fact/history item, not a new buy-milk task. |
| U10 | “I sent the invoice.” | A completed/past statement, not a new outstanding action. |
| U11 | “I promised Sarah I’d send the file.” | One outstanding send-file action associated with Sarah where appropriate. |
| U12 | “Don’t remind me to call John.” | No call-John reminder is created. It must not ignore the negation. |
| U13 | “Sarah reminded me to call John.” | This reported speech must not create a scheduled reminder automatically. |
| U14 | “If I have time, maybe clean the garage.” | It is treated as tentative/idea-like or asks for review, not as a high-confidence timed reminder. |
| U15 | “I should call Mom, but I already emailed her.” | It should not turn the completed email into a new action; the call may remain an action. |

## 4. Dates, times, reminders, alarms, and recurrence

| ID | Say this | Expected result |
|---|---|---|
| T01 | “Remind me in 30 seconds to stretch.” | One notification arrives about 30 seconds later and opens the correct item. |
| T02 | “Call Mom tomorrow at 5.” | The task is due tomorrow at 5:00 PM. Without reminder language, it should not silently add an alert. |
| T03 | “Call Mom tomorrow at 5 and remind me at 4:45.” | Due time is 5:00 PM; reminder time is 4:45 PM. They are visibly distinct. |
| T04 | “Remind me tomorrow to water the plants.” | It is dated tomorrow and alerts at the default time, currently 9:00 AM. |
| T05 | “Remind me at midnight to check the door.” | It resolves to the next sensible midnight, not noon or a past time. |
| T06 | “Book the appointment for 4/5.” | Because 4/5 is ambiguous, Speak It asks for review instead of guessing April 5 or May 4. |
| T07 | “Book the appointment for 13/5.” | It resolves to May 13 without asking which field is the month. |
| T08 | “Book the appointment for 5/13.” | It resolves to May 13 without asking which field is the month. |
| T09 | “Every Monday at 9 remind me to file my timesheet.” | A weekly Monday 9:00 AM reminder is created and recurrence is visible. |
| T10 | “Remind me every day to check my blood pressure.” | A daily reminder is created using the default 9:00 AM time. Missing or non-repeating behavior is a high-priority bug. |
| T11 | “Remind me every Friday to submit my report.” | A weekly Friday reminder is created using the default 9:00 AM time. Missing or non-repeating behavior is a high-priority bug. |
| T12 | “Remind me every 24 hours to drink water.” | The recurrence is elapsed-time based and visibly different from “every day at 9.” |
| T13 | Complete a recurring item. | The completed occurrence is recorded and the next occurrence remains scheduled. The whole series must not vanish unexpectedly. |
| T14 | Edit a recurring item’s time and save it. | Future occurrences use the new time; old pending notifications do not remain duplicated. |
| T15 | “Remind me at 7 tomorrow to get up.” | This is a normal notification reminder unless the wording explicitly requests an alarm. |
| T16 | “Wake me at 7 tomorrow.” | Alarm behavior is used if supported on this iOS version; otherwise a clear notification fallback is created. The title should describe getting up, not a generic “Your reminder.” |
| T17 | “Set alarms for 7 and 7:15 tomorrow.” | Two separate alarm/fallback items are created at the correct times. |
| T18 | Create three reminders for the exact same minute in one capture. | Related notifications are grouped sensibly; alarms remain separately actionable. |
| T19 | Change the iPhone time zone, reopen Speak It, inspect a future 9:00 AM item, then restore the time zone. | The item follows the app’s intended local-time behavior consistently and does not duplicate or shift unpredictably. |

## 5. Modify, complete, cancel, and delete

| ID | Say or do this | Expected result |
|---|---|---|
| M01 | Create “Buy cereal,” then say “Mark buy cereal done.” | The matching item completes once and leaves Today. |
| M02 | Create “Dentist Friday at 2,” then say “Move dentist to Friday at 3.” | The same item moves to 3:00 PM; a second dentist item is not created. |
| M03 | Create one milk reminder, then say “Cancel my milk reminder.” | The exact reminder is cancelled and its notification is removed. |
| M04 | Say “Cancel my dentist reminder” when none exists. | Speak It says no match was found and cancels nothing else. |
| M05 | Create two similar call-Mom reminders, then say “Cancel my call Mom reminder.” | It asks which one instead of guessing. |
| M06 | Say “Cancel all my reminders.” | A broad destructive cancellation is not performed without explicit confirmation and a clear scope. |
| M07 | Complete an item and wait more than five seconds. | Undo expires cleanly; the item remains available in completed history. |
| M08 | Archive a memory, undo, then archive it again and restore it from Archive. | The item moves and returns with all content intact. |
| M09 | Tap permanent Delete, then cancel at the confirmation. | Nothing is deleted. |
| M10 | Permanently delete a disposable test item and confirm. | Only that item disappears and it does not resurrect after relaunch. |

## 6. Today, Memory, search, and editing

| ID | Do this | Expected result |
|---|---|---|
| V01 | Create an overdue action, one due today, one future action, and one undated action. | They appear in sensible sections/order: overdue/today, Coming up, and When you have time. |
| V02 | Give two items different priorities, with the lower-priority one due earlier. | Higher priority sorts ahead where the product promises priority ordering; time information remains visible. |
| V03 | Try swiping a Today row as if to complete it. | It does not accidentally complete or delete. Use the circle/editor to complete it. |
| V04 | Complete and archive Today items. | They leave active Today immediately and do not return after relaunch. |
| V05 | Open Memory after creating a person fact, idea, and reference. | They appear in the correct Pinned/Ideas/People/Reference organization. Actions do not leak into Memory. |
| V06 | Search for a word from the middle of a memory, using different capitalization. | The correct memory appears; irrelevant items are limited. |
| V07 | Pin and unpin a memory. | It moves into and out of Pinned without duplicating. |
| V08 | In Ideas, try New, Promising, Exploring, and Parked filters. | Each filter shows only matching ideas and the selection is retained appropriately. |
| V09 | Switch between compact and comfortable density, then relaunch. | Layout changes without clipping; density, filters, and sorting persist. |
| V10 | Scroll down in Memory and then upward. | The dock hides and returns smoothly; it never traps navigation. |
| V11 | Edit organized text and metadata, then inspect the original transcript. | Edited content changes, but the original transcript remains immutable. |
| V12 | Rapidly open and close multiple item editors. | The correct item is always shown; edits do not land on the wrong record. |

## 7. Location reminders on the physical phone

Before this section, decide on safe test locations for Home and Work. Location reminders require Always Location and Precise Location for dependable background triggers.

| ID | Do or say this | Expected result |
|---|---|---|
| L01 | Open Settings → Capture & reminders → Places before setting locations. | Home and Work show Not set, with a clear way to configure them. |
| L02 | Set Home to Current Location. | iOS asks for location access when needed and Speak It shows a recognizable place/address. |
| L03 | Set Work by searching for an address. | The chosen address is stored and shown correctly. |
| L04 | Say “Remind me to take the bins out when I get home.” | A location reminder linked to Home is created. If permission is insufficient, it clearly shows Needs review/permission guidance. |
| L05 | Decline the request for Always Location. | The reminder stays safely blocked and offers Open Settings; it does not pretend to be active. |
| L06 | Grant Always Location. | The permission blocker clears and the reminder becomes eligible to trigger. |
| L07 | Turn Precise Location off. | Speak It clearly reports that Precise Location is needed for reliable reminders. |
| L08 | Re-enable Precise Location. | The warning clears and eligible reminders resume without duplicates. |
| L09 | Create a Home reminder, then change the saved Home address. | The reminder follows the Home pointer to the new address while its original wording stays unchanged. |
| L10 | Say “Remind me to lock the car when I leave here.” | “Here” becomes a one-time coordinate snapshot, not a pointer that moves with you later. |
| L11 | In Airplane Mode, say “Remind me when I leave here.” | The thought is saved, but Speak It clearly says the current location is unavailable instead of inventing one. |
| L12 | Say “Remind me to buy cereal when I get to Costco.” | Because arbitrary business geocoding is unsupported, it is saved as Needs review/inert and does not choose a random Costco. |
| L13 | Say “Remind me to feed the dog when I get home tonight.” | It preserves both place and time but asks which trigger to use; neither trigger runs until resolved. |
| L14 | With an active arrival reminder, let the app sit in the background and enter the Home region. | One notification fires. Opening it shows the correct reminder. |
| L15 | Repeat L14 after swiping the app away. | Record the actual result. iOS may not relaunch a user-force-quit app for geofences; the UI must not claim a trigger fired if it did not. |
| L16 | Repeat a location test after a reboot and first unlock. | The active reminder re-registers and fires once, not zero times or repeatedly. |
| L17 | Complete, delete, or change the location on an active reminder, then cross the old boundary. | The old geofence does not fire. |
| L18 | Create two reminders for the same location and cross the boundary. | Both intended reminders fire once without suppressing or multiplying each other. |

For the deepest location pass, also use `LOCATION_DEVICE_QA.md` in this repository.

## 8. Interruptions, permissions, and recovery

| ID | Do this | Expected result |
|---|---|---|
| R01 | Deny Microphone permission, then try voice capture. | A clear explanation and Open Settings/type alternative appear; no dead-end spinner. |
| R02 | Deny Speech Recognition permission, then try voice capture. | A clear explanation and recovery path appear; typed capture still works. |
| R03 | Re-enable both permissions and retry. | Voice capture works without reinstalling the app. |
| R04 | Begin speaking, then lock the phone mid-capture. | The app handles the interruption predictably and offers recovery; it never silently loses recoverable audio. |
| R05 | Begin speaking, then background the app. | The UI and saved state remain consistent when you return. |
| R06 | Receive a phone/FaceTime call or invoke Siri during capture. | Recording pauses/stops safely and recovery options appear; no crash or corrupt item. |
| R07 | Start with AirPods, disconnect them mid-capture, and keep talking. | The route change is handled without a stuck recorder; any lost audio is clearly disclosed. |
| R08 | Use Airplane Mode for a normal typed capture and then a voice capture. | Local capture remains usable; unavailable features explain themselves and retry after reconnecting. |
| R09 | Enable Low Power Mode and perform five captures. | Captures, organization, and notifications remain correct; no endless processing. |
| R10 | If a recording cannot be organized, tap Try Again. | The retained recording is retried; it is not deleted before a successful save. |
| R11 | On a failed recording, tap Type Instead. | The user can save a typed replacement while the failed audio is handled safely. |
| R12 | On a failed recording, choose Delete Recording and cancel once. | Cancelling keeps the recording and recovery card. |
| R13 | Confirm Delete Recording, force-quit, and relaunch. | The deleted recording does not resurrect. |

## 9. Entry points and iPhone integrations

| ID | Do this | Expected result |
|---|---|---|
| I01 | Long-press the Home Screen icon and choose the speak action. | One capture opens directly. |
| I02 | Long-press the Home Screen icon and choose the type action. | One typed capture opens directly with the keyboard ready. |
| I03 | Add and tap the Lock Screen Speak It widget. | It opens the intended capture route once. Private item text is not exposed by default. |
| I04 | Run the Speak It Capture shortcut from Shortcuts. | The capture is delivered once and appears in Speak It. |
| I05 | Assign that shortcut to Double Back Tap, lock the phone, and double-tap. | The shortcut starts as iOS permits, without multiple captures. |
| I06 | If the phone has an Action Button configured for the shortcut, press it once and rapidly twice. | One press starts capture; rapid triggers do not create duplicate sessions. |
| I07 | Share selected text from Safari/Notes to Speak It. | The exact shared text reaches a reviewable capture and is saved once. |
| I08 | Share a webpage URL to Speak It. | The URL and useful context are retained without freezing the share sheet. |
| I09 | Start capture from Siri or Spotlight. | It reaches the correct Speak It action and does not require hunting through the app. |
| I10 | Start a capture that shows a Live Activity, lock the phone, then finish/cancel it. | Status is accurate and the Live Activity disappears when the capture is over. |
| I11 | Tap a notification’s available actions, then open the app. | The intended item changes exactly once and the UI reflects the action. |
| I12 | Say “Add dentist appointment Friday at 2 to my calendar.” | Speak It prepares the correct calendar event/review flow; it does not silently create the wrong event. |
| I13 | Say “Text Sarah happy birthday tomorrow at 9.” | It schedules the follow-up and later prepares Apple’s message composer; it does not claim the message was silently sent. |

## 10. Privacy, offline behavior, sync, and account edges

| ID | Do this | Expected result |
|---|---|---|
| P01 | Inspect Lock Screen widgets and notifications with the phone locked. | Thought/task names are hidden by default unless the explicit privacy toggle was enabled. |
| P02 | Enable lock-screen content, verify it, then disable it. | The choice takes effect both ways and stays after relaunch. |
| P03 | Capture private-looking nonsense while offline, force-quit, and reopen. | The data remains locally available and is not lost because no account/network exists. |
| P04 | Use the app in Airplane Mode for ten minutes, then reconnect. | No sign-in wall appears; saved data remains consistent and pending local behavior recovers. |
| P05 | Open the sharing/referral area. | It may offer “Share Speak It,” but it does not promise a disabled reward or show a broken referral balance. |
| P06 | Open any Pro/purchase screen but do not buy. Rotate, background, and restore. | It stays readable, dismisses correctly, and does not unlock or charge anything accidentally. |
| P07 | If iCloud sync is visibly enabled, create a disposable item and check a second signed-in device. | It syncs once without duplication. If iCloud is unavailable under this development signing profile, the app must say so safely rather than implying sync succeeded. |
| P08 | Turn network access on and off several times while browsing Today and Memory. | Local content never disappears, reorders wildly, or duplicates. |

## 11. Accessibility and visual quality

| ID | Do this | Expected result |
|---|---|---|
| X01 | Enable VoiceOver and navigate Today, Capture, an editor, Memory, and Settings. | Every control has a useful label and logical order; state and destructive actions are announced. |
| X02 | Set Dynamic Type to the largest accessibility size. | Essential text wraps, buttons remain tappable, and no content is clipped off-screen. |
| X03 | Enable Bold Text and Increase Contrast. | Layout remains stable and text is legible. |
| X04 | Test Light and Dark appearances on every main screen. | Contrast is sufficient; sheets, text fields, separators, icons, and alerts remain visible. |
| X05 | Enable Reduce Motion and repeat capture/complete/navigation flows. | The app respects the setting and remains understandable without relying on animation. |
| X06 | Use only one hand and tap near edges, between rows, and outside sheets. | Tap targets are forgiving; accidental destructive actions do not occur. |
| X07 | Open the keyboard in every text field and use dictation, emoji, paste, Undo, and Return. | The keyboard does not cover Save/Cancel, corrupt input, or trap the user. |

## 12. Stress, corruption, and Build 13 handoff

| ID | Do this | Expected result |
|---|---|---|
| Z01 | Make 30 normal captures in a row: ten tasks, ten memories, and ten mixed/messy thoughts. | All 30 are recoverable and correctly categorized within reasonable limits; no slowing, crash, or duplicate storm. |
| Z02 | While an item is being saved, immediately switch tabs, background the app, and return. | The item is saved once and appears in the correct place. |
| Z03 | Schedule five reminders one minute apart, force-quit the app, and lock the phone. | Each intended notification arrives once and in order. |
| Z04 | Rapidly complete, undo, edit, archive, and restore disposable items. | No item vanishes, duplicates, or inherits another item’s text. |
| Z05 | Fill Today and Memory with enough items to scroll several screens. | Scrolling stays smooth, rows do not visually reuse the wrong content, and search remains accurate. |
| Z06 | Reboot after the stress pass and inspect totals/content. | Data remains intact and the app launches normally. |
| Z07 | Leave at least one action, memory, recurring reminder, location reminder, archived item, and completed item in Build 12. | This becomes the preserved upgrade fixture for Build 13. |
| Z08 | Install Build 13 over Build 12 without deleting the app. | All Build 12 data, settings, permissions, recurrence, reminder state, and location configuration survive the upgrade. No onboarding reset or duplicate notifications. |

## High-priority bug watchlist

Treat these as especially important if observed:

1. A recurring reminder without an explicitly spoken time fails to alert at the default 9:00 AM time or stops after the first occurrence.
2. “Wake me” creates a generic alarm title such as “Your reminder” instead of using the intended action.
3. A capture is lost after interruption, force-quit, lock, route change, or failed organization.
4. The same trigger creates duplicate captures, reminders, notifications, or geofences.
5. Speak It guesses an ambiguous date or arbitrary place instead of asking for review.
6. A normal scheduled message is marked complete before the Apple message composer confirms a send.
7. Private item content appears on the Lock Screen with privacy display disabled.
8. A completed, cancelled, deleted, or edited reminder still fires from stale scheduling.
9. Data disappears, duplicates, or changes classification after relaunch, reboot, offline use, or the Build 13 upgrade.
10. Any crash, infinite spinner, blank screen, audio recording dead end, or screen that cannot be dismissed.

## Bug note template

```text
Case ID:
Result: FAIL / WEIRD / BLOCKED
Exact words/actions:
Expected:
Actual:
Time observed:
Screenshot or recording:
Did it happen again?:
Anything unusual (offline, AirPods, locked, permission state):
```
