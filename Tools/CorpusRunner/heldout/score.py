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


def destination_rate(counter):
    total = counter["dest_ok"] + counter["dest_miss"]
    return counter["dest_ok"] / total if total else 1.0


for fam, counter in sorted(by_family.items(),
                           key=lambda kv: (destination_rate(kv[1]), kv[0])):
    print(f"{fam:<{NAME}}{counter['scored']:>4}"
          f"{cell(counter['dest_ok'], counter['dest_ok'] + counter['dest_miss'])}"
          f"{cell(counter['count_ok'], counter['count_scored'])}")
print("-" * WIDTH)
print("  Worst destination rate first. A whole-set average hides the family")
print("  that is broken, and these rates are what an adversarial pairing has")
print("  to be read against — see Tools/CorpusRunner/adversarial/README.md.")

if verbose:
    print()
    for kind, cid, utt, want, got in misses:
        print(f"{kind:7} {cid}  {utt[:70]}\n        want {want} · got {got}")
