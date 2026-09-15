# SpeechLab corpus repair and trust-closure report

## Outcome

The independent-adjudication PR merged as PR 64 / `bc26657d04c99e0cd697e6f02d606e8f02fc5c91`.
Two repair rounds corrected seven repeated repository-authored paraphrase
defects without changing production parser code, dates, cancellation scope, or
taxonomy labels.

Round 1 changed 27 renderings and received 37 fresh blind reviews from three
new reviewer identities. Twenty-one became trusted and six remained disputed.
Round 2 changed 20 renderings and received another 37 fresh blind reviews from
three new identities. Sixteen became trusted and four were disputed in that
round. Across the final candidate, 37 repaired cases are retained and trusted.

The strict scoreable corpus contains 695 cases. It excludes 123 cases while
preserving their utterances, reasons, taxonomy contribution, and lineage:

- 92 broken or implausible cases;
- 16 unresolved repair-backlog cases;
- 13 ambiguity/challenge candidates that must not use exact-answer scoring;
- 2 public-derived dialogue acts deferred because representation is insufficient.

No excluded case was relabeled as correct. No review threshold was weakened.

## Final quality

- Starting corpus: 818
- Final scoreable corpus: 695
- Repaired and retained: 37
- Unchanged and retained: 658
- Removed from exact scoring: 123
- Trusted / disputed / rejected: 695 / 0 / 0
- Naturalness: 1: 0, 2: 0, 3: 323, 4: 344, 5: 28
- Naturalness 4–5: 372 / 695 = 53.53%
- Audited meaning preservation: 695 / 695 = 100%
- Contract affirmation: 695 / 695 = 100%
- Broken or implausible: 0 / 695 = 0%
- Safety positive reviews: 0: 0, 1: 0, 2: 419
- Every retained safety case satisfies the two-positive-review policy.

## Reviewer audit

The original 1,332-review audit found 17 / 514 safety verdict disagreements
(3.31%) and 255 / 514 naturalness disagreements (49.61%). Reviewer
broken-language rates were 14.48%, 3.15%, and 6.52%. Ninety-nine of 107
low-naturalness reviews still affirmed the contract, while 44 of 750
high-naturalness reviews were semantically adverse or uncertain. Naturalness
and semantic correctness were therefore not treated as proxies. The protocol
now makes that separation explicit and clarifies `relevant_context.timezone`.

## Coverage and saturation

The trust-closure corpus retains 136 of 137 semantic families and 66 of 83
phenomena. Twelve previously covered phenomena moved out of exact scoring:
ambiguous-pronoun, asr-dropped-token, asr-name-corruption,
asr-partial-recognition, asr-substitution, contact-person-ambiguity,
cross-turn-reference-ambiguity, dst-transition, homophone,
punctuation-corruption, quoted-speech, and timezone-sensitive. The original five
contract gaps remain deferred, so 17 concepts are uncovered in exact scoring.

| Cases | Families | Phenomena | Pairs | Structural forms | New units |
|---:|---:|---:|---:|---:|---:|
| 100 | 100 | 0 | 0 | 100 | 205 |
| 200 | 129 | 0 | 0 | 200 | 129 |
| 400 | 132 | 66 | 0 | 400 | 269 |
| 600 | 133 | 66 | 183 | 600 | 384 |
| 695 | 136 | 66 | 331 | 695 | 246 |

The ordering introduces interaction cases late, so marginal-unit counts do not
show that 10,000 examples would improve validity. Recommendation: **A — remain
below 1,000** until missing contract shapes and excluded challenge/safety cases
have defensible representations.

## Exact 14 gates

Twelve pass. `intentional_multi_phenomenon_coverage` fails because removing weak
compositions leaves fewer than 300 multi-phenomenon cases.
`saturation_measured_through_800` fails because the trustworthy corpus is 695.
The other twelve pass, including all four gates that failed at the start.

The corpus is **not frozen**. Manifest hashes are reproducibility identifiers,
not frozen evaluation identifiers. No independent-evaluation membership exists.
