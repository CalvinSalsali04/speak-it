# Public-data pilot

The pilot contains 42 text-only records selected for linguistic value. Foreign
intent labels are provenance, not Speak It truth; each record has a separately
authored Speak It contract at `machine-reviewed` confidence.

| Source | Records | Frozen source/version | License |
|---|---:|---|---|
| PRESTO | 12 | `presto_v1.zip`; repository `fa47167477453afebe698a287409514df5a7dadf` | CC BY 4.0 |
| MASSIVE | 10 | 1.0; repository `f966f21846043aabef9b0f974fa7970027f43738` | CC BY 4.0 |
| Taskmaster | 10 | TM-1 sample at `d92cb6af3005f1dc09c39e75e7daf4a04905e00b` | CC BY 4.0 |
| SLURP text | 10 | `test.jsonl` at `8eb16545762be97ace75334109d73824217311f1` | Text CC BY 4.0 per MASSIVE NOTICE |

Verified upstream documentation:

- PRESTO describes more than 550,000 contextual multilingual conversations,
  including disfluency and revision partitions, and states CC BY 4.0:
  <https://github.com/google-research-datasets/presto>
- MASSIVE's notice states that MASSIVE and incorporated SLURP text are CC BY
  4.0: <https://github.com/alexa/massive/blob/main/NOTICE.md>
- Taskmaster TM-1 states CC BY 4.0 and documents 13,215 spoken/written dialogs:
  <https://github.com/google-research-datasets/Taskmaster/blob/master/TM-1-2019/README.md>
- The SLURP source repository is preserved at:
  <https://github.com/pswietojanski/slurp>

The exact archive/file SHA-256 values, source record IDs, source annotations,
context, license, and mapping decision are stored per row in
`public/source-records.jsonl`. No audio was downloaded into the repository,
used for labels, or included in the corpus.

Pilot results: the four sources added four semantic shapes absent from the 133
historical shapes and supplied natural revisions, short fragments, temporal
phrasing, dialogue references, and longer multi-constraint turns. All 42 still
require independent semantic review.
