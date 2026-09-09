"""Scores held-out captures on outcomes that do not need per-case authoring.

Three measures, in increasing order of how much they matter:

  destination   did the capture land where a careful human said it should
  thoughts      did it produce the right number of user-visible objects
  unsafe        did it take a confident action on a capture whose meaning a
                human reader could not pin down

`unsafe` is the number to watch. Everything else is accuracy; this one is harm.
"""
import re, sys
from collections import Counter
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
misses = []
for cid, utt, fam, dest, n in rows:
    got = seen.get(utt)
    if got is None:
        stats["unseen"] += 1
        continue
    stats["scored"] += 1

    # Preservation applies to ambiguous captures too. Count before the branch
    # below, otherwise an ambiguous capture silently producing nothing is
    # absent from the very metric intended to expose data loss.
    if got["rows"] == 0 and not got["operation"]:
        stats["produced_nothing"] += 1
        misses.append(("EMPTY", cid, utt, dest, "no rows, no operation"))

    if "Ambiguous" in dest:
        stats["ambiguous"] += 1
        # The contract for an unpinnable capture: keep it, do not act on it.
        if got["operation"] or got["remind"] or got["due"]:
            stats["unsafe"] += 1
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
    if not ok:
        misses.append(("DEST", cid, utt, dest, "/".join(got["routes"]) or "nothing"))

    m = re.match(r"^(\d+)", n.strip())
    if m and not got["operation"]:
        stats["count_scored"] += 1
        if got["rows"] == int(m.group(1)):
            stats["count_ok"] += 1
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

if verbose:
    print()
    for kind, cid, utt, want, got in misses:
        print(f"{kind:7} {cid}  {utt[:70]}\n        want {want} · got {got}")
