#!/usr/bin/env python3
"""Checks a candidate choice-family set against the balance rules in
`Docs/CHOICE_FAMILY_EVALUATION.md` §6, before anything is scored against it.

It checks B1, B2 and B3. **It cannot check B4 or B5**, and it says so on every
run rather than printing a clean bill over five requirements it verified three
of. A checker that reports "balanced" while two thirds of the requirement is a
human judgement nobody made is the defect this project keeps finding in its own
instruments.

Row tags carry what the file format has no column for:

    choice-<slot>-<resolution>

    slot        time | person | place | object | clause
    resolution  r1 (bare restatement) | r2 (marked selection) | r3 (elimination)
                open (no resolution — the J2 rows)
                inferred (R4 — collected, tagged, and never in the family rate)

The tags are claims, not evidence, so where a tag can be checked against the
text it is: an `r1` row is asserted to carry no resolution marker, and a row
whose text says otherwise fails rather than being believed.
"""
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import corpus_paths

SLOTS = ("time", "person", "place", "object", "clause")
RESOLUTIONS = ("r1", "r2", "r3", "open", "inferred")
IN_FAMILY = ("r1", "r2", "r3", "open")
RESOLVED = ("r1", "r2", "r3")

#: Words a speaker uses to select one alternative over another. The list exists
#: to make B1 checkable and to generate B2's decoys; it is deliberately NOT the
#: definition of a resolution, which §2 states in terms of what the words do.
#: Anything here can appear meaning something else entirely — "no rush",
#: "better call her back", "actually" meaning *in fact* — and that is the point.
MARKERS = (
    "actually", "no", "better", "i think", "rather", "instead", "definitely",
    "let's say", "lets say", "scratch that", "on second thought",
    "on second thoughts", "i'll go with", "ill go with", "make it", "forget",
)

#: A literal that must be found by the same matcher the checks use, before any
#: B1 result is reported. A matcher that quietly stops matching reports every
#: row as marker-free, which reads exactly like a well-balanced set.
SELF_CHECK = "actually no take the bus"

TAG = re.compile(r"^choice-([a-z]+)-([a-z0-9]+)$")
ALLOW = re.compile(r"^#\s*allow-marker\s+(\S+)\s+(.+?)\s*$")


def markers_in(text):
    """Every marker present in `text`, matched on word boundaries.

    Substring matching is what turned "16 40" into a time and read `actually`
    inside `actual`; the boundaries are the whole reason this is a function
    with a fixture rather than an `in` test written inline.
    """
    low = text.lower()
    found = []
    for marker in MARKERS:
        if re.search(rf"(?<!\w){re.escape(marker)}(?!\w)", low):
            found.append(marker)
    return found


def matcher_is_working():
    return bool(markers_in(SELF_CHECK))


def read(path):
    """(rows, allowances). Rows are (id, utterance, slot, resolution)."""
    rows, allowances = [], {}
    for line in Path(path).read_text().splitlines():
        allowed = ALLOW.match(line)
        if allowed:
            allowances[allowed.group(1)] = allowed.group(2)
            continue
        if line.startswith("#") or not line.strip():
            continue
        cells = line.split("\t")
        if len(cells) < 3 or cells[0] == "id":
            continue
        tag = TAG.match(cells[2].strip())
        if not tag:
            continue
        rows.append((cells[0], cells[1], tag.group(1), tag.group(2)))
    return rows, allowances


def check(path):
    path = Path(path).resolve()
    if path in set(corpus_paths.sealed()):
        print(f"choice-balance: {path.name} is a sealed set. This tool prints "
              f"capture ids and would be read while the set is being shaped, "
              f"which is the whole thing sealing is for.")
        return 2

    if not matcher_is_working():
        print("choice-balance: the marker matcher cannot find a marker in a "
              "string that contains three of them. Every row below would read "
              "as marker-free and the set would look perfectly balanced. "
              "Fix the matcher before reading any result here.")
        return 2

    rows, allowances = read(path)
    if not rows:
        print(f"choice-balance: no `choice-<slot>-<resolution>` rows in "
              f"{path.name}. That is not a balanced set, it is an empty one — "
              f"and an empty set passes every proportion below trivially.")
        return 2

    family = [r for r in rows if r[3] in IN_FAMILY]
    resolved = [r for r in family if r[3] in RESOLVED]
    bad_tags = [r for r in rows if r[2] not in SLOTS or r[3] not in RESOLUTIONS]

    print()
    print(f"CHOICE BALANCE — {path.name}")
    print("=" * 68)
    print(f"  rows tagged choice-*       {len(rows)}")
    print(f"  in the family rate         {len(family)}"
          f"   (inferred, excluded: {len(rows) - len(family)})")
    print(f"  of those, with a resolution{len(resolved):>4}"
          f"   (open: {len(family) - len(resolved)})")
    print()

    failures = []

    if bad_tags:
        failures.append(f"B0  {len(bad_tags)} row(s) carry a tag outside the "
                        f"grammar: " + ", ".join(r[0] for r in bad_tags))

    # --- B1 -----------------------------------------------------------------
    bare = [r for r in resolved if r[3] == "r1"]
    share = len(bare) / len(resolved) if resolved else 0.0
    print(f"B1  bare restatement (r1)    {len(bare)}/{len(resolved)}"
          f"  ({100 * share:.0f}%, floor 33%)")
    if share < 1 / 3:
        failures.append("B1  fewer than a third of the resolutions are bare "
                        "restatements, so a marker list could score the family")

    mistagged = []
    for cid, utt, _slot, _res in bare:
        present = markers_in(utt)
        if present and cid not in allowances:
            mistagged.append((cid, present))
    if mistagged:
        failures.append(
            "B1  tagged r1 but carries a resolution marker: "
            + "; ".join(f"{cid} ({', '.join(m)})" for cid, m in mistagged)
            + ". Either the tag is wrong, or the marker means something else "
              "here — in which case say so with a `# allow-marker <id> "
              "<reason>` line, which costs an edit and a sentence.")
    if allowances:
        print(f"    marker allowances        {len(allowances)}"
              f"  ({', '.join(sorted(allowances))})")

    # --- B2 -----------------------------------------------------------------
    decoys = [r for r in family
              if r[3] not in ("r2", "r3") and markers_in(r[1])]
    print(f"B2  markers that resolve none{len(decoys):>4}"
          f"/{len(family)}  (floor 1)")
    if not decoys:
        failures.append("B2  no capture carries a resolution marker that "
                        "resolves nothing, so nothing here would catch a "
                        "parser that scores the family off the marker list")

    # --- B3 -----------------------------------------------------------------
    slots = Counter(r[2] for r in family)
    missing = [s for s in SLOTS if not slots[s]]
    print("B3  slots                    "
          + "  ".join(f"{s} {slots[s]}" for s in SLOTS))
    if missing:
        failures.append("B3  no captures for slot(s): " + ", ".join(missing)
                        + " — the family would quietly mean the date family "
                          "again")
    if family:
        worst, count = slots.most_common(1)[0]
        if count > len(family) / 2:
            failures.append(f"B3  `{worst}` is {count} of {len(family)} "
                            f"captures, over half")

    print()
    print("NOT CHECKED HERE — a human has to do these, and nothing below")
    print("reports on them, so a pass above is a pass on three rules of five")
    print("-" * 68)
    print("  B4  are the alternatives and the resolution paraphrases of one")
    print("      canonical sentence? Four of the five rows this project")
    print("      already had fail exactly that, and read as understanding.")
    print("  B5  how many authors wrote these, and is any published rate")
    print("      resting on one of them?")
    print("-" * 68)

    if failures:
        print()
        for line in failures:
            print(f"  FAIL  {line}")
        print()
        return 1

    print()
    print("  B1, B2 and B3 pass. B4 and B5 are unexamined.")
    return 0


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        print("usage: choice-balance.py <set.tsv>")
        return 2
    return check(argv[1])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
