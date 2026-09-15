# SpeechLab split scoring policy

SpeechLab reports each role separately. There is no overall accuracy number.

| Role | Scoring policy | Visibility |
|---|---|---|
| Development | Field-level diagnostics against visible contracts; failures are inspectable. | Visible |
| Regression | Exact contract and safety-scope checks for independently specified fixed behavior. | Visible |
| Independent evaluation | Exact contract checks plus field-level error categories; membership and labels become sealed only after freeze. | Sealed after freeze |
| Safety | Strict item count, date/time/location, person/reference, negation, prohibition, and cancellation scope; any unsafe branch is a failure. | Separate safety report |
| Public-derived | Contract correctness and provenance reported by source; never blended with authored examples. | Visible until assigned another frozen role |
| Synthetic stress | Robustness and semantic-consistency deltas only; never presented as product accuracy. | Visible |
| Ambiguity/challenge | Set-membership or explicit-review behavior after acceptable outcomes are adjudicated; no single-answer exact-match score. | Visible challenge set |

The current 695-case trust-closure artifact is **not frozen** and therefore has
no independent-evaluation membership. The 13 challenge candidates remain
outside exact-answer scoring, and the two representation-deferred cases remain
outside all scoring.
