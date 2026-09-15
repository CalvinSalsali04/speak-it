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
        edited = text.replace(f"| {largest:,} |", "| 1,111 |", 1)
        self.assertNotEqual(edited, text,
                            "the fixture edited nothing, so the tests below "
                            "check a document that is not stale")
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

    SNAPSHOT = (
        "The snapshot this section was written from, on 2026-09-15, was 5,501\n"
        "distinct utterances over 20 sources reducing to 17 bodies and 10 "
        "populations,\nof which 3,702 were the gating corpus")

    def section(self):
        text = self.bf.DOC.read_text(encoding="utf-8")
        start = text.index("## 2026-09-15 — twenty sources are ten "
                           "populations")
        return text[start:text.index("\n## ", start + 4)]

    def test_the_legacy_snapshot_is_present_and_unchanged(self):
        self.assertEqual(self.bf.DOC.read_text(encoding="utf-8")
                         .count(self.SNAPSHOT), 1)

    def test_no_surrounding_prose_restates_a_figure_the_block_owns(self):
        import re
        section = self.section()
        start, end = self.bf.marked_region(section)
        outside = (section[:start] + section[end:]).replace(self.SNAPSHOT, "")
        owned = {f"{value:,}" for value in self.figures.values()
                 if isinstance(value, int) and value > 99}
        owned |= {str(value) for value in self.figures.values()
                  if isinstance(value, int) and value > 99}
        found = sorted(figure for figure in owned
                       if re.search(rf"(?<![\d,]){re.escape(figure)}(?![\d,])",
                                    outside))
        self.assertEqual(
            found, [],
            "the prose around the generated block states a figure the block "
            "computes, so it will go stale the next time anybody adds a test "
            "string; say it once, inside the block")

    def test_the_sweep_would_notice(self):
        """An empty sweep and a clean one are the same output, and this
        section has been clean since the prose was reworded for it."""
        import re
        owned = f"{self.figures['distinct']:,}"
        self.assertTrue(re.search(rf"(?<![\d,]){re.escape(owned)}(?![\d,])",
                                  "a sentence saying " + owned))


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


if __name__ == "__main__":
    unittest.main()
