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

Every multi-word frame ends in `to`, and `to` has been the first entry of
`clauseInternalLead` since it was written, so multi-word frames are protected
whether or not anyone decided to protect them. Only single tokens are exposed,
which is what makes this checkable rather than a matter of judgement.
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


#: Single-token obligation forms the splitter deliberately does not hold, and
#: why. An entry here is a decision somebody made, not a gap.
#:
#: Keep this list short and keep the reasons specific. A form added here
#: without a reason that survives reading is how the defect above comes back.
DELIBERATELY_UNPROTECTED = {
    "better": (
        "also an ordinary comparative, and a comparative is exactly where a "
        "spoken sentence ends one clause and starts another -- 'the weather is "
        "better book the campsite' has to split. See `deonticBetterSubject`."
    ),
}

#: What each list held when this suite was written. Pinned so that a list
#: quietly losing an entry fails here; a deliberate change re-pins it and says
#: why in the commit, exactly as `test_observation.py`'s census does.
SIZES = {"split": 144, "route": 23, "whose": 9, "title": 24, "glue": 10}

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
        empty set there would pass `single_token(...) <= split` trivially, and
        the suite would report a clean bill for a vocabulary it could not see.
        """
        cases = {
            "SpeechRepair.swift": ("clauseInternalLead", pv.clause_internal_lead),
            "Actionability.swift": ("obligationLead", pv.obligation_lead),
            "ThoughtOrganizer.swift": ("let link", pv.obligation_frame_link),
            "ThoughtExtractor.swift": (r'of: #"^(?:i\s+)?(?:', pv.dangling_auxiliary),
        }
        original = pv.REPOS
        for filename, (needle, reader) in cases.items():
            with self.subTest(filename), tempfile.TemporaryDirectory() as tmp:
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
        self.singles = pv.single_token(pv.union(self.lists))

    def test_every_single_token_form_is_held_by_the_splitter(self):
        unprotected = self.singles - self.lists["split"]
        undeclared = unprotected - set(DELIBERATELY_UNPROTECTED)
        self.assertFalse(
            undeclared,
            f"{sorted(undeclared)} are obligation forms of one word that "
            "`clauseInternalLead` does not hold, so a sentence can be cut "
            "between them and what they govern -- the `I hafta` defect. Add "
            "them to `clauseInternalLead`, or to DELIBERATELY_UNPROTECTED with "
            "a reason."
        )

    def test_every_declared_exception_is_still_one(self):
        """A declaration that has stopped being true is a place to hide a form.

        If `better` is added to `clauseInternalLead` tomorrow, the entry above
        becomes a comment that reads like a rule and checks nothing, and the
        next form added beside it inherits that.
        """
        for form, reason in DELIBERATELY_UNPROTECTED.items():
            with self.subTest(form):
                self.assertIn(
                    form, self.singles,
                    f"`{form}` is declared unprotected but no list calls it an "
                    "obligation any more; drop the declaration."
                )
                self.assertNotIn(
                    form, self.lists["split"],
                    f"`{form}` is declared unprotected and the splitter now "
                    "holds it; drop the declaration."
                )
                self.assertGreater(len(reason), 40, "a reason, not a label")

    def test_the_check_notices_a_form_that_slips_through(self):
        """The mutation the test above exists for, run against it."""
        lists = copy.deepcopy(self.lists)
        lists["route"] = lists["route"] | {"mustnt"}
        slipped = pv.single_token(pv.union(lists)) - lists["split"]
        self.assertIn("mustnt", slipped - set(DELIBERATELY_UNPROTECTED))


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
        self.assertEqual(len(whole), 38)


if __name__ == "__main__":
    unittest.main(verbosity=1)
