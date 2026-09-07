# Speak It documentation

Design, decision, and QA documents for the Speak It iPhone app. Code-level
guidance for automated agents lives in the root `CLAUDE.md`; this folder is the
long-form record behind it.

Documents marked **historical** record a state that has since been superseded.
They are kept because later decisions cite them, not because they still describe
the app.

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

## The understanding pipeline

| Document | What it is |
| --- | --- |
| [AMBIGUITY_TAXONOMY.md](AMBIGUITY_TAXONOMY.md) | The semantic architecture specification: each family of ambiguity English forces |
| [CLASSIFICATION_DATASET.md](CLASSIFICATION_DATASET.md) | The deterministic extraction and classification suite |
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

The repository-level release process (build numbers, tags, TestFlight) is in
[../CONTRIBUTING.md](../CONTRIBUTING.md), and shipped changes are summarised in
[../CHANGELOG.md](../CHANGELOG.md).
