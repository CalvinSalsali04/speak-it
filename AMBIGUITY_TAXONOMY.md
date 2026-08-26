# Ambiguity taxonomy

The semantic architecture specification. Each family names a decision English
genuinely leaves open, the signals available to settle it, which of those
signals Speak It currently trusts, how it fails, and what it should do when the
evidence runs out.

This document exists because the repair unit is a **family**, not a sentence. A
defect that is not placed in a family here will be fixed with a rule, and a rule
fixed one sentence at a time is how a parser rots.

Status values used below:

- **STRUCTURAL** — decided from sentence structure or closed grammatical class.
  Generalizes to words the app has never seen.
- **VOCABULARY** — decided by membership of an open-class word list. Does not
  generalize; the list is always one word short.
- **ABSENT** — the distinction is not represented anywhere in the pipeline.

Every claim marked *measured* was reproduced through the real rules path against
the fixed frame Monday 2026-08-03 10:00 America/Toronto.

## Instruments

| instrument | what it answers | current |
|---|---|---|
| `SpeakItTests/SemanticCorpus*` | does the app still agree with the contract | 1,000 of 1,022 clean, 0 blocking |
| — of which `Ordinary speech (control)` | does a rule fire when it should not | 133 cases, 0 failures |
| `Tools/CorpusRunner` | the same question in 20s instead of 6 minutes | — |
| `Tools/CorpusRunner/mutation-gate.sh` | is a subsystem actually protected | 10 of 10 protected |
| `Tools/CorpusRunner/heldout` | does it generalise to unseen wording | 71.6% destination · 9 of 69 ambiguous captures acted on |

The corpus is a regression net and cannot detect improvement — it is at ceiling
by construction, because it is authored from this contract by the same person
who writes the rules. The held-out set is the progress meter. Read
[Tools/CorpusRunner/heldout/README.md](Tools/CorpusRunner/heldout/README.md)
before touching it.

---

## 1. Command versus statement (speech act)

Whether the person is asking the app to do something, or telling it something.

- **Signals available:** imperative shape (verb-initial, no subject); subject
  person and number; tense; modality; subject-auxiliary inversion; vocatives.
- **Signals trusted today:** verb-initial position, an action-verb list, and a
  set of obligation lead phrases.
- **Status:** partly STRUCTURAL, partly VOCABULARY.
- **Known failure modes:** an errand whose verb is not on any of the six
  action-verb lists reads as a note. A question with clear directive force
  ("can you pick up milk on the way home") reads as a note.
- **Fallback:** Memory, preserved verbatim.

## 2. Matrix clause versus complement clause

Whether a keyword governs the whole utterance or sits inside something the
speaker is reporting, quoting, or asking to have relayed.

- **Signals available:** communication and reporting verbs (a near-closed class:
  tell, text, email, message, say, ask, let X know, hear, mention); the
  complementizer `that` and its elision; a second finite verb after the matrix
  verb's object.
- **Signals trusted today:** three closed-class frames, in
  `CaptureOperationDetector.cancellationIsEmbedded` — an imperative
  communication verb with a recipient behind it (relay), a finite verb of saying
  (report), and a recording verb (record). Tested on the **whole capture**, never
  on the clause, because the clause splitter throws the frame away.
- **Status:** STRUCTURAL, and scoped to the descriptive cancellation family
  only. Explicit commands in `cancelPatterns` are unaffected.
- **Known failure modes before the guard:** *measured, 12/12* relay frames and
  *6/6* report frames produced a cancel operation and zero rows. Now 0/18, with
  the 10 explicit cancellations still cancelling.
- **Still missing:** the distinction exists only where cancellation is decided.
  Reported speech elsewhere — agent versus patient in "Sarah told Mike" — has no
  representation, so family 14 is unchanged.
- **Fallback:** a cue in a complement clause never triggers an operation.
- **Tests:** `SemanticCorpusO.speechActScope` (31 cases). Mutation: deleting the
  guard costs 38 blocking failures.

## 3. Negation scope

Which predicate a negator modifies, and whether the result is prohibitive.

- **Signals available:** the negator's position relative to the matrix verb and
  to any infinitival complement; negative polarity items; `never`, `no longer`,
  `instead of`, `skip`, `avoid`.
- **Signals trusted today:** adjacency to the infinitival connector, in
  `ReminderPhrasing.isProhibitive`. Both spellings English allows — `not to VP`
  and `to not VP` — normalise to one reading, and the prohibition is rendered as
  a negative imperative rather than stripped.
- **Status:** STRUCTURAL for scope. The *representation* is still partial: there
  is no field on `ThoughtOrganization` meaning prohibitive, so the negation
  lives in the row's own wording. `inferredType` refuses an action type for a
  prohibition, on the ground that a prohibited action is not an instance of that
  action — "don't buy milk" is not a shopping row.
- **Known failure modes before the fix:** *measured* — "Remind me not to eat
  before the blood test" became the task "Eat before the blood test" and fired a
  notification for it. The two spellings behaved oppositely. Now 10/10 paired
  spellings agree on every field, and the row reads "Don't eat before the blood
  test". Still correct: "Don't forget to call Mom" → "Call Mom"; "Please don't
  pay the invoice yet" preserved as Memory.
- **Fallback:** a negator that cannot be attached to a predicate forces review.
  It must never silently disappear.
- **Tests:** `SemanticCorpusP.prohibitions` (17 cases, `severityFloor:
  .behavioral` because the title is the notification body). Mutation: deleting
  the rule costs 17 blocking failures.

## 4. Name versus common noun

Whether a token refers to a person or is an ordinary word.

- **Signals available:** argument position relative to a person-taking verb;
  determiner presence (a determiner rules out a bare given name); possessive and
  appositive frames; coordination partners; embedding out-of-vocabulary status;
  capitalization (unreliable).
- **Signals trusted today:** capitalization, an NLTagger `.nameType` reading, and
  a ~400-entry `neverName` list — an unbounded complement expressed as a list.
- **Status:** VOCABULARY, with a capitalization dependency.
- **Known failure modes:** *measured* — NLTagger tags "Call" itself as a
  PersonalName in "Call Bill about the invoice", and tags "and" as a PersonalName
  in "Call Alex and Alexa". "Rose" reads as OtherWord even title-cased.
  Lowercasing the corpus produces 6 CRITICAL failures, all of them this family.
  Embedding OOV is high-precision (15/16 distinctive names OOV, 0/12 ordinary
  nouns OOV) but 14/16 of the hard names — bill, mark, grace, rose, hope, will —
  are in vocabulary, so it covers only the easy cases.
- **Fallback:** prefer the reading that does not create an outward-facing action.

## 5. Person versus occupation

"Call Dr. Patel" versus "call the dentist" versus "Patel is my dentist".

- **Signals available:** determiner presence; occupational morphology (-ist,
  -er, -ian); embedding distance to occupation seeds; copula frames.
- **Signals trusted today:** morphology plus embedding distance to 12 seeds with
  published thresholds and a reported error rate.
- **Status:** STRUCTURAL. **This is the template for the rest of the app** — it
  is the only decision that scores evidence and admits its own failure rate.
- **Known failure modes:** words outside the embedding vocabulary fall back to
  the default reading.
- **Fallback:** treat as a described target, not a named person.

## 6. Noun versus verb

"book a table" versus "read the book"; "charge the phone" versus "a charge on my
card".

- **Signals available:** determiner and preposition context; position; NLTagger
  lexical class **over a full sentence**.
- **Signals trusted today:** full-sentence tagging in the shopping reader
  (correct); **fragment tagging** in the conjunct splitter (incorrect).
- **Status:** STRUCTURAL where full sentences are tagged; unreliable elsewhere.
- **Known failure modes:** the same tagger calls "chicken", "salt" and "juice"
  verbs in isolation and nouns in context. The conjunct splitter tags the right
  conjunct alone, so it inherits exactly that error.
- **Fallback:** do not split.

## 7. One thought versus coordinated objects

Whether `and` joins two objects, two predicates, or two sentences.

- **Signals available:** presence of a finite verb on the right conjunct;
  presence of an independent subject; verb ellipsis and gapping; coordinate
  parallelism.
- **Signals trusted today:** a cascade that tags the right conjunct in isolation
  and consults person-detection and store-detection as side effects, plus an
  anaphora test: a non-actionable conjunct whose subject is a pronoun, a negative
  quantifier, or absent continues the previous clause instead of starting a new
  thought. Both halves must be recollection — anaphora binds reference, not
  commitment.
- **Status:** partly STRUCTURAL, with a VOCABULARY fallback for product lists.
- **Known failure modes:** *measured* — comma-less lists of unfamiliar products
  split correctly 0/5, versus 5/5 for familiar ones. Measured on the three
  coordination types with matched frames: NP 10/10 and VP 10/10 keep every
  conjunct actionable; S-coordination is the weak one. Mutation: forcing the
  conjunct test always-false costs 23 blocking failures.
- **The three cases, all decidable from a full-sentence POS sequence:**
  - `buy milk and eggs` — right side has no verb and no subject → NP
    coordination → one thought, two objects.
  - `buy milk and text Daniel` — right side has a finite verb, no subject → VP
    coordination → two thoughts, shared subject.
  - `buy milk and Sarah hates sushi` — right side has its own subject and
    predicate → S coordination → two independent thoughts.
- **Fallback:** do not split. A merged thought is recoverable by the person; a
  wrongly split one has already lost its shared time and person.

## 8. Shopping item versus abstract object

- **Signals available:** acquisition verb; determiner pattern; count/mass
  morphology; embedding region.
- **Signals trusted today:** the acquisition verb (structural) for **type**, and
  a ~230-entry grocery list for **which list**.
- **Status:** type is STRUCTURAL; list assignment is VOCABULARY.
- **Known failure modes:** *measured* — item type is correct 30/30 for products
  the app has never seen, but list assignment is correct 0/25. Every unfamiliar
  food lands on "Other". Also "get bloodwork done tomorrow" reads as shopping.
- **Fallback:** the default list, which is the current behaviour and is
  acceptable — the wrong list is a mild cost, the wrong destination is not.

## 9. Time versus quantity

Numbers that are not clock times.

- **Signals available:** the head noun the number modifies (table **for** four,
  flight 815, aisle 12, size 10); preposition (`for` a party size versus `at` a
  time); currency and unit markers.
- **Signals trusted today:** a set of negative lookarounds around clock patterns.
- **Status:** VOCABULARY of exceptions.
- **Known failure modes:** *measured* — "Book a table for four" resolves to
  16:00; "Book a table for eight at nine" resolves to 20:00, letting the party
  size beat the explicit "at nine".
- **Fallback:** no time. A missing time is visible; a wrong time is not.

## 10. Future event versus task versus memory

- **Signals available:** tense; aspect; subject person; whether the speaker is
  the agent; explicit request verbs.
- **Signals trusted today:** two separate taxonomies computed independently and
  reconciled by three one-way promotion rules.
- **Status:** partly STRUCTURAL, partly VOCABULARY.
- **Known failure modes:** `inferredType` ends in `return .note`, so "I
  recognized nothing" is the most common outcome and the promotion rules exist
  to rescue it.
- **Fallback:** Memory.

## 11. Correction versus second thought

"Friday, actually Saturday" (one thought, repaired) versus "Friday and also
Saturday" (two).

- **Signals available:** edit terms; **word and POS parallelism between the
  reparandum and the repair**; whether the two candidates fill the same slot.
- **Signals trusted today:** edit-term marker lists, plus a same-slot test.
- **Status:** VOCABULARY. Note that `ThoughtExtractor.correctedText` is dead
  code with no caller; the live implementation is `SelfCorrectionResolver`.
- **Known failure modes:** "Buy 2 apples, no 3" produces the title "Buy 3apples"
  *(measured)*. "tomorrow no not tomorrow Wednesday" resolves to the retracted
  date. A marker mid-sentence can swallow the object before it.
- **Fallback:** keep both readings and force review rather than deleting the
  earlier one.

## 12. Recurrence versus a single occurrence

- **Signals available:** `every`, `each`, `daily`, plural weekday forms, and
  crucially the **scope** of the quantifier.
- **Signals trusted today:** a quantifier over weeks, plus a weekday that is not
  behind an exception marker and not inside a noun phrase. The wall clock comes
  from `TemporalIntentParser.statedWallClock` — the app's one clock grammar —
  rather than from a second reader of its own.
- **Status:** STRUCTURAL for scope; the frequency words themselves are a
  genuinely finite set.
- **Known failure modes before the fix:** *measured* — "Wake me at 7 daily" gave
  19:00 while "Set an alarm for 7" gave 07:00; "Set an alarm for 5 every morning"
  and "…for 6:30 every weekday" both gave 09:00, discarding an hour that had
  already been parsed. "Remind me weekly on Sundays" fired Monday, because the
  weekday pattern matched only the singular. "I go to the gym every day except
  Sunday" read as weekly on Sundays. All fixed.
- **Still open:** "Daily at 9 take the meds" resolves a due time but leaves
  `delivery: none`, so it never alerts. That is a delivery-selection defect, not
  a clock one.
- **Fallback:** single occurrence at the time actually spoken.
- **Tests:** mutation — deleting `statedWallClock` costs 3 blocking failures.

## 13. Location versus organization versus person

- **Signals available:** motion verbs; prepositions (`at`, `from`, `to`);
  saved-place names; whether the candidate also reads as a person.
- **Signals trusted today:** lead patterns plus a 68-entry store list, or "every
  token is capitalized".
- **Status:** VOCABULARY, with a capitalization dependency.
- **Known failure modes:** "pick up milk and eggs from Sarah" assigns the list
  "Sarah". An unknown store spoken lowercase yields no list name at all.
- **Fallback:** no place trigger. A geofence the person did not ask for is a
  worse error than a missing one.

## 14. Reported command versus actual command

"Call Mike tomorrow" versus "Sarah said call Mike tomorrow" versus "Sarah said
she'd call Mike tomorrow".

- **Signals available:** a reporting verb with a clausal complement; the subject
  of the embedded clause; agent versus patient role.
- **Signals trusted today:** a reported-speech pattern in the actionability
  reader, which does not carry role information forward.
- **Status:** partly present, but role assignment is ABSENT — person selection is
  positional, so "Sarah told Mike" has no representation distinguishing teller
  from told.
- **Fallback:** Memory, with both names preserved.

## 15. Preference versus request

"Sarah doesn't like sushi" versus "don't order sushi for Sarah".

- **Signals available:** subject person; stative versus dynamic predicate;
  imperative shape.
- **Signals trusted today:** predicate lists plus subject detection.
- **Status:** VOCABULARY.
- **Fallback:** Memory as a person fact.

## 16. Pronoun reference

- **Signals available:** number and gender agreement; recency; grammatical role
  parallelism; c-command constraints.
- **Signals trusted today:** the first detected mention above low confidence,
  with no agreement check.
- **Status:** VOCABULARY plus recency.
- **Known failure modes:** "call Priya tomorrow and drop the kids at **their**
  swim lesson" attributes *their* to Priya.
- **Fallback:** leave the pronoun unresolved. Do not attach a person.

---

## Cross-cutting rules

1. **Context.** No analyser may receive less than a full sentence when a full
   sentence is available. Tag once, over the raw sentence; sub-spans read the
   tags they already carry. Never construct a fragment or a synthetic sentence
   to tag.
2. **Action safety.** Creating an actionable object, scheduling a notification,
   creating a geofence, or modifying an existing item requires strictly more
   evidence than preserving something as Memory.
3. **Abstention.** When the top two readings are close, preserve the wording and
   offer both. Do not pick silently. Across the adversarial set, 40% of
   genuinely ambiguous utterances produced an actionable row or a date.
4. **Rendering.** Punctuation and casing must not change meaning. Comma-free and
   unpunctuated renderings currently hold at zero blocking failures; lowercased
   does not, and the gap is entirely family 4.
5. **Preservation.** The parser may remove command scaffolding. It may never
   invent content — no word in a title without a spoken source or a declared
   repair.

## Adding a family

A new defect belongs here before it is fixed. Record the signals available, the
signal you intend to trust, and the counterexample class that signal will
create. If you cannot name what the rule would wrongly capture, it is not ready
to be written.
