# Lane: register — dialect, non-native grammar, slang, code-switching, accented ASR

**688 distinct utterances probed** (711 rows produced), across non-native word order,
British/Irish/Australian/Indian/Singaporean/African English, informal and young register,
code-switching and loanwords, politeness scaffolding, and plausible accent-driven
misrecognitions. Every A/B pair below was run against its North American control in the
same probe run, so the deltas are the register effect, not baseline noise.

**Verdict: the lane is not clean.** The pipeline is materially narrower than "English".
Four clusters produce *confidently wrong* times or dates rather than no time at all, which
is the failure the brief singled out. Two more silently invent content. The rest cost
routing.

Frame of reference throughout: **Monday 2026-08-03 10:00 America/Toronto**.

---

## Root-cause clustering

| # | Cluster | Sev | Utterances hit | Primary site |
|---|---|---|---|---|
| C1 | `remind me at <unparsed time>` → geofence at a place that does not exist | CRITICAL | 24 | `LocationIntentParser.swift:47-51` |
| C2 | Spoken clock face fails → bare-clock fallback takes the *offset* as the hour | CRITICAL | 11 | `ThoughtOrganizer.swift:2296-2303` / `2337-2375` |
| C3 | Day-month date order ("15 August") → resolves to **today**, or to nothing | CRITICAL | 8 | `ThoughtOrganizer.swift:2158-2170` |
| C4 | Zero-padded 24-hour times 01:00–07:59 flipped to PM | CRITICAL | 5 | `ThoughtOrganizer.swift:2388-2418` |
| C5 | `pureFillers` deletes "oh"/"ah"/"er" from the middle of names | CRITICAL | 6 | `SpeechRepair.swift:27, 120-122` |
| C6 | "kindly" is invisible as politeness scaffolding; flips route both ways | BEHAVIORAL | 9 | `Actionability.swift:146` + `actionBody` filler list |
| C7 | Non-North-American action verbs missing from `actionVerb` | BEHAVIORAL | 17 | `Actionability.swift:70-77` |
| C8 | Dropped infinitive `to` / dropped auxiliary kills the obligation lead | BEHAVIORAL | 14 | `Actionability.swift:86` |
| C9 | Leading adverb / discourse marker becomes a fabricated person | BEHAVIORAL | 15 | `PersonMention.swift` |
| C10 | Apologetic + announcement scaffolding → junk rows, lost reminders | BEHAVIORAL | 8 | clause splitter, upstream of `SpeechRepair` |
| C11 | "Sunday week" resolves a week early | CRITICAL (narrow) | 2 | weekday resolver |
| C12 | Non-Western grocery vocabulary falls to `list=Other` | METADATA | 12 | `ShoppingGroups.swift` |

---

## C1 — CRITICAL — `remind me at <time>` becomes an arrival geofence at a nonexistent place

**Mechanism.** `LocationIntentParser.leads` ends with an unconditional lead
`\b(?:remind|tell|ping|alert)\s+(?:me|us)\s+at\s+` (`LocationIntentParser.swift:72-79`).
The only thing stopping it from eating a *time* is `clockPhrase`
(`LocationIntentParser.swift:47-51`), which is anchored `^` and lists exactly:
digits, `noon|midnight|half past|quarter past|quarter to`, the bare hour words, and
`this time|the same time`. Anything else after "at" is treated as a searchable place name.

The result is not "no reminder". It is a **location reminder for a place that cannot be
geocoded** — so nothing ever fires, and the row shows a place trigger the user never asked
for. This is the single worst finding in the lane, and every hit is a register form.

| utterance | observed | expected |
|---|---|---|
| `remind me at half five to take the bins out` | `Take the bins out` \| `location=arrive named(half five)` | reminder at 17:30 |
| `remind me at half twelve` | `Your reminder` \| `location=arrive named(half twelve)` | reminder at 12:30 |
| `remind me at seventeen thirty to call the bank` | `location=arrive named(seventeen thirty)` | reminder at 17:30 |
| `remind me at eighteen hundred to call mum` | `location=arrive named(eighteen hundred)` | reminder at 18:00 |
| `remind me at zero nine hundred to call the bank` | `location=arrive named(zero nine hundred)` | reminder at 09:00 |
| `remind me at teatime to call the bank` | `location=arrive named(teatime)` | ~17:00–18:00 |
| `remind me at breakfast to take my tablets` | `location=arrive named(breakfast)` | morning anchor |
| `remind me at sharp 5 to call the bank` | `location=arrive named(sharp 5)` | 17:00 |
| `remind me at around half five to call mum` | `location=arrive named(around half five)` | 17:30 |
| `remind me at sixish to call the bank` | `location=arrive named(sixish)` | 18:00 |

Full list of the 24 fabricated place names observed: `half five`, `half two`,
`half twelve`, `quarter five`, `about half five`, `around half five`, `fife thirty`,
`tree o'clock`, `tree pass four`, `twenty pass eight`, `seventeen thirty`,
`eighteen hundred`, `zero nine hundred`, `teatime`, `tea time`, `supper`, `breakfast`,
`first light`, `sunset`, `close of play`, `knocking off time`, `sharp 5`, `sixish`.

Note the shape of the affected populations: British/Irish half-hour speech, everyone who
speaks a 24-hour clock (most of Europe, India, Latin America, much of Asia), Indian English
`sharp N`, and any hedged time. `remind me at lunch`, `at 5`, `at 17:30`, `at noon`,
`at midnight`, `at EOD`, `at 5 sharp`, `at 6ish`, `at half past five` all work correctly —
so this is a whitelist that stopped one step short.

## C2 — CRITICAL — the spoken clock face fails and the *offset* is read as the hour

**Mechanism.** `spokenClockFace` (`ThoughtOrganizer.swift:2337-2375`) requires the exact
words `past|after|to|till|til|before|of`. When the recognizer renders the connective
differently, that function returns nil and control falls to the bare-clock rule at
`2296-2303`, which takes the **first** hour-shaped token after `at`. In "ten past six" that
token is `ten`. So the sentence still produces a confident time — the wrong one, by hours.

| utterance | observed due | expected |
|---|---|---|
| `call the bank at ten pass six` | **Mon Aug 3 22:00** | 18:10 |
| `meeting at ten passed six` | **Mon Aug 3 22:00** | 18:10 |
| `meeting at ten too six` | **Mon Aug 3 22:00** | 17:50 |
| `meeting at ten two six` | **Mon Aug 3 22:00** | 17:50 |
| `call the bank at five pass six` | **Mon Aug 3 17:00** | 18:05 |
| `remind me at nine hundred hours to call the bank` | **REM Mon Aug 3 21:00** | 09:00 |
| `call mum at six terty` | **Mon Aug 3 18:00** | 18:30 |
| `meeting at nine terty tomorrow` | **Tue Aug 4 09:00** | 09:30 |

`to`→`too`/`two` and `past`→`passed`/`pass` are ordinary homophone renderings, not exotic
ones; `ten past six` and `ten to six` are the *default* way most of the English-speaking
world states those times. Control: `at ten past six` → 18:10 correctly, `at ten to six` →
17:50 correctly.

**Second face of the same cluster:** when `half five` survives to the temporal layer it
does not produce a wrong hour, it drops to day-only — and a day-only reminder then alerts
at the 09:00 default, which *is* a wrong alarm:

- `alarm for half six tomorrow morning` → **REM Tue Aug 4 09:00, delivery: alarm**
  (user asked for 06:30; alarm rings 2.5 h late)
- `remind me tomorrow at half nine to ring the bank` → **REM Tue Aug 4 09:00** (wanted 09:30)
- `remind me at half five tomorrow to call mum` → **REM Tue Aug 4 09:00** (wanted 17:30)

And a further 9 utterances silently lose the stated time altogether (no wrong alarm, but
the row is wrong): `the train is at half eight tomorrow` → `Tue Aug 4 (day only)`;
`the appointment is at half eleven on Thursday` → `Thu Aug 6 (day only)`;
`meet Sarah at half five` → no due; `I've got a viewing at half two` → Memory note;
`lunch with Aoife at half one` → Memory note; `the match is on at half eight` → Memory note.

Safe failures worth preserving: `set an alarm for half six` and `wake me at half seven`
both produce `needsReview` with no time. That is the correct shape.

## C3 — CRITICAL — day-month date order resolves to today, or vanishes

**Mechanism.** `monthAndDay` (`ThoughtOrganizer.swift:2104-2178`) reads month-first
("August 15") and a reversed form that **requires the word `of`** ("the 15th of August",
line 2163). The bare day-month order has no branch, so the ordinal is claimed by the
day-of-month parser, which knows nothing about months — the exact failure the comment at
2158-2162 documents for the `of` case.

| utterance | observed | expected |
|---|---|---|
| `the meeting is on 15 August at 11` | **Mon Aug 3 11:00** | Sat Aug 15 11:00 |
| `the meeting is on 15th August at 11` | **Mon Aug 3 11:00** | Sat Aug 15 11:00 |
| `dentist on 3 November at 2` | **Mon Aug 3 14:00** | Tue Nov 3 14:00 |
| `exam on 20 October at 9` | **Mon Aug 3 21:00** | Tue Oct 20 09:00 |
| `my flight is on 22 September` | Memory/note, **no date** | Today, Tue Sep 22 |
| `the wedding is on 12 December` | Memory/note, **no date** | Sat Dec 12 |
| `book the ticket for 15th August` | Today/task, **no date** | Sat Aug 15 |
| `pay the rent on 1 September` | Today/task, **no date** | Tue Sep 1 |

Controls all pass: `on August 15 at 11` → Sat Aug 15 11:00; `on the 15th of August at 11`
→ Sat Aug 15 11:00; `on November 3 at 2` → Tue Nov 3 14:00.

Day-month is the spoken standard in the UK, Ireland, Australia, NZ, India, and essentially
all of Europe, Africa and Latin America. When a clock time is present the app does not
degrade to "no date" — it commits to **today**, which is the worst available answer.

## C4 — CRITICAL — zero-padded 24-hour times 01:00–07:59 are flipped to PM

**Mechanism.** `defaultedBareHourOnNamedDay` (`ThoughtOrganizer.swift:2388-2418`) ends with
`guard (1...7).contains(time.hour)` → `hour + 12`. It never asks whether the hour was
zero-padded or whether an explicit minute was supplied. A leading zero is only ever
produced by someone using a 24-hour clock, and it is unambiguously morning.

| utterance | observed | expected |
|---|---|---|
| `the train leaves at 06:20 tomorrow` | **Tue Aug 4 18:20** | Tue Aug 4 06:20 |
| `the train leaves at 06:20 on Friday` | **Fri Aug 7 18:20** | Fri Aug 7 06:20 |
| `my flight is at 07:15 tomorrow` | **Tue Aug 4 19:15** | Tue Aug 4 07:15 |
| `call at 01:00 tomorrow` | **Tue Aug 4 13:00** | Tue Aug 4 01:00 |
| `the ferry is at 05:45 on Saturday` | Memory/note, day-only, time dropped | Sat Aug 8 05:45 |

`08:45`, `09:00`, `11:00`, `12:30`, `14:00`, `16:45`, `22:15` all resolve correctly, and
`set an alarm for 05:30 tomorrow` is rescued by the alarm rule. So the defect is confined
to 01–07 with a leading zero — but that band is exactly the early-train / early-flight
band, where a 12-hour error is the most expensive.

Related but **not** register-specific, so flagged separately rather than counted here:
`be up at 6 tomorrow`, `I need to wake up at 6 tomorrow`, `I need to get up at 6 tomorrow`
and `gotta be up at 6 tomorrow` all resolve to **18:00**. `committedAlarmHour`
(`ThoughtOrganizer.swift:2318-2331`) only recognises `set an alarm|alarm for/at|wake me`.
"Be up"/"get up"/"wake up" are the ordinary way to say the same thing. No reminder is
attached, so this is a wrong *due date* rather than a wrong alarm — but it is the same
family.

## C5 — CRITICAL — "oh", "ah", "er" are deleted from the middle of names

**Mechanism.** `SpeechRepair.pureFillers` (line 27) is
`um+|uh+|erm|er|hmm+|mm+|mhm|oh|ah`, and lines 120-122 strip it **anywhere** in the string,
not just at sentence edges. `Oh` is a top-10 Korean surname; `Ah` is the standard
Chinese/Hokkien/Cantonese familiar prefix; `Er` is a Singaporean professional honorific.

The word is gone from the title **and from the row's preserved quote**:

| utterance | observed row / quote | expected |
|---|---|---|
| `remind me to call Mr Oh tomorrow` | title `Call Mr`, quote `remind me to call Mr tomorrow`, **person nil** | person = Oh |
| `call Oh Se-hun about the tickets` | title `Call Se-hun`, quote `call Se-hun about the tickets` | Oh Se-hun |
| `remind me to call Ah Mei tomorrow` | title `Call Mei`, quote `remind me to call Mei tomorrow` | Ah Mei |
| `call ah ma tonight` | title `Call ma tonight`, quote `call ma tonight` | Ah Ma |
| `remind me to call ah gong on Sunday` | title `Call gong on Sunday` | Ah Gong |
| `remind me to call Er Tan tomorrow` | title `Call Tan`, person `Tan` | Er Tan |

`--repairs` confirms the stage: `disfluency: remind me to call Mei tomorrow`.

The strip is doing real work elsewhere (`tomorrow call the bank ah` → `Tomorrow call the
bank` is correct), so the fix is positional/contextual, not removal.

## C6 — BEHAVIORAL — "kindly" is invisible, and flips routing in both directions

**Mechanism.** `please` and `just` are in `recordingFrame` (`Actionability.swift:146`) and in
the leading-filler strip that `actionBody`/`hasActionVerbHead` uses. `kindly` is in neither.
So `kindly <action verb>` fails `hasActionVerbHead` and falls to Memory, while
`kindly note that …` fails `recordedFactBody` and escapes to Today as an event.

Clean A/B, same run:

| utterance | observed | control |
|---|---|---|
| `kindly send the report to my manager tomorrow` | **Memory/note**, no due | `send the report…` → Today/task, due Tue Aug 4 |
| `kindly book the flight for Friday` | **Memory/note**, no due | `book the flight for Friday` → Today/task, due Fri Aug 7 |
| `kindly add milk to the shopping list` | **Memory/note**, no shopping row | `add milk…` → Today/shopping, list Groceries |
| `kindly note that the rent is due on the fifth` | **Today/event**, due Wed Aug 5 | `please note that…` → Memory/note |
| `kindly do the needful regarding the visa papers` | **Memory/note** | `please do the needful before EOD` → Today/task |
| `kindly send the report only after lunch` | **Memory/note** | Today/task |
| `could you please add eggs and milk to the list` | **Memory/note**, no rows | `please add eggs and milk…` → Today/task |
| `kindly revert back to me on this` | **Memory/note** | Today/task |

`kindly remind me to …` works (the reminder path is separate), which is why this looks
narrower than it is. Both directions of the Today/Memory contract are violated.

## C7 — BEHAVIORAL — non-North-American action verbs are missing from `actionVerb`

`Actionability.swift:70-77` is a closed verb list. It has `call` and `phone` but not `ring`;
`go` but not `pop`/`nip`; `message`/`text` but not `hit up` or the light-verb forms
("give X a ring", "shoot X a text", "hop on a call"). A capture whose only verb is one of
these has no recognisable action, so it lands in Memory and loses any time it carried.

Clean A/B:

| register form | observed | control |
|---|---|---|
| `ring the bank` | **Memory/note** | `call the bank` → Today/task |
| `ring the surgery in the morning` | **Memory/note** | `call the surgery in the morning` → Today/task |
| `ring the tradie about the fence` | **Memory/note** | `call the tradie…` → Today/task |
| `pop to the shops for milk and bread` | **Memory/note** | `go to the shops…` → Today/task |
| `nip to the chemist for paracetamol` | **Memory/note** | `go to the chemist…` → Today/task |
| `hit up the landlord about the leak` | **Memory/note** | `message the landlord…` → Today/task |
| `shoot Dana a text about Friday` | **Memory/note, person dropped** | `send Dana a text…` → Today/task, person Dana |
| `hop on a call with Sam at 11` | **Memory/note, no due** | `call Sam at 11` → Today, due 11:00 |
| `loop in Priya on the email tomorrow` | **Memory/note, no due, person dropped** | `email Priya tomorrow` → Today, due Aug 4, person Priya |
| `crack on with the taxes this weekend` | **Memory/note, no due** | `start the taxes this weekend` → Today, due Sat Aug 8 |

Also in this family, lower confidence: `give mum a ring this evening`, `give Dave a bell`,
`chuck the receipts in the drawer`, `jump on a call with the team tomorrow`,
`gonna cop groceries after work`, `open the AC at 9 tonight` (Indian English "open the
light/AC" is read as `descriptiveVerb` → knowledge), `Sir wants the file by Friday`.

`ring mum tomorrow` *appears* to work — but only because `tomorrow` rescues it through
`isCalendarCommitment`; it lands as an **event**, not a task.

Honest note: `chuck the old router in the bin` and `scope out a new dentist this week` also
fail with their North American controls (`throw…`, `find…`), so those are not register
findings. Only the pairs listed above show a register delta.

## C8 — BEHAVIORAL — dropped infinitive `to` and dropped auxiliaries kill the obligation lead

`obligationLead` (`Actionability.swift:86`) lists `need to`, `want to`, `have to` — never
bare `need`/`want` + bare infinitive, which is the single most common L2 English pattern.
`must` and `should` *are* bare, which is why "I must to call the bank" survives and
"I want buy milk" does not.

| utterance | observed | control |
|---|---|---|
| `I want buy milk` | **Memory/note** | `I want to buy milk` → Today/shopping, Groceries |
| `I need buy bread and eggs` | **Memory/note, 1 row** | `I need to buy bread and eggs` → **2** Today/shopping rows |
| `I need go pharmacy today` | **Memory/note**, no due | `I need to go to the pharmacy today` → Today/task, due Mon Aug 3 |
| `tomorrow I go to dentist` | **Memory/note**, no due | `tomorrow I am going to the dentist` → Today/event, due Tue Aug 4 |
| `tomorrow after work I go to supermarket` | Memory/note, **no due** | control → Today/event, due Tue Aug 4 17:00 |
| `I ave to call the bank tomorrow` (dropped h) | **Memory/note** | `I have to…` → Today/task |
| `I am not remember to pay the bill` | Memory/note | Today |
| `I will to send the email in the evening` | Memory/note, **temporal lost entirely** | — |
| `I am wanting to book the flight next week` | Memory/note, **`next week` lost** | — |
| `my wife say we need buy new fridge` | Memory/note | Today |

Also here: `I need to be reminded for my medicine every morning` → recurs daily, due
Tue Aug 4 09:00, but **remind: nil**. The control `remind me to take my medicine every
morning` sets the reminder. A recurring medicine reminder that never fires.

Honest scoping: **verb-final and topic-fronted order is fine.** `the bank I must call
tomorrow`, `to the bank I must go tomorrow`, `tomorrow the dentist I have to see` all route
to Today with the right date. Tag questions (`you are coming tomorrow isn't it`,
`the meeting tomorrow is it at 3`) are fine too. The damage is specific to the missing `to`
and the missing auxiliary, not to word order.

## C9 — BEHAVIORAL — a leading adverb or discourse marker becomes a fabricated person

Fifteen fabricated person records observed. These create a contact and, in several cases,
pull the row into the People surface.

`person=Deffo`, `person=Definitely`, `person=Lowkey`, `person=Highkey`, `person=Imma`,
`person=I'm Gonna`, `person=Brb Gotta`, `person=Bet I'll`, `person=Round`
(`call round to my mam's on Sunday` — control `go round to my mam's` gives the correct
`person=Mam`), `person=Manager` (`I have meeting with manager…`; the control with the
article `my manager` correctly extracts nobody), `person=Fortnight`
(`schedule the appointment for a fortnight's time`), `person=Eid`
(`remind me to send Eid money to my nephew`), `person=De` ×2 (`call de bank at 3`,
`call de doctor…` — Caribbean/Irish-influenced "de" for "the"), `person=Homie`,
`person=Bro`.

`person=Definitely` and `person=I'm Gonna` prove this is **not purely a slang problem** —
it is a general unknown-leading-token heuristic that slang and dropped articles merely
expose more often. Weight the fix accordingly.

Two more in this family that lose a real name instead of inventing one:
`call tía Rosa tomorrow at 4` and `call tia Rosa tomorrow at 4` → **no person at all**,
while `call aunt Rosa tomorrow at 4` → `person=Aunt Rosa`.

## C10 — BEHAVIORAL — apologetic and announcement scaffolding produces junk rows

The clause splitter treats "one more thing" / "a quick note" as a boundary mid-sentence,
orphaning whatever preceded it into a row of its own — and in the "sorry" case it also
mangles the word.

| utterance | observed |
|---|---|
| `sorry one more thing remind me to buy milk` | row 1 title **`Rry`**, quote **`rry`**; row 2 `Buy milk` |
| `sorry one more thing call the bank` | row 1 **`Rry`**; row 2 `Call the bank` |
| `worry one more thing call the bank` | row 1 `Worry`; "one more thing" gone from every quote |
| `just a quick note please remind me to call the bank` | row 1 `A quick`; row 2 `Please remind me to call the bank` → **Memory, reminder lost** |
| `sorry to bother you but remind me to pay the rent` | single row titled **`Sorry to bother you`** — the task is gone from the title |
| `give me a missed call tomorrow` | row 1 `Give me a missed`; row 2 `Call tomorrow` |
| `I vill call the bank tomorrow` | row 1 `I vill`; row 2 `Call the bank tomorrow` |
| `I must to remember buy milk` | row 1 `I must to remember`; row 2 `Buy milk` |

`one more thing call the bank` (no apology) is handled correctly — the announcement is
stripped and one clean row results. The bug is only when something precedes it.
Also lost outright: `may I request a reminder to call the bank tomorrow` and
`I'd appreciate a reminder to call the bank tomorrow` → Memory/note, **no reminder**.

## C11 — CRITICAL (narrow) — "Sunday week" resolves a week early

`on Sunday week we have the christening` → **due Sun Aug 9**; the Irish/British/Australian
"Sunday week" means the Sunday of next week, **Sun Aug 16**.
`I'm off on holiday Sunday week` → same, Sun Aug 9 instead of Aug 16.
The app produces a confident date exactly one week early. Narrow in frequency, but it is a
wrong date rather than a missing one, hence the severity.

## C12 — METADATA — non-Western grocery vocabulary falls to `list=Other`

`list=Other` for: `dahi`, `roti`, `naan`, `paneer`, `chai`, `mochi`, `matcha`, `siu mai`,
`char siu`, `pan dulce`, `Brötchen`, `pierogi`.
`list=Groceries` for: `kimchi`, `tofu`, `tortillas`, `frijoles`, `bok choy`, `ginger`.
Nothing acts wrongly on it; the items still reach a shopping list. Inconsistent enough to
be visible to a user whose whole basket is "Other".

---

## Unsupported but harmless — out of scope for a rule-based English parser shipping today

These produced **no date and no wrong behaviour** — the app declined rather than guessed.
I would not fix these before C1–C5, and several I would not fix at all.

- `fortnight` as a duration: `I'll see the dentist in a fortnight` → Memory/note, no date.
  (`we're away for a fortnight from Saturday` correctly dates the *start*.)
- `this arvo` / `Sunday arvo`: ignored, falls back to day-only. `call the letting agent this
  arvo` → Today/task, no due.
- `prepone`: `prepone the meeting to Tuesday` → Today/event, due Tue Aug 4 — arguably right
  by accident. `can we prepone the call to 11` → Memory/note.
- `mañana` / `manana`: `remind me manana to call the bank` → needsReview, no date. Correct
  shape of failure.
- Whole non-English sentences (`je dois appeler la banque demain`,
  `ich muss morgen die Bank anrufen`, `mañana tengo cita con el dentista`) → Memory/note.
  Correct: the app is English-only and did not invent anything.
- Nigerian Pidgin aspect markers (`I dey go`, `I go call`, `we go meet`, `she don finish`)
  → Memory/note. Genuinely out of scope. (The junk-row split on `she don finish` belongs
  to C10, not here.)
- French/European `19h30`, `9h`, `15h` time format → day-only. Declines cleanly.
- `next to next week`, `last to last week`, `coming Monday`, `tomorrow itself`,
  `today itself` → no date or Memory. Declines cleanly.
- `can or not tomorrow at 3` → Mon Aug 3 15:00. Traced to a general `not tomorrow` negation
  rule (`not tomorrow at 3` behaves identically); the Singlish tag question is not the
  cause. Low value, do not chase.

---

## Already correct — guards to preserve through any fix

Probed deliberately; all behaved well and any fix must not regress them.

**Names.** Diacritics and non-Anglo names are handled correctly:
`José`, `Jose`, `Zoë`, `Renée`, `François`, `Nguyễn`, `Björn`, `Müller`, `Siobhán`,
`Ngozi`, `Oluwaseun`, `Xiaoli`, `D'Angelo`, `Mary-Anne`, `Jean-Luc`, `Ng` — every one
extracted as `person` with the correct due date.

**Kinship loanwords.** `abuela`, `maman`, `oma`, `nonna`, `yaya`, `lola`, `mama`, `baba`,
`papi`, `didi`, `thatha`, `kuya`, `jiejie`, `ate`, `chachu`, `gong gong`, `mi amor` all
extract as people and route to `personFollowUp` with reminders intact.

**Loanword shopping.** `kimchi and tofu`, `tortillas and frijoles`, `bok choy and ginger`,
`buy chai and biscuits`, `buy Brötchen` all become shopping rows on Today.

**Religious/cultural nouns.** `book the puja for Saturday`, `book the mandap for the
twelfth`, `remind me about suhoor tomorrow`, `Diwali is on the twentieth remind me to buy
sweets` (due Thu Aug 20, reminder set), `remind me insha'Allah to call the bank tomorrow`
(politeness particle correctly ignored, reminder set for Tue Aug 4).

**Dictation repairs that genuinely help accented speech.** `ate` → `eight`
(`at ate o'clock` → 20:00; `meeting at ate tomorrow` → Tue Aug 4 08:00; `ate thirty` →
20:30). `pee em`/`ay em` → pm/am (`seven pee em` → 19:00; `six ay em tomorrow` → alarm at
Tue Aug 4 06:00). `6ish` → `around 6` → 18:00. `17:30` → `5:30 pm`. These are real wins;
`SpeechRepair` helps far more than it hurts, with C5 the single exception.

**Spoken clock face, canonical forms.** `half past five` → 17:30, `quarter past six` →
18:15, `quarter to six` → 17:45, `ten past six` → 18:10, `twenty past eight` → 20:20,
`ten to six` → 17:50, `at noon` → 12:00, `at midnight` → Aug 4 00:00.

**Bare-modal L2 forms.** `tomorrow I must to call the bank`, `we must to book hotel for the
trip`, `I should to buy gift for Anna`, `must remember to pay the fine` all route to Today
correctly — `must`/`should` being bare in `obligationLead` is what saves them.

**Word order.** Topic fronting, verb-final order, and tag questions all survive (see C8).

**British day/date vocabulary.** `on the fourteenth` → Fri Aug 14, `on the first` → Tue Sep
1, `for the twelfth` → Wed Aug 12, `before the end of the month` → Mon Aug 31,
`bank holiday Monday` → Mon Aug 10, `sort out the insurance before Friday` → Fri Aug 7,
`post the letter tomorrow`, `put the bins out tonight` → Mon Aug 3 20:00.

**Safe declines under `remind`/`alarm`.** `set an alarm for half six`, `wake me at half
seven`, `set a reminder for half five`, `remind me at half past to call the bank` — all
`needsReview` with no invented time. This is the shape C1 should adopt.

---

## Files and lines

- `SpeakIt/Repositories/LocationIntentParser.swift:47-51` — `clockPhrase` (C1);
  `:72-79` — the unconditional `remind me at` lead.
- `SpeakIt/Repositories/ThoughtOrganizer.swift:2296-2303` — bare-clock fallback (C2);
  `:2337-2375` — `spokenClockFace`; `:2388-2418` — `defaultedBareHourOnNamedDay` (C4);
  `:2318-2331` — `committedAlarmHour`; `:2104-2178` — `monthAndDay` (C3).
- `SpeakIt/Repositories/SpeechRepair.swift:27` — `pureFillers`; `:120-122` — the global
  strip (C5).
- `SpeakIt/Repositories/Actionability.swift:70-77` — `actionVerb` (C7); `:86` —
  `obligationLead` (C8); `:146` — `recordingFrame` (C6).
- `SpeakIt/Repositories/PersonMention.swift` — leading-token person heuristic (C9);
  the stop-word set at `:800-810` is the likely place to widen.
- `SpeakIt/Features/Shopping/ShoppingGroups.swift` — grocery vocabulary (C12).

Corpus and raw output:
`/private/tmp/claude-501/-Users-calvinwak-Documents-Speak-It/2d496464-c81e-4d5d-a491-7fc31108d195/scratchpad/register/`
(`all.txt` = 688 deduplicated utterances, `all-out.txt` = full probe output,
`fmt.py` = the compact formatter).
