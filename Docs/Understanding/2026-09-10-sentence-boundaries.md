# Lowercase sentence boundaries

The first 2,000 evaluated cases from the two-million-case synthetic bank exposed a lost-task defect: `remember alex singh likes socks. go to elm shop to buy socks.` became a single Memory note. Apple's sentence tokenizer sometimes treats lowercase text after a period as part of the preceding sentence.

The rule-based extractor now also respects explicit sentence punctuation before an action, including a fronted date. It preserves abbreviation boundaries such as `dr. cook` and `st. john`, and does not split inside decimal numbers. The existing action vocabulary and downstream reported-speech handling still apply.

Replaying the same 66 affected development cases restored a separate Memory and task in **66/66**, up from **0/66**. Full semantic consistency is still **0/66** because lowercase two-word subjects lose person metadata; this fix does not claim to solve that separate defect. Seven additional boundary checks cover capitalization, communication, abbreviations, reported wording, fronted dates, and decimals. Focused Swift tests passed and the existing **1,381-case corpus remains clean**. Machine-readable evidence is in the sibling JSON file.

## Remaining development triage

- `frame-2/noise-3`: task loss repaired; lowercase two-word Memory subject metadata still needs work. `PersonMentionResolver.factSubject` only extends the subject to a capitalized second name. Any extension needs common-noun/place guards, not blanket capitalization.
- `frame-1/noise-1`: a hesitation immediately after `call` leaves a comma that hides the person. Preserve boundaries between independent commands when repairing this.
- Lowercase place names ending in `Walk` can trigger communication/person interpretation around `buy`. Inspect representative metadata before changing name rules.
- Conditional and separately dated frames have additional capitalization disagreements. Their consistency counts alone do not establish which output is correct.

The campaign continues from its checkpoint with results separated by probe hash. Generated count, evaluated count, consistency, and independently reviewed correctness remain distinct. Reserved evaluation examples were not inspected or used for this fix.
