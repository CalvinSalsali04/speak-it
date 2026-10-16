#!/usr/bin/env python3
"""Self-tests for the whole-capture scorer.

Every fixture here is a NONSENSE toy row ("zorp the blicket") written inline.
None is a capture, none resembles one, and nothing here reads a sealed set: the
instrument is tested on data that cannot teach anybody anything about speech.
"""
import contextlib
import io
import json
import pathlib
import re
import shutil
import sys
import tempfile
import unittest
from datetime import datetime
from zoneinfo import ZoneInfo

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import score  # noqa: E402

ZONE = ZoneInfo("America/Toronto")


def epoch(text):
    return datetime.fromisoformat(text).replace(tzinfo=ZONE).timestamp()


def want(**fields):
    base = {"destination": "Memory", "type": "note", "due": None, "remind": None,
            "delivery": "none", "person": None, "place": None, "recurs": None}
    base.update(fields)
    return base


def got(**fields):
    base = {"title": "Zorp the blicket", "route": "Memory", "type": "note",
            "due": None, "reminder": None, "delivery": "none", "person": None,
            "location": "nil", "recurrenceRule": None, "shoppingGroup": None,
            "needsReview": False}
    base.update(fields)
    return base


def toy(cid="TOY-1", family="single-task", items=None, **extra):
    row = {"id": cid, "family": family, "input": "typed",
           "utterance": f"zorp the blicket {cid}",
           "items": [want()] if items is None else items}
    row.update(extra)
    return row


def output(row, items=None, operations=None):
    return {"text": row["utterance"], "items": items if items is not None else [got()],
            "operations": operations or []}


class TheContractMustAssertEveryField(unittest.TestCase):
    def test_a_complete_toy_row_is_valid(self):
        self.assertEqual(score.validate([toy()]), [])

    def test_an_unasserted_field_is_refused_not_passed(self):
        item = want()
        del item["person"]
        problems = score.validate([toy(items=[item])])
        self.assertTrue(any("`person` is not asserted" in p for p in problems))

    def test_unknown_family_duplicate_id_and_bad_time_are_refused(self):
        rows = [toy(family="gibberish"), toy(), toy(items=[want(due="tomorrowish")])]
        problems = " ".join(score.validate(rows))
        self.assertIn("family must be one of", problems)
        self.assertIn("duplicate id", problems)
        self.assertIn("due must be null", problems)

    def test_problems_name_ids_never_text(self):
        row = toy(family="gibberish")
        for line in score.validate([row]):
            self.assertNotIn("zorp", line)

    def test_sixteen_families_eight_of_them_p0(self):
        self.assertEqual(len(score.FAMILIES), 16)
        self.assertEqual(len(set(score.FAMILIES)), 16)
        self.assertEqual(len(score.P0_FAMILIES), 8)


class WholeCaptureJudgement(unittest.TestCase):
    def test_every_field_matching_is_correct(self):
        row = toy()
        self.assertTrue(score.judge(row, output(row))["correct"])

    def test_one_behavioral_field_fails_the_whole_capture(self):
        row = toy(items=[want(), want(destination="Today", type="task")])
        result = score.judge(row, output(row, [got(), got(route="Memory", type="task")]))
        self.assertFalse(result["correct"])
        self.assertEqual(result["failed"], ["destination"])
        self.assertEqual(result["worst"], "behavioral")

    def test_a_metadata_field_also_fails_it(self):
        row = toy(items=[want(person="Quux")])
        result = score.judge(row, output(row, [got(person="Flarn")]))
        self.assertEqual((result["correct"], result["worst"]), (False, "metadata"))

    def test_wrong_count_is_critical(self):
        row = toy(items=[want(), want()])
        result = score.judge(row, output(row, [got()]))
        self.assertIn("count", result["failed"])
        self.assertEqual(result["worst"], "critical")

    def test_needs_review_is_its_own_destination(self):
        row = toy(items=[want(destination="NeedsReview", type="task")])
        self.assertTrue(score.judge(row, output(row, [got(route="Today", type="task",
                                                          needsReview=True)]))["correct"])
        self.assertIn("destination", score.judge(
            row, output(row, [got(route="Today", type="task")]))["failed"])

    def test_items_are_aligned_whatever_order_they_come_out_in(self):
        row = toy(items=[want(person="Quux"), want(destination="Today", type="task")])
        out = output(row, [got(route="Today", type="task"), got(person="Quux")])
        self.assertTrue(score.judge(row, out)["correct"])

    def test_a_title_defect_is_cosmetic_and_never_fails(self):
        row = toy()
        result = score.judge(row, output(row, [got(title="um zorp the blicket")]))
        self.assertTrue(result["correct"])
        self.assertEqual(result["cosmetic"], ["hesitation kept"])

    def test_title_constraints_are_not_cosmetic(self):
        row = toy(items=[want(title_has=["not blicket"], title_lacks=["wibble"])])
        self.assertTrue(score.judge(row, output(row, [got(title="Zorp not blicket")]))["correct"])
        failed = score.judge(row, output(row, [got(title="Zorp blicket wibble")]))["failed"]
        self.assertEqual(failed, ["title_has", "title_lacks"])

    def test_no_output_is_incorrect_rather_than_skipped(self):
        result = score.judge(toy(), None)
        self.assertEqual((result["correct"], result["missing"]), (False, True))

    def test_an_alternative_reading_is_accepted(self):
        row = toy(items=[want(), want()], alternatives=[{"items": [want()]}])
        result = score.judge(row, output(row))
        self.assertEqual((result["correct"], result["reading"]), (True, 1))


class Timing(unittest.TestCase):
    def check(self, expected, actual):
        return score.time_ok(expected, None if actual is None else epoch(actual))

    def test_day_only_is_not_nine_am(self):
        self.assertTrue(self.check("2026-08-04", "2026-08-04T00:00"))
        self.assertFalse(self.check("2026-08-04", "2026-08-04T09:00"))

    def test_any_time_that_day(self):
        self.assertTrue(self.check("2026-08-04 *", "2026-08-04T09:00"))
        self.assertFalse(self.check("2026-08-04 *", "2026-08-05T09:00"))

    def test_exact_minute_in_toronto(self):
        self.assertTrue(self.check("2026-08-04T15:30", "2026-08-04T15:30"))
        self.assertFalse(self.check("2026-08-04T15:30", "2026-08-04T03:30"))

    def test_null_asserts_absence_and_any_asserts_presence(self):
        self.assertTrue(self.check(None, None))
        self.assertFalse(self.check(None, "2026-08-04T15:30"))
        self.assertTrue(self.check("any", "2026-09-01T01:00"))
        self.assertFalse(self.check("any", None))

    def test_a_reminder_that_should_not_ring_fails_as_remind(self):
        row = toy(items=[want(destination="NeedsReview", type="task")])
        out = output(row, [got(route="Today", type="task", needsReview=True,
                               reminder=epoch("2026-08-03T20:00"),
                               delivery="notification")])
        self.assertEqual(score.judge(row, out)["failed"], ["delivery", "remind"])


class PlaceRecurrenceOperations(unittest.TestCase):
    def test_place(self):
        self.assertTrue(score.place_ok({"event": "arrive", "place": "home"},
                                       "arrive home repeats=false"))
        self.assertTrue(score.place_ok({"event": "leave", "place": "the Glorp"},
                                       "leave named(Glorp) repeats=false"))
        self.assertFalse(score.place_ok({"event": "arrive", "place": "home"},
                                        "leave home repeats=false"))
        self.assertFalse(score.place_ok(None, "arrive work repeats=true"))
        self.assertTrue(score.place_ok(None, "nil"))

    def test_recurrence_weekdays_use_calendar_numbering(self):
        rule = {"frequency": "weekly", "interval": 1, "weekdays": [2, 4]}
        self.assertTrue(score.recurs_ok({"frequency": "weekly",
                                         "weekdays": ["mon", "wed"]}, rule))
        self.assertFalse(score.recurs_ok({"frequency": "weekly",
                                          "weekdays": ["tue"]}, rule))
        self.assertFalse(score.recurs_ok(None, rule))

    def test_operation_and_its_target_are_critical(self):
        row = toy(items=[], operations=[{"operation": "cancel", "target": "the blicket"}])
        good = output(row, [], [{"operation": "cancel", "target": "zorp blicket"}])
        wrong_target = output(row, [], [{"operation": "cancel", "target": "wibble"}])
        no_op = output(row, [], [])
        self.assertTrue(score.judge(row, good)["correct"])
        self.assertEqual(score.judge(row, wrong_target)["failed"], ["operation_target"])
        self.assertEqual(score.judge(row, no_op)["worst"], "critical")


class SeverityMirrorsTheCorpus(unittest.TestCase):
    """The grading table is `CorpusSeverity.forField`, not a second opinion."""

    NAMES = {"count": "count", "operation": "operation",
             "operationTarget": "operation_target", "route": "destination",
             "delivery": "delivery", "recurrence": "recurs", "location": "place",
             "reminderDate": "remind", "dueDate": "due", "type": "type",
             "person": "person", "needsReview": "destination"}

    def test_every_graded_corpus_field_carries_the_same_severity_here(self):
        source = (score.ROOT / "SpeakItTests" / "SemanticCorpus.swift").read_text()
        body = source[source.index("static func forField"):]
        for case, level in re.findall(r'case ((?:"\w+",?\s*)+):\s*return \.(\w+)', body):
            for field in re.findall(r'"(\w+)"', case):
                if field not in self.NAMES:
                    continue
                mine = score.SEVERITY[self.NAMES[field]]
                # needsReview is metadata there and a destination here: it is
                # what decides whether a row sits in Needs review, so it is
                # graded with the surface it moves the row to.
                if field == "needsReview":
                    self.assertEqual(mine, "behavioral")
                else:
                    self.assertEqual(mine, level, field)


class SealedReportAndOneShotScoring(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        self.rows = [toy("TOY-1"), toy("TOY-2", family="negation-becomes-action",
                                       items=[want(destination="Today", type="task")])]
        self.contract = self.dir / "set.jsonl"
        self.contract.write_text("".join(json.dumps(r) + "\n" for r in self.rows))
        self.actual = self.dir / "actual.jsonl"
        self.actual.write_text(json.dumps(output(self.rows[0])) + "\n"
                               + json.dumps({"id": "TOY-2", "text": "different asr text",
                                             "items": [got()], "operations": []}) + "\n")

    def run_cli(self, *argv):
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            try:
                code = score.main([str(a) for a in argv])
            except SystemExit as stop:
                code = stop.code
        return code, buffer.getvalue()

    def test_default_report_prints_no_text_no_ids_and_no_aggregate(self):
        _, out = self.run_cli("score", self.contract, self.actual, "--unsealed")
        self.assertNotIn("zorp", out.lower())
        self.assertNotIn("TOY-", out)
        rated = [line for line in out.splitlines() if "%)" in line]
        self.assertTrue(rated)
        self.assertEqual([line for line in rated
                          if not line.startswith(score.FAMILIES)], [],
                         "a rate that is not a family's is an aggregate")
        for family in score.FAMILIES:
            self.assertIn(family, out)
        self.assertIn("UNDER MINIMUM", out)
        self.assertRegex(out, r"negation-becomes-action\s+1\s+0\s+0/1")

    def test_failures_flag_is_the_only_way_text_is_printed(self):
        _, out = self.run_cli("score", self.contract, self.actual, "--unsealed", "--failures")
        self.assertIn("TOY-2", out)

    def test_actual_output_is_matched_by_id_when_text_differs(self):
        by_id, by_text = score.index_actual(score.load_jsonl(self.actual))
        self.assertIn("TOY-2", by_id)

    def test_seal_score_once_then_detect_an_edit(self):
        seal, receipt = self.dir / "seal.json", self.dir / "receipt.json"
        self.assertEqual(self.run_cli("seal", self.contract, "--out", seal)[0], 0)
        self.assertNotEqual(self.run_cli("seal", self.contract, "--out", seal)[0], 0)
        sealed = ("score", self.contract, self.actual, "--seal", seal, "--receipt",
                  receipt, "--commit", "0" * 40, "--path", "rules")
        self.assertEqual(self.run_cli(*sealed)[0], 0)
        self.assertEqual(json.loads(receipt.read_text())["results"]["TOY-2"]["correct"], False)
        self.assertNotEqual(self.run_cli(*sealed)[0], 0, "scoring is one-shot")
        self.assertEqual(self.run_cli("verify", self.contract, "--seal", seal,
                                      "--receipt", receipt)[0], 0)
        edited = dict(self.rows[0], utterance="zorp the wibble")
        self.contract.write_text(json.dumps(edited) + "\n" + json.dumps(self.rows[1]) + "\n")
        code, out = self.run_cli("verify", self.contract, "--seal", seal, "--receipt", receipt)
        self.assertEqual(code, 1)
        self.assertIn("1 edited", out)
        self.assertNotIn("wibble", out)

    def test_a_sealed_score_refuses_a_set_that_moved_since_sealing(self):
        seal = self.dir / "seal.json"
        self.run_cli("seal", self.contract, "--out", seal)
        self.contract.write_text(self.contract.read_text() + json.dumps(toy("TOY-3")) + "\n")
        code, _ = self.run_cli("score", self.contract, self.actual, "--seal", seal,
                               "--receipt", self.dir / "r.json", "--commit", "x",
                               "--path", "rules")
        self.assertNotEqual(code, 0)
        self.assertFalse((self.dir / "r.json").exists())

    def test_a_set_inside_the_repository_cannot_be_sealed(self):
        code, _ = self.run_cli("seal", HERE / "never-written.jsonl", "--out", self.dir / "s.json")
        self.assertNotEqual(code, 0)
        self.assertFalse((HERE / "never-written.jsonl").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
