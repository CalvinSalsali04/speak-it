# Speak It Build 14 — device smoke test

Target: **Speak It 1.0 (14), Release**, on Calvin's iPhone 13, iOS 26.6.
Commit: `c5be8d5`.

Install Release, not Debug — Debug is very laggy on device:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project SpeakIt.xcodeproj -scheme SpeakIt -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/SpeakItDevice14
```

Then install the built `.app` with `xcrun devicectl`.

**What is new in this build:** every schema version is frozen, the store moves
to version 4 on first launch, and Needs review now names what the interpreter
could not settle instead of guessing a reason from the row's other fields. Test
D5 and A2 are the two that exercise it directly.

Nothing about parsing changed. If a phrase reads differently than it did in
build 13, that is a finding.

---

## A. Installation and data

| # | Action | Expect | Blocker if |
|---|---|---|---|
| **A1** | Fresh install onto a phone with no Speak It data (delete the app first). Launch. | Onboarding appears. No `StorageUnavailableView`, no "storage unavailable" copy anywhere. First capture works. | The storage error screen appears at all. That is the version 4 store failing to create — **stop-ship**. |
| **A2** | **Upgrade path.** Before installing build 14, launch your *existing* build 13 install and note 3–4 items you can recognise (one with a reminder, one note, one completed). Then install build 14 over it without deleting. | Every item is still there, same titles, same dates, same completion and archive state. Reminders unchanged. Places (Home/Work) still set. | Any item missing, any date moved, any completed item back as outstanding, or the storage error screen. **Stop-ship** — this is the V3→V4 migration. |
| **A3** | After A2, force quit and relaunch twice. | Library identical both times. No re-migration, no duplicates. | Anything changes between launches. |
| **A4** | Start a voice capture, speak a sentence, and **force quit mid-recording** (swipe up before it saves). Relaunch. | The words are recovered — either saved, or offered back as an interrupted draft with Try Again / Type Instead. Never silently gone. | The capture vanished with no trace. **Stop-ship**. |

> Note on A2: free-capture allowance lives in the Keychain and survives deleting
> the app. To test a true first-time user you need the Debug `--ui-testing-reset`
> launch, not just a reinstall.

---

## B. Basic capture

Say each, then check where it landed.

| # | Say | Expect | Blocker if |
|---|---|---|---|
| **B1** | "Call the dentist tomorrow at 2" | **Today**, task, reminder tomorrow 2:00 PM. | Lands in Memory, or no reminder. |
| **B2** | "The studio door code is 4821" | **Memory**, note. No reminder. | Lands in Today, or schedules anything. |
| **B3** | "Buy laundry detergent" | **Today**, shopping, on a list. | Typed as a plain task with no list, or routed to Memory. |
| **B4** | "Sarah's birthday is May 3" | **Memory**, person fact, filed under Sarah. | Lands in Today. A dated *fact* must not become an action. |

---

## C. Structural parser cases

These are the readings the last three phases were about. Expected results below
are what the pipeline produces today — verified against the same code that is in
this build.

| # | Say | Expect | Blocker if |
|---|---|---|---|
| **C1** | "Buy milk and eggs" | **Two** shopping rows, "Buy milk" and "Buy eggs", both on the Groceries list. | One row saying "Buy milk and eggs", or three rows. |
| **C2** | "Buy milk and text Daniel" | **Two** rows: "Buy milk" (Today, shopping, Groceries) and "Text Daniel" (Today, person follow-up, Daniel). | Merged into one row, or "eggs"-style treatment that puts Daniel on a shopping list. |
| **C3** | "Buy milk and Sarah hates sushi" | **Two** rows, and they split across destinations: "Buy milk" → **Today** (shopping); "Sarah hates sushi" → **Memory** (note, filed under Sarah). | Both in one destination, or one row. This is the split that proves coordination is read by structure, not by the word "and". |
| **C4** | "Sarah said the meeting is off" | **Memory**, note, filed under Sarah. Nothing scheduled. | Lands in Today, or creates a reminder. Reported speech must not become your task. |
| **C5** | "Text Mike that the deal is off" | **Today**, person follow-up, Mike. This one *is* yours to do. | Lands in Memory — that would mean a real instruction was filed away as trivia. |
| **C6** | "Sarah told me to call Mike" | **Today**, task. It is yours to do. | Lands in Memory. *Known imperfection, not a blocker:* the person recorded is Sarah, not Mike. Note it, do not stop for it. |
| **C7** | "Sarah told Mike to call me" | **Memory**, note. Somebody else's action. | Lands in Today — that is the app inventing a task you were never given. |
| **C8** | "Remind me not to eat before the blood test" | **Today**, task, titled "**Don't** eat before the blood test". Goes to **Needs review** (a reminder was asked for with no resolvable time). | The title drops the negation and reads "Eat before the blood test". **Stop-ship** — inverted medical instruction. |
| **C9** | "Let me know if the meeting is Tuesday or Wednesday" | **Needs review**, and the row reads "**Time not settled**". Opening it prompts "Pick the day you meant" and marks the reminder field. No date, no alarm. | It says "Task or note?" — that is build 13's guess and means the new persisted reason is not reaching the UI. Also a blocker if it silently schedules Tuesday or Wednesday. |

**C9 is the one new user-visible behavior in this build.** Worth doing twice.

---

## D. Temporal

| # | Say (D5 is a tap, not a phrase) | Expect | Blocker if |
|---|---|---|---|
| **D1** | "Remind me to call the clinic on Friday at 9:30 am" | Today, reminder Friday 9:30 AM. Row shows the time. | Wrong day, wrong hour, or no time shown. |
| **D2** | "Pick up the parcel on Thursday" | Today, **day only** — no time of day shown anywhere, no hour in the row or the editor. | An invented hour appears in the row. |
| **D3** | "Remind me to take my vitamins every morning at 8" | Today, recurring, next occurrence tomorrow 8:00 AM (or today if before 8). | Fires immediately, or never schedules. |
| **D4** | "Remind me to call Mom at 5" then immediately "actually make that 6" | The reminder ends at **6:00**, one row, not two. | Two rows, or the time stays at 5. |
| **D5** | **Do not say this one — tap it.** Open the C9 row, turn on "Remind me" in the editor, set tomorrow 10 AM, tap Save. | It leaves Needs review, lands in Today with that alarm, and the asterisk clears. | It stays in Needs review after the field is answered. |

---

## E. System integration

| # | Action | Expect | Blocker if |
|---|---|---|---|
| **E1** | From B1/D1, wait for the notification to actually fire (set one 2 minutes out). | Notification arrives on time, with the action text — not the raw transcript. | Never arrives, or arrives at the wrong time. **Stop-ship** for a missed reminder. |
| **E2** | Lock the phone. Let a reminder fire. | Appears on the lock screen, readable, and opens the right item. | Nothing on the lock screen. |
| **E3** | Set Home in Places. Say "Remind me to bring in the mail when I get home". Leave and return home. | Before Home is set: the row says it is waiting on a place, and never claims to be scheduled. After: fires once on arrival. | It fires at the wrong place, fires twice for a one-shot, or claims to be armed while Home is unset. |
| **E4** | Places: set Home, force quit, relaunch, open Places. | Home still set, same address. | Home is gone after a relaunch. |
| **E5** | Deny microphone permission (Settings → Speak It → Microphone off), open capture. | A clear explanation and a route to Settings. No crash, no silent dead mic. | Crash, or a recording UI that appears to work and captures nothing. |
| **E6** | Re-enable microphone. Start a voice capture and **take a phone call** (or trigger an alarm) mid-recording. | Recording stops cleanly, words so far are preserved, and recovery is offered. | Words lost, or the app wedges in a recording state. |
| **E7** | Connect AirPods. Capture a sentence through them. | Transcribes at comparable quality; audio routes correctly; no stuck session after disconnect. | Silence, or the session never ends. |
| **E8** | Background the app mid-capture (home swipe), come back. | Capture either continues (audio background mode is enabled) or ends cleanly with words preserved. | Words lost. |
| **E9** | Back Tap: Settings → Accessibility → Touch → Back Tap → Double Tap → Shortcut → "Speak It Capture". Double-tap the back of the phone from the lock screen and from another app. | App opens straight into listening, from cold launch too. | Opens to the home screen without listening, or does not open. *Not a stop-ship* — it is a convenience path. |
| **E10** | Home-screen long-press → "Start speaking" and "Type a thought". | Both open directly into the right mode. | Either opens the wrong screen. |
| **E11** | Use up free captures to the paywall, then buy monthly in Sandbox. Then delete and reinstall and use **Restore**. | Pro unlocks; after reinstall Restore returns Pro without paying again. | Purchase does not unlock, or Restore fails. **Stop-ship** for a paid user losing access. |
| **E12** | On the paywall, check the prices shown. | Monthly $2.99, flat, with no struck-through regular price. Annual shows the sale price with $29.99 struck through, and says the offer — not the subscriber's rate — ends **October 22, 2026**. Annual is cheaper than twelve months of monthly. | The displayed price disagrees with what App Store Connect charges, monthly shows a discount, or annual costs more than twelve monthly payments while badged `BEST VALUE`. |

---

## Ship gate

Build 14 is ready to archive if:

- [ ] **A1–A4** all pass — especially A2, the upgrade.
- [ ] **C8** keeps the negation.
- [ ] **C9** says "Time not settled".
- [ ] **C3, C4, C5, C7** land in the destinations above.
- [ ] **E1** fires on time.
- [ ] **E11** purchase and restore both work.

Anything in the "Blocker if" column marked **stop-ship** stops the build.
Everything else: write it down, finish the sheet, and decide afterwards.

## Found during the build 14 run

- **A bare "set a reminder for <time>" titles the row after the time.** Said on
  its own it produces a row called "Tomorrow 10 AM"; joined with `and` it
  produces the placeholder "Your reminder". Both schedule correctly and both
  keep the original wording on the row, but neither title says what to do when
  the alarm fires.

  This is the `missingAction` semantic gap — "remind me about the thing, with
  nothing in it to do". The gap and its review copy ("Needs something to do")
  already exist and round-trip; nothing produces it yet, because
  `TemporalCommitment` is still the only producer of a non-resolved state. So
  this is the known coverage hole from Phase 2.1 surfacing in real use rather
  than a new defect. Not a beta blocker: the reminder you asked for exists, at
  the time you asked for, with your words intact.

## Known and accepted for this beta

- **Analytics is off.** `SPEAKIT_ANALYTICS_KEY` is empty in Release, so this
  build transmits nothing. If you want beta telemetry, inject the key at archive
  time: `xcodebuild ... SPEAKIT_ANALYTICS_KEY=phc_...`. Do not commit it.
- **The referral program is off.** `SPEAKIT_REFERRAL_API_URL` is empty, so those
  paths are inert rather than broken.
- **Do not install build 13 over build 14.** Build 14 moves the store to schema
  version 4 and build 13 cannot read it — it would fall back to empty in-memory
  storage and show the storage screen. Nothing is destroyed, and reinstalling
  build 14 recovers everything, but testers should be told to move forward only.
- **C6** records Sarah rather than Mike as the person. Known, not a blocker.
