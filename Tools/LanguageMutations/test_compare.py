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


class KeysComeFromTheReader(unittest.TestCase):
    """Every field the comparison reads must be one `read_blocks` produces.

    This was checked by hand twice, once by the author and once by the
    reviewer, and both of us said the same thing about it: that is exactly the
    shape which passes twice and then fails silently the day somebody adds a
    sixth field. A hand-written fixture cannot catch it either, because the
    fixture gets written by the same person adding the field.

    So the keys are not listed here. They are collected by watching the
    functions run against a block that remembers what it was asked for, and
    compared against what the reader actually emits. Adding a field to
    `_consequence` without adding it to `read_blocks` fails the first test;
    adding it to `read_blocks` and reading it nowhere fails the second.
    """

    PROBE = (
        '── "base"\n'
        "   row title:  Call Sarah\n"
        "   route:      Today   type: task   category: none   priority: normal\n"
        "   due:        Fri Aug 7 (day only)\n"
        "   remind:     nil   delivery: silent\n"
        '── "retitled"\n'
        "   row title:  Don't call Sarah\n"
        "   route:      Today   type: task   category: none   priority: normal\n"
        "   due:        Fri Aug 7 (day only)\n"
        "   remind:     nil   delivery: silent\n"
    )

    class Recorder(dict):
        """A block that remembers which fields were asked of it."""

        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self.seen = set()

        def __getitem__(self, key):
            self.seen.add(key)
            if key not in self:
                # Record the read and keep going. Raising here would kill the
                # test on a KeyError and report a traceback instead of the
                # name of the field that is missing, which is the one thing
                # the person who just added it needs to be told.
                return ()
            return super().__getitem__(key)

    def blocks(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "probe.txt"
            path.write_text(self.PROBE)
            return compare.read_blocks(str(path))

    def fields_read(self):
        """Drive every comparison path and return the union of fields touched.

        `disagreement` is driven with two equal blocks under `strict` on
        purpose: equality is what makes it fall past every early return and
        reach the last comparison, so one call covers all of them.
        """
        blocks = self.blocks()
        seen = set()
        for base_name, mutated_name, strength, call in [
            ("base", "base", "strict", compare.disagreement),
            ("base", "retitled", "divergent", compare.disagreement),
            ("base", "retitled", "divergent", compare.weakness),
        ]:
            base = self.Recorder(blocks[base_name])
            mutated = self.Recorder(blocks[mutated_name])
            call(base, mutated, strength)
            seen |= base.seen | mutated.seen
        for single in (compare._consequence, compare._reading, compare._describe):
            block = self.Recorder(blocks["base"])
            single(block)
            seen |= block.seen
        return seen

    def test_every_field_the_comparison_reads_is_produced(self):
        produced = set(self.blocks()["base"])
        missing = self.fields_read() - produced
        self.assertEqual(
            set(), missing,
            f"read but never parsed out of the probe: {sorted(missing)} — "
            "these raise KeyError on a real run",
        )

    def test_every_field_produced_is_read_somewhere(self):
        """A parsed field nobody compares is a promise the report does not keep."""
        unused = set(self.blocks()["base"]) - self.fields_read()
        self.assertEqual(
            set(), unused,
            f"parsed and then ignored: {sorted(unused)} — either compare it "
            "or stop reading it",
        )

    def test_the_recorder_reports_reads_exactly(self):
        """Both of the recorder's answers have to be right, so both are injected.

        A recorder that reported every key it held would make the first test
        vacuous; one that stayed silent about a key it was asked for but did
        not hold would make it silently pass on exactly the defect it exists
        for. Neither direction is safe to assume, and
        `test_completion_refuses_a_verb_it_cannot_conjugate` in
        `test_mutate.py` is here because this project has assumed one before.
        """
        held_but_never_asked_for = self.Recorder(
            dict(self.blocks()["base"], spare=())
        )
        compare._consequence(held_but_never_asked_for)
        self.assertNotIn(
            "spare", held_but_never_asked_for.seen,
            "reported a field nothing asked for: the second test would fail "
            "on a field that is genuinely used",
        )
        self.assertIn(
            "routes", held_but_never_asked_for.seen,
            "reported nothing at all: the first test can never fail",
        )

        asked_for_but_not_held = self.Recorder(self.blocks()["base"])
        del asked_for_but_not_held["due"]
        compare._consequence(asked_for_but_not_held)  # must not raise
        self.assertIn(
            "due", asked_for_but_not_held.seen,
            "a field read but not parsed must still be reported, or the "
            "missing-field test passes on the case it was written for",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
