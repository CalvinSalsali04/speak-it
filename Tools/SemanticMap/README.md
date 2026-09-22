# Semantic map probe

Phase 1–4 of `Docs/SEMANTIC_MAP_ARCHITECTURE.md`, as a host-side tool that
compiles the live parser beside it. Not part of the app.

```bash
./Tools/SemanticMap/build.sh
./Tools/SemanticMap/build/semantic-map --selfcheck
./Tools/SemanticMap/build/semantic-map --availability
./Tools/SemanticMap/census-devsets.sh                       # no model
./Tools/SemanticMap/build/semantic-map --run in.txt --out runs.jsonl [--shadow] [--no-jobs] [--atom-format lines|inline]
./Tools/SemanticMap/build/semantic-map --replay runs.jsonl --arm rules|production|map [--policy NAME] [--records-out r.jsonl]
python3 Tools/SemanticMap/score.py census|trace|router|whole|selftest ...
```

| file | what it is |
| --- | --- |
| `Sources/Atoms.swift` | whitespace atoms of the original transcript, and locating a rules row among them |
| `Sources/SemanticMap.swift` | the map's types and the decoding that refuses, never repairs |
| `Sources/SemanticJobs.swift` | the three model jobs, their prompts and runtime schemas; the only file here that generates |
| `Sources/ComplexityFeatures.swift` | content-free router candidates, each reusing the parser's own detector |
| `Sources/Arbiter.swift` | verdicts, the four powers, the structural guarantee |
| `Sources/ProductionRoute.swift` | production's model route, step by step, with every exit recorded |
| `Sources/Records.swift` | run and census records, input reading |
| `Sources/SelfCheck.swift` | deterministic checks, no model |
| `score.py` | every table, content-free; `selftest` checks it against `heldout/score.py` |
| `LABELS.md` | the fresh-slice schema and who may write it |

Input files are a bare capture per line or `id<TAB>capture`; a multi-column
corpus TSV is refused rather than handing its label columns to a model. Run
records (`--run`) carry capture text and the model's raw answer for replay and
stay on the machine that made them. Census records and every `score.py` table
carry no text.
