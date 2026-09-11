"""Fails if a held-out capture also lives in a corpus that gets tuned against.

The everyday set is only worth keeping if nothing in it has been used to
develop a rule. That is easy to break by accident — an utterance gets quoted in
a finding, someone adds it to a dev set, and the benchmark quietly stops
measuring generalisation. This check makes the boundary mechanical instead of a
promise, and it is why `Tools/CorpusRunner/everyday/test_score.py` runs it.

It compares against every corpus that development touches: the gating semantic
corpus, the development sets, and the older held-out set (a capture shared with
that one is not contaminated, but it is a duplicate measurement, so it is
reported too).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
THRESHOLD = 0.70

#: Prose is checked for *verbatim* sealed captures, and only for captures at
#: least this many words long. A short capture -- "call mum", "buy milk" -- can
#: appear in a sentence somebody wrote about something else, and a check that
#: cries leak on those gets switched off. So the coverage is stated rather than
#: implied: **a sealed capture shorter than this is not protected in prose.**
#: Every capture in all three sealed sets that is shorter than this is counted
#: and printed on every run, so the size of the gap is visible instead of
#: inferred.
PROSE_MIN_WORDS = 6

#: Captures already public in tracked prose when this check was written, each
#: with where it is and why it is forgiven rather than fixed. **The marker moves
#: the exit status, never the count**: every one is still reported as a leak on
#: every run, for the same reason a `KNOWN:` row in `abandonment.tsv` is still
#: counted as a failure -- a rate a marker can improve is a rate people learn to
#: write markers for.
#:
#: These cannot be un-leaked. The text is in git history, so deleting it from
#: the document restores nothing; the only real remedy is to retire the captures
#: from the sealed sets and re-record the generation, which moves published
#: figures and is therefore Calvin's call rather than this file's. Until that is
#: decided they are listed here so the check can gate on anything *new* instead
#: of being switched off for being red on arrival.
PROSE_DOCUMENTED = {
    # The everyday set (authored 2026-09-11) reuses sentences from a sweep
    # written 2026-08-25. These were development material first and sealed
    # captures second, which is the direction that costs a measurement.
    ("everyday.tsv", "F02"): "PipelineSweep/domains.md — negation table",
    ("everyday.tsv", "F06"): "PipelineSweep/domains.md — negation table",
    ("everyday.tsv", "F19"): "PipelineSweep/domains.md — negation table",
    ("everyday.tsv", "F29"): "PipelineSweep/domains.md — negation table",
    ("everyday.tsv", "M04"): "PipelineSweep/domains.md — negation table",
    ("everyday.tsv", "W17"): "PipelineSweep/domains.md",
    ("everyday.tsv", "W20"): "PipelineSweep/domains.md — negation table",
    ("everyday.tsv", "W51"): "PipelineSweep/domains.md, LANGUAGE_BASELINE.md, "
                             "and this set's own README",
    # The held-out set (2026-08-25) came first and later documentation
    # reproduced these. C342 is the standard location-reminder example in the
    # App Store and hand-QA documents, so it has been run by hand repeatedly.
    ("heldout.tsv", "C236"): "PipelineSweep/routing.md — question table",
    ("heldout.tsv", "C342"): "five App Store and hand-QA documents",
    ("heldout.tsv", "C358"): "AMBIGUITY_TAXONOMY.md",
}

# Every set that must stay unseen. Each is checked against the tuned corpora
# and against the other sealed sets: an overlap with another sealed set is not
# contamination, but it is the same capture measured twice under two names.
SEALED = [
    HERE / "everyday.tsv",
    ROOT / "Tools/CorpusRunner/adversarial/adversarial.tsv",
]


def norm(text):
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def mine(path):
    """The sealed set's own captures, keyed by normalised text.

    Reads the utterance column from the header for the same reason `harvest`
    does: a hard-coded index is correct until a set is laid out differently,
    and then this compares the wrong field and passes for the wrong reason.
    The registry test will happily register such a set, so this side has to be
    layout-independent too.
    """
    lines = Path(path).read_text().splitlines()
    column = column_of(lines, "utterance")
    if column is None:
        raise SystemExit(
            f"leak check: {Path(path).name} has no column headed 'utterance'")
    ids = column_of(lines, "id") or 0
    out = {}
    for line in lines:
        parts = line.split("\t")
        if line.startswith("#") or not line.strip() or len(parts) <= column:
            continue
        if parts[column].strip().lower() == "utterance":
            continue
        out[norm(parts[column])] = parts[ids] if len(parts) > ids else "?"
    return out


def column_of(lines, name):
    """Index of a named column, read from whichever line carries the header."""
    for line in lines:
        fields = [f.strip().lower() for f in line.lstrip("#").strip().split("\t")]
        if name in fields:
            return fields.index(name)
    return None


def utterance_column(lines):
    """Finds the column a corpus file keeps its utterances in.

    Corpora in this repository do not agree on layout: `heldout.tsv` and the
    development sets put the utterance second, `everyday.tsv` puts it third,
    and `heldout.tsv` writes its header inside a comment. Hard-coding a column
    is how this check silently starts comparing the wrong field and passing for
    the wrong reason — which is worse than failing, because a leak check that
    cannot fail reads as proof. So the header is read instead.
    """
    return column_of(lines, "utterance")


def harvest(path):
    """Every utterance in one corpus file."""
    text = path.read_text(errors="ignore")
    if path.suffix != ".tsv":
        # Swift corpus sources: any string literal long enough to be a capture.
        return re.findall(r'"([^"\\]{12,})"', text)

    lines = text.splitlines()
    column = utterance_column(lines)
    if column is None:
        raise SystemExit(
            f"leak check: {path.name} has no column headed 'utterance', so the "
            f"capture to compare cannot be identified. Add the header rather "
            f"than letting this file go unchecked.")
    out = []
    for line in lines:
        if line.startswith("#") or not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) <= column or fields[column].strip().lower() == "utterance":
            continue
        out.append(fields[column])
    return out


#: All three, and `heldout.tsv` deliberately among them. The overlap check
#: below treats the held-out set as one more corpus to compare against, which
#: is right for *that* question -- a shared capture there is a duplicate
#: measurement, not contamination. It is wrong for this one. The first sealed
#: capture ever committed into a tracked document was a held-out row, and a
#: list that left it out would have watched the other two.
SEALED_ALL = SEALED + [ROOT / "Tools/CorpusRunner/heldout/heldout.tsv"]

#: Where prose lives. Not "every tracked file": the corpora themselves are full
#: of capture text by design, and so is any file this check already reads.
PROSE_SKIP = {".git", "node_modules", "build", "output", "tmp", "DerivedData"}


def prose_files():
    """Every Markdown file in the repository, which is where prose goes.

    Deliberately not narrowed to `Docs/`. The leak this was written for landed
    in `Docs/LANGUAGE_BASELINE.md`, but a README beside a corpus is the more
    tempting place to quote a capture, and `CLAUDE.md` is read by every agent
    that touches this repository.
    """
    for path in sorted(ROOT.rglob("*.md")):
        if PROSE_SKIP & set(path.relative_to(ROOT).parts):
            continue
        yield path


def flatten(text):
    """Normalised to one line, so a capture wrapped across lines still matches.

    This is the part that is easy to get wrong and impossible to notice: prose
    wraps, and a capture quoted in a paragraph is routinely split over two
    lines. Normalising per line would let every wrapped quotation through, and
    the check would pass on exactly the cases a human reader would call the
    most obvious leaks.
    """
    return " " + re.sub(r"[^a-z0-9]+", " ", text.lower()).strip() + " "


def check_prose():
    """Sealed capture text committed into the repository's prose.

    Separate from the overlap check above because it answers a different
    question. That one asks whether a sealed capture was tuned against; this
    asks whether it is still sealed at all. A capture pasted into a document is
    not contaminating a corpus -- it is simply public, in git history, for good.

    Prints ids and files and never the capture text. A leak detector whose
    output quotes the thing it found would copy the leak into every CI log.
    """
    short = 0
    captures = []
    for path in SEALED_ALL:
        if not path.exists():
            continue
        for cid, text in harvest_ids(path):
            words = norm(text).split()
            if len(words) < PROSE_MIN_WORDS:
                short += 1
                continue
            captures.append((path.name, cid, " " + " ".join(words) + " "))

    hits = []
    for doc in prose_files():
        try:
            body = flatten(doc.read_text(encoding="utf-8", errors="ignore"))
        except OSError:
            continue
        for set_name, cid, needle in captures:
            if needle in body:
                hits.append((doc.relative_to(ROOT), set_name, cid,
                             len(needle.split())))

    print()
    print("=== sealed capture text in tracked prose")
    print(f"documents scanned        {len(list(prose_files()))}")
    print(f"captures long enough     {len(captures)}")
    print(f"too short to protect     {short}  (under {PROSE_MIN_WORDS} words)")
    documented = [h for h in hits if (h[1], h[2]) in PROSE_DOCUMENTED]
    fresh = [h for h in hits if (h[1], h[2]) not in PROSE_DOCUMENTED]
    print(f"sealed text in prose      {len(hits)}"
          f"  ({len(documented)} documented, {len(fresh)} new)")
    if not hits:
        print("prose check ok: no sealed capture appears verbatim in a "
              "tracked document.")
        return True

    print()
    for doc, set_name, cid, length in sorted(fresh) + sorted(documented):
        mark = "" if (set_name, cid) in PROSE_DOCUMENTED else "  ← NEW"
        print(f"  LEAK  {doc}  <-  {set_name} {cid}  ({length} words){mark}")

    if documented:
        print()
        print(f"  {len(documented)} of these were already public when this check")
        print("  was written, and are counted above rather than excused:")
        for (set_name, cid), where in sorted(PROSE_DOCUMENTED.items()):
            print(f"    {set_name} {cid}  {where}")
        print("  They cannot be un-leaked -- the text is in history -- so the")
        print("  remedy is to retire them from the sealed sets, which moves")
        print("  published figures and is a decision rather than an edit.")

    if not fresh:
        print()
        print("prose check ok: no NEW sealed capture has been committed into a")
        print("tracked document. The documented ones above still count.")
        return True

    print()
    print("prose check FAILED: a sealed capture is committed into a tracked")
    print("document, which unseals it permanently and in history. Remove the")
    print("text; the id and the shape carry the argument without it.")
    return False


def harvest_ids(path):
    """`(id, utterance)` for one sealed set.

    `harvest` returns utterances alone, which is right for the overlap check --
    it compares text against text. The prose check has to *name* what it found
    without printing it, so it needs the id travelling beside the capture.
    """
    lines = path.read_text(errors="ignore").splitlines()
    column = utterance_column(lines)
    if column is None:
        raise SystemExit(
            f"leak check: {path.name} has no column headed 'utterance', so "
            f"its captures cannot be identified. Add the header rather than "
            f"letting this file go unchecked.")
    out = []
    for line in lines:
        if line.startswith("#") or not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) <= column or fields[column].strip().lower() == "utterance":
            continue
        out.append((fields[0].strip(), fields[column]))
    return out


def others(exclude):
    sources = list((ROOT / "SpeakItTests").glob("SemanticCorpusData*.swift"))
    sources += list((ROOT / "Tools/CorpusRunner/devsets").glob("*.tsv"))
    sources.append(ROOT / "Tools/CorpusRunner/heldout/heldout.tsv")
    sources += [p for p in SEALED if p != exclude]
    found = {}
    for path in sources:
        if not path.exists():
            continue
        for candidate in harvest(path):
            found.setdefault(norm(candidate), path.name)
    return found


def verdict(sources):
    """Which failure this is, in the words that send the reader to the right place.

    An overlap with a tuned corpus means the set has stopped measuring
    generalisation. An overlap between two sealed sets means no such thing —
    nothing has been tuned against either — it means one measurement is being
    counted twice. Printing the first message for the second case sends
    someone hunting a leak that does not exist.
    """
    if sources - {q.name for q in SEALED}:
        return ("leak check FAILED: a held-out capture overlaps a corpus that "
                "is developed against, so it no longer measures generalisation.")
    return ("leak check FAILED: a capture appears in two sealed sets, so one "
            "measurement is being counted as two. Neither set is "
            "contaminated; remove the duplicate from one of them.")


def main():
    """Checks every sealed set, so adding one cannot mean forgetting to check it."""
    failed = 0
    for path in SEALED:
        if not path.exists():
            raise SystemExit(f"leak check: {path} is listed as sealed but missing")
        failed |= check(path)
    #: Runs whatever the overlap check said. The two answer different questions
    #: and a set can pass one while failing the other -- a capture quoted in a
    #: document is still absent from every tuned corpus, which is exactly the
    #: state that let one through.
    for path in SEALED_ALL:
        if not path.exists():
            raise SystemExit(f"leak check: {path} is listed as sealed but missing")
    failed |= 0 if check_prose() else 1
    return failed


def similarities(ours, theirs):
    """One pass over the cross-product, returning what both readers need.

    `ranked` is each capture with the single tuned string it most resembles,
    highest first — the closest-miss report. `near` is every pair at or above
    the threshold, which is a different thing and must stay so: one capture can
    near-duplicate strings in two corpora at once, and `verdict` decides which
    failure to name from the set of sources. Reducing that to the best match
    per capture would drop a tuned source behind a higher-scoring sealed one
    and print "counted twice" for what is actually contamination.
    """
    tuned = [(set(other.split()), other, source)
             for other, source in theirs.items() if len(other.split()) >= 4]
    ranked, near = [], []
    for utterance, cid in ours.items():
        tokens = set(utterance.split())
        if len(tokens) < 4:
            continue
        best = None
        for other_tokens, other, source in tuned:
            overlap = len(tokens & other_tokens) / len(tokens | other_tokens)
            if best is None or overlap > best[0]:
                best = (overlap, other, source)
            if overlap >= THRESHOLD and utterance not in theirs:
                near.append((cid, round(overlap, 2), source, utterance, other))
        if best is not None:
            ranked.append((best[0], cid, utterance, best[2], best[1]))
    return sorted(ranked, reverse=True), near


def check(path):
    ours, theirs = mine(path), others(path)
    exact = [(cid, utterance, theirs[utterance])
             for utterance, cid in ours.items() if utterance in theirs]

    ranked, near = similarities(ours, theirs)

    print(f"=== {path.parent.name}/{path.name}")
    print(f"held-out captures        {len(ours)}")
    print(f"strings from tuned sets  {len(theirs)}")
    print(f"exact collisions         {len(exact)}")
    print(f"near duplicates (>={THRESHOLD})  {len(near)}")
    for cid, utterance, source in exact:
        print(f"  COLLISION  {cid}  also in {source}\n    {utterance}")
    for cid, overlap, source, utterance, other in sorted(near, key=lambda r: -r[1]):
        print(f"  NEAR  {cid}  j={overlap}  {source}\n    held out: {utterance}"
              f"\n    tuned:    {other}")
    if exact or near:
        sources = {src for _, _, src in exact} | {src for _, _, src, _, _ in near}
        print("\n" + verdict(sources), file=sys.stderr)
        return 1
    report_closest(ranked)
    print("\nleak check ok: nothing held out appears in a tuned corpus.")
    return 0


def report_closest(ranked, show=3):
    """The nearest misses, printed on a clean run.

    A pass/fail answer cannot show a set drifting. Two sets both reported
    "clean" are in different states if one tops out at 0.31 and the other at
    0.68, and only the second is one careless capture away from a leak. So the
    closest few are printed even when nothing crosses the line.

    Deliberately not a second threshold. There is no warning band and no
    non-zero exit here, because a number that blocks a merge is a number people
    learn to game — the same reason the scorers in this repository report
    rather than gate. This is for the reader, who can see a set getting closer
    over successive runs and ask why before the check ever fails.
    """
    if not ranked:
        return
    print(f"closest, no leak         j={ranked[0][0]:.2f} (line is {THRESHOLD})")
    for overlap, cid, utterance, source, other in ranked[:show]:
        print(f"  {cid}  j={overlap:.2f}  nearest in {source}"
              f"\n    held out: {utterance}\n    tuned:    {other}")


if __name__ == "__main__":
    sys.exit(main())
