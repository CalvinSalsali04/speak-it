#!/usr/bin/env python3
"""Whether N instances of a form are N observations of it.

The census in `connective-census.py` answers the first question a target has
to survive: **is this form attested in material we may read?** A zero there
ends a proposal. This module answers the second, which has now saved two
proposals by hand and is the one nothing checks:

    Forty rows contain the word. Are they forty observations, or one
    observation written forty times?

Both failures happened on 2026-09-14, hours apart, on different material:

  * `plus` appears in 44 readable utterances across 5 sources. 41 of them
    appear in each of four files the census's own containment check reports
    as views of one population, and twelve stems carry all 44 rows with one
    frame taking two thirds. Read off the census table, `plus 44 0.8%` is an
    attested form with five sources behind it. It is one blueprint.
  * `wait` appears in 53 over 14 sources, and a third of them are one frame,
    `I was going to ask— wait, ...`. A detector keyed on the phrase would
    fire on captures that are one sentence with the nouns changed.

A row count cannot tell those apart from forty people saying a thing, and a
row count is what every sizing in this repository has used. **Neither can a
source count**: both of the above pass that test, and the stem share is the
only column here that catches them. Those figures are over the connective
census's population; this module reads the development sets until the
SpeechLab walk is wired, so running it will not reproduce them.

WHAT THIS MEASURES, stated plainly because a concentration number is exactly
the kind of figure that gets read as a verdict:

  * How many **distinct sources** carry the form. Twelve views of one
    population are one body of material, and SpeechLab keeps a dozen.
  * How many **distinct five-word stems** the matching rows have, and what
    share the commonest stem takes. A stem is a crude measure of frame and
    it is meant to be: the point of using a cruder one is that when it
    disagrees with a subtler one the subtler one has some explaining to do.
    On `cases-adjudicated.jsonl` the repository's own structural-template
    gate reports 816 templates for 818 cases, largest 0.24%. Five-word stems
    give 330 and 4.6%. A factor of nineteen on the largest bucket.

WHAT IT DOES NOT MEASURE. Whether the rows are *good*, whether a form is
worth handling, or whether people say it. It is a shape, and a shape with a
mark on it is still a shape: the mark below says a population is concentrated
by these two mechanical measures, never that evidence is weak. That judgement
belongs to a person reading why the rows are alike.
"""
import collections
import re
import textwrap

#: Words of an utterance that make its stem. Five because it is long enough
#: to separate two different openings and short enough that a template with
#: the nouns swapped still collides. Changing it changes every figure derived
#: from it, so it is named once here rather than passed around.
STEM_WORDS = 5

#: A form's hits are concentrated when either holds. Both are deliberately
#: blunt and both are printed beside the mark, so a reader can disagree with
#: the threshold without having to re-derive the numbers.
ONE_SOURCE = 1
CROWDED_STEM = 0.25

#: Below this many rows, neither arm means anything: one utterance is one
#: source and one stem, so it scores 100% concentrated and reads as a finding
#: about a population of one. `hold on` does exactly this. The shape is still
#: computed and printed -- only the mark is withheld, because the mark is the
#: part that gets quoted.
TOO_FEW = 4

WHERE = ("anywhere", "leading", "trailing")


def stem(text, words=STEM_WORDS):
    """The first `words` alphabetic words, lowered. Punctuation is dropped.

    Dropped rather than kept because the templates this exists to find differ
    in their punctuation -- `I was GOING to ask— wait` and `I was going to
    ask, wait` are the same frame, and a stem that separates them reports
    diversity that is not there, which is the direction that costs something.

    **Digits go with the punctuation, and that is load bearing.** `call Ana
    at 3` and `call Ana at 4` are one frame, so a stem that keeps the number
    reports two. It is also the first thing this module's own canary caught:
    a fixture written to be a *varied* population varied only in a digit, so
    the measure correctly called forty rows one frame and the canary failed
    -- which is what a canary is for. Anything whose variation is numeric is
    invisible here, and a form that only varies numerically will read as one
    frame. That is the intended reading and not a defect, but it has to be
    known before a figure from here is quoted.
    """
    return " ".join(re.findall(r"[a-z']+", text.lower())[:words])


def pattern_for(phrase, where="anywhere"):
    """The pattern for a declared phrase. There is no other way to make one.

    **The phrase is the only input.** A hand-written regex beside a name is a
    second owner of the same fact, and on 2026-09-14 two sizings were
    published where the two had drifted: a row counted as `I lost it` was
    matched by `I lost (it|my train)`, and one counted as trailing `I mean`
    was matched by `I mean` anywhere. Each overstated its form by a factor of
    four, in a section arguing that phrase-keyed detection is the wrong
    instrument.

    A third case is the better one, because nobody was careless in it. Two
    readers counted "the `I was going to ask— wait` frame" stably and
    differently for two days, 28 against 31. Three rows read `I was going to,
    um, ask— wait, ...`: a pattern requiring `going to ask` adjacent finds 28
    and one allowing the interpolation finds 31. Both were right about
    different patterns, and what separated two careful counts was a
    three-character optional group neither had written down. Naming the
    phrase is not naming the pattern.

    So `where` is an argument rather than something the caller expresses by
    editing a pattern, and `test_observation.py` fails if any matched row
    does not contain the phrase it is filed under.
    """
    if where not in WHERE:
        raise ValueError(f"where must be one of {WHERE}, not {where!r}")
    body = r"\s+".join(re.escape(word) for word in phrase.split())
    edge = {"anywhere": (r"\b", r"\b"),
            "leading": (r"^\W*", r"\b"),
            "trailing": (r"\b", r"[\W]*$")}[where]
    return re.compile(edge[0] + body + edge[1], re.IGNORECASE)


Shape = collections.namedtuple(
    "Shape", "rows sources stems largest_stem largest_share concentrated")


def shape(pairs):
    """`(source, utterance)` pairs in, one `Shape` out.

    **`rows` counts distinct utterances and `sources` counts every source
    that carries one.** The two have to be taken differently or the shape is
    wrong in opposite directions: SpeechLab keeps a dozen views of one
    population, so counting the pairs inflates `rows` by however many copies
    exist, while deduplicating first and keeping only the surviving copy's
    source understates how widely a form is spread. On the seven development
    sets alone the difference is 631 pairs against 618 utterances.

    `largest_share` is over rows rather than over stems, because the question
    is what fraction of the evidence one frame supplies.
    """
    if not pairs:
        return Shape(0, 0, 0, 0, 0.0, False)
    texts = {}
    for source, text in pairs:
        texts.setdefault(text, set()).add(source)
    rows = len(texts)
    sources = len({source for carried in texts.values() for source in carried})
    stems = collections.Counter(stem(text) for text in texts)
    largest = stems.most_common(1)[0][1]
    share = largest / rows
    return Shape(rows, sources, len(stems), largest, share,
                 sources <= ONE_SOURCE or share >= CROWDED_STEM)


def mark_for(found):
    """The word printed beside a row, which is the part that gets quoted.

    Three outcomes, not two. A form nobody says and a form said fifty
    different ways both come back `concentrated == False`, so printing only
    CONCENTRATED or nothing makes absence and dispersion identical -- and
    absence is the answer that ends a proposal, so it is the one that must
    never be mistaken for a measurement. `TOO_FEW` is the third: a population
    of one is concentrated by arithmetic and says nothing.
    """
    if found.rows == 0:
        return "  ABSENT"
    if found.rows < TOO_FEW:
        return "  TOO FEW"
    return "  CONCENTRATED" if found.concentrated else ""


def census(forms, pairs):
    """`{name: Shape}` for declared forms over `(source, utterance)` pairs.

    `forms` is `{name: where}`. The name is the phrase, which is what makes
    the label and the measure the same object.
    """
    out = {}
    for phrase, where in forms.items():
        found = pattern_for(phrase, where)
        out[phrase] = shape([(s, t) for s, t in pairs if found.search(t)])
    return out


#: A pair the measure must separate before any of its numbers are believed.
#: One frame forty times, against forty openings -- a measure that reported
#: these two alike would report every population as diverse, and diverse is
#: the answer that lets a proposal through.
#: Varied in WORDS, not in digits -- see `stem`. The first version of this
#: varied only the number and the measure rightly called it one frame.
VARIED_OPENINGS = (
    "remember the", "call about", "book a", "send over", "pick up",
    "ask Dana", "cancel my", "renew the", "check whether", "print two",
    "email back", "drop off", "return that", "order more", "fix the",
    "chase the", "confirm my", "move the", "split the", "log this",
)
CANARY_TEMPLATED = [("one", f"I was going to ask wait about the {word}")
                    for word in VARIED_OPENINGS]
CANARY_VARIED = [(f"s{n}", f"{opening} thing before the week is out")
                 for n, opening in enumerate(VARIED_OPENINGS)]


def frame_population(rows, on_one_stem, sources=4):
    """`rows` distinct utterances, `on_one_stem` of them one frame.

    **Several sources on purpose.** `concentrated` is an OR, so with a single
    source `ONE_SOURCE` decides it alone and any fixture built that way
    measures `CROWDED_STEM` not at all. That is exactly what the two canaries
    above could not see: `CANARY_TEMPLATED` is one source, one stem and a
    share of 1.0, concentrated twice over and at ceiling on both, so the
    threshold could be moved to 0.99 without changing a single verdict.
    A fixture at ceiling on the property under test cannot measure a
    threshold below it.
    """
    if not 1 <= on_one_stem <= rows:
        raise ValueError(f"on_one_stem must be 1..{rows}, not {on_one_stem}")
    if max(on_one_stem, rows - on_one_stem) > len(VARIED_OPENINGS):
        raise ValueError(
            f"{rows} rows with {on_one_stem} on one stem needs more than the "
            f"{len(VARIED_OPENINGS)} distinct openings available")
    if sources < 1:
        raise ValueError(f"sources must be at least 1, not {sources}")
    texts = [f"I was going to ask wait about the {word}"
             for word in VARIED_OPENINGS[:on_one_stem]]
    texts += [f"{opening} thing before the week is out"
              for opening in VARIED_OPENINGS[:rows - on_one_stem]]
    return [(f"s{n % sources}", text) for n, text in enumerate(texts)]


#: Two populations straddling `CROWDED_STEM`, derived from it rather than
#: written at 0.25, so moving the threshold deliberately keeps these honest
#: while the pinned shape in the tests catches it being moved accidentally.
STRADDLE_ROWS = 20
_CROWDED = int(-(-CROWDED_STEM * STRADDLE_ROWS // 1))  # ceil, no import
CANARY_CROWDED = frame_population(STRADDLE_ROWS, _CROWDED)
CANARY_SPREAD = frame_population(STRADDLE_ROWS, _CROWDED - 1)


def self_check(measure=None):
    """True when `measure` can still tell the two canaries apart.

    `measure` is an argument so the canary itself can be checked, which is
    not decoration: found by mutation, forcing this function to `return True`
    was the one change to this module that no test noticed. A test asserting
    `self_check()` is true is satisfied perfectly by a function that is always
    true -- the same shape as a detector that matches nothing satisfying every
    assertion about what it finds. `test_observation.py` now hands this two
    deliberately broken measures and requires it to say so.
    """
    measure = measure or shape
    templated, varied = measure(CANARY_TEMPLATED), measure(CANARY_VARIED)
    crowded, spread = measure(CANARY_CROWDED), measure(CANARY_SPREAD)
    return (templated.concentrated and not varied.concentrated
            and templated.stems == 1 and varied.stems == len(CANARY_VARIED)
            # The threshold arm, which the two above cannot reach. Both of
            # these carry several sources, so `ONE_SOURCE` is false for both
            # and only `CROWDED_STEM` can separate them.
            and crowded.sources > ONE_SOURCE and spread.sources > ONE_SOURCE
            and crowded.concentrated and not spread.concentrated)


#: What this reads, stated because the alternative is a reader assuming.
#:
#: This block used to list what was NOT read, which was the honest form of the
#: same statement while two populations were missing. Both are now read, and a
#: silent claim of total coverage is worse than a list of gaps -- so the claim
#: is written down and `test_observation.py` checks it against the census,
#: which owns the answer. Four instruments in this directory have described
#: themselves as covering readable material while omitting some of it.
READ_WHAT = (
    "READ: every source `readable_material.readers()` declares -- the corpus "
    "files, the gating corpus in SpeakItTests, and the SpeechLab tree with "
    "its sealed paths refused by name. That is the same population the "
    "connective census counts, and a test fails if the two ever differ. No "
    "sealed set is read.")


def readable_pairs():
    """`(source, utterance)` for every source this project may read.

    Through `readable_material.readers()`, which is the one owner of which
    sources exist and how each kind is read, so this grows no walk of its own
    and cannot drift from what the census counts. `test_observation.py`
    asserts the two populations are identical rather than merely similar.

    This used to read the seven development sets and print a block naming the
    two populations it did not read. That block was honest and it was also
    the reason every figure this module produced had to be qualified: `plus`
    reported 0 rows here while the census reported 44, and a reader running
    the tool to check a figure from it got the wrong answer with no error.

    **The source key is the repository-relative path, not the basename.**
    Two of the twenty sources are both called `renderings.jsonl`, under
    different SpeechLab directories, so keying on the name silently merged
    them: nineteen sources reported for twenty, and any form appearing in
    only those two would report `sources == 1` and be marked CONCENTRATED by
    the source arm. A false mark, produced by the half of this measure that
    exists to notice exactly that -- twelve views of one population are not
    twelve bodies of material, and neither are two distinct files one.
    """
    import readable_material
    for path, read in readable_material.readers():
        name = str(readable_material.shown(path))
        for text in read(path):
            yield name, text


def main(argv):
    import corpus_paths  # noqa: F401  (imported for the path insert's sake)
    if not self_check():
        print("observation: the canary failed -- the measure can no longer "
              "tell one frame repeated from many frames, so every number it "
              "would print below is unreliable. Nothing was measured.")
        return 2
    forms = {phrase: "anywhere" for phrase in argv} or {
        "and": "anywhere", "so": "anywhere", "wait": "anywhere",
        "I mean": "anywhere", "hold on": "anywhere", "I forgot": "anywhere",
    }
    pairs = list(readable_pairs())
    #: Distinct, to agree with the `rows` column. The pair count is 631 and
    #: the utterance count is 618; printing the first beside rows computed
    #: from the second is how a header and a table come to disagree.
    print(f"ARE THESE N INSTANCES N OBSERVATIONS? — "
          f"{len({text for _s, text in pairs})} distinct utterances, "
          f"{len({s for s, _ in pairs})} sources")
    print("-" * 74)
    print(f"  {'form':16} {'rows':>5} {'srcs':>5} {'stems':>6} "
          f"{'top frame':>10}")
    for phrase, found in sorted(census(forms, pairs).items()):
        print(f"  {phrase:16} {found.rows:5} {found.sources:5} "
              f"{found.stems:6} {found.largest_share:9.0%}{mark_for(found)}")
    print("-" * 74)
    print(f"  CONCENTRATED means {ONE_SOURCE} source or one frame taking "
          f"{CROWDED_STEM:.0%} of the rows.")
    print("  It is a shape, not a verdict: it says these rows are alike by "
          "two crude")
    print("  measures, never that the evidence is weak. Why they are alike "
          "is a reading.")
    print(f"  ABSENT is no rows at all; TOO FEW is under {TOO_FEW}, where one "
          f"utterance is")
    print("  one source and one stem and scores 100% by arithmetic.")
    print("  A stem drops digits, so variation that is only numeric is "
          "invisible here:")
    print("  `call Ana at 3` and `call Ana at 4` count as one frame.")
    print()
    for line in textwrap.wrap(READ_WHAT, 72):
        print(f"  {line}")
    return 0


if __name__ == "__main__":
    import sys as _sys
    _sys.exit(main(_sys.argv[1:]))
