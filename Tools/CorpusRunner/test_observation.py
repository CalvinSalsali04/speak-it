"""Self-tests for the measure that asks whether N instances are N observations."""
import pathlib
import re
import sys
import unittest
import unittest.mock

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

    #: The corpus states an `equivalence_class` per rendering. Found by
    #: walking `readable_material.readers()` rather than by naming a file,
    #: because the first version of this test hard-coded one path and one
    #: field name -- the exact pattern `readable_material` was written to end
    #: -- and read two of the six sources that carry the column.
    def declaring_sources(self):
        """Every readable jsonl carrying the column, and whether it groups."""
        import json, readable_material
        sealed = {q.resolve() for q in readable_material.corpus_paths.sealed()}
        found = {}
        for path, _read in readable_material.readers():
            if path.suffix != ".jsonl":
                continue
            #: A second refusal, not the first one. `speechlab_files()`
            #: raises on a sealed path before `readers()` can yield it, so
            #: this cannot fire today and is stated as a duplicate rather
            #: than counted as the guard. It stays because the cost of being
            #: wrong here is reading sealed material, and because the walk
            #: could gain a source that does not come through that refusal.
            self.assertNotIn(path.resolve(), sealed,
                             f"{readable_material.shown(path)} is sealed and "
                             f"this test opens it")
            rows = [json.loads(line) for line
                    in path.read_text(encoding="utf-8").splitlines()
                    if line.strip()]
            if not rows or not all("equivalence_class" in r for r in rows):
                continue
            #: Non-None by construction: `readers()` drops any file whose
            #: `utterance_field` is None before yielding it. Asserting it
            #: here would be a check that cannot fail, which reads the same
            #: as one that passes.
            field = readable_material.utterance_field(path)
            found[str(readable_material.shown(path))] = [
                (r[field], r["equivalence_class"],
                 r["equivalence_class"] == r.get("blueprint_id"))
                for r in rows]
        return found

    def test_only_one_source_declares_a_grouping_and_the_rest_are_names(self):
        """Five of the six carry the column as another spelling of the id.

        `equivalence_class == blueprint_id` on every row means the column
        groups nothing -- it is a name. Someone will reach for it precisely
        because of what it is called, so the distinction is measured rather
        than remembered. A second real grouping appearing here is a reason to
        re-make the choice below, not to fold it into the same figure.
        """
        sources = self.declaring_sources()
        self.assertGreaterEqual(len(sources), 2, "a file list that shrank "
                                "would satisfy the assertions below")
        grouping = {name for name, rows in sources.items()
                    if not all(degenerate for _, _, degenerate in rows)}
        self.assertEqual(
            grouping, {"Tools/SpeechLab/phase2/data/renderings.jsonl"},
            "exactly one readable source groups renderings by meaning")

    def test_the_declared_class_is_not_a_sharper_stem(self):
        """Why the unit is the frame and not the class the corpus declares.

        Phase 2 states 818 renderings over 137 declared meanings, which reads
        as ground truth for "how many independent observations is this" and
        would retire the five-word heuristic. It is ground truth for a
        different question. Two renderings sit in different classes when they
        *mean* different things, and the generator varies meaning by refilling
        the slots of one sentence:

            Could you hang onto both of these--<errand>, plus <fact>

        **Measured on this one source, so that rows and groups share a
        denominator.** An earlier version grouped every readable row, falling
        back to the frame for rows declaring no class, and reported `plus` as
        44 rows over 32 groups and `wait` as 53 over 50. Those are two units
        in one column: only 41 of `plus`'s rows declare a class and only 31
        of `wait`'s, so `wait`'s "50" was 31 declared classes and 19 frames
        added together. The conclusion was unchanged and the honest figures
        are wider apart, which is the usual way round for a mixed
        denominator -- the mixing diluted the effect rather than making it.

        **The per-form figures are in `SHAPE_ON_PHASE_TWO` and asserted by
        `test_the_table_in_the_argument_is_recomputed_per_form`, not written
        out here.** They were written out here, in the very change that
        corrected them, while the assertions in this test stayed aggregate
        and caught nothing. A second copy in prose drifts from the copy that
        is checked, which is the failure this whole class is about.

        The class erases the concentration this instrument exists to
        report. It is the right denominator for meaning coverage and the
        wrong one for form coverage, and a connective is a property of the
        form.

        There is a second, independent reason, and it is the stronger one:
        the renderings were generated *from* the classes rather than
        classified afterwards -- every row carries a `blueprint_id`, a
        deterministic generator and a `curated phrase-plan` authoring method
        -- so 137 is a parameter of the generator. Counting it measures the
        generator, not the material.

        This asserts the fact the argument rests on, because an argument in a
        comment is worth nothing once the corpus it describes has moved on.
        """
        import collections
        rows = self.declaring_sources()[
            "Tools/SpeechLab/phase2/data/renderings.jsonl"]
        self.assertGreater(len(rows), 500, "a file that shrank to nothing "
                           "would satisfy every assertion below")
        per_frame = collections.defaultdict(set)
        for text, klass, _ in rows:
            per_frame[observation.stem(text)].add(klass)
        classes = {klass for _, klass, _ in rows}
        busiest = max(len(seen) for seen in per_frame.values())

        self.assertLess(len(classes), len(per_frame),
                        "fewer declared meanings than frames would make the "
                        "class the coarser unit, and this argument the wrong "
                        "way round")
        self.assertGreaterEqual(
            busiest, 10,
            f"one frame carried {busiest} declared meanings, so the class no "
            f"longer separates what the frame merges and the unit is worth "
            f"revisiting")

    #: The four figures per form the argument above is made of, so that the
    #: table is this test's output rather than a claim beside it. Written
    #: because the assertions in the test above are aggregates over all 818
    #: rows -- `len(classes) < len(per_frame)` and `busiest >= 10` -- and not
    #: one of them is per-form. They stood unchanged while the column was 31
    #: declared classes and 19 frames added together, and they stand unchanged
    #: now that it is 31 of 31: they did not catch that error and would not
    #: catch the next one. A figure lives where something recomputes it, and
    #: this figure was living in a docstring inside the pull request that
    #: corrected it.
    SHAPE_ON_PHASE_TWO = {
        #  form:  (rows, frames, busiest frame, classes, busiest class)
        "plus": (41, 9, 29, 29, 2),
        "wait": (31, 7, 19, 31, 1),
    }

    def test_the_table_in_the_argument_is_recomputed_per_form(self):
        """Each form's row against the one source, measured both ways."""
        import collections
        rows = self.declaring_sources()[
            "Tools/SpeechLab/phase2/data/renderings.jsonl"]
        for form, expected in sorted(self.SHAPE_ON_PHASE_TWO.items()):
            pattern = observation.pattern_for(form)
            #: One class per distinct utterance, asserted rather than
            #: assumed, so both columns are counted over the same thing.
            #: This was `Counter(k for t, k in hits if t in texts)`, where
            #: `texts` was built from `hits` -- so the filter read as a
            #: deduplication and removed nothing, leaving frames counted over
            #: distinct texts and classes over rows. Identical today, since
            #: phase 2 holds 818 distinct texts over 818 rows, and this
            #: pull request's own defect one level down the moment it is not.
            declared = {}
            for text, klass, _degenerate in rows:
                if not pattern.search(text):
                    continue
                self.assertEqual(declared.setdefault(text, klass), klass,
                                 f"{form}: one utterance, two declared "
                                 f"classes, so the two columns would stop "
                                 f"sharing a denominator")
            texts = set(declared)
            frames = collections.Counter(observation.stem(t) for t in texts)
            classes = collections.Counter(declared.values())
            self.assertEqual(
                (len(texts), len(frames), max(frames.values()),
                 len(classes), max(classes.values())), expected, form)

    def test_the_frame_concentrates_and_the_declared_class_does_not(self):
        """The claim the table exists to support, as a comparison.

        Stated as the inequality rather than as two percentages, because the
        percentages are what drifted. Both forms are marked by the frame and
        neither by the class, which is the whole result: adopting the class
        erases both findings.
        """
        for form, (rows, _f, frame, _c, klass) in sorted(
                self.SHAPE_ON_PHASE_TWO.items()):
            self.assertGreaterEqual(frame / rows, observation.CROWDED_STEM,
                                    f"{form} is concentrated by frame")
            self.assertLess(klass / rows, observation.CROWDED_STEM,
                            f"{form} is not concentrated by declared class")

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


class TheMotivatingFiguresAtTheTopAreRecomputed(unittest.TestCase):
    """The two bullets opening `observation.py` are the argument for it.

    They are also a paragraph of figures with nothing holding them to the
    corpus, and one went stale exactly that way: the `wait` bullet said 14
    sources, #70 fixed the `path.name` collision that produced 14 and wrote
    "`wait` is 15 sources rather than the 14 reported in #68" into its own
    commit message, and the bullet went on saying 14 for a day. The same paragraph told a reader that running this module "will
    not reproduce them", which #70 had made false in the other direction --
    it reproduces both lines exactly.

    Neither was caught by anything. Sweeping every digit written inside a
    comment or a string in this one file turned up three sites that needed
    changing, all three found by reading rather than by an instrument. This
    pins the two bullets, which are the claims the module is argued from; it
    is not a general mechanism for prose, and the rest of the file's prose
    remains unpinned.
    """

    #: (rows, sources, stems, largest frame as a whole percent) for the two
    #: forms the module docstring is about, recomputed below rather than
    #: trusted. Same shape as `SHAPE_ON_PHASE_TWO` in #73 and for the same
    #: reason: a figure lives where something recomputes it.
    MOTIVATING = {"plus": (48, 8, 12, 65), "wait": (58, 18, 30, 33)}

    def test_the_corpus_still_says_what_the_bullets_say(self):
        forms = {phrase: "anywhere" for phrase in self.MOTIVATING}
        found = observation.census(forms, list(observation.readable_pairs()))
        measured = {phrase: (shape.rows, shape.sources, shape.stems,
                             round(shape.largest_share * 100))
                    for phrase, shape in found.items()}
        self.assertEqual(measured, self.MOTIVATING)

    def test_the_bullets_state_those_figures(self):
        """The tuple above pins the corpus; this pins the prose to the tuple.

        Only the figures written as digits are matched. `twelve stems`, `two
        thirds` and `a third` are words in that paragraph and are not parsed
        here -- they ride on the tuple, which fails first and puts whoever
        fixes it in the right paragraph.
        """
        rows, sources, _stems, _share = self.MOTIVATING["plus"]
        self.assertIn(f"`plus` appears in {rows} readable utterances across "
                      f"{sources} sources", observation.__doc__)
        self.assertIn(f"carry all {rows} rows", observation.__doc__)
        rows, sources, _stems, _share = self.MOTIVATING["wait"]
        self.assertIn(f"`wait` appears in {rows} over {sources} sources",
                      observation.__doc__)

    def test_the_paragraph_does_not_say_the_figures_will_not_reproduce(self):
        """The sentence that went false in the other direction.

        It said this module reads the development sets alone, so running it
        would not reproduce the bullets. #70 wired the walk and made that
        untrue, and a docstring warning a reader off correct output is worse
        than one quoting a stale number, because there is no digit to check.

        This is the weak half deliberately. The test above is what actually
        establishes that the bullets reproduce, by reproducing them; this
        only stops the retracted sentence returning in the wording it had,
        and a denial worded differently would pass it.
        """
        self.assertNotIn("will not reproduce", observation.__doc__)
        self.assertIn("python3 observation.py plus wait", observation.__doc__)


class ARefusalFromTheWalkReadsAsARefusal(unittest.TestCase):
    """A raise from `readers()` is a result, not a crash.

    `connective-census.py` prints "REFUSED: ..." and exits 2 for the same
    three conditions -- a sealed path, a renamed utterance column, an
    unclassified SpeechLab file -- while this module printed a traceback.
    Both are loud, so this is not a correctness fix; it is that one of the two
    tells a reader what to do and the other makes them read a stack.
    """

    def test_it_prints_a_sentence_and_exits_two(self):
        import contextlib, io
        def refuse():
            raise ValueError("a source is unclassified")
        out = io.StringIO()
        with unittest.mock.patch.object(observation, "readable_pairs", refuse):
            with contextlib.redirect_stdout(out):
                code = observation.main([])
        self.assertEqual(code, 2)
        self.assertIn("REFUSED", out.getvalue())
        self.assertIn("a source is unclassified", out.getvalue())
        self.assertNotIn("Traceback", out.getvalue())

    def test_it_prints_no_figure_after_refusing(self):
        """A refusal that still prints a table is the worse of the two.

        The exit code is read by CI and the table is read by a person, so a
        run that says REFUSED and then prints numbers hands the person a
        figure produced from a population the tool has just disowned.
        """
        import contextlib, io
        def refuse():
            raise ValueError("a source is unclassified")
        out = io.StringIO()
        with unittest.mock.patch.object(observation, "readable_pairs", refuse):
            with contextlib.redirect_stdout(out):
                observation.main([])
        self.assertNotIn("ARE THESE N INSTANCES", out.getvalue())


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

        The figure is a census of `SpeakItTests`, not a property of the
        parser, so it moves whenever a test file gains a multi-word literal.
        3702 -> 3739 on 2026-09-11: `StoredRowRemovalTests` added 37 and
        removed none. 3739 -> 3745 the same day, when review of that change
        added three more tests to the class. 3745 -> 3755 on 2026-09-15: six
        `corpusCase` rows and four `note:` arguments for the numbered
        enumerator in front of a fact. 3755 -> 3758 the same day, when the
        review of that change found the copula guard taking a boundary away:
        two more rows and one more `note:`. 3758 -> 3788 the same day: the
        Foundation Models interpretation prototype landed two test classes
        whose fixtures are hand-written captures. 3788 -> 3797 in review of
        that change, which made the two role fields load-bearing and added
        four cases for them. 3797 -> 3904 when the cancellation-scope fixture
        added its focused production controls. 3904 -> 3912 on 2026-09-16:
        the two `SpeechRepairTests` cases for "I was thinking", whose inputs
        and expectations are nine multi-word literals of which eight are new
        to this directory. 3912 -> 3916 the same day, when the follow-up to
        that change added two tests running the repair's output straight into
        `ThoughtCompletion.unfinished`. The utterances were already here, so
        the four are three assertion messages and — enumerated rather than
        assumed — one quoted phrase inside a doc comment, `"keeps the words"`.
        Worth knowing before predicting one of these deltas: a phrase put in
        quotation marks while explaining a test counts exactly like a fixture.
        3916 -> 3929 the same day again, adding the abstain-when-blind helper
        and its two guard tests. Thirteen, enumerated: six assertion messages,
        one probe sentence, two phrases quoted inside a doc comment (`"not
        measured here"`, `"measured and correct"` — the hazard the paragraph
        above had just finished naming), and **four** fragments of a single
        skip message, because a message built by concatenating string literals
        across lines counts once per fragment and not once per message.
        Counting messages would have predicted ten.
        3929 -> 3928 an hour later, the first *fall* in this log: review found
        that the chain test put an assertion ahead of its `XCTSkip`, which
        depends on XCTest recording a failure that precedes a skip, and nothing
        here establishes that it does. Moving the skip to the first statement
        dropped the assertion message "the repair must leave the bare marker",
        whose claim `testThroatClearingStillComesOff` already makes without
        skipping. One literal, enumerated rather than assumed, and the sign is
        the interesting part: deleting an assertion moves this count exactly
        like adding a fixture does. 3928 -> 3928 later the same day, and a
        zero is worth a line here for the same reason a fall was: the follow-up
        gave three `ThoughtCompletionTests` tests an abstention and added two
        guards over the helper's call sites, and moved this count by nothing,
        because a `throws` and a call add no literal and every phrase in the
        new comments is in backticks rather than quotation marks. Deliberate,
        after the entry two paragraphs above learned that a quoted phrase in a
        doc comment counts exactly like a fixture. **An unchanged count that
        nobody recomputed is indistinguishable from one nobody checked**, which
        is why it is written down rather than left out. 3928 -> 3928 again on
        that follow-up's review, which narrowed a stated reason in a doc
        comment and closed a blind spot in one of those guards: prose and a
        Python guard, no Swift literal either way, and the backtick rule held
        for the rewritten paragraph. 3928 -> 4047 on 2026-09-17, where this log
        stops describing a single line: the Candidate47 reconciliation
        branch carries Candidate47's fixtures and main's together.
        Candidate47 added 36 `ActionabilityTests` methods and one
        `ThoughtCompletionTests` method without recounting here, so its
        recorded 3904 measures 4023 on its own tree; the reconciliation
        then carries main's `SpeechRepairTests` and
        `ThoughtCompletionTests` fixtures on top, which is the rest of
        the way to 4047. Neither recorded figure describes this tree, so
        it is recomputed rather than taken from a side, and main's
        entries above are kept because they are the only record of how
        main reached 3928. 4047 -> 4068 on 2026-09-21, from the morning
        brief naming one task: fourteen tests in `MorningBriefTests`,
        twenty-one literals, enumerated rather than assumed. Eight are
        fixtures or expected output, and they divide the way this log
        keeps warning they will: four task names (`"Call the dentist —
        9 AM"`, `"Drop off the parcel"`, `"Email the landlord — overdue
        since Friday"`, `"Pick up the keys"`) and four renderings of how
        long something has been waiting (`"overdue since yesterday"`,
        `"overdue since Friday"`, `"overdue since Wednesday"`, `"overdue
        by 19 days"`). Eleven are assertion messages. **The last two are
        the hazard three paragraphs above, hit again by somebody who had
        just read it**: a doc comment added in review quotes the
        principle the ranking follows, and `"what will not reach them
        otherwise"` and `"what is latest"` count exactly like fixtures.
        They are left in quotation marks rather than rewritten into
        backticks, because the count is a tripwire and not a target, and
        a log entry is the cheaper honesty. Several fixtures these tests
        use add nothing, for two different reasons that the first draft
        of this entry ran together. Three were already in this
        directory: `"Book the flights"` in `DurabilityTests`,
        `"Call the dentist"` in seven files including
        `TemporalFullPathTests`, and `"Email the landlord"` in three
        including `InterpretationPolicyTests` — note that the literals
        this branch adds are the *composed* forms, `"Call the dentist —
        9 AM"` and `"Email the landlord — overdue since Friday"`, which
        are new strings even though their task names are not. The
        fourth, `"5 PM"`, is not a near-miss at all: it is four
        characters, and `swift_literals` counts nothing under twelve, so
        it was never in this population and its presence elsewhere is
        beside the point. Predicting twenty-one from the test count
        would have missed all three directions at once. The development-set overlap stayed at 114,
        so — unlike #79 — not one of the twenty-one is verbatim a devset
        row; that was checked by regenerating `LANGUAGE_BASELINE.md`,
        not assumed from the wording. 4068 -> 4076 on 2026-09-23, from
        launch recovery leaving a capture the person has touched alone:
        three `DurabilityTests` tests, eight literals, enumerated rather
        than assumed. One is a fixture, the edited title `Call the plumber
        about the kitchen leak`, and seven are assertion messages
        interpolating the processing status, each counted once: `left open,
        it is re-read at every launch`, `recovery must neither delete the
        edited row nor add rows beside it`, `recovery must still split the
        capture it never finished`, `recovery reset the review`, `the
        hand-picked date was reverted`, `the placeholder was left
        unorganized`, and `the typed title was reverted`. The two-thought
        sentence and `The original words are never rewritten` were already
        in `DurabilityTests` and add nothing. Review of the same change
        moved it 4076 -> 4090 that day, with three more tests (a spoken
        move and a spoken cancel held rather than acted on an unorganized
        placeholder, and each mark keeping recovery off alone) and
        fourteen more literals. Three are fixtures, `Move the plumber to
        Friday` and the table names `time set by hand` and `place set by
        hand`. One is the hazard above once more, `book the car service`
        quoted in two doc comments and counted once. Ten are assertion
        messages: `A move whose only match is an unorganized placeholder
        must be held`, the same with `A cancel`, `recovery must still
        split the capture the move never reached`, the same with `the
        cancel`, `the held move stays as a review row`, `the held move
        was lost at relaunch`, `the placeholder was marked as the
        person's`, `the placeholder was moved`, and two interpolating the
        mark's name, `recovery re-read a capture the person had marked`
        and `the row must carry this mark alone`. `Cancel the plumber
        reminder` was already in `CaptureOperationTests` and adds
        nothing. 4090 -> 4099 on 2026-09-23, from broad operations leaving
        out the rows of an unorganized capture: three `DurabilityTests`
        tests, nine literals, enumerated rather than assumed, and all nine
        are assertion messages: `A broad cancel must be held for
        confirmation`, `an unorganized capture was named for deletion`,
        `everything the confirmed request named is cancelled`, `recovery
        must still organize the capture the confirmation skipped`, `the
        finished capture was not cancelled`, `the placeholder was marked
        done`, `the prompt would count a capture confirming leaves alone`,
        `the review row is resolved`, and `the unfinished capture and its
        words were deleted`. `Cancel every reminder`, the two-thought
        sentence and `recovery must still split the capture the cancel
        never reached` were already here, and `Buy milk`, quoted in a doc
        comment, is under twelve characters and never counted.
        This branch had, on its own parent, 4068 -> 4087 on 2026-09-23, from
        DEL-25 (a confirmed "cancel all my reminders" reaching Memory):
        three tests in `CaptureOperationTests`, nineteen literals,
        enumerated rather than assumed. Six are fixtures: three spoken
        requests (`"Cancel all my reminders"`, `"Delete all my notes"`,
        `"Mark all my tasks done"`) and three Memory rows (`"The spare key
        is under the blue pot"`, `"A podcast about city parks"`,
        `"Something about the lease"`). The fourth Memory row, `"Sarah
        likes oat milk"`, was already here, and `"Priya's birthday"` too.
        Twelve are assertion messages, two of them interpolated. The last
        is the doc-comment hazard once more, in a `//` comment this time:
        the editor's prompt quoted as `"Cancel N items?"` counts like a
        fixture, and is left quoted. One message, `"A broad cancel must be
        held for confirmation"`, is also in #131's `DurabilityTests`, so
        the two branches together add one fewer than their deltas sum to.
        The two met on 2026-09-23, when #131 was merged into the DEL-25
        branch so that `heldCandidate` could ask the kind question too:
        4099 (#131) -> 4124, recounted on the merged tree rather than
        summed. Twenty-five, enumerated: DEL-25's nineteen less the one
        message both sides carry is eighteen, and the two confirm-time
        tests the merge added bring seven assertion messages, all new:
        `a row edited into a note was deleted`, `confirming an old record
        reached Memory`, `precondition: both were held`, `precondition:
        the edited row is a Memory note`, `the number confirmed is not
        the number acted on` (used twice, counted once), `the prompt
        counts Memory rows from an old record` and `the prompt counts a
        row that is now a note`. Typing #131's three placeholders as
        tasks added a helper and four preconditions and no literal. What the test
        is actually
        guarding — that the two readings of "multi-word" still agree exactly
        and in both directions —
        is the assertion above, and it is unaffected.
        """
        root = pathlib.Path(self.rm.__file__).resolve().parents[2]
        found = set()
        for swift in sorted((root / "SpeakItTests").glob("*.swift")):
            text = swift.read_text(encoding="utf-8", errors="replace")
            found.update(self.rm.swift_literals(text))
        space = {l for l in found if " " in l.strip()}
        split = {l for l in found if len(l.split()) > 1}
        self.assertEqual(space, split)
        self.assertEqual(len(space), 4124)

    def test_the_coverage_statement_carries_no_hand_typed_figure(self):
        """It says what is read, not how much. A count in there is one
        nothing recomputes, which is how the last three got in."""
        self.assertNotRegex(re.sub(r"#\d+", "", observation.READ_WHAT), r"\d")

    def test_the_coverage_statement_names_the_owner(self):
        self.assertIn("readable_material", observation.READ_WHAT)
        self.assertIn("sealed", observation.READ_WHAT)


class TheDiagnosticIsNotAllowedToAbstain(unittest.TestCase):
    """`LexicalTagging.skipIfBlind` lets a tagger-dependent assertion report
    "not measured here" instead of a verdict it cannot support. Applied to the
    diagnostic itself it would be self-concealing: the one test whose failure
    tells anybody the lexical model is missing would go quiet, and the suite
    would skip its way to green. That is the same defect as a step that runs no
    tests, one level up, and it is invisible from a summary table.

    Checked here rather than in Swift because it is a claim about which source
    calls what, and this is the suite that already reads `SpeakItTests`.
    """

    def source(self):
        root = pathlib.Path(__file__).resolve().parents[2]
        return (root / "SpeakItTests" / "RenderingInvarianceTests.swift").read_text(
            encoding="utf-8", errors="replace")

    def test_the_environment_probe_does_not_call_the_skip_helper(self):
        text = self.source()
        start = text.index("final class NaturalLanguageEnvironmentTests")
        body = text[start:start + text[start:].index("\n}\n") + 2]
        self.assertNotIn(
            "skipIfBlind", body,
            "NaturalLanguageEnvironmentTests must still fail loudly on a blind "
            "image; abstaining there hides the only signal that says why "
            "everything else is abstaining")

    def test_the_helper_it_must_not_call_still_exists_under_that_name(self):
        """Without this the assertion above passes by spelling. Rename the
        helper and `skipIfBlind` appears nowhere, so "the probe does not call
        it" becomes true of every file in the repository."""
        self.assertIn("func skipIfBlind", self.source())


class TheAbstentionRunsBeforeAnythingItCouldSwallow(unittest.TestCase):
    """`LexicalTagging.skipIfBlind` must be the first statement of every test
    that calls it.

    #99 shipped it that way on review's objection, and the reason is that the
    alternative rests on something nobody here has established: whether XCTest
    records a failure that happened *before* a test throws `XCTSkip`. If it does
    not, an assertion placed ahead of the skip is reported as a skip on a blind
    image, and a genuine regression in the half that could still be measured
    disappears into the Skipped column. That is the failure the helper exists to
    prevent, wearing the helper's own clothes.

    The ordering was argued at length in a docstring and checked by nothing:
    moving the skip back below a statement left `test_score` and this suite
    green. A decision that only prose defends is one the next person undoes
    without knowing there was a decision.

    Checked here rather than in Swift for the same reason as
    `TheDiagnosticIsNotAllowedToAbstain`: it is a claim about the shape of a
    source file, and this is the suite that already reads `SpeakItTests` and
    runs on Linux on every pull request.
    """

    HELPER = "LexicalTagging.skipIfBlind("

    #: What may precede the call on its own line. `try` is the call itself;
    #: anything else there is a statement that ran first.
    PREFIX_OK = ("", "try")

    def call_sites(self):
        """Every (file, test, lines before the call, text before it on its line).

        The fourth element exists because the third cannot cover it. Slicing
        `lines[back + 1:index]` stops at the call's own line, so a statement
        sharing that line was invisible:

            XCTAssertNil(ThoughtCompletion.unfinished(in: `Milk`)); try skip()

        Injected exactly that and this class reported OK. Odd Swift style, so
        it was never likely — but a guard with a blind spot on the one line it
        is most about is the shape of defect this suite exists to catch, and it
        was found by review reading the slice rather than by the guard.
        """
        root = pathlib.Path(__file__).resolve().parents[2]
        signature = re.compile(r"^\s*func\s+(test[A-Za-z0-9_]*)\s*\(")
        sites = []
        for swift in sorted((root / "SpeakItTests").glob("*.swift")):
            lines = swift.read_text(encoding="utf-8", errors="replace").splitlines()
            for index, line in enumerate(lines):
                if self.HELPER not in line:
                    continue
                head = line[:line.index(self.HELPER)].strip()
                #: A doc comment that *names* the helper is not a call site.
                #: Without this, `/// Abstains via LexicalTagging.skipIfBlind()`
                #: reddens the suite -- and names the wrong test, because the
                #: comment sits above its own `func` so the walk back finds the
                #: previous one. Reproduced against the guard as first shipped,
                #: so it is not new here, and found by review rather than by the
                #: guard. Documenting the helper should not be what breaks it.
                if head.startswith("//"):
                    continue
                for back in range(index - 1, -1, -1):
                    found = signature.match(lines[back])
                    if found:
                        sites.append((swift.name, found.group(1),
                                      lines[back + 1:index], head))
                        break
                else:
                    self.fail(f"{swift.name}:{index + 1} calls the helper "
                              "outside any test function")
        return sites

    def test_nothing_runs_before_the_abstention(self):
        for name, test, between, head in self.call_sites():
            self.assertIn(
                head, self.PREFIX_OK,
                f"{name}: {test} runs `{head}` on the same line, before it "
                "abstains. Same defect as a statement on the line above, and "
                "the line-range check cannot see this one.")
            for line in between:
                stripped = line.strip()
                self.assertTrue(
                    not stripped or stripped.startswith("//"),
                    f"{name}: {test} runs `{stripped}` before it abstains. "
                    "An assertion ahead of the skip is only reported if XCTest "
                    "keeps a failure that precedes a thrown XCTSkip, which is "
                    "not established here; put the claim in a test that never "
                    "abstains instead.")

    def test_there_is_something_to_check(self):
        """Without this the assertion above passes by having nothing to say.
        Rename the helper, or drop its last caller, and `every call site is
        first` becomes true of the empty set -- the same shape as a test
        selection that matches nothing, and as the guard that cannot fire."""
        self.assertGreaterEqual(len(self.call_sites()), 1)


if __name__ == "__main__":
    unittest.main()
