# The canonical device baseline

The exact tree all real-device evidence is gathered from. Authorised by Calvin
on 2026-09-17, after PR #107 merged.

**It is not Candidate47, and it does not replace Candidate47.**
`Docs/Understanding/Candidate47/` and its frozen manifest are untouched and stay
authoritative for what Candidate47 was. This is a second, separate receipt for a
second, separate tree.

| | |
|---|---|
| Receipt | `Docs/Understanding/DeviceBaseline/RECEIPT.json` |
| Manifest | `Docs/Understanding/DeviceBaseline/device-baseline-source.json` (68 Swift files) |
| Verifier | `Tools/Reliability250K/verify_device_baseline.py` |
| Swift tree established by | `413a68f`, the squash merge of #107 |

```
$ python3 Tools/Reliability250K/verify_device_baseline.py
Device baseline identity PASS: 68 Swift files, 66 byte-identical to Candidate47,
2 declared deviation(s). No production execution.
```

## The two intentional deviations

Exactly two production Swift files differ from Candidate47. The inventory is
identical, 66 of 68 files are byte-identical, and **the verifier fails by name
if a third ever appears.**

| file | kind | why |
|---|---|---|
| `SpeakIt/Repositories/SpeechRepair.swift` | behavioural | #106 carried main's #96 contemplation-hedge fix onto Candidate47's rewritten `DisfluencyFilter`. Reviewed independently at `d02e30c`. |
| `SpeakIt/Interpretation/ModelInterpreter.swift` | **provenance only** | #107 replaced Swift's per-process-seeded `hashValue` with FNV-1a over the **unchanged** instruction bytes. |

The prompt is untouched, and the proof needs no measurement: the `instructions`
literal is absent from #107's diff. That file has one hunk,
`@@ -105,10 +105,34 @@`, and line 105 is the literal's closing delimiter
arriving as *context*.

## What is deliberately held out

**Foundation Models semantics.** `e555f2a`'s grounding instruction, its
quoted-example rewrite, and the isolation guard's third rule are **not** here.
The prompt text is Candidate47's.

**So `test_interpretation_isolation.py` green means less than it looks.** This
tree carries the **two-rule** guard: nothing in the interpretation path reaches
the network, and the deterministic half does not import FoundationModels. The
grounding rule is **absent, not failing**. Nobody should read this baseline's
green as evidence that grounding protection holds — it is not enforced at all.

Restoring that rule costs **five** sites, measured rather than estimated:
`:92`, `:93`, `:99` in the instructions and `:147`, `:190` in `@Guide`
descriptions. Confirmed independently by two threads. The reconciliation record
(`CANDIDATE47_RECONCILIATION.md` section 19) carries the falsifier and records
one rejected shortcut: stripping the quotation marks would turn the check green
while leaving the example in the prompt.

## How to use it

1. Take a **fresh checkout** of the commit on `main` carrying this file.
2. Run the verifier. A PASS describes *that checkout*, whichever commit it
   stands on, because it hashes the Swift tree directly.
3. Build device evidence only from that tree, and record the commit beside every
   capture.

Evidence from any other tree is not evidence about this baseline. The final
report records the main workspace at `/Users/calvinwak/Documents/Speak It` as
based on `2932272` — neither Candidate47 nor this — and a capture attributed to
the wrong tree is worse than no capture.

## Two things this receipt does not claim

**Ancestry is not identity here.** Candidate47's own commit `15bde21` is **not**
an ancestor of `main`: #106 landed as a squash. Identity rests entirely on the
per-file hashes, never on `git merge-base`.

**The Swift has never been compiled from this tree.** No Swift toolchain exists
in the container this was assembled in. `RECEIPT.json` lists what is unverified
in full — the corpus gate, the unit suite, the release build, the `--selfcheck`
assertions, and every device-only behaviour. That list is the point of the
device phase, and it should shrink by measurement, not by editing.

## The reference the deviations are measured against

Every deviation count here is measured against Candidate47's own manifest,
`Docs/Understanding/Candidate47/development/candidate47-source.json`. Edit that
file and a real deviation disappears while every other check still passes. The
defects thread raised this while grading #109 as a limit that could not be
closed from inside, with Calvin's instruction not to touch the directory as the
only thing holding it.

It could be closed, and the reason is more useful than the fix. The manifest's
SHA-256 was already recorded twice when Candidate47 was frozen —
`f46a0a6e…`, in `evidence-integrity.json` and again in `FROZEN_CANDIDATE.json`.
**Nothing recomputed it.** `verify_frozen.py` consults `artifacts_sha256` only
when given `--evidence-root`, and then resolves those paths against the
preserved output directory rather than against the manifest it has just read as
its reference. The value was present, correct, and unchecked — which from the
outside reads exactly like a check.

The verifier now recomputes it against **both** recorded copies and requires
them to agree, so a single edit anywhere in that set fails by name. Both are
used rather than one copied into the receipt: a fourth copy of the same claim
would be a fourth thing to drift, and Candidate47's files are not written.

```
edited the manifest to hide a deviation   red: both records disagree
edited only evidence-integrity.json       red: that record disagrees
edited the manifest AND covered it in
  evidence-integrity.json                 red: FROZEN_CANDIDATE.json still disagrees
edited the frozen manifest so it agreed
  with the baseline on SpeechRepair,
  erasing a declared deviation            red: declared deviation is absent
```

The last is the sharpest, and it is the evaluation thread's, run while grading
#110 rather than taken from this list.

**What this buys, measured rather than characterised.** The defects thread
argued the residue should read *accidental*, since all three Candidate47 files
sit in one directory and a deliberate editor has them under hand. Running it
says the checks are layered more than either of us assumed: covering both hash
records still fails, because `RECEIPT.json` quotes the Candidate47 hash from
the other directory.

Hiding one deviation completely takes **four coordinated edits across two
directories** — the frozen manifest, both records pinning its hash, and the
receipt's own declaration. At that point both modes return exit 0 and the only
surviving tell is the printed count dropping from 2 deviations to 1, which a
reader notices and no check does.

So: reliable against the accidental and partial edit, which is the realistic
case; defeated by a deliberate four-file change, which is not silent in any
useful sense. Stating it as "raises the cost of a silent change" would invite a
reader to infer a resistance to tampering that nothing here provides.

## What runs in CI, and what does not

The verifier does two separable things, and only one of them pins a tree.

**The full run is not in CI.** Its first check walks `SpeakIt/` and hashes every
file, so it **must** fail the moment `main` legitimately moves. Wiring that into
CI would either block all future Swift work or, worse, invite someone to
regenerate the manifest to get green — which is how a baseline stops being one.
`verify_frozen.py` is out of CI for the same reason. Run it against a checkout
of the baseline, which is the only tree it describes.

**`--receipt-only` is in CI**, in the Linux language-tooling job, on every pull
request. It compares the baseline manifest with Candidate47's and the receipt
with both. Those are three frozen files; it reads no working tree, so it cannot
redden when `main` moves. It exists for the one mistake that is otherwise
silent: somebody lands a third deviation, regenerates the manifest so the
content check passes, and leaves the receipt claiming two.

The earlier blanket claim here — that the verifier pins a tree and so cannot be
in CI — was true of the first check and false of the other two. The defects
thread caught it while grading #109 and the correction is theirs.

**What a receipt-only PASS does not say.** It says the three documents agree
with each other. It says nothing about whether any checkout matches them, so a
third Swift deviation landed *without* regenerating the manifest leaves it
green. Only the full run answers that, and only against the baseline checkout.
The step is named `The device-baseline receipt agrees with its manifests` so the
green cannot be read as more than it is.

Both the reachability and the two failure directions were run rather than
argued:

```
planted a Swift edit          full run red, --receipt-only green   (no false red)
deleted a Swift file          full run red, --receipt-only green   (reads no tree)
third deviation + regenerated
  manifest, receipt at two    --receipt-only red: UNDECLARED deviation
stale hash in the receipt     --receipt-only red: quotes a stale baseline hash
receipt declares a deviation
  that is not one             --receipt-only red: declared deviation is absent
```

A manifest edited on its own matches neither the `ios` nor the old `prose` path
filter, so the check would not have run on exactly the pull request it exists
for. **All three of its inputs need a glob, and that took two passes to get
right.** The first added `Docs/Understanding/DeviceBaseline/**` and
`Tools/Reliability250K/**` and left Candidate47's frozen manifest uncovered;
the evaluation thread measured that with this repository's own `as_regex`, and
by then the reference check had added two more uncovered reads. Three files,
not one. `Docs/Understanding/Candidate47/**` now covers them all — the whole
directory, since everything under it is frozen and a glob wider than what the
check reads costs one cheap Linux job.

All of these sit in `prose`, which gates the Linux job only and bills no Mac.

The guard that should have caught this could not: `test_score.py`'s
`test_every_markdown_file_the_check_reads_starts_the_job` considers Markdown
only, and these checks read JSON. A version asking whether every file *any*
gated check reads matches some glob would have failed on the first pass here.
That is its own change, not this one.
