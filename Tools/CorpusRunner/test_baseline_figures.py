#!/usr/bin/env python3
"""Tests for the generated population block in `LANGUAGE_BASELINE.md`.

Two properties, and the second is the one that is easy to lose. First, the
committed block agrees with a fresh walk. Second, **the block is derived from
the walk rather than printed beside it** — a generator that emits a constant
string passes the first test forever, and a document nobody can tell is stale
is exactly what this change exists to remove. So most of what follows hands
the generator a doctored measurement and checks that the prose moves.

Run as a script, which is how CI runs it. Nothing below may be defined after
the runner at the bottom; `test_connective_census.py` sweeps for that.
"""
import importlib.util
import pathlib
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent


def load(name, filename):
    """Import a hyphenated or plain module from this directory by path."""
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FiguresCase(unittest.TestCase):
    """One walk of the tree, shared. Each test may doctor its own copy."""

    @classmethod
    def setUpClass(cls):
        cls.bf = load("baseline_figures", "baseline_figures.py")
        cls.texts = cls.bf.readable_material.source_texts()
        cls.figures = cls.bf.figures(texts=cls.texts)

    def flat(self, figures=None):
        """The block with its line wrapping removed.

        Every sentence here is wrapped to a column, so a phrase this file
        asserts on can be split across a newline at any time by a figure two
        words earlier changing width. Asserting on the wrapped text makes the
        test fail for a reason that has nothing to do with what it checks.
        """
        return " ".join(self.bf.block(
            self.figures if figures is None else figures).split())

    def doctored(self, **changes):
        figures = dict(self.figures)
        figures.update(changes)
        return figures


class TheCommittedBlockAgreesWithTheCorpus(FiguresCase):
    """The property the whole file exists for."""

    def test_the_document_carries_both_markers(self):
        """Without this the test below compares nothing and passes."""
        text = self.bf.DOC.read_text(encoding="utf-8")
        self.assertIn(self.bf.BEGIN, text)
        self.assertIn(self.bf.END, text)

    def test_the_committed_block_is_what_a_fresh_walk_produces(self):
        text = self.bf.DOC.read_text(encoding="utf-8")
        start, end = self.bf.marked_region(text)
        self.assertEqual(text[start:end], self.bf.block(self.figures),
                         "Docs/LANGUAGE_BASELINE.md disagrees with the "
                         "corpus; run baseline_figures.py --write")

    def test_the_block_is_not_empty(self):
        """A generator returning its two markers and nothing between them
        agrees with a document holding its two markers and nothing between
        them, and the section would then state nothing at all."""
        lines = self.bf.block(self.figures).splitlines()
        self.assertGreater(len(lines), 40)

    def test_the_check_reports_agreement_and_not_merely_absence(self):
        import contextlib
        import io
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.bf.main([]), 0)


class AMissingMarkerIsARefusal(FiguresCase):
    """The failure this instrument is most likely to die of.

    Deleting one comment would leave a document with figures in it and no
    check on them, and a guard that returns "nothing to compare" on that input
    is indistinguishable from no guard. Both halves are exercised, because a
    refusal on the begin marker says nothing about the end marker.
    """

    def test_no_begin_marker_refuses(self):
        with self.assertRaises(ValueError) as caught:
            self.bf.marked_region("text with " + self.bf.END)
        self.assertIn("missing its begin marker", str(caught.exception))

    def test_no_end_marker_refuses(self):
        """On the wording, not merely on the word.

        Asserting `"end" in message` passed a mutation that deleted this
        branch entirely: the out-of-order check below caught the same input
        and its message says "before its begin marker", which contains the
        word. A guard proved only by a substring of another guard's message
        is not proved.
        """
        with self.assertRaises(ValueError) as caught:
            self.bf.marked_region(self.bf.BEGIN + " text")
        self.assertIn("missing its end marker", str(caught.exception))

    def test_neither_marker_names_both(self):
        with self.assertRaises(ValueError) as caught:
            self.bf.marked_region("a document about something else")
        self.assertIn("begin and end", str(caught.exception))

    def test_the_markers_in_the_wrong_order_refuses(self):
        with self.assertRaises(ValueError) as caught:
            self.bf.marked_region(self.bf.END + "\n" + self.bf.BEGIN)
        self.assertIn("before its begin", str(caught.exception))

    def test_the_refusal_names_the_document(self):
        """A diagnostic that raises while formatting itself has happened
        three times in this directory; `shown` returns a Path, not a str."""
        with self.assertRaises(ValueError) as caught:
            self.bf.marked_region("")
        self.assertIn("LANGUAGE_BASELINE.md", str(caught.exception))


class TheProseMovesWhenTheMeasurementDoes(FiguresCase):
    """That the block is computed and not a constant with the right answer in.

    Each of these doctors one figure and reads the output. A test asserting
    only that `block()` returns a long string would pass against a generator
    that ignores its argument entirely.
    """

    def test_a_different_population_changes_every_share(self):
        moved = self.flat(self.doctored(distinct=9999))
        self.assertIn("9,999", moved)
        self.assertNotIn(f"share of {self.figures['distinct']:,}", moved)

    def test_a_different_body_count_changes_the_reduction_sentence(self):
        self.assertIn("reduce to 3 distinct bodies",
                      self.flat(self.doctored(bodies=3)))

    def test_the_headline_percentage_is_computed(self):
        figures = self.doctored(not_spoken=self.figures["distinct"])
        self.assertIn("100.0% of everything this project may read",
                      self.flat(figures))

    def test_a_population_row_comes_from_the_measurement(self):
        figures = self.doctored(
            populations=[(10, "`a.tsv`"), (5, "`b.tsv`")], shared=[])
        block = self.bf.block(figures)
        self.assertIn("| 10 |", block)  # a table row, so not flattened
        self.assertIn("`b.tsv`", block)
        for _, label in self.figures["populations"]:
            self.assertNotIn(label, block)


class TheClaimsAreConditionalOnTheirOwnFigures(FiguresCase):
    """Generated prose that would go on asserting something false.

    This is the defect the document had, reproduced one level up: a sentence
    saying two kinds "share nothing" is a claim, and a generator that prints
    it beside a non-zero count has automated the error rather than fixed it.
    """

    def test_share_nothing_is_claimed_only_when_they_share_nothing(self):
        self.assertIn("share nothing", self.flat())
        overlapping = self.flat(self.doctored(fixtures_and_generated=4))
        self.assertNotIn("share nothing", overlapping)
        self.assertIn("4 utterances are in both", overlapping)

    def test_the_other_pair_is_checked_too(self):
        """Two conditions joined by `and`; one of them alone is half a guard,
        and the half nobody exercises is the half that is wrong."""
        self.assertNotIn("share nothing",
                         self.flat(self.doctored(generated_and_spoken=1)))

    def test_the_double_count_sentence_drops_when_there_is_no_double_count(self):
        block = self.flat(self.doctored(
            overlap_in_two_sets=0, overlap_pairs=[],
            overlap_sum=self.figures["both"]))
        self.assertIn("which is the heading exactly", block)
        self.assertNotIn("against a heading of", block)

    def test_a_row_in_three_development_sets_is_rendered_not_raised(self):
        """Nothing stops an utterance sitting in three sets. The version that
        unpacked `(first, second)` would have raised on the day it did."""
        block = self.flat(self.doctored(
            overlap_pairs=[(("a", "b", "c"), 2)], overlap_in_two_sets=2))
        self.assertIn("two in `a` and `b` and `c`", block)

    def test_the_pairs_are_named_and_not_only_counted(self):
        """A reduction reporting "seven" without saying which seven is the
        finding this section is about, made one level smaller."""
        block = self.flat()
        for (first, second), _ in self.figures["overlap_pairs"]:
            self.assertIn(f"`{first}` and `{second}`", block)


class TheWalkRefusesRatherThanGeneratingZeroes(FiguresCase):
    """Every way the measurement can be empty and still look like a number."""

    def test_no_sources_refuses(self):
        with self.assertRaises(ValueError) as caught:
            self.bf.figures(texts={})
        self.assertIn("agrees with itself", str(caught.exception))

    def test_a_missing_kind_refuses(self):
        devsets = {path: texts for path, texts in self.texts.items()
                   if self.bf.kind_of(path) == self.bf.SPOKEN}
        with self.assertRaises(ValueError) as caught:
            self.bf.figures(texts=devsets)
        self.assertIn("fixtures", str(caught.exception))

    def test_every_source_is_classified(self):
        """Every source in the tree today falls in one of the three."""
        kinds = {self.bf.kind_of(path) for path in self.texts}
        self.assertEqual(kinds, {self.bf.FIXTURES, self.bf.GENERATED,
                                 self.bf.SPOKEN})

    def test_a_source_in_none_of_the_three_trees_refuses(self):
        """The half the test above cannot reach.

        `kind_of` used to end `return SPOKEN`, which made that test unable
        to fail and this refusal unreachable -- a corpus landing outside all
        three trees would have been counted as material that sounds like
        somebody talking, which is the figure this document is cited for.
        """
        self.assertIsNone(self.bf.kind_of(pathlib.Path("Tools/Elsewhere/x")))
        outside = dict(self.texts)
        outside[pathlib.Path("Tools/Elsewhere/x.tsv")] = frozenset({"hello"})
        with self.assertRaises(ValueError) as caught:
            self.bf.figures(texts=outside)
        self.assertIn("Tools/Elsewhere/x.tsv", str(caught.exception))

    def test_a_sibling_directory_is_refused_rather_than_absorbed(self):
        """The refusal above, for the paths that look like they belong.

        `kind_of` asked `GATING in str(path)`, so a tree whose name merely
        extends one of the three was filed as that one instead of refused.
        Which is the worst version of the catch-all rather than a weaker one:
        `devsets2` classified as **spoken**, the same wrong direction, and
        reachable by a plausible new directory rather than by nothing.

        Unreachable today -- `readers()` cannot yield such a path -- so it is
        pinned here or it is not pinned anywhere, and the fix would have been
        free to rot straight back to a substring. This is also `corpus_paths`'
        bug from #80 in code written after #80 landed, which is why the test
        names all three rather than the one that was found.
        """
        for name in ("Tools/SpeechLab2/x.jsonl",
                     "Tools/CorpusRunner/devsets2/x.tsv",
                     "SpeakItTestsExtra/x.swift"):
            with self.subTest(name):
                self.assertIsNone(self.bf.kind_of(self.bf.ROOT / name))

    def test_the_three_trees_themselves_still_classify(self):
        """The control for the test above: a refusal that refuses everything
        would pass it, and `test_every_source_is_classified` reaches only the
        paths `readers()` happens to yield today."""
        for name, kind in (("SpeakItTests/x.swift", self.bf.FIXTURES),
                           ("Tools/SpeechLab/x.jsonl", self.bf.GENERATED),
                           ("Tools/CorpusRunner/devsets/x.tsv",
                            self.bf.SPOKEN)):
            with self.subTest(name):
                self.assertEqual(self.bf.kind_of(self.bf.ROOT / name), kind)

    def test_a_development_set_that_yields_nothing_refuses(self):
        """A reader that has quietly stopped reading, rather than a row of
        zeroes. `census()` says this about its own walk; this one does not go
        through `census()`, so it has to say it itself."""
        empty = dict(self.texts)
        devset = next(path for path in empty
                      if self.bf.kind_of(path) == self.bf.SPOKEN)
        empty[devset] = frozenset()
        with self.assertRaises(ValueError) as caught:
            self.bf.figures(texts=empty)
        self.assertIn("yielded no utterances", str(caught.exception))

    def test_the_three_kinds_cover_the_population(self):
        figures = self.figures
        self.assertEqual(
            figures["fixtures_only"] + figures["generated"]
            + figures["spoken_only"] + figures["both"], figures["distinct"])


class WritingIsTheOnlyWayToFixAStaleDocument(FiguresCase):
    """`--write` round-trips, and the check fails before it runs.

    Both directions on a copy, never on the committed file. A round-trip test
    that only writes cannot tell a working rewrite from one that erases the
    region and reports success.
    """

    def quietly(self, argv):
        """`main` prints; a test suite that prints its fixtures hides its own
        failures in the noise."""
        import contextlib
        import io
        with contextlib.redirect_stdout(io.StringIO()) as out:
            code = self.bf.main(argv)
        self.last_output = out.getvalue()
        return code

    def setUp(self):
        import tempfile
        self.original = self.bf.DOC
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        copy = pathlib.Path(self.tmp.name) / "LANGUAGE_BASELINE.md"
        copy.write_text(self.original.read_text(encoding="utf-8"),
                        encoding="utf-8")
        self.bf.DOC = copy
        self.addCleanup(setattr, self.bf, "DOC", self.original)
        self.copy = copy
        #: Bring the copy current before each test, so this class measures the
        #: write mechanism and not the committed document's state. Without it
        #: a stale baseline fails three tests here as well as the one that
        #: owns that finding, and four failures for one cause is a report
        #: nobody reads past.
        self.quietly(["--write"])

    def stale(self):
        """Edit the copy the way a person would, and prove the edit landed.

        The first version substituted the literal `| 3,702 |`. That was the
        gating-corpus row when it was written; #79 moved it to 3,745, the
        substitution became a no-op, and the three tests below started
        asserting things about a document nobody had made stale -- one of
        which then failed and one of which would have passed forever. A
        fixture built from a figure that moves is the same defect as a
        document built from one.
        """
        text = self.copy.read_text(encoding="utf-8")
        largest = max(count for count, _ in self.figures["populations"])
        row = f"| {largest:,} |"
        edited = text.replace(row, "| 1,111 |", 1)
        # `assertNotEqual(edited, text)` says this and prints both documents to
        # say it: 283 KB of baseline for a one-line message. This file has a
        # `quietly()` because a suite that prints its fixtures hides its own
        # failures in the noise, and the failure path is where that costs most.
        #
        # Counting the row is the quiet form, and the first attempt at it was
        # **weaker** as well as quieter: `text.count(row) >= 1` passes a
        # substitution that finds the row and replaces it with itself, which is
        # the no-op this whole docstring is about. The difference of the two
        # counts is the property -- one occurrence went -- and it fails for
        # both causes, the row being absent and the replacement doing nothing.
        self.assertEqual(
            text.count(row) - edited.count(row), 1,
            f"the fixture edited nothing: it looked for {row!r} and the "
            f"document carries it {text.count(row)} time(s) before and "
            f"{edited.count(row)} after, so the tests below check a document "
            f"that is not stale")
        self.copy.write_text(edited, encoding="utf-8")

    def test_a_stale_document_fails_the_check(self):
        self.stale()
        self.assertEqual(self.quietly([]), 1)

    def test_write_repairs_it(self):
        self.stale()
        self.assertEqual(self.quietly(["--write"]), 0)
        self.assertEqual(self.quietly([]), 0)

    def test_write_keeps_everything_outside_the_region(self):
        before = self.copy.read_text(encoding="utf-8")
        self.stale()
        self.quietly(["--write"])
        after = self.copy.read_text(encoding="utf-8")
        start, end = self.bf.marked_region(before)
        self.assertEqual(after[:start], before[:start])
        self.assertEqual(after[end - len(before):] if False else
                         after[after.index(self.bf.END):],
                         before[before.index(self.bf.END):])

    def test_a_document_with_no_region_refuses_rather_than_writing(self):
        self.copy.write_text("nothing to see here", encoding="utf-8")
        self.assertEqual(self.quietly(["--write"]), 2)
        self.assertEqual(self.copy.read_text(encoding="utf-8"),
                         "nothing to see here")


class NoFigureOutsideTheBlockRestatesOneInsideIt(FiguresCase):
    """The limit of every marked figure, closed for this section.

    A generated block cannot stop somebody writing 5,501 into the paragraph
    below it, and that sentence then goes stale exactly as before. So the
    surrounding prose is swept: no number the block owns may appear in it.

    The one exception is deliberate and is pinned verbatim below — the
    section is dated, and a regeneration that silently restated what it
    originally said would be its own defect. That sentence is the legacy
    record, it is expected never to change, and the test fails if it does.
    """

    #: The legacy sentence, as words rather than as laid out. It used to be
    #: pinned as an exact three-line string with the hard newlines in it, so a
    #: reflow that changed nothing anybody means would fail as a count
    #: mismatch — a failure whose message cannot be read as "somebody rewrapped
    #: a paragraph". Matching whitespace-insensitively keeps the guarantee that
    #: matters (these words and these figures, unchanged) and drops the trap.
    SNAPSHOT = ("The snapshot this section was written from, on 2026-09-15, "
                "was 5,501 distinct utterances over 20 sources reducing to 17 "
                "bodies and 10 populations, of which 3,702 were the gating "
                "corpus")

    def snapshot_pattern(self):
        import re
        return re.compile(r"\s+".join(
            re.escape(word) for word in self.SNAPSHOT.split()))

    def section(self):
        text = self.bf.DOC.read_text(encoding="utf-8")
        start = text.index("## 2026-09-15 — twenty sources are ten "
                           "populations")
        return text[start:text.index("\n## ", start + 4)]

    def test_the_legacy_snapshot_is_present_and_unchanged(self):
        """Calvin's rule: old numbers stay visible and marked legacy rather
        than being silently rewritten. So the one place this document states
        the superseded figures is pinned, and `--write` must never reach it."""
        found = self.snapshot_pattern().findall(
            self.bf.DOC.read_text(encoding="utf-8"))
        self.assertEqual(
            len(found), 1,
            "the dated snapshot above the block is the legacy record and is "
            "expected never to change; regenerate the block, not the sentence "
            "saying what it used to say")

    def owned(self):
        """Every figure the block computes, in both spellings prose uses.

        Hoisted out of the sweep so that the canary below tests the set the
        sweep is actually built from. It was a local, and the canary built a
        one-element stand-in of its own — so `owned = set()` in the sweep swept
        nothing, found nothing, and the whole suite stayed green. That is the
        `kind_of` catch-all again, in the test file, in the same change: a
        coverage check that cannot fire looks exactly like one that finds
        nothing to report.
        """
        numbers = [value for value in self.figures.values()
                   if isinstance(value, int) and value > 99]
        return ({f"{value:,}" for value in numbers}
                | {str(value) for value in numbers})

    def restated_in(self, prose):
        """Every owned figure `prose` states, by the sweep's own matching.

        One implementation for the real sweep and the canary. Two copies would
        let the canary keep passing over a sweep whose matching had been
        changed underneath it, which is the half of this that already failed.
        """
        import re
        return sorted(figure for figure in self.owned()
                      if re.search(rf"(?<![\d,]){re.escape(figure)}(?![\d,])",
                                   prose))

    def test_no_surrounding_prose_restates_a_figure_the_block_owns(self):
        section = self.section()
        start, end = self.bf.marked_region(section)
        outside = self.snapshot_pattern().sub(
            "", section[:start] + section[end:], count=1)
        self.assertEqual(
            self.restated_in(outside), [],
            "the prose around the generated block states a figure the block "
            "computes, so it will go stale the next time anybody adds a test "
            "string; say it once, inside the block")

    def test_the_sweep_would_notice(self):
        """Plant an owned figure in prose and watch the sweep return it.

        A clean sweep and a sweep over an empty set print the same result, so
        the test above passes either way and this is the only thing standing
        between them. It has to run the real `owned()` and the real matching
        to say anything: the first version asserted a regex against a string
        it wrote itself, which left the set unguarded.
        """
        owned = self.owned()
        self.assertGreaterEqual(
            len(owned), 8,
            f"the sweep owns {len(owned)} figures, so it cannot find one and "
            f"the sweep above reports clean for a document it never read")
        headline = f"{self.figures['distinct']:,}"
        self.assertIn(headline, owned)
        self.assertIn(
            headline,
            self.restated_in(f"the readable population is {headline} "
                             f"distinct utterances."),
            "the sweep did not find a figure it owns, stated plainly")


class TheDocumentSaysHowToRegenerateIt(FiguresCase):
    """A generated block nobody knows how to regenerate gets hand-edited,
    and the hand edit is then reverted by the next `--write` without
    anybody being told which of the two was right."""

    def test_the_command_is_in_the_document(self):
        text = self.bf.DOC.read_text(encoding="utf-8")
        self.assertIn("baseline_figures.py --write", text)

    def test_the_command_in_the_document_is_the_real_path(self):
        text = self.bf.DOC.read_text(encoding="utf-8")
        import re
        quoted = re.findall(r"`python3 (\S+baseline_figures\.py) --write`",
                            text)
        self.assertTrue(quoted)
        for path in quoted:
            self.assertTrue((self.bf.ROOT / path).exists(), path)


class APerFamilyScoreCannotOutliveItsPopulation(FiguresCase):
    """A per-family row cites the population it was measured over, in brackets.

    The generated block fixed the figures nothing recomputed. It does not
    reach the per-family gap tables, which are dated run records and are
    deliberately left alone -- rewriting a run record is the thing #83 argues
    against. But a run record that reads as current is a stale figure whoever
    wrote it, and `| restart (4) |` says four pairs while `rambling.tsv` now
    holds six.

    So the bracket is checked rather than the score. Which sets are twinned,
    which families they carry and how many pairs each holds are all recomputed
    from the `family` column, and a row is matched to its set by its label
    being a twinned family name -- never by a line range, a file name or a
    declared list, all three of which go stale the same way the figure did.
    """

    def setUp(self):
        self.twinned = self.bf.twinned_families()

    def test_the_sets_that_are_twinned_are_read_from_the_data(self):
        """Without this the checks below could be looking at nothing.

        `coherent-long` is the case that makes the derivation worth having: it
        is eleven rows of `rambling.tsv` and it is NOT twinned, because it is
        the guard family that must stay one row however long it gets. A
        declared list of families would have to remember that; reading the
        `family` column cannot forget it.
        """
        self.assertEqual(
            sorted(self.twinned), ["Tools/CorpusRunner/devsets/rambling.tsv"])
        families = self.twinned["Tools/CorpusRunner/devsets/rambling.tsv"]
        self.assertNotIn("coherent-long", families,
                         "the guard family has become twinned, or the "
                         "derivation has started counting untwinned rows")
        self.assertGreater(len(families), 4)

    def test_an_unpaired_twin_refuses_rather_than_reporting_a_count(self):
        """A half-count is not a small error in a gap measurement.

        A gap between twins needs two twins. If a family gains a clean row
        with no spoken one, every score across it is measuring something else,
        and a count reported for it would read exactly like a sound one.
        """
        path = pathlib.Path(self.bf.ROOT, "Tools/CorpusRunner/devsets/rambling.tsv")
        with tempfile.TemporaryDirectory() as tmp:
            copy = pathlib.Path(tmp) / "rambling.tsv"
            text = path.read_text(encoding="utf-8")
            self.assertIn("restart-clean", text, "the fixture's anchor is stale")
            copy.write_text(text + "RB99C\tan added clean row with no twin\t"
                                   "restart-clean\tToday\t1\n")
            with self.assertRaises(ValueError) as caught:
                self.bf.twinned_families(paths=[copy])
        self.assertIn("restart", str(caught.exception))
        self.assertIn("not a twinned family any more", str(caught.exception))

    def test_a_row_citing_the_wrong_population_is_reported(self):
        """Both directions on a document this test writes.

        A checker that reported everything, or nothing, would pass a
        one-directional test. So: the same family, one row with the count the
        data holds and one without.
        """
        twinned = {"x.tsv": {"restart": 6}}
        good = "| restart (6) | 4/4 \u2192 4/4 |"
        bad = "| restart (4) | 4/4 \u2192 4/4 |"
        self.assertEqual(
            self.bf.stale_family_rows(text=good, twinned=twinned), ([], []))
        self.assertEqual(
            self.bf.stale_family_rows(text=bad, twinned=twinned),
            ([("restart", 4, 6)], []))

    def test_a_twinned_family_with_no_row_at_all_is_reported(self):
        """The half a bracket check would never fail on.

        The table introduces itself as *the* per-family gaps. A family that
        exists in the set and has no row is a completeness claim that has
        stopped being true, and no amount of checking the rows that are there
        can see it -- which is how `deliberation-open` came to be two pairs
        that the table has never mentioned.
        """
        twinned = {"x.tsv": {"restart": 6, "deliberation-open": 2}}
        mismatched, unrowed = self.bf.stale_family_rows(
            text="| restart (6) | 4/4 |", twinned=twinned)
        self.assertEqual(mismatched, [])
        self.assertEqual(unrowed, [("deliberation-open", 2)])

    def test_a_set_level_row_is_not_mistaken_for_a_family(self):
        """`routed (116)` names a file, not a family, and is not this check's.

        The population block already generates the set-level figures. A
        checker that grabbed every `name (number)` row would report a
        disagreement here the moment the two counted different things -- and
        they do: 116 is `routed.tsv`'s row count and its distinct-utterance
        count is 114.
        """
        twinned = {"x.tsv": {"restart": 6}}
        self.assertEqual(
            self.bf.stale_family_rows(
                text="| routed (116) | destination | 74/84 |",
                twinned=twinned),
            ([], [("restart", 6)]))

    @unittest.expectedFailure
    def test_no_per_family_row_cites_a_population_the_set_no_longer_has(self):
        """KNOWN STALE, and the decorator is the record of it.

        `rambling.tsv` was 57 rows when the gap table was measured and is 85
        now. Four things are out of date and none can be fixed from Linux,
        because the scores themselves need a macOS run:

            restart            cited 4 pairs, the set holds 6
            decision           cited 4 pairs, the set holds 10
            deliberation-open  2 pairs, no row
            two-facts          2 pairs, no row

        Marked expected rather than fixed by hand, and marked here rather than
        as a sentence above the table, because a sentence recomputes nothing
        and goes stale the next time somebody adds ten rows -- which is the
        defect being recorded, one level up.

        **The decorator cannot be left behind.** `unittest` reports a passing
        expected-failure as an unexpected success and exits non-zero, so the
        run that refreshes this table fails until somebody removes this line.
        A marker that can only be too generous is the shape this codebase
        keeps getting caught by; this one fails in both directions.
        """
        mismatched, unrowed = self.bf.stale_family_rows()
        self.assertEqual((mismatched, unrowed), ([], []))

    def test_an_empty_result_is_a_refusal_and_not_a_clean_table(self):
        """The hole `TWIN_HALVES` being a declared word leaves open.

        The counterexample is asserted first, against the behaviour the
        refusal replaces, so it cannot quietly stop being a counterexample:
        with nothing twinned, `stale_family_rows` reports no stale row and no
        missing family -- the same answer it gives for a table that is
        genuinely up to date.

        **The fixture renames BOTH halves, and the first version of this test
        renamed one and proved nothing.** Renaming `-rambling` alone fires the
        unpaired refusal above instead, because `errand` is then 8 clean rows
        against 0 spoken ones. So does renaming `-clean` alone. The case that
        actually reaches this refusal is the set leaving the derivation whole,
        which is also what a renamed `family` column does.
        """
        self.assertEqual(
            self.bf.stale_family_rows(text=self.bf.DOC.read_text("utf-8"),
                                      twinned={}),
            ([], []),
            "an empty derivation no longer reads as a clean table, so this "
            "test has stopped demonstrating why the refusal below exists")

        path = pathlib.Path(self.bf.ROOT,
                            "Tools/CorpusRunner/devsets/rambling.tsv")
        text = path.read_text(encoding="utf-8")
        for half in self.bf.TWIN_HALVES:
            self.assertIn(f"-{half}\t", text, "the fixture's anchor is stale")
        renamed = text
        for half, other in zip(self.bf.TWIN_HALVES, ("plain", "spoken")):
            renamed = renamed.replace(f"-{half}\t", f"-{other}\t")
        with tempfile.TemporaryDirectory() as tmp:
            copy = pathlib.Path(tmp) / "rambling.tsv"
            copy.write_text(renamed)
            with self.assertRaises(ValueError) as caught:
                self.bf.twinned_families(paths=[copy])
        message = str(caught.exception)
        self.assertIn("reads as the tables being current", message)
        self.assertIn("TWIN_HALVES", message)

    def test_the_refusal_does_not_fire_on_the_sets_as_they_are(self):
        """The other direction, or a `raise` on every input would pass above.

        Both halves of the refusal are checked here rather than left to the
        rest of the class going green, because the rest of the class would go
        green against a fixture too.
        """
        self.assertIn("Tools/CorpusRunner/devsets/rambling.tsv",
                      self.bf.twinned_families())

    def test_a_bracket_far_from_any_gap_table_is_still_reported(self):
        """Deliberate, and pinned so that narrowing it has to argue with this.

        The scan reads the whole document, so a sentence anywhere that happens
        to hold `| long (5) |` is reported although it is nowhere near a gap
        table. Scoping it would mean naming the table by line range or by
        heading: the range goes stale exactly as the bracket does, and the
        heading is a spelling. A false report names a line somebody can look
        at in a second; a missed one is what this check was written for.
        """
        twinned = {"x.tsv": {"long": 3}}
        stray = "\n".join(["# Something else entirely"] + ["prose"] * 40
                           + ["| long (5) | unrelated |"])
        self.assertEqual(
            self.bf.stale_family_rows(text=stray, twinned=twinned),
            ([("long", 5, 3)], []))

    def test_the_known_staleness_is_exactly_what_is_recorded(self):
        """The expected failure above says which rows and by how much.

        Without this it says only "something is stale", and a fifth
        discrepancy could arrive with the suite still green and the docstring
        still naming four.
        """
        mismatched, unrowed = self.bf.stale_family_rows()
        self.assertEqual(mismatched, [("decision", 4, 10), ("restart", 4, 6)])
        self.assertEqual(unrowed, [("deliberation-open", 2), ("two-facts", 2)])


class ASectionRecordsTheSetStateItWasMeasuredOver(FiguresCase):
    """The half `stale_family_rows` cannot reach: a count written in prose.

    The bracket check reads `| restart (4) |`. The same section also calls
    `coherent-long` "those seven rows" where the set holds eleven, and no
    amount of parsing table brackets finds that sentence. A whole-set
    fingerprint does not find it either -- it fires on the same cause and
    names the set that moved, which is what sends somebody back to read the
    section rather than trusting it.

    Deliberately NOT a check on which sections ought to carry a fingerprint.
    Deciding that mechanically needs a heuristic for "does this section report
    a measurement", and the obvious one misfires: seventeen of this document's
    twenty-nine sections name a development set and contain a rate somewhere,
    including one whose only mention of `rambling.tsv` is a row in a source
    table. A heuristic standing in for that judgement is the defect this
    module exists to remove, so the judgement stays with whoever writes the
    section and only its consequence is mechanical.
    """

    def test_the_document_carries_at_least_one_fingerprint(self):
        """Otherwise every check below passes over nothing.

        A sweep with an empty population reports clean in the same voice as a
        sweep that found nothing wrong, which is this file's recurring bug and
        the reason `test_the_sweep_would_notice` exists twenty lines up.
        """
        found = self.bf.fingerprints()
        self.assertTrue(
            found,
            "no section records the set state it was measured over, so "
            "`stale_fingerprints` is checking nothing and will go on "
            "reporting clean however far the development sets drift")
        for name, rows in found:
            self.assertIn(name, self.bf.devset_rows(),
                          f"{name} is fingerprinted and is not a readable "
                          f"development set")
            self.assertGreater(rows, 0)

    def test_only_the_last_fingerprint_for_a_set_is_checked(self):
        """An earlier one is a record of a run that happened, not a stale claim.

        Two fingerprints for one set, the older disagreeing with the data and
        the newer agreeing. Only the newer decides. Without this the check
        would ask a dated record to change, which is what this document's own
        corrections argue against.
        """
        text = ("*Measured over `rambling.tsv` at 57 rows.* ... later ... "
                "*Measured over `rambling.tsv` at 85 rows.*")
        self.assertEqual(
            self.bf.stale_fingerprints(text=text, rows={"rambling.tsv": 85}),
            [])
        self.assertEqual(
            self.bf.stale_fingerprints(text=text, rows={"rambling.tsv": 90}),
            [("rambling.tsv", 85, 90)])

    def test_a_fingerprint_naming_a_set_that_is_gone_is_reported(self):
        """The direction a count comparison never fails on.

        A renamed or deleted development set leaves its fingerprint behind
        agreeing with nothing, and a checker that only compares numbers reads
        that as silence.
        """
        self.assertEqual(
            self.bf.stale_fingerprints(
                text="*Measured over `retired.tsv` at 12 rows.*",
                rows={"rambling.tsv": 85}),
            [("retired.tsv", 12, None)])

    def test_the_pattern_does_not_match_prose_about_fingerprints(self):
        """A sentence describing the convention is not a fingerprint.

        This docstring and the ones around it say the words; if the pattern
        were loose enough to match them, the document would fingerprint itself
        and the count above would be meaningless.
        """
        for prose in ("we should record what each run was measured over",
                      "Measured over rambling.tsv at 57 rows",
                      "*Measured over `rambling.tsv`.*"):
            with self.subTest(prose=prose):
                self.assertEqual(self.bf.fingerprints(text=prose), [])

    @unittest.expectedFailure
    def test_no_live_fingerprint_has_outlived_its_set(self):
        """KNOWN STALE, the same staleness the bracket check records.

        `rambling.tsv` was 57 rows when the 16:54 run read it and is 85 now.
        Two instruments now fail on that one cause, and they are not
        redundant: the bracket check names which family rows are wrong, and
        this names the set and the size of the drift, which is what covers
        the counts written in sentences. Both clear in the same macOS run,
        and the decorator cannot be left behind -- `unittest` reports a
        passing expected-failure as an unexpected success and exits non-zero.
        """
        self.assertEqual(self.bf.stale_fingerprints(), [])

    def test_the_known_drift_is_exactly_what_is_recorded(self):
        """So a second set cannot drift while the suite stays green."""
        self.assertEqual(self.bf.stale_fingerprints(),
                         [("rambling.tsv", 57, 85)])

    def test_two_sets_with_one_basename_are_refused_not_merged(self):
        """The key is a basename because the prose names a basename.

        Not a live defect and the test says so below: seven readable paths
        with seven distinct names. It is here because the failure mode is a
        plausible number and no error -- the dictionary would keep whichever
        path sorted last, and a fingerprint naming that name would be checked
        against one of the two sets with nothing recording which. The same
        collision, on `renderings.jsonl`, really happened one module over.

        Re-keying on the path is the wrong fix: the fingerprint has to name
        what the sentence names, and a repository path in an English sentence
        is worse than this refusal.
        """
        with tempfile.TemporaryDirectory() as tmp:
            first, second = pathlib.Path(tmp, "a"), pathlib.Path(tmp, "b")
            for where in (first, second):
                where.mkdir()
                (where / "twins.tsv").write_text("id\ttext\nX1\thello\n")
            with self.assertRaises(ValueError) as caught:
                self.bf.devset_rows(paths=[first / "twins.tsv",
                                           second / "twins.tsv"])
        self.assertIn("twins.tsv", str(caught.exception))
        self.assertIn("cannot say which one", str(caught.exception))

    def test_the_readable_sets_do_not_collide_today(self):
        """The other direction, or a `raise` on everything would pass above.

        This is also the assertion that makes the refusal above a guard for a
        case that does not exist rather than a fix for one that does.
        """
        paths = self.bf.corpus_paths.readable()
        self.assertEqual(len({path.name for path in paths}), len(paths))
        self.assertEqual(len(self.bf.devset_rows()), len(paths))


if __name__ == "__main__":
    unittest.main()
