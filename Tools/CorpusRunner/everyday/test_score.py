"""Regression coverage for the everyday-set instrument itself.

The scorer is the thing being tested here, not the parser. Every fixture is
hand-written probe output, so these tests run anywhere — including a container
with no Swift toolchain, where the pipeline itself cannot be executed at all
(five of its files need Apple's NaturalLanguage framework).

That separation is the point. A measuring instrument that has never been
checked against a known input is not evidence about anything.
"""
import pathlib
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
HEADER = "id\tdomain\tutterance\texpect\tkeep\treject\tfamilies\tnote\n"


def block(utterance, *rows, operations=()):
    """Builds probe output in exactly the layout Tools/PipelineProbe prints."""
    out = [f'── "{utterance}"']
    for operation in operations:
        out.append(f"   operation:   {operation} target=nil")
    if not rows and not operations:
        out.append("   items:       NONE  ← capture produced nothing")
    for index, row in enumerate(rows, start=1):
        out.append(f"   item {index} of {len(rows)}:")
        out.append(f"     row title:  {row.get('title', '')}")
        out.append(f"     route:      {row.get('route', 'Today')}   "
                   f"type: {row.get('type', 'task')}   category: general   "
                   f"priority: normal")
        out.append(f"     due:        {row.get('due', 'nil')}")
        out.append(f"     remind:     {row.get('remind', 'nil')}   "
                   f"delivery: notification")
        out.append("     temporal:   none")
        if row.get("person"):
            out.append(f"     person:     {row['person']}")
        if row.get("list"):
            out.append(f"     list:       {row['list']}")
        out.append("     state:      resolved")
        if row.get("quote"):
            out.append(f"     quote:      {row['quote']}")
    return "\n".join(out) + "\n"


class ScoreTests(unittest.TestCase):
    def score(self, labels, probe, *flags):
        with tempfile.TemporaryDirectory() as root:
            directory = pathlib.Path(root) / "everyday"
            directory.mkdir()
            cases = directory / "everyday.tsv"
            cases.write_text(HEADER + labels)
            output = directory / "probe.txt"
            output.write_text(probe)
            return subprocess.check_output(
                [sys.executable, str(HERE / "score.py"), str(cases), str(output),
                 *flags],
                text=True,
            )

    # --- routing ---------------------------------------------------------

    def test_correct_routing_passes(self):
        result = self.score(
            "A1\twork-school\tcall the vet\tToday:task\t-\t-\tfiller\tnote\n",
            block("call the vet", {"title": "Call the vet", "route": "Today"}),
        )
        self.assertIn("1/1    (100.0%)", result)

    def test_memory_capture_routed_to_today_is_a_routing_failure(self):
        result = self.score(
            "A1\twork-school\tthe exam is open book\tMemory:note\t-\t-\treference\tnote\n",
            block("the exam is open book",
                  {"title": "Exam is open book", "route": "Today"}),
            "--failures",
        )
        self.assertIn("ROUTING    A1", result)
        self.assertIn("want {'Memory': 1} · got {'Today': 1}", result)

    # --- splitting and merging ------------------------------------------

    def test_extra_rows_are_counted_as_over_segmentation(self):
        result = self.score(
            "A1\tfreelance\twater the plants\tToday:task\t-\t-\tmulti-thought\tnote\n",
            block("water the plants",
                  {"title": "Water"}, {"title": "The plants"}),
        )
        self.assertIn("over-segmented (split)      1", result)
        self.assertIn("under-segmented (merge)     0", result)

    def test_missing_rows_are_counted_as_under_segmentation(self):
        result = self.score(
            "A1\tfreelance\tcall Sam and email Jo\tToday:task|Today:task\t-\t-\tmulti-thought\tnote\n",
            block("call Sam and email Jo", {"title": "Call Sam and email Jo"}),
        )
        self.assertIn("under-segmented (merge)     1", result)
        self.assertIn("over-segmented (split)      0", result)

    # --- loss -------------------------------------------------------------

    def test_a_dropped_negation_is_counted_as_loss(self):
        result = self.score(
            "A1\tfamily-health\tSarah has no dairy at all\tMemory:note\tno dairy\t-\tnegation\tnote\n",
            block("Sarah has no dairy at all",
                  {"title": "Sarah dairy at all", "route": "Memory", "type": "note"}),
            "--failures",
        )
        self.assertIn("LOSS       A1", result)
        self.assertIn("gone: no dairy", result)

    def test_information_surviving_only_in_the_quote_is_not_loss(self):
        result = self.score(
            "A1\tfamily-health\tSarah has no dairy at all\tMemory:note\tno dairy\t-\tnegation\tnote\n",
            block("Sarah has no dairy at all",
                  {"title": "Sarah dairy", "route": "Memory", "type": "note",
                   "quote": "Sarah has no dairy at all"}),
        )
        self.assertNotIn("LOSS", result)

    def test_a_date_is_read_from_the_due_line(self):
        result = self.score(
            "A1\twork-school\tsend it tomorrow\tToday:task\tAug 4\t-\tdate\tnote\n",
            block("send it tomorrow",
                  {"title": "Send it", "due": "Tue Aug 4 (day only)"}),
        )
        self.assertNotIn("LOSS", result)

    def test_a_time_is_read_from_the_reminder_line(self):
        result = self.score(
            "A1\tfamily-health\tpick her up at 5:30\tToday:task\t17:30\t-\ttime\tnote\n",
            block("pick her up at 5:30",
                  {"title": "Pick her up", "remind": "Tue Aug 4 17:30"}),
        )
        self.assertNotIn("LOSS", result)

    # --- invention --------------------------------------------------------

    def test_an_unresolved_correction_is_counted_as_invention(self):
        result = self.score(
            "A1\twork-school\tfive slides actually six slides\tToday:task\tsix\tfive slides\tself-correction\tnote\n",
            block("five slides actually six slides",
                  {"title": "Five slides actually six slides"}),
            "--failures",
        )
        self.assertIn("INVENTION  A1", result)
        self.assertIn("reading still shows: five slides", result)

    def test_a_superseded_value_left_only_in_the_quote_is_not_invention(self):
        """The quote is meant to hold the speaker's own words, wrong ones included."""
        result = self.score(
            "A1\twork-school\tfive slides actually six slides\tToday:task\tsix\tfive slides\tself-correction\tnote\n",
            block("five slides actually six slides",
                  {"title": "Six slides",
                   "quote": "five slides actually six slides"}),
        )
        self.assertNotIn("INVENTION", result)
        self.assertIn("invention", result)  # the column still exists

    # --- ambiguity and harm ----------------------------------------------

    def test_scheduling_an_ambiguous_capture_is_unsafe(self):
        result = self.score(
            "A1\tmoney-travel\tthe flight is 7:05 or 7:50\tAmbiguous\t-\t-\tambiguous\tnote\n",
            block("the flight is 7:05 or 7:50",
                  {"title": "Flight", "remind": "Mon Aug 3 19:05"}),
            "--failures",
        )
        self.assertIn("ACTED ON ANYWAY             1", result)
        self.assertIn("UNSAFE     A1", result)

    def test_preserving_an_ambiguous_capture_without_acting_is_safe(self):
        result = self.score(
            "A1\tmoney-travel\tthe flight is 7:05 or 7:50\tAmbiguous\t-\t-\tambiguous\tnote\n",
            block("the flight is 7:05 or 7:50",
                  {"title": "Flight is 7:05 or 7:50", "route": "Memory",
                   "type": "note"}),
        )
        self.assertIn("ACTED ON ANYWAY             0", result)

    def test_an_ambiguous_capture_producing_nothing_is_still_content_loss(self):
        result = self.score(
            "A1\tmoney-travel\tuh I dunno\tAmbiguous\t-\t-\tambiguous\tnote\n",
            block("uh I dunno"),
        )
        self.assertIn("produced nothing at all     1", result)

    # --- operations -------------------------------------------------------

    def test_an_expected_operation_is_scored_on_the_operation_line(self):
        result = self.score(
            "A1\twork-school\tnever mind the poster\tOp:cancel\t-\t-\tcancellation\tnote\n",
            block("never mind the poster", operations=["withdraw"]),
        )
        self.assertIn("1/1    (100.0%)", result)

    def test_an_operation_target_counts_as_visible_output(self):
        """A withdrawal that named the thought did not lose it."""
        result = self.score(
            "A1\twork-school\tnever mind the poster session\tOp:cancel\tposter session\t-\tcancellation\tn\n",
            block("never mind the poster session",
                  operations=["withdraw"]).replace("target=nil",
                                                   "target=poster session"),
        )
        self.assertNotIn("LOSS", result)

    def test_a_withdrawal_that_named_nothing_is_still_content_loss(self):
        result = self.score(
            "A1\twork-school\tnever mind the poster session\tOp:cancel\tposter session\t-\tcancellation\tn\n",
            block("never mind the poster session", operations=["withdraw"]),
            "--failures",
        )
        self.assertIn("LOSS       A1", result)

    def test_a_cancellation_that_produced_a_task_instead_is_a_routing_failure(self):
        result = self.score(
            "A1\twork-school\tnever mind the poster\tOp:cancel\t-\t-\tcancellation\tnote\n",
            block("never mind the poster", {"title": "Mind the poster"}),
            "--failures",
        )
        self.assertIn("ROUTING    A1", result)
        self.assertIn("operations=none", result)

    # --- reporting --------------------------------------------------------

    def test_missing_probe_results_are_visible_rather_than_silently_dropped(self):
        result = self.score(
            "A1\twork-school\tsomething never run\tToday:task\t-\t-\tfiller\tnote\n", "")
        self.assertIn("missing probe results       1", result)

    def test_families_are_reported_separately_and_worst_first(self):
        labels = (
            "A1\twork-school\tSarah has no dairy\tMemory:note\tno dairy\t-\tnegation\tn\n"
            "A2\twork-school\tcall the vet\tToday:task\t-\t-\tfiller\tn\n"
        )
        probe = (block("Sarah has no dairy",
                       {"title": "Sarah dairy", "route": "Today"})
                 + block("call the vet", {"title": "Call the vet"}))
        result = self.score(labels, probe)
        self.assertIn("PER FAMILY", result)
        families = result.split("PER FAMILY")[1]
        self.assertLess(families.index("negation"), families.index("filler"),
                        "the broken family must be listed before the healthy one")

    def test_domains_are_reported_separately(self):
        labels = (
            "A1\twork-school\tcall the vet\tToday:task\t-\t-\tfiller\tn\n"
            "A2\tfreelance\tinvoice Halvorsen\tToday:task\t-\t-\tproper-noun\tn\n"
        )
        probe = (block("call the vet", {"title": "Call the vet"})
                 + block("invoice Halvorsen", {"title": "Invoice", "route": "Memory"}))
        result = self.score(labels, probe)
        self.assertIn("work-school", result)
        self.assertIn("freelance", result)
        # The healthy domain must not be dragged down by the broken one.
        work = [l for l in result.splitlines() if l.startswith("work-school")][0]
        self.assertIn("100.0%", work)

    def test_failure_output_carries_the_input_and_the_pipeline_output(self):
        result = self.score(
            "A1\twork-school\tthe exam is open book\tMemory:note\t-\t-\treference\twhy\n",
            block("the exam is open book", {"title": "Exam", "route": "Today"}),
            "--failures",
        )
        self.assertIn('said:     "the exam is open book"', result)
        self.assertIn("expected: Memory:note   — why", result)
        self.assertIn("row title:  Exam", result)
        self.assertIn("Do NOT use them to steer a fix", result)


class SealTests(unittest.TestCase):
    """The set must stay sealed unless a flag explicitly unseals it.

    A scorer that needs a flag to stay sealed is safe to run from a harness; one
    that prints failures by default is not, because the harness cannot un-print
    them. This test holds the scorer on the safe side of that line.
    """

    LABELS = ("A1\twork-school\tthe exam is open book\tMemory:note\tno exam\t-\treference\tn\n")
    PROBE = None

    def run_score(self, *flags):
        return ScoreTests.score(
            self, self.LABELS,
            block("the exam is open book", {"title": "Exam", "route": "Today"}),
            *flags)

    def test_default_output_reveals_no_failure_detail(self):
        result = self.run_score()
        self.assertNotIn("FAILURES", result)
        self.assertNotIn("the exam is open book", result)
        self.assertNotIn("ROUTING", result)
        # The rates themselves are still reported.
        self.assertIn("0/1    (  0.0%)", result)

    def test_failures_flag_unseals_and_says_so(self):
        for flag in ("--failures", "--verbose"):
            with self.subTest(flag=flag):
                result = self.run_score(flag)
                self.assertIn("FAILURES", result)
                self.assertIn("the exam is open book", result)

    def test_an_unrecognised_flag_does_not_unseal(self):
        result = self.run_score("--summary")
        self.assertNotIn("FAILURES", result)


class TitleHygieneTests(unittest.TestCase):
    """The title measure must only fire on material that is never content.

    Its value depends entirely on its false-positive rate: a hygiene number
    that flags ordinary words is worse than no number, because someone will
    chase it.
    """

    def score(self, utterance, title, keep="-"):
        return ScoreTests.score(
            self,
            f"A1\twork-school\t{utterance}\tToday:task\t{keep}\t-\tfiller\tn\n",
            block(utterance, {"title": title}),
            "--failures",
        )

    def assert_clean(self, utterance, title):
        result = self.score(utterance, title)
        self.assertNotIn("TITLE      A1", result,
                         f"false positive on title {title!r}")

    def assert_defect(self, utterance, title, defect):
        result = self.score(utterance, title)
        self.assertIn("TITLE      A1", result)
        self.assertIn(defect, result)

    # --- fires where it should -------------------------------------------

    def test_hesitation_left_in_the_title(self):
        self.assert_defect("um send the deck", "Um send the deck",
                           "hesitation kept")

    def test_farewell_left_in_the_title(self):
        self.assert_defect("redo the deck bye", "Redo the deck bye",
                           "farewell kept")

    def test_title_opening_on_a_conjunction(self):
        self.assert_defect("call Sam and email Jo", "And email Jo",
                           "opens on 'and'")

    def test_numbered_preamble_left_in_the_title(self):
        self.assert_defect("number one finalize the budget",
                           "Number one finalize the budget",
                           "preamble 'number one' kept")

    def test_stutter_left_in_the_title(self):
        self.assert_defect("I need to I need to finish the doc",
                           "I need to I need to finish the doc",
                           "stutter kept: i need to")

    def test_an_empty_title_is_a_defect(self):
        self.assert_defect("um yeah so", "", "empty title")

    def test_a_long_capture_titled_with_itself_was_never_summarised(self):
        utterance = ("so basically the deploy went out early and now the docs "
                     "are wrong so I need to update the docs")
        self.assert_defect(utterance, utterance, "title is the whole capture")

    # --- stays quiet where it should -------------------------------------

    def test_an_ordinary_title_is_clean(self):
        self.assert_clean("send Priya the deck", "Send Priya the deck")

    def test_a_short_capture_titled_with_itself_is_not_a_defect(self):
        """Most captures are short, and their own words are the right title."""
        self.assert_clean("call the vet", "Call the vet")

    def test_a_business_name_that_starts_with_a_filler_sound_is_clean(self):
        self.assert_clean("go to Umberto's for bread", "Go to Umberto's for bread")

    def test_ordinary_words_that_double_as_fillers_are_not_flagged(self):
        """like, basically and honestly are real words often enough."""
        self.assert_clean("things I like about the new plan",
                          "Things I like about the new plan")
        self.assert_clean("write the basically finished draft",
                          "Write the basically finished draft")

    def test_a_repeated_word_that_is_not_a_stutter_is_clean(self):
        self.assert_clean("the report on the report format",
                          "The report on the report format")

    def test_that_used_as_a_determiner_mid_title_is_clean(self):
        self.assert_clean("buy that oat cereal", "Buy that oat cereal")

    def test_a_title_ending_in_a_word_containing_bye_is_clean(self):
        self.assert_clean("email Abye Okafor", "Email Abye Okafor")

    def test_title_hygiene_appears_in_the_report_with_a_breakdown(self):
        result = self.score("um send the deck", "Um send the deck")
        self.assertIn("TITLE HYGIENE", result)
        self.assertIn("hesitation kept", result)
        self.assertIn("lower bound", result)


def leak_check_module():
    """leak-check.py has a hyphen in its name, so it needs loading by path."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "leak_check", HERE / "leak-check.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class LeakCheckTests(unittest.TestCase):
    """The boundary guard has to read the right field to mean anything.

    A leak check comparing the wrong column passes for the wrong reason, which
    is worse than failing: it reads as proof that nothing leaked.
    """

    def setUp(self):
        self.leak = leak_check_module()

    def test_the_utterance_column_is_read_from_the_header(self):
        for header, expected in (
            ("id\tutterance\tfamily\texpected_destination\texpected_thoughts", 1),
            ("id\tdomain\tutterance\texpect\tkeep", 2),
            ("# id\tutterance\tfamily", 1),
            ("utterance\tnote", 0),
        ):
            with self.subTest(header=header):
                self.assertEqual(
                    self.leak.utterance_column(header.split("\n")), expected)

    def test_a_corpus_laid_out_differently_is_still_read_correctly(self):
        with tempfile.TemporaryDirectory() as root:
            path = pathlib.Path(root) / "odd.tsv"
            path.write_text(
                "# a corpus that puts the capture fourth\n"
                "id\tfamily\tnote\tutterance\n"
                "X1\tnegation\twhy\tSarah has no dairy at all\n")
            self.assertEqual(self.leak.harvest(path),
                             ["Sarah has no dairy at all"])

    def test_a_corpus_with_no_utterance_header_fails_loudly(self):
        """Silently skipping it would leave that corpus unchecked forever."""
        with tempfile.TemporaryDirectory() as root:
            path = pathlib.Path(root) / "headerless.tsv"
            path.write_text("X1\tsome capture text\tnegation\n")
            with self.assertRaises(SystemExit):
                self.leak.harvest(path)

    def test_the_header_row_is_not_harvested_as_a_capture(self):
        with tempfile.TemporaryDirectory() as root:
            path = pathlib.Path(root) / "set.tsv"
            path.write_text("id\tutterance\nX1\tbuy milk\n")
            self.assertEqual(self.leak.harvest(path), ["buy milk"])

    def test_the_existing_held_out_set_harvests_its_documented_size(self):
        """An anchor against a real file: heldout/README.md says 389."""
        path = HERE.parent / "heldout" / "heldout.tsv"
        if not path.exists():
            self.skipTest("heldout.tsv not present")
        self.assertEqual(len(self.leak.harvest(path)), 389)


class DevsetScorerSealTests(unittest.TestCase):
    """A development scorer must not be aimable at a held-out set.

    `route-score.sh` and `score.sh` take a set NAME and build a path from it.
    Until this guard, `../heldout/heldout` resolved to a real file, and because
    `route-score.sh` already uses the held-out scorer on the same five columns,
    `route-score.sh ../heldout/heldout --verbose` printed every held-out
    failure. The entry points that refuse arguments do not help: the hole was
    one level down, in the scorer they call.
    """

    DEVSETS = HERE.parent / "devsets"

    def run_scorer(self, script, name):
        path = self.DEVSETS / script
        if not path.exists():
            self.skipTest(f"{script} not present")
        return subprocess.run([str(path), name, "--verbose"],
                              capture_output=True, text=True)

    def test_a_pathed_name_cannot_reach_a_held_out_set(self):
        for script in ("route-score.sh", "score.sh"):
            for name in ("../heldout/heldout", "../everyday/everyday",
                         "/etc/passwd", "../../../etc/passwd"):
                with self.subTest(script=script, name=name):
                    result = self.run_scorer(script, name)
                    self.assertEqual(result.returncode, 2,
                                     f"{script} accepted {name!r}")
                    combined = result.stdout + result.stderr
                    self.assertNotIn("HELD-OUT SET", combined)
                    self.assertNotIn("remind me to uh remind me", combined)

    def test_an_empty_or_flag_like_name_is_refused(self):
        """Refused, not necessarily by the same route.

        An empty name is caught by the shell's own `${1:?}` check and exits 1;
        a flag-like one is caught by the name guard and exits 2. Both refuse
        and neither reaches a corpus, which is what matters — asserting the
        exact code would make this test about bash rather than about sealing.
        """
        for script in ("route-score.sh", "score.sh"):
            for name in ("", "--verbose", "-rf"):
                with self.subTest(script=script, name=name):
                    result = self.run_scorer(script, name)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("HELD-OUT SET",
                                     result.stdout + result.stderr)

    def test_a_real_development_set_name_is_still_accepted(self):
        """The guard must not break the thing it protects."""
        result = self.run_scorer("route-score.sh", "routed")
        self.assertNotEqual(
            result.returncode, 2,
            "a bare development set name must pass the name check")
        self.assertNotIn("is not a development set name",
                         result.stdout + result.stderr)


class CorpusTests(unittest.TestCase):
    """The committed set itself, checked for the properties it claims."""

    def rows(self):
        rows = []
        for line in open(HERE / "everyday.tsv"):
            parts = line.rstrip("\n").split("\t")
            if parts[0] == "id" or not line.strip():
                continue
            self.assertEqual(len(parts), 8, f"wrong column count: {parts[0]}")
            rows.append(parts)
        return rows

    def test_every_case_is_well_formed_and_unique(self):
        rows = self.rows()
        self.assertGreaterEqual(len(rows), 200)
        ids = [r[0] for r in rows]
        self.assertEqual(len(ids), len(set(ids)), "duplicate case id")
        utterances = [r[2].lower() for r in rows]
        self.assertEqual(len(utterances), len(set(utterances)),
                         "the same capture appears twice")

    def test_every_domain_carries_a_comparable_number_of_captures(self):
        from collections import Counter
        counts = Counter(r[1] for r in self.rows())
        self.assertGreaterEqual(len(counts), 5)
        self.assertLessEqual(max(counts.values()) - min(counts.values()), 5,
                             "domains must stay comparable or the by-domain "
                             "rates cannot be read against each other")

    def test_expectations_use_the_closed_vocabulary(self):
        routes = {"Today", "Memory"}
        types = {"task", "shopping", "idea", "person", "event", "note"}
        for row in self.rows():
            for token in row[3].split("|"):
                if token == "Ambiguous" or token.startswith("Op:"):
                    continue
                route, _, item_type = token.partition(":")
                self.assertIn(route, routes, f"{row[0]}: bad route {token}")
                self.assertIn(item_type, types, f"{row[0]}: bad type {token}")

    def test_reject_spans_are_long_enough_to_match_deliberately(self):
        """A one- or two-character reject span matches by accident."""
        for row in self.rows():
            for span in row[5].split("|"):
                if span in ("", "-"):
                    continue
                self.assertGreaterEqual(
                    len(span), 3,
                    f"{row[0]}: reject span {span!r} is too short to be meaningful")

    def test_keep_spans_are_long_enough_to_match_deliberately(self):
        for row in self.rows():
            for span in row[4].split("|"):
                if span in ("", "-"):
                    continue
                self.assertGreaterEqual(
                    len(span), 2,
                    f"{row[0]}: keep span {span!r} is too short to be meaningful")

    def test_ambiguous_cases_expect_nothing_else(self):
        for row in self.rows():
            tokens = row[3].split("|")
            if "Ambiguous" in tokens:
                self.assertEqual(tokens, ["Ambiguous"],
                                 f"{row[0]}: ambiguous cases carry no other expectation")

    def test_every_asserted_date_matches_the_real_calendar(self):
        """A wrong weekday here would be a false failure forever.

        The reference frame is Monday 2026-08-03 America/Toronto. Every `Aug N`
        span is checked against the actual calendar: the utterance must name
        that weekday, say "tomorrow" for the following day, or name the day
        number outright. Contested readings — "next Tuesday" spoken on a Monday
        — are deliberately not asserted anywhere in the set, because baking an
        argument into a held-out label makes the baseline wrong rather than
        strict.
        """
        import datetime
        import re
        reference = datetime.date(2026, 8, 3)
        self.assertEqual(reference.strftime("%A"), "Monday")
        checked = 0
        for row in self.rows():
            spoken = row[2].lower()
            for column in (4, 5):
                for span in row[column].split("|"):
                    match = re.fullmatch(r"Aug (\d+)", span.strip())
                    if not match:
                        continue
                    checked += 1
                    day = datetime.date(2026, 8, int(match.group(1)))
                    weekday = day.strftime("%A").lower()
                    named = weekday in spoken
                    tomorrow = ("tomorrow" in spoken
                                and day == reference + datetime.timedelta(days=1))
                    numbered = re.search(rf"\b{day.day}(st|nd|rd|th)?\b", spoken)
                    self.assertTrue(
                        named or tomorrow or numbered,
                        f"{row[0]}: {span} is a {weekday}, which the capture "
                        f"never names: {row[2]!r}")
        self.assertGreaterEqual(checked, 10,
                                "date assertions have gone missing from the set")

    def test_every_span_could_actually_match(self):
        """A span that appears nowhere is a dead check that reads as a pass."""
        import re
        derived = re.compile(r"^(aug \d+|\d{1,2} \d{2})$")

        def norm(text):
            return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()

        for row in self.rows():
            spoken = norm(row[2])
            for column, kind in ((4, "keep"), (5, "reject")):
                for span in row[column].split("|"):
                    if span in ("", "-"):
                        continue
                    folded = norm(span)
                    self.assertTrue(
                        folded in spoken or derived.match(folded),
                        f"{row[0]}: {kind} span {span!r} is neither in the "
                        f"capture nor a date or time the probe derives, so it "
                        f"can never match: {row[2]!r}")

    def test_no_reject_span_is_material_title_hygiene_already_measures(self):
        """Two measures must not both move on one fix.

        Seven captures once listed "bye" as a rejected value. A farewell left
        in a title is a title defect, and `title` already counts it, so the
        discourse-framing change of 2026-09-11 moved `invention` from 5/19 to
        12/19 without a single superseded value being resolved — one fix
        counted twice, which is exactly how apparent progress gets
        manufactured. Farewells belong to title hygiene; `invention` is for a
        value the reading asserts that the speaker superseded or never meant.
        """
        farewells = {"bye", "goodbye", "byebye", "thanks", "thank you",
                     "cheers", "see you", "that's it", "ta"}
        for row in self.rows():
            for span in row[5].split("|"):
                if span in ("", "-"):
                    continue
                self.assertNotIn(
                    span.strip().lower(), farewells,
                    f"{row[0]}: {span!r} is a farewell, which `title` already "
                    f"measures. Counting it here too makes one fix move two "
                    f"metrics.")

    def test_the_set_does_not_overlap_a_corpus_that_is_tuned_against(self):
        result = subprocess.run(
            [sys.executable, str(HERE / "leak-check.py")],
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0,
                         f"leak check failed:\n{result.stdout}\n{result.stderr}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
