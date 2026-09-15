"""Reports where a mutation changed Speak It's answer.

Reads one probe transcript containing both the base utterances and their
mutations, and prints, per mutation family, how often the pair disagreed.

WHAT THIS MEASURES, AND WHAT IT DOES NOT

It measures **consistency**. A disagreement proves one of the two answers is
wrong without saying which, which is why it needs no labels. Agreement proves
only that the engine treats the pair alike: a capture it gets wrong identically
under every mutation is counted clean here. Nothing this prints may be quoted
as accuracy, and a run with no disagreements is not evidence the product works.

The two strengths come from mutate.py:

  strict     every field must match
  structure  destination and row count must match; titles may differ
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict


def read_blocks(path):
    """Probe output, keyed by the utterance it was produced for.

    The block shape is the one Tools/CorpusRunner/heldout/score.py reads, so
    the two tools stay readable against the same probe.
    """
    blocks = {}
    with open(path) as handle:
        text = handle.read()
    for block in re.split(r'\n(?=── ")', text):
        m = re.match(r'── "(.*?)"', block)
        if not m:
            continue
        blocks[m.group(1)] = {
            "routes": tuple(re.findall(r"route:\s+(\S+)", block)),
            "titles": tuple(re.findall(r"row title:\s*(.*)", block)),
            "rows": len(re.findall(r"row title:", block)),
            "operation": bool(re.search(r"operation:", block)),
            "due": tuple(re.findall(r"due:\s+(\S+)", block)),
            "remind": tuple(re.findall(r"remind:\s+(\S+)", block)),
        }
    return blocks


def disagreement(base, mutated, strength):
    """What differs between a base reading and its mutation, or None."""
    if base is None or mutated is None:
        return "missing probe output"
    if base["routes"] != mutated["routes"]:
        return f"destination {'/'.join(base['routes']) or 'nothing'} → {'/'.join(mutated['routes']) or 'nothing'}"
    if base["rows"] != mutated["rows"]:
        return f"row count {base['rows']} → {mutated['rows']}"
    if base["operation"] != mutated["operation"]:
        return f"operation {base['operation']} → {mutated['operation']}"
    if strength == "structure":
        return None
    if base["due"] != mutated["due"]:
        return f"due {'/'.join(base['due'])} → {'/'.join(mutated['due'])}"
    if base["remind"] != mutated["remind"]:
        return f"remind {'/'.join(base['remind'])} → {'/'.join(mutated['remind'])}"
    if base["titles"] != mutated["titles"]:
        return f"title {' | '.join(base['titles'])} → {' | '.join(mutated['titles'])}"
    return None


def main():
    if len(sys.argv) < 3:
        print("usage: compare.py <mutations.tsv> <probe-output> [--verbose]", file=sys.stderr)
        return 2
    pairs_path, probe_path = sys.argv[1], sys.argv[2]
    verbose = "--verbose" in sys.argv

    blocks = read_blocks(probe_path)
    per_family = defaultdict(lambda: {"pairs": 0, "disagree": 0, "examples": []})

    with open(pairs_path) as handle:
        lines = handle.readlines()
    for line in lines:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 4 or parts[0] == "base":
            continue
        base_text, mutated_text, family, strength = parts[:4]
        stat = per_family[family]
        stat["pairs"] += 1
        found = disagreement(blocks.get(base_text), blocks.get(mutated_text), strength)
        if found:
            stat["disagree"] += 1
            stat["examples"].append((base_text, mutated_text, found))

    total_pairs = sum(s["pairs"] for s in per_family.values())
    total_bad = sum(s["disagree"] for s in per_family.values())

    print()
    print("MUTATION INVARIANCE — consistency, not accuracy")
    print("=" * 72)
    print(f"{'family':<16}{'pairs':>8}{'disagreed':>12}{'rate':>10}")
    print("-" * 72)
    for family in sorted(per_family, key=lambda f: -per_family[f]["disagree"]):
        stat = per_family[family]
        rate = 100 * stat["disagree"] / max(stat["pairs"], 1)
        print(f"{family:<16}{stat['pairs']:>8}{stat['disagree']:>12}{rate:>9.1f}%")
    print("-" * 72)
    print(f"{'TOTAL':<16}{total_pairs:>8}{total_bad:>12}"
          f"{100 * total_bad / max(total_pairs, 1):>9.1f}%")
    print("=" * 72)
    print("  Each disagreement means one of the two answers is wrong. Which one")
    print("  is a question for a person; that this pair cannot both be right is")
    print("  not. Agreement is not evidence of correctness.")

    if verbose:
        for family in sorted(per_family):
            for base_text, mutated_text, found in per_family[family]["examples"]:
                print(f"\n[{family}] {found}")
                print(f"  base    {base_text}")
                print(f"  mutated {mutated_text}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
