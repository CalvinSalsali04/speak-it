"""Regression coverage for the everyday-set instrument itself.

The scorer is the thing being tested here, not the parser. Every fixture is
hand-written probe output, so these tests run anywhere — including a container
with no Swift toolchain, where the pipeline itself cannot be executed at all
(five of its files need Apple's NaturalLanguage framework).

That separation is the point. A measuring instrument that has never been
checked against a known input is not evidence about anything.
"""
import collections
import contextlib
import io
import pathlib
import re
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

    def test_the_ambiguous_denominator_is_reported(self):
        """The safety rate is a fraction, and this is its denominator.

        `ACTED ON ANYWAY` is printed as a percentage `of them`, so a silent
        zero here does not read as a missing number — it divides by a floor of
        one and reports a single unsafe action as 100%. Two ambiguous captures
        rather than one, so the assertion cannot pass on that floor.
        """
        result = self.score(
            "A1\tmoney-travel\tthe flight is 7:05 or 7:50\tAmbiguous\t-\t-\tambiguous\tnote\n"
            "A2\tmoney-travel\tit is either Thursday or Friday\tAmbiguous\t-\t-\tambiguous\tnote\n",
            block("the flight is 7:05 or 7:50",
                  {"title": "Flight", "remind": "Mon Aug 3 19:05"})
            + block("it is either Thursday or Friday",
                    {"title": "Either Thursday or Friday", "route": "Memory",
                     "type": "note"}),
        )
        self.assertIn("genuinely ambiguous         2", result)
        self.assertIn("ACTED ON ANYWAY             1  (50.0% of them)", result)

    def test_a_wrong_thought_count_is_reported_on_the_count_column(self):
        """`count` has its own column, and split/merge do not stand in for it.

        Over- and under-segmentation are tallied next to this measure and are
        already asserted elsewhere, so a `count` that always passed would leave
        those tallies intact and report every capture correctly segmented while
        the merge line beside it says otherwise.

        The assertion is on the failure line rather than on the count column,
        because the two rate columns cannot move independently: routing
        compares a Counter of wanted routes against produced ones, so any
        wrong row count fails routing as well and the column alone does not
        say which measure noticed. The named failure entry does.
        """
        result = self.score(
            "A1\tfreelance\tcall Sam and email Jo\tToday:task|Today:task\t-\t-\tmulti-thought\tnote\n",
            block("call Sam and email Jo", {"title": "Call Sam and email Jo"}),
            "--failures",
        )
        self.assertIn("COUNT      A1", result)
        self.assertIn("want 2 rows · got 1", result)
        self.assertIn("under-segmented (merge)     1", result)

    def test_type_agreement_is_also_reported_free_of_the_count_failure(self):
        """The plain figure cannot separate a type error from a count error.

        `want_types` and `have_types` are Counters over rows, so a capture the
        pipeline split or merged wrongly differs by a whole row and can never
        match, whatever types it chose. The plain line therefore carries every
        `count` failure inside it and reads as though types were the problem.
        The second line conditions on correct segmentation and is the only one
        that says anything about types.

        The fixture proves both halves at once: one capture merged (right type,
        wrong row count) and one segmented correctly with a wrong type. The
        plain line sees two failures, the conditioned line sees the one that is
        actually about a type.
        """
        result = self.score(
            "A1\tfreelance\tcall Sam and email Jo\tToday:task|Today:task\t-\t-\tmulti-thought\tn\n"
            "A2\tfreelance\tthe exam is open book\tMemory:note\t-\t-\treference\tn\n",
            block("call Sam and email Jo",
                  {"title": "Call Sam and email Jo", "type": "task"})
            + block("the exam is open book",
                    {"title": "Exam is open book", "route": "Memory", "type": "task"}),
        )
        self.assertIn("item type matched the label 0/2", result)
        self.assertIn("of those segmented right  0/1", result)

    def test_type_agreement_conditioned_figure_counts_a_clean_capture(self):
        """A correctly segmented, correctly typed capture reaches both lines."""
        result = self.score(
            "A1\tfreelance\tcall Sam\tToday:task\t-\t-\tfiller\tn\n",
            block("call Sam", {"title": "Call Sam", "type": "task"}),
        )
        self.assertIn("item type matched the label 1/1", result)
        self.assertIn("of those segmented right  1/1", result)

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

    def prose_world(self, docs, captures=("alpha bravo charlie delta echo foxtrot",)):
        """A repository-shaped fixture: one sealed set, some Markdown.

        The real check walks `ROOT`, so the module's `ROOT`, `SEALED_ALL` and
        `PROSE_DOCUMENTED` are pointed at the temporary tree for the duration.
        """
        root = pathlib.Path(tempfile.mkdtemp())
        sealed = root / "sealed.tsv"
        sealed.write_text("id\tutterance\n" + "".join(
            f"S{i}\t{c}\n" for i, c in enumerate(captures)))
        for name, body in docs.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body)
        self.leak.ROOT = root
        self.leak.SEALED_ALL = [sealed]
        self.leak.PROSE_DOCUMENTED = {}
        return root

    def test_a_sealed_capture_quoted_in_a_document_is_a_leak(self):
        self.prose_world({"Docs/notes.md": "We saw `alpha bravo charlie delta "
                                           "echo foxtrot` go wrong.\n"})
        self.assertFalse(self.leak.check_prose())

    def test_a_quotation_wrapped_across_lines_is_still_caught(self):
        """The failure mode that would have made this check decorative.

        Prose wraps. A capture quoted inside a paragraph is routinely split
        over two lines, so a check that normalised line by line would pass on
        exactly the leaks a human would call most obvious.
        """
        self.prose_world({"Docs/wrapped.md":
                          "the sentence was alpha bravo charlie\n"
                          "delta echo foxtrot and it failed\n"})
        self.assertFalse(self.leak.check_prose())

    def test_a_capture_too_short_to_protect_is_counted_not_flagged(self):
        """Stated coverage rather than implied coverage.

        A three-word capture appears in ordinary prose by accident, so it is
        out of scope -- and the count of what is out of scope prints on every
        run, so the size of the gap is visible instead of inferred.
        """
        root = self.prose_world({"Docs/short.md": "I said call mum today.\n"},
                                captures=("call mum today",))
        self.assertTrue(self.leak.check_prose())

    def test_a_documented_leak_is_still_counted_but_does_not_gate(self):
        """Same rule as a `KNOWN:` row: the marker moves the exit, not the count.

        These captures cannot be un-leaked -- the text is in git history -- so
        the list exists to let the check gate on anything new. If it removed
        them from the count instead, the report would say the sets are clean
        when they are not.
        """
        self.prose_world({"Docs/notes.md": "quoting alpha bravo charlie delta "
                                           "echo foxtrot here\n"})
        self.leak.PROSE_DOCUMENTED = {("sealed.tsv", "S0"): "known"}
        import io, contextlib
        said = io.StringIO()
        with contextlib.redirect_stdout(said):
            ok = self.leak.check_prose()
        self.assertTrue(ok, "a documented leak must not gate")
        self.assertIn("1 documented", said.getvalue())
        self.assertIn("sealed text in prose      1", said.getvalue())

    def test_the_report_never_prints_the_capture_it_found(self):
        """A leak detector that quotes its finding copies the leak to every log."""
        self.prose_world({"Docs/notes.md": "alpha bravo charlie delta echo "
                                           "foxtrot\n"})
        import io, contextlib
        said = io.StringIO()
        with contextlib.redirect_stdout(said):
            self.leak.check_prose()
        self.assertNotIn("alpha bravo charlie", said.getvalue())
        self.assertIn("sealed.tsv S0", said.getvalue())

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

    def test_the_sealed_sets_own_captures_are_read_by_header_too(self):
        """`mine()` hard-coded column 2 while `harvest()` read the header.

        Both sealed sets put the utterance third today, so it was correct —
        and the registry test will happily register a set laid out
        differently, at which point this side compares the wrong field and the
        check passes for the wrong reason. That is the failure the
        `utterance_column` docstring warns about, on the other half of the
        same script.
        """
        with tempfile.TemporaryDirectory() as root:
            path = pathlib.Path(root) / "odd.tsv"
            path.write_text(
                "# title: A SET LAID OUT DIFFERENTLY\n"
                "id\tfamily\tnote\tutterance\treject\n"
                "X1\tnegation\twhy\tbuy the oat milk not the soy\t-\n")
            self.assertEqual(self.leak.mine(path),
                             {"buy the oat milk not the soy": "X1"})

    def test_the_verdict_distinguishes_contamination_from_double_counting(self):
        """The two failures need different words or the reader hunts the wrong one."""
        sealed = {p.name for p in self.leak.SEALED}
        tuned = self.leak.verdict({"routed.tsv"})
        self.assertIn("developed against", tuned)
        duplicate = self.leak.verdict(sealed)
        self.assertIn("counted as two", duplicate)
        self.assertNotIn("developed against", duplicate)
        # A mixed failure is the serious one and must read as contamination.
        self.assertIn("developed against",
                      self.leak.verdict(sealed | {"routed.tsv"}))

    def test_the_closest_miss_is_ranked_and_reported(self):
        """A pass/fail answer cannot show a set drifting toward the line.

        Two sets both reported clean are in different states if one tops out at
        0.31 and the other at 0.68. This asserts the ranking finds the right
        nearest neighbour and orders by it, so the number printed on a clean
        run is the one a reader should be watching.
        """
        ours = {"book the small meeting room for the standup": "A1",
                "the spare key is under the planter by the door": "A2"}
        theirs = {"book the small meeting room for the review": "near.tsv",
                  "nothing whatever to do with any of that text": "far.tsv"}
        ranked, near = self.leak.similarities(ours, theirs)
        self.assertEqual([row[1] for row in ranked], ["A1", "A2"])
        self.assertGreater(ranked[0][0], 0.6)
        self.assertEqual(ranked[0][3], "near.tsv")
        self.assertLess(ranked[1][0], 0.2)

    def test_the_closest_miss_never_gates(self):
        """Reporting, not a second threshold.

        A warning band would become a number people tune against, which is the
        reason the scorers in this repository report rather than gate. A
        capture sitting just under the line must still exit zero, and the
        reader is the one who decides it is too close.
        """
        ours = {"pick up the dry cleaning and drop the parcel at the "
                "post office before six today": "A1"}
        theirs = {"pick up the dry cleaning and drop the parcel at the "
                  "post office on saturday": "devset.tsv"}
        ranked, near = self.leak.similarities(ours, theirs)
        self.assertGreater(ranked[0][0], self.leak.THRESHOLD - 0.05)
        self.assertLess(ranked[0][0], self.leak.THRESHOLD)
        # The gate is near duplicates only, and this pair is not one.
        self.assertEqual(near, [])

    def test_every_near_duplicate_source_is_kept_not_just_the_closest(self):
        """One capture can be close to two corpora, and only one of them matters.

        `verdict` decides between contamination and double-counting from the
        set of sources a capture collided with. If near duplicates were reduced
        to the best match per capture, a tuned corpus scoring just below a
        sealed one would vanish from that set and the check would report "the
        same capture counted twice" for what is actually a leak — the milder of
        the two messages, for the more serious failure.
        """
        stem = "pick up the dry cleaning and drop the parcel at the post"
        ours = {f"{stem} office": "A1"}
        theirs = {f"{stem} office now": "adversarial.tsv",  # the closer one
                  f"{stem} box": "routed.tsv"}              # tuned, but lower
        _, near = self.leak.similarities(ours, theirs)
        sources = {src for _, _, src, _, _ in near}
        self.assertEqual(sources, {"adversarial.tsv", "routed.tsv"})
        self.assertIn("developed against", self.leak.verdict(sources))

    def test_ranking_ignores_captures_too_short_to_compare(self):
        """Short strings collide by accident, which is why the check skips them.

        `harvest` pulls bare fragments out of Swift sources, and a three-word
        one shares most of its tokens with plenty of captures. Including them
        would make the reported closest miss a permanent false alarm and teach
        the reader to ignore the line. Nothing is lost by skipping them: a
        short string that genuinely appears on both sides is an exact
        collision, which is counted separately and fails the check outright.

        Both sides are skipped, so this fixture keeps one long string on each
        side. Testing only our side would pass even if a short tuned string
        were still a comparison target.
        """
        ours = {"buy milk": "A1", "the spare key is under the planter": "A2"}
        theirs = {"buy milk": "devset.tsv",
                  "the spare key is under the doormat": "devset.tsv"}
        ranked, near = self.leak.similarities(ours, theirs)
        self.assertEqual([row[1] for row in ranked], ["A2"])
        self.assertEqual(ranked[0][4], "the spare key is under the doormat")

    def test_the_existing_held_out_set_harvests_its_documented_size(self):
        """An anchor against a real file: heldout/README.md says 389."""
        path = HERE.parent / "heldout" / "heldout.tsv"
        if not path.exists():
            self.skipTest("heldout.tsv not present")
        self.assertEqual(len(self.leak.harvest(path)), 389)


class LeakCheckReachTests(unittest.TestCase):
    """A check is only as good as the pull requests it runs on.

    `leak-check.py` has its own step in the `language-tools` job, which was
    the fix for it living only inside the Mac-only corpus gate. But that job
    is gated on a path filter, and a guard that does not run on the pull
    request carrying the leak is no better than one that runs nowhere.
    """

    WORKFLOW = HERE.parents[2] / ".github" / "workflows" / "ci.yml"

    def globs(self):
        """The `ios` filter, read from the workflow rather than assumed.

        Parsed with a regex rather than a YAML library on purpose: this runs
        on a CI image whose Python may not carry PyYAML, and a test that
        errors on an import tells nobody anything. If the block cannot be
        found the test fails rather than passing vacuously, for the same
        reason a corpus with no `utterance` header stops the check.
        """
        if not self.WORKFLOW.exists():
            self.skipTest("ci.yml not present")
        block = re.search(r"^\s*ios:\s*\n((?:\s*-\s*'[^']*'\s*\n)+)",
                          self.WORKFLOW.read_text(), re.M)
        self.assertIsNotNone(block, "the ios path filter could not be found")
        return re.findall(r"'([^']+)'", block.group(1))

    @staticmethod
    def covered(path, globs):
        for pattern in globs:
            if pattern.endswith("/**"):
                if path.startswith(pattern[:-2]):
                    return True
            elif path == pattern:
                return True
        return False

    def test_every_corpus_the_overlap_check_reads_is_inside_the_filter(self):
        """The half that is genuinely covered, enumerated rather than assumed."""
        globs = self.globs()
        for path in ("SpeakItTests/SemanticCorpusDataG.swift",
                     "SpeakItTests/SpeechRepairTests.swift",
                     "Tools/CorpusRunner/devsets/routed.tsv",
                     "Tools/CorpusRunner/everyday/everyday.tsv",
                     "Tools/CorpusRunner/heldout/heldout.tsv",
                     "Tools/CorpusRunner/adversarial/adversarial.tsv"):
            with self.subTest(path=path):
                self.assertTrue(self.covered(path, globs),
                                f"{path} can change without running the check")

    @unittest.expectedFailure
    def test_the_documents_the_prose_check_reads_are_inside_the_filter(self):
        """Open defect, recorded as a test rather than only as a sentence.

        `Docs/**` is not in the `ios` filter, so a pull request that only
        edits documentation never runs this check — and a capture quoted into
        a document is exactly what the prose half exists to catch. The one
        such leak caught so far was caught by luck: that pull request also
        touched a Swift file.

        Marked expected-failure rather than skipped so it cannot outlive the
        defect. Add `Docs/**` to the filter and this reports an *unexpected
        success*, which fails the run until the marker comes off — the same
        contract as a `KNOWN:` row that starts passing. Fixing it is an edit
        to `.github/workflows/ci.yml`, which this repository's automation
        cannot merge.
        """
        globs = self.globs()
        self.assertTrue(self.covered("Docs/LANGUAGE_BASELINE.md", globs),
                        "a documentation-only pull request skips the leak check")


class SwiftLiteralHarvestTests(unittest.TestCase):
    """The tuned side of the boundary is only as wide as what it reads.

    This check spent its life reporting `exact collisions 0` for everyday
    while two everyday captures sat in `SemanticCorpusDataG.swift` as
    `corpusCase` rows. Nothing was wrong with the comparison; the harvest
    never handed it the strings.
    """

    def setUp(self):
        self.leak = leak_check_module()

    def test_a_literal_is_found_whatever_precedes_it(self):
        """The regression that let two everyday captures into the gating corpus.

        The old harvest was one regex over the whole file, pairing quote
        characters left to right with no idea which of them opens a literal.
        A literal too short to match leaves its two quotes unconsumed, the
        scan falls out of phase, and from there it reads the *gaps between*
        strings instead of the strings. Here it returns the source text
        `)\\ncorpusCase(.x, ` and never sees the capture at all.
        """
        text = 'foo("ok")\ncorpusCase(.x, "Sarah has no dairy at all", count: 1)\n'
        self.assertIn("Sarah has no dairy at all", self.leak.swift_literals(text))

    def test_the_code_between_two_literals_is_not_harvested_as_one(self):
        """The other half of the same defect, and the half that hid it.

        Harvesting gaps does not merely lose captures, it inflates the count
        that is supposed to show coverage. The real file reported 2,465
        strings while holding 2,101 literals, so the number a reader would
        check read as *more* thorough than the truth.
        """
        text = 'foo("ok")\ncorpusCase(.x, "Sarah has no dairy at all", count: 1)\n'
        for found in self.leak.swift_literals(text):
            self.assertNotIn("corpusCase", found)

    def test_an_escaped_quote_does_not_end_a_literal(self):
        text = r'let s = "he said \"buy the milk\" and left the room"'
        self.assertEqual(len(self.leak.swift_literals(text)), 1)

    def test_a_literal_shorter_than_a_capture_is_skipped(self):
        """Identifiers and keys are strings too, and matching them is noise."""
        self.assertEqual(self.leak.swift_literals('let k = "id"'), [])

    def test_an_unbalanced_quote_does_not_swallow_the_rest_of_the_file(self):
        """Why this scans per line rather than over the whole text."""
        text = ('// the user says "buy milk\n'
                'corpusCase(.x, "Sarah has no dairy at all", count: 1)\n')
        self.assertIn("Sarah has no dairy at all", self.leak.swift_literals(text))


class TunedSideWidthTests(unittest.TestCase):
    """What counts as tuned material, and what was being left out of it."""

    def setUp(self):
        self.leak = leak_check_module()

    def test_a_hand_written_test_fixture_counts_as_tuned_material(self):
        """`SemanticCorpusData*.swift` was not the only tuned corpus.

        A fixture in an ordinary test file is tuned by definition: somebody
        iterated on the rules until that exact sentence went green. Held-out
        C342 is the fixture in eight assertions of `LocationReminderTests`,
        and while this globbed one filename pattern none of that was visible.
        """
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            (root / "SpeakItTests").mkdir(parents=True)
            (root / "Tools/CorpusRunner/devsets").mkdir(parents=True)
            (root / "SpeakItTests" / "LocationReminderTests.swift").write_text(
                'func t() { assert(text: "the spare key is under the doormat") }\n')
            sealed = root / "Tools/CorpusRunner/everyday/everyday.tsv"
            sealed.parent.mkdir(parents=True)
            sealed.write_text("id\tdomain\tutterance\nS0\th\tunrelated capture here\n")
            self.leak.ROOT = root
            self.leak.SEALED = [sealed]
            self.leak.SEALED_ALL = [sealed]
            found = self.leak.others(sealed)
        self.assertIn(self.leak.norm("the spare key is under the doormat"), found)

    def test_the_held_out_set_is_checked_and_not_only_compared_against(self):
        """It was on the tuned side of the loop only.

        `heldout.tsv` was a corpus to compare *against* and never a set under
        check, so the set carrying the published destination figure was the
        one set whose overlap with tuned material nothing ever looked at.
        Three of its captures are exact matches for tuned strings.
        """
        script = HERE / "leak-check.py"
        if not (HERE.parent / "heldout" / "heldout.tsv").exists():
            self.skipTest("heldout.tsv not present")
        out = subprocess.run([sys.executable, str(script)],
                             capture_output=True, text=True).stdout
        self.assertIn("=== heldout/heldout.tsv", out)

    def test_a_documented_overlap_is_counted_but_does_not_gate(self):
        """Red on arrival is how a check gets switched off.

        The marker moves the exit status and never the count, for the same
        reason a `KNOWN:` row is still counted as a failure: a number a
        marker can improve is a number people learn to write markers for.
        """
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            (root / "SpeakItTests").mkdir(parents=True)
            (root / "Tools/CorpusRunner/devsets").mkdir(parents=True)
            (root / "SpeakItTests" / "T.swift").write_text(
                'assert("the spare key is under the doormat")\n')
            sealed = root / "Tools/CorpusRunner/everyday/everyday.tsv"
            sealed.parent.mkdir(parents=True)
            sealed.write_text("id\tdomain\tutterance\n"
                              "S0\th\tthe spare key is under the doormat\n")
            self.leak.ROOT = root
            self.leak.SEALED = [sealed]
            self.leak.SEALED_ALL = [sealed]

            self.leak.OVERLAP_DOCUMENTED = {}
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
                undocumented = self.leak.check(sealed)

            self.leak.OVERLAP_DOCUMENTED = {("everyday.tsv", "S0"): "known"}
            buf2 = io.StringIO()
            with contextlib.redirect_stdout(buf2), contextlib.redirect_stderr(buf2):
                documented = self.leak.check(sealed)

        self.assertEqual(undocumented, 1, "a new overlap must fail the run")
        self.assertEqual(documented, 0, "a documented overlap must not gate")
        self.assertIn("exact collisions         1", buf2.getvalue())
        self.assertIn("S0", buf2.getvalue())

        #: The documented row is the steady state -- reported on every green
        #: run -- so its text must not be printed, or the overlap half of this
        #: file puts sealed captures into every CI log, which is the harm the
        #: prose half was written to avoid. The undocumented row still prints
        #: both sides: that run fails, and somebody has to judge whether the
        #: pair is contamination or coincidence, which two ids cannot answer.
        self.assertNotIn("the spare key is under the doormat", buf2.getvalue())
        self.assertIn("(documented)", buf2.getvalue())
        self.assertIn("the spare key is under the doormat", buf.getvalue())


    def test_a_documented_near_duplicate_does_not_print_its_text_either(self):
        """The near branch needed its own fixture to be tested at all.

        The collision test above only ever produces an exact match, so the
        near branch was never reached by it: a mutation putting the capture
        text back into the documented-near line went unnoticed. A branch no
        fixture reaches is not defence in depth, it is a branch nobody is
        checking.
        """
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            (root / "SpeakItTests").mkdir(parents=True)
            (root / "Tools/CorpusRunner/devsets").mkdir(parents=True)
            (root / "SpeakItTests" / "T.swift").write_text(
                'assert("the spare key is under the doormat now")\n')
            sealed = root / "Tools/CorpusRunner/everyday/everyday.tsv"
            sealed.parent.mkdir(parents=True)
            sealed.write_text("id\tdomain\tutterance\n"
                              "S0\th\tthe spare key is under the doormat\n")
            self.leak.ROOT = root
            self.leak.SEALED = [sealed]
            self.leak.SEALED_ALL = [sealed]
            self.leak.OVERLAP_DOCUMENTED = {("everyday.tsv", "S0"): "known"}
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
                code = self.leak.check(sealed)
        out = buf.getvalue()
        self.assertEqual(code, 0, "a documented near duplicate must not gate")
        self.assertIn("near duplicates (>=0.7)  1  (1 documented, 0 new)", out)
        self.assertIn("NEAR  S0", out)
        self.assertIn("(documented)", out)
        self.assertNotIn("doormat", out)


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


class HeldOutFamilyReportTests(unittest.TestCase):
    """The 389-capture set's per-family table, added so pairings can be read.

    `adversarial/README.md` tells the reader to judge each pairing against its
    ingredients, and those ingredients are families of `heldout.tsv`. The
    scorer parsed the family column and discarded it, so that instruction could
    not be followed. These tests cover the table and, more importantly, that
    adding it did not unseal the set.
    """

    HELDOUT = HERE.parent / "heldout"

    def score(self, route="Today"):
        if not (self.HELDOUT / "heldout.tsv").exists():
            self.skipTest("heldout.tsv not present")
        rows = [l.split("\t") for l in
                (self.HELDOUT / "heldout.tsv").read_text().splitlines()
                if not l.startswith("#") and l.strip()
                and l.split("\t")[0] != "id"]
        blocks = []
        for r in rows:
            blocks.append(
                f'── "{r[1]}"\n   item 1 of 1:\n     row title:  X\n'
                f"     route:      {route}   type: task   category: general"
                f"   priority: normal\n     due:        nil\n"
                f"     remind:     nil   delivery: notification\n"
                f"     temporal:   none\n     state:      resolved")
        with tempfile.TemporaryDirectory() as d:
            probe = pathlib.Path(d) / "probe.txt"
            probe.write_text("\n".join(blocks) + "\n")
            return subprocess.check_output(
                [sys.executable, str(self.HELDOUT / "score.py"),
                 str(self.HELDOUT / "heldout.tsv"), str(probe)], text=True)

    def test_the_family_table_still_prints_no_capture_text(self):
        """The whole point of the set. A finer number is still only a number."""
        result = self.score()
        self.assertIn("PER FAMILY", result)
        # A capture from the top of the file, and one from the middle.
        self.assertNotIn("remind me to uh remind me to call the vet", result)
        for line in result.splitlines():
            self.assertLess(len(line), 100,
                            f"a line long enough to be a capture: {line!r}")

    def test_every_family_tag_reaches_the_table_untruncated(self):
        """A fixed column silently renamed `occupation-vs-person`.

        Truncation is worse than a wide table: the row still looks like a
        family, so nobody checks it twice.
        """
        result = self.score()
        table = result[result.index("PER FAMILY"):]
        families = {r.split("\t")[2].strip() for r in
                    (self.HELDOUT / "heldout.tsv").read_text().splitlines()
                    if not r.startswith("#") and r.strip()
                    and r.split("\t")[0] != "id"}
        rows = {line.split()[0] for line in table.splitlines()
                if line and not line[0].isspace() and line.split()}
        for family in families:
            self.assertIn(family, rows, f"{family} is missing or truncated")

    def test_a_family_with_no_scorable_row_reads_as_a_dash(self):
        """`ambiguous` captures skip destination and count by design.

        Printing 0/0 as 0.0% would put a whole family at the top of a table
        sorted worst-first, which is where the eye goes.
        """
        table = self.score()
        table = table[table.index("PER FAMILY"):]
        ambiguous = [l for l in table.splitlines() if l.startswith("ambiguous")]
        self.assertTrue(ambiguous, "no ambiguous row in the table")
        self.assertIn("—", ambiguous[0])
        self.assertNotIn("0.0%", ambiguous[0])


def score_module():
    """score.py is a script; the matcher is unit-testable in process."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("score_mod", HERE / "score.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def lengths_module():
    """The comparability report lives beside the set it describes."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "lengths", HERE.parent / "adversarial" / "lengths.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def generation_module():
    """generation-check.py has a hyphen in its name, so it loads by path."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "generation_check", HERE / "generation-check.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GenerationCheckTests(unittest.TestCase):
    """The sealing claim, made mechanical.

    Every sealed set's README says its captures have never been scored and then
    edited, and until this check nothing enforced it. What the check can prove
    is narrow and worth stating: it cannot tell a legitimate new generation
    from a quiet edit, because they are the same diff. The generation row does
    the real work; this only makes the edit impossible to make silently.

    So these tests are mostly about the two ways it could be useless: firing on
    edits that are not the claim (a note, a tag, a reordering), which teaches
    people to re-record without reading, and not firing on edits that are.
    """

    def setUp(self):
        self.gen = generation_module()
        if not self.gen.MANIFEST.exists():
            self.skipTest("generations.tsv not present")

    def test_the_committed_sets_match_their_recorded_generation(self):
        """The check, run for real. A red main is the thing this prevents."""
        here, there = self.gen.present(), self.gen.recorded()
        self.assertEqual(sorted(here), sorted(there))
        for name in here:
            with self.subTest(corpus=name):
                self.assertEqual(self.gen.difference(there[name], here[name]),
                                 ([], []))

    def test_the_recorded_hashes_are_written_sorted(self):
        """Order means nothing to the verdict and everything to the diff.

        A generation that moves three captures should show as three changed
        lines, not as a rewritten file nobody reads.
        """
        rows = [line.split("\t") for line in
                self.gen.HASHES.read_text().splitlines()
                if not line.startswith("#") and line.strip()]
        self.assertEqual(rows, sorted(rows))

    def test_every_sealed_set_is_recorded(self):
        """A set missing from the manifest is the one nobody would notice."""
        rows = self.gen.generations()
        for name, path in self.gen.SEALED.items():
            if path.exists():
                with self.subTest(corpus=name):
                    self.assertIn(name, rows)
                    self.assertEqual(int(rows[name]["captures"]),
                                     len(self.gen.present()[name]))

    def test_the_hash_is_of_the_capture_and_nothing_around_it(self):
        """A note, a tag or a retitled README is not "scored and then edited".

        A check that fires on those is one people learn to re-record without
        reading, which costs more than it protects.
        """
        self.assertEqual(self.gen.digest("call the vet"),
                         self.gen.digest("call the vet"))
        self.assertNotEqual(self.gen.digest("call the vet"),
                            self.gen.digest("call the vet today"))

    def test_reordering_rows_is_not_a_generation(self):
        """It changes nothing about what is measured."""
        rows = ["a", "b", "c"]
        self.assertEqual(self.gen.difference(rows, list(reversed(rows))),
                         ([], []))

    def test_an_edited_capture_is_reported_as_one_change_not_two(self):
        """Its old hash goes and a new one arrives, so it shows on both sides.

        Reporting that as one removal and one addition sends someone hunting a
        capture nobody deleted.
        """
        gone, added = self.gen.difference(["a", "b"], ["a", "c"])
        self.assertEqual((gone, added), (["b"], ["c"]))
        self.assertEqual(min(len(gone), len(added)), 1)

    def test_a_capture_that_is_gone_is_not_read_as_an_edit(self):
        gone, added = self.gen.difference(["a", "b"], ["a"])
        self.assertEqual((gone, added), (["b"], []))

    @contextlib.contextmanager
    def recording_into_a_scratch_copy(self):
        """Point the recorder's two output files at a temporary directory.

        `record` writes to module-level paths, so a test that calls it writes
        to the committed manifest. Every test here exercises a refusal, so in
        principle nothing is written -- but a mutation that turns a refusal
        into a write then corrupts real data, which is exactly what happened
        while these tests were being written. A test must not be able to do
        that however the code under it behaves.
        """
        manifest, hashes = self.gen.MANIFEST, self.gen.HASHES
        with tempfile.TemporaryDirectory() as root:
            self.gen.MANIFEST = pathlib.Path(root) / "generations.tsv"
            self.gen.HASHES = pathlib.Path(root) / "captures.sha256"
            self.gen.MANIFEST.write_text(manifest.read_text())
            self.gen.HASHES.write_text(hashes.read_text())
            try:
                yield
            finally:
                self.gen.MANIFEST, self.gen.HASHES = manifest, hashes

    def refuses(self, *args):
        """(exit status, what it said) for one `record` call, written nowhere."""
        err = io.StringIO()
        with self.recording_into_a_scratch_copy():
            with contextlib.redirect_stderr(err):
                with contextlib.redirect_stdout(io.StringIO()):
                    status = self.gen.record(*args)
        return status, err.getvalue()

    def test_the_recorder_refuses_a_number_that_is_not_the_next_one(self):
        """Typing the number out is what makes opening a generation a decision."""
        status, said = self.refuses("adversarial", 7, "2026-09-11")
        self.assertEqual(status, 1)
        self.assertIn("not 7", said)

    def test_the_recorder_refuses_when_nothing_changed(self):
        """Otherwise it is a button people press to turn a red check green."""
        rows = self.gen.generations()
        status, said = self.refuses(
            "adversarial", int(rows["adversarial"]["generation"]) + 1,
            "2026-09-11")
        self.assertEqual(status, 1)
        self.assertIn("unchanged", said)

    def test_an_unknown_set_is_refused_by_name(self):
        status, said = self.refuses("everydy", 1, "2026-09-11")
        self.assertEqual(status, 1)
        self.assertIn("not a sealed set", said)

    def test_a_rewritten_manifest_keeps_one_header_and_stays_sorted(self):
        """Both properties of a file that is read back and rewritten.

        Reading the column header as data gave a set named "set", written back
        out as a second header line: a file that corrupts a little more each
        time it is rewritten and reads fine until somebody looks. And the
        hashes are written sorted so a generation shows as the lines it
        changed rather than as a rewritten file nobody reads.
        """
        with self.recording_into_a_scratch_copy():
            rows = self.gen.generations()
            self.assertNotIn("set", rows)
            self.gen.write({name: sorted(values) for name, values
                            in self.gen.recorded().items()}, rows)
            text = self.gen.MANIFEST.read_text()
            self.assertEqual(text.count("set\tgeneration\tcaptures"), 1)
            self.assertEqual(sorted(rows), sorted(self.gen.generations()))
            lines = [l.split("\t") for l in self.gen.HASHES.read_text().splitlines()
                     if not l.startswith("#") and l.strip()]
            self.assertEqual(lines, sorted(lines))

    @contextlib.contextmanager
    def a_scratch_world(self, sets):
        """Sealed sets of our own, already recorded, with the module aimed at them.

        `main` reads module-level paths, so without this a test exercising the
        check's own verdict would read the committed sets and write beside
        them. The committed data is never touched here, whatever the code
        under test does.
        """
        sealed = self.gen.SEALED, self.gen.MANIFEST, self.gen.HASHES
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            self.gen.SEALED = {}
            for name, captures in sets.items():
                (root / name).mkdir()
                path = root / name / f"{name}.tsv"
                path.write_text(
                    "id\tdomain\tutterance\texpect\tkeep\treject\tfamilies\tnote\n"
                    + "".join(f"{name[:2].upper()}{i:02}\tg\t{c}\tToday:task"
                              f"\t-\t-\tf\tn\n"
                              for i, c in enumerate(captures)))
                self.gen.SEALED[name] = path
            self.gen.MANIFEST = root / "generations.tsv"
            self.gen.HASHES = root / "captures.sha256"
            here = self.gen.present()
            self.gen.write(here, {
                name: {"set": name, "generation": "1",
                       "captures": str(len(values)), "recorded": "2026-09-11",
                       "note": "first record"}
                for name, values in here.items()})
            try:
                yield root
            finally:
                self.gen.SEALED, self.gen.MANIFEST, self.gen.HASHES = sealed

    def check(self):
        """(exit status, what it printed, what it complained)."""
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = self.gen.main([])
        return status, out.getvalue(), err.getvalue()

    #: Two sets, so deleting one leaves the check with something to report.
    WORLD = {"alpha": ["call the vet", "book the car in"],
             "beta": ["email Nadia the invoice"]}

    def test_an_untouched_world_passes(self):
        """The control. Without it every test below could pass on a broken rig."""
        with self.a_scratch_world(self.WORLD):
            status, said, complained = self.check()
        self.assertEqual(status, 0, complained)
        self.assertIn("generation check ok", said)
        self.assertIn("alpha", said)
        self.assertIn("beta", said)

    def test_a_deleted_set_is_a_failure_and_not_an_absence(self):
        """The defect this replaced: `present()` only reports a set whose file
        exists, so iterating it made a deleted set invisible. Removing all 120
        adversarial captures printed the other two sets and "no sealed capture
        has been edited since it was scored", exit 0. Reproduced before fixing.
        """
        with self.a_scratch_world(self.WORLD):
            self.gen.SEALED["alpha"].unlink()
            status, said, complained = self.check()
        self.assertEqual(status, 1)
        self.assertIn("alpha", complained)
        self.assertIn("2 removed", complained)
        self.assertIn("0 captures now against 2 recorded", complained)
        self.assertNotIn("generation check ok", said)

    def test_a_vanished_set_is_told_to_be_restored_not_recorded(self):
        """`--record` would write a generation of zero captures and turn this
        green over a set that is not there, so the failure must not offer it.
        """
        with self.a_scratch_world(self.WORLD):
            self.gen.SEALED["alpha"].unlink()
            _, _, complained = self.check()
        self.assertIn("Restore it", complained)
        self.assertNotIn("--record", complained)

    def test_the_recorder_refuses_a_set_with_no_captures(self):
        """Mechanical, rather than advice in a failure message."""
        with self.a_scratch_world(self.WORLD):
            self.gen.SEALED["alpha"].unlink()
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                with contextlib.redirect_stdout(io.StringIO()):
                    status = self.gen.record("alpha", 2, "2026-09-11")
            recorded_still = self.gen.generations()["alpha"]["captures"]
        self.assertEqual(status, 1)
        self.assertIn("no captures", err.getvalue())
        self.assertEqual(recorded_still, "2",
                         "a refused record must leave the manifest alone")

    def test_a_set_still_on_disk_but_never_recorded_is_a_failure(self):
        """The other side of the union: added, not removed."""
        with self.a_scratch_world(self.WORLD) as root:
            (root / "gamma").mkdir()
            path = root / "gamma" / "gamma.tsv"
            path.write_text("id\tdomain\tutterance\texpect\tkeep\treject"
                            "\tfamilies\tnote\nGA00\tg\tnew capture"
                            "\tToday:task\t-\t-\tf\tn\n")
            self.gen.SEALED["gamma"] = path
            status, _, complained = self.check()
        self.assertEqual(status, 1)
        self.assertIn("gamma", complained)
        self.assertIn("1 added", complained)
        self.assertIn("1 capture now against 0 recorded", complained)

    def test_a_duplicated_capture_is_not_blamed_on_the_manifest(self):
        """`difference` is set-based, so a duplicate moves only the count.

        Without its own branch that lands on "the manifest has been edited by
        hand", which sends someone to correct a file that is correct. No set
        has a duplicate today, so the wrong sentence was waiting for the first
        one.
        """
        world = dict(self.WORLD, alpha=["call the vet", "call the vet"])
        with self.a_scratch_world(self.WORLD):
            recorded_alpha = self.gen.recorded()["alpha"]
        with self.a_scratch_world(world):
            #: Recorded from the duplicated set, so the hashes agree and only
            #: the count can differ — which is the state being tested.
            status, _, complained = self.check()
        self.assertEqual(status, 1)
        self.assertIn("identical to another capture", complained)
        self.assertNotIn("edited by hand", complained)
        self.assertEqual(len(recorded_alpha), 2)

    def test_a_malformed_hash_line_names_itself(self):
        """766 lines of hex; an unpack error sends someone scrolling."""
        with self.a_scratch_world(self.WORLD):
            good = self.gen.HASHES.read_text()
            self.gen.HASHES.write_text(good + "alpha no tab here\n")
            expected = len(good.splitlines()) + 1
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                with self.assertRaises(SystemExit):
                    self.gen.recorded()
        self.assertIn(f"line {expected}", err.getvalue())
        self.assertIn("set<TAB>hash", err.getvalue())

    def test_the_manifest_holds_no_capture_text(self):
        """It is committed, so it must reveal nothing the sets are sealing."""
        hashes = self.gen.HASHES.read_text()
        for name, path in self.gen.SEALED.items():
            if not path.exists():
                continue
            with self.subTest(corpus=name):
                for capture in self.gen.harvest(path)[:40]:
                    self.assertNotIn(capture, hashes)


class PerFamilyTableTests(unittest.TestCase):
    """The per-family table has to say when a row is not its own reading.

    A family whose captures all come from one group is that group's row under
    a second name. On the adversarial set twelve of sixteen families are in
    that position, and three pairs of them cover the identical captures, so
    `ellipsis`, `multi-date` and `ellipsis-x-date` print the same figures three
    times with nothing saying so. Quoting two of them, or averaging them, is
    the one-phenomenon-counted-twice error that has already manufactured a
    fake gain once in this repository.
    """

    def score(self, labels, group="pair"):
        with tempfile.TemporaryDirectory() as root:
            directory = pathlib.Path(root) / "set"
            directory.mkdir()
            cases = directory / "s.tsv"
            cases.write_text(HEADER.replace("domain", group) + labels)
            probe = directory / "probe.txt"
            probe.write_text("".join(
                block(row.split("\t")[2], {"title": "X", "route": "Today"})
                for row in labels.splitlines()))
            return subprocess.check_output(
                [sys.executable, str(HERE / "score.py"), str(cases), str(probe)],
                text=True)

    def family_rows(self, report):
        """The table's data lines, between its rule and the closing rule."""
        lines = report.splitlines()
        start = next(i for i, l in enumerate(lines) if "PER FAMILY" in l)
        body = lines[start:]
        header = next(i for i, l in enumerate(body) if l.startswith("family"))
        end = next(i for i, l in enumerate(body[header + 2:]) if set(l) == {"-"})
        return body[header + 2:header + 2 + end]

    def test_a_family_confined_to_one_group_says_which(self):
        report = self.score(
            "A1\tpair-one\tcall the vet\tToday:task\t-\t-\tellipsis\tn\n"
            "A2\tpair-one\tcall the dentist\tToday:task\t-\t-\tellipsis\tn\n")
        rows = [r for r in self.family_rows(report) if r.startswith("ellipsis")]
        self.assertEqual(len(rows), 1)
        self.assertIn("← pair-one only", rows[0])

    def test_a_family_spanning_groups_is_not_marked(self):
        """Otherwise the mark is decoration and nobody reads it."""
        report = self.score(
            "A1\tpair-one\tcall the vet\tToday:task\t-\t-\tellipsis\tn\n"
            "A2\tpair-two\tcall the dentist\tToday:task\t-\t-\tellipsis\tn\n")
        rows = [r for r in self.family_rows(report) if r.startswith("ellipsis")]
        self.assertEqual(len(rows), 1)
        self.assertNotIn("only", rows[0])

    def test_the_note_appears_only_when_some_row_carries_the_mark(self):
        spanning = self.score(
            "A1\tpair-one\tcall the vet\tToday:task\t-\t-\tellipsis\tn\n"
            "A2\tpair-two\tcall the dentist\tToday:task\t-\t-\tellipsis\tn\n")
        confined = self.score(
            "A1\tpair-one\tcall the vet\tToday:task\t-\t-\tellipsis\tn\n"
            "A2\tpair-one\tcall the dentist\tToday:task\t-\t-\tellipsis\tn\n")
        self.assertNotIn("never average them", spanning)
        self.assertIn("never average them", confined)

    def test_every_family_row_keeps_its_figures_in_column(self):
        """A name wider than the column pushes the row right, not off.

        `occupation-vs-person` is 20 characters against a column of 18, so
        every figure on that row sat two places out while still looking like
        data. Truncating instead would be worse; the column is sized to the
        longest tag present.
        """
        report = self.score(
            "A1\tpair-one\tcall the vet\tToday:task\t-\t-\toccupation-vs-person\tn\n"
            "A2\tpair-two\tcall the dentist\tToday:task\t-\t-\tidiom\tn\n")
        offsets = {r.index("1/1") for r in self.family_rows(report)}
        self.assertEqual(len(offsets), 1, "family rows are not in column")

    def test_the_committed_sets_are_marked_as_the_data_requires(self):
        """Real data, because the point is which rows may be quoted.

        Every everyday family spans domains, so nothing there is marked; the
        adversarial set carries `ellipsis` and `multi-date` on one pairing
        each, and on the same one.
        """
        for name, path in (("everyday", HERE / "everyday.tsv"),
                           ("adversarial",
                            HERE.parent / "adversarial" / "adversarial.tsv")):
            if not path.exists():
                self.skipTest(f"{path.name} not present")
            with self.subTest(corpus=name):
                rows = [line.split("\t") for line in path.read_text().splitlines()
                        if not line.startswith("#") and line.strip()
                        and line.split("\t")[0] != "id"]
                groups = {}
                for row in rows:
                    for family in row[6].split("|"):
                        groups.setdefault(family, set()).add(row[1])
                confined = {f for f, g in groups.items() if len(g) == 1}
                if name == "everyday":
                    self.assertEqual(confined, set(),
                                     "an everyday family stopped spanning domains")
                else:
                    self.assertEqual(groups["ellipsis"], {"ellipsis-x-date"})
                    self.assertEqual(groups["multi-date"], {"ellipsis-x-date"})
                    self.assertIn("run-on", confined)


class FamilyRankingTests(unittest.TestCase):
    """Where a family sits in this table is a claim, and it was two wrong ones.

    The table is the triage list: worst first, and somebody starts at the top.
    It ranks across five measures and prints three of them, so a family could
    hold the top row on `loss` or `invention` while every figure on its line
    read 100% -- a position the reader cannot check against anything visible.
    And ties broke on `n`, which is not the denominator of any rate here:
    `recurrence` carries 22 captures of which exactly one is scored for
    invention, so its 0/1 outranked a 0/8 on the strength of 22 against 8
    while the evidence was 1 against 8. Six of the everyday set's 25 families
    have an invention denominator of 1 or 2 over 12 to 33 captures.
    """

    def score(self, labels, probe):
        with tempfile.TemporaryDirectory() as root:
            directory = pathlib.Path(root) / "everyday"
            directory.mkdir()
            cases = directory / "everyday.tsv"
            cases.write_text(HEADER + labels)
            output = directory / "probe.txt"
            output.write_text(probe)
            return subprocess.check_output(
                [sys.executable, str(HERE / "score.py"), str(cases), str(output)],
                text=True)

    def order(self, report):
        """Family names in the order the table ranks them."""
        lines = report.splitlines()
        start = next(i for i, l in enumerate(lines) if "PER FAMILY" in l)
        body = lines[start:]
        header = next(i for i, l in enumerate(body) if l.startswith("family"))
        rows = []
        for line in body[header + 2:]:
            if set(line) == {"-"}:
                break
            rows.append(line.split()[0])
        return rows

    def row(self, report, family):
        lines = [l for l in self.order(report)]
        self.assertIn(family, lines)
        for line in report.splitlines():
            if line.startswith(family + " ") or line.startswith(family + "\t"):
                return line
        self.fail(f"no row for {family}")

    #: Eight captures routed wrong: a rate of 0.0 measured over eight.
    def wide(self, family, n=8):
        labels, probe = "", ""
        for i in range(n):
            utterance = f"wide {family} {i}"
            labels += (f"W{i}\twork-school\t{utterance}\tToday:task\t-\t-\t"
                       f"{family}\tn\n")
            probe += block(utterance, {"title": utterance, "route": "Memory",
                                       "type": "note"})
        return labels, probe

    #: Many captures, all of them clean, and exactly one scored for invention
    #: -- which fails. A rate of 0.0 measured over one.
    def thin(self, family, n=10):
        labels, probe = "", ""
        for i in range(n - 1):
            utterance = f"thin {family} {i}"
            labels += (f"T{i}\twork-school\t{utterance}\tToday:task\t-\t-\t"
                       f"{family}\tn\n")
            probe += block(utterance, {"title": utterance})
        utterance = f"thin {family} superseded"
        labels += (f"T9\twork-school\t{utterance}\tToday:task\t-\tsuperseded\t"
                   f"{family}\tn\n")
        probe += block(utterance, {"title": "call about the superseded number"})
        return labels, probe

    def test_at_an_equal_rate_the_measures_own_denominator_decides(self):
        """The regression: `n` used to decide, and it is the larger here."""
        thin_labels, thin_probe = self.thin("fam-thin", n=10)
        wide_labels, wide_probe = self.wide("fam-wide", n=8)
        report = self.score(thin_labels + wide_labels, thin_probe + wide_probe)
        order = self.order(report)
        self.assertEqual(order.index("fam-wide") + 1, order.index("fam-thin"),
                         f"0/8 must outrank 0/1, got {order}")

    def test_n_is_not_what_broke_the_tie(self):
        """Same shapes, and the thin family now carries more captures still."""
        thin_labels, thin_probe = self.thin("fam-thin", n=20)
        wide_labels, wide_probe = self.wide("fam-wide", n=8)
        report = self.score(thin_labels + wide_labels, thin_probe + wide_probe)
        self.assertLess(self.order(report).index("fam-wide"),
                        self.order(report).index("fam-thin"))

    #: Many captures, all clean, and exactly one scored for loss -- which
    #: fails because the span it must preserve is not in the title.
    def thin_loss(self, family, n=10):
        labels, probe = "", ""
        for i in range(n - 1):
            utterance = f"lossy {family} {i}"
            labels += (f"L{i}\twork-school\t{utterance}\tToday:task\t-\t-\t"
                       f"{family}\tn\n")
            probe += block(utterance, {"title": utterance})
        utterance = f"lossy {family} keeps a span"
        labels += (f"L9\twork-school\t{utterance}\tToday:task\tRoncesvalles\t-\t"
                   f"{family}\tn\n")
        probe += block(utterance, {"title": "something else entirely"})
        return labels, probe

    def test_the_mark_generalises_to_the_other_unprinted_measure(self):
        """`loss` is the second measure `worst()` reads and the table omits.

        Written because the mark was built for the `invention` case that
        prompted it, and a guard tested only on the case that prompted it is
        a guard for that case. `loss` exercises the same branch through a
        different measure, so the branch is the thing under test rather than
        the string `invention`.
        """
        labels, probe = self.thin_loss("fam-loss", n=10)
        report = self.score(labels, probe)
        row = self.row(report, "fam-loss")
        self.assertIn("ranked on loss 0/1", row)
        self.assertIn("(100.0%)", row)
        self.assertIn("ranked on <measure>", report)

    def test_a_loss_ranked_family_outranks_nothing_better_evidenced(self):
        """The tie-break holds for `loss` as it does for `invention`."""
        thin_labels, thin_probe = self.thin_loss("fam-loss", n=20)
        wide_labels, wide_probe = self.wide("fam-wide", n=8)
        report = self.score(thin_labels + wide_labels, thin_probe + wide_probe)
        self.assertLess(self.order(report).index("fam-wide"),
                        self.order(report).index("fam-loss"))

    def test_a_row_ranked_on_a_measure_with_no_column_says_so(self):
        """Otherwise its printed figures read 100% at the top of the table."""
        labels, probe = self.thin("fam-thin", n=10)
        report = self.score(labels, probe)
        row = self.row(report, "fam-thin")
        self.assertIn("ranked on invention 0/1", row)
        self.assertIn("(100.0%)", row)
        self.assertIn("ranked on <measure>", report)

    def test_a_row_ranked_on_a_printed_column_is_not_marked(self):
        """The evidence is already on the line, so a mark would be noise."""
        labels, probe = self.wide("fam-wide", n=8)
        report = self.score(labels, probe)
        self.assertNotIn("ranked on", self.row(report, "fam-wide"))
        self.assertNotIn("ranked on <measure>", report)

    def test_a_family_scored_on_one_measure_ranks_on_it_and_is_not_marked(self):
        """`ambiguous` is this shape in the real set, and the README says so.

        Its captures are unpinnable, so routing and count are never scored and
        only `title` is. Every hand-transcribed table of this set puts it last,
        and the README now claims the scorer arrives there without being told
        to. That claim needs something holding it, or it is a sentence in a
        document — which is the failure mode this directory exists to remove.

        Not marked, because `title` is a printed column: the rate the row is
        ranked on is in front of the reader, and the `—` cells say the rest.
        """
        labels, probe = "", ""
        for i in range(15):
            utterance = f"unpinnable {i}"
            labels += (f"A{i}\twork-school\t{utterance}\tAmbiguous\t-\t-\t"
                       f"fam-amb\tn\n")
            probe += block(utterance, {"title": utterance, "route": "Memory",
                                       "type": "note"})
        wide_labels, wide_probe = self.wide("fam-bad", n=8)
        report = self.score(labels + wide_labels, probe + wide_probe)

        self.assertEqual(self.order(report), ["fam-bad", "fam-amb"])
        row = self.row(report, "fam-amb")
        self.assertNotIn("ranked on", row)
        self.assertIn("—", row)
        self.assertNotIn("NOT RANKED", report)

    def test_a_family_with_nothing_scored_is_not_ranked_at_all(self):
        """It used to score 1.0, which is where a perfect family goes."""
        labels = ("A1\twork-school\tnever run\tToday:task\t-\t-\tfam-absent\tn\n"
                  "A2\twork-school\tmissed one\tToday:task\t-\t-\tfam-wide\tn\n")
        probe = block("missed one", {"title": "Missed one", "route": "Memory",
                                     "type": "note"})
        report = self.score(labels, probe)
        self.assertNotIn("fam-absent", self.order(report))
        self.assertIn("NOT RANKED", report)
        self.assertIn("fam-absent", report.split("NOT RANKED")[1])

    def test_the_not_ranked_block_is_absent_when_every_family_was_scored(self):
        labels, probe = self.wide("fam-wide", n=2)
        self.assertNotIn("NOT RANKED", self.score(labels, probe))

    def test_the_footer_denies_that_n_is_a_denominator(self):
        """`n` reads as one, and six families would be misread through it."""
        labels, probe = self.wide("fam-wide", n=2)
        self.assertIn("`n` is the", self.score(labels, probe))
        self.assertIn("denominator of none of these columns",
                      self.score(labels, probe))

    def test_worst_refuses_a_family_it_cannot_rank_rather_than_answering(self):
        """The filter is the guard; this only stops a caller mis-sorting."""
        sys.path.insert(0, str(HERE))
        try:
            score = __import__("score")
        finally:
            sys.path.pop(0)
        with self.assertRaises(ValueError):
            score.worst(collections.Counter())

    def test_worst_reports_the_measure_and_its_denominator(self):
        sys.path.insert(0, str(HERE))
        try:
            score = __import__("score")
        finally:
            sys.path.pop(0)
        counter = collections.Counter({"routing_ok": 1, "routing_miss": 7,
                                       "title_ok": 8})
        self.assertEqual(score.worst(counter), (0.125, 8, "routing"))

    def test_at_an_equal_rate_and_denominator_the_better_evidenced_names_it(self):
        """Two measures tied; the mark must not understate the evidence."""
        sys.path.insert(0, str(HERE))
        try:
            score = __import__("score")
        finally:
            sys.path.pop(0)
        counter = collections.Counter({"routing_ok": 0, "routing_miss": 2,
                                       "invention_ok": 0, "invention_miss": 8,
                                       "title_ok": 10})
        self.assertEqual(score.worst(counter), (0.0, 8, "invention"))

class ComparabilityTests(unittest.TestCase):

    """A pairing may only be read against an ingredient of comparable length.

    `adversarial/README.md` says to judge each pairing against the families it
    is built from. The set's first reading showed that instruction can be
    followed and still be wrong: `runon-x-repair` scored 8/12 where the
    everyday `run-on` family scored 0/8, and the reason was that the pairing
    was written at half the length, not that composition was easier. The rule
    was written down after that. These tests make it mechanical, because a rule
    that lives only in a README goes stale the first time someone edits a
    capture.
    """

    #: Comparisons known to be unmakeable, and named as such in the README.
    #: Each is a defect in the set rather than in the parser: the pairing wants
    #: rewriting at its ingredient's length. Entries stay until that happens,
    #: and the test below fails in both directions — a new one that nobody
    #: declared, and a declared one that is no longer true.
    UNREADABLE = {("runon-x-repair", "run-on")}

    def setUp(self):
        self.lengths = lengths_module()
        if not self.lengths.SETS["adversarial"][0].exists():
            self.skipTest("adversarial.tsv not present")

    def test_the_unreadable_comparisons_are_exactly_the_declared_ones(self):
        self.assertEqual(
            self.lengths.unreadable(), self.UNREADABLE,
            "a pairing's length range moved relative to an ingredient's. "
            "Either a row that nobody can read was introduced, or a declared "
            "one was fixed and this list is now stale.")

    def test_every_ingredient_tag_can_be_looked_up_somewhere(self):
        """A tag no set carries is a comparison that cannot be made at all.

        Different from disjoint lengths and worse: there is no ingredient row
        to put beside the pairing, so the reader has nothing to compare and no
        sign that anything is missing.
        """
        tables = {name: self.lengths.families(name)
                  for name in self.lengths.SOURCES}
        for pair, tags in sorted(self.lengths.ingredients().items()):
            for tag in sorted(tags):
                with self.subTest(pair=pair, family=tag):
                    self.assertTrue(
                        any(tag in table for table in tables.values()),
                        f"{pair} is tagged {tag!r}, which no ingredient set "
                        f"carries, so that pairing cannot be read against it")

    def test_one_comparable_source_is_enough_to_keep_a_pairing_readable(self):
        """The branch the committed sets do not currently exercise.

        `heldout/` writes short single-mechanism sentences and `everyday/`
        writes natural-length ones, so the same family can be disjoint in one
        and overlapping in the other. That pairing is still readable — against
        the source that overlaps — and calling it unreadable would discard a
        usable row.
        """
        short, natural, pairing = [3, 4], [9, 14], [8, 12]
        both_disjoint = [("p", pairing, "f", "heldout", short),
                         ("p", pairing, "f", "everyday", [40, 50])]
        one_overlaps = [("p", pairing, "f", "heldout", short),
                        ("p", pairing, "f", "everyday", natural)]
        self.assertEqual(self.lengths.unreadable(both_disjoint), {("p", "f")})
        self.assertEqual(self.lengths.unreadable(one_overlaps), set())

    def test_the_readme_names_every_unreadable_comparison(self):
        """Otherwise the table says one thing and the prose says another."""
        readme = (HERE.parent / "adversarial" / "README.md").read_text()
        for pair, family in sorted(self.UNREADABLE):
            with self.subTest(pair=pair):
                self.assertIn(pair, readme)
                self.assertIn(family, readme)
        self.assertIn("disjoint", readme)

    def test_counting_reads_the_capture_and_not_the_note(self):
        """Every column of these files is prose; the wrong one still counts.

        A word count taken from `note` would produce a full, plausible table
        that measures nothing about the captures at all.
        """
        import statistics
        pairs = self.lengths.pairings()
        self.assertIn("runon-x-repair", pairs)
        self.assertEqual(len(pairs["runon-x-repair"]), 12)
        rows = list(self.lengths.read("adversarial"))
        self.assertEqual(sorted(pairs["runon-x-repair"]),
                         sorted(len(r["utterance"].split()) for r in rows
                                if r["pair"] == "runon-x-repair"))
        # Pinned to the figures the README prints, so that a reading taken
        # from some other column cannot agree with itself and pass.
        self.assertEqual(statistics.median(pairs["runon-x-repair"]), 13)
        self.assertEqual((min(pairs["runon-x-repair"]),
                          max(pairs["runon-x-repair"])), (10, 16))


class SpanMatchTests(unittest.TestCase):
    """Span matching anchors its left edge and tolerates its right one."""

    def setUp(self):
        self.score = score_module()

    def test_a_number_does_not_match_inside_a_longer_number(self):
        # The bug this exists to prevent: a capture corrected 6:40 to 7:40, the
        # pipeline rendered the evening time 16:40 for some other thought, and
        # the discarded 6:40 was reported as invented.
        self.assertFalse(self.score.carries("6:40", self.score.norm("meet at 16:40")))
        self.assertFalse(self.score.carries("8:45", self.score.norm("closes 18:45")))

    def test_a_number_still_matches_itself(self):
        self.assertTrue(self.score.carries("6:40", self.score.norm("train at 6:40")))

    def test_a_word_does_not_match_inside_a_longer_word(self):
        self.assertFalse(self.score.carries("oslo", self.score.norm("konsoslo")))

    def test_a_label_still_matches_an_inflected_rendering(self):
        # Labels are written in the spoken form; renderings pluralise.
        self.assertTrue(self.score.carries("500 gram", self.score.norm("buy 500 grams")))
        self.assertTrue(self.score.carries("night", self.score.norm("three nights")))


class SealedRegistryTests(unittest.TestCase):
    """Adding a held-out set must not mean remembering to protect it."""

    def setUp(self):
        self.leak = leak_check_module()

    def test_every_set_in_this_format_is_registered_as_sealed(self):
        """A sealed set missing from the registry is never leak-checked.

        The failure is silent and permanent: the set keeps being reported as
        held out while nothing verifies that it still is. So membership is
        derived from the file's own shape — a `reject` column means it is
        scored by this scorer — rather than from anyone's memory.
        """
        registered = {p.resolve() for p in self.leak.SEALED}
        for path in sorted((HERE.parent).glob("*/*.tsv")):
            header = ""
            for line in open(path):
                if "utterance" in line.lower():
                    header = line.lstrip("#").lower()
                    break
            if "reject" not in header:
                continue
            self.assertIn(
                path.resolve(), registered,
                f"{path.parent.name}/{path.name} is scored as a held-out set "
                f"but is not in leak-check.py's SEALED list, so nothing checks "
                f"that it stays unseen")

    def test_each_sealed_set_is_checked_against_the_others(self):
        """Two sealed sets sharing a capture is one measurement counted twice.

        `others()` returns normalised capture text, so the property is checked
        by looking for a sibling's actual capture in the comparison corpus.
        """
        everyday, sibling = self.leak.SEALED[0], self.leak.SEALED[1]
        compared = self.leak.others(exclude=everyday)
        a_sibling_capture = self.leak.norm(self.leak.harvest(sibling)[0])
        self.assertIn(
            a_sibling_capture, compared,
            "a sealed set must be compared against its siblings, or the same "
            "capture can sit in two sets and be counted as two measurements")

    def test_a_set_excluded_from_the_comparison_is_not_compared_to_itself(self):
        """Otherwise every capture collides with itself and the check is noise."""
        everyday = self.leak.SEALED[0]
        compared = self.leak.others(exclude=everyday)
        own_capture = self.leak.norm(self.leak.harvest(everyday)[0])
        self.assertNotIn(own_capture, compared)


class SetTitleTests(unittest.TestCase):
    """The shared scorer must print the name of the set it actually scored."""

    def setUp(self):
        self.score = score_module()

    def test_a_set_declares_its_own_banner(self):
        with tempfile.TemporaryDirectory() as root:
            path = pathlib.Path(root) / "s.tsv"
            path.write_text("# title: A DIFFERENT SET\nid\tdomain\tutterance\n")
            self.assertEqual(self.score.set_title(path), "A DIFFERENT SET")

    def test_a_set_without_a_banner_keeps_the_original(self):
        with tempfile.TemporaryDirectory() as root:
            path = pathlib.Path(root) / "s.tsv"
            path.write_text("id\tdomain\tutterance\n")
            self.assertIn("EVERYDAY", self.score.set_title(path))

    def test_the_two_committed_sets_do_not_share_a_banner(self):
        titles = {self.score.set_title(p) for p in CorpusTests.CORPORA}
        self.assertEqual(len(titles), 2,
                         "two sets printing one name makes a quoted report "
                         "impossible to attribute")


class CorpusTests(unittest.TestCase):
    """The committed set itself, checked for the properties it claims."""

    #: Every labelled set scored by this file's scorer. Structural guards run
    #: over all of them, so a set added later inherits them instead of being
    #: the one nobody checked.
    CORPORA = (HERE / "everyday.tsv", HERE.parent / "adversarial" / "adversarial.tsv")

    def corpora(self):
        out = {}
        for path in self.CORPORA:
            self.assertTrue(path.exists(), f"{path} is listed but missing")
            rows = []
            for line in open(path):
                parts = line.rstrip("\n").split("\t")
                if line.startswith("#") or parts[0] == "id" or not line.strip():
                    continue
                self.assertEqual(len(parts), 8,
                                 f"{path.name}: wrong column count: {parts[0]}")
                rows.append(parts)
            out[path.name] = rows
        return out

    def rows(self):
        return [r for rows in self.corpora().values() for r in rows]

    def test_every_case_is_well_formed_and_unique(self):
        rows = self.rows()
        self.assertGreaterEqual(len(rows), 300)
        ids = [r[0] for r in rows]
        self.assertEqual(len(ids), len(set(ids)), "duplicate case id")
        utterances = [r[2].lower() for r in rows]
        self.assertEqual(len(utterances), len(set(utterances)),
                         "the same capture appears twice")

    def test_every_domain_carries_a_comparable_number_of_captures(self):
        from collections import Counter
        for name, rows in self.corpora().items():
            with self.subTest(corpus=name):
                counts = Counter(r[1] for r in rows)
                self.assertGreaterEqual(len(counts), 5)
                self.assertLessEqual(
                    max(counts.values()) - min(counts.values()), 5,
                    f"{name}: groups must stay comparable or the by-group "
                    f"rates cannot be read against each other")

    def test_every_group_label_fits_the_report_column(self):
        """A label wider than the column silently misaligns every row after it.

        The table pads the name to 18 and the reader's eye relies on that; an
        over-long group name shifts its own row's figures out of their columns,
        which reads as a rendering glitch rather than as the data error it is.
        """
        for name, rows in self.corpora().items():
            for row in rows:
                self.assertLessEqual(
                    len(row[1]), 17,
                    f"{name}: group {row[1]!r} is too wide for the report column")

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

    #: Words that mark an exclusion rather than a repair.
    CONTRAST = re.compile(r"\b(not|rather than|instead of)\b", re.I)

    def test_the_contrast_rule_catches_exclusions_and_spares_repairs(self):
        """The guard above is only worth having if it separates the two.

        An exclusion names a value the speaker meant to keep out of the
        reading; a repair replaces one. A faithful title carries the first and
        must not carry the second, which is why only the second may assert
        invention.
        """
        for exclusion in ("book the small meeting room not the big one",
                          "the blue inhaler not the brown one",
                          "pay by card rather than by transfer",
                          "use the side door instead of the front"):
            self.assertTrue(self.CONTRAST.search(exclusion), exclusion)
        for repair in ("the deadline is the 14th sorry I mean the 15th",
                       "we need eight licences no sorry twelve licences",
                       "send it to Okonjo I mean to Vasquez",
                       "I honestly dont know whether to raise rates"):
            self.assertIsNone(self.CONTRAST.search(repair), repair)

    def test_contrast_captures_assert_no_rejected_value(self):
        """Invention means one thing: a value the repair discarded.

        `book the small room not the big one` mentions the big room on purpose.
        A title that keeps the contrast is faithful, not inventive, so a
        substring test over the reading cannot tell `excluded the big room`
        from `booked the big room`.

        The rule is derived from the capture's own words rather than from its
        `negation` tag. Keying it to the tag left a hole: a contrast capture
        nobody happened to tag was unprotected, and five such captures were
        already in the set. A tag is a label someone remembered to write; the
        sentence is the evidence.
        """
        for row in self.rows():
            contrast = self.CONTRAST.search(row[2])
            if contrast or "negation" in row[6].split("|"):
                self.assertEqual(
                    row[5], "-",
                    f"{row[0]}: this capture excludes a value with "
                    f"{contrast.group(0)!r} rather than superseding it, so it "
                    f"cannot assert invention — a faithful title contains the "
                    f"excluded value"
                    if contrast else
                    f"{row[0]}: a negation capture cannot assert invention")

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
