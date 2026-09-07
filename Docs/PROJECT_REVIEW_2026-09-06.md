# Speak It repository and product review — September 6, 2026

The highest-value work is preserving every intended action, carrying its meaning across devices, and making corrections effortless. Keep the local-first architecture and Today/Memory distinction. Improve the boundaries between interpretation stages before adding another model or redesigning the whole interface.

> This is the original review, preserved as a baseline. Implementation and current verification are recorded in [PRODUCT_IMPROVEMENTS_2026-09-07.md](PRODUCT_IMPROVEMENTS_2026-09-07.md).

## Scope and evidence

Reviewed the iPhone capture, extraction, consolidation, repository, synchronization, Today, Memory, and row-presentation paths, alongside existing architecture and audit documents. This is a focused core-product review, not a security audit of the referral service or founder dashboard.

Built the repository's host parser probe from current source and replayed 11 synthetic utterances. No Xcode UI, simulator, device, or full test-suite runs. Nine utterances were also measured over five warmed benchmark rounds: approximately **33.1 ms per capture averaged across the batch**. These are Mac rules-path measurements, not iPhone latency or per-capture p95. The probe cannot exercise SwiftData, real model generation, notification delivery, or actual speech recognition.

Existing user changes were left intact. No application source was changed.

## Findings, in priority order

### 1. P1 — Successful operations skip other tasks in the same capture

**Evidence:** `SwiftDataThoughtRepository.swift:989–1018`, `:1152`. The probe reads both “Cancel the dentist reminder and buy milk” and its reversed form as a cancellation plus a shopping item. When an existing dentist reminder matches, `applyCaptureOperation` performs the cancellation and clears the capture's placeholder. `createCaptureResult` then returns from the operation branch before `organizePersistedCapture` saves the shopping item. Only the `.notFound` branch with extracted items continues into creation.

**Impact:** the user's cancellation succeeds but “Buy milk” never becomes an actionable row. An ambiguous operation likewise prevents independent creations from being saved. The original transcript is preserved; this is loss from the organized result, not deletion of the original words.

**Change:** treat operation results and new items as independent outputs of one capture. Preserve and organize creation items for performed, ambiguous, and unmatched operations; retain unresolved operation evidence separately. Keep operation-side cleanup from deleting creation placeholders or closing the entire capture prematurely. Define partial-failure behavior so retrying cannot perform the same operation twice.

**Verification needed when implementing:** a small repository-level set covering a successful cancellation plus creation, ambiguity plus creation, and a save failure/retry. The parser alone cannot establish persistence correctness. This finding is established by the actual parser output and repository control flow; it was not run against a store during this review.

### 2. P1 — iCloud does not transport the complete meaning of an item

**Evidence:** `ICloudSyncService.swift:3–30`, `SwiftDataThoughtRepository.swift:2161–2181`, `:2226–2258`. The snapshot includes temporal intent but omits location intent and the stored semantic state/gap. The local model explicitly stores all three. Shopping-group metadata is also absent from the library snapshot.

**Impact:** a newly importing device receives a location reminder without its place condition. A review item loses its original reason for being uncertain. Existing items can retain stale local meanings because incoming updates have no fields with which to replace them. Named shopping lists cannot reliably reproduce their grouping on another device.

**Change:** version the sync payload and carry portable semantic meaning, shopping-group records, and their conflict-resolution timestamps. Distinguish an older payload that cannot express a field from an explicit removal in a newer payload. Reconstruct denormalized trigger fields through the existing setters. Keep device permission state local; separately define how Home/Work mappings and frozen “here” coordinates should travel.

**Verification needed:** round-trip location, combined time/place, contested/unsupported semantics, group metadata, explicit clearing, and old-version payloads. These are narrow data-contract checks rather than UI tests.

### 3. P1 — Consolidation can confidently hide independent errands

**Reproduced:**

> I keep meaning to book the dentist and I have to call the bank about the fee and honestly I should just cancel the gym membership

The current rules return one resolved Today row: **Call the bank about the fee**. The complete quote survives, but the dentist and gym actions do not have rows. This is already documented in `KNOWN_ISSUES.md`; the current-source replay confirms it remains present.

`IntentConsolidation.swift:128–174` permits collapsing when its independent substantive-clause reader recognizes at most one intention. That reader does not understand all the obligation forms the other stages recognize. A discourse marker can therefore license discarding meaningful clauses.

**Change:** establish one shared clause interpretation: source span, action predicate, object/person, ownership, negation, modality, and attached time/place spans. Make consolidation consume that evidence instead of another phrase vocabulary. Begin incrementally with shared obligation frames and conservative merging. Merge only when clauses demonstrably describe the same action or supply its reason/context; leave contested spans visible for review.

Also reproduced: “I think I need to sit down and finally do my taxes this weekend” creates a separate **Sit down** task; “I should rarely call Dana about the refund” creates **I should rarely** as a resolved task. Those demonstrate why downstream title cleanup cannot repair upstream segmentation.

### 4. P1 — The AI guard does not establish preservation of actions or routing

**Evidence:** `ThoughtExtractor.swift:119–149`, `:2285–2338`. `preservesEverything` accepts any overlap with one distinguishing token per rules row and skips rows without distinguishing tokens. Validation checks quote grounding but accepts model-selected item kind and person, and uses that kind to retain or remove actionable dates. It also constructs `OrganizedThought` without passing the deterministic semantic state, whose initializer defaults to resolved.

**Constructed counterexample, not an observed model response:** for rules rows “Call Mom tomorrow” and “email Alex Friday”, model quotes “tomorrow” and “Friday” satisfy the token-preservation condition while omitting both actions. If classified as notes, they can also lose their actionable dates. Exact words alone do not prove preservation of meaning.

**Change:** require each independent action and its essential arguments, polarity, ownership, and attached constraints to remain represented. Use explicit source spans and conservative alignment; overlapping full-capture quotes should not count as proof. Carry the deterministic semantic verdict through refinement. Treat routing or reminder changes as higher-risk proposals than title/category improvements, and fall back when the validation cannot establish equivalence.

The current implementation already uses `SystemLanguageModel.default` and greedy sampling. Recommendations in the older AI-feasibility document to switch those settings are stale and should not become new work.

## Performance: target waiting and repeated work

**Narrow model invocation.** `shouldRefine` runs for every multi-item capture and common tokens such as “and” and commas (`ThoughtExtractor.swift:2221`). Thus clear lists can pay model latency. The final organized result awaits the model (`SwiftDataThoughtRepository.swift:969`), although the raw capture is already persisted first. There is no explicit application-level refinement deadline in this path.

Gate refinement on concrete unresolved segmentation or semantic disagreement, with reason codes. Give optional refinement a cancellation-aware time budget and safely retain the rules result when it expires. Avoid publishing actionable provisional rows that silently reorganize after the user interacts with them.

Apple documents session prewarming and recommends doing it when at least a second exists before response generation. Capture may provide that window, but only keep a warmed session when its likely use justifies memory/energy cost. This is a candidate optimization, not a measured speedup here. [Apple: prewarm](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm(promptprefix:)).

**Compute screen sections once per relevant change.** Today repeatedly filters/sorts `allItems` and reconstructs shopping summaries; Memory repeatedly filters, matches and sorts from broad queries (`TodayView.swift:235–369`, `LibraryView.swift:596–629`). A computed property is not a memoized value. Build one projection keyed by item changes, the relevant clock boundary, and device authorization/metadata changes. Preserve the existing routing authority rather than copying its rules into multiple predicates.

**Reduce save-side fan-out.** Every `persistChanges` publishes a widget snapshot. That fetches candidates, filters/sorts them all, then keeps eight (`SwiftDataThoughtRepository.swift:602–625`, `:2100–2102`). Coalesce redundant publication and use a single-pass top-eight selection with a separate exact count where needed. For collection screens, narrow fetches and paginate where supported; applying a fetch limit before semantic filtering could incorrectly exclude eligible items. [Apple: fetchLimit](https://developer.apple.com/documentation/swiftdata/fetchdescriptor/fetchlimit).

**Align latency targets with endpoint policy.** The source currently waits **1,900 ms** for apparently complete speech, then 4/8 seconds for uncertain/incomplete endings (`SpeechTranscriber.swift:136–139`). The architecture document still says 1.1 seconds, while the performance document targets under one second from last voice activity to organized output. Those targets cannot describe the ordinary automatic-stop path as currently implemented. Separate manual-stop and automatic-stop budgets; measure cutoffs as well as delay before shortening the pause. A visible, accessible “Done” affordance is worth a usability experiment.

## Product and visual improvements

1. **Make review a specific repair action.** Today already explains the missing information, but every review row opens the general editor (`TodayView.swift:903`). Route “Which person?”, “Set Home”, and “Choose time or place” directly to the relevant control, retaining access to the original quote and full editor. This reduces work while preserving uncertainty honestly.
2. **Keep the calm design; improve hierarchy.** The shared row already has semantic colors, scaled badges, accessibility labels, and 44-point completion controls. Prioritize the title and meaningful time/place condition, then suppress redundant type/category metadata where the section already communicates it. The fixed two-line title limit deserves a Dynamic Type-aware policy (`CapturedItemRow.swift:95`). These are code-informed design proposals, not visually verified defects.
3. **Make Memory forgiving before making it conversational.** Search currently requires every query token to occur literally in a field, and relevance is pin/priority/recency rather than query relevance (`LibraryView.swift:230–264`). First add exact-name/title weighting, normalized aliases and indexed lexical search. Then experiment with locally computed sentence embeddings as a secondary retrieval channel. Apple explicitly documents embeddings for text retrieval and paraphrase similarity. Keep exact matches prominent, combine rankings, and show the supporting original excerpt. Cache vectors per item revision and check language availability. [Apple: text similarity](https://developer.apple.com/documentation/naturallanguage/finding-similarities-between-pieces-of-text).
4. **Learn explicit corrections locally.** Speech vocabulary already learns names and user-provided corrections. Extend that principle carefully to confirmed person aliases and preferred destinations. Do not treat every generated title or inferred classification as training truth; doing so could reinforce the app's mistakes.

## Recommended sequence

| Order | Deliverable | Why |
| --- | --- | --- |
| 1 | Preserve creation items alongside operations; complete the sync contract | Prevent lost actions and cross-device semantic drift |
| 2 | Shared clause evidence, conservative consolidation, stronger refinement validation | Improve what the app understands without uncontrolled rule expansion |
| 3 | Narrow refinement, align latency metrics, compute projections once | Reduce waiting and repeated work with measurable boundaries |
| 4 | Targeted review controls and better lexical Memory ranking | Improve daily usefulness and reduce correction effort |
| 5 | Optional semantic retrieval and local personalization experiments | Add capability after correctness and baseline retrieval are sound |

Use the existing lightweight corpus/probe for language changes, adding cases from these failures and keeping a separate holdout of natural paraphrases. Use narrowly targeted repository checks for the persistence and sync fixes. Reserve real-device work for the questions this review cannot answer: model quality/latency, endpoint cutoff rate, and hardware behavior. No broad UI-test campaign is needed to begin this work.
