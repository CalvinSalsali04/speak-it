# Semantic map architecture

**Status: prototype, measurement only. Nothing here is on the capture path.**
Everything below lives in `Tools/SemanticMap/`, a host-side probe that
compiles the live parser beside it. Production's extraction, prompts, schemas,
hybrid arbitration and persistence are untouched, so this cannot conflict with
work on those interfaces, PR #117's entity work included, which this builds
on without editing.

**Uncompiled until it is built on a Mac.** No session that wrote this has a
Swift toolchain. The Python scorer and every repository check that is Python
were run; the Swift was checked against production's declarations by reading
them, which is not compiling. The first `./Tools/SemanticMap/build.sh` on
Calvin's Mac is the first compile.

## The problem, as the code states it

Production asks Apple's model about a capture only through
`ThoughtExtractionEngine.extract` (`SpeakIt/Repositories/ThoughtExtractor.swift:196`),
and every step of that route is a silent exit to the rules reading:

| step | where | what it means |
| --- | --- | --- |
| the rules read an operation | `ThoughtExtractor.swift:220` | the model is never considered |
| over 1,500 **characters** | `RefinementPolicy`, `:188` | a character count guarding a 4,096-token context |
| no rules row needs review | `:189-190` | **a confident rules reading is never checked, however complex the capture** |
| only `unsupported` rows need review | `:190` | excluded by the same line |
| model unavailable or locale unsupported | `:2999` | rules |
| no answer in 2 seconds | `:2973` | the answer is discarded, whatever it was |
| any row's quote or context not grounded, a duplicate, over 12 | `validate`, `:3029` | the whole answer is discarded |
| `RefinementGuard.preservesEverything` fails | `:241` | the whole answer is discarded |

None of these exits is recorded, so nobody can say how often a hard capture
never reaches the model, reaches it too late, or reaches it and is thrown
away. The third row is the structural gap Calvin named: a long, messy capture
the rules read confidently and wrongly is exactly the capture the model is
never asked about.

## Phase 1: the route, traced

`ProductionRoute.swift` runs production's steps in production's order and
records the exit. It does not re-implement them:

- the policy decision is `RefinementPolicy.shouldRefine` itself, with the
  reason decomposed beside it and a `policyDrift` flag when the two disagree;
- the generation uses production's own `@Generable` types, validator and
  grounding check, cut out of the live `ThoughtExtractor.swift` by `build.sh`
  at every build (`ProductionRefinementMirror`, with `private` removed), and
  the instructions literal is cut out the same way;
- the two literals the trace must restate (the budget and the prompt prefix)
  and the length gate are grepped for by `build.sh`, which refuses to build if
  any has changed;
- the model is run **without** the budget and timed, so a late answer is
  recorded as `budgetExpired` together with what validation and the guard
  would have done with it (`unbudgeted`);
- token counts come from `SystemLanguageModel.tokenCount(for:)` (26.4+) for
  the prompt, the instructions (through the `Instructions` overload, not as
  prompt text), the schema and the generated answer, beside `contextSize`.
  They are taken after the timed call, so counting cannot warm the model
  inside the window being measured. They are never estimated from
  characters; before 26.4 the fields are empty;
- production has a second route to the model: when a capture's operation
  finds no target and rows sit beside it,
  `SwiftDataThoughtRepository.swift:1111-1116` re-extracts with operations
  off, and that reading meets the same gate. The probe has no store, so it
  records the gate that re-extraction would meet (`fallbackPolicy`) rather
  than claiming the exit was taken.

`--census` runs the deterministic half on any Mac with no model: every
capture's policy exit, and 27 content-free complexity features. The
`confidentOnComplex` shape (three or more clauses or forty or more atoms,
nothing flagged) counts how many structurally complex captures the rules
answer without ever involving the model. It is a shape, not an error:
`score.py router` joins it to labels to ask whether those readings were right.

No user content reaches analytics. The census is content-free; the run records
carry the capture and the model's raw answer because replay needs both, and
stay on the machine that made them.

## Phase 2: the grounded semantic map

The capture is divided into **atoms**, maximal runs of non-whitespace in the
original transcript (`Atoms.swift`, the half of Phase B's `SourceAtoms` that
compiled and ran on Calvin's Mac). The model only ever names atoms by index.
It is given no field that can hold text, so there is nothing to ground and
nothing it writes can be shown to a person.

Phase B's single combined contract died on a cross-array coupling (59 of 85
`rambling` readings refused before segmentation could be judged). So the map
is three small jobs, each its own session with its own runtime schema, and no
array's length depends on another's:

| job | the model returns | bounded by |
| --- | --- | --- |
| units | atom ids a thought ends on | `0...n-2`, at most `min(12, ceil(n/2)) - 1` splits |
| relations | `(relation, from, to)` over the units | unit ids, `min(12, 2U)` links, seven relation tokens |
| entities | `(firstAtom, lastAtom, kind)` | atom ids, `min(12, n)` spans, six kind tokens |

Relations: `replaces`, `cancels`, `isConditionFor`, `isMessageContentOf`,
`givesContextTo`, `continues`, `unclear`. Entity kinds mirror PR #117's
`EntityKind`: person, organization, place, topic, role, unknown.

Decoding refuses a whole job on any malformation (`SemanticDecoding`, one
`JobRefusal` case per rule) and repairs nothing: no sorting, clamping,
deduplicating or re-pointing. A symmetric relation's direction is canonicalised
because that loses nothing. Refused output is kept verbatim, so "the model
proposed something useful that a rule refused" stays separable from "the
model proposed nothing useful". The `framework*` refusals would mean Apple
generated outside a bound its own schema declared, and are reported apart.

Prompts carry no example values: both device runs showed the model copying
examples back as content.

The model has no authority over source text, names, dates, reminder text,
cancellations, notifications, geofences or stored mutations. Each of those is
produced, if at all, by the existing parser reading a slice of the original
transcript.

## Phase 3: the router is measured, not written

`ComplexityFeatures` records every candidate signal for every capture. Where
the parser already has a detector for a phenomenon, the feature is that
detector (`SelfCorrectionResolver`, `CaptureOperationDetector`,
`ClauseScope.read`, `ConditionalIntentScope`, `IntentConsolidator`,
`PersonMentionResolver`, `ActionabilityReader`), so a feature cannot disagree
with the parser about what a correction is. `score.py router` reports each
feature's coverage, the rules failure rate when it fires, its lift over the
base rate and the share of all failures it catches, and scores production's
current policy as a router beside them.

Nothing routes on these yet. Development runs ask the jobs about every
capture, which costs more but makes every router answerable offline: the
arbiter is deterministic, so a router that would have declined a capture is
simulated by giving that capture the rules reading.

Unavailable model: the map is absent and the arbiter returns the rules
reading exactly. That is the only fallback there is, and it is today's
behaviour on every device without Apple Intelligence.

## Phase 4: the arbiter

`Arbiter.swift`. Every decision is classified as one of: `agree`,
`modelAddsStructure`, `rulesStronger`, `modelViolatesGrounding`,
`modelConflictsSafety`, `unresolved`, with a closed, content-free reason.

What the map may change, exhaustively:

1. **Split** a rules row at a model boundary, when each piece read by the
   parser keeps everything the row had (`RefinementGuard.preservesEverything`,
   the guard production's hybrid path already uses) and no piece carries an
   executable value the row lacked. Refused before anything is read when the
   cut is inside quotation (`ClauseScope.isInsideQuotation`), inside a
   reported or message complement (`ClauseScope.read`), separates a condition
   from what it governs (`ConditionalIntentScope`), or falls after a
   closed-class word that needs its complement. A piece may inherit a leading
   day or time only where the map says one thought `givesContextTo` another,
   and only the words `leadingTemporalContext` finds in the source thought.
2. **Merge** adjacent Memory rows the model reads as one thought, when neither
   carries anything executable or owed and the parser reads the joined span as
   one row. Actions are never merged: that could hide one.
3. **Withdraw** execution (reminder, due date, recurrence, place trigger) and
   flag review on a row the map says was replaced, cancelled, made
   conditional, or is message content, when the rules still execute it. The
   row is kept. The model can take capability away and can never grant it.
4. **Clear** a person the rules inferred when the map calls the span something
   else, unless PR #117's `entityKind(in:)` calls it a person, in which case
   the rules win. The map never adds a person.

Never: create an operation, a reminder, a date, a place trigger, a name or any
text. A capture with an operation is not arbitrated. A final check confirms
no instant, place or recurrence in the output is new, and falls back to the
rules reading whole if one is; that is a structural guarantee, reported as
one (`noNewInstantHeld`), and a firing means an arbiter bug. It is a set
check and says no more than that: a split can put an existing instant on a
second row, which would schedule it twice, so the number of executing rows
added is recorded beside it (`executingRowsAdded`) and reported by the
scorers rather than folded into the guarantee.

Two rules about evidence the grader of #118 sharpened:

- A relation is never recorded as agreement while a row carrying both of its
  sides still executes. For `replaces` and `cancels` that row is withdrawn
  unless the parser repaired it (the correction was applied in place); for
  `isConditionFor` a row holding its own condition that executes with a
  resolved state is withdrawn (`spanningRowStillExecutes`), unless the row
  already encodes the condition: a place trigger for "when I get to Costco",
  or an instant the condition's own words give (`conditionEncodedInRow`).
  For `isMessageContentOf`, a row carrying both a message and its contents
  keeps its instant only when the words outside the contents carry it on
  their own ("at five text Sam that I'm late"), and that is recorded as
  `unresolved`, not agreement; otherwise the contents timed it ("text Sam
  that I'll be late at six") and it is withdrawn (`messageContentTimesRow`).
  The contents are `ClauseScope.read`'s complement, or the model's span where
  it finds none.
- A person is cleared only when the model gives a positive non-person kind
  and `PersonMentionResolver.entityKind(in:)` also gives one. The model's
  `unknown` is an abstention (`modelAbstained`), and a deterministic
  `unknown`, or a row naming more than one candidate, keeps the person
  (`personRejectedOnlyByModel`): #117 keeps an unfamiliar name a person, and
  one model vote does not overrule it.

`unresolved` is never hidden. Where evidence disagrees and neither side is
decisive, the capture keeps the rules reading and the decision log says so;
a withdrawal flags the row, and nothing is sent to review merely because two
readings could not be combined.

`ArbitrationPolicy` switches each of the four powers off separately, and
`--replay --policy` scores any combination from one device run.

## Preregistered falsifiers

Written before any device run. Each names the result that kills it.

| claim | falsified by |
| --- | --- |
| P1. Production never asks the model about a material share of rules failures | `score.py router`: `rules failures production never asks about` is a small share of all failures |
| P2. The 2 s budget throws away answers production would accept | `score.py trace`: the budget discarded 0 accepted answers |
| P3. The 1,500-character cap, not the context, is the binding limit | prompt + instructions + schema tokens approach `contextSize` below 1,500 characters |
| M1. The units job finds boundaries the parser misses | `split/splitAccepted` is outnumbered by `splitLosesContent` + `cutAfterDanglingWord` + `cutInsideQuotation`, or map-arm row counts are no closer to labels than the rules' |
| M2. The relations job finds withdrawals and corrections the rules still execute | on inspection of raw records, `withdrawnRowStillExecutes` / `correctedRowStillExecutes` mostly fire where nothing was withdrawn |
| M3. The entity job types contextually | one kind is at least 90% of at least 20 answers (`score.py trace` prints DEGENERATE), the `temporalRole`/`locationRole` precedent; or cleared persons are mostly real people |
| M4. Factoring fixes Phase B's refusal rate | a job's refusal rate on `rambling` is near Phase B's 59/85 |
| M5. The model finds coherent long thoughts the parser split | `merge/mergedMemory` stays at zero while `mergeNotClean` or `mergeWouldHideAction` fire, i.e. the merge power is inert; category D shows no gain on the fresh slice |
| S1. No arbitration outcome creates a new instant | `executionOutsideRulesReading` ever fires, or an unsafe count on the map arm exceeds the rules arm |
| S2. No arbitration outcome schedules an existing instant twice | `executingRowsAdded` fires on any capture (counted per rules row, beside `executingRowsRemoved`, so a withdrawal cannot net it away) |

Development sets are for killing claims, not for supporting them. Only the
fresh slice supports one.

## Census on `rambling` (Calvin's Mac, 2026-09-22)

Calvin ran `./Tools/SemanticMap/census-devsets.sh` at `1f2e4bc` with the
`JobRefusal` fix applied locally, and reported for `rambling`: 85 captures,
20 rules failures; production's policy asks the model about 6 captures, and
4 of them are among the 20 failures. The other 16 are never sent: 14 because no row
needs review, 2 because only unsupported rows do. P1 is therefore not
falsified on this set.

| signal | fires | failures when it fires | failures caught |
| --- | --- | --- | --- |
| confidentOnComplex | 10 | 8 (80%, lift 3.40) | 8/20 |
| mixedTodayMemory | 19 | 11 | 11/20 |
| clauses>=3 | 13 | 9 | 9/20 |
| rulesItems>=3 | 12 | 8 | 8/20 |
| atoms>=25 | 22 | 10 | 10/20 |
| disfluency | 24 | 4 | weak |

Development evidence only, from a set this work has read: it says the
current router hides most rules failures from the model, not which router
would be right. No router is chosen from it and production routing is not
changed.

## The diagnostic run (next, on Calvin's Mac)

The smallest run that answers one question: given the captures the router
hides, does the grounded map recover useful structure without damaging
complex captures the rules already get right?
`./Tools/SemanticMap/diagnostic.sh` selects, from the rules reading and the
labels alone (`score.py select`), every rules failure production never sends
to the model, every `confidentOnComplex` capture, and one rules-correct
complex control per failure (its C/R twin where there is one, else the
nearest in atoms), deduplicated. On the census above that is about 16
failures, 2 correct `confidentOnComplex` captures and 14 controls. Each gets
production's model in shadow and the three jobs; `score.py diagnostic` then
reports per group: model availability, each job's outcome, the arbiter's
contribution, failures improved and correct captures damaged (for the map
and for production's own model as if the router had asked), grounding
rejections, latency and the final fallback, with ids only.

What each outcome decides:

- Improved on hidden failures, nothing damaged among controls: the design is
  worth a fresh slice; the next step is the freeze and an independent author.
- Improved, and controls damaged: the damaging power is named by the
  arbiter reasons on the damaged ids, and is switched off with `--replay
  --policy` before anything else is run. No new generation is needed.
- Nothing improved, with jobs accepted: the map is inert on these failures
  (M1, M2, M5), and the failures' layer is the parser, not routing.
- Jobs mostly refused: M4, and the job prompts are the finding.

## Phase 5: the fresh slice

Schema, authoring protocol and scoring are in `Tools/SemanticMap/LABELS.md`.
The slice is written by a different author, after the freeze commit below,
from the capture alone, and scored per category A–J with no overall row.
The short/long paired bank and Astra's long-blurb findings are development
evidence; neither was found in the repository, any branch, any pull request or
the project files, so they come in only if Calvin supplies them.

**Freeze commit:** not yet. The architecture freezes after the first device
run has been read, because M1–M5 may kill a power, and a slice written against a
design that then changes has been spent.

## Phase 6: speech evidence

`SpeechRecognitionBackend.swift:248-249` asks `DictationTranscriber` for
alternative transcriptions, audio time ranges and transcription confidence.
`:290` keeps only `result.text.characters`; the alternatives and attributes
are discarded. The `SFSpeechRecognizer` path (`:89`) keeps only
`bestTranscription`. So N-best evidence is requested and never read.

Nothing is added to production. The evidence that would justify it is a set of
real device captures where the best transcription lost a name or a word the
alternatives kept, measured against what the person said; that needs the
alternatives logged beside the capture, which is a debug-only change to make
after the device run shows ASR name errors are a leading family. The safe use,
if it earns one, is display-side: an alternative may be *offered*, never
substituted, because the transcript is truth.

## Phase 7: device validation

Every capture starts from a fresh checkout where
`verify_device_baseline.py` passes, and records: intended wording, raw ASR,
the rules output, production's trace, the map and the arbiter's decisions,
persisted items, reminder and geofence state, review state, device, OS,
locale, time zone, reference clock, contacts and saved places, whether
interpretation was on, and the commit.

Chain, each link checked separately: microphone, raw ASR, interpretation,
accepted result, persistence, notification or geofence delivery. ASR, parser,
model and integration failures are counted separately. Real audio across the
high-risk families (negation, quotation and messages, cancellation, conditions
and places, corrections, long mixed captures), never clean dictation.

What this prototype adds to that plan: the run record is the interpretation
half of the per-capture record. Promotion to the app would also need a product
decision this document does not make: three generations cost roughly three
times production's model latency, so the map cannot sit on the capture path;
the shape that respects "do not slow the capture path" is a revision after
save, which changes rows a person may already be looking at.

## The ten questions, today

No device run has been made with this code, so most answers are "not yet
measured", and each says what measures it.

1. **Short captures still excellent?** Unchanged by construction: nothing here
   is in the app. Category A of the fresh slice measures the map arm.
2. **Clear long multi-task captures reliable?** Not measured. Category B.
3. **Messy long speech improves?** Not measured. Category C, and M1.
4. **Model adds value beyond fallback?** Not measured. `mapChangedOutput` and
   the whole-capture difference between the `map` and `rules` arms.
5. **Quotes, corrections, conditions safely scoped?** By construction the map
   can only remove execution from them (S1). Whether it removes the right
   ones is M2 and categories F, G, I.
6. **Entities typed contextually?** Not measured; M3 decides whether the
   entity job is informative at all.
7. **What triggers unnecessary Needs Review?** Measured by the fresh slice's
   `review` column. The arbiter adds review only where the map says a row was
   corrected, withdrawn, made conditional or is message content.
8. **What fails without Apple Intelligence?** Nothing new: the map is absent
   and the output is the rules reading, byte for byte (`noMap`).
9. **Confirmed broad P0 family?** None can be confirmed or ruled out from
   this work; P0 is a device question under the exit gate.
10. **Ready for controlled TestFlight?** This prototype is not a candidate: it
    ships nothing. The TestFlight decision stays with the device baseline.

## Commands (Calvin's Mac)

```bash
./Tools/SemanticMap/build.sh                              # first compile; on failure, send build/build-errors.log
./Tools/SemanticMap/build/semantic-map --selfcheck        # must print "selfcheck ok"
./Tools/SemanticMap/build/semantic-map --availability     # model, context size, token counting
./Tools/SemanticMap/census-devsets.sh > census.txt        # no model: P1 on the development sets

# The diagnostic run: the rows the router hides, plus matched controls, on rambling only.
./Tools/SemanticMap/diagnostic.sh                        # writes output/semantic-map-diagnostic/<time>/
```

Send back `selection.txt` and `diagnostic.txt` from that folder (ids and
counts only), and `runs.jsonl` if the per-capture raw outputs should be read
here. The run file holds development-set text only, and is what lets every
later change to the deterministic half be re-scored without the model. The
full 85-capture run is not the next step.
