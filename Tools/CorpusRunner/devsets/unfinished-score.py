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

**`unsafe` is reported split, because one number was answering two questions.**
The commitment test used to sit outside the recall test, so a capture the app
recognised as unfinished and dated anyway counted the same as one it never
recognised at all. Those are not the same defect. The first is a guard letting
a commitment through, which is harm on the path that is supposed to prevent it.
The second is the recall miss showing through: nothing decided the fragment was
unfinished, so nothing was ever asked to suppress the date, and the count goes
to zero when recall improves without any guard being touched.

The split is what makes them separable, and it is why the exit status can now
fail on the first without failing on the second. The total is unchanged: a
breakdown that moved the number it breaks down would be worth nothing.

**What the split still cannot see, and the exit status now depends on it.**
`flagged` and `committed` are both read over the whole capture block rather
than per row, which the probe output does not separate. So a multi-row capture
whose *finished* half legitimately carries a date, with an unfinished half
beside it, reads as "recognised, and committed anyway" — a guard failure that
is not one, and one this condition would fail the run on. The count is zero
today and no capture in the set has that shape, which is exactly why it is
written here rather than discovered later: the first time this gates, check
whether the capture has more than one row before believing it. `unsafe` has
always had this blind spot; the split inherits it rather than introducing it.
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

def limits(path):
    """Recorded design limits declared in the set's header.

    `# limit: <source file> | <phrase it must still contain> | <ids>` marks
    captures the implementation has already decided not to attempt. Parsed
    here, checked in `Tools/CorpusRunner/test_score.py`: the scorer has to run
    without the repository around it, and a citation nobody verifies is the
    kind of claim this whole directory exists to stop making.
    """
    out = []
    for line in open(path):
        if not line.startswith("# limit:"):
            continue
        parts = [f.strip() for f in line[len("# limit:"):].split("|")]
        if len(parts) != 3:
            continue
        source, phrase, ids = parts
        out.append((source, phrase, ids.split()))
    return out


stats = Counter()
byfam = defaultdict(Counter)
misses = []


def scored_line(stats, labelled):
    """`N of M labelled`, and what it means when the two differ.

    A scorer here drops an unseen row from the denominator rather than
    failing it, so **a denominator arriving at exactly its label count is the
    only evidence anyone gets that no row was dropped**. That reconciliation
    was a hand check somebody did against the label file; printing both
    numbers on one line makes it something the instrument does.
    """
    if stats["unseen"]:
        return (f"{stats['scored']} of {labelled} labelled"
                f"  ← {stats['unseen']} with no probe result, "
                f"excluded from every rate below")
    return f"{stats['scored']} of {labelled} labelled"
#: Counted, never subtracted. A limit changes what the reader concludes from
#: the rate, not the rate.
declared = limits(labels_path)
limited = {cid for _, _, ids in declared for cid in ids}

for cid, utt, fam, exp in rows:
    got = seen.get(utt)
    if got is None:
        #: A labelled row the probe never emitted. It used to increment this
        #: counter and nothing else: the counter was never printed, no miss
        #: was appended for it, and this file had no exit status at all. So a
        #: truncated probe run, a lost line or an encoding difference took
        #: rows out of the denominator and the report said nothing -- 34 of
        #: 57 would quietly become a rate over whatever survived.
        stats["unseen"] += 1
        misses.append(("UNSEEN", cid, utt, "a probe result",
                       "the runner never emitted this line"))
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
        if cid in limited:
            stats["limited"] += 1
            byfam[fam]["limited"] += 1
        if flagged:
            stats["inc_ok"] += 1
            byfam[fam]["ok"] += 1
        else:
            misses.append(("MISSED", cid, utt, "flag as unfinished",
                           f"rows={got['rows']} routes={'/'.join(got['routes'])} state={'/'.join(got['states'])}"))
        if committed:
            stats["unsafe"] += 1
            #: Which of the two this is. Inside the branch rather than beside
            #: it, because `flagged` is exactly the recall test three lines up:
            #: a capture that was flagged and dated anyway is a guard failing,
            #: and one that was never flagged had no guard consulted.
            if flagged:
                stats["unsafe_recognised"] += 1
            misses.append(("UNSAFE", cid, utt, "no date/reminder",
                           f"flagged={flagged} due={got['due']} "
                           f"remind={got['remind']} op={got['operation']}"))
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
        #: Named rather than inlined, because the same expression is now the
        #: thing the unsafe split asks about. This branch's recall test is not
        #: `flagged` alone: a withdrawal the app acted on is handled too.
        handled = bool(flagged or got["rows"] == 0 or got["review"]
                       or got["operation"])
        if handled:
            stats["abd_ok"] += 1
        else:
            misses.append(("ABANDON", cid, utt, "withdrawn or flagged",
                           f"rows={got['rows']} routes={'/'.join(got['routes'])}"))
        if committed:
            stats["unsafe"] += 1
            if handled:
                stats["unsafe_recognised"] += 1
            misses.append(("UNSAFE", cid, utt, "no date/reminder",
                           f"handled={handled} due={got['due']}"))
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
print(f"  scored                        {scored_line(stats, len(rows))}")
print(f"  recall   unfinished flagged   {stats['inc_ok']}/{inc}"
      f"  ({100 * stats['inc_ok'] / max(inc, 1):.1f}%)")
print(f"  FALLOUT  finished misflagged  {stats['fallout']}/{fp}"
      f"  ({100 * stats['fallout'] / max(fp, 1):.1f}%)")
print(f"  abandonment handled           {stats['abd_ok']}/{stats['abd_total']}")
print(f"  mixed: finished half survives {stats['mix_ok']}/{stats['mix_total']}")
print()
print(f"  UNSAFE   fragment given a date/reminder/operation   {stats['unsafe']}")
#: Printed on every run, including a clean one. A split that appears only when
#: it is non-zero tells a later reader nothing about the runs where it stayed
#: quiet -- the same reason `scored N of M labelled` prints when N == M.
print(f"    recognised, and committed anyway  {stats['unsafe_recognised']}"
      f"   ← a guard let a commitment through")
print(f"    never recognised at all           "
      f"{stats['unsafe'] - stats['unsafe_recognised']}"
      f"   ← the recall miss showing through")
print("=" * 68)
print("  Fallout is the number that decides whether this ships: a wrongly")
print("  interrupted finished thought is worse than a missed fragment.")

if stats["limited"]:
    #: The ids, and deliberately no arithmetic. Printing "so the reachable
    #: ceiling is 50 of 57" was the first draft and it was wrong twice over. A
    #: ceiling is a denominator in waiting: once 50 is in the report, 34 of 50
    #: is in the reader's head, and 68% is a nicer number than 59.6% that
    #: nobody earned. And it would be false — what the source records is that
    #: three *tagger classes* were tried and cost more than they recovered,
    #: which is a statement about one signal, not about the language. The app
    #: already measures the speaker's pauses and throws them away; a boundary
    #: that read timings would not face the same ambiguity. A recorded limit is
    #: a decision taken with the signals to hand. The disclosure is a fact; the
    #: subtraction would be a forecast.
    print()
    print(f"  {stats['limited']} of the {inc} unfinished captures are recorded "
          f"design limits:")
    for source, phrase, ids in declared:
        covered = [c for c in ids if c in limited]
        print(f"    {source}")
        print(f"      \"{phrase}\"")
        print(f"      {' '.join(covered)}")
    print("  They are counted as misses above and stay that way. A limit says")
    print("  the gap is known and declined with the signals we have, not that")
    print("  it is closed and not that it is unreachable.")
print()
print(f"{'FAMILY':32}{'CASES':>7}{'OK':>7}")
print("-" * 48)
for fam in sorted(byfam, key=lambda f: byfam[f]["total"] - byfam[f]["ok"], reverse=True):
    c = byfam[fam]
    #: Marked on the row rather than left to the block above, because this
    #: table is what gets quoted and a family half made of declined cases
    #: reads as the biggest available win when it is not.
    mark = f"   {c['limited']} recorded as a limit" if c["limited"] else ""
    print(f"{fam:32}{c['total']:>7}{c['ok']:>7}{mark}")

if verbose:
    print()
    for kind, cid, utt, want, got in misses:
        print(f"{kind:10} {cid}  {utt[:64]}\n           want {want} · got {got}")

#: This file used to have no exit status at all, so `unfinished-score.sh`
#: could not fail on anything. `language-metrics.sh` discards dev-set scorer
#: exit codes by design -- the scorers report, they do not gate -- so this
#: cannot redden the language job. It fails a hand run, which is where a
#: dropped row is worth stopping for.
#:
#: `unsafe_recognised` is in this condition and the total `unsafe` is not,
#: and the split above is what makes that distinction available. The earlier
#: note here said the total stayed out because the set is not clean on it --
#: `Docs/LANGUAGE_BASELINE.md` records **2 unsafe** at `9d91a0b` -- so gating
#: it would redden every hand run on a pre-existing defect, and that this
#: condition should grow once those two captures were identified.
#:
#: They have been. Both are captures the app never flagged as unfinished, so
#: nothing was ever asked to withhold the date: they are the recall miss
#: showing through and they disappear when recall improves, with no guard to
#: write. Gating on them would block every run on a number that is not
#: independently movable. A capture that *was* recognised and dated anyway is
#: the opposite -- a guard that ran and let a commitment past -- and that is
#: worth stopping for. Same reasoning as a recorded limit: the disclosure is a
#: fact, and the part somebody already owns forgives the exit status, not the
#: rate.
sys.exit(1 if (stats["unseen"] or stats["unsafe_recognised"]) else 0)
