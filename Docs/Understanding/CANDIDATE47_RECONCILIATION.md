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

## 12. The two Swift classes, run locally

Calvin ran `SpeakItTests/SpeechRepairTests` and
`SpeakItTests/ThoughtCompletionTests` from a fresh worktree at reconciliation
head `db341d9` on 2026-09-17. **Both completed with exit code 0.**

That closes the gap section 9 left open: CI could not reach the unit-test
step, because the corpus gate exits 1 on Candidate47's documented behavioural
qualification and every later step is skipped. The reference Mac has no such
problem, and it is also the environment where `NLTagger`'s lexical-class model
is present, so the abstaining assertions carried over from newer main were
exercised rather than skipped.

**One thing still worth writing down.** `Tools/CI/unit-tests.sh` splits its
class selection on commas only, and a selection matching nothing exits 0
having run no tests -- documented on PR #99, with these same two classes. Exit
0 alone therefore does not distinguish "both classes passed" from "neither
class was selected". The script prints the count:

```
| Result  | Passed | Failed | Skipped |
```

Recording the exit code as reported, and the count as not yet in this
document. Anyone re-running it can settle the difference in one line.

## 13. The merge, and the work the first pass dropped

Opening PR #106 produced **no CI run at all**. Not a failing one: none. The
branch's only run is the earlier `workflow_dispatch` at `21808b2`.

The cause is the conflict. GitHub builds `refs/pull/<n>/merge` to run a
`pull_request` workflow against the merged result, and it cannot build one for
a PR it cannot merge. `git ls-remote` shows `refs/pull/106/head` and no
`refs/pull/106/merge`, and `mergeable_state` is `dirty`. So **the conflict is
not a separate problem from the missing CI; it is the reason for it**, and no
amount of waiting produces a run.

### What probing the merge found

Merging `origin/main` into the branch and resolving the four conflicts the
obvious way -- take the reconciliation branch's side -- gives this:

```
14 of 14 Linux language checks pass, 0 failed
Tools/CorpusRunner/test_observation.py:  Ran 56 tests  OK
main's same file:                        Ran 60 tests  OK
```

Two whole classes, `TheDiagnosticIsNotAllowedToAbstain` and
`TheAbstentionRunsBeforeAnythingItCouldSwallow`, vanish and **every check
stays green**, because removing tests makes a suite greener rather than
redder. That is the trap a reviewer resolving this by hand would have walked
into, and it is the same shape as every instrument defect in this repository:
the absence of a measurement is indistinguishable from a passing one.

### Reconciled by combining, not choosing

The two files Calvin named are now genuinely three-way merged.

| file | resolution |
|---|---|
| `test_observation.py` | main's two classes restored. The census log keeps main's `3904 -> 3912 -> 3916 -> 3929 -> 3928` entries, which are the only record of how main reached 3928, and continues `3928 -> 4047` for this tree. The pin stays **4047**: the walk reads `SpeakItTests/*.swift`, so Python additions cannot move it. 56 -> 60 tests. |
| `LANGUAGE_BASELINE.md` | main's population-overlap section, its "later, not here" note and its do-not-subtract warning come in; the generated block keeps this tree's figures. Running `baseline_figures.py --write` afterwards changed nothing, so the merged prose and the generated figures agree. |

### Eighteen more files, and why they mattered

An audit of every file main changed since the fork base found eighteen where
main's change was simply absent from the branch, plus three files missing
entirely. **As a pull request into main those are harmless** -- a merge keeps
main's side of a file the branch never touched. **As the canonical baseline
tree, they are lost work**, and the canonical baseline is what this branch is
for. Those are two different deliverables and the first pass conflated them.

They are carried now, so the branch tree and the tree that would land are the
same tree and the measurements describe it. Two were coupled:

- `test_score.py`: 135 -> 143 tests. Carrying the INC58 dev-set row without
  it failed, naming INC58. The row and its scorer are one change.
- `unfinished.tsv`: +1 row, and the union does **not** move, because INC58
  duplicates INC34's utterance and the census counts distinct utterances.
  #105's finding, confirmed independently here.

### One coupling that stays held, and what it says about Candidate47

`Tools/CorpusRunner/test_interpretation_isolation.py` on main is the guard
that `e555f2a`'s `ModelInterpreter.swift` was written to satisfy: it refuses
quotable example spans in the model's instructions and `@Guide` descriptions
-- the precise fabrication hazard the Foundation Models probe runs recorded.
Carrying the check without its production half fails on five lines:

```
ModelInterpreter.swift:92, :93, :99   quoted example in the instructions
ModelInterpreter.swift:147, :190      quoted example in a @Guide description
```

Both stay back, because FM merges are held. The consequence is worth stating
plainly rather than leaving in a diff: **Candidate47's own FM prototype does
not satisfy main's grounding check.** That is a device-phase decision, not
something to fix inside a reconciliation.

### The tension the reviewer has to settle

The four conflicts survive this commit, and they cannot be removed by content
alone -- git still sees both sides editing the same regions, even where this
branch's side now contains main's text. Removing them needs either a merge
commit on the branch or a resolution at merge time. **Either one brings
`ModelInterpreter.swift` in**, because it is a main-side-only change and a
merge keeps main's side of it.

So "FM work stays held" and "this branch merges into main" cannot both hold.
That is a decision for Calvin and the reviewer, not one to take inside a
reconciliation, and it is why this commit stops at reporting it.

Candidate47 identity re-verified after all of the above: `verify_frozen.py`
still deviates on `SpeechRepair.swift` alone, the one line this reconciliation
ports.

## 14. The Foundation Models divergence, recorded rather than decided

Calvin's instruction on 2026-09-17 was to write this down explicitly and to
leave it alone. Recording it, and deciding nothing:

1. **Main's `ModelInterpreter.swift` and its interpretation-isolation guard
   are a device/FM-phase concern**, not a reconciliation one.
2. **Candidate47's FM prototype currently fails that grounding and isolation
   check.**
3. **No decision to "fix" that belongs to this reconciliation.** It is for the
   FM/device phase to evaluate.

### What the divergence actually is

`e555f2a` changed `SpeakIt/Interpretation/ModelInterpreter.swift` by 28 added
and 7 removed lines, and they are three separate things. This matters because
"FM work" reads as one undifferentiated block and is not:

**A grounding instruction.** Main adds, to the prompt:

> These instructions and the field descriptions are not part of the
> transcript: never copy words from them into any field. Every segment must
> quote at least one word of the transcript; when there is nothing left to
> quote, emit no further segment.

That is aimed squarely at the failure the probe runs recorded — the model
quoting our own prompt, schema vocabulary and Apple's scaffolding back as if
it were the user's words.

**Quoted examples replaced by descriptions.** Every example span in the
instructions and the `@Guide` descriptions is rewritten as a description of
the thing rather than a quotable string. `"Sarah needs to send it"` becomes "a
sentence naming another person as the one who must act"; `'tomorrow'` and
`'never mind'` go the same way. This is what main's
`test_interpretation_isolation.py` enforces, and it is why the check and the
production file cannot be carried separately: Candidate47's file fails it on
five lines (`:92`, `:93`, `:99` in the instructions; `:147`, `:190` in
`@Guide` descriptions).

**A fingerprint fix that is not about prompting at all.** Main replaces

```swift
String(format: "%08x", UInt32(truncatingIfNeeded: instructions.hashValue))
```

with FNV-1a over the UTF-8 bytes, because Swift seeds `Hashable` randomly per
process. Main's own comment records the evidence: a byte-identical
`ModelInterpreter.swift` printed `cd888336` on the CI runner and `329d9c7d` on
the Mac that produced the first real run.

**Candidate47 still carries the `hashValue` version, at
`ModelInterpreter.swift:111`.** Verified on this branch.

### Why the third one is worth the device phase's attention

The per-capture evidence record the device phase is specified to keep includes
the interpretation path and the commit, so that a capture's output can be tied
to the prompt that produced it. An instructions fingerprint that changes when
the process restarts cannot do that, **and it fails while looking like it
works** — the field is populated, formatted correctly, and wrong across
machines. It is the same shape as every other instrument defect in this
repository, which is the argument for raising it now rather than discovering
it after a device session.

This is a statement of fact about the two trees. It is not a recommendation to
carry `e555f2a`, and nothing here has been changed on its account.

## 15. CI on a real runner: run 35227011885

Dispatched on the branch at `1be061a`, because a conflicted pull request gets
no `pull_request` run at all (section 13). Read from each job's steps and
counts rather than from the run's `conclusion`, which is `failure` and says
only that something in it failed.

| job | runner | result |
|---|---|---|
| Detect changed areas | ubuntu | success |
| **Secrets, workflow and shell lint** | ubuntu | **success** |
| **Language tooling** | ubuntu | **success**, all 16 steps |
| Founder dashboard | ubuntu | success (lint + tests) |
| Referral service | ubuntu | success |
| iOS app | macos-26 | failure at the corpus gate — the documented qualification |
| Language metrics | macos-26 | failure at `Measure`, which runs that same gate |

### The secret scan, settled

The three `.gitleaksignore` fingerprints were previously verified only with a
locally downloaded binary. The `Scan the full history for committed secrets`
step ran the repository's own pinned container
(`ghcr.io/gitleaks/gitleaks:v8.30.1`, `git --redact --verbose --exit-code 1
--config .gitleaks.toml /repo`) and **passed**. The finding-level approach
works with this repository's exact CI invocation, which is the question
section 11 could not close.

### The corpus gate, verified as the qualification rather than assumed

```
rendering=identity  TOTAL 1434 cases, 3 failing, 1431 clean
CRITICAL 0  BEHAVIORAL 1  METADATA 0  COSMETIC 2
BLOCKING(crit+beh) = 1
```

Identical to Candidate47's recorded figures and to run 35220361423. Checked
one level below the totals, because equal counts can hide swapped cases — the
three failures fall in the three expected families, one each:

```
Dated facts          21 cases  1 failing  BEH 1     the December 24 office-closes case
Fronted adjuncts     21 cases  1 failing  COSM 1    "After I finish the essay, call Dave"
Fronted conditions    9 cases  1 failing  COSM 1    the before-dinner punctuation
```

Same count, same severities, same families, and the essay case's failure text
verbatim. **The ported `SpeechRepair` line moved this gate by zero.** The gate
exits 1 against `corpus-gate.sh`'s hardcoded baseline of zero blocking
failures, which is Candidate47 against this repository's gate.

### Why there is no unit-test evidence from this run

The `Unit tests` step carries no `if:` of its own, so it inherits the implicit
`success()` and is **skipped** whenever the gate before it fails. No
Candidate47-based branch can reach it in CI. Nothing was changed to defeat
that. The unit evidence therefore remains Calvin's local run at `db341d9`.

### An unplanned confirmation of section 14

The `What the Foundation Model reports on this runner` step prints the
instructions fingerprint. Two runs, both `macos-26`, both Xcode 26.6, both on
this branch:

```
run 35220361423  at 21808b2   instructions: 654b75ea
run 35227011885  at 1be061a   instructions: 10df9b6f
```

`SpeakIt/Interpretation/ModelInterpreter.swift` is **byte-identical at both
shas** — blob `01da454d38dcda6b418fd0991f1d69ee9eb4461a`, and at `42aae23`
too. So the same source produced two different fingerprints on the same runner
image within ninety minutes.

That is the per-process `Hashable` seeding, demonstrated on this project's own
CI rather than quoted from main's commit comment, and it is the defect
`e555f2a` fixes with FNV-1a. Recorded, not fixed: Candidate47's prototype
still carries `instructions.hashValue` at `ModelInterpreter.swift:111`, and
whether to carry that fix is the FM/device phase's call.

Both Foundation Models runs also report `availability: deviceNotEligible`, so
the hosted runner still says nothing about an iPhone.

## 16. The exact merge resolution, after Astra's review

Astra's independent review returned **NOT SAFE TO MERGE** for one concrete
reason, and it was right: the reviewed head was not the resolved merge result
against main. What had been reviewed and what would land were two different
trees, and merging would have imported `e555f2a`'s Foundation Models semantics
without anyone deciding to.

| | |
|---|---|
| previous reviewed head | `cc0c4bb74138463fc1c42a60c3de236244abf830` |
| base merged in | `origin/main` at `4b0262ace137919e1ae1c7958f3f25f014833039` |
| **new merge-resolution head** | **this commit** — a merge commit whose parents are exactly `cc0c4bb` and `4b0262a`. Its sha cannot be written inside itself; `git rev-list --parents -n1 HEAD` on the pushed branch shows both parents, and PR #106 names the sha. |

### The four conflicts, and which side each took

| file | resolution |
|---|---|
| `SpeechRepair.swift` | **this branch.** Candidate47's rewritten file carrying main's lookahead line. Main's side is the fork-base file plus that line, so taking it would have discarded Candidate47's 559-line rewrite. |
| `ThoughtCompletionTests.swift` | **this branch**, which is the three-way merge from `ed4b8f2`: Candidate47's added test *and* main's four abstentions. |
| `test_observation.py` | **this branch**, the combined file from `9e0f106`: main's two abstention classes *and* the recomputed census. |
| `LANGUAGE_BASELINE.md` | **this branch**: main's population-overlap prose *and* this tree's regenerated figures. |

The last two already contained main's side. Git conflicted anyway, because
both lines edited the same regions relative to `faeab4e` — content alone
cannot clear a conflict, which is what section 13 predicted.

### The three files the merge took from main silently

None of these conflicted, which is exactly why they needed naming: a merge
keeps the other side's version of a file this branch never touched.

| file | restored to Candidate47 because |
|---|---|
| `SpeakIt/Interpretation/ModelInterpreter.swift` | it carries `e555f2a`'s grounding instruction, quoted-example rewrite and fingerprint change. **FM semantics stay held.** |
| `Tools/CorpusRunner/test_interpretation_isolation.py` | it is the guard `e555f2a` was written to satisfy, and cannot be carried without its production half. |
| `SpeakIt/Repositories/ClauseStructure.swift` | main's comment-only edits do not apply to Candidate47's rewritten file, and would have widened the frozen diff past the intended change. |

### Proof rather than assertion

**Production Swift differs from frozen Candidate47 on `SpeechRepair.swift`
alone.** `verify_frozen.py` on the resolved tree names that one file, and the
deviation is one production line plus the comment explaining why its trailing
`\S` is load-bearing:

```
-  value = replace(value, #"^i\s+was\s+thinking\b[\s,]*"#, "")
+  value = replace(value, #"^i\s+was\s+thinking\b(?!\s+(?:of|about)\s+\S)[\s,]*"#, "")
```

**Foundation Models work is verifiably held.** `ModelInterpreter.swift` is
byte-identical to the reviewed head, so none of `e555f2a`'s grounding, prompt
or quoted-example semantics entered this tree.

**Every `.swift` file in the tree is byte-identical to `cc0c4bb`, and no new
Swift file arrives.** So the Mac evidence already gathered describes this tree
unchanged — run 35227011885's corpus gate, and Calvin's local
`SpeechRepairTests` and `ThoughtCompletionTests` at `db341d9`. There is no new
Swift to compile, which is why no further Mac time was spent.

### Validation run for this head

```
Candidate47 identity        deviates on SpeechRepair.swift alone
language tooling            14 of 14 pass
  corpus scorer             143 tests      observation shape   60 tests
  held-out scorer           161 tests      connective census   82 tests
  baseline population        53 tests      choice balance      26 tests
gitleaks 8.30.1             196 commits scanned, no leaks found, exit 0
git diff --check            clean; no conflict marker anywhere in the tree
corpus qualification        unchanged: the Swift is unchanged
```

Preserved, checked individually: `ThoughtCompletionTests` 16 methods carrying
both sides' work, `test_observation.py` 11 classes and 60 tests pinned at
4047, `test_score.py` 143 tests, the three `.gitleaksignore` fingerprints, and
this document.

The 250K campaign was not re-run, and nothing here asks for it.

### Booked, not done here

Once #106 merges, a **separate provenance-only** change replaces
`instructions.hashValue` with deterministic FNV-1a over the unchanged
instruction bytes (sections 14 and 15 record why). It carries no prompt,
grounding or quoted-example semantics, and must not be combined with them.

## 17. The provenance follow-up: a second deviation, on purpose

`Docs/Understanding/CANDIDATE47_RECONCILIATION.md` closes with #106. This
section records the one change that follows it, because it makes the identity
check say something new and a reader who is not expecting that will read it as
a regression.

**After this follow-up, `verify_frozen.py` names two files, not one:**

```
Candidate47 identity FAILED:
  SpeakIt/Interpretation/ModelInterpreter.swift   <- this follow-up
  SpeakIt/Repositories/SpeechRepair.swift         <- the reconciliation, #96
```

That is the intended state, not a drift. Both deviations are deliberate and
each has its own review.

### What changed, and what did not

`ModelInterpreter.instructionsFingerprint` was
`UInt32(truncatingIfNeeded: instructions.hashValue)`. Swift seeds `Hashable`
per process on purpose, so that value identified the process that wrote a run
record rather than the prompt that produced it. Section 15 has the measurement:
two CI runs over a byte-identical `ModelInterpreter.swift` printed `654b75ea`
and `10df9b6f`. A field that changes when nothing changed is not provenance,
and it is worse than an absent field because it reads like one.

It is now FNV-1a over the UTF-8 bytes of the same string.

**The instruction bytes are unchanged.** The `instructions` literal is
byte-identical to `main`: 36 lines, 1916 bytes, on both sides. None of
`e555f2a`'s grounding instruction, quoted-example rewrite or prompt semantics
entered with this — those remain held for the FM/device phase, exactly as
section 14 records. This change is the fingerprint and nothing else.

### Why it is pinned against published vectors

The self-check asserts the published FNV-1a 32-bit vectors — `""` to
`811c9dc5`, `"a"` to `e40c292c`, `"foobar"` to `bf9cf968` — rather than a
literal computed from our own prompt. A literal computed from the prompt would
have to be rewritten every time the prompt legitimately changed, and a check
that gets rewritten to match the code has stopped checking anything.

Those three vectors alone would still pass against a function that ignored its
argument, so two more assertions sit beside them: that the recorded fingerprint
is that function over `instructions`, and that appending one byte to the
instructions changes it. That is the falsifier for "the guard never fires".

### Where it runs

The check went into `Tools/InterpretationProbe/main.swift`'s `--selfcheck`
rather than into `SpeakItTests/`, for one reason worth recording: **the unit
suite is unreachable in CI on any Candidate47-based tree.** `corpus-gate.sh`
exits 1 against its hardcoded zero baseline, the `Unit tests` step carries no
`if:` and so inherits `success()`, and it is skipped. See the open item in
section 15.

**The selfcheck's coverage, stated exactly, because an earlier draft of this
section overstated it.** The probe steps carry `if: always()` (`ci.yml:424`,
`:428`, `:432`), but they live in the `language` job, which is
`if: github.event_name == 'workflow_dispatch'` (`ci.yml:338`). A step-level
`always()` protects against an *earlier step in the same job* failing; it does
nothing when the job never starts. On a push or a pull request the `language`
job is skipped outright — observable in any recent run's job list — so **these
assertions do not execute per pull request at all.**

What is true is narrower: **on a dispatch**, the `ios` job does run, the corpus
gate still reddens, `Unit tests` is still skipped behind it, and the selfcheck
is then the only place a Swift assertion on this line executes. That is the
claim. Read without the qualifier it sounds like per-PR coverage, which would
be a claim nothing recomputes, in its most ordinary form: true of one event
type, quoted as true generally. Caught in review rather than by a check, which
is the point — no instrument here distinguishes "skipped job" from "passing
job" at a glance.

**Not run here, and not claimable from this container:** no Swift compiles in
this environment (`download.swift.org` is refused by the proxy), so the
selfcheck assertions above have been written and not executed. They need
`./Tools/InterpretationProbe/build.sh && build/interpret --selfcheck` on a Mac,
or a `ci.yml` dispatch. No fingerprint value is quoted in this section for the
same reason: the engine that computes it cannot run here.

## 18. The squash moved the manifests to a new commit, and main went red

Recorded because it cost a red `main` and the cause is not obvious from the
failure.

#106 merged as a **squash**, `fc36db5`. A squash writes a new commit rather
than carrying the branch's, so Candidate47's three freeze manifests arrived on
`main` under a sha that no `.gitleaksignore` entry named. The entries were
pinned to `15bde21`, which the squash dropped from `main`'s history.

```
$ git merge-base --is-ancestor 15bde21 origin/main
NO
```

The scan on `main` (run 35231863437, `push` on `fc36db5`) then reported the
same three findings it had been passing on the branch, at the same files and
the same lines, under new fingerprints:

```
190 commits scanned.  leaks found: 3
  Docs/Understanding/Candidate47/baseline/freeze.json:generic-api-key:172
  Docs/Understanding/Candidate47/iteration-2/freeze.json:generic-api-key:173
  Docs/Understanding/Candidate47/iteration-4/freeze.json:generic-api-key:173
```

Nothing about the content changed. Section 11's argument still holds: these
are SHA-256 manifest lines whose key happens to contain "auth", the value was
recomputed and matches, and the manifests' bytes are the identity
`verify_frozen.py` checks, so editing them is not available.

**The fix is three more finding-level fingerprints, at `fc36db5`**, keeping the
`15bde21` three: that commit is still reachable from
`origin/codex/candidate47-closeout`, so an entry removed there would stop
covering a scan of that branch. Six entries, no broadened rule, no allowlisted
file, no ignored commit — the prohibitions in section 11 are intact.

**That fix is #108, not this branch** — merged as `2ef3d021`, after which
`main`'s own CI went green again. Another thread reached the same diagnosis and
had it up within minutes, with verification this container could not produce: `ci.yml`'s own invocation at the pinned gitleaks 8.30.1, before
and after, plus a planted `stripe-access-token` on line 173 of
`baseline/freeze.json` — beside an excused line, inside an excused file — still
reported. No gitleaks binary exists here, so the duplicate this branch briefly
carried was reverted in favour of the one that was actually run. Two fixes to
one file would only have collided at its tail.

**One thing from #108 worth keeping, because it nearly invalidated a probe.**
Its first plant used `AKIAIOSFODNN7EXAMPLE` and went undetected — that value is
in gitleaks' own default allowlist. **A plant the scanner cannot see reads
exactly like a scan that works.** Section 11's probe is not affected, and the
reason is worth naming rather than assumed: it ran a control (allowlist absent,
same plants, both detected) and its falsifier reported `aws-access-token` and
`stripe-access-token` as two leaks with exit 1. A canonical example key would
have been silent in both. The control is what made that legible, which is the
argument for running one every time.

**The general lesson, which is not about gitleaks.** A finding-level
fingerprint is content plus *location*, and a squash, rebase or amend changes
the location while leaving the content identical. So an exception that was
verified to be narrow can stop applying without anything it was protecting
against having changed. That is the same family as the rest of this
document's instrument lessons: **the exception is an instrument, and it can
fail silently in the direction of noise as easily as in the direction of
blindness.** Here it failed loudly, which is the good direction, and only
because the scan runs on pushes to `main`.

**Before deleting any of the six**, check both:

```
git merge-base --is-ancestor <sha> origin/main
git branch -r --contains <sha>
```

An ignore entry that matches nothing is invisible, not loud.

## 19. "The isolation guard passes" — which guard, and what the deleted rule would cost

Section 17 and #107 both report `test_interpretation_isolation.py` passing.
That is true and it is weaker than it sounds, so the qualification belongs
next to the claim rather than in somebody's memory.

**Which guard passes.** The reconciliation retained Candidate47's
`test_interpretation_isolation.py`, which has **two** rules: nothing in the
interpretation path may reach the network, and the deterministic half may not
import FoundationModels. Against `4b0262a` it is 135 lines where main's was
206 — 71 fewer — and `PROMPT_FILE` and `QUOTED_EXAMPLE` are gone with them.

Main's third rule, the grounding one, is **absent, not failing**. So is
`e555f2a`'s grounding sentence in the prompt. That is Calvin's instruction
working exactly as written — `ModelInterpreter.swift` and its isolation
behaviour were to be retained, and `e555f2a`'s semantics held for the FM/device
phase. What needs to be legible is the cost, because **an absent check on a
green tree is the state this document's own instrument lessons call hardest to
notice later.** A reader six weeks from now must not take main's green as
evidence that grounding protection holds. It is not enforced at all.

**What restoring rule 3 would cost: five sites, not two.** Measured by
extracting the deleted `prompt_examples` from `4b0262a` and running it against
`origin/main`'s `ModelInterpreter.swift`:

```
hits: 5
  :92   the instructions      "Sarah ... it" is owed by somebody else
  :93   the instructions      "Mum said I should call the dentist"
  :99   the instructions      "Ask Dana about Friday"
  :147  a @Guide description  'tomorrow'
  :190  a @Guide description  'never mind'
```

**Two is the wrong answer, and the way to get it is instructive.** Running only
the `QUOTED_EXAMPLE` regex gives the two `@Guide` hits, because that pattern
matches single-quoted spans. The three instruction lines use double quotes,
which inside a Swift multi-line string need no escape — and the rule's own code
carries a *second* branch for exactly that case:

```python
if where == "the instructions" and '"' in text:
```

Its comment says why: *"Two of the four leaking sites were this shape; a rule
that caught the other two and stopped would have read as protection."* So the
author anticipated this undercount and wrote the branch against it. Reading the
comment as a statement that the rule cannot see double-quoted examples, and
stopping at two, reproduces the very failure it warns about — which is worth
recording because two sessions did it independently today before the rule was
run.

**The falsifier, one command:**

```
git show 4b0262a:Tools/CorpusRunner/test_interpretation_isolation.py > old_guard.py
python3 -c "import old_guard,pathlib; print(len(old_guard.prompt_examples(
    pathlib.Path('SpeakIt/Interpretation/ModelInterpreter.swift'),'x')))"
```

On a branch that adds lines above them the `@Guide` numbers shift; on #107's
head they are 171 and 214. The count does not move.

### All five have device evidence behind them, not one

The prototype thread ran `a5e4d2a`'s guard against an archive of `origin/main`
independently and reached the same five, which is the confirmation this
section's count needed. It also supplied the part that changes what the five
mean.

The 46-capture `runon` device run produced **two** leak shapes, and both have
their cause present on main:

| observed on device | site |
|---|---|
| ten captures emitting a segment quoted as the bare word `tomorrow` | `:147`, the `carriedContext` `@Guide` that word sits in |
| captures emitting sentences lifted out of the instructions | `:92`, `:93`, `:99` |

So this is not one site with evidence and four without. Restoring rule 3 is a
five-site change, and the sites are not interchangeable with each other.

### Rejected: stripping the quotation marks

Recorded because it is attractive, it was proposed in good faith, and it is
the exact failure this repository keeps paying for.

The idea: rewrite the three instruction examples without quotation marks, and
the rule goes green at no cost to the prose. It fails on its own terms — the
rule's instruction branch tests `'"' in text`, so removing the quotes **turns
the check green while leaving the example sitting in the prompt**, which the
device run shows the model copies. That is a marker standing in for the
judgement it approximates, and it would leave us with a guard that passes
because the signal was removed rather than the problem.

Do not propose it again. If rule 3 comes back, the examples have to stop being
examples.

**Not a recommendation to restore it here.** Whether rule 3 and the grounding
sentence come back is the FM/device-phase decision Calvin parked, and section
14 holds the reasons. They are one change and the FM phase is where they land
together. This section supplies the price tag he would be deciding against:
five sites, three of them in the instructions, both observed leak shapes
covered.
