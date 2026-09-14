#!/usr/bin/env python3
"""How often each clause connective appears in material this project may read.

Not a measurement of the parser. It never runs one, and it says nothing about
whether a capture containing `so` is split correctly. It answers one question,
which kept being answered from memory: **is there readable material in which a
given connective appears at all?**

That question decides whether a family can be worked on. Four targets in a row
died of the same cause, and it was not the parser: the readable sets could not
size them, and every example was a sentence this project had written for the
occasion. A count of zero here is the earliest possible warning that a fifth is
about to go the same way.

WHAT A ZERO DOES AND DOES NOT MEAN, because this is the number most likely to
be quoted out of the report that prints it:

  * It does NOT mean people do not say the form. Every row counted here was
    authored by this project, so the census largely records what we have
    thought to write down. Treating a zero as evidence about speech is the
    circular step this file exists to make visible rather than to license.
  * It DOES mean a change aimed at that form cannot be sized, reviewed or
    regression-covered from readable material -- and therefore that the only
    thing shaping it would be a sealed set, which is the one input a parser
    change may not have.

Sealed sets are not read. Sources come from `corpus_paths.readable()` plus a
declared list of SpeechLab files, and the declared list is checked against
`corpus_paths.sealed()` at the point of use rather than trusted. SpeechLab
seals by filename convention -- `sealed` in the name or path -- so that is
refused too, and its real holdout lives outside the repository entirely.
"""
import json
import os
import pathlib
import re
import sys
from collections import Counter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import corpus_paths  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]

#: Where SpeechLab keeps its material. Everything under here is walked rather
#: than listed, because a hand-written list is what this census got wrong on
#: its first two runs, in both directions at once: it named one of the ten
#: files that carry utterances, and it excluded `phase2/public/source-records`
#: on the grounds that the file "holds provenance, not utterances" -- a
#: conclusion produced entirely by reading only a `text` field from a file
#: whose field is called `utterance`.
#:
#: `corpus_paths` exists because exactly this happened to the leak check. The
#: lesson did not transfer on its own, so the rule is repeated here: ask the
#: directory, not your memory of it.
SPEECHLAB = "Tools/SpeechLab"

#: Field names that hold an utterance. Closed, and checked for completeness
#: below rather than assumed.
UTTERANCE_FIELDS = ("text", "utterance", "spoken_rendering")

#: What a field name looks like when it holds an utterance. A file carrying
#: none of `UTTERANCE_FIELDS` is skipped silently, which is correct for a
#: manifest and wrong for a schema that renamed its column -- and the second
#: is indistinguishable from the first at the point of skipping. So a skipped
#: file whose keys look like they hold speech fails the run instead.
LOOKS_LIKE_SPEECH = re.compile(
    r"utterance|text|sentence|transcript|rendering|phrase|wording",
    re.IGNORECASE)

#: Keys that match the pattern above and demonstrably do not hold an utterance.
#: Each costs a line, which is the point: the alternative is a pattern loose
#: enough to wave anything through.
NOT_SPEECH = frozenset({
    "text_hash",          # a digest of an utterance, not one
    "rendering_id",       # an identifier
    "rendering_count",
})


#: The connectives that join a fact to the errand it creates. The first three
#: are word-forms the splitter handles today; the rest it does not handle at
#: all. Both halves are listed because a census of only the missing ones has no
#: baseline to read against: what makes a zero mean anything is `and` in the
#: same column, on the same rows. No figure is written here -- the report
#: prints them, and a count copied into a comment is one nothing recomputes.
#:
#: Two connectives the splitter does handle are absent by necessity rather than
#: oversight: a comma and bare juxtaposition have no word to search for, so a
#: census of surface forms cannot count them and does not pretend to.
CONNECTIVES = (
    ("and", r"\band\b"),
    ("so", r"\bso\b"),
    ("then", r"\bthen\b"),
    ("also", r"\balso\b"),
    ("plus", r"\bplus\b"),
    ("which means", r"\bwhich means\b"),
    ("that means", r"\bthat means\b"),
    ("because of that", r"\bbecause of that\b"),
    ("therefore", r"\btherefore\b"),
    ("meaning", r"\bmeaning\b"),
    ("which is why", r"\bwhich is why\b"),
)


def shown(path):
    """A path as a reader would name it, without raising on an outside path.

    `relative_to` throws for anything outside the repository, and every use of
    it here is inside an error message -- so a diagnostic about a stray file
    failed with a different error about the same file, and said nothing about
    what was actually wrong.
    """
    try:
        return path.relative_to(ROOT)
    except ValueError:
        return path


def speechlab_files():
    """Every `.jsonl` under SpeechLab, walked, with sealed paths refused.

    Walked rather than globbed: `rglob` does not descend a symlinked directory,
    and the claim here is about every file in a tree.
    """
    sealed = {p.resolve() for p in corpus_paths.sealed()}
    out = []
    for here, folders, files in os.walk(ROOT / SPEECHLAB, followlinks=True):
        for name in sorted(files):
            if not name.endswith(".jsonl"):
                continue
            path = pathlib.Path(here, name)
            if "sealed" in str(path.relative_to(ROOT)).lower():
                raise ValueError(
                    f"{shown(path)} is sealed by SpeechLab's "
                    f"filename convention and must not be read here")
            if path.resolve() in sealed:
                raise ValueError(
                    f"{shown(path)} is in corpus_paths.sealed()")
            out.append(path)
    return sorted(out)


def utterance_field(path):
    """Which field holds the utterance, or None when the file holds none.

    Raises when a file holds no known field but has one that looks like it
    should: that is a rename, and a rename skipped silently takes a whole
    corpus out of the denominator without changing a single line of output.
    """
    keys = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        for field in UTTERANCE_FIELDS:
            if isinstance(record.get(field), str) and record[field]:
                return field
        keys.update(k for k, v in record.items() if isinstance(v, str))
    suspicious = sorted(k for k in keys
                        if k not in NOT_SPEECH and LOOKS_LIKE_SPEECH.search(k))
    if suspicious:
        raise ValueError(
            f"{shown(path)} carries no field named "
            f"{' or '.join(UTTERANCE_FIELDS)}, but has {suspicious} — either "
            f"a schema renamed its utterance column, in which case this "
            f"census has silently stopped counting a corpus, or the name is "
            f"a coincidence and belongs in NOT_SPEECH")
    return None


def tsv_utterances(path):
    """Column two of every data row. The devsets all put the utterance there."""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or not line.strip():
            continue
        cells = line.split("\t")
        if len(cells) < 2 or cells[0] == "id":
            continue
        yield cells[1]


def jsonl_utterances(path, field=None):
    """Every utterance in a JSONL file, under whichever field carries them."""
    field = field or utterance_field(path)
    if field is None:
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        value = json.loads(line).get(field)
        if isinstance(value, str) and value:
            yield value


def contained_sources():
    """Pairs of sources where one's utterances are a subset of another's.

    Reported, not refused, and the distinction is worth the paragraph.

    This began as a refusal, written when the sources were a hand-declared
    pair and one turned out to be an exact subset of the other. Once the tree
    is walked instead of listed, the same check fires on twenty-eight pairs:
    SpeechLab keeps a dozen views of one utterance population -- candidates,
    accepted candidates, a review set, a stratified sample, an adjudicated
    copy -- and overlap between them is the design, not a mistake.

    What the original defect actually did was inflate the denominator, and
    deduplication fixes that on its own, whatever the sources overlap. So the
    refusal was guarding a property already held elsewhere, and keeping it
    would have meant either excluding real material or maintaining a list of
    permitted overlaps, which is a hand-written list again.

    It stays as output because a reader deciding how much independent evidence
    is here should see that twelve sources are not twelve populations.

    Reads every source a second time rather than reusing the walk, because a
    guard sharing state with the thing it guards fails with it.
    """
    texts = {}
    for path, read in _readers():
        texts[path] = set(read(path))
    out = []
    for a in texts:
        for b in texts:
            if a is not b and texts[a] and texts[a] <= texts[b]:
                out.append((a, b))
    return out


def _readers():
    """(path, reader) for every declared source, in reading order."""
    readers = [(p, tsv_utterances) for p in corpus_paths.readable()]
    for path in speechlab_files():
        field = utterance_field(path)
        if field is not None:
            readers.append((path, lambda p, f=field: jsonl_utterances(p, f)))
    return readers


def census():
    """(counts, distinct, sources). Counts are utterances containing the form.

    The unit is the **distinct utterance**, not the row. Two sources can hold
    the same text -- one of them did, as an exact subset of the other -- and a
    row-counted denominator then reports a form as rarer than it is while
    reporting the corpus as larger than it is. Both errors point the same way,
    towards "there is plenty of material here", which is the conclusion this
    census exists to test rather than to flatter.
    """
    counts, sources = Counter(), []
    seen = set()
    patterns = [(name, re.compile(pattern, re.IGNORECASE))
                for name, pattern in CONNECTIVES]
    for path, read in _readers():
        here, fresh = 0, 0
        for utterance in read(path):
            here += 1
            if utterance in seen:
                continue
            seen.add(utterance)
            fresh += 1
            for name, pattern in patterns:
                if pattern.search(utterance):
                    counts[name] += 1
        if not here:
            raise ValueError(
                f"{shown(path)} yielded no utterances. Either the "
                f"file is empty or its field names moved, and a reader that "
                f"has quietly stopped reading reports every form as absent, "
                f"which is the verdict this census exists to produce honestly")
        sources.append((shown(path), here, fresh))
    return counts, len(seen), sources


def main():
    try:
        counts, distinct, sources = census()
    except ValueError as exc:
        print(f"connective census REFUSED: {exc}")
        return 2

    if not distinct:
        print("connective census REFUSED: no readable rows were read at all, "
              "which produces a zero for every form and is indistinguishable "
              "from a repository where nobody says anything")
        return 2

    width = max(len(name) for name, _ in CONNECTIVES)
    print()
    read = sum(here for _, here, _ in sources)
    print(f"CONNECTIVES IN READABLE MATERIAL — {distinct} distinct utterances "
          f"from {read} rows, {len(sources)} sources, no sealed set read")
    print("-" * (width + 26))
    for name, _ in CONNECTIVES:
        share = 100.0 * counts[name] / distinct
        print(f"  {name:<{width}}{counts[name]:>6}{share:>8.1f}%")
    print("-" * (width + 26))
    print("  Distinct utterances containing the form, not occurrences of it.")
    print("  Nothing here says whether the parser handles any of them.")
    if read != distinct:
        print(f"  {read - distinct} row(s) repeat text counted under an")
        print("  earlier source and are not counted twice.")
    contained = contained_sources()
    if contained:
        pairs = sorted({f"{a.name} inside {b.name}" for a, b in contained})
        print(f"  {len(pairs)} source pair(s) where one is wholly contained in")
        print("  the other. Not an error -- SpeechLab keeps several views of")
        print("  one population -- but it means the source count below is not")
        print("  a count of independent bodies of material:")
        for pair in pairs[:6]:
            print(f"    {pair}")
        if len(pairs) > 6:
            print(f"    and {len(pairs) - 6} more")
    print()
    absent = [name for name, _ in CONNECTIVES if not counts[name]]
    if absent:
        print(f"  {len(absent)} form(s) appear in no readable row: "
              + ", ".join(absent))
        print("  A change aimed at one of those cannot be sized, reviewed or")
        print("  regression-covered from anything this project may read, so")
        print("  the only thing left to shape it would be a sealed set.")
        print("  That is a reason to go and get material, not a reason to")
        print("  build -- and it is NOT evidence that nobody says the form.")
    else:
        print("  Every form appears somewhere readable.")
    print()
    for path, here, fresh in sources:
        repeat = "" if here == fresh else f"  ({here - fresh} already seen)"
        print(f"    {fresh:>5}  {path}{repeat}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
