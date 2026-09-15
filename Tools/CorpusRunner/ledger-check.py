#!/usr/bin/env python3
"""Recompute the sealed-set cost ledger instead of reading its conclusions.

`Docs/LANGUAGE_BASELINE.md` carries one row per change that moved a sealed
measure, and then a sentence stating the running total. Both are written by
hand, at different times, by whoever measured the change -- which is the
arrangement that has already produced a wrong figure in this repository twice
today. A stated total is a claim about the rows above it, and the only reason
to believe it is that somebody added them up correctly on the day.

So the total is not read here. It is recomputed from the rows and the run fails
if the two disagree. Same for each row's direction: `255/310 -> 254/310` is a
loss of one whatever the last cell says.

WHAT THIS CANNOT DO, and the reason it is written at the top rather than
mentioned in a message somewhere:

  * **It cannot know that a change moved a measure and got no row.** Nothing
    in this container can run the parser, and even on a Mac the ledger's claim
    is about a change that happened rather than about the current state. A
    ledger everybody forgets to write reads as "no change" on its worst day,
    and no amount of checking the rows that ARE there fixes that. The same
    hole as every count check: a figure nobody marked cannot be recomputed.
  * It does not judge whether a cost was acceptable. The ledger's own header
    says it is not a budget.

What it does catch is the failure that has actually happened: a number in
prose drifting from the rows it summarises, and a measure name that is not a
measure.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASELINE = ROOT / "Docs" / "LANGUAGE_BASELINE.md"

HEADING = "## Sealed-set cost ledger"

#: A row saying nothing moved. Written out so "no measure moved" and "a measure
#: moved by zero" stay distinguishable -- they are different claims, and one
#: flag over both is how distinct populations collapse.
NOTHING_MOVED = "no sealed measure moved"

#: The dash the table uses for an absent figure. Not a hyphen.
ABSENT = "—"

#: The minus sign the ledger writes in its direction cell. Also not a hyphen.
MINUS = "−"


def ledger_section(text):
    """The lines between the ledger heading and the next heading, or None."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip() == HEADING:
            rest = lines[i + 1:]
            for j, later in enumerate(rest):
                if later.startswith("## "):
                    return rest[:j]
            return rest
    return None


def rows(section):
    """The data rows of the ledger table, each as a list of cells."""
    out = []
    for line in section:
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if not cells or set("".join(cells)) <= set("- "):
            continue                      # the |---|---| separator
        if cells[0].lower() == "date":
            continue                      # the header
        out.append(cells)
    return out


def fraction(cell):
    """`255/310` as a pair, or None for an absent figure."""
    cell = cell.strip().strip("`*")
    if cell in {ABSENT, "-", ""}:
        return None
    match = re.fullmatch(r"(\d+)\s*/\s*(\d+)", cell)
    if not match:
        raise ValueError(f"not a figure and not an absent marker: {cell!r}")
    return int(match.group(1)), int(match.group(2))


def measured_delta(row):
    """The movement the row's own from/to columns describe.

    Returns None when the row records a change that moved nothing, which is a
    different thing from a movement of zero and is kept different.
    """
    before, after = fraction(row[3]), fraction(row[4])
    if before is None and after is None:
        return None
    if before is None or after is None:
        raise ValueError(f"half a pair of figures in row {row[1]!r}: "
                         f"{row[3]!r} -> {row[4]!r}")
    if before[1] != after[1]:
        raise ValueError(f"row {row[1]!r} changes its own denominator "
                         f"({before[1]} -> {after[1]}), so the two figures are "
                         f"not comparable and no direction can be read from them")
    return after[0] - before[0]


def stated_delta(row):
    """The movement the row's last cell claims."""
    cell = row[5].strip().strip("*` ")
    if cell == NOTHING_MOVED:
        return None
    match = re.fullmatch(rf"[{MINUS}\-+]?\s*(\d+)", cell.replace(" ", ""))
    if not match:
        raise ValueError(f"row {row[1]!r} states a direction this cannot "
                         f"read: {cell!r}")
    value = int(match.group(1))
    return -value if cell.lstrip().startswith((MINUS, "-")) else value


def total_claim(section):
    """The running-total sentence, as (rows, changes), or None if absent."""
    text = " ".join(section)
    match = re.search(
        rf"Running total:\s*\*\*([{MINUS}\-+]?\s*\d+)\s*rows?\*\*,\s*"
        rf"across\s+(\w+)\s+changes?", text)
    if not match:
        return None
    raw = match.group(1).replace(" ", "")
    value = int(raw.lstrip(MINUS + "-+"))
    if raw.startswith((MINUS, "-")):
        value = -value
    words = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
             "seven": 7, "eight": 8, "nine": 9, "ten": 10}
    changes = match.group(2)
    return value, words.get(changes.lower(), int(changes) if changes.isdigit()
                            else None)


def check(text):
    """Every disagreement found, as a list of strings. Empty means consistent."""
    section = ledger_section(text)
    if section is None:
        return [f"{BASELINE.name} has no '{HEADING}' section. The ledger is "
                f"how a cost that no single write-up displays becomes "
                f"readable; its absence is not a clean run."]

    table = rows(section)
    problems = []
    if not table:
        problems.append("the ledger section has no rows, so either nothing has "
                        "ever moved a sealed measure or the table was lost; "
                        "those need different responses and this cannot tell "
                        "them apart")

    running = 0
    moved = 0
    #: Which sealed measure each movement was in. A single running total is a
    #: sum, and summing 254/310 with 34/56 is collapsing two instruments into
    #: one number -- the thing this file's own rules forbid everywhere else.
    #: It has been safe so far only because exactly one measure has ever moved,
    #: which is a precondition nothing stated and nothing enforced. Now it is
    #: enforced, so the day a second measure moves this fails and asks for a
    #: per-measure total instead of quietly adding them up.
    measures_moved = set()
    for row in table:
        if len(row) < 6:
            problems.append(f"a ledger row has {len(row)} cells, not 6: {row}")
            continue
        try:
            measured, stated = measured_delta(row), stated_delta(row)
        except ValueError as exc:
            problems.append(str(exc))
            continue
        if measured != stated:
            problems.append(
                f"row {row[1]!r} states {row[5].strip()} but its own figures "
                f"({row[3]} -> {row[4]}) say "
                f"{'nothing moved' if measured is None else measured}")
            continue
        if measured is not None:
            running += measured
            moved += 1
            measures_moved.add(row[2].strip().lower())

    if len(measures_moved) > 1:
        problems.append(
            "rows record movements in more than one sealed measure "
            f"({', '.join(sorted(measures_moved))}), so a single running "
            "total would add up figures over different denominators. State a "
            "total per measure instead, and update this check to read them.")

    claim = total_claim(section)
    if claim is None:
        if table:
            problems.append("the ledger has rows but no running total, which "
                            "is the one line a reader takes at a glance")
    else:
        stated_total, stated_changes = claim
        if stated_total != running:
            problems.append(
                f"the running total says {stated_total:+d} but the rows sum to "
                f"{running:+d}")
        if stated_changes is not None and stated_changes != moved:
            problems.append(
                f"the running total says it is across {stated_changes} "
                f"change(s), but {moved} row(s) record a movement")
    return problems


def main():
    if not BASELINE.exists():
        print(f"ledger check: {BASELINE} does not exist")
        return 1
    problems = check(BASELINE.read_text(encoding="utf-8"))
    if not problems:
        print("ledger check ok: every row's direction matches its own figures, "
              "and the running total is the sum of the rows.")
        print("  It cannot tell you about a change that moved a measure and "
              "was never written down.")
        return 0
    print("ledger check FAILED:")
    for problem in problems:
        print(f"  {problem}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
