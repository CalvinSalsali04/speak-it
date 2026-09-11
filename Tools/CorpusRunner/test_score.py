"""Regression coverage for the evaluation instrument, independent of parser output."""
import pathlib
import subprocess
import sys
import tempfile
import unittest


class ScoreTests(unittest.TestCase):
    def score(self, labels, probe):
        with tempfile.TemporaryDirectory() as root:
            directory = pathlib.Path(root) / "devsets"
            directory.mkdir()
            cases = directory / "test.tsv"
            cases.write_text("id\tutterance\tfamily\texpected_destination\texpected_thoughts\n" + labels)
            output = directory / "probe.txt"
            output.write_text(probe)
            scorer = pathlib.Path(__file__).parent / "heldout" / "score.py"
            return subprocess.check_output(
                [sys.executable, str(scorer), str(cases), str(output), "--verbose"], text=True
            )

    def test_development_data_is_not_reported_as_held_out_and_missing_results_are_visible(self):
        result = self.score("A\tmissing words\tfamily\tMemory\t1\n", "")
        self.assertIn("DEVELOPMENT SET — 1 labelled utterances", result)
        self.assertIn("missing probe results      1", result)
        self.assertNotIn("HELD-OUT SET", result)

    def test_empty_ambiguous_capture_is_counted_as_content_loss(self):
        result = self.score(
            "A\tuncertain words\tfamily\tAmbiguous-preserve\t1\n",
            '── "uncertain words"\n',
        )
        self.assertIn("captures producing nothing 1", result)
        self.assertIn("EMPTY   A", result)
        self.assertIn("missing probe results      0", result)


class PerFamilyRankingTests(unittest.TestCase):
    """The per-family table is a triage list, so its order is a claim.

    Two things made that claim wrong. A family whose every capture is labelled
    unpinnable has no destination rate at all, and the ranking scored it 1.0 --
    seating it at the bottom of a table whose footer reads worst first, where a
    family that passes everything belongs. And ties broke alphabetically, so a
    rate over one capture sat wherever its name fell, including above a rate
    over twenty.
    """

    def score(self, labels, probe):
        with tempfile.TemporaryDirectory() as root:
            directory = pathlib.Path(root) / "devsets"
            directory.mkdir()
            cases = directory / "test.tsv"
            cases.write_text(
                "id\tutterance\tfamily\texpected_destination\texpected_thoughts\n"
                + labels)
            output = directory / "probe.txt"
            output.write_text(probe)
            scorer = pathlib.Path(__file__).parent / "heldout" / "score.py"
            return subprocess.check_output(
                [sys.executable, str(scorer), str(cases), str(output)], text=True)

    def rows(self, labels, probe):
        """(ranked families in order, not-ranked families in order)."""
        result = self.score(labels, probe)
        head, _, rest = result.partition("PER FAMILY")
        ranked_block, marker, unranked_block = rest.partition("NOT RANKED")

        def families(block):
            names = []
            for line in block.splitlines():
                first = line.split()[0] if line.split() else ""
                if first.startswith("fam-"):
                    names.append(first)
            return names

        return families(ranked_block), families(unranked_block) if marker else []

    #: One capture each, so `n` and the destination denominator agree except
    #: where a capture is unpinnable. Probe answers Today for everything, so a
    #: label of Memory is a miss and a label of Today is a hit.
    def probe_for(self, utterances, routes=None):
        routes = routes or {}
        return "\n".join(
            f'\u2500\u2500 "{u}"\n  row title: x\n  route: {routes.get(u, "Today")}'
            for u in utterances) + "\n"

    def test_a_family_with_no_scorable_destination_is_not_ranked(self):
        labels = ("A\tunpinnable\tfam-open\tAmbiguous-preserve\t1\n"
                  "B\tplain\tfam-plain\tToday\t1\n")
        ranked, unranked = self.rows(labels, self.probe_for(["unpinnable", "plain"]))
        self.assertEqual(ranked, ["fam-plain"])
        self.assertEqual(unranked, ["fam-open"])

    def test_an_unrankable_family_does_not_sort_as_if_it_passed_everything(self):
        """The regression itself: it used to land below a failing family."""
        labels = ("A\tunpinnable\tfam-open\tAmbiguous-preserve\t1\n"
                  "B\tmissed\tfam-broken\tMemory\t1\n")
        ranked, unranked = self.rows(labels, self.probe_for(["unpinnable", "missed"]))
        self.assertNotIn("fam-open", ranked)
        self.assertEqual(ranked, ["fam-broken"])

    def test_at_an_equal_rate_the_larger_denominator_ranks_first(self):
        """`fam-aaa` sorts first alphabetically and must still come second."""
        labels = ("A\tnarrow\tfam-aaa\tMemory\t1\n"
                  "B\twide one\tfam-zzz\tMemory\t1\n"
                  "C\twide two\tfam-zzz\tMemory\t1\n")
        ranked, _ = self.rows(
            labels, self.probe_for(["narrow", "wide one", "wide two"]))
        self.assertEqual(ranked, ["fam-zzz", "fam-aaa"])

    def test_the_not_ranked_block_is_absent_when_every_family_is_scorable(self):
        labels = "A\tplain\tfam-plain\tToday\t1\n"
        result = self.score(labels, self.probe_for(["plain"]))
        self.assertIn("PER FAMILY", result)
        self.assertNotIn("NOT RANKED", result)

    def test_the_destination_denominator_is_the_scorable_count_not_n(self):
        """Three captures carry the tag; one of them can be scored."""
        labels = ("A\tmissed\tfam-mixed\tMemory\t1\n"
                  "B\tunpinnable one\tfam-mixed\tAmbiguous-preserve\t1\n"
                  "C\tunpinnable two\tfam-mixed\tAmbiguous-preserve\t1\n")
        result = self.score(
            labels, self.probe_for(["missed", "unpinnable one", "unpinnable two"]))
        line = next(l for l in result.splitlines() if l.startswith("fam-mixed"))
        self.assertIn("0/1", line)
        self.assertNotIn("0/3", line)
        self.assertEqual(line.split()[1], "3")


class DevsetScorerTests(unittest.TestCase):
    """The two scorers nobody was checking.

    `34 of 57` and `24 of 24` have both been quoted at the owner of this
    project, and until now neither `unfinished-score.py` nor
    `abandonment-score.py` had a single test. These pin the arithmetic behind
    those numbers and the two judgements inside it that are easy to get
    backwards: a retraction on a capture the speaker withdrew is the app
    obeying, not inventing, and a documented failure is still a failure.
    """

    DEV = pathlib.Path(__file__).parent / "devsets"

    def run_scorer(self, scorer, header, rows, blocks):
        with tempfile.TemporaryDirectory() as root:
            labels = pathlib.Path(root) / "set.tsv"
            labels.write_text(header + "".join(rows))
            probe = pathlib.Path(root) / "probe.txt"
            probe.write_text("".join(blocks))
            done = subprocess.run(
                [sys.executable, str(self.DEV / scorer), str(labels), str(probe)],
                capture_output=True, text=True)
            return done.returncode, done.stdout

    #: The probe prints one block per capture. Only the fields each scorer
    #: reads are written, so a test that passes for the wrong reason has to get
    #: past the real parser rather than a stub of it.
    def unfinished_block(self, utt, gap=False, due="nil", remind="nil",
                         rows=1, operation=None):
        out = f'\u2500\u2500 "{utt}"\n'
        for _ in range(rows):
            out += f"  row title: X\n  route: Today\n  due: {due}\n  remind: {remind}\n"
        out += f"  state: {'incomplete gap=incompleteThought' if gap else 'complete'}\n"
        out += "  needsReview: false\n"
        if operation:
            out += f"  operation: {operation}\n"
        return out

    def unfinished(self, rows, blocks):
        return self.run_scorer(
            "unfinished-score.py",
            "id\tutterance\tfamily\texpectation\tnote\n", rows, blocks)

    def test_recall_counts_only_flagged_unfinished_captures(self):
        _, report = self.unfinished(
            ["A\tone\tf\tIncomplete\t\n", "B\ttwo\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=True),
             self.unfinished_block("two")])
        self.assertIn("recall   unfinished flagged   1/2", report)

    def test_fallout_counts_a_finished_capture_that_was_flagged(self):
        """The number the scorer itself calls the shipping decision."""
        _, report = self.unfinished(
            ["A\tone\tf\tComplete\t\n", "B\ttwo\tf\tComplete\t\n"],
            [self.unfinished_block("one", gap=True),
             self.unfinished_block("two")])
        self.assertIn("FALLOUT  finished misflagged  1/2", report)

    def test_a_withdrawal_is_not_an_invented_commitment(self):
        """"Never mind" producing a retraction is the app doing as it was told.

        Counting that as `unsafe` scores the correct behaviour as harm, and
        `unsafe` is the row that is supposed to only ever fall.
        """
        _, withdrawn = self.unfinished(
            ["A\tone\tf\tAbandoned\t\n"],
            [self.unfinished_block("one", rows=0, operation="retract target=x")])
        self.assertIn("date/reminder/operation   0", withdrawn)

        _, invented = self.unfinished(
            ["A\tone\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=True, due="2026-08-04")])
        self.assertIn("date/reminder/operation   1", invented)

    def test_a_capture_the_probe_never_saw_is_not_scored_as_anything(self):
        """Otherwise a truncated probe run reads as a set that got easier."""
        _, report = self.unfinished(
            ["A\tone\tf\tIncomplete\t\n", "B\tmissing\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=True)])
        self.assertIn("scored                        1", report)
        self.assertIn("recall   unfinished flagged   1/1", report)

    def test_a_mixed_capture_needs_the_finished_half_to_survive(self):
        _, one_row = self.unfinished(
            ["A\tone\tf\tMixed\t\n"], [self.unfinished_block("one", rows=1)])
        self.assertIn("mixed: finished half survives 0/1", one_row)
        _, two_rows = self.unfinished(
            ["A\tone\tf\tMixed\t\n"], [self.unfinished_block("one", rows=2)])
        self.assertIn("mixed: finished half survives 1/1", two_rows)

    def abandonment_block(self, utt, rows=1, title="X", titles=None,
                          retract=False, due="nil", remind="nil"):
        """`titles` gives each row its own, which is the case that matters.

        A Mixed capture can come back as two rows — the finished half and the
        withdrawn one — and that is the only shape where "is there a survivor"
        and "did the withdrawal leak" give different answers.
        """
        out = f'\u2500\u2500 "{utt}"\n'
        for row in (titles if titles is not None else [title] * rows):
            out += (f"  row title: {row}\n  route: Today\n"
                    f"  due: {due}\n  remind: {remind}\n")
        if retract:
            out += "  operation: retract target=x\n"
        return out

    def abandonment(self, rows, blocks):
        return self.run_scorer(
            "abandonment-score.py",
            "id\tutterance\tfamily\texpectation\tnote\n", rows, blocks)

    def test_a_documented_failure_is_still_counted_in_the_rate(self):
        """It used to be counted as a pass.

        A `KNOWN:` marker moved a failing row into the pass column, so a
        documented fallout of 1 printed as 0 — on the one number this scorer
        calls the shipping decision. The marker now moves the exit status.
        """
        #: A distinctive id, because the block that names the documented rows
        #: has to be shown to actually name them. Asserting on "A" would have
        #: matched the word "FALLOUT" and passed whatever the code did.
        _, report = self.abandonment(
            ["ZQ07\tone\tf\tKept\tKNOWN: pre-existing\n"],
            [self.abandonment_block("one", rows=0)])
        self.assertIn("FALLOUT  kept words withdrawn 1/1", report)
        self.assertIn("are documented (KNOWN:) and counted in the rates", report)
        self.assertIn("ZQ07", report.split("counted in the rates")[1])

    def test_the_exit_status_forgives_documented_and_not_new_failures(self):
        """The gate is where a marker may act, because the rate is quoted."""
        documented, _ = self.abandonment(
            ["A\tone\tf\tKept\tKNOWN: pre-existing\n"],
            [self.abandonment_block("one", rows=0)])
        self.assertEqual(documented, 0)

        fresh, _ = self.abandonment(
            ["A\tone\tf\tKept\t\n"],
            [self.abandonment_block("one", rows=0)])
        self.assertEqual(fresh, 1)

    def test_a_marker_on_a_row_that_now_passes_fails_the_run(self):
        """A suppression must not outlive the thing it suppressed.

        Left alone it silently forgives a defect that no longer exists, which
        is the same shape as a held-out limit that was implemented and never
        undeclared.
        """
        status, report = self.abandonment(
            ["A\tone\tf\tKept\tKNOWN: pre-existing\n"],
            [self.abandonment_block("one", rows=1)])
        self.assertEqual(status, 1)
        self.assertIn("now PASS — remove the marker", report)

    def test_a_withdrawn_half_left_in_a_title_fails_a_mixed_capture(self):
        """The finished half must survive *alone*.

        A row titled "never mind, buy milk" is the withdrawal becoming the
        commitment, which reads as a pass on row count alone.
        """
        _, leaked = self.abandonment(
            ["A\tone\tf\tMixed\t\n"],
            [self.abandonment_block("one", title="never mind buy milk")])
        self.assertIn("mixed: finished half survives 0/1", leaked)
        _, clean = self.abandonment(
            ["A\tone\tf\tMixed\t\n"],
            [self.abandonment_block("one", title="buy milk")])
        self.assertIn("mixed: finished half survives 1/1", clean)

    def test_a_surviving_half_does_not_excuse_the_withdrawn_one(self):
        """Two rows: the finished half kept, and the withdrawal kept beside it.

        "Is there a survivor" says yes and the capture still failed, because
        the thing the speaker took back came back as a row of its own. This is
        the only shape where the two checks disagree, so without it the leak
        check is covered by nothing — which is how it was, until a mutation
        removing it broke no test.
        """
        _, both = self.abandonment(
            ["A\tone\tf\tMixed\t\n"],
            [self.abandonment_block("one", titles=["buy milk", "never mind"])])
        self.assertIn("mixed: finished half survives 0/1", both)

    def test_a_mixed_capture_that_produced_nothing_is_a_failure(self):
        """Both halves gone is the worst outcome, not a quiet one.

        Found by a mutation: dropping the "did anything come back" check broke
        no test, because every case written so far produced at least one row.
        """
        _, report = self.abandonment(
            ["A\tone\tf\tMixed\t\n"],
            [self.abandonment_block("one", rows=0)])
        self.assertIn("mixed: finished half survives 0/1", report)

    def test_a_mixed_capture_retracted_whole_is_a_failure(self):
        """The withdrawal took the finished half with it.

        Also found by a mutation. A retraction is the right answer to
        `Abandoned` and the wrong one here, and nothing separated the two.
        """
        _, report = self.abandonment(
            ["A\tone\tf\tMixed\t\n"],
            [self.abandonment_block("one", title="buy milk", retract=True)])
        self.assertIn("mixed: finished half survives 0/1", report)

    def test_the_committed_sets_declare_the_markers_the_report_names(self):
        """Real data: four rows carry a marker, and each says why."""
        path = self.DEV / "abandonment.tsv"
        if not path.exists():
            self.skipTest("abandonment.tsv not present")
        marked = [line.split("\t") for line in path.read_text().splitlines()
                  if "\tKNOWN:" in line]
        self.assertTrue(marked, "no documented failure is declared any more")
        for row in marked:
            with self.subTest(capture=row[0]):
                reason = row[4][len("KNOWN:"):].strip()
                self.assertGreater(
                    len(reason), 20,
                    f"{row[0]} is marked KNOWN: without saying why, which is a "
                    f"suppression rather than a documented failure")


if __name__ == "__main__":
    unittest.main()
