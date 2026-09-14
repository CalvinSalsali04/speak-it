"""The one place that knows which corpus files are readable and which are sealed.

Every scan in this repository asks one of two questions — "what does readable
material contain?" or "has a sealed capture leaked?" — and until now each scan
answered by globbing and remembering. That fails in both directions and both
have now happened:

  * too narrow. `leak-check.py` looped a `SEALED` list that did not contain
    `heldout.tsv`, so the set carrying the published destination figure was
    compared against and never checked. `devset-failures.sh` kept its own list
    of development sets and `rambling.tsv` reached one runner and not the
    other.

  * too wide. A scan answering a question about readable material was pointed
    at every `*.tsv` under this directory and printed a sealed capture into an
    agent's session. Nothing was inspected and no rule changed, but the row is
    recorded in `everyday/leak-check.py` because the denominator's job is to
    say what has been seen.

So the repair is here rather than in any one scan: ask for `readable()` and you
are handed a list that cannot contain a sealed file. Reaching sealed material
takes naming `sealed()`, which is a thing a reviewer can grep for.

The guard that makes it more than a convention is `unclassified()`. A shared
list still silently omits a set nobody added to it; a classification that must
be **total** cannot. `Tools/CorpusRunner/test_score.py` fails the run if any
`*.tsv` under this directory is in neither list, so adding a corpus and
forgetting to classify it is a failure rather than a quiet omission.
"""
import pathlib

HERE = pathlib.Path(__file__).resolve().parent

#: Sealed sets. Scored, never read while rules are being changed. Reaching
#: these takes calling `sealed()` by name.
SEALED_NAMES = {
    "everyday/everyday.tsv",
    "adversarial/adversarial.tsv",
    "heldout/heldout.tsv",
    "consequence/consequence.tsv",
}

#: Development sets. Written to be read: read the failures, fix the layer, run
#: it again.
READABLE_NAMES = {
    "devsets/abandonment.tsv",
    "devsets/coordination.tsv",
    "devsets/framing.tsv",
    "devsets/rambling.tsv",
    "devsets/routed.tsv",
    "devsets/runon.tsv",
    "devsets/unfinished.tsv",
}

#: Not corpora at all. `generations.tsv` is the record of when each sealed set
#: was last scored; it holds no utterances. Listed rather than ignored, because
#: "everything else is fine" is how a corpus goes unclassified.
MANIFEST_NAMES = {
    "generations.tsv",
}


def sealed():
    """The sealed label files. Never pass these to a scan about readable text."""
    return sorted(HERE / name for name in SEALED_NAMES)


def readable():
    """The development sets, and nothing that is sealed.

    The filter at the end is not redundant with `READABLE_NAMES`. It is the
    property the caller is relying on, asserted at the point of return rather
    than trusted to whoever last edited the list above.
    """
    out = sorted(HERE / name for name in READABLE_NAMES)
    return [path for path in out if path not in set(sealed())]


def unclassified(root=None):
    """Every `*.tsv` under `root` that is in none of the three lists.

    Must be empty. This is the whole reason the lists are worth having: a
    convention omits silently, and a total classification cannot.

    `root` exists so a test can point this at a directory holding a stray file
    without creating one in the repository. The declared set is always the real
    one, so a test cannot accidentally make the check pass by declaring its own.
    """
    root = pathlib.Path(root) if root else HERE
    declared = {HERE / name
                for name in SEALED_NAMES | READABLE_NAMES | MANIFEST_NAMES}
    return sorted(path for path in root.rglob("*.tsv") if path not in declared)


def missing():
    """Declared files that are not on disk, so a deletion cannot pass silently."""
    declared = sorted(HERE / name
                      for name in SEALED_NAMES | READABLE_NAMES | MANIFEST_NAMES)
    return [path for path in declared if not path.exists()]


def searchable(root=None):
    """Every file it is safe to search, which is every file except the sealed ones.

    This exists because the record of the first exposure caused the second one,
    within two hours. A capture id is safe to *store* and unsafe to *grep*: the
    sealed file is the one place an id sits beside its text, so any recursive
    search from the repository root turns the record into a lookup key and
    hands back the row. The person who did it was checking that the record
    existed.

    "Do not grep an id from the root" is a true sentence and the weakest kind
    of guard there is -- a rule somebody has to remember, competing with a
    command that is shorter to type. So the safe search is the easy one:

        python3 Tools/CorpusRunner/corpus_paths.py --grep C283

    searches everything except the three sealed files and cannot return a
    sealed row. It is not a sandbox and does not try to be; `grep -r` still
    exists. It removes the reason to reach for it.

    One honest limit: a sealed capture already quoted in a tracked document is
    findable here, because the document is readable material. That is the
    sixteen occurrences `leak-check.py` counts on every run, not a new hole.
    """
    root = pathlib.Path(root) if root else HERE.parents[1]
    forbidden = set(sealed())
    out = []
    for path in root.rglob("*"):
        if not path.is_file() or ".git" in path.parts:
            continue
        if path in forbidden or path.resolve() in {q.resolve() for q in forbidden}:
            continue
        out.append(path)
    return sorted(out)


#: A string that exists, in this file, so that a scan finding nothing can be
#: told apart from a scan that is broken.
#:
#: **Zero is the one result that looks identical whether the scan worked or
#: not.** Every other number invites "is that right?"; zero invites "good".
#: Not hypothetical: a one-off scan for the word "so" across the corpora
#: hard-coded column two, and `everyday.tsv` keeps its utterance in column
#: three, so it searched the wrong field, returned zero, and that zero was
#: published as "the everyday set contains no instance of it". The real answer
#: is 34. What caught it was a README describing eighteen filler captures,
#: which cannot coexist with zero disfluency markers -- a document, not an
#: instrument.
#:
#: So every search here proves it can find something before it reports finding
#: nothing. The canary costs one pass over material already being read, and it
#: refuses to report rather than returning an empty result.
SELF_CHECK = "corpus-paths-canary-do-not-delete"


def _scan(pattern, root=None):
    """Every (path, line number, line) in readable material matching `pattern`."""
    import re
    matcher = re.compile(pattern)
    for path in searchable(root):
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for number, line in enumerate(text.splitlines(), 1):
            if matcher.search(line):
                yield path, number, line


def scan_is_working(root=None):
    """Whether a search here can find a string known to be in readable material.

    The known-positive is `SELF_CHECK`, which sits in this file, and this file
    is readable material. A scan that cannot find it is not reading what it
    thinks it is reading, and its zero means nothing.
    """
    return any(_scan(SELF_CHECK, root))


def _grep(pattern, root=None):
    """`--grep`: the readable-only search, as path:line:text."""
    if not scan_is_working(root):
        print("corpus-paths: the search cannot find a string that is in its own "
              "source, so it is not reading what it thinks it is reading. Any "
              "result below, especially a zero, means nothing. Fix the traversal "
              "before trusting it.")
        return 2
    hits = 0
    for path, number, line in _scan(pattern, root):
        hits += 1
        print(f"{path}:{number}: {line.strip()[:200]}")
    print(f"\n{hits} match(es) in readable material. "
          f"{len(sealed())} sealed files were not searched, by construction, "
          f"and the search was confirmed able to find a known string first.")
    return 0 if hits else 1


if __name__ == "__main__":
    import sys
    if len(sys.argv) == 3 and sys.argv[1] == "--grep":
        sys.exit(_grep(sys.argv[2]))
    print(f"sealed        {len(sealed())}")
    print(f"readable      {len(readable())}")
    print(f"unclassified  {len(unclassified())}  (must be 0)")
    print(f"missing       {len(missing())}  (must be 0)")
    print("\nsearch readable material with:  "
          "python3 Tools/CorpusRunner/corpus_paths.py --grep PATTERN")
