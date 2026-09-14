#!/usr/bin/env python3
"""Per-connector rates for the consequence set, which the family table cannot give.

The family column encodes split-versus-whole and spoken-versus-written, so the
shared scorer has no place to put the connector. The first run of this set
therefore reported that 22 of 32 split captures still read as one thought after
#57, and could not say which of the eight connectors those 22 sit under. That
is the difference between "one phenomenon, eight surface forms, and we fixed
one" as an inference and as a measurement.

The block is carried by the id, because the set was written in a fixed rotation
and sealed: `CQ01`-`CQ40` in eight blocks of five, then `CQ41`-`CQ56` adding two
per block in spoken register. Nothing here edits the set to add a column.

Rates only, and no capture text on any path, including the error paths, where a
row is named by its id. A finer-grained number is still a number.
"""
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

#: The rotation, in order. Position is the block number.
CONNECTORS = ("and", "so", "which means", ",", "then", "that means",
              "because of that", "none")

#: Rows written in the no-connector block that contain a connector WORD used as
#: something else. Word presence is not connector use, and this project's most
#: repeated bug is a marker standing in for the judgement it approximates. So
#: the check stays strict and the exceptions cost an edit and a sentence.
ACKNOWLEDGED = {
    "CQ40": "`then` is the object of `before`, not a joiner: \"before then\".",
    "CQ55": "opens with a bare `so` as a discourse marker, one of the two rows "
            "written to carry that use; its `then` is the CQ40 one.",
}

ID = re.compile(r"^(CQ\d+)\t")
BLOCK_SIZE, SPOKEN_FIRST, SPOKEN_PER_BLOCK = 5, 41, 2


def block_of(cid):
    """Block index for a capture id, or None if it falls outside the rotation."""
    n = int(cid[2:])
    if 1 <= n < SPOKEN_FIRST:
        return (n - 1) // BLOCK_SIZE
    index = (n - SPOKEN_FIRST) // SPOKEN_PER_BLOCK
    return index if 0 <= index < len(CONNECTORS) else None


def carries(text, connector):
    """Whether the connector's surface form appears, on word boundaries."""
    if connector == ",":
        return "," in text
    return bool(re.search(rf"(?<!\w){re.escape(connector)}(?!\w)", text.lower()))


def labels(path):
    rows = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not ID.match(line):
            continue
        cells = line.split("\t")
        if len(cells) >= 5:
            rows.append((cells[0], cells[1], cells[4].strip()))
    return rows


def probe(path):
    seen = {}
    for chunk in re.split(r'\n(?=── ")', Path(path).read_text(encoding="utf-8")):
        m = re.match(r'── "(.*?)"', chunk)
        if m:
            seen[m.group(1)] = {
                "rows": len(re.findall(r"row title:", chunk)),
                "operation": bool(re.search(r"operation:", chunk)),
            }
    return seen


def rotation(rows):
    """(per-block hits, base rate across every row, unexplained no-connector ids).

    The base rate is printed beside the hits on purpose. `,` appears in 21 of
    the 56 captures, so "7 of 7 carry a comma" is very nearly true of any seven
    rows and verifies almost nothing. A check that passes for everything reads
    exactly like a check that passed.
    """
    hits, base, unexplained = Counter(), Counter(), []
    for cid, text, _ in rows:
        index = block_of(cid)
        for position, connector in enumerate(CONNECTORS):
            if connector == "none":
                continue
            present = carries(text, connector)
            base[connector] += present
            if present and position == index:
                hits[index] += 1
            if present and CONNECTORS[index] == "none" and cid not in ACKNOWLEDGED:
                unexplained.append((cid, connector))
    return hits, base, unexplained


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        print("usage: block-report.py <consequence.tsv> <probe output>")
        return 2

    rows = labels(argv[1])
    if not rows:
        print("block-report: no CQ rows read from", Path(argv[1]).name,
              "\n  Every rate below would be computed over nothing, and a "
              "report over nothing prints the same clean table as a perfect "
              "run.")
        return 2

    stray = sorted(cid for cid, _, _ in rows if block_of(cid) is None)
    if stray:
        print("block-report: outside the rotation: " + ", ".join(stray)
              + "\n  The rotation is what makes a per-connector rate mean "
                "anything, so an unplaced row is a failure, not a footnote.")
        return 2

    seen = probe(argv[2])
    hits, base, unexplained = rotation(rows)

    scored = defaultdict(Counter)
    missing, ranged = [], []
    for cid, text, want in rows:
        index = block_of(cid)
        got = seen.get(text)
        if got is None:
            missing.append(cid)
            continue
        if got["operation"]:
            scored[index]["operation"] += 1
            continue
        if "-" in want:
            ranged.append(cid)
            continue
        half = "whole" if want.startswith("1") else "split"
        scored[index][half] += 1
        if got["rows"] == int(re.match(r"^(\d+)", want).group(1)):
            scored[index][half + "_ok"] += 1

    width = max(len(c) for c in CONNECTORS) + 2
    print()
    print(f"CONSEQUENCE, BY CONNECTOR BLOCK — {len(rows)} captures, "
          f"{len(rows) - len(missing)} scored")
    print("=" * (width + 46))
    print(f"{'connector':<{width}}{'n':>3}{'must split':>18}{'must stay whole':>20}")
    print("-" * (width + 46))

    for index, connector in enumerate(CONNECTORS):
        counter = scored[index]
        total = counter["split"] + counter["whole"]
        print(f"{connector:<{width}}{total:>3}"
              f"{cell(counter['split_ok'], counter['split']):>18}"
              f"{cell(counter['whole_ok'], counter['whole']):>20}"
              f"{verdict(counter)}")

    print("-" * (width + 46))
    if any(verdict(scored[i]) for i in range(len(CONNECTORS))):
        # Printed only when a block earns it. An explanation that appears
        # whatever the numbers say is one a reader learns to skip, and it also
        # makes the verdict unsearchable -- which is how this project's first
        # version of the same section got its own tests wrong, and how this
        # one did too, on the first run of the suite below.
        print("  Read the two columns together and never the right one alone.")
        print("  A parser that never splits scores every whole row and no")
        print("  split row, so a block marked NOT INFORMATIVE is telling you")
        print("  the mechanism is absent there rather than correct. The mark")
        print("  clears by itself when that block's split column leaves zero.")
    else:
        print("  No block is carried by its whole rows alone: every one of")
        print("  them splits something, so both columns are worth reading.")

    if missing:
        print()
        print(f"  {len(missing)} capture(s) had no probe result: "
              + ", ".join(missing))

    if ranged:
        # The shared scorer grew a range-aware count; this report has not, and
        # taking the lower bound quietly would put a capture in the wrong half
        # of the table and move a block's rate. Named rather than absorbed.
        print()
        print(f"  {len(ranged)} capture(s) carry a range label and are NOT in "
              f"the table above: " + ", ".join(ranged))
        print("  This report is strict-only. A range means the author recorded "
              "that")
        print("  two readings are defensible, which is not a thing `must split` "
              "or")
        print("  `must stay whole` has a column for.")

    print()
    print("ROTATION — the claim that each block uses its own connector")
    print("-" * (width + 46))
    for index, connector in enumerate(CONNECTORS):
        if connector == "none":
            continue
        inblock = sum(1 for cid, _, _ in rows if block_of(cid) == index)
        share = f"{base[connector]}/{len(rows)}"
        note = "  (weak: common across the set)" if base[connector] > len(rows) / 3 else ""
        print(f"  {connector:<{width}}{hits[index]:>2}/{inblock}"
              f"   appears in {share} overall{note}")
    print(f"  {'none':<{width}} checked by absence, below")
    for cid, reason in sorted(ACKNOWLEDGED.items()):
        print(f"    {cid} carries a connector word and is recorded: {reason}")
    print("-" * (width + 46))
    print("  A connector present in a third of the whole set says little by")
    print("  being present in one block, so each hit count is printed beside")
    print("  its base rate rather than on its own.")

    if unexplained:
        print()
        for cid, connector in unexplained:
            print(f"  FAIL  {cid} is in the no-connector block and contains "
                  f"`{connector}`, with no recorded reason. Either it is "
                  f"mis-blocked, or the word is doing something else and that "
                  f"belongs in ACKNOWLEDGED with a sentence.")
        return 1
    return 0


def cell(ok, total):
    if not total:
        return "—"
    return f"{ok}/{total} ({100 * ok / total:.0f}%)"


def verdict(counter):
    vacuous = (counter["whole"] and counter["whole_ok"] == counter["whole"]
               and counter["split"] and not counter["split_ok"])
    return "  NOT INFORMATIVE" if vacuous else ""


if __name__ == "__main__":
    sys.exit(main(sys.argv))
