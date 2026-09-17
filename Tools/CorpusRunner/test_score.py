"""Regression coverage for the evaluation instrument, independent of parser output."""
import ast
import collections
import contextlib
import csv
import io
import json
import os
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
        """The half of rule 3 that can be checked without a probe run.

        This used to say "a declaration must not quietly cover a row that is
        not a miss", and it does not check that. `Incomplete` is the row's
        *label* — what it is supposed to be — not whether the probe currently
        gets it wrong. Whether a declared capture still misses is a fact about
        a run, and this suite has no run: it is Linux-only and the parser is
        macOS-only.

        So the name is accurate and the old docstring was not, which is the
        expensive direction — a reader checking whether rule 3 was enforced
        would have found this test, read the first line, and stopped.

        The miss half is checked where the evidence exists: `unfinished-score.py`
        prints DECLARED LIMITS NOW PASSING with the ids on every scoring run.
        """
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

        INC58, "I was thinking about", joined it on 2026-09-16 and is the
        argument this pin asks for. It ends on a preposition, which the cited
        comment does cover -- but only for a preposition stranded at the end
        of a longer clause. This capture is not that: `DisfluencyFilter.stripped`
        reduces it to the single token "about", and the one-token branch of
        `ThoughtCompletion.unfinished` accepts `.preposition` exactly where the
        multi-token switch refuses it. Same word class, different branch, and
        the branch is the whole reason the row exists.

        That sentence used to end "-- no other row in the set reaches it",
        and it was false when written. INC34 is the identical utterance
        under `incomplete-complement` and had been in the set since
        2026-08-26, three weeks before #99 added INC58, so both rows reach
        that branch. The claim was pinned by the assertion below, which
        checks the note *contains* "one-token branch" and never that the
        uniqueness it asserted held: a prose pin cannot check a claim about
        the data. `DuplicateUtterancesAreAllListed` is the check that can.

        Declaring it would record an accepted limit for a capture
        the engine is expected to get right, which is the marker-for-judgement
        substitution this test exists to prevent, one level up.
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
        self.assertNotIn("INC58", declared,
                         "INC58 is a one-token capture reaching the branch that "
                         "accepts a lone preposition; the comment covers the "
                         "multi-token case")
        self.assertIn("one-token branch", rows["INC58"][4])
        # Being outside the declaration is not free: an exception has to say
        # why it is one.
        #
        # This and the identity pin below are both load-bearing, and **each
        # covers what the other one's first stated reason claimed**, which is
        # why neither is the redundant one. Established by injection on
        # 2026-09-16, not by reading:
        #
        #   INC46 quietly removed from the `# limit:` line -> THIS loop fires,
        #       because every declared row in the family carries an empty note.
        #       The pin never sees it. (The commit that added the pin said the
        #       opposite; that reason was wrong.)
        #   a new undeclared row WITH a plausible note      -> only the PIN
        #       fires. This loop waves it through, so a row can be added to the
        #       family, expected to pass, and argued nowhere.
        #
        # So the loop guards the declaration shrinking and the pin guards the
        # exception set growing. Delete either and one of those goes silent.
        for cid in sorted(family - declared):
            self.assertTrue(
                rows[cid][4].strip(),
                f"{cid} sits outside the declaration and gives no reason")
        if declared:
            self.assertEqual(sorted(family - declared), ["INC45", "INC58"])


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

    #: Both rows declared, so whatever the report says about limits has to
    #: hold for a passing one and a failing one at the same time.
    DECLARED_AB = "# limit: some/File.swift | a stated reason | A B\n"

    def declared_both(self, first_flagged, second_flagged=False):
        return self.unfinished(
            [self.DECLARED_AB,
             "A\tone\tf\tIncomplete\t\n", "B\ttwo\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=first_flagged),
             self.unfinished_block("two", gap=second_flagged)])

    def test_a_declared_limit_is_counted_never_subtracted(self):
        """The arithmetic, and the sentence that used to contradict it.

        The limit check and the correctness check are two independent `if`s,
        so a declared capture the probe flags is counted in both. That is
        deliberate -- a limit changes what the reader concludes from the rate,
        not the rate -- but the report used to print "They are counted as
        misses above and stay that way" directly beneath a recall figure that
        had just counted one of them as a pass.

        Both rows here are declared and one is flagged. A report claiming
        every limit is a miss cannot also say 1/2, and this pins that it no
        longer tries to.
        """
        _, report = self.declared_both(first_flagged=True)
        self.assertIn("recall   unfinished flagged   1/2", report)
        self.assertIn("2 of the 2 unfinished captures are recorded", report)
        self.assertNotIn("counted as misses", report)
        self.assertIn("counted, never subtracted", report)

    def test_a_declared_limit_that_passes_is_named_in_the_report(self):
        """The assertion is on the printing, not on the arithmetic.

        A count the scorer computes and does not print is a figure nobody
        recomputes, so this asserts the line appears *and* that it carries the
        id. Naming the row is the point: a family total cannot say which
        capture is which, and reconstructing one from `8 cases, 7 declared,
        2 OK` is exactly the reasoning this report already made fail.
        """
        _, report = self.declared_both(first_flagged=True)
        self.assertIn("DECLARED LIMITS NOW PASSING   1 of 2", report)
        #: Matched as a whole line rather than with `assertIn`, because "A"
        #: occurs inside half the prose in this report and a substring test
        #: would pass without anything having been named.
        named = [l.strip() for l in report.splitlines() if l.strip() == "A"]
        self.assertEqual(named, ["A"], "the passing limit must be named")
        self.assertIn("re-read the reason each of these cites", report)
        #: The line above anchors one line of a seven-line block, so the
        #: operative sentence underneath it could be reverted to "remove the
        #: ids that no longer belong" while this test stayed green. Review found
        #: that by injection. Both halves are pinned because the first says
        #: *re-read* and only the second says what may then be removed, and it
        #: is the second that a reader acts on.
        self.assertIn("trim only the ids whose", report)

    def test_the_passing_count_prints_even_when_it_is_zero(self):
        """Absence of the line would read exactly like nobody having looked.

        Without this, printing the block only when something passes would
        still satisfy the test above, and the healthy state would be silent --
        the shape where a green tick and an unasked question are
        indistinguishable.
        """
        _, report = self.declared_both(first_flagged=False)
        self.assertIn("recall   unfinished flagged   0/2", report)
        self.assertIn("DECLARED LIMITS NOW PASSING   0 of 2", report)
        self.assertNotIn("re-read the reason each of these cites", report)

    def test_the_block_is_absent_when_nothing_is_declared(self):
        """A set with no declaration must not grow a limits section."""
        _, report = self.unfinished(
            ["A\tone\tf\tIncomplete\t\n"],
            [self.unfinished_block("one", gap=True)])
        self.assertNotIn("DECLARED LIMITS NOW PASSING", report)
        self.assertNotIn("recorded design limits", report)

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


class AcceptableCounts(unittest.TestCase):
    """The label reader that decides 
    the thought-count metric.

    It is tested directly rather than through a run because it is a pure
    function that a whole published figure rests on, and because the defect it
    fixes was invisible end to end: the strict reading produced a plausible
    number for a year and nothing compared it against the label it came from.
    """

    def reader(self):
        import importlib.util
        path = (pathlib.Path(__file__).resolve().parent
                / "heldout" / "score.py")
        source = path.read_text()
        # Import the function without running the script, which expects argv.
        namespace = {}
        start = source.index("def acceptable_counts(")
        end = source.index("def tally(")
        exec(compile("import re\n" + source[start:end], str(path), "exec"),
             namespace)
        return namespace["acceptable_counts"]

    def test_an_exact_label_permits_exactly_one_count(self):
        self.assertEqual(self.reader()("3"), ({3}, 3, False))

    def test_a_range_permits_every_count_in_it(self):
        acceptable, strict, prose = self.reader()("1-2")
        self.assertEqual(acceptable, {1, 2})
        self.assertEqual(strict, 1)
        self.assertFalse(prose)

    def test_a_wider_range_is_inclusive_at_both_ends(self):
        self.assertEqual(self.reader()("4-5")[0], {4, 5})
        self.assertEqual(self.reader()("0-1")[0], {0, 1})

    def test_whitespace_around_the_dash_is_tolerated(self):
        self.assertEqual(self.reader()("2 - 3")[0], {2, 3})

    def test_a_prose_label_falls_back_to_the_leading_integer_and_says_so(self):
        """The fallback is the old behaviour. What is new is that it is named.

        Three captures carry a label like `2 (or 1 with 2 alerts)`. Reading the
        leading integer is a guess, and a guess that reports itself can be
        counted; one that does not becomes part of the figure.
        """
        acceptable, strict, prose = self.reader()("2 (or 1 with 2 alerts)")
        self.assertEqual((acceptable, strict), ({2}, 2))
        self.assertTrue(prose)

    def test_an_unparseable_label_is_not_scored_at_all(self):
        self.assertEqual(self.reader()(""), (set(), None, False))
        self.assertEqual(self.reader()("some")[1], None)

    def test_the_strict_answer_is_always_one_the_label_permits(self):
        """Otherwise range-aware could score below strict, which is nonsense.

        This is the property that makes the two figures comparable: the strict
        reading has to be a special case of the range-aware one, so the second
        can only ever be the same or higher.
        """
        for label in ["0", "3", "0-1", "1-2", "2-3", "4-5", "2 (or 1 with 2 alerts)"]:
            with self.subTest(label=label):
                acceptable, strict, _ = self.reader()(label)
                self.assertIn(strict, acceptable)

    def test_the_real_file_uses_only_shapes_this_understands(self):
        """A fourth label shape would be silently read as its leading integer."""
        path = (pathlib.Path(__file__).resolve().parent
                / "heldout" / "heldout.tsv")
        if not path.exists():
            self.skipTest("heldout.tsv not present")
        reader = self.reader()
        prose = []
        for line in path.read_text().splitlines():
            if line.startswith("#") or not line.strip():
                continue
            parts = line.split("\t")
            if len(parts) < 5 or parts[0] == "id":
                continue
            _, strict, is_prose = reader(parts[4])
            if is_prose:
                prose.append(parts[0])
        self.assertLessEqual(
            len(prose), 3,
            f"more prose count labels than the three recorded: {sorted(prose)}. "
            f"Each is read as its leading integer, which is a guess.")


class CompromisedRegistry(unittest.TestCase):
    """The held-out exclusion list, and the ways it can pass while doing nothing.

    Every assertion here exists because the corresponding mistake was made in
    this repository on 2026-09-11: a two-limb count reported as a column
    rather than a union, and a guard whose expected answer was the system's
    default answer.

    Ids only. Nothing in this class reads the utterance column.
    """

    HELDOUT = pathlib.Path(__file__).resolve().parent / "heldout" / "heldout.tsv"

    def registry(self):
        sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "heldout"))
        import compromised
        return compromised

    def heldout_ids(self):
        if not self.HELDOUT.exists():
            self.skipTest("heldout.tsv not present")
        ids = set()
        for line in self.HELDOUT.read_text().splitlines():
            if line.startswith("#") or not line.strip():
                continue
            parts = line.split("\t")
            if len(parts) >= 5 and parts[0] != "id":
                ids.add(parts[0])
        return ids

    def test_every_excluded_id_is_really_in_the_set(self):
        """A typo excludes nothing and the clean score becomes the legacy one.

        This is the failure mode that cannot be seen from the output: both
        numbers are printed, both look plausible, and the difference between
        them is silently zero.
        """
        c = self.registry()
        unknown = sorted(c.EXCLUDED - self.heldout_ids())
        self.assertEqual(
            unknown, [],
            f"compromised.py names ids that are not in heldout.tsv: {unknown}. "
            f"The clean sealed score would exclude nothing for these.")

    def test_the_exclusion_actually_removes_rows(self):
        """Guards against the registry emptying out and nobody noticing."""
        c = self.registry()
        self.assertTrue(c.EXCLUDED, "the exclusion set is empty")
        self.assertTrue(
            c.EXCLUDED & self.heldout_ids(),
            "no excluded id is in the set, so clean == legacy")

    def test_compromised_is_the_union_of_the_two_state_categories(self):
        """The union, not either column, and not their sum.

        C342 sits in both limbs, which is exactly what let a column pass for
        the union and kept the wrong total looking self-consistent. A sum
        would say six here and the right answer is five.
        """
        c = self.registry()
        self.assertEqual(
            c.COMPROMISED,
            set(c.IN_TUNED_MATERIAL) | set(c.VERBATIM_IN_DOCUMENT))
        self.assertLess(
            len(c.COMPROMISED),
            len(c.IN_TUNED_MATERIAL) + len(c.VERBATIM_IN_DOCUMENT),
            "the two limbs no longer overlap -- if that is real, this test "
            "should be updated deliberately rather than relaxed")

    def test_clean_excludes_at_least_everything_compromised(self):
        c = self.registry()
        self.assertTrue(c.COMPROMISED <= c.EXCLUDED)

    def test_every_category_says_why_each_capture_is_in_it(self):
        """A bare id is not a record. Provenance is what makes it auditable."""
        c = self.registry()
        for name, table in c.CATEGORIES:
            for cid, provenance in table.items():
                with self.subTest(category=name, capture=cid):
                    self.assertGreater(
                        len(provenance.strip()), 10,
                        f"{cid} is listed under {name!r} without saying where")

    def test_the_registry_agrees_with_the_leak_check_that_detects_them(self):
        """Two records of one fact drift. This is the thing that notices.

        `compromised.py` is the scorer's exclusion list. PR #55 adds
        `OVERLAP_DOCUMENTED`, `PROSE_DOCUMENTED` and
        `EXPOSED_WITHOUT_INSPECTION` to `everyday/leak-check.py`, which is the
        check that actually *detects* these captures. Once both exist, the two
        must name the same ids, and the leak check should become the source
        the registry derives from -- a figure belongs to the check that
        computes it.

        Skips until #55 lands, which is the weak form and is deliberate here:
        the alternative is asserting against a file that does not exist yet.
        The skip message names what will arm it, so a skip in the output is a
        reminder rather than a silence.
        """
        leak = (pathlib.Path(__file__).resolve().parent
                / "everyday" / "leak-check.py")
        if not leak.exists():
            self.skipTest("everyday/leak-check.py not present")
        source = leak.read_text()
        names = ["OVERLAP_DOCUMENTED", "PROSE_DOCUMENTED",
                 "EXPOSED_WITHOUT_INSPECTION"]
        if not all(n in source for n in names):
            self.skipTest(
                "leak-check.py does not carry the documented lists yet; "
                "PR #55 adds them. When it lands this test arms itself and "
                "compromised.py should derive from it rather than restate it.")

        #: `__file__` is set because leak-check.py resolves its own path to
        #: find the repository root, and a bare exec namespace has no
        #: `__file__` at all. `__name__` is set to something other than
        #: `__main__` so that exec'ing the module defines its lists without
        #: also running its command line.
        namespace = {"__file__": str(leak), "__name__": "leak_check_under_test"}
        exec(compile(source, str(leak), "exec"), namespace)  # noqa: S102
        #: Their lists cover every sealed set; `compromised.py` covers the
        #: held-out set alone, because the clean sealed score is a held-out
        #: figure. So the comparison is restricted to held-out captures, and
        #: restricted BY THE FILE IN THE KEY rather than by an id prefix: a
        #: prefix test would be a second guess about the data sitting inside
        #: the check meant to catch guesses, and it would silently pass the
        #: day a set adopts a colliding prefix.
        theirs = set()
        for n in names:
            for key in namespace[n]:
                self.assertIsInstance(
                    key, tuple,
                    f"{n} stopped using (file, id) keys, so this comparison "
                    f"can no longer tell which set a capture belongs to")
                source_file, capture_id = key[0], key[1]
                if source_file == "heldout.tsv":
                    theirs.add(capture_id)  # ids only, never text
        self.assertTrue(
            theirs,
            "no held-out capture is named by leak-check.py at all, which "
            "means this test is comparing against an empty set and would "
            "pass however wrong compromised.py became")
        ours = self.registry().EXCLUDED
        self.assertEqual(
            ours, theirs,
            "compromised.py and leak-check.py disagree about which held-out "
            "captures are not unseen. One of them is wrong and the clean "
            "sealed score is computed from the first.")

    def test_why_reports_both_categories_for_a_doubly_compromised_capture(self):
        """The accessor has to return the union too, not the first hit."""
        c = self.registry()
        doubled = set(c.IN_TUNED_MATERIAL) & set(c.VERBATIM_IN_DOCUMENT)
        if not doubled:
            self.skipTest("no capture is compromised both ways any more")
        for cid in doubled:
            with self.subTest(capture=cid):
                self.assertEqual(len(c.why(cid)), 2)


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

    def test_readable_hands_back_every_readable_file_on_disk(self):
        """The list being total does not make what is handed out total.

        `unclassified()` and `missing()` both read `READABLE_NAMES` directly,
        so neither can see `readable()` returning fewer paths than it declares.
        Slicing one off its return passes every suite in this repository: each
        consumer derives from that one call, so all of them move together, the
        census prints one fewer source and 5,482 utterances instead of 5,501,
        and nothing compares either number to anything.

        That is not hypothetical here. The census read 1,908 utterances until
        `SpeakItTests` was added, and #68 described two corpora it was not
        reading. Both were a population short while reporting confidently.

        So this derives the answer a second way -- everything on disk that is
        not sealed and not a manifest -- rather than restating the constant.
        It is the exact complement of `unclassified()`: that one says the
        lists cover the disk, this one says `readable()` returns all of the
        part it owns.
        """
        paths = self.paths()
        sealed = set(paths.sealed())
        manifest = {paths.HERE / name for name in paths.MANIFEST_NAMES}
        on_disk = sorted(path for path in paths.HERE.rglob("*.tsv")
                         if path not in sealed and path not in manifest)
        self.assertTrue(on_disk, "no readable corpus found on disk at all, "
                                 "so this test is measuring nothing")
        self.assertEqual(
            paths.readable(), on_disk,
            "readable() and the directory disagree; every figure derived "
            "from it moves with it, so neither the count nor the report "
            "can show this")

    def test_the_readable_search_cannot_return_a_sealed_file(self):
        """The search that caused the second exposure, made safe by construction.

        An id is safe to store and unsafe to grep: the sealed file is the one
        place an id sits beside its text, so a recursive search from the
        repository root turns the record into a lookup key. That happened
        within two hours of the record being written, to somebody checking
        that the record existed.
        """
        paths = self.paths()
        searchable = set(paths.searchable())
        for path in paths.sealed():
            self.assertNotIn(path, searchable,
                             f"{path.name} is searchable, so grepping a "
                             f"capture id returns the capture")

    def test_the_search_proves_it_can_find_something_first(self):
        """Zero is the one result that looks the same whether the scan worked.

        The real instance: a scan for the word "so" hard-coded column two,
        `everyday.tsv` keeps its utterance in column three, and the zero it
        returned was published as a fact about the corpus. The true answer was
        34. Every other number invites "is that right?"; zero invites "good".
        """
        self.assertTrue(self.paths().scan_is_working(),
                        "the search cannot find a string that sits in its own "
                        "source, so any zero it reports means nothing")

    def test_a_search_that_reads_nothing_refuses_to_report(self):
        """A broken scan must fail loudly, not return an empty result.

        Driven through the real entry point rather than by asserting on
        `scan_is_working` alone, because the value of the canary is that the
        caller cannot skip it.
        """
        paths = self.paths()
        with tempfile.TemporaryDirectory() as empty:
            #: A root with no corpus_paths.py in it, so the known-positive is
            #: genuinely absent -- the same state a traversal defect produces.
            self.assertFalse(paths.scan_is_working(empty))
            said = io.StringIO()
            with contextlib.redirect_stdout(said):
                status = paths._grep("anything at all", empty)
            self.assertEqual(status, 2,
                             "a search that cannot find its own canary must "
                             "exit differently from one that found no matches")
            self.assertIn("means nothing", said.getvalue())

    def test_the_canary_is_actually_in_the_file(self):
        """Otherwise the self-check is a test of nothing, passing forever."""
        paths = self.paths()
        source = pathlib.Path(paths.__file__).read_text(encoding="utf-8")
        self.assertGreaterEqual(
            source.count(paths.SELF_CHECK), 1,
            "SELF_CHECK must appear in the module's own source; that is the "
            "whole mechanism, and renaming the constant without leaving the "
            "literal behind silently disarms it")

    def test_the_readable_search_still_reaches_ordinary_files(self):
        """A search that reads nothing finds nothing, and passes.

        The exact shape of the symlink defect: excluding everything satisfies
        the test above perfectly.
        """
        searchable = {p.name for p in self.paths().searchable()}
        self.assertIn("rambling.tsv", searchable)
        self.assertIn("leak-check.py", searchable)

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

    def test_the_sealed_list_is_exactly_the_declared_sealed_sets(self):
        #: Pinned to literal names rather than derived from the module, and
        #: deliberately so: a test that adapts to whatever the list says cannot
        #: notice a set being added or dropped. Adding one is a real decision
        #: -- it opens a generation, needs a README, a score.sh and a manifest
        #: row -- so it should cost an edit here and a sentence saying why.
        #: `consequence.tsv` joined on 2026-09-14: blind-authored evidence for
        #: the resultive-`so` boundary, which Calvin asked for and which is
        #: worth nothing if it is developed against.
        self.assertEqual(sorted(p.name for p in self.paths().sealed()),
                         ["adversarial.tsv", "consequence.tsv",
                          "everyday.tsv", "heldout.tsv"],
                         "the sealed list changed; if that was deliberate, say "
                         "in the note above which set arrived or left and why")


def ledger_check_module():
    """ledger-check.py has a hyphen in its name, so it needs loading by path."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "ledger_check", pathlib.Path(__file__).parent / "ledger-check.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


LEDGER = """## Sealed-set cost ledger

| date | change | measure | from | to | |
| --- | --- | --- | --- | --- | --- |
| 2026-09-11 | a boundary (#57) | held-out thought count | 255/310 | 254/310 | **\u22121** |
| 2026-09-11 | a tightening (#57) | \u2014 | \u2014 | \u2014 | no sealed measure moved |

- **held-out thought count: \u22121 row**, across one change.

## Next heading
"""


class TheHeaderIsReadInOnePlace(unittest.TestCase):
    """Which line is the header, and which column holds the capture.

    Four defects have come from four readers working this out separately, and
    the reason is one file wide: every corpus here comments its header except
    `everyday.tsv`, which writes it as an ordinary first line. So
    `startswith("#")` is right ten times out of eleven -- the worst hit rate a
    rule people copy can have, because the tenth reader has no reason to doubt
    it. One of those four re-derivations reported 256 rows for a 255-capture
    set; another reported that a corpus contains no instance of a word it uses
    34 times.

    So these tests are about the two questions being answered in one place and
    answered the same way, not about any one scan being right.
    """

    #: The four sealed sets are published denominators. A reader that gains or
    #: loses a row changes a rate nobody re-derives, so the sizes are pinned
    #: here by count alone -- no id, no text.
    SEALED_SIZES = {
        "heldout.tsv": 389,
        "everyday.tsv": 255,
        "adversarial.tsv": 120,
        "consequence.tsv": 56,
    }

    def paths(self):
        sys.path.insert(0, str(pathlib.Path(__file__).parent))
        try:
            import corpus_paths
        finally:
            sys.path.pop(0)
        return corpus_paths

    def corpus(self, body):
        room = tempfile.TemporaryDirectory()
        self.addCleanup(room.cleanup)
        path = pathlib.Path(room.name) / "set.tsv"
        path.write_text(body, encoding="utf-8")
        return path

    def test_both_header_layouts_in_this_repository_are_read(self):
        """The asymmetry itself, pinned in both directions.

        A rule that reads only the commented one is right ten times and wrong
        on the largest readable corpus; a rule that reads only the first line
        is right once.
        """
        paths = self.paths()
        commented = ["# id\tutterance\tfamily", "C1\thello\tx"]
        bare = ["id\tdomain\tutterance", "C1\twork\thello"]
        self.assertEqual(paths.utterance_column(commented), 1)
        self.assertEqual(paths.utterance_column(bare), 2)
        self.assertEqual(paths.header_index(commented), 0)
        self.assertEqual(paths.header_index(bare), 0)

    def test_the_header_line_is_never_counted_as_data(self):
        """The 256-for-255 defect, in both layouts."""
        paths = self.paths()
        for body in ("# id\tutterance\nC1\thello\nC2\tthere\n",
                     "id\tutterance\nC1\thello\nC2\tthere\n"):
            with self.subTest(body=body.splitlines()[0]):
                path = self.corpus(body)
                self.assertEqual(len(list(paths.data_rows(path))), 2)
                self.assertEqual([u for _n, _i, u in paths.utterances(path)],
                                 ["hello", "there"])

    def test_every_column_is_read_from_the_same_line(self):
        """Two columns resolved by two independent scans can disagree.

        `column_of` looked for its name on any line rather than on the header
        line, so a commented-out old header still names an `id` column as far
        as the id lookup is concerned, while the utterance lookup uses the
        real one. Every row then reports the wrong field as its id, and the
        report that names a leak names the wrong thing -- which is worse than
        naming nothing, because nothing looks like a failure and this does not.
        """
        paths = self.paths()
        path = self.corpus("# id\told_utterance\n"
                           "# ref\tid\tutterance\n"
                           "R1\tX01\thello\n"
                           "R2\tX02\tthere\n")
        self.assertEqual(paths.id_column(
            path.read_text(encoding="utf-8").splitlines()), 1)
        found = [cid for _n, cid, _u in paths.utterances(path)]
        self.assertEqual(
            found, ["X01", "X02"],
            "the id column was resolved from a line other than the one the "
            f"utterance column came from; got {found}")

    def test_a_row_too_short_for_the_utterance_column_is_refused(self):
        """A dropped row is a smaller denominator and no message.

        This is the shape this repository keeps finding: the malformed row is
        exactly the row worth knowing about, and skipping it makes the file
        look clean and one capture smaller. No corpus file here has one today,
        so refusing costs nothing and stays cheap only while that holds.
        """
        paths = self.paths()
        path = self.corpus("# id\tutterance\nC1\thello\nC2\n")
        with self.assertRaises(ValueError) as raised:
            list(paths.utterances(path))
        self.assertIn("3", str(raised.exception),
                      "the refusal must name the line, or it sends a reader "
                      "looking through the whole file")

    def test_a_row_with_an_empty_id_is_refused_too(self):
        """Found by mutation: restoring `cid or "?"` in the leak check changed
        no verdict, which looked like the deleted line being dead. It was not
        -- a header can name an id column and a row can still leave the cell
        empty, and the fallback was quietly printing a placeholder where the
        report is supposed to print a name. Refusing the missing column and
        not the missing value is the half-measure, so both refuse now and the
        fallback really is dead."""
        paths = self.paths()
        path = self.corpus("# id\tutterance\nX01\thello\n\tthere\n")
        with self.assertRaises(ValueError) as raised:
            list(paths.utterances(path))
        self.assertIn("3", str(raised.exception))
        self.assertIn("empty", str(raised.exception))

    def test_the_id_cell_is_stripped(self):
        """`harvest_ids` stripped it before the conversion; the contract that
        replaced it has to keep doing so, or a padded cell reaches a report
        that is compared against ids elsewhere."""
        paths = self.paths()
        path = self.corpus("# id\tutterance\n  X01  \thello\n")
        self.assertEqual([cid for _n, cid, _u in paths.utterances(path)],
                         ["X01"])

    def test_a_row_too_short_for_the_id_column_is_refused_as_cleanly(self):
        """A layout with the id after the utterance is not one we have, which
        is why the short-row check could ignore it and no test would notice.
        On such a file the refusal became an IndexError with no line number --
        the difference between a reader that declines and one that crashes."""
        paths = self.paths()
        path = self.corpus("# utterance\tid\nhello\tX01\nthere\n")
        with self.assertRaises(ValueError) as raised:
            list(paths.utterances(path))
        self.assertIn("3", str(raised.exception))

    def test_a_corpus_with_no_id_header_refuses_rather_than_naming_nothing(self):
        """An unnamed row is worse here than a missing one.

        The leak check's prose half exists to **name** a leak without printing
        it. An id lookup that returns None and becomes the empty string turns
        the one safe report into one that says a sealed capture is committed
        somewhere and cannot say which. Absent is not column zero and it is
        not "". Raised by the reader, because the previous version of this was
        a `fields[0]` in the caller, and the conversion that removed it made
        the failure quieter rather than louder.
        """
        paths = self.paths()
        path = self.corpus("# ref\tutterance\nX01\thello\n")
        with self.assertRaises(ValueError) as raised:
            list(paths.utterances(path))
        self.assertIn("id", str(raised.exception))
        with self.assertRaises(ValueError):
            paths.id_column(["# ref\tutterance"])

    def test_every_corpus_file_names_an_id_column(self):
        """Counts only. The refusal above costs nothing while this holds."""
        paths = self.paths()
        for path in sorted(paths.sealed() + paths.readable()):
            with self.subTest(corpus=path.name):
                lines = path.read_text(encoding="utf-8").splitlines()
                self.assertEqual(paths.id_column(lines), 0)

    def test_a_corpus_with_no_utterance_header_refuses_rather_than_guessing(self):
        paths = self.paths()
        with self.assertRaises(ValueError):
            paths.utterance_column(["# id\tcapture", "C1\thello"])

    def test_column_of_returns_none_rather_than_something_usable(self):
        """`column_of(...) or 0` is how a missing header becomes column one."""
        paths = self.paths()
        self.assertIsNone(paths.column_of(["# id\tutterance"], "domain"))

    def test_every_corpus_file_reads_and_nothing_is_dropped(self):
        """Counts only -- no id and no text leaves this test.

        `data_rows` and `utterances` must agree on every file: the second is
        the first plus a column lookup, and a gap between them is a silently
        skipped row.
        """
        paths = self.paths()
        for path in sorted(paths.sealed() + paths.readable()):
            with self.subTest(corpus=path.name):
                rows = len(list(paths.data_rows(path)))
                utterances = len(list(paths.utterances(path)))
                self.assertGreater(rows, 0)
                self.assertEqual(rows, utterances)
                if path.name in self.SEALED_SIZES:
                    self.assertEqual(rows, self.SEALED_SIZES[path.name])

    def test_the_corpora_do_not_agree_on_a_column(self):
        """Why a hard-coded index is not merely untidy.

        If every set kept its utterance in the same column, every hard-coded
        reader would be correct and this whole family would be invisible until
        the layout changed. They do not, so this records what is actually true
        -- and if it ever stops being true, the reader that hard-codes the new
        common index starts passing by luck.
        """
        paths = self.paths()
        columns = {paths.utterance_column(
            p.read_text(encoding="utf-8").splitlines())
            for p in paths.sealed() + paths.readable()}
        self.assertGreater(len(columns), 1, f"one column everywhere: {columns}")


class EveryCorpusReaderIsDeclared(unittest.TestCase):
    """Who is still working out the file format for themselves.

    Five defects have come from five readers deriving the same two rules --
    which lines are data, which column holds the capture -- and each was found
    by accident, years of reading apart in instrument time. The rules now have
    one owner in `corpus_paths`. That on its own fixes nothing, because the
    sixth reader will be written by somebody who has not read this class.

    So the list below is the point. A file that slices a tab-separated line
    itself is either on it, with a reason, or the run fails. The list is
    allowed to shrink and nothing else; an entry that stops matching fails too,
    so a converted reader cannot be left on it and a stale entry cannot sit
    here looking like remaining work.

    It is not a claim that the listed readers are wrong. It is a claim that
    each is a place the next defect in this family will appear, written down
    where the next person changing one will see it.
    """

    HERE = pathlib.Path(__file__).resolve().parent

    #: `cut -f` for shell, a tab split for Python. Deliberately crude: a
    #: detector with exceptions is a detector somebody routes around, and the
    #: cost of a false positive here is one line in the list below.
    SLICES = re.compile(r"""split\("\\t"\)|split\('\\t'\)|cut -f""")

    #: Every file that still reads a corpus its own way, and why it has not
    #: moved yet. Shrinks; never grows without the reason being written here.
    HAND_ROLLED = {
        "adversarial/lengths.py":
            "reads label columns as well as the utterance; moves with the "
            "adversarial scorer",
        "adversarial/score.sh":
            "`cut -f3` into the probe's input file. Shell cannot call Python "
            "cheaply here, and the extraction is checked by comparing the "
            "file it writes against `corpus_paths.utterances`",
        "choice-balance.py":
            "reads the tag column, not the utterance; the tag grammar is its "
            "own and belongs to it",
        "consequence/block-report.py":
            "reads the connector and block columns; same reason",
        "consequence/score.sh":
            "`cut -f2` into the probe's input file, checked the same way as "
            "the adversarial one",
        "devsets/abandonment-score.py":
            "development-set scorer, reads its own label columns",
        "devsets/score.py":
            "development-set scorer, reads its own label columns",
        "devsets/unfinished-score.py":
            "development-set scorer, reads its own label columns",
        "everyday/generation-check.py":
            "hashes whole rows rather than reading a column, so the format "
            "question it asks is a different one",
        "everyday/score.py":
            "the largest scorer; converting it needs the everyday suite green "
            "on a Mac, which this container cannot do",
        "everyday/score.sh":
            "`cut -f3` into the probe's input file, checked the same way as the "
            "adversarial one. This is the one that has to say three",
        "heldout/score.py":
            "scores the sealed set; converting it needs its own suite green on a "
            "Mac, which this container cannot do",
        "heldout/score.sh":
            "`cut -f2` into the probe's input file. This is the one whose "
            "commented header used to arrive as a 390th capture",
    }

    #: Suites build corpora inline to test readers, which is the one place
    #: writing the format out by hand is the job rather than a copy of it.
    TESTS = re.compile(r"(^|/)test_[^/]+\.py$")

    def readers(self):
        found = []
        for path in sorted(self.HERE.rglob("*")):
            if path.suffix not in (".py", ".sh") or not path.is_file():
                continue
            relative = str(path.relative_to(self.HERE))
            if relative == "corpus_paths.py" or self.TESTS.search(relative):
                continue
            if self.SLICES.search(path.read_text(encoding="utf-8")):
                found.append(relative)
        return found

    def test_the_detector_finds_a_hand_rolled_reader(self):
        """Without this, a detector that matches nothing passes every
        assertion below and reports the family as solved."""
        with tempfile.TemporaryDirectory() as room:
            room = pathlib.Path(room)
            (room / "a.py").write_text('cells = line.split("\\t")\n')
            (room / "b.sh").write_text('cut -f2 corpus.tsv\n')
            (room / "c.py").write_text('import corpus_paths\n')
            hits = [p.name for p in sorted(room.iterdir())
                    if self.SLICES.search(p.read_text())]
            self.assertEqual(hits, ["a.py", "b.sh"])

    def test_no_undeclared_reader_slices_a_corpus_itself(self):
        undeclared = [r for r in self.readers() if r not in self.HAND_ROLLED]
        self.assertEqual(
            undeclared, [],
            "these read a tab-separated corpus their own way and are not in "
            "HAND_ROLLED. Use corpus_paths.utterances / data_rows, or add the "
            "file here with the reason it cannot")

    def test_the_list_only_shrinks(self):
        """A converted reader left on the list is a to-do that reads as done.

        The same shape as an annotation that documents a failure and then
        absolves it: the entry stays, the defect is gone, and the list stops
        being a measurement of anything.
        """
        readers = set(self.readers())
        stale = sorted(set(self.HAND_ROLLED) - readers)
        self.assertEqual(
            stale, [],
            "no longer slice a corpus by hand, so remove them from "
            "HAND_ROLLED rather than leaving the list overstating the work")

    def test_the_reasons_are_reasons(self):
        for name, why in sorted(self.HAND_ROLLED.items()):
            with self.subTest(reader=name):
                self.assertGreater(
                    len(why.split()), 3,
                    f"{name} is listed without saying why it has not moved")


class TheShellExtractionAgreesWithTheReader(unittest.TestCase):
    """The four `score.sh` scripts cut a column out of a corpus with `cut -f`.

    Shell cannot call the one reader cheaply, so those four stay hand-rolled
    and are declared in `EveryCorpusReaderIsDeclared`. Declaring them is not
    the same as checking them, and this family's whole history is readers
    quietly disagreeing: `heldout/score.sh` used to cut column two off EVERY
    line, so the commented header's second cell -- the bare word `utterance`
    -- reached the probe as a 390th capture, and nothing said so.

    So each script's extraction is run and compared against
    `corpus_paths.utterances` for the same file. By count and by digest, never
    by value: three of these four corpora are sealed, and a unittest failure
    message prints both sides of an assertEqual. A mismatch here reports the
    first line number that differs and nothing else.
    """

    HERE = pathlib.Path(__file__).resolve().parent

    #: The script, and the corpus it extracts from. The command is read out of
    #: the script rather than repeated here: a copy of a command is a fifth
    #: reader, which is the thing this file is about.
    SCRIPTS = (
        ("adversarial/score.sh", "adversarial/adversarial.tsv"),
        ("heldout/score.sh", "heldout/heldout.tsv"),
        ("consequence/score.sh", "consequence/consequence.tsv"),
        ("everyday/score.sh", "everyday/everyday.tsv"),
    )

    def paths(self):
        sys.path.insert(0, str(self.HERE))
        try:
            import corpus_paths
        finally:
            sys.path.pop(0)
        return corpus_paths

    def extraction(self, script):
        """The pipeline the script uses to write its utterance file."""
        lines = [l for l in (self.HERE / script).read_text(encoding="utf-8")
                 .splitlines()
                 if "cut -f" in l and not l.lstrip().startswith("#")]
        self.assertEqual(len(lines), 1,
                         f"{script}: expected one extraction line, found "
                         f"{len(lines)}")
        return lines[0].split(">")[0].strip()

    def test_each_script_extracts_exactly_what_the_reader_reads(self):
        paths = self.paths()
        for script, corpus in self.SCRIPTS:
            with self.subTest(script=script):
                command = self.extraction(script)
                shelled = subprocess.run(
                    ["sh", "-c", command],
                    cwd=self.HERE, capture_output=True, text=True,
                    env={**os.environ, "SP": str((self.HERE / script).parent)})
                self.assertEqual(shelled.returncode, 0, shelled.stderr)
                got = shelled.stdout.splitlines()
                want = [u for _n, _i, u in paths.utterances(self.HERE / corpus)]
                self.assertEqual(
                    len(got), len(want),
                    f"{script} extracts {len(got)} lines, the reader reads "
                    f"{len(want)} from {corpus}")
                first = next((i for i, (a, b) in enumerate(zip(got, want))
                              if a != b), None)
                self.assertIsNone(
                    first,
                    f"{script} and corpus_paths disagree from extracted line "
                    f"{(first or 0) + 1} onward. Not printed: these sets are "
                    f"sealed and an assertEqual would render both sides")

    def test_the_comparison_can_actually_fail(self):
        """A command that returns nothing would agree with nothing, and the
        length check is the only thing standing between that and a pass."""
        paths = self.paths()
        want = [u for _n, _i, u in
                paths.utterances(self.HERE / "devsets/routed.tsv")]
        shelled = subprocess.run(
            ["sh", "-c", "cut -f2 devsets/routed.tsv"],
            cwd=self.HERE, capture_output=True, text=True)
        #: Column two with no header handling: one line too many, and the
        #: extra one is the header. Exactly the 390th-capture defect.
        self.assertNotEqual(len(shelled.stdout.splitlines()), len(want))


class SealedSetsDoNotRenderAsText(unittest.TestCase):
    """A sealed set must not be readable from a diff.

    The consequence set was written so the thread that owns parser changes
    would not have seen it, and that thread read all fifty-six captures an
    hour later — reviewing the pull request that added it. Nobody did anything
    wrong. A reviewer has to check something, and the review surface offered
    the text and nothing else.

    `.gitattributes` marks every sealed file `-diff`, so `git diff`, `git show`
    and `git log -p` report a binary change instead of printing captures, and
    the structural report becomes the thing a reviewer reads. What that does
    NOT do is make the file unreadable: anyone can still open it, and should
    be able to. It removes the easy accidental path, not the deliberate one.

    These tests exist because a `.gitattributes` line is the kind of thing that
    is written once for the sets that exist that day. The fifth sealed set will
    arrive without one unless something fails.
    """

    HERE = pathlib.Path(__file__).resolve().parent
    ROOT = HERE.parents[1]

    def rules(self):
        """Every path this repository marks `-diff`."""
        text = (self.ROOT / ".gitattributes").read_text(encoding="utf-8")
        out = set()
        for line in text.splitlines():
            line = line.split("#", 1)[0].strip()
            if line.endswith(" -diff"):
                out.add(line[: -len(" -diff")].strip())
        return out

    def sealed_paths(self):
        sys.path.insert(0, str(self.HERE))
        import corpus_paths
        return {path.relative_to(self.ROOT).as_posix()
                for path in corpus_paths.sealed()}

    def test_the_file_carries_rules_at_all(self):
        """No rules would satisfy the subset test below perfectly."""
        self.assertGreaterEqual(len(self.rules()), 4)

    def test_every_sealed_set_is_marked(self):
        missing = sorted(self.sealed_paths() - self.rules())
        self.assertEqual(missing, [],
                         "sealed sets a reviewer would read as plain text")

    def test_nothing_that_is_not_sealed_is_marked(self):
        """The rule hides text, so it must not creep onto readable material.

        A development set that stopped rendering would make ordinary review
        worse for no gain, and would do it quietly.
        """
        extra = sorted(self.rules() - self.sealed_paths())
        self.assertEqual(extra, [], "readable files hidden from review")

    def test_git_actually_applies_the_rule(self):
        """The rule is checked against git, not against the file's wording.

        A `.gitattributes` entry that is present and not in force is exactly
        the shape of check this repository keeps finding: the claim is on
        disk, the behaviour is not, and nothing says so.
        """
        for path in sorted(self.sealed_paths()):
            result = subprocess.run(
                ["git", "check-attr", "diff", "--", path],
                cwd=self.ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(result.stdout.strip().endswith("diff: unset"),
                            f"{path}: {result.stdout.strip()}")


class LedgerCheckTests(unittest.TestCase):
    """The ledger states a total per measure, each a claim about its own rows.

    Both halves are hand-written, at different times, by whoever measured the
    change. That is the arrangement that produced a wrong published figure
    twice in one day here, so the totals are recomputed rather than read.
    """

    def setUp(self):
        self.ledger = ledger_check_module()

    def test_a_consistent_ledger_passes(self):
        """The control. Without it every failure below could be the fixture."""
        self.assertEqual(self.ledger.check(LEDGER), [])

    def test_a_total_that_disagrees_with_its_rows_fails(self):
        """The failure this exists for: prose drifting from the table above it.

        The `assertNotEqual` is not decoration. This test spent a day passing
        for the wrong reason: it mutated the literal `**\u22121 row**`, the
        ledger's wording changed to `count: \u22121 row`, the replacement
        became a no-op, and a clean run on an unmutated document read as the
        check working. A mutation test has to assert that its mutation applied
        -- that is the same defect as the `sed` that failed silently and let a
        whole suite report OK on an untouched tree.
        """
        drifted = LEDGER.replace("count: \u22121 row", "count: \u22123 rows")
        self.assertNotEqual(drifted, LEDGER,
                            "the mutation did not apply, so everything below "
                            "would be measuring the unmutated document")
        problems = self.ledger.check(drifted)
        self.assertTrue(any("sum to" in p for p in problems), problems)
        self.assertTrue(any("-3" in p or "\u22123" in p for p in problems),
                        "the report must name the stated figure, or a reader "
                        "cannot tell which of the two numbers to fix")

    def test_a_change_count_that_disagrees_with_the_rows_fails(self):
        """The other half of the running-total sentence, and it was unguarded.

        A mutation removed this comparison and nothing moved. "Across one
        change" is the denominator of the total: the same net figure across
        one change and across nine are different findings, and the second is
        the one the ledger exists to make visible. A total whose denominator
        nobody checks is the defect this file has written down four times.
        """
        problems = self.ledger.check(
            LEDGER.replace("across one change", "across four changes"))
        self.assertTrue(any("change(s)" in p for p in problems), problems)

    def test_a_row_whose_direction_contradicts_its_figures_fails(self):
        problems = self.ledger.check(
            LEDGER.replace("| **\u22121** |", "| **+1** |"))
        self.assertTrue(any("its own figures" in p for p in problems), problems)

    def test_a_change_of_denominator_is_not_a_direction(self):
        """`255/310 -> 254/311` has no readable direction.

        Two figures over different denominators are not comparable, which is
        the whole argument for not comparing numbers across a generation. A
        subtraction that ignores it produces a confident wrong answer.
        """
        problems = self.ledger.check(LEDGER.replace("254/310", "254/311"))
        self.assertTrue(any("denominator" in p for p in problems), problems)

    def test_nothing_moved_and_moved_by_zero_stay_different_claims(self):
        """One flag over two populations is the recurring bug in this repo."""
        problems = self.ledger.check(
            LEDGER.replace("| \u2014 | \u2014 | \u2014 | no sealed measure moved |",
                           "| a measure | 10/20 | 10/20 | no sealed measure moved |"))
        self.assertTrue(problems,
                        "a row carrying real figures while claiming nothing "
                        "moved reads as untouched and is not")

    def test_a_missing_ledger_is_a_failure_and_not_a_clean_run(self):
        """A check that treats absence as success cannot fail on deletion.

        Exactly how `generation-check.py` once reported ok with a whole sealed
        set deleted.
        """
        problems = self.ledger.check("# Language baseline\n\nNo ledger here.\n")
        self.assertTrue(any("no '## Sealed-set cost ledger' section" in p
                            for p in problems), problems)

    def test_an_emptied_table_is_distinguishable_from_a_quiet_year(self):
        # Split on the first row in full, not on its date: both rows carry
        # `| 2026-09-11`, so the bare date names two places and `[0]` quietly
        # picks one. Caught by `EveryMutationInThisFileApplies`.
        empty = LEDGER.split("| 2026-09-11 | a boundary")[0] + "\n## Next heading\n"
        problems = self.ledger.check(empty)
        self.assertTrue(any("no rows" in p for p in problems), problems)

    def test_the_baseline_carries_the_ledger(self):
        """The real ledger passes the real check.

        This was pinned as an expected failure while the ledger lived on the
        core language thread's branch and this check lived on the evaluation
        thread's. That is the weak form done deliberately: a skip would have
        gone quiet forever, an expected failure reports an UNEXPECTED SUCCESS
        the moment the section exists, and an unexpected success fails the run.

        It did exactly that, on the merge that brought the two branches
        together, which is the only event that could have armed it. The marker
        is off because the thing it was waiting for arrived; the mechanism is
        worth keeping for the next check that has to outlive a branch.
        """
        self.assertEqual(self.ledger.check(
            self.ledger.BASELINE.read_text(encoding="utf-8")), [])


class EverySuiteIsActuallyRun(unittest.TestCase):
    """A test file nobody runs and a test file that does not exist are the
    same file.

    `language-tools` names its Python suites one line at a time. That is
    deliberate — `unittest discover` does not descend into a directory without
    an `__init__.py`, so a discovery step would silently stop covering the
    `everyday/` half. The cost of naming them is that the next suite someone
    adds is covered by nothing and reports nothing, which is exactly what
    happened to the leak check for the eighteen percent of the corpus it never
    read.

    So the list is checked for totality rather than trusted: every `test_*.py`
    under `Tools/CorpusRunner/` has to appear in the workflow.
    """

    HERE = pathlib.Path(__file__).resolve().parent
    WORKFLOW = HERE.parents[1] / ".github" / "workflows" / "ci.yml"

    def suites(self):
        return sorted(self.HERE.rglob("test_*.py"))

    def test_the_search_for_suites_finds_more_than_none(self):
        """Zero suites would satisfy the test below perfectly."""
        self.assertGreaterEqual(len(self.suites()), 3)

    def test_every_suite_under_the_corpus_runner_is_named_in_the_workflow(self):
        workflow = self.WORKFLOW.read_text(encoding="utf-8")
        root = self.HERE.parents[1]
        unrun = [str(path.relative_to(root)) for path in self.suites()
                 if str(path.relative_to(root)) not in workflow]
        self.assertEqual(unrun, [],
                         "suites that run nowhere but on somebody's laptop")

class DuplicateUtterancesAreAllListed(unittest.TestCase):
    """The same utterance under two ids -- listed here, or the test fails.

    Found 2026-09-16 from a number that looked wrong and was not: the scorer
    reports `164 of 164 labelled` for `unfinished.tsv` while the census counts
    163 utterances. Both are right. 164 rows carry 163 distinct utterances,
    because "I was thinking about" is in it as INC34 (`incomplete-complement`)
    and again as INC58 (`trailing-function-word`).

    TWO DIFFERENT THINGS, KEPT APART ON PURPOSE.

    `WITHIN_A_SET` is the one that distorts a rate. Both rows are scored by the
    same scorer into the same denominators, and every pair found so far carries
    the SAME expectation under a DIFFERENT family -- so one answer decides both,
    neither row can fail unless the other does, and the second contributes a
    denominator and no discriminating power. Two family rates then share a case:
    a fix aimed at one moves the other, and the family denominators sum past the
    size of the set.

    `ACROSS_SETS` is recorded, not judged. Eleven utterances live in more than
    one readable set. That is not obviously a defect -- the sets measure
    different properties, and one string belonging to both a routing set and a
    coordination set is not the same thing as one rate counting it twice. **No
    claim is made here about whether it should change.** It is asserted only so
    that it cannot drift unnoticed, which is the failure this whole class exists
    for: a count nobody rechecks is how the first one survived three weeks.

    An earlier version of this class was called `NoUtteranceIsScoredTwice-
    Unnoticed` while scanning only within each file, so eleven utterances were
    scored twice, unnoticed, under a name saying none were. Caught in review. A
    claim broader than what holds, inside the check written to stop claims
    broader than what holds.

    WHY THIS DOES NOT JUST CALL `corpus-shape.py`, WHICH ALREADY FINDS THEM.
    It does, exactly: run it against `unfinished.tsv` and it prints
    `unique utterances 163  DUPLICATED AT: INC34, INC58` and exits 1. They went
    unnoticed anyway, because **nothing invokes that tool** -- no script under
    `Tools/CI/`, no workflow step. It is a reviewer's hand-run instrument, and
    it reports a problem on two of the seven readable sets right now.

    It is also not wirable as it stands: on `abandonment.tsv`, which is ragged
    (37 rows of five columns, 18 of four), it raises `IndexError` at the label
    counter rather than reporting the raggedness it just printed. Repairing it,
    and deciding whether a blind reviewer's tool belongs in CI, is a change to
    that tool with its own argument. So this is deliberately a second
    implementation, and the honest reason is that it is the one that runs. Note
    that it is also within-file only, so it cannot see `ACROSS_SETS` either.

    Removing an id changes a denominator, which is a cost for the ledger rather
    than a drive-by edit -- and whichever row of a pair goes, the rate gets
    worse, so nobody is trimming these to flatter a number.
    """

    #: The refusal text and the duplicate lists are both longer than the
    #: default cutoff, and a truncated one is a failure message that names no
    #: file, no line and no id -- which is the whole job of these assertions.
    maxDiff = None

    #: (set, utterance) -> the ids sharing it inside that one file.
    WITHIN_A_SET = {
        ("unfinished.tsv", "I was thinking about"): ["INC34", "INC58"],
        ("routed.tsv", "Sarah said the meeting is off"): ["DO09", "RC01"],
        ("routed.tsv", "possibly move the meeting to Friday"): ["AD19", "HY10"],
    }

    #: utterance -> every (set, id) holding it, where more than one set does.
    #: `Sarah said the meeting is off` is in both lists and neither is wrong:
    #: it is duplicated inside `routed.tsv` AND present in `coordination.tsv`,
    #: which is three homes in total. The within-set entry naming two ids was
    #: read as naming all of them in review, so the two lists are separate.
    ACROSS_SETS = {
        "Sarah said call Mike tomorrow": [
            ("coordination.tsv", "RS04"), ("routed.tsv", "RC02")],
        "Sarah said never mind": [
            ("abandonment.tsv", "ABN26"), ("unfinished.tsv", "FP39")],
        "Sarah said the meeting is off": [
            ("coordination.tsv", "RS01"), ("routed.tsv", "DO09"),
            ("routed.tsv", "RC01")],
        "Sarah told Mike to call me": [
            ("routed.tsv", "AO09"), ("unfinished.tsv", "FP41")],
        "Tomorrow I need to, never mind": [
            ("abandonment.tsv", "ABN03"), ("unfinished.tsv", "ABD01")],
        "buy milk and text daniel": [
            ("coordination.tsv", "LC04"), ("unfinished.tsv", "FP78")],
        "don't call the plumber": [
            ("coordination.tsv", "NG01"), ("routed.tsv", "DO04")],
        "remind me not to eat before the blood test": [
            ("coordination.tsv", "NG02"), ("routed.tsv", "DO08")],
        "remind me to": [
            ("routed.tsv", "IR07"), ("unfinished.tsv", "INC26")],
        "text Mike that the deal is off": [
            ("coordination.tsv", "CM02"), ("routed.tsv", "DO10")],
        "the wedding was off and then back on": [
            ("coordination.tsv", "NG06"), ("routed.tsv", "DO12")],
    }

    def paths(self):
        #: Same accessor idiom as `CorpusPathTests`: import it the way the
        #: scorers do rather than adding a module-level import to this file.
        sys.path.insert(0, str(pathlib.Path(__file__).parent))
        try:
            import corpus_paths
        finally:
            sys.path.pop(0)
        return corpus_paths

    def homes(self):
        """(utterance -> [(set name, id)], set name -> why it was refused).

        Every row comes from `corpus_paths.utterances`, which is the reader the
        scorers use. Three drafts of this method got here:

        1. `column_of` behind `except Exception`, believing it was handling an
           unreadable header. `column_of` returns None rather than raising, so
           nothing was handled, `None` flowed downstream, and the failure
           arrived as a `TypeError` several lines later.
        2. `utterance_column` and `id_column`, which do raise, over a
           hand-rolled row loop guarded by `if len(cells) > max(...)`. That
           guard **skipped** a short row. `utterances()` **refuses** one, and
           its own comment is the argument: "A dropped row is a denominator one
           smaller and no message." Appending one tab-free line to a set left
           this scan reading 164 of 165 rows with all four tests green -- a
           duplicate detector losing a row in silence, which is the defect this
           class exists to catch, a layer below where it was looking.
        3. This one, which owns no parsing at all.

        A set is scanned whole or not at all: rows are collected per file and
        merged only if the file is read to the end, so `refused` means exactly
        "contributed nothing" rather than "contributed an unknown prefix". The
        refusal text is kept because it names the file, and the line when there
        is one -- a short row and an empty id cell carry a line number, a
        missing header carries the column it could not find. That is what
        anyone fixing it needs and what a bare "this set dropped out"
        withholds.
        """
        corpus_paths = self.paths()
        homes, refused = {}, {}
        for path in corpus_paths.readable():
            found = []
            try:
                for _, cid, utterance in corpus_paths.utterances(str(path)):
                    found.append((utterance, (path.name, cid)))
            except ValueError as refusal:
                #: Caught, not propagated, so that the failure is one
                #: assertion naming the set and quoting its refusal, rather
                #: than four stack traces -- and so that
                #: `test_every_readable_set_was_scanned` reaches its own assert
                #: instead of erroring first, which would make it a guard that
                #: cannot fire. "And the line" would be too strong: a row
                #: refusal carries a line number, a missing header does not.
                refused[path.name] = str(refusal)
                continue
            for utterance, home in found:
                homes.setdefault(utterance, []).append(home)
        return homes, refused

    def scanned_homes(self):
        """`homes()`, with the precondition the lists depend on asserted first.

        A refused set makes every list below wrong in the same uninteresting
        way: the entries in that file simply vanish. Asserting the refusal
        here means each of those failures reads as the refusal, naming the
        file and line, instead of leading with a thousand-character diff of
        utterances that are missing for a reason nobody has been told yet.

        It does NOT stop them failing -- `test_every_readable_set_was_scanned`
        would then be the only thing standing between a half-read corpus and a
        green suite, and one assertion carrying a guarantee alone is how this
        PR started.
        """
        homes, refused = self.homes()
        self.assertEqual(
            refused, {},
            "this list cannot be exact while a readable set goes unread, so "
            "the failure is the refusal above and not a duplicate.")
        return homes

    def test_every_readable_set_was_scanned(self):
        """A set dropping out makes both lists below look exact."""
        _, refused = self.homes()
        self.assertEqual(
            refused, {},
            "a readable set could not be read to the end, so it contributed "
            "no rows and a duplicate inside it would not be found -- both "
            "lists below would still pass. Three of the seven sets appear in "
            "neither list, which is exactly where a new duplicate would show "
            "up, so a set dropping out is otherwise invisible. The refusal "
            "above names the file, and the line when there is one.")

    def test_the_scan_reaches_rows_at_all(self):
        """Without this, an empty result reads the same as a clean corpus."""
        homes = self.scanned_homes()
        self.assertGreater(sum(len(v) for v in homes.values()), 500,
                           "the scan read almost nothing, so the checks below "
                           "would report a clean corpus either way")

    def test_within_set_duplicates_are_exactly_the_listed_ones(self):
        """Keyed by (set, utterance): two sets can hold the same duplicate."""
        homes = self.scanned_homes()
        found = {}
        for utterance, where in homes.items():
            per_set = {}
            for name, cid in where:
                per_set.setdefault(name, []).append(cid)
            for name, ids in per_set.items():
                if len(ids) > 1:
                    found[(name, utterance)] = sorted(ids)
        self.assertEqual(found, {k: sorted(v) for k, v in self.WITHIN_A_SET.items()},
                         "the utterances duplicated inside a single readable "
                         "set are not the ones listed. A new one means a row "
                         "was added that already existed under another id in "
                         "that file, so the family rates it lands in stop "
                         "being independent. One disappearing means this list "
                         "is stale.")

    def test_cross_set_sharing_is_exactly_the_listed_set(self):
        """Recorded so it cannot drift. Not a claim that it is wrong."""
        homes = self.scanned_homes()
        found = {u: sorted(set(w)) for u, w in homes.items()
                 if len({name for name, _ in w}) > 1}
        self.assertEqual(found, {u: sorted(set(w)) for u, w in self.ACROSS_SETS.items()},
                         "the utterances appearing in more than one readable "
                         "set are not the ones listed. Whether that is a defect "
                         "is undecided; going unnoticed is not allowed either "
                         "way.")


class CorpusShapeTests(unittest.TestCase):
    """The reviewer's tool for a sealed set, which must never print a capture.

    It exists because reviewing #62 meant reading all fifty-six captures of a
    sealed set in a pull request diff, which spent the set as blind evidence
    for every parser change after that one. The properties a reviewer actually
    needed were all computable without reading a row.
    """

    def shape(self):
        path = (pathlib.Path(__file__).resolve().parent / "corpus-shape.py")
        namespace = {"__file__": str(path), "__name__": "corpus_shape_under_test"}
        exec(compile(path.read_text(encoding="utf-8"), str(path), "exec"),  # noqa: S102
             namespace)
        return namespace

    def run_on(self, text):
        """Returns (exit status, printed output) for a corpus written inline."""
        shape = self.shape()
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "corpus.tsv"
            path.write_text(text, encoding="utf-8")
            said = io.StringIO()
            with contextlib.redirect_stdout(said):
                status = shape["main"]([str(path)])
        return status, said.getvalue()

    GOOD = ("id\tutterance\tfamily\texpected_thoughts\n"
            "X01\tthe lease ends in March\ta\t1\n"
            "X02\tthe bin goes out on Thursday\tb\t2\n")

    def test_no_capture_text_reaches_the_output(self):
        """The whole point. A reviewer must be able to run this and stay blind."""
        status, said = self.run_on(self.GOOD)
        self.assertEqual(status, 0, said)
        for text in ("the lease ends in March", "the bin goes out on Thursday"):
            self.assertNotIn(text, said,
                             "the shape report printed a capture, which is the "
                             "one thing it exists to avoid")

    #: `everyday.tsv`'s layout: the utterance third, not second. Every test
    #: above uses the common layout, which is precisely why a reader that
    #: hard-codes column one passed all of them.
    EVERYDAY_SHAPED = ("id\tdomain\tutterance\tkeep\n"
                       "X01\twork\tthe lease ends in March\ty\n"
                       "X02\thome\tthe bin goes out on Thursday\ty\n")

    def test_an_empty_utterance_is_found_in_the_other_layout_too(self):
        """The check read column one until 2026-09-14.

        On the one corpus that keeps its utterance third it was therefore
        reading `domain`, which is never empty -- so the empty-utterance check
        could not fail on the 255-capture set, and reported nothing, which is
        what a working check also reports. It sat six lines under a comment
        saying the column is never assumed.
        """
        status, said = self.run_on(
            self.EVERYDAY_SHAPED + "X03\tmoney\t\ty\n")
        self.assertEqual(status, 1, said)
        self.assertIn("empty utterance", said)
        self.assertIn("X03", said)

    def test_an_empty_cell_that_is_not_the_utterance_is_not_reported(self):
        """The other direction, or the test above passes on a check that
        reports every empty cell anywhere."""
        status, said = self.run_on(
            self.EVERYDAY_SHAPED + "X03\t\tthe kettle needs descaling\ty\n")
        self.assertNotIn("empty utterance", said)

    def test_a_duplicate_row_is_named_by_id_and_not_by_text(self):
        """Even the error path stays blind, which is where text usually leaks."""
        status, said = self.run_on(self.GOOD + "X03\tthe lease ends in March\ta\t1\n")
        self.assertEqual(status, 1)
        self.assertIn("X01", said)
        self.assertIn("X03", said)
        self.assertNotIn("the lease ends in March", said)

    def test_the_utterance_column_comes_from_the_header(self):
        """`everyday.tsv` keeps it third and the devsets keep it second.

        A hard-coded column is the defect that reported zero instances of the
        word "so" in a corpus containing 34 of them.
        """
        third = ("id\tdomain\tutterance\texpect\n"
                 "X01\thome\tthe lease ends in March\tMemory\n")
        status, said = self.run_on(third)
        self.assertEqual(status, 0, said)
        self.assertIn("utterance column    2", said)
        self.assertNotIn("the lease ends in March", said)

    def test_a_file_with_no_utterance_header_is_refused_not_guessed(self):
        """Refusing beats reporting on whichever column happened to be second."""
        status, said = self.run_on("X01\tsomething\tother\n")
        self.assertEqual(status, 1)
        self.assertIn("refuses to report on content rather than guess", said)

    def test_an_uncommented_header_is_not_counted_as_a_capture(self):
        """Counting everyday's header row reported 256 rows for 255 captures."""
        status, said = self.run_on(self.GOOD)
        self.assertEqual(status, 0, said)
        self.assertIn("rows                2", said)

    def test_a_commented_header_is_found_too(self):
        """`heldout.tsv` writes its header inside a comment."""
        status, said = self.run_on("# id\tutterance\tfamily\n"
                                   "X01\tthe lease ends in March\ta\n")
        self.assertEqual(status, 0, said)
        self.assertIn("utterance column    1", said)

    def test_every_sealed_set_passes_its_own_shape_check(self):
        """And reports the capture count its README claims.

        Pinned to literals: a test that reads the count out of the file it is
        checking cannot notice the file changing.
        """
        runner = pathlib.Path(__file__).resolve().parent
        expected = {"consequence": 56, "everyday": 255,
                    "heldout": 389, "adversarial": 120}
        shape = self.shape()
        for name, count in expected.items():
            path = runner / name / f"{name}.tsv"
            if not path.exists():
                continue
            with self.subTest(corpus=name):
                said = io.StringIO()
                with contextlib.redirect_stdout(said):
                    status = shape["main"]([str(path)])
                out = said.getvalue()
                self.assertEqual(status, 0, out)
                self.assertIn(f"rows                {count}", out,
                              f"{name} no longer holds {count} captures; if "
                              f"that was deliberate it opens a generation")

class ThisFileRunsAllOfItselfTests(unittest.TestCase):
    """A class defined after `unittest.main()` is never run as a script.

    Not hypothetical: `CorpusShapeTests` was appended to the end of this file,
    which put it after the `__main__` guard. `python3 -m unittest
    test_score.CorpusShapeTests` ran it and passed, because importing a module
    defines everything in it. `python3 test_score.py` -- which is what CI runs
    -- called `unittest.main()` before the class existed and reported 81 tests
    instead of 88, cleanly, at exit 0.

    That is the recurring shape: a check that never runs and a check that
    passes are the same output. Every edit that appends to this file is one
    keystroke away from it, so the guard is mechanical rather than remembered.
    """

    def test_nothing_is_defined_after_the_main_guard(self):
        source = pathlib.Path(__file__).resolve().read_text(encoding="utf-8")
        marker = 'if __name__ == "__main__":'
        self.assertIn(marker, source)
        after = source.split(marker)[-1]
        self.assertNotIn(
            "\nclass ", after,
            "a class is defined after the __main__ guard, so it is invisible "
            "to `python3 test_score.py` and will not run in CI. Move the "
            "guard back to the end of the file.")
        self.assertNotIn(
            "\ndef ", after,
            "a function is defined after the __main__ guard and will not be "
            "seen when this file runs as a script")


class ReconciliationTests(unittest.TestCase):
    """The exclusions block claims an arithmetic identity, so it is checked.

    The clean denominator for a measure must be the legacy one minus exactly
    the excluded captures recorded as entering that measure. The first version
    worked participation out from the label with `^\\d+` and reported that
    eleven captures fed a thought count whose denominator had fallen by nine:
    an Ambiguous capture returns before the count block, and a capture the
    probe answers with an operation is skipped by it, and both carry a numeric
    label. A reconciliation that does not reconcile is worse than none, because
    it reads as having been checked.
    """

    def check(self):
        """`reconciliation_problems`, lifted out of the script around it."""
        path = (pathlib.Path(__file__).resolve().parent
                / "heldout" / "score.py")
        source = path.read_text(encoding="utf-8")
        start = source.index("def reconciliation_problems(")
        end = source.index("def tally(", start)
        namespace = {}
        exec(compile(source[start:end], str(path), "exec"), namespace)  # noqa: S102
        return namespace["reconciliation_problems"]

    LEGACY = {"dest_ok": 200, "dest_miss": 120,       # destination over 320
              "count_scored": 310, "ambiguous": 69}
    CLEAN = {"dest_ok": 195, "dest_miss": 115,        # destination over 310
             "count_scored": 301, "ambiguous": 68}

    #: Eleven excluded captures: ten feed destination, nine feed the thought
    #: count, one is ambiguous instead. That is the real shape of the held-out
    #: registry and the shape the first version got wrong.
    FEEDS = dict(
        [(f"C{i:03d}", ["destination", "thought count"]) for i in range(1, 10)]
        + [("C010", ["destination"]), ("C011", ["ambiguous/unsafe"])])
    EXCLUDED = set(FEEDS)

    def test_a_consistent_set_of_denominators_reports_nothing(self):
        self.assertEqual(
            self.check()(self.LEGACY, self.CLEAN, self.FEEDS, self.EXCLUDED), [])

    def test_a_capture_credited_to_a_measure_it_never_entered_is_caught(self):
        """The exact defect: the Ambiguous capture listed under thought count."""
        feeds = dict(self.FEEDS)
        feeds["C011"] = ["ambiguous/unsafe", "thought count"]
        problems = self.check()(self.LEGACY, self.CLEAN, feeds, self.EXCLUDED)
        self.assertTrue(any("thought count" in p for p in problems), problems)
        self.assertTrue(any("fell by 9" in p for p in problems), problems)

    def test_a_denominator_that_moved_on_its_own_is_caught(self):
        """The other direction: the tally changed and the exclusions did not."""
        clean = dict(self.CLEAN, count_scored=299)
        problems = self.check()(self.LEGACY, clean, self.FEEDS, self.EXCLUDED)
        self.assertTrue(any("fell by 11" in p for p in problems), problems)

    def test_every_measure_is_checked_and_not_just_the_first(self):
        """Three identities, so a break in any one has to surface."""
        clean = dict(self.CLEAN, dest_ok=190, ambiguous=60)
        problems = self.check()(self.LEGACY, clean, self.FEEDS, self.EXCLUDED)
        self.assertTrue(any("destination" in p for p in problems), problems)
        self.assertTrue(any("ambiguous" in p for p in problems), problems)


class LedgerPerMeasureTotalTests(unittest.TestCase):
    """A running total is a sum, and a sum needs one denominator.

    Until 2026-09-15 the ledger stated one total across every row, and adding
    them up was meaningful only because exactly one sealed measure had ever
    moved. Nothing said so and nothing enforced it, so a guard was added that
    refused a second measure and told whoever hit it to state a total per
    measure instead.

    **On 2026-09-15 a second measure moved** -- everyday clean titles, 245/255
    to 246/255, from the numbered-enumerator boundary -- and the guard fired on
    the real ledger exactly as designed. What replaced the single total is a
    line per measure, so the tests below describe the arrangement that guard
    asked for rather than the one it was protecting.

    The property is unchanged and is the only one that matters: **254/310 and
    246/255 are never added together**, and a measure that moved never goes
    without a total a reader can find at a glance. Both failure directions are
    tested, because a check that only catches the missing total accepts a total
    for a measure nothing moved, and that is how a row gets deleted quietly.
    """

    def ledger(self):
        return ledger_check_module()

    #: Built here rather than by editing the real fixture. A test that edits a
    #: document by string replacement skips itself the day the wording moves,
    #: and a skipped test checks nothing. That is not hypothetical: the
    #: wording moved on 2026-09-15 and took a sibling test with it.
    def written(self, rows, totals):
        body = ["## Sealed-set cost ledger", "",
                "| date | change | measure | from | to | |",
                "| --- | --- | --- | --- | --- | --- |"]
        body.extend(rows)
        body += [""] + totals + ["", "## Next heading", ""]
        return "\n".join(body)

    ONE = "| 2026-09-11 | a change | held-out thought count | 255/310 | 254/310 | **\u22121** |"
    TWO = "| 2026-09-14 | another | consequence thought count | 30/56 | 34/56 | **+4** |"
    ONE_TOTAL = "- **held-out thought count: \u22121 row**, across one change."
    TWO_TOTAL = "- **consequence thought count: +4 rows**, across one change."

    def test_one_measure_with_its_own_total_is_accepted(self):
        """The control. Without it every test below passes for any reason."""
        self.assertEqual(self.ledger().check(
            self.written([self.ONE], [self.ONE_TOTAL])), [])

    def test_two_measures_each_with_its_own_total_is_accepted(self):
        """The arrangement that replaced the single total, and it must pass.

        This is the case the old guard refused. If it ever starts failing,
        the ledger has no legal shape at all for a second measure and the
        next person to move one is stuck.
        """
        self.assertEqual(self.ledger().check(
            self.written([self.ONE, self.TWO],
                         [self.ONE_TOTAL, self.TWO_TOTAL])), [])

    def test_two_measures_under_one_total_is_still_refused(self):
        """The original property: no figure is ever a sum over two sets."""
        problems = self.ledger().check(
            self.written([self.ONE, self.TWO],
                         ["- **held-out thought count: +3 rows**, "
                          "across two changes."]))
        said = " ".join(problems)
        self.assertIn("no running total names it", said)
        self.assertIn("consequence thought count", said,
                      "the report must name the measure that has no total, or "
                      "the fix is a hunt")

    def test_a_total_for_a_measure_no_row_moved_is_refused(self):
        """The other direction, and the one a missing-total check accepts.

        A total whose row was deleted still reads as a live cost. Nothing
        catches that except comparing the two sets of names both ways.
        """
        problems = self.ledger().check(
            self.written([self.ONE], [self.ONE_TOTAL, self.TWO_TOTAL]))
        said = " ".join(problems)
        self.assertIn("no row records a movement in it", said)
        self.assertIn("consequence thought count", said)

    def test_each_measure_keeps_its_own_change_count(self):
        """`across one change` is the denominator of that measure's total.

        The same net figure across one change and across nine are different
        findings, and per-measure totals give the wrong one a second place to
        hide.
        """
        problems = self.ledger().check(
            self.written([self.ONE, self.TWO],
                         [self.ONE_TOTAL,
                          "- **consequence thought count: +4 rows**, "
                          "across three changes."]))
        self.assertTrue(any("change(s)" in p for p in problems), problems)

    def test_the_real_ledger_gives_every_moved_measure_a_total(self):
        """The real document, not a fixture, under the real check."""
        real = self.ledger().BASELINE.read_text(encoding="utf-8")
        self.assertEqual(self.ledger().check(real), [])

    def test_the_checker_self_tests_pass(self):
        """`ledger-check.py` carries its own parser tests and runs them first.

        Repeated here so the failure is attributed. A broken parser makes
        every assertion in this class meaningless, and a suite that reports
        one generic failure sends the reader to the wrong file.
        """
        self.assertEqual(self.ledger().self_test(), [])


class TheProseHalfOfTheLeakCheckIsTriggered(unittest.TestCase):
    """Every file the leak check reads must also start the job that runs it.

    `leak-check.py` walks every Markdown file in the repository, because a
    README beside a corpus is a more tempting place to quote a capture than a
    design document is. The job that runs it, `language-tools`, was gated on
    the `ios` path filter, and that filter lists no Markdown at all -- so a
    documentation-only pull request ran no sealed-set check whatsoever. #56
    nearly committed a held-out capture verbatim into `LANGUAGE_BASELINE.md`
    and was stopped by a person reading the diff.

    This is the totality shape this repository keeps finding in its own
    instruments, one level up: the check was correct, its coverage complete,
    and nothing ran it. So the property under test is not "the filter mentions
    Markdown" -- that is satisfied by `Docs/**`, which would leave `CLAUDE.md`
    and every `Tools/**/README.md` outside a language directory uncovered. It
    is that **no file the check reads is missed by every glob**, tested
    against the files actually on disk.

    What it cannot do, stated because the same hole is everywhere else here:
    it reads the globs, not GitHub's matcher. A glob this translator and
    picomatch disagree about passes here and fails there, or worse.
    """

    ROOT = pathlib.Path(__file__).resolve().parents[2]
    WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"

    #: The filter outputs that gate `language-tools`. Read from the job's own
    #: `if:` rather than written here, so adding a third output to the gate
    #: without widening this test is not possible.
    JOB = "language-tools"

    @staticmethod
    def as_regex(glob):
        """A paths-filter glob as a regex. `**` spans directories, `*` does not."""
        out, i = "", 0
        while i < len(glob):
            if glob.startswith("**/", i):
                out += "(?:[^/]+/)*"
                i += 3
            elif glob.startswith("**", i):
                out += ".*"
                i += 2
            elif glob[i] == "*":
                out += "[^/]*"
                i += 1
            elif glob[i] == "?":
                out += "[^/]"
                i += 1
            else:
                out += re.escape(glob[i])
                i += 1
        return re.compile(f"^{out}$")

    def job_body(self, job=None):
        """The lines of one job, from its key to the next key at that indent.

        `\n  ` is not the delimiter: it is also the prefix of every `\n    `
        inside the body, so splitting on it returns an empty job and every
        test below then passes or fails for a reason that is not the one it
        is named for. It cost a run to notice.
        """
        lines = self.WORKFLOW.read_text(encoding="utf-8").splitlines()
        want = f"  {job or self.JOB}:"
        if want not in lines:
            raise self.failureException(
                f"no job named `{want.strip()}` in the workflow, so every "
                f"assertion about it below would pass vacuously")
        start = lines.index(want)
        for j, later in enumerate(lines[start + 1:], start + 1):
            if re.fullmatch(r"  \S.*", later):
                return "\n".join(lines[start:j])
        return "\n".join(lines[start:])

    def gate_outputs(self):
        """The `needs.changes.outputs.X` names in the job's `if:` condition."""
        return set(re.findall(r"needs\.changes\.outputs\.(\w+)",
                              self.job_body()))

    def globs(self, outputs):
        """Every glob listed under the named filters."""
        text = self.WORKFLOW.read_text(encoding="utf-8")
        found, current = [], None
        #: Skipping the `filters: |` line itself, which sits two levels out
        #: from the block it introduces and so ends the walk immediately.
        block = text[text.index("filters: |"):].splitlines()[1:]
        for line in block:
            if re.fullmatch(r" {12}(\w+):", line):
                current = line.strip().rstrip(":")
            elif line.strip().startswith("- '") and current in outputs:
                found.append(line.strip()[3:-1])
            elif line.strip() and not line.startswith(" " * 12):
                break
        return found

    def markdown_the_check_reads(self):
        """Every `.md` path `leak-check.py` would walk, relative to the root."""
        out = []
        for here, folders, files in os.walk(self.ROOT, followlinks=True):
            folders[:] = [f for f in folders if f != ".git"]
            for name in files:
                if name.endswith(".md"):
                    out.append(str(pathlib.Path(here, name)
                                   .relative_to(self.ROOT)))
        return out

    def test_the_job_is_gated_on_something(self):
        """An `if:` this cannot parse would make every test below vacuous."""
        self.assertTrue(self.gate_outputs(),
                        f"no `needs.changes.outputs.*` found in {self.JOB}")

    def test_the_globs_were_found(self):
        """No globs makes the coverage test below fail for the wrong reason,
        and an empty read is the one input that looks like total failure."""
        self.assertGreater(len(self.globs(self.gate_outputs())), 5)

    def test_the_translator_agrees_with_itself_in_both_directions(self):
        """A matcher that matches nothing reports every file as uncovered; one
        that matches everything reports the filter as complete. Both wrong."""
        star = self.as_regex("**/*.md")
        for hit in ("CLAUDE.md", "Docs/README.md", "Tools/a/b/c.md"):
            self.assertIsNotNone(star.match(hit), hit)
        for miss in ("Docs/README.txt", "notes.md.swift"):
            self.assertIsNone(star.match(miss), miss)
        narrow = self.as_regex("Docs/**")
        self.assertIsNotNone(narrow.match("Docs/a/b.md"))
        self.assertIsNone(narrow.match("CLAUDE.md"))
        one = self.as_regex("Tools/*/x.md")
        self.assertIsNotNone(one.match("Tools/CI/x.md"))
        self.assertIsNone(one.match("Tools/a/b/x.md"))

    def test_every_output_the_gate_names_is_actually_exported(self):
        """The `if:` and the `filters:` block are two of three parts.

        The third is the `outputs:` map on the `changes` job, and it is the
        one nothing above reads. Delete `prose:` from it and the filter still
        evaluates, the `if:` still names it, every other test here still
        passes -- and `needs.changes.outputs.prose` is the empty string, so
        `language-tools` is gated on `ios` alone and a documentation-only
        pull request runs no sealed-set check. That is this pull request's
        own hole, reopened by deleting one line, with the suite green.

        A check that never runs and a check that passes are the same output;
        so is a gate wired to an output nobody exports.
        """
        body = self.job_body("changes")
        for name in sorted(self.gate_outputs()):
            exported = re.search(
                rf"^      {name}: .*steps\.filter\.outputs\.{name}\b",
                body, re.MULTILINE)
            self.assertIsNotNone(
                exported,
                f"`{self.JOB}` is gated on needs.changes.outputs.{name}, but "
                f"the `changes` job exports no `{name}` built from "
                f"steps.filter.outputs.{name}. That expression is the empty "
                f"string at runtime, so the gate silently drops the filter.")

    def test_every_markdown_file_the_check_reads_starts_the_job(self):
        patterns = [self.as_regex(g) for g in self.globs(self.gate_outputs())]
        files = self.markdown_the_check_reads()
        self.assertGreater(len(files), 20, "no Markdown found to check")
        uncovered = [f for f in files
                     if not any(p.match(f) for p in patterns)]
        self.assertEqual(
            uncovered[:10], [],
            f"{len(uncovered)} Markdown file(s) are read by leak-check.py and "
            f"match no path filter that starts language-tools, so changing "
            f"only them runs no sealed-set check at all")

    #: Checks whose inputs are declared rather than walked. A module lands here
    #: by exposing `INPUTS`, a tuple of repository-relative paths it reads.
    def checks_that_declare_their_inputs(self):
        """Every module under Tools/ exposing an `INPUTS` tuple, discovered.

        Discovered rather than listed, because a hand-written list is the same
        defect one level up: it goes stale the next time a check learns to read
        another file, and nothing fails when it does.
        """
        found = {}
        for path in sorted(self.ROOT.glob("Tools/**/*.py")):
            source = path.read_text(encoding="utf-8", errors="replace")
            if "INPUTS" not in source:
                continue
            for node in ast.parse(source).body:
                if not isinstance(node, ast.Assign):
                    continue
                names = [t.id for t in node.targets if isinstance(t, ast.Name)]
                if "INPUTS" not in names:
                    continue
                # literal_eval, never exec: this walks every Python file under
                # Tools/, and a discovery step that runs them would be a far
                # larger thing than the guard it serves.
                found[str(path.relative_to(self.ROOT))] = tuple(
                    ast.literal_eval(node.value))
        return found

    def test_the_declared_input_scan_finds_something(self):
        """Zero declaring modules makes the coverage test below vacuous, and a
        vacuous guard reads exactly like one that holds."""
        self.assertTrue(self.checks_that_declare_their_inputs(),
                        "no module under Tools/ declares INPUTS, so the "
                        "coverage test below asserts nothing")

    def test_every_file_a_gated_check_reads_starts_the_job(self):
        """The generalisation of the Markdown test above, and the reason it
        exists: that one considers `.md` only, so a check reading JSON was
        invisible to it.

        On 2026-09-17 `verify_device_baseline.py` shipped reading three files
        under `Docs/Understanding/Candidate47/` that matched no glob gating
        this job. A pull request editing only them started nothing, so the
        check that detects tampering with them never ran on the commit that
        did it. It was missed twice in twenty minutes: once when the check was
        written, once when it learned to read two more files.
        """
        patterns = [self.as_regex(g) for g in self.globs(self.gate_outputs())]
        uncovered = []
        for module, inputs in self.checks_that_declare_their_inputs().items():
            for rel in inputs:
                if not any(p.match(rel) for p in patterns):
                    uncovered.append(f"{rel} (read by {module})")
        self.assertEqual(
            uncovered, [],
            f"{len(uncovered)} file(s) are read by a check this job runs and "
            f"match no path filter that starts it, so a pull request editing "
            f"only them runs that check not at all")

    def test_a_declared_input_that_is_not_a_file_is_caught(self):
        """INPUTS is prose until something resolves it. A path that does not
        exist is a typo, and a typo is covered by no glob for the wrong
        reason -- or worse, covered by one and silently checking nothing."""
        for module, inputs in self.checks_that_declare_their_inputs().items():
            for rel in inputs:
                self.assertTrue(
                    (self.ROOT / rel).is_file(),
                    f"{module} declares INPUTS entry {rel!r}, which is not a "
                    f"file in this repository")

    def test_a_declaring_check_reads_nothing_it_did_not_declare(self):
        """The declaration can drift from the code. A path literal naming a
        real file in this repository, outside INPUTS, is a read that the
        coverage test above cannot see.

        Resolved against the root rather than matched by shape, so a JSON key
        that happens to look like a path -- `development/candidate47-source.json`
        is one, inside `artifacts_sha256` -- is not mistaken for a read.
        """
        for module, inputs in self.checks_that_declare_their_inputs().items():
            source = (self.ROOT / module).read_text(encoding="utf-8")
            for value, line in self.undeclared_real_files(source, inputs):
                self.fail(
                    f"{module}:{line} names {value!r}, a real file, but "
                    f"INPUTS does not list it -- so nothing checks that "
                    f"editing it starts this job")

    def undeclared_real_files(self, source, declared):
        """Every string literal in `source` naming a real file not in `declared`.

        A literal is tested by resolving it against the root, NOT by looking
        for a path separator in it. An earlier version skipped anything
        without a "/", which silently exempted the whole repository root --
        `ROOT / '.gitleaksignore'` is the natural way to write that read, and
        six of the ten tracked root files match no glob that starts any job,
        so the literals this scan could not see overlapped the files the
        coverage test most needs to be told about.

        That condition was load-bearing for a second reason, which is why it
        is replaced rather than deleted: `is_file()` raises ENAMETOOLONG on
        any literal with a component over 255 bytes, which every long
        slash-free docstring in a checked module is. Catching the error keeps
        that protection without a length cutoff, which would skip a real file
        at a long-but-legal path (measured: 266 characters, every component
        under 40, `is_file()` answers it fine).
        """
        declared = set(declared)
        found = []
        for node in ast.walk(ast.parse(source)):
            if not isinstance(node, ast.Constant):
                continue
            if not isinstance(node.value, str) or node.value in declared:
                continue
            try:
                real = (self.ROOT / node.value).is_file()
            except (OSError, ValueError):
                continue
            if real:
                found.append((node.value, node.lineno))
        return found

    def test_the_undeclared_scan_sees_a_file_at_the_repository_root(self):
        """The falsifier for the condition above, kept rather than described.

        Both halves matter. A root-level literal has no separator in it and
        must still be reported; a long slash-free literal must not raise. The
        first is the hole this replaced, found by the grading thread on #112;
        the second is what the replaced condition was accidentally doing.
        """
        source = (
            "ROOT = 1\n"
            "STRAY = ROOT / '.gitleaksignore'\n"
            "DOC = '" + "x" * 300 + "'\n"
            "OK = 'CLAUDE.md'\n")
        found = self.undeclared_real_files(source, ("CLAUDE.md",))
        self.assertEqual(
            [value for value, _ in found], [".gitleaksignore"],
            "a real file named by a literal at the repository root must be "
            "reported, a declared one must not be, and a 300-character "
            "slash-free literal must neither raise nor be reported")
        self.assertEqual([line for _, line in found], [2])

    #: Observes a check's reads instead of reading its declaration. Kept as a
    #: string because it runs in a subprocess: an audit hook cannot be removed
    #: once installed, and this suite should not carry one for its remaining
    #: tests.
    OBSERVER = """
import importlib.util, json, pathlib, sys
ROOT = pathlib.Path(sys.argv[1]).resolve()
MODULE = ROOT / sys.argv[2]
opened = []
sys.addaudithook(lambda event, args: opened.append(args[0])
                 if event == "open" and args else None)
spec = importlib.util.spec_from_file_location("observed", MODULE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
sys.argv = [str(MODULE), *sys.argv[3:]]
try:
    mod.main()
except SystemExit:
    pass
seen = set()
for entry in opened:
    if not isinstance(entry, (str, bytes)):
        continue
    text = entry if isinstance(entry, str) else entry.decode("utf-8", "replace")
    try:
        rel = pathlib.Path(text).resolve().relative_to(ROOT)
    except (ValueError, OSError):
        continue
    if "__pycache__" not in rel.parts:
        seen.add(str(rel))
print(json.dumps(sorted(seen)))
"""

    def observed_reads(self, module, *args):
        """Every repository file `module` actually opens, by audit hook.

        The declaration tests above are static: they see path literals, and a
        path assembled from parts is invisible to them. This one sees what the
        process opens, however the path was built -- and is blind to the other
        half, branches this invocation does not take. Neither subsumes the
        other, which is why both are here.
        """
        done = subprocess.run(
            [sys.executable, "-c", self.OBSERVER, str(self.ROOT), module, *args],
            capture_output=True, text=True, timeout=300)
        self.assertEqual(done.returncode, 0,
                         f"observing {module} failed: {done.stderr[-2000:]}")
        return json.loads(done.stdout)

    def test_every_file_a_gated_check_actually_opens_starts_the_job(self):
        """The measured counterpart of the declared-coverage test above.

        `--receipt-only` is the invocation observed because its branch set is
        tiny and deterministic: no working tree is walked, so the read set is
        the documents alone. The full run additionally hashes 68 Swift files,
        which `SpeakIt/**` covers already and which would say nothing new here.

        Falsifying this test means planting a COMPUTED read of an uncovered
        file, so that the static scan above cannot see it. Build the path from
        parts that are real files in no checkout: `('.gitleaks' + 'ignore')`
        works, `('.git' + 'leaksignore')` does not. `.git` is a directory in a
        normal clone and a regular FILE in a `git worktree` checkout, so that
        second spelling fails the static scan too, in some working copies and
        not others -- which reads as this test being redundant. Found by the
        grading thread on #112, whose worktree disagreed with CI.
        """
        patterns = [self.as_regex(g) for g in self.globs(self.gate_outputs())]
        for module in self.checks_that_declare_their_inputs():
            reads = self.observed_reads(module, "--receipt-only", "--quiet")
            self.assertTrue(reads, f"observing {module} recorded no reads at "
                                   f"all, so this test asserts nothing")
            uncovered = [r for r in reads
                         if not any(p.match(r) for p in patterns)]
            self.assertEqual(
                uncovered, [],
                f"{module} opens {len(uncovered)} file(s) matched by no path "
                f"filter that starts this job: {uncovered[:5]}")



class EveryMutationInThisFileApplies(unittest.TestCase):
    """A test that mutates a module constant must actually change it.

    Several tests here take a document constant and rewrite one literal in it
    to build the broken version they assert on. When the constant's wording
    moves, the literal stops occurring, `str.replace` returns the string
    unchanged, and the test goes on passing -- against the *unmutated*
    document, which is the one case it was written to say nothing about. It is
    silent: no error, no skip, a green line in the report.

    That happened on 2026-09-15. The ledger's running total was reworded from
    `**-1 row**` to `count: -1 row` and
    `test_a_total_that_disagrees_with_its_rows_fails` kept passing while
    measuring nothing. It was caught by accident, inside a branch, and never
    reached `main` -- but five sibling mutations in this file had the same
    shape and nothing would have caught the next one.

    So the property is mechanical and covers all of them at once: for every
    `CONSTANT.replace(literal, ...)` and `CONSTANT.split(literal)` in this
    file, the literal occurs **exactly once** in that constant. Zero is the
    silent no-op. More than one is the other half: a mutation that fires in
    two places at once is not the edit the test's name describes, and which
    one the assertion is about stops being readable.

    Deliberately not a check that each test asserts its own mutation applied.
    That needs a judgement about which call is the mutation, and this needs
    none: it reads the source, not the intent. The one thing it cannot see is
    a mutation built by string formatting rather than a literal.
    """

    SOURCE = pathlib.Path(__file__).resolve()
    #: The methods whose first argument is matched against the constant.
    MUTATORS = {"replace", "split"}

    def module_constants(self, tree):
        """Module-level `NAME = "..."` assignments, by name."""
        found = {}
        for node in tree.body:
            if not isinstance(node, ast.Assign) or len(node.targets) != 1:
                continue
            target = node.targets[0]
            if (isinstance(target, ast.Name)
                    and isinstance(node.value, ast.Constant)
                    and isinstance(node.value.value, str)):
                found[target.id] = node.value.value
        return found

    def mutations(self):
        """Every (line, constant name, literal) this file mutates."""
        tree = ast.parse(self.SOURCE.read_text(encoding="utf-8"))
        constants = self.module_constants(tree)
        out = []
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            func = node.func
            if not (isinstance(func, ast.Attribute) and func.attr in self.MUTATORS):
                continue
            if not (isinstance(func.value, ast.Name) and func.value.id in constants):
                continue
            if not (node.args and isinstance(node.args[0], ast.Constant)
                    and isinstance(node.args[0].value, str)):
                continue
            out.append((node.lineno, func.value.id, node.args[0].value))
        return out

    def test_the_scan_finds_mutations_at_all(self):
        """Nothing found makes the test below pass for the emptiest reason."""
        self.assertGreaterEqual(
            len(self.mutations()), 5,
            "no constant mutations found -- either they moved to a shape this "
            "cannot read, or the scan is broken; both need looking at, and "
            "neither is a clean run")

    def test_every_mutated_literal_occurs_exactly_once(self):
        tree = ast.parse(self.SOURCE.read_text(encoding="utf-8"))
        constants = self.module_constants(tree)
        wrong = []
        for line, name, literal in self.mutations():
            count = constants[name].count(literal)
            if count != 1:
                wrong.append(f"{self.SOURCE.name}:{line}  {name}.replace/split "
                             f"({literal!r}) occurs {count} times in {name}")
        self.assertEqual(
            wrong, [],
            "a mutation that does not apply exactly once: 0 means the test "
            "runs against the unmutated document and passes for that reason; "
            "more than 1 means it changes somewhere the test's name does not "
            "describe. Fix the literal, not this check.")


if __name__ == "__main__":
    unittest.main()
