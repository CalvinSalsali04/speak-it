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

    def test_the_set_does_not_overlap_a_corpus_that_is_tuned_against(self):
        result = subprocess.run(
            [sys.executable, str(HERE / "leak-check.py")],
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0,
                         f"leak check failed:\n{result.stdout}\n{result.stderr}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
