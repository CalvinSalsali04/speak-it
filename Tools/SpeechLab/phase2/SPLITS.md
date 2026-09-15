# Evaluation roles and freeze policy

Cases have explicit proposed roles rather than one aggregate score:

| Role | Current cases | Use before adjudication |
|---|---:|---|
| Safety | 489 | Review queue only; not trusted |
| Development | 176 | Visible exploratory cases |
| Synthetic stress | 111 | Mutation/composition robustness, never accuracy |
| Public-derived | 42 | Provenance-preserving review queue |
| Regression | 0 | Created only after a behavior is independently specified and fixed |
| Independent evaluation | 0 | Created only after semantic labels are frozen |

An additional 25 public-derived or synthetic-stress cases are safety-critical,
so the total safety-critical population is 514 even though their primary role
is not `safety`.

`artifacts/split-manifest.json` is intentionally marked `frozen: false`. A future
freeze requires independent review, two independent approvals for every safety
case included, resolution or exclusion of disputes, and a rerun of all quality
gates. Independent-evaluation failures must not subsequently be exposed to
implementation work.
