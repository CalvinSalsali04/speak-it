# Candidate47 / main reconciliation

Candidate47 is the verified deterministic baseline. Ten commits landed on
`main` while it was being finished. This records what was carried across,
what was deliberately not, and what is still somebody's decision.

**This branch is a proposal. It is not merged, and it is not to be merged
until an independent second review has read it.**

## 1. Identity, before anything was compared

`Tools/Reliability250K/verify_frozen.py`, run from the closeout branch head
`13ee748`:

```
Candidate47 identity PASS: 68 Swift files; 71 total hash checks. No production execution.
```

Exit 0, with no file named as differing.

Read that as a content match, not a count match. `main` also carries exactly
68 production Swift files, so the count is a coincidence and proves nothing
on its own; what passed is a SHA-256 per file against
`Candidate47/development/candidate47-source.json`, plus the three evaluator
files named in `FROZEN_CANDIDATE.json`, which is where 71 comes from.

`13ee748` is one commit ahead of the production commit
`15bde2157036000fa8b070c3ff731fed21b1a5ce`, and it touches six files, all
documents and zero Swift. So the tree the verifier hashed is `15bde21`'s.

## 2. The divergence

The merge base is `faeab4e` (#93, 2026-09-15), the same commit `CLOSURE.json`
records as `base_commit`. Ten commits have landed on `main` since.

| | commits | what they touch |
|---|---:|---|
| No production Swift | 6 | tooling, corpora, documents |
| Production Swift, comment-only | 2 | `ClauseStructure.swift` (`599fb7d`, `bd1f760`) |
| Production Swift, prototype only | 1 | `ModelInterpreter.swift` (`e555f2a`) |
| **Production behaviour** | **1** | **`SpeechRepair.swift` (`a5e4d2a`)** |

Both `ClauseStructure.swift` commits are comment-only in production Swift:
the code lines in those diffs are unchanged context. `599fb7d` is easy to
miss because its title describes a behaviour change, which lives in its test
files rather than in the parser.

## 3. Carried across

**`3788dc9` — the contemplation hedge.** One line of `DisfluencyFilter`:

```
-  ^i\s+was\s+thinking\b[\s,]*
+  ^i\s+was\s+thinking\b(?!\s+(?:of|about)\s+\S)[\s,]*
```

Candidate47 carried that line byte-identical to the fork base, so this is the
same edit `a5e4d2a` made, applied to an unmodified line. "I was thinking" is
throat-clearing in front of a clause the speaker owes and the sentence's own
verb in front of its complement; the old rule deleted the second kind and left
`of calling Priya`, a fragment with the hedge gone.

`SpeakItTests/SpeechRepairTests.swift` and
`SpeakItTests/RenderingInvarianceTests.swift` come from `main` whole, because
Candidate47 never changed either. They carry the four regression methods for
this rule and `LexicalTagging.skipIfBlind`, which those methods need to
compile. **That helper is a scope addition beyond the ported line**: it is a
compile dependency, not a choice.

**`ed4b8f2` — the completion tests.** `ThoughtCompletionTests.swift` is the
only file both sides changed, both additively, so it is a clean three-way
merge rather than a decision. One doc comment carried from `main` cited
`ClauseStructure.swift:702` and `:709`; both predicates are still ordered that
way on this tree, several hundred lines lower, so the comment now quotes them
instead of numbering them.

**`21808b2` — the census.** See section 5.

## 4. Deliberately not carried

| | why |
|---|---|
| `e555f2a` `ModelInterpreter.swift` | Prompt hardening and an FNV-1a fingerprint in the Foundation Models prototype. Production calls none of it, Candidate47 does not change the file, and it is outside this reconciliation's scope. A clean port whenever it is wanted. |
| `599fb7d`, `bd1f760` `ClauseStructure.swift` | Comments only, onto a file Candidate47 rewrote by 559 lines. Carrying them would be noise against a tree whose surrounding code no longer matches what they describe. |
| 22 tooling, corpus and document files | Not behaviour. Includes `Tools/PipelineProbe/questions/declared-limits.txt`, the `unfinished.tsv` edits, the `InterpretationProbe` run scripts and the `LanguageMutations` work. |

## 5. The two files the closure excluded

`Docs/LANGUAGE_BASELINE.md` and `Tools/CorpusRunner/test_observation.py` were
excluded from the Candidate47 freeze on purpose (final report, section D).
They are also the two files any fixture change moves, because the gating
corpus in `SpeakItTests` is about two thirds of the readable population. This
reconciliation adds fixtures, so it could not avoid them.

The multi-word pin, which is the sharpest of the figures involved:

| | pin | measured |
|---|---:|---:|
| fork base `faeab4e` | 3904 | 3904 |
| Candidate47 `15bde21` | 3904 | **4023** |
| `main` `4b0262a` | 3928 | 3928 |
| this branch | **4047** | 4047 |

Candidate47's own tree is stale against itself: its 36 added
`ActionabilityTests` methods and one `ThoughtCompletionTests` method moved the
population and the closure did not recount, so
`Tools/CorpusRunner/test_observation.py` fails on the Candidate47 tree before
any reconciliation — two failures, measured, not predicted.

Taking either 3904 or 3928 would have been choosing a side, and both are wrong
for this tree. `21808b2` recomputes instead. **Recomputation is a third
option, not a side.** It is kept as its own commit so it can be dropped whole;
dropping it leaves the behaviour commits intact and the branch red on the
census.

**Still open, and not decided here.** Calvin's uncommitted edits to both files
on his Mac are a third state no session can see. `main` carries a cost-ledger
row for #96 that this branch does not.

## 6. What the runs have to answer

The port is clean as text and unverified as behaviour, and the reason is
specific. `599fb7d`'s comments state that the trailing `\S` in the repair
lookahead and `ClauseStructure`'s acceptance of a lone `.preposition` are a
matched pair: the lookahead keeps stripping "I was thinking about" when
nothing follows, precisely so the bare "about" reaches
`ThoughtCompletion.unfinished` and is read as an abandoned thought rather
than becoming an errand. Candidate47 rewrote that file by 559 lines and has
six `trailingFunctionWord` return sites.

So the questions a run decides, and a reading does not:

1. Does the corpus gate hold on the Candidate47 tree with the ported line?
2. Does `testTheRepairAndTheFragmentRuleAreOneChain` still see
   `.trailingFunctionWord` after Candidate47's rewrite?
3. Do the three abandonment rows (`routed` HY04, `unfinished` INC34 and FP12)
   behave as they do on `main`?

## 7. A separate finding, not fixed here

Candidate47's own added method,
`testRequestFramesNeedTheirObjectsAndCoordinatorsNeedAContinuation`, does not
abstain, and half of it cannot be exercised on a GitHub-hosted runner: its
`XCTAssertNotNil` rows are discriminating and fail where NLTagger has no
lexical-class model, while its `XCTAssertNil` rows pass there vacuously. It is
left exactly as Candidate47 wrote it. Changing a protected regression anchor
is not part of this reconciliation, and it is named here rather than resolved.

## 8. Device phase

Device evidence must be built from a fresh checkout of the reconciled commit
once it is approved. The final report records the main workspace at
`/Users/calvinwak/Documents/Speak It` as based on `2932272` — the build-19
merge of 2026-09-09, 136 commits behind the fork base, differing in 14 frozen
Swift files. It is neither Candidate47 nor `main`, and a capture attributed to
the wrong tree is worse than no capture.
