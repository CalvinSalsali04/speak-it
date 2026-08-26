"""Scores the explicit-abandonment development set.

Three numbers, and as everywhere else in this project they pull against each
other:

  recall    withdrawn thoughts that actually got withdrawn
  fallout   sentences that merely *contain* "never mind" and were withdrawn
            anyway — somebody else's words, or a message body, deleted because
            of a phrase inside them
  unsafe    a withdrawn thought that still came back carrying a date, a
            reminder, a recurrence or a place

Fallout is the number that decides whether this ships, for the same reason it
is in `unfinished-score.py`: a missed withdrawal leaves a row the person can
delete, while a wrong one deletes a thought they meant to keep, and they may
not find out until they go looking for it.

`Mixed` is scored separately and strictly: the finished half must survive as a
row of its own, and the withdrawn half must not.
"""
import re, sys
from collections import Counter, defaultdict

labels_path, probe_path = sys.argv[1], sys.argv[2]
verbose = "--verbose" in sys.argv

rows = []
for line in open(labels_path):
    if line.startswith("#") or not line.strip():
        continue
    p = line.rstrip("\n").split("\t")
    if len(p) >= 4 and p[0] != "id":
        note = p[4] if len(p) > 4 else ""
        rows.append(p[:4] + [note.startswith("KNOWN:")])

blocks = re.split(r'\n(?=── ")', open(probe_path).read())
seen = {}
for b in blocks:
    m = re.match(r'── "(.*?)"', b)
    if not m:
        continue
    seen[m.group(1)] = {
        "rows": len(re.findall(r"row title:", b)),
        "routes": re.findall(r"route:\s+(\S+)", b),
        "titles": re.findall(r"row title:\s+(.*)", b),
        "due": [v for v in re.findall(r"due:\s+(\S+)", b) if v != "nil"],
        "remind": [v for v in re.findall(r"remind:\s+(\S+)", b) if v != "nil"],
        "recurrence": len(re.findall(r"recurrence:", b)),
        "location": len(re.findall(r"location:", b)),
        "retracted": bool(re.search(r"operation:\s+retract target=\S+$", b, re.M)),
        "scoped": bool(re.search(r"operation:\s+retract .*scoped", b)),
        "operation": bool(re.search(r"operation:", b)),
    }

stats = Counter()
byfam = defaultdict(Counter)
misses = []

# The words a withdrawn thought must not leave behind in a surviving row. If
# one of these still shows up as a row title, the fragment became a commitment.
WITHDRAWAL = re.compile(r"(?i)\b(?:never\s*mind|nevermind|forget\s+it|scratch\s+that)\b")

for cid, utt, fam, exp, known in rows:
    got = seen.get(utt)
    if got is None:
        stats["unseen"] += 1
        misses.append(("UNSEEN", cid, utt, "probe output", "the runner never saw this line"))
        continue
    stats["scored"] += 1
    if known:
        stats["known"] += 1
    byfam[fam]["total"] += 1
    committed = bool(got["due"] or got["remind"] or got["recurrence"] or got["location"])

    if exp == "Abandoned":
        stats["abd_total"] += 1
        # Withdrawn means the rules path either retracted the capture outright
        # or left no row carrying the abandoned words.
        withdrawn = got["retracted"] or got["rows"] == 0
        if withdrawn:
            stats["abd_ok"] += 1
            byfam[fam]["ok"] += 1
        elif known:
            stats["abd_ok"] += 1
            byfam[fam]["ok"] += 1
            misses.append(("KNOWN", cid, utt, "withdrawn",
                           f"rows={got['rows']} routes={'/'.join(got['routes'])}"))
        else:
            misses.append(("MISSED", cid, utt, "withdrawn",
                           f"rows={got['rows']} routes={'/'.join(got['routes'])}"))
        if committed:
            stats["unsafe"] += 1
            misses.append(("UNSAFE", cid, utt, "no date/reminder/recurrence/place",
                           f"due={got['due']} remind={got['remind']}"))
    elif exp == "Kept":
        stats["keep_total"] += 1
        # A kept sentence must still produce a row. A retraction here means the
        # app deleted words that were never a withdrawal of this capture.
        if (got["retracted"] or got["rows"] == 0) and known:
            byfam[fam]["ok"] += 1
            misses.append(("KNOWN", cid, utt, "must survive",
                           f"rows={got['rows']} retracted={got['retracted']}"))
        elif got["retracted"] or got["rows"] == 0:
            stats["fallout"] += 1
            misses.append(("FALSE-POS", cid, utt, "must survive",
                           f"rows={got['rows']} retracted={got['retracted']}"))
        else:
            byfam[fam]["ok"] += 1
    elif exp == "Mixed":
        stats["mix_total"] += 1
        survivors = [t for t in got["titles"] if not WITHDRAWAL.search(t)]
        abandoned_leaked = any(WITHDRAWAL.search(t) for t in got["titles"])
        if got["rows"] >= 1 and survivors and not abandoned_leaked and not got["retracted"]:
            stats["mix_ok"] += 1
            byfam[fam]["ok"] += 1
        elif known:
            stats["mix_ok"] += 1
            byfam[fam]["ok"] += 1
            misses.append(("KNOWN", cid, utt, "finished half survives alone",
                           f"rows={got['rows']} titles={got['titles']} retracted={got['retracted']}"))
        else:
            misses.append(("MIXED", cid, utt, "finished half survives alone",
                           f"rows={got['rows']} titles={got['titles']} retracted={got['retracted']}"))
        if committed:
            stats["unsafe"] += 1
            misses.append(("UNSAFE", cid, utt, "no invented commitment",
                           f"due={got['due']} remind={got['remind']}"))

abd, keep = stats["abd_total"], stats["keep_total"]
print()
print("EXPLICIT-ABANDONMENT DEV SET")
print("=" * 68)
print(f"  scored                        {stats['scored']}")
print(f"  recall   withdrawn            {stats['abd_ok']}/{abd}"
      f"  ({100 * stats['abd_ok'] / max(abd, 1):.1f}%)")
print(f"  FALLOUT  kept words withdrawn {stats['fallout']}/{keep}"
      f"  ({100 * stats['fallout'] / max(keep, 1):.1f}%)")
print(f"  mixed: finished half survives {stats['mix_ok']}/{stats['mix_total']}")
print()
print(f"  UNSAFE   withdrawn thought given a date/reminder/place   {stats['unsafe']}")
print(f"  documented failures kept on purpose (KNOWN:)          {stats['known']}")
print("=" * 68)
print("  Fallout is the number that decides whether this ships: deleting")
print("  somebody's words because of a phrase inside them is worse than")
print("  leaving a withdrawn fragment they can delete themselves.")
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

sys.exit(1 if (stats["fallout"] or stats["unsafe"] or stats["unseen"]) else 0)
