"""Scores the unfinished-thought development set.

Two numbers matter and they pull against each other:

  recall     unfinished thoughts recognised as unfinished
  fallout    finished thoughts wrongly called unfinished

Fallout is the one that hurts. A missed fragment costs somebody a row they
have to delete; a false positive interrupts somebody who said exactly what
they meant, and it happens on the common path rather than the rare one.

`unsafe` counts the third thing: a fragment that came back with a date, a
reminder, or a stored-data operation attached to it — the app inventing a
commitment out of half a sentence.
"""
import re, sys
from collections import Counter, defaultdict

labels_path, probe_path = sys.argv[1], sys.argv[2]
verbose = "--verbose" in sys.argv
GAP = "incompleteThought"

rows = []
for line in open(labels_path):
    if line.startswith("#") or not line.strip():
        continue
    p = line.rstrip("\n").split("\t")
    if len(p) >= 4 and p[0] != "id":
        rows.append(p[:4])

blocks = re.split(r'\n(?=── ")', open(probe_path).read())
seen = {}
for b in blocks:
    m = re.match(r'── "(.*?)"', b)
    if not m:
        continue
    seen[m.group(1)] = {
        "rows": len(re.findall(r"row title:", b)),
        "routes": re.findall(r"route:\s+(\S+)", b),
        "gaps": re.findall(r"state:\s+\S+(?:\s+gap=(\S+))?", b),
        "states": re.findall(r"state:\s+(\S+)", b),
        "review": len(re.findall(r"needsReview: true", b)),
        "due": [v for v in re.findall(r"due:\s+(\S+)", b) if v != "nil"],
        "remind": [v for v in re.findall(r"remind:\s+(\S+)", b) if v != "nil"],
        "operation": bool(re.search(r"operation:", b)),
    }

stats = Counter()
byfam = defaultdict(Counter)
misses = []

for cid, utt, fam, exp in rows:
    got = seen.get(utt)
    if got is None:
        stats["unseen"] += 1
        continue
    stats["scored"] += 1
    flagged = GAP in [g for g in got["gaps"] if g]
    # A retraction is the app doing what it was told, not harm. "Never mind"
    # is supposed to withdraw the fragment; counting that as an invented
    # commitment scores the correct behaviour as a failure.
    withdrew = got["operation"] and exp == "Abandoned"
    committed = bool(got["due"] or got["remind"] or (got["operation"] and not withdrew))

    if exp == "Incomplete":
        stats["inc_total"] += 1
        byfam[fam]["total"] += 1
        if flagged:
            stats["inc_ok"] += 1
            byfam[fam]["ok"] += 1
        else:
            misses.append(("MISSED", cid, utt, "flag as unfinished",
                           f"rows={got['rows']} routes={'/'.join(got['routes'])} state={'/'.join(got['states'])}"))
        if committed:
            stats["unsafe"] += 1
            misses.append(("UNSAFE", cid, utt, "no date/reminder",
                           f"due={got['due']} remind={got['remind']} op={got['operation']}"))
    elif exp == "Complete":
        stats["fp_total"] += 1
        byfam[fam]["total"] += 1
        if flagged:
            stats["fallout"] += 1
            misses.append(("FALSE-POS", cid, utt, "must not be called unfinished",
                           f"rows={got['rows']} routes={'/'.join(got['routes'])}"))
        else:
            byfam[fam]["ok"] += 1
    elif exp == "Abandoned":
        stats["abd_total"] += 1
        if flagged or got["rows"] == 0 or got["review"] or got["operation"]:
            stats["abd_ok"] += 1
        else:
            misses.append(("ABANDON", cid, utt, "withdrawn or flagged",
                           f"rows={got['rows']} routes={'/'.join(got['routes'])}"))
        if committed:
            stats["unsafe"] += 1
            misses.append(("UNSAFE", cid, utt, "no date/reminder", f"due={got['due']}"))
    elif exp == "Mixed":
        stats["mix_total"] += 1
        # The finished half has to survive as its own row.
        if got["rows"] >= 2:
            stats["mix_ok"] += 1
        else:
            misses.append(("MIXED", cid, utt, ">=2 rows, finished half survives",
                           f"rows={got['rows']} routes={'/'.join(got['routes'])}"))

inc, fp = stats["inc_total"], stats["fp_total"]
print()
print("UNFINISHED-THOUGHT DEV SET")
print("=" * 68)
print(f"  scored                        {stats['scored']}")
print(f"  recall   unfinished flagged   {stats['inc_ok']}/{inc}"
      f"  ({100 * stats['inc_ok'] / max(inc, 1):.1f}%)")
print(f"  FALLOUT  finished misflagged  {stats['fallout']}/{fp}"
      f"  ({100 * stats['fallout'] / max(fp, 1):.1f}%)")
print(f"  abandonment handled           {stats['abd_ok']}/{stats['abd_total']}")
print(f"  mixed: finished half survives {stats['mix_ok']}/{stats['mix_total']}")
print()
print(f"  UNSAFE   fragment given a date/reminder/operation   {stats['unsafe']}")
print("=" * 68)
print("  Fallout is the number that decides whether this ships: a wrongly")
print("  interrupted finished thought is worse than a missed fragment.")
print()
print(f"{'FAMILY':32}{'CASES':>7}{'OK':>7}")
print("-" * 48)
for fam in sorted(byfam, key=lambda f: byfam[f]["total"] - byfam[f]["ok"], reverse=True):
    c = byfam[fam]
    print(f"{fam:32}{c['total']:>7}{c['ok']:>7}")

if verbose:
    print()
    for kind, cid, utt, want, got in misses:
        print(f"{kind:10} {cid}  {utt[:64]}\n           want {want} · got {got}")
