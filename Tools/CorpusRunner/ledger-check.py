#!/usr/bin/env python3
"""Recompute the sealed-set cost ledger instead of reading its conclusions.

`Docs/LANGUAGE_BASELINE.md` carries one row per change that moved a sealed
measure, and then a line per measure stating that measure's running total. Both
are written by hand, at different times, by whoever measured the change --
which is the arrangement that has already produced a wrong figure in this
repository twice today. A stated total is a claim about the rows above it, and
the only reason to believe it is that somebody added them up correctly on the
day.

So the totals are not read here. Each is recomputed from the rows for that
measure and the run fails if the two disagree. Same for each row's direction:
`255/310 -> 254/310` is a loss of one whatever the last cell says.

**One total per measure, never one total.** Until 2026-09-15 exactly one sealed
measure had ever moved, so a single running total was arithmetically harmless
and this file said so while refusing to rely on it. The second measure moved on
2026-09-15 and the guard written for that day fired. What replaced the single
total is a line per measure, because 254/310 and 246/255 are different sets
asking different questions: their sum is not a quantity, and a reader who nets
a loss on one against a gain on the other has learned nothing true about
either. A measure with rows and no line is a failure, and so is a line naming a
measure no row moved.

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


#: How many changes a per-measure line says it covers, spelled out.
WORDS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
         "seven": 7, "eight": 8, "nine": 9, "ten": 10}

#: A per-measure running total:
#:
#:     - **held-out thought count: -1 row**, across one change.
#:
#: The measure name is matched against the row's own measure cell rather than
#: against a list kept here, so a measure this file has never heard of still
#: gets checked and a typo in either place shows up as a mismatch instead of
#: being silently accepted by a fuzzy rule.
TOTAL_LINE = re.compile(
    rf"^\s*[-*]\s+\*\*(?P<measure>[^:*]+?):\s*"
    rf"(?P<delta>[{MINUS}\-+]?\s*\d+)\s*rows?\*\*,\s*"
    rf"across\s+(?P<changes>\w+)\s+changes?")


def total_claims(section):
    """Each per-measure running total, as {measure: (rows, changes)}.

    Duplicates are kept rather than collapsed: two lines for one measure is a
    disagreement to report, not a last-one-wins.
    """
    claims = {}
    duplicates = []
    for line in section:
        match = TOTAL_LINE.match(line)
        if not match:
            continue
        measure = match.group("measure").strip().lower()
        raw = match.group("delta").replace(" ", "")
        value = int(raw.lstrip(MINUS + "-+"))
        if raw.startswith((MINUS, "-")):
            value = -value
        changes = match.group("changes")
        count = WORDS.get(changes.lower(),
                          int(changes) if changes.isdigit() else None)
        if measure in claims:
            duplicates.append(measure)
        claims[measure] = (value, count)
    return claims, duplicates


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

    #: Rows and changes per sealed measure. Never one running total: summing
    #: 254/310 with 246/255 is collapsing two instruments into one number, the
    #: thing this file's own rules forbid everywhere else.
    running = {}
    moved = {}
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
            measure = row[2].strip().lower()
            if not measure or measure == ABSENT:
                problems.append(
                    f"row {row[1]!r} records a movement "
                    f"({row[3]} -> {row[4]}) but names no measure, so nothing "
                    f"can say which sealed set it was in")
                continue
            running[measure] = running.get(measure, 0) + measured
            moved[measure] = moved.get(measure, 0) + 1

    claims, duplicates = total_claims(section)
    for measure in sorted(set(duplicates)):
        problems.append(
            f"the ledger states more than one running total for "
            f"{measure!r}; one measure gets one line")

    if table and not claims:
        problems.append("the ledger has rows but no per-measure running "
                        "total, which is the line a reader takes at a glance")

    for measure in sorted(set(running) | set(claims)):
        if measure not in claims:
            problems.append(
                f"rows move {measure!r} by {running[measure]:+d} across "
                f"{moved[measure]} change(s), but no running total names it. "
                f"A movement with no total is a cost that no glance finds, "
                f"which is the whole reason this section exists.")
            continue
        if measure not in running:
            problems.append(
                f"a running total names {measure!r}, but no row records a "
                f"movement in it. Either the row was lost or the measure is "
                f"misspelled in one of the two places.")
            continue
        stated_total, stated_changes = claims[measure]
        if stated_total != running[measure]:
            problems.append(
                f"the running total for {measure!r} says "
                f"{stated_total:+d} but its rows sum to {running[measure]:+d}")
        if stated_changes is not None and stated_changes != moved[measure]:
            problems.append(
                f"the running total for {measure!r} says it is across "
                f"{stated_changes} change(s), but {moved[measure]} row(s) "
                f"record a movement in it")
    return problems


def _document(rows, totals):
    """A minimal ledger section, for the self-tests below."""
    return "\n".join(
        [HEADING, "", "| date | change | measure | from | to | |",
         "| --- | --- | --- | --- | --- | --- |"]
        + rows + [""] + totals + ["", "## Something else"])


GOOD_ROW = "| 2026-09-11 | a change | held-out thought count | 255/310 | 254/310 | **−1** |"
GOOD_TOTAL = "- **held-out thought count: −1 row**, across one change."
OTHER_ROW = "| 2026-09-15 | another change | everyday clean titles | 245/255 | 246/255 | **+1** |"
OTHER_TOTAL = "- **everyday clean titles: +1 row**, across one change."

#: Each case is (name, document, a substring the failure must contain, or None
#: for "this must pass"). These run on every invocation rather than behind a
#: flag: a checker whose own parser is never exercised is the instrument that
#: cannot fail, and this one's parser was rewritten the day a second measure
#: moved. Cheap enough -- no file is read.
SELF_TESTS = [
    ("one measure, consistent", _document([GOOD_ROW], [GOOD_TOTAL]), None),
    ("two measures, each with its own total",
     _document([GOOD_ROW, OTHER_ROW], [GOOD_TOTAL, OTHER_TOTAL]), None),
    ("two measures summed into one total",
     _document([GOOD_ROW, OTHER_ROW], ["- **held-out thought count: 0 rows**, across two changes."]),
     "no running total names it"),
    ("a total for a measure no row moved",
     _document([GOOD_ROW], [GOOD_TOTAL, OTHER_TOTAL]),
     "no row records a movement in it"),
    ("a per-measure total with the wrong sum",
     _document([GOOD_ROW, OTHER_ROW],
               ["- **held-out thought count: −2 rows**, across one change.", OTHER_TOTAL]),
     "says -2 but its rows sum to -1"),
    ("a per-measure total with the wrong change count",
     _document([GOOD_ROW, OTHER_ROW],
               [GOOD_TOTAL, "- **everyday clean titles: +1 row**, across two changes."]),
     "says it is across 2 change(s), but 1 row(s)"),
    ("one measure named twice",
     _document([GOOD_ROW], [GOOD_TOTAL, GOOD_TOTAL]),
     "more than one running total"),
    ("rows but no total", _document([GOOD_ROW], []),
     "no per-measure running total"),
    ("a movement with no measure named",
     _document(["| 2026-09-11 | a change | — | 255/310 | 254/310 | **−1** |"],
               [GOOD_TOTAL]),
     "names no measure"),
]


def self_test():
    """Every disagreement the self-tests found. Empty means the parser works."""
    failures = []
    for name, document, expected in SELF_TESTS:
        found = check(document)
        if expected is None:
            if found:
                failures.append(f"{name}: expected a clean run, got {found}")
        elif not any(expected in problem for problem in found):
            failures.append(f"{name}: expected a problem containing "
                            f"{expected!r}, got {found}")
    return failures


def main():
    broken = self_test()
    if broken:
        print("ledger check SELF-TEST FAILED -- the checker itself is wrong, "
              "so its verdict on the real ledger means nothing:")
        for failure in broken:
            print(f"  {failure}")
        return 1

    if not BASELINE.exists():
        print(f"ledger check: {BASELINE} does not exist")
        return 1
    problems = check(BASELINE.read_text(encoding="utf-8"))
    if not problems:
        print(f"ledger check ok ({len(SELF_TESTS)} self-tests, then the file): "
              "every row's direction matches its own figures, and each "
              "measure's running total is the sum of that measure's rows.")
        print("  It cannot tell you about a change that moved a measure and "
              "was never written down.")
        return 0
    print("ledger check FAILED:")
    for problem in problems:
        print(f"  {problem}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
