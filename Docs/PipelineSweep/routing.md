# Lane: routing — destination, item type, category, priority, needsReview

**Instrument:** `frozen/probe`, reference Monday 2026-08-03 10:00 America/Toronto.
**Volume:** 626 distinct utterances across 14 files (`scratchpad/routing/A..N*.txt`, combined `ALL.txt`).
**Raw output:** `scratchpad/routing/ALL.out`, one-line-per-row digest `scratchpad/routing/ALL.tsv`.

**Headline numbers**

| measure | value |
| --- | --- |
| utterances probed | 626 |
| rows produced | 646 (44 of them are 2nd/3rd rows from splitting) |
| captures that produced **no row at all** (swallowed as a cancel op) | 24 |
| rows flagged `needsReview` | 66 (10.2%) |
| rows whose title was replaced by the placeholder **"Review captured thought"** | 29 |
| rows with category `general` | 414 / 646 = **64%** |
| rows with priority ≠ normal | 39 (31 high, 8 urgent) |

The lane is **not clean**. Destination is wrong often enough that a normal week of
journal-and-facts captures would visibly leak onto Today, and a normal week of
errands would visibly leak into Memory. Almost all of it collapses into **11 root
causes**, ranked below by user-visible impact.

---

## R1 — `.event` is assigned by keyword scan and `.event` is unconditionally a Today row

**Mechanism.** `ThoughtOrganizer.inferredType` line 564:

```swift
if containsPhrases(text, ["appointment", "meeting", "dinner at", "event on", "reservation at"]) {
    return .event
}
```

There is no tense check, no copula check, no date requirement. `ItemType.event.isActionable == true`
(`DomainEnums.swift:528`), so **any** sentence containing the word "meeting" or
"appointment" — a memory, an opinion, a reference note, a complaint — becomes a Today row
in the Events category. `ActionabilityReader` only vetoes this when it independently
returns `.knowledge`, and a copular sentence with no `completedVerb` returns `.ambiguous`,
which by design cannot demote a type.

**Hits:** 12 utterances. **Severity: BEHAVIORAL**, one CRITICAL (fabricated due date).

| utterance | observed | expected |
| --- | --- | --- |
| `the meeting was actually useful for once` | Today / event / events / p1 / **REVIEW** | Memory / note |
| `my first appointment with the new therapist went okay` | Today / event / events | Memory / note (past tense) |
| `the meeting notes are in the shared drive under Q3` | Today / event / events | Memory / note / work — reference |
| `i think the best meeting we ever had was the offsite` | Today / event / events | Memory / note |
| `the dinner at Ana's was lovely` | Today / event / events | Memory / note / people |
| `the standing meeting got cancelled` | Today / event / events | Memory / note |
| `a meeting with the accountant would probably help` | Today / event / events | Memory / idea |
| `Marcus is the one who runs the Monday meeting` | Today / event / **due=Mon Aug 10** | Memory / note / people, no date — **CRITICAL, invented due date** |
| `set up a meeting with Priya` | Today / event / events | Today / **task** (arranging a meeting is an errand, not the meeting) |
| `that appointment reminder text is annoying` | 2 rows; #1 Today/event, #2 Today/personFollowUp+REVIEW | 1 Memory note |
| `her appointment book is always full` | 2 rows; #1 Today/event | 1 Memory note |
| `i need to move the appointment to next week` | Today / **event** / REVIEW, due=nil | Today / **task** (rescheduling is work to do) |

Contrast that holds correctly: `i hate how many meetings we have` → Memory/note (the
splitter happens to leave "meetings" plural, which the phrase matcher misses). That
near-miss is itself evidence the rule is lexical rather than semantic.

---

## R2 — `isCalendarCommitment` is the last resort, so a bare date/clock word with no recognised verb becomes a dated Today event

**Mechanism.** `Actionability.read` (`Actionability.swift:267`) falls through to
`isCalendarCommitment` (line 462). That function returns `true` for any text matching
`calendarCue` — which includes `today`, `tonight`, `tomorrow`, weekday names, month names,
spoken clock faces, and `dayOfMonthCue` = `\bthe\s+(?:\d{1,2}(?:st|nd|rd|th)|first|second|third…)\b` —
provided no copula-plus-non-scheduled-noun and no `actionVerb`/`completedVerb` is present.
The type is then promoted to `.event` at `ThoughtOrganizer.swift:252`, and the temporal
parser resolves the cue into a real due date.

This is why **journal entries acquire due dates**. It is the single most alarming family
in this lane, because a person's diary lands in Today's schedule.

**Hits:** 11. **Severity: CRITICAL** (fabricated due dates) for the dated ones.

| utterance | observed | expected |
| --- | --- | --- |
| `i felt weirdly calm walking home tonight` | Today / event / p2 / **due=Mon Aug 3 20:00** | Memory / note, no date |
| `lonely tonight for no particular reason` | Today / event / p2 / **due=Mon Aug 3 20:00** | Memory / note |
| `happy in a small ordinary way today` | Today / event / p2 / **due=Mon Aug 3** | Memory / note |
| `i keep waking up at four` | Today / event / p2 / **due=Mon Aug 3 16:00** | Memory / note (and it means 4 a.m.) |
| `something about today just felt lighter` | Today / event / p2 | Memory / note |
| `that quote about the second best time to plant a tree` | Today / event / **due=Wed Sep 2** | Memory / note — "the second" read as a day of month |
| `the second hand shop takes clothes only on Tuesdays` | Today / event / **due=Wed Sep 2** | Memory / note — same "the second" trap |
| `Ana wished me happy birthday at midnight` | Today / event / p2 / **due=Tue Aug 4** | Memory / note / people (past) |
| `the tax slip usually comes in late February` | Today / event / events | Memory / note |
| `how many people are coming Saturday` | Today / event / **due=Sat Aug 8** | Memory / note (a question) |
| `the thing i keep forgetting is that the pharmacy closes at seven not eight` | Today / task / **due=Mon Aug 3 19:00** | Memory / note — opening hours, not a 7 p.m. task |

`the recipe is in the green book on the second shelf` is *correctly* Memory only because
its copula plus non-scheduled noun catches it first — the guard is accidental, not aimed
at the ordinal.

---

## R3 — `ClauseJuxtaposition.pieces` splits at any verb-homograph noun, inventing rows and Today tasks

**Mechanism.** `SpeechRepair.swift:965` `instructionOpeners` contains `water, meet, book,
text, order, call, take, check, charge, file, sign, visit, put, get, move, add, make`…
`pieces(in:)` (line 1024) cuts before any of those words unless the preceding word is in
`clauseInternalLead` (line 972). That set covers determiners, pronouns, prepositions and
auxiliaries but not ordinary nouns or adjectives, so **"less water", "swim meet",
"appointment book", "reminder text", "him get"** are all read as clause boundaries.

**Hits:** 44 multi-row utterances, of which ~25 are spurious. **Severity: CRITICAL** where
a phantom Today task or a mangled quote results.

| utterance | observed | expected |
| --- | --- | --- |
| `the plant on the windowsill needs less water than i thought` | 2 rows: "The plant on the windowsill needs less" (Memory) + **"Water than I thought" (Today/task)** | 1 Memory note |
| `it's hard watching him get older` | 2 rows: "It's hard watching him" + **"Get older" → Today/shopping/list=Other** | 1 Memory note |
| `the swim meet is Saturday morning` | 2 rows: "The swim" + "Meet is Saturday morning" (Today/task, due Sat) | 1 Today event, due Sat morning |
| `why does the car make that noise on cold mornings` | 2 rows: "Why does the car" + **"Make that noise on cold mornings" (Today/task)** | 1 Memory note |
| `we're meeting Ana and Marcus at the restaurant at seven thirty on Friday` | 2 event rows; **#1 has no due date at all** | 1 event, Fri Aug 7 19:30 |
| `so we're in row twelve seats a and b and the gate is c forty two` | "We're in row twelve seats a" + "B and the gate is c forty two" | 1 reference note |
| `supposing we did move would the kids be okay` | "Supposing we did" + **"Move would the kids be okay" (Today/task)** | 1 Memory note |
| `that was an urgent care visit not the er` | "That was an urgent care" (p3 **urgent**) + "Visit not the" (Today/task) | 1 Memory note, normal priority |

Splitting on a real `and` between two real actions works well (`i need to buy dog food and
call the vet` → correct two rows). The failure is exclusively the no-conjunction
juxtaposition path.

---

## R4 — `IntentConsolidation` blanks the title and forces `unclear` + `needsReview` on ordinary conversational speech

**Mechanism.** `IntentConsolidation.consolidate` (`IntentConsolidation.swift:119-160`).
When no clause is "substantive" and any `elaborativeMarker` (line 59) matches, the whole
capture becomes `Consolidation(title: "Review captured thought", requiresReview: true)`.
`ThoughtExtractor.swift:243-255` then overwrites the organization with
`itemType: .unclear, category: .general, needsClarification: true`.

`elaborativeMarker` includes `for a while`, `for ages`, `forever`, `kind of`, `sort of`,
`kinda`, `honestly`, `basically`, `i mean`, `to be honest`, `the whole thing`,
`that's why`, `i keep thinking`, `i was thinking`, `i've been putting`, `i always forget`,
`even though`. These are not rambling markers — they are how people talk.

**Hits:** 29 rows (4.6% of all rows). 17/30 in the dedicated probe file `K-elaborative.txt`.
**Severity: BEHAVIORAL** (the quote survives, but the row title the user sees is a
placeholder, the item lands in `unclear`, and it is pushed onto Today — see R11).

| utterance | observed title / type | expected |
| --- | --- | --- |
| `the market's been flat for a while` | "Review captured thought" / unclear / REVIEW | Memory / note, own wording |
| `Sam thinks the market's going to be flat for a while` | "Review captured thought" / unclear / REVIEW | Memory / note / people |
| `honestly i'm just glad it's over` | "Review captured thought" / unclear / REVIEW | Memory / note |
| `i keep thinking about the house we saw` | "Review captured thought" / unclear / REVIEW | Memory / note |
| `kind of amazing that it still works` | "Review captured thought" / unclear / REVIEW | Memory / note |
| `we've had that fridge forever` | "Review captured thought" / unclear / REVIEW | Memory / note |
| `even though it rained the day was good` | "Review captured thought" / unclear / REVIEW | Memory / note |
| `i don't know why i'm so anxious lately` | "Review captured thought" (via `shouldKeepAsOneSafetyItem` negation branch) / REVIEW | Memory / note |
| `i mean it's fine it's just not what i expected` | "Review captured thought" / unclear / REVIEW | Memory / note |
| `i keep thinking about that conversation with my dad` | "Review captured thought" / unclear / REVIEW | Memory / note / people |
| `we returned the sofa because it didn't fit` | "Review captured thought" / unclear / REVIEW | Memory / note |
| `I didn't call Catherine because she cancelled` | "Review captured thought" / unclear / REVIEW | Memory / note — this is the exact sentence `Actionability.isExplainedPast` documents as a knowledge win, and consolidation undoes the presentation of it |

---

## R5 — `obligationLead` promotes musings, aspirations and hypotheticals to Today tasks; no hedge vocabulary is read

**Mechanism.** `Actionability.hasObligationLead` (line 445) matches `obligationLead`
(line 86: `should`, `want to`, `wanna`, `ought to`, `need to`, `have to`, `gotta`, `must`)
**anywhere in the sentence**, and returns `.actionable`. Nothing looks for hedges —
`someday`, `eventually`, `at some point`, `one of these days`, `more often`, `i wonder if`,
`i think i want to` — and nothing checks who the subject is.

The result is arbitrary from the user's point of view, because the *near-identical*
sentence framed with `would be nice to` correctly stays in Memory (`readsLikeIdeaProposal`).

**Hits:** ~15. **Severity: BEHAVIORAL.**

| utterance | observed | expected |
| --- | --- | --- |
| `someday i want to learn piano` | Today / task | Memory (idea) — or Today "when you have time", but it must match the next row |
| `it would be nice to visit Nan` | Memory / idea / ideas | — same shape as the row above, opposite destination |
| `eventually i want to redo the bathroom` | Today / task | Memory / idea |
| `we should probably eat out less` | Today / task | Memory / note (a resolution, not an errand) |
| `we should call my parents more often` | Today / task | Memory / note |
| `i wonder if we should just replace the whole fence` | Today / task | Memory / idea |
| `i really ought to see the doctor about my knee at some point` | Today / task | Memory, or Today with no date — but "at some point" is ignored entirely |
| `i think i want to switch banks eventually` | Today / task | Memory / idea |
| `my sister thinks we should all go together next year` | Today / task | Memory / note / people |
| `should i be worried about the mole on my arm` | Today / task | Memory / note (a question) |
| `sort of a strange day` | **Today / task** | Memory / note |
| `kinda want to move somewhere warmer` | Today / task, person=**"Kinda"** | Memory / idea |
| `maybe we should get the kids into music lessons` | Memory / idea | vs `we should get a quote for the driveway` → Today / task — the only difference is the word "maybe" |

Related sub-case: the *inverse* miss. `we're supposed to bring a salad on Saturday` →
**Memory / note, date discarded**, because `obligationLead` contains `am supposed to` and
`'m supposed to` but not `(?:we|they)['’]re supposed to`.

---

## R6 — the closed `actionVerb` vocabulary drops real errands into Memory

**Mechanism.** `Actionability.actionVerb` (line 70) is a fixed list. `hasActionVerbHead`
only fires when the *body* starts with one of them. A bare imperative whose verb is not in
the list gets `.ambiguous` → `.note` → Memory. The user sees an errand filed as a fact.

**Hits:** 12. **Severity: BEHAVIORAL** (a task that will never appear on Today).

| utterance | observed | expected |
| --- | --- | --- |
| `fill out the form` | Memory / note | Today / task |
| `fill out the school forms for Nadia` | Memory / note / school | Today / task |
| `fill in the application` | Memory / note | Today / task |
| `look into the warranty` | Memory / note | Today / task |
| `figure out the childcare` | Memory / note | Today / task |
| `deal with the parking ticket` | Memory / note | Today / task |
| `change the furnace filter` | Memory / note | Today / task |
| `ping the team about the launch` | Memory / note / work | Today / task |
| `let Ana know we're running late` | Memory / note | Today / personFollowUp — time-critical |
| `give her a call back` | Memory / note | Today / personFollowUp |
| `reach out to the accountant` | Memory / note | Today / task |
| `asap call the hospital` | Memory / note / **p3 urgent** | Today / task — see R9 |

Compare `sort out the insurance` → Today / task (only because `sort` is in the list) and
`i need to sort out the insurance renewal` → Today. The gate is purely lexical.

---

## R7 — `^(get|grab|pick up) + non-determiner` sends people and abstractions to the grocery list

**Mechanism.** `ThoughtOrganizer.swift:512-517`:

```swift
if text.range(of: #"^(?:get|grab|pick\s+up)\s+(?:\d+\s+)?(?!the\b|a\b|an\b|my\b|his\b|her\b|our\b|their\b|that\b|this\b)\w"#, …) != nil {
    return .shopping
}
```

A proper noun or an adverb after the verb passes the negative lookahead, so the item
becomes `.shopping`, lands in the Shopping category, and is assigned a list.

**Hits:** 8. **Severity: BEHAVIORAL**, and unusually embarrassing in a demo.

| utterance | observed | expected |
| --- | --- | --- |
| `pick up Nadia at four` | Today / **shopping** / list=Other / due 16:00 | Today / task |
| `pick up Marcus from the airport at six` | Today / **shopping** / list=Other | Today / task |
| `grab Nadia from daycare` | Today / **shopping** / list=Other | Today / task |
| `get Ana at the station` | Today / **shopping** / list=Other | Today / task |
| `pick up Priya at noon` | Today / **shopping** / list=Other | Today / task |
| `get better at saying no` | Today / **shopping** / list=Other | Memory / note |
| `get back to Priya about the quote` | Today / **shopping** / list=Other, person=Priya | Today / personFollowUp |
| `order of operations matters here` | Today / **shopping** / list=Other | Memory / note |
| `i really should get around to fixing that door` | Today / **shopping** / list=Other | Today / task |
| `it's hard watching him get older` #2 | Today / **shopping** / list=Other ("Get older") | (row should not exist — R3) |

`pick up my sister Friday` → Today / task, correctly, because `my` is in the lookahead.

Adjacent gap in the same area: **`add X to the list` is not recognised as a shopping
command.** `add batteries to the list` and `add eggs to the list` both come out
Today / task / general, while `put paper towels on the shopping list` correctly becomes
shopping. And `we need eggs milk and something for dinner` stays a single **Memory note**,
because `ShoppingGroupParser.namesOnlyProducts` requires *every* significant word to be a
known product — one vague item ("something for dinner") demotes the whole list.

---

## R8 — copular commitments lose their date when the noun is not in `scheduledNoun`

**Mechanism.** `Actionability.isCalendarCommitment` (line 476-495): when a copula is
present, the sentence is only a commitment if it also matches `scheduledNoun`
(`Actionability.swift:124`). That list has ~50 nouns. Anything outside it returns `false` →
`.ambiguous` → `.note` → Memory, and the resolved date is discarded on the way out.

**Hits:** 8. **Severity: BEHAVIORAL**, arguably CRITICAL — the user stated a day and a
clock and the app kept neither.

| utterance | observed | expected |
| --- | --- | --- |
| `Nadia's school play is Thursday at six` | Memory / note / school, **due=nil** | Today / event, Thu Aug 6 18:00 |
| `soccer practice is Tuesday at five` | Memory / note, **due=nil** | Today / event, Tue Aug 4 17:00 |
| `my haircut is Wednesday at ten` | Memory / note, **due=nil** | Today / event, Wed Aug 5 10:00 |
| `the open house is Sunday afternoon` | Memory / note, **due=nil** | Today / event, Sun Aug 9 |
| `the bake sale is Friday` | Memory / note, **due=nil** | Today / event, Fri Aug 7 |
| `we've got the plumber coming Tuesday` | Memory / note, **due=nil** | Today / event, Tue Aug 4 |
| `i'm on call this weekend` | Memory / note, **due=nil** | Today / event |
| `book club is Thursday night` | Today / task (via the `book` action verb!), due Thu 20:00 | Today / event — right day, wrong type, for the wrong reason |

Meanwhile `the recital is Saturday at two`, `my shift is Saturday night`, `the school
concert is next Thursday at seven` and `Nadia's birthday party is Saturday at one` all work
— because `recital`, `shift`, `concert`, `party` happen to be on the list. Two identical
sentences about a child's evening event get opposite destinations depending on whether the
word is "recital" or "play".

---

## R9 — priority is a keyword scan over raw text with no actionability gate

**Mechanism.** `ThoughtOrganizer.inferredPriority` (line 664) scans the *whole* lowercased
text for `urgent | asap | immediately | right now` → `.urgent`, and `today | tomorrow |
deadline | important` → `.high`. It never asks whether the item is actionable, and it never
looks at whether the keyword is being used as an adjective about something else.

**Severity: METADATA** on its own, but it is what makes Memory notes sort into the top of
lists and take an emphasis treatment they have not earned.

| utterance | observed | expected |
| --- | --- | --- |
| `that was an urgent care visit not the er` | Memory / note / **p3 urgent** | p1 — "urgent care" is a clinic |
| `things are heavy right now` | Memory / note / **p3 urgent** | p1 |
| `right now i just need a minute` | Memory / note / **p3 urgent** | p1 |
| `i'm not talking to my brother right now` | Memory / note / **p3 urgent** | p1 |
| `i'm reading a really important book about grief` | Memory / note / **p2 high** | p1 |
| `the important thing is she felt heard` | Memory / note / **p2 high** | p1 |
| `we watched a documentary about the deadline for the climate targets` | Memory / note / work / **p2** | p1, personal |
| `today was rough` / `today was long` / `work was fine today` | Memory / note / **p2 high** | p1 — every journal entry containing "today" is high priority |
| `i want to remember that today Nadia said she wants to be a marine biologist` | Memory / note / **p2** | p1 |
| `asap send the file to Marcus` | **Memory** / note / p3 | Today / task / p3 |
| `asap call the hospital` | **Memory** / note / p3 | Today / task / p3 |

The last two are the worst pairing: `ActionabilityReader.actionBody` (line 534) strips a
leading `urgent|important|high-priority` label before reading the head verb, but **not
`asap`**, so `asap call the hospital` never reaches `hasActionVerbHead`, is filed as a
Memory note, and is simultaneously marked Urgent. It is the highest-stakes wording in the
vocabulary and it lands in the archive.

Two side-effects of the same missing strip: `urgent call the school` yields
`person = "Urgent"` and `important call the vet back today` yields `person = "Important"`,
so both are filed under People with a fabricated contact name.

**Correct guard:** `explicitlyNotUrgent` works — `it's not urgent but i should replace the
tap` → p1.

---

## R10 — category is a coarse keyword scan; 64% of everything is `general`

**Mechanism.** `ThoughtOrganizer.inferredCategory` (line 582). After the type-derived cases
(shopping / ideas / events / people) it tests two fixed word lists, then a small
`personal` list, then falls through to `.general`.

- `assignment, exam, class, lecture, professor, course, school, study, homework` → `.school`
- `project, launch, client, deadline, report, presentation, office, work` → `.work`
- `home, family, dentist, doctor, dinner, weekend, workout` → `.personal`

**Severity: METADATA / BEHAVIORAL.** Misfires observed:

| utterance | observed | expected |
| --- | --- | --- |
| `the report from the doctor came back clean` | **work** (matched "report") | personal / health |
| `the project i'm reading about is a bridge in Norway` | **work** | general |
| `we watched a documentary about the deadline for the climate targets` | **work** | general |
| `i realized i actually work better in the morning` | **work** | general |
| `proud of myself for getting through the presentation` | work | general or personal |
| `my class reunion is next June` | **school** | people / personal |
| `i wouldn't mind trying that pottery class` | **school** | personal |
| `they cancelled the class last minute` | school | general |
| `i had this thought that we could turn the shed into an office` | **work** | ideas |
| `pay the hydro bill`, `renew my passport`, `book the car in for its oil change`, `mow the lawn`, `sign the permission slip` | all **general** | personal / home |

Household and admin errands — the largest single category of real captures — have no
home. Every one of them is `general`. There is also no `health`, `finance`, `home` or
`errand` category in `ItemCategory`.

---

## R11 — negation is read as a cancel operation on captures that were never about an existing item, and the capture then produces no row

**Mechanism.** `CaptureOperationDetector` (`SpeechRepair.swift:1087`) classifies a large family of first-person
denials as `cancel`. `SwiftDataThoughtRepository.applyCaptureOperation` (line 949-953):
when the target matches nothing, `discardCaptureItems(for: session)` runs and the outcome
is `.notFound` — **no item is created**. The `CaptureSession` transcript survives, but the
person gets no row.

**Hits:** 24 of 626 utterances (3.8%) produced zero rows. **Severity: CRITICAL** for the
subset that were statements rather than instructions — the capture produces nothing at all.

| utterance | observed | expected |
| --- | --- | --- |
| `i'm not going to Ana's wedding after all` | `cancel target=ana's wedding after all` → no row if nothing matches | Memory note (a decision worth keeping) |
| `we're not doing Christmas at my parents this year` | `cancel target=christmas at my parents this year` | Memory note |
| `i'm not doing the commute five days a week` | `cancel target=the commute five days a week` | Memory note |
| `i'm not going back to that dentist` | `cancel target=back to that dentist` | Memory note |
| `i'm not doing that again` | `cancel target=that` | Memory note |
| `i'm not going to worry about it` | `cancel target=worry about it` | Memory note |
| `no need to worry about the car it's under warranty` | `cancel target=worry about the car it's under warranty` | Memory note |
| `i'm not going to the gym on weekends anymore` | `cancel` | Memory note |

The inconsistency is stark inside the same family: `i'm not going to therapy anymore it
wasn't helping` → Memory note; `i'm not going to the gym on weekends anymore` → cancel.
`i'm not renewing my subscription` → Memory note; `i'm not renewing the lease` → Memory
note; but `i'm not going to bother with the extended warranty` → cancel.

---

## R12 — `needsReview` fires on ordinary clean captures, and Today's "Needs review" is not route-filtered

**Two distinct problems.**

**(a) Memory items appear on Today.** `TodayView.needsReview` (`TodayView.swift:230-240`)
filters `allItems` — every non-archived item — through
`ShoppingListProjection.belongsInTopLevelReview`, which calls
`CapturedItem.requiresReview` (`CapturedItem.swift:183`):

```swift
return needsClarification || locationBlocker(authorization:) != nil
```

There is no check on `itemType`, `belongsInToday`, or route. So **every** `unclear` Memory
note — all 29 "Review captured thought" rows from R4, plus 11 of the 30 questions I probed
— is displayed on the Today surface. Knowledge is showing up on the action surface, which
is exactly the blur the product contract forbids. **Severity: BEHAVIORAL.**

**(b) Clean captures are flagged.** 66 / 646 rows (10.2%) carry `needsReview`.

| utterance | observed | comment |
| --- | --- | --- |
| `remind me to email Priya the invoice` | Today / personFollowUp / person=Priya / **REVIEW** | nothing is ambiguous; the user just did not name a time |
| `remind me to take the bins out` | Today / task / **REVIEW** | same |
| `remind me about the parcel` | Today / task "The parcel" / **REVIEW** | same |
| `don't let me forget the passports` | Today / task "The passports" / **REVIEW** | same |
| `call Ana next week` | Today / personFollowUp / person=Ana / **REVIEW** | but `email Marcus sometime this week` → no review. Inconsistent for the same vagueness |
| `where did i put the spare key` · `what was the wifi password again` · `how do you spell her last name` · `when did we last change the furnace filter` | Memory / **unclear** / REVIEW | ordinary questions; 11/30 questions flagged |
| `i need to call back that woman from the school` | Today / personFollowUp / **REVIEW** | "that woman from the school" is a description, and should resolve as `.described`, not `.missing` |

Correctly raised: `call them tomorrow`, `tell them we can't make it`, `i owe them a reply`
— genuine missing follow-up targets.

---

## Secondary observation (feeds category=people, other lanes own the fix)

`PersonMentionResolver` invents contact names from ordinary nouns, and because
`ThoughtOrganizer.swift:359` routes `type == .note && personName != nil` to
`ItemCategory.people`, every one of these is **misfiled under People**:

`person = "Aftersun"` (the film we watched last night was called Aftersun) ·
`"Santa Clara"` (the hotel we liked in Lisbon) · `"Sage"` (that shade of green is called sage) ·
`"Cloud White"` (the paint colour) · `"Rest"` (the recipe says to rest the dough) ·
`"Faster Than"` · `"Ran Way"` (the meeting ran way over) · `"Lenses"` (order more contact lenses) ·
`"I'd"` (i'd like to get better at not checking my phone at dinner) · `"Kinda"` ·
`"Husband"` · `"Add"` · `"Urgent"` · `"Important"`.

Also observed while probing, outside this lane but CRITICAL and worth relaying:

- `right the code for the storage unit is one nine nine five and the office closes at six`
  → title **and quote** both read "one nine **five**". A digit is destroyed in a reference code.
- `the tenant downstairs works nights so no vacuuming before ten`
  → title and quote both read "the tenant downstairs vacuuming before ten". Four words lost from the quote.
- `something shifted this week and i can't name it`
  → title and quote read "**mething** shifted this week". The filler stripper ate "So" from "Something".
- `we're due at the dentist at nine` → due **Mon Aug 3 21:00** (9 p.m. dentist).
- `i should reserve a table for six` → due **Mon Aug 3 18:00**; "for six" is party size, not a time.

---

## Already correct — guards that must survive any fix

Probed deliberately and behaving well. Do not regress these.

1. **Past-tense history stays in Memory.** 53 / 55 of batch `D-past.txt` were Memory/note:
   `she called me yesterday about the fence`, `i already sent the invoice`, `we cancelled
   the trip`, `i submitted the application on Friday`, `the package shipped Tuesday`,
   `i paid the invoice this morning`, `Priya emailed the whole team about it`. No due dates
   invented, no tasks resurrected.
2. **The documented `Actionability` invariants hold.** `Catherine called me at five` →
   Memory (time never promotes history). `Ana's birthday is October twelfth` → Memory /
   people, no date. `Alex moved to Toronto in September` → Memory. `remember Mum's number
   is 555 0134` → Memory / people. `remember to buy milk tomorrow` → Today / shopping,
   due Tue Aug 4. `the office closes December 24` → Memory. `application closes Friday` →
   Today (deadline noun). `rent is due on the first` → Today, Sep 1. `the party is
   Saturday` → Today, Sat Aug 8. `the meeting was moved to Thursday` → Today, Thu Aug 6.
   `I forgot to call Catherine` → Today / personFollowUp. `I was supposed to call Mom
   yesterday but she already called me` → Memory (discharged obligation).
   `idea for tomorrow's team meeting` → Memory / idea.
3. **Reference details go to Memory intact.** wifi passwords, gate codes, policy numbers,
   seat numbers, confirmation codes, model numbers, addresses, parking levels — all
   Memory / note with the wording preserved.
4. **Plain errands with a listed verb route correctly.** ~60 of the 78 in `A-action.txt`
   landed Today / task with the right category and normal priority and no invented date.
5. **Shopping basics.** `milk eggs bread` → three checkable Groceries rows. `get milk`,
   `pick up some eggs`, `i should get shampoo`, `we're out of coffee`, `buy dog food` all
   → shopping / Groceries. `get the dry cleaning` and `get the kids from school` correctly
   stay tasks (the determiner rule works when the object has one).
6. **Explicit reminders and alarms.** `remind me to call the dentist tomorrow at ten` →
   due + reminder Tue Aug 4 10:00, notification. `set an alarm for six thirty` → alarm
   delivery Tue Aug 4 06:30. `set a timer for twenty minutes` → alarm Mon Aug 3 10:20.
   `wake me at five` → alarm Tue Aug 4 05:00. `uh remind me to bring the folder tomorrow
   morning` → Tue Aug 4 09:00.
7. **Person follow-ups vs errands.** `call Mum` / `text Ana that we're running late` /
   `tell Marcus the meeting moved` / `wish Priya happy birthday` / `i owe Ana a call` →
   personFollowUp / people with the right person. `call the dentist` / `call the landlord`
   / `call the bank about that charge` / `i owe the city forty dollars` → task, not People.
8. **Conditionals and hypotheticals stay in Memory.** `if it rains i'll cancel the
   picnic`, `assuming the weather holds we'll go up Friday`, `if the sitter cancels we stay
   home`, `if all else fails we just drive`, `i'd only go if Sam goes`, `we may or may not
   go`, `i might not go at all` — all Memory / note with no fabricated dates.
9. **`explicitlyNotUrgent` works.** `it's not urgent but i should replace the tap` → p1.
10. **The idea family is stable.** `idea for the podcast intro`, `what if we did the party
    at the park instead`, `maybe create a shared calendar for the family`, `it would be
    cool to build a little weather station`, `concept for the garden layout` → Memory /
    idea / ideas. `i have no idea where the receipt is` and `the ideal temperature for the
    roast is 190` correctly do **not** become ideas.
11. **Multi-intent captures with a real conjunction split correctly.** `i need to buy dog
    food and call the vet` → shopping + task. `we need milk and i should call the plumber`
    → shopping + task. `i need to call the school and also the dentist and pick up bread`
    → task + shopping.
