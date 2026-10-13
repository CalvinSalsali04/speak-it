# Fresh long-capture qualification — failed, now development evidence

Date: 2026-09-27. **V1 long-capture release is blocked.** The criteria in
`LONG_CAPTURE_RELEASE_CRITERIA.md` were locked before any of these cases were
run. An independent author wrote the 240 cases and sealed expected meanings;
an independent editor approved each of four 60-case batches before candidate
output was inspected. The app then ran all 240 inputs through
`SwiftDataThoughtRepository.createCaptureResult` on an iOS 26.5 simulator,
with a fresh in-memory SwiftData store per case. Three independent scorers
compared whole captured meaning against the sealed answers. The original
transcript remained present in every session, but transcript retention alone
does not make an incorrect, unreviewed interpretation safe.

The candidate was the dirty working tree frozen by
`/private/tmp/long_capture_candidate_freeze_2026-09-27.json` (app-source
manifest SHA-256 `740eed5a468cd0621adf5b2ccfcecbe988e98e7f4d52cabb2db137d2f84096c1`).
No app source changed between that manifest and the qualification run. The
combined input SHA-256 was
`b9ec1406ae302ab3e8aeafaa15cff4034137aac18b63661627d83990a216cb50`;
the trace records that same fixture hash and 240 cases. Trace SHA-256:
`5af50fd1ad3f96ce285af5ff2382a0b41b815d891951a57654e79b5e0db51169`.
The sealed answers were kept outside the test fixture. All files are under
`/private/tmp/long_capture_release_fresh_240_*_2026-09-27.json`; the four
case-level score files are under `/private/tmp/long_capture_release_score_batch[1-4]_2026-09-27.json`.
SHA-identical durable copies of the freeze manifest, input, sealed answers,
trace, and four score files are in
`Tools/UnderstandingLab/Development/long_capture_fresh_240_2026-09-27/`.
They are regression material for future candidates, not an unseen holdout.

## Whole-capture results

| Family | Correct | Safe incomplete | Unsafe or silently incomplete |
|---|---:|---:|---:|
| Clear long multi-task | 0/20 | 0/20 | 20/20 |
| Natural rambling | 0/20 | 0/20 | 20/20 |
| Coherent long Memory | 0/20 | 0/20 | 20/20 |
| Mixed Today + Memory | 0/20 | 0/20 | 20/20 |
| Corrections | 0/20 | 0/20 | 20/20 |
| Withdrawals | 0/20 | 0/20 | 20/20 |
| Quoted/reported speech | 0/20 | 0/20 | 20/20 |
| Alternatives resolved later | 2/20 | 0/20 | 18/20 |
| Shared context | 0/20 | 2/20 | 18/20 |
| Multiple dates and people | 0/20 | 0/20 | 20/20 |
| Capacity, 10–30 intentions | 0/20 | 0/20 | 20/20 |
| Beginning/middle/end retention | 1/20 | 0/20 | 19/20 |
| **Total** | **3/240 (1.25%)** | **2/240 (0.83%)** | **235/240 (97.92%)** |

These are strict whole-capture verdicts, not percentages of correctly created
rows. A capture with one missing action, wrong owner, invented action, wrong
route, or unreviewed under-split list is incorrect. This gate is far below every
locked family threshold and the 95% overall threshold. It also contains
zero-tolerance failures, so an aggregate score alone would not rescue it.

## Systemic failures observed

- **Silent capacity collapse:** one clear 30-intention list yielded four
  unreviewed rows. Other clear lists yielded only 2–6 rows from 10–30 intended
  jobs. Digits dictated as `1 task; 2 task` were not treated as list boundaries;
  other numbered lists lost distinct neighbouring intentions. There is no
  acceptable visible tail fallback in these cases.
- **Context promoted into rows:** a clear nine-action studio capture produced
  21 rows, including wet-patch observations and explanatory statements, while
  the key handoff was filed as Memory. An explicit one-thought historical
  Memory produced 33 rows, some read as executable actions.
- **Ownership and state:** all 20 correction captures retained stale seeded
  actions. Sixteen of 20 withdrawal captures requested a mutation but produced
  no operation. No destructive operation was observed targeting the wrong seed,
  which is a narrower positive finding and does not make the whole captures
  correct.
- **Quote/report safety:** quoted or reported commands were promoted into Today
  in multiple captures. Another case produced an actionable recording share
  without keeping its required phone-number removal on that action row.
- **Review is insufficient:** some cases contained Needs Review rows, but those
  rows did not cover all missing meaning; a generic “Review captured thought”
  title does not expose the missing intention to the user.

## Verification boundary and next decision

Before the gate, the candidate passed the 1,403-case corpus gate, the complete
sharded iOS unit suite with zero failing assertions, the focused onboarding UI
flow, and the unsigned Release compile. The first simulator invocation skipped
the sealed corpus because Xcode did not forward a shell environment variable;
after setting the simulator launch environment, the actual 240-case run
completed and its trace hash matched the frozen input. The simulator variables
were cleared afterward. These checks establish compilation and existing
regression health, not long-capture release readiness. The trace does not
expose whether Foundation Models refinement ran; live microphone/ASR/device
quality remains untested and must not be inferred from text input.

This fresh set became **development/regression evidence** as soon as the first
post-gate source change was made. The next cycle must implement general
invariants for source-to-intention coverage, stable identity and list
boundaries, context ownership, and operation/quote safety. It must add
opposite-direction controls and preserve short captures. After those mechanisms
freeze and pass app checks, a **different independently authored unseen set**
must be sealed and scored against the new candidate. The current 240 cases
cannot be reused to claim launch readiness. Physical microphone qualification
on an authorized iPhone remains a separate required gate.
