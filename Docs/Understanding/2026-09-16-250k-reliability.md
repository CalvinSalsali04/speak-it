# Speak It 250K reliability phase — in progress

The supplied combined bank is frozen and verified: 250,000 unique case IDs,
418 semantic families, 513 structural variants, valid contract hashes and item
counts. Bank SHA-256: `eec6aabf7b23920ba0798e549a92613990077387431afdcddfacbbf0cdcb1311`.

The verified source is `/private/tmp/speak-it-conditional-intent`. Its production working source was captured before execution. An initial run mistakenly used the older main checkout; it is retained separately in `older-main-diagnostic/` and excluded from this baseline. Branch:
`codex/conditional-intent-safety`; base commit: `faeab4e90bee4f67d60e33daa248f48b333ca445`. The working tree already
contained uncommitted parser fixes and unrelated user work, which were preserved.
Full working-source hash: `846e7a1bb45071ac4c38f2c4e37e104fdaa838e9d3d029b7152a091e6ff43cf7`.
Parser-source hash: `eecdd86d51f4792a005d689b3cf475f54ac79f726d787483718eae0d9e60c8fa`.
The reproducible archive and per-file hashes are in
`output/reliability-250k/baseline/`.

The full baseline is running through the compiled production host rules path.
Do not change product behavior before it completes. `progress.json` is the
live completed-shard counter; `execution.log` and `shards/` retain evidence.
The full run must contain 250,000 aligned outputs before it is reported as done.

The simulator NaturalLanguage asset failure (every token returning OtherWord)
is an outstanding infrastructure measurement issue. Host tagging passed its
health check. No simulator repairs or production accommodation were attempted.

The host path does not exercise Foundation Models refinement, SwiftData,
contact context, notification delivery, or physical location resolution. An output-only measurement harness exports complete native temporal/location intent, confidence, and capture-operation fields. Do not infer complete
end-to-end safety or contextual resolution from this run.

`Tools/Reliability250K/` supplies the resumable runner, offline deterministic
evaluator, report builder, evaluator tests, and local blind analyst. The latter
receives only utterance/context before any three-way comparison. A pilot is kept
separate from the revised schema. Official Ollama 0.34.1 fell back to CPU;
0.11.10 detected Metal and is used for the revised local pass. Qwen3 8B weights
and model identity are stored under ignored output. No paid inference is used.

Candidate severities are not confirmed defects. In particular, lexical overlap,
unavailable target-type ontology, context, and advanced temporal interpretation
need separate adjudication. The bank contains 4,957 marked ambiguous rows and
6,000 context-bearing rows. The 104 `before after` constructions are bank-quality
candidates, not edited or automatically invalidated contracts.

Next: finish all 250K outputs, evaluate saved output, adjudicate root-cause
families, report the first full baseline, then implement general P0/P1 fixes with
focused fixtures and protected cancellation/conditional gates. No completion or
success claim has been made.
