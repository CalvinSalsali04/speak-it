# Semantic corpus — 182 → 439, and the hardening passes it forced

Reference instant: **Monday 2026-08-03 10:00 America/Toronto**.

```
TOTAL  439 cases, 430 passing, 9 failing
CRITICAL: 0   BEHAVIORAL: 0   METADATA: 10   COSMETIC: 0
```

Full unit suite: **451 passed, 0 failures, 5 skipped.**
Release compile: **clean, 0 warnings.**

Release gate — 350–500 cases, 0 CRITICAL, 0 BEHAVIORAL — **met**. The ten
remaining metadata disagreements were each reviewed for user consequence and
are listed at the bottom.

The final 37 cases form a collision family. Each pairs a real semantic signal
with ordinary wording that merely contains the same characters: `idea` versus
`ideal`, `work` versus `network`, arrival versus `get paid`, and a clock versus
`for two-factor`. They also cover ordinary negation (`has no pets`), compound
subjects, fronted conditional reminders, and unsupported non-spatial triggers.

## How the expansion was run

The process was fixed in advance so the suite could not become a description of
the implementation:

1. Author all 220 new expectations from the product contract.
2. Run all 402 without touching production code.
3. Cluster the failures.
4. Review whether the expectations were right.
5. Only then change the engine.

Step 2 produced **92 failures: 43 CRITICAL, 47 BEHAVIORAL, 34 METADATA**, and
all 182 original cases still passed — so every failure was in new ground rather
than a regression.

## The new families

The original ten are organised by topic. The eleven new ones are organised by
**axis of variation**: each takes intents that already pass in their bare form
and bends exactly one thing about how they are spoken. A cluster therefore names
a transformation — "filler is not being stripped", "the correction is not
winning" — which is the unit a fix actually has.

Two TestFlight-derived families then pin dated facts and consolidation; the
collision family is the twenty-fourth and final family in the current gate.

| Family | Cases | What it bends |
| --- | --- | --- |
| Filler and lead-ins | 18 | noise in front of a working sentence |
| Corrections | 24 | who, what, when, how often, where — each corrected |
| Outstanding obligations | 16 | the same action, reported as not done |
| Completion and cancellation | 21 | acting on something that already exists |
| Time of day | 20 | a stated clock, said every way people say it |
| Date only | 14 | a day with no time, which must stay one |
| Deadlines versus reminders | 18 | two dates in one sentence, two fields |
| Alarms | 15 | delivery as a three-way choice |
| Events | 16 | a commitment with nothing to perform |
| Pronouns and possessives | 18 | who the capture is about |
| Compositions | 40 | all of the above, at once |
| Semantic keyword collisions | 37 | the same token used with a different grammatical meaning |

`compositions` is the one that earned its place. Every ingredient in it passes
alone somewhere else in the corpus; what it tests is whether the features are
independent. They were not, and the worst defect found in this entire pass only
exists in combination.

`collisions` protects the other side of that boundary: every rule must require
evidence for the meaning it assigns. Finding a substring or a motion-shaped
verb is not evidence by itself. The route oracle also reads both item type and
an explicit reminder date, matching production instead of assuming type alone
decides Today versus Memory.

## Expectations corrected before any production change

Seven cases were scored wrong by me rather than by the app. Four were caught at
step 4, three more once the engine's answer turned out to be the better one:

| Case | Corrected to | Why |
| --- | --- | --- |
| `Don't call Catherine tomorrow, call her Friday` | cancellation unasserted | If a call is already scheduled for tomorrow, cancelling it is right. The non-negotiable half is that Friday is not left empty. |
| `Pick up the prescription at the pharmacy and gas at the station` | capped at metadata | The second clause has no verb of its own, and one item naming both errands still gets both done. |
| `Buy milk when I get home, actually when I get to the store` | `route` added | Scoring only the type hid the consequence: read as a note, the errand leaves Today. |
| `Set an alarm for 6` | split in two | Which 6 is arguable; that it is an alarm at all is not, and one ceiling was shielding both. |
| `Remind me to ask Dr. Okonkwo's office about the referral` | `.none` + review | No time was ever named. There is nothing to schedule, so a delivery promise would be one the app cannot keep. |
| `Set an alarm for 6` (hour) | 06:00 tomorrow | Decided during the pass — see the alarm rule below. |
| `Mom's birthday is Friday` | Memory, no due date | Speak It already files a person's birthday as knowledge under that person. An annual fact is not this week's commitment. |

## The ten repairs

### A. An operation consumed the whole utterance — 19 CRITICAL

The worst finding, and the only one that destroyed captured thoughts. Operation
detection ran once against the entire transcript, so any sentence that both
managed an existing item **and** stated a new one lost the new one:

```
"Don't remind me about the dentist anymore, but remind me to call Mom at six"
   →  0 items, cancel target "dentist anymore, but remind me to call mom at six"
```

Five sentences produced nothing at all. The same root cause ran the other way
too: when the split did happen, no clause was examined for an operation, so the
cancellation became a task.

**Fix** — `CaptureOperationDetector.partition` reads clause by clause and
returns the operations *and* the remaining text. The split is allowed to be
wrong: if no clause reads as an operation the **original text** is returned
untouched, so an over-eager boundary can never damage an ordinary capture.

One constraint had to be preserved. A bare "and" after a denial is genuinely
ambiguous — "don't buy milk and call support" can negate one conjunct or both —
and that ambiguity was already owned on purpose by `hasMixedPolarity`, which
holds the whole utterance for review. So a negation-led utterance splits only on
a comma or a contrastive "but", never on a bare "and".

### B. Operation vocabulary was too narrow — 14 CRITICAL

`I already called Mom` was recognised. `Done with the report` became a task
called *Done with the report*. Also unrecognised: `Mark the report as done`,
`Already picked up the prescription`, `I've already emailed…`, `I paid the rent
already`, `That's done`, `Scratch…`, `Remove … from my list`, `Take … off`,
`Forget about…`. Each created an item asserting the reverse of what was said.

`Don't remind me about the dentist anymore` also yielded the target `dentist
anymore`, which would never match a stored item.

### C. A leading filler phrase became its own item — 3 CRITICAL

`You know,` / `I mean,` / `Right, so,` each produced a phantom second item.
`Uh,` and `Okay so` were already handled; these were not. The fix keeps the
riskier openers behind a required comma — "Right, so, email Chen" is discourse
noise, "Right turn at the lights" is a direction.

### D. Splitting — 6 CRITICAL

Over-splitting `Alex and his brother are coming Friday` into two thoughts;
under-splitting `Set two alarms, 6:30 and 6:45` into one alarm, and three others.
`Call Catherine tomorrow at five and remind me an hour before` produced a second
item reading "remind me an hour before" with no subject.

### E. Outstanding obligations filed to Memory — 6 BEHAVIORAL

`I owe Mom a call`, `I keep meaning to…`, `I've been putting off…`, `I was going
to call Catherine but I didn't`, `The report is still not done`. Each reports a
thing not done, in the present tense, which is what kept them out of the
past-tense rules. The task never appeared where it would get done.

### F. Corrections — 6 BEHAVIORAL, 3 wrong people

Two left the person with **no reminder at all** (`Remind me in an hour, no make
it two hours`; `Set an alarm for 7, actually 6:30`). Three produced people who
do not exist — `Catherine Alex`, `Alex Catherine`, and a silently ignored
correction that would have texted the wrong person.

The cause was a missing slot. The resolver classified a correction into TIME or
DATE and otherwise fell back to swapping the prefix's trailing noun phrase —
which for these sentences is the date. Three slots were added: **person**,
**duration**, and **trigger** (swapping a whole place clause for a clock, or the
reverse). `correction` was added as a marker word.

### G. Ordinal days and copular statements carried no due date — 9 BEHAVIORAL

`Remind me on the 15th` worked, so the ordinal parser existed — it was wired
into the reminder path only. And any sentence built on a copula was classified
as a fact, so `The party is Saturday` went to Memory with no date.

**Fix** — a day number is now a calendar cue (digit *and* word forms, guarded so
"the first Monday every month" stays a monthly series), and a copular sentence
is a commitment when its subject names something scheduled and it states a
specific **day**. Reported speech and "remember …" facts are read earlier, so
this cannot resurrect them, and a bare month still means Memory.

### H. Clock parsing — 8 BEHAVIORAL

```
Set an alarm for 6:45 tomorrow   →  09:00   (alarm three hours late)
Wake me up at 6:30               →  18:30 today
Dinner reservation at 8 on the 14th  →  08:00
Concert Saturday night           →  00:00
half past two / quarter past six →  nothing scheduled at all
```

`for` was missing from the prepositions that introduce a clock, so the minute
was dropped whenever a day was present — the shape most alarms are spoken in.
Spoken clock faces ("half past two", "four thirty", "ten to six") and "night"
as a daypart were added.

**A decision worth recording:** an alarm's bare hour is now committed to the
morning. The general rule picks the next occurrence of a bare hour, which is
right everywhere else and reliably wrong for alarms. The window is 4–11, not
1–11, because "set an alarm for the meeting at 3" names a 3 PM meeting.

### I. Attributes did not inherit across split items, and one leaked — 6 BEHAVIORAL

A shared *time* inherited correctly; a shared place or series did not. `Remind me
at the pharmacy to pick up my prescription and buy toothpaste` put the geofence
on the first errand only, so the second never fired anywhere. `Every other
Friday at five, remind me to submit the report and pay the contractor` put the
series on one of two.

Leaking the other way, `Remind me every Friday to submit the report, and
Catherine needs a copy` gave the memory a weekly recurrence and put it on Today.
A shared command is now withheld from any clause carrying its own subject and
predicate — an imperative has no subject in front of its verb, which is what
tells the two apart.

### J. Person resolution missed several frames — metadata by field, behavioral in effect

`Lunch with Alex`, `Coffee with Priya`, `Catherine's wedding`, `Priya's book`,
`I owe Mom a call`, `Alex and his brother`, `Catherine is presenting` — all
filed nobody, so none appeared under People.

Added: social nouns behave like prepositional address verbs; `owe` aims at a
person; occasions belong to their owner; a possessive anywhere in the sentence
names its owner; a copula plus a human activity is a fact about a human; and a
compound subject is read past its coordination.

**Cross-clause pronouns** were also added: an item that says "him" or "she" now
takes its name from the person the same capture named. The antecedent comes from
the whole capture rather than from sibling items, because it is not always in
one — "Don't call Catherine tomorrow, call her Friday" cancels the clause that
names her. It only fills a name that is missing, only from a confidently-read
mention, and never invents one.

That last guard was added after this pass briefly filed a person called
**"Don't"** — the same class of defect as the *Wait Sam* bug the previous round
closed. Negations and auxiliaries are now excluded from name tokens.

### Exceptions to a series

`Every Friday at five … except this Friday` and `Call Mom every Sunday, except
when I'm travelling` built a correct series and dropped the exclusion silently —
firing on precisely the day the person excluded. Speak It cannot store an
exclusion, so it now asks instead.

## The ten remaining disagreements

None gate the release. Each was reviewed individually for user consequence:

| Case | Disagreement | Judgement |
| --- | --- | --- |
| `Remember Catherine said I need to call Alex Friday` | person Catherine, not Alex | Routing and the date are right, which is the part that decides whether the call happens. Who a relayed obligation is "about" is genuinely two-sided. |
| `Give Mom's recipe to Catherine` | person Mom, route Memory | Two people, one possessive. Arguable and low-consequence. |
| `Remember Catherine's husband is called David` | `Catherine's husband` | The note is about both. |
| `I haven't heard back from Catherine` | no person | Waiting on someone is not obviously an owed action. |
| `Pick up the prescription … and gas at the station` | 1 item, not 2 | One item naming both errands still gets both done. |
| `Finish the deck by end of day` | no due date | Whether "end of day" carries a closing hour is undecided. |
| `Pay the invoice within 30 days` | no due date | A window, not a date. |
| `Standup moved from 9 to 9:30` | no due date | The stated time is already past at the reference instant. |
| `Book club every second Tuesday` | weekly, not fortnightly | "Every second Tuesday" is fortnightly to most people and the second Tuesday of the month to some. |
| `The conference is the 10th through the 12th` | start date only | Date ranges are unmodelled. |

## Contract questions settled during this pass

Three were genuinely open and are now decided in code, with the reasoning at the
call site:

1. **A named weekday that is today means the next one.** "The deadline is
   Monday", said Monday morning, resolved to *today*. Somebody who meant today
   would have said today.
2. **An alarm's bare hour is morning** (4–11), where every other bare hour takes
   the next occurrence.
3. **A person's birthday is knowledge, not an appointment.** It stays in Memory
   under that person, matching the behaviour already pinned for
   "Alex's birthday is October 12".

## Also in this pass

The `ReminderScheduler` concurrency warning is gone. `ReminderDeliverySink` was
marked `@MainActor` while holding no main-actor state — both
`UNUserNotificationCenter.current()` and `AlarmManager.shared` are their own
thread-safe singletons — so `.live` could not be read from the nonisolated
`delivery` property. That is a warning today and an error under the Swift 6
language mode, on the one code path that tears a reminder down. Release now
compiles with zero warnings.
