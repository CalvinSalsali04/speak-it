# Semantic-unit experiment: decision rule and outcome plans

Written and pinned in `MANIFEST` before any generation. `decide.py` computes
the outcome from the scored run; this file says why each gate exists and what
follows from each outcome. Nothing here is implemented, and nothing is
implemented before the run decides.

## 1. The rule

The run is judged against the frozen gold under both views:
- `any`: every admissible owner is accepted.
- `own`: a span that may be its own unit must be one.

The constant "one unit" answer sits beside both candidates. It is 16/30 exact under `any` and 12/30 under `own`.

**Run validity comes first.** The run is RUN INVALID, and no decision is made, if any of these hold:
- A capture has no record in either arm.
- A capture has two records in one arm (an unrecorded retry).
- A prompt fingerprint differs from `df4c6e25` (ranges) or `71e026b5` (labels).
- A job was skipped for any reason other than a one-line capture.

A candidate **qualifies** only if it passes all six gates, all on view `any` unless marked:

| Gate | Threshold | Why |
|---|---|---|
| Material gain | at least 4 more exact captures than the one-unit answer, in **both** views | "Materially improves" must be a margin over the answer that needs no model; 4 of 30 is a real difference on this set |
| Multi-unit recovery | exact on at least half of the 14 captures whose gold has two or more units in every reading | The one-unit answer gets 0 of these. Winning on single-unit captures alone would repeat the whole-list illusion |
| Silent wrong cuts | 3 or fewer captures classed over-split, absorbed or wrong-boundaries | Downstream code cannot detect these. Malformed, capacity, dropped and filler-only can be detected and sent to the current path |
| Guarded families | zero silent wrong cuts in reported speech, message content, or deliberation that ends in a decision | A cut there separates content from its carrier or a decision from its negation. That is the exit gate's P0 shape |
| Broken single units | 2 or fewer captures the one-unit answer gets exact and the candidate does not | Splitting one coherent thought is the rules' own failure; a candidate must not reintroduce it |
| Representability | candidate 2 only: 29/30 or better. The precheck measured 30/30 | Calvin's condition for candidate 2 |

**Outcome:**
- **Neither qualifies:** C, neither.
- **Exactly one qualifies:** it wins, and the other failed a named gate.
- **Both qualify:**
  - One wins outright if it leads by at least 3 exact captures in both views.
  - Otherwise candidate 1 wins if candidate 2 made more silent wrong cuts.
  - Otherwise candidate 2 wins. Its cuts can only fall on deterministic clause edges and it has no thought cap. That is the "simplifies" in Calvin's condition for candidate 2.

There is no fourth outcome and no merged candidate.

**What the rule does not decide:**
- Latency and tokens are reported, but they are integration constraints, not gates.
- Production's existing refinement already exceeds its 2 s budget on most complex captures, so any integration runs off the capture path. The capture is saved first and refined afterwards.

## 2. After outcome A: candidate 1, ranges, wins

**The written reason:** the gates it passed, and each candidate-2 gate that failed, by capture id.

**The cap:**
- Production allows 20 rows. Overflow folds every remaining quote into one review row (`ThoughtExtractor.swift`, `rowCap = 20`), so no words are lost there.
- The experiment's cap of 20 sat in the model's schema. That is different: a model at its maximum cannot say "there is more".
- In production the schema maximum becomes the atom count, which is only a hard limit on nonsense. The existing row cap stays the only place rows are folded.
- A model answer that reaches the schema maximum is treated as a capacity refusal, and the whole capture takes the current path.
- No unit is ever dropped by a cap. The CAP25 fixture is the regression test.

**Smallest grounded integration:**
- The model returns ranges only.
- The app rebuilds each unit's text as the exact slice of the transcript.
- Each slice goes through the existing deterministic reading (`ThoughtOrganizer.organize`), exactly as a rules segment does today.
- Any content atom that no unit covers is carried whole into one review row, never dropped.
- If any invariant fails, the capture takes today's path: ordered, in bounds, no overlap, no filler-only unit, no one-word unit.

## 3. After outcome B: candidate 2, labels, wins

**The written reason:** the same as for outcome A, reversed.

**Source preservation:**
- `clause_lines.py` is ported to Swift as a pure function over whitespace atoms.
- A parity test runs the Python and the Swift over every frozen input and every development set: the lines must match exactly.
- The invariant that the lines partition the atoms (checked today by `UnitsExperimentInputs.read`) becomes a precondition. A unit's text is always the slice from its first line's first atom to its last line's last atom.
- The splitter reads no parser output, and that stays true.

**Smallest grounded integration:** the same as for outcome A, with lines in place of ranges.
- It needs no cap handling: one label per line, and the row cap folds overflow as it does today.
- A one-line capture is one unit without asking the model.

## 4. After outcome C: neither wins

- **Say neither.** Name the gate each candidate failed, by capture id.
- **Production semantics stay exactly as they are.** The semantic map stays diagnostic-only for V1.
- **The V1 lead is told** that no production semantic change is expected before the V1 freeze.
- **No hybrid is proposed** to avoid the negative result.

## 5. After a winner: the integration experiment (designed now, built only after the decision)

**Goal:** prove the chain from a grounded semantic unit, to a deterministic reading of exactly that source, with no invented execution and no silently lost source. It does this before any production change.

**Inputs:** the winner's recorded answers from the run. It makes no new generation. The same 30 captures and the same frozen gold are used.

**Pipeline:** the winner's units become exact source slices. Each slice goes through the rules-only reading from `Tools/PipelineProbe`, with its fixed clock, no store and no model. The output is rows.

**Four checks per capture, each pre-registered as zero-tolerance:**
1. **Grounded.** Every row's quote lies inside its unit's slice.
2. **Deterministic.** Two runs give identical rows. Every date, reminder, alarm, person and cancellation comes from the organizer reading the slice.
3. **No invented execution.** Each executable field is compared with the current rules reading of the whole capture, and each field the unit path adds is listed. The fail condition is any exit-gate P0 shape:
   - a condition split from its action and executed unconditionally;
   - a negation separated from what it negates;
   - quoted or message content becoming the user's own command;
   - a cancellation that lost its target.
4. **No silent lost source.** Every content atom is in a unit or in the listed uncovered set.

**Comparison:** rows against gold units, beside today's rules rows on the same captures.

**Where it runs:** the pipeline is Swift but uses no model.
- It can compile and run on the hosted macos-26 runner. That the runner can run it is inferred: the runner has compiled Swift here before, but has not run this probe.
- Otherwise it joins the next consolidated Mac batch, and is not a separate ask.

**Out of scope:** routing, entities, relations, the launch holdout and a 250K run. Entities and relations come back only when stable unit identity exists and measurement shows they are needed.

## 6. The production interface, if a candidate wins

**The interface is one optional input to extraction:** the transcript's semantic units, as source atom spans, or nil.
- Nil means today's path, unchanged.
- The model identifies boundaries only. Deterministic code keeps ownership of execution and safety.

**Semantic files likely to overlap:**
- `SpeakIt/Repositories/ThoughtExtractor.swift`: segmentation, `rowCap`, `RefinementGuard`, `RefinementPolicy` and `IntelligentThoughtExtractor`.
- `SpeakIt/Interpretation/`: the prototype. Production does not call it.
- For outcome B, a new Swift clause-line file.
