"""Self-tests for the measure that asks whether N instances are N observations."""
import pathlib
import re
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import observation  # noqa: E402


class TheLabelAndTheMeasureAreOneObject(unittest.TestCase):
    """The defect this module was written after, in its own terms.

    Two sizings published on 2026-09-14 named a phrase and counted a
    different one: rows filed under `I lost it` were matched by
    `I lost (it|my train)`, rows filed under trailing `I mean` were matched
    by `I mean` anywhere. Each overstated its form by a factor of four. A
    third figure was reported as drifting and had not: it was read out of a
    comma-separated list by position, against a phrase list in another order.
    Nothing caught any of it,
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

    def test_the_constant_is_the_only_copy_of_the_width(self):
        """`words=STEM_WORDS` in the signature made the constant a copy.

        A default argument binds once, at definition. So rebinding
        `observation.STEM_WORDS` renamed a value nothing read, and the
        obvious test of whether the width matters -- set it, call `stem`,
        watch the answer move -- would have reported that it does not,
        while passing. The width has to be resolved when `stem` runs.
        """
        was = observation.STEM_WORDS
        try:
            observation.STEM_WORDS = 2
            self.assertEqual(observation.stem("one two three four"),
                             "one two")
            self.assertEqual(
                observation.shape([("s", "one two three four"),
                                   ("s", "one two nine ten")]).stems, 1,
                "shape must take the width from the constant too")
        finally:
            observation.STEM_WORDS = was
        self.assertEqual(observation.stem("one two three four"),
                         "one two three four")


class TheStemWidthIsADecisionAndIsPinnedLikeOne(unittest.TestCase):
    """`STEM_WORDS` moves verdicts, and only its own value pinned it.

    Mutating it to 3, 4, 6 or 8 failed exactly one test -- the
    `assertEqual(STEM_WORDS, 5)` above -- and `self_check()` returned True at
    every one of those widths. A value pin catches an edit and says nothing
    about what the value buys, so the next reader with a reason to widen it
    updates the number, gets green, and loses findings silently.

    On readable material the width is not a rounding choice. `then` carries
    37% on one frame at four words and 5% at five; `meaning` 35% and 18%.
    `plus` holds 66% through six words and falls to 11% at eight, and `wait`
    36% to 6% -- so the two forms this instrument was built to find both stop
    being marked somewhere between six words and eight.
    """

    def widths(self, population):
        return {n: observation.shape(population, n).concentrated
                for n in range(3, 9)}

    def test_the_narrow_canary_differs_at_exactly_word_five(self):
        """The fixture's shape, pinned so an edit cannot flatten it.

        If these sentences stopped agreeing through word four, or started
        agreeing at word five, the straddle would keep passing and pin
        nothing -- which is how a fixture that cannot tell two states apart
        gets written in the first place.
        """
        texts = [text for _, text in observation.CANARY_NARROW]
        self.assertEqual(len(set(texts)), len(observation.STEM_PROBE))
        self.assertEqual(len({observation.stem(x, 4) for x in texts}), 1)
        self.assertEqual(len({observation.stem(x, 5) for x in texts}),
                         len(texts))

    def test_the_wide_canary_differs_at_exactly_word_six(self):
        texts = [text for _, text in observation.CANARY_WIDE]
        shared = [x for x in texts if x.startswith("I was going to ask")]
        self.assertEqual(len(shared), observation.WIDE_ON_ONE_STEM)
        self.assertEqual(len({observation.stem(x, 5) for x in shared}), 1)
        self.assertEqual(len({observation.stem(x, 6) for x in shared}),
                         len(shared))

    def test_neither_canary_is_decided_by_the_source_arm(self):
        """`concentrated` is an OR. A single-source fixture measures the
        width not at all, which is how the threshold went unpinned."""
        for name in ("CANARY_NARROW", "CANARY_WIDE"):
            found = observation.shape(getattr(observation, name))
            self.assertGreater(found.sources, observation.ONE_SOURCE, name)

    def test_narrowing_the_width_invents_a_template(self):
        marks = self.widths(observation.CANARY_NARROW)
        self.assertEqual(marks, {3: True, 4: True, 5: False,
                                 6: False, 7: False, 8: False})

    def test_widening_the_width_loses_a_real_template(self):
        marks = self.widths(observation.CANARY_WIDE)
        self.assertEqual(marks, {3: True, 4: True, 5: True,
                                 6: False, 7: False, 8: False})

    def test_exactly_one_width_satisfies_the_whole_canary_set(self):
        """The straddle, stated as the single claim it exists to make."""
        passing = [n for n in range(3, 9)
                   if observation.self_check(
                       lambda pairs, n=n: observation.shape(pairs, n))]
        self.assertEqual(passing, [observation.STEM_WORDS])

    def test_the_probe_words_vary_where_the_measure_can_see(self):
        """`stem` drops digits, so a numeric probe varies nothing."""
        import re
        self.assertEqual(len(set(observation.STEM_PROBE)),
                         len(observation.STEM_PROBE))
        for word in observation.STEM_PROBE:
            self.assertRegex(word, r"^[a-z]+$")


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


class TheThresholdIsTheDecisionAndIsPinnedLikeOne(unittest.TestCase):
    """`CROWDED_STEM` could be moved from 0.25 to 0.99 with every test green.

    Found by the core language thread's review. Not cosmetic: it silently
    stops marking the exact population the stem measure was added for, and
    the suite reports nothing, which is what a working suite also reports.

    The reason the canaries missed it is the useful half. `concentrated` is
    an OR of two arms, and both canaries are single-source, so `ONE_SOURCE`
    decided them and `CROWDED_STEM` was never consulted. `CANARY_TEMPLATED`
    is also at share 1.0 -- at ceiling on the property under test, so no
    threshold below it can be measured. Same shape as a control already at
    ceiling, and the same shape as `self_check` being asserted true by a test
    that would accept a canary which always returns true.
    """

    def test_the_straddle_pair_sits_either_side_of_the_constant(self):
        crowded = observation.shape(observation.CANARY_CROWDED)
        spread = observation.shape(observation.CANARY_SPREAD)
        self.assertGreaterEqual(crowded.largest_share, observation.CROWDED_STEM)
        self.assertLess(spread.largest_share, observation.CROWDED_STEM)

    def test_neither_straddle_fixture_is_decided_by_the_source_arm(self):
        """If either were single-source this pair would prove nothing."""
        for name in ("CANARY_CROWDED", "CANARY_SPREAD"):
            found = observation.shape(getattr(observation, name))
            self.assertGreater(found.sources, observation.ONE_SOURCE, name)

    def test_the_straddle_is_derived_rather_than_written_at_0_25(self):
        """Moving the threshold on purpose must not leave a stale fixture."""
        source = pathlib.Path(observation.__file__).read_text()
        derived = source.split("STRADDLE_ROWS = ")[1].split("CANARY_SPREAD")[0]
        self.assertIn("CROWDED_STEM", derived,
                      "the straddle must be computed from the constant")
        self.assertNotIn("0.25", derived)

    def test_the_threshold_still_marks_the_shape_it_was_chosen_for(self):
        """The pinned half, and the one that catches 0.25 -> 0.99.

        Ten distinct utterances, four of them one frame, over four sources.
        That is the `wait` shape -- concentrated by frame while spread across
        sources, which is precisely the half `ONE_SOURCE` cannot see. A
        threshold that does not mark this is not the threshold this module
        was built around, whatever the straddle pair says about itself.
        """
        found = observation.shape(observation.frame_population(10, 4))
        self.assertEqual(found.rows, 10)
        self.assertGreater(found.sources, observation.ONE_SOURCE)
        self.assertAlmostEqual(found.largest_share, 0.4)
        self.assertTrue(
            found.concentrated,
            f"CROWDED_STEM is {observation.CROWDED_STEM}, which no longer "
            f"marks a population that is 40% one frame across four sources")

    def test_the_threshold_still_leaves_a_dispersed_population_unmarked(self):
        """The other direction, and it is not symmetric with the first.

        A threshold drifting down marks ordinary dispersion, and the mark is
        the part that gets quoted, so it would stop good proposals rather
        than let bad ones through. At 0.10 this module's own report marks
        `I mean` at 17%, which is a form spread over six stems in six rows.
        """
        found = observation.shape(observation.frame_population(20, 3))
        self.assertAlmostEqual(found.largest_share, 0.15)
        self.assertGreater(found.sources, observation.ONE_SOURCE)
        self.assertFalse(
            found.concentrated,
            f"CROWDED_STEM is {observation.CROWDED_STEM}, which now marks a "
            f"population that is 15% one frame over four sources")

    def test_the_band_these_tests_leave_free_is_stated_not_implied(self):
        """Two pinned shapes bound the constant to (0.15, 0.40].

        Inside that band a change is deliberate and these tests stay green,
        which is what the straddle pair is for and is the reviewer's own
        requirement. Saying where the band ends is the honest part: a test
        suite that pins a constant loosely and implies it pins it exactly is
        the same defect as a marker standing in for a judgement.
        """
        self.assertGreater(observation.CROWDED_STEM, 0.15)
        self.assertLessEqual(observation.CROWDED_STEM, 0.40)

    def test_the_canary_notices_a_threshold_that_marks_nothing(self):
        def never_crowded(pairs):
            found = observation.shape(pairs)
            return found._replace(concentrated=found.sources <= 1)
        self.assertFalse(observation.self_check(never_crowded))

    def test_the_canary_notices_a_threshold_that_marks_everything(self):
        def always_crowded(pairs):
            return observation.shape(pairs)._replace(concentrated=True)
        self.assertFalse(observation.self_check(always_crowded))

    def test_a_population_too_large_for_the_openings_is_refused(self):
        with self.assertRaises(ValueError):
            observation.frame_population(100, 50)
        with self.assertRaises(ValueError):
            observation.frame_population(10, 0)


class AbsenceAndDispersionDoNotPrintTheSame(unittest.TestCase):
    """`concentrated` is False for a form nobody says and for one said fifty
    ways. Printing only CONCENTRATED or nothing made those identical, and
    absence is the answer that ends a proposal -- the one that must never be
    mistaken for a measurement."""

    def test_a_form_with_no_rows_reads_absent(self):
        self.assertIn("ABSENT", observation.mark_for(observation.shape([])))

    def test_a_population_of_one_is_too_few_rather_than_concentrated(self):
        found = observation.shape([("a", "hold on I lost it")])
        self.assertEqual(found.largest_share, 1.0)
        self.assertTrue(found.concentrated, "the arithmetic is still true")
        self.assertIn("TOO FEW", observation.mark_for(found))
        self.assertNotIn("CONCENTRATED", observation.mark_for(found))

    def test_a_real_concentration_still_says_so(self):
        found = observation.shape(observation.frame_population(10, 4))
        self.assertIn("CONCENTRATED", observation.mark_for(found))

    def test_a_dispersed_population_gets_no_mark(self):
        found = observation.shape(observation.CANARY_VARIED)
        self.assertEqual(observation.mark_for(found).strip(), "")

    def test_too_few_is_the_boundary_it_says_it_is(self):
        at = observation.shape(observation.frame_population(
            observation.TOO_FEW, observation.TOO_FEW))
        self.assertNotIn("TOO FEW", observation.mark_for(at))
        below = observation.shape(observation.frame_population(
            observation.TOO_FEW - 1, observation.TOO_FEW - 1))
        self.assertIn("TOO FEW", observation.mark_for(below))


class WhatItReadsIsCheckedAgainstTheOneOwner(unittest.TestCase):
    """This module used to print a list of populations it did not read.

    Honest, and the reason every figure it produced needed qualifying: `plus`
    reported 0 rows here and 44 in the census, and a reader checking a figure
    got the wrong answer with no error. Both populations are read now, so the
    list is gone and the claim it was hedging -- that this reads all readable
    material -- has to be checked instead, because a silent claim of total
    coverage is worse than a stated gap. Four instruments in this directory
    have described themselves as covering readable material while omitting
    some of it, this one included.
    """

    @classmethod
    def setUpClass(cls):
        import readable_material
        cls.rm = readable_material
        cls.pairs = list(observation.readable_pairs())

    def test_it_reads_the_same_population_the_census_reports(self):
        """Against the census's own reported figure, not against the walk.

        Comparing `readable_pairs()` to `readers()` would be very nearly a
        tautology, since the first is built on the second: both would go to
        zero together and agree perfectly. So this asks the other instrument
        what it counted and requires the same number.
        """
        import importlib.util
        here = pathlib.Path(observation.__file__).resolve().parent
        spec = importlib.util.spec_from_file_location(
            "connective_census_for_test", here / "connective-census.py")
        census = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(census)
        _counts, distinct, sources = census.census()

        mine = {text for _s, text in self.pairs}
        self.assertGreater(distinct, 5000, "the census itself read nothing")
        self.assertEqual(len(mine), distinct)
        # `census()` returns sources as (path, rows, distinct) triples.
        self.assertEqual(len({s for s, _t in self.pairs}), len(sources))
        self.assertTrue(all(rows > 0 for _p, rows, _d in sources),
                        "a source reading nothing reports every form absent")

    def test_every_declared_source_actually_contributed(self):
        """A source reading nothing reports every form absent, and absence is
        the answer that ends a proposal."""
        carried = {name for name, _t in self.pairs}
        self.assertEqual(len(carried), len(self.rm.readers()))

    def test_the_source_key_is_a_path_and_not_a_basename(self):
        """The bug this caught in itself, kept as a regression.

        Two sources are both named `renderings.jsonl`, under different
        SpeechLab directories. Keyed on the basename they merged: nineteen
        sources for twenty, and any form appearing in only those two would
        report `sources == 1` and be marked CONCENTRATED by the source arm --
        a false mark from the half of the measure that exists to catch
        exactly this.
        """
        names = [p.name for p, _r in self.rm.readers()]
        self.assertLess(len(set(names)), len(names),
                        "if basenames stop colliding this proves nothing")
        keys = {name for name, _t in self.pairs}
        self.assertEqual(len(keys), len(self.rm.readers()))

    def test_the_two_multi_word_rules_have_not_drifted_apart(self):
        """`swift_utterances` filters `len(split()) > 1`; the count this
        module used to publish was measured with `" " in strip()`. They agree
        on this corpus, exactly and in both directions, which is worth
        pinning rather than trusting -- "multi-word" was standing in for a
        rule nobody had written down, and reading it three ways gave 3702,
        3760 and 3804.
        """
        root = pathlib.Path(self.rm.__file__).resolve().parents[2]
        found = set()
        for swift in sorted((root / "SpeakItTests").glob("*.swift")):
            text = swift.read_text(encoding="utf-8", errors="replace")
            found.update(self.rm.swift_literals(text))
        space = {l for l in found if " " in l.strip()}
        split = {l for l in found if len(l.split()) > 1}
        self.assertEqual(space, split)
        self.assertEqual(len(space), 3702)

    def test_the_coverage_statement_carries_no_hand_typed_figure(self):
        """It says what is read, not how much. A count in there is one
        nothing recomputes, which is how the last three got in."""
        self.assertNotRegex(re.sub(r"#\d+", "", observation.READ_WHAT), r"\d")

    def test_the_coverage_statement_names_the_owner(self):
        self.assertIn("readable_material", observation.READ_WHAT)
        self.assertIn("sealed", observation.READ_WHAT)


if __name__ == "__main__":
    unittest.main()
