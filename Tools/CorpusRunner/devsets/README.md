# Development sets

Where rules are worked out. **Not a gate, and not held out.**

```bash
./Tools/CorpusRunner/devsets/score.sh coordination [--verbose]
./Tools/CorpusRunner/devsets/route-score.sh routed [--verbose]
./Tools/CorpusRunner/devsets/route-score.sh framing [--verbose]
./Tools/CorpusRunner/devsets/unfinished-score.sh [--verbose]
./Tools/CorpusRunner/devsets/abandonment-score.sh [--verbose]
```

These exist so that `../heldout/` never has to be opened during development.
The held-out set answers one question — did this generalise past the examples
it was designed against — and it can only answer it once per change, and only
if nobody looked. Iterating needs somewhere else to iterate.

| set | unit | scored by | what it measures |
|---|---|---|---|
| `coordination.tsv` | `probe --clauses` | `score.py` | where clause boundaries fall |
| `routed.tsv` | full rules path | `../heldout/score.py` | destination, and unsafe action on an ambiguous capture |
| `framing.tsv` | full rules path | `../heldout/score.py` | whether the frame around speech is read as frame: sign-offs, enumeration |
| `runon.tsv` | full rules path | `../heldout/score.py` | several thoughts in one breath with no marker, and the boundaries that must not be cut |
| `rambling.tsv` | full rules path | `../heldout/score.py` | whether filler, false starts and length change the reading, measured against a clean twin of the same content |
| `unfinished.tsv` | full rules path | `unfinished-score.py` | whether a thought was finished at all |
| `abandonment.tsv` | full rules path | `abandonment-score.py` | whether "never mind" was this speaker taking this thought back |

`framing.tsv` was written from the everyday set's per-family *rates* — `run-on`
0/8, `rambling-intro` 1/6, `trailing-goodbye` 2/7, `sequencing` 6/17 — and from
no capture in it. A rate says which family to look at; a sentence would have
ended the set's usefulness.

`rambling.tsv` is the one set here whose headline is a **difference rather than
a rate**. Every capture is written twice under one id stem — `RB04C` clean,
`RB04R` the same content spoken with filler — and both twins carry the same
label, so the clean family is a control and the gap between the two families is
what filler and disfluency actually cost. A clean family at 20/20 beside its
rambling twin at 11/20 names nine captures the app understands typed and loses
spoken; two families failing equally means the label is wrong and rambling is
not what broke it. Do not average across the halves: the clean rows are
deliberately easy and would flatter any single number taken over the file.

It exists because the other five sets stopped discriminating. They sit at or
near their ceilings while the sealed everyday set routes 168/240 and the
adversarial set 52/116, so development steered by them is steered by
instruments that can no longer see the remaining failures. Long, filler-heavy,
multi-errand speech is the material none of them carry, and it is the material
the product is for.

`runon.tsv` has the same provenance and goes further than measuring: it states
what the app should do with speech nobody punctuated. Two halves are two rows
when each would still be **findable on its own**, and one note when the second
half would not — which is the product contract rather than taste, since Memory
is for knowledge worth finding later. The first draft said "same topic is one
note" and that rule gave the same label to two rows that are not the same: "the
parking is round the back" retrieves under nothing once it is severed, while
"Okonkwo is chairing the panel" retrieves under Okonkwo.

Its guards are split three ways on purpose, because three different mechanisms
pass them and one rate would hide which is working: `anaphora-guard` (the second
clause opens on a pronoun or deictic — mechanical), `bridging-guard` (it opens on
a definite that resolves only through the first clause — not mechanical, and the
rows that will fail longest), and `object-guard` (the second noun phrase is not a
subject at all). A topic rule scored on an undivided family would read as working
while anaphora carried it.

`routed.tsv`, `framing.tsv` and `runon.tsv` are deliberately scored by the **held-out
scorer**, on the same five columns, so the number being developed against is the
same number being reported at the end. Only the data differs.

## Reading the coordination set

The unit is `splitClauses` rather than the finished rows, because the shopping
grouper splits one product list into several rows and would otherwise drown the
signal. `over` and `under` are counted apart: an over-split invents a row, an
under-split buries a thought inside another one, and they are not the same
defect.

## The labels are not sacred

Several expectations in `routed.tsv` were wrong on the first pass — the gating
corpus already settles that "Dentist next Monday" is a dated event and that
"Remind me tomorrow" schedules at the default hour, and the labels said
otherwise. They were corrected against the corpus, which is the product
contract; the app was not changed to match a label. When a case here disagrees
with a gating corpus case, the corpus wins and the label is the bug.

Two rows are expected to fail and are kept anyway: `DO02` and `DO03` ask for
"delete the reminder to call Dave" and "remove the dentist appointment" to be
recognised as operations. They are not, and they fail closed to a Memory row
that nothing acts on. Widening the destructive vocabulary to close them would
trade a safe gap for an unsafe one.

## Recorded limits, and why they never move a number

A miss and a decision not to try read identically in a rate. `unfinished.tsv`
scores 34 of 57 on recall, and seven of those captures are a limit somebody
already measured and wrote down: trailing preposition, conjunction and adverb
were each tried as a class and each removed, because "Meet Mike at" and
"we're almost out" are the same tag shape and only one of them is unfinished.
A reader triaging that table sees 23 misses and reads 23 as 23 available.

The set's header now declares them:

```
# limit: SpeakIt/Repositories/ClauseStructure.swift | out of scope, and honestly so | INC41 INC42 INC43 INC44 INC46 INC47 INC48
```

and the report gains a block naming those seven captures, plus a mark on the
family row, because the table is what gets quoted.

**It deliberately computes no ceiling.** "Recall cannot pass 50 of 57" was the
first draft and it was wrong twice. A ceiling is a denominator in waiting: once
50 is in the report, 34 of 50 is in the reader's head, and 68% is a nicer
number than 59.6% that nobody earned — which is the rule below being broken in
the one place it cannot be tested. And it would be false. What
`ClauseStructure.swift` records is that three *tagger classes* were tried and
each cost more than it recovered, which is a statement about one signal.
`Docs/SEGMENTATION_ARCHITECTURE.md` names another the app already measures and
throws away: the speaker's pause, asked for at `SpeechRecognitionBackend.swift`
and flattened out of the transcript a line later. A boundary that read timings
would not meet the ambiguity that `Noun Conjunction` creates. A recorded limit
is a decision taken with the signals to hand; calling it a ceiling promotes it
to a property of the language.

Three rules stop this becoming a machine for excusing failures, and
`../test_score.py` holds all three:

1. **A limit never changes a rate.** Those seven are still misses in the 34 of
   57. Declaring one makes a number more visible rather than better, so there
   is nothing to gain by declaring one falsely.
2. **The citation is verified, not stated.** The phrase must still appear in
   the named source, so a limit cannot outlive the decision that made it:
   implement the thing and delete the comment, and the declaration fails until
   somebody removes it.
3. **A declared capture must exist and be a miss**, so a declaration cannot
   quietly cover a row that was passing anyway.

`INC45` is deliberately outside the declaration and a test pins that. "I need
to talk to Sarah about the" ends on a determiner, which the cited comment does
not cover and the code below it handles separately; sweeping it in would be a
label standing in for the judgement it approximates.

**What is not mechanical yet.** `DO02` and `DO03` in `routed.tsv`, above, are
the same shape — expected to fail, kept deliberately — and are recorded only in
this prose. They are a harder case: the reason is that closing them would trade
a safe gap for an unsafe one, which is a judgement with no line of source to
cite, so the citation rule does not fit them as written. Until it does, that
rate carries two declined cases with nothing in the report saying so.

## The denominator is the only evidence that nothing was lost

Every scorer here drops a labelled row the probe never emitted, rather than
failing it. So a truncated probe run, a lost line or an encoding difference
takes captures out of the denominator and the rate is computed over whatever
survived — a set that quietly got easier.

**A denominator arriving at exactly its label count is therefore the only
evidence anyone gets that no row was dropped.** That reconciliation used to be
a hand check against the label file. Both scorers here now print it:

```
  scored                        57 of 57 labelled
  scored                        56 of 57 labelled  ← 1 with no probe result, excluded from every rate below
```

It prints on a clean run too. A line that appears only on failure is not
evidence of anything on the runs where it stays quiet.

`unfinished-score.py` had the worst version of this: it incremented a counter
that was never printed, appended no miss, and had no exit status at all, so
`unfinished-score.sh` could not fail on anything. `abandonment-score.py`
counted and gated on it but only recorded the miss under `--verbose`, and
`language-metrics.sh` never passes `--verbose` — so on the report every
published figure comes from, a dropped row was silent in both.

The five scorers now sit in three groups, which is worth knowing before
quoting any of them:

| scorer | a labelled row with no probe result |
|---|---|
| `score.py` (coordination) | counted as a **failure**; denominator stays whole |
| `unfinished-score.py`, `abandonment-score.py` | excluded, printed, and the run fails |
| `../heldout/score.py`, `../everyday/score.py` | excluded and printed; neither has an exit status |

Coordination's answer is the strongest of the three, and switching the others
to it would change published rates, so it needs a run and a note rather than a
quiet edit.

**Nothing has been lost so far.** `unfinished.tsv` holds 96 `Complete` and 57
`Incomplete`, which is exactly the published `0/96` and `34/57`; the same
reconciliation holds for every set the baseline publishes. That was checked by
hand against the label files. The point of the line above is that the next
check is the instrument's, not somebody's.

## `KNOWN:` markers, and the numbers that change because of them

Four rows of `abandonment.tsv` carry a note beginning `KNOWN:` — a failure
somebody documented rather than fixed, each with its reason. Until now the
marker moved the row into the **pass** column, so `recall`, `fallout` and the
mixed row all reported better than the set actually did. `fallout` is the
number this scorer's own docstring calls the shipping decision, and a
documented fallout of 1 printed as 0.

**The marker now moves the exit status, not the rate.** A documented failure is
counted as a failure everywhere it is counted at all; the report then names the
ids and says which part of the total somebody already owns, and the exit status
forgives that part so a pre-existing defect does not block a hand run. A rate a
marker can improve is a rate people learn to write markers for.

**So these numbers will read differently from any previously quoted.** Nothing
about the parser changed — the earlier figures were the same behaviour scored
with four rows excused. Anything recorded before this should be treated as
scored under the old rule and not compared across it.

**A `KNOWN:` row that starts passing now fails the run.** Removing the marker
costs one line and leaving it is a suppression nobody is watching: it silently
forgives a defect that no longer exists. Same reasoning as a recorded limit
whose source comment has gone.

Both scorers now have self-tests in `../test_score.py`, which runs on every
pull request. They had none, and `34 of 57` and `24 of 24` had both been
quoted from them. Writing the tests found three real gaps by mutation rather
than by reading: a Mixed capture that produced no rows at all, one retracted
whole, and a withdrawal that came back as its own row beside the surviving
half — none of which any case in the set happened to exercise.


## Why abandonment is its own file

`unfinished.tsv` asks whether a sentence stopped. `abandonment.tsv` asks
whether the person then said so. They are different questions with different
failure modes, and folding the second into the first would have moved the
denominators the unfinished floor is quoted against — 34/57 recall, 0/96
fallout, 2 unsafe — which is exactly the number a release is checked on.

Its fallout column is the one to read. Every row under `ordinary-content` is a
sentence that contains a withdrawal word and is not a withdrawal: "I need to
forget it", "remind me to scratch that off the list". The first version of the
rule that fixed the release blocker destroyed all of them, because it asked
whether the words in front of the marker looked unfinished — and they always
do, once you take the marker off the end. Those rows exist so that never
happens quietly.
