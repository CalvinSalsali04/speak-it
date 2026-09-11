# Language baseline

The numbers a language change is judged against. Every figure here came from
one run of `Tools/CI/language-metrics.sh` on a real Mac. Nothing in this file
is an estimate, and nothing in it was produced in a container where the parser
cannot run.

**The newest section marked as a baseline is the current baseline.** A section
that records a change which did not ship says so in its first lines. Older
sections stay as written; they are the record of what was true when they were
measured, not a claim about today.

## Three standing rules, two of them learned by paying for them

**Never quote a set total on its own.** On 2026-09-11 `runon.tsv` went from
33/44 to 35/45 on thought count — an improvement by any reading of the total —
while containing a regression that the per-family table made obvious at a
glance: `statement-runon` at 0 of 6 beside `errand-runon` at 6 of 8. The
change that produced the total also broke four cases of the gating corpus. A
total is a weighted average of things that moved in both directions, and it is
the one number that cannot tell you which.

**An instrument's output is the thing under test, not its source.** Four
checks in this repository reported a verdict nobody could act on, and every
one of them had been reviewed by reading its code: a step that wrote failures
to a path nothing collected, the same step skipped on the only run that needed
it, a gate that printed a count and named a command requiring a Mac, and a
mutation harness that ran in an already-broken copy so every measure read as
protected. Run the instrument, read what it prints, and check that a reader
who has only that output can act on it.

A fifth joined them on 2026-09-11, and it is the one that got furthest:
`abandonment-score.py` reads a `KNOWN:` note in the data — a marker written to
*document* a failure — and scores the row as a pass. The report printed
`recall 24/24`, `FALLOUT 0/24` and `documented failures kept on purpose 4` on
adjacent lines, so the contradiction was in the output the whole time and was
read past twice, here and in this file. A figure can come from a real run on a
real Mac, as every figure here does, and still be wrong about the parser. See
"Correction — 2026-09-11" below.

**Every number in this file is the rules path.** `Tools/PipelineProbe` says so
itself: it "runs the **rules path only** … It does not run the Foundation Models
refinement", and `language-metrics.sh` scores through the probe. So 233/320 on
held-out destination is a rules-path figure, and a sentence quoting it as what
an iOS 26 user receives is quoting it wrong.

Today that is exact rather than approximate, and the reason is worth knowing
rather than taking on trust. `RefinementPolicy.shouldRefine`
(`ThoughtExtractor.swift:187`) runs the on-device model only where an item is
already `needsReview`, and not at all above 1,500 characters. For every capture
the rules answered confidently, no refinement happens, so the rules answer *is*
the product answer and the number is the product number.

That makes the caveat a trigger rather than a hedge, and the trigger is one
line of code: **if `shouldRefine` ever fires on anything beyond `needsReview`,
every figure in this file stops describing the product** — not slightly, but for
the whole population that gate newly covers — and stays wrong until an
instrument exists that can run the refined path. Nothing here can measure that
today; `PipelineProbe` has no way to reach it. Whoever widens that gate owns
producing the instrument first.

## Correction — 2026-09-11: the abandonment figures in this file are not what the set scored

**`24/24` and `0/24` are the scorer's numbers, not the set's.** Every place this
file quotes them is marked `†`, and each should be read as unverified until a
macOS run with a repaired scorer replaces it.

`Tools/CorpusRunner/devsets/abandonment-score.py` accepts a fifth column, and a
note beginning `KNOWN:` marks a row documented as failing today and kept on
purpose. The scorer neither excludes such a row from the denominator nor reports
it separately: it credits the row as a **pass**. Recall (lines 83–87) and the
mixed row (116–120) increment the same counter a genuine pass increments, and a
marked `Kept` row (99–102) is credited to its family while skipping
`stats["fallout"] += 1` entirely. Each of those three branches is reached only
*because* the case failed. Four rows of `abandonment.tsv` carry the marker:

| row | expected | what its marker says fails today | figure it inflates |
|---|---|---|---|
| ABN20 `I was going to call Mike scratch that` | Abandoned | no licence catches this without also destroying "I need to scratch that" | recall |
| ABN38 `Never mind the gap` | Kept | the cancel pattern reads a named object as managing an item | **fallout** |
| ABN40 `Never mind, buy milk` | Mixed | a leading withdrawal takes the whole capture, milk included | mixed — not published here |
| ABN46 `Call the dentist and I was going to actually never mind` | Mixed | an earlier "call" makes `ClauseScope` read the whole capture as a message | mixed — not published here |

So if the four markers still describe what the parser does, the figures this
file should carry are **recall 23/24 and fallout 1/24** — and the second is the
one that matters. The scorer's own docstring calls fallout "the number that
decides whether this ships", for the stated reason that a missed withdrawal
leaves a row the person can delete while a wrong one deletes a thought they
meant to keep. A documented fallout of 1, printed as 0, is exactly the reading
that decision must not be made on. The mixed row would move from 7/7 to 5/7;
this file has never published it.

**Neither figure is corrected in place, because neither can be measured from a
Linux container** — the probe that feeds the scorer needs Apple's
`NaturalLanguage`. What is established from source is the defect and which rows
it touches; the fallout reading of 1 was reported by the evaluation thread from
their run. The repaired scorer is theirs to land, and this file takes its real
numbers from the first `language_only` run after it does.

Two smaller consequences of the same branch outlive the arithmetic:

- **The gate cannot fail on a documented fallout.** The scorer ends on
  `sys.exit(1 if (stats["fallout"] or stats["unsafe"] or stats["unseen"]) else 0)`,
  and a `KNOWN:` fallout never increments `stats["fallout"]`. A marker written to
  document a failure also silences the exit code that would have surfaced it.
- **`documented failures kept on purpose (KNOWN:)` counts markers, not
  failures.** It is incremented for every marked row that was scored, whether or
  not that row failed, so it will keep reading 4 after one of them starts
  passing — which is the moment the marker should be removed.

**Nothing else in this file is affected**, and that is checkable rather than
inferred. `KNOWN:` appears in exactly two files in the repository,
`abandonment.tsv` and its own scorer — but the stronger argument is that every
other published denominator reconciles with the label file it came from:

| published | denominator | label file says |
|---|---|---|
| coordination 115/121 | 121 | 121 rows, and a row the probe never emitted counts as a **failure** here, not an exclusion |
| routed 74/84, ambiguous 3/32 | 84 and 32 | 116 rows, 32 carrying `Ambiguous` — 116 − 32 = 84 |
| framing 41/45 | 45 | 45 rows, none ambiguous |
| runon 41/46 | 46 | 46 rows, none ambiguous |
| unfinished 34/57 and 0/96 | 57 and 96 | 57 `Incomplete` and 96 `Complete` of 163 rows |
| held-out 233/320 | 320 | 389 rows, 69 carrying `Ambiguous` — 389 − 69 = 320 |

All of those scorers except coordination's drop a labelled row the probe never
emitted out of the denominator rather than failing it. So a denominator arriving
at exactly its label count is positive evidence that none was dropped on the run
these figures came from. That check is available for every rate above, and it passes for all of
them. It is the check the abandonment figures needed and could not get, because
there the arithmetic departs from the labels by design.

**One scorer would hide the drop next time.** `unfinished-score.py` increments
an `unseen` counter and then never prints it, never records a miss for it, and
never gates on it — the only one of the five that does none of the three.
Coordination counts a missing row as a failure; abandonment prints it, records
it and fails the exit code on it; held-out and everyday both print
`missing probe results`, and everyday's mutation harness checks that the counter
can still report. `unfinished` alone would publish a rate over a shrunken set
with nothing in its output to say so. The reconciliation above is what stands in
for that today, and it is a hand check rather than an instrument.

## 2026-09-11 12:34 — branch at `9d91a0b`, the two guard repairs that shipped

Branch `claude/hearth-thread-tod920`,
[run 34598981239](https://github.com/CalvinSalsali04/speak-it/actions/runs/34598981239),
`macos-26`, `language_only`. **This is the current baseline** once the branch
merges. Two causes: an ordinal is not an amount, and a complement-taking verb
governs the clause behind it.

| instrument | baseline (`2d8fe760`) | shipped (`9d91a0b`) |
|---|---|---|
| gating corpus | 1393, **0 failing** | 1393, **0 failing** |
| everyday routing / count | 168/240 · 193/232 | 168/240 · 193/232 |
| everyday loss / invention / titles | 230/244 · 14/22 · 245/255 | 230/244 · 14/22 · 245/255 |
| everyday over- / under-split | 16 · 23 | 16 · 23 |
| everyday acted on anyway | 0 | 0 |
| held-out destination / count | 233/320 · 255/310 | **233/320 · 255/310** |
| held-out acted on anyway | 7 | 7 |
| adversarial routing / count | 53/116 · 79/105 | **52/116** · **78/105** |
| adversarial over- / under-split | 8 · 18 | **9** · 18 |
| adversarial titles / loss / invention | 117/120 · 113/116 · 10/24 | unchanged |
| adversarial acted on anyway | 1 | 1 |
| **runon dev destination** | 41/46 | **42/46** |
| **runon dev thought count** | 33/44 | **35/44** |

Every other development set is unchanged: coordination 115/121, routed 74/84
and 77/79 with 3 acted on anyway, framing 41/45 and 43/44, unfinished 34/57
recall with 0/96 fallout and 2 unsafe, abandonment 24/24 with 0/24 †.

† Overstated by the scorer; see "Correction — 2026-09-11" above.

**The held-out 389 is back to the baseline figure exactly**, which retires the
−1/+2 seen in the two withdrawn runs: all of that movement belonged to the
causes that came out.

### What it fixed, and what it cost

| row | before | after |
|---|---|---|
| RM03 | destination and count both wrong | **passes both** |
| RO05 "remind me the bins go out on Tuesday" | over-split into 2 | **1 row** |
| one capture in `runon-x-repair` | correct | **over-split** |

`errand-runon` is now 8/8 on destination and 7/7 on thought count.
`object-guard` holds at 10/10 on count with RO05's over-split gone.

**The cost is one sealed capture and it is in the direction that matters
most.** Adversarial over-segmentation went from 8 to 9; a wrongly severed row
retrieves under nothing. The capture cannot be inspected — the set reports
rates only — but the cause can be reasoned to: of the two changes only the
ordinal exemption *enables* a cut, so the complement guard cannot have caused
an over-split.

**It was merged anyway, and this is the reason.** The guard being relaxed is
wrong on its own terms: "the 26th" is a complete noun phrase and "$89" is not,
and keeping a rule that cannot tell them apart because one hard composition
capture happens to benefit from the confusion is the wrong trade. The harm it
was causing is worse than the harm it now causes — a capture that lost its
errand entirely ("Priya starts on the 14th order her a laptop" arriving as one
Memory row) costs the user the task, while an extra row on a hard sentence
leaves both halves visible. The everyday set and the 389 are untouched either
way.

Watch adversarial over-segmentation on the next change. If it moves again, the
ordinal exemption is the first thing to re-examine.

## 2026-09-11 12:25 — why the unit suite fails on a GitHub-hosted Mac: answered

Same run, [34597902006](https://github.com/CalvinSalsali04/speak-it/actions/runs/34597902006),
`iOS app` job, `macos-26`. `SpeakItTests/NaturalLanguageEnvironmentTests` asks
Apple's framework directly instead of inferring it from a behaviour that
failed, and this is the first run in which it has ever executed.

**The lexical-class tagger returns nothing on that runner's simulator.** The
failure messages carry the tagging of each sentence, so the answer is in the
job log rather than in an `.xcresult` nobody can download:

```
on:OtherWord the:OtherWord 15th:OtherWord pay:OtherWord the:OtherWord rent:OtherWord
when:OtherWord I:OtherWord finish:OtherWord the:OtherWord essay:OtherWord call:OtherWord dave:OtherWord
I:OtherWord had:OtherWord better:OtherWord luck:OtherWord last:OtherWord time:OtherWord
```

Every token, in every sentence, is `OtherWord`. Not tagged differently — not
tagged. And the two embedding tests **passed**, so `NLEmbedding.wordEmbedding`
loads on the same machine in the same process. It is specifically `NLTagger`'s
`.lexicalClass` that has no model.

That explains every behavioural failure beside it, and each one is a rule
reading the tagger's silence as a fact:

| assertion | what the rule needed |
|---|---|
| `("on the 15th pay the rent") != ("pay the rent")` | "pay" to be a verb |
| `("when I finish the essay call dave") != ("call dave")` | "finish" to be a verb |
| `("actionable") != ("knowledge")` — *I had better luck last time* | "luck" to be a noun |
| `("ambiguous") != ("actionable")` — *Unpack boxes* | the embedding path, reached only after the tag |
| `"buy the milk tomorrow call the dentist"` arrived as one row | "buy" to be a verb |

The corpus gate passes on the same runner minutes earlier because
`Tools/CorpusRunner` runs on the **host**, where the tagger works. The
difference between the two has never been anyone's diff.

**What this does and does not say.** It says the suite cannot be trusted on a
GitHub-hosted `macos-26` simulator for any tagger-dependent assertion, and that
the author's Mac remains the reference environment. It does **not** establish
that a real iPhone can reach the same state; that is a separate question and
this run cannot answer it. What it does establish is the failure *mode* if one
ever did: not a crash and not an error, but every capture quietly reading as
though it had no verbs in it. Recorded in `Docs/KNOWN_ISSUES.md`.

## 2026-09-11 12:20 — branch at `4af3af9`, the three guard repairs alone

Branch `claude/hearth-thread-tod920`,
[run 34597902006](https://github.com/CalvinSalsali04/speak-it/actions/runs/34597902006),
`macos-26`. **Not a baseline.** It is the control for the section below: the
same branch with the statement boundary removed, so every figure here is the
three guard repairs and nothing else.

**The gating corpus is back to 1393 cases, 0 failing at every severity**, which
settles the attribution: all four CRITICAL regressions were the statement
boundary, and none of them was a guard repair.

| instrument | baseline (`2d8fe760`) | four causes (`90434e9`) | three guards (`4af3af9`) |
|---|---|---|---|
| gating corpus failing | 0 | **4 CRITICAL** | 0 |
| everyday routing / count | 168/240 · 193/232 | 168/240 · 193/232 | 168/240 · 193/232 |
| everyday over- / under-split | 16 · 23 | 16 · 23 | 16 · 23 |
| held-out destination / count | 233/320 · 255/310 | 232 · 256 | **232** · **257** |
| held-out acted on anyway | 7 | 7 | 7 |
| adversarial routing / count | 53/116 · 79/105 | 51 · 76 | **52** · **77** |
| adversarial over- / under-split | 8 · 18 | — | **9** · **19** |
| runon dev destination | 41/46 | 41/46 | 41/46 |
| runon dev thought count | 33/44 | 35/45 | **35/45** |

Every other development set is unchanged: coordination 115/121, routed 74/84
and 77/79 with 3 acted on anyway, framing 41/45 and 43/44, unfinished 34/57
recall with 0/96 fallout and 2 unsafe, abandonment 24/24 with 0/24 †.

† Overstated by the scorer; see "Correction — 2026-09-11" above.

**The everyday set is bit-identical for the third run running.** Neither the
statement boundary nor the guard repairs changed a single one of 255 natural
captures.

### What actually changed, row by row

The `Development-set failures` step now runs on a red run as well as a green
one, so this is read off the log rather than inferred.

| row | before | after | cause |
|---|---|---|---|
| RM03 | count and destination both wrong | **passes** | ordinal is not an amount |
| RO05 "remind me the bins go out on Tuesday" | over-split into 2 | **1 row** | clausal complement |
| RF04 "first thing tomorrow email the landlord about the damp" | over-split into 2 | 1 row, **routed to Memory** | verbless temporal head |
| RE03 "book the car in for Thursday renew my passport" | passes | **merged into 1** | verbless temporal head |
| RE08 "text Marcus about Saturday move the standup to 9:15" | passes | **merged into 1** | verbless temporal head |

Two of the three causes are clean. The third is not, and the row-level view is
the only reason that is visible: at the set level it reads as +2.

### The verbless-temporal-head relaxation is wrong, and why generalises

It accepted any head that carries no verb and ends on a time word, on the
argument that no list of openers can finish while the end of the phrase is
always the time. The argument about openers is right. The conclusion is not,
because **"carries no verb" is the tagger's answer, not a fact.** `NLTagger`
does not reliably call a sentence-initial "book" or "text" a verb, so
"book the car in for Thursday" reads as verbless and ends on a day — an adjunct
by that test, and the errand behind it is swallowed.

The original rule was safe because it *also* demanded a fronting preposition,
which an imperative clause does not have. The preposition is the half of the
test the tagger cannot be wrong about, and it is load-bearing. Removed, with
both captures above kept as the guard in
`ActionabilityTests.testAnAdjunctInFrontOfACutNeedsAPrepositionAndNotJustATime`.

**RF04's real root cause is elsewhere and is the better next target.** Merged
into one row it routes to **Memory**, so `Actionability` does not read
"first thing tomorrow email the landlord about the damp" as an errand at all.
The same fronting vocabulary is the cause in both places; fixing it in the
router is what would make the capture correct, and the over-split was the
symptom rather than the disease.

## 2026-09-11 12:03 — branch at `90434e9`, the statement-boundary attempt, withdrawn

Branch `claude/hearth-thread-tod920`,
[run 34596594804](https://github.com/CalvinSalsali04/speak-it/actions/runs/34596594804),
`macos-26`. **This is not a baseline.** It is the measurement that decided a
change should not ship, recorded because a negative result costs the same
dispatch as a positive one and is worth as much.

The change had four causes, three of them repairs to guards that already
existed and one of them new machinery: a boundary between two juxtaposed
*statements*, proposed where the second clause opened on the speaker's own
possessive, a first-person obligation, or a resolved proper name.

### The verdict, in one table

| instrument | baseline (`2d8fe760`) | this run (`90434e9`) |
|---|---|---|
| gating corpus | 1393 cases, **0** failing | 1393 cases, **4 CRITICAL** |
| everyday routing / count | 168/240 · 193/232 | 168/240 · 193/232 |
| everyday loss / invention / titles | 230/244 · 14/22 · 245/255 | 230/244 · 14/22 · 245/255 |
| everyday over- / under-split | 16 · 23 | 16 · 23 |
| held-out destination / count | 233/320 · 255/310 | **232/320** · **256/310** |
| held-out acted on anyway | 7 | 7 |
| adversarial routing / count | 53/116 · 79/105 | **51/116** · **76/105** |
| adversarial loss / invention / titles | 113/116 · 10/24 · 117/120 | 113/116 · 10/24 · 117/120 |
| runon dev destination | 41/46 | 41/46 |
| runon dev thought count | 33/44 | **35/45** |

The everyday block is bit-identical, family by family and defect by defect, on
255 captures. **The change did nothing at all to natural speech**, cost two
adversarial routings and three adversarial counts, cost one held-out
destination for one held-out count, and broke four cases of the gate.

### The family it was written for did not move

`runon.tsv` reports per family for the first time in this run, which is what
made the verdict readable rather than a single total.

| family | n | destination | thought count |
|---|---|---|---|
| adjunct-guard | 4 | 3/4 (75.0%) | 4/4 (100%) |
| anaphora-guard | 6 | 5/6 (83.3%) | 6/6 (100%) |
| **statement-runon** | 6 | 5/6 (83.3%) | **0/6 (0%)** |
| mixed-runon | 8 | 7/8 (87.5%) | 5/7 (71.4%) |
| object-guard | 10 | 9/10 (90.0%) | 10/10 (100%) |
| bridging-guard | 4 | 4/4 (100%) | 4/4 (100%) |
| errand-runon | 8 | 8/8 (100%) | 6/8 (75.0%) |

`statement-runon` is the family the new machinery was written for and it is
**0 of 6**. Every one of the two counts it gained came from the three guard
repairs, in `errand-runon` and `mixed-runon`. The guard families were not
over-split: `adjunct-guard`, `anaphora-guard`, `object-guard` and
`bridging-guard` are all at 100% on thought count.

The count denominator moved from 44 to 45 because one capture stopped being
read as an Operation, which is a behaviour change rather than a scorer change:
`heldout/score.py` only scores a count where the pipeline produced rows.

### Why it broke the gate, which is the part worth keeping

One case failed in each of four families, and none of them is a run-on
sentence. The gate reported a count and not the rows (see below), so these were
found by tracing every capture of those four families through the rule by hand
rather than read off a log. Three are unambiguous:

| family | capture | where the rule cut |
|---|---|---|
| Semantic keyword collisions | "I have no idea where my passport is" | before `my passport` |
| Ordinary speech (control) | "It reminded me of something my dad used to say" | before `my dad` |
| Intent consolidation | one of two captures opening a clause on `I have to` or `I need to` | before the obligation |

The fourth is in `Filler that collapsed a capture`, whose eight captures
include the same sentence as one of the two Intent-consolidation candidates,
differing only by a full stop — so the same cut fails a case in both families.
Which of the two consolidation captures it is cannot be settled without running
the corpus, and it does not change the cause.

The rule asked whether the words on each side of a cut carry a subject and a
predicate. They do in all four — and **a subject and a predicate do not make a
prefix a finished clause.** "I have no idea where" has both and is plainly
unfinished. "It reminded me of something" has both and is about to be modified
by a relative clause with no relativizer. The test I wrote proves the two sides
are clauses; it never proves the left one is *over*.

That is a general fact about this approach rather than a bug in these four
rows, which is why the rule came out rather than being patched: it fires
constantly on possessives inside subordinate clauses and never once where it
was aimed. The guard list now lives in
`SpeakItTests/ActionabilityTests.testNothingCutsBetweenTwoJuxtaposedStatements`,
carrying both the original seven rows and these four, so the next attempt fails
in a second instead of in a dispatch.

### Two instruments that reported a count and not the rows

Both cost this dispatch and are fixed on the same branch.

- The corpus gate printed `4 blocking failures` and told the reader to run
  `corpus-run --verbose`, which needs a Mac nobody reading a CI log has. It now
  prints the rows.
- The `Development-set failures` step had no `always()`, so the run that went
  red — the only run that needed it — skipped it.

## 2026-09-11 11:26 — `main` at `2d8fe760`, the discourse-framing change merged

Commit `2d8fe760` on `main`,
[run 34593643935](https://github.com/CalvinSalsali04/speak-it/actions/runs/34593643935),
`macos-26`. **This is the current baseline.**

It is the after-picture for the discourse-framing change, and it is the only
run that compares cleanly with the 10:57 section below: same everyday
generation (255 captures, 22 invention cases), same scorer, same corpus data,
one merge apart. The 10:12 section measured the same change against the
235-capture generation with the old invention scorer, so its everyday figures
do not compare with either of these.

Two instruments read for the first time in this run: `runon.tsv`, the
development set written for the next change before that change exists, and the
120-capture adversarial held-out set, which merged after the 10:57 run started.

### What moved, and what did not — everyday, 255 captures

| measure | before (`2c5ac5b`) | after (`2d8fe760`) |
|---|---|---|
| routing | 167/240 (69.6%) | **168/240 (70.0%)** |
| count | 192/232 (82.8%) | **193/232 (83.2%)** |
| nothing lost | 230/244 (94.3%) | 230/244 (94.3%) |
| nothing invented | 14/22 (63.6%) | 14/22 (63.6%) |
| clean titles | 237/255 (92.9%) | **245/255 (96.1%)** |
| over-segmented | 17 | **16** |
| under-segmented | 23 | 23 |
| genuinely ambiguous | 15 | 15 |
| **acted on anyway** | **0** | **0** |

Nothing regressed on any of the four domain-level measures, and no everyday
family lost ground on any of its three. The gating corpus stayed at 1393
cases, 0 failing across all four severities.

| measure | all domains | family-health | fitness-errands | freelance | money-travel | work-school |
|---|---|---|---|---|---|---|
| routing | 168/240 (70.0%) | 30/48 (62.5%) | 37/48 (77.1%) | 34/48 (70.8%) | 32/48 (66.7%) | 35/48 (72.9%) |
| count | 193/232 (83.2%) | 39/47 (83.0%) | 38/46 (82.6%) | 38/46 (82.6%) | 39/47 (83.0%) | 39/46 (84.8%) |
| nothing lost | 230/244 (94.3%) | 49/49 (100%) | 48/50 (96.0%) | 45/49 (91.8%) | 46/49 (93.9%) | 42/47 (89.4%) |
| nothing invented | 14/22 (63.6%) | 0/4 (0%) | 3/4 (75.0%) | 3/5 (60.0%) | 4/5 (80.0%) | 4/4 (100%) |
| clean titles | 245/255 (96.1%) | 50/51 (98.0%) | 51/51 (100%) | 47/51 (92.2%) | 50/51 (98.0%) | 47/51 (92.2%) |

Item type matched the label 145/232, reported and never gated.

### Title hygiene, by defect

| defect | before | after |
|---|---|---|
| farewell kept | 7 | **0** |
| preamble `number one` / `number three` kept | 3 | **0** |
| preamble `number two` kept | 2 | 1 |
| preamble `what happened was` kept | 1 | 1 |
| title is the whole capture | 8 | 8 |

Every farewell is gone. What is left is one enumerator, one preamble, and the
eight captures whose title is the entire recording — which is the segmentation
defect wearing a title-shaped coat, not a hygiene defect.

### Everyday per family, worst routing first

| family | n | routing | count | title |
|---|---|---|---|---|
| run-on | 8 | 0/8 (0%) | 0/8 (0%) | 7/8 (87.5%) |
| rambling-intro | 6 | 1/6 (16.7%) | 1/6 (16.7%) | 4/6 (66.7%) |
| trailing-goodbye | 7 | 2/7 (28.6%) | 4/7 (57.1%) | **7/7 (100%)** |
| sequencing | 17 | 7/17 (41.2%) | 8/17 (47.1%) | 16/17 (94.1%) |
| multi-thought | 40 | 19/40 (47.5%) | 22/40 (55.0%) | **40/40 (100%)** |
| operation | 10 | 5/10 (50.0%) | 0/2 (0%) | 10/10 (100%) |
| cancellation | 12 | 6/12 (50.0%) | 1/4 (25.0%) | 12/12 (100%) |
| hedged | 24 | 9/17 (52.9%) | 15/17 (88.2%) | 22/24 (91.7%) |
| filler | 18 | 9/14 (64.3%) | 12/14 (85.7%) | **18/18 (100%)** |
| list | 20 | 13/20 (65.0%) | 14/20 (70.0%) | 18/20 (90.0%) |
| relative-date | 6 | 4/6 (66.7%) | 5/6 (83.3%) | 6/6 (100%) |
| person | 33 | 23/33 (69.7%) | 26/32 (81.2%) | 32/33 (97.0%) |
| date | 38 | 26/37 (70.3%) | 30/37 (81.1%) | 36/38 (94.7%) |
| negation | 51 | 36/51 (70.6%) | 41/47 (87.2%) | 49/51 (96.1%) |
| location | 12 | 9/12 (75.0%) | 10/12 (83.3%) | 11/12 (91.7%) |
| self-correction | 39 | 30/39 (76.9%) | 37/39 (94.9%) | 39/39 (100%) |
| time | 28 | 21/27 (77.8%) | 26/27 (96.3%) | 27/28 (96.4%) |
| quantity | 34 | 27/34 (79.4%) | 32/34 (94.1%) | 31/34 (91.2%) |
| reference | 34 | 27/34 (79.4%) | 28/34 (82.4%) | 33/34 (97.1%) |
| false-start | 14 | 12/14 (85.7%) | 12/14 (85.7%) | 14/14 (100%) |
| recurrence | 22 | 19/22 (86.4%) | 21/22 (95.5%) | 22/22 (100%) |
| proper-noun | 15 | 13/15 (86.7%) | 12/14 (85.7%) | 15/15 (100%) |
| repetition | 10 | 10/10 (100%) | 10/10 (100%) | 10/10 (100%) |
| question | 9 | 1/1 (100%) | 1/1 (100%) | 9/9 (100%) |
| ambiguous | 15 | — | — | 14/15 (93.3%) |

The `negation` row is the 51-capture family after PR #33 added the tag to W09,
F05 and F14. It does not compare with the 48-capture row in the 10:57 section.

`n` counts captures carrying the tag, so the rows overlap: one capture can be
filler, negation and multi-thought at once.

### Held-out set — 389 utterances, sealed

Destination 233/320 (72.8%), thought count 255/310 (82.3%), producing nothing
0, genuinely ambiguous 69, **acted on anyway 7 (10.1%)**. Identical to every
run before it. **Nothing has moved the generalisation measure yet**, and that
remains the honest headline for the framing change: it fixed what a person
reads on a row, and it has not been shown to help a speaker the parser has
never met.

### Adversarial held-out set — 120 captures, first reading

Phenomena in combination: each capture crosses two families that are each
already imperfect alone. Written held out, by interaction rather than by
mechanism or content, and never tuned against.

| measure | value |
|---|---|
| routing | 53/116 (45.7%) |
| count | 79/105 (75.2%) |
| nothing lost | 113/116 (97.4%) |
| nothing invented | 10/24 (41.7%) |
| clean titles | 117/120 (97.5%) |
| over-segmented | 8 |
| under-segmented | 18 |
| genuinely ambiguous | 4 |
| **acted on anyway** | **1 (25.0%)** |

**The one row that should only ever fall is not zero here.** Everyday and the
389-set both hold at 0 and 7 respectively; on captures built to be hard, one
of the four ambiguous cases got a confident action. Four cases is a small
denominator and 25% is not a rate worth quoting, but the count is the number
that matters and it is 1, not 0.

Routing at 45.7% against everyday's 70.0% is the headline. Combination is
where the parser is worst, and it is not a uniform collapse:

| pairing | routing | count | nothing lost | nothing invented |
|---|---|---|---|---|
| ellipsis × date | 0/10 (0%) | 1/10 (10.0%) | 10/10 (100%) | — |
| reported speech × operation | 3/12 (25.0%) | 7/7 (100%) | 12/12 (100%) | — |
| idiom × operation | 3/10 (30.0%) | 4/4 (100%) | 10/10 (100%) | — |
| brand-verb × multi-task | 4/12 (33.3%) | 10/12 (83.3%) | 12/12 (100%) | — |
| negation × multi-task | 5/12 (41.7%) | 8/12 (66.7%) | 11/12 (91.7%) | — |
| not-a-time × date | 5/12 (41.7%) | 11/12 (91.7%) | 12/12 (100%) | — |
| conditional × negation | 7/12 (58.3%) | 9/12 (75.0%) | 10/12 (83.3%) | — |
| role × multi-person | 7/12 (58.3%) | 9/12 (75.0%) | 12/12 (100%) | — |
| run-on × self-correction | 8/12 (66.7%) | 8/12 (66.7%) | 12/12 (100%) | 4/12 (33.3%) |
| self-correction × name | 11/12 (91.7%) | 12/12 (100%) | 12/12 (100%) | 6/12 (50.0%) |

**`ellipsis × date` at 0/10 is the worst single reading in any instrument.**
Ellipsis — "and the other one too", "same again next week" — leaves the verb
and often the object to be recovered from the previous clause, and the parser
has no stage that recovers them. Combined with a date it routes nothing right
and counts one in ten.

Worth flagging against a stated prediction: **`run-on × self-correction` reads
66.7% routing here while everyday's `run-on` family reads 0/8.** The
expectation was that combination would compose the two failures and read
worse. It did not, and that is evidence the everyday `run-on` captures are
harder along some dimension the adversarial pairing does not carry — likely
length and thought count, not the run-on property itself. Two sets, two
readings; the everyday one is the one to fix against.

Title hygiene is near clean at 117/120: 2 titles are the whole capture, 1
opens on `that`.

### Development sets — not a gate, not held out

| set | measure | this run (`2d8fe760`) | last read at |
|---|---|---|---|
| gating corpus | cases / failing | 1393 / **0** | 1381 / 0 at `2c5ac5b`; the change adds 12 cases |
| coordination | boundaries | 115/121 (95.0%) | 115/121 at 10:12, and at 09:56 before the change |
| routed (116) | destination / count | 74/84 (88.1%) / 77/79 (97.5%) | 74/84 at 10:12 and 09:56 |
| routed (116) | acted on anyway | 3 | 3 at 10:12 and 09:56 |
| framing (45) | destination / count | 41/45 (91.1%) / 43/44 (97.7%) | 41/45 at 10:12; the set is newer than 09:56 |
| unfinished | recall / fallout / unsafe | 34/57 / 0/96 / 2 | same at 10:12 and 09:56 |
| abandonment † | recall / fallout | 24/24 / 0/24 | same at 10:12 and 09:56 |
| **runon (46)** | destination | **41/46 (89.1%)** | first reading |
| **runon (46)** | thought count | **33/44 (75.0%)** | first reading |
| **runon (46)** | acted on anyway | **0** | first reading |

† Overstated by the scorer; see "Correction — 2026-09-11" above.

The right-hand column names where each comparison figure came from rather than
calling it "before": the 10:57 run on `2c5ac5b` reported its gating-corpus
total but its development-set block was not recorded, so the honest comparison
for those sets is the 10:12 / 09:56 pair on the branch, which brackets the same
parser change.

**The shape of `runon.tsv`'s first reading is the finding.** Destination is
89.1% and count is 75.0%: on speech with no marker between two thoughts, the
parser usually routes the capture to the right place and usually fails to
notice there were two thoughts. Eleven of forty-four scored rows have the
wrong count. That is the signature of a missing boundary rather than a
misread meaning, and it is exactly what the set was written to isolate.

The per-row failures are not in this run: the `Development-set failures` step
wrote them to a file nothing collected. The step now prints to the job log.

## 2026-09-11 10:57 — `main` at generation 3, with no parser change in it

Commit `2c5ac5b` on `main`,
[run 34591348628](https://github.com/CalvinSalsali04/speak-it/actions/runs/34591348628),
`macos-26`. This run exists because the unit suite failed on the framing
branch and the same suite had to be run on unchanged `main` to find out whose
failure it was; the language job came free with it.

**This is the before-picture the framing change has to be compared against**,
and it is the first everyday reading at the set's third generation (255
captures, 22 invention cases). It does **not** contain the discourse-framing
change. The 10:12 section below measured that change against the 235-capture
generation, so those two sets of everyday figures do not compare with each
other. These do, once the branch is measured again.

**The unit suite in this same run failed**, and so does the suite on the
framing branch, with an identical list of 57 failing assertions. That is the
state of the suite on a GitHub-hosted `macos-26` runner; the `ios` job had
never run there before today. It does not make the numbers above wrong — they
come from `Tools/CorpusRunner`, a host-side binary that passed its own gate at
1381/1381 in the same job — but they were taken on a commit whose simulator
suite does not pass on that runner, and that belongs next to them until the
failure is understood.

### Everyday held-out set — 255 captures, nothing tuned against them

| measure | all domains | family-health | fitness-errands | freelance | money-travel | work-school |
|---|---|---|---|---|---|---|
| routing | 167/240 (69.6%) | 30/48 (62.5%) | 37/48 (77.1%) | 33/48 (68.8%) | 32/48 (66.7%) | 35/48 (72.9%) |
| count | 192/232 (82.8%) | 39/47 (83.0%) | 38/46 (82.6%) | 37/46 (80.4%) | 39/47 (83.0%) | 39/46 (84.8%) |
| nothing lost | 230/244 (94.3%) | 49/49 (100%) | 48/50 (96.0%) | 45/49 (91.8%) | 46/49 (93.9%) | 42/47 (89.4%) |
| nothing invented | 14/22 (63.6%) | 0/4 (0%) | 3/4 (75.0%) | 3/5 (60.0%) | 4/5 (80.0%) | 4/4 (100%) |

Over-segmented 17, under-segmented 23, produced nothing 0, missing probe
results 0. Genuinely ambiguous 15, **acted on anyway 0**. Item type matched the
label 145/232, reported and never gated.

Clean titles 237/255 (92.9%). The 18 defects: 8 where the title is the whole
capture, 7 farewells kept, 5 numbered preambles kept (`number one` ×2,
`number two` ×2, `number three` ×1), 1 `what happened was`. Fourteen of the
eighteen are framing left in place, which is what the branch change exists to
remove.

### Per family, worst first

| family | n | routing | count | title |
|---|---|---|---|---|
| run-on | 8 | 0/8 (0%) | 0/8 (0%) | 4/8 (50.0%) |
| rambling-intro | 6 | 1/6 (16.7%) | 1/6 (16.7%) | 3/6 (50.0%) |
| trailing-goodbye | 7 | 2/7 (28.6%) | 4/7 (57.1%) | 0/7 (0%) |
| sequencing | 17 | 6/17 (35.3%) | 7/17 (41.2%) | 12/17 (70.6%) |
| multi-thought | 40 | 19/40 (47.5%) | 22/40 (55.0%) | 36/40 (90.0%) |
| operation | 10 | 5/10 (50.0%) | 0/2 (0%) | 10/10 (100%) |
| cancellation | 12 | 6/12 (50.0%) | 1/4 (25.0%) | 12/12 (100%) |
| hedged | 24 | 9/17 (52.9%) | 15/17 (88.2%) | 19/24 (79.2%) |
| list | 20 | 12/20 (60.0%) | 13/20 (65.0%) | 17/20 (85.0%) |
| filler | 18 | 9/14 (64.3%) | 12/14 (85.7%) | 15/18 (83.3%) |
| relative-date | 6 | 4/6 (66.7%) | 5/6 (83.3%) | 6/6 (100%) |
| person | 33 | 23/33 (69.7%) | 26/32 (81.2%) | 32/33 (97.0%) |
| date | 38 | 26/37 (70.3%) | 30/37 (81.1%) | 36/38 (94.7%) |
| negation | 48 | 34/48 (70.8%) | 38/44 (86.4%) | 46/48 (95.8%) |
| location | 12 | 9/12 (75.0%) | 10/12 (83.3%) | 11/12 (91.7%) |
| self-correction | 39 | 30/39 (76.9%) | 37/39 (94.9%) | 39/39 (100%) |
| time | 28 | 21/27 (77.8%) | 26/27 (96.3%) | 27/28 (96.4%) |
| quantity | 34 | 27/34 (79.4%) | 32/34 (94.1%) | 31/34 (91.2%) |
| reference | 34 | 27/34 (79.4%) | 28/34 (82.4%) | 33/34 (97.1%) |
| false-start | 14 | 12/14 (85.7%) | 12/14 (85.7%) | 13/14 (92.9%) |
| recurrence | 22 | 19/22 (86.4%) | 21/22 (95.5%) | 22/22 (100%) |
| proper-noun | 15 | 13/15 (86.7%) | 12/14 (85.7%) | 13/15 (86.7%) |
| repetition | 10 | 10/10 (100%) | 10/10 (100%) | 10/10 (100%) |
| question | 9 | 1/1 (100%) | 1/1 (100%) | 9/9 (100%) |
| ambiguous | 15 | — | — | 14/15 (93.3%) |

`n` counts captures carrying the tag, so the rows overlap: one capture can be
filler, negation and multi-thought at once. The negation row here is the
48-capture family; PR #33 later added the tag to W09, F05 and F14, so the next
reading's negation row is out of 51 and does not compare with this one.

### Held-out set — 389 utterances, sealed

Destination 233/320 (72.8%), thought count 255/310 (82.3%), producing nothing
0, genuinely ambiguous 69, **acted on anyway 7 (10.1%)**. Identical to every
previous run. Nothing has moved this number yet.

### Adversarial set

Not in this run: it merged after the run started. Its first reading is still
outstanding.

## 2026-09-11 10:12 — after the discourse-framing change

First measured language change since the baseline. Commit `412a1a8` on
`claude/hearth-thread-tod920`,
[run #51](https://github.com/CalvinSalsali04/speak-it/actions/runs/34587781290),
`macos-26`. Compared against the 09:56 section below, which is the only
difference: no other change landed between them.

### What moved, and what did not

| instrument | measure | before | after |
|---|---|---|---|
| gating corpus | cases / failing | 1381 / 0 | 1393 / **0** |
| everyday | routing | 152/220 (69.1%) | 153/220 (69.5%) |
| everyday | count | 172/212 (81.1%) | 173/212 (81.6%) |
| everyday | nothing lost | 210/224 (93.8%) | 210/224 (93.8%) |
| everyday | nothing invented | 5/19 (26.3%) | 12/19 (63.2%) — **not a real gain, see below** |
| everyday | clean titles | 217/235 (92.3%) | **225/235 (95.7%)** |
| everyday | over-split | 17 | 16 |
| everyday | under-split | 23 | 23 |
| everyday | ambiguous acted on | 0 | 0 |
| held-out (389) | destination | 233/320 (72.8%) | 233/320 (72.8%) |
| held-out (389) | thought count | 255/310 (82.3%) | 255/310 (82.3%) |
| held-out (389) | acted on anyway | 7 | 7 |
| coordination | boundaries | 115/121 (95.0%) | 115/121 (95.0%) |
| routed | destination | 74/84 (88.1%) | 74/84 (88.1%) |
| routed | acted on anyway | 3 | 3 |
| unfinished | recall / fallout | 34/57 / 0/96 | 34/57 / 0/96 |
| abandonment † | recall / fallout | 24/24 / 0/24 | 24/24 / 0/24 |
| **framing** (new) | destination | — | 41/45 (91.1%) |
| **framing** (new) | thought count | — | 43/44 (97.7%) |
| **framing** (new) | acted on anyway | — | 0 |

† Overstated by the scorer; see "Correction — 2026-09-11" above.

**Nothing regressed.** Not one everyday family lost ground on any of its three
measures, no development set moved down, and the gating corpus stayed at zero
failures across all four severities while growing by the 12 new cases.

### Title hygiene, by defect

| defect | before | after |
|---|---|---|
| farewell kept | 7 | **0** |
| preamble `number one` kept | 2 | **0** |
| preamble `number two` kept | 2 | 1 |
| preamble `number three` kept | 1 | **0** |
| preamble `what happened was` kept | 1 | 1 |
| title is the whole capture | 8 | 8 |

### The families the change was aimed at

| family | n | routing | count | title |
|---|---|---|---|---|
| trailing-goodbye | 7 | 2/7 → 2/7 | 4/7 → 4/7 | **0/7 → 7/7** |
| run-on | 8 | 0/8 → 0/8 | 0/8 → 0/8 | 4/8 → 7/8 |
| rambling-intro | 6 | 1/6 → 1/6 | 1/6 → 1/6 | 3/6 → 4/6 |
| sequencing | 17 | 6/17 → **7/17** | 7/17 → **8/17** | 12/17 → 16/17 |
| multi-thought | 40 | 19/40 → 19/40 | 22/40 → 22/40 | 36/40 → **40/40** |
| list | 20 | 12/20 → **13/20** | 13/20 → **14/20** | 17/20 → 18/20 |
| filler | 18 | 9/14 → 9/14 | 12/14 → 12/14 | 15/18 → **18/18** |

### What this is honestly worth

The title half of the problem is solved on this evidence: every farewell is
gone, and `trailing-goodbye`, `multi-thought` and `filler` are at 100% clean
titles. That is the visible defect — the words a person reads on the row —
and it was the whole of `trailing-goodbye`'s title score.

The segmentation half barely moved. Routing gained one capture and count
gained one; `run-on` is still 0/8 and `multi-thought` still 19/40. Enumerated
speech is now cut where the speaker said to cut it, and that is a small share
of run-on speech: most of it carries no marker at all, which is a harder
problem and the next one to take.

**The held-out set did not move, at all.** That is the honest headline. This
change was aimed at a family the 389-utterance set varies by mechanism rather
than by content, so there was little there for it to move, but the rule stands:
a change that has not moved the generalisation measure has not been shown to
help on that measure, whatever the everyday numbers say.

**The invention jump is not a result, and was corrected within the hour.** The
number moved from 5/19 to 12/19, and the arithmetic gives it away: **seven of
the nineteen invention cases listed `bye` as the value the reading must not
show**, and 5 + 7 = 12. On the twelve cases that test what the measure is for —
a superseded value, a corrected number, a corrected weekday, an inverted
negation — the score was 5/12 before this change and 5/12 after. Nothing about
invention improved.

The cause was the scorer, not the change: a farewell left in a title is a title
defect, and it was being counted a second time as an invention, so one fix moved
two metrics. The evaluation thread found this, has narrowed `reject` to values
the reading must not *assert*, and added a test that fails if a farewell returns
to that column. Verified here against `everyday.tsv` on `main` rather than taken
on trust: 19 rows carry a reject value and 7 of them are `bye`.

Once that lands, the invention column on both of these sections stops being
comparable with later runs. Treat 5/19 and 12/19 as belonging to a scorer that
no longer exists.

## 2026-09-11 09:56 — complete baseline on `main`

The baseline language improvement work is judged against. It is the first run
that covers every corpus the repository has.

| | |
|---|---|
| commit | `330344a` (`main`, after #28 and #29 merged) |
| run | [CI #50](https://github.com/CalvinSalsali04/speak-it/actions/runs/34586389323), `language_only` dispatch |
| runner | GitHub-hosted `macos-26`, Xcode 26.6 |
| wall clock | 4 min 02 s for the job; 3 min 52 s of it the measurement |

Six instruments, kept apart on purpose. A single accuracy figure across them
would be meaningless: they do not measure the same thing, they do not share a
denominator, and the two that are near ceiling would drown the four that are
not.

### 1. Gating corpus — regression net (self-consistency)

```
rendering=identity  TOTAL 1381 cases, 0 failing, 1381 clean
CRITICAL 0  BEHAVIORAL 0  METADATA 0  COSMETIC 0
```

Unchanged and saturated. This instrument can only confirm that a change broke
nothing already written down. **It is not an accuracy figure and must never be
quoted as one.**

### 2. Everyday speech — held out, 235 captures, by content

Five life domains, 47 captures each, written from the product description and
from how adults dictate. Never tuned against. This is the closest instrument
the repository has to Calvin's north star, and it is the one that should drive
the work.

| domain | routing | count | loss | invention |
|---|---|---|---|---|
| **all domains** | **152/220 (69.1%)** | **172/212 (81.1%)** | **210/224 (93.8%)** | **5/19 (26.3%)** |
| family-health | 27/44 (61.4%) | 35/43 (81.4%) | 45/45 (100.0%) | 0/4 (0.0%) |
| fitness-errands | 34/44 (77.3%) | 34/42 (81.0%) | 44/46 (95.7%) | 1/5 (20.0%) |
| freelance | 29/44 (65.9%) | 33/42 (78.6%) | 41/45 (91.1%) | 1/4 (25.0%) |
| money-travel | 29/44 (65.9%) | 35/43 (81.4%) | 42/45 (93.3%) | 2/3 (66.7%) |
| work-school | 33/44 (75.0%) | 35/42 (83.3%) | 38/43 (88.4%) | 1/3 (33.3%) |

Domains differ by 16 points on routing, which is less than the spread between
families below. **Content domain is not where the problem lives.**

| | |
|---|---|
| over-segmented (split) | 17 |
| under-segmented (merge) | **23** |
| produced nothing at all | 0 |
| item type matched the label | 132/212 |
| genuinely ambiguous | 15 |
| **acted on anyway** | **0 (0.0%)** |

Two things to take from that block. Abstention is perfect on this set — not one
capture a careful reader could not pin down was scheduled or modified anyway.
And **merges outnumber splits, 23 to 17**: see "What this changes" below.

`invention` deserves its own line. Only 19 of the 235 captures carry a value the
reading must *not* show, and on **14 of those 19 it shows it anyway**. The
denominator is small, but a 74% rate on a harm measure is the worst number in
this file.

> **Corrected 2026-09-11 10:25.** Seven of those 19 rows listed `bye` as the
> rejected value, which is a title defect the title metric already counted. The
> figure above is what the scorer reported and is left as recorded, but it is
> not a clean invention rate, and it is not comparable with runs after the
> evaluation thread's narrowing of that column.

#### Title hygiene — 217/235 clean (92.3%)

A lower bound on defects: it counts removable material still in the shown
title, never whether a title reads well.

| domain | clean titles |
|---|---|
| family-health | 44/47 (93.6%) |
| fitness-errands | 45/47 (95.7%) |
| freelance | 41/47 (87.2%) |
| money-travel | 45/47 (95.7%) |
| work-school | 42/47 (89.4%) |

| defect | count |
|---|---|
| title is the whole capture | 8 |
| farewell kept | 7 |
| preamble `number one` kept | 2 |
| preamble `number two` kept | 2 |
| preamble `what happened was` kept | 1 |
| preamble `number three` kept | 1 |

#### Per family — the table that matters

`n` counts captures carrying the tag, so the rows overlap: one capture can be
filler, negation and multi-thought at once.

| family | n | routing | count | title |
|---|---|---|---|---|
| run-on | 8 | **0/8 (0.0%)** | **0/8 (0.0%)** | 4/8 (50.0%) |
| rambling-intro | 6 | **1/6 (16.7%)** | **1/6 (16.7%)** | 3/6 (50.0%) |
| trailing-goodbye | 7 | **2/7 (28.6%)** | 4/7 (57.1%) | **0/7 (0.0%)** |
| sequencing | 17 | **6/17 (35.3%)** | **7/17 (41.2%)** | 12/17 (70.6%) |
| multi-thought | 40 | **19/40 (47.5%)** | **22/40 (55.0%)** | 36/40 (90.0%) |
| operation | 10 | 5/10 (50.0%) | 0/2 (0.0%) | 10/10 (100.0%) |
| cancellation | 12 | 6/12 (50.0%) | 1/4 (25.0%) | 12/12 (100.0%) |
| hedged | 24 | 9/17 (52.9%) | 15/17 (88.2%) | 19/24 (79.2%) |
| list | 20 | 12/20 (60.0%) | 13/20 (65.0%) | 17/20 (85.0%) |
| negation | 38 | 24/38 (63.2%) | 28/34 (82.4%) | 36/38 (94.7%) |
| filler | 18 | 9/14 (64.3%) | 12/14 (85.7%) | 15/18 (83.3%) |
| relative-date | 6 | 4/6 (66.7%) | 5/6 (83.3%) | 6/6 (100.0%) |
| date | 36 | 24/35 (68.6%) | 28/35 (80.0%) | 34/36 (94.4%) |
| person | 31 | 22/31 (71.0%) | 24/30 (80.0%) | 30/31 (96.8%) |
| location | 11 | 8/11 (72.7%) | 9/11 (81.8%) | 10/11 (90.9%) |
| reference | 34 | 27/34 (79.4%) | 28/34 (82.4%) | 33/34 (97.1%) |
| quantity | 29 | 23/29 (79.3%) | 27/29 (93.1%) | 26/29 (89.7%) |
| time | 25 | 20/24 (83.3%) | 23/24 (95.8%) | 24/25 (96.0%) |
| self-correction | 24 | 20/24 (83.3%) | 22/24 (91.7%) | 24/24 (100.0%) |
| false-start | 14 | 12/14 (85.7%) | 12/14 (85.7%) | 13/14 (92.9%) |
| proper-noun | 14 | 12/14 (85.7%) | 11/13 (84.6%) | 12/14 (85.7%) |
| recurrence | 22 | 19/22 (86.4%) | 21/22 (95.5%) | 22/22 (100.0%) |
| repetition | 10 | 10/10 (100.0%) | 10/10 (100.0%) | 10/10 (100.0%) |
| question | 9 | 1/1 (100.0%) | 1/1 (100.0%) | 9/9 (100.0%) |
| ambiguous | 15 | — | — | 14/15 (93.3%) |

### 3. Held-out set — 389 utterances, held out by mechanism

| measure | value | change |
|---|---|---|
| destination correct | 233/320 (72.8%) | unchanged |
| thought count correct | 255/310 (82.3%) | unchanged |
| captures producing nothing | 0 | unchanged |
| genuinely ambiguous | 69 | unchanged |
| **acted on anyway** | **7 (10.1%)** | unchanged |

Identical to the 09:38 run, as it must be: nothing merged between them touched
the parser. Failures were not read; the job cannot read them.

### 4. Development sets — readable, and where fixes are worked out

| set | measure | value |
|---|---|---|
| coordination | clause boundaries correct | 115/121 (95.0%) |
| routed | destination correct | 74/84 (88.1%) |
| routed | thought count correct | 77/79 (97.5%) |
| routed | ambiguous acted on anyway | 3/32 (9.4%) |
| unfinished | unfinished flagged (recall) | 34/57 (59.6%) |
| unfinished | finished misflagged (fallout) | 0/96 (0.0%) |
| unfinished | fragment given a date or reminder | 2 |
| abandonment † | withdrawals recognised | 24/24 (100%) |
| abandonment † | kept words wrongly withdrawn | 0/24 (0.0%) |

† Overstated by the scorer; see "Correction — 2026-09-11" above.

Coordination failures, all six: `occupations` 3 (all over-splits), `brands` 1
(over-split), `multiple-people` 1 (over-split), `three-or-more` 1 (under-split).

Weakest unfinished families: `incomplete-complement` 1/10,
`trailing-function-word` 2/8, `abandoned-midthought` 3/9.

### 5. Synthetic stress — still none

`Tools/LanguageMutations/invariance.sh` has never run against the real engine.
No consistency number exists, and consistency would not be an accuracy number
if it did.

### 6. Public-dataset derived — still none

`Docs/PUBLIC_DATASETS.md` records the licence survey. No data has been
integrated, and no external label has been treated as ground truth.

## What this changes

**The over-splitting hypothesis does not survive first contact with unseen
speech.** It came from the coordination development set, where five of six
failures point one way. On the everyday set, which nothing has been tuned
against, the count goes the other way: 23 merges against 17 splits. The
development set is measuring a narrow question — coordinated noun phrases —
and the held-out sets are measuring whole recordings. Over-splitting is real
and narrow; under-splitting is what real captures actually suffer from.

**The failure is concentrated in discourse structure, not in semantics.** The
five worst families by routing — run-on (0%), rambling-intro (16.7%),
trailing-goodbye (28.6%), sequencing (35.3%), multi-thought (47.5%) — are all
the same situation: one recording carrying several thoughts, wrapped in the
framing people put around speech. The families that read the *content* of a
sentence, once it has been cut out correctly, are in the eighties and nineties.

Title hygiene says the same thing from the other side: 14 of the 18 title
defects are framing material left in place — 7 farewells, 6 numbered
enumerators, 1 narrative opener — and `trailing-goodbye` scores **0/7**.

`grep` for farewell handling in `SpeakIt/` returns nothing. `IntentConsolidation`
owns elaborative framing and deliberately stands down the moment two
substantive clauses are present, so it is a collapse stage for rambling with a
single point rather than a general framing stage. Nothing owns enumerators
(`number one`, `first of all`, `secondly`) either, and an enumerator is a
clause boundary a speaker states out loud. That is one missing layer producing
two visible symptoms.

## 2026-09-11 09:38 — first measured run, PR #28 branch

| | |
|---|---|
| commit | `f3f0e5f` |
| branch | `claude/hearth-thread-tod920` (PR #28) |
| run | [CI #49](https://github.com/CalvinSalsali04/speak-it/actions/runs/34584864381), `language_only` dispatch |
| runner | GitHub-hosted `macos-26`, Xcode 26.6 |
| wall clock | 4 min 12 s for the job; 3 min 56 s of it the measurement itself |

### Gating corpus — self-consistency

```
rendering=identity  TOTAL 1381 cases, 0 failing, 1381 clean
CRITICAL 0  BEHAVIORAL 0  METADATA 0  COSMETIC 0
```

**This instrument is exhausted.** Not near ceiling — at it, with zero failures
at every severity including cosmetic. It can confirm that a change broke
nothing already written down. It cannot report progress, because there is no
remaining headroom in which progress could show.

Two figures in circulation were stale and are corrected here: the runner's own
README quotes 841 cases as sample output, and 999 of 1,022 was reported from a
static read. The measured size is 1,381.

### Held-out set — generalisation

389 utterances written before anyone read the parser.

| measure | value |
|---|---|
| destination correct | 233/320 (72.8%) |
| thought count correct | 255/310 (82.3%) |
| captures producing nothing | 0 |
| genuinely ambiguous | 69 |
| **acted on anyway** | **7 (10.1%)** |

Every row is identical to the baseline recorded on 2026-09-09 in
`Tools/CorpusRunner/heldout/README.md`. That is the most useful thing about
this first run: the harness reproduces numbers arrived at independently by
hand, so the instrument agrees with the one that came before it. The failures
were not read, and the job cannot read them — the wrapper refuses `--verbose`
and `--failures`.

**The gap is 27.2 points.** A saturated regression net at 100% and the honest
instrument at 72.8% is the real size of the problem, and it is the number to
watch rather than either one alone.

### Development sets — where rules are worked out

Not held out. Failures here may be read.

| set | measure | value |
|---|---|---|
| coordination | clause boundaries correct | 115/121 (95.0%) |
| routed | destination correct | 74/84 (88.1%) |
| routed | thought count correct | 77/79 (97.5%) |
| routed | ambiguous acted on anyway | 3/32 (9.4%) |
| unfinished | unfinished flagged (recall) | 34/57 (59.6%) |
| unfinished | finished misflagged (fallout) | 0/96 (0.0%) |
| unfinished | fragment given a date or reminder | 2 |
| abandonment † | withdrawals recognised | 24/24 (100%) |
| abandonment † | kept words wrongly withdrawn | 0/24 (0.0%) |
| abandonment | withdrawn thought acted on | 0 |

† Overstated by the scorer; see "Correction — 2026-09-11" above.

### The weakest families, by measurement rather than by impression

Recall is where the room is; fallout is already zero, which is the safer place
for it to be. That holds for `unfinished` as written. For `abandonment` it was
the scorer talking: see "Correction — 2026-09-11" above.

| family | set | score |
|---|---|---|
| `incomplete-complement` | unfinished | **1/10** |
| `trailing-function-word` | unfinished | **2/8** |
| `abandoned-midthought` | unfinished | **3/9** |
| `occupations` | coordination | **1/4**, all three failures over-splits |
| `dangling-infinitive` | unfinished | 18/20 |
| `brands` | coordination | 4/5, the failure an over-split |
| `multiple-people` | coordination | 5/6, the failure an over-split |
| `three-or-more` | coordination | 6/7, the failure an under-split |

Five of the six coordination failures are **over-splits**: the segmenter
inventing a row nobody asked for. That is one direction, not a scatter, and it
is worth treating as one question rather than six.

## What this baseline does not cover

- The everyday corpus (235 captures) was not on `main` when this ran, so the
  report's discovery section reads "none yet". It will appear on its own once
  that lands; the discovery mechanism was exercised and behaved correctly with
  nothing to find.
- `Tools/LanguageMutations/invariance.sh` has still never run against the real
  engine. No consistency number exists.
- These are rules-path numbers from `Tools/PipelineProbe`, not the shipping
  app with its store. See `Tools/PipelineProbe/README.md` for what that cannot
  tell you.

## Everyday corpus — generation 3 (2026-09-11)

The everyday held-out set grew from 235 captures to 255, and its `invention`
measure from 12 cases to 22, so **everyday numbers from before this change are
not comparable to numbers after it.** Compare within a generation, never across.
`Tools/CorpusRunner/everyday/README.md` holds the generation table and the
reasoning.

Two things changed together, deliberately at a pause rather than between two
comparisons:

- Twenty captures added, four per domain. Fifteen carry a genuine superseded
  value — a corrected number, time, weekday, person or place. `invention` had
  been the thinnest measure in the set.
- Ten captures were withdrawn from `invention` (five of them pre-existing). They
  phrase an exclusion, not a repair — `book the small meeting room not the big
  one` — and the excluded value is spoken deliberately, so a faithful title
  contains it. Two of the old ones rejected `not 2D` and `not 6`, strings a
  *correct* title carries. Net effect 12 → 22 cases, all genuine supersessions.
  The withdrawn captures are still scored for routing, count, loss and title,
  so the negation family's routing signal is intact. What no measure reports is
  **invention on a negated or superseded value** — whether the reading treated
  the operative value as operative. That needs a judgement a span test cannot
  make, so it belongs in a readable development set; the everyday README says so
  and warns against closing the gap by re-adding a span test.
- Span matching now anchors its left edge. The old test was a plain substring
  match over normalised text, where `6:40` folds to `6 40` and sits inside
  `16 40`, so a pipeline that correctly discarded a superseded time could be
  reported for inventing it. Direction of the correction is known: `loss` can
  only get stricter, `invention` only less false.

Nothing here was tuned against, and the set stays sealed: it has been scored
non-verbose and its failures have not been read.

## Adversarial held-out set — new instrument, no reading yet (2026-09-11)

`Tools/CorpusRunner/adversarial/` is a third sealed set, 120 captures in 10
pairings of 12. It is a different axis rather than more of the other two:

| set | held out by | what it varies |
|---|---|---|
| `heldout/` (389) | mechanism | one phenomenon per capture |
| `everyday/` (255) | content | ordinary life speech |
| `adversarial/` (120) | interaction | two phenomena deliberately compounded |

The gap it fills is specific. `heldout.tsv` carries exactly one family tag on
all 389 rows, so nothing in the repository asked whether the pipeline's layers
**compose**. Every pairing here is built from two ingredients `heldout/` already
measures separately, so a pairing scoring badly while both ingredients score
well alone is evidence about architecture rather than a missing rule.

**Read a pairing against its ingredients, never on its own** — if an ingredient
is already weak in `heldout/`, a weak pairing says nothing new.

It is scored by the everyday scorer unchanged, so it needs no second
implementation and inherits the defects already found and fixed there. It is
discovered by the existing `score.sh` convention, so `language-metrics.sh`
picks it up with no edit. Its baseline table is empty for the same reason
everyday's was: the engine cannot run in a Linux container, and a number from
anywhere else would be invented.

## Family denominators moved on 2026-09-11, after the generation-3 note

Separate from any generation: five captures gained a `negation` family tag in
PR #33, because they exclude a value with `not` and had never been tagged. That
moves the `negation` row of the per-family tables and nothing else — no capture
was added or removed, and no `reject` span changed, so every headline measure is
untouched.

| set | `negation` from | to |
|---|---|---|
| everyday | 48 | **51** |
| adversarial | 24 | **26** |

Costs nothing today: the last published everyday numbers are the 235-capture
generation, so no `negation` rate from generation 3 has been quoted yet, and the
adversarial set has never been scored. **The next reading is the first for both,
and should be recorded against 51 and 26.**

A generation is about a measure changing. A family denominator can move without
one, which is why it is recorded separately rather than folded into the
generation table.

## How to reproduce

```bash
./Tools/CI/language-metrics.sh --report /tmp/language-metrics.txt
```

Or dispatch `ci.yml` with `language_only`. Record the result here as a new
dated section; do not edit an old one.
