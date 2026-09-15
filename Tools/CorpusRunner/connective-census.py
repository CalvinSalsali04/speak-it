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

TWO QUESTIONS, IN THIS ORDER. This file answers the first -- is the form
attested at all -- and deliberately does not answer the second: are N
instances N observations. A generated corpus answers the first cheaply and the
second never, because its rows are renderings of a smaller number of meanings.
`plus` reads as the third-commonest connective here and all 41 of its rows
come from one file; the SpeechLab adjudication corpus is 818 utterances over
137 semantic families. Counting the first and reporting it as the second is
how a family gets named that nobody has ever been observed to say.

AND DO NOT HAND-TYPE WHAT THIS COULD COMPUTE. On 2026-09-15 four figures went
into `Docs/LANGUAGE_BASELINE.md` from a one-off script rather than from a
check, and all four were wrong: two counted a looser pattern than the label
beside them, one was attributed to the wrong file and argued the opposite of
what it was cited for. They were caught only because the section said out loud
that they were hand-typed. A figure this file could produce and does not
should grow this file.

Sealed sets are not read. Sources come from `corpus_paths.readable()` plus a
declared list of SpeechLab files, and the declared list is checked against
`corpus_paths.sealed()` at the point of use rather than trusted. SpeechLab
seals by filename convention -- `sealed` in the name or path -- so that is
refused too, and its real holdout lives outside the repository entirely.
"""
import pathlib
import re
import sys
from collections import Counter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import corpus_paths  # noqa: E402

#: The walk, the readers and the sealed refusals live in one module so that
#: this file and `observation.py` ask the same question of the same material.
#: They were here until a second consumer wanted them; see that module's
#: docstring for why the split happened when it did.
import readable_material  # noqa: E402
from readable_material import (  # noqa: E402
    GATING, LOOKS_LIKE_SPEECH, NOT_SPEECH, ROOT, SPEECHLAB, UTTERANCE_FIELDS,
    contained_sources, independent_bodies, jsonl_utterances, readers,
    reduce_to_bodies, shown, source_texts, speechlab_files, swift_literals,
    swift_utterances, tsv_utterances, utterance_field)

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
    for path, read in readers():
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
        bodies, maximal = independent_bodies()
        print(f"  {len(pairs)} source pair(s) where one is wholly contained in")
        print("  the other. Not an error -- SpeechLab keeps several views of")
        print("  one population -- but it means the source count above is not")
        print("  a count of independent bodies of material. It reduces to")
        print(f"  {len(bodies)} distinct bodies and {len(maximal)} that sit "
              f"inside no other,")
        print(f"  so read {len(sources)} sources as {len(maximal)} "
              f"populations. Pairs:")
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
