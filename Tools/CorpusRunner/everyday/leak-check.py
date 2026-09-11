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

# Every set that must stay unseen. Each is checked against the tuned corpora
# and against the other sealed sets: an overlap with another sealed set is not
# contamination, but it is the same capture measured twice under two names.
SEALED = [
    HERE / "everyday.tsv",
    ROOT / "Tools/CorpusRunner/adversarial/adversarial.tsv",
]


def norm(text):
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def mine(path):
    out = {}
    for line in open(path):
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3 or parts[0] == "id" or line.startswith("#"):
            continue
        out[norm(parts[2])] = parts[0]
    return out


def utterance_column(lines):
    """Finds the column a corpus file keeps its utterances in.

    Corpora in this repository do not agree on layout: `heldout.tsv` and the
    development sets put the utterance second, `everyday.tsv` puts it third,
    and `heldout.tsv` writes its header inside a comment. Hard-coding a column
    is how this check silently starts comparing the wrong field and passing for
    the wrong reason — which is worse than failing, because a leak check that
    cannot fail reads as proof. So the header is read instead.
    """
    for line in lines:
        fields = [f.strip().lower() for f in line.lstrip("#").strip().split("\t")]
        if "utterance" in fields:
            return fields.index("utterance")
    return None


def harvest(path):
    """Every utterance in one corpus file."""
    text = path.read_text(errors="ignore")
    if path.suffix != ".tsv":
        # Swift corpus sources: any string literal long enough to be a capture.
        return re.findall(r'"([^"\\]{12,})"', text)

    lines = text.splitlines()
    column = utterance_column(lines)
    if column is None:
        raise SystemExit(
            f"leak check: {path.name} has no column headed 'utterance', so the "
            f"capture to compare cannot be identified. Add the header rather "
            f"than letting this file go unchecked.")
    out = []
    for line in lines:
        if line.startswith("#") or not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) <= column or fields[column].strip().lower() == "utterance":
            continue
        out.append(fields[column])
    return out


def others(exclude):
    sources = list((ROOT / "SpeakItTests").glob("SemanticCorpusData*.swift"))
    sources += list((ROOT / "Tools/CorpusRunner/devsets").glob("*.tsv"))
    sources.append(ROOT / "Tools/CorpusRunner/heldout/heldout.tsv")
    sources += [p for p in SEALED if p != exclude]
    found = {}
    for path in sources:
        if not path.exists():
            continue
        for candidate in harvest(path):
            found.setdefault(norm(candidate), path.name)
    return found


def main():
    """Checks every sealed set, so adding one cannot mean forgetting to check it."""
    failed = 0
    for path in SEALED:
        if not path.exists():
            raise SystemExit(f"leak check: {path} is listed as sealed but missing")
        failed |= check(path)
    return failed


def check(path):
    ours, theirs = mine(path), others(path)
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

    print(f"=== {path.parent.name}/{path.name}")
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
