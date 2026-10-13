# September 27 exposed-set development rescore

**Status: V1 blocked.** This is a measurement on the now-exposed 240-case gate after development changes. It is not fresh qualification evidence and must never be presented as launch proof. The exact candidate scored is recorded in `Tools/UnderstandingLab/Development/long_capture_fresh_240_2026-09-27/long_capture_postgate_candidate_manifest_2026-09-27.json`. The production repository path was run with a fresh in-memory store for each capture. The output trace SHA-256 is `8ddab9d9d7ace68fc8d8e42ab92b695b22e86f2ac92c5eaedfd591bbc71e3b1b`.

| Family | Whole correct | Safe incomplete | Unsafe or silent incomplete |
| --- | ---: | ---: | ---: |
| Clear long multi-task | 0/20 | 0/20 | 20/20 |
| Natural rambling | 0/20 | 0/20 | 20/20 |
| Coherent long Memory | 4/20 | 1/20 | 15/20 |
| Mixed Today and Memory | 0/20 | 0/20 | 20/20 |
| Corrections | 0/20 | 0/20 | 20/20 |
| Withdrawals | 0/20 | 0/20 | 20/20 |
| Quote/report | 0/20 | 1/20 | 19/20 |
| Alternatives resolved later | 0/20 | 0/20 | 20/20 |
| Shared context | 0/20 | 2/20 | 18/20 |
| Multiple dates/people | 0/20 | 0/20 | 20/20 |
| Capacity | 8/20 | 1/20 | 11/20 |
| Beginning/middle/end retention | 0/20 | 0/20 | 20/20 |
| **Total** | **12/240 (5%)** | **5/240 (2.1%)** | **223/240 (92.9%)** |

The four independent batch score files are beside the trace; SHA-256 values are `4992d93c2a1b3431d8ef27a3948feeb02ff513dad42bf557c9019d2539ca7c5d`, `e5d40115b3c6030f2b7bbd08c6d49acf08ddaba40fa6f0b29c01cedad4f605d8`, `523c314a882a91fe1aa973d8d43a6bf29a7a8263b4e5f361ff777f92a13d531a`, and `808ae1227cfd1626280f26a9dd1913215d812b851fb6865e69cb5f4dbd1c5a4b` for batches 1–4 respectively.

## What the score says

The dominant representation failure is **source ownership before row projection**. Adjacent action, explanation, quoted report, time, correction, and choice clauses frequently become independent executable rows before their semantic owner is fixed. That produces both extra intentions and lost or wrongly routed intended meaning. The tags across batches are not a common taxonomy, so their raw counts should not be summed; examples show the pattern in every family. A correction can withdraw an action yet leave that action as a Today row. Reported speech can become the user's task. Dates can attach to neighboring actions. Long memories can fragment into action rows. This needs a general occurrence-level disposition and ownership invariant, not a patch for a gate sentence.

Capacity now preserves the **number** of expected rows in all 20 capacity captures (400 expected, 400 observed), but only 8 whole captures are correct. Row count therefore does not establish semantic completeness. Several failures assign a date to a hyphenated modifier such as “first-aid”; a general lexical boundary fix was made *after* this trace. Its effect is not included in this score.

The prior fresh gate was 3/240 correct, 2/240 safe incomplete, and 235/240 unsafe/silent. The change to 12/240 on the exposed development set is useful diagnostic evidence, but cannot support release. No new unseen text set or physical microphone qualification has been run on the later code. The locked criteria in `LONG_CAPTURE_RELEASE_CRITERIA.md` remain unchanged.

## Next mechanism boundary

Before segmentation or action interpretation, each meaningful source occurrence needs a disposition: own-voice committed intention, context owned by an intention, Memory knowledge, quoted/reported content with an external speaker, correction/withdrawal/replacement of a stable intention, resolved alternative, or genuine review. Every occurrence must either project into the right row, attach to an identified owner, or remain visibly reviewable. An occurrence may not silently disappear, and a quoted or withdrawn occurrence may not become an executable action. This is the smallest shared root indicated by the failures; it does not require reopening broad semantic-map research or an unguided Foundation Models segmentation experiment.

After that invariant is implemented and frozen, commission a **new independently authored unseen** set, score whole-capture correctness by family, then run the authorized physical microphone matrix. The present score blocks V1 regardless of green short-capture tests or release compilation.
