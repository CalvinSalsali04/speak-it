"""Regression coverage for the per-connector report, not for the parser.

Every probe output here is written by hand, so these run in a container with no
Swift toolchain — which is where this set was written and where the engine
cannot be built at all.

Two of these tests are about the report's own honesty rather than its
arithmetic: that it prints no capture text on any path including the error
paths, and that its numbers agree with the shared scorer, which parses the same
probe output with a separately written matcher.
"""
import contextlib
import importlib.util
import io
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SET = HERE / "consequence.tsv"


def report_module():
    spec = importlib.util.spec_from_file_location(
        "block_report", HERE / "block-report.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def utterances():
    out = {}
    for line in SET.read_text(encoding="utf-8").splitlines():
        cells = line.split("\t")
        if re.match(r"^CQ\d+$", cells[0]) and len(cells) >= 5:
            out[cells[0]] = (cells[1], cells[4].strip())
    return out


def probe_text(rows, splitter=lambda cid, want: 1):
    """Probe output producing `splitter(id, want)` rows for each capture."""
    chunks = []
    for cid, (utt, want) in rows.items():
        made = splitter(cid, want)
        body = "".join("  row title: x\n  route:   Today\n" for _ in range(made))
        chunks.append(f'── "{utt}"\n{body}')
    return "\n".join(chunks)


class ReportCase(unittest.TestCase):
    def setUp(self):
        self.report = report_module()
        self.rows = utterances()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def marked(self):
        """Connectors marked NOT INFORMATIVE in the TABLE.

        Counting the phrase in the whole report conflates a verdict on a block
        with the paragraph explaining what the verdict means, which is how this
        test failed first time round and why the explanation is now printed
        only when a block earns it.
        """
        found = set()
        for line in self._last.splitlines():
            if "NOT INFORMATIVE" not in line:
                continue
            for connector in self.report.CONNECTORS:
                if line.startswith(connector):
                    found.add(connector)
        return found

    def run_on(self, labels_path, probe_body):
        path = pathlib.Path(self.tmp.name) / "probe.txt"
        path.write_text(probe_body, encoding="utf-8")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = self.report.main(["block-report.py", str(labels_path), str(path)])
        self._last = out.getvalue()
        return code, self._last

    def labels_file(self, lines):
        path = pathlib.Path(self.tmp.name) / "labels.tsv"
        path.write_text("# id\tutterance\tfamily\tdest\tthoughts\n" + "".join(lines),
                        encoding="utf-8")
        return path


class ANeverSplittingParser(ReportCase):
    def test_every_block_is_marked_not_informative(self):
        code, _ = self.run_on(SET, probe_text(self.rows))
        self.assertEqual(code, 0)
        self.assertEqual(self.marked(), set(self.report.CONNECTORS))

    def test_the_whole_column_is_at_ceiling_while_the_split_column_is_zero(self):
        _, text = self.run_on(SET, probe_text(self.rows))
        self.assertIn("0/4 (0%)", text)
        self.assertIn("3/3 (100%)", text)


class APerfectParser(ReportCase):
    def splitter(self, cid, want):
        return int(want[0])

    def test_nothing_is_marked_not_informative(self):
        code, text = self.run_on(SET, probe_text(self.rows, self.splitter))
        self.assertEqual(code, 0)
        self.assertEqual(self.marked(), set())
        self.assertIn("both columns are worth reading", text)

    def test_the_mark_clears_by_itself_rather_than_by_an_edit(self):
        """One block splits correctly; only that block loses the mark."""
        def one_block(cid, want):
            return int(want[0]) if self.report.block_of(cid) == 0 else 1
        self.run_on(SET, probe_text(self.rows, one_block))
        self.assertEqual(self.marked(),
                         set(self.report.CONNECTORS) - {"and"})


class NoCaptureTextIsEverPrinted(ReportCase):
    """The report is run repeatedly while a sealed set is being read; printing
    one capture would spend it exactly as a diff did."""

    def assert_clean(self, text):
        leaked = [cid for cid, (utt, _) in self.rows.items() if utt in text]
        self.assertEqual(leaked, [], "capture text reached the report's output")

    def test_the_successful_path_prints_no_capture(self):
        _, text = self.run_on(SET, probe_text(self.rows))
        self.assert_clean(text)

    def test_the_failure_path_prints_no_capture(self):
        utt, _ = self.rows["CQ36"]
        lines = [f"CQ36\t{utt} and the rest\tconsequence-split\tToday\t2\n"]
        code, text = self.run_on(self.labels_file(lines), "")
        self.assertEqual(code, 1)
        self.assertIn("CQ36", text)
        self.assertNotIn(utt, text)


class TheRotationIsCheckedRatherThanAsserted(ReportCase):
    def test_every_capture_in_the_set_lands_in_exactly_one_block(self):
        placed = [self.report.block_of(cid) for cid in self.rows]
        self.assertNotIn(None, placed)
        self.assertEqual(len(self.rows), 56)

    def test_each_block_holds_the_same_number_of_captures(self):
        from collections import Counter
        sizes = Counter(self.report.block_of(cid) for cid in self.rows)
        self.assertEqual(sorted(sizes), list(range(len(self.report.CONNECTORS))))
        self.assertEqual(set(sizes.values()), {7})

    def test_an_id_outside_the_rotation_fails_rather_than_being_dropped(self):
        lines = ["CQ99\ta b c\tconsequence-split\tToday\t2\n"]
        code, text = self.run_on(self.labels_file(lines), "")
        self.assertEqual(code, 2)
        self.assertIn("CQ99", text)

    def test_an_unexplained_connector_in_the_no_connector_block_fails(self):
        lines = ["CQ39\tthe boiler is serviced then book the sweep\t"
                 "consequence-split\tToday\t2\n"]
        code, text = self.run_on(self.labels_file(lines), "")
        self.assertEqual(code, 1)
        self.assertIn("CQ39", text)
        self.assertIn("no recorded reason", text)

    def test_the_two_recorded_exceptions_do_not_fail_the_real_set(self):
        code, text = self.run_on(SET, probe_text(self.rows))
        self.assertEqual(code, 0)
        for cid in self.report.ACKNOWLEDGED:
            self.assertIn(cid, text)

    def test_the_base_rate_is_printed_so_a_weak_check_reads_as_weak(self):
        _, text = self.run_on(SET, probe_text(self.rows))
        self.assertIn("appears in 21/56 overall  (weak", text)

    def test_connector_matching_respects_word_boundaries(self):
        self.assertFalse(self.report.carries("android sales", "and"))
        self.assertFalse(self.report.carries("sober by then", "so"))
        self.assertTrue(self.report.carries("milk and eggs", "and"))


class AnEmptyReadIsRefused(ReportCase):
    def test_no_rows_is_not_a_clean_run(self):
        code, text = self.run_on(self.labels_file([]), "")
        self.assertEqual(code, 2)
        self.assertIn("no CQ rows", text)

    def test_the_empty_verdict_differs_from_the_failure_verdict(self):
        empty, _ = self.run_on(self.labels_file([]), "")
        lines = ["CQ39\tthe boiler is done then book the sweep\tx\tToday\t2\n"]
        failing, _ = self.run_on(self.labels_file(lines), "")
        self.assertEqual(empty, 2)
        self.assertEqual(failing, 1)


class ItAgreesWithTheSharedScorer(ReportCase):
    """Two separately written matchers read the same probe output.

    An end-to-end test cannot check its own matcher, so the check is that the
    shared scorer — whose parsing this file deliberately does not import —
    reaches the same thought-count totals. It holds because this set labels no
    capture Ambiguous, which the shared scorer excludes from its count; a set
    that did would need the caveat, not the assertion.
    """

    def totals(self, text):
        m = re.search(r"thought count strict\s+(\d+)/(\d+)", text)
        return (int(m.group(1)), int(m.group(2))) if m else None

    def test_the_two_scorers_report_the_same_thought_count(self):
        body = probe_text(self.rows, lambda cid, want: int(want[0]))
        path = pathlib.Path(self.tmp.name) / "probe.txt"
        path.write_text(body, encoding="utf-8")

        shared = subprocess.run(
            [sys.executable, str(ROOT / "Tools/CorpusRunner/heldout/score.py"),
             str(SET), str(path)], capture_output=True, text=True)
        self.assertEqual(shared.returncode, 0, shared.stderr)

        _, mine = self.run_on(SET, body)
        ok = sum(int(a) for a, _ in re.findall(r"(\d+)/(\d+) \(", mine))
        total = sum(int(b) for _, b in re.findall(r"(\d+)/(\d+) \(", mine))
        self.assertEqual((ok, total), self.totals(shared.stdout))


if __name__ == "__main__":
    unittest.main(verbosity=1)
