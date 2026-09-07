# Gamification proposal — a calm habit loop for Speak It

Status: 2026-09-08. Phases 1 and 2 are built and then trimmed the same day
(`ActivityLedger`, `HabitNotificationScheduler`, `WeekRowView`, the Today and
Reminder check changes); the decision and the trim are recorded in
`Docs/DECISIONS.md`. What shipped is leaner than the text below: dots only on
the eyebrow line with no summary line and no "kept up" count, captures and
completions only (reviewing Today does not fill a dot), no offer on Today at
all (the brief is a switch under Capture & reminders, beside the default
reminder time), no weekly nudge, and the brief's settings in `HabitDefaults`
rather than `UserPreferences`. Phases 3 and 4 remain proposals.

## Recommendation in one paragraph

Do not copy Duolingo. Copy the two things that make Duolingo work — a reward
at the exact moment of the action, and one honest number that says "you are
keeping this up" — and refuse the rest: leagues, XP, hearts, mascots, guilt
notifications, badge shelves, and a daily streak that dies when you miss a
day. Speak It's promise is calm and "nothing you say is lost"; a streak that
punishes silence contradicts the product it is decorating. The proposal is four
small pieces, none needing a schema migration, shipped in order: (1) an
"all clear" state on Today and a completion reward that already half exists;
(2) a seven-dot **This week** row on Today that counts active days without ever
being "lost"; (3) one useful, opt-in **morning brief** notification that is
technically and visibly different from reminders; (4) quiet one-time
milestones on the save receipt and a Memory count. Everything is derived from
data the store already holds, so it can never drift from the truth.

## Why not Duolingo's version

Duolingo's numbers are real: it reports 55% of daily actives retained
month-over-month, more than three million users on 365-day-plus streaks, and a
10% lift in long-term retention from the Streak Freeze alone
([Propel](https://www.trypropel.ai/resources/blogs/duolingo-customer-retention-strategy),
[Deconstructor of Fun](https://duolingo.deconstructoroffun.com/mechanics/streaks)).
Its reminder engine fires 23.5 hours after the last session and escalates
emotional pressure after three idle days
([Digia](https://www.digia.tech/post/duolingo-habit-forming-reminders-retention-architecture/)).
The famous "these reminders don't seem to be working, we'll stop for now"
message is widely reported as one of its best performers precisely because it
withdraws pressure.

Three facts about Speak It make the daily-streak version wrong here:

1. **The lesson is the product at Duolingo; the capture is not the product
   here.** People learn by doing a lesson every day. Nobody has a thought
   worth keeping every day on schedule. A daily-capture goal manufactures
   junk captures, and junk captures poison Today, Memory, and the corpus.
2. **The free plan is ten captures for life.** A daily-capture streak walks a
   free user into the wall in ten days and then punishes them for the wall.
   The active-day definition below deliberately counts finishing and reviewing,
   not only capturing, so a free user at the limit can still "keep it up".
3. **Rigid streaks lose the people they were meant to keep.** Secondary
   sources summarising a 2020 CHI study report streak anxiety as the top reason
   people abandon habit apps and a large jump in quitting after a single missed
   day ([EHM](https://www.ehm-tech.com/habit/blog/habit-streaks-do-they-actually-work/),
   [Cohorty](https://blog.cohorty.app/the-psychology-of-streaks-why-they-work-and-when-they-backfire/)).
   Duolingo answers this with purchasable freezes and a gem economy. Speak It
   answers it by never having a streak that can break.

### Copied, adapted, refused

| Duolingo mechanic | Speak It | Why |
| --- | --- | --- |
| Reward at the moment of action (chime, animation) | **Keep.** Save haptic and `SavedCaptureSeal` already exist. Add the completion reward. | Immediate, intrinsic, no new state. |
| Daily streak counter | **Adapt** to a seven-dot week with no loss state, and an optional "weeks kept up" count. | Forgiving by construction; nothing to freeze. |
| Streak Freeze / gems | **Refuse.** | Only needed to soften a mechanic we are not shipping. |
| Practice reminder at last-session time | **Adapt** into a morning brief with real content, at a time the user picks. | Useful beats nagging; the preference field already exists. |
| "Reminders don't seem to be working" auto-stop | **Keep** the behaviour, quieter copy. | Self-limiting nudges are the calm version. |
| Streak-at-risk / Duo-is-sad notifications | **Refuse.** | Guilt is the opposite of calm. |
| XP, leagues, leaderboards, friends | **Refuse.** | Needs a server and social graph; contradicts local-first. |
| Hearts / limited attempts | **Refuse.** | The ten-capture allowance already is the scarcity; do not add a second one. |
| Badge shelf / achievements tab | **Adapt** to one line on the receipt, once, and a count in Memory. | No new screen, no controls. |
| Daily quests | **Refuse.** | Adds a to-do list to a to-do app. |

## Principles

- **Reward outcomes, not opens.** Every signal below fires on something the
  person actually wanted: a thought kept, a task finished, a day reviewed.
  Opening the app is never itself rewarded.
- **Nothing is ever lost.** No counter goes to zero because of silence. The
  week row simply shows fewer dots; the weeks count pauses rather than resets.
- **One number per surface.** Today gets the week row. Memory gets the
  thoughts-kept count. The receipt gets a milestone line. Nothing gets two.
- **Derived, never stored.** Active days, counts, and milestones come from
  `CaptureSession.createdAt`, `CapturedItem.completedAt`, and a
  last-reviewed date. Like the tutorial counter decision, one number computed
  in one place cannot disagree with the data.
- **Free and Pro see the same mechanics.** Pro is never sold as "more
  gamification". The mechanics are honest for both; the free wall is the free
  wall.
- **Everything is off-able, and the loud parts start off.** The week row is
  visual and quiet, so it ships on. Notifications ship off and are offered
  once.

## The mechanics

### 1. All clear, and the completion reward

Today already has completed sections and a haptic on save. Two additions:

- **Completion haptic** on task check-off (`.success` on the last open item,
  `.light` otherwise), gated by Reduce Motion like the seal.
- **All clear state.** When Now and Today hold no open items, the empty area
  reads one calm line: "All clear for today." plus the week row. This is the
  Things and Todoist zero-inbox pattern; it is the most restrained reward
  there is because it is the absence of work.

No new state, no new controls.

### 2. The week row

Seven small dots under the Today header, Monday to Sunday in the user's
calendar, today's dot outlined. A filled dot is an **active day**:

- a capture was saved (`CaptureSession.createdAt` on that day, any source), or
- a task was completed (`CapturedItem.completedAt` on that day), or
- Today was reviewed (the app was foregrounded on Today; stored as a single
  last-reviewed date in the app-group defaults, next to `ReminderDefaults`).

Reviewing counts because a person who opens Today, sees nothing to do, and
closes it *did* the thing the app is for. It also means a free user at the
wall keeps earning dots by using what they captured.

Below the dots, one line, and only when it is true:

- "4 active days this week"
- "Kept up 6 weeks" — a week is kept up at **three or more** active days.
  This is the only streak-like number, it advances once a week, and a thin
  week pauses it rather than resetting it to zero. Copy never says "lost" or
  "broken".

Tap target: the row is not a button. Nothing to tap, nothing to configure.
It is hidden until the second active day ever, so a first-time user sees no
scoreboard before they have done anything.

Accessibility: the row exposes one label, "This week: four active days, kept
up six weeks," and is otherwise decorative.

### 3. Milestones

Quiet, one-time, on the save receipt where the seal already plays:

- Thoughts kept: 10, 50, 100, 250, 500, 1,000 — "Your 100th thought kept."
- Tasks finished: 25, 100, 500 — shown on the All clear line once.

Shown once, then recorded in app-group defaults as "shown"; never a shelf,
never a share sheet. Memory's header gains a single count, "213 thoughts
since March", which is both the collection stat and the most honest Pro value
statement the app has. The paywall's `runningLow` context may reuse the same
number ("You've kept 8 thoughts here") in place of a generic pitch.

### 4. Notifications — two classes that must not blur

Speak It already sends **product notifications**: reminders the person asked
for, plus the Live Activity slot. Everything in this proposal is a second
class, **habit notifications**, and the difference must be visible in code,
in settings, and on the Lock Screen.

| | Product (existing reminders) | Habit (new) |
| --- | --- | --- |
| Why it exists | The person said "remind me" | The app thinks it would help |
| Opt-in | Notification permission | Permission **and** its own toggle, default off |
| Interruption level | `.timeSensitive` (breaks Focus) | `.passive` (no sound, no wake, flows into Scheduled Summary) |
| `threadIdentifier` | `speak-it-reminders` | `speak-it-habit` |
| Identifier prefix | `SpeakIt.reminder.` | `SpeakIt.habit.` |
| Category / actions | Done, Snooze | none (tap opens Today) |
| Cadence | when due | at most one per day, at a chosen time |
| Contains user text | yes, the task | counts only, never transcript text |
| Auto-stop | never | after 5 unopened in a row |
| Counted in Settings "pending" | yes | shown on its own line |

Apple defines Passive as "does not require immediate attention" and reserves
Time Sensitive for urgent user attention that may break Focus
([WWDC21](https://developer.apple.com/videos/play/wwdc2021/10091/),
[HIG](https://developer.apple.com/design/human-interface-guidelines/managing-notifications)).
Using `.passive` is the technical line between "you asked" and "we suggest".
It also means a habit notification never competes with a reminder on the Lock
Screen and never punches through a Focus the person set.

**The morning brief.** `UserPreferences` already carries
`morningBriefingEnabled` and `morningBriefingTime`, unused since v1; the
backlog lists "morning notification" as Later. This is that feature, and it is
the only habit notification worth building first because it is useful before
it is motivating:

- "2 due today, 1 overdue." — tap opens Today.
- "Nothing due today." is **not** sent. Silence is the calm state.
- At most once a week, if there was no capture in seven days and nothing is
  due: "Nothing waiting. Anything on your mind?" This is the one nudge, and
  it is the one that stops itself.

Scheduling reality: local notifications carry fixed content, so the brief is
scheduled for the next **three** mornings each time the app or share
extension goes to the background, from the store as it is then. Counts are
computable in advance from `dueDate`, and the only thing that changes them
(completion) happens in-app and reschedules. Three slots keep well inside the
64 pending-request limit that reminders share. `RootView`'s self-healing
pass filters by the `SpeakIt.habit.` prefix and removes anything stale.

**Weekly summary (later).** Sunday evening, passive: "This week: 12 thoughts
kept, 9 done." Same toggle, same thread. Ships only if the brief earns its
keep.

**Where it is offered.** Not in onboarding; the permission budget is spent on
speech and reminders there. Offer once, inline on Today, after the third
active day: "Want a short brief each morning?" with Yes / Not now. Not now is
final until Settings. The existing Notifications settings screen gains a
"Morning brief" section with the toggle and the time.

## The free plan

- The week row and milestones never say "capture every day". Copy on Today
  speaks of active days, not captures.
- At the wall, completions and reviews still fill dots, so the row does not
  become a second paywall.
- The 10-thoughts milestone coincides with the wall. Do **not** fire it there;
  the paywall already owns that moment. Milestones start at 50, which is by
  construction Pro-only, and read as a gift rather than a limit.
- The morning brief works for free users; it never mentions remaining
  captures.

## Data, code, and cost

No schema migration. New state lives in app-group defaults (like
`ReminderDefaults` and `SavedPlaceStore`) because the share extension must
also refresh the brief:

- `lastReviewedDay: Date` (start of day, calendar-local).
- `milestonesShown: [String]`.
- `habitBriefUnopenedCount: Int`, `habitBriefOfferShown: Bool`.
- `morningBriefingEnabled` / `morningBriefingTime` stay where they are in
  `UserPreferences`, since they already migrated through every schema.

One new repository-layer type, `ActivityLedger` (in `SpeakIt/Repositories/`),
exposes `activeDays(in: week)`, `weeksKeptUp()`, `thoughtsKept()`, and
`milestone(after save:)`. It queries two dates ranges with `#Predicate` and a
fetch limit; the count queries use `fetchCount`. Nothing runs on the main
thread beyond reading the cached result, and the row re-computes only on
save, completion, foreground, and day change (`NSCalendarDayChanged`).

One new scheduler type, `HabitNotificationScheduler`, beside
`ReminderScheduler`, owns the prefix, thread, `.passive` level, the three-day
window, and the auto-stop counter. `NotificationPresentationDelegate`
increments the unopened counter on delivery and clears it on tap.

Estimated effort, in the order to ship:

| Phase | Scope | Effort |
| --- | --- | --- |
| 1 | Completion haptic, All clear line, week row, `ActivityLedger` + tests | one focused day |
| 2 | Morning brief: scheduler, settings section, inline offer, self-heal, tests in the machine's zone | one to two days |
| 3 | Milestones on receipt, Memory count, paywall number | half a day |
| 4 | Weekly summary | half a day, only after measuring 2 |

## Analytics (closed vocabulary only)

Add to `SpeakItAnalyticsEvent`, all content-free:

- `weekRowShown(activeDays: Int)` — integer 0–7, fired once per day at most.
- `weekKeptUp(weeks: AnalyticsCountBucket)` — bucketed 1, 2–4, 5–12, 13+.
- `milestoneShown(kind: thoughts|tasks, tier: Int)`.
- `habitBriefOffered`, `habitBriefEnabled(source: offer|settings)`,
  `habitBriefDisabled(source: settings|autoStop)`, `habitBriefOpened`.

Update `PrivacyInfo.xcprivacy` tests only if a new data category appears; none
does. Counts are not user content.

## Success and stop conditions

Measure with events that already exist plus the ones above:

- **Keep shipping if** the four-week return rate (`app_opened` per install)
  rises, the share of active days that are completion-or-review-only stays
  material (proof the row is not just a capture counter), and
  `habitBriefDisabled(autoStop)` stays under a quarter of enables.
- **Roll back the brief if** disables exceed enables within two weeks, or
  `capture_saved` with `itemCount == 0` or high `needsReviewCount` rises after
  launch (junk captures made to fill a dot).
- **Never A/B the copy toward pressure.** The Duolingo bandit optimises for
  opens; ours must optimise for the person not turning it off.

## What was deliberately not proposed

- A Home Screen widget with the dots. There is no widget target today, and
  the Lock Screen slot lists tasks; a scoreboard there would compete with the
  work.
- Sounds. The save haptic is the sound.
- Sharing a streak. There is nothing to share, which is the point.
- Server-side anything. All of this runs from the local store and Keychain,
  and survives with the same guarantees the captures have.

## Open decisions for Calvin

1. Three active days for a "kept up" week, or four? Three is forgiving for
   people who capture at work only; four is closer to a real habit.
2. Does the week row live in the Today header or under the All clear line
   only? Header is always visible; under All clear rewards finishing.
3. Morning brief default time: reuse the new **Default reminder time**
   preference, or its own time? Recommendation: its own, because a 6 PM
   reminder default should not move the brief to the evening.

## Sources

- [Duolingo's Customer Retention Strategy — Propel](https://www.trypropel.ai/resources/blogs/duolingo-customer-retention-strategy)
- [Duolingo Streaks — Deconstructor of Fun](https://duolingo.deconstructoroffun.com/mechanics/streaks)
- [Duolingo's Habit-Forming Reminders — Digia](https://www.digia.tech/post/duolingo-habit-forming-reminders-retention-architecture/)
- [How Duolingo's Streak Mechanic Actually Works — Apptitude](https://apptitude.io/blog/how-duolingos-streak-mechanic-actually-works/)
- [Send communication and Time Sensitive notifications — WWDC21](https://developer.apple.com/videos/play/wwdc2021/10091/)
- [Managing notifications — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/managing-notifications)
- [Notifications — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/notifications)
- [Habit Streaks: Why They Work and When They Backfire — EHM](https://www.ehm-tech.com/habit/blog/habit-streaks-do-they-actually-work/)
- [The Psychology of Streaks — Cohorty](https://blog.cohorty.app/the-psychology-of-streaks-why-they-work-and-when-they-backfire/)
- [Streak Anxiety From Fitness Apps — OgamicX](https://ogamic.com/blog/streak-anxiety-from-fitness-apps)
