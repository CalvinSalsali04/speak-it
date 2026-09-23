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
    MOTIVATING = {"plus": (48, 8, 12, 65), "wait": (60, 18, 32, 32)}

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
        not assumed from the wording. 4068 -> 4070 on 2026-09-23, from a
        named-weekday series returning to its stated clock after a
        spring-forward: one assertion message (`"2:30 does not exist that
        night"`) and one quotation in the new test's doc comment (`"every
        Sunday at 2:30 AM"`), which counts like a fixture, the hazard
        above again. Nothing was removed. 4068 -> 4076 on 2026-09-23, from
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
        comment, is under twelve characters and never counted. 4068 -> 4069 on 2026-09-23, from
        the AlarmKit orphan sweep: four `DurabilityTests` methods and one
        literal, enumerated rather than assumed, the assertion message
        `"Relaunch must cancel an alarm whose row is gone"`. The capture
        they share, `"Set an alarm for 7 AM to take my pills"`, was
        already in `CaptureOperationTests` and adds nothing, and every
        phrase their doc comments quote is in backticks. 4068 -> 4073 on 2026-09-23, from
        cancelling an item's alarm synchronously instead of only in the
        queued scheduler pass: seven literals in, two out, net five, and
        all nine are assertion messages, enumerated rather than assumed.
        The two that went out were reworded rather than deleted, which
        moves this count exactly like adding and deleting does: `"The
        cancelled reminder's pending notification must be removed"` and
        `"A cancelled alarm must be cancelled in AlarmKit, not just
        deleted from the store"`. The seven that came in are their
        rewordings, `"The cancelled reminder's pending notification must
        be removed before any queued pass runs"` and `"A cancelled alarm
        must be cancelled in AlarmKit before any queued pass runs"`; the
        two post-drain checks in `CaptureOperationTests`, `"After the
        queued pass the cancelled reminder must still be gone"` and
        `"After the queued pass the cancelled alarm must still be
        gone"`; the two neighbour checks, `"The queued pass must not
        reach past the cancelled reminder"` and `"The queued pass must
        not cancel an alarm it was not asked about"`; and `"Relaunch must
        cancel an alarm that no row asks for"` in `DurabilityTests`. The
        new relaunch test's fixture, `"Set an alarm for 7 AM to take my
        pills"`, adds nothing because `CaptureOperationTests` already had
        it, and every phrase in the new doc comments is in backticks. The
        development-set overlap stayed at 114, checked by regenerating
        `LANGUAGE_BASELINE.md`. 4073 -> 4074 the same day, from the
        sweep reading an explicit every-row set: one assertion message in
        `DurabilityTests`, `"A pass that does not name every row must not
        cancel an alarm it does not know"`, and none removed. 4074 ->
        4072 the same day, from dropping this change's own alarm sweep, which
        duplicated #127's: two `DurabilityTests` messages go with their
        tests, that one and `"Relaunch must cancel an alarm that no row asks
        for"`, and none is added. 4068 -> 4073 on 2026-09-23, from
        the row's bell and the scheduler reading one delivery function:
        three tests in `ItemPresentationTests`, five literals, all
        assertion messages — `"precondition: the wording asks for no
        alert"`, `"a future reminder date is scheduled whatever the
        wording says"`, `"the row must not deny an alert iOS is
        holding"`, `"precondition: the alarm was given a moment"` and
        `"precondition: the day was heard"`. Both fixtures add nothing,
        `"Call the accountant tomorrow"` being in `DurabilityTests` and
        `"Set an alarm for 6:45 tomorrow"` in `SemanticCorpusDataC`, and
        a phrase the doc comment first quoted was put in backticks
        instead. 4073 -> 4074 the same day, from the review of that change:
        three more tests in `ItemPresentationTests` (the receipt counting a
        hand-set reminder once, its kind label matching the scheduler's
        delivery, and a past reminder date armed with no request) add one
        fixture, `"Set an alarm for 6:45 and call the accountant
        tomorrow"`; `"Call the accountant tomorrow"` and `"precondition:
        the wording asks for no alert"` are reused, and their doc comments
        quote in backticks. 4068 -> 4077 on 2026-09-23, from
        snoozing a recurring reminder no longer retiming its series: three
        `TemporalFullPathTests` tests, nine literals, enumerated rather than
        assumed, and all nine are assertion messages --
        `"Precondition: the series alerts at its due time"` (used twice,
        counted once), `"Precondition: this does not recur"`, `"a repeating
        trigger built from the snoozed minute retimes the series on the
        phone"`, `"a snooze belongs to the occurrence it was pressed on"`,
        `"a snooze moves the alert, not the occurrence"`, `"only a series
        has an alert of its own to protect"`, `"the occurrence after a
        snoozed one fires at the series' own time"`, `"the occurrence after
        the moved one is back on the series' clock"` and `"tomorrow means
        tomorrow at the series' time, not at the snoozed minute"`. The three
        fixtures add nothing, because each was already in this directory:
        `"Remind me every Monday at 9 am to take the bins out"` and `"Remind
        me in 20 minutes to switch the laundry"` in
        `SwiftDataThoughtRepositoryTests`, `"Remind me every day at 8 am to
        take my meds"` in `ReleaseReadinessTests`. Reused on purpose, so
        the change adds no sentence to this population. 4077 -> 4083 the
        same day, when review found that change left a snoozed series with
        nothing armed after the snooze fired, and the fix arms the series'
        own repeating trigger beside the one-shot: one new
        `TemporalFullPathTests` test, one new `SwiftDataThoughtRepositoryTests`
        test and two added assertions, six literals, enumerated rather than
        assumed, all of them assertion or failure messages -- `"a snoozed
        occurrence needs its one-shot and its series"`, `"an occurrence back
        on its series' alert needs no second trigger"`, `"the one-shot fires
        at the snooze"`, `"the series must be armed as a repeating
        trigger"`, `"the series' first match must be the next occurrence,
        not this one again"` and `"the snoozed fire must be a one-shot"`.
        The one fixture is reused again, and the identifier test's doc
        comment keeps its names in backticks, so neither adds anything.
        4083 -> 4088 the same day again, from that change's grading: a
        series whose alert had fired was disarmed by any scheduling pass
        that included it, a snooze record could fail without a word, and a
        failed add left a one-shot armed alone. Four new tests, five
        literals, enumerated rather than assumed, all assertion messages --
        `"Precondition: the alert has fired"`, `"Precondition: the snoozed
        one-shot has fired"`, `"Today still counts only alerts ahead"`, `"a
        snooze with nowhere to record must make somewhere, not skip the
        record"` and `"after the snooze fires, the series trigger is all
        that is left to arm"`. One more message, `"the series must be armed
        as a repeating trigger"`, is used again and was already here, and
        the rollback test's identifiers (`"one-shot"`, `"series"`) are under
        twelve characters, so they were never in this population.
        4088 -> 4088 the same day, and a swap is worth a line for the same
        reason a zero was: a hosted Mac in UTC failed the scheduler
        assertions these tests made under the Toronto pin, so they moved
        into two machine-zone helpers. One message left, `"a repeating
        trigger built from the snoozed minute retimes the series on the
        phone"`, and one arrived, `"the repeating match must be the series'
        own clock, not the snooze's"`. `"the series' first match must be
        the next occurrence, not this one again"` moved into a helper and
        still counts once. One out and one in, enumerated rather than
        assumed: an unchanged count here is a different population.
        4088 -> 4093 on 2026-09-23, from the second round of that
        change's grading. Two tests arrived. One snoozes a recurring place
        reminder that has no intent blob and checks it stays a place
        reminder: `"Precondition: a place reminder"`, `"Precondition: no
        intent blob"`, `"the backfill a snooze makes must not turn a place
        reminder into a clock reminder"`. The other reads what a scheduling
        pass selects to arm: `"Remind me tomorrow at 9 am to call the
        dentist"`, `"a series whose alert has fired must still be armed by
        the pass"`. They also reuse the weekly bins sentence and
        `"Precondition: the alert has fired"`, which were already here.
        4093 -> 4100 on 2026-09-23, from the third round of that
        change's grading, eight in and one out. The launch backfill test
        brought `"Remind me tomorrow at 10 am to water the plants"`, `"not
        an intent"`, `"Precondition: data that will not decode"`, `"the
        backfill must not re-derive the trigger"`, `"a row with no intent
        data is still backfilled"` and `"intent data that will not decode
        must be kept, not replaced"`. The pass read from the notification
        center brought `"the pass must leave the series armed, not only
        cancel it"`. One message was false once Today stopped reading
        `init?(item:)`: `"Today still counts only alerts ahead"` went, and
        `"an alert that has fired is no longer still ahead"` came.
        4069 -> 4076 on
        2026-09-23, from repeating AlarmKit alarms: six
        `TemporalFullPathTests` methods and seven literals, enumerated
        rather than assumed. Five are the names an inexpressible-rule test
        gives its cases (`"first Monday every month"`, `"every other
        Tuesday"`, `"every 2 days"`, `"every 3 hours"`, `"a day after
        completion"`) and two are assertion messages. Two more case names,
        `"every month"` and `"every year"`, add nothing because they are
        under twelve characters. The first draft quoted phrases in its doc
        comments and measured 4078, one of the two extras being
        `", every Tuesday for "`: a quotation opened on one line and
        closed on the next pairs with the wrong mark and counts the prose
        between two quotes as a literal. Those comments use backticks now.
        4076 -> 4078 on 2026-09-23, from that change's review: one
        `TemporalFullPathTests` method that builds a real request, because
        the six above never reached the overload production calls. Three
        literals in, one out, enumerated rather than assumed. In: the
        capture `"Set an alarm every day at 6:30 AM"`, new to this
        directory, and two assertion messages, `"production asks
        alarmSchedule only for an alarm"` and `"a relative alarm registered
        too late rings at the next match, not today"`. Out: `"an occurrence
        under a minute away could pass while AlarmKit registers it"`, the
        message the second one replaced because the reason it gave applied
        to the one-shot branch just as much. A reworded message is a fall
        and a rise, not a zero, and it only nets to zero when both sides
        clear twelve characters.
        4068 -> 4071 on 2026-09-23, from the
        widget snapshot holding for review what Today holds: one test in
        `LocationReminderTests`, three literals, enumerated rather than
        assumed. Two are assertion messages (`"a row in review is not
        counted as due"`, `"the ordinary row is next, and the held one is
        never offered"`) and one is the App Shortcut's phrase quoted in the
        test's doc comment, `"Complete my next item"`, the hazard above
        once more. Both capture fixtures add nothing: `"Remind me to take
        out the garbage when I get home"` is already in this file and
        `"I need to implement calendar integration tomorrow"` in
        `SwiftDataThoughtRepositoryTests`. 4071 -> 4075 on 2026-09-23, from
        the grade of that change: the widget's queued tap on a held row is
        dropped, one test with four literals, three assertion messages
        (`"a tap from a stale widget does not complete a held row"`, `"an
        ordinary row's tap is still applied"`, `"the dropped tap is not
        retried forever"`) and one skip message (`"the shared app group
        container is unavailable on this simulator"`). 4075 -> 4074 on
        2026-09-23, from the second grade: the test queues its taps in a
        folder of its own through the queue's new directory overloads, so it
        can no longer skip, and that skip message is gone. 4068 -> 4083 on 2026-09-23, from
        the runtime linguistic-health signal: sixteen added and one
        removed, enumerated rather than assumed, and the removal is the
        part worth reading first. The probe sentence `pay the rent on
        friday` left this directory because `LexicalTagging.probe` now
        reads `LinguisticHealth.probe` from the app instead of spelling
        it out, so a literal can leave the census by moving into
        production code and nothing else changing. Of the sixteen, seven
        are fixtures or expected output: two captures new here (`Buy milk
        and text Dana tomorrow at 5, and Sarah hates sushi`, `Remind me
        at 5 pm to call Mom`), the two quotes and two analysis texts of
        the hand-built inherited-series rows (`submit the report`,
        `Catherine needs a copy`, `Remind me every Friday to submit the
        report`, `Remind me every Friday to Catherine needs a copy`), and
        the new review copy, asserted verbatim. Nine are assertion
        messages, one of them an interpolated template. Two fixtures add
        nothing because they were already here -- the U1 sentence itself
        is a `SemanticCorpusDataD` row and `I had better luck last time`
        was already a fixture -- and one reused assertion message adds
        nothing for the same reason. 4083 -> 4110 on 2026-09-23, from the
        review of that signal (operations held, the timing test asking
        the resolver, the reading cache emptied on the first usable
        verdict): twenty-seven added and none removed, enumerated rather
        than assumed. Twelve are fixtures: two operation captures and
        their stored target (`Cancel the plumber`, `Call the plumber`),
        a hand-built scoped fragment (`tomorrow I need to, never mind`),
        a hand-built reschedule and its transcript (`move the dentist to
        Friday`, `Buy milk and move the dentist to Friday`), and seven
        timing phrases the resolver reads (`rent is due on the first`,
        `send it by eod`, `finish the deck by the end of the work day`,
        `call mom first thing`, `check the oven in forty five minutes`,
        `check the oven in 45 mins`, `file the forms by the last day of
        the year`). Fifteen are assertion messages, two of them
        interpolated templates. Four fixtures add nothing because they
        were already here -- `On the 15th pay the rent` is a corpus and
        `ActionabilityTests` row, `Actually never mind` is in
        `CaptureOperationTests`, `Buy milk and tomorrow I need to, never
        mind` is in `AbandonmentTests`, and `Catherine needs a copy`
        came in with the entry above -- and a precondition message used
        twice counts once. 4110 -> 4111 on 2026-09-23, from the second
        review: `On the 15th pay the rent` moved to its own test, which
        abstains on a blind tagger because only the tagger reads that
        date, and the timing list now holds `On the 15th, pay the rent`,
        which the day-number regex reads. That is the one addition; the
        bare phrase and the new test's messages were already here, and
        nothing was removed. 4068 -> 4115 on 2026-09-22, where the
        capture-experience branch merges in. That branch was cut before the
        morning brief landed, so its own two moves were measured against 4047
        and are recorded here as they were read rather than rebased onto the
        entry above: 4047 -> 4073 for `CaptureFeedbackTests`, the suite that
        arrived with the four capture fixes, whose commit left both this
        figure and the population block in `LANGUAGE_BASELINE.md` stale and
        the `language` job red before anything was added to it; then
        4073 -> 4094 for the stale-callback lifecycle test and the
        delayed-save coverage in the same file. The two branches touch
        different files, so the merged tree carries both sets and nothing
        cancels. Every one of the branch's literals is a fixture or an
        assertion message in a suite about screens and recognizer callbacks,
        so no parser behaviour is behind either number, and the doc comments
        written for them prefer backticks to quotation marks for the reason
        the entry above hit the hard way. 4115 -> 4119 on 2026-09-23, when
        the saving flag's lowering moved into `CaptureSaveInFlight` and one
        test walks every way out of persistence. Four, enumerated: three
        assertion messages and the ending `"threw a cancellation"` (named `"was cancelled"` in the first draft), which counts
        because it has a space in it; `"returned"` and `"threw"` do not.
        The rewritten test double added none. 4119 -> 4121 later on
        2026-09-23, from two `CaptureFeedbackTests` tests proving a stale
        speech `start` releases only the backend it was handed (LIF-7).
        Two, enumerated: both are assertion messages. The tests deliver
        no words, and every phrase in their doc comments is in backticks.
        4119 -> 4128 on 2026-09-23,
        when a save came to belong to the capture screen that started it
        (`CapturePresentation`) and Save & Close stopped racing
        finalization. Nine, enumerated: eight assertion messages, one of them
        interpolated, and the fixture `"buy milk and eggs today"`, the final
        wording a finalization delivers; its partial, `"buy milk and eggs"`,
        was already counted elsewhere and adds nothing. Then 4128 -> 4132
        on the same branch, when review found the late save's charge and
        retry cleanup asserted by nothing and they moved into
        `CaptureSaveSettlement`. Four, enumerated, all assertion messages:
        `"a stored thought went uncharged because its screen had gone"`,
        `"the stored thought's draft was left to be recovered again"`,
        `"the replaced attempt stayed in Needs review beside its retry"` and
        `"a clarification retry spent a second free capture"`. The event
        names the order test logs are single words under twelve characters
        and add none. Then 4132 -> 4135, when audio recovery that finishes
        after its screen has gone came to leave its words on the draft
        (`CaptureRecoveryHandoff`) rather than saving through that screen.
        Three, enumerated, all failure messages of closures that must not
        run: `"recovered words were sent to typing"`,
        `"a failed recovery started a save"` and
        `"a discarded recording was saved"`. The fixture
        `"buy milk and eggs today"` was already counted earlier in this entry.
        The development-set overlap stayed at 114, checked by
        regenerating `LANGUAGE_BASELINE.md`. 4068 -> 4075 on 2026-09-23, from
        audio recovery no longer calling a pass that stopped partway the
        whole recording: six tests across `CaptureRecoveryEscapeTests` and
        `DurabilityTests`, seven literals, enumerated by diffing
        `swift_literals` before and after rather than assumed. Five are
        fixtures (`" buy milk and call "`, padded on purpose to exercise the
        trim, `"buy milk and call"`, `"buy milk and call the"`, `"buy milk
        and call mom"`, `"Renew the parking permit and"`) and two are
        assertion messages (`"Another attempt has to stay on offer"` and
        `"Reported as the whole recording: \\(text)"`, which counts with its
        interpolation). `"buy milk"` and `"   "` add nothing: both are under
        the twelve-character minimum. 4075 -> 4076 the same day, from the
        capture screen offering the words a failed pass kept: two more tests
        in `CaptureRecoveryEscapeTests` add one fixture, `"Buy milk, and call
        the plumber"`, capitalised and punctuated on purpose to exercise the
        comparison; every other literal they use was already counted.
        4076 -> 4077 the same day, from `"buy milkshake"`, the fixture
        pinning that the kept words must carry on by whole words.
        The doc comments use backticks, and the development-set overlap
        stayed at 114. 4135 -> 4153 on 2026-09-23,
        when the relaunch-handoff branch (#128) was stacked on this one: it
        was measured on its own as 4068 -> 4086, from
        recording the handoff of a draft to its CaptureSession so a
        relaunch stops replaying words already committed: seven
        test methods in `DurabilityTests.swift` and eighteen literals, enumerated rather
        than assumed. Nine are fixtures: `"Call the landlord about the
        lease"`, `"Renew the passport before March"`, `"Book the car in
        for its service"`, `"Text Jordan the gate code"`, `"Text  Jordan
        the gate code "` (the same words with a doubled space and a
        trailing one, which is the point of that test and a distinct
        string here), `"Text Jordan the new gate code"`, `"Water the
        tomatoes tonight"`, `"Something else entirely"` and `"Ask Dana for
        the invoice number"`. Eight are assertion messages: `"A committed
        practice save must not be replayed"`, `"A committed handoff
        releases its draft"`, `"The seeded recording must be one the audio
        pass would replay"`, `"Uncommitted words must come back"`, `"The
        text pass leaves audio drafts to the audio pass"`, `"The same
        words, differently spaced, are still the handed-off words"`, `"The
        old format must decode"` and `"A pre-handoff draft must still be
        replayed after the update"`. The eighteenth is the doc-comment
        hazard once more: a test explaining how an older draft decodes
        quotes `"not handed off"`, and it counts like a fixture. The
        practice sentence the tutorial test reuses, `"Tomorrow at 9, ask
        Maya about the proposal."`, adds nothing, because three files here
        already carry it. Stacked, the eighteen land on 4135 unchanged,
        because the two branches' test literals share none; that is the
        merged tree measured, not the two figures added. The
        development-set overlap stayed at 114, checked
        by regenerating `LANGUAGE_BASELINE.md` rather than assumed.
        4153 -> 4156 on 2026-09-23, when the Save Thought intent and
        Today's typed recovery came to hand off through
        `CaptureDraftStore.handOff`, and late audio recovery came to
        withdraw a handoff as `update` does: four test methods in
        `DurabilityTests.swift` and three literals, enumerated. One is a
        fixture, `"Pick up the dry cleaning on Thursday"`, the typed words,
        used twice. Two are assertion messages, `"The draft must carry the
        handoff before the commit starts"` and `"The commit's error must
        reach the caller"`. The rest add nothing: the practice sentence,
        `"No speech detected"`, the gate-code fixtures the withdrawal
        test reuses and the reused assertion messages are already
        counted. 4135 -> 4162 on 2026-09-23,
        when "Try saying it again" came to replace the attempt by its
        session id (`deleteCapture(sessionID:)`) rather than by the rows
        the screen was shown. Twenty-seven, enumerated: nineteen assertion
        messages, seven of them preconditions; six fixtures, the attempt and
        retry sentences and the split part `"Ask about the fee"` (its twin
        `"Call the bank"` and the attempt `"Buy milk and call the dentist"`
        were already counted); and two phrases quoted in doc comments, the
        button title `"Review what I understood"` and the tail of the
        failure notice, `"still in Needs review"`. 4162 -> 4182 on
        2026-09-23, when review found the guard that stops a retry deleting
        its own session tested only in its true direction, and the rows
        `deleteCapture` reports read by one no-op assertion. Twenty,
        enumerated: two fixtures, the lowercased echo of the attempt
        `"something about the bank and the fee thing"` and the thought said
        again, `"Call the bank about the overdraft fee"`; and eighteen
        assertion messages, five of them preconditions. The merge of
        `claude/v1-reliability-nyngoe-stale-save` touched no test file and
        added none. 4156 -> 4176 on 2026-09-23, when VoiceOver announcements
        moved behind `VoiceOverAnnouncer` so that nothing Speak It posts is
        spoken into an open microphone: `VoiceOverAnnouncementTests`, ten
        test methods in `CaptureFeedbackTests.swift`, and twenty literals,
        enumerated. Seven are fixtures (`"Can you clarify?"`, `"I understood
        the thought, but not when."`, `"Recovering your words"`,
        `"Remembered. Memory."`, `"Today\\n2 free captures left"`, `"Try
        saying it a different way, or include the missing detail."` and
        `"Still listening"`) and three are expected output (`"Can you
        clarify? I understood the thought, but not when."`, `"Remembered.
        Today. 2 free captures left."` and `"Saving your thought"`). Eight are
        assertion messages, one of them interpolated. The last two are the
        doc-comment hazard once more, hit on purpose this time because the
        quotation is the point: a falsifier quotes the broken reading
        `"Can you clarify?."`, and a test's summary quotes the design it
        rejects, `"post it before the engine starts"`. No parser behaviour is
        behind any of the twenty. 4176 -> 4178 on 2026-09-23, when review
        found the open-microphone count with no backstop and
        `SpeechTranscriber` came to give its claim back in `deinit`: one test
        method and two literals, enumerated, both assertion messages:
        `"a released transcriber kept the microphone claimed"` and `"the
        transcriber outlived its last reference, so this proves nothing"`.
        4178 -> 4179 on 2026-09-23, when a VoiceOver finish report came to be
        read as either a string or an attributed string: one test method
        and one literal, an assertion message, `"a report in the attributed
        form did not match what was posted"`. Its fixture, `"Listening"`, is
        one word and adds nothing. 4179 -> 4181 on 2026-09-23, when the
        lost-finish-report test came to wait for its own task for at most
        five seconds instead of hanging under its falsifier: no new method
        and two literals, enumerated: the expectation's description, `"the
        allowance ran out and the microphone could open"`, and an assertion
        message, `"a lost finish report held the microphone shut"`. The
        description avoids the word `wait` on purpose: a test literal
        carrying it moves the `wait` figures pinned in
        `TheMotivatingFiguresAtTheTopAreRecomputed`.
        4156 -> 4161 on 2026-09-23, when a voice capture that
        reuses a typed draft came to get a protected recording (audit D6):
        four test methods in `DurabilityTests.swift` and five literals,
        enumerated. Three are assertion messages, `"Today and the launch
        audio pass must offer the recording"`, `"The text pass must leave a
        draft with a recording to the audio pass, or one thought is saved
        twice"` and `"An empty transcript beside a recording is still a
        capture to recover"`. Two are button titles quoted in the tests' doc
        comments, `"Speak instead"` and `"Type instead"`, which the
        extractor reads like any other line. The typed fixture `"Pick up the
        dry cleaning"` is already counted, and `"Call Dana"` is under the
        twelve-character floor. 4161 -> 4166 the same day, when words typed
        before speaking came to be kept ahead of the recovered recording:
        three test methods in `DurabilityTests.swift` and five literals,
        enumerated. Three are fixtures, `"about the invoice tomorrow"`, the
        recognizer's stand-in result, `"Call Dana about the"`, the spoken
        checkpoint, and `"Call Dana about the invoice tomorrow"`, the joined
        words. Two are assertion messages, `"The original transcript is what
        was typed and what was said, in that order"` and `"The recognizer's
        failure must reach the caller"`. `"No speech detected"` and `"Email
        Sam"` add nothing: the first is already counted and the second is
        under the floor. 4166 -> 4182 on 2026-09-23, when review of #144
        found Type instead keeping a finished run's words, erased typed
        words coming back with the recording, and Today's save of kept
        typed words untested: three test methods added and one rewritten,
        across `CaptureFeedbackTests.swift` and `DurabilityTests.swift`, and
        sixteen literals, enumerated. Twelve are assertion messages:
        `"this no longer reproduces the idle state that kept its words"`,
        `"a finished run has no Live Activity to end"`, `"the spoken words
        were saved a second time after the editor that already held them"`,
        `"The recording is still a capture to recover after the editor is
        emptied"`, `"Erased words were still set aside for recovery"`,
        `"Recovering the recording brought back the words the person
        erased"`, `"Deleting the recording saved words the person had
        erased"`, `"a recording is intended"`, `"The typed words were left
        to no recovery pass"`, `"The launch must release a kept draft whose
        words reached a committed session"`, `"The text pass never replayed
        the kept draft"` and `"Today's save and the launch fallback stored
        the kept words twice"`. Three are fixtures. One is the spoken
        words, `"about the invoice"`; the other two are the readings
        VoiceOver is given for the voice screen, `"Typed: Call Dana"` and
        `"Typed: Call Dana. about the invoice"`. The sixteenth is the doc-comment hazard again: a
        falsifier quotes the words that used to come back, `"Call Dana about
        the invoice"`. `"buy milk"`, `"and eggs"`, `"and bread"` and
        `"Typed:"` are under the floor, and the button titles the doc
        comments quote were already counted. The development-set overlap
        stayed at 114, checked by regenerating `LANGUAGE_BASELINE.md`.
        4182 -> 4184 the same day, when the typing fallback after a voice
        failure came to call `stopForTyping` as "Type instead" does: a
        `.failed` half added to `testTypeInsteadForgetsTheSpokenWordsInEveryState`,
        and two literals, both assertion messages, `"this no longer
        reproduces the failed state the typing fallback reads"` and `"a
        failed run has no Live Activity left to end"`. The error domain is
        one word and adds nothing. 4184 stays 4184 the same day, when that
        test's last assertion was found to be entailed by the one above it
        (`joined` with an empty second argument returns the first) and was
        removed: one assertion message out, `"the spoken words were saved a
        second time after the editor that already held them"`, and one in,
        `"the transcriber kept words the editor already holds, for the next
        save to add again"`, now on the empty-transcript assertion that can
        fail. `"buy milk"`, which went with it, was under the floor.
        4074 -> 4082 on 2026-09-23, from the
        test that a date added in the editor holds a place reminder rather
        than leaving it shown as armed: one `LocationReminderTests` method,
        eight literals, enumerated rather than assumed, and all eight are
        assertion messages (`"precondition: a place reminder with Home set
        is armed"`, `"the predicate the reconciler excludes on"`, `"a due
        date alone schedules no alert"`, `"a crossing is refused while the
        date is set"`, `"the place is held, not deleted"`, `"what the row
        claims must be what iOS is holding"`, `"no pin for a place nothing
        watches"`, `"the held place delivers once the date is gone"`). Its
        one fixture, `"Remind me to take the bins out when I get home"`,
        was already in this file and adds nothing, and its doc comment puts
        every phrase in backticks. It was
        written as 4068 -> 4076 on its own branch, before it was stacked
        on the delivery change above; the two sets of additions do not
        overlap, so the merged tree was measured at 4082 rather than
        either side's figure being kept. 4082 -> 4088 on 2026-09-23, from
        that change's review: one more `LocationReminderTests` method, the
        sibling that turns on `Remind me` rather than `Has a due date`, so
        the held item carries a `reminderDate` the clock scheduler still
        arms. Six literals, all assertion or failure messages
        (`"precondition: the wording names no alert of its own"`, `"a held
        item's reminder date is still scheduled"`, `"the row must show the
        reminder iOS is holding for a held place"`, `"the row's time is the
        time that fires"`, `"the row's bell is the alert that fires"`, and
        the `XCTFail` text `"a held item with a reminder is shown by its
        time, got \\(state)"`, which counts with its interpolation
        unexpanded). Its fixture is the same bins sentence as the test
        before it and adds nothing, and its doc comment quotes in
        backticks. 4088 -> 4104 on 2026-09-23, from DEL-7, a place reminder
        past the region budget or refused by iOS shown as armed: three
        `LocationReminderTests` methods and two helpers, sixteen literals,
        enumerated by diffing the set rather than assumed. Five are
        fixtures, one per mutation that frees or claims a slot (`"Remind me
        to feed the cat every time I get home"`, and the same frame around
        `water the plants`, `charge my phone`, `check the mail` and `lock
        the bike`); one is expected output, the receipt `"Needs review · Too
        many place reminders"`; one is the helper's request title `"filler
        \\(index)"`, which counts with its interpolation unexpanded. The
        other nine are assertion messages, two of them interpolated
        (`"precondition for \\(step): a place reminder"` and `"\\(step) must
        re-plan the region budget at once, not at the next foreground"`),
        each counted once however many steps run it. That second message
        first read `not wait for a foreground`, and a new row for `wait`
        moved the pinned motivating figures above, so it was reworded rather
        than the figures re-pinned: they argue from the corpus as it was,
        and an assertion message is not evidence about `wait`. The badge-in
        and garbage sentences were already in this file and add nothing, and
        every phrase the doc comments quote is in backticks. 4104 -> 4113 the
        same day, from that change's review: three more
        `LocationReminderTests` methods (a split that makes a place reminder,
        a firing one-shot handing its slot on, and a live place whose
        trigger-kind column is nil still being planned), nine literals, all
        assertion messages, enumerated by diffing the set against the
        committed head. Their fixtures add nothing: `"Call the dentist"` is
        in eight other files already, and the bins, garbage and badge-in sentences
        were in this one. 4074 -> 4107 on 2026-09-23 again, from rows the
        system holds for review arming nothing: ten tests across
        `ItemPresentationTests`, `TemporalFullPathTests`,
        `LocationReminderTests` and `SwiftDataThoughtRepositoryTests`,
        thirty-three literals, enumerated by diffing this census against
        `HEAD` rather than counted from the tests. Six are fixtures or
        expected output: a transcript, `"Remind me every weekday at 8 except
        holidays"`; two hand-built titles, `"Take the bins out"` and
        `"Weekday check-in"`; and three renderings of the withheld trigger,
        `"Reminder not set · "`, `"Reminder not set · Next time you arrive
        at Home"` and the interpolated `"Reminder not set · \\(timing)"`,
        which counts as its source text. Twenty-seven are assertion
        messages, and five of those appear twice and count once. The other
        transcripts add nothing, because each is already in this directory:
        the vague-time and series-exception rows in `SemanticCorpusDataE`
        and `SemanticCorpusDataD`, `"Remind me to call mom tomorrow at 5pm"`
        in `ItemPresentationTests`, and both Home transcripts in
        `LocationReminderTests`. 4107 -> 4117 the same day, from the review
        of that change: three more tests, one each in
        `SwiftDataThoughtRepositoryTests` (a hand-set place not releasing a
        guessed time), `MorningBriefTests` (a held row keeping the brief's
        lead) and `DurabilityTests` (a whole-store pass cancelling a held
        row's alarm), add ten literals, all assertion messages. Every
        fixture they use was already here: `"Remind me to take out the
        garbage when I get home"`, `"Set an alarm for 6:45 tomorrow"`,
        `"Pick up the keys"` and `"Private words"`, and so were two of the
        messages, `"precondition: the system holds it"` and `"the counts
        are unchanged by the order"`. 4117 -> 4121 the same day, from
        nothing held being timed by its proposal: `MorningBriefTests`'
        held-row test is rewritten so the task leads, and one test is added
        for a list whose only dated entry is held. Five assertion messages
        are added, `"the held list is not timed by its proposal"`, `"the
        held list is not counted as due"`, `"a held proposal does not time
        its list"`, `"the held entry is still on the list"` and `"a held
        proposal creates no morning"`, and one is removed, `"the held list
        is the silent one"`, whose claim is no longer true. Every fixture
        was already here.
        4121 -> 4140 on 2026-09-23 again, from
        Needs review listing what the receipt says it does (REV-3): three
        new tests and one rewritten in `ItemPresentationTests`, nineteen
        literals, enumerated by diffing this census against `HEAD`. Five are
        fixtures: a transcript, `"Buy milk and eggs later, and call the
        plumber"`; a segment, `"Buy eggs later"`; a hand-built title,
        `"Call the plumber"`, which is its segment too; and the title edit,
        `"Dish soap thing"` to `"Buy dish soap"`. Fourteen are assertion
        messages, one of them the interpolated per-sentence message of the
        single-item receipt loop, and one `"got \\(result.receiptContext)"`.
        The transcripts that loop captures add nothing, because each is
        already in this directory, and the doc comments quote in backticks.
        4140 -> 4148 the same day, from merging the place half of the hold
        reading only the place's mark (4121 -> 4129 on its own branch): two
        tests in `LocationReminderTests` add eight literals, none of them
        already on this branch, counted by diffing this census before and
        after the merge. Seven are assertion messages, `"the save confirmed
        the place it showed"`, `"confirming is not a new trigger"`, `"the
        saved place is delivered"`, `"precondition: the time carries the
        mark"`, `"precondition: the place does not"`, `"precondition: a place
        alone"` and `"a place nobody confirmed is not delivered"`; the eighth
        is a KNOWN_ISSUES heading a doc comment quotes, `"Saving counts as
        confirming"`. The transcript, the title and `"precondition: the
        system holds it"` were already here. 4148 -> 4151 the same day,
        from merging a save that leaves the place out no longer confirming it
        (4129 -> 4132 on its own branch): one test in
        `LocationReminderTests` adds three assertion messages,
        `"precondition: a place was read"`, `"precondition: nobody confirmed
        it"` and `"a place the save never named is not confirmed"`, none of
        them already on this branch, and none is removed. 4151 -> 4153 the
        same day, from merging the pin that the editor sends every place it
        shows back as an edit (4132 -> 4134 on its own branch): two
        assertion messages, `"a place the editor showed comes back as an
        edit"` and `"the editor cannot add a place"`, none of them already on
        this branch, and none is removed.
        4068 -> 4077 on 2026-09-23, from
        keeping a time set by hand through a re-read: five
        `SwiftDataThoughtRepositoryTests` tests, nine literals added and
        none removed, enumerated rather than assumed. One is a fixture,
        `"Remind me to call Catherine tomorrow at 9 AM"`, used six times
        and counted once. Eight are assertion messages: `"Organize again
        replaced a due date set by hand"`, `"Organize again restored a
        time the person removed"`, `"a split replaced a time set by
        hand"`, `"a time only the system wrote was not re-read"`,
        `"launch re-read a time set by hand"`, `"the fixture needs a
        spoken time to lose"`, `"the place must be the system's"` and
        `"the system's place is still released"`. The Sobeys wording the
        holdout test reuses was already here, and no phrase in the new doc
        comments is in quotation marks. 4077 -> 4079 on 2026-09-23, from
        review of the same change: one more split test, which puts the
        time words in part 1, two literals added and none removed, found
        by diffing `swift_literals` before and after. Both are assertion
        messages, `"part 0 no longer keeps the time by position"` and
        `"part 1 did not read its own spoken time"`. Its fixture is the
        Catherine sentence above, already counted, `"Buy milk"` is under
        twelve characters, and its doc comment quotes nothing. 4068 -> 4109 on 2026-09-23, from
        DEL-11, a saved place beside a bare day: forty-one literals,
        enumerated rather than assumed. Nineteen are captures: eighteen
        `corpusCase` rows added to `SemanticCorpusB.location`, plus the one
        `LocationReminderTests` capture, `"Remind me to call Mom when I get
        home tomorrow"`, which its three new tests share and which counts
        once. Thirteen are `note:` arguments on those rows and nine are
        assertion messages. One of the nine interpolates a place and a
        temporal kind, and it counts once however many iterations print
        it. The quoted "tonight" in the new comments is under twelve
        characters and counts nothing. The development-set overlap stayed
        at 114, checked by regenerating `LANGUAGE_BASELINE.md`.
        4109 -> 4145 on 2026-09-23, from the review of that change (the
        place name ending where a time begins, the scheduler refusal, and a
        named place beside a time held too): forty-eight added and twelve
        removed, enumerated rather than assumed by diffing this population
        at both commits. Added: eight `corpusCase` captures in
        `SemanticCorpusB.location` (`"Remind me to call Mom when I get home
        Friday"`, `"When I get home Friday, remind me to call Mom"`, `"When
        I get to work Friday remind me to submit my timesheet"`, `"When I
        get to work next Monday remind me to submit my timesheet"`, and
        `"Remind me to water the plants when I get home"` followed by `on
        the 15th`, `this weekend`, `August 20th` and `the day after
        tomorrow`); four `note:` arguments, one of them on the Costco row
        that moved; six test captures (`"Remind me at Costco tomorrow to
        buy batteries"`, `"Remind me to bring the snacks when I get to
        Sunday school"`, `"Remind me to buy bread when I get to the Monday
        market"`, `"Remind me to get eggs, bread, and cheese in one hour"`,
        `"Remind me to stretch when I get to the gym"`, `"When I go to
        Sobeys in an hour, remind me to get eggs"`); two expected place
        names, `"monday market"` and `"sunday school"`; twenty-five
        assertion messages; and three phrases quoted in doc comments,
        `"sobeys in an hour"`, `"work next monday"` and `"when I go to
        Sobeys in an hour…"`, the hazard named above, hit once more. The development-set overlap
        stayed at 114, checked by regenerating `LANGUAGE_BASELINE.md`.
        Removed: the Costco row's old note and eleven assertion messages
        from the tests that asserted the time won over a named place.
        Three of the new assertion messages said "wait", and the `wait`
        bullet pinned in `TheMotivatingFiguresAtTheTopAreRecomputed` counts
        any utterance in this directory that contains the word, assertion
        messages included: it moved from 58 rows to 60 on prose nobody
        would say. The messages were first reworded to say "held" and
        "stays" rather than the bullet repinned. Review called that what it
        is, test prose edited to keep a figure, so on 2026-09-23 the three
        messages were restored word for word and the bullet repinned from
        (58, 18, 30, 33) to (60, 18, 32, 32), in `MOTIVATING` and in the
        `observation.py` docstring. That this census reads assertion
        messages as utterances is a defect in the instrument, left visible
        rather than hidden. The count here does not move: three literals
        out, the same three back.
        4145 -> 4154 on 2026-09-23, from the second review of that change
        (names that end in a number or a weekday): nine added, none
        removed, enumerated by diffing this population at both commits.
        Four test captures (`"Remind me to get a coffee when I get to gate
        5"`, `"Remind me to drop off the forms when I get to room 204"`,
        `"Remind me to grab a table when I get to TGI Fridays"`, `"Remind
        me to grab napkins when I get to Ruby Tuesday"`), each also a
        `corpusCase` in `SemanticCorpusB.location` except the room; three
        `note:` arguments on those rows; and two phrases quoted in a doc
        comment, `"Ruby Tuesday"` and `"Costco Tuesday"`. The
        development-set overlap stayed at 114.
        4154 -> 4155 on 2026-09-23, from aligning the scheduler refusal
        with #138 (a place set by hand no longer releases the time beside
        it): one assertion message added, `"a place set by hand does not
        confirm the time beside it"`, none removed, found by diffing this
        population at both commits. The overlap stayed at 114.
        4155 -> 4159 on 2026-09-23, from making DEL-18's shift visible:
        four added, none removed, found by diffing this population at both
        commits. Two `corpusCase` captures in `SemanticCorpusB.location`
        (`"Remind me to take my pills when I go to bed tonight"`, `"Remind me
        to mute my phone when I'm in a meeting tomorrow"`) and their two
        `note:` arguments. The overlap stayed at 114. Still 4159 on
        2026-09-23 after the round-3 grade: those two notes each gained a
        sentence saying the place they pin (bed, meeting) is a false place a
        later fix should move, so two literals were replaced by two and the
        count did not change.
        4159 -> 4167 on 2026-09-23, from keeping the store list on a
        shopping row held only by DEL-18's place-and-time hold: eight added,
        none removed, found by diffing this population at both commits. One
        test, `testOnlyThePlaceAndTimeHoldKeepsAReviewRowOnTheStoreList`,
        brought its capture (`"When I get to Costco tomorrow, buy milk"`),
        a trip fixture's quote and title (`"go to Costco"`, `"Go to
        Costco"`) and five assertion messages (`"fixture: the hold puts the
        row in review"`, `"the hold alone keeps the store's list"`, `"a row
        in review for another reason names no list"`, `"the hold beside
        another question names no list"`, `"the dated trip keeps its
        reminder beside a held list"`). Its `"buy milk"` and `"Buy milk"`
        were already in the population.
        4100 -> 4104 on 2026-09-23, from the fifth round of that change's
        grading: a snooze of a recurring row whose intent data will not
        decode had no test. Four in, none out, all assertion messages --
        `"Precondition: the backfill kept the bytes"`, `"Precondition: the
        row recurs"`, `"a snooze of this row must report it unreadable, not
        recorded"` and `"a snooze must not write a record over intent data
        it cannot read"`. It reuses the weekly bins sentence, `"not an
        intent"` and `"Precondition: data that will not decode"`.
        4078 -> 4093 on 2026-09-23, from a
        repeating alarm that has rung staying armed: three
        `TemporalFullPathTests` methods and fifteen literals, all assertion
        messages, enumerated rather than assumed. Their two captures, `"Set
        an alarm every day at 6:30 AM"` and `"Alarm at 7 every weekday"`,
        were already in this directory and add nothing. The sixteenth,
        making 4094, is `"Every weekday"` quoted in a doc comment. It was
        briefly rewritten into backticks to leave 4093 and then put back,
        for the reason the 4068 entry gives: the count is a tripwire, not a
        target.
        4182 -> 4190 on 2026-09-23, when replacing the attempt began
        stopping its alarm synchronously: one method and eight literals,
        enumerated rather than assumed. One fixture, the retry `"Set an
        alarm for 7:30 AM to take my vitamins"` (the attempt, `"Set an
        alarm for 7 AM to take my pills"`, was already counted), and
        seven assertion messages, two of them preconditions.
        4113 -> 4113 on 2026-09-23, from that change's third grading: a
        doc comment in `LocationReminderTests` was corrected to name the
        three tests that reach the scoped fetch, and a comment holds no
        literal, so none came in or went out.
        4167 -> 4190 on 2026-09-23, from the launch pass that moves a
        stored place-and-time row nobody was asked about into review (F7):
        23 added, none removed, found by diffing this population at both
        commits. Three tests in `SwiftDataThoughtRepositoryTests` brought a
        title (`"Take out the garbage"`), a phrase quoted in a doc comment
        (`"when I get home tomorrow"`), two row names (`"time set by
        hand"`, `"already in review"`), three interpolated messages read
        as literal text (`"\\(name): review flag changed"` and two
        siblings) and 16 other assertion messages.
        4068 -> 4074 on 2026-09-23, from `BudgetedWorkTests`: six new
        literals, all assertion messages, none a fixture, enumerated by
        diffing the literal sets rather than counted from the tests.
        4074 -> 4079 the same day, from the two tests the grade asked
        for (one model call at a time, and a cancelled capture): five
        more assertion messages, no fixture. 4079 -> 4083 from the
        second round's two (a capture cancelled mid-call, and the claim
        deadline): four assertion messages. 4083 -> 4085 from the third
        round: the claimed-path precondition and the takeover being
        observable, two assertion messages.
        4068 -> 4068 on 2026-09-23, from the capture diagnostics: six
        new tests and two extended ones add no literal, because every
        expected value is a snake_case label with no space and the one
        private-message fixture, `"The user typed a private thought
        here"`, was already in `SwiftDataThoughtRepositoryTests`.
        4068 -> 4068 on 2026-09-23, from the diagnostics' truthfulness
        fixes: dropping `max_duration` from the pinned `stop_trigger` set
        removes a snake_case label, not a multi-word literal.
        #152's branch had, on its own parent, 4068 -> 4087 on 2026-09-23, from
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
        tasks added a helper and four preconditions and no literal.
        4124 -> 4125 the same day, in review of #150: a fifth knowledge
        row for the DEL-25 tests, an `.unclear` safety row held for review
        in a finished capture, so that only its kind can leave it out. One
        literal, its words, `Something I never finished saying`, recounted
        from the tree rather than incremented. 4125 -> 4138 on
        2026-09-23, from DEL-26 (a single-target cancel deleting a
        knowledge row held for review): three `CaptureOperationTests`
        tests and a helper, thirteen literals, enumerated rather than
        assumed. Four are fixtures (`Sarah said the landlord is raising
        the rent`, `Stop reminding me about the landlord`, `Never mind the
        lease`, `Remind me to call the landlord tomorrow`) and eight are
        assertion messages. The thirteenth is a new shape of the quoting
        hazard: two doc comments each say a quoted utterance `is a
        gating-corpus cancel with target` a quoted noun, and the extractor
        reads the words *between* the closing and the opening quotation
        marks as a literal, ` is a gating-corpus cancel with target `,
        counted once for both. Left as written. 4138 -> 4142 the same day,
        in review of #152: the "Never mind the lease" test gains an
        unrelated action row, so a vague reading would list two rows and
        fail. Four literals, recounted from the tree: the row's words,
        `Water the tomato plants`, and three assertion messages. 
        4800 -> 4843 on 2026-09-23, merging #152 at `74040e2` (which
        carries #150) into the V1 candidate: measured from the merged tree,
        not taken from either side (4800 on the candidate, 4142 on #152,
        4099 at their merge base `b9f044c`; #152 and #150 add 43 and
        remove 0, and none of the 43 was already on the candidate):
        4800 + 43 - 0 = 4843.
        #151's branch had, on its own parent, 4068 -> 4102 on 2026-09-23, from
        holding reported advice for review (case 4 of Calvin's
        2026-09-16 reported-speech ruling): thirty-five literals in and
        one out, enumerated with the census helper rather than predicted.
        Thirty are utterances in six `ActionabilityTests` methods and
        seven new `SemanticCorpusQ` rows, four are `note:` arguments, and
        one is an assertion message. The one out is the old `note:` on
        the `SemanticCorpusD` row "Priya said I should call the
        landlord", which the ruling changed from a Today task to a review
        row; its replacement note carries the old sentence plus the
        ruling, so the edit counts once each way rather than not at all.
        This time the overlap moved, 114 -> 115: "Sarah told me to call
        Mike" is `routed.tsv` row AO04 verbatim, found by regenerating
        `LANGUAGE_BASELINE.md` rather than by reading. 4102 -> 4105 on
        2026-09-23, from the grade of #151 (F1) adding the reminder and
        message verbs to the advice frame: three utterances in two
        `ActionabilityTests` methods, `"Sarah reminded me I should call
        Mike"`, `"Sarah texted me that I should call Mike tomorrow at
        3"` and the case-3 control `"Sarah reminded me to call Mike"`,
        enumerated with the census helper, none out. 4105 -> 4107 the
        same day, from the refinement guard for held reported advice
        (grade of #151, section 4): two literals in two
        `RefinementGuardTests` methods, the canned action half `"I
        should call Mike tomorrow at 3"` and the assertion message
        `"the split handed back a dated task for somebody else's
        advice"`, none out.
        4843 -> 4882 on 2026-09-23, merging #151 at `9fb10da` into the V1
        candidate: measured from the merged tree, not taken from either side
        (4843 on the candidate, 4107 on #151, 4068 at their merge base
        `fbb6f90`; #151 adds 40 and removes 1, none of the 40 was already
        on the candidate, and the one it removes, the old `SemanticCorpusD`
        note, was still there): 4843 + 40 - 1 = 4882. What the test
        is actually
        guarding — that the two readings of "multi-word" still agree exactly
        and in both directions —
        is the assertion above, and it is unaffected. 4068 -> 4116 on
        2026-09-22, from entity context: nine tests in
        `PersonMentionTests`, forty-eight literals, enumerated by
        diffing this file's own multi-word set against `origin/main`
        rather than counted by hand, and every one is in that single
        file. Twenty-nine are captures, thirteen are assertion or skip
        messages — two of those interpolated, and they count exactly
        like fixtures — **and six are the doc-comment hazard this log
        has now recorded three times**. Three of the six are frames a
        comment quotes in order to say what is wrong with them (`"I
        spoke with <name>"`, `"<name> said hello"`, `"when I get to
        <shop>"`) and three are not phrases at all: `"), and a bare "`,
        `"reach out to"` and `"walk with Sam"` are the gaps between
        quoted fragments in a sentence, which is what a comment-blind
        reader sees when a comment lists particle forms in quotation
        marks. 29 + 13 + 6 = 48; an earlier draft of this entry gave
        groups that summed to 35 against a total of 39 and said six
        tests where there were seven, which is the same failure this
        file exists to catch, one level up — **a figure inside a log
        entry recomputes nowhere either**. Left as they are, on the
        precedent two paragraphs above: the count is a tripwire, not a
        target, and rewriting a sentence to please it would be tuning
        the instrument. The development-set overlap stayed at 114, so
        none of the forty-eight is verbatim a devset row; checked by
        regenerating `LANGUAGE_BASELINE.md`, not assumed. Predicting the
        count from the nine test methods would have missed the six
        comment fragments entirely. 4116 -> 4118 on 2026-09-23, merging
        #137 into the V1 candidate: measured from the merged tree, not
        taken from either side (4116 on the candidate, 4070 on #137,
        4068 at their merge base; #137 adds 2 and removes 0, 0 of its
        additions were already on the candidate). 4118 -> 4140 on
        2026-09-23, merging #124 into the V1 candidate: measured from
        the merged tree, not taken from either side (4118 on the
        candidate, 4090 on #124, 4068 at their merge base; #124 adds 22
        and removes 0, 0 of its additions were already on the
        candidate). 4140 -> 4149 on 2026-09-23, merging #131 into the V1
        candidate: measured from the merged tree, not taken from either
        side (4140 on the candidate, 4099 on #131, 4090 at their merge
        base; #131 adds 9 and removes 0, 0 of its additions were already
        on the candidate). 4149 -> 4150 on 2026-09-23, merging #127 into
        the V1 candidate: measured from the merged tree, not taken from
        either side (4149 on the candidate, 4069 on #127, 4068 at their
        merge base; #127 adds 1 and removes 0, 0 of its additions were
        already on the candidate). 4150 -> 4154 on 2026-09-23, merging
        #145 into the V1 candidate: measured from the merged tree, not
        taken from either side (4150 on the candidate, 4072 on #145,
        4068 at their merge base; #145 adds 6 and removes 2, 0 of its
        additions were already on the candidate). 4154 -> 4160 on
        2026-09-23, merging #122 into the V1 candidate: measured from
        the merged tree, not taken from either side (4154 on the
        candidate, 4074 on #122, 4068 at their merge base; #122 adds 6
        and removes 0, 0 of its additions were already on the
        candidate). 4160 -> 4192 on 2026-09-23, merging #129 into the V1
        candidate: measured from the merged tree, not taken from either
        side (4160 on the candidate, 4100 on #129, 4068 at their merge
        base; #129 adds 32 and removes 0, 0 of its additions were
        already on the candidate). 4192 -> 4206 on 2026-09-23, merging
        #133 into the V1 candidate: measured from the merged tree, not
        taken from either side (4192 on the candidate, 4078 on #133,
        4069 at their merge base; #133 adds 9 and removes 0, 0 of its
        additions were already on the candidate). The merge resolution
        itself adds 5 (`a daily series is one AlarmKit can repeat`, `the
        repetition must keep the series' hour`, `the repetition must
        keep the series' minute`, `the snooze landed on the series' own
        minute, so the two readings agree`, `the snoozed occurrence
        rings once, at the snooze`).

        4068 -> 4084 on 2026-09-23, from Merge and Undo keeping an open row
        open (REV-5): three `SwiftDataThoughtRepositoryTests` tests and their
        shared fixture, sixteen literals, enumerated rather than assumed. One
        fixture, `"Pay the water bill"`. Fourteen assertion messages:
        `"precondition: the capture holds exactly the two split rows"`,
        `"precondition: the first row is done"`, `"precondition: the second
        row is open"`, `"precondition: the merged sentence states a time"`,
        `"the open row is the one that survives"`, `"one open row among the
        sources keeps the result open"`, `"the result is something the
        scheduler would arm"`, `"merge re-arms the result through
        synchronizeReminders, so it is pending now"`, `"Undo files the whole
        capture for review"`, `"the whole transcript is the row's words"`,
        `"the original words are untouched"`, `"with every row closed the
        earliest row survives"`, `"every source row was done, so the result
        is done"` and `"no open row appears from a capture that was
        finished"`. And one phrase quoted in a doc comment, `"one reviewable
        item"`, the footer the Undo test is named against: the hazard this log
        has named three times, left in quotation marks for the same reason as
        before. Two literals the tests use add nothing because they were
        already here: the fixture `"Remind me to call Sam in 3 hours"` and the
        skip message `"notification permission is not granted on this
        simulator"`, both in `TemporalFullPathTests`. The merged sentence the
        fixture's doc comment quotes spans two lines, so it is not one literal
        and counts for nothing.

        4084 -> 4085 on 2026-09-23, from the grade of that change: the merge
        test now shows its starting point instead of leaving it derivable,
        with one assertion message, `"precondition: the open row has nothing
        pending before the merge"`. 4206 -> 4223 on 2026-09-23, merging
        #141 into the V1 candidate: measured from the merged tree, not
        taken from either side (4206 on the candidate, 4085 on #141,
        4068 at their merge base; #141 adds 17 and removes 0, 0 of its
        additions were already on the candidate). 4223 -> 4229 on
        2026-09-23, merging #142 into the V1 candidate: measured from
        the merged tree, not taken from either side (4223 on the
        candidate, 4074 on #142, 4068 at their merge base; #142 adds 6
        and removes 0, 0 of its additions were already on the
        candidate). 4229 -> 4272 on 2026-09-23, merging #130 into the V1
        candidate: measured from the merged tree, not taken from either
        side (4229 on the candidate, 4111 on #130, 4068 at their merge
        base; #130 adds 44 and removes 1, 0 of its additions were
        already on the candidate). 4272 -> 4319 on 2026-09-23, merging
        #116 into the V1 candidate: measured from the merged tree, not
        taken from either side (4272 on the candidate, 4115 on #116,
        4068 at their merge base; #116 adds 47 and removes 0, 0 of its
        additions were already on the candidate). 4319 -> 4323 on
        2026-09-23, merging #119 into the V1 candidate: measured from
        the merged tree, not taken from either side (4319 on the
        candidate, 4119 on #119, 4115 at their merge base; #119 adds 4
        and removes 0, 0 of its additions were already on the
        candidate). 4323 -> 4325 on 2026-09-23, merging #134 into the V1
        candidate: measured from the merged tree, not taken from either
        side (4323 on the candidate, 4121 on #134, 4119 at their merge
        base; #134 adds 2 and removes 0, 0 of its additions were already
        on the candidate). 4325 -> 4341 on 2026-09-23, merging #126 into
        the V1 candidate: measured from the merged tree, not taken from
        either side (4325 on the candidate, 4135 on #126, 4119 at their
        merge base; #126 adds 16 and removes 0, 0 of its additions were
        already on the candidate). 4341 -> 4350 on 2026-09-23, merging
        #123 into the V1 candidate: measured from the merged tree, not
        taken from either side (4341 on the candidate, 4077 on #123,
        4068 at their merge base; #123 adds 9 and removes 0, 0 of its
        additions were already on the candidate). 4350 -> 4371 on
        2026-09-23, merging #128 into the V1 candidate: measured from
        the merged tree, not taken from either side (4350 on the
        candidate, 4156 on #128, 4135 at their merge base; #128 adds 21
        and removes 0, 0 of its additions were already on the
        candidate). 4371 -> 4418 on 2026-09-23, merging #132 into the V1
        candidate: measured from the merged tree, not taken from either
        side (4371 on the candidate, 4182 on #132, 4135 at their merge
        base; #132 adds 47 and removes 0, 0 of its additions were
        already on the candidate). 4418 -> 4443 on 2026-09-23, merging
        #139 into the V1 candidate: measured from the merged tree, not
        taken from either side (4418 on the candidate, 4181 on #139,
        4156 at their merge base; #139 adds 25 and removes 0, 0 of its
        additions were already on the candidate). 4443 -> 4471 on
        2026-09-23, merging #144 into the V1 candidate: measured from
        the merged tree, not taken from either side (4443 on the
        candidate, 4184 on #144, 4156 at their merge base; #144 adds 28
        and removes 0, 0 of its additions were already on the
        candidate). 4471 -> 4485 on 2026-09-23, merging #125 into the V1
        candidate: measured from the merged tree, not taken from either
        side (4471 on the candidate, 4088 on #125, 4074 at their merge
        base; #125 adds 14 and removes 0, 0 of its additions were
        already on the candidate). 4485 -> 4510 on 2026-09-23, merging
        #135 into the V1 candidate: measured from the merged tree, not
        taken from either side (4485 on the candidate, 4113 on #135,
        4088 at their merge base; #135 adds 25 and removes 0, 0 of its
        additions were already on the candidate). 4510 -> 4570 on
        2026-09-23, merging #138 into the V1 candidate: measured from
        the merged tree, not taken from either side (4510 on the
        candidate, 4134 on #138, 4074 at their merge base; #138 adds 60
        and removes 0, 0 of its additions were already on the
        candidate). 4570 -> 4582 on 2026-09-23, merging #143 into the V1
        candidate: measured from the merged tree, not taken from either
        side (4570 on the candidate, 4079 on #143, 4068 at their merge
        base; #143 adds 11 and removes 0, 0 of its additions were
        already on the candidate). The merge resolution itself adds 5
        (`precondition: a live place reminder`, `precondition: no time
        sits beside the place`, `precondition: the column reads time`,
        `precondition: the place is still stored`, `precondition: the
        setter keeps the copy in step`) and removes 4 (`precondition: a
        hand-set place survives a reorganize`, `precondition: the column
        no longer says location`, `precondition: the date wrote over the
        place`, `precondition: the reorganize took the time away`). 4582
        -> 4600 on 2026-09-23, merging #140 into the V1 candidate:
        measured from the merged tree, not taken from either side (4582
        on the candidate, 4153 on #140, 4134 at their merge base; #140
        adds 19 and removes 0, 1 of its additions was already on the
        candidate). 4600 -> 4700 on 2026-09-23, merging #136 into the V1
        candidate: measured from the merged tree, not taken from either
        side (4600 on the candidate, 4167 on #136, 4068 at their merge
        base; #136 adds 109 and removes 10, 0 of its additions were
        already on the candidate). The merge resolution itself adds 2
        (`launch released a named place held beside a time`, `the row's
        bell reads the same refusal as the scheduler`) and removes 1
        (`the system's place is still released`). 4700 -> 4704 on
        2026-09-23, re-merging #129 at `9b88e05` into the V1 candidate
        in the second merge rehearsal: measured from the merged tree,
        not taken from either side (4700 on the candidate, 4104 on #129,
        4100 at their merge base; #129 adds 4 and removes 0, 0 of its
        additions were already on the candidate). 4704 -> 4720 on
        2026-09-23, re-merging #133 at `316e828` into the V1 candidate
        in the second merge rehearsal: measured from the merged tree,
        not taken from either side (4704 on the candidate, 4094 on #133,
        4078 at their merge base; #133 adds 16 and removes 0, 0 of its
        additions were already on the candidate). 4720 -> 4728 on
        2026-09-23, re-merging #132 at `867bdae` into the V1 candidate
        in the second merge rehearsal: measured from the merged tree,
        not taken from either side (4720 on the candidate, 4190 on #132,
        4182 at their merge base; #132 adds 8 and removes 0, 0 of its
        additions were already on the candidate). 4728 -> 4728 on
        2026-09-23, re-merging #135 at `39fd13c` into the V1 candidate
        in the second merge rehearsal: measured from the merged tree,
        not taken from either side (4728 on the candidate, 4113 on #135,
        4113 at their merge base; #135 adds 0 and removes 0, 0 of its
        additions were already on the candidate). 4728 -> 4750 on
        2026-09-23, re-merging #136 at `5d00235` into the V1 candidate
        in the second merge rehearsal: measured from the merged tree,
        not taken from either side (4728 on the candidate, 4190 on #136,
        4167 at their merge base; #136 adds 23 and removes 0, 1 of its
        additions was already on the candidate). 4750 -> 4767 on
        2026-09-23, merging #146 at `8d50b6c` into the V1 candidate in
        the second merge rehearsal: measured from the merged tree, not
        taken from either side (4750 on the candidate, 4085 on #146,
        4068 at their merge base; #146 adds 17 and removes 0, 0 of its
        additions were already on the candidate). 4767 -> 4767 on
        2026-09-23, merging #148 at `666eb1e` into the V1 candidate in
        the second merge rehearsal: measured from the merged tree, not
        taken from either side (4767 on the candidate, 4068 on #148,
        4068 at their merge base; #148 adds 0 and removes 0, 0 of its
        additions were already on the candidate). 4767 -> 4767 on
        2026-09-23, a candidate commit of the second merge rehearsal
        (rehearsal-1 grade, item (c)): the snoozed repeating-alarm test
        now skips on the condition the schedule turns on, not on equal
        clocks, so its skip message changed. One in (`the series' next
        ring is within a minute of the snooze, where the repetition is
        armed by design`), one out (`the snooze landed on the series'
        own minute, so the two readings agree`). 4767 -> 4773 on
        2026-09-23, a candidate commit of the second merge rehearsal
        (merge line F1, #129 with #133): a snoozed repeating alarm keeps
        its series under the item ID and rings once under its own ID;
        the (c) test is replaced by two tests and a durability test is
        added. Seven in (`a relative alarm is refused by design`,
        `cancelling a row must cancel its series and its snooze`,
        `precondition: the snooze is still ahead`, `snoozing one
        occurrence must leave the series armed under the item ID`, `the
        ID maps back to its row`, `the series rings within a minute,
        where a relative alarm is refused by design`, `the snooze must
        not replace the series' alarm`), one out (`the series' next ring
        is within a minute of the snooze, where the repetition is armed
        by design`): 4767 + 7 - 1 = 4773. 4773 -> 4775 on 2026-09-23, a
        candidate commit of the second merge rehearsal (merge line F3,
        #132 with #135): `deleteCapture` re-plans the region budget, and
        the region-freeing test gains a step for it. Two in (`Remind me
        to bring the umbrella every time I get home`, `replacing an
        attempt`), none out: 4773 + 2 - 0 = 4775. 4775 -> 4775 on
        2026-09-23, merging #148 at `373ddc5` into the V1 candidate in
        the rehearsal-2 follow-up: measured from the merged tree, not
        taken from either side (4775 on the candidate, 4068 on #148,
        4068 at their merge base `666eb1e`; #148 adds 0 and removes 0, 0
        of its additions were already on the candidate). 4775 -> 4778 on
        2026-09-23, a candidate commit of the rehearsal-2 follow-up (#148
        with #123, #139 and #144): partial recovery passes get failure
        kinds of their own and an empty VoiceOver finish sends nothing.
        Three in, all phrases quoted in the new tests' doc comments, the
        hazard above once more (`VoiceOver is on`, `stopped after partial
        words`, `timed out having read nothing`), none out: 4775 + 3 - 0
        = 4778. The tests' fixture, `buy milk and call`, was already in
        `DurabilityTests`, and every expected value is a snake_case label. 4778 -> 4800 on
        2026-09-23, from DEL-23 (the launch and foreground reconcile
        leaves a ringing alarm alone): four `DurabilityTests` tests and one
        `TemporalFullPathTests` decision test. Twenty-two in, all assertion
        messages, enumerated rather than assumed: `a completed row's alarm
        must not outlive the pass`, `a held row's alarm must not outlive
        the pass`, `a one-shot five minutes after its ring`, `a one-shot
        that rang before the window`, `a one-shot that rang eight days
        ago`, `a removed row's alarm must not outlive the pass`, `a row
        that arms nothing`, `a row with no fire`, `a series AlarmKit
        repeats rang this morning without the app`, `a series whose first
        ring is tomorrow`, `a snooze that fired half a minute ago`, `an
        alarm still ahead`, `an alarm that rang before the window is
        cancelled as before`, `nor stop the series beside it`, `opening
        the app must not silence a snooze that is ringing`, `opening the
        app must not silence an alarm that is ringing`, `precondition: a
        series`, `precondition: an alarm`, `precondition: an alarm once
        released`, `precondition: held`, `precondition: nothing re-arms
        it`, `precondition: the snooze displaced the occurrence`. None
        out. The fixtures add nothing: `Set an alarm for 7 AM to take my
        pills` and `Set an alarm every day at 6:30 AM` were already here,
        `a notification` already was too, and `Alarm` is under twelve
        characters: 4778 + 22 - 0 = 4800, measured from the tree after merging the candidate at `026a78a` into #153 (DEL-23 was written at 4775 -> 4797).
        4882 -> 4886 on 2026-09-23, a candidate commit fixing the hosted
        f6c5bd2 failures (an intent the build cannot read is not erased
        by the roll-forward or a restore): one `TemporalFullPathTests`
        test. Four in, all assertion messages, enumerated by diffing
        `swift_literals` before and after (`a readable intent still
        replaces the bytes`, `carrying nothing erased the bytes`, `no
        bytes: nil goes through the setter as before`, `precondition:
        bytes that will not decode`). None out. Its fixture, `Take the
        bins out`, was already here: 4882 + 4 - 0 = 4886. 4886 -> 4889
        the same day, the next commit of that fix: #138's hand-set-place
        test is retargeted to the documented save-confirms rule under
        #143. Four in, all assertion messages (`Organize again replaced
        the time the editor showed and the save confirmed`, `a time the
        person confirmed stays armed through a re-read`, `precondition:
        only the hold can refuse the clock`, `the re-read kept the time's
        mark`). One out (`precondition: the re-read wiped the time's
        mark`), whose premise #143 ended: 4886 + 4 - 1 = 4889.
        """
        root = pathlib.Path(self.rm.__file__).resolve().parents[2]
        found = set()
        for swift in sorted((root / "SpeakItTests").glob("*.swift")):
            text = swift.read_text(encoding="utf-8", errors="replace")
            found.update(self.rm.swift_literals(text))
        space = {l for l in found if " " in l.strip()}
        split = {l for l in found if len(l.split()) > 1}
        self.assertEqual(space, split)
        self.assertEqual(len(space), 4889)

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



class NothingSpeakItSaysReachesAnOpenMicrophone(unittest.TestCase):
    """The audio session has no echo cancellation, so an announcement
    VoiceOver speaks while the recognizer is capturing can be transcribed into
    the person's original words (audit `v1/audits/accessibility.md`, A11Y-3).

    `VoiceOverAnnouncer` holds the rule and `VoiceOverAnnouncementTests` asks
    its decisions. What neither can see is the two facts about *other* files
    that the rule depends on: that nothing posts an announcement around it,
    and that `SpeechTranscriber.start` waits for silence immediately before
    the engine starts, with no suspension in between. An `await` added in that
    span is exactly the frame in which a notice could be posted and spoken
    into the microphone, and no Swift test can run `start` without a
    microphone. Checked here for the reason `TheDiagnosticIsNotAllowedToAbstain`
    gives: it is a claim about which source calls what, and this suite runs on
    Linux on every pull request.
    """

    ROOT = pathlib.Path(__file__).resolve().parents[2]
    SOURCES = ("SpeakIt", "Shared", "SpeakItShareExtension", "SpeakItLiveActivity")
    HOME = pathlib.Path("Shared") / "SharedCaptureInbox.swift"
    #: Both ways Swift can ask VoiceOver to speak: UIKit's
    #: `UIAccessibility.post(notification:argument:)` and SwiftUI's
    #: `AccessibilityNotification.Announcement(_:).post()`. Whitespace,
    #: newlines included, may sit around the dot, so a call broken across two
    #: lines is still one call.
    POSTS = (
        re.compile(r"UIAccessibility\s*\.\s*post\s*\("),
        re.compile(r"AccessibilityNotification\s*\.\s*Announcement\s*\("),
    )

    @staticmethod
    def code(line):
        """The line without a trailing `//` comment; a comment names, it does
        not call."""
        return line.split("//", 1)[0]

    def transcriber(self):
        path = self.ROOT / "SpeakIt" / "Features" / "Capture" / "SpeechTranscriber.swift"
        return path.read_text(encoding="utf-8", errors="replace").splitlines()

    def only(self, lines, needle, calls=False):
        """The one line carrying `needle`. With `calls`, a line declaring a
        function is not a call of it and is skipped."""
        found = [i for i, line in enumerate(lines) if needle in self.code(line)
                 and not (calls and "func " in self.code(line))]
        self.assertEqual(len(found), 1, f"expected one `{needle}`, found {len(found)}")
        return found[0]

    def body(self, lines, declaration):
        """A member's lines, from its declaration to its closing brace."""
        first = self.only(lines, declaration)
        last = next(i for i in range(first + 1, len(lines))
                    if lines[i].startswith("    }"))
        return [self.code(line) for line in lines[first:last]]

    def posts(self, text):
        """The line number of every announcement posted in `text`, with
        trailing comments removed first."""
        code = "\n".join(self.code(line) for line in text.splitlines())
        return sorted(code.count("\n", 0, found.start()) + 1
                      for pattern in self.POSTS for found in pattern.finditer(code))

    def announcer_lines(self):
        """The first and last line of `VoiceOverAnnouncer` in `HOME`: from its
        declaration to the first closing brace in column zero."""
        lines = (self.ROOT / self.HOME).read_text(
            encoding="utf-8", errors="replace").splitlines()
        first = self.only(lines, "final class VoiceOverAnnouncer")
        last = next(i for i in range(first + 1, len(lines)) if lines[i] == "}")
        return first + 1, last + 1

    def all_posts(self):
        found = []
        for top in self.SOURCES:
            for swift in sorted((self.ROOT / top).rglob("*.swift")):
                text = swift.read_text(encoding="utf-8", errors="replace")
                found += [(swift.relative_to(self.ROOT), n) for n in self.posts(text)]
        return found

    def test_every_announcement_goes_through_the_one_helper(self):
        first, last = self.announcer_lines()
        outside = [(path, n) for path, n in self.all_posts()
                   if not (path == self.HOME and first <= n <= last)]
        self.assertEqual(
            outside, [],
            f"announcements posted outside VoiceOverAnnouncer ({self.HOME}, "
            f"lines {first}-{last}): {outside}. Each one is spoken whether or "
            "not a microphone is open.")

    def test_the_scan_knows_both_apis_and_a_broken_line(self):
        """Falsifier for the scan itself: with only the UIKit spelling, or
        with a per-line search, one of these three is missed."""
        self.assertEqual(self.posts(
            "UIAccessibility.post(notification: .announcement, argument: m)\n"
            "AccessibilityNotification.Announcement(m).post()\n"
            "UIAccessibility\n    .post(notification: .announcement, argument: m)\n"
            "// UIAccessibility.post( in a comment is not a call\n"), [1, 2, 3])

    def test_the_microphone_opens_straight_after_the_wait(self):
        lines = self.transcriber()
        wait = self.only(lines, "waitUntilMicrophoneMayOpen(")
        opened = self.only(lines, "claimMicrophone()", calls=True)
        start = self.only(lines, "audioEngine.start()")
        self.assertLess(wait, opened)
        self.assertLess(opened, start)
        between = [self.code(line).strip() for line in lines[wait + 1:start]]
        suspending = [line for line in between if "await" in line]
        self.assertEqual(
            suspending, [],
            "a suspension between the wait and `audioEngine.start()` lets a "
            "notice be posted after the check and spoken into the microphone")

    def test_the_claim_reports_the_microphone_open(self):
        body = self.body(self.transcriber(), "func claimMicrophone()")
        self.assertTrue(any("announcer.microphoneWillOpen()" in line for line in body))

    def test_closing_the_microphone_is_reported_where_audio_stops(self):
        lines = self.transcriber()
        body = self.body(lines, "private func stopAudioInput()")
        self.assertTrue(any("audioEngine.stop()" in line for line in body))
        self.assertTrue(
            any("announcer.microphoneDidClose()" in line for line in body),
            "a microphone that is never reported closed silences VoiceOver for "
            "the rest of the session")

    def test_a_transcriber_that_goes_gives_its_claim_back(self):
        """`SpeechTranscriber` is released by its screen, and a claim it
        still holds then must not outlive it (see its `deinit`)."""
        body = self.body(self.transcriber(), "deinit {")
        self.assertTrue(any("holdsMicrophone" in line for line in body))
        self.assertTrue(any("announcer.microphoneDidClose()" in line for line in body))

    def test_a_finish_report_is_read_through_the_helper(self):
        """VoiceOver may report a finished announcement as an attributed
        string, which does not bridge to `String`. `spokenText(fromFinishReport:)`
        reads both forms and `VoiceOverAnnouncementTests` asks it, but an
        observer that went back to `as? String` would leave that test green
        and silently never match an attributed report, holding the
        microphone's wait to its full allowance."""
        lines = (self.ROOT / self.HOME).read_text(
            encoding="utf-8", errors="replace").splitlines()
        observed = self.only(lines, "UIAccessibility.announcementDidFinishNotification")
        closes = next(i for i in range(observed + 1, len(lines))
                      if self.code(lines[i]).strip() == "})")
        body = [self.code(line) for line in lines[observed:closes]]
        self.assertTrue(
            any("VoiceOverAnnouncer.spokenText(" in line for line in body),
            "the finish observer no longer reads its report through "
            "`spokenText(fromFinishReport:)`")
        self.assertFalse(any("as? String" in line for line in body))

    def test_there_is_something_to_check(self):
        """Without this the first test passes when the helper is renamed or
        moved: nothing posts anywhere, and `[HOME]` becomes `[]`."""
        first, last = self.announcer_lines()
        inside = [n for path, n in self.all_posts()
                  if path == self.HOME and first <= n <= last]
        self.assertGreaterEqual(len(inside), 1)

class TheLaunchPassesRunBeforeAnyCaptureCanBegin(unittest.TestCase):
    """Two launch passes may only run while no capture is under way in this
    process (Known Issues, "The launch passes rely on ordering").

    After a kill, a draft killed before its first audio buffer is identical in
    the store to one being recorded right now: `.capturing`, a recording file
    name, and under 512 bytes on disk. What tells them apart is not persisted,
    only *when* the pass runs. `pruneEmptyTextDrafts` drops a draft with no
    words and no recording, which is a live recording before its first buffer;
    `recoverInterruptedCaptureDraft` commits a draft with words and no
    recording, which is a live recording that carries typed words. Both are
    right only because they run in `RootView`'s launch task before the capture
    screen could have begun a draft, and the review of #144 found that nothing
    failed if that stopped being true.

    Two facts, then. Each pass has one caller, in the launch task. And the
    launch task does not suspend above either pass in a shipping build except
    where it always has: the one `Task.yield()` above the prune, which the
    capture screen cannot use (it has to be presented, and its own `.task`
    sleeps 180 ms before it begins a draft), and, above the text pass only,
    `recoverInterruptedAudioDrafts()`, whose length is the text pass's 12 s
    margin in Known Issues. `#if DEBUG` lines are left out, because the
    example loaders there await before the prune on purpose and Known Issues
    says so; their `#else` branches are shipping code and are kept.

    Checked here rather than in Swift because no XCTest can run the launch
    task, and because it is a claim about where source sits, which is what
    this suite reads on Linux on every pull request.
    """

    ROOT = pathlib.Path(__file__).resolve().parents[2]
    SOURCES = ("SpeakIt", "Shared", "SpeakItShareExtension", "SpeakItLiveActivity")
    HOME = pathlib.Path("SpeakIt") / "App" / "RootView.swift"
    PASSES = ("recoverInterruptedCaptureDraft", "pruneEmptyTextDrafts")
    #: The suspensions above each pass that the argument above allows.
    ALLOWED_ABOVE_PRUNE = ["await Task.yield()"]
    ALLOWED_ABOVE_TEXT_PASS = ["await Task.yield()", "await recoverInterruptedAudioDrafts()"]

    @staticmethod
    def code(line):
        """The line without a trailing `//` comment; a comment names, it does
        not call."""
        return line.split("//", 1)[0]

    def root_view(self):
        return (self.ROOT / self.HOME).read_text(
            encoding="utf-8", errors="replace").splitlines()

    #: The launch work either sits in `body`'s `.task` closure or, since the
    #: merged V1 fixes made `body` too long to type-check, in a method whose
    #: only caller is that `.task`.
    LAUNCH_METHOD = "performLaunchWork"

    def launch_task(self, lines):
        """(first, last) line indices of the `.task` closure, or the
        `.task`-only method, that holds the once-per-process maintenance
        guard, braces included."""
        guards = [i for i, line in enumerate(lines)
                  if "guard !hasPerformedMaintenance" in self.code(line)]
        self.assertEqual(len(guards), 1, "expected one maintenance guard")
        method = f"private func {self.LAUNCH_METHOD}() async {{"
        first = next(i for i in range(guards[0], -1, -1)
                     if self.code(lines[i]).strip() in (".task {", method))
        if self.code(lines[first]).strip() == method:
            use = re.compile(r"\b" + self.LAUNCH_METHOD + r"\b")
            callers = [self.code(line).strip() for i, line in enumerate(lines)
                       if i != first and use.search(self.code(line))]
            self.assertEqual(
                callers, [f".task {{ await {self.LAUNCH_METHOD}() }}"],
                f"`{self.LAUNCH_METHOD}` must be called only by the root "
                "view's `.task`; any other caller can run the launch passes "
                "while a capture is being recorded.")
        indent = lines[first][:len(lines[first]) - len(lines[first].lstrip())]
        last = next(i for i in range(first + 1, len(lines))
                    if lines[i].rstrip() == indent + "}")
        return first, last

    def shipping(self, lines):
        """`lines` with every line only a DEBUG build compiles blanked out."""
        kept, stack = [], []
        for line in lines:
            directive = line.strip()
            if directive.startswith("#if"):
                stack.append(directive == "#if DEBUG")
                kept.append("")
                continue
            if directive.startswith(("#else", "#elseif")) and stack:
                stack[-1] = False
                kept.append("")
                continue
            if directive.startswith("#endif") and stack:
                stack.pop()
                kept.append("")
                continue
            kept.append("" if any(stack) else line)
        return kept

    def test_each_pass_has_one_caller_and_it_is_the_launch_task(self):
        lines = self.root_view()
        first, last = self.launch_task(lines)
        for name in self.PASSES:
            use = re.compile(r"\b" + name + r"\b")
            sites = []
            for top in self.SOURCES:
                for swift in sorted((self.ROOT / top).rglob("*.swift")):
                    for number, line in enumerate(
                            swift.read_text(encoding="utf-8",
                                            errors="replace").splitlines(), 1):
                        code = self.code(line)
                        if use.search(code) and "func " + name not in code:
                            sites.append((swift.relative_to(self.ROOT), number))
            self.assertEqual(
                len(sites), 1,
                f"`{name}` is used at {sites}. A second caller can run while a "
                "capture is being recorded, and a live recording is "
                "indistinguishable in the store from an interrupted one.")
            path, number = sites[0]
            self.assertEqual(path, self.HOME)
            self.assertTrue(
                first < number - 1 < last,
                f"`{name}` is called at RootView.swift:{number}, outside the "
                "launch task, where a capture may already be under way.")

    def suspensions_above(self, call):
        """Every shipping `await` in the launch task above the one line
        that calls `call`."""
        lines = self.root_view()
        first, last = self.launch_task(lines)
        found = [i for i in range(first, last) if call in self.code(lines[i])]
        self.assertEqual(len(found), 1, f"expected one `{call}` in the launch task")
        above = self.shipping(lines[first:found[0]])
        return [self.code(line).strip() for line in above
                if re.search(r"\bawait\b", self.code(line))]

    def test_nothing_suspends_above_the_prune_in_a_shipping_build(self):
        self.assertEqual(
            self.suspensions_above("CaptureDraftStore.pruneEmptyTextDrafts()"),
            self.ALLOWED_ABOVE_PRUNE,
            "the launch task suspends before `pruneEmptyTextDrafts()`, so the "
            "capture screen can begin a recording first and the prune can "
            "delete it before its first buffer lands. Move the new work below "
            "the launch passes.")

    def test_nothing_new_suspends_above_the_text_pass_in_a_shipping_build(self):
        """The window between the prune and the text pass already holds the
        audio pass, the one unbounded suspension in the task; a second one
        there eats the same 12 s margin. The allowed list is compared exactly,
        so moving the text pass above the audio pass, which is safer, also
        fails here: whoever does it updates `ALLOWED_ABOVE_TEXT_PASS` to say
        so. That is a false alarm by design, not a catch."""
        self.assertEqual(
            self.suspensions_above("repository?.recoverInterruptedCaptureDraft()"),
            self.ALLOWED_ABOVE_TEXT_PASS,
            "the launch task gained a suspension before "
            "`recoverInterruptedCaptureDraft()`, so a recording begun meanwhile "
            "that carries typed words can be committed by the text pass as if "
            "it had been interrupted. Move the new work below the launch passes.")

    def test_there_is_something_to_check(self):
        """The tests above already refuse an empty answer: a renamed pass
        has no call site to count, and a filter that blanked the whole task
        would find no `Task.yield()`. This pins the rest of what they assume:
        that the region they read is a real launch task whose maintenance
        guard is shipping code, and that the passes are still declared under
        the names this class reads."""
        lines = self.root_view()
        first, last = self.launch_task(lines)
        self.assertGreater(last - first, 10)
        body = self.shipping(lines[first:last])
        self.assertIn("guard !hasPerformedMaintenance else { return }",
                      [line.strip() for line in body])
        store = (self.ROOT / "SpeakIt" / "Features" / "Capture"
                 / "CaptureDraftStore.swift").read_text(encoding="utf-8")
        self.assertIn("static func pruneEmptyTextDrafts()", store)
        repository = (self.ROOT / "SpeakIt" / "Repositories"
                      / "SwiftDataThoughtRepository.swift").read_text(encoding="utf-8")
        self.assertIn("func recoverInterruptedCaptureDraft()", repository)


class AVoiceOverGatedBranchSendsNoAnalytics(unittest.TestCase):
    """A branch that runs only while VoiceOver is on must send no analytics
    event, because any event of its own says "VoiceOver is on" against a
    per-install id (DECISIONS, #148's "Rehearsal-2 follow-up").

    `CaptureWordlessEnding.analyticsEvents(quality:)` makes the decision and
    a Swift test drives it, but the ending is an argument: the capture
    screen's VoiceOver-gated finish passes `.finishedByPerson`, which sends
    nothing, and `armNoSpeechTimeout` passes `.noSpeechTimeout`, which sends
    `capture_failed(speech)` and a quality sample. Swap the two and every
    Swift test still passes (diagnostics follow-up grade, "The gap"). So this
    reads `CaptureView.swift` and checks three facts:

    - the one place `.finishedByPerson` is passed is inside a
      VoiceOver-gated branch;
    - `.noSpeechTimeout` is passed only from `armNoSpeechTimeout`, and never
      from inside a VoiceOver-gated branch;
    - nothing inside a VoiceOver-gated branch calls `SpeakItAnalytics` or
      `analyticsEvents(` directly.

    A gate is an `if` or `guard` whose condition names
    `accessibilityVoiceOverEnabled`. An `if` gates its whole chain, `else`
    branches included, since an event sent only when VoiceOver is *off* is
    the same flag read the other way. A `guard` gates the rest of the block
    it sits in. Any other use of the flag is refused until it is listed in
    `NOT_GATES` or taught here, so a new shape cannot slip past unread. What
    this cannot see is a property derived from the flag, such as
    `requiresExplicitSavedConfirmation`, which the grade walked and found
    silent; and it checks where the analytics call sits, not the timing
    `capture_ready_ms` carries (Known Issues, "VoiceOver use is kept out of
    analytics events, not out of one timing").
    """

    ROOT = pathlib.Path(__file__).resolve().parents[2]
    SOURCES = ("SpeakIt", "Shared", "SpeakItShareExtension", "SpeakItLiveActivity")
    HOME = pathlib.Path("SpeakIt") / "Features" / "Capture" / "CaptureView.swift"
    FLAG = re.compile(r"\baccessibilityVoiceOverEnabled\b")
    #: Uses of the flag that are not a branch, as their stripped source line.
    NOT_GATES = (
        "@Environment(\\.accessibilityVoiceOverEnabled) private var accessibilityVoiceOverEnabled",
        "!autoDismissesSingleItemConfirmation || accessibilityVoiceOverEnabled",
    )
    FINISHED = re.compile(r"\.finishedByPerson\b")
    TIMEOUT = re.compile(r"\.noSpeechTimeout\b")
    ANALYTICS = re.compile(r"\bSpeakItAnalytics\b|\banalyticsEvents\s*\(")
    #: String literals and comments, in one left-to-right pass, so a brace or
    #: a name inside either is not read as code.
    NOT_CODE = re.compile(
        r'"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"|//[^\n]*|/\*[\s\S]*?\*/')

    @classmethod
    def code(cls, text):
        """`text` with every string literal and comment blanked, newlines
        kept, so offsets and line numbers still match the file."""
        return cls.NOT_CODE.sub(
            lambda found: re.sub(r"[^\n]", " ", found.group(0)), text)

    @staticmethod
    def closing(code, opening):
        """The offset of the `}` that closes the `{` at `opening`."""
        depth = 0
        for index in range(opening, len(code)):
            if code[index] == "{":
                depth += 1
            elif code[index] == "}":
                depth -= 1
                if depth == 0:
                    return index
        raise AssertionError(f"unbalanced brace at offset {opening}")

    @staticmethod
    def enclosing(code, offset):
        """The offset of the `{` that opens the block holding `offset`."""
        depth = 0
        for index in range(offset - 1, -1, -1):
            if code[index] == "}":
                depth += 1
            elif code[index] == "{":
                if depth == 0:
                    return index
                depth -= 1
        raise AssertionError(f"no block encloses offset {offset}")

    def gates(self, code):
        """(start, end) offsets of every VoiceOver-gated region, and the
        stripped lines of any use of the flag this class cannot classify."""
        regions, unknown = [], []
        for found in self.FLAG.finditer(code):
            start = code.rfind("\n", 0, found.start()) + 1
            end = code.find("\n", found.start())
            line = code[start:end if end != -1 else len(code)].strip()
            if line in self.NOT_GATES:
                continue
            if re.match(r"(\}\s*else\s+)?if\b", line):
                last = self.closing(code, code.index("{", found.end()))
                while re.match(r"\s*else\b", code[last + 1:]):
                    last = self.closing(code, code.index("{", last + 1))
                regions.append((start, last))
            elif re.match(r"guard\b", line):
                regions.append((start, self.closing(
                    code, self.enclosing(code, found.start()))))
            else:
                unknown.append(line)
        return regions, unknown

    def violations(self, text):
        """Every way `text`, a copy of the capture screen, breaks the rule.
        Empty when it keeps it."""
        code = self.code(text)
        regions, unknown = self.gates(code)
        problems = [f"unclassified use of the VoiceOver flag: {line!r}"
                    for line in unknown]
        gated = lambda offset: any(a <= offset <= b for a, b in regions)
        line_of = lambda offset: code.count("\n", 0, offset) + 1
        uses = lambda pattern: [
            found.start() for found in pattern.finditer(code)
            if not code[code.rfind("\n", 0, found.start()) + 1:found.start()]
            .strip().startswith("case")]

        finished = uses(self.FINISHED)
        if len(finished) != 1:
            problems.append(f"`.finishedByPerson` passed {len(finished)} times, "
                            f"at lines {[line_of(o) for o in finished]}; expected once")
        problems += [f"`.finishedByPerson` passed outside a VoiceOver gate at "
                     f"line {line_of(o)}" for o in finished if not gated(o)]

        declared = re.search(r"func armNoSpeechTimeout\(\)[^{]*\{", code)
        timer = ((declared.end() - 1, self.closing(code, declared.end() - 1))
                 if declared else (-1, -1))
        timeout = uses(self.TIMEOUT)
        if not timeout:
            problems.append("`.noSpeechTimeout` is passed nowhere")
        for offset in timeout:
            if gated(offset):
                problems.append(f"`.noSpeechTimeout` passed inside a VoiceOver "
                                f"gate at line {line_of(offset)}")
            if not timer[0] < offset < timer[1]:
                problems.append(f"`.noSpeechTimeout` passed outside "
                                f"`armNoSpeechTimeout` at line {line_of(offset)}")

        problems += [f"analytics call inside a VoiceOver gate at line "
                     f"{line_of(found.start())}"
                     for found in self.ANALYTICS.finditer(code)
                     if gated(found.start())]
        return problems

    def capture_view(self):
        return (self.ROOT / self.HOME).read_text(encoding="utf-8", errors="replace")

    def test_the_capture_screen_keeps_every_gate_silent(self):
        self.assertEqual(
            self.violations(self.capture_view()), [],
            "a VoiceOver-gated branch in CaptureView.swift can now send "
            "analytics, which says \"VoiceOver is on\" against a per-install id")

    def test_neither_ending_is_passed_anywhere_else(self):
        """`CaptureWordlessEnding` is internal, so another file could pass an
        ending without this class reading it. Test targets are not scanned:
        they drive the decision directly, which is what they are for."""
        elsewhere = []
        for top in self.SOURCES:
            for swift in sorted((self.ROOT / top).rglob("*.swift")):
                if swift.relative_to(self.ROOT) == self.HOME:
                    continue
                code = self.code(swift.read_text(encoding="utf-8", errors="replace"))
                if self.FINISHED.search(code) or self.TIMEOUT.search(code):
                    elsewhere.append(swift.relative_to(self.ROOT))
        self.assertEqual(elsewhere, [])

    def test_swapping_the_two_endings_is_caught(self):
        """The planted swap the grade describes: both call sites exchange
        their argument. Each one must be reported."""
        text = self.capture_view()
        swapped = (text.replace("endAttemptWithoutWords(.finishedByPerson)", "\0")
                   .replace("endAttemptWithoutWords(.noSpeechTimeout)",
                            "endAttemptWithoutWords(.finishedByPerson)")
                   .replace("\0", "endAttemptWithoutWords(.noSpeechTimeout)"))
        self.assertNotEqual(swapped, text)
        problems = self.violations(swapped)
        self.assertTrue(any("`.finishedByPerson` passed outside" in p for p in problems),
                        problems)
        self.assertTrue(any("`.noSpeechTimeout` passed inside" in p for p in problems),
                        problems)

    def test_the_scan_reads_each_gate_shape(self):
        """Falsifiers for the scan itself, on small sources: an event in an
        `if` gate, in its `else`, and after a `guard` gate is each caught; the
        same event outside any gate, or in a comment or a string, is not; an
        unlisted use of the flag is refused."""
        def reads(body):
            return self.violations(
                "func f() {\n" + body + "\n}\n"
                "func g() { endAttemptWithoutWords(.finishedByPerson) }\n"
                "private func armNoSpeechTimeout() {\n"
                "    endAttemptWithoutWords(.noSpeechTimeout)\n}\n")
        track = "SpeakItAnalytics.track(.x)"
        self.assertEqual(reads(track), ["`.finishedByPerson` passed outside a "
                                        "VoiceOver gate at line 4"])
        gate = "if accessibilityVoiceOverEnabled {\n  endAttemptWithoutWords(.finishedByPerson)\n"
        clean = lambda body: self.violations(
            "func f() {\n" + body + "\n}\n"
            "private func armNoSpeechTimeout() {\n"
            "    endAttemptWithoutWords(.noSpeechTimeout)\n}\n")
        self.assertEqual(clean(gate + "}\n" + track), [])
        self.assertEqual(clean(gate + "  // " + track + "\n  let s = \"" + track + "\"\n}"), [])
        self.assertEqual(len(clean(gate + "  " + track + "\n}")), 1)
        self.assertEqual(len(clean(gate + "} else {\n  " + track + "\n}")), 1)
        self.assertEqual(len(clean(
            "guard accessibilityVoiceOverEnabled else { return }\n"
            "endAttemptWithoutWords(.finishedByPerson)\n" + track)), 1)
        self.assertEqual(len(clean(gate + "}\nlet v = accessibilityVoiceOverEnabled")), 1)

    def test_there_is_something_to_check(self):
        """The screen still has the gates and the calls this class reads: the
        empty-finish gate and the listening-haptic `guard`, and analytics
        still sent through `SpeakItAnalytics.track`."""
        text = self.capture_view()
        code = self.code(text)
        regions, _ = self.gates(code)
        self.assertGreaterEqual(len(regions), 2)
        self.assertIn("endAttemptWithoutWords(.finishedByPerson)", code)
        self.assertIn("endAttemptWithoutWords(.noSpeechTimeout)", code)
        self.assertIn("SpeakItAnalytics.track(", code)
        service = (self.ROOT / "SpeakIt" / "App" / "AnalyticsService.swift").read_text(
            encoding="utf-8")
        self.assertIn("enum SpeakItAnalytics {", service)
        self.assertIn("static func track(_ event: SpeakItAnalyticsEvent)", service)


if __name__ == "__main__":
    unittest.main()
