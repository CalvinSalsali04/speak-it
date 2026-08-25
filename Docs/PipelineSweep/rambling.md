# Lane: rambling — long, real, unrehearsed captures

**Instrument:** `frozen/probe`, frame Mon 2026-08-03 10:00 America/Toronto.
**Corpus:** 376 utterances, average 22.6 words, max 105 words, in
`scratchpad/rambling/{A..K}*.txt`. 867 rows produced.
Themes: multi-topic runs (A, I), self-interruption/restart (B, B2), trailing
off (C), heavy filler (D), thinking-aloud-to-decision (E), mixed
knowledge+action (F), single coherent thoughts that must not split (G),
60–105 word captures (H), reminder/person/shopping mixes (J), guard
confirmations (K).

> **Provenance note.** `SpeakIt/Repositories/*.swift` was being edited by the
> main session while this sweep ran (`ThoughtExtractor.swift` grew 1691 → 1793
> lines mid-session). Every behaviour below is from the **frozen probe**
> baseline. Line numbers were re-verified against the working tree at the end
> of the sweep and all the cited anchors still hold, but prefer the function
> name + quoted regex over the number if they have drifted again.

**Headline:** the lane is not clean. Long captures fail in ways short ones do
not, and three of the failures destroy content outright rather than
misfiling it. The two named failure modes both exist, but the more dangerous
one is a third: **whole-capture annihilation**, where a 30–60 second capture
produces one row, a placeholder row, or no rows at all.

---

## Root-cause clusters, most impactful first

### C1 — CRITICAL. The segment cleaner eats the first letters of real words, including names, in the quote itself

**Mechanism.** `ThoughtExtractor.swift:1218-1227` (`appendSegment`):

```swift
of: #"(?i)^(?:and|also|then|plus|so|first|second|third|finally|one\s+more\s+thing|another\s+thing)\s*[:,]?\s*"#
```

There is **no `\b` after the alternation**, and `\s*[:,]?\s*` all match empty.
Any segment whose first word merely *begins* with `and`, `also`, `then`,
`plus`, `so`, `first`, `second`, `third` or `finally` loses those letters.
This runs on every segment, so the damage lands in `sourceQuote` — the field
that is supposed to be the user's untouched wording. It only fires when the
capture splits into 2+ segments, which is precisely what long captures do
(a single-segment capture takes the `parts.count > 1` early return in
`segmentedThoughts` and keeps the raw transcript).

**Hits:** every capture where a conjunct starts with one of those letter
sequences. In a rambling corpus that is common; personal names make it
severe.

| utterance | observed | expected |
|---|---|---|
| `email Marcus and Andrew needs the file too` | row 2 title **`Rew needs the file too`**, quote `rew needs the file too`, **person: `Rew`** | `Andrew needs the file too`, person `Andrew` |
| `call Dave and Andrea about the quote` | row 2 **`Rea about the quote`** | `Andrea about the quote` |
| `call the plumber and Sonia is coming at three` | row 2 **`Nia is coming at three`**, **person: `Nia`** | person `Sonia` |
| `pick up milk and Sophie needs her lunch money` | row 2 **`Phie needs her lunch money`** | `Sophie …` |
| `call the vet and something is wrong with the dog` | row 2 **`Mething is wrong with the dog`** | `something is wrong…` |
| `call the vet and someone needs to feed the dog` | row 2 **`Meone needs to feed the dog`** | `someone…` |
| `sort of I need to email the client and update the invoice and follow up on the old one` | row 1 title and quote **`Rt of I need to email the client…`** | `sort of…` |
| `software update on the laptop and call the dentist` | row 1 **`Ftware update on the laptop`** | `software update…` |

This is the brief's CRITICAL definition met exactly: words the user said are
gone from the title **and** the quote, and a fabricated person name (`Rew`,
`Nia`) is written to the People section. Cheapest fix in the whole sweep:
add `\b` (and require the separator to be real whitespace).

---

### C2 — CRITICAL. A fabricated capture operation discards the entire capture

**Mechanism.** `CaptureOperationDetector.partition` (`SpeechRepair.swift`)
splits the transcript on `and|but|then|also|plus|,|;` and asks `detect()` of
each piece. In a long capture, a clause like *"cancel the cable"* or *"push
the signing to next week"* is a **new errand**, not a request to act on an
existing Speak It row — but `detect` reads it as one. Then
`SwiftDataThoughtRepository.swift:~951`:

```swift
case 0:
    // Nothing to act on. No fake item stands in for the request.
    discardCaptureItems(for: session)
    return .notFound(operation: request.operation, target: target)
```

and the call sites (`:757`, `:865`) take the operation branch **instead of**
`organizePersistedCapture`, so `extraction.items` are never persisted. Zero
matches ⇒ every row of the capture is deleted. The transcript survives on
`CaptureSession`; nothing appears on Today or Memory.

**Hits:** 8/376. Each one is total loss of a multi-errand capture.

| utterance | observed operation | what is destroyed |
|---|---|---|
| `call Rogers about the bill and cancel the cable and keep the internet and ask about the loyalty discount` | `cancel target=cable` | all 4 errands |
| `okay so a bunch of things um first I need to call the dentist and reschedule Maya's cleaning … and finally remind me to call mom on Sunday` (105 words) | `reschedule target=maya's cleaning because it's the same day as the field trip` | ~9 topics incl. the Sunday reminder for Mom |
| `the pharmacist said the two meds interact so ask Dr Chen about switching and don't take them together in the meantime` | `cancel target=take them together in the meantime` | the Dr Chen follow-up and the interaction note |
| `Kevin said the contract needs the indemnity clause changed so send it back to legal and push the signing to next week` | `reschedule target=signing` | both rows |
| `the daycare has a spot in September but they need the deposit by the 15th so pay the deposit and cancel the other waitlist` | `cancel target=other waitlist` | deposit task + Sept-15 date |
| `part of me wants to cancel but I already paid so just go and make the most of it` | `complete target=paid so just go` | both rows |
| `do we cancel the trip or reschedule reschedule call the airline about the credit` | `reschedule target=call the airline about the credit` | the airline call exists **only** as the operation target |
| `I've been thinking about the gym membership honestly cancel it I haven't gone since March` | `cancel target=it i haven't gone since march` | quote is truncated to `I have been thinking about the gym membership honestly`; the rest lives only in the target |

The last two are worse than "row discarded": the words survive nowhere at
all once the operation is dropped — they are not in any title and not in any
quote. Suggested guard: do not run an operation when the same capture also
yields ≥1 creatable item, or at minimum fall back to creating the items on
`.notFound` instead of discarding.

---

### C3 — CRITICAL / BEHAVIORAL. One filler word collapses a whole multi-errand capture to a single row

**Mechanism.** `IntentConsolidation.swift:125` / `:139`. `consolidate` fires when
`substantive.count <= 1` and a `preambleMarker` appears **anywhere** in the
transcript. `preambleMarker` = `anyway|anyways|honestly|basically|to be
honest|i mean|the (main|whole|real)? (thing|point|issue) is|i was (just)
thinking|i've been (meaning|thinking|putting|trying)|i keep
(forgetting|meaning|telling|thinking)|i always forget`.
`isSubstantive` rejects any clause whose action object is
anaphoric (`it|this|that|them|those|these|so|one`) — pronouns are constant
in rambling speech, so real errands are routinely judged non-substantive and
the whole capture folds into one item, or into the literal placeholder title
`Review captured thought`.

**Hits:** 36/376 utterances contain a preamble marker; **19 of those
collapsed to a single row**. 7 produced `Review captured thought`.

This also breaks the project's rendering-invariance rule — the same content,
with realistic filler added, produces a different item count:

| utterance | observed | expected |
|---|---|---|
| `um right so I mean the meeting is uh Thursday at 2 and I still need to like finish the slides` | **1 row** `Finish the slides`, **due nil** | 2 rows; meeting Thu Aug 6 14:00 |
| `the meeting is Thursday at 2 and I still need to finish the slides` (same content, no filler) | 2 rows, meeting **due Thu Aug 6 14:00** | (correct) |
| `honestly I want a second opinion so get another quote and also while I'm thinking about it pay the hydro bill it's due the eleventh` | **1 row** `Get another quote` [Today/shopping] | 3 rows incl. hydro bill due the 11th |
| *(drop the word `honestly`)* | 3 rows, hydro bill on Today | (correct) |
| `um okay so the plumber came … so get another quote and also while I'm thinking about it pay the hydro bill it's due the eleventh` (105 words) | **1 row: `Get another quote`, typed `shopping`, list `Groceries`** | plumber diagnosis note + 2nd-opinion task + hydro bill due Aug 11 |
| `so uh I mean um the car needs the winter tires on and like also the plates renewed` | **1 row `Review captured thought`** | 2 rows |
| `I always forget to pay the hydro bill and also the water bill and also the gas bill` | **1 row `Review captured thought`** | 3 bill tasks |
| `I keep forgetting to take the bins out and also to water the plants and also to feed the fish` | **1 row `Take the bins out`** | 3 tasks |
| `right so I mean um the printer is out of toner and uh you know I need to order more` | **1 row `Order more`** (of what?) | note + shopping row |
| `the deal is structured so that we get 40 percent at signing and the rest on delivery which means the cash flow gap in Q3 is basically the whole risk` | **1 row titled `The deal is structured`** | one note carrying the whole point |

The 105-word plumber capture is the single worst observed outcome in this
lane: 105 words in, one grocery row out.

---

### C4 — CRITICAL. Hard cap of 12 rows, silently applied

**Mechanism.** `ThoughtExtractor.swift:336`: `safeSegments.prefix(12)`.
Segments 13+ are dropped. Each dropped segment carried its own quote, so
those words exist in **no** field — only in the raw `CaptureSession`
transcript.

```
buy milk and buy eggs … and buy salt and buy pepper and buy oil   (15 items)
  → items 1..12 only; salt, pepper, oil vanish

call the dentist and call the vet … and call the notary and call the arborist  (15)
  → items 1..12 only; daycare, notary, arborist vanish
```

A 45-second grocery list reaching 15–20 entries is ordinary, not a stress
case.

---

### C5 — BEHAVIORAL, highest volume. Two divergent verb vocabularies: the splitter's is far smaller than the router's

**Mechanism.** `ThoughtExtractor.swift:251` `actionLeadPattern` (≈40 verbs) is
what every connector split looks ahead for
(`\s+(?:and|also|then|plus)\s+(?=actionLeadPattern)`), while
`Actionability.swift` `ActionabilityReader.actionVerb` (≈110 verbs) is what decides
Today vs Memory. Verbs in the second list but not the first —
`clean, fix, sign, mail, confirm, print, water, feed, replace, install,
update, register, upload, forward, wrap, donate, defrost, vacuum, sort,
drop off, refill, top up, reserve, take, do, visit` — do not open a new
clause. Additionally the splitter has **no rule for `so <verb>`**, which is
how English joins a fact to the action it implies, and no rule for
`another thing` mid-sentence.

**Effect A — the first action of a knowledge+action capture stays inside the
Memory note.** ~18/30 of the mixed lane (F). The capture *does* split, but
one clause too late.

| utterance | observed | expected |
|---|---|---|
| `the doctor said my blood pressure is 140 over 90 which is borderline so cut back on salt and book a follow up in six weeks` | 1 `[Memory/note] The doctor said … so cut back on salt`; 2 `[Today] Book a follow up` | note + **task "cut back on salt"** + task |
| `the vet said Rufus is 3 kilos overweight so switch to the light food and book a weigh in for a month out` | note absorbs `so switch to the light food` | separate task |
| `my accountant said the RRSP room is 12000 this year so set up the transfer and also get the T4 from the old job` | note absorbs `so set up the transfer`, title ends `…so set up the transfer and` | separate task |
| `the lawyer said the closing costs are about 2 percent so set aside 12000 and email her the mortgage approval` | note absorbs `so set aside 12000` | separate task |
| `HR said the benefits reset in January so use the massage credits before then and book two sessions` | note absorbs `so use the massage credits` | separate task |
| `the insurance denied the claim … so I have 30 days to appeal and I need to get the plumber's report` | **1 row: `Get the plumber's report`** — the 30-day appeal deadline is only in the quote | note + appeal task with a date + report task |

**Effect B — errands after a connector merge into the previous row.**

| utterance | observed |
|---|---|
| `call the plumber and get the furnace serviced and clean the gutters and also I should look into the roof` | 2 rows; row 2 holds three errands (`clean` not in the split list) |
| `call the accountant plus gather the receipts and one more thing download the T4s from the portal` | **1 row** holding all three |
| `call the vet Tuesday another thing Rufus needs the light food now plus the flea stuff` | **1 row** |
| `email the tenants about the inspection also the tap is still leaking oh and the smoke detector battery` | **1 row** |
| `drop the recycling off also the garbage goes out tonight oh and the green bin` | **1 row** |
| `Monday call the roofer Tuesday the fence guy Wednesday the arborist and pick whoever is cheapest by Friday` | **1 row**, due Mon Aug 10 |

**Effect C — the same gap sends real errands to Memory.** Verbs absent from
both lists, or present only where the split did not fire, produce
`[Memory/note]` rows for plain imperatives: `Blow up the balloons`,
`Hide the presents`, `Pump the tires`, `Find my helmet`, `Rehearse the talk`,
`Transfer the deposit`, `Stop at the pharmacy`, `Switch the internet plan`,
`Seal the window`, `Declutter the basement`, `Gather the receipts`,
`Freeze the card`, `Dispute the other one`, `Change the furnace filter`,
`Fill out the form`, `Set up the portfolio site`, `Finalize the seating chart`.
194 of 867 rows landed in Memory; a large minority of those are errands.

---

### C6 — BEHAVIORAL. Mid-sentence filler is never removed, so it becomes rows and dangling title tails

**Mechanism.** Every strip in `DisfluencyFilter.stripped`
(`SpeechRepair.swift`, `DisfluencyFilter.stripped`) is either `^`-anchored or comma-gated. Real
dictation supplies neither. `like` before a verb therefore survives, and
`ClauseJuxtaposition` then splits at the verb, stranding the filler as its
own clause. `mergeFragments`/`isFragment`
(`ThoughtExtractor.swift`, `mergeFragments` / `isFragment`) only recognises a bare auxiliary
(`^(?:i\s+)?(?:gotta|need to|should|…)$`), so `I should probably like`
passes through as a real item.

| utterance | observed |
|---|---|
| `I need to like call the dentist tomorrow` | **row 1 `[Today/task] Like`** (quote `I need to like`) + row 2 `Call the dentist tomorrow` |
| `we should like book the hotel this week` | **row 1 `[Today/task] We should like`** |
| `so um you know the thing is I need to like actually finish the report and send it to Marcus tonight` | **row 1 `[Today/task] Actually`** |
| `okay um so I mean I should probably like call the vet and also uh get Rufus's food` | **row 1 `[Today/task] Like`** |

6 such rows in the corpus, from only a handful of seeded cases — the
underlying pattern (`need to like <verb>`) is one of the commonest fillers in
spoken English.

The same anchoring gap leaves **60 titles ending in a dangling connector**:
`Call the dentist and reschedule and`, `Send it to Priya before that and`,
`Email Kevin the contract and`, `Buy the cake and candles plus balloons and
one more thing`, `Kevin said the contract needs the indemnity clause changed
so`, `Call Nana and`. Cosmetic on its own; it is also the visible tell for C5.

Related same-family artifacts: `The...... right the tax thing` (filler
stripped between ellipses), `Pay the—— the property tax installment`,
`Set a timer for 25 **minutesthe** pasta box says 11` (missing separator
after a self-correction), `Anyways get gas` routed to Memory because only
`anyway` is in `leadIns`, and `Right so at the vet today…` where the leading
`right so` survived.

---

### C7 — BEHAVIORAL. Self-correction refuses the commonest restart shape, and is punctuation-dependent

**Mechanism.** `SpeechRepair.swift:669`:
`guard !endsWithFunctionWord(prefix) else { return text }`. People interrupt
themselves mid-noun-phrase — *"I need to call the— actually…"*,
*"email Marcus the— no, just call him"*, *"pick up the— never mind"* — which
always leaves the prefix ending on a determiner. The guard, written to
protect *"remind me to make it snappy"*, vetoes every one of them, so the
abandoned fragment survives into the row.

Verified identical with and without the em dash (`B-restart.txt` vs
`B2-nodash.txt`), so this is not a punctuation artifact — but one case
*is* punctuation-dependent, which violates the rendering-invariance rule:

| utterance | observed |
|---|---|
| `I need to call the— actually no I need to email the landlord about the leak first` | 1 row `Call the— actually no I need to email the landlord about the leak first` |
| `email Marcus the— no actually just call him it's faster call Marcus about the contract` | 3 rows: `Email Marcus the— no actually just`, `Call him it's faster` (REVIEW), `Call Marcus about the contract` — the same call three times |
| `pick up the— what do you call it— the thing for the sink the washer I need a new washer` | 1 row keeping the whole abandoned search |
| `I should go to the gym**—** actually no I should just go for a walk after dinner` | repaired → `Go for a walk after dinner` |
| `I should go to the gym actually no I should just go for a walk after dinner` (no dash) | **not** repaired → `Go to the gym actually no I should just go for a walk after dinner` |
| `I have to renew the— scratch that Dad already renewed it just thank him` | 1 row `Renew the— scratch that Dad already renewed it just thank him` — the retracted task still lands on Today |
| `wait scratch that I don't need to go to the bank I need to go to the post office and mail the passport renewal` | **1 [Memory/note]** containing both the retraction and both real errands; neither errand reaches Today |
| `I need to buy a gift for— no wait her birthday is next month never mind` | a shopping row is created despite `never mind` |
| `add milk to the list actually we have milk add oat milk instead` | 2 rows; the retracted `Add milk to the list actually we have milk` still becomes a row |

---

### C8 — CRITICAL. Bare numbers and ordinals inside narrative become fabricated dates, alarms and recurrences

The corpus produced a fabricated or wrong temporal field in 14 distinct
utterances. All are long/narrative; a short capture rarely contains a stray
number.

| utterance | observed | expected |
|---|---|---|
| `the lease renewal came in they want a 4 percent increase I should counter at 2 and email the property manager this week` | **due Mon Aug 3 14:00, priority 2** | no due date |
| `…baked it in a preheated dutch oven at 500 for 20 minutes covered` | Today **event, due Mon Aug 3 17:00** (`500` → 5:00 pm) | a Memory note, no date |
| `what made the trip good was that we didn't plan anything past the first two days and just followed…` | Today **event due Tue Sep 1** | Memory note, no date |
| `what I love about that restaurant is that they make the pasta in house every morning and you can watch them…` | **Today task, recurs daily, due Tue Aug 4 09:00** | Memory note |
| `need to finish the quarterly report and send it to Marcus and then schedule…` | title **`Need to finish the every 3 months report`**, **recurs monthly ×3, due Tue Nov 3** — the word *quarterly* is destroyed | task, no recurrence |
| `set an alarm for 6 30 and remind me to take the pills at 8 and also I need to leave the house by 7 45…` | pills **Mon Aug 3 20:00**, leave **Mon Aug 3 19:45** | Tue 08:00 and Tue 07:45 |
| `set two alarms 6 30 and 6 45` | 3 rows: `Alarm for 6:30` ✓, **`Alarm for 6` @ 06:00 (invented)**, **`Alarm for 45` with no time** | two alarms, 06:30 and 06:45 |
| `set two alarms 6 30 and 6 45 and remind me to leave by 7 and also…` | **both alarms gone** — row 1 is a Memory note `Set two alarms 6:30 and 6 45` | two alarms + a reminder |
| `Sarah's birthday is the 19th so remind me on the 17th to get a card…` | **reminder Wed Aug 19 09:00** | reminder on the **17th** |
| `remind me in an hour to check the oven and also in twenty minutes to flip the chicken…` | row 2 `[Memory/note] In twenty minutes to flip the chicken`, **no reminder** | reminder at 10:20 |
| `book the dentist for Tuesday no wait Wednesday because Tuesday I have the thing with Priya` | title says Wednesday, **due Tue Aug 4** | Wed Aug 5 |
| `pay the visa by Friday plus the hydro bill is due the eleventh and one more thing renew the plates` | row 1 (the visa) **due Tue Aug 11** | Fri Aug 7 |
| `pick up Maya at 5 no she has practice till 6 pick her up at 6 15` | **due Mon Aug 3 17:00** (correction not applied) | 18:15 |
| `tomorrow morning call the insurance company about the appeal and afternoon pick up Maya from swimming and evening make the pie` | phantom row `Tomorrow morning` @ 09:00; the insurance call gets **15:00**; the Maya pickup gets **20:00**; the pie gets none — every time is shifted one clause | 3 rows, morning/afternoon/evening on their own errands |
| `call Kevin about the contract at 10 plus email the notary…` | **due Mon Aug 3 22:00** | Tue 10:00 |
| `I'm not sure if Tuesday works I have the thing at 3 so let's do Wednesday morning instead` | **due Wed Aug 5 03:00** | Wed morning, not 3 a.m. |

---

### C9 — CRITICAL / METADATA. Person detection invents names out of split fragments

Fragments produced by C1/C5/C10 are handed to `PersonMention` with no
sentence context, and a capitalised or sentence-initial token becomes a
person.

`Staples` (from *"buy printer ink and staples and a new mouse…"`),
`Charger` (*"buy a new phone charger and a case…"* — `phone` read as the
verb, splitting the noun phrase), `What` (*"I gotta call— you know what just
remind me…"* and *"I realized … what's actually bothering me…"*),
`Who` (*"figure out who's driving"*), `Each` (*"ask each of them for
references"*), `Engineer` (*"we need an engineer's letter"*),
`Grandmother`, `Rogers`, `Dev I'm` (*"tell Dev I'm doing it"*),
plus `Rew` and `Nia` from C1.

Worst single case:
```
buy a new phone charger and a case and screen protector and back up the old phone first
  1 [Today/shopping] Buy a new                     list=Other
  2 [Today/personFollowUp] Phone charger and a case and screen protector and back up the old   person=Charger
  3 [Today/personFollowUp] Phone first             REVIEW
```

---

### C10 — BEHAVIORAL. One coherent thought is shattered

**14 of the 20 single-thought captures in `G-onethought.txt` were split.**
Two mechanisms:

1. `splitIndependentConjuncts` (`ThoughtExtractor.swift`, `splitIndependentConjuncts`) breaks noun
   coordinations when the right conjunct is capitalised or tagged as a verb:
   `the knob and tube` → `The inspector said the knob` / `Tube is only in the
   garage…`; `the difference between the mortgage and the rent` → two notes;
   `turkey and stuffing` → a row beginning `Stuffing and I said I'd handle a
   side…`; `back up the old phone` split mid-phrase.
   The `conjunctionIdioms` list is the right shape but too short.
2. `mergeFragments` lets one-word rows through: 19 rows in the corpus have
   ≤1 content word — `Ask`, `Check`, `Candles`, `Sign it`, `Like`,
   `Actually`, `Thing tomorrow`, `Alarm`, `About the wedding`.

| utterance | observed |
|---|---|
| `do I need a permit for this probably yeah I should just call the city and ask` | row 2 = **`Ask`** |
| `I wonder if the warranty covers this I should dig out the paperwork and check` | row 2 = **`Check`** |
| `about the wedding… um… I think we're doing 80 people and the venue caps at 90` | 3 rows, incl. `[Today/event] The venue caps at 90` |
| `the whole point of the reorg is that the platform team owns the runtime and the product teams own their own features…` | 2 Memory notes |
| `the thing I keep coming back to is that we made the app faster and nobody noticed but we changed the empty state copy and three people emailed about it` | **3** Memory notes |
| `so first thing tomorrow email Kevin the contract and then call the notary…` | phantom row 1 `[Today/event] Thing tomorrow` due Aug 4 |

Note the asymmetry the code comments claim ("fabricated rows cost more than
merged ones") does not hold here — C3 merges *and* C10 fabricates, on
different inputs.

---

### C11 — BEHAVIORAL. A leading subordinate clause takes an errand off Today

Rambling speech chains errands with *"while I'm at it…"*, *"after that…"*,
*"while I'm there…"*. Each one routes the errand to Memory.

```
while I'm at it pay the hydro bill              → [Memory/note]
while I'm thinking about it call the vet        → [Memory/note]
after that pick up the prescription             → [Memory/note]
while I'm there grab the vitamins               → [Memory/note] "While I'm there" + [Today] "Grab the vitamins"
```

Seen inside long captures too: *"so tomorrow I need to be at the clinic by
8 15 … and then after that pick up the prescription and get to work by 10"*
→ the prescription pickup is a Memory note.

---

## Answering the brief's specific questions

**Does mixed action+knowledge split correctly?** Partially. The *second*
action reliably gets its own Today row; the *first* action stays inside the
Memory note (C5, effect A). The knowledge half is usually correctly a Memory
note — except when a bare number in it fabricates a date and flips the whole
row to a Today event/task (C8).

**Is the original wording preserved?** Yes in the great majority — `quote`
held the full utterance in every collapse case I checked, including the
105-word plumber capture. Four exceptions, all CRITICAL:
1. C1 — the quote itself is corrupted (`rew`, `nia`, `mething`, `rt of`).
2. C4 — segments past #12 have no quote at all.
3. C2 — when an operation is detected the surviving quote is truncated to
   the pre-operation clause, and the rest exists only as an operation target
   that is then thrown away.
4. `set a timer for 20 minutes no 25 …` → quote `Set a timer for 25
   minutesthe pasta box says 11…`; the words `20 minutes` are gone and two
   words are fused.

**Is there a length cliff?** Not a smooth one — quality is *unstable* rather
than monotonically degrading. Dropping the first six words of the 105-word
plumber capture changed the row count 1 → 6 → 6 → 6 → 1 → 5 → 1 → 1 → 1.
Three real cliffs exist: the hard `prefix(12)` cap (C4), the
`IntentConsolidator` veto which becomes more likely the more pronouns and
filler a capture contains (C3), and the operation detector which becomes
more likely the more clauses there are (C2). Above ~60 words the last clause
also becomes an ever-growing tail blob (`H-verylong.txt`: rows of 50–60
words holding four unrelated errands).

---

## Already correct — guards that behave well, do not break these

- **Plain errand runs with in-vocabulary verbs split cleanly and
  completely.** `call the landlord about the heat and take out the recycling
  and pay rent and fix the closet door` → 4/4 correct Today tasks. Same for
  `water the plants and feed the fish and bring in the mail and check on the
  neighbours cat`, `email the tenants about the inspection and fix the
  leaking tap and replace the smoke detector battery`, `get the snow tires on
  and check the washer fluid and book the oil change and renew the plates`,
  `book the eye exam and order new contacts and check if the insurance covers
  the frames`.
- **Shopping expansion inside a long mixed capture.**
  `buy milk eggs bread butter and also call the pharmacy about the refill and
  remember they close at 6 on Saturdays` → 4 grocery rows (list `Groceries`)
  + 1 task + 1 Memory note. Exactly right.
- **Shared reminder prefix distribution, and its withholding from facts.**
  `remind me at home to water the plants and also feed the fish and remember
  the fish food is in the drawer` → two `arrive home` geofenced tasks + one
  plain Memory note.
  `remind me every Friday to submit the timesheet and also Catherine needs a
  copy` → weekly recurrence on the task only; `Catherine needs a copy` stays
  a Memory note with person `Catherine`. The documented guard holds.
  `remind me at the pharmacy to pick up the prescription oh and grab vitamins
  while I'm there` → both errands carry the named-place trigger.
- **Lead-time qualifier merging.** `book the physio for Tuesday at 4 and
  remind me an hour before` → one row, due Tue 16:00, reminder Tue 15:00.
- **Elided-verb sharing across a conjunct.** `call Alex and Alexa tomorrow at
  five` → two `personFollowUp` rows, **both** due Tue Aug 4 17:00.
- **Conjunction idioms already listed.** `I keep going back and forth on this
  but I need to call the insurance company` and `it's been touch and go but I
  still need to book the dentist` each stay one row.
- **Self-correction slot repair, when the replacement is a clean slot value.**
  `remind me tomorrow at 9 no make it 10 to call the clinic` → 10:00.
  `remind me to take the chicken out at 4 actually make it 3 30` → 15:30.
- **Multi-moment captures with explicit anchors.** `I need to be at the
  airport by 5 am Friday so set an alarm for 3 15 and remind me to check in
  Thursday night and pack the chargers` → 3 rows, alarm Fri 05:00, reminder
  Thu 20:00, plus a plain task. Correct.
- **Three-way action / shopping / knowledge split.** `call the dentist
  tomorrow buy milk and remember Catherine is allergic to peanuts` → task
  (due Tue) + Groceries row + Memory note with person. Correct.
- **Leading disfluency stripping never ate content** in 376 utterances; the
  failures are all *mid-sentence* filler (C6), never the leading strip.
- **`sourceQuote` fidelity** outside the four exceptions listed above —
  including every C3 collapse, where the full utterance is retained.
