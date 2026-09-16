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
  divergent  the readings must NOT match — the mutation changed the meaning,
             so an identical answer is the defect and is what gets reported

A divergent family has three outcomes, not two, and the third is the one worth
reading. Every divergent family works by **adding words**, and a row title is
built from the person's words, so the title differs almost by construction. If
a title difference counted as the engine noticing, the test would be satisfied
by string propagation: "don't call Sarah" could still put an open errand on
Today, with "Don't" copied into the title, and this tool would say nothing. So
a pair whose title moved and whose consequence did not is reported in its own
column — `weakness` below — rather than folded into either verdict.
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
    """What the pair got wrong, or None.

    For strict and structure families that is a difference between the two
    readings. For a divergent family it is the absence of one: the mutation
    changed what the speaker means, so two identical readings say the engine
    cannot see the change. Which of the two readings is right is deliberately
    not asserted — that is what lets these run without labels.

    A divergent pair that moved only its row title is **not** reported here and
    is not a clean pass either; `weakness` has it. The two are mutually
    exclusive by construction, which `test_compare.py` asserts.
    """
    if base is None or mutated is None:
        return "missing probe output"
    if strength == "divergent":
        if _reading(base) == _reading(mutated):
            return f"unchanged reading: {_describe(base)}"
        return None
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


def weakness(base, mutated, strength):
    """A divergent pair that moved its row title and nothing the person acts on.

    Not a defect and not a pass. The added word reached the title, so it
    survived transcription and repair; but the destination, the row count, the
    operation and the dates are what the person actually acts on, and none of
    them moved. Speak It answering *don't call Sarah* with an open Today errand
    titled "Don't call Sarah" lands here, and that is the failure these families
    exist to catch — it must not read as the engine having noticed.

    Given its own column rather than merged into either verdict, because
    merging it would decide, silently and for every family at once, a question
    only the row in front of you can answer. Naming the bucket is what keeps
    the instrument from collapsing into one number.
    """
    if strength != "divergent" or base is None or mutated is None:
        return None
    if _consequence(base) != _consequence(mutated):
        return None
    if base["titles"] == mutated["titles"]:
        # Nothing moved at all. That is blindness, and `disagreement` reports
        # it; returning it here too would count one pair twice.
        return None
    return f"title-only divergence: {_describe(base)}"


def _consequence(block):
    """Everything the person acts on. Deliberately not the title.

    A title is what the capture is called; this is what it does.
    """
    return (
        block["routes"], block["rows"], block["operation"],
        block["due"], block["remind"],
    )


def _reading(block):
    """Everything an engine can say about a capture, as one comparable value.

    Title is included on purpose, and it is why `disagreement` alone would be
    too quiet: a pair matching on every one of these has produced *literally*
    the same answer, which is the strongest claim this tool can make. A pair
    that matches on all but the title is the weaker finding `weakness` reports.
    """
    return (
        block["routes"], block["rows"], block["operation"],
        block["due"], block["remind"], block["titles"],
    )


def _describe(block):
    where = "/".join(block["routes"]) or "nothing"
    titles = " | ".join(block["titles"]) or "no rows"
    return f"{where}, {block['rows']} row(s), {titles}"


def main():
    if len(sys.argv) < 3:
        print("usage: compare.py <mutations.tsv> <probe-output> [--verbose]", file=sys.stderr)
        return 2
    pairs_path, probe_path = sys.argv[1], sys.argv[2]
    verbose = "--verbose" in sys.argv

    blocks = read_blocks(probe_path)
    per_family = defaultdict(
        lambda: {"pairs": 0, "disagree": 0, "weak": 0, "examples": [], "weak_examples": []}
    )

    with open(pairs_path) as handle:
        lines = handle.readlines()
    for line in lines:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 4 or parts[0] == "base":
            continue
        base_text, mutated_text, family, strength = parts[:4]
        stat = per_family[family]
        stat["pairs"] += 1
        base_block, mutated_block = blocks.get(base_text), blocks.get(mutated_text)
        found = disagreement(base_block, mutated_block, strength)
        if found:
            stat["disagree"] += 1
            stat["examples"].append((base_text, mutated_text, found))
        thin = weakness(base_block, mutated_block, strength)
        if thin:
            stat["weak"] += 1
            stat["weak_examples"].append((base_text, mutated_text, thin))

    total_pairs = sum(s["pairs"] for s in per_family.values())
    total_bad = sum(s["disagree"] for s in per_family.values())
    total_weak = sum(s["weak"] for s in per_family.values())

    print()
    print("MUTATION INVARIANCE — consistency, not accuracy")
    print("=" * 72)
    print(f"{'family':<16}{'pairs':>8}{'disagreed':>12}{'rate':>10}{'title-only':>13}")
    print("-" * 72)
    for family in sorted(per_family, key=lambda f: -per_family[f]["disagree"]):
        stat = per_family[family]
        rate = 100 * stat["disagree"] / max(stat["pairs"], 1)
        print(f"{family:<16}{stat['pairs']:>8}{stat['disagree']:>12}"
              f"{rate:>9.1f}%{stat['weak']:>13}")
    print("-" * 72)
    print(f"{'TOTAL':<16}{total_pairs:>8}{total_bad:>12}"
          f"{100 * total_bad / max(total_pairs, 1):>9.1f}%{total_weak:>13}")
    print("=" * 72)
    print("  Each disagreement means one of the two answers is wrong. Which one")
    print("  is a question for a person; that this pair cannot both be right is")
    print("  not. Agreement is not evidence of correctness.")
    if total_weak:
        print()
        print("  title-only: a meaning-changing mutation that moved the row title")
        print("  and nothing the person acts on — same destination, same rows,")
        print("  same operation, same dates. The words reached the title; read")
        print("  these before treating the family's zero as understanding.")

    if verbose:
        for family in sorted(per_family):
            stat = per_family[family]
            for base_text, mutated_text, found in stat["examples"] + stat["weak_examples"]:
                print(f"\n[{family}] {found}")
                print(f"  base    {base_text}")
                print(f"  mutated {mutated_text}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
