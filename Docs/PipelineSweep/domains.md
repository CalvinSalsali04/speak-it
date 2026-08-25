# Lane: domains — does the pipeline handle the content of adult life?

**Answer: no, not yet.** The pipeline is tuned for short errand grammar ("call the
dentist tomorrow", "milk eggs bread"). Real adult captures are compound-noun-dense,
negation-dense, number-dense and narrative, and each of those densities collides with a
different rule. **Reference detail itself is safe** — codes, dosages, part numbers and
measurements survive verbatim (see "Already correct") — but the *sentences around them*
are being split, negated, re-worded and mis-dated.

666 utterances probed (plus ~20 ad-hoc one-offs) across work, parenting, health, money/admin, home/vehicle,
travel, social, learning, plus dense rambling captures and 8 targeted mechanism probes.
Utterance files and raw output: `scratchpad/domains/*.txt`, `*.raw`.

---

## Root-cause clustering

### C1 — `SelfCorrectionResolver` fires on ordinary "no" and "actually", deleting words and inverting negation
**CRITICAL. ~28 utterances. Every domain. This is the single worst finding.**

`SpeakIt/Repositories/SpeechRepair.swift:581-594` (`correctionPattern`).
The doc comment at :586-589 states the intended rule exactly:

> `no` is special: it is ordinary sentence content far more often than a repair marker
> ("I have no idea", "Sarah has no pets"). It may lead a correction only after
> punctuation/dash. Without punctuation, a positive cue such as "wait" or "actually"
> must be present.

The code does not implement that. `anyMarker` (which contains `no|nope`) is used in
**both** branches:

```swift
let anyMarker = #"(?:no|nope|\#(punctuatedOnlyMarker)|\#(unambiguousMarker))"#
let punctuated   = #"(?:\s*[—–-]\s*|\s*,\s*)(?:\#(anyMarker)\b\s*,?\s*)+"#
let unpunctuated = #"\s+(?:\#(anyMarker)\b\s*,?\s*)+"#     // ← should exclude no|nope
```

Dictation supplies no commas, so in a voice-first app the *unpunctuated* branch is the
one that always runs. `actually` is in `unambiguousMarker` and has the same problem: it
is an ordinary adverb far more often than a repair marker.

Every "X has no Y", "… so no Y", and "… actually …" sentence is destroyed **in the title
and in the per-row quote**, and the negation is inverted.

| utterance | observed row title | expected |
|---|---|---|
| `Sarah has no dairy at all` | **`Sarah dairy at all`** | `Sarah has no dairy at all` |
| `tell Priya no changes after Thursday` | **`Tell changes after Thursday`**, person=**`Changes`** | title intact, person=`Priya` |
| `the class has no birthday treats policy` | **`The birthday treats policy`** | intact |
| `the venue has no wheelchair access` | **`The wheelchair access`** | intact |
| `the hotel has no shuttle after 10` | **`The shuttle after 10`** | intact |
| `we have no milk left` | **`We milk left`** | intact |
| `Noor is fasting this month so no lunch meetings` | **`Noor is fasting this lunch meetings`** | intact |
| `the office is closed this week so no standup` | **`The office is closed this week standup`** | intact |
| `the deploy actually went fine` | **`The went fine`** | intact |
| `the numbers actually improved last quarter` | **`The improved last quarter`** | intact |
| `tell Sam the client actually approved it` | **`Tell Sam approved it`** | intact |
| `research whether standing desks actually do anything` | **`Research whether do anything`** | intact |
| `check whether the standing desk actually helps` | **`Check whether helps`** | intact |

The allergy case is the one to lead with: a note whose whole purpose is a negative
constraint is stored with the negation removed. 8/8 of my `"… so no X"` probes and
9/20 of my `"has no X"` probes inverted. Guards that *do* hold: `there is no X`,
`there's no X`, `I have no idea`, `say no to X`, `tell the teacher no nuts`.

---

### C2 — `ClauseJuxtaposition` splits compound nouns whose head word is a verb homograph
**CRITICAL / BEHAVIORAL. ~25 utterances. Work, money, home, health, parenting.**

`SpeakIt/Repositories/SpeechRepair.swift:966` — `instructionOpeners` contains
`water|finish|call|order|return|schedule|check|charge|file|sign|mail|note|take|put|move|
text|message|pay|book|pack`. `pieces(in:)` splits before any of them once ≥2 words
precede it, unless the immediately preceding word is in `clauseInternalLead` — a list of
**function words only** (`the`, `a`, `my`, prepositions, modals…).

So `the water heater` is safe (preceded by `the`) but every **noun-modifier + noun**
compound splits, because the modifier is a noun or adjective:

| utterance | observed | expected |
|---|---|---|
| `the fridge water filter is model DA29-00020B` | 2 rows: `The fridge` / `Water filter is model DA29-00020B` | 1 Memory note |
| `my SIN is on the tax return not writing it here` | 2 rows: `My SIN is on the tax` / `Return not writing it here` | 1 Memory note |
| `the amazon order number is 702-4418923-0044821` | 2 rows: `The amazon` / `Order number is …` — second is a **shopping row on list "Other"** with person=**`Order`** | 1 Memory note |
| `the custody schedule changes to alternating weeks in September` | 2 rows: `The custody` / `Schedule changes to…` | 1 Memory note |
| `note from the customer call they churn risk is the SSO gap` | 2 rows: `From the customer` / `Call they churn risk…` (2nd = personFollowUp) | 1 Memory note |
| `the coffee order was wrong` | **2 shopping rows on Groceries**: `The coffee` / `Order was wrong` | 1 Memory note |
| `the paint is eggshell finish not satin` | 2 rows: `The paint is eggshell` / `Finish not satin` | 1 Memory note |
| `the pharmacist said take it with food twice daily` | 2 rows: `The pharmacist said` / `Take it with food twice every day` (+ C3 damage) | 1 row |

17 of 30 realistic compound nouns in `compound.txt` split (`tax return`, `conference
call`, `customer call`, `paint finish`, `sales order`, `phone charge`, `payment
schedule`, `vaccine schedule`, `credit check`, `background check`, `invoice charge`,
`delivery pack`, `text message`, `parts order`, `coffee order`, `work order`, `hot water
tank`). Half the fragments then acquire a fabricated person or a shopping list.

Also in this cluster: `add Kofi and Meera to the incident channel` → `Add Kofi` +
`Meera to the incident channel` (the second name loses the verb), and
`pick up Owen's inhaler and Ella's allergy meds` → shopping row + a Memory note that is
no longer an errand.

---

### C3 — `SpokenShorthandRepair` rewrites frequency adjectives into "every N", mutating words, fabricating dates and pulling facts into Today
**CRITICAL. ~20 utterances. Health, work, money, home, travel.**

`SpeakIt/Repositories/SpeechRepair.swift:300-312`. `monthly`, `weekly`, `daily` got a
lookahead guard so that "the monthly report" survives. `quarterly`, `annually`, `yearly`,
`biweekly`, `fortnightly` did **not**, and the `daily` guard still fires at end of
sentence, which is where a dosage puts it.

Consequences are triple: the user's word is replaced in title **and quote**, a
`calendarRecurrence` temporal intent is forced, and that manufactures a due date.

| utterance | observed | expected |
|---|---|---|
| `the quarterly report is due to the board` | title `The **every 3 months** report…`, **due Tue Nov 3 10:00**, recurs monthly×3 | title intact, no due |
| `the yearly checkup is overdue` | `The **every year** checkup is overdue`, **due Aug 3 2027** | intact; overdue, not a year away |
| `send Maya the quarterly business review deck` | `Send Maya the **every 3 months** business review deck`, due Nov 3 | intact |
| `take 500mg twice daily` | `Take 500mg twice **every day**`, **due Tue Aug 4 09:00, recurs daily** | no recurrence, no due (matches the correct `twice a day` behaviour) |
| `the drops are four times daily` | `…four times **every day**`, due + daily recurrence | intact |
| `I'm supposed to take the vitamin D 2000 IU daily` | `…2000 IU **every day**`, due Tue Aug 4 09:00 | dosage preserved |
| `the pharmacy closes at 9 on weeknights` | `The pharmacy closes at 9 **every weekday evening**`, **due Mon Aug 3 21:00, recurs weekdays** | Memory note, no due |
| `my vitamin B12 is low he wants injections monthly` | `…injections **every month**`, due Thu Sep 3 | intact |
| `we get paid biweekly so the budget is off` | **zero rows** (see C5) | 1 Memory note |

The multiplier is silently discarded: "twice daily", "three times daily" and "four times
daily" all become a single daily recurrence.

Second half of the same cluster — **descriptive third-person statements become Today
tasks with recurrences**: `the shuttle runs every 30 minutes`, `the bus comes every 20
minutes`, `the cleaner comes weekly`, `the newsletter goes out weekly`, `the report goes
out monthly`, `the meter is read quarterly`, `we meet biweekly`, `garbage is picked up
weekly on Tuesday`, `the city picks up yard waste every other Wednesday`. None of these
is a commitment the user asked to be reminded about.

Sub-day intervals are also coerced: `take the antibiotic every 8 hours` and
`the shuttle runs every 30 minutes` both produce **recurs: daily ×1** with a due
~24h out. The medication one is the dangerous one.

Also here: `close of business` / `COB` → `end of day` (:289-290) rewrites the user's
words in title and quote; `an hour and a half` → `90 minutes`; `midday` → `noon`;
`about N` → `around N` on any 1–2 digit number, which produces `we talked around 3
things in the standup`, `my dose is around 2 pills`, `he's around 12 and still in car
seat`, `it's around nine hundred which is insane`.

Note: `remind: nil, delivery: none` on all of these — they are fabricated **due dates
and recurrence rules**, not ringing notifications. Still CRITICAL by the brief's
definition, but worth knowing it is not a 3am alarm.

---

### C4 — Fabricated and wrong due dates from ordinary domain noun phrases
**CRITICAL. ~15 utterances. Work, home, parenting, travel, health.**

Four distinct date bugs that share a shape: a noun phrase is read as a date slot.

**(a) `the first <noun>` → the 1st of next month.** Overrides an explicit weekday.
- `the first draft is due Wednesday` → **due Tue Sep 1** (Wednesday discarded)
- `the first payment comes out Friday` → **due Tue Sep 1** (Friday discarded)
- `the first aid kit needs restocking` → **due Tue Sep 1**
- `swap to winter tires before the first snow` → **due Tue Sep 1**
- `the first appointment is at 9` → **due Tue Sep 1 09:00**
- `the school needs the immunization form before the first day` → **due Tue Sep 1**
- `the second draft is due Wednesday` → **due Wed Sep 2**
Guards that hold: `the first quarter`, `the first week`, `the first responder`,
`the third option`.

**(b) `last <Weekday>` → the *next* occurrence of that weekday.**
- `draft the incident postmortem for the outage last Tuesday` → **due Tue Aug 4**
- `file the claim for the accident last Monday` → **due Mon Aug 10**
- `the meeting last Tuesday went badly` → **due Tue Aug 4**, person=**`Last`**
- `write up the notes from the call last Thursday` → **due Thu Aug 6**, person=**`Last`**
Guard that holds: `the rash started last Friday` (past-tense verb).

**(c) A time window collapses to its end.**
- `the electrician is coming Tuesday between 8 and noon` → **due Tue Aug 4 12:00**.
  Expected 08:00 or day-only; noon is when the window closes.

**(d) A bare hour that has already passed rolls to PM.**
- `the tour meets at the fountain at 9 sharp` → **due Mon Aug 3 21:00**. A tour at 9pm.
- `the therapist has an opening Wednesdays at 5` → **due Mon Aug 3 17:00** — *today*,
  when the user said Wednesdays. Wrong day entirely.
- `we should do a movie night this weekend` → due Sat Aug 8 **20:00** (time invented).

---

### C5 — Voice-command detection swallows whole captures, producing zero rows
**CRITICAL. ~9 utterances. Money, work, health.**

`CaptureOperationDetector`. A leading `cancel`, a leading/trailing `already`, and
`… is off` are read as commands against existing items. When nothing matches, the
capture disappears — no row, no note, nothing.

| utterance | observed | expected |
|---|---|---|
| `cancel the Netflix subscription before it renews` | `operation: cancel`, **0 items** | Today task |
| `cancel my Spotify` | `operation: cancel`, **0 items** | Today task |
| `cancel the gym membership it costs 62 a month` | `operation: cancel`, **0 items** | Today task |
| `cancel the recurring donation to the food bank` | `operation: cancel`, **0 items** | Today task |
| `we get paid biweekly so the budget is off` | `operation: cancel target=we get paid every 2 weeks so the budget`, **0 items** | Memory note |
| `I already paid the hydro bill` | `operation: complete`, **0 items** | (arguably intended) |
| `already sent Priya the doc` | `operation: complete`, **0 items** | (arguably intended) |

The worst variant eats **half** a capture: `so the insurance covers physio at eighty
percent up to five hundred and I've used about two hundred already` →
`operation: complete target=used around two hundred` **plus** one row that stops at
"five hundred". The trailing clause is gone from every field.

Guards that hold: `I need to cancel …`, `remember to cancel …`, `the deal is off`,
`the standup is off this week`.

---

### C6 — `ClockDigitRepair` turns real quantities into clock times
**CRITICAL. 4+ utterances. Money, home/vehicle, work.**

`SpeakIt/Repositories/SpeechRepair.swift:189-201`. After a cue word
(`at|for|by|around|until|till|alarm|timer`) a 3–4 digit number becomes `H:MM`. The
negative-lookahead guard covers `is|was|are|were|dollars|bucks|needs|owed|outstanding`
but not measurement units or a bare end-of-sentence.

| utterance | observed | expected |
|---|---|---|
| `the rate holds for 120 days` | `The rate holds for **1:20** days` | intact |
| `we're at 142 on the odometer` | `We're at **1:42** on the odometer`, **due Mon Aug 3 13:42** | intact, no due |
| `the mortgage is at 419 a month` | `The mortgage is at **4:19** a month` | intact |
| `the invoice is for 1250` | `The invoice is for **12:50**` | intact |

In the dense capture `right the deal with the car is the timing belt at 160k and we're
at 142 so probably next spring` this produced a second row reading
`We're at 1:42 so probably next spring` with **due Mon Aug 3 13:42**.

Guards that hold: `130 square feet`, `230 kilometres`, `145 dollars`, `125 milligrams`,
`416 555 0134` (phone), `5 45 Yonge Street`.

---

### C7 — Person extraction invents names from role nouns and from verb phrases
**BEHAVIORAL. ~25 utterances. Every domain.**

Two sub-shapes.

*Role noun in the possessive becomes a contact:* `the accountant's fee went up` →
person=`Accountant`; also `Contractor`, `Babysitter`, `Cousin`, `Brother`, `Teacher`,
`Dean`, `Neighbour`, `Physio`, `Grandma`, `Dad`, `Dr. Google`. These create fake people
in Memory ▸ People.

*A verb phrase is read as a surname:* these are outright inventions.
- `the phone bill went up again` → person=**`Bill Went`**
- `the on call rotation changes Monday` → person=**`Rotation Changes`**
- `the meeting notes are in the doc` → person=**`Notes Are`**
- `the customer call went badly` → person=**`Went Badly`**
- `Alex is out next week so I need to cover the on call rotation` → person=**`Rotation`**
- `remind me to cancel the recurring status meeting nobody uses` → person=**`Nobody`**
- `the framework is called jobs to be done` → person=**`Jobs`**
- `I told Rachel I'd send her the doc by EOW` → person=**`Rachel I'd`**
- `the email thread has 40 replies` → person=**`Thread`**; `the message board is dead` → `Board`
- `ping Dev ops about the certificate expiring in March` → person=**`Dev`**
- `the amazon order number is …` → person=**`Order`**; `the meeting id is …` → `Id`

Symmetrically, real names in the middle of a sentence are missed:
`blocked on the staging creds waiting on Marcus from infra` (no person),
`the demo environment keeps timing out worth mentioning to Sasha` (no person),
`check in on Miguel his mom is in hospice` (no person),
`Nadia is doing dry January so bring non alcoholic` (no person).

---

### C8 — Routing: reference statements land in Today, commitments land in Memory
**BEHAVIORAL. ~45 utterances. Every domain. Highest raw volume.**

The actionability reader keys off a leading imperative verb, so third-person
*statements about the world* that happen to begin with a verb-ish word go to Today, and
*first-person commitments* phrased without an imperative go to Memory.

Should be **Memory**, observed **Today**:
`the dishwasher warranty runs out in November` (event) ·
`the interest rate resets to 5.19 percent in October` (event) ·
`Tuesday flight is cheaper by 200 dollars` (event, due Tue Aug 4) ·
`the ferry only runs on weekends in October` (event) ·
`the tire pressure should be 35 psi front and rear` (task) ·
`the tax refund should be about 1400` (task) ·
`Maya and Owen both have birthdays in March` (event) ·
`we decided in the meeting to postpone the redesign until Q1` (event) ·
`the sleep study is booked for September` (category **school**) ·
`the eye exam is overdue by two years` (category **school**) ·
`book recommendation from my brother Piranesi` (task — "book" read as the verb) ·
`the thing I want to remember from that podcast is …` (task, despite "want to remember").

Should be **Today**, observed **Memory**:
`action item from standup ship the auth fix by end of sprint` ·
`circle back with the Northwind folks about the pricing tier` ·
`loop in legal on the Vasquez contract before we send it` ·
`blocked on the staging creds waiting on Marcus from infra` ·
`Meera asked for the churn numbers by Friday` (also loses the Friday due) ·
`push back on the Q3 deadline it's not realistic` ·
`double check the analytics event names before we ship` ·
`sync with design about the empty states before handoff` ·
`the deck needs a slide on unit economics` ·
`reach out to that recruiter about the staff eng role` ·
`transfer money to the joint account for the property tax` ·
`set up the pre authorized payment for the water bill` ·
`close the old chequing account` ·
`we owe the daycare the updated immunization record` ·
`Ella needs new cleats before the season starts` ·
`we need a new smoke detector for the basement` ·
`the lawn mower blade needs sharpening`.

Type confusion inside Today is its own sub-shape: "book/schedule/bring X appointment" →
`event` rather than `task` (`book the dermatologist appointment for the mole`,
`they want a stool sample before the appointment`, `bring the list of medications to the
appointment`, `draft the incident postmortem…`, `ping Dev ops about…`). And `get`/`grab`
force `shopping`: `get it to me by end of day` and `get back to me by COB tomorrow` both
became **shopping rows on list "Other"**.

---

### C9 — Shopping recognition is vocabulary-gated, so real-world lists stay one row and "we need X" misses Today
**BEHAVIORAL. ~12 utterances. Parenting, home, work.**

`milk eggs bread` splits into three Groceries rows. Nothing else does.

- `pick up drywall screws caulk and a putty knife` → **1 row**
- `grab printer paper toner and a box of pens` → **1 row**, list=**Groceries**
- `pick up hockey tape mouthguard and shin pads` → **1 row**
- `buy sunscreen bug spray and a first aid kit` → **1 row**
- `pick up potting soil mulch and grass seed` → **1 row**

And `we need <thing>` reaches Today only when the thing is in the product vocabulary:
`we need milk` / `we need diapers` / `we need dish soap` → Today shopping;
`we need drywall screws` / `we need printer ink HP 63 black and colour` /
`we need furnace filters 16 by 25 and a smoke alarm` /
`we're out of dish soap paper towel and garbage bags` → **Memory note**.

---

### C10 — Copular "X is <Month Nth>" produces no date at all
**BEHAVIORAL. ~7 utterances. Money, social, work.**

A bare number works; the ordinal suffix after a copula does not. `by <Month Nth>` works.

| utterance | due |
|---|---|
| `the deadline is March 3` | Wed Mar 3 |
| `the deadline is March 3rd` | **nil** |
| `the party is September 14` | Mon Sep 14 |
| `the party is September 14th` | **nil** |
| `the deadline is October 22nd` / `is on October 22nd` | **nil** |
| `the RRSP contribution deadline is March 1st` | **nil** |
| `our anniversary is September 14th` / `the closing is September 14th` | **nil** |
| `pay the bill by September 14th` | Mon Sep 14 (works) |
| `the lease ends June 30th` | Wed Jun 30 (works — verb, not copula) |

Related no-date gaps in the same shape: `Erin's birthday is next Friday` (Memory, no
due), `our anniversary is the 14th of September` (no due), `kindergarten registration
deadline is the end of February` (no due), `finish the report by EOW` (no due, while
`by EOD` works), `have it done by end of month` / `close it out by end of quarter`
(Memory, no due).

---

### C11 — `unclear` replaces the row title with "Review captured thought"
**BEHAVIORAL (CRITICAL when it stacks on C1). 3 utterances.**

- `pickup moved to 3:15 because of the assembly` → title **`Review captured thought`**,
  no due. The quote holds the words; the row a parent sees is a placeholder.
- `um I told Rachel I'd get her the doc by Friday but honestly it's going to be Monday`
  → title `Review captured thought`, person=`Rachel I'd`.
- `so Kofi wants more scope and honestly he's ready but there's no headcount until Q1`
  → title `Review captured thought` **and** quote `Kofi wants more scope and honestly
  he's headcount until Q1` — C1 already ate "ready but there's no", so *both* fields
  have lost content.

Rare (1 in 361 across the eight domain files), but when it fires the row is unreadable.

---

## Already correct — do not regress these

Verified guards, worth pinning before any fix lands.

1. **Reference detail survives verbatim.** 30/30 in `refdetail.txt` and 12/12 embedded
   in actions: `XG7T42`, `INV-2026-0448`, `WR884120`, `702-4418923-0044821`,
   `1Z999AA10123456784`, `2026-CV-00841`, `WH01X10230`, `S/N 4471-8829`, `Bosch
   SHPM88Z75N`, `MERV 13`, `225 55 R17`, `DA29-00020B`, `NGK BPR6ES`, `Thunder47Bay`,
   `1002 47881 592`, `416 555 0182`, `4820174`, `5591 star`, `PLAT-4417`, `AC 8 5 4`,
   `1,204.55`, `4.79 percent`, `0000`, spelled-out digits (`A four seven two Q`,
   `four four seven one eight eight two nine`), and measurements
   (`16 by 25 by 1`, `32 and a quarter`, `47 and a half`, `35 psi`, `5 quarter by 6`,
   `36 inch`, `138 over 88`, `A1C 5.9`, `10mg to 20mg`, `500mg`, `2000 IU`).
2. **`take 500mg twice a day` produces no recurrence and no alarm.** Also
   `take it three times a day with food`, `apply the cream twice a day for a week`,
   `he takes his insulin twice a day` (correctly Memory). Only the `daily`-suffixed
   variants break (C3) — the `a day` form is the reference behaviour to converge on.
3. **`expires in March` does not become a due date.** `the credit card expires in
   March`, `my mortgage renewal is coming up in March`, `the promo rate expires after 6
   months`, `the referral takes six weeks` — all Memory, no due.
4. **`EOD` resolves to today, day-only** (`send it by EOD`, `I need to email the client
   by EOD`) with no invented clock time.
5. **`the CRA` is not a person** (`call the CRA about the notice of assessment`), nor is
   `the IRS`, `HR`, `the hiring manager`, `the property manager`, `the loan officer`,
   `the front desk`, `the case worker`.
6. **`picture day` / `PA day` are not dates** — `picture day is Thursday`, `PA day is
   Friday` stay Memory notes rather than inventing a "day" date.
7. **Guarded shorthand rewrites hold**: `the monthly report`, `the weekly planning doc`,
   `the daily standup` all survive intact (only `quarterly`/`yearly`/`annually`/
   `biweekly`/`fortnightly` lack the guard).
8. **Idea detection is clean**: `app idea …`, `business idea …`, `what if the app worked
   entirely offline …`, `idea we could …`, `gift idea for Sam …` → Memory ▸ idea.
9. **Genuine two-thought captures split correctly**: `my passport expires in July 2027
   renew before then`, `Marcus's dad passed away send a card`, `the leak under the sink
   got worse call a plumber`, `Maya lost her retainer again call the ortho`,
   `so the furnace guy said the filter is 16 by 25 by 1 and I should change it every
   three months`.
10. **`I need to cancel …` / `remember to cancel …` produce rows** — the guard against
    the C5 command path already exists for the explicit forms.
11. **Explicit day+time works**: `appointment with the cardiologist on the 19th at 2:15`
    → Wed Aug 19 14:15; `soccer game Saturday 9am at Riverdale field` → Sat Aug 8 09:00;
    `check in opens 24 hours before at 6:40am` → Tue Aug 4 06:40;
    `the twins have a dentist appointment on the 12th` → Wed Aug 12.
12. **`every other Wednesday` and `every Thursday` build correct recurrences**
    (`weekly ×2 days[4]`, `weekly ×1 days[5]`).

---

## Files

| file | utterances | purpose |
|---|---|---|
| `domains/work.txt` | 59 | knowledge work |
| `domains/parenting.txt` | 48 | school, kids, family |
| `domains/health.txt` | 48 | dosages, appointments, symptoms |
| `domains/money.txt` | 48 | bills, taxes, account numbers |
| `domains/home.txt` | 45 | repairs, measurements, vehicle |
| `domains/travel.txt` | 30 | flights, codes, packing |
| `domains/social.txt` | 34 | people facts, gifts, condolences |
| `domains/learning.txt` | 32 | books, ideas, quotes |
| `domains/rambling.txt` | 35 | dense multi-topic real captures |
| `domains/{shorthand,cancels,deletion,nophrase,compound,markers,persons,refdetail,refdetail2,deadline,firstmonth,errands,dosage,clockdigits,completed}.txt` | 287 | mechanism isolation |

`domains/fmt.py` compacts probe output; `domains/lossscan.py` flags utterances whose
words are missing from every output field.
