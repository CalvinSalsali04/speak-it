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


if __name__ == "__main__":
    unittest.main()
