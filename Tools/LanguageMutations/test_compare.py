"""Tests for the disagreement reporter.

The probe cannot run on Linux, so these drive `compare.py` from a synthetic
transcript in the shape the probe emits. They check the comparison logic, not
the parser's output — which is the half that can be checked anywhere.
"""

import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import compare


def transcript(entries):
    """Build probe-shaped output. Each entry: (utterance, route, [titles])."""
    out = []
    for utterance, route, titles in entries:
        block = [f'── "{utterance}"']
        for title in titles:
            block.append(f"   row title: {title}")
            block.append(f"   route:     {route}")
            block.append("   due:       nil")
            block.append("   remind:    nil")
        out.append("\n".join(block))
    return "\n".join(out)


def run(pairs, entries, verbose=False):
    with tempfile.TemporaryDirectory() as d:
        pairs_path = Path(d) / "pairs.tsv"
        probe_path = Path(d) / "probe.txt"
        pairs_path.write_text("base\tmutated\tfamily\tstrength\n" + "".join(
            "\t".join(p) + "\n" for p in pairs))
        probe_path.write_text(transcript(entries))
        argv = ["compare.py", str(pairs_path), str(probe_path)]
        if verbose:
            argv.append("--verbose")
        import sys
        old, sys.argv = sys.argv, argv
        buffer = io.StringIO()
        try:
            with redirect_stdout(buffer):
                compare.main()
        finally:
            sys.argv = old
        return buffer.getvalue()


class Disagreements(unittest.TestCase):
    def test_identical_readings_agree(self):
        out = run(
            [("buy milk", "um buy milk", "filler", "strict")],
            [("buy milk", "Today", ["Buy milk"]),
             ("um buy milk", "Today", ["Buy milk"])],
        )
        self.assertIn("filler", out)
        self.assertRegex(out, r"filler\s+1\s+0")

    def test_a_changed_destination_is_a_disagreement(self):
        out = run(
            [("buy milk", "buy milk bye", "sign-off", "strict")],
            [("buy milk", "Today", ["Buy milk"]),
             ("buy milk bye", "Memory", ["Buy milk bye"])],
        )
        self.assertRegex(out, r"sign-off\s+1\s+1")

    def test_a_changed_row_count_is_a_disagreement(self):
        out = run(
            [("a and b", "okay so a and b", "preamble", "strict")],
            [("a and b", "Today", ["A", "B"]),
             ("okay so a and b", "Today", ["Okay so a", "B", "C"])],
        )
        self.assertRegex(out, r"preamble\s+1\s+1")

    def test_structure_strength_forgives_a_changed_title(self):
        """A proper-noun swap must change the title; that is the point of it."""
        out = run(
            [("buy socks at Mooji", "buy socks at Daiso", "proper-noun", "structure")],
            [("buy socks at Mooji", "Today", ["Buy socks at Mooji"]),
             ("buy socks at Daiso", "Today", ["Buy socks at Daiso"])],
        )
        self.assertRegex(out, r"proper-noun\s+1\s+0")

    def test_strict_strength_does_not_forgive_a_changed_title(self):
        out = run(
            [("buy milk", "um buy milk", "filler", "strict")],
            [("buy milk", "Today", ["Buy milk"]),
             ("um buy milk", "Today", ["Um buy milk"])],
        )
        self.assertRegex(out, r"filler\s+1\s+1")

    def test_missing_probe_output_counts_as_a_disagreement(self):
        out = run(
            [("buy milk", "um buy milk", "filler", "strict")],
            [("buy milk", "Today", ["Buy milk"])],
        )
        self.assertRegex(out, r"filler\s+1\s+1")


class Honesty(unittest.TestCase):
    def test_the_report_refuses_to_read_as_accuracy(self):
        out = run(
            [("buy milk", "um buy milk", "filler", "strict")],
            [("buy milk", "Today", ["Buy milk"]),
             ("um buy milk", "Today", ["Buy milk"])],
        )
        self.assertIn("consistency, not accuracy", out)
        self.assertIn("Agreement is not evidence of correctness", out)

    def test_verbose_names_the_pair_that_disagreed(self):
        out = run(
            [("buy milk", "buy milk bye", "sign-off", "strict")],
            [("buy milk", "Today", ["Buy milk"]),
             ("buy milk bye", "Memory", ["Buy milk bye"])],
            verbose=True,
        )
        self.assertIn("destination Today → Memory", out)
        self.assertIn("buy milk bye", out)



class MeaningChangeIsInverted(unittest.TestCase):
    """A divergent family reports sameness, not difference."""

    BASE = {
        "routes": ("today",), "titles": ("Call Sarah",), "rows": 1,
        "operation": False, "due": (), "remind": (),
    }

    def test_an_identical_reading_is_the_defect(self):
        found = compare.disagreement(self.BASE, dict(self.BASE), "divergent")
        self.assertIsNotNone(found)
        self.assertIn("unchanged reading", found)

    def test_a_changed_consequence_passes(self):
        """These are the differences that mean the engine acted differently."""
        for field, value in [
            ("routes", ("memory",)),
            ("rows", 0),
            ("operation", True),
            ("due", ("2026-09-17",)),
        ]:
            mutated = dict(self.BASE)
            mutated[field] = value
            self.assertIsNone(
                compare.disagreement(self.BASE, mutated, "divergent"),
                f"a changed {field} should count as the engine noticing",
            )
            self.assertIsNone(
                compare.weakness(self.BASE, mutated, "divergent"),
                f"a changed {field} is not merely a title move",
            )

    def test_a_title_only_change_is_neither_verdict(self):
        """The case the single bucket got wrong, in the direction that matters.

        Every divergent family works by adding words and a title is built from
        the person's words, so a title difference is nearly free. Counting it
        as noticing made the test satisfiable by string propagation: Speak It
        could answer "don't call Sarah" with an open Today errand titled "Don't
        call Sarah" and this tool would report nothing. It is now its own
        column — not clean, not blind.
        """
        mutated = dict(self.BASE, titles=("Don't call Sarah",))
        self.assertIsNone(compare.disagreement(self.BASE, mutated, "divergent"))
        found = compare.weakness(self.BASE, mutated, "divergent")
        self.assertIsNotNone(found, "a title-only divergence must not be silent")
        self.assertIn("title-only", found)

    def test_the_two_buckets_never_hold_the_same_pair(self):
        """A pair counted twice would inflate a rate nobody could reconcile."""
        cases = [
            dict(self.BASE),
            dict(self.BASE, titles=("Don't call Sarah",)),
            dict(self.BASE, routes=("memory",)),
            dict(self.BASE, rows=2, titles=("Call Sarah", "Ask Dana")),
            None,
        ]
        for mutated in cases:
            both = (
                compare.disagreement(self.BASE, mutated, "divergent") is not None
                and compare.weakness(self.BASE, mutated, "divergent") is not None
            )
            self.assertFalse(both, f"counted twice: {mutated}")

    def test_the_weak_bucket_is_only_for_divergent_families(self):
        mutated = dict(self.BASE, titles=("Um call Sarah",))
        for strength in ("strict", "structure"):
            self.assertIsNone(compare.weakness(self.BASE, mutated, strength))

    def test_a_title_only_divergence_reaches_the_report(self):
        """The bucket is worthless if it stops at the function."""
        out = run(
            [("call Sarah", "don't call Sarah", "negation", "divergent")],
            [("call Sarah", "Today", ["Call Sarah"]),
             ("don't call Sarah", "Today", ["Don't call Sarah"])],
            verbose=True,
        )
        self.assertIn("title-only", out)
        self.assertRegex(out, r"negation\s+1\s+0\s+0\.0%\s+1")
        self.assertIn("before treating the family's zero as understanding", out)

    def test_missing_output_is_still_reported(self):
        self.assertEqual(
            "missing probe output",
            compare.disagreement(self.BASE, None, "divergent"),
        )


class FieldsAreReadWhole(unittest.TestCase):
    """A date is four tokens and the reader used to keep one of them.

    `due:        Fri Aug 7 (day only)` matched against `(\\S+)` gave `Fri`, so
    every time of day was invisible and any two dates sharing a weekday
    compared equal. Harmless while `due` only had to differ from `nil`, and
    not harmless once `_consequence` reads it: a divergent pair whose date
    really moved would land in `title-only`, the column that means the engine
    did nothing.
    """

    PROBE = (
        '── "base"\n'
        "   row title:  Call Sarah\n"
        "   route:      Today   type: task   category: none   priority: normal\n"
        "   due:        Fri Aug 7 (day only)\n"
        "   remind:     nil   delivery: silent\n"
        '── "mutated"\n'
        "   row title:  Call Sarah\n"
        "   route:      Today   type: task   category: none   priority: normal\n"
        "   due:        Fri Aug 14 (day only)\n"
        "   remind:     Fri Aug 14 09:00   delivery: alert\n"
    )

    def blocks(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "probe.txt"
            path.write_text(self.PROBE)
            return compare.read_blocks(str(path))

    def test_a_date_keeps_every_token(self):
        blocks = self.blocks()
        self.assertEqual(("Fri Aug 7 (day only)",), blocks["base"]["due"])
        self.assertEqual(("Fri Aug 14 (day only)",), blocks["mutated"]["due"])

    def test_two_dates_on_the_same_weekday_are_not_equal(self):
        blocks = self.blocks()
        self.assertNotEqual(blocks["base"]["due"], blocks["mutated"]["due"])

    def test_a_value_stops_at_the_next_field_on_its_line(self):
        """`remind:` is followed by `delivery:`, which is not part of the time."""
        blocks = self.blocks()
        self.assertEqual(("nil",), blocks["base"]["remind"])
        self.assertEqual(("Fri Aug 14 09:00",), blocks["mutated"]["remind"])
        self.assertEqual(("Today",), blocks["base"]["routes"])

    def test_a_moved_date_under_one_title_is_not_filed_as_title_only(self):
        """The misfiling the truncation would have caused, pinned."""
        base, mutated = self.blocks()["base"], self.blocks()["mutated"]
        self.assertEqual(base["titles"], mutated["titles"])
        self.assertIsNone(compare.disagreement(base, mutated, "divergent"))
        self.assertIsNone(compare.weakness(base, mutated, "divergent"))

    def test_a_moved_date_is_a_strict_disagreement(self):
        base, mutated = self.blocks()["base"], self.blocks()["mutated"]
        found = compare.disagreement(base, mutated, "strict")
        self.assertIsNotNone(found, "strict promises every field matches")
        self.assertIn("due", found)


if __name__ == "__main__":
    unittest.main(verbosity=2)
