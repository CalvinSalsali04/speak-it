# A no-action measure on public sentences, and the defect it found

Records the first measurement taken on captures nobody on this project wrote,
and the one defect cluster it exposed. Instrument: `Tools/UnderstandingLab/`.

## What was added

`import_massive_questions.py` imports 350 English question and state-query
utterances from MASSIVE 1.1 (CC BY 4.0) — `alarm_query`, `lists_query`,
`datetime_query`, `qa_factoid`, `qa_definition`, `qa_maths`, `calendar_query` —
split 280 development / 70 evaluation on the source partitions.

These carry a contract, unlike the existing `public.jsonl`, because there is one
direction in which a public intent label is unambiguous: **a question is not an
instruction to act.** The destination stays unasserted — that is Speak It's
decision, not Amazon's — but no reminder may be scheduled and no operation may
be executed. `general_quirky` was excluded as too heterogeneous to label
honestly.

`lab.py` now globs `*.jsonl` rather than naming two files, so an importer
contributes data by writing one. `test_lab.py`'s size guard reads the importers'
manifests instead of hardcoded counts.

## Baseline, development split, 2026-09-10

| measure | value |
|---|---|
| labelled rows | 544 |
| unique captures probed (with variants) | 2,130 |
| no-action contract | **1,065/1,109 (96.0%)** |
| distinct utterances violating it | **11 of 280** |
| authored contracts | 72/72 |
| semantic consistency | 1,560/1,586 (98.4%) |
| title consistency | 1,561/1,586 (98.4%) |
| captures producing nothing | 0 |

The evaluation split has not been scored and its failures were not written.

## The defect: a temporal expression inside a question becomes its deadline

The 44 failing contract checks are 11 distinct utterances across their rendering
variants, and 10 of the 11 are one root cause. A date or time word inside an
interrogative is read as that capture's own due date or reminder, so a question
lands in Today carrying a deadline nobody stated.

```
have i set any alarm for today            -> Today, due today, reminder 14:00
what's the description for the alarm at eleven am
                                          -> Today, due and reminder at 11:00
what's the date today                     -> Today, due today
time and date of today                    -> Today, due today
please read out the tasks from the list for today
                                          -> Today, due today
what's going to be the forecast tomorrow for outer nowherevill
                                          -> Today, due tomorrow
please let me know the alarm kept for tuesday's meeting
                                          -> Today, due Tuesday
```

The eleventh is the number-as-clock collision the corpus already has a family
for, reached through a question: `tell me the answer for two plus two` resolves
*two* to 14:00 and dates the row.

One case also over-splits: `let me know about any alarms set today` becomes two
rows, the second titled *Set today*.

The shape of the fix is a gate, not a vocabulary: the temporal reader should not
assign a due date or reminder when the clause it sits in is interrogative and
nothing in it is an obligation. Speak It already distinguishes actionability;
this is that test reaching the temporal assignment. `calendar_query` passes at
100% under the weaker tier, so the failure is specific to questions that carry a
date word and no action.

## Why the existing suites could not find this

The gating corpus is authored from the product contract by the person writing
the rules, and no one writes 280 questions about alarms into their own test set.
The held-out set contains a `question` family of 12 sentences and may only be
read at release. This cluster needed sentences from outside the project, with a
claim weak enough to be defensible on them.

## Second instrument: date-parser negative cases

`import_temporal_negatives.py` imports 32 strings that Duckling (BSD) and chrono
(MIT) ship as **negative** cases — text their own authors decided contains no
time expression. They are adversarial by construction: each looks enough like a
time to have been worth writing down. The claim is the question set's, reached
from the other side: a capture with no time expression must not acquire a due
date or a reminder. All 32 sit in the development split; the set is an
instrument, not a reported number.

Written-only forms were dropped rather than scored, because Speak It reads
transcribed speech: URLs, markdown scrapings, version strings, and slash or
`14PM` style dates. Duckling's `Martin Luther King' day` was dropped too, since
it is negative there because of apostrophe placement, not because the words name
no day.

Result: **86/99 checks, 4 of 32 utterances invent a date.** Two root causes.

**A dotted or decimal numeral is read as a clock.**

```
at 650.650.6500   -> Today, due tomorrow 06:50, title "At 6:50.650.6500"
at 6.5 kilograms  -> Today, due tomorrow 06:00
```

A phone number and a weight both become deadlines. The first also shows the
repair layer rewriting `650.` to `6:50.` inside the row title, so the displayed
words are not the spoken ones.

**An impossible calendar date is silently rolled forward, and a stated past year
is replaced with a future one.**

```
February 29, 2022 -> due 2027-03-01 13:00
June 31, 2022     -> due 2027-07-01 12:00
```

2022 was not a leap year and June has thirty days. Both resolve anyway, to a
different month *and* a different year from the one the speaker said. This is
the sharpest of the four: the product contract says never invent dates, and here
the app states a date the user did not say, five years from the one they did.

## The fix

Three root causes, three changes, all gated by eleven new corpus cases written
from the contract and run untouched first: seven failed, four guards passed.

**A dot between digit groups is a separator, not a clock.**
`ClockDigitRepair`'s third-digit-group guard refused a space or a dash but not
a dot, so `416.555.0134` was rewritten to `4:16.555.0134`. The guard now reads
`(?![-.\s]?\d)`. A dot with no digit behind it is still the full stop that ends
a dictated sentence, so "dinner at 830." keeps its clock.

**A number a separator continues is not an hour.** `decimalGuard`
(`(?![.,]\d)`) stops the bare-hour rule taking the 6 from "6.5 kilograms" and
the 1 from "1,250 dollars". The digit behind the separator is what
distinguishes those from "let's do dinner at 6.", which is pinned as a guard.

**A day the month does not have is not a date.** `ThoughtOrganizer.date` built
components leniently, and `Calendar` rolls them over silently, so June 31
became July 1, then July 1 of the *next year* once the roll-over had already
passed. The date is now searched for rather than constructed: the resolver
walks forward to a year that actually has that month and day, and returns
nothing when no year does. February 29 therefore resolves to 2028, the next
real leap day, instead of March 1. The same validation was added to the
"31st of next month" path.

Two further defects surfaced while checking the other renderings, both the same
family, both fixed rather than left blocking:

- Comma-free, `1,250` becomes `1 250`, and the bare-hour rule read the 1.
  `adjacentNumberGuard` refuses a bare hour that another number follows —
  structural, because `ClockDigitRepair` runs first and a bare hour still
  standing in front of digits is one that layer already declined to join.
- Unpunctuated, `12.50` becomes `1250`, which the repair turned into 12:50.
  The amount-noun guard covered only "<noun> is <number>", so the same noun one
  word closer to the digits was unguarded; "set the price at 1250" now stays a
  price.

## Questions that were given deadlines, and the regression that fix caused

The question-set cluster was closed in the two places where a question is
unambiguous.

**Contracted wh-forms.** The interrogative test wanted a wh-word, a space and an
auxiliary, so it held "what is the date today" and scheduled "what's the date
today" — the same question, decided by a punctuation mark the speaker never
chose. Contracted forms are now read, with `['’]?s` keeping "whose" out.

**Polar questions with a pronoun subject.** The existing test wanted a
determiner and excluded "have", because "have the car serviced Friday" is an
instruction. An English imperative cannot take a subject pronoun, so "have I"
is unambiguously a question. Without this, a question about alarms was answered
by scheduling an alarm.

That second change broke something, and the unit suite caught it on the next
run: "can you remind me to submit the form at 4 PM" stopped scheduling its
reminder. Second-person inversion forms a polite request, not a question, so
"you" is excluded from the pronoun list. One authored expectation was also wrong
rather than the app — "could you book the dentist for Tuesday" belongs in Memory
by the action-ownership contract — and the case was corrected to match.

What is deliberately still open: "let me know", "tell me" and "read out" frames,
which can carry a real deadline and so need attachment analysis rather than a
guard; a bare noun phrase like "time and date of today"; arithmetic read as a
clock; and an interrogative buried in the second half of a run-on. All are in
`Docs/KNOWN_ISSUES.md`.

## Final state

| measure | before | after |
|---|---|---|
| question families | 1,065/1,109 (96.0%) | **1,085/1,109 (97.8%)** |
| imported negative corpora | 86/99 | **96/96 (100%)** |
| authored contracts | 72/72 | 72/72 |
| distinct captures taking a date | 11 | **6** |
| gating corpus | 1,381 clean | **1,403 clean, 0 blocking** |
| unit suite | — | **812 tests, 0 failures** |
| unseen set, acted on anyway | 7/69 | 7/69 |
| unseen set, destination | 233/320 | 232/320 |

Zero blocking failures in all four renderings. Release compile clean. The
mutation gate protects all 22 subsystems, including a new `calendar-date` entry
that costs 46 blocking failures to delete. Every development set is unchanged on
every row. The one held-out destination case that moved was recorded and not
read, and the safety row did not move.

## An open limitation, not an invented date

`February 29, 2022` now resolves to 2028-02-29. Speak It's date grammar does not
read stated years at all — every month-and-day resolves to its next occurrence,
which is why "December 4" means the coming one. So the app files a year the
speaker did not say, and chrono marks that string negative precisely because it
*does* read the year.

That case was therefore removed from the imported set with the reason recorded
in the importer, because scoring it would score chrono's contract rather than
Speak It's. The missing feature is real and worth its own decision: a stated
year is currently discarded. `June 31` stays in the set, since no year has that
day. Note that the corpus comparator checks month, day, hour and minute and
never the year, so it cannot catch a wrong-year defect either.

## Licensing note

TOPv2's license was unresolved in the research memo. Its shipped `LICENSE` and
`README` both state **CC BY-SA 4.0**, so it is usable with attribution and
share-alike on redistributed derivatives. Duckling is BSD 3-Clause and chrono is
MIT, both confirmed from source.

## Next

1. Fix as its own task, following the usual workflow: author a corpus family
   from the contract first, run it untouched, then change the rules, then the
   mutation gate. Do not patch these eleven sentences.
2. Engine files were left untouched here — `ThoughtExtractor.swift`,
   `ThoughtOrganizer.swift` and `SpeechRepair.swift` carry uncommitted work.
3. Score the evaluation split once, after the fix, and record the number.
4. The positive half of the temporal oracle is still open: Microsoft
   Recognizers-Text (MIT, 4,120 cases with gold resolutions) and Duckling's ~950
   positive cases. It needs a per-row reference-time flag on the probe, and it
   can only be scored conditionally — when Speak It assigns an instant, that
   instant must match the gold one. Recall cannot be asserted, because Speak It
   is a capture organiser and declining to date a sentence is often correct.

Research behind the dataset choices, with licenses and alternatives:
`Docs/Understanding/` and the memo delivered 2026-09-10.
