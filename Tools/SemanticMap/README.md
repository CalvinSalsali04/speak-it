# Semantic map probe

Phase 1–4 of `Docs/SEMANTIC_MAP_ARCHITECTURE.md`, as a host-side tool that
compiles the live parser beside it. Not part of the app.

```bash
./Tools/SemanticMap/build.sh
./Tools/SemanticMap/build/semantic-map --selfcheck
./Tools/SemanticMap/build/semantic-map --availability
./Tools/SemanticMap/census-devsets.sh                       # no model
./Tools/SemanticMap/diagnostic.sh                           # model: the rows the router hides, plus controls
./Tools/SemanticMap/build/semantic-map --run in.txt --out runs.jsonl [--shadow] [--no-jobs] [--atom-format lines|inline]
./Tools/SemanticMap/build/semantic-map --replay runs.jsonl --arm rules|production|asked|map [--policy NAME] [--records-out r.jsonl]
python3 Tools/SemanticMap/score.py census|trace|router|whole|select|diagnostic|selftest ...
```

| file | what it is |
| --- | --- |
| `Sources/Atoms.swift` | whitespace atoms of the original transcript, and locating a rules row among them |
| `Sources/SemanticMap.swift` | the map's types and the decoding that refuses, never repairs |
| `Sources/SemanticJobs.swift` | the three model jobs, their prompts and runtime schemas; the only file here that generates |
| `Sources/ComplexityFeatures.swift` | content-free router candidates, each reusing the parser's own detector |
| `Sources/Arbiter.swift` | verdicts, the four powers, the no-new-instant guarantee and the executing-row count |
| `Sources/ProductionRoute.swift` | production's model route, step by step, with every exit recorded |
| `Sources/Records.swift` | run and census records, input reading |
| `Sources/SelfCheck.swift` | deterministic checks, no model |
| `score.py` | every table, content-free; `selftest` checks it against `heldout/score.py` |
| `diagnostic.sh` | the smallest model run on `rambling`: selection, run, replay of every arm, per-group report |
| `LABELS.md` | the fresh-slice schema and who may write it |

Input files are a bare capture per line or `id<TAB>capture`; a multi-column
corpus TSV is refused rather than handing its label columns to a model. Run
records (`--run`) carry capture text and the model's raw answer for replay and
stay on the machine that made them. Census records and every `score.py` table
carry no text.
