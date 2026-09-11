# Segmentation: what the current design cannot do

**2026-09-11.** A read-only investigation, written after two principled
attempts to extend clause splitting were measured and withdrawn on the same
day. Nothing here changes behaviour. Every claim cites the source it came from,
and every claim that could not be checked says so.

## Why this exists rather than a third attempt

The standing rule for this workstream is to find the failure family, fix the
layer, and prove it generalises — and to stop accumulating heuristics when the
architecture is the thing in the way. Two attempts in one day says it is.

- A **statement boundary** ([run 34596594804](https://github.com/CalvinSalsali04/speak-it/actions/runs/34596594804))
  gained **0 of 6** on `statement-runon`, the development family it was written
  for, left all 255 everyday captures bit-identical, and broke four CRITICAL
  cases of the gating corpus.
- A **relaxed fronted-adjunct test** ([run 34597902006](https://github.com/CalvinSalsali04/speak-it/actions/runs/34597902006))
  merged two captures that used to split correctly.

Both failed the same way: they read an `NLTagger` answer as a fact about the
sentence. "These words carry a subject and a predicate, so the clause is
finished." "This head carries no verb, so it is an adjunct." Neither is a fact;
both are a guess from a tagger that answers `OtherWord` for every token when
its model is absent (`Docs/KNOWN_ISSUES.md`).

Meanwhile the everyday held-out set has not moved on routing or thought count
across four measured runs, and its worst families are all segmentation:
`run-on` 0/8, `rambling-intro` 1/6, `sequencing` 7/17, `multi-thought` 19/40.

## What the pipeline does today

`ThoughtExtractor.splitClauses` (`SpeakIt/Repositories/ThoughtExtractor.swift:1266`)
is the whole of segmentation, in four stages:

1. One alternation regex over **surface markers**: newlines, semicolons, a
   comma followed by a connector and an action verb, an enumerator
   (`firstly`, `number two`, `another thing`), or a connector in front of a
   trigger word.
2. `ClauseJuxtaposition.pieces` (`SpeakIt/Repositories/SpeechRepair.swift`),
   the only stage that reads structure rather than surface — and it proposes a
   cut **only in front of a verb from a closed errand vocabulary**
   (`instructionOpeners`), then refuses it through a stack of guards.
3. `splitIndependentConjuncts`.
4. `mergeFragments`, which puts back pieces that cannot stand alone.

### The structural limit, stated precisely

**Every boundary this pipeline can find is either punctuated, connected by a
function word, announced by an enumerator, or immediately followed by an errand
verb.** There is no code path that proposes a boundary between two juxtaposed
*statements*.

That is not a gap in a heuristic. It is the shape of the design: stage 1 is a
regex over markers the recognizer may not have written down, and stage 2 needs
a word from a list on the right-hand side. "The flight lands at 6:40 Ines is
bringing the projector" contains no marker, no connector, no enumerator and no
errand verb, so it arrives as one row titled after the flight.

`statement-runon` reading 0 of 6 on thought count is that sentence, six times.
It is not a measurement of how well the rule works. **There is no rule.**

### And the distinction it would have to make is not structural

Established while writing the withdrawn attempt, and still true:

- "Our recycling goes out on Tuesdays / the garage code is 4821" is two rows.
- "The car is due its service / the mileage limit is thirty thousand" is one.

Same shape — complete clause, definite noun phrase, verb. What separates them
is whether the second half is *findable on its own*, which is the product
contract (Memory is for knowledge worth finding later) and not a fact about
the words. Embedding distance does not separate them either: `rent` and `lease`
are close neighbours and still two thoughts.

So a stronger structural rule is not the answer. The answer has to come from
information the pipeline does not currently have.

## Two pieces of information the app already has and throws away

### 1. The speaker's pauses

Both recognizer paths ask for per-word timing and then discard it.

- The analyzer path asks for it explicitly —
  `preset.attributeOptions.formUnion([.audioTimeRange, .transcriptionConfidence])`
  at `SpeakIt/Features/Capture/SpeechRecognitionBackend.swift:249` — and then
  flattens the result forty lines later: `let text = String(result.text.characters)`
  at line 290. `AttributedString.characters` drops every run attribute,
  `.audioTimeRange` among them.
- The `SFSpeechRecognizer` path takes `result.bestTranscription.formattedString`
  at line 89, discarding `bestTranscription.segments`, each of which carries a
  `timestamp` and a `duration`.

A person listening to "the flight lands at 6:40 … Ines is bringing the
projector" hears the boundary. It is in the audio, the recognizer measured it,
the app asked for it, and one line of string conversion throws it away. Every
stage downstream then tries to recover from word order alone a boundary the
speaker marked with silence.

**Cost of keeping it:** the timings do not need to be persisted.
`CaptureSession.originalTranscription` is a `String` in all four schema
versions (`SpeakIt/Models/SchemaV1.swift`), and adding a field would need a
SchemaV5 and a migration — but segmentation runs at capture time, so the
timings only have to survive from the recognizer to `ThoughtExtractor`, in
memory. Re-analysing an old capture later would not have them. That is a real
limit and a much smaller one than a schema change.

**What cannot be claimed:** whether pause length actually separates these
sentences is **unmeasured and currently unmeasurable here.** Every corpus in
this repository is text — `heldout.tsv`, `everyday.tsv`, `adversarial.tsv`, the
development sets and the gating corpus are all strings with no timings, and
`Tools/PipelineProbe` takes a line of text. So the instruments encode the same
assumption the parser does: that segmentation is a function of words alone.
Testing a pause-based boundary would need either real captures recorded with
their timings or a new instrument, and that work comes before any rule.

### 2. The on-device model, which is never asked

`FoundationModels` refinement is already integrated
(`ThoughtExtractor.swift:228`), already bounded to two seconds
(`extractWithinBudget`, line 2526), and already guarded against losing content
(`RefinementGuard.preservesEverything`). No paid inference, no network call.

It runs only when `RefinementPolicy.shouldRefine` says so, and that is
(line 187):

```swift
return fallback.contains { item in
    item.needsReview && item.organization.state.kind != .unsupported
}
```

**The model is consulted only when the rules already doubt themselves.** The
run-on failure is the exact opposite: the rules are confident and wrong. One
row, well-formed, nothing flagged. So on the captures where a second opinion
would help most, it is never asked for.

That is a gate keyed on the wrong signal. "Did the rules hesitate?" is not the
same question as "is this the shape of capture the rules are known to get
confidently wrong?" — a long capture with no punctuation that produced a single
row is the run-on signature, and it is cheap to recognise.

### And a measurement gap that follows from it

`Tools/PipelineProbe/README.md` says it plainly: the probe "runs the **rules
path only** … It does not run the Foundation Models refinement." Every language
number in `Docs/LANGUAGE_BASELINE.md` therefore measures the rules path.

The gate above bounds how much that matters: refinement fires only on
`needsReview` items, so for every other capture the rules answer *is* what the
user gets and the numbers are exact. But it means **no instrument here measures
what an iOS 26 user actually receives**, and if the gate were widened, the
numbers would stop describing the product until an instrument existed that
could run that path.

## What to do next, in order

1. **An instrument before a rule.** Nothing above can be evaluated with what
   exists. Decide whether the probe can run the refinement path, and what a
   corpus carrying timings would look like.
2. **Widening the refinement gate is the cheapest candidate** — no new
   dependency, no schema change, no capture-path work — and it is measurable as
   soon as step 1 is done.
3. **Keeping the timings is the more interesting one**, because it gives the
   parser a signal it has never had rather than a better guess at the one it
   has. It needs the capture path touched, so it needs a before-and-after
   latency measurement.
4. **Do not write a third structural rule for statement boundaries.** Both
   failed attempts, and the reason, are in
   `SpeakItTests/ActionabilityTests.testNothingCutsBetweenTwoJuxtaposedStatements`.

## What this document does not establish

- That pauses separate these sentences. Unmeasured, and no instrument here can
  measure it yet.
- That widening the refinement gate improves anything. The model has never been
  run against any corpus in this repository.
- That either change is safe on the capture path. Neither has been timed.
- Anything about a device. Every claim above is from the source, not from a run
  on an iPhone.
