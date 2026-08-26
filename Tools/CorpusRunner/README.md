# Corpus runner

Replays the **entire semantic corpus** against the real production sources on
the host, in about 20 seconds. The simulator suite takes 245.

```bash
./Tools/CorpusRunner/build.sh
./Tools/CorpusRunner/build/corpus-run
```

```
FAMILY                             CASES  FAILING  CRIT   BEH  META  COSM
Multi-clause paragraphs               16        5     0     0     3     7
Events                                18        2     0     0     2     0
...
rendering=identity  TOTAL 841 cases, 23 failing, 818 clean
CRITICAL 0  BEHAVIORAL 0  METADATA 18  COSMETIC 15
BLOCKING(crit+beh) = 0
```

Families are sorted by blocking failures first, so triage starts at the top.

## Options

| flag | effect |
|---|---|
| `--family <substring>` | run only families whose name matches |
| `--rendering <name>` | `identity` (default), `comma-free`, `unpunctuated`, `lowercased` |
| `--verbose` | print the full clustered disagreement report per family |
| `--list` | dump every case as `family<TAB>utterance` |

The renderings mirror `RenderingInvarianceTests`. Note that this runner applies
a rendering to **every** case, while the XCTest suite skips cases the transform
leaves unchanged — so the totals are comparable within this tool, not across.

## Relationship to the test suite

It compiles the same slices as `Tools/PipelineProbe` (see that README for why
three files are sliced), plus `SpeakItTests/SemanticCorpus*.swift` and
`CorpusEvaluator.swift` with the test-target import stripped. Expectations,
severities and the fixed reference instant are the real ones, so a result here
reproduces in `SemanticCorpusTests` and vice versa.

Two things it cannot tell you, both inherited from the probe: it runs the rules
path only, and it has no SwiftData store, so capture operations resolve no
targets and nothing about persistence, scheduling or the UI is exercised.

It also runs **every** family in `CorpusEvaluator.allFamilies`, including any
that have no XCTest runner of their own. That is deliberate — it is how the
`splitCompound` family was found to have 15 cases and no gate.

## Mutation testing

```bash
./Tools/CorpusRunner/mutate.sh <name> <file> <line> '<injected statement>'
```

Copies the sources to a mirror, injects the statement immediately after the
signature on `<line>`, rebuilds, and replays the corpus. Use it to answer the
only question that establishes whether a test protects anything: **if I delete
this algorithm, does anything fail?**

```bash
# Delete all person extraction.
./Tools/CorpusRunner/mutate.sh people SpeakIt/Repositories/PersonMention.swift 116 'return []'
```

```
MUTATION [people]
rendering=identity  TOTAL 841 cases, 105 failing, 736 clean
CRITICAL 2  BEHAVIORAL 0  METADATA 102  COSMETIC 15
BLOCKING(crit+beh) = 2
```

105 utterances change and 2 of them can fail the suite, because
`CorpusSeverity.forField` classifies `person`, `type`, `category` and
`needsReview` as non-gating `.metadata` — about 21% of all corpus assertions.
Read that number before trusting a green run on a semantic change.

The mirror lives under `$TMPDIR/SpeakItMutation` (override with `MUTATE_WORK`).
Your working tree is never modified.
