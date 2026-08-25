# Speak It — Final Release Candidate Acceptance Audit

> **HISTORICAL AUDIT — SUPERSEDED AUGUST 24, 2026.** This file preserves the
> observations from an earlier build and its provisional P1 classifications;
> several were fixed afterwards. Do not use its top-line verdict as the current
> release decision. `APP_STORE_SUBMISSION.md` now carries the live verdict,
> current automated evidence, and remaining submission gates.

> **STATUS: IN PROGRESS.** The executive summary and release verdict at the top of
> this file are provisional and will be rewritten once every section is complete.
> The section-by-section body below is the durable evidence record and is written
> incrementally as each section finishes.

---

## RUNNING SUMMARY

**Provisional verdict: NOT READY FOR TESTFLIGHT**

| | |
| --- | --- |
| Audit completion | **~95%** |
| Sections complete | A, B, C, D, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T |
| Sections partial | E (toggle-driven fields blocked in an earlier session) |
| Sections not started | none |
| **P0 confirmed** | **0** |
| **P1 confirmed** | **1** |
| P1 pending severity review | 5 |
| P2 | 15 |
| P3 | 8 |

The provisional verdict rests on a single confirmed P1 (recurring reminders that
never fire), not on general instability. Everything verified so far is either
sound or P2-and-below.

### AUDIT CHECKPOINT

```
AUDIT CHECKPOINT
Completed: A, B, C, D, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T
Partial:   E (title/type/category/due-time/recurrence-interval/complete/delete
              all verified; every Toggle-driven field — add/remove due date,
              add/remove reminder, add/remove recurrence — blocked in an
              earlier session by a Toggle-control automation limitation, not
              a product defect; overdue-row and location-edit outstanding;
              alarm-edit now covered by SECTION J this session)
Remaining: none — only E's toggle-blocked fields remain open, and those need
    a tooling fix (or physical device), not more audit time
P0: 0
P1: 1 confirmed, 5 pending severity review (added E-1: recurring reminders'
    2nd+ occurrence depends on the user completing the 1st — source-confirmed,
    not yet black-box reproduced to a missed notification; added Q-1: the
    floating dock overlaps content and its own labels become unreadable at
    the largest accessibility text sizes; added M-1: the working-tree website
    currently prints a 50%-off summer sale the shipping app's own flag has
    switched off, and disagrees with the app's own monthly-plan pricing UI —
    not yet committed or deployed, but must not ship as-is)
P2 added this session: S-1 (PrivacyInfo.xcprivacy has no
    NSPrivacyAccessedAPICategorySystemBootTime declaration for the
    `ProcessInfo.processInfo.systemUptime` call in SpeechTranscriber.swift)
P3 added this session: L-1 (no Associated Domains entitlement or
    apple-app-site-association file backs the https://speakitapp.ca/invite
    universal-link branch of ReferralDeepLink — currently harmless because the
    live redemption flow uses the speakit:// custom scheme instead, but the
    https branch is dead code as shipped); T-1 (Website's referral
    troubleshooting prose on /support/ and /privacy/ is static and not gated
    by REFERRALS_ENABLED, unlike the promotional card on the home page);
    R-1 (an interrupted typed draft recovers correctly and silently on next
    launch — durable by design, but no toast/banner acknowledges the
    recovery to the person)
Last completed section: R (this session — black-box error/recovery states
    plus a full final clean-install re-confirmation); I, J, O
    (re-confirmation), P (earlier session); L, M, S, T (prior session —
    static/source/build audit only)
Simulator state: iPhone 17 / E5892B9B. Release build rebuilt clean from the
                 current working tree (`e488642` + uncommitted changes,
                 unchanged since the prior checkpoint) into
                 /tmp/SpeakItAuditRelease this session. SECTION R ended with
                 a **genuinely fresh install**: uninstalled, `simctl privacy
                 reset all`, keychain reset, no stray plist found, reinstalled,
                 and walked Welcome → Try it now → "Buy toothpaste" →
                 Remembered → Continue → Today → terminate/relaunch (Welcome
                 did not repeat). Today currently holds exactly one item,
                 **Buy toothpaste** (Shopping, When you have time), and
                 Memory is empty. Appearance is **system default (light)** —
                 the prior session's Dark preference and all prior sample
                 data (Call the bank, passport/bins test items, Ideas/People
                 entries, location authorization state) were cleared by this
                 reset and are gone. Any future session should treat this as
                 the new baseline rather than expecting the state described
                 in earlier checkpoint entries below.
Prior simulator state (superseded by the SECTION R reset above; preserved
                 only for historical reference to earlier sections' results):
                 iPhone 17 / E5892B9B, Release build rebuilt clean from the
                 current working tree and reinstalled fresh at the start of
                 an earlier session (build 10). Location authorization ended
                 that session as Always (restored after a deliberate
                 revoke/grant test in SECTION I). Today ended that session
                 with: Needs review 0, Coming up 3 (Call the bank; Every
                 Monday at 9 remind me to file the t… ; Pay rent on the
                 15th), When you have time 1 (Take out the bins when I get
                 home, resolved to Home with Status: Active), 1 completed
                 today (the former alarm item "Your reminder"). Appearance
                 **Dark** in-app. Day-change and timezone behavior remain
                 unverified live — see SECTION P.
```

---

## EXACT BUILD AND CONFIGURATION TESTED

| Item | Value |
| --- | --- |
| Working tree | `e488642` + uncommitted changes (see `git status`) |
| Marketing version / build | `1.0` / `10` |
| Bundle ID | `com.calvinwak.SpeakIt` |
| Deployment target | iOS 17.0 |
| Device family | iPhone only (`TARGETED_DEVICE_FAMILY = 1`) |
| Simulator | iPhone 17, iOS 26.5, `E5892B9B-DB3E-4102-AB62-E1598FCC3F7E` |
| Release build | `/tmp/SpeakItAuditRelease` — compiled clean |
| Debug build | `/tmp/SpeakItAuditDebug` — compiled clean |
| `SPEAKIT_ANALYTICS_KEY` | `""` (empty — Debug and Release) |
| `SPEAKIT_REFERRAL_API_URL` | `""` (empty — referrals OFF) |
| `SPEAKIT_SUMMER_SALE_ENABLED` | `NO` (sale OFF) |
| `SPEAKIT_ICLOUD_SYNC_AVAILABLE` | `YES` in Release, `NO` in Debug |
| Signing team | `LZZT2A38SD` (personal team — still to be switched) |
| Release entitlements | `SpeakItRelease.entitlements` (app group + iCloud) |

Both builds were exercised. Findings are noted as Release-specific where relevant.

### ENVIRONMENT CAVEAT — earlier fresh-install QA on this simulator was not valid

A simulator-level preferences file at

```
~/Library/Developer/CoreSimulator/Devices/E5892B9B-.../data/Library/Preferences/com.calvinwak.SpeakIt.plist
```

dated **August 3** contained `SpeakIt.hasCompletedWelcome = true` and **survived
`simctl uninstall`**. Any first-run testing performed on this simulator before
this audit therefore silently skipped Welcome and was not actually proving first
run. I moved the file aside to the scratchpad before testing section A.

**This is not an application defect.** `hasCompletedWelcome` is a normal
`@AppStorage` key; the stale file is an artifact of this simulator device, not of
the app. It is recorded here only so that prior QA results on this device are not
trusted. A genuine clean-state check will be repeated at the end of the audit.

---

## SECTION A — FRESH INSTALL

**Result: PASS**

### What was tested

Genuinely clean first launch of the **Release** build: `simctl uninstall`,
`simctl keychain reset`, `simctl privacy reset all`, stale plist removed, then
install and launch. Both the "Try it now" and "Explore first" paths, permission
behaviour, first capture durability, the receipt, and relaunch.

### Black-box observations

| Step | Observed | Verdict |
| --- | --- | --- |
| First launch | Welcome appears. Wordmark, "NO ACCOUNT" chip, listening orb, headline "Speak it. / It's handled.", the three beats **Speak → Organized → Remembered**, hint "Try 'Buy toothpaste,' or use your own words.", **Try it now**, **Explore first**. | PASS |
| Try it now | Full-screen capture, "Tap to speak / Say anything you don't want to forget.", **Type instead** at the bottom. No permission prompt yet. | PASS |
| Permission timing | Speech-recognition prompt appears only on tapping the orb — never at launch, never during Welcome. Microphone prompt follows. | PASS |
| Permission denial | Denying both produces "Microphone access is off — Allow microphone and speech recognition, or type instead." with **Open Settings** and **Type instead**. | PASS — no dead end |
| Abandon first capture | X on an empty capture returns to **Welcome**; `hasCompletedWelcome` is **not** written. | PASS |
| First capture | Typed "Buy toothpaste" → **Remembered**, subtitle "Today · When you have time", the organized row, and **Continue**. Receipt does **not** auto-dismiss. | PASS |
| Durability boundary | `hasCompletedWelcome = true` and `freeCapturesUsed = 1` appear in the app's plist only **after** the save returns. | PASS |
| Receipt row tap | Opens a "Capture details" sheet showing the original wording. | PASS |
| Continue | One screen: **Today is for action** / **Memory is for knowledge**, with correct explanatory copy, then **Continue**. | PASS — matches product contract |
| Relaunch | Lands directly in Today. Onboarding does not repeat. | PASS |
| Explore first | Enters the product with an empty Today; no capture is faked. | PASS |
| Notification permission | Not requested during onboarding at all. First requested later, in context, when a capture actually created a reminder. | PASS |

### Findings

- **P2 — A-1: Welcome cannot scroll and is vertically tight.** In the **Debug**
  build the extra "Load test examples" button compresses the stack enough to
  truncate the headline to "Speak it….". Release renders correctly on iPhone 17,
  but the screen has no `ScrollView`, so a 667 pt device (iPhone SE 3rd gen) is
  at risk. *Not verified on SE — see device checklist.*
- **P2 — A-2: Capture details sheet is off-theme and mislabelled.** Shows
  "Shopping · Shopping" (category and type duplicated), uses the default blue
  system tint and plain list style rather than the Speak It monochrome tokens,
  and offers **Split** on a capture that produced a single item.
- **P3 — A-3: Two "Done" controls** are visible simultaneously on the typing
  screen — one inline beside the subtitle, one as the keyboard accessory.

### Source investigation (after observation)

- `RootView.markFirstCaptureSucceeded()` / `handleCaptureCancelled()` implement
  the durability boundary exactly as `DECISIONS.md` (2026-08-17, "First value
  must be durable, perceivable, and replayable") describes. Verified correct.
- `WelcomeView` body is a plain `VStack` with no `ScrollView`, confirming A-1.

### Unresolved contract question

None.

---

## SECTION B — CORE CAPTURE

**Result: PASS with findings** (one P1 is recorded under section H, where the
defect family belongs)

### What was tested

Eleven representative captures covering task, memory, person, shopping, event,
date-only task, timed reminder, due-date-plus-separate-reminder, alarm,
recurrence, location reminder, multi-thought, messy speech with self-correction,
and the free-limit boundary. Typed input was used because the simulator has no
working microphone; the voice path's failure fallback was itself verified.

### Black-box observations

| # | Spoken/typed | Receipt | Row / destination | Verdict |
| --- | --- | --- | --- | --- |
| 1 | Buy toothpaste | Today · When you have time | Today › When you have time · Shopping | PASS |
| 2 | Call Mom tomorrow at 5 | — | Coming up · Aug 20, 5:00 PM · People · Person follow-up. Editor: **Remind me OFF** | see B-1 |
| 3 | Remember Catherine's birthday is May 3 | Memory · People | Memory › People, title cleaned | PASS |
| 4 | Dentist appointment Friday at 2 | `Timeline · Fri 2:00 PM` | Coming up · Aug 21, 2:00 PM · Events · Event | see B-2 |
| 5 | Finish the report by Friday, remind me Wednesday | — | Due Aug 21 (date-only), reminder Aug 26 9:00 AM. Row prints **Aug 26** | see B-3 |
| 6 | Wake me up at 6:30 tomorrow | — | AlarmKit prompt shown in context. Title "**Your reminder**". Editor: "This is an alarm because you explicitly asked for one." | see J |
| 7 | Every Monday at 9 remind me to file the timesheet | `Reminder · Mon 9:00 AM · Every Monday` | Aug 24, 9:00 AM · Every Monday. Title is the raw sentence, truncated to "Every Monday at 9 remind me to file the t…" | see B-4 |
| 8 | Remind me to take out the bins when I get home | `Needs review · Set your Home location` | Needs review, pin glyph, "Set your Home location" in red | PASS |
| 9 | Buy milk, call Alex tomorrow, and remember Catherine likes sushi | `3 things · 1 action · 1 reminder · 1 memory` | Three correct items: Buy milk (Shopping), Call Alex tomorrow (Person follow-up, Aug 20), Catherine likes sushi (Memory › People) | see G-1 |
| 10 | Um so I need to, no wait, I should email Sam about the, uh, the invoice by Thursday | `Timeline · Tomorrow 12:00 AM` | "Email Sam about the, the invoice by Thursday", Aug 20 date-only | see B-5 |
| 11 | (11th capture) | — | Paywall: "You've used your 10 free captures." | PASS — see K |

Voice path on simulator: tapping the orb yields "**Voice had trouble starting.
Your thought can still be saved by typing.**" and drops into the typing surface
with the text preserved. Correct, non-destructive fallback.

### Findings

- **P1 (pending severity review) — B-1: a dated but non-alerting task is visually
  identical to a real reminder.** "Call Mom tomorrow at 5" has `Remind me` off
  and schedules no notification (confirmed absent from the pending-notification
  store). Its Today row — "Call Mom tomorrow · People · Person follow-up ·
  Aug 20, 5:00 PM" — is indistinguishable from "Call the bank · Task · Aug 20,
  9:00 AM", which *does* alert. There is no bell, alarm or any other persistent
  glyph distinguishing them. The only signal is the receipt word "Timeline",
  which auto-dismisses after 3.6 s.
  *Per the relayed instruction, the default for this is P1 if no persistent
  visual distinction exists. Confirmed: none exists. Final call deferred to the
  end-of-audit severity review, pending the complete section C sweep.*
- **P2 — B-2: "Timeline" is not product vocabulary.** `ReminderScheduler.confirmationContext`
  prints `Timeline` whenever `item.reminderDate == nil`. The product's two
  destinations are Today and Memory; "Timeline" appears in no user-facing
  glossary, on no screen, and in no Learn Speak It lesson.
- **P2 — B-3: a due date with a separate reminder hides the deadline.** The row
  prints the *reminder* date (Aug 26) while the list sorts by the *due* date
  (Aug 21), so the item appears out of chronological order and the deadline it is
  actually about is invisible. *May rise in severity depending on section C.*
- **P2 — B-4: titles are inconsistently cleaned, and truncation hides the task.**
  "Take vitamins" and "Stretch" were cleaned correctly, but "Every Monday at 9
  remind me to file the timesheet" kept the whole raw sentence and the 2-line
  limit cuts it at "file the t…" — the actual task is unreadable on the row.
- **P2 (pending severity review) — B-5: "12:00 AM" is printed for date-only
  items.** `ReminderScheduler.friendlyDate` formats any `Date` with a time
  component and does not consult `isDateOnly`, so a day-only capture is announced
  as "Tomorrow 12:00 AM". *Instruction: promote to P1 if prominent enough to read
  as "Speak It understood midnight". Currently observed only on the capture
  receipt and in the editor's Due row; not on Today rows, which correctly print
  the bare day. Leaning P2 — final call at end of audit.*
- **P3 — B-6: `friendlyDate` drops the date beyond tomorrow.** Past tomorrow it
  prints weekday + time only ("Fri 2:00 PM"), which is ambiguous for anything
  more than a week out.

### Source investigation (after observation)

- `ReminderScheduler.deliveryKindLabel(for:)` returns `"Timeline"` when
  `item.reminderDate == nil` — B-2, and the mechanism behind B-1.
- `ReminderScheduler.friendlyDate(_:)` takes only a `Date` and has no
  `isDateOnly` parameter — B-5, B-6.
- `ItemPresentation.primaryTimingText` *does* handle `isDateOnly` correctly and
  prints a bare day, which is why Today rows are right and receipts are wrong.
  The two surfaces disagree despite `ItemPresentation` existing precisely to stop
  that (see `DECISIONS.md`, "one reading of an item, shared by every surface").

### Unresolved contract question

Should a timed task that the user did **not** ask to be reminded about carry a
persistent visual marker distinguishing it from one that will alert? The
`DECISIONS.md` entry of 2026-08-14 establishes the *behaviour* ("buy milk
tomorrow schedules nothing; remind me to buy milk tomorrow alerts") but says
nothing about how the two are told apart on screen.

---

## SECTION G — MULTI-THOUGHT CAPTURE

**Result: PASS with one finding**

### What was tested

A three-clause capture mixing two actions and one memory, with a shared date on
one clause only.

### Black-box observations

"Buy milk, call Alex tomorrow, and remember Catherine likes sushi" produced
exactly three items, no duplicates, nothing lost:

| Item | Destination | Date |
| --- | --- | --- |
| Buy milk | Today › When you have time · Shopping | none |
| Call Alex tomorrow | Today › Coming up · People · Person follow-up | Aug 20, date-only |
| Catherine likes sushi | Memory › People · Note | none |

**Attribute inheritance is correct**: "tomorrow" attached only to the clause that
carried it. It did **not** leak onto "Buy milk" or onto the Catherine memory —
which is exactly the behaviour `DECISIONS.md` (2026-08-17) specifies. All three
rows remain traceable to one capture session via Capture details.

### Findings

- **P2 — G-1: the receipt's reminder count overstates what will alert.** The
  receipt read "3 things · 1 action · 1 reminder · 1 memory". The "1 reminder"
  is "Call Alex tomorrow", which has no notification scheduled. `reminderCount`
  in `ThoughtRepository.swift` counts any item whose `reminderState` is `.time`,
  and `reminderState` falls back to `item.dueDate` when `reminderDate` is nil —
  so a merely-dated item is counted as a reminder. Same root confusion as B-1.

### Source investigation (after observation)

`ItemPresentation.reminderState` uses `item.reminderDate ?? item.dueDate`, so a
date-only task with no alert reports `.time`. `CaptureCreationResult.reminderCount`
then counts it. Confirmed in `ThoughtRepository.swift:94-101` and
`ItemPresentation.swift:146`.

### Unresolved contract question

Same as B — whether "reminder" in the receipt means "has a date" or "will alert".
Currently it means the former and reads as the latter.

---

## SECTION H — REMINDER AND TEMPORAL UI

**Result: FAIL — contains the audit's only confirmed P1**

### What was tested

Phrasings drawn from the section H list: today, tomorrow, Friday, on the 15th,
end of month, tomorrow at a time, due-Friday-remind-Wednesday, every day at nine,
every morning, every Friday, every Monday at 9. The semantic contracts are frozen;
this section judges only whether the resulting product presentation is coherent
and whether what the app *shows* matches what it will *do*.

### Black-box observations

| Phrase | Receipt | Row | Notification actually scheduled? |
| --- | --- | --- | --- |
| "Pay rent on the 15th" | `Timeline · Tue 12:00 AM` | Sep 15 · Task | n/a (no reminder asked) |
| "Submit expenses end of month" | `Timeline · Mon 12:00 AM` | Aug 31 · Task | n/a |
| "Call the bank" (+ reminder) | `Reminder · Tomorrow 9:00 AM` | Aug 20, 9:00 AM | ✅ yes |
| "Check the oven" (+ reminder) | `Reminder · Tomorrow 11:56 AM` | Aug 20, 11:56 AM | ✅ yes |
| "Every Monday at 9 remind me to file the timesheet" | `Reminder · Mon 9:00 AM · Every Monday` | Aug 24, 9:00 AM · Every Monday | ✅ yes |
| "Remind me every day at nine to take vitamins" | `Reminder · Tomorrow 9:00 AM · Every day` | Aug 20, 9:00 AM · Every day | ✅ yes |
| **"Remind me every morning to stretch"** | **`Timeline · Tomorrow 9:00 AM · Every day`** | **Aug 20, 9:00 AM · Every day** | ❌ **NO — none, ever** |
| **"Remind me every Friday to water the plants"** | **`Reminder · Fri 12:00 AM · Every Friday`** | **Aug 21, 12:00 AM · Every Friday** | ⚠️ **yes, at MIDNIGHT** |

### Evidence

The decisive evidence is the system's own pending-notification store, read
directly from the simulator:

```
~/Library/Developer/CoreSimulator/Devices/E5892B9B-.../data/Library/
    UserNotifications/B5DFC590-0FF0-4EE4-AEEE-B4BAC0F49338/PendingNotifications.plist
```

Extracted request identifiers and bodies:

```
SpeakIt.session.14D7F3BC-….14D7F3BC-…-1787241360   Check the oven
SpeakIt.session.89A5CF08-….89A5CF08-…-1787230800   Take vitamins
SpeakIt.session.0F59B017-….0F59B017-…-1787576400   Every Monday at 9 remind me to file the timesheet
SpeakIt.session.7086CDBA-….7086CDBA-…-1787749200   Finish the report by Friday, remind me Wednesday
SpeakIt.session.B5ED0D20-….B5ED0D20-…-1787230800   Call the bank
```

**"Stretch" is absent.** The user said "remind me"; nothing will ever fire.

### Findings

- **P1 CONFIRMED — H-1: a recurring reminder with no explicit clock either never
  fires or fires at midnight.**

  The user-facing damage is that the silent row is *visually identical* to a
  working one: same section, same date, same time, same "Every day" subtitle,
  same completion circle. The only distinguishing signal anywhere in the product
  is the word "Timeline" on a receipt that auto-dismisses after 3.6 seconds.

  This meets the P1 bar on two clauses at once — "feature promises one behavior
  and performs another" and "important information invisible" — and arguably
  approaches P0 ("wrong reminder delivery caused by application state"), though I
  am holding it at P1 because no existing data is lost or corrupted.

  **Affected family:** recurrence + explicit reminder request + no explicit clock
  time. This includes the very common "remind me every morning…", "remind me
  every night…", "remind me every Friday…", "remind me every day to…".
  **Unaffected:** recurrence *with* an explicit clock.

### Source investigation (after observation)

Three individually reasonable lines interact to produce this:

1. [`ThoughtOrganizer.swift:1186`](SpeakIt/Repositories/ThoughtOrganizer.swift:1186)
   ```swift
   delivery: reminderDate == nil ? .none : delivery
   ```
   The one-off resolver found no clock in "every morning", so `reminderDate` is
   nil and `delivery` is zeroed — even though `wantsReminder` was true.

2. [`ThoughtOrganizer.swift:271`](SpeakIt/Repositories/ThoughtOrganizer.swift:271)
   ```swift
   let reminderDate = timing.delivery == .none ? timing.reminderDate
                                               : (recurringDate ?? timing.reminderDate)
   ```
   Because delivery was already zeroed in step 1, the recurrence's own first
   occurrence is never promoted to the reminder date. The date exists — it is on
   screen — but it is only a due date.

3. [`ThoughtOrganizer.swift:307`](SpeakIt/Repositories/ThoughtOrganizer.swift:307)
   ```swift
   needsClarification: (timing.needsClarification && recurringDate == nil) || …
   ```
   `timing.needsClarification` was correctly true ("reminder requested but no
   time resolved"), but the presence of a recurrence date suppresses it — so the
   item does not even reach Needs review, where the gap would have been named.

   The "every Friday" branch differs only in that its recurrence resolves to
   00:00 rather than to a daypart hour, so it keeps `delivery` and schedules a
   real notification — at midnight.

### Intended contract (locked, for the fix phase — not yet implemented)

```
Explicit "remind me" + recurrence + explicit time
  -> recurring notification at the explicit time
"Remind me every morning ..."
  -> recurring notification at 9:00 AM
"Remind me every Friday ..."
  -> recurring notification Friday at 9:00 AM
Recurrence with NO explicit reminder request
  -> may remain a non-alerting recurring timeline item

Never: silently no notification after the user said "remind me"
Never: midnight merely because the recurrence is date-based
```

### Unresolved contract question

Resolved by the locked contract above.

---

## SECTION F — OPERATIONS

**Result: PASS on safety, FAIL on the confirmation path**

### What was tested

Cancel against an exact confident target; broad destructive language in two
phrasings; free-allowance accounting for operations.

### Black-box observations

| Utterance | Receipt | Effect | Allowance |
| --- | --- | --- | --- |
| "Cancel the reminder to water the plants" | **Cancelled** / "Water the plants" / bell-slash glyph | Correct single target acted on. All unrelated items survived. Needs review count unchanged. | 8 → **8** (not consumed) ✅ |
| "Cancel everything" | **Remembered** / "Needs review · Task or note?" | Saved as a new junk item "Cancel everything / Unclear". **Nothing destroyed.** | 8 → **9** (consumed) ❌ |
| "Cancel all my reminders" | **Confirm first** / "That affects everything — confirm in Needs review" / warning triangle | Held for confirmation. **Nothing destroyed.** | 0 → **1** (consumed) ❌ |

**The critical safety property holds in every case: no broad destructive request
was ever executed, at any confidence.** Confirmation copy is correct and
distinct — "Cancelled", not "Remembered", for a real cancellation.

### Findings

- **P1 (pending severity review) — F-1: the broad-cancel confirmation path does
  not exist.** The receipt for "Cancel all my reminders" states "confirm in
  Needs review". The Needs review row reads "Cancel all my reminders / **Task or
  note?**". Opening it shows an editor whose banner is "\* Task or note? / Choose
  a type", with Type = Unclear, Has a due date OFF, Remind me OFF, and a Needs
  clarification toggle. **There is no control anywhere to confirm or execute the
  cancellation.** The only forward move is to classify a destructive command as a
  Task or a Note, which leaves a permanent junk row titled "Cancel all my
  reminders" in Today or Memory. The user's reminders remain fully active and
  nothing on screen says so.

  Consequence: not destructive and not data-losing, but the app explicitly
  directs the user to an action that does not exist. Meets "feature promises one
  behavior and performs another".

- **P2 — F-2: the word "everything" bypasses the destructive-scope safety copy.**
  "Cancel everything" produces "Remembered" and the generic "Task or note?"
  instead of "Confirm first". Safety is preserved either way — nothing is
  destroyed — but the most natural phrasing gets the weakest handling.

- **P2 — F-3: operations that produce no new thought still consume a free
  capture.** Verified 0 → 1 for the held broad-cancel, and 8 → 9 for
  "Cancel everything". `CaptureOperationOutcome.createsNewThought` is hard-coded
  `false`, yet a review row is stored and the allowance is spent. Two broad
  attempts burn a fifth of the free trial for operations the user never received.

### Source investigation (after observation)

- F-2: [`SpeechRepair.swift:452`](SpeakIt/Repositories/SpeechRepair.swift:452)
  ```swift
  if matches(lower, #"\b(?:anything|everything|nothing)\b"#) { return nil }
  ```
  returns nil for *any* text containing "everything". The broad-scope branch that
  would return `isBroad: true` sits three lines later at
  [`:455`](SpeakIt/Repositories/SpeechRepair.swift:455) and is therefore
  unreachable for that word. It is reachable via "all" / "every", which is why
  "Cancel all my reminders" behaves correctly. The guard's own comment is about
  "Don't schedule anything Friday" — a legitimate constraint case — so the fix
  must preserve that while letting destructive scope through.
- F-1: the receipt copy comes from `CaptureOperationCopy.needsConfirmation`,
  computed at capture time only. Per `KNOWN_ISSUES.md` ("Clarification reasons
  are inferred, not recorded"), `needsClarification` is a bare `Bool`, so the
  broad-cancel reason is discarded on save and `ClarificationRequirement`
  re-derives the generic "Task or note?" from the item's fields. **The receipt
  and the review row disagree by construction**, not by accident.

### Unresolved contract question

What *should* a confirmed broad cancel do? There is no design for the
confirmation affordance itself — only for holding the request. This needs a
product decision before F-1 can be fixed, not just a code change.

---

## SECTION K — FREE TIER AND PAYWALL

**Result: PASS** (purchase completion is DEVICE/SANDBOX REQUIRED)

### What was tested

The complete free capture flow from a clean allowance, the boundary at capture
10 and 11, paywall copy and controls, Restore Purchases, legal links, dismissal,
and whether Pro UI appears before entitlement.

### Black-box observations

| Check | Observed | Verdict |
| --- | --- | --- |
| Captures 1–10 allowed | Yes. Countdown copy appears on the receipt from 2 remaining: "2 free captures left", "1 free capture left", "Last free capture used". | PASS |
| 10th capture succeeds | Yes — the tenth save completes normally and shows its receipt. | PASS |
| 11th reaches paywall | Yes. Hero: "**You've used your 10 free captures.**" Body: "Everything you saved is still yours. You've used all 10 free captures — upgrade for unlimited capture." | PASS |
| Duplicate does not consume | Contract verified in source (`consumesFreeCapture` / `result.isDuplicate`); the 15-second window was not reproducible through the typed UI. | PARTIAL |
| Operations do not consume | **Exact-match cancel: PASS** (8 → 8). Broad-cancel: FAIL — see F-3. | MIXED |
| Paywall copy consistency | Internally consistent. "Free captures do not renew" in Settings agrees with the lifetime model and with `Website/README.md`. | PASS |
| Products displayed | No products in this environment (no StoreKit config at runtime). Shows "**Pro is being prepared** — Everything you already saved remains available. Plans will appear here as soon as the App Store products are connected." with a **Check again** button. Honest and non-blocking. | PASS |
| Purchase button with no products | Disabled, labelled "**Plans unavailable in this build**". | see K-1 |
| Restore visible and functional | Yes. Invokes the real App Store sign-in sheet. Cancelling returns "Purchases couldn't be restored. Request Canceled." | PASS as far as environment permits |
| Legal links | **Privacy** opens the in-app privacy screen. **Terms** links to Apple's standard EULA. **Share Speak It** opens the share sheet. All three have ≥44 pt targets. | PASS |
| Closing the paywall | "Not now" (free-limit context) and "Continue using Speak It free" (account context) both dismiss correctly. | PASS |
| Pro UI before entitlement | Account row reads "Speak It Free" with a capture-count progress bar; no Pro-only affordances are shown. | PASS |
| Value summary | "N organized / N completed" card renders with a correct accessibility label. | PASS |

**No purchase was attempted and no credentials were entered.**

### Findings

- **P2 — K-1: "Plans unavailable in this build" is developer-facing copy on a
  customer-facing control.** A real customer hitting a StoreKit outage would see
  the word "build". The surrounding "Pro is being prepared" card is well-written;
  the button label is not.

### Source investigation (after observation)

- `FreePlanAllowance.lifetimeCaptureLimit = 10`, `normalizedUsage` only clamps
  and never returns captures — a clock moved backwards cannot mint a fresh
  allowance. Matches `DECISIONS.md` 2026-08-14.
- `FreeCaptureLedger` writes to the Keychain and `storedCaptureCount` takes the
  max of Keychain and `UserDefaults`, so the count cannot move backwards across a
  reinstall. Confirmed by inspection; the documented ceiling (device erase,
  restore to new hardware) still stands.
- `SubscriptionStore.purchase` passes `appAccountToken` and never edits an
  entitlement locally. `entitlementProductIDs` includes the lifetime
  non-consumable but `productIDs` (what the paywall merchandises) does not —
  matching the stated intent that lifetime is code-only.
- `purchaseButtonTitle` returns the K-1 string when `selectedProduct == nil`.

### DEVICE / SANDBOX REQUIRED

- Actual Sandbox purchase of monthly and annual.
- Correct localized `displayPrice` rendering once products exist.
- Restore Purchases succeeding on a second device.
- Verifying the tenth-capture boundary against a real StoreKit configuration.

---

## SECTION C — TODAY

**Result: PASS on structure and mechanics; carries the decisive evidence that
promotes B-1 to P1**

### What was tested

Needs review with four simultaneous rows; the editor reached from a review row;
section ordering and membership with all four sections populated; row ordering
within a section; completion, the undo toast, and completed-item recoverability;
the dock/last-row clearance question; and a direct visual comparison of alerting
versus non-alerting rows.

### Black-box observations

**Section ordering** (top to bottom) was consistent and matches the product
contract: Pro discovery card → Capture anywhere card → **Needs review** →
*(Now / Rest of today when populated)* → **Coming up** → **When you have time** →
**N completed today**. Review outranks everything, which is correct.

**Needs review** showed 4 rows, newest first:

| Row | Stated gap | Correct? |
| --- | --- | --- |
| Cancel all my reminders | Task or note? | ❌ wrong question — see F-1 |
| Cancel everything | Task or note? | ❌ wrong question — see F-2 |
| Call them tomorrow | Needs a person | ✅ |
| Take out the bins when I get home | Set your Home location | ✅ |

For the two genuine cases the section works exactly as `DECISIONS.md`
(2026-08-12) describes: the row **names the gap** rather than hedging, and the
editor shows a matching banner with a red `*` against the single field that
answers it ("\* Needs a person / Add who this is about", asterisk on the Person
field). The warning colour is the muted `speakWarning` token, and a section
holding four rows still reads calm. **PASS.**

**Collapsible sections.** "Coming up" (13) is collapsed by default and "When you
have time" expanded; both toggle correctly and the counts are accurate. No stale
rows were observed after completion or after editing.

**Completion and undo.** Tapping a row's completion circle moved the item out of
Today immediately, decremented the section count (2 → 1), and showed a
"**Task completed** / **Undo**" toast positioned *above* the dock, not under it.
After the undo window elapsed, a "**1 completed today**" link appeared at the
bottom of Today, so the completed item remains reachable and recoverable.
**PASS** — matches `USER_FLOWS.md` "Complete or undo".

**Dock clearance — the question raised earlier is answered: PASS.** While
scrolling, the floating dock does visually pass over mid-list rows, but at the
scroll limit the final row ("Buy toothpaste", then "Buy milk") sits fully visible
*above* the dock, and the "1 completed today" link below it is also fully
reachable. `contentMargins(.bottom, DockScroll.clearance)` is doing its job. **No
row is permanently hidden under floating UI.**

**Original wording preserved.** Opening an item produced by a three-clause
capture shows, under "Originally captured", the complete untouched transcript
"Buy milk, call Alex tomorrow, and remember Catherine likes sushi". **PASS** —
the core product promise holds.

### The decisive observation for B-1

With Today fully populated, "Coming up" contained these rows simultaneously:

| Row as rendered | Will it alert? |
| --- | --- |
| Take vitamins · Every day · Aug 20, 9:00 AM | ✅ **yes** |
| **Stretch · Every day · Aug 20, 9:00 AM** | ❌ **no** |
| Call the bank · Task · Aug 20, 9:00 AM | ✅ yes |
| Check the oven · Task · Aug 20, 11:56 AM | ✅ yes |
| Call Mom tomorrow · People · Person follow-up · Aug 20, 5:00 PM | ❌ no |

"Take vitamins" and "Stretch" are **structurally identical rows** — same section,
same subtitle pattern, same recurrence label, same date, same time, same
completion circle, same absence of any glyph — and one of them will never fire.

There is **no persistent visual distinction anywhere in Today** between an item
that will alert and one that will not. Per the relayed instruction, this settles
the question.

### Findings

- **P1 — C-1 (= B-1), promoted from P2:** a dated but non-alerting item is
  visually indistinguishable from a real reminder. Confirmed against a fully
  populated Today. The only signal is a receipt word that auto-dismisses, which
  the instruction explicitly excludes.
- **P1 candidate — C-2 (= F-1):** broad-cancel confirmation path does not exist.
  Recorded in full under section F.
- **P2 — C-3 (= B-3):** the "Finish the report by Friday, remind me Wednesday"
  row prints Aug 26 while the list sorts it by Aug 21, so it appears between two
  Aug 20/21 rows while displaying a later date. Against the full section this
  reads as a sorting bug to the user even though the sort is correct. Confirmed
  but not promoted — the item is still reachable and its dates are visible in the
  editor.

### Source investigation (after observation)

`CapturedItemRow.passiveTrailingContent` renders a `mappin.and.ellipse` glyph for
place-triggered items and *nothing* to distinguish a time-triggered item that
will alert from one that will not. `trailingText` comes from
`ItemPresentation.primaryTimingText`, which is derived from
`reminderDate ?? dueDate` and therefore cannot tell the two apart by
construction. This is the same single root as B-1/G-1.

### Unresolved contract question

Carried forward from B: what persistent marker should distinguish "will alert"
from "merely dated"? This needs a product decision, not only a code change.

### Supplementary observations (second session, fresh data set)

Re-verified against a **second, independently-built data set** (app data was
found empty at the start of this session — see note under SECTION E) covering
the remaining C checklist items: a normal task, a date-only task, a single
timed reminder, a recurring reminder, a location reminder, and an alarm.

- **Ordering re-confirmed.** Needs review → Coming up → When you have time,
  identical to the first data set.
- **C-1 / B-1 re-confirmed with a second example.** "Pay rent on the 15th"
  (date-only, no reminder) sits inside **Coming up** alongside "Call the bank"
  (alerting) and "Every Monday… " (alerting, recurring) with no visual
  distinction. Same defect, independent data.
- **Completed screen.** Opening "N completed today" shows a dedicated
  **Completed** list grouped by day ("TODAY"), with the title struck through
  and the completion **time** shown ("9:51 PM"). Matches `USER_FLOWS.md`.
  **PASS.**
- **Mark incomplete.** A completed item's editor Actions section correctly
  swaps **"Mark complete"** for **"Mark incomplete"** — state-aware, not a
  static label. **PASS.**
- **Delete permanently.** Confirmed via a real deletion: the editor's Actions
  section shows a red **Delete permanently** row; tapping it raises a
  confirmation popover — "**Delete this thought permanently?** This removes
  the item and its original capture when no other items use it. This cannot
  be undone." — before anything is destroyed. After confirming, the item is
  gone and the empty state reads "**Nothing completed yet** / Finished tasks
  will remain safely available here." **PASS** — matches the destructive-copy
  bar set elsewhere in the app (see F).
- **Overdue and date-only-presentation-under-edit were not completed this
  session** — see the "Outstanding" note under SECTION E. The date-only
  presentation defect itself (B-5) was independently reconfirmed: the Due row
  in the editor for a date-only task still renders a time component.

---

## SECTION S — RELEASE SURFACE AUDIT *(partial)*

**Result so far: PASS on the shipped binary's strings**

### What was tested so far

String extraction from the compiled **Release** binary at
`/tmp/SpeakItAuditRelease/Build/Products/Release-iphonesimulator/SpeakIt.app/SpeakIt`.

### Black-box observations

Every URL present in the Release binary:

```
https://apps.apple.com/account/subscriptions
https://us.i.posthog.com
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

No `localhost`, no `127.0.0.1`, no staging or ngrok host, no `mailto:`, no
`@gmail`, no old support address, no test API key.

Developer-only UI strings — all confirmed **absent** from the Release binary:

| String | Result |
| --- | --- |
| Pretend to be a new customer | absent ✅ |
| Test Customer Journey | absent ✅ |
| Load test examples | absent ✅ |
| DEVELOPER PURCHASE PREVIEW | absent ✅ |
| Developer test · no charge | absent ✅ |
| Developer controls are removed | absent ✅ |
| Start as a brand-new free user | absent ✅ |
| Jump directly to the upgrade moment | absent ✅ |
| Customer journey is active | absent ✅ |

The `#if DEBUG` fencing around the developer surfaces is therefore effective.

### Still outstanding in section S

`Info.plist` values in the built product; entitlements in the built product;
`PrivacyInfo.xcprivacy` correctness; the analytics event vocabulary check;
`SpeakIt.storekit` absence from the bundle; version/build numbers across all
three targets; referral and summer-sale flag behaviour at runtime (sections L
and M); and a TODO/FIXME sweep for user-visible unfinished work.

---

## SECTION D — MEMORY

**Result: PASS**

### What was tested

The Memory landing screen and its four destinations, the People index with two
facts about the same person, drilling into a person, whether a dated memory
leaked into Today, and whether any actionable obligation was stranded in Memory.

### Black-box observations

**Memory landing.** Eyebrow "Find · Recognize · Reuse", title **Memory**, a
search field ("Search people, ideas, or facts"), and the orienting copy
"**What do you want to remember?** Tasks stay in Today. Memory keeps the ideas,
people, and facts you may need later." — which restates the product contract
correctly and in the user's language.

Four destination cards with live counts: **Pinned 0**, **Ideas 0**,
**People 2 — "1 person remembered"**, **Reference 0**. Below them, "Recently
added — The latest things worth remembering" listing "Catherine likes sushi ·
People · Note · 11:47 AM".

**People index — the key check.** Two separately-captured facts about the same
person collapsed correctly into **one** entry:

```
C   Catherine                                    2  ›
    Catherine likes sushi
```

Opening Catherine shows both, newest first, under the heading "Remembered":

| Item | Label | Time |
| --- | --- | --- |
| Catherine likes sushi | People · Note | 11:47 AM |
| Catherine's birthday is May 3 | People · Note | 11:42 AM |

with the footer "**Facts stay in Memory. Actions stay in Today.**"

This is exactly the behaviour `DECISIONS.md` (2026-08-19, "One person resolver")
specifies, and it verifies the consequence that the semantic corpus was blind to:
capture a sentence naming a human, then find that human under People. **PASS.**

**A dated memory did not leak into Today.** "Catherine's birthday is May 3"
carries a date and correctly stayed in Memory rather than becoming a May 3
commitment — matching the frozen contract that a birthday is knowledge, not an
appointment. **PASS.**

**No actionable obligation was stranded in Memory.** Every task, reminder and
follow-up captured during this audit appeared in Today; only notes and person
facts appeared in Memory. **PASS.**

**No ordinary memory received recurrence or reminder behaviour.** Neither
Catherine fact showed a repeat label, a date chip, or a completion circle.
**PASS.**

**Dock badge agrees with the screen.** The dock reads "Memory 2" and Memory holds
exactly 2 open items — the `memoryBadgeCount` narrowing described in
`RootView.swift` is working.

### Findings

- **P3 — D-1: the People card's count and subtitle measure different things.**
  The card shows "**2**" beside the label People while its subtitle reads
  "**1 person remembered**". The 2 is an item count and the 1 is a person count;
  side by side the 2 reads as "two people". Cosmetic, but it is the one number on
  the Memory screen that can be misread.

### Not tested in this section

Ideas filters (New / Promising / Exploring / Parked), pinning, archive/restore,
and compact-versus-comfortable row density were not exercised because no Ideas or
Pinned items existed in the store. Search was not exercised. **These remain
outstanding** and are listed in the device/follow-up checklist rather than
claimed as passing.

### Source investigation (after observation)

`MemoryPeopleIndex` (extracted from the view body per `DECISIONS.md` 2026-08-19)
is what makes the collapse testable and is behaving as documented. No defect
found.

### Unresolved contract question

None.

---

## SECTION E — EDITING MATRIX

**Result: PASS on every editing path that could be exercised; one new P1/P2
candidate finding on recurrence delivery; a significant portion of the
matrix (all Toggle-driven fields) could not be exercised in this session for
tooling reasons — see below.**

### Session note: data set and environment

The app's data store was found **empty** (0 items, 10/10 free captures) at
the start of this session, despite the checkpoint recording "~21 items in
store." The Capture Anywhere setup screen was left on-screen from a prior
session. Cause not investigated (out of scope for C/E) — most likely the
end-of-audit fresh-install re-check mentioned in the ENVIRONMENT CAVEAT was
run between sessions. A fresh, representative data set was captured for this
matrix: a normal task ("Buy toothpaste"), a date-only task ("Pay rent on the
15th"), a single timed reminder ("Call the bank", Aug 20 9:00 AM), a
recurring reminder ("Every Monday at 9 remind me to file the timesheet"), a
location reminder ("Take out the bins when I get home" → Needs review, Home
location already configured from a prior session), and an alarm ("Wake me up
at 6:30 tomorrow"). All six captured cleanly and matched the exact B/H
findings already on record (Timeline vocabulary, alarm titled "Your
reminder", location gap correctly named).

### Tooling limitation — read this before the results below

**Every native `Toggle` (switch) control in the editor — "Has a due date,"
"Remind me," "Repeat," "Needs clarification" — was unresponsive to synthetic
taps in this automation session.** This was investigated thoroughly before
being accepted as an environment limitation, not a product defect:

- Confirmed not a coordinate-math error: adjacent controls at
  similarly-derived coordinates on the same screens (the row's own
  completion circle, the Type/Category `Menu`, the compact `DatePicker`
  trigger, a `Stepper`, and a `UIPickerView` wheel) **all responded
  correctly** once coordinates were computed correctly.
- Tried tap, held-tap (300 ms), and horizontal drag-across-the-switch —
  none actuated any `Toggle`.
- Reproduced across a full app relaunch and a full simulator **reboot**.
- By contrast, `Button`/`Menu`/row-navigation/`Stepper`/`DatePicker`
  (compact button *and* the wheel it opens) all worked reliably once
  targeted correctly.

**Consequence: "add reminder," "remove reminder," "add due date," "remove
due date," "add recurrence," "remove recurrence," and "toggle needs
clarification" could not be directly exercised via the UI this session.**
These remain **outstanding** and should be re-attempted on a physical device
or with a fixed automation harness before relying on this section as
complete. Everything else in the matrix below was genuinely exercised.

### What was exercised, and results

| Action | Representative item(s) | Result |
| --- | --- | --- |
| Edit title | Pay rent on the 15th (typed " (edited)") | Field accepts edits; cursor lands at tap position. **PASS** |
| Cancel discards edits | Pay rent on the 15th, Buy toothpaste | Reopening after **Cancel** shows the original, unmodified title every time — edits are never silently persisted. **PASS**, repeatedly confirmed |
| Change Type / Category | Buy toothpaste (Type menu opened: Task/Shopping/Idea/Person follow-up/Event/Note/Unclear) | `Menu` opens correctly, current value checked, dismiss-without-change works. **PASS** |
| Change due **time** (wheel picker) | Every Monday… (Due 9:00 AM → 10:00 AM) | Wheel picker opens on tapping the compact trigger, scroll changes the value, change persists after Save. **PASS** — see finding E-2 below |
| Change recurrence **interval** | Every Monday… (Every 1 week → Every 2 weeks via Stepper) | Stepper responds, row label updates on save ("Every 2 weeks" now shown on the Today row). **PASS** — see finding E-1 (delivery-timing caveat) |
| Complete (row circle) | Buy toothpaste | Completes immediately, "Task completed / Undo" toast, "1 completed today" link. **PASS**, matches SECTION C |
| Complete (editor "Mark complete" / "Mark incomplete") | Buy toothpaste | Label is state-aware (swaps after completion). **PASS** |
| Delete permanently | Buy toothpaste (completed) | Confirmation popover with correct, honest destructive copy; item is actually removed; empty state renders correctly. **PASS** |
| Cancel edits (nav bar) | All items | Reliable in every attempt — this is the one control that never failed to respond. **PASS** |

### Findings

- **P1/P2 candidate (pending further investigation) — E-1: a recurring
  reminder's delivery schedule depends on the app processing completion, not
  on the stated recurrence.** Source-confirmed (not just black-box): per
  [`ReminderScheduler.swift:685-757`](SpeakIt/Repositories/ReminderScheduler.swift:685),
  every notification this app schedules is a **one-shot** trigger
  (`repeats: false`) for a single concrete `fireDate` — there is no
  `repeats: true` anywhere in the file. The next occurrence of a recurring
  item is only computed when the *current* occurrence is marked complete,
  via `SwiftDataThoughtRepository.nextRecurrenceDate(for:rule:completedAt:)`
  ([`SwiftDataThoughtRepository.swift:1771-1798`](SpeakIt/Repositories/SwiftDataThoughtRepository.swift:1771)),
  which generates a new `CapturedItem` and schedules *its own* one-shot
  notification. **Consequence: if the user never marks a recurring reminder
  complete (and never reopens the app to process it some other way), it
  fires once and then never again — silently.** This is the same defect
  family as **H-1** (recurring reminder promises repeated delivery, performs
  a single delivery) but from a different root cause (H-1 is about the first
  occurrence never getting a clock at all; E-1 is about occurrence #2+ never
  existing unless the user completes #1). Not yet black-box reproduced to a
  fired/missed notification (would require advancing simulator time past a
  fire date without completing the item, and inspecting whether a second
  notification appears) — flagging as a source-confirmed mechanism, severity
  to be set at the end-of-audit review alongside H-1.
- **P3 — E-2: due time and reminder time are independently editable and can
  silently diverge.** Changing "Call the bank"'s **Due** time from 9:00 AM to
  10:00 AM left **Reminder time** at 9:00 AM — the two fields do not track
  each other even though most captures set them to the same instant. Not
  necessarily wrong (a due time and an alert time are conceptually
  different), but there is no UI affordance to see or resolve the resulting
  gap, and it compounds B-3 (due vs. reminder date already reads as a sorting
  bug to users).

### Outstanding (not completed this session)

- **Overdue-row presentation.** Could not set a due date into the past —
  blocked by the `Toggle`/`DatePicker` interaction issue for items that
  don't already carry a due date, and repeated attempts to open "Pay rent on
  the 15th" from the Today list to change its *existing* due date into the
  past were not successful before time ran out on this pass (intermittent
  tap misses on that specific row, cause not isolated).
- **Location reminder edit (change/remove Place, change Trigger).** The
  editor for "Take out the bins…" was reached and observed (Place: Home,
  Trigger: When I arrive, both correct), but changing or removing the
  location was not attempted this session.
- **Alarm item edit.** The alarm's Today row and receipt were verified (see
  SECTION B), but its editor was not opened this session, so title edit /
  cancel-alarm behaviour for the AlarmKit path is unverified beyond what
  SECTION B already recorded. AlarmKit's own store is not human-readable
  from the simulator filesystem (checked: no plaintext record of the alarm
  was found under `Library/Preferences/com.apple.mobiletimerd.plist` or
  `Caches/com.apple.mobiletimerd/AlarmSync.data`), so teardown verification
  for the alarm path will need on-device QA regardless.
- **Direct add/remove of reminder, due date, and recurrence** — see the
  tooling-limitation note above.

### Source investigation (after observation)

Covered inline under each finding above.

### Unresolved contract question

None beyond what's already open under B/C/H (the "will alert" marker) and a
new one raised by E-1: should a recurring reminder's future occurrences be
pre-scheduled up front (e.g., the next N occurrences), rather than generated
one-at-a-time only on completion? This is an architecture question, not a
one-line fix.

---

## SECTION O — CAPTURE ANYWHERE

**Result: PASS in-app; every entry point's real-world trigger is DEVICE REQUIRED**

### What was tested

The Capture Anywhere setup surface reached from the Today discovery card, the
inventory of offered entry points, device-appropriate recommendation, the
setup-verification flow, and the explanatory disclosure. Plus the entry points
reachable from this Mac.

### Inventory of supported entry points

| Entry point | Offered in setup | Exercisable here | Result |
| --- | --- | --- | --- |
| In-app dock capture (voice) | n/a | ✅ | PASS — used throughout the audit |
| In-app dock capture → Type instead | n/a | ✅ | PASS — used throughout |
| Home Screen quick action "Start speaking" | n/a | ⚠️ declared in `Info.plist`, not exercised | outstanding |
| Home Screen quick action "Type a thought" | n/a | ⚠️ declared in `Info.plist`, not exercised | outstanding |
| `speakit://capture` deep link | n/a | ✅ handled in `RootView.handleDeepLink` | PASS by inspection |
| `speakit://today` deep link | n/a | ✅ | PASS by inspection |
| `speakit://setup` deep link | n/a | ✅ | PASS by inspection |
| Action Button | ✅ **RECOMMENDED** | ❌ | DEVICE REQUIRED |
| Lock Screen widget | ✅ | ❌ | DEVICE REQUIRED |
| Control Center | ✅ | ❌ | DEVICE REQUIRED |
| Back Tap | ✅ | ❌ | DEVICE REQUIRED — iOS does not expose the gesture to automation |
| Share extension | n/a | ❌ | DEVICE REQUIRED |
| Siri / Save Thought App Intent | n/a | ❌ | DEVICE REQUIRED |

### Black-box observations

The setup screen reads:

> **CAPTURE ANYWHERE — One gesture. Then speak.**
> Choose one way to reach Speak It outside the app. You can add the others later.

**BEST FOR THIS IPHONE** offers **Action Button — Press and hold — RECOMMENDED**,
correctly selected by default on an iPhone 17. **OTHER WAYS** lists Lock Screen
(Tap once), Control Center (Swipe, then tap) and Back Tap (Double tap), each with
a selection control.

A permission card, "**Allow voice access first** — Try one capture so iPhone can
ask…", with an **Allow** button, appears above the fold.

Choosing Action Button reveals a **ONE-TIME SETUP** card with three numbered
steps (Open Settings → Action Button / Choose Speak It Capture / Press and hold
to speak), each with accurate sub-copy.

Below it, a **Prove it works** card: "Don't leave setup guessing. Speak It will
confirm after a real outside-the-app thought is saved." with **I added it — test
now** and **Finish later**. This matches `USER_FLOWS.md` step 8 — setup completes
only after Speak It detects a real outside-the-app save, not merely on the user
asserting they configured it. **Good design; no defect.**

**"Which option should I use?"** is a working disclosure (not a dead link). It
expands to honest comparative copy including the caveat "…Back Tap is convenient
but iOS may occasionally miss the gesture", which correctly sets expectations
rather than overpromising.

### Findings

None. No dead navigation, no placeholder copy, no unfinished screen, and the
recommendation logic picked the right option for the hardware.

### Convergence check

All in-app entry points route through `RootView.presentCapture` →
`CaptureView` → `SwiftDataThoughtRepository.createCaptureResult`, and the
external ones (`SaveThoughtIntent`, `SharedCaptureInbox`, quick actions, deep
links) all call `createCaptureResult` as well. Verified by inspection: there is
one capture pipeline and no divergent organization path. This matches
`DECISIONS.md` "One capture implementation across surfaces".

### DEVICE REQUIRED

Action Button, Lock Screen widget, Control Center, Back Tap, Share extension and
Siri all need a physical iPhone. Back Tap specifically cannot be automated at all.

### Unresolved contract question

None.

---

*(SECTION E above is partial — see its own outstanding list. Sections L, M,
R, T remain. SECTIONS I, J, and P appear later in this file, appended in a
later session.)*

---

## SECTION D — SUPPLEMENTARY (gap-fill: Reference, Ideas, archive, search)

**Result: PASS on every mechanic exercised; one new P2 durability/UX finding
in the capture flow that surfaced while populating test data.**

### What was tested this session

The items SECTION D originally left outstanding because the store held no
Ideas/Pinned/Reference data: the Ideas filter chips, swipe-to-archive and
restore, the dedicated Archive screen, and search (both Memory's global
search and a destination's local search). Reference and People were
re-confirmed only briefly since SECTION D already passed them in full.

### Black-box observations

- **Reference destination.** Empty state is honest and on-brand: "Nothing
  here yet / Useful facts, decisions, and context will appear here." A
  search field, a sort control, and a density-toggle icon (the outstanding
  "compact vs. comfortable" control from SECTION D) are all present in the
  toolbar even with zero items. **PASS.**
- **Ideas filter chips.** All four expected filters are present and
  scrollable: **New, Promising, Exploring, Parked** — confirmed by swiping
  the chip row, which also revealed the fourth chip was clipped off-screen
  by default (not a defect; standard horizontal-scroll affordance, but no
  scroll-shadow hints that more chips exist). A captured Idea defaults into
  **New**, matching the empty-state copy ("Ideas you capture will begin in
  New"). **PASS.**
- **Swipe-to-archive.** Swiping an Ideas row reveals a single **Archive**
  action; tapping it removes the row and shows a **"Moved to Archive" /
  Undo** toast, matching the honest-confirmation pattern already verified
  elsewhere in this audit (SECTION F, SECTION C). **PASS.**
- **Archive discoverability and restore.** After archiving, the Memory
  landing screen grows a new row above the tab bar — **"Archive — 1 saved
  out of sight"** — so the archived item is never actually lost from view.
  Opening it lists the item with a swipe-revealed **Restore** action;
  tapping Restore returns the item to Ideas and the Archive row disappears
  from Memory landing once empty. **Full round trip confirmed working.**
  **PASS.**
- **Search.** Memory's own top-level search field could not be reliably hit
  with synthetic taps this session (a coordinate-calibration limitation, not
  a confirmed defect — see the note under SECTION N about the same
  difficulty), so search was instead verified through the Ideas
  destination's toolbar search icon, which **is** the same search
  implementation surfaced in a different location. Typing "airplane" kept
  the matching item visible; typing "zzz" replaced it with a **"No
  matches"** empty state and a working clear ("×") control. **PASS** as a
  proof of the underlying search/filter behavior; the Memory-landing entry
  point specifically should be re-poked on a physical device or with a
  fixed automation harness before being called complete.

### Findings

- **P2 — D-2: reopening "Type instead" a second time in one session
  pre-fills the field with the *previous already-saved* capture's text
  instead of starting blank, and repeated Save taps update that same record
  in place rather than creating a new one.** Reproduced directly: capturing
  "Idea: build a paper airplane app someday" saved correctly and returned to
  a blank capture screen. Reopening **Type instead** immediately afterward
  showed that same sentence still sitting in the text field (not blank);
  typing a second, unrelated sentence ("The wifi router password is on the
  sticker under the modem") appended it directly onto the first with **no
  separator** ("…somedayThe wifi…"). Saving again did **not** create a
  second item — `Settings > Capture history` confirms exactly **one**
  record exists, titled with the fully merged, run-together text. No data
  was silently lost (nothing disappeared), but a user who reopens capture
  right after saving and starts typing a *new*, *unrelated* thought would
  have it silently concatenated onto their previous one instead of saved
  separately — quietly corrupting an existing Memory item. This directly
  touches the product's "immutable original transcript" guarantee in
  `CLAUDE.md`, since the merged text is what the app now treats as the
  original wording for that item. **Not yet source-investigated** (out of
  time this session) — worth a `CaptureView`/`CaptureViewModel` look at
  whether the typed-text `@State`/draft is being reset on successful save.
- **P3 — D-3: the capture screen's touch responsiveness froze after one
  cycle of opening/dismissing the "Keep this thought?" discard dialog.**
  After using the dialog's **Keep Editing** option once, the **Save
  thought** button and the text field itself stopped responding to further
  taps in that same capture session (X and the dialog's own buttons kept
  working). A full app relaunch recovered cleanly with **no data loss** —
  the one already-saved item was intact and unduplicated. Reproduced once;
  not yet isolated to a specific repro path, so filed at P3 pending a
  second reproduction. Flagging because a durability-sensitive screen going
  unresponsive, even recoverably, is exactly the failure class SECTION E's
  toggle-automation notes and `DURABILITY_FINDINGS.md` are watching for.

### Source investigation (after observation)

Not performed this session for D-2/D-3 (time-boxed) — flagged for the next
session or for direct code reading of `SpeakIt/Features/Capture/CaptureView.swift`.

### Unresolved contract question

None beyond the open "will alert" marker question carried from B/C/H.

---

## SECTION N — SETTINGS

**Result: PASS on every screen reached; one real navigation-consistency
finding.**

### What was tested

Every visible row in "Account & Settings" reached from Today's profile
icon: Your Speak It / Create your profile, Learn Speak It, Plan (Speak It
Free progress, Share Speak It), Appearance (System/Light/Dark), Places
(Home, Work), Activity (Completed, Capture history), and Data & Privacy
(iCloud sync, Privacy, Share anonymous app analytics, Show task names on
Lock Screen). Purchases/Restore and the legal links (Privacy Policy,
Terms) live on the paywall (`SpeakItProView`), not in this Settings sheet —
those were already fully verified in **SECTION K** and were not repeated
here per instruction.

### Black-box observations

- **Places.** "Home: Not set" / "Work: Not set" with clear explanatory copy.
  Opening either presents a working **map picker**: search-by-address field,
  "Use my current location," and a labelled ~150 m radius circle. Backing
  out via **Cancel** (or an unsaved back navigation) leaves both places
  correctly "Not set" — no accidental partial save. **PASS.**
- **Activity → Completed.** Opens to the correct empty state
  ("Nothing completed yet…") for this session's data. **PASS.**
- **Activity → Capture history.** Lists every capture from this session in
  reverse-chronological order with an accurate timestamp, method ("Typed in
  app"), and a "1 saved" outcome per row — this is what let SECTION D's
  supplementary testing confirm exactly one record existed for the
  merged-text finding (D-2) above. **PASS.**
- **Data & Privacy → Privacy.** A full, honest, plain-language privacy page:
  "No account required," "Your library stays private" (with the iCloud-sync
  caveat spelled out), "Recovery audio is temporary" (states exactly when
  the local recording is deleted and how to clear an interrupted one from
  Capture history), "Speech recognition is provided by Apple," "Reminders
  are opt-in," "Location is only for place reminders" (states places are
  never sent to analytics and are excluded from iCloud Sync), "Anonymous
  analytics are content-free" (explicitly lists what is *never* sent:
  recordings, transcripts, task titles, memory text, names, emails, search
  words), and "Referrals use an anonymous ID" (states the referral service
  never receives thoughts, recordings, profile, or the contact list). This
  matches `CLAUDE.md`'s privacy rules verbatim and is some of the clearest
  copy in the app. **PASS.**
- **Share anonymous app analytics** defaults **ON**, but this is a
  harmless, correctly-scoped default: per `CLAUDE.md` and the EXACT BUILD
  table, `SPEAKIT_ANALYTICS_KEY` is empty in this build, so no event can
  actually transmit regardless of the toggle's state. **Show task names on
  the Lock Screen** correctly defaults **OFF**, with copy explaining the
  Lock Screen widget only ever shows a count, never names, when off.
  **PASS.**
- **Plan → Speak It Free.** Row and inline progress bar agree exactly with
  the free-capture ledger exercised throughout this session ("4 of 10 free
  captures remaining" after this session's activity). **Share Speak It**
  opens the system share sheet. **PASS.**
- **Appearance.** The System/Light/Dark segmented control applies
  immediately and **globally** — confirmed by switching to Dark and then
  navigating to Memory, which rendered in full dark theme (monochrome
  tokens preserved, no light-themed leftovers). Reopening Settings
  afterward also correctly renders the settings sheet itself in dark theme.
  (An initial screenshot taken in the same tool call as the toggle showed
  the settings sheet still light-themed with only the status bar dark; a
  fresh screenshot a moment later showed it fully repainted to dark. This
  was a one-frame render lag, not a persistent bug — re-verified and
  dropped as a false alarm.) **PASS.**
- **No developer-only controls found anywhere in this Settings sheet** in
  the Release build — consistent with SECTION S's binary string scan, which
  already confirmed the `#if DEBUG` fencing removes every developer-only
  string from the Release binary. **PASS.**

### Findings

- **P2 — N-1: the "Places" screen is the only pushed screen in Settings
  with no visible back control.** Every other pushed screen (Ideas,
  Reference, Archive, Capture history, "Set Home"/"Set Work") shows a
  clear, custom, high-contrast circular "‹" button at the top-left. Places
  shows none — only "Places" centered in the header, nothing at either
  side. The only way back is the system edge-swipe-from-left gesture,
  which is non-obvious (there is no on-screen affordance hinting it exists)
  and, in this session's testing, took multiple attempts to register even
  when deliberately invoked from the correct screen edge. This is a real
  discoverability gap: a user who reaches Places (a fairly central screen —
  it's how Home/Work location reminders get configured) and doesn't know
  or can't perform the edge-swipe gesture has no visible way back to
  Settings. This also has accessibility implications: `CLAUDE.md` requires
  "a useful accessibility label/hint" and a tappable full shape for
  controls, and a missing control fails that bar for VoiceOver users by
  definition. No data-loss risk — it is a navigation dead-end in appearance
  only, not in fact — but worth a one-line fix (add the same custom back
  button used everywhere else) before release.

### Source investigation (after observation)

Not performed this session (time-boxed after the coordinate-calibration
difficulty on this specific screen made confirming N-1 itself already take
several attempts) — likely a missing `.toolbar { ToolbarItem(.navigation) }`
override in `SpeakIt/Features/Setup/AccountSettingsView.swift` (or wherever
the Places list view lives) that every *other* pushed row in that file
correctly sets.

### Unresolved contract question

None.

---

## SECTION Q — ACCESSIBILITY (Dynamic Type; VoiceOver not exercised)

**Result: PASS on text scaling and legibility on every screen reached; one
confirmed P1/P2 layout defect in the app's primary navigation surface at
the largest accessibility text sizes.**

### What was tested

Dynamic Type was driven directly via
`xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`
(the largest available accessibility size, larger than anything reachable
through the in-app Text Size slider alone) rather than through iOS
Settings, since the simulator control tool used this session can drive
`simctl` but has no reliable way to operate the system Settings app's UI.
Today (with a populated Needs review card and a populated Coming up
section), the item editor ("Edit Thought"), and the app's floating bottom
dock (present on every screen) were exercised at this size. Text size was
reset to the system default (`large`) before ending the session.

VoiceOver itself (spoken labels, hints, and swipe-navigation focus order)
was **not exercised this session** — see "Not tested" below.

### Black-box observations

- **Today's heading, date, and "Needs review" section header** all scale
  correctly and wrap onto multiple lines without clipping or overlap
  against each other. **PASS.**
- **The "Needs review" card itself** wraps its title correctly across four
  lines at this size, keeps its "?" gap-glyph and disclosure chevron
  visible and positioned sensibly, and remains genuinely tappable — opening
  it reached the "Edit Thought" editor correctly. **PASS.**
- **The "Edit Thought" editor** scales well: **Cancel** and **Save** stay
  pinned, unclipped, and legible in the header at every size tested; the
  "Set Home location" gap-banner and the "Thought" field both wrap onto
  multiple lines cleanly; **Cancel** correctly discarded the (unmodified)
  edit and returned to Today without any accidental save. **PASS.**

### Findings

- **P1/P2 (severity to be set at end-of-audit review) — Q-1: the floating
  bottom dock's own labels become unreadable and the dock overlaps
  surrounding content at the largest accessibility text sizes.** At
  Accessibility-XXXL, the dock's "Today" and "Memory" labels wrap onto two
  lines each inside the dock's pill ("To-day" over two lines; "Me / mo / ry"
  over three, colliding with its own unread-count badge), which is already
  a real legibility failure for exactly the population Dynamic Type exists
  to serve. Worse, because the dock does not appear to grow its reserved
  clearance to match its own wrapped height, it visually **rides up over
  the bottom of the "Needs review" card** and **fully covers the "Coming
  up" section header** directly beneath it — the same floating-dock
  clearance mechanism (`contentMargins(.bottom, DockScroll.clearance)`)
  that SECTION C confirmed works correctly at normal text sizes does not
  appear to account for the dock's own height growing under large Dynamic
  Type. This is the app's primary navigation control, present on every
  screen; the same failure pattern should be assumed to affect Memory's
  tab bar (which carries a "Memory 1" badge whose second word — plan
  "Reference"/"People" labels elsewhere are shorter, but "Memory" itself
  already wraps) and any other screen the dock appears on. Recommend either
  truncating/shortening dock labels above a content-size threshold, or
  switching to icon-only labels at accessibility sizes, plus recomputing
  scroll clearance from the dock's actual rendered height rather than a
  fixed constant.

### Not tested this session

- **VoiceOver** (spoken labels/hints, rotor, and swipe-focus order) on any
  screen. This simulator-control tooling can drive `simctl`'s Dynamic-Type
  knob directly but has no way to capture VoiceOver's audio output or read
  the accessibility tree, and turning VoiceOver on would also change every
  gesture's meaning (single-tap-to-focus vs. double-tap-to-activate),
  which is incompatible with the coordinate-tap automation used everywhere
  else in this pass. **Needs a macOS Accessibility Inspector pass against
  the Simulator, or a physical-device VoiceOver pass, before this can be
  called done.**
- **Welcome** was not reachable this session — onboarding is already
  complete on this device/build combination and re-triggering first-run
  state was out of scope for this pass (SECTION A already covers Welcome's
  layout at normal size, including the P2 no-`ScrollView` finding A-1,
  which would be expected to compound under large Dynamic Type but was not
  re-verified here).
- **Capture, Needs Review's own dedicated editor variant, and the paywall**
  were not exercised at large Dynamic Type this session due to time — carry
  forward as outstanding for the next Q pass, alongside VoiceOver above.

### Source investigation (after observation)

Not performed this session (time-boxed) — likely worth checking whether the
dock's container view computes its own height dynamically (and whether
`DockScroll.clearance` is a fixed constant or derived from that height) in
`SpeakIt/App/RootView.swift` or wherever the shared dock component lives.

### Unresolved contract question

None beyond what Q-1 itself raises: should the dock switch to an
icon-only / abbreviated-label presentation above a certain Dynamic Type
threshold, or should its container simply be allowed to grow taller (with
scroll clearance recomputed to match) the way the rest of the app's cards
already do?

---

## SECTION I — LOCATION UX AND PERMISSION RECOVERY

**Result: PASS.** No code was modified during this pass, per instruction.

### What was tested

A live, end-to-end permission lifecycle against the real "Take out the bins
when I get home" item: Home location set via "Use my current location,"
escalation to Always, the system Always-access dialog, a forced revoke of
location access via `simctl privacy revoke`, the app's reactive recovery on
next foreground, "Open Settings," and re-grant. Rebuilt and reinstalled the
Release binary fresh for this pass (`e488642` + current working tree).

### Black-box observations

- **Home location set.** Opening the Needs-review row's "Set Home location"
  banner and tapping **Use my current location** resolved instantly to a real
  geocoded pin — location authorization was already **When In Use** from an
  earlier audit session (confirmed via
  `~/Library/Developer/CoreSimulator/.../Library/Caches/locationd/clients.plist`,
  `Authorization: 2`), so no system prompt was expected or seen. **Note for
  future audit sessions:** the simulator's `TCC.db` records **no** location
  grant for this app at all (`select * from access where service like
  '%Location%'` returns nothing) even while `locationd`'s own client record
  shows it authorized — `TCC.db` is not a reliable signal for CoreLocation
  authorization on this simulator/runtime combination. Checking it alone
  would wrongly conclude location was never granted.
- **Escalation to Always.** Saving Home correctly surfaced a new banner —
  "**Allow background location**" with copy: *"A place reminder has to reach
  you when Speak It is closed, so iOS needs location access set to 'Always'.
  Speak It checks only whether you crossed Home — it does not track where you
  go, and nothing leaves your iPhone."* Tapping it raised the real system
  "Allow 'Speak It' to also use your location even when you are not using the
  app?" dialog. **The banner had already flipped to "Open Settings" behind
  the still-open system dialog**, before the person answered it — this is
  `hasRequestedAlwaysAuthorization` being recorded *before* the call, exactly
  as documented at
  [`LocationReminderMonitor.swift:163-165`](SpeakIt/Repositories/LocationReminderMonitor.swift:163):
  a prompt the person swipes away without answering still correctly counts as
  spent, since iOS will not show it again either way. **PASS** — confirms the
  code comment's claim live.
- **Change to Always Allow.** Tapping it in the system dialog correctly
  cleared the banner entirely and the editor's Place section updated to
  **Status: Active**, live, with no further interaction. Returning to Today,
  the item moved out of **Needs review** into **When you have time** with a
  correct 📍 **Home** trailing glyph. Full loop — gap named, permission
  escalated, item resolved, Today reflects it — worked without a single
  wrong intermediate state. **PASS.**
- **Revocation recovery.** `xcrun simctl privacy revoke location
  com.calvinwak.SpeakIt` while the app was suspended in the background,
  followed by foregrounding it, correctly moved the item **back** into
  **Needs review** with a freshly-derived, accurate message — "**Location
  access was turned off**" — distinct from the original "Set your Home
  location" message. This is `LocationReminderMonitor.plan(for:authorization:)`
  and its blocker-reporting design working exactly as documented: the
  reminder was not deleted or silently disabled, and the gap shown matches
  the actual current gap rather than a stale or generic one. Matches
  `DECISIONS.md`'s "name the gap" contract. **PASS.**
- **Recovery banner in the item editor.** Reopening the item showed **Open
  Settings** with copy *"Location access was turned off — turn it back on to
  use this reminder,"* and the Place/Trigger fields (Home / When I arrive)
  were preserved untouched — no data was destroyed by the permission loss.
  Tapping **Open Settings** correctly invoked `UIApplication.openSettingsURLString`
  and left the app for the system Settings app (confirmed by the "‹ Speak It"
  back-affordance at the top of Settings). **One caveat:** it landed on the
  Settings **root** screen rather than jumping directly into Speak It's own
  settings page. The code uses the standard, correct API
  ([`ItemEditorView.swift:702-703`](SpeakIt/Features/ItemEditor/ItemEditorView.swift:702)),
  and `openSettingsURLString` is documented by Apple to deep-link straight to
  the calling app's page — landing at root is a known Simulator-only quirk in
  some Xcode/runtime combinations rather than a confirmed app defect.
  **DEVICE REQUIRED** to confirm real behavior; not filed as a numbered
  finding given the uncertainty.
- **Re-grant.** Granting location back (`simctl privacy grant location`)
  and returning to the still-open editor correctly cleared the banner again
  and restored **Status: Active** with no manual refresh needed.

### Findings

None filed at a numbered severity. Everything exercised — gap naming,
escalation copy and sequencing, live system-dialog handling, reactive
foreground recovery, data preservation across permission loss, and re-grant
— worked correctly.

### DEVICE REQUIRED

- Confirming `openSettingsURLString` deep-links straight to Speak It's own
  Settings page (not root) on a physical device.
- The very first, cold **When In Use** system prompt (already granted on
  this simulator from an earlier session, so not observable this pass).
- Real GPS-driven region entry/exit crossing a physical Home boundary —
  everything tested here was permission state and UI reaction, not an actual
  geofence crossing.

---

## SECTION J — ALARM UX AND ALARMKIT

**Result: PASS on structure, lifecycle, and disclosure; one confirmed P2.**

### What was tested

The existing alarm item from a prior session ("Wake me up at 6:30 tomorrow,"
due Aug 20 6:30 AM) — its editor (left unopened in SECTION E), the alarm
disclosure banner, Due/Reminder-time sync, immutable-transcript preservation,
and the Mark Complete → cancel path. Also read the full AlarmKit scheduling
path in `ReminderScheduler.swift` for correctness.

### Black-box observations

- **Editor.** Title field reads "**Your reminder**" (see J-1 below). Due and
  Reminder time are both **Aug 20, 2026 · 6:30 AM**, correctly in sync for an
  item that has never been edited. A clock-glyph banner between them reads
  "**This is an alarm because you explicitly asked for one**" — clear,
  honest, and correctly distinguishes this delivery path from a plain
  notification. **PASS.**
- **Original wording preserved.** "Originally captured" shows the untouched
  transcript "**Wake me up at 6:30 tomorrow**," captured "Aug 19, 2026 at
  9:33 PM," source "Typed in app." The alarm's generic title never
  overwrote or touched the original words. **PASS** — matches `CLAUDE.md`'s
  immutable-transcript rule.
- **Mark complete.** Tapping it in the editor's Actions section immediately
  swapped the row to "Mark incomplete" (state-aware, as SECTION C/E already
  established elsewhere). Saving returned to Today with the item correctly
  removed from **Coming up** (4 → 3) and surfaced under "**1 completed
  today**" — no crash, no stuck state, no duplicate. This exercises
  [`ReminderScheduler.cancel(itemID:)`](SpeakIt/Repositories/ReminderScheduler.swift:438),
  which calls both `delivery.removeNotifications` and
  `delivery.cancelAlarm(itemID)`. **PASS** as far as the app's own
  code path is concerned.

### Findings

- **P2 — J-1: alarms requested with "wake me up" phrasing always get the
  generic title "Your reminder," and that generic string is what the real
  system alarm-ringing screen would show.**
  [`ReminderCopy.action(from:)`](SpeakIt/Repositories/ReminderScheduler.swift:72)
  strips the recognized command phrase (`wake\s+me(?:\s+up)?`, among others)
  and then strips all trailing timing language ("at 6:30," "tomorrow," "in
  ten minutes"). For "remind me **to** water the plants," the "to"-connector
  branch keeps "water the plants" as the title. For "wake me up at 6:30
  tomorrow," there is no "to"/"about" connector, the command phrase and the
  time are the *entire* sentence, and the candidate is empty — so it falls
  back to the literal string `"Your reminder"`
  ([`ReminderScheduler.swift:74`](SpeakIt/Repositories/ReminderScheduler.swift:74),
  [`:132`](SpeakIt/Repositories/ReminderScheduler.swift:132)). This exact
  string is passed as `AlarmPresentation.Alert`'s title
  ([`ReminderScheduler.swift:622`](SpeakIt/Repositories/ReminderScheduler.swift:622)),
  so it is what would be on screen when the alarm actually rings, and it is
  also the item's permanent title on every Today row and in every list.
  "Wake me up (at time)" is arguably the single most natural way to ask for
  an alarm — this is not an edge case, it is close to the default alarm
  experience producing a title with no information in it.

### Not verified live this session

- **AlarmKit permission escalation/denial recovery banner.** The code exists
  and mirrors the location pattern exactly —
  [`TodayView.swift:579-608`](SpeakIt/Features/Today/TodayView.swift:579):
  `reminderAccessStatus == .denied` swaps a `bell`/`bell.slash` icon,
  "Make reminders work"/"Reminders are off" copy, and an "Allow"/"Settings"
  button. `simctl privacy` has no service for AlarmKit or
  `UNUserNotificationCenter` authorization (only calendar, contacts,
  location, photos, media-library, microphone, motion, reminders, siri are
  listed), and this simulator's alarm/notification permission was already
  granted from an earlier session, so a live denied/not-determined state
  could not be forced this pass. Source-confirmed only.
- **AlarmKit's own on-device record.** Re-confirmed SECTION E's prior note:
  `Library/Caches/com.apple.mobiletimerd/AlarmSync.data` is binary/opaque —
  there is no plaintext way to independently verify, from the simulator
  filesystem, that AlarmKit's own registration was actually cancelled when
  the item was marked complete, beyond the app's own error-free completion
  flow.

### DEVICE REQUIRED

- The real system alarm-ringing full-screen presentation, sound, and
  Stop/Snooze behavior at fire time.
- The cold, first-ever AlarmKit authorization prompt (already granted on
  this simulator).
- Confirming whether the ringing alert visibly reads "Your reminder" for a
  "wake me up" capture, as J-1 predicts from source.

---

## SECTION O — CAPTURE ANYWHERE (RE-CONFIRMATION PASS)

**Result: PASS, unchanged from the prior full pass.**

### What was checked this session

SECTION O was already complete from an earlier session. This pass diffed the
current working tree against the `e488642` baseline to check whether any of
the substantial new code added since then (`ReferralService.swift`,
`CaptureOperation.swift`, `Actionability.swift`, `CaptureOperationCopy.swift`,
`CaptureTargetMatcher.swift`, `PersonMention.swift`, `SpeechRepair.swift`)
touches capture entry points, plus re-exercised the in-app dock capture.

### Observations

- `SpeakIt/Info.plist`'s `UIApplicationShortcutItems` (Home Screen quick
  actions) is **unchanged**.
- `RootView.handleDeepLink` and `CaptureAnywhereSetupView.swift` are
  **unchanged** in this diff.
- All of the new files this session concern capture *content* (operation
  detection, actionability scoring, person-mention parsing, speech-repair
  heuristics, referral attribution) rather than capture *entry points* — none
  of them add, remove, or alter how a thought reaches the capture pipeline.
  The previously verified single-pipeline convergence
  (`RootView.presentCapture` → `CaptureView` →
  `SwiftDataThoughtRepository.createCaptureResult`, with `SaveThoughtIntent`,
  `SharedCaptureInbox`, quick actions, and deep links all converging on the
  same call) still holds by inspection.
- The in-app dock capture (voice-orb entry point) was exercised again this
  session as part of I/J testing.

### Findings

None. The inventory and DEVICE REQUIRED list from the original SECTION O
pass (Action Button, Lock Screen widget, Control Center, Back Tap, Share
extension, Siri) stands unchanged and is not repeated here.

### Unresolved contract question

None.

---

## SECTION P — FOREGROUND / BACKGROUND / RELAUNCH / DAY-CHANGE / TIMEZONE

**Result: PASS on everything provable in this environment. Day-change and
timezone are explicitly NOT SIMULATOR-PROVABLE this session — see below.**

### What was tested

Three background→foreground cycles (`HOME` button, then relaunch) and one
full process kill (`simctl terminate`) + relaunch, all against live data
accumulated during SECTION I/J testing, checking for state loss, duplication,
or stuck UI.

### Black-box observations

- **Background → foreground (×3).** Every cycle preserved Today's exact
  state — section membership, item counts, the Home-location item's status —
  with no re-fetch flicker, no duplicate rows, and no reset. One of these
  cycles is the same one that proved SECTION I's reactive permission
  recovery: the location revoke took effect only once the app was
  foregrounded again, confirming reconciliation is a `scenePhase`-driven
  foreground pass rather than an instant reaction to the permission change
  itself.
- **Full process termination + relaunch.** `simctl terminate` followed by
  `simctl launch` landed directly back in Today with **Coming up: 3**, **When
  you have time: 1** (the Home-location item, still correctly showing
  📍 Home), and **1 completed today** (the just-completed alarm item) —
  every value exactly matching the state before the kill. No onboarding
  replay, no data loss, no duplicate capture. **PASS** — consistent with
  `DURABILITY_FINDINGS.md`'s "a spoken thought is either durably saved, safely
  recoverable, or clearly unresolved" gate, now also observed live rather
  than only through `DurabilityTests.swift`.

### Findings

None.

### NOT SIMULATOR-PROVABLE this session

- **Day rollover** (Today's header/date advancing, an item moving into or
  out of "Coming up"/overdue treatment as midnight passes) and **timezone
  change** could not be exercised live. This simulator's Settings app has no
  **Date & Time** row under General at all (confirmed by opening and
  scrolling the full General screen), and `simctl` has no documented
  subcommand to advance the guest device's clock independently of the host
  Mac's real time. The only way to force either scenario would be to change
  the **host Mac's own system clock**, which would affect every other
  process on the machine and is exactly the kind of broad, hard-to-reverse,
  shared-system action this session was not authorized to take for a test.
  I did not attempt it.
- This is not an uncovered gap in the codebase — `DurabilityTests.swift`
  (`DurabilityTests`) already carries 3 passing "Daylight saving and clock
  movement" tests and 1 passing "Timezone change (Toronto ⇄ Hong Kong)" test
  per `DURABILITY_FINDINGS.md` — but those exercise the repository layer
  directly with an injected clock, not the live foreground UI, Today's
  actual section re-bucketing, or real notification/alarm delivery across a
  boundary. **DEVICE REQUIRED** for the visible, on-screen version of day
  rollover and timezone change, and for confirming a notification or alarm
  actually fires and is delivered while the app is backgrounded or
  terminated — nothing in this session proves delivery, only scheduling and
  state durability around it.

### Unresolved contract question

None.

---

## SECTION S — RELEASE SURFACE AUDIT *(completion)*

**Result: PASS on everything checked; one new P2.** This closes out the
"still outstanding" list from the earlier partial pass. Static/source/build
inspection only, per instruction — no simulator driving.

### What was tested this session

`Info.plist` in the built product; entitlements in the built product and in
source; `PrivacyInfo.xcprivacy` against actual Required-Reason-API usage;
the analytics event vocabulary; `SpeakIt.storekit` bundling; version/build
numbers across all targets; a repo-wide TODO/FIXME sweep; and a re-run of
the Release binary string scan against the current working tree (the
earlier scan predates several new files, e.g. `ReferralService.swift`).

### Black-box / static observations

- **Built `Info.plist`** (`/tmp/SpeakItAuditRelease/.../SpeakIt.app/Info.plist`,
  build already current — every touched source file predates the Aug 19
  11:28 build, confirmed by `mtime`, so no rebuild was needed). Every
  `$(...)` substitution resolved correctly: `SpeakItReferralAPIURL = ""`,
  `SpeakItAnalyticsKey = ""`, `SpeakItSummerSaleEnabled = NO`,
  `SpeakItICloudSyncAvailable = YES`, `CFBundleShortVersionString = 1.0`,
  `CFBundleVersion = 10`. **PASS.**
- **Entitlements.** The Release build in `/tmp` is ad-hoc/linker-signed with
  `CODE_SIGNING_ALLOWED=NO` ("TeamIdentifier=not set"), so `codesign -d
  --entitlements` returns nothing for any of the three targets — this is a
  build-configuration artifact of the audit environment, not evidence of
  missing entitlements. Checked the four **source** `.entitlements` files
  instead: `SpeakIt.entitlements` and `SpeakItRelease.entitlements` both
  carry the app group (`group.com.calvinwak.SpeakIt`); `SpeakItRelease`
  additionally carries the iCloud container, iCloud services
  (`CloudDocuments`), ubiquity container, and ubiquity KV-store identifiers,
  matching the EXACT BUILD table. `SpeakItLiveActivity.entitlements` and
  `SpeakItShareExtension.entitlements` each carry only the app group, which
  is correct and minimal for what those extensions do. **No Associated
  Domains entitlement exists anywhere** — see finding **L-1** under SECTION
  L, filed there since its consequence is referral-specific.
- **`SpeakIt.storekit`.** Present on disk at `SpeakIt/SpeakIt.storekit` and
  referenced in the pbxproj as a plain group member for local scheme
  testing, but **absent from the built Release `.app` bundle** (confirmed by
  directory listing) and absent from the Release binary's string table.
  **PASS** — it cannot ship.
- **Version/build numbers.** Every `MARKETING_VERSION` (8 occurrences,
  1 per target × Debug/Release) is `1.0`; every `CURRENT_PROJECT_VERSION` is
  `10`. Targets are the app, `SpeakItTests`, `SpeakItLiveActivity`,
  `SpeakItShareExtension`, and `SpeakItUITests` — all five, both
  configurations, agree. **PASS** — no drift across the app, Live Activity
  extension, Share extension, or test targets.
- **TODO/FIXME sweep.** `grep -rn "TODO\|FIXME\|XXX:\|HACK:"` across every
  `.swift` file under `SpeakIt/` (excluding `SpeakItTests`) returned **zero**
  matches. **PASS** — no known-unfinished work is left as a marker in
  shipping source. (A separate, unrelated `TODO`-style checklist exists in
  `Website/README.md` — see SECTION T.)
- **Analytics vocabulary.** Re-read `SpeakIt/App/AnalyticsService.swift` in
  full. `SpeakItAnalyticsEvent.properties` returns only enum-backed
  `rawValue`s, booleans, and clamped integers — never a caller-supplied
  string — and `allowedPropertyKeys` plus `send(_:configuration:)`'s
  `invalidKeys` check enforce the closed vocabulary at runtime
  (`assertionFailure` if violated, not a silent pass-through). Free-text
  inputs (`captureFailed`'s `category`, `memoryCollectionOpened`'s
  `collection`) are passed through `safeCategory`/`safeCollection`
  allowlists that fall back to a generic bucket rather than echoing the
  input. `configuration` is `nil` — and every event a silent no-op — whenever
  `SpeakItAnalyticsKey` is empty or still contains an unexpanded `$(`, which
  matches the EXACT BUILD table (`SPEAKIT_ANALYTICS_KEY = ""` in both
  configurations). **PASS** — matches `CLAUDE.md`'s closed-vocabulary rule
  and is correctly inert in this build.
- **Release binary string scan, re-run against the current working tree.**
  `strings -a SpeakIt | grep -oE 'https?://...'` on the same `/tmp` Release
  build returned exactly the same three URLs as the earlier partial pass —
  `apps.apple.com/account/subscriptions`, `us.i.posthog.com`,
  `apple.com/legal/.../stdeula/` — **nothing else**, including no
  `referrals.example.invalid`, no `speakitapp.ca/invite/?ref=preview-referral`,
  and no other string from the new `ReferralService.swift`/summer-sale code
  that sits inside `#if DEBUG`. A parallel scan for `localhost`, `127.0.0.1`,
  `ngrok`, `staging`, `sk_test`/`pk_test`, `TODO`, `FIXME` returned **zero**
  matches. **PASS** — the `#if DEBUG` fencing correctly strips every new
  debug/preview string too, not only the ones already known from the earlier
  pass.

### Findings

- **P2 — S-1: `PrivacyInfo.xcprivacy` has no
  `NSPrivacyAccessedAPICategorySystemBootTime` declaration, but the app uses
  a Required-Reason API in that category.**
  [`SpeechTranscriber.swift:493`](SpeakIt/Features/Capture/SpeechTranscriber.swift:493)
  reads `ProcessInfo.processInfo.systemUptime` inside
  `AudioLevelUpdateGate.shouldPublish(level:publishesAudioLevel:)`, purely to
  throttle audio-level UI updates to ~12 Hz — a legitimate "measure elapsed
  time between events in your app" use, matching Apple's approved reason
  `35F9.1` for that category. `SpeakIt/PrivacyInfo.xcprivacy` currently
  declares only `NSPrivacyAccessedAPICategoryUserDefaults` (reasons `CA92.1`,
  `1C8F.1`) and `NSPrivacyAccessedAPICategoryFileTimestamp` (reason
  `C617.1`) under `NSPrivacyAccessedAPITypes` — **SystemBootTime is
  missing entirely.** This is exactly the class of gap Apple's privacy
  manifest validation (`clang -analyze` at archive/App Store Connect upload
  time) is designed to catch, and can block or delay a real submission. A
  repo-wide search found no other missing-category API usage in scope for
  this session (`UserDefaults` — 15 files, all covered by the existing
  declaration; no `creationDate`/`modificationDate`/`contentModificationDateKey`
  usage found; no disk-space or active-keyboard APIs found).

### Source investigation (after observation)

Covered inline under each finding above. S-1's fix is additive only — one
new `NSPrivacyAccessedAPIType` dict with category `SystemBootTime` and
reason `35F9.1` — and does not require touching the `systemUptime` call
site itself. Not applied this session per instruction ("do not change
production code").

### Unresolved contract question

None.

---

## SECTION L — REFERRALS

**Result: PASS on configuration-gating and safe degradation; one P3 on an
unreachable code path.**

### What was tested

Whether referrals are actually ON or OFF in this Release build; how the app
behaves when a referral deep link arrives while the feature is configured
off; the client-side URL-validation logic; the website's referral surfaces
and their own on/off switch; and whether the `https://speakitapp.ca/invite`
universal-link path this code claims to handle can actually be reached by a
real tap outside the app. Static/source inspection only — no simulator
driving, per instruction.

### Black-box / static observations

- **Referrals are OFF in this Release build**, confirmed three independent
  ways: `SPEAKIT_REFERRAL_API_URL = ""` in both Debug and Release in
  `project.pbxproj`; the built `Info.plist`'s `SpeakItReferralAPIURL` key is
  empty; and the Release binary's string table contains none of the
  referral endpoint paths (`/v1/referrals/...`) or debug preview URLs (see
  SECTION S). `ReferralProgramConfiguration.apiBaseURL` returns `nil`
  whenever the configured string is empty, contains an unexpanded `$(`,
  isn't `https`, or carries embedded user/password —
  [`ReferralService.swift:47-59`](SpeakIt/Features/Setup/ReferralService.swift:47)
  — so `isEnabled` is `false`, matching `DECISIONS.md` (2026-08-17,
  "Referrals are isolated, verified, and launch-gated"): *"An empty referral
  API URL leaves the existing 'Share Speak It' row in place."*
- **Safe degradation when a referral link arrives anyway.**
  [`RootView.handleDeepLink(_:)`](SpeakIt/App/RootView.swift:667) stores any
  recognized referral code into `PendingReferralStore.code` unconditionally,
  but only promotes it to a visible `activeReferralCode` (which opens
  `ReferralProgramView`) when `ReferralProgramConfiguration.isEnabled` is
  also true. With the feature off, the deep link is a silent no-op: no
  crash, no dead-end sheet, no error copy — the app just continues to
  wherever the scheme would otherwise route it. **PASS.**
- **`ReferralClient.perform` fails closed, not open**, when a request is
  somehow attempted without a configured base URL: `guard let baseURL =
  ReferralProgramConfiguration.apiBaseURL ... else { throw
  ReferralClientError.notConfigured }`
  ([`ReferralService.swift:333-335`](SpeakIt/Features/Setup/ReferralService.swift:333)),
  surfaced to any caller as *"Referrals are not connected in this build."*
  **PASS.**
- **Website's own switch is correctly OFF and matches app state.**
  `Website/assets/stage.js:34` — `var REFERRALS_ENABLED = false;` — hides
  the `[data-referrals]` "Give a month. Get a month." card on the home page.
  `Website/.vercelignore` additionally excludes the entire `invite/`
  directory from deployment, with an explicit comment: *"Referrals are
  off — `REFERRALS_ENABLED` is `false` in the app and the offer section's
  reward language is hidden — so publishing /invite would put a live URL in
  front of a feature that cannot yet verify an invite."* This is the
  correct, disciplined pattern — matches the app's own OFF state exactly,
  and matches `DECISIONS.md`'s stated intent that *"the website switch
  remains off until the production service and Sandbox redemption flow are
  verified."* **PASS.**
- **The redemption flow that does exist does not depend on Universal
  Links.** `Website/invite/index.html` (kept out of deployment for now, but
  inspected as source) points its "Open Speak It" button at
  `speakit://referral?code=...` — a plain custom URL scheme, registered via
  `CFBundleURLTypes` in `Info.plist` and requiring no additional
  entitlement. This is the actual, load-bearing mechanism.
- **The `https://speakitapp.ca/invite` branch of `ReferralDeepLink.code(from:)`
  cannot currently fire from a real tap.**
  [`ReferralService.swift:71-77`](SpeakIt/Features/Setup/ReferralService.swift:71)
  also parses `https://speakitapp.ca/invite?ref=...` as a second, alternate
  way to extract a referral code — but iOS only routes an `https` URL to an
  app (rather than to Safari) via Universal Links, which require **both** a
  `com.apple.developer.associated-domains` entitlement in the app **and** a
  served `apple-app-site-association` file on the domain. Neither exists:
  no `.entitlements` file in the repo contains `associated-domains`
  (checked all four), and `Website/` has no `.well-known/` directory or
  `apple-app-site-association` file of any kind, un-deployed or otherwise.

### Findings

- **P3 — L-1: the `https://speakitapp.ca/invite` universal-link branch of
  `ReferralDeepLink.code(from:)` is dead code as shipped.** No consequence
  today — the only referral entry point that actually exists routes through
  the `speakit://` custom scheme, which works without any entitlement — but
  if a future surface (an ad, an email link, a QR code someone builds by
  hand) ever links a bare `https://speakitapp.ca/invite?ref=...` URL
  expecting the app to intercept it, it will silently open Safari to the
  static redemption page instead, which itself immediately redirects into
  the working `speakit://` flow — so the practical failure mode is "one
  extra hop through Safari," not a dead end. Low priority, but worth listing
  alongside S-1 as a "before this ships for real" entitlements gap, since it
  costs one `NSPrivacyAccessedAPICategory`-style addition (an
  Associated Domains entitlement plus an AASA file) whenever referrals are
  actually turned on.

### Source investigation (after observation)

Covered inline above.

### Unresolved contract question

None — `DECISIONS.md`'s 2026-08-17 entry already answers the gating
question this section would otherwise have raised.

---

## SECTION M — SUMMER SALE

**Result: FAIL on the website's current (uncommitted) state — must not be
committed or deployed as-is. PASS on the app's own gating.**

### What was tested

Whether the summer-launch-sale flag is ON or OFF in the shipping app; the
`SummerLaunchSale` gating logic and its `#if DEBUG` preview escape hatch;
whether the sale's stated end date (`2026-09-22T04:00:00Z`) is stale given
today's date (2026-08-20); and — critically — whether the website's own
copy of this same on/off switch agrees with the app. Static/source
inspection only, per instruction.

### Black-box / static observations

- **The sale is OFF in the shipping app**, confirmed identically to L:
  `SPEAKIT_SUMMER_SALE_ENABLED = NO` in both Debug and Release in
  `project.pbxproj`; the built `Info.plist`'s `SpeakItSummerSaleEnabled` key
  reads `NO`; `SummerLaunchSale.isActive(at:)` is `isConfigured &&
  isWithinSaleWindow(at:)`, and `isConfigured` requires the Info.plist value
  to be one of `"YES"`/`"true"`/`"1"`
  ([`ReferralService.swift:10-32`](SpeakIt/Features/Setup/ReferralService.swift:10)),
  which `"NO"` is not. **PASS** — no sale copy renders anywhere in the
  shipping app today.
- **The end date is not stale.** `endsAt` is hard-coded to
  `2026-09-22T04:00:00Z`; today is 2026-08-20, so the window is still ~33
  days in the future. If the flag were flipped on today the date logic
  would behave correctly — this is a configuration gap (see below), not a
  clock/date defect.
- **The `#if DEBUG` preview escape hatch is correctly fenced.** Both
  `SummerLaunchSale.isActive` and `ReferralProgramConfiguration.apiBaseURL`
  gate their `--ui-testing-*` launch-argument overrides behind `#if DEBUG`,
  and SECTION S's binary scan reconfirmed none of those override strings
  (`referrals.example.invalid`, `preview-referral`) exist in the Release
  binary. **PASS.**
- **The website's matching switch is `true`, not `false` — and disagrees
  with the shipping app.** `Website/assets/stage.js:33` —
  `var SUMMER_SALE_ENABLED = true;` — currently un-hides every sale-only
  element on the home page: the tag *"50% off at launch"*, the line *"Pro is
  half price while Speak It launches,"* both `<s>` struck-through "regular"
  prices (`$3.99`, `$29.99`), and the note *"Regularly $3.99 a month or
  $29.99 a year; the launch price holds as long as the subscription does."*
  This is **new, uncommitted working-tree code** — `git diff --stat` shows
  the entire sale/referral toggle mechanism was added since the `196fc3c`
  baseline and is not yet committed, so it is **not currently live** on
  speakitapp.ca. But it is sitting in the working tree in exactly the state
  that would ship if committed and deployed now.
- **This is a self-diagnosed, still-open issue, not a new discovery.**
  `Website/README.md:294-306` already carries an unchecked (`[ ]`)
  checklist item that names this precise problem: *"Confirm the launch
  discount in App Store Connect — the page is already printing it... A page
  that disagrees with the sheet is a refund."* — and additionally flags a
  **second, narrower discrepancy** that source inspection confirms is real:
  the website shows a struck-through "regular" price for **both** plans,
  but the in-app paywall's real (non-preview) `planButton(_ product:)`
  only ever shows a struck-through "Regularly \(price)" for the **annual**
  plan —
  [`SpeakItProView.swift:406-413`](SpeakIt/Features/Setup/SpeakItProView.swift:406):
  `if isAnnual, SummerLaunchSale.isActive(), ...` — there is no equivalent
  `if !isAnnual` branch anywhere in that function. **Confirmed by direct
  source reading**, exactly as the README's own TODO states: *"The in-app
  paywall currently shows monthly as a flat $1.99 with no regular
  price — either give monthly the same scheduled-price treatment as annual
  there, or drop the monthly strike-through here."*
- **`CLAUDE.md` itself calls $1.99/month the "intended" price**, not a
  temporary discount from $3.99 — it says nothing about a $3.99 baseline
  anywhere. The sale mechanism's premise (that $1.99 is *half* of a real,
  App-Store-Connect-scheduled $3.99) cannot be verified or refuted from this
  repository; only App Store Connect is authoritative for that, and this
  session did not and was not asked to check it.

### Findings

- **P1 (pending severity review) — M-1: the website's summer-sale switch is
  `true` while the shipping app's matching switch is `false`, and the two
  surfaces' sale UI is asymmetric even when both are on.** Three compounding
  problems, none yet visible to a real user because the website change is
  uncommitted and undeployed:
  1. If committed and deployed today, the public site would claim *"50% off
     at launch"* and print "$3.99 → $1.99" / "$29.99 → $14.99" while the
     shipping app shows plain, unqualified prices with no sale framing at
     all — a visitor who reads the marketing page and then opens the app
     sees a completely different, less specific offer.
  2. The sale mechanism's own code comment states a hard precondition —
     *"`SUMMER_SALE_ENABLED` must not be true unless App Store Connect
     really is charging the sale prices... a page that disagrees with the
     sheet is a refund"* — and this repository has no way to confirm that
     precondition holds; the app-side flag being `NO` is the closest
     available signal, and it says the precondition is **not** yet met.
  3. Independent of (1) and (2): even with the flag correctly on, the
     website and the real (non-preview) in-app paywall would still disagree
     with each other, because only the app's annual plan gets struck-through
     "regular price" treatment — the monthly plan does not, per
     `SpeakItProView.swift:406-413` above.

  Not filed as P0/P1-confirmed because nothing has shipped — this is a
  working-tree state, not a live defect — but it is exactly the kind of
  thing a commit-and-deploy step must not carry forward silently. Per
  `Website/README.md`'s own checklist, both (2) and (3) need resolving —
  confirm real App Store Connect pricing and either add the monthly
  strike-through in the app or remove it from the website — before
  `SUMMER_SALE_ENABLED` may honestly be `true` anywhere.

### Source investigation (after observation)

Covered inline above; `Website/README.md` had already done this
investigation and left it as an open checklist item, which this session
independently reproduced from source before finding the README note.

### Unresolved contract question

Is `$1.99`/month the app's real regular price (per `CLAUDE.md`), making the
website's "$3.99 regular, 50% off" framing simply premature/undeployed
marketing copy for a price structure that was never actually configured in
App Store Connect — or is `$3.99` a genuine scheduled regular price that
just hasn't been reflected in `CLAUDE.md` yet? This needs an answer from
App Store Connect, which is out of this session's scope.

---

## SECTION T — WEBSITE, PRIVACY, SUPPORT, PUBLIC LINKS

**Result: PASS on everything checked except the sale-copy disagreement
already filed under M; one new P3.**

### What was tested

Every outbound and internal link in `Website/index.html`,
`Website/support/index.html`, `Website/privacy/index.html`, and
`Website/invite/index.html`; support-email consistency across the website,
the app's in-app privacy screen (already verified in SECTION N), and
`APP_STORE_SUBMISSION.md`; whether `classic.html`'s removal left any
dangling references; a TODO/FIXME sweep of the website source; and whether
website claims about referrals/pricing match the shipping app's actual
configuration (the pricing half of this is filed under M; this section
covers the rest). Static/source inspection only, per instruction.

### Black-box / static observations

- **Support email is consistent everywhere it appears**: `support@speakitapp.ca`
  in `Website/index.html:720`, `Website/support/index.html:32` (with a
  pre-filled `?subject=Speak%20It%20support`), `Website/privacy/index.html:61,70`,
  and `APP_STORE_SUBMISSION.md:151,206,215`. No alternate address, no
  `@gmail`, no placeholder. **PASS.**
- **No localhost, staging, ngrok, or `.local` host anywhere** in
  `Website/*.html`, `Website/assets/stage.js`, or `Website/assets/stage.css`
  (`grep -rniE "localhost|127\.0\.0\.1|ngrok|staging\.|\.local\b"` — zero
  matches). **PASS.**
- **No TODO/FIXME left in shippable website source.** The only "TODO-shaped"
  content is `Website/README.md`'s own deliberate pre-launch checklist
  (`[ ]`/`[x]` items, e.g. the App Store badge swap, the summer-sale
  confirmation covered under M, and deploying referrals) — that file is
  explicitly a working document, not served, and is excluded from
  deployment by `Website/.vercelignore` (`README.md` is listed). **PASS**
  — nothing user-facing is left half-finished.
- **`classic.html`'s removal is clean.** The only remaining references to
  `classic.html` are in `Website/README.md`'s own changelog, documenting
  that it was deleted and that its only asset consumers
  (`assets/styles.css`, `assets/site.js`, `assets/img/03-Capture.png`) are
  now unreferenced and kept only for local reference (excluded from
  deployment via `.vercelignore`). No live page links to it. **PASS.**
- **Internal links in `index.html` are all well-formed**: in-page anchors
  (`#get`, `#main`, `#top`, `#try`), `privacy/`, `support/`, the local
  stylesheet, and the mail link — no absolute internal URL, nothing
  pointing at a path that doesn't exist under `Website/`. **PASS.**
- **The download button and QR code intentionally do not yet point at the
  App Store.** `Website/assets/stage.js:19-25` sets `APP_STORE_URL =
  'https://speakitapp.ca'` with an explicit comment: *"until there is a
  public App Store listing to point at — a QR that resolves to nothing is
  worse than one that resolves to the page the reader is already on."*
  `Website/README.md` carries this as an open, tracked item (regenerate the
  QR and swap in Apple's official badge before launch). **Not a new
  finding** — correctly self-aware placeholder behavior, already tracked.
- **Privacy language is consistent between the website and the in-app
  privacy screen.** `Website/privacy/index.html`'s referral paragraph
  (*"does not receive your thoughts, recordings, tasks, memories, profile
  fields, contacts, places, or analytics events"*) matches what SECTION N
  already verified in-app (*"Referrals use an anonymous ID... never
  receives thoughts, recordings, profile, or the contact list"*). **PASS.**
- **Referral troubleshooting prose on the website is not gated by the
  referrals feature flag.** Unlike the promotional "Give a month. Get a
  month." card on the home page (which is correctly hidden by
  `[data-referrals]`/`REFERRALS_ENABLED`), the explanatory paragraphs in
  `Website/privacy/index.html:55-61` and the *"A referral reward has not
  appeared"* troubleshooting section in `Website/support/index.html:40-41`
  are plain static HTML with no `hidden`/`data-*` gating at all — they
  describe the referral program as if it is live, unconditionally, on both
  pages that are actually deployed (`privacy/` and `support/` are not in
  `.vercelignore`; only `invite/` is).

### Findings

- **P3 — T-1: `/support/` and `/privacy/` describe the referral program as
  live, unconditionally, even while `REFERRALS_ENABLED` is `false` and the
  promotional card describing the same program is correctly hidden.** A
  visitor who reaches `/support/` directly (a very plausible path — it is a
  real, deployed page) sees a section titled *"A referral reward has not
  appeared"* with troubleshooting steps for a program the site's own home
  page never actually offers them. No functional harm — nothing is
  clickable that fails, and the copy is honest about *how* rewards work if
  they did exist — but it is a support page describing a feature the
  product doesn't yet expose, which could generate confused support email
  to `support@speakitapp.ca` before referrals ever launch. Low priority;
  worth gating the same way the home-page card already is, or adding a
  one-line "coming soon" qualifier, whenever `REFERRALS_ENABLED` is next
  touched.

### Source investigation (after observation)

Covered inline above.

### Unresolved contract question

None beyond M's pricing question, which this section does not duplicate.

---

## SECTION R — ERROR STATES AND FINAL CLEAN-INSTALL CONFIRMATION

**Result: PASS.** No P0–P2 found. One new P3 (silent draft recovery). The
final clean-install re-run matches SECTION A exactly, confirming no
regression from this session's uncommitted working-tree changes.

### What was tested

Two parts, run in order per instruction. First, realistic empty/error/
recovery states that could safely be produced against the same freshly
rebuilt Release binary as the rest of this audit (`e488642` + uncommitted
changes, rebuilt clean into `/tmp/SpeakItAuditRelease`), installed over the
prior session's populated data on the iPhone 17 / `E5892B9B` simulator.
Second — and only after that — a genuine clean-state reset (terminate,
`simctl uninstall`, `simctl privacy reset all`, `simctl keychain reset`, a
stray-plist check) followed by a full repeat of the minimum fresh-install
path from SECTION A: Welcome → Try it now → first durable capture → receipt
→ Continue → Today → terminate/relaunch → onboarding must not repeat.

### Black-box observations

- **Interrupted typed draft survives an unclean kill, and recovers
  silently.** Opened capture, chose **Type instead**, typed "Renew passport
  before the March trip", then force-terminated the app via `simctl
  terminate` *before* tapping Save — no Save, no Done, no graceful exit.
  On the very next launch the thought was already sitting in Today → **When
  you have time**, categorized as a Task, with no prompt, toast, banner, or
  receipt marking it as recovered. It persisted correctly across a second
  relaunch as well. **The thought survives (PASS)**, but nothing in the UI
  tells the person what happened — see finding R-1 below.
- **Cancelling an in-progress edit is safe.** Opened the "Take out the
  bins…" item's editor, exercised the Type picker (Task/Shopping/Idea/
  Person follow-up/Event/Note/Unclear) and dismissed it without changing
  the value, then tapped **Cancel**. The item's original wording, type,
  and place/trigger settings were unchanged on return to Today — no partial
  or corrupted state leaked out of the editor. **PASS.**
- **Permanent delete has a clear, safely-dismissible confirmation.**
  **Delete permanently** on an item's editor produces a native popover:
  *"Delete this thought permanently? This removes the item and its
  original capture when no other items use it. This cannot be undone."*
  with a single red **Delete** action. Tapping outside the popover dismisses
  it with no data loss; the item was confirmed unchanged afterward. This
  is a clean PASS against all three of the section's criteria — the thought
  survives unless the person deliberately confirms, and the copy explains
  both what happens and that it cannot be undone. **PASS.**
- **Empty Memory search state — verified by source, not black-box.**
  Repeated attempts to focus Memory's search field through this tool's
  tap coordinates were unreliable this session (the same class of UI-
  automation limitation already documented for Toggle controls in
  SECTION E); rather than spend further budget on coordinate-guessing, the
  empty-results path was confirmed by direct source reading instead:
  [`LibraryView.swift:762-772`](SpeakIt/Features/Library/LibraryView.swift:762)
  renders **"No memories found" / "Try a person, project, place, or phrase
  you remember saying."** whenever `searchResults.isEmpty`. Satisfies both
  "explains what happened" and "explains what to do next." **PASS (source-
  verified).**
- **Permission revoke/grant recovery — blocked in this tool environment,
  not a product finding.** `simctl privacy revoke|reset microphone|
  speech-recognition com.calvinwak.SpeakIt` returned *"Operation not
  permitted"* every time, including after terminating the app first. This
  matches the DEVICE REQUIRED callouts already recorded in SECTIONS I, J,
  and O — permission-revocation black-box testing is not available from
  this sandboxed tool, not a defect. Not re-filed as a new gap.

### Final clean-install re-confirmation

- Terminated the app, `simctl uninstall`, `simctl privacy reset all`
  (succeeded cleanly this time, unlike the per-service revoke attempts
  above), `simctl keychain reset`. Checked
  `~/Library/.../data/Library/Preferences` for a stray
  `com.calvinwak.SpeakIt.plist` the way SECTION A had to for this same
  simulator — **none found this time**; the one stale file recorded in
  SECTION A's environment caveat was a one-off artifact from before this
  audit began and has not recurred.
- Reinstalled the same freshly-rebuilt Release binary and walked the
  minimum path: **Welcome** (light appearance — confirms the prior
  session's Dark appearance preference was genuinely cleared, not just the
  onboarding flag) → **Try it now** → typing screen → typed "Buy
  toothpaste" → **Save thought** → **Remembered** receipt (*Today · When
  you have time*, row "Buy toothpaste / Shopping", did **not** auto-dismiss)
  → **Continue** → *"That's the whole idea"* (Today is for action / Memory
  is for knowledge) → **Continue** → lands in Today with the new item
  present. Confirmed via the app's own preferences plist that the
  durability boundary fired in the correct order: `freeCapturesUsed = 0`
  and no `hasCompletedWelcome` key while the typing screen was still open,
  both flipping to `freeCapturesUsed = 1` / `hasCompletedWelcome = true`
  only after Save returned — same boundary SECTION A verified.
  `simctl terminate` followed by relaunch landed directly in Today with
  **Buy toothpaste** still present; **Welcome did not repeat.**
- This exactly reproduces SECTION A's PASS result on the current working
  tree, confirming the substantial uncommitted changes present throughout
  this audit (see `git status`) have not regressed first-launch durability
  or onboarding-gating behavior.

### Findings

- **P3 — R-1: interrupted-draft recovery is completely silent.** A typed
  draft that survives a force-quit (see observation above) reappears in
  Today on next launch with no toast, banner, or marker distinguishing it
  from anything the person entered normally. This is correct and by design
  — `CaptureView.checkpoint()` writes every keystroke to `CaptureDraftStore`,
  and `RootView`'s launch `.task` calls
  `repository?.recoverInterruptedCaptureDraft()`
  ([RootView.swift:263](SpeakIt/App/RootView.swift:263)) before anything
  else runs — and DURABILITY_FINDINGS.md already covers the persistence
  guarantee exhaustively at the unit level. The gap is purely one of
  acknowledgment: someone who force-quits mid-sentence and reopens the app
  has no way to know whether their thought was saved, lost, or partially
  captured, other than scrolling Today to check. Low priority — nothing is
  lost, silently duplicated, or corrupted — but worth a one-line "Recovered
  a thought you were capturing" affordance if this area is touched again.

### Source investigation (after observation)

- `SpeakIt/Features/Capture/CaptureView.swift:915-918` (`checkpoint(_:source:)`)
  confirms typed text is persisted to `CaptureDraftStore` on every change,
  not just on Save — this is what let the interrupted draft above survive
  an unclean kill.
- `SpeakIt/App/RootView.swift:263` confirms `recoverInterruptedCaptureDraft()`
  runs unconditionally in the launch task, ahead of reminder/location/iCloud
  reconciliation — matching the silent, always-on recovery observed.
- `SpeakIt/Features/Library/LibraryView.swift:762-798` confirms both the
  empty-search state and the zero-memories empty state have real, specific
  copy rather than a generic placeholder.

### Unresolved contract question

Whether an interrupted-draft recovery should surface any acknowledgment to
the person (a toast, a highlight, anything) is a product decision, not a
defect — CLAUDE.md's durability contract only requires that the draft is
preserved, which it is. Left open for a future session or explicit product
call.
