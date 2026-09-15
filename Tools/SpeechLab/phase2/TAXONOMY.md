# Taxonomy version 2

`config/taxonomy-v2.json` separates six levels that were mixed in the original
flat list:

1. Semantic state
2. Discourse structure
3. Repair and deliberation
4. Surface speech
5. ASR and transcription
6. Contextual and product resolution

Semantic state is also represented orthogonally through intent kind, operation,
polarity, and certainty. This avoids pretending that “action,” “punctuation
loss,” and “shared location” are interchangeable kinds of phenomenon.

All 64 `speechlab-1` IDs remain valid and map to themselves. Input aliases such
as `capitalization-loss`, `name-corruption`, and `person-ambiguity` map to a
canonical ID without changing historical rows.

Nineteen narrowly scoped concepts were added: correction chains, scoped
withdrawal, resolved and unresolved alternatives, stutter-like repetition,
casual grammar, incomplete clauses, discourse markers, cross-turn reference and
ambiguity, contact ambiguity, timezone and DST sensitivity, five explicit ASR
effects, and cancellation scope.

The taxonomy now contains 83 IDs. The Phase 2 corpus covers 78. It deliberately
does not manufacture `conditional-intent`, `conjunction-ambiguity`,
`self-correction-quantity`, `shared-object`, or `unresolved-alternative` cases
when the current contract or available semantic shapes cannot express them
without misleading labels. These are explicit coverage gaps, not implied
support.
