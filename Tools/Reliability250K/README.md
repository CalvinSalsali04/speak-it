# Candidate47 campaign closure

The synthetic campaign is complete. The canonical account is
[the final report](../../Docs/Understanding/FINAL_RELIABILITY_REPORT.md).
The exact evaluator and report implementation are preserved here; their shared
`Tools/SpeechLabStressBank/run.py` dependency is tracked in the base history.

Run only the read-only identity check for closure/retrieval:

```sh
python3 Tools/Reliability250K/verify_frozen.py
python3 Tools/Reliability250K/verify_frozen.py --evidence-root '/Users/calvinwak/Documents/Speak It/output/reliability-250k'
```

The external immutable 250K bank and large raw artifacts remain in the original
ignored evidence directory; do not commit, regenerate, or alter the bank.
`Docs/Understanding/Candidate47/evidence-integrity.json` inventories verified
large files. Small source identities, summaries and closure records are tracked.
Historical absolute paths in copied JSON are provenance, not instructions to
switch source trees or run old candidates. Candidate20 and other rejected or
partial candidates are historical evidence only. No launcher is added here.

A future machine needs a byte-preserving copy of the ignored evidence directory
for raw-case comparison. The local source commit alone is sufficient to recover
Candidate47 production Swift source, but does not contain the external bank,
compiled probe, raw outputs, model weights, or device results.
