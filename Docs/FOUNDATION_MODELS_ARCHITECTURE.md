# Interpreting a capture with Apple's Foundation Model

What this proposes, in one line: **the model decides what was said, and the
existing deterministic pipeline decides what Speak It does about it.**

    audio → transcript → Foundation Model interpretation → typed intent
          → deterministic policy and resolution → execution

This document records the boundary, what was built to try it, and — the part
that matters most — what is and is not measured. Nothing here has been run
against a model. See **What nobody has measured yet** before quoting any of it.

## 0. What was already there

`SpeakIt/Repositories/ThoughtExtractor.swift` already contains a complete
Foundation Models integration, and it is not the architecture above. It is a
*refinement*:

- `RefinementPolicy.shouldRefine` consults the model only when the rules already
  produced an item with `needsReview` set and a state other than `unsupported`.
  A capture the rules read confidently never reaches the model, however wrong
  that reading was. (The 2026-08-26 entry in `Docs/DECISIONS.md` describes a
  much broader trigger — every multi-row capture, plus a marker list. The code
  is the narrow version; the entry is a record of an earlier one.)
- A capture carrying any operation returns before the model is reached, so
  cancellation, completion and withdrawal are outside its reach entirely.
- `RefinementGuard.preservesEverything` requires the model's reading to preserve
  every row the rules found. Failing it keeps the rules reading.
- The model returns a seven-field struct: quote, title, inherited context, kind,
  category, person, confidence. There is no field for a correction, an abandoned
  thought, reported speech, negation, a reference, or an operation.

So the five families this project measures worst are, with one exception, the
families the current integration cannot reach: the rules must first flag the
capture, and the schema has no field for what went wrong. **Its quality
contribution has never been measured in either direction** — the corpus runner
calls `extractWithRules`, and no Apple Intelligence device has been available to
this repository.

## 1. What stays deterministic, and why

The split is not "rules for the easy half". It is: **anything whose failure the
person cannot undo stays deterministic, and anything that is a judgement about
language goes to the model.**

That principle needs a second axis, because on its own it does not separate the
two ways this pipeline gets a field wrong. **A loud failure is recoverable and a
silent one is not.** Marking a topic mention as a deadline fires a notification
nobody asked for: annoying, and dismissed in one tap. Marking a real deadline as
a topic drops the reminder and nobody ever knows to look. No data is destroyed
either way, and only one of them is ever found. The same asymmetry decides the
obligation field below — a task that lands in Memory is not lost, it is unseen —
and it is why `unclear` keeps its schedule and gets flagged instead of being
quietly made safe.

| Question | Who answers | Why |
|---|---|---|
| Which words belong to one thought | model | Segmentation is the top failure family and is a linguistic judgement; `run-on` is split correctly 2 of 10 times on the held-out set. |
| What the speaker was doing with a span — finished, abandoned, corrected, quoted, hypothetical | model | The pipeline has no field for any of these. They are reconstructed afterwards from structure; `decision` scores 1 of 6 on thought count and `ellipsis` 0 of 4 on destination. |
| Who owes the action | model | "Sarah needs to send it" and "I need to send it" differ by a word and by everything. |
| Which words are the time, the place, the person | model | Naming a span is what a model is good at. |
| **What that time is** | **rules** | `TemporalIntent` and the recurrence parser. A model has no field for a date; the schema physically cannot carry one. |
| **Whether it schedules** | **rules** | "A date says when something is true, not that there is something to do" is a product contract, not a reading. |
| **Today or Memory** | **rules, over a model-supplied field** | `ThoughtOrganizer` and `ActionabilityReader` decide, and they already have to agree with each other — but see the paragraph under this table. This row is the one place the boundary is easier to state than to hold. |
| **Whether a place becomes a geofence** | **rules** | `LocationIntentParser` plus the saved-place store. |
| **Which stored row a "cancel that" means** | **rules** | `CaptureTargetMatcher`. The model reports the words; matching needs the store and is where a wrong answer destroys data. |
| **Whether a destructive request runs at all** | **rules, plus agreement** | See below. |
| Persistence, migration, notifications, recurrence arithmetic, Live Activity, StoreKit | rules | None of it is language. |

**Where this boundary is thinnest, said plainly.** `obligation` is not the same
kind of field as `temporalRole`. `ActionabilityReader.read` contains
`if obligationBelongsToAnotherPerson(value) { return .knowledge }` — whose
errand it is *is* the Today-or-Memory decision, not an input to it. So calling
destination deterministic while the model supplies the obligation is true about
which code runs and misleading about what decides. The honest statement: the
mapping from obligation to destination stays a deterministic product contract,
and the evidence that mapping consumes now comes from the model. That is the
trade, and it is the thing the comparison has to measure first.

Two prior facts make the size of it visible, both from this repository rather
than from reasoning. The obligation vocabulary lives in five lists in four
files, which agree on five of the thirty-seven forms between them, and the
2026-09-15 decision is that merging them is wrong because three of the
differences are load-bearing. One of those differences is a safety property a
classifier cannot have: `ObligationFrame.link` is safe *by omission* — a form it
does not list can never sit inside the span it deletes, so an unrecognised
wording keeps its words. A model asked for `obligation` answers for every input,
including wordings nobody has seen; it cannot decline. It converts "I did not
recognise this" into a confident third option. That is not a reason to keep the
field in the rules, but it is a property being traded away on purpose rather
than by accident.

**The destructive rule.** An operation the model reported executes only when the
deterministic partitioner independently read an operation of the same kind in
the same capture. The model may describe a cancellation; it may not be the only
reading that saw one. Everything else arrives with `needsReview` set, which is
the existing behaviour for an unresolvable target: Speak It asks. A request that
reaches everything — "cancel all my reminders" — is refused before agreement is
even considered, because both readings agreeing is not a reason to destroy
everything.

## 2. The schema

`SpeakIt/Interpretation/CaptureInterpretation.swift`. A capture is `segments`
and `operations`.

Each segment carries: the exact `quote`; `carriedContext` for words that apply
to it from elsewhere in the capture; a `disposition` (`stated`, `corrected`,
`abandoned`, `reported`, `hypothetical`, `aside`); `polarity`; an `obligation`
(`speakerOwes`, `otherOwes`, `noObligation`, `unclear`); `attributedTo` for
quoted words; `supersededBy` for a correction; `temporalText` with a
`temporalRole`; `locationText` with a `locationRole`; `personNamed`;
`references` for pronouns; a `suggestedTitle`; and a confidence.

Three properties are worth stating because they are what make the boundary
enforceable rather than aspirational:

1. **There is no `Date` in the file.** Not one. A model cannot return an instant
   because there is nowhere to put one.
2. **Every field that quotes the person is an exact span of the transcript**,
   including every cross-reference. So a correction pointing at a span that does
   not exist, an invented name, an invented deadline and a hallucinated errand
   all fail the same mechanical check.
3. **There is no destination and no execution.** The word "Today" does not
   appear in the schema.

`temporalRole` and `obligation` deserve a note. They are the two fields that
carry a linguistic judgement the deterministic layer currently has to infer from
substrings: "ask Dana about Friday" has a weekday in it and no deadline, and
somebody else's "needs to" is an obligation that is not the speaker's. Recording
`temporalText` is not resolving it — `ThoughtOrganizer` still reads those words
with the same parser it always has. `obligation` is the field where "recording
is not deciding" does *not* hold, for the reason in section 1.

**Which fields are read, and which are only recorded.** An enum case nothing
downstream can observe is a marker standing in for a judgement, which is this
codebase's recurring defect, so the list is stated rather than implied.

Read by `InterpretationBridge`: `disposition`, `obligation`, `temporalRole`
(`topic` and `standingFact` remove a schedule), `locationRole` (only
`arrivalTrigger` and `departureTrigger` keep a place trigger),
`references.refersToExistingItem`, `confidencePercent`, `suggestedTitle`,
`quote` and `carriedContext`.

Recorded and not read: `polarity`, `attributedTo`, `personNamed`,
`supersededBy` and `references.refersToQuote`. Each is checked by the policy —
`supersededBy` must name another segment, `attributedTo` and `personNamed` must
be in the transcript — and each is carried for a reader rather than acted on:
the organizer infers the person itself, and the negation is in the words it
reads. Acting on them is a behaviour change, and behaviour changes here want a
measurement first.

## 3. The prototype

Four files, none of which production calls:

- `SpeakIt/Interpretation/CaptureInterpretation.swift` — the schema. No Apple
  Intelligence dependency; compiles and is testable anywhere.
- `SpeakIt/Interpretation/InterpretationPolicy.swift` — the deterministic gate.
  Grounding, structural impossibilities, invented detail, and the agreement rule
  for destructive requests.
- `SpeakIt/Interpretation/InterpretationBridge.swift` — interpretation to rows,
  by calling `ThoughtOrganizer.organize` on each segment's own words. Its
  overrides only ever withdraw capability.
- `SpeakIt/Interpretation/ModelInterpreter.swift` — the only file that talks to a
  model. `@Generable` mirror types, instructions, greedy sampling.

`ThoughtExtractionEngine` does not call any of it. Wiring shadow mode later is a
call site, not a rewrite.

**On-device, enforced.** `Tools/CorpusRunner/test_interpretation_isolation.py`
fails the build if anything under `SpeakIt/Interpretation/` names a URL, a
session, a socket or any model other than `SystemLanguageModel`, and if the
policy, bridge or schema import FoundationModels. It runs on Linux on every pull
request. The rule exists because the sealed sets may be pointed at this path,
and a set that has been sent to somebody's server cannot be made unseen again —
there is no red build that undoes it.

**Know its shape before citing it as total.** It is keyed on names, and guards
that share a vocabulary share a blind spot. A network call reached through a
helper in another directory, or through a type alias, is invisible to it. It
catches the way this rule would actually be broken — somebody adding a call
here later — and it is not a proof.

## 4. How the comparison runs

`Tools/InterpretationProbe/build.sh` builds `interpret`, which emits **the same
report format as `Tools/PipelineProbe`** — both now share
`Tools/PipelineProbe/rowreport.swift`, so the two emitters cannot drift. Every
scorer this project already has (`devsets/score.py`, `everyday/score.py`,
`heldout/score.py`) can therefore score the generative path unchanged.

    interpret --availability                       # what the framework says here
    interpret --interpret utterances.txt --out runs.jsonl [--runs 3] [--repair]
    interpret --replay runs.jsonl [--fallback] [--annotate]
    interpret --spread runs.jsonl
    interpret --selfcheck                          # needs no model

Generating needs hardware. Everything after it does not: `--replay` takes the
recorded interpretations and runs policy, bridge and resolution deterministically
on any Mac. So a run made once on a device can be re-scored by anybody, and a
change to the deterministic half is checkable without paying for the model
again.

`--fallback` is the difference between two questions. Without it you measure the
model path alone, and a rejected reading scores as a failure. With it a rejected
reading falls back to the rules, which is what shipping would actually do.

**`--spread` is a measure in its own right.** A generative path has no single
score: the same capture can read two ways on two runs. Sampling is pinned to
greedy and recorded with every run, and an intent that changes between runs is a
product defect even when both readings are defensible.

## 5. The dangerous families, and what the schema does about each

| Family | Today | What the schema adds |
|---|---|---|
| run-on / multi-thought | destination 10/10, split 2/10 held out; the splitter recognises two connectors, `and` and `so`, of the eight people use | Segmentation is asked for directly rather than derived from connector vocabulary. This is the family with the most to gain and the one a connector list cannot reach. |
| abandoned thoughts | `ellipsis` 0/4 on destination; `ThoughtCompletion.unfinished` reads the last token and its predecessor | `disposition: .abandoned`, which the bridge turns into a kept note with `incompleteThought` and no schedule. |
| reported speech | 3/10, and the harm-shaped one — somebody else's sentence becoming the speaker's errand | `disposition: .reported` plus `attributedTo`, and the policy *rejects* a reading where quoted words arrive as the speaker's obligation. |
| negation and removal | "Don't buy milk" reads as a cancel with no items; `cancel` reaches further than `remove` | Polarity and operations are separate fields, and no operation executes on the model's word alone. |
| corrections | `SelfCorrectionResolver` repairs by slot replacement, so a whole-clause alternative has no slot | `disposition: .corrected` with `supersededBy`, which is a clause-level relation rather than a slot. |

## 6. Shadow mode

The wiring, when it is wanted, is one branch in
`ThoughtExtractionEngine.extract`:

1. The rules path runs and returns, exactly as now. The person's capture never
   waits on the model and never depends on it.
2. When shadow mode is on and the model is available, a **detached** task
   interprets the same transcript, runs the policy and the bridge, and compares
   the rows to the rules' rows.
3. The comparison is recorded **locally and content-free**: which rule rejected
   a reading, whether the row count differed, whether the destination differed,
   which disposition was involved. `SpeakIt/App/AnalyticsService.swift`'s closed
   vocabulary is the standard, and no transcript, title, name or span may leave
   the device. A local diagnostic file, readable in Account & Settings, is the
   most this should ever be.
4. Nothing the shadow path produces is shown or saved as a row.

Two things have to be true before that branch is written: the model has to be
reachable on a real device, and the comparison has to be worth recording — which
is the measurement in section 4, not a guess.

## 7. What nobody has measured yet

This is the section to read before quoting anything above.

- **No model has run.** Not once, not here. Every claim above is about what the
  code does with an interpretation, not about what an interpretation looks like.
- **The Swift in this change has not been compiled.** It was written on Linux,
  where Apple's NaturalLanguage and FoundationModels do not exist. The `language`
  CI job now builds the prototype and runs its self-check, which is where the
  first compile happens.
- **Whether the model can be reached on our CI at all is an open question with a
  cheap answer.** `interpret --availability` prints what the framework reports
  and never fails the job. The expectation, from `Docs/DECISIONS.md`, is
  `appleIntelligenceNotEnabled` or `deviceNotEligible` on a hosted runner; the
  point of the step is to stop expecting and know.
- **`--repair` is an unanswered fork**, not a setting. The rules have always been
  given repaired text; a model is supposed to handle disfluency itself. Which one
  it should get is a measurement, and the flag is recorded in every run so the
  two cannot be confused.
- **Our sets can only show whether the new path beats the parser on material we
  wrote.** Every readable utterance in this repository was authored by this
  project. A generative path could plausibly do better on speech it has seen in
  training and that we have never written down — which is the whole argument for
  it — and our corpus cannot detect that, in either direction.

## 8. What real recordings would have to settle

The open ask for twenty to thirty real captures is unchanged by this proposal,
and three of the questions it answers are now sharper:

1. **Do the dispositions occur?** `corrected`, `abandoned`, `reported` and
   `hypothetical` are our categories. Nothing establishes their frequency in
   real speech, and a schema field for a phenomenon nobody produces is cost with
   no benefit.
2. **Does interpretation survive a real transcript?** Everything measured here
   is text. Real captures arrive through Apple's recogniser, which errs before
   any interpreter sees a word, and no figure in this repository measures a
   capture end to end from audio.
3. **How long does it take on the device the person owns?** Apple's on-device
   model runs at tens of tokens a second on the floor device. A capture that
   waits on it is a different product from one that does not, and no figure here
   has been measured on hardware.

A portion sealed before any session reads a line is still the part that makes
them evidence rather than more material we wrote.

## 9. No custom model

Nothing here trains anything. The question this exists to answer is how far
Apple's model gets on its own, and that question is unanswerable while a second
variable is moving.
