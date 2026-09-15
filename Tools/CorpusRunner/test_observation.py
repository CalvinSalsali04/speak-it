"""Self-tests for the measure that asks whether N instances are N observations."""
import pathlib
import re
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import observation  # noqa: E402


class TheLabelAndTheMeasureAreOneObject(unittest.TestCase):
    """The defect this module was written after, in its own terms.

    Three sizings published on 2026-09-14 named a phrase and counted a
    different one: rows filed under `I lost it` were matched by `I lost`,
    rows filed under trailing `I mean` were matched by `I mean` anywhere.
    Each overstated its form by a factor of four or more. Nothing caught it,
    because the name lived in prose and the pattern lived in a script and
    neither had any way to disagree out loud.

    `pattern_for` takes the phrase and nothing else, so the two cannot drift.
    These tests are what stops a regex argument being added back.
    """

    def test_a_matched_row_always_contains_the_phrase_it_is_filed_under(self):
        rows = [
            "I lost the thread of what I was saying",
            "I lost it completely halfway through",
            "so I mean that is the gist",
            "the thing is, I mean",
        ]
        for phrase in ("I lost it", "I mean"):
            found = observation.pattern_for(phrase)
            for row in rows:
                if found.search(row):
                    self.assertIn(phrase.lower(), row.lower(),
                                  f"{row!r} counted under {phrase!r}")

    def test_the_phrase_that_was_overcounted_is_now_separated(self):
        """`I lost` matched four rows and `I lost it` one. The difference was
        the entire discrepancy in the published figure."""
        rows = ["I lost the thread", "I lost my place", "I lost it", "I lost track"]
        hit = [r for r in rows if observation.pattern_for("I lost it").search(r)]
        self.assertEqual(hit, ["I lost it"])

    def test_trailing_is_an_argument_rather_than_a_pattern(self):
        rows = ["the thing is, I mean", "I mean the blue one", "I mean."]
        trailing = observation.pattern_for("I mean", "trailing")
        self.assertEqual([r for r in rows if trailing.search(r)],
                         ["the thing is, I mean", "I mean."])
        anywhere = observation.pattern_for("I mean", "anywhere")
        self.assertEqual(len([r for r in rows if anywhere.search(r)]), 3)

    def test_leading_is_too(self):
        rows = ["I forgot the milk", "and I forgot the milk", "  I forgot"]
        leading = observation.pattern_for("I forgot", "leading")
        self.assertEqual([r for r in rows if leading.search(r)],
                         ["I forgot the milk", "  I forgot"])

    def test_an_unknown_anchor_is_refused(self):
        """Not silently treated as `anywhere`, which is the loosest reading
        and the one that overstates."""
        with self.assertRaises(ValueError):
            observation.pattern_for("I mean", "at the end")

    def test_whitespace_between_the_words_is_flexible_but_the_words_are_not(self):
        found = observation.pattern_for("hold on")
        self.assertTrue(found.search("hold  on a second"))
        self.assertTrue(found.search("HOLD ON"))
        self.assertFalse(found.search("holding on"))
        self.assertFalse(found.search("hold the line on"))


class TheMeasureCanTellTheTwoApart(unittest.TestCase):
    """A measure that reported every population as diverse would pass every
    other test here and let every proposal through, since diverse is the
    answer that does not stop anything."""

    def test_the_canary(self):
        self.assertTrue(observation.self_check())

    def test_the_canary_notices_a_broken_measure(self):
        """Without this, `self_check` forced to `return True` passes the test
        above and every number the report prints is unguarded. That mutation
        was the only one of eleven this module did not catch."""
        def always_concentrated(pairs):
            return observation.Shape(len(pairs), 1, 1, len(pairs), 1.0, True)

        def always_diverse(pairs):
            return observation.Shape(len(pairs), 9, len(pairs), 1, 0.0, False)

        self.assertFalse(observation.self_check(always_concentrated),
                         "a measure calling everything concentrated passed")
        self.assertFalse(observation.self_check(always_diverse),
                         "a measure calling everything diverse passed -- and "
                         "diverse is the answer that stops nothing")

    def test_one_frame_many_rows_is_concentrated(self):
        found = observation.shape(observation.CANARY_TEMPLATED)
        self.assertEqual(found.stems, 1)
        self.assertEqual(found.largest_share, 1.0)
        self.assertTrue(found.concentrated)

    def test_many_frames_many_sources_is_not(self):
        found = observation.shape(observation.CANARY_VARIED)
        self.assertEqual(found.stems, len(observation.CANARY_VARIED))
        self.assertFalse(found.concentrated)

    def test_one_source_is_concentrated_however_varied_the_frames(self):
        """`plus`: 41 rows, 41 different sentences, one file. Frame diversity
        does not make twelve views of one population into twelve."""
        pairs = [("only.jsonl", f"{word} thing before the week is out")
                 for word in observation.VARIED_OPENINGS]
        found = observation.shape(pairs)
        self.assertEqual(found.stems, len(pairs))
        self.assertTrue(found.concentrated, "one source is one body of material")

    def test_one_utterance_in_two_sources_is_one_row_and_two_sources(self):
        """The two counts have to be taken differently or the shape is wrong
        in opposite directions. Counting the pairs inflates `rows` by however
        many copies a dozen views of one population keep; deduplicating and
        keeping only the survivor's source understates the spread."""
        pairs = [("a.tsv", "the lease ends in March next year"),
                 ("b.tsv", "the lease ends in March next year"),
                 ("b.tsv", "put the bins out before Thursday morning")]
        found = observation.shape(pairs)
        self.assertEqual(found.rows, 2, "the duplicate is one utterance")
        self.assertEqual(found.sources, 2, "but both files carry material")

    def test_a_duplicate_does_not_invent_a_frame(self):
        """`stems` counts over distinct text too, or a copied row reads as a
        second instance of its own frame."""
        pairs = [("a", "I was going to ask wait about the keys"),
                 ("b", "I was going to ask wait about the keys")]
        found = observation.shape(pairs)
        self.assertEqual((found.rows, found.stems, found.largest_stem), (1, 1, 1))

    def test_nothing_matched_is_not_quietly_diverse(self):
        """Zero rows must not come back looking like a healthy population."""
        found = observation.shape([])
        self.assertEqual(found.rows, 0)
        self.assertEqual(found.stems, 0)
        self.assertFalse(found.concentrated)

    def test_digits_do_not_make_frames(self):
        """Recorded because it is load bearing and caught the canary's own
        first fixture: variation that is only numeric is invisible here."""
        pairs = [("s", f"call Ana at {n} about the thing") for n in range(20)]
        self.assertEqual(observation.shape(pairs).stems, 1)

    def test_punctuation_and_case_do_not_make_frames(self):
        pairs = [("s", "I was GOING to ask— wait, the keys"),
                 ("s", "I was going to ask, wait: the keys")]
        self.assertEqual(observation.shape(pairs).stems, 1)

    def test_the_stem_length_is_named_once(self):
        """Every figure derived from a stem moves when this moves, so it is a
        constant rather than a default repeated at each call site."""
        self.assertEqual(observation.STEM_WORDS, 5)
        self.assertEqual(observation.stem("one two three four five six"),
                         "one two three four five")


class TheCensusReportsPerForm(unittest.TestCase):

    POOL = ([("a.jsonl", f"I was going to ask wait about the {w}")
             for w in observation.VARIED_OPENINGS]
            + [(f"s{n}.tsv", f"{w} thing before the week is out")
               for n, w in enumerate(observation.VARIED_OPENINGS)])

    def test_a_templated_form_and_a_spread_one_are_distinguished(self):
        found = observation.census({"wait": "anywhere", "thing": "anywhere"},
                                   self.POOL)
        self.assertTrue(found["wait"].concentrated)
        self.assertFalse(found["thing"].concentrated)
        self.assertEqual(found["wait"].rows, found["thing"].rows,
                         "the row count is the same, which is the point")

    def test_a_form_nobody_says_reports_zero_rows_rather_than_being_absent(self):
        found = observation.census({"therefore": "anywhere"}, self.POOL)
        self.assertIn("therefore", found)
        self.assertEqual(found["therefore"].rows, 0)


if __name__ == "__main__":
    unittest.main()
