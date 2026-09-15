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


# --- Which lines are data, and which column holds the utterance -------------
#
# Four separate defects have come from four readers working this out again:
#
#   * `heldout/score.sh` cut column two off EVERY line, so a commented header's
#     second cell -- the bare word `utterance` -- was fed to the probe as a
#     390th capture.
#   * A one-off scan hard-coded column two and reported that the everyday set
#     contains no instance of the word "so". It keeps its utterance in column
#     THREE, so the scan had been counting a label column, and the answer it
#     gave was wrong rather than merely small. What the right answer is does
#     not belong here: it is an aggregate over a sealed set's content, and a
#     fact of that kind, sitting in a file every reader opens, is available to
#     size the next change. The lesson needs only that the scan was wrong.
#   * `corpus-shape.py` counted `everyday.tsv`'s header as a row and reported
#     256 rows for a 255-capture set.
#   * And `corpus-shape.py` had to solve the whole problem from scratch to do
#     it, as did `leak-check.py`, `heldout/score.py` and `everyday/score.py`,
#     by four different mechanisms.
#
# The mechanism that is right already existed, in `everyday/leak-check.py`,
# which is the wrong place for it: one owner, in the module that already owns
# which files exist.
#
# The asymmetry that causes it is worth naming, because it is one file wide.
# Every corpus here comments its header EXCEPT `everyday.tsv`, which writes it
# as an ordinary first line. So `startswith("#")` is correct ten times out of
# eleven, which is the worst possible hit rate for a rule people copy.

#: The cell that identifies a header line, in any of the layouts here.
HEADER_KEY = "utterance"


def cells_of(line):
    """A line's cells as written, stripped, with any leading `#` removed."""
    return [cell.strip() for cell in line.lstrip("#").strip().split("\t")]


def header_cells(line):
    """A line's cells lowered, which is the form column names are matched in."""
    return [cell.lower() for cell in cells_of(line)]


def header_row(lines):
    """The header's column names as written, or None when there is no header.

    `header_cells` lowers, because matching a name should not care how it was
    typed. A tool printing the header for a reviewer wants it as written, and
    lowering it there is how a display starts disagreeing with the file.
    """
    head = header_index(lines)
    return None if head is None else cells_of(lines[head])


def header_index(lines):
    """Index of the line that carries the column names, or None.

    The header is the line naming `utterance`, rather than the first line or
    the commented one, because those two rules disagree across this directory
    and each is right somewhere.
    """
    for number, line in enumerate(lines):
        if HEADER_KEY in header_cells(line):
            return number
    return None


def column_of(lines, name):
    """Index of a named column, read from the header line.

    From *the* header line, not from whichever line happens to carry the word.
    Two columns resolved by two independent scans can land on two different
    lines: a data cell reading `id` is a header as far as an id lookup is
    concerned while the utterance lookup uses the real one, and every row then
    reports the same id. That reads as a corpus with duplicate ids rather than
    as a reader that lost track of which line it was on.

    Returns None when the header does not name it, or when there is no header.
    Callers that need the utterance column should use `utterance_column`,
    which refuses instead: `column_of(...) or 0` is how a missing header
    quietly becomes column one.
    """
    head = header_index(lines)
    if head is None:
        return None
    cells = header_cells(lines[head])
    return cells.index(name) if name in cells else None


def utterance_column(lines):
    """Which column a corpus file keeps its utterances in.

    Raises rather than returning None. A corpus file with no header is not a
    file whose utterances live in column two; it is a file this cannot read,
    and guessing is the defect above rather than a fallback for it.
    """
    column = column_of(lines, HEADER_KEY)
    if column is None:
        raise ValueError(
            "no line in this file names an `utterance` column, so which column "
            "holds the capture is unknown. Assuming one is how a scan came to "
            "report that a corpus contained no instance of a word it uses 34 "
            "times. Add a header rather than defaulting.")
    return column


def id_column(lines):
    """Which column carries the row id.

    Raises, for the same reason `utterance_column` does and one the leak check
    made concrete: its prose half exists to **name** a leak without printing
    it, so an id that silently arrives as the empty string turns the one safe
    report into one that says a sealed capture is committed somewhere and
    cannot say which. Absent is not column zero, and it is not "".
    """
    column = column_of(lines, "id")
    if column is None:
        raise ValueError(
            "no line in this file names an `id` column, so its rows cannot be "
            "named. A row that cannot be named cannot be reported without "
            "printing it, which for a sealed set is the thing being avoided.")
    return column


def data_rows(path):
    """Yields (line number, cells) for the rows that are data.

    A row is data when it is not blank, not a comment, and not the header --
    the header identified by the cells it names rather than by being first or
    by being commented, because those two rules disagree across this directory
    and each is right somewhere.
    """
    lines = pathlib.Path(path).read_text(encoding="utf-8").splitlines()
    head = header_index(lines)
    for number, line in enumerate(lines):
        if number == head or line.startswith("#") or not line.strip():
            continue
        yield number + 1, line.split("\t")


def utterances(path):
    """Yields (line number, id, utterance) for every data row of a corpus file.

    The two questions answered together, which is how they are always asked.
    """
    lines = pathlib.Path(path).read_text(encoding="utf-8").splitlines()
    column = utterance_column(lines)
    ids = id_column(lines)
    for number, cells in data_rows(path):
        if len(cells) <= max(column, ids):
            # Refused rather than skipped. A dropped row is a denominator one
            # smaller and no message, on exactly the row worth knowing about:
            # the file reads as clean and one capture shorter, and every rate
            # computed from it is quietly wrong. No corpus file here has a
            # short row today, so this costs nothing until one appears.
            raise ValueError(
                f"{pathlib.Path(path).name} line {number}: {len(cells)} "
                f"cell(s), but the utterance is column {column + 1} and the id "
                f"is column {ids + 1}. A row this reader cannot parse is not a "
                f"row to skip.")
        if not cells[ids].strip():
            # Refusing the missing column and not the missing value is the
            # half-measure this repository keeps writing. A row whose id cell
            # is empty cannot be named either, and the caller that most needs
            # the name had a `cid or "?"` standing in for it -- a placeholder
            # for an id, in the one report whose whole safety property is that
            # it names a leak instead of printing it.
            raise ValueError(
                f"{pathlib.Path(path).name} line {number}: the id cell "
                f"(column {ids + 1}) is empty, so this row cannot be named. "
                f"An unnamed row cannot be reported without printing it.")
        yield number, cells[ids].strip(), cells[column]


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
