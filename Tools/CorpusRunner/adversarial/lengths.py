"""Whether each pairing can be read against its ingredients at all.

`README.md` in this directory tells the reader to judge a pairing against the
families it is built from, never on its own. That instruction is only safe
where the two are comparable *inputs*, and the set's first reading proved they
are not always. `runon-x-repair` scored 8/12 on routing where the everyday
`run-on` family scored 0/8 — which looks like combination being easier than its
ingredient, and is in fact a pairing written at roughly half its ingredient's
length, with ranges that do not overlap at all.

So: for every pairing, and every family its captures are tagged with, compare
the word counts. Disjoint ranges are the hard verdict — that comparison cannot
be made and the row must not be read against that ingredient. Overlapping
ranges are not a clean bill of health; they only fail to prove the two
incomparable, which is why the median ratio is printed beside them rather than
folded into a pass or a fail. A threshold that blocked a merge here would be a
number people learn to write around.

Everything is counted from the labels — the utterance's word count — so running
this unseals nothing. No failure is read and no scorer is invoked.

    python3 Tools/CorpusRunner/adversarial/lengths.py

prints the table `README.md` carries, in markdown, so it can be regenerated
rather than kept in step by hand.
"""
import pathlib
import statistics

HERE = pathlib.Path(__file__).resolve().parent
RUNNER = HERE.parent

#: Each labelled set, with the columns it actually uses. `heldout.tsv` writes
#: its header as a comment line and the other two write an ordinary first row,
#: so the layout is stated here rather than guessed from whichever line comes
#: first — guessing is how a check ends up reading the wrong column and passing
#: for the wrong reason.
SETS = {
    "adversarial": (HERE / "adversarial.tsv",
                    ["id", "pair", "utterance", "expect", "keep", "reject",
                     "families", "note"]),
    "heldout": (RUNNER / "heldout" / "heldout.tsv",
                ["id", "utterance", "family", "expected_destination",
                 "expected_thoughts"]),
    "everyday": (RUNNER / "everyday" / "everyday.tsv",
                 ["id", "domain", "utterance", "expect", "keep", "reject",
                  "families", "note"]),
}

#: The order ingredient sources are reported and searched in. `heldout/` first
#: because its families are the ones the pairings were built from; `everyday/`
#: second because it tags the same families on natural-length speech and is
#: often the comparable row where the held-out one is not.
SOURCES = ("heldout", "everyday")


def read(name):
    """Every data row of one set, as dicts. Missing sets yield nothing."""
    path, header = SETS[name]
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("#") or line.split("\t") == header:
            continue
        yield dict(zip(header, line.split("\t")))


def words(row):
    return len(row["utterance"].split())


def pairings():
    """Pairing name -> the word counts of its captures."""
    out = {}
    for row in read("adversarial"):
        out.setdefault(row["pair"], []).append(words(row))
    return out


def ingredients():
    """Pairing name -> the families its captures are tagged with.

    Read from the captures rather than from the pairing's name, because a
    capture may carry a third tag the name does not mention: two `reported-x-op`
    captures exclude a value with "not" and are tagged `negation` as well.
    """
    out = {}
    for row in read("adversarial"):
        out.setdefault(row["pair"], set()).update(row["families"].split("|"))
    return out


def families(name):
    """Family -> the word counts of its captures, in one ingredient source."""
    out = {}
    for row in read(name):
        tags = row["family"].split("|") if "family" in row else \
            row["families"].split("|")
        for tag in tags:
            out.setdefault(tag, []).append(words(row))
    return out


def disjoint(a, b):
    return max(a) < min(b) or max(b) < min(a)


def comparisons():
    """Every (pairing, ingredient, source) comparison the set makes possible.

    Yields `(pair, pair_lengths, family, source, family_lengths)`. A family the
    source does not carry is simply absent — `heldout/` has no `date` family and
    `everyday/` has no `ellipsis` family, and neither absence is an error.
    """
    pairs, ings = pairings(), ingredients()
    tables = {name: families(name) for name in SOURCES}
    for pair in sorted(pairs):
        for family in sorted(ings[pair]):
            for source in SOURCES:
                if family in tables[source]:
                    yield pair, pairs[pair], family, source, tables[source][family]


def unreadable(stream=None):
    """The (pairing, ingredient) comparisons that cannot be made at all.

    A pairing is unreadable against an ingredient only when *every* source
    carrying that family is disjoint from it. One disjoint source is not
    enough: where `heldout/` is written short and `everyday/` at natural
    length, the second row is the comparable one and the pairing can still be
    read — against that row, and the reader has to be told which.

    `stream` replaces the committed sets with comparisons of the caller's own,
    so that rule can be tested: no pairing in the set today is disjoint from
    one source and overlapping in another, which would leave the branch that
    matters covered by nothing.
    """
    verdicts = {}
    for pair, lengths, family, _, theirs in (comparisons() if stream is None
                                             else stream):
        verdicts.setdefault((pair, family), []).append(disjoint(lengths, theirs))
    return {key for key, seen in verdicts.items() if all(seen)}


def number(value):
    """Medians land on .0 for odd counts; the trailing zero is just noise."""
    return f"{value:g}"


def table():
    print("| pairing | median words | ingredient | in | n | median | range "
          "| comparable? |")
    print("|---|---|---|---|---|---|---|---|")
    current = None
    for pair, lengths, family, source, theirs in comparisons():
        if pair != current:
            head = (f"`{pair}` | {number(statistics.median(lengths))} "
                    f"({min(lengths)}–{max(lengths)})")
            current = pair
        else:
            head = " | "
        ours, mine = statistics.median(lengths), statistics.median(theirs)
        if disjoint(lengths, theirs):
            verdict = "**no — ranges disjoint**"
        else:
            ratio = ours / mine
            # "1.0x shorter" is noise dressed as a finding: below the first
            # decimal the two medians are the same length.
            direction = "" if round(ratio, 1) == 1.0 else \
                (" longer" if ratio > 1 else " shorter")
            verdict = f"{ratio:.1f}×{direction}"
        print(f"| {head} | `{family}` | `{source}/` | {len(theirs)} "
              f"| {number(mine)} | {min(theirs)}–{max(theirs)} | {verdict} |")


if __name__ == "__main__":
    table()
    for pair, family in sorted(unreadable()):
        print(f"\nunreadable: `{pair}` cannot be read against `{family}` — "
              f"no source carrying that family overlaps its length range.")
