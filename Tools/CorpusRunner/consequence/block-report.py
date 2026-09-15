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

Rates only. No capture text on any path, including the error paths, where a row
is named by its id -- and that claim is enforced rather than asserted for
everything derived from the set, and bounded by shape for the two reasons
recorded by hand below, which are the only text here a guard cannot compare
against the set. A finer-grained number is still a number.
"""
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

#: The rotation, in order. Position is the block number.
CONNECTORS = ("and", "so", "which means", ",", "then", "that means",
              "because of that", "none")

#: Words a reason may name, because every one of them is either already public
#: in CONNECTORS or a grammatical term rather than anything a capture is about.
#: A word not on this list costs an edit and a sentence, which is the point: it
#: is how an ordinary content word from a capture is stopped from arriving one
#: reason at a time.
ROLE_VOCABULARY = frozenset({"and", "so", "then", "before", "after", "because",
                            "which", "that", "means", "no"})

#: Rows written in the no-connector block that contain a connector WORD used as
#: something else. Word presence is not connector use, and this project's most
#: repeated bug is a marker standing in for the judgement it approximates. So
#: the check stays strict and the exceptions cost an edit and a sentence.
#:
#: These reasons are the one thing in this file no downstream guard can reach.
#: Everything else printed here is derived from ids and from probe output, and a
#: test can catch a capture echoed back out of its own input; these are written
#: by hand from the sealed set and compiled into the source, so a test that
#: refuses to read the set cannot compare them against it. One of them quoted
#: two words of its capture until 2026-09-14.
#:
#: What IS checkable without the set is the shape. A reason names a grammatical
#: role, so it never needs a quoted span: no double quotes at all, and a
#: backticked span must be a single token drawn from ROLE_VOCABULARY above.
#: `test_block_report.py` enforces that. It bounds the shape rather than the
#: content, which is why the vocabulary is closed and not merely single-word.
ACKNOWLEDGED = {
    "CQ40": "`then` is the object of the preposition `before`, not a joiner.",
    "CQ55": "opens with a bare `so` as a discourse marker, one of the two rows "
            "written to carry that use; its `then` is the CQ40 one.",
}


def quotation_in(reason):
    """The reason a recorded exception is malformed, or None if it is fine.

    Its own function with its own fixtures in both directions, because a rule
    about what may not appear in some text cannot be checked by that text
    staying silent: a matcher that stopped matching passes a no-quotes
    assertion on anything at all.
    """
    if '"' in reason:
        return "contains a double-quoted span, which is how a fragment of a capture gets printed"
    for span in re.findall(r"`([^`]*)`", reason):
        if not span:
            return "has an empty backtick pair"
        if " " in span:
            return f"backticks the multi-word span {span!r}; name the role rather than quoting the words"
        if span.lower() not in ROLE_VOCABULARY:
            return (f"backticks `{span}`, which is not in ROLE_VOCABULARY; "
                    f"either it is a grammatical term worth adding there with a "
                    f"sentence, or it is a word out of a capture")
    return None

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
