"""Scores held-out captures on outcomes that do not need per-case authoring.

Three measures, in increasing order of how much they matter:

  destination   did the capture land where a careful human said it should
  thoughts      did it produce the right number of user-visible objects
  unsafe        did it take a confident action on a capture whose meaning a
                human reader could not pin down

`unsafe` is the number to watch. Everything else is accuracy; this one is harm.
"""
import re, sys
from collections import Counter, defaultdict
from pathlib import Path

labels_path, probe_path = sys.argv[1], sys.argv[2]
verbose = "--verbose" in sys.argv

rows = []
for line in open(labels_path):
    if line.startswith("#") or not line.strip():
        continue
    parts = line.rstrip("\n").split("\t")
    if len(parts) >= 5 and parts[0] != "id":
        rows.append(parts[:5])

blocks = re.split(r'\n(?=── ")', open(probe_path).read())
seen = {}
for b in blocks:
    m = re.match(r'── "(.*?)"', b)
    if not m:
        continue
    seen[m.group(1)] = {
        "rows": len(re.findall(r"row title:", b)),
        "routes": re.findall(r"route:\s+(\S+)", b),
        "operation": bool(re.search(r"operation:", b)),
        # The value has to be read and compared. A `(?!nil)` lookahead after
        # `\s+` backtracks over the padding and passes on every line, which
        # scored every ambiguous capture as unsafe.
        "due": any(v != "nil" for v in re.findall(r"due:\s+(\S+)", b)),
        "remind": any(v != "nil" for v in re.findall(r"remind:\s+(\S+)", b)),
    }

def wanted_today(dest):
    return any(k in dest for k in ("Today", "Shopping", "Event", "Alarm"))

stats = Counter()
# Per family as well as overall. This set carries exactly one family tag on
# every row, by design, so that a failure names the phenomenon that caused it
# — and until now the scorer read that column and dropped it, leaving four
# aggregate numbers. Tools/CorpusRunner/adversarial/README.md tells the reader
# to judge each pairing against its ingredients, and the ingredients live here,
# so without this the instruction could not be followed.
#
# Rates only, and the default output stays sealed: no capture text, no failure
# detail, `--verbose` unchanged. A finer-grained number is still a number.
by_family = defaultdict(Counter)
misses = []
for cid, utt, fam, dest, n in rows:
    fam = fam.strip() or "untagged"
    got = seen.get(utt)
    if got is None:
        stats["unseen"] += 1
        continue
    stats["scored"] += 1
    by_family[fam]["scored"] += 1

    # Preservation applies to ambiguous captures too. Count before the branch
    # below, otherwise an ambiguous capture silently producing nothing is
    # absent from the very metric intended to expose data loss.
    if got["rows"] == 0 and not got["operation"]:
        stats["produced_nothing"] += 1
        misses.append(("EMPTY", cid, utt, dest, "no rows, no operation"))

    if "Ambiguous" in dest:
        stats["ambiguous"] += 1
        by_family[fam]["ambiguous"] += 1
        # The contract for an unpinnable capture: keep it, do not act on it.
        if got["operation"] or got["remind"] or got["due"]:
            stats["unsafe"] += 1
            by_family[fam]["unsafe"] += 1
            misses.append(("UNSAFE", cid, utt, dest,
                           f"op={got['operation']} due={got['due']} remind={got['remind']}"))
        continue

    if "Operation" in dest:
        ok = got["operation"]
    elif wanted_today(dest):
        ok = "Today" in got["routes"]
    else:
        ok = bool(got["routes"]) and "Memory" in got["routes"]
    stats["dest_ok" if ok else "dest_miss"] += 1
    by_family[fam]["dest_ok" if ok else "dest_miss"] += 1
    if not ok:
        misses.append(("DEST", cid, utt, dest, "/".join(got["routes"]) or "nothing"))

    m = re.match(r"^(\d+)", n.strip())
    if m and not got["operation"]:
        stats["count_scored"] += 1
        by_family[fam]["count_scored"] += 1
        if got["rows"] == int(m.group(1)):
            stats["count_ok"] += 1
            by_family[fam]["count_ok"] += 1
        else:
            misses.append(("COUNT", cid, utt, m.group(1), str(got["rows"])))

d_total = stats["dest_ok"] + stats["dest_miss"]
print()
directory = Path(labels_path).resolve().parent.name
label = {"heldout": "HELD-OUT SET", "devsets": "DEVELOPMENT SET"}.get(directory, "CAPTURE SET")
print(f"{label} — {len(rows)} labelled utterances")
print("=" * 66)
print(f"  scored                     {stats['scored']}")
print(f"  missing probe results      {stats['unseen']}")
print(f"  destination correct        {stats['dest_ok']}/{d_total}"
      f"  ({100 * stats['dest_ok'] / max(d_total, 1):.1f}%)")
print(f"  thought count correct      {stats['count_ok']}/{stats['count_scored']}"
      f"  ({100 * stats['count_ok'] / max(stats['count_scored'], 1):.1f}%)")
print(f"  captures producing nothing {stats['produced_nothing']}")
print()
print(f"  genuinely ambiguous        {stats['ambiguous']}")
print(f"  ACTED ON ANYWAY            {stats['unsafe']}"
      f"  ({100 * stats['unsafe'] / max(stats['ambiguous'], 1):.1f}% of them)")
print("=" * 66)
print("  The last number is the one that matters: a confident wrong action on")
print("  a capture whose meaning a careful human could not pin down.")


def cell(ok, total):
    """`ok/total (pct)` padded to the column, or an em dash when unscored."""
    if total == 0:
        return f"{'—':>17}"
    return f"{f'{ok}/{total}'.ljust(7)}({100 * ok / total:>5.1f}%)".rjust(17)


# Sized to the longest tag actually present rather than to a constant. A fixed
# width silently truncates `occupation-vs-person` to `occupation-vs-per`, which
# reads as a different family and is the sort of thing nobody notices twice.
NAME = max([len(f) for f in by_family] + [len("family")]) + 1
WIDTH = NAME + 4 + 17 + 17

print()
print("PER FAMILY — one tag per capture, so these columns do not overlap")
print("=" * WIDTH)
print(f"{'family':<{NAME}}{'n':>4}{'destination':>17}{'thought count':>17}")
print("-" * WIDTH)


def destination_scored(counter):
    """How many of the family's captures the destination rate is computed from.

    Not `n`. A capture labelled `Ambiguous-*` is excluded from destination by
    design — the contract for an unpinnable capture is to keep it and not act,
    which the unsafe counter measures instead — so a family made largely of
    them carries a destination denominator far below its row count.
    """
    return counter["dest_ok"] + counter["dest_miss"]


def destination_rate(counter):
    """Deliberately undefined on a zero denominator, rather than 1.0.

    Answering 1.0 there is what sorted a family with no scorable destination
    into the bottom of a table whose footer says worst first — the position a
    family that passes everything occupies. The fix is the filter below, not a
    safer fallback here: a family with nothing to score has no place in a
    ranking at all, and a fallback would only decide where to put it. So this
    raises if one ever reaches it, which is a caller bug.
    """
    return counter["dest_ok"] / destination_scored(counter)


def row(fam, counter):
    return (f"{fam:<{NAME}}{counter['scored']:>4}"
            f"{cell(counter['dest_ok'], destination_scored(counter))}"
            f"{cell(counter['count_ok'], counter['count_scored'])}")


#: Families with nothing scorable are held out of the ranking entirely — this
#: filter is the guard, and the whole of it. Of the rest: rate first, then
#: denominator descending, because at an equal rate the better evidenced family
#: is the worse finding. Breaking that tie alphabetically seated one-capture
#: rows at the top of the list triage starts from.
ranked = sorted((f for f, c in by_family.items() if destination_scored(c)),
                key=lambda f: (destination_rate(by_family[f]),
                               -destination_scored(by_family[f]), f))
unranked = sorted(f for f, c in by_family.items() if not destination_scored(c))

for fam in ranked:
    print(row(fam, by_family[fam]))
print("-" * WIDTH)
print("  Worst destination rate first; at an equal rate, the larger")
print("  denominator first. A whole-set average hides the family that is")
print("  broken, and these rates are what an adversarial pairing has to be")
print("  read against — see Tools/CorpusRunner/adversarial/README.md.")
print("  `n` is captures carrying the tag, not the denominator of either")
print("  rate: read each denominator from its own column before quoting a")
print("  row, because a rate over 1 or 2 captures ranks like any other.")

if unranked:
    print()
    print("NOT RANKED — no scorable destination in these families")
    print("-" * WIDTH)
    for fam in unranked:
        print(row(fam, by_family[fam]))
    print("-" * WIDTH)
    print("  Every capture carrying these tags is labelled unpinnable, so")
    print("  there is no destination rate for them to be worst or best at.")
    print("  They are measured by ACTED ON ANYWAY above, not by this table.")

#: Families whose rate means nothing read on its own.
#:
#: A guard family is labelled "do not split here"; its target family is
#: labelled "split here". Both are juxtaposed clauses with no connector, so a
#: parser with no boundary logic at all passes every guard row and fails every
#: target row. A guard at ceiling beside a target at zero is therefore evidence
#: about whether the mechanism EXISTS, not about whether it is right -- and the
#: table above prints that 4/4 among the healthy rows, where anyone scanning
#: reads it as coverage.
#:
#: `runon.tsv` says in its own header that bridging is "the row that will still
#: be failing last". It is the row that passes first, and nothing in the
#: repository owns a statement-statement boundary for it to be guarding.
CONTROL_PAIRS = [("anaphora-guard", "statement-runon"),
                 ("bridging-guard", "statement-runon"),
                 ("object-guard", "statement-runon")]

present = [(g, t) for g, t in CONTROL_PAIRS if g in by_family or t in by_family]
if present:
    lines, vacuous_any = [], False
    for guard, target in present:
        if guard not in by_family or target not in by_family:
            missing = guard if guard not in by_family else target
            lines.append(f"  {guard} / {target}: {missing} is not in this set, "
                         f"so the other half is being read alone")
            continue
        g, t = by_family[guard], by_family[target]
        paired = g["count_scored"] and t["count_scored"]
        vacuous = paired and g["count_ok"] == g["count_scored"] and not t["count_ok"]
        vacuous_any = vacuous_any or vacuous
        lines.append(f"  {guard:<16}{g['count_ok']:>3}/{g['count_scored']:<3}"
                     f"  vs  {target:<16}{t['count_ok']:>3}/{t['count_scored']:<3}"
                     f"  {'NOT INFORMATIVE' if vacuous else 'informative'}")
    print()
    print("CONTROL PAIRS \u2014 a guard read against what it guards against")
    print("-" * WIDTH)
    for line in lines:
        print(line)
    print("-" * WIDTH)
    if vacuous_any:
        # Printed only when a row earns it. Boilerplate that appears whatever
        # the numbers say is boilerplate a reader learns to skip -- and it also
        # makes the verdict unsearchable, which is how the first version of
        # this section got its own tests wrong.
        print("  NOT INFORMATIVE means a parser that never splits scores")
        print("  exactly those two numbers, so the guard's pass is evidence")
        print("  the mechanism is absent rather than correct. The rows stay")
        print("  counted -- they are a real regression guard against an")
        print("  over-split -- but the rate is not progress. The verdict")
        print("  changes by itself once the target family leaves zero.")
    else:
        print("  Each guard above is read against the family it guards")
        print("  against, so neither rate is carrying the other.")

if verbose:
    print()
    for kind, cid, utt, want, got in misses:
        print(f"{kind:7} {cid}  {utt[:70]}\n        want {want} · got {got}")
