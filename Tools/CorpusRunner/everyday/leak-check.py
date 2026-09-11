"""Fails if a held-out capture also lives in a corpus that gets tuned against.

The everyday set is only worth keeping if nothing in it has been used to
develop a rule. That is easy to break by accident — an utterance gets quoted in
a finding, someone adds it to a dev set, and the benchmark quietly stops
measuring generalisation. This check makes the boundary mechanical instead of a
promise, and it is why `Tools/CorpusRunner/everyday/test_score.py` runs it.

It compares against every corpus that development touches: the gating semantic
corpus, the development sets, and the older held-out set (a capture shared with
that one is not contaminated, but it is a duplicate measurement, so it is
reported too).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
THRESHOLD = 0.70


def norm(text):
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def mine():
    out = {}
    for line in open(HERE / "everyday.tsv"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3 or parts[0] == "id" or line.startswith("#"):
            continue
        out[norm(parts[2])] = parts[0]
    return out


def others():
    sources = list((ROOT / "SpeakItTests").glob("SemanticCorpusData*.swift"))
    sources += list((ROOT / "Tools/CorpusRunner/devsets").glob("*.tsv"))
    sources.append(ROOT / "Tools/CorpusRunner/heldout/heldout.tsv")
    found = {}
    for path in sources:
        if not path.exists():
            continue
        text = path.read_text(errors="ignore")
        if path.suffix == ".tsv":
            candidates = [line.split("\t")[1] for line in text.splitlines()
                          if len(line.split("\t")) > 1 and not line.startswith("#")]
        else:
            candidates = re.findall(r'"([^"\\]{12,})"', text)
        for candidate in candidates:
            found.setdefault(norm(candidate), path.name)
    return found


def main():
    ours, theirs = mine(), others()
    exact = [(cid, utterance, theirs[utterance])
             for utterance, cid in ours.items() if utterance in theirs]

    near = []
    for utterance, cid in ours.items():
        tokens = set(utterance.split())
        if len(tokens) < 4:
            continue
        for other, source in theirs.items():
            other_tokens = set(other.split())
            if len(other_tokens) < 4:
                continue
            overlap = len(tokens & other_tokens) / len(tokens | other_tokens)
            if overlap >= THRESHOLD and utterance not in theirs:
                near.append((cid, round(overlap, 2), source, utterance, other))

    print(f"held-out captures        {len(ours)}")
    print(f"strings from tuned sets  {len(theirs)}")
    print(f"exact collisions         {len(exact)}")
    print(f"near duplicates (>={THRESHOLD})  {len(near)}")
    for cid, utterance, source in exact:
        print(f"  COLLISION  {cid}  also in {source}\n    {utterance}")
    for cid, overlap, source, utterance, other in sorted(near, key=lambda r: -r[1]):
        print(f"  NEAR  {cid}  j={overlap}  {source}\n    held out: {utterance}"
              f"\n    tuned:    {other}")
    if exact or near:
        print("\nleak check FAILED: a held-out capture overlaps a corpus that is "
              "developed against.", file=sys.stderr)
        return 1
    print("\nleak check ok: nothing held out appears in a tuned corpus.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
