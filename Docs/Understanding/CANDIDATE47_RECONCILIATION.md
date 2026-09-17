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

## 9. What the macOS run answered

Run 35220361423, dispatched on `21808b2` (this tree plus the report document,
which changes no behaviour).

**The corpus gate, and the port cost it nothing.**

```
rendering=identity  TOTAL 1434 cases, 3 failing, 1431 clean
CRITICAL 0  BEHAVIORAL 1  METADATA 0  COSMETIC 2
BLOCKING(crit+beh) = 1
```

The three failing cases are, individually, the three the Candidate47 final
report names as its own qualifications:

| severity | case | what the run printed |
|---|---|---|
| BEHAVIORAL | "Remind me before the office closes December 24" | `delivery: expected notification, got none` |
| COSMETIC | "Book the dentist and before dinner call Mom" | `title[1]: expected Before dinner call Mom, got Before dinner, Call Mom` |
| COSMETIC | "After I finish the essay, call Dave" | `title: expected Call Dave, got After I finish the essay, Call Dave` |

Same count, same severities, same cases. So the ported line moved the gate by
zero. **The control is Candidate47's own recorded measurement in its final
report, not a run of the unmodified tree made here**, which would cost a
second dispatch.

**The gate nevertheless exits 1, and that is not about this branch.**
`Tools/CI/corpus-gate.sh` compares against a hardcoded baseline of zero
blocking failures, so Candidate47's qualified behavioural difference is a
hard CI failure. Candidate47 cannot pass the gate as that script is written,
and neither can anything built on it.

**That is why the Swift test classes have no result.** Steps after a failing
step are skipped, so `Unit tests` never ran and
`SpeakItTests/SpeechRepairTests` and `SpeakItTests/ThoughtCompletionTests`
remain unmeasured. No dispatch can reach them while the gate blocks.

**The abandonment development set is clean on the column that matters.**
`UNSAFE withdrawn thought given a date/reminder/place   0`, with the four
documented failures (ABN20, ABN38, ABN40, ABN46) unchanged and still counted
in the rates.

**Foundation Models on the hosted runner**: `deviceNotEligible`, as on every
previous run. The instructions fingerprint is `654b75ea` rather than main's,
because `e555f2a`'s prompt change was deliberately not carried.

## 10. The secret scan, and an allowlist that failed its own test

The scoped allowlist proposed in section 5's neighbourhood was written,
tested both ways, and **reverted, because it did not do what it said**.

Measured with gitleaks 8.30.1, the version `ci.yml` pins:

| | result |
|---|---|
| `condition = "AND"` + `paths` + a 64-hex regex | history scan clean — but a planted AWS key and a planted Stripe key in the same file went **undetected** |
| control, allowlist absent, same plants | both plants **detected**, so they are real probes |
| `condition = "AND"` + `paths` + a regex matching nothing | still excused everything |

The third row is the diagnosis: a global allowlist's `paths` skips the file
before any regex is consulted, so `condition` changes nothing there. gitleaks
also accepts unknown allowlist keys silently — a deliberately invented key
produced no error — so a typo and an unsupported option look identical.

**"Only a 64-hex value, only in those three files" is therefore not
expressible in a gitleaks global allowlist.** The closest formulation that
was measured to work uses no `paths` at all:

```toml
[[allowlists]]
regexTarget = "line"
regexes = ['''^\s*"[A-Za-z0-9_./-]+\.[A-Za-z0-9]+": "[a-f0-9]{64}",?\s*$''']
```

The JSON key must be a file path with an extension, which is what a manifest
line is and what a secret's key name is not. Measured: the three manifest
hashes are excused, and all three plants are still caught — including a
64-character hex value placed under the key `"api_key"`, which the
value-shape-only version would have excused.

It is narrower than what was tried on value shape and broader on file scope.
It was **not** taken either: any rule keyed on shape excuses every future line
of that shape, wherever it appears. What shipped instead is in section 11.

## 11. What was committed: three fingerprints, and nothing else

`.gitleaksignore` carries three lines. Each names one finding by the exact
fingerprint gitleaks 8.30.1 emits -- commit, file, rule and line number:

```
15bde2157036000fa8b070c3ff731fed21b1a5ce:Docs/Understanding/Candidate47/baseline/freeze.json:generic-api-key:172
15bde2157036000fa8b070c3ff731fed21b1a5ce:Docs/Understanding/Candidate47/iteration-2/freeze.json:generic-api-key:173
15bde2157036000fa8b070c3ff731fed21b1a5ce:Docs/Understanding/Candidate47/iteration-4/freeze.json:generic-api-key:173
```

All three are the same manifest line in three copies:

```
"FounderDashboard/app/chatgpt-auth.ts": "4265a2e7...e42cc"
```

**Why each is a false positive.** The freeze manifests map every file of the
frozen tree to its SHA-256, and `verify_frozen.py` checks the tree against
them. The flagged value is that file's hash, recomputed here rather than
assumed: `sha256` of `FounderDashboard/app/chatgpt-auth.ts` is
`4265a2e7c2dcb3a6f4b7026f762bf5b6e4caec76cc13c0a45987ee9a9f2e42cc`, which is
the flagged value in all three files. `generic-api-key` fires on these three
of the manifests' several hundred identically shaped lines only because the
key beside the hash is a path containing "auth". Editing the manifests is not
available: their bytes are the identity the verifier checks.

**Nothing else is excused.** Not a file, not a commit, not the
`generic-api-key` rule, not 64-character hex values, not manifest-shaped
lines. A fingerprint pins the line number and the commit, so a real key on a
neighbouring line of the same file is still reported -- which is exactly what
the falsifier below shows.

**Measured, in the mode `ci.yml` actually uses.** All four runs are
`gitleaks 8.30.1 git --redact --verbose --exit-code 1 --config .gitleaks.toml`,
the invocation from `.github/workflows/ci.yml`:

| | scan | result |
|---|---|---|
| before | no ignore file | 3 leaks, the three fingerprints above, exit 1 |
| after | the three fingerprints | **190 commits scanned, no leaks found, exit 0** |
| falsifier | plus an AWS key and a Stripe key committed on lines 174 and 175 of `iteration-2/freeze.json` | **2 leaks, `aws-access-token` and `stripe-access-token`, exit 1** |
| after removing the plants | the three fingerprints | 190 commits scanned, no leaks found, exit 0 |

The falsifier ran in `git` mode rather than `dir` mode, which meant committing
the plants; that was done on a local scratch branch, `ac7ce70`, never pushed
and deleted immediately after. Its plant commit carried a different SHA from
`15bde21`, so no ignore entry could have matched the plants even by accident,
and lines 174 and 175 sit either side of the ignored line 173 in the same
file. `.gitleaks.toml` is unchanged.
