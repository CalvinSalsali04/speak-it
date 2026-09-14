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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compromised

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

def tally(rows):
    """Accumulate every measure over the given rows.

    Called twice — once over every labelled capture (the legacy metric)
    and once with the known-not-unseen captures removed (the clean sealed
    metric). One function so the two numbers cannot drift apart: a change
    to how anything is counted lands in both or neither.
    """
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
    return stats, by_family, misses


stats, by_family, misses = tally(rows)

# The registry describes `heldout.tsv` and nothing else. This scorer also runs
# the development sets, where excluding a held-out id would be meaningless and
# the presence check below would be a false alarm, so the exclusion is scoped
# to the set it is about rather than applied to whatever it is pointed at.
directory = Path(labels_path).resolve().parent.name
scoring_heldout = directory == "heldout"
excluded_ids = compromised.EXCLUDED if scoring_heldout else set()

if scoring_heldout:
    # Every excluded id must really be in the file. A typo excludes nothing and
    # the clean number quietly becomes the legacy one: both are printed, both
    # look plausible, and the difference between them is silently zero. That is
    # a guard whose expected answer is the system's default answer, which is
    # the failure this repository keeps paying for.
    missing = sorted(excluded_ids - {r[0] for r in rows})
    if missing:
        sys.exit(f"compromised.py names ids not in {labels_path}: "
                 f"{', '.join(missing)}")

clean_rows = [r for r in rows if r[0] not in excluded_ids]
clean, clean_by_family, _ = tally(clean_rows)

d_total = stats["dest_ok"] + stats["dest_miss"]
print()
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
print("  These are the LEGACY figures: every labelled capture, including the")
print("  ones known not to be unseen. They are what older sections of")
print("  Docs/LANGUAGE_BASELINE.md mean, and they are kept for that reason.")

# ---------------------------------------------------------------- clean sealed
if scoring_heldout:
  c_total = clean["dest_ok"] + clean["dest_miss"]
  print()
  print(f"CLEAN SEALED — {len(clean_rows)} captures still plausibly unseen")
  print("=" * 66)
  print(f"  destination correct        {clean['dest_ok']}/{c_total}"
        f"  ({100 * clean['dest_ok'] / max(c_total, 1):.1f}%)")
  print(f"  thought count correct      {clean['count_ok']}/{clean['count_scored']}"
        f"  ({100 * clean['count_ok'] / max(clean['count_scored'], 1):.1f}%)")
  print(f"  genuinely ambiguous        {clean['ambiguous']}")
  print(f"  ACTED ON ANYWAY            {clean['unsafe']}"
        f"  ({100 * clean['unsafe'] / max(clean['ambiguous'], 1):.1f}% of them)")
  print("=" * 66)
  print("  USE THIS ONE for any claim about generalising to unseen speech.")
  print("  It is not a better score; it is the same measures over the rows")
  print("  entitled to carry that claim. It may read higher or lower.")

  print()
  print(f"EXCLUSIONS — {len(rows)} labelled, "
        f"{len(compromised.EXCLUDED)} excluded, {len(clean_rows)} clean")
  print("=" * 66)
  for name, table in compromised.CATEGORIES:
      ids = sorted(table)
      print(f"  {name:<32} {len(ids):>2}  {' '.join(ids)}")
  print("-" * 66)
  print(f"  compromised (in tuned material or in a document) : "
        f"{len(compromised.COMPROMISED)}")
  print(f"  excluded from the clean sealed score             : "
        f"{len(compromised.EXCLUDED)}")
  print("  The categories overlap — C342 is in two — so the excluded total is")
  print("  a union and not a sum. Counting it as a sum is how the published")
  print("  figure read three when it was five.")
  print()
  print("  Which subtotals the excluded captures feed, so the denominators")
  print("  above can be reconciled by hand:")
  for cid in sorted(compromised.EXCLUDED):
      feeds = []
      for r in rows:
          if r[0] != cid:
              continue
          feeds.append(f"family:{r[2].strip()}")
          feeds.append("ambiguous/unsafe" if "Ambiguous" in r[3] else "destination")
          if re.match(r"^\d+", r[4].strip()):
              feeds.append("thought count")
      print(f"    {cid}  " + ", ".join(feeds))
  print("=" * 66)
  print("  Ids only. No capture text and no failure reason is read or printed")
  print("  by this section, and an id must never be grepped from the")
  print("  repository root -- see the note in compromised.py.")


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
print("PER FAMILY (LEGACY denominators) — one tag per capture")
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

if verbose:
    print()
    for kind, cid, utt, want, got in misses:
        print(f"{kind:7} {cid}  {utt[:70]}\n        want {want} · got {got}")
