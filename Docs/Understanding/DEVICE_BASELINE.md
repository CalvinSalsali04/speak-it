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

## Why the verifier is not in CI

It pins a tree, so it **must** fail the moment `main` legitimately moves. Wiring
it into CI would either block all future Swift work or, worse, invite someone to
regenerate the manifest to get green — which is how a baseline stops being one.
`verify_frozen.py` is out of CI for the same reason. Run it against a checkout
of the baseline, which is the only tree it describes.
