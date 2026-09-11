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


if __name__ == "__main__":
    unittest.main(verbosity=2)
