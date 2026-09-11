"""Regression coverage for the evaluation instrument, independent of parser output."""
import pathlib
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


if __name__ == "__main__":
    unittest.main()
