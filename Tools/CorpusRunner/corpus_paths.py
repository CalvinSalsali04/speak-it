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
