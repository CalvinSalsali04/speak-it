#!/usr/bin/env python3
"""Whether N instances of a form are N observations of it.

The census in `connective-census.py` answers the first question a target has
to survive: **is this form attested in material we may read?** A zero there
ends a proposal. This module answers the second, which has now saved two
proposals by hand and is the one nothing checks:

    Forty rows contain the word. Are they forty observations, or one
    observation written forty times?

Both failures happened on 2026-09-14, hours apart, on different material:

  * `plus` appears in 41 readable utterances. All 41 are in one file, and
    that file is reported by the census's own containment check as contained
    in three others. Read off the table, `plus 41 2.1%` is an attested form.
  * `wait` appears in 40. 31 are in one file and 28 of those are the same
    frame, `I was going to ask— wait, ...`. A detector keyed on the phrase
    would fire on 28 captures that are one sentence with the nouns changed.

A row count cannot tell those apart from forty people saying a thing, and a
row count is what every sizing in this repository has used.

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
    second owner of the same fact, and on 2026-09-14 three sizings were
    published where the two had drifted: a row counted as `I lost it` was
    matched by `I lost`, and one counted as trailing `I mean` was matched by
    `I mean` anywhere. Each overstated its form by a factor of four or more,
    in a section arguing that phrase-keyed detection is the wrong instrument.

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
    return (templated.concentrated and not varied.concentrated
            and templated.stems == 1 and varied.stems == len(CANARY_VARIED))


#: Populations this report does NOT read yet, printed on every run.
#:
#: A tool that reads some of the material and says "readable material" is the
#: defect this repository has caught in four instruments now, most recently in
#: a census that omitted the gating corpus -- 3,704 distinct literals, the
#: material this project reads most -- while describing itself as covering
#: what may be read. So the gap is output rather than a known limitation, and
#: it costs three lines.
NOT_READ = (
    ("Tools/SpeechLab/**.jsonl",
     "about 1,290 distinct utterances. The walk that reaches them safely, "
     "with its sealed-by-filename refusal, is in #66; this calls it rather "
     "than growing a second one."),
    ("SpeakItTests/*.swift",
     "3,704 distinct multi-word literals, a superset of the 1,380 gating "
     "captures. `swift_literals` lives in `everyday/leak-check.py` and wants "
     "a home before a third reader imports it by path."),
)


def readable_pairs():
    """`(source, utterance)` for every readable development set.

    Through `corpus_paths.utterances`, so this is not a fifth reader of the
    corpus format -- see `EveryCorpusReaderIsDeclared` in `test_score.py`.
    """
    import corpus_paths
    for path in corpus_paths.readable():
        for _number, _cid, text in corpus_paths.utterances(path):
            yield path.name, text


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
        mark = "  CONCENTRATED" if found.concentrated else ""
        print(f"  {phrase:16} {found.rows:5} {found.sources:5} "
              f"{found.stems:6} {found.largest_share:9.0%}{mark}")
    print("-" * 74)
    print(f"  CONCENTRATED means {ONE_SOURCE} source or one frame taking "
          f"{CROWDED_STEM:.0%} of the rows.")
    print("  It is a shape, not a verdict: it says these rows are alike by "
          "two crude")
    print("  measures, never that the evidence is weak. Why they are alike "
          "is a reading.")
    print()
    print("  NOT READ by this run:")
    for where, why in NOT_READ:
        print(f"    {where}")
        for line in textwrap.wrap(why, 66):
            print(f"      {line}")
    return 0


if __name__ == "__main__":
    import sys as _sys
    _sys.exit(main(_sys.argv[1:]))
