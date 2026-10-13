# Exposed 1,770-input execution trace — September 28, 2026

The user-supplied synthetic development inputs ran through
`SwiftDataThoughtRepository.createCaptureResult` with isolated in-memory
SwiftData stores. All ten bounded Xcode test batches passed and the merge
verified exact case-ID order against `development_inputs.jsonl`. The first
single-process attempt was interrupted after Xcode waited 2,107 seconds for
a test worker and did not enter the test body. It supplies no case result.
Parallel test workers were disabled for the bounded runs. The simulator's
`en_CA` locale matches all 1,770 fixture contexts; each case supplied its own
reference instant and Toronto time zone. The app's date-only alert default
was recorded as 09:00. Notification scheduling was disabled.

The compressed [raw trace](../../Tools/UnderstandingLab/Development/example_pack_full_2026-09-28/raw_repository_trace.json.gz),
[per-case execution counts](../../Tools/UnderstandingLab/Development/example_pack_full_2026-09-28/execution_counts.json),
and [hash manifest](../../Tools/UnderstandingLab/Development/example_pack_full_2026-09-28/manifest.json)
are exposed development evidence. The raw trace has the immutable original,
seeded before state, persisted after state, Today/Memory route, reminder
fields, and operation outcome. The proposed expected answers never entered
the repository. A passing batch means its raw trace was produced; it is not a
semantic pass, a microphone run, or independent release evidence.

## Execution counts

| Measure | Result |
| --- | ---: |
| Cases / distinct roots / exact aliases | 1,770 / 310 / 14 |
| Exact `CaptureSession.originalTranscription` preservation | 1,770 / 1,770 |
| Newly persisted rows | 27,150 |
| Rows marked needs clarification | 3,242 |
| Captures with at least one review row | 1,311 / 1,770 |
| New Today / Memory rows | 13,019 / 10,889 |
| Seeded-item changes | 5 case renderings, one saved target each |
| Maximum rows from one case | 80 |
| Notification delivery / clarification replies / microphone cases | 0 / 0 / 0 |

The five seeded changes are S062's punctuated, lowercase, linebreak, filler,
and concise renderings. Each completed the intended `saved_poster` target and
left `saved_print` untouched. S062's light-punctuation rendering did not
complete the target; its opposite control correctly made no seeded change.
No changed seeded target was wrong in this run, but many requested mutations
were not performed. These initial-capture results say nothing about reply
idempotency. `CaptureSession` source preservation does not prove every source
clause was correctly owned by a displayed row.

The capacity case S049 kept 30 rows in each of its five main renderings,
including the last obligation. The punctuated pilot still routes “water the
parsley” as Shopping. That is a semantic error even though no row cap lost
the obligation. One composed filler rendering produced 79 rows against 21
proposed items; a separate case reached 80 rows. These are strong
over-splitting signals, not a scored judgment on every composed case.

## Family and rendering coverage

The numbers below are execution counts. **Review captures** counts cases
with at least one saved review row, including reviews that may be unnecessary.
The 25-case source-grounded pilot audit separately reports 2 automatically
correct, 2 safe incomplete, and 21 wrong persisted whole captures on the
final semantic candidate. The rest of this pack was not independently
adjudicated, so no automatic-correctness rate is assigned here.

| Family | Cases | New rows | Review captures |
| --- | ---: | ---: | ---: |
| Beginning, middle, end retention | 35 | 364 | 27 |
| Capacity and numbered lists | 35 | 770 | 7 |
| Clarification dialogues | 35 | 259 | 27 |
| Coherent Memory | 35 | 137 | 10 |
| Commitment versus idea | 35 | 163 | 13 |
| Compositional stress | 1,000 | 22,050 | 913 |
| Conditions and dependencies | 35 | 207 | 22 |
| Current-capture corrections | 35 | 172 | 14 |
| Dictation and incomplete speech | 35 | 207 | 16 |
| Duplicates and restatement | 35 | 172 | 14 |
| Entity and reference ownership | 35 | 211 | 13 |
| Event context | 35 | 163 | 0 |
| Location and permissions | 35 | 130 | 22 |
| Mixed destinations | 35 | 242 | 20 |
| Natural extended | 70 | 707 | 47 |
| Negation scope | 35 | 102 | 26 |
| Quote and report ownership | 35 | 175 | 17 |
| Recurrence and clock edges | 35 | 134 | 22 |
| Saved-item mutations | 35 | 117 | 24 |
| Scattered tasks | 35 | 276 | 19 |
| Time scope | 35 | 193 | 17 |
| Withdrawal scope | 35 | 199 | 21 |

| Rendering | Cases | New rows | Review captures |
| --- | ---: | ---: | ---: |
| Punctuated, including controls | 530 | 6,753 | 312 |
| Lowercase | 310 | 3,457 | 250 |
| Light punctuation loss | 310 | 2,104 | 225 |
| Linebreak fragments | 310 | 6,063 | 261 |
| Spoken fillers | 310 | 8,773 | 263 |

The 1,550 main renderings share 310 roots; 110 concise and 110 opposite
controls add direct synthetic probes. The 1,000 composed cases derive from
seed scenarios. Their rows are correlated, and the 14 marked exact aliases
must be excluded from any later aggregate scoring. The machine-readable
summary records both all cases and non-alias counts by family and rendering.

## Interpretation and limits

The text run exposes large row expansion and high review frequency, especially
for compositions and filler renderings. Those facts agree with the pilot's
observed wrong source ownership; they do not distinguish visible from silent
wrong interpretation in every case. The raw trace also does not exercise a
specific clarification question, local reply, duplicate reply, relaunch,
notification delivery, microphone continuity, audio fidelity, or physical
interruptions. No missing execution is counted as success. The existing
240-case answers and this pack's proposed answer key were not changed.

The next semantic work should use the audited pilot and opposite controls to
repair the first wrong source-owner stage, then rerun this exposed pack as
development feedback. An independently authored audited set after the
candidate freezes, plus actual microphone qualification, remains necessary
before any release claim.
