# Speak It Build 13 — New-User Bug Hunt

Target: Speak It 1.0 (Build 13, Release) on Calvin's iPhone 13, iOS 26.6
Installed: 2026-08-22
Device state: **factory-fresh** — app container deleted and the Keychain free-capture ledger cleared, so this is a genuine first-ever install.

Purpose: decide whether Build 13 is ready to ship. If every **Ship gate** box is ticked, Build 13 is ready.

Automated evidence already in hand: full unit suite green (508 tests, 1 intentional skip, 0 failures) and a clean Release compile for device. Everything below is the part machines cannot check.

**157 checks across the pass**, plus 9 ship-gate boxes, a 15-line stop-ship watchlist, and 4 gaps to acknowledge at sign-off. Tick a box only when you actually saw the expected result. If something is wrong, leave it unticked and write it up with the template at the end.

| Section | Checks | Done |
|---|---|---|
| 0. Before you start | 3 | ☐ |
| 1. First run | 10 | ☐ |
| 2. Guided first capture | 10 | ☐ |
| 3. Free allowance and paywall | 13 | ☐ |
| 4. Speech engine | 13 | ☐ |
| 5. Clock repair and alarms | 12 | ☐ |
| 6. Shopping lists | 12 | ☐ |
| 7. Understanding | 16 | ☐ |
| 8. Recurrence and DST | 10 | ☐ |
| 9. Core regression sweep | 20 | ☐ |
| 10. Entry points | 12 | ☐ |
| 11. Location reminders | 12 | ☐ |
| 12. Accessibility and visuals | 8 | ☐ |
| 13. Stress and durability | 6 | ☐ |

---

## 0. Before you start

The reset covered everything the app owns. Three things live outside the app and survived it. Clear them now or Section 1 will not be a true first run.

- [ ] **P01** Shortcuts app → delete any existing "Speak It Capture" shortcut.
  *Why:* it is orphaned and points at the old install.
- [ ] **P02** Settings → Accessibility → Touch → Back Tap → set Double Tap and Triple Tap to None.
- [ ] **P03** Home Screen and Lock Screen → confirm no leftover Speak It widget.

Do **not** reinstall, delete, or reset the app during this pass. The whole point is one continuous life of one install.

### What was reset, and what that means

- All captures, tasks, memories, settings, and permissions are gone.
- The **10 free lifetime captures are genuinely restored to 10.** First time the paywall gate has been testable end to end, because the allowance is stored in the Keychain specifically to survive reinstalls (`SpeakIt/Features/Setup/SubscriptionStore.swift:5`). Spend those 10 deliberately — Section 3 depends on them.
- Notification, microphone, speech, and location permissions will all be asked for again from scratch.

### How to test

- Talk like a person, not like a test script. Ramble, pause, correct yourself, mumble.
- For every problem record: case ID, exact words spoken or typed, what happened, what you expected, and the time.
- Use `BLOCKED` in your notes for anything you could not attempt.

### Known limits of this build — not bugs

- **Purchases cannot complete.** This is a local Release install, not TestFlight. The StoreKit config file is wired only into the Xcode scheme, so the app talks to the real sandbox. The paywall UI and the capture gate are fully testable; an actual transaction is not. Do not fail a case because a purchase will not finish — mark it `BLOCKED`.
- **The SFSpeechRecognizer fallback path will not be exercised here.** This phone is iOS 26.6, so it runs Apple's SpeechAnalyzer backend. The legacy path ships untested on this device by definition. See Gaps at the end.
- Named businesses such as "Costco" are not geocoded. Saved safely + needs review is correct.
- A dated task without "remind me" may appear in the timeline without alerting. "Buy milk tomorrow" should not alert; "Remind me to buy milk tomorrow" should.
- An ordinary reminder is not an alarm. "Wake me" / "set an alarm" asks for alarm behavior.
- Speak It cannot silently send a text. It prepares Apple's composer and completes only after a confirmed send.
- Today rows do not use swipe-to-complete. Use the circle or the editor.
- Referral rewards are off. Sharing may work; no reward should be promised.

---

## 1. First run — never tested on a clean device

Highest-value section in this pass. Build 13 changed the very first launch after a true uninstall (`PersistenceController.swift:63` prepares the app-group store directory that iOS has not created yet). That code path has never run on this phone before today.

**Do these in order, before opening anything else.**

- [ ] **N01** Tap the Speak It icon for the very first time.
  *Expect:* opens to Welcome. No crash, no blank screen, no "storage unavailable", no delay beyond a normal cold launch.
- [ ] **N02** Watch specifically for a storage error on that first launch.
  *Expect:* `StorageUnavailableView` never appears. **If it does, stop** — that is the Build 13 store-directory fix failing, and it is stop-ship.
- [ ] **N03** Read every screen of Welcome as if you have never seen the app.
  *Expect:* wording is clear and honest. Nothing promises a feature that does not exist. Nothing asks for an account.
- [ ] **N04** Try to skip or dismiss Welcome.
  *Expect:* skipping is either cleanly possible or cleanly unavailable. It never traps you or half-completes.
- [ ] **N05** Force-quit during Welcome, then reopen.
  *Expect:* Welcome resumes sensibly. It does not skip to Today with onboarding silently marked complete.
- [ ] **N06** Complete Welcome.
  *Expect:* you land on Today, empty.
- [ ] **N07** Read the empty Today screen.
  *Expect:* the empty state explains what to do next. Not a blank void, not a wall of controls.
- [ ] **N08** Open Memory before capturing anything.
  *Expect:* calm empty state that explains what Memory is for. No crash on an empty store.
- [ ] **N09** Open Settings before capturing anything.
  *Expect:* every row renders, and the free-capture counter reads **10 of 10 remaining** (0 used). Anything else means the Keychain reset failed — stop and report.
- [ ] **N10** Force-quit and relaunch after completing Welcome.
  *Expect:* opens straight to Today. Welcome does not reappear.

## 2. Guided first capture — new in Build 13

Build 13 added three concrete example phrases to the guided first capture.

- [ ] **G01** Reach the guided first capture as a new user.
  *Expect:* three concrete example phrases, readable and specific, and genuinely things the app handles well.
- [ ] **G02** Say one of the suggested phrases verbatim.
  *Expect:* it works exactly as the example implies. An example that does not deliver is high-priority — it is the first thing a new user judges the app on.
- [ ] **G03** Say all three suggested phrases, one per capture.
  *Expect:* all three behave as advertised and land in the right destination.
- [ ] **G04** Ignore the examples and say something of your own.
  *Expect:* the guide does not force you down its path or discard your wording.
- [ ] **G05** Trigger the first capture and say nothing at all.
  *Expect:* ends gracefully, offers retry/type, creates no garbage item, and does **not** burn a free capture.
- [ ] **G06** Check the free-capture counter after the guided capture.
  *Expect:* decremented by exactly the number of real captures you made — no more.
- [ ] **G07** Deny the microphone permission when first asked, then retry.
  *Expect:* clear explanation and a typed alternative. No dead-end spinner.
- [ ] **G08** Deny speech recognition when first asked, then retry.
  *Expect:* clear recovery path; typed capture still works.
- [ ] **G09** Grant both permissions and retry.
  *Expect:* voice capture works immediately — no reinstall, no app restart needed.
- [ ] **G10** Watch the very first voice capture closely for transcription quality.
  *Expect:* see Section 4 — on a fresh install the on-device model may still be downloading.

## 3. Free allowance and paywall — genuinely testable for the first time

The counter is at 10. Spend it on purpose. Once it is gone it is gone, short of another Keychain reset.

- [ ] **F01** After each of your first few captures, check Settings.
  *Expect:* the count decrements by exactly one per real saved capture.
- [ ] **F02** Make a capture that fails, or that you discard.
  *Expect:* it does **not** consume a free capture. Charging for a discarded or failed capture is high-priority.
- [ ] **F03** Make a capture that splits into several items.
  *Expect:* counts as **one** capture, not one per extracted item.
- [ ] **F04** Reach capture 8 and 9.
  *Expect:* any "running low" messaging is honest, calm, and not nagging.
- [ ] **F05** Use the 10th capture.
  *Expect:* completes normally and is saved. The 10th is not stolen by the paywall.
- [ ] **F06** Attempt an 11th capture.
  *Expect:* paywall appears with the "used all 10" wording. Nothing is lost; the attempted thought is not silently discarded.
- [ ] **F07** Read the paywall as a new user.
  *Expect:* price and terms are clear and match the intended $1.99/month. Nothing misleading.
- [ ] **F08** Dismiss the paywall.
  *Expect:* you return to the app, and everything already saved is fully readable and editable.
- [ ] **F09** Confirm the app is not bricked at the limit.
  *Expect:* reading, editing, completing, searching, archiving, and reminders all still work. Only new capture is gated.
- [ ] **F10** Force-quit and relaunch at the limit.
  *Expect:* the limit persists. It neither resets to 10 nor falsely reports Pro.
- [ ] **F11** Try the 11th capture via Shortcut, widget, and Share extension.
  *Expect:* the gate holds on every entry point with a clear message — not a silent failure or a lost capture.
- [ ] **F12** Tap Restore Purchases with no purchase.
  *Expect:* reports honestly that nothing was found. Does not hang or falsely unlock.
- [ ] **F13** Attempt an actual purchase.
  *Expect:* `BLOCKED` on this build. Record whether products load at all, and whether failure is graceful rather than a spinner or a crash.

## 4. Speech engine — the biggest change in Build 13

Recognition now runs behind `SpeechRecognitionBackend`: SpeechAnalyzer on iOS 26+, with automatic SFSpeechRecognizer fallback. On a fresh install the on-device model may not be downloaded yet, so early captures may transparently use the fallback and later ones the new engine. **A quality or behavior change partway through this pass is exactly what we are hunting for.**

- [ ] **E01** Compare transcription quality on captures 1–3 versus captures 8–10.
  *Expect:* any shift is an improvement or invisible. A regression mid-session is high-priority.
- [ ] **E02** Make the very first voice capture within seconds of first launch.
  *Expect:* never blocked, never spinning on a model download, never failing because the model is missing.
- [ ] **E03** Capture on Wi-Fi, then in Airplane Mode.
  *Expect:* recognition still works offline. Any unavailable feature explains itself instead of failing silently.
- [ ] **E04** Tap Speak and start talking instantly: "Call the dentist tomorrow."
  *Expect:* the opening word is captured. "Call" is not clipped. This is the classic engine-swap regression.
- [ ] **E05** Speak continuously for about 60 seconds with five unrelated thoughts.
  *Expect:* stable throughout, nothing truncated mid-session, sensible splitting.
- [ ] **E06** Speak very quietly, then very loudly.
  *Expect:* both handled without a stuck recorder or an empty transcript.
- [ ] **E07** Speak with background noise — TV on, tap running.
  *Expect:* degrades gracefully. Does not hang or save nonsense as fact.
- [ ] **E08** Use accented names and non-English words: "Café with Zoë."
  *Expect:* preserved correctly. No mojibake.
- [ ] **E09** Start with AirPods, disconnect mid-capture, keep talking.
  *Expect:* route change handled without a stuck recorder. Any lost audio is clearly disclosed.
- [ ] **E10** Take a phone call or invoke Siri mid-capture.
  *Expect:* recording pauses or stops safely with recovery offered. No crash, no corrupt item.
- [ ] **E11** Lock the phone mid-capture, then unlock.
  *Expect:* predictable handling and recovery. Recoverable audio is never silently lost.
- [ ] **E12** Enable Low Power Mode and make five captures.
  *Expect:* capture, organization, and notifications stay correct. No endless processing.
- [ ] **E13** Force-quit mid-capture, then relaunch.
  *Expect:* no zombie recorder, no stuck Live Activity, no lost saved data.

## 5. Clock repair and alarms — Build 13 fixes

Build 13 repairs compact clock digits, keeps alarm-time lists intact when dictation writes "to" between times, titles wake/alarm rows by the command, and stops a *ringing* AlarmKit alarm on completion. iOS 26.6 supports AlarmKit, so real alarm behavior is expected here.

- [ ] **K01** "Set an alarm for 630 tomorrow."
  *Expect:* resolves to **6:30** — not 630, not a review prompt. This is the compact-digit repair.
- [ ] **K02** "Set an alarm for 730 in the morning."
  *Expect:* resolves to 7:30 AM.
- [ ] **K03** "Set alarms for 7 and 7:15 tomorrow."
  *Expect:* two separate alarms at the correct times.
- [ ] **K04** "Set alarms for 7 to 7:15 tomorrow." (dictation often writes "to" for "and")
  *Expect:* still two alarms — not a single range, not one dropped time. This is the Build 13 fix.
- [ ] **K05** "Wake me at 7 tomorrow."
  *Expect:* alarm behavior, with a title describing getting up — **not** a generic "Your reminder" and not a leftover bare hour.
- [ ] **K06** "Wake me up at 6:45 so I can go to the gym."
  *Expect:* title reflects the command or purpose, not the stray hour.
- [ ] **K07** Let an alarm actually ring, then complete the item from the app while it is ringing.
  *Expect:* the ringing alarm **stops**. This is the Build 13 fix, and a still-ringing alarm after completion is high-priority.
- [ ] **K08** Let an alarm ring and dismiss it from the system UI instead.
  *Expect:* the item's state stays consistent with what you did.
- [ ] **K09** Complete an alarm item well before it fires.
  *Expect:* the scheduled alarm is cancelled and never fires.
- [ ] **K10** Set an alarm, delete the item, then wait past the time.
  *Expect:* nothing fires.
- [ ] **K11** "Remind me at 7 tomorrow to get up."
  *Expect:* a normal notification, not an alarm — the wording did not request one.
- [ ] **K12** Set an alarm, lock the phone, and let it fire with the app force-quit.
  *Expect:* fires correctly and opens the right item.

## 6. Shopping lists — new in Build 13

Grouped shopping lists now ship in Today, and fronted place conditions with commas keep rows on the store list.

- [ ] **H01** "Buy bread and milk and eggs."
  *Expect:* one grouped shopping list or card — not three noisy unrelated reminders.
- [ ] **H02** "At the store, buy bread, milk, and eggs."
  *Expect:* the fronted place condition keeps all three on the store list. This is the Build 13 comma fix.
- [ ] **H03** "When I'm at the grocery store, pick up bananas, coffee, and paper towels."
  *Expect:* all three land on one store list, correctly grouped.
- [ ] **H04** Add more items to an existing list in a second capture.
  *Expect:* they join the existing list rather than creating a duplicate.
- [ ] **H05** Check the item grouping — produce, dairy, and so on.
  *Expect:* sensible grouping. A wrong group is minor; a lost item is not.
- [ ] **H06** Tick off individual items on the list.
  *Expect:* each ticks independently and the state survives relaunch.
- [ ] **H07** Tick every item on a list.
  *Expect:* the list completes sensibly and leaves Today without deleting your history.
- [ ] **H08** Open the shopping list card with one item, then with about 20.
  *Expect:* both render well. No clipping, no runaway height, smooth scrolling.
- [ ] **H09** Edit a shopping item's wording.
  *Expect:* edits save; the original transcript stays immutable.
- [ ] **H10** Delete one item from a list of several.
  *Expect:* only that item goes. The list survives.
- [ ] **H11** View the shopping list at largest Dynamic Type and in Dark Mode.
  *Expect:* readable, tappable, nothing clipped.
- [ ] **H12** "Buy milk." (single item)
  *Expect:* does not create a weird one-row shopping list if a plain action is more appropriate. Judge whether it feels right.

## 7. Understanding — Build 13 routing changes

- [ ] **D01** Late in the evening: "Remind me to take out the bins today."
  *Expect:* falls back to **8 PM** rather than kicking to review. This is the Build 13 late-day fix.
- [ ] **D02** "I keep meaning to call the dentist."
  *Expect:* routes to Today as an outstanding obligation, not to Memory.
- [ ] **D03** "I've been putting off renewing my passport."
  *Expect:* routes to Today as an outstanding action.
- [ ] **D04** "Sarah birthday is May 13." (dropped possessive)
  *Expect:* files under the person Sarah in Memory, not as a task due May 13.
- [ ] **D05** "Remember Mom favourite flower is peonies." (dropped possessive)
  *Expect:* files under Mom.
- [ ] **D06** "Buy milk."
  *Expect:* one undated action under When you have time. No alert.
- [ ] **D07** "Remind me to buy milk tomorrow."
  *Expect:* dated tomorrow, alerts at the 9:00 AM default.
- [ ] **D08** "Maybe I could learn guitar."
  *Expect:* an idea, not a firm action.
- [ ] **D09** "Don't remind me to call John."
  *Expect:* no call-John reminder. The negation must be honored.
- [ ] **D10** "Sarah reminded me to call John."
  *Expect:* reported speech must not auto-schedule a reminder.
- [ ] **D11** "I bought milk yesterday."
  *Expect:* a past fact, not a new buy-milk task.
- [ ] **D12** "Book the appointment for 4/5."
  *Expect:* ambiguous — asks for review rather than guessing.
- [ ] **D13** "Book the appointment for 13/5."
  *Expect:* resolves to May 13 without asking.
- [ ] **D14** "Call Mom at five—no, wait—make that six tomorrow."
  *Expect:* one item at 6:00 PM, not two.
- [ ] **D15** "Buy bread. Call Alex. Remember Alex is allergic to peanuts. Idea: host brunch."
  *Expect:* actions to Today, the fact to People, the idea to Ideas. Nothing lost.
- [ ] **D16** "Remind me to feed the dog when I get home tonight."
  *Expect:* place plus time in one trigger — asks which to use. Neither fires until resolved.

## 8. Recurrence and DST — Build 13 fix

Repeating notifications now trigger only when the next fire is the occurrence itself, so DST and future-dated series fire correctly.

- [ ] **Y01** "Every Monday at 9 remind me to file my timesheet."
  *Expect:* weekly Monday 9:00 AM reminder, recurrence visible.
- [ ] **Y02** "Remind me every day to check my blood pressure."
  *Expect:* daily reminder at the 9:00 AM default. Missing or non-repeating is high-priority.
- [ ] **Y03** "Remind me every Friday to submit my report."
  *Expect:* weekly Friday reminder at the default time.
- [ ] **Y04** "Remind me every 24 hours to drink water."
  *Expect:* elapsed-time recurrence, visibly different from "every day at 9."
- [ ] **Y05** Create a recurring reminder that starts **in the future** — e.g. every Monday, created on a Wednesday.
  *Expect:* the first notification fires on the correct future occurrence. Not immediately, and not never. This is the Build 13 fix.
- [ ] **Y06** Set a short recurring reminder and let it fire twice.
  *Expect:* both fire, once each, at the right times.
- [ ] **Y07** Complete one occurrence of a recurring item.
  *Expect:* that occurrence is recorded and the next stays scheduled. The series does not vanish.
- [ ] **Y08** Edit a recurring item's time and save.
  *Expect:* future occurrences use the new time. No duplicate stale notifications.
- [ ] **Y09** Change the iPhone time zone, reopen, inspect a future 9:00 AM item, then restore the time zone.
  *Expect:* behavior stays consistent. No duplication or unpredictable shifting.
- [ ] **Y10** Delete a recurring item and wait past its next fire time.
  *Expect:* nothing fires.

## 9. Core regression sweep

Everything above is new. This is the safety net.

- [ ] **B01** Type only spaces and save.
  *Expect:* no empty thought. The UI explains what is needed.
- [ ] **B02** Capture identical wording twice within 15 seconds, then again after 15+ seconds.
  *Expect:* the immediate repeat is blocked as a duplicate; the later one is kept.
- [ ] **B03** Trigger capture repeatedly — while Starting, while Listening, while Organizing.
  *Expect:* one session, one result. No stacking, no duplicates, no lost prior result.
- [ ] **B04** Start a capture, enter words, then close it.
  *Expect:* offers keep, type, or discard. Never silently loses the draft.
- [ ] **B05** Complete an item, then undo.
  *Expect:* leaves Today, returns intact.
- [ ] **B06** Complete an item and wait past the undo window.
  *Expect:* undo expires cleanly; the item is in completed history.
- [ ] **B07** Edit wording and time, then inspect the original transcript.
  *Expect:* edits apply; the original transcript is unchanged and still available.
- [ ] **B08** Create overdue, due-today, future, and undated actions.
  *Expect:* correct sections and order.
- [ ] **B09** Try swiping a Today row.
  *Expect:* does not accidentally complete or delete.
- [ ] **B10** Search a mid-word term from a memory using different capitalization.
  *Expect:* the right memory is found.
- [ ] **B11** Pin and unpin a memory.
  *Expect:* moves in and out of Pinned without duplicating.
- [ ] **B12** Archive, undo, archive again, restore from Archive.
  *Expect:* content intact throughout.
- [ ] **B13** Tap permanent Delete, then cancel.
  *Expect:* nothing is deleted.
- [ ] **B14** Permanently delete a disposable item and confirm.
  *Expect:* only that item goes, and it does not resurrect after relaunch.
- [ ] **B15** "Cancel my milk reminder" with exactly one match.
  *Expect:* that reminder is cancelled and its notification removed.
- [ ] **B16** "Cancel my call Mom reminder" with two similar matches.
  *Expect:* asks which one. Does not guess.
- [ ] **B17** "Cancel all my reminders."
  *Expect:* not performed without explicit confirmation and clear scope.
- [ ] **B18** Rapidly open and close several item editors.
  *Expect:* always the right item. Edits never land on the wrong record.
- [ ] **B19** Force-quit and relaunch.
  *Expect:* everything saved is still there.
- [ ] **B20** Reboot the phone, unlock, reopen.
  *Expect:* data intact; scheduled reminders still present.

## 10. Entry points

Set these up as a new user — the Shortcut does not exist yet.

- [ ] **J01** Run the in-app Capture Anywhere setup from scratch.
  *Expect:* instructions are clear and the Shortcut is actually created.
- [ ] **J02** Long-press the Home Screen icon → speak action.
  *Expect:* one capture opens directly.
- [ ] **J03** Long-press the Home Screen icon → type action.
  *Expect:* typed capture opens with the keyboard ready.
- [ ] **J04** Add and tap the Lock Screen widget.
  *Expect:* opens the intended route once. No private text exposed by default.
- [ ] **J05** Run the Speak It Capture shortcut from Shortcuts.
  *Expect:* delivered once, appears in the app.
- [ ] **J06** Assign it to Double Back Tap, lock the phone, double-tap.
  *Expect:* starts as iOS permits. No multiple captures.
- [ ] **J07** Share selected text from Safari or Notes to Speak It.
  *Expect:* exact text reaches a reviewable capture, saved once.
- [ ] **J08** Share a webpage URL.
  *Expect:* URL and context retained without freezing the share sheet.
- [ ] **J09** Start a capture that shows a Live Activity, lock the phone, then finish or cancel.
  *Expect:* status accurate; the Live Activity disappears when done.
- [ ] **J10** Tap a notification's actions, then open the app.
  *Expect:* the item changes exactly once and the UI reflects it.
- [ ] **J11** "Text Sarah happy birthday tomorrow at 9."
  *Expect:* schedules the follow-up and later prepares Apple's composer. Never claims a silent send.
- [ ] **J12** "Add dentist appointment Friday at 2 to my calendar."
  *Expect:* prepares the correct event or review flow. Does not silently create a wrong event.

## 11. Location reminders

Grant location permissions fresh. Requires Always plus Precise for dependable background triggers.

- [ ] **L01** Settings → Capture & reminders → Places, before setting anything.
  *Expect:* Home and Work show Not set, with a clear way to configure.
- [ ] **L02** Set Home to Current Location.
  *Expect:* iOS asks for access; a recognizable place or address is shown.
- [ ] **L03** "Remind me to take the bins out when I get home."
  *Expect:* a Home location reminder is created, or it clearly shows needs-review / permission guidance.
- [ ] **L04** Decline Always Location.
  *Expect:* stays safely blocked with Open Settings. Never pretends to be active.
- [ ] **L05** Grant Always Location.
  *Expect:* the blocker clears and the reminder becomes eligible.
- [ ] **L06** Turn Precise Location off, then back on.
  *Expect:* clearly reports the need for Precise; the warning clears on re-enable without duplicates.
- [ ] **L07** "Remind me to buy cereal when I get to Costco."
  *Expect:* saved as needs-review or inert. Does not pick a random Costco.
- [ ] **L08** "Remind me to lock the car when I leave here."
  *Expect:* a one-time coordinate snapshot, not a pointer that follows you.
- [ ] **L09** In Airplane Mode: "Remind me when I leave here."
  *Expect:* saved, but clearly states location is unavailable rather than inventing one.
- [ ] **L10** With an active arrival reminder, background the app and enter the Home region.
  *Expect:* one notification fires and opens the correct reminder.
- [ ] **L11** Change the saved Home address with an active Home reminder.
  *Expect:* the reminder follows the pointer; its wording is unchanged.
- [ ] **L12** Complete, delete, or change location on an active reminder, then cross the old boundary.
  *Expect:* the old geofence does not fire.

For a deeper pass use `LOCATION_DEVICE_QA.md`.

## 12. Accessibility and visual quality

- [ ] **X01** VoiceOver across Today, Capture, editor, Memory, Settings, **and the new shopping list**.
  *Expect:* useful labels, logical order, destructive actions announced.
- [ ] **X02** Largest accessibility Dynamic Type on every screen, including the shopping list and paywall.
  *Expect:* text wraps, buttons stay tappable, nothing clipped off-screen.
- [ ] **X03** Bold Text and Increase Contrast.
  *Expect:* layout stable, text legible.
- [ ] **X04** Light and Dark on every main screen, including new Build 13 screens.
  *Expect:* sufficient contrast; sheets, fields, separators, icons, alerts all visible.
- [ ] **X05** Reduce Motion through capture, complete, and navigation flows.
  *Expect:* respected and still understandable.
- [ ] **X06** Switch to Dark Mode while the app is open.
  *Expect:* every screen stays readable. No flash of an invisible layout.
- [ ] **X07** Keyboard in every text field: dictation, emoji, paste, Undo, Return.
  *Expect:* never covers Save or Cancel, never traps you.
- [ ] **X08** One-handed tapping near edges and between rows.
  *Expect:* forgiving targets; no accidental destructive actions.

## 13. Stress and durability

Run this once you accept it will hit the capture limit — plan around F05 and F06.

- [ ] **Z01** Fill Today and Memory with enough items to scroll several screens.
  *Expect:* smooth scrolling, no wrong-content row reuse, accurate search.
- [ ] **Z02** While an item is saving, switch tabs, background the app, and return.
  *Expect:* saved once, in the right place.
- [ ] **Z03** Schedule five reminders one minute apart, force-quit, lock the phone.
  *Expect:* each arrives once, in order.
- [ ] **Z04** Rapidly complete, undo, edit, archive, and restore disposable items.
  *Expect:* nothing vanishes, duplicates, or inherits another item's text.
- [ ] **Z05** Reboot after the stress pass and inspect totals.
  *Expect:* data intact, app launches normally.
- [ ] **Z06** Leave the app backgrounded 30+ minutes, then return.
  *Expect:* refreshes correctly and accepts input.

---

## Ship gate for Build 13

Build 13 is ready when **every box below** is ticked.

- [ ] **Clean first launch** — N01, N02, N09 pass. The fresh-install store fix is the single riskiest change in this build.
- [ ] **Onboarding examples deliver** — G01, G02, G03 pass.
- [ ] **Allowance is honest** — F02, F03, F05, F06, F09, F10 pass. Charged accurately, and the limit neither steals a capture nor bricks the app.
- [ ] **No speech regression** — E01, E02, E04 pass.
- [ ] **Alarm fixes hold** — K01, K04, K05, K07 pass. K07 (stop a ringing alarm) is the one a user notices most.
- [ ] **Shopping lists work** — H01, H02, H06 pass.
- [ ] **Routing changes work** — D01, D02, D04 pass.
- [ ] **Recurrence actually repeats** — Y02, Y05 pass.
- [ ] **Nothing on the stop-ship watchlist was observed.**

Any single stop-ship item means Build 13 is not ready, no matter how much else passes.

### Stop-ship watchlist

Tick each line only at the very end of the pass, and only if you never saw it.

- [ ] **W01** No crash, hang, infinite spinner, blank screen, or undismissable screen.
- [ ] **W02** No `StorageUnavailableView` on a clean first launch (N02).
- [ ] **W03** No capture lost after interruption, force-quit, lock, route change, or failed organization.
- [ ] **W04** No free capture consumed by a discarded or failed capture, and the 10th was not stolen by the paywall.
- [ ] **W05** The allowance never reset to 10, and the app never falsely reported Pro.
- [ ] **W06** The app never became unusable at the capture limit — only new capture was gated.
- [ ] **W07** No alarm kept ringing after its item was completed (K07).
- [ ] **W08** No recurring reminder fired once and stopped, or never fired.
- [ ] **W09** No completed, cancelled, deleted, or edited reminder fired from stale scheduling.
- [ ] **W10** No duplicate captures, reminders, notifications, or geofences from one trigger.
- [ ] **W11** Speak It never guessed an ambiguous date or an arbitrary place instead of asking for review.
- [ ] **W12** No scheduled message was marked complete before the composer confirmed a send.
- [ ] **W13** No private item content appeared on the Lock Screen with privacy display disabled.
- [ ] **W14** No data disappeared, duplicated, or changed classification after relaunch or reboot.
- [ ] **W15** No original transcript wording was altered or lost by professionalization or editing.

### Gaps this pass cannot close

Record these as known-unverified when you sign off on Build 13.

- [ ] **Acknowledged: in-app purchase completion.** Needs TestFlight or a sandbox Apple ID. The gate is verified; the transaction is not.
- [ ] **Acknowledged: the SFSpeechRecognizer fallback path.** This phone is iOS 26.6 and always takes the SpeechAnalyzer route, so the legacy path is unexercised on device.
- [ ] **Acknowledged: the Build 12 → 13 upgrade.** The on-device upgrade fixture was deliberately destroyed to create this clean state. Mitigating factor: the SwiftData schema is unchanged at V3 in this build (`PersistenceController.swift:6`), so there is no migration stage between 12 and 13 — the upgrade risk is low but unproven on hardware. Worth a simulator 12→13 install before submitting.
- [ ] **Acknowledged: multi-device iCloud sync.** Only one device is in play.

---

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
Anything unusual (offline, AirPods, locked, permission state, capture count):
```
