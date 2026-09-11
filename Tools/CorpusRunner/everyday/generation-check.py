"""Fails if a sealed set's captures changed without a new generation.

Each sealed set's README claims its captures have never been scored and then
edited. That claim is load-bearing — it is the whole reason a number from these
sets means anything — and until now nothing enforced it. A reader checks the
paragraph, not the git history that would distinguish a length-only edit from
one made after seeing failures.

**What this proves, and what it does not.** It cannot tell a legitimate new
generation from a quiet edit; nothing can, because the two are the same diff.
The generation row does the real work. This check only makes the edit
impossible to make silently, so the conversation happens.

Two records, with different jobs:

  * `generations.tsv` — the generation each set is on, for a human to read.
  * `generations/captures.sha256` — one hash per capture, so the failure can
    say how many captures changed rather than only that something did.

Hashes are of the capture text alone, so this file reveals no capture and
committing it unseals nothing.

The capture column is read through `leak-check.py`'s `harvest`, not by a second
implementation of it: the sets do not agree on layout, and a checker reading
the wrong column passes for the wrong reason, which is worse than failing.

Run it from the repository root:

    python3 Tools/CorpusRunner/everyday/generation-check.py

To open a new generation, having decided to, name the set and the number:

    python3 Tools/CorpusRunner/everyday/generation-check.py --record everyday 4

It refuses an unknown set, any number that is not the next one, a set whose
captures have not actually changed, and a set whose captures are all gone, so
recording is a decision rather than a reflex. Then write the generation's row
in that set's README saying what changed and which numbers no longer compare.

The check reads the union of the sets on disk and the sets on record, not the
ones on disk. A set that has been deleted is absent from disk, and iterating
disk made its disappearance invisible rather than a failure.
"""
import hashlib
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNNER = HERE.parent

#: Every set whose captures are claimed never to have been edited after
#: scoring. All three, deliberately: a claim enforced on one set and taken on
#: trust on the others, with nothing saying which is which, is the situation
#: this check exists to end.
SEALED = {
    "everyday": RUNNER / "everyday" / "everyday.tsv",
    "heldout": RUNNER / "heldout" / "heldout.tsv",
    "adversarial": RUNNER / "adversarial" / "adversarial.tsv",
}

MANIFEST = RUNNER / "generations.tsv"
HASHES = RUNNER / "generations" / "captures.sha256"
#: `recorded` is the day this manifest first held the set at that
#: generation, which is all it can honestly claim. The day a generation
#: was opened lives in that set's README, where the narrative is.
COLUMNS = ["set", "generation", "captures", "recorded", "note"]


_LEAK_CHECK = None


def harvest(path):
    """`leak-check.py`'s reader, so there is one answer to "which column".

    This file sits in `everyday/` next to that one although it covers all three
    sealed sets, for the same reason the leak check does: they are the two
    guards on the same boundary and splitting them across directories would
    leave neither obviously in charge of it.
    """
    global _LEAK_CHECK
    if _LEAK_CHECK is None:
        spec = importlib.util.spec_from_file_location(
            "leak_check", HERE / "leak-check.py")
        _LEAK_CHECK = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_LEAK_CHECK)
    return _LEAK_CHECK.harvest(path)


def digest(capture):
    """Short, and of the capture alone — never of the row around it.

    A README edit, a changed note, a retagged family: none of those is
    "scored and then edited", and a check that fires on them is one people
    learn to regenerate without reading.
    """
    return hashlib.sha256(capture.encode()).hexdigest()[:16]


def present():
    """Set name -> the hashes of its captures on disk, sorted.

    Sorted because reordering rows changes nothing about what is measured, and
    a check that fires on a reorder spends its credibility on a non-event.
    """
    return {name: sorted(digest(c) for c in harvest(path))
            for name, path in SEALED.items() if path.exists()}


def recorded():
    """Set name -> the hashes last recorded.

    Read in file order and left that way: every comparison below goes through
    `difference`, which is set-based, so order is irrelevant to the verdict.
    The file is written sorted for the sake of its diff, and a test asserts
    that where it belongs rather than this function quietly re-sorting and
    making the property untestable.
    """
    out = {}
    if HASHES.exists():
        for number, line in enumerate(HASHES.read_text().splitlines(), 1):
            if line.startswith("#") or not line.strip():
                continue
            try:
                name, value = line.split("\t")
            except ValueError:
                #: Naming the line matters more here than anywhere: this file
                #: is 766 lines of hex, so "not enough values to unpack" sends
                #: someone scrolling through it looking for nothing.
                print(f"generation-check: {HASHES} line {number} is not "
                      f"`set<TAB>hash`: {line!r}", file=sys.stderr)
                raise SystemExit(1)
            out.setdefault(name, []).append(value)
    return out


def generations():
    """Set name -> the row of `generations.tsv`, as a dict.

    The column header is skipped explicitly. Reading it as data gives a set
    literally named "set", which then gets written back out as a second header
    line on the next record — a file that corrupts a little more each time it
    is rewritten, and reads fine until someone looks.
    """
    out = {}
    if MANIFEST.exists():
        for line in MANIFEST.read_text().splitlines():
            if line.startswith("#") or not line.strip():
                continue
            row = dict(zip(COLUMNS, line.split("\t")))
            if row["set"] == "set":
                continue
            out[row["set"]] = row
    return out


def captures(n):
    return f"{n} capture" + ("" if n == 1 else "s")


def difference(theirs, ours):
    """(gone, added). A capture whose text was edited shows in both."""
    return sorted(set(theirs) - set(ours)), sorted(set(ours) - set(theirs))


def write(hashes, rows):
    HASHES.parent.mkdir(parents=True, exist_ok=True)
    HASHES.write_text(
        "# One hash per capture of each sealed set. Written by\n"
        "# everyday/generation-check.py --record; never by hand.\n"
        + "".join(f"{name}\t{value}\n"
                 for name in sorted(hashes) for value in hashes[name]))
    MANIFEST.write_text(
        "# Which generation each sealed set is on. A generation opens when a\n"
        "# capture's text changes; numbers never compare across one. The\n"
        "# narrative for each lives in that set's README.\n"
        + "\t".join(COLUMNS) + "\n"
        + "".join("\t".join(rows[name][c] for c in COLUMNS) + "\n"
                 for name in sorted(rows)))


def record(name, number, today):
    if name not in SEALED:
        print(f"generation-check: {name!r} is not a sealed set. "
              f"Known: {', '.join(sorted(SEALED))}.", file=sys.stderr)
        return 1
    rows, here, there = generations(), present(), recorded()
    current = int(rows[name]["generation"]) if name in rows else 0
    if number != current + 1:
        print(f"generation-check: {name} is on generation {current}, so the "
              f"next one is {current + 1}, not {number}. The number is typed "
              f"out so that opening a generation is a decision.", file=sys.stderr)
        return 1
    if here.get(name, []) == there.get(name, []):
        print(f"generation-check: {name}'s captures are unchanged, so there is "
              f"no generation to open. Recording anyway would make this check "
              f"something people run to turn red green.", file=sys.stderr)
        return 1
    if not here.get(name):
        #: The fourth refusal, and the one the failure path now points at. A
        #: set whose file is missing or empty is not a later version of
        #: itself, and recording it would write a generation of zero captures
        #: and turn the check green over a set that is not there.
        print(f"generation-check: {name} has no captures — its file is "
              f"missing or empty. Restore it rather than recording a "
              f"generation over it.", file=sys.stderr)
        return 1
    gone, added = difference(there.get(name, []), here.get(name, []))
    rows[name] = {"set": name, "generation": str(number),
                  "captures": str(len(here.get(name, []))), "recorded": today,
                  "note": f"-{len(gone)} +{len(added)} captures"}
    there[name] = here.get(name, [])
    write(there, rows)
    print(f"generation-check: {name} is now generation {number}, "
          f"{len(here.get(name, []))} captures ({len(gone)} gone, "
          f"{len(added)} added).")
    print(f"Now write that generation's row in {name}/README.md: what changed, "
          f"and which numbers no longer compare across it.")
    return 0


def main(argv):
    if argv[:1] == ["--record"]:
        if len(argv) != 3 or not argv[2].isdigit():
            print("usage: generation-check.py --record <set> <generation>",
                  file=sys.stderr)
            return 1
        from datetime import date
        return record(argv[1], int(argv[2]), date.today().isoformat())

    here, there, rows = present(), recorded(), generations()
    failed = False
    #: The union, not what is on disk. `present()` only reports a set whose
    #: file exists, so iterating it meant a deleted set was not a failure but
    #: an absence: remove `adversarial.tsv` entirely and this printed the other
    #: two and "no sealed capture has been edited since it was scored", exit 0,
    #: with 120 captures gone. Removal is squarely inside what the READMEs say
    #: opens a generation, so the sentence was false in a state the check was
    #: written to cover. Reproduced, then fixed. CI was never blind to it —
    #: leak-check.py and test_score.py both fail on the same tree — but a check
    #: whose own verdict is wrong is the thing this file exists to prevent.
    for name in sorted(set(here) | set(there)):
        gone, added = difference(there.get(name, []), here.get(name, []))
        if gone or added:
            failed = True
            # A capture whose text was edited leaves its old hash and gains a
            # new one, so it shows on both sides. Reporting it as one removal
            # and one addition would send someone hunting a capture nobody
            # deleted.
            edited = min(len(gone), len(added))
            print(f"generation-check FAILED: {name} — "
                  f"{captures(edited)} changed text, "
                  f"{len(added) - edited} added, {len(gone) - edited} removed "
                  f"({captures(len(here.get(name, [])))} now against "
                  f"{len(there.get(name, []))} recorded).", file=sys.stderr)
            if there.get(name) and not here.get(name):
                #: Every capture is gone. The advice below would be actively
                #: wrong here: `--record` would happily write a generation of
                #: zero captures and turn the check green over a set that no
                #: longer exists. There is one correct response to this.
                print(f"  Every capture in {name} is gone, and its file is "
                      f"missing or empty. Restore it. Do not record a "
                      f"generation: a set with no captures is not a later "
                      f"version of one, and recording it would turn this "
                      f"check green over a set that is not there.",
                      file=sys.stderr)
                continue
            nxt = int(rows[name]["generation"]) + 1 if name in rows else 1
            print(f"  Editing a capture of a set that has already been scored "
                  f"opens a new generation. If that is what this is, run\n"
                  f"    python3 Tools/CorpusRunner/everyday/generation-check.py"
                  f" --record {name} {nxt}\n"
                  f"  then write that generation's row in {name}/README.md: "
                  f"what changed, and which numbers no longer compare across "
                  f"it. If it is not what this is, put the captures back.",
                  file=sys.stderr)
        elif len(set(here.get(name, []))) != len(here.get(name, [])):
            #: Two captures with identical text. `difference` is set-based, so
            #: the hashes still match and only the count moves — which would
            #: otherwise land in the branch below and blame the manifest for
            #: an edit to the set. No set has a duplicate today; the sentence
            #: would have been wrong the first time one did.
            failed = True
            duplicates = len(here[name]) - len(set(here[name]))
            print(f"generation-check FAILED: {name} has "
                  f"{captures(duplicates)} whose text is identical to another "
                  f"capture in the same set. Two copies of one capture are one "
                  f"measurement counted twice; give it its own wording or "
                  f"remove it. The manifest is not at fault.", file=sys.stderr)
        elif name in rows and int(rows[name]["captures"]) != len(here.get(name, [])):
            failed = True
            print(f"generation-check FAILED: {name} has {len(here.get(name, []))} "
                  f"captures but generations.tsv records "
                  f"{rows[name]['captures']}, while every capture hash "
                  f"matches. The manifest has been edited by hand; correct "
                  f"the count rather than re-recording.", file=sys.stderr)
    if failed:
        return 1
    for name in sorted(here):
        generation = rows[name]["generation"] if name in rows else "?"
        print(f"{name:<12} generation {generation:<3} "
              f"{len(here[name]):>4} captures  unchanged")
    print()
    print("generation check ok: no sealed capture has been edited since it was "
          "scored.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
