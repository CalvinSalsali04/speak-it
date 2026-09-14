#!/usr/bin/env python3
"""Everything a reviewer needs about a sealed set, without reading one capture.

A sealed set arrives in a pull request, and a pull request has to be reviewed.
On 2026-09-14 that meant the thread which owns parser changes read all
fifty-six captures of the consequence set in the diff, spending the set as
blind evidence for every change after that one. Nobody was careless. There was
simply no way to check the set without looking at it.

There is now. What a reviewer actually has to establish is structural:

  - the row count matches what the README claims
  - ids are unique, and so are utterances, so no row is scored twice
  - every row has the same number of columns
  - the label vocabulary is closed, and each label's population is reported
  - a per-block breakdown, so a connector rotation claimed in advance can be
    checked against what was written
  - nothing in the file is empty where it must not be

None of that requires a human to read a capture, so this prints none. It
reports lengths, counts and hashes. The one place text could leak is an error
message naming a bad row, so rows are named by id and column, never by value.

Usage:
    python3 Tools/CorpusRunner/corpus-shape.py <tsv> [--blocks N]

`--blocks N` groups ids into consecutive runs of N by their trailing number,
which is how the consequence set's connector rotation is expressed.
"""
import collections
import hashlib
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import corpus_paths  # noqa: E402  (after the path insert, which it needs)


#: A line is the header if it names the utterance column. Nothing weaker
#: works: `heldout.tsv` writes its header inside a comment, `everyday.tsv`
#: writes it as an ordinary first line, and a file's first data row is a
#: perfectly plausible header to anything that just takes line one. Counting
#: everyday's header as a capture reported 256 rows for a 255-capture set,
#: which is the off-by-one a reviewer would wave through.
#:
#: That rule used to live here, spelled out a third time. It is in
#: `corpus_paths` now, with the other twelve readers being moved onto it, for
#: the reason this tool exists: a property a reviewer trusts instead of
#: reading the file has to be computed the same way everywhere, and this file
#: contributed two of the four defects the move was written for.
def read(path):
    """Rows and the header, however the file happens to write it."""
    lines = pathlib.Path(path).read_text(encoding="utf-8").splitlines()
    return ([cells for _number, cells in corpus_paths.data_rows(path)],
            corpus_paths.header_row(lines))


def digest(values):
    """A stable fingerprint of content, so two files can be compared unread."""
    h = hashlib.sha256()
    for v in values:
        h.update(v.encode("utf-8"))
        h.update(b"\0")
    return h.hexdigest()[:16]


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    path = pathlib.Path(argv[0])
    block = None
    if "--blocks" in argv:
        block = int(argv[argv.index("--blocks") + 1])
    rows, header = read(path)

    problems = []
    print(f"{path}")
    print(f"  rows                {len(rows)}")
    print(f"  columns in header   {len(header) if header else 'no header found'}")
    if header:
        print(f"  header              {' | '.join(header)}")

    widths = collections.Counter(len(r) for r in rows)
    if len(widths) == 1:
        print(f"  columns per row     {next(iter(widths))}, uniform")
    else:
        print(f"  columns per row     RAGGED: {dict(widths)}")
        for r in rows:
            if len(r) != widths.most_common(1)[0][0]:
                problems.append(f"{r[0]}: has {len(r)} columns")

    ids = [r[0] for r in rows]
    dupe_ids = [i for i, n in collections.Counter(ids).items() if n > 1]
    print(f"  unique ids          {len(set(ids))}"
          f"{'' if not dupe_ids else '  DUPLICATES: ' + ', '.join(sorted(dupe_ids))}")
    if dupe_ids:
        problems.append(f"duplicate ids: {sorted(dupe_ids)}")

    #: The utterance column is READ FROM THE HEADER, never assumed. Corpora
    #: here do not agree: the development sets and `heldout.tsv` keep the
    #: utterance second, `everyday.tsv` keeps it third. A scan that hard-coded
    #: column two reported that the everyday set contained no instance of the
    #: word "so", and the real answer was 34 -- it had been reading the family
    #: column, which of course contains no prose. Zero is the one result that
    #: looks the same whether the scan worked, so a tool whose whole purpose is
    #: to let a reviewer skip reading the file must not guess where to look.
    column = corpus_paths.column_of(
        pathlib.Path(path).read_text(encoding="utf-8").splitlines(), "utterance")
    if column is None:
        problems.append("no column named 'utterance' in the header, so this "
                        "tool cannot tell which field holds the captures and "
                        "refuses to report on content rather than guess")
    elif widths and next(iter(widths)) > column:
        texts = [r[column] for r in rows]
        print(f"  utterance column    {column} (from the header, not assumed)")
        seen = collections.Counter(texts)
        dupe_text = sorted(rows[i][0] for i, t in enumerate(texts) if seen[t] > 1)
        print(f"  unique utterances   {len(set(texts))}"
              f"{'' if not dupe_text else '  DUPLICATED AT: ' + ', '.join(dupe_text)}")
        if dupe_text:
            problems.append(f"rows sharing an utterance: {dupe_text}")
        lengths = sorted(len(t) for t in texts)
        print(f"  utterance length    min {lengths[0]}, median "
              f"{lengths[len(lengths)//2]}, max {lengths[-1]} characters")
        print(f"  content fingerprint {digest(texts)}")
        #: `r[column]`, not `r[1]`. This read column one until 2026-09-14, so
        #: on `everyday.tsv` -- the one corpus that keeps its utterance third
        #: -- it checked the `domain` column, which is never empty. A check
        #: that cannot fail is indistinguishable from one that passes, and it
        #: sat six lines under a comment saying the column is never assumed.
        blank = [r[0] for r in rows if not r[column].strip()]
        if blank:
            problems.append(f"rows with an empty utterance: {blank}")

    #: Every column after the utterance is a label, and a label column is only
    #: useful if its vocabulary is small and closed. Printing the population of
    #: each value is what lets a reviewer check a balance claimed in a README.
    for col in range(0, next(iter(widths), 0)):
        if col == 0 or col == column:
            continue
        name = header[col] if header and col < len(header) else f"column {col}"
        values = collections.Counter(r[col] for r in rows)
        if len(values) > 12:
            print(f"  {name:<18}  {len(values)} distinct values (not a label column)")
            continue
        rendered = ", ".join(f"{v or '(empty)'}={n}" for v, n in sorted(values.items()))
        print(f"  {name:<18}  {rendered}")

    if block:
        print(f"\n  blocks of {block}, by the trailing number in each id:")
        def number(i):
            m = re.search(r"(\d+)$", i)
            return int(m.group(1)) if m else 0
        numbered = sorted(rows, key=lambda r: number(r[0]))
        last = next(iter(widths)) - 1
        for start in range(0, len(numbered), block):
            chunk = numbered[start:start + block]
            counts = collections.Counter(r[last] for r in chunk)
            spread = " ".join(f"{k}={v}" for k, v in sorted(counts.items()))
            print(f"    {chunk[0][0]}-{chunk[-1][0]}  n={len(chunk):<3} {spread}")

    print()
    if problems:
        for p in problems:
            print(f"  PROBLEM: {p}")
        print(f"\ncorpus shape: {len(problems)} problem(s). "
              f"No capture text was printed.")
        return 1
    print("corpus shape ok. No capture text was printed, so a reviewer can "
          "check these properties\nwithout spending the set.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
