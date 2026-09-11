# Speak It documentation

Design, decision, and QA documents for the Speak It iPhone app. Code-level
guidance for automated agents lives in the root `CLAUDE.md`; this folder is the
long-form record behind it.

Documents marked **historical** record a state that has since been superseded.
They are kept because later decisions cite them, not because they still describe
the app.

Latest continuation review: [September 9 findings and verification](CONTINUATION_REVIEW_2026-09-09.md).

## Product

| Document | What it is |
| --- | --- |
| [PRODUCT_REQUIREMENTS.md](PRODUCT_REQUIREMENTS.md) | Phase 1 objective and scope |
| [CORE_PRODUCT_PROPOSAL.md](CORE_PRODUCT_PROPOSAL.md) | The original product proposal |
| [USER_FLOWS.md](USER_FLOWS.md) | First launch, capture, Today, and Memory flows |
| [SCREEN_SPECIFICATIONS.md](SCREEN_SPECIFICATIONS.md) | Per-screen specification |
| [DATA_MODEL.md](DATA_MODEL.md) | `CaptureSession`, `CapturedItem`, and their relationships |

## Architecture and decisions

| Document | What it is |
| --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Platform, layers, persistence, speech, and the understanding pipeline |
| [DECISIONS.md](DECISIONS.md) | Dated decision log. Add an entry whenever behaviour, limits, or pricing change |
| [KNOWN_ISSUES.md](KNOWN_ISSUES.md) | Limitations that ship, with the reasoning |
| [BACKLOG.md](BACKLOG.md) | Done / Next / Later |
| [VOICE_ENDPOINTING_DECISION.md](VOICE_ENDPOINTING_DECISION.md) | Adaptive endpointing: why a finished sentence gets 1.9 seconds |
| [PERFORMANCE_BENCHMARKING.md](PERFORMANCE_BENCHMARKING.md) | Capture performance targets and measurements |
| [PRICING_AND_CONVERSION_2026-09-07.md](PRICING_AND_CONVERSION_2026-09-07.md) | Why weekly billing was rejected, how the price ladder is set, and where the funnel leaks |
| [GAMIFICATION_PROPOSAL.md](GAMIFICATION_PROPOSAL.md) | Proposal: a calm habit loop (week row, morning brief, milestones) and why Duolingo's streak is refused |

## The understanding pipeline

| Document | What it is |
| --- | --- |
| [AMBIGUITY_TAXONOMY.md](AMBIGUITY_TAXONOMY.md) | The semantic architecture specification: each family of ambiguity English forces |
| [CLASSIFICATION_DATASET.md](CLASSIFICATION_DATASET.md) | The deterministic extraction and classification suite |
| [PUBLIC_DATASETS.md](PUBLIC_DATASETS.md) | Licence and relevance survey of public speech corpora, and the rule that we import language but never answers |
| [LANGUAGE_BASELINE.md](LANGUAGE_BASELINE.md) | The measured numbers a language change is judged against, and where the room actually is |
| [SEGMENTATION_ARCHITECTURE.md](SEGMENTATION_ARCHITECTURE.md) | Why clause splitting cannot find a boundary between two statements, and the two signals the app already has and discards |
| [SEMANTIC_CORPUS_EXPANSION.md](SEMANTIC_CORPUS_EXPANSION.md) | The corpus growing from 182 to 439 cases and the hardening it forced |
| [SEMANTIC_CORPUS_FINDINGS.md](SEMANTIC_CORPUS_FINDINGS.md) | **Historical.** The 182-case release gate |
| [PIPELINE_SWEEP_FINDINGS.md](PIPELINE_SWEEP_FINDINGS.md) | Seven-lane read-only sweep of the pipeline (2026-08-24) |
| [PipelineSweep/](PipelineSweep/) | The per-lane write-ups behind that sweep |

Tooling for this area lives in `Tools/CorpusRunner` and `Tools/PipelineProbe`;
each has its own README.

## Testing and QA

| Document | What it is |
| --- | --- |
| [TEST_CASES.md](TEST_CASES.md) | Automated repository tests and what each protects |
| [CAPTURE_STRESS_TEST_PLAN.md](CAPTURE_STRESS_TEST_PLAN.md) | Release gate for every outside-the-app capture route |
| [DURABILITY_FINDINGS.md](DURABILITY_FINDINGS.md) | The durability destruction pass |
| [LOCATION_DEVICE_QA.md](LOCATION_DEVICE_QA.md) | Physical-iPhone QA for location reminders |
| [BUILD_12_HUMAN_QA.md](BUILD_12_HUMAN_QA.md) | **Historical.** Build 12 human bug hunt |
| [BUILD_13_HUMAN_QA.md](BUILD_13_HUMAN_QA.md) | **Historical.** Build 13 new-user bug hunt |
| [BUILD_14_DEVICE_SMOKE.md](BUILD_14_DEVICE_SMOKE.md) | **Historical.** Build 14 device smoke test |
| [FINAL_RELEASE_AUDIT.md](FINAL_RELEASE_AUDIT.md) | **Historical.** Release-candidate acceptance audit; code comments cite its finding IDs (B-1, F-1, H-1…) |

## Release

| Document | What it is |
| --- | --- |
| [APP_STORE_SUBMISSION.md](APP_STORE_SUBMISSION.md) | The working submission checklist for the first release |
| [APP_STORE_LISTING.md](APP_STORE_LISTING.md) | Store listing copy with character counts: name, subtitle, description, keywords, plan names, captions |
| [APP_STORE_REVIEW_PACKAGE.md](APP_STORE_REVIEW_PACKAGE.md) | Review Notes, age rating, App Privacy answers, export compliance, DSA, field-by-field App Store Connect checklist |
| [APP_STORE_READINESS_2026-09-09.md](APP_STORE_READINESS_2026-09-09.md) | What the September 9 readiness pass verified, fixed, deferred, and what still needs a human |
| [APP_STORE_PRICING_STATUS_2026-09-09.md](APP_STORE_PRICING_STATUS_2026-09-09.md) | What App Store Connect held for both subscriptions on September 9 |

The repository-level release process (build numbers, tags, TestFlight) is in
[../CONTRIBUTING.md](../CONTRIBUTING.md), and shipped changes are summarised in
[../CHANGELOG.md](../CHANGELOG.md).

- [September 8 pricing and trial decision](PRICING_DECISION_2026-09-08.html) — focused evidence, retained prices and free allowance, promotion requirements.
