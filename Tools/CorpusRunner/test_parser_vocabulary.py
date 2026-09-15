"""The five obligation vocabularies, checked against each other.

`Docs/KNOWN_ISSUES.md` records that five lists in four files state "this is an
obligation" and still disagree, and that converging them changes `count` and
`route` and so needs its own measurement pass. This suite does not converge
them. It makes the disagreement **declared** instead of accidental, so that
adding a form to one list without deciding about the others fails here rather
than in somebody's Memory tab.

The one property that is not a matter of taste is the one that already bit:

    A single-token obligation form missing from `clauseInternalLead` gets cut
    off from what it governs. "I hafta drop the car off on Thursday" filed a
    Memory note titled "I hafta" beside the errand, because `hafta`, `oughta`
    and `needa` were in the route and title lists and not in the splitter's.

What makes it checkable rather than a matter of judgement is that the exposed
position is mechanical. `ClauseJuxtaposition` decides a cut from the single
token standing in front of the candidate verb, so the position at risk is the
frame's **last** word -- `to` in "have to call", `better` in "had better call",
the whole word in "hafta call". Most of those last words are `to`, which the
splitter has held since it was written; the rest are checked here one by one.
"""
import copy
import pathlib
import shutil
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import parser_vocabulary as pv  # noqa: E402


#: Exposed words that `clauseInternalLead` deliberately does not hold, and the
#: mechanism that holds them instead. An entry here is not an unprotected form;
#: it is one protected somewhere a set of single tokens cannot reach. Each is
#: checked below, both that the exception is still needed and that the
#: mechanism it names still does the work.
#:
#: Keep this list short and keep the reasons specific. An entry whose reason
#: names no mechanism is how the defect above comes back.
PROTECTED_BY_A_SECOND_MECHANISM = {
    "better": (
        "also an ordinary comparative, and a comparative is exactly where a "
        "spoken sentence ends one clause and starts another -- 'the weather is "
        "better book the campsite' has to split. A set of single tokens cannot "
        "tell the two apart, so `SpeechRepair` reads the word in front of it "
        "instead: `deonticBetterSubject`, at the same guard and to the same "
        "effect. That is what protects `better`, `had better`, `i/we better` "
        "and `'d better`, and it is checked by "
        "`test_the_second_mechanism_holds_every_subject_those_frames_carry`."
    ),
}

#: The tokens a transcript puts in front of `better` for each frame that ends
#: in it, which are what `deonticBetterSubject` has to hold for the exception
#: above to be true. `i/we better` gives `i` and `we` and `had better` gives
#: `had` mechanically. `['’]d better` does not: the router writes the clitic as
#: its own alternative, but a transcript tokenises "I'd" as one word, so the
#: token the splitter sees is the pronoun carrying it -- spelled out here in
#: both apostrophes and in the apostrophe-less form dictation produces.
BETTER_SUBJECTS = {
    "i", "we", "had",
    "i'd", "i’d", "id", "we'd", "we’d",
}

#: What each list held when this suite was written. Pinned so that a list
#: quietly losing an entry fails here; a deliberate change re-pins it and says
#: why in the commit, exactly as `test_observation.py`'s census does.
SIZES = {"split": 144, "route": 22, "whose": 9, "title": 24, "glue": 10}

#: Forms all four claimants agree are obligations.
#:
#: Five rather than the seven `Docs/KNOWN_ISSUES.md` quotes, and the difference
#: is not drift. That table names three lists; `thirdPersonObligation` is a
#: fourth, and it is a deliberately smaller closed class -- only the forms
#: English can predicate of somebody who is not the speaker. `gotta` and `want
#: to` are the two it declines, which is correct: "Mike gotta call Sarah" is
#: not English and "Mike wants to call Sarah" is a preference, not an errand
#: the person owes.
AGREED = {"have to", "must", "need to", "ought to", "should"}

#: The same intersection over the three lists the document tabulates, kept so
#: that its figure and this suite cannot drift apart without one of them
#: failing.
AGREED_IN_THE_DOCUMENTED_THREE = {
    "gotta", "have to", "must", "need to", "ought to", "should", "want to",
}


def the_filter_this_replaced(forms):
    """`single_token` as it stood: kept a form only if it had no space in it.

    Here as a control. A mutation that the old filter would also have caught
    proves nothing about the reformulation, so the test below checks its
    counterexample against this before checking it against the new filter.
    """
    return {f for f in forms if " " not in f and "/" not in f}


class EveryListCanBeRead(unittest.TestCase):
    """A reader that returns empty passes every subset check below."""

    def test_each_list_is_found_and_not_empty(self):
        for name, forms in pv.read_all().items():
            with self.subTest(name):
                self.assertTrue(forms, f"{name} read as empty rather than refusing")

    def test_each_list_is_the_size_it_was(self):
        for name, forms in pv.read_all().items():
            with self.subTest(name):
                self.assertEqual(
                    len(forms), SIZES[name],
                    f"`{name}` moved from {SIZES[name]} to {len(forms)} entries. "
                    "If that was deliberate, re-pin SIZES and say why; if it "
                    "was not, a vocabulary has drifted."
                )

    def test_a_renamed_constant_refuses_rather_than_reads_empty(self):
        """The failure this module exists to make loud.

        Reformat a constant and a regex reader stops finding it. Returning an
        empty set there would pass `exposed_tail(...) <= split` trivially, and
        the suite would report a clean bill for a vocabulary it could not see.

        Every reader is here, the two protection mechanisms included. A reader
        left out is one that can start returning empty without anything saying
        so.
        """
        cases = {
            "split": ("SpeechRepair.swift", "clauseInternalLead", pv.clause_internal_lead),
            "route": ("Actionability.swift", "obligationLead", pv.obligation_lead),
            "whose": ("Actionability.swift", "thirdPersonObligation", pv.third_person_obligation),
            "title": ("ThoughtOrganizer.swift", "let link", pv.obligation_frame_link),
            "glue": ("ThoughtExtractor.swift", r'of: #"^(?:i\s+)?(?:', pv.dangling_auxiliary),
            "better": ("SpeechRepair.swift", "deonticBetterSubject", pv.deontic_better_subject),
        }
        original = pv.REPOS
        for label, (filename, needle, reader) in cases.items():
            with self.subTest(label), tempfile.TemporaryDirectory() as tmp:
                tree = pathlib.Path(tmp) / "Repositories"
                shutil.copytree(original, tree)
                target = tree / filename
                text = target.read_text(encoding="utf-8")
                self.assertTrue(
                    needle in text,
                    f"the mutation itself found nothing in {filename}; the "
                    "needle is stale, so this test was passing for free"
                )
                target.write_text(text.replace(needle, "renamedByThisTest"), encoding="utf-8")
                pv.REPOS = tree
                try:
                    with self.assertRaises(pv.Refused):
                        reader()
                finally:
                    pv.REPOS = original

    def test_the_control_passes_either_side_of_that_mutation(self):
        """Without it, a reader that always raised would look protected."""
        self.assertTrue(pv.clause_internal_lead())
        self.assertTrue(pv.obligation_lead())


class NoObligationFormIsCutOffFromWhatItGoverns(unittest.TestCase):

    def setUp(self):
        self.lists = pv.read_all()
        self.tails = pv.exposed_tail(pv.union(self.lists))

    def test_every_exposed_word_is_held_by_the_splitter(self):
        unprotected = self.tails - self.lists["split"]
        undeclared = unprotected - set(PROTECTED_BY_A_SECOND_MECHANISM)
        self.assertFalse(
            undeclared,
            f"{sorted(undeclared)} end an obligation frame and "
            "`clauseInternalLead` does not hold them, so a sentence can be cut "
            "between the frame and what it governs -- the `I hafta` defect. "
            "Add them to `clauseInternalLead`, drop the frames that end in "
            "them, or add an entry to PROTECTED_BY_A_SECOND_MECHANISM naming "
            "the mechanism that protects them instead."
        )

    def test_every_declared_exception_is_still_one(self):
        """A declaration that has stopped being true is a place to hide a form.

        If `better` is added to `clauseInternalLead` tomorrow, the entry above
        becomes a comment that reads like a rule and checks nothing, and the
        next form added beside it inherits that.
        """
        for word, reason in PROTECTED_BY_A_SECOND_MECHANISM.items():
            with self.subTest(word):
                self.assertIn(
                    word, self.tails,
                    f"`{word}` is declared an exception but no obligation frame "
                    "ends in it any more; drop the declaration."
                )
                self.assertNotIn(
                    word, self.lists["split"],
                    f"`{word}` is declared an exception and the splitter now "
                    "holds it; drop the declaration."
                )
                self.assertGreater(len(reason), 40, "a reason, not a label")

    def test_the_second_mechanism_holds_every_subject_those_frames_carry(self):
        """The exception's reason, checked rather than read.

        `better` leaves the filter above naming `deonticBetterSubject` as what
        protects it. Nothing checked that set existed, let alone that it held
        the subjects the four `better` frames carry -- so trimming it would
        have reopened the `I better` row with the declaration still reading
        like a rule.
        """
        subjects = pv.deontic_better_subject()
        missing = BETTER_SUBJECTS - subjects
        self.assertFalse(
            missing,
            f"{sorted(missing)} stand in front of `better` in a frame the "
            "router calls an obligation, and `deonticBetterSubject` no longer "
            "holds them, so those sentences are cut at `better` after all."
        )

    def test_the_check_notices_a_single_word_that_slips_through(self):
        """The mutation the invariant exists for, run against it."""
        lists = copy.deepcopy(self.lists)
        lists["route"] = lists["route"] | {"mustnt"}
        slipped = pv.exposed_tail(pv.union(lists)) - lists["split"]
        self.assertIn("mustnt", slipped - set(PROTECTED_BY_A_SECOND_MECHANISM))

    def test_the_check_notices_a_multi_word_frame_that_slips_through(self):
        """The mutation the reformulation exists for.

        The filter this replaced kept only forms with no space in them, on the
        reasoning that every multi-word frame ends in `to`. Four did not, and
        `got ta` -- a real entry of `obligationLead` until this change -- was
        exposed at `ta` and left the old filter looking protected. Any frame
        whose last word the splitter does not hold has to be caught, however
        many words stand in front of it.
        """
        lists = copy.deepcopy(self.lists)
        lists["route"] = lists["route"] | {"got ta"}
        self.assertNotIn(
            "got ta", the_filter_this_replaced(lists["route"]),
            "the mutation is not a counterexample to the old filter, so it "
            "says nothing about the reformulation"
        )
        slipped = pv.exposed_tail(pv.union(lists)) - lists["split"]
        self.assertIn("ta", slipped - set(PROTECTED_BY_A_SECOND_MECHANISM))


class WhatTheListsAgreeOn(unittest.TestCase):
    """A census, in the shape `test_observation.py` uses.

    It asserts nothing about what the right answer is. It fails when the answer
    moves, which is the point: five lists drifting apart is the defect, and the
    only way it has ever been noticed is somebody counting by hand.
    """

    def test_the_agreed_core_has_not_moved(self):
        lists = pv.read_all()
        agreed = set.intersection(*(lists[name] for name in pv.CLAIMANTS))
        self.assertEqual(
            agreed, AGREED,
            "the forms all four claimants agree are obligations have changed. "
            "Re-pin AGREED and say in the commit which list moved and why."
        )

    def test_the_documented_figure_still_reproduces(self):
        """`Docs/KNOWN_ISSUES.md` says seven forms are agreed. Recomputed."""
        lists = pv.read_all()
        agreed = lists["route"] & lists["title"] & lists["glue"]
        self.assertEqual(agreed, AGREED_IN_THE_DOCUMENTED_THREE)

    def test_the_core_is_a_small_part_of_the_whole(self):
        """The finding this suite was written around, kept recomputed.

        `Docs/KNOWN_ISSUES.md` says the lists agree on a small minority of the
        forms between them. That sentence is prose; this is the arithmetic
        under it, so the document cannot go on saying it after it stops being
        true.
        """
        lists = pv.read_all()
        whole = pv.union(lists)
        self.assertLess(len(AGREED), len(whole) / 2)
        self.assertEqual(len(whole), 37)


#: Every subject in the gating corpus that `obligationBelongsToAnotherPerson`
#: could read as an owner, with what it is. The rule's docstring says it does
#: not decide animacy, and that the cost of not deciding is hypothetical
#: because no inanimate subject is attested. That is a claim about a corpus
#: that grows every week, written as a sentence that recomputes nowhere -- and
#: it had already drifted: the docstring said 1,022 cases and
#: `Docs/KNOWN_ISSUES.md` said 1,069 for the same corpus, which held 1,404
#: that day.
#:
#: Animacy cannot be decided mechanically here -- that gap is the thing being
#: documented -- so the subjects are pinned by hand and the screen below is
#: what finds them. A new one fails this, and somebody looks at it once.
THIRD_PERSON_SUBJECTS_IN_THE_CORPUS = {
    "Mike": "a person",
    "My brother": "a person",
    "Priya": "a person",
    "Dana": "a person",
    "No": (
        "not a subject: the screen is wider than the rule and catches the "
        "bare `No` of `No need to book the table`. The corpus labels that row "
        "`count: 0, operation: [.cancel]`, so the parser does not read it as "
        "anybody's obligation. Kept here rather than excluded, because a "
        "screen narrowed until it agrees with the rule stops being able to "
        "disagree with it."
    ),
}


class WhoTheCorpusSaysOwesSomething(unittest.TestCase):
    """The attested half of the animacy decision, recomputed.

    `Actionability.obligationBelongsToAnotherPerson` files an obligation with a
    third-party subject in Memory without asking whether that subject is a
    person, so "the car has to go in Tuesday" goes to Memory too. The rule
    ships that way on purpose: it is the safer direction, and the corpus shows
    nothing of the shape.

    Only the second half of that is checkable, and only this way round. This
    suite cannot tell an animate subject from an inanimate one; it hands every
    subject of the shape to a person who can, and fails when the set changes.
    """

    def test_the_screen_finds_the_shape_it_claims_to(self):
        """A screen matching nothing would pass the census below in silence."""
        found = pv.third_person_subjects([
            "Mike should call Sarah",
            "The car has to go in Tuesday",
            "I need to call Mike",
            "Someone should build the deck",
            "tomorrow I need to book the table",
        ])
        self.assertEqual(
            [s for s, _ in found], ["Mike", "The car"],
            "the screen must catch a third-party subject whatever it denotes, "
            "and must not catch the speaker or an indefinite one"
        )

    def test_no_new_third_party_subject_has_appeared(self):
        census = {}
        for subject, text in pv.third_person_subjects():
            census.setdefault(subject, []).append(text)
        self.assertEqual(
            sorted(census), sorted(THIRD_PERSON_SUBJECTS_IN_THE_CORPUS),
            "the subjects the ownership rule could read as owners have "
            "changed. Decide whether the new one is a person: if it is not, "
            "the animacy gap in `obligationBelongsToAnotherPerson` has stopped "
            "being hypothetical and `Docs/KNOWN_ISSUES.md` needs the case. "
            "Either way, pin it in THIRD_PERSON_SUBJECTS_IN_THE_CORPUS with "
            "what it is. Found: " + repr(sorted(census))
        )


if __name__ == "__main__":
    unittest.main(verbosity=1)
