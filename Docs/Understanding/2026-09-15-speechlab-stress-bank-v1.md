# SpeechLab Stress Bank v1 — production rules baseline

## Outcome

The supplied bank was structurally valid and all 10,000 utterances were run once,
in order, through the frozen production rules path compiled by `PipelineProbe`.
No parser behavior was changed before or during the run. This is synthetic
failure-discovery evidence, not a Speak It accuracy measurement.

The strongest result is safety scope: **271 cases converted withdrawn,
conditional, selectively cancelled, or negated language into at least one
positive actionable row**. They divide into 126 whole-thought abandonment scope
leaks, 72 detached conditions, 61 selective-cancellation leaks, and 12 synthetic
ASR `not two` negation splits.

The highest-value next target is a single explicit scope model for withdrawal and
selective cancellation across composite captures. The two cancellation clusters
account for 187 of 271 unsafe positives and require opposite but related scope
decisions: withdraw the whole composite when “forget that” refers to it, while
removing only the named item when “skip X” narrows the scope.

## Reproducible identity

| Field | Value |
|---|---|
| Bank | SpeechLab Stress Bank v1 (`SpeechLab-Stress-Bank-v1`) |
| Cases / seed | 10,000 / 5601 |
| ZIP SHA-256 | `86c717bb781e9891a3700f213aa62db2a187295381249f193029908ed683586f` |
| JSONL SHA-256 | `6ea6622a948c4f25a13f61a8ffe023d0c9a4ad761a1f291f5cb77c19c67dc727` |
| Parser Git commit | `2932272b8741901fcb3e3f62e4a6998e7dc07689` |
| Branch | `main` |
| Parser source SHA-256 | `7c90d550d64ce1c2d97553c7bd0fa1e2fd6de028e119a15f037a926945088b84` |
| Frozen probe SHA-256 | `db3be2cfe0144a2fecd6600c681f4fa7225ebb00d064bda8b3e346972964e485` |
| Evaluator | `speechlab-stress-evaluator-1.0.0` |
| Evaluator SHA-256 | `a22b99a9b791954138a0cb692e0c574f8e9718078f2ba29b9601ade33501b2c4` |
| Reference frame | 2026-08-03 10:00 America/Toronto |
| Environment | macOS 26.5.2 arm64; Swift 6.3.3; Python 3.13.1 |

The working tree was already dirty and `main` was 123 commits behind
`origin/main`. The commit alone therefore does not fully identify the parser;
the source-tree and frozen-binary hashes above are authoritative. The baseline
captured those pre-existing working-tree parser changes. No branch, commit, push,
or PR was created.

## Ingestion audit

All checks passed: 10,000 rows; ordered unique IDs `SB10K-00001` through
`SB10K-10000`; 10,000 exact-unique utterances; canonical contract hashes;
expected item counts; phenomenon counts; two consistent root schemas (the second
adds `acceptable_contracts` on 71 ambiguity rows); manifest counts; coverage CSV
counts; the 200-row sample; 187 semantic families; 219 structures; 81 phenomena;
1,488 safety-critical rows; and 170 `requires_review` rows. The original ZIP and
JSONL were not modified.

## Aggregate comparison

The exact/disagreement denominator excludes the 170 explicitly ambiguous cases.
“Exact” is the evaluator's documented projection from the bank's abstract
contract onto Speak It's native title, analysis, route, person, temporal,
recurrence, semantic-state, and operation fields.

| Measure | Count |
|---|---:|
| Non-ambiguous cases | 9,830 |
| Exact structured agreements | 2,264 |
| Disagreements | 7,566 |
| Synthetic stress-bank disagreement rate | 76.9685% |
| Item-count failures | 6,455 |
| Over-splits | 6,034 |
| Under-splits | 421 |
| Lost-information failures | 421 |
| Invented-information failures | 6,034 |
| Routing failures | 479 |
| Date failures | 2,753 |
| Time failures | 808 |
| Recurrence failures | 114 |
| Person/reference failures | 115 |
| Location/destination association failures | 5,285 |
| Correction failures | 1,742 |
| Abandoned-thought failures | 390 |
| False-start failures | 256 |
| Unfinished-clause failures | 153 |
| Cancellation failures | 239 |
| Selective-cancellation failures | 170 |
| Negation failures | 12 |
| Prohibition polarity failures | 0 |
| Shared-context failures | 2,924 |
| Ordering failures | 9 |
| Trailing-noise artifacts | 979 |
| Unsafe positive actions | **271** |

The very large over-split, invented-information, and destination counts must not
be read at face value as 6,034 independent product bugs. Much of that volume is
one representational disagreement: the bank models “go to Walmart and buy milk”
as one destination-plus-action item, while Speak It often emits a visit row and
a purchase row. Spot checks classify that family as primarily a bank/product
granularity mismatch, with real context-propagation defects mixed into the more
complex variants.

## Ambiguity

Of 170 `requires_review` cases, 57 matched an allowed interpretation, 54 visibly
preserved uncertainty, and 59 neither matched an allowed contract nor retained a
non-resolved/review state. Therefore **111/170 received safe or allowed ambiguity
handling; 59/170 require review as ambiguity-handling mismatches**. These rows are
not included in the naive exact-agreement rate.

Representative contrast:

- `SB10K-07513`, “Maybe the electronics store or the Apple Store Thursday, not
  sure yet,” stayed a Memory/unclear row with `needsReview=true`: legitimate
  uncertainty was preserved.
- `SB10K-07559`, the same unresolved construction with Long Fong Mall or Walmart,
  preserved the words but emitted `state=resolved` and no review flag: likely a
  real semantic-state inconsistency.
- `SB10K-08508`, “Call Avery or Noah about the booking,” kept both alternatives in
  the title. The structured person field selected Avery, so the visible result is
  reasonable but the metadata choice remains arguable.

## Safety-critical cohort

The 1,488 safety-critical cases produced 503 exact/allowed results, 985
disagreements, and 271 unsafe positives. Cohorts overlap because one case may
carry several phenomena.

| Safety phenomenon | Cases | Disagreements | Unsafe positive |
|---|---:|---:|---:|
| Negation | 215 | 25 | 12 |
| Prohibitive reminders | 274 | 140 | 0 |
| “Don’t forget” positive intent | 72 | 6 | 0 |
| Cancellation | 115 | 115 | 0 |
| Full abandonment | 181 | 130 | 126 |
| Partial cancellation | 163 | 133 | 0 |
| Selective cancellation | 216 | 170 | 61 |
| Replacing an action | 73 | 73 | 0 |
| Negative state change | 48 | 48 | 0 |
| Temporal negation | 72 | 7 | 0 |
| Location negation | 73 | 73 | 0 |
| Unresolved alternatives | 71 | 71 | 0 |
| Conditional intent | 145 | 90 | 72 |
| Cancellation scope | 238 | 187 | 126 |

The 115/115 cancellation and 48/48 negative-state disagreements are mostly a
contract representation issue: the bank expects an item such as
`cancel_reminder`, while production correctly emits a native `cancel` operation.
They are not unsafe positives. Likewise, the location-prohibition sample emitted
a cancel operation for the forbidden destination rather than acting on it; its
remaining disagreement was date/context propagation.

## Top 20 root-cause clusters

The automatic clusterer retains full distributions of semantic family,
phenomena, structure ID, item count, length band, safety class, mismatch
dimensions, and likely subsystem in `clusters.json`. This table applies
spot-check judgment so a huge questionable generator pattern does not outrank a
smaller real safety defect.

| # | Cases | Priority | Cluster / likely subsystem | Representative evidence | Disposition |
|---:|---:|:---:|---|---|---|
| 1 | 126 | P0 | Full abandonment leaves earlier action active / safety scope | `SB10K-03011`: retract operation is scoped, but “Go to the hardware store” survives | Real bug, high confidence |
| 2 | 72 | P0 | Condition detached from actionable reminder / clause segmentation | `SB10K-07514`: “If Marco replies” becomes a note; “Buy garbage bags” becomes unconditional | Real bug, high |
| 3 | 61 | P0 | Selective cancellation retains withdrawn item / safety scope | `SB10K-04635`: positive “Go to the florist” survives “skip the florist” | Real bug, high |
| 4 | 12 | P0 | ASR `not two` negation split / repair + segmentation | `SB10K-09748`: “not two” row plus positive “Call Noah” | Real robustness bug; synthetic realism low |
| 5 | 1,645 | P1 | Shared temporal context detached/uneven / segmentation + temporal | `SB10K-04601`: only the first of four produced rows keeps “in three days” | Real bug mixed with granularity mismatch |
| 6 | 1,296 | P3 | Composite errand decomposed into visit + purchase / segmentation | `SB10K-00003`: two correct visible rows where bank insists on one composite | Bank/product contract mismatch, high |
| 7 | 979 | P1 | Trailing conversation becomes an extra row/title / repair | `SB10K-01511`: “that is the only thing” becomes a Memory row | Real bug, high |
| 8 | 550 | P2 | Date/date-correction mismatch / temporal | `SB10K-06472`: corrected “Monday” resolves to the following Monday, while bank leaves the anchor implicit | Mixed; needs contract-by-contract evidence |
| 9 | 496 | P2 | Person/destination/location association / reference parser | `SB10K-00036`: action/date are correct; destination survives only in source quote | Mostly representation gap; some real association loss |
| 10 | 416 | P1 | Corrected destination split from its action / repair + segmentation | `SB10K-03003`: corrected mall and purchase become separate rows with no association | Real bug, high |
| 11 | 266 | P2 | Other over-splitting, chiefly partial cancellation/conditional fallback | `SB10K-03012`: “keep the mall but skip the bottle” is not represented as one retained visit | Mixed |
| 12 | 260 | P2 | False start/unfinished restart creates extra structure / repair | `SB10K-03007`: restart is cleaned, but composite errand still splits | Primarily granularity mismatch in sample |
| 13 | 260 | P1 | Superseded action/object survives correction / repair | `SB10K-03002`: both “Buy shampoo” and corrected “Get cosmetics” survive | Real bug, high |
| 14 | 246 | P1 | Clock, fuzzy-time, or corrected-time mismatch / temporal | `SB10K-03083`: title says 6, resolved due remains the three-day duration without 6 | Real bug, high |
| 15 | 237 | P1 | Pronoun/shared-object chain merged or loses antecedent / references | `SB10K-08502`: “pick up socks” and “return it tomorrow” collapse into one action | Real bug, high |
| 16 | 167 | P3 | Other under-splitting / operations + representation | `SB10K-07503`: native cancel operation disagrees with bank's expected task item | Mostly bank representation mismatch |
| 17 | 129 | P3 | Appointment noun phrase lacks bank's implicit `attend` verb / projection | `SB10K-00012`: correct event, date, time and salon; only inferred action differs | Bank contract issue, high |
| 18 | 114 | P1 | Recurrence missing or bound to wrong clause / recurrence + segmentation | `SB10K-06414`: monthly follow-up becomes weekly Sunday; `SB10K-06420` detaches recurrence from action | Real bug, high |
| 19 | 113 | P2 | Explicit ambiguity handling / semantic state | `SB10K-07559`: alternatives remain visible but state is resolved with no review | Mixed; 59 definite handling mismatches |
| 20 | 109 | P1 | Selective cancellation mismatch without unsafe positive / safety scope | `SB10K-04633`: retained Costco action disappears and only “Skip Long Fong Mall” remains | Real bug, high |

## Coverage leaders

Full counts for all 187 families, 81 phenomena, and 219 structures are in
`summary.json`. The leading failing buckets are shown here.

### Semantic families

| Family | Failing / cases |
|---|---:|
| `wrapper.errand.buy` | 395 / 395 |
| `wrapper.errand.grab` | 358 / 383 |
| `wrapper.errand.get` | 340 / 388 |
| `wrapper.errand.pick_up` | 313 / 334 |
| `clean.errand.buy` | 186 / 186 |
| `clean.errand.get` | 159 / 204 |
| `clean.errand.pick_up` | 148 / 189 |
| `clean.errand.grab` | 147 / 194 |
| `correction.negated_old_date` | 144 / 144 |
| `clean.appointment` | 141 / 141 |

### Phenomena

| Phenomenon | Failing / cases |
|---|---:|
| `multiple_items` | 2,586 / 2,707 |
| `shared_temporal_context` | 2,485 / 2,560 |
| `discourse_wrapper` | 1,982 / 2,111 |
| `correction` | 1,416 / 1,743 |
| `trailing_conversational_noise` | 979 / 1,056 |
| `clean_speech` | 821 / 1,500 |
| `filler` | 771 / 823 |
| `sequencing_language` | 741 / 746 |
| `explicit_date` | 679 / 1,166 |
| `safety_critical` label | 595 / 1,098 |

### Structures

| Structure | Failing / cases |
|---|---:|
| `corr.15` | 144 / 144 |
| `clean.appointment` | 141 / 141 |
| `corr.8` | 139 / 144 |
| `corr.0` | 134 / 145 |
| `corr.10` | 126 / 126 |
| `corr.2` | 124 / 124 |
| `corr.12` | 122 / 122 |
| `corr.1` | 119 / 119 |
| `wrapper.4` | 108 / 108 |
| `corr.6` | 107 / 126 |

## Representative spot-check dispositions

A 31-case judgment sample covered every major root cluster and the highest-risk
subclusters. It is a triage sample, not an extrapolation over all disagreements:

| Disposition | Count |
|---|---:|
| A — likely real Speak It bug | 21 |
| B — likely synthetic-bank/contract issue | 6 |
| C — legitimate ambiguity/reasonable preservation | 3 |
| D — unclear/mixed; needs more evidence | 1 |

The real-bug sample IDs were `SB10K-03011`, `03027`, `07514`, `07529`, `04635`,
`09207`, `09748`, `04601`, `04617`, `01511`, `04667`, `03003`, `03013`, `03002`,
`03004`, `08502`, `06414`, `06420`, `03083`, `07559`, and `04633`. Likely
contract issues were `00003`, `00036`, `00012`, `07503`, `07512`, and `03007`.
Legitimate ambiguity examples were `07513`, `07528`, and `08508`. `00001` was
left unclear because it combines the vague date “next week,” an ambiguous bare
hour, and the bank/product composite-errand disagreement.

## Relationship to existing evidence

Current local evidence on the same working-tree parser:

- CorpusRunner: **1,403/1,403 clean**, zero critical, behavioral, metadata, or
  cosmetic disagreement on its authored product-contract corpus.
- Coordination development set: **115/121** correct, six failures.
- Routing development set: destination **74/84**, count **77/79**, and 3/32
  genuinely ambiguous captures acted on anyway.
- Unfinished development set: recall **34/57**, zero finished-speech fallout,
  and two unsafe fragment actions.
- Explicit-abandonment development set: **24/24** withdrawn, zero fallout and
  zero unsafe, with four documented failures.
- Sealed/held-out aggregate only (no failure contents inspected): destination
  **233/320**, count **255/310**, 7/69 ambiguous captures acted on, zero missing.
- The prior 40 everyday captures were 32/40 after fixes.
- The separate two-million-case synthetic consistency run was 93.3417%
  consistent and 100% title-consistent; it did not measure correctness.

The 10K bank confirms known coordination, routing/destination, unfinished-
thought, ambiguous-action, and messy-speech weaknesses. It also explains why a
green 1,403-case CorpusRunner is insufficient for these combinations.

Genuinely new or materially broadened families are: compound full-abandonment
scope (missed by the 24/24 abandonment dev result), conditional reminder
detachment, long-list selective cancellation, recurrence binding across two
clauses, and the synthetic `not two` polarity split. The huge composite-errand
family is not accepted as a new production defect without first deciding the
product's intended row granularity.

No repository artifact or result manifest named **Trusted Core v1** was present,
so no direct Trusted Core comparison was invented. Its role remains the semantic
anchor exactly as requested. This run did not inspect sealed failure contents.

## Scope and limitations

This baseline covers the production deterministic rules path compiled from the
current `SpeakIt/Repositories` and `SpeakIt/Models` sources. As documented by
`PipelineProbe`, it does not execute optional on-device Foundation Models
refinement, SwiftData target resolution, persistence, notification delivery, or
UI behavior. The frozen output is still the exact path used by CorpusRunner and
the repository's semantic gate.

## Files and reproduction

Integration added:

- `Tools/SpeechLabStressBank/run.py`
- `Tools/SpeechLabStressBank/test_run.py`
- `Tools/SpeechLabStressBank/README.md`
- richer read-only JSON observability in `Tools/PipelineProbe/main.swift`
- this report

One-command future run against the then-current parser:

```bash
python3 Tools/SpeechLabStressBank/run.py \
  --bank /Users/calvinwak/Downloads/speakit_speechlab_10k_bank_v1.zip \
  --output output/speechlab-stress-bank-v1 \
  --build-probe
```

Evaluator-only rescoring without rerunning the bank:

```bash
python3 Tools/SpeechLabStressBank/run.py \
  --bank /Users/calvinwak/Downloads/speakit_speechlab_10k_bank_v1.zip \
  --output output/speechlab-stress-bank-v1 \
  --probe output/speechlab-stress-bank-v1/probe \
  --reuse-actual output/speechlab-stress-bank-v1/actual.jsonl
```

Ignored evidence is under `output/speechlab-stress-bank-v1/`. Important result
hashes: raw actual JSONL
`875a5a51c3d29e72bcfcc58a1c2b32ba2b0f43877112f2f10a5ea56be5609ebf`,
per-case result JSONL
`cfb944f4f2b878eb7fe993d2a24b24a6bda5a726fba8b1c561f3b4badcbba3b1`,
summary `9d8e8b177d4638b2638f869bc38d189d0895692b617c316677ced9e7b960a47c`,
and clusters `106517ba92580772035f2ae56bea218ea6141779a4196e7a00ecf321c6ef1e70`.
`result-manifest.json` records all artifact hashes and sizes.

Branch/commit/PR/push state: `main` at
`2932272b8741901fcb3e3f62e4a6998e7dc07689`; working tree dirty; no new commit;
no push; no PR.
