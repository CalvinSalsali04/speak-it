# Architecture

## Platform

- SwiftUI application targeting iOS 17+
- SwiftData local persistence
- Speech and AVFoundation for live in-app transcription
- App Intents, AudioRecordingIntent, ActivityKit, and App Shortcuts for background capture
- NaturalLanguage rules with optional Foundation Models refinement on supported devices
- XCTest with in-memory SwiftData stores
- The iOS target uses Apple frameworks only; the optional referral program uses
  the separately deployed Node service in `ReferralService`

## Data flow

```text
Voice or text capture
    ↓
SpeechTranscriber / App Intent
    ↓ raw transcript checkpoint
CaptureDraftStore
    ↓ durable parent + placeholder
ThoughtRepository protocol
    ↓
SwiftDataThoughtRepository
    ↓ ThoughtExtractionEngine
Rule-based extraction → optional on-device Foundation Models refinement
    ↓ atomic item replacement
ModelContext → local SwiftData store
    ↓
ReminderScheduler + @Query-backed SwiftUI views
```

Views may query models with `@Query` for presentation, but they do not insert, mutate, save, or delete persistent models directly. All commands pass through `ThoughtRepository`, injected with a custom SwiftUI environment value.

`PersistenceController.shared` owns the production `ModelContainer`. In-app and outside-the-app capture use the same repository path, so both follow the same extraction, validation, reminder, and durability rules.

Schema versioning keeps two things apart on purpose. Every numbered version in `SchemaV1.swift` — `SpeakItSchemaV1` through `SpeakItSchemaV4` — is history: each nests its own frozen `@Model` copies, none may ever be edited, and together they are what `SpeakItMigrationPlan` migrates a store *from*. `SpeakItSchemaCurrent` is the live shape the app addresses, is the only declaration allowed to move, and is what `PersistenceController.schema` opens. Collapsing the two — letting the newest numbered version name the live classes — is what makes adding the next version redefine the previous one and stop existing stores from opening. `SchemaFreezeTests` pins the version 3 contract to a real store a shipped build wrote, pins version 4 to the shape it was introduced with, and fails the moment a persisted model changes shape without a new version.

Version 4 stores what the interpreter concluded. `OrganizedThought.state` — a `SemanticState` of `resolved`, `underspecified`, `contested` or `unsupported`, carrying a named `SemanticGap` when it is not resolved — used to be computed for every reading and dropped on the way into `CapturedItem`, so "Needs review" reconstructed a reason afterwards from the item's type, person and dates. It is now written to `semanticStateRawValue` and `semanticGapRawValue`, and `CapturedItem.clarificationRequirement` reports the recorded gap ahead of that reconstruction. Two things still outrank it, because neither is a reading of a sentence: a held destructive request, and what the device is waiting for on a place trigger. A row with no recorded verdict — everything written before version 4 — keeps the derivation it already had and is never reported as `resolved`.

Voice data flows through `SpeechTranscriber`: permission request → model preheat → audio engine → first-buffer readiness cue → partial Speech results → adaptive natural-pause detection → final transcript → repository. The Core Audio tap performs only a bounded buffer copy and level measurement; ordered recognition conversion, recovery-file writing, and quality analysis run on `SpeechCaptureAudioProcessor` away from the real-time callback. That processor is synchronously drained before the backend receives `endAudio()`, preserving the final queued syllable. Recognition itself runs behind the `SpeechRecognitionBackend` protocol (`SpeechRecognitionBackend.swift`): on iOS 26+ with the current locale's model installed, capture uses Apple's on-device `SpeechAnalyzer` with the dictation-specific `DictationTranscriber`, progressive high-quality results, N-best/confidence attributes, lingering model retention, and `SpeechDetector` voice activity. This is the Apple path documented to consume contextual strings. Otherwise — older iOS, unsupported locale, or a model still downloading in the background — it falls back to the original `SFSpeechRecognizer` path, so capture is never blocked on a model download. Both backends feed the same orchestration, vocabulary corrections, and durability machinery. Context is ranked and capped at Apple's 100-phrase limit; only the preferred side of an explicit correction is boosted. Outside the app, partial text is mirrored into a Live Activity. During an unfinished voice capture, `CaptureDraftStore` also holds an encrypted-at-rest, backup-excluded temporary recording so recognizer or process interruption cannot silently lose the person’s words. It is deleted immediately after a successful save or intentional discard. A recording whose recovery fails is never removed automatically: Capture history offers Try Again, Type Instead, and a confirmed Delete Recording, and deletion writes a tombstone in `CaptureDraftStore` so a checkpoint written elsewhere cannot resurrect it on the next launch. Failure copy comes from `CaptureRecoveryPresentation`, keyed on `CaptureRecoveryFailureKind` rather than the recognizer's own message.

The in-app voice screen starts in continuous capture and waits for explicit
Finish. Its protected audio draft is required before recording begins. The
person may explicitly select Auto finish; only that mode uses natural-pause
detection, a bounded state machine rather than one global silence timer.
Apparently complete wording uses a 1.9-second silence window. Ambiguous
endings show **Still listening…** and wait up to 4 seconds; strong continuation
cues use the same status and wait up to 8 seconds. A new transcript cancels and
reclassifies the pending endpoint. Recent microphone activity can briefly rebase
the decision before the
recognizer catches up, but those deferrals are capped so background noise cannot
hold the microphone open indefinitely. Manual pulse taps, interruptions, and
protected-recording recovery retain their existing precedence. A backend only
reports whole-stream completion after the app closes its audio input; stable
SpeechAnalyzer segment results are assembled without being mistaken for the end
of the user's turn.
Endpoint classification tokenizes spoken letters and numbers independently of
punctuation, so pause-induced formatting such as `tomorrow. At.` cannot hide the
final continuation word. Display and persistence still retain the recognizer's
original punctuation unchanged. The same lexical signature stabilizes partial
results: formatting-only ASR revisions update the visible transcript without
restarting the pause clock or hiding its prompt, while word additions, removals,
or substitutions cancel and rebuild the decision. A retraction to no lexical
content cancels the pending endpoint.
See `VOICE_ENDPOINTING_DECISION.md` for the evidence, edge cases, and beta gate.

`CapturePerformanceTrace` follows the in-app path from activation to microphone
readiness and from the last detected voice activity to a real
`CapturedItemRow` rendered from the final persisted model. OSSignposter stages
separate transcript finalization, semantic parsing, temporal resolution, raw
durability, final persistence, rendering, and later notification acceptance.
All elapsed values use `ContinuousClock`; wall-clock `Date` values never enter
latency arithmetic. Legacy voice activity is timestamped on the audio callback
before UI throttling; iOS 26 uses Apple's trained detector so steady noise does
not extend a turn. The endpoint decision and final transcript are separate
milestones. Recoverable or asynchronously enriched rows are excluded until they
are stable.
Only closed enums and integer durations may enter performance analytics; the
trace never retains or logs user-authored content. See
`PERFORMANCE_BENCHMARKING.md`.

Inside rule-based extraction the order is: speech repair, then operation
partitioning, then **intent consolidation**, then clause splitting, then
organizing. Consolidation (`IntentConsolidator`) answers *how many things were
said* before anything answers *what they are*. It can only ever collapse a
capture to one item, never split one, and it fires only when the wording is
positively narrative — so a paragraph elaborating on a single phone call becomes
one row, while a list of three errands is left to the splitter untouched.

Destination is decided by two independent readings that must agree.
`ActionabilityReader` reads the wording; `CapturedItem.belongsInToday` /
`belongsInMemory` read the stored item. Both follow one rule: **a date says when
something is true, not that there is something to do.** A resolved date never
moves a fact to Today; only a reminder — asked for out loud, or set by hand in
the editor — does. Memory then splits People from Reference purely on whether
the item names somebody.

Semantic readers match grammatical evidence, never arbitrary substrings.
Taxonomy uses whole words and explicit phrase frames; a bare clock is read only
when the item or reminder context permits one; and motion-shaped words require
a spatial complement before they create a place trigger. A fronted condition
belongs to the instruction after its comma rather than becoming a second item.
When that condition is clear but cannot be monitored (for example payday or
another event completing), its temporal intent records an unsupported
condition and Needs review says **Trigger not supported** instead of pretending
the user omitted a time.

### The structural layer

`ClauseStructure.swift` holds the linguistic reading the rest of the pipeline
asks questions of. It exists because the same question kept being answered by a
different local rule each time.

`SentenceContext` tags a whole clause once with `NLTagger` and keeps the token
spans, so a rule can ask about a *part* of a sentence without re-tagging that
part on its own. That matters because `NLTagger` is contextual and answers
differently about a fragment: "cassava" is a Noun in "buy plantains and cassava"
and a Verb by itself. It never lets `nameType` decide a clause boundary — that
tag only fires on a capitalized token, and a reading that turns on it is a
reading the speaker cannot control.

`ClauseScope` finds one boundary: where the matrix speech act ends and a
reported or quoted proposition begins. It distinguishes reporting ("Sarah
said…"), communicating ("text Mike that…") and reminding, recovers the speaker
and recipient when structure gives them, and reads the actor — deliberately
including `unresolved`, because inventing one puts a task on Today that nobody
agreed to do. It is not a dependency parser and not recursive.

`TemporalCommitment` answers whether a stated day was settled on. Two candidate
days, a hedge with nobody behind it, or a question all mean the resolver's
instant is not a plan.

`SemanticState` records how settled a reading is — `resolved`,
`underspecified`, `contested`, `unsupported` — with a named `SemanticGap` rather
than a numeric confidence. A person can be shown a reason; nobody can be shown a
0.62. Actionability stays asymmetric: anything short of `resolved` may still
produce a row and may not produce an alarm.

`TranscriptProvenance` keeps what was said beside what was read. The repair
chain runs before understanding, which is the right order, but `sourceQuote` is
cut from the repaired text — so every row also carries `rawQuote`, the span of
the original transcript it came from, and `wasRepaired`. `ContentDriftTests`
asserts across the whole corpus that no quote holds a word the person never
said unless a repair is recorded in its span. Titles are exempt and reported
separately, because the contract has them paraphrase.

Explicit references to the state or retention of an earlier output resolve after its details and Memory context have been consolidated. Ordinals count accessible intention roots, excluding date instructions and source explanations. Unresolved or contradictory references remain reviewable; an undated-state assertion never erases a date. Recording narration uses the same structural cues for source roles and written boundaries, with quote and independent-commitment guards.

One `CaptureSession` always keeps the complete untouched transcript. Extraction
has no fixed row cap; independent intentions can become independently accessible
linked `CapturedItem` records. Rules run on every supported iPhone. An
occurrence-based ledger audits ownership of words in the repaired creation text
after row shaping and holds unowned words in Needs Review. This ledger does not
yet prove coverage of words removed by repair or partitioned into operations.

Without a runtime-bank configuration, the older optional Foundation Models
refinement adjudicates one unresolved intention and cannot re-segment a
multi-row capture. Its accepted quote must match the rules row's raw quote,
and deterministic code still controls dates and reminders.

The Build 21 personal trial additionally configures `RuntimeExampleInterpreter`
with the pinned development bank. Current-source certificates may accept a
complete reading before retrieval. Otherwise local reference interpretation,
and whole-capture Foundation Models generation when the device/OS/locale
supports it, propose a complete plan under the existing source, coverage,
ownership, correction and saved-state validators. Proposed bank records remain
unapproved. Retrieval is guidance, never current-source truth or permission to
mutate a saved item. Failed generation/validation remains visible as recoverable
review or the established guarded fallback; unsupported devices retain the
local interpreter/rules path. Generation has an unchanged outer twenty-second
budget and reference selection an eight-second budget.

The retrieval candidate provides separately pinned compact lexical and semantic
routing assets over 1,696 real examples spanning all 212 bank blueprints. These
assets select IDs whose complete payloads are loaded from the 510,000-record
bank; they do not search all 510,000 wordings on every capture. Invalid assets
or empty compact results preserve full-bank lexical fallback within the same
selection deadline. New routing remains disabled in the bundled configuration
until qualification chooses its final state. Reference prewarm uses the owning
background actor even when Foundation Models are unavailable. NaturalLanguage
encoder access stays serial, and semantic limits never shorten the original
capture or the source supplied to interpretation.

## Referral boundary

The core product does not depend on Speak It servers. When the production
referral URL is configured, the app keeps a random UUID and credential in
Keychain and uses the UUID as StoreKit's `appAccountToken`. Only that identifier,
referral codes, and App Store-signed transaction data cross the boundary. The
backend verifies Apple's JWS, prevents self-referral and replay, and records a
minimal referral/reward ledger. It never receives thoughts, audio, tasks,
memories, profile fields, contacts, places, or analytics events.

```text
Keychain UUID + credential
    ↓ accept/share invite
ReferralService ledger
    ↓ redeem Apple offer code
StoreKit signed transaction JWS
    ↓ verify with Apple root certificates
Qualified referral → one reward
    ↓
Apple one-time offer code or signed promotional offer
```

The Release configuration keeps the referral API URL empty by default. This is
a truthfulness gate: reward language is not visible unless a deployment is
explicitly connected.

## Boundaries

- `Models`: stored entities and raw-value domain enums
- `Repositories`: validation, write operations, transactions, and persistence errors
- `Features`: screen-specific presentation and interaction
- `Intents`: system-visible actions and Siri/App Shortcut phrases
- `Components`: reusable rows, empty states, and error presentation
- `Preview Content`: isolated in-memory sample environment
- `SpeakItTests`: repository contract and persistence behaviour

## Failure strategy

- Validate before insertion.
- Insert and commit the raw capture plus placeholder before organization work.
- Replace the placeholder with all extracted children in one second transaction.
- Roll back failed writes and surface a user-readable error.
- Do not clear capture text unless persistence succeeds.
- Queue interrupted drafts so a later Back Tap cannot overwrite an earlier capture.
- Retry recognition from protected temporary audio after a live-recognizer failure; never discard it unless persistence succeeds or the person explicitly deletes it.
- Voice transcription is not reported as saved until the repository save succeeds.
- Never execute destructive, negated, hypothetical, or reported instructions; retain them as reviewable items.

## September 2026 interpretation and sync update

Mixed captures persist independent creations before applying an operation to an existing item. Operation cleanup preserves those item IDs, and unresolved operations receive a separate review row. Free-capture accounting includes newly created items even when an operation also succeeds.

Optional FoundationModels refinement runs only for short, review-worthy, supported readings. Clear lists stay on rules. A two-second cancellation race prefers the rules fallback; cancellation remains cooperative with Apple's runtime. Accepted refinements retain independent actions, quote substance and resolved behavioral metadata. Deterministic organization supplies type, person and semantic state.

The iCloud library payload is version 3 (separate from the SwiftData schema). Its optional portable-semantics envelope carries temporal and location intent, semantic state/gap and shopping group. An absent envelope is an older writer with no opinion; a present envelope can explicitly clear fields. The item's modification timestamp governs the envelope, and newer legacy edits preserve the available envelope. Device permissions and Home/Work configuration remain local.

## 2026-10-03 isolated runtime example candidate

The isolated candidate adds runtime example assistance in `ThoughtExtractionEngine`, called by the actual async `SwiftDataThoughtRepository` capture path after the immutable raw parent has been persisted. It snapshots current saved items with full identity/version/field state and saved-place availability. It retrieves complementary whole worked examples, passes them to the supported local interpreter, then validates complete current-source meaning and proposed saved effects before existing durable replacement, review and reminder behavior. Rejected generated proposals retain the complete transcript as visible review. Persistent model shapes and migrations are unchanged.

Both Debug and Release in this isolated candidate define `SPEAKIT_RUNTIME_CANDIDATE` and bundle the exact reviewed SQLite selection and approval manifest. The current selection is 59 independently AI-reviewed records covering 49 of 212 source blueprints; this is neither human approval nor approval of the complete bank or feature. Main is not modified by this candidate. Explicit Debug configurations support retrieval OFF, manual diagnostic selection and full-bank proposed experimental retrieval. Proposed records require `SPEAKIT_RUNTIME_ALLOW_PROPOSED=1`; production configurations reject them and validate the asset checksum and each record's exact approval. See the coverage manifest for retained and unavailable patterns.

The complete 510,000-record library and its verified 1,371,029,504-byte SQLite index remain usable in isolated experimental retrieval. Measurements justified keeping this full development index outside the mobile bundle. The approved mobile database is 352,256 bytes. SQLite selection does not decode the entire source bank into memory; bounded JSON remains an optional development format. Host measurements, including index verification/load and warm selection, are recorded in `RuntimeEvidence/` and do not establish physical iPhone performance.

Apple Foundation Models interpretation requires the available supported model and locale on iOS 26.4 or newer. The existing source-grounded local interpreter runs on iOS 17 and newer and consumes approved examples as validated abstract constraints for supported purposes, allocations, recipient roles, question preservation and atomic saved revisions. Every current name, quantity, owner, date, place and saved identifier comes from the actual input/context. Complete capability equivalence on older supported devices remains unqualified. Literal family-call tasks preserve the relationship without requiring a contact lookup. Their protected source path is not counted as retrieval benefit.

Examples are considered for complex/confident readings too. Retrieval and model prompting have bounded budgets; examples are discarded before current input is truncated. Current-source occurrence coverage, role/purpose/quantity/correction checks and actual saved snapshot checks govern acceptance. Saved revisions retain the complete pending proposal and independent creations, and execute through repository atomic validation and existing user target review. Unsupported or ambiguous effects remain reviewable. Current withdrawal handling preserves the withdrawn words in Memory and does not create the cancelled task.

The Source11 candidate integrates the C11 source certificate after 14 focused checks, including actual durable save/retry/reopen, and independent guard review. Its prototype and failed falsifiers remain isolated under `RuntimeEvidence/Continuation20261003`. It validates bounded complete source discourse independently of the rules producer using immutable identity lineage, exact occurrence ownership, independent purpose/role/timing reconstruction and paragraph/quote scope. Source-only acceptance must be reported separately from worked-example consumption.

The candidate is NOT QUALIFIED. Latest locked development evidence is C10-v3: 4/12 complete OFF and 6/12 ON, zero unsafe outcomes in that cohort; two ON gains consumed eligible approved analogy constraints. Historical broader failures remain preserved. Fresh release qualification and current final corpus/full-unit/Release/UI checks, resources on physical hardware, StoreKit and existing device flows remain mandatory. No shipped behavior or launch readiness is asserted here.

## Isolated runtime example candidate (2026-10-06, not release-qualified)

The candidate selects local approved worked references while interpreting every eligible new capture, including confident rule results. The supported on-device interpreter receives the complete current transcript, actual context and fitted reference mechanisms. Compact decisions cover every app-created current source atom; they cannot author another capture’s names, saved IDs or source anchors. Later revisions reconcile the complete current plan before the existing source/state validator and durable ThoughtRepository can replace capture rows. Original transcript, Today/Memory routing, review and reminder behavior remain on their existing paths.

An exact adjacent current role clarification can have one schema-constrained owner only after the app matches the whole current matrix and every repeated role slot. This preserves direct contact versus an embedded relative, and a physical object owner versus recipient. The matrix purpose remains generated, including unresolved review; this constraint supplies no date, reminder, contact identity, saved target or execution permission. Correction/withdrawal wording or unpaired own role wording or a denial in the complete capture disables these local bindings so ordinary nonadjacent correction links remain available. All atoms, literal relationship wording and clocks still pass complete reconciliation and existing source validation. Quotes, mismatched roles and extra-clause forms decline the binding proof.

Source40’s checked-proposal diagnostic injects independently reviewed semantics after generation into validation, synthetic durable saving, cold reopen and shared ItemPresentation. It does not evaluate the model or establish pixels, notification delivery or phone qualification. The full510,000-source library and full index remain available for research; shipping uses only exact independently AI-reviewed eligible records, with no human approval claim. Final software, fresh-query and authorized hardware/account release gates remain required.

Source42's bounded current custody/exclusion statement has its own Memory owner after complete physical-nominal and literal-custodian proof. Its full words remain searchable in Memory; a purchase cannot absorb that independent fact. Correct six-purpose and grouped eight-purpose proposals pass validation and synthetic save/retry/cold reopen/shared presentation. The previously accepted five-purpose proposal is preserved as the demonstrated destination error, not semantic success. Alternative separate purchase rows remain an unqualified shared-source contract limitation; complete shopping groups are supported. None of these diagnostics grades a model, pixels or actual notification delivery.

## Isolated runtime example candidate

Source44's prototype selects worked examples for current captures before reading uncertainty. The current transcript, actual user context and saved-state snapshots remain authoritative. A compact, required ownership decision for every current source atom replaces generated source echoes only when current syntax permits that contract; complete source, cross-unit links, corrections and the existing semantic/state validator remain required. Closed capture-position prefixes and a proved single conditional matrix action no longer masquerade as extra predicates. Alternative or additional actions retain the expressive contract.

Per-call diagnostics read the supported model's own context capacity and independently tokenize instructions, schema, source, actual user context, prompt and output; component counts are nonadditive. Reference selection, fitting and returned-response conditioning are distinct stages. A returned response is not proof of causal reference use or correctness. Independently checked proposals injected after generation test the actual validation, synthetic durable saving, retry, cold reopening and presentation path separately from model evaluation.

Complete current purchase partitions preserve every quantity, package member and shared exclusion. A current own-voice withdrawal cannot remain in a detached review row beside an active purchase, regardless of its proposed purpose tag. Ordinary unrelated actions and quoted context keep their existing guards. Source44 remains an unpromoted candidate with release, full-suite, fresh held-out and device/account qualification outstanding.

Source45 measures a second compact representation: an exact-length ordered array of the same current ownership decisions. The slot-to-current-atom map is supplied by the app, and all forced purposes, role links, full membership, cycles, orphan links and independent facts still pass the unchanged complete ownership decoder before the existing source/state validator. Generic link choices occur once in the guided array schema; current-proof annotations include only forced slot constraints. This addresses the measured per-call Source44 schema expansion (1,288 tokens for BE01), not a proven semantic gain. Original keyed-schema tests and all failed versions remain preserved.

Source46 is an unpromoted repair of Source45's measured array transport regressions. It restores Source44's exact keyed string contract for at most five ownership atoms. Larger graphs keep every current key and use bounded scalar integer guides: 0–7 are the existing purposes, 8+i is continuation to actual atom i, and 8+N+i is withdrawal/correction to i. Forced current proofs have singleton bounds; bound parents retain canonical-only choices. Integers decode to the identical full keyed proof decoder and final source/state validation. No atom, relationship, list member, condition or correction is removed. The five-atom boundary isolates the exposed small-contract regressions; it is a prototype comparison choice, not a shipping or release threshold. Actual per-call costs and same-cohort correctness remain unmeasured until the next sealed comparison.

Source112 is an unpromoted invocation-local preparation repair. Each bounded part may reuse its own materialized preflight request only when complete current source/context, instructions, grouping data, public schema bytes, schema cost, output reserve, own current model capacity, and ordered admitted reference bytes match exactly. Changed common references trigger ordinary fitting. No receipt crosses parts or captures. Actual per-call component accounting still uses the call model, and cancellation checks and the outer 20-second deadline remain. Preparation timings distinguish fresh fitting from exact reuse; saved semantics and whole-graph validation are unchanged. Semantic benefit remains unmeasured.

Source113 is an unpromoted compact transport of the existing expressive outline. Each row carries the same purpose, rewrite flag, review flag and ordered exact current evidence IDs. Shared source remains representable and must still receive complete disjoint literal anchors/reconciliation before validation and effects; fixed-owner eligibility is not widened. Special joint-call decisions retain their prior expressive schema. The source/context remains complete, no title/fact fields enter the first response, and complete membership and all old semantic/state guards remain. The response reserve keeps the previous768 minimum; lower per-row encoding overhead is measured, not proof of correctness. Admission identity now compares UTF8 bytes, and every staged SDK entry rechecks cancellation after awaited accounting.
