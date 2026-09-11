"""Regression coverage for the evaluation instrument, independent of parser output."""
import collections
import csv
import io
import pathlib
import re
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
class RecordedLimitTests(unittest.TestCase):
    """A declined gap and an open one must not read the same in a report.

    `unfinished.tsv` scores recall at 34 of 57, and seven of its captures are a
    limit somebody already measured and wrote down: trailing preposition,
    conjunction and adverb were each tried as a class and removed, because
    "Meet Mike at" and "we're almost out" are the same tag shape and only one
    is unfinished. A reader triaging that table sees 23 misses and 23 reads as
    23 available. These tests hold the three rules that keep the mark from
    becoming a machine for excusing failures: it never changes a rate, its
    citation is verified rather than asserted, and it can only cover captures
    that are actually misses.
    """

    ROOT = pathlib.Path(__file__).resolve().parents[2]
    SET = pathlib.Path(__file__).parent / "devsets" / "unfinished.tsv"
    SCORER = pathlib.Path(__file__).parent / "devsets" / "unfinished-score.py"

    def setUp(self):
        if not self.SET.exists():
            self.skipTest("unfinished.tsv not present")

    def require_declarations(self):
        """Skip when the set declares no limit, rather than fail.

        Five of the six tests in this class used to go red the day every
        recorded limit was implemented and the declarations came off -- the
        good outcome. That is the same shape as a `KNOWN:` marker test
        asserting a marker still exists, and as a ranking fallback that seats
        an unrankable family where a perfect one goes: a check that cannot be
        satisfied by success. Measured rather than reasoned about, by running
        the class against a copy of the set with the header stripped.

        It cannot tell "every limit was implemented" from "somebody lost the
        header line" -- both are a file with no `# limit:` in it, the same
        ambiguity the generation check has between a legitimate generation and
        a quiet edit. So the one assertion that holds in both states stays
        live below rather than being skipped with the rest.
        """
        if not self.declarations():
            self.skipTest("no limit is declared, so there is nothing to check")

    def declarations(self):
        """Parsed here as data. The scorer's own parser is exercised by running
        it below; this is the citation check, which needs the repository."""
        out = []
        for line in self.SET.read_text().splitlines():
            if not line.startswith("# limit:"):
                continue
            source, phrase, ids = [f.strip() for f in
                                   line[len("# limit:"):].split("|")]
            out.append((source, phrase, ids.split()))
        return out

    def captures(self):
        rows = {}
        for line in self.SET.read_text().splitlines():
            if line.startswith("#") or not line.strip():
                continue
            parts = line.split("\t")
            if parts[0] == "id":
                continue
            rows[parts[0]] = parts
        return rows

    def score(self, text=None):
        """Run the real scorer against a probe that flags nothing.

        Every unfinished capture therefore misses, which is the state the
        disclosure has to survive: a limit must not improve the rate even when
        the rate is as bad as it can be.
        """
        with tempfile.TemporaryDirectory() as root:
            labels = pathlib.Path(root) / "unfinished.tsv"
            labels.write_text(text if text is not None else self.SET.read_text())
            probe = pathlib.Path(root) / "probe.txt"
            probe.write_text("\n".join(
                f'\u2500\u2500 "{row[1]}"\n  row title: X\n  route: Today\n'
                f'  state: complete\n  needsReview: false\n  due: nil\n'
                f'  remind: nil'
                for row in self.captures().values()) + "\n")
            return subprocess.check_output(
                [sys.executable, str(self.SCORER), str(labels), str(probe)],
                text=True)

    def test_a_declared_limit_cites_a_phrase_its_source_still_contains(self):
        """A limit cannot outlive the decision that made it.

        Implement the thing and delete the comment, and this fails until the
        declaration goes with it. Without this the citation is a claim of the
        kind this directory exists to stop making.
        """
        self.require_declarations()
        for source, phrase, _ in self.declarations():
            with self.subTest(source=source):
                path = self.ROOT / source
                self.assertTrue(path.exists(), f"{source} does not exist")
                self.assertIn(phrase, path.read_text(),
                              f"{source} no longer says {phrase!r}, so the "
                              f"limit it records may have been implemented")

    def test_every_declared_capture_exists_and_is_an_unfinished_one(self):
        """A declaration must not quietly cover a row that is not a miss."""
        #: Skipped rather than left to loop over nothing: a test that reports
        #: green having asserted nothing is the vacuous half of the same
        #: defect as one that reports red on the good outcome.
        self.require_declarations()
        rows = self.captures()
        for _, _, ids in self.declarations():
            for cid in ids:
                with self.subTest(capture=cid):
                    self.assertIn(cid, rows, f"{cid} is declared and absent")
                    self.assertEqual(rows[cid][3], "Incomplete",
                                     f"{cid} is declared a limit but is not an "
                                     f"unfinished capture")

    def test_a_limit_changes_the_reading_and_never_the_rate(self):
        """The rule that removes any incentive to declare one falsely."""
        self.require_declarations()
        with_limit = self.score()
        without = self.score("\n".join(
            line for line in self.SET.read_text().splitlines()
            if not line.startswith("# limit:")) + "\n")

        def recall(report):
            return next(l for l in report.splitlines() if "recall" in l)

        self.assertEqual(recall(with_limit), recall(without))
        self.assertIn("recorded design limits", with_limit)
        self.assertNotIn("recorded design limits", without)

    def test_the_report_names_the_captures_and_computes_no_ceiling(self):
        """The disclosure is a fact; a ceiling would be a forecast.

        The first draft printed "recall cannot pass 50/57". Two things were
        wrong with it. A ceiling is a denominator in waiting — once 50 is in
        the report, 34 of 50 is in the reader's head, and 68% is a nicer number
        than 59.6% that nobody earned, which is precisely what the never-change
        -a-rate rule exists to prevent. And it would be false: the source
        records that three *tagger classes* were tried and cost more than they
        recovered, which is a statement about one signal. The app already
        measures the speaker's pauses and discards them; a boundary reading
        timings would not meet the same ambiguity. A recorded limit is a
        decision taken with the signals to hand, not a property of the
        language.
        """
        self.require_declarations()
        rows = self.captures()
        unfinished = sum(1 for r in rows.values() if r[3] == "Incomplete")
        declared = {c for _, _, ids in self.declarations() for c in ids}
        report = self.score()
        self.assertIn(f"{len(declared)} of the {unfinished} unfinished", report)
        for cid in sorted(declared):
            with self.subTest(capture=cid):
                self.assertIn(cid, report)
        self.assertNotIn(f"{unfinished - len(declared)}/{unfinished}", report)
        self.assertNotIn("ceiling", report)

    def test_the_family_row_says_how_much_of_it_is_declined(self):
        """The table is what gets quoted, so the mark has to be on the row.

        A family that is mostly declined reads as the largest available win
        from the table alone.
        """
        self.require_declarations()
        line = next(l for l in self.score().splitlines()
                    if l.startswith("trailing-function-word"))
        self.assertIn("recorded as a limit", line)

    def test_the_trailing_determiner_capture_is_deliberately_not_declared(self):
        """INC45 is "I need to talk to Sarah about the".

        The cited comment covers preposition, conjunction and adverb; a
        trailing determiner is none of those and the code below it handles
        determiners separately. Sweeping it in would be a label standing in for
        the judgement it approximates. Pinned so that widening the declaration
        has to argue with this rather than happen quietly.
        """
        rows = self.captures()
        declared = {c for _, _, ids in self.declarations() for c in ids}
        family = {cid for cid, r in rows.items()
                  if r[2] == "trailing-function-word"}
        #: Deliberately not behind `require_declarations`. "INC45 is never
        #: declared" is true whether or not anything else is, so this is the
        #: assertion that survives the state the others skip -- otherwise the
        #: whole class goes quiet on a lost header line and nothing notices.
        self.assertNotIn("INC45", declared,
                         "INC45 ends on a determiner, which the cited comment "
                         "does not cover")
        self.assertIn("dangling article", rows["INC45"][4])
        if declared:
            self.assertEqual(sorted(family - declared), ["INC45"])


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

    def run_scorer(self, scorer, header, rows, blocks, *flags):
        with tempfile.TemporaryDirectory() as root:
            labels = pathlib.Path(root) / "set.tsv"
            labels.write_text(header + "".join(rows))
            probe = pathlib.Path(root) / "probe.txt"
            probe.write_text("".join(blocks))
            done = subprocess.run(
                [sys.executable, str(self.DEV / scorer), str(labels), str(probe),
                 *flags],
                capture_output=True, text=True)
            return done.returncode, done.stdout

    #: The probe prints one block per capture. Only the fields each scorer
    #: reads are written, so a test that passes for the wrong reason has to get
    #: past the real parser rather than a stub of it.
    def unfinished_block(self, utt, gap=False, due="nil", remind="nil",
                         rows=1, operation=None, review=False):
        out = f'\u2500\u2500 "{utt}"\n'
        for _ in range(rows):
            out += f"  row title: X\n  route: Today\n  due: {due}\n  remind: {remind}\n"
        out += f"  state: {'incomplete gap=incompleteThought' if gap else 'complete'}\n"
        out += f"  needsReview: {'true' if review else 'false'}\n"
        if operation:
            out += f"  operation: {operation}\n"
        return out

    def unfinished(self, rows, blocks, *flags):
        return self.run_scorer(
            "unfinished-score.py",
            "id\tutterance\tfamily\texpectation\tnote\n", rows, blocks, *flags)

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

    def test_a_flagged_capture_dated_anyway_is_the_guard_failing(self):
        """The half of `unsafe` that is harm on the path meant to prevent it.

        The app decided this fragment was unfinished and attached a date to it
        regardless, so something ran and let the commitment past.
        """
        code, report = self.unfinished(
            ["A\tone\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=True, due="2026-08-04")])
        self.assertIn("date/reminder/operation   1", report)
        self.assertIn("recognised, and committed anyway  1", report)
        self.assertIn("never recognised at all           0", report)
        self.assertEqual(code, 1, "a guard letting a commitment through gates")

    def test_a_capture_never_flagged_is_the_recall_miss_showing_through(self):
        """The other half, and the shape both real ones turned out to be.

        Nothing decided this was unfinished, so nothing was ever asked to
        withhold the date. It is the recall miss with a date attached, and it
        goes when recall goes -- there is no guard here to write. `INC33
        Tomorrow I want` is this, one trailing `to` away from `INC01 Tomorrow
        I want to`, which is flagged and not unsafe.
        """
        code, report = self.unfinished(
            ["A\tone\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=False, due="2026-08-04")])
        self.assertIn("date/reminder/operation   1", report)
        self.assertIn("recognised, and committed anyway  0", report)
        self.assertIn("never recognised at all           1", report)
        self.assertEqual(code, 0, "gating this blocks on a number recall owns")

    def test_the_split_prints_on_a_clean_run(self):
        """A line that shows up only when it is non-zero is not evidence.

        Same reasoning as `scored N of M labelled` printing when N == M: a
        reader of a quiet run has to be able to tell the split was computed.
        """
        _, report = self.unfinished(
            ["A\tone\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=True)])
        self.assertIn("date/reminder/operation   0", report)
        self.assertIn("recognised, and committed anyway  0", report)
        self.assertIn("never recognised at all           0", report)

    def test_the_split_does_not_move_the_total_it_splits(self):
        """A breakdown that changed its own subject would be worth nothing.

        One of each: the total stays 2 and the two halves account for it.
        """
        _, report = self.unfinished(
            ["A\tone\tf\tIncomplete\t\n", "B\ttwo\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=True, due="2026-08-04"),
             self.unfinished_block("two", gap=False, due="2026-08-04")])
        self.assertIn("date/reminder/operation   2", report)
        self.assertIn("recognised, and committed anyway  1", report)
        self.assertIn("never recognised at all           1", report)

    def test_an_abandoned_capture_splits_on_handled_not_on_flagged(self):
        """This branch's recall test is wider than `flagged`.

        A withdrawal the app acted on is handled too, so asking `flagged` here
        would file a handled-and-dated capture under "never recognised" and
        hide the guard failure this split exists to surface.
        """
        #: Handled but *not* flagged, which is the only shape that separates
        #: `handled` from `flagged`. A fixture where both are true passes
        #: either way -- the first draft of this test used one, and a mutation
        #: swapping `handled` for `flagged` went unnoticed until it was
        #: measured. A guard tested only where its two candidates agree is not
        #: tested at all.
        code, report = self.unfinished(
            ["A\tone\tf\tAbandoned\t\n"],
            [self.unfinished_block("one", gap=False, review=True,
                                   due="2026-08-04")])
        self.assertIn("date/reminder/operation   1", report)
        self.assertIn("recognised, and committed anyway  1", report)
        self.assertIn("never recognised at all           0", report)
        self.assertEqual(code, 1)

    def test_an_unseen_row_still_gates_beside_the_new_condition(self):
        """The condition grew; it did not get replaced.

        Both halves of the exit status have to survive the other being added,
        and a scorer that stopped failing on a dropped row would have traded
        one silent failure for another.
        """
        code, report = self.unfinished(
            ["A\tone\tf\tIncomplete\t\n", "B\tmissing\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=True)])
        self.assertIn("1 of 2 labelled", report)
        self.assertIn("recognised, and committed anyway  0", report)
        self.assertEqual(code, 1, "a dropped row gates on its own")

    def test_a_capture_the_probe_never_saw_is_visible_in_the_report(self):
        """The exclusion was never the property worth pinning.

        The old version of this test asserted `scored 1` and `recall 1/1` on a
        set of two labelled rows, and its docstring said that was what stopped
        "a truncated probe run reading as a set that got easier". It was not:
        dropping the row from the denominator *is* a set that got easier. The
        rate really is over what survived, and the only defence is that the
        report says so and the run fails. That is what this pins now.
        """
        status, report = self.unfinished(
            ["A\tone\tf\tIncomplete\t\n", "B\tmissing\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=True)])
        self.assertIn("1 of 2 labelled", report)
        self.assertIn("1 with no probe result", report)
        self.assertIn("recall   unfinished flagged   1/1", report)
        self.assertEqual(status, 1, "a dropped row must fail the run")

    def test_a_complete_run_says_the_denominator_reconciles(self):
        """Both numbers print even when they agree -- that is the check.

        A scorer here drops an unseen row instead of failing it, so the
        denominator matching the label count is the only evidence anyone gets
        that nothing was lost between the label file and the probe run. A
        line that appears only on failure cannot be that evidence.
        """
        status, report = self.unfinished(
            ["A\tone\tf\tIncomplete\t\n", "B\ttwo\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=True),
             self.unfinished_block("two", gap=True)])
        self.assertIn("2 of 2 labelled", report)
        self.assertNotIn("no probe result", report)
        self.assertEqual(status, 0)

    def test_the_report_names_which_capture_went_missing(self):
        """A count says one is gone; only the id says which.

        Found by mutation: deleting the miss entirely left every assertion
        above still passing, because they all read the summary line.
        """
        _, report = self.unfinished(
            ["A\tone\tf\tIncomplete\t\n", "ZQ07\tvanished line\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=True)], "--verbose")
        self.assertIn("UNSEEN", report)
        self.assertIn("ZQ07", report)
        self.assertIn("vanished line", report)

    def test_the_abandonment_scorer_reconciles_on_a_clean_run_too(self):
        """The branch a mismatch never reaches.

        Also found by mutation: every other assertion here builds a set with
        a row missing, so nothing covered what the line says when nothing is.
        """
        status, report = self.abandonment(
            ["A\tone\tf\tAbandoned\t\n", "B\ttwo\tf\tAbandoned\t\n"],
            [self.abandonment_block("one", rows=0),
             self.abandonment_block("two", rows=0)])
        self.assertIn("2 of 2 labelled", report)
        self.assertNotIn("no probe result", report)
        self.assertEqual(status, 0)

    def test_the_abandonment_scorer_prints_it_too_and_not_only_in_verbose(self):
        """It counted and gated on this, and never printed it.

        `language-metrics.sh` never passes `--verbose`, so on the report every
        published figure comes from, a dropped row was as silent here as in
        the other scorer.
        """
        status, report = self.abandonment(
            ["A\tone\tf\tAbandoned\t\n", "B\tmissing\tf\tAbandoned\t\n"],
            [self.abandonment_block("one", rows=0)])
        self.assertIn("1 of 2 labelled", report)
        self.assertIn("1 with no probe result", report)
        self.assertEqual(status, 1)

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

    def abandonment(self, rows, blocks, *flags):
        return self.run_scorer(
            "abandonment-score.py",
            "id\tutterance\tfamily\texpectation\tnote\n", rows, blocks, *flags)

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
        #: Skipped, not failed, when there are none left. `assertTrue(marked)`
        #: meant this test went red the day all four documented defects were
        #: fixed and the markers came off -- a test that cannot be satisfied
        #: by the good outcome, which is the same family as a fallback that
        #: makes an unrankable family look perfect. The assertion with teeth
        #: is the per-row one below: a marker must say why.
        if not marked:
            self.skipTest("no documented failure is declared any more")
        for row in marked:
            with self.subTest(capture=row[0]):
                reason = row[4][len("KNOWN:"):].strip()
                self.assertGreater(
                    len(reason), 20,
                    f"{row[0]} is marked KNOWN: without saying why, which is a "
                    f"suppression rather than a documented failure")




class RamblingPairingTests(unittest.TestCase):
    """The rambling set's headline is the GAP between twins, so the pairing is
    the instrument.

    `RB04C` and `RB04R` carry the same content, one written and one spoken, and
    the number worth reading is the difference between them. That only measures
    anything while both halves carry the same labels and differ only in how the
    content is said. Nothing here reads parser output: these are properties of
    the label file, so they hold on a Linux container, and they fail the moment
    somebody edits one side of a pair.
    """

    SET = pathlib.Path(__file__).parent / "devsets" / "rambling.tsv"

    #: Ids with no twin, declared rather than tolerated: a dropped row and a
    #: deliberate singleton are indistinguishable from here, and the failure
    #: mode of a silently tolerated singleton is a gap headline computed over
    #: fewer pairs than the reader thinks.
    UNPAIRED = {
        "RB25": "coherent-long, written as one long unrehearsed capture with "
                "no clean counterpart by design",
        "RB26": "coherent-long, same design",
        "RB27": "coherent-long, same design",
    }

    #: Pairs whose rambling half ends with its clean half word for word, split
    #: by WHY, because one of these is a property of the family and the other
    #: is a habit of whoever typed it, and a single flag over both gets quoted
    #: as whichever is convenient.
    #:
    #: A restart IS the speaker saying the whole thing again. A restart capture
    #: that did not end with the complete utterance would be the mislabelled
    #: one, so there is nothing here to fix.
    RESTART_ENDS_WITH_TWIN = {
        "RB09": "restart: 'send Yusuf the I mean send Yusuf the updated quote'",
        "RB10": "restart: 'book a table for book a table for six on Saturday'",
        "RB11": "restart: 'order the order the replacement filter for the furnace'",
    }

    #: A decision is different. The speaker weighs options and then states the
    #: outcome -- and in these four the outcome is phrased as the canonical
    #: sentence rather than as a person resolving a choice ('no, the bus').
    #: So "return the final clause" scores them correctly with no deliberation
    #: handling at all, which is the rate improving without the capability.
    #: Counted, not excused: these are the rows to rewrite, and the family is
    #: 4/4 clean to 1/4 rambling even WITH the answer handed over.
    DECISION_ENDS_WITH_TWIN = {
        "RB13": "decision resolves as 'take the bus to the airport on Sunday' verbatim",
        "RB14": "decision resolves as 'give Dimitri the blue chair' verbatim",
        "RB15": "decision resolves as 'cook the salmon on Thursday' verbatim",
        "RB16": "decision resolves as 'so book the afternoon session'",
    }

    @classmethod
    def rows(cls):
        body = cls.SET.read_text(encoding="utf-8")
        lines = [l for l in body.splitlines() if l and not l.startswith("#")]
        return list(csv.DictReader(io.StringIO("\n".join(lines)), delimiter="\t"))

    @staticmethod
    def flatten(text):
        return re.sub(r"[^a-z0-9 ]", " ", text.lower()).split()

    @classmethod
    def ends_with(cls, rambling, clean):
        """Whether the rambling half finishes with its clean twin word for word.

        A function with a fixture rather than an inline `endswith`, because an
        end-to-end test cannot check its own matcher: mutating the comparison
        and mutating the thing that would notice are the same edit. The last
        guard written in this repository shipped with a comparison that could
        never fire, and it was a mutation that found it, not a reading.
        """
        return cls.flatten(rambling)[-len(cls.flatten(clean)):] == cls.flatten(clean)

    def pairs(self):
        by = {r["id"]: r for r in self.rows()}
        for rid, row in sorted(by.items()):
            match = re.fullmatch(r"(RB\d+)C", rid)
            if match and match.group(1) + "R" in by:
                yield match.group(1), row, by[match.group(1) + "R"]

    def test_the_matcher_sees_a_trailing_twin_and_only_a_trailing_twin(self):
        self.assertTrue(self.ends_with("honestly the afternoon so book the session",
                                       "book the session"))
        self.assertTrue(self.ends_with("Book the Session.", "book the session"),
                        "case and punctuation must not hide a verbatim ending")
        self.assertFalse(self.ends_with("book the session and then go home",
                                        "book the session"),
                         "a twin in the middle is not a twin at the end")
        self.assertFalse(self.ends_with("book the", "book the session"))

    def test_every_capture_is_paired_or_declared_unpaired(self):
        by = {r["id"]: r for r in self.rows()}
        for rid in by:
            match = re.fullmatch(r"(RB\d+)([CR])", rid)
            with self.subTest(id=rid):
                if not match:
                    self.assertIn(rid, self.UNPAIRED,
                                  "a capture with no C/R suffix must say why")
                    continue
                twin = match.group(1) + ("R" if match.group(2) == "C" else "C")
                self.assertIn(twin, by, f"{rid} lost its twin; the gap headline "
                                        "is computed over pairs")
        for rid in self.UNPAIRED:
            with self.subTest(declared=rid):
                self.assertIn(rid, by, "a declared singleton that is gone must "
                                       "leave the list with it")
                self.assertNotIn(rid + "C", by,
                                 "a declared singleton that gained a twin is no "
                                 "longer a singleton")

    def test_twins_agree_on_destination_and_thought_count(self):
        """The one assertion that survives a relabel.

        Deliberately not pinned to literal counts: RB28 and RB30 were relabelled
        from 3 thoughts to 4 after they were written, and a test carrying the old
        number would have had to be edited to accept the correction -- which is
        the shape where a wrong label and a wrong test agree with each other.
        Agreement between halves holds whatever the right answer turns out to be.
        """
        for stem, clean, rambling in self.pairs():
            with self.subTest(pair=stem):
                self.assertEqual(clean["expected_destination"],
                                 rambling["expected_destination"],
                                 "a pair split across destinations measures "
                                 "routing, not rambling")
                self.assertEqual(clean["expected_thoughts"],
                                 rambling["expected_thoughts"],
                                 "a pair that disagrees on thought count has a "
                                 "gap built into its labels")

    def test_a_rambling_twin_ending_in_its_clean_twin_is_declared_and_reasoned(self):
        """Whether a trivial rule scores well here is part of the measurement.

        If the rambling half ends with the clean half word for word, "return the
        final clause" answers the pair with no structural recovery whatsoever.
        That is worth knowing about a set whose purpose is to show structural
        recovery failing.
        """
        documented = dict(self.RESTART_ENDS_WITH_TWIN, **self.DECISION_ENDS_WITH_TWIN)
        self.assertEqual(
            len(documented),
            len(self.RESTART_ENDS_WITH_TWIN) + len(self.DECISION_ENDS_WITH_TWIN),
            "an id in both lists is an id whose reason nobody has decided")

        found = [stem for stem, clean, rambling in self.pairs()
                 if self.ends_with(rambling["utterance"], clean["utterance"])]
        self.assertTrue(found, "the matcher found nothing at all, which on this "
                               "set means it stopped working")
        for stem in found:
            with self.subTest(pair=stem):
                self.assertIn(stem, documented,
                              "a new pair hands the answer to a trivial rule; "
                              "say which population it belongs to")
        for stem, reason in documented.items():
            with self.subTest(documented=stem):
                self.assertIn(stem, found,
                              "documented as ending with its twin and no longer "
                              "does; a list that outlives its rows is a list "
                              "nobody is reading")
                self.assertGreater(len(reason.strip()), 20,
                                   "a documented row needs the reason, not a mark")

    def test_the_two_populations_are_not_interchangeable(self):
        """A marker standing in for the judgement it approximates is the bug.

        Parking a decision row in the restart list would make an artefact look
        constitutive, which is the whole reason the two lists exist separately.
        """
        by = {r["id"]: r for r in self.rows()}
        for stem in self.RESTART_ENDS_WITH_TWIN:
            with self.subTest(restart=stem):
                self.assertIn("restart", by[stem + "R"]["family"])
        for stem in self.DECISION_ENDS_WITH_TWIN:
            with self.subTest(decision=stem):
                self.assertIn("decision", by[stem + "R"]["family"])

    def test_each_paired_family_has_the_same_number_of_halves(self):
        """A dropped row shows up as a family that is heavier on one side."""
        counts = collections.Counter(r["family"] for r in self.rows())
        for family, total in sorted(counts.items()):
            if not family.endswith("-clean"):
                continue
            other = family[: -len("-clean")] + "-rambling"
            with self.subTest(family=family):
                self.assertEqual(total, counts[other],
                                 f"{family} and {other} must stay matched")


class ControlPairTests(unittest.TestCase):
    """A guard family's rate, read against the thing it guards against.

    `runon.tsv` labels `bridging-guard` "do not split" and `statement-runon`
    "split here", and both are juxtaposed clauses with no connector. A parser
    with no boundary logic passes every guard row and fails every target row,
    so `bridging-guard 4/4` beside `statement-runon 0/6` is what the ABSENCE
    of the mechanism looks like -- and the family table sorts that 4/4 in
    among the healthy rows. Nobody is building bridging logic, so left alone
    it reads as coverage indefinitely.

    The rows stay counted. They are a real regression guard against an
    over-split; it is the reading that was wrong, not the data.
    """

    LABELS = ("G1\tguard one here\tbridging-guard\tMemory\t1\n"
              "G2\tguard two here\tbridging-guard\tMemory\t1\n"
              "T1\ttarget one here\tstatement-runon\tMemory\t2\n"
              "T2\ttarget two here\tstatement-runon\tMemory\t2\n")

    def block(self, utterance, rows):
        out = f'\u2500\u2500 "{utterance}"\n'
        return out + "  row title: X\n  route: Memory\n" * rows

    def score(self, labels, probe):
        with tempfile.TemporaryDirectory() as root:
            directory = pathlib.Path(root) / "devsets"
            directory.mkdir()
            cases = directory / "runon.tsv"
            cases.write_text("id\tutterance\tfamily\texpected_destination"
                             "\texpected_thoughts\n" + labels)
            output = directory / "probe.txt"
            output.write_text(probe)
            scorer = pathlib.Path(__file__).parent / "heldout" / "score.py"
            return subprocess.check_output(
                [sys.executable, str(scorer), str(cases), str(output)], text=True)

    def never_splits(self):
        return "".join(self.block(u, 1) for u in
                       ["guard one here", "guard two here",
                        "target one here", "target two here"])

    def test_a_guard_at_ceiling_beside_a_target_at_zero_is_not_a_pass(self):
        report = self.score(self.LABELS, self.never_splits())
        self.assertIn("NOT INFORMATIVE", report)
        self.assertIn("bridging-guard", report.split("CONTROL PAIRS")[1])

    def test_it_becomes_informative_the_moment_the_target_leaves_zero(self):
        """The marker has to retire itself, or it is a permanent excuse."""
        probe = (self.block("guard one here", 1) + self.block("guard two here", 1)
                 + self.block("target one here", 2) + self.block("target two here", 1))
        section = self.score(self.LABELS, probe).split("CONTROL PAIRS")[1]
        self.assertIn("informative", section)
        self.assertNotIn("NOT INFORMATIVE", section)

    def test_a_guard_that_is_not_at_ceiling_is_informative_on_its_own(self):
        """Zero on the target is not by itself the condition.

        A guard the parser fails somewhere is telling you something real about
        where it splits, whatever the target does -- so the verdict must turn
        on both halves, not on the target alone. Tested because a check whose
        two conditions always agree in the data is a check on one condition.
        """
        probe = (self.block("guard one here", 1) + self.block("guard two here", 2)
                 + self.block("target one here", 1) + self.block("target two here", 1))
        section = self.score(self.LABELS, probe).split("CONTROL PAIRS")[1]
        self.assertNotIn("NOT INFORMATIVE", section)

    def test_half_a_declared_pair_is_reported_rather_than_skipped(self):
        """A renamed family must not quietly remove the contrast.

        Printing nothing when one side is missing is how a declared pair stops
        being read: the section simply gets shorter and the guard goes back to
        being a healthy-looking row in the table above.
        """
        report = self.score("G1\tguard one here\tbridging-guard\tMemory\t1\n",
                            self.block("guard one here", 1))
        self.assertIn("is not in this set, so the other half is being read alone",
                      report)


class CorpusPathTests(unittest.TestCase):
    """Which files a scan is allowed to open, decided once rather than per scan.

    Both directions have now cost something. Too narrow: `leak-check.py` looped
    a list that did not contain `heldout.tsv`, and `devset-failures.sh` kept its
    own list of development sets, so `rambling.tsv` reached one runner and not
    the other. Too wide: a scan asking a question about readable material was
    pointed at every `*.tsv` here and printed a sealed capture into an agent's
    session.

    The repair is a total classification rather than a convention, because a
    shared list still silently omits a set nobody added to it.
    """

    def paths(self):
        sys.path.insert(0, str(pathlib.Path(__file__).parent))
        try:
            import corpus_paths
        finally:
            sys.path.pop(0)
        return corpus_paths

    def test_readable_and_sealed_share_nothing(self):
        paths = self.paths()
        self.assertFalse(set(paths.readable()) & set(paths.sealed()))

    def test_every_corpus_file_is_classified(self):
        """The guard that makes this more than a convention.

        A set nobody classified is a set every scan decides about on its own,
        which is the state this replaces.
        """
        stray = self.paths().unclassified()
        self.assertEqual(stray, [], "classify these in corpus_paths.py: "
                                    f"{[p.name for p in stray]}")

    def test_a_stray_corpus_file_is_actually_detected(self):
        """A check that treats absence as success cannot fail on addition."""
        paths = self.paths()
        with tempfile.TemporaryDirectory() as room:
            room = pathlib.Path(room)
            (room / "newset.tsv").write_text("id\tutterance\n", encoding="utf-8")
            found = [p.name for p in paths.unclassified(room)]
            self.assertIn("newset.tsv", found)

    def test_a_declared_file_that_is_gone_is_reported(self):
        """Deleting a corpus must not pass as quietly as adding one."""
        self.assertEqual(self.paths().missing(), [])

    def test_readable_refuses_a_sealed_path_even_if_the_list_is_wrong(self):
        """The seam, with a fixture on it.

        `readable()` filters its own output against `sealed()` rather than
        trusting whoever last edited the name list. Without a test reaching
        that filter, the two would have to disagree in the repository before
        anybody found out — and the whole point is that they never should.
        """
        paths = self.paths()
        original = paths.READABLE_NAMES
        try:
            paths.READABLE_NAMES = original | {"heldout/heldout.tsv"}
            self.assertNotIn("heldout.tsv",
                             [p.name for p in paths.readable()],
                             "a sealed path reached a caller asking for "
                             "readable material")
        finally:
            paths.READABLE_NAMES = original

    def test_the_sealed_list_is_the_three_sealed_sets(self):
        self.assertEqual(sorted(p.name for p in self.paths().sealed()),
                         ["adversarial.tsv", "everyday.tsv", "heldout.tsv"])


if __name__ == "__main__":
    unittest.main()
