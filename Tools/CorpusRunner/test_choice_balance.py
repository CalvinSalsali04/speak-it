"""Regression coverage for the choice-family balance checker.

The checker is what is under test, never the parser. Every fixture is a small
TSV written here, so these run in a container with no Swift toolchain.

Three of these tests exist because of the same class of defect: an instrument
that reports a clean result when it has in fact read nothing, matched nothing,
or checked a requirement it cannot check.
"""
import contextlib
import importlib.util
import io
import pathlib
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent


def balance_module():
    spec = importlib.util.spec_from_file_location(
        "choice_balance", HERE / "choice-balance.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HEADER = "# id\tutterance\tfamily\texpected_destination\texpected_thoughts\n"


def row(cid, utterance, tag):
    return f"{cid}\t{utterance}\t{tag}\tToday\t1\n"


#: Six resolutions, three of them bare restatements (33%+), all five slots
#: present, one decoy carrying a marker that resolves nothing.
BALANCED = [
    row("X01", "tuesday or friday for the physio book the tuesday slot",
        "choice-time-r1"),
    row("X02", "ask priya or dan about the invoice ask dan about the invoice",
        "choice-person-r1"),
    row("X03", "the king branch or the dundas one return it to dundas",
        "choice-place-r1"),
    row("X04", "the blue chair or the grey one actually the blue chair",
        "choice-object-r2"),
    row("X05", "drive to the airport or take the bus no take the bus",
        "choice-clause-r2"),
    row("X06", "the king branch or the dundas one not the king one",
        "choice-place-r3"),
    row("X07", "salmon wednesday or thursday i genuinely cannot decide",
        "choice-time-open"),
    row("X08", "ring the surgery there is no rush about it at all",
        "choice-clause-open"),
]


class FixtureCase(unittest.TestCase):
    def setUp(self):
        self.balance = balance_module()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def write(self, lines):
        path = pathlib.Path(self.tmp.name) / "choice.tsv"
        path.write_text(HEADER + "".join(lines))
        return path

    def run_check(self, lines):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = self.balance.check(self.write(lines))
        return code, out.getvalue()


class BalancedSetPasses(FixtureCase):
    def test_a_balanced_set_exits_zero(self):
        code, _ = self.run_check(BALANCED)
        self.assertEqual(code, 0)

    def test_the_pass_says_which_rules_it_did_not_check(self):
        """A pass on three rules of five must not read as a pass on five."""
        _, text = self.run_check(BALANCED)
        self.assertIn("B4 and B5 are unexamined", text)
        self.assertIn("NOT CHECKED HERE", text)

    def test_inferred_rows_are_counted_out_of_the_family(self):
        lines = BALANCED + [row("X09", "take the bus so leave the car at home",
                                "choice-clause-inferred")]
        code, text = self.run_check(lines)
        self.assertEqual(code, 0)
        self.assertIn("inferred, excluded: 1", text)


class EmptyIsNotBalanced(FixtureCase):
    def test_a_file_with_no_choice_rows_refuses_rather_than_passing(self):
        """Every proportion in the checker is satisfied perfectly by nothing.

        This is the one result that looks identical whether the reader worked.
        """
        code, text = self.run_check([row("X01", "buy milk", "rambling-clean")])
        self.assertEqual(code, 2)
        self.assertIn("it is an empty one", text)

    def test_the_empty_verdict_is_not_the_failure_verdict(self):
        empty, _ = self.run_check([])
        broken, _ = self.run_check(BALANCED[:1])
        self.assertEqual(empty, 2)
        self.assertNotEqual(broken, 0)


class MatcherCanary(FixtureCase):
    def test_the_self_check_string_is_matched_by_the_real_matcher(self):
        self.assertTrue(self.balance.matcher_is_working())
        self.assertTrue(self.balance.markers_in(self.balance.SELF_CHECK))

    def test_a_matcher_that_matches_nothing_refuses_to_report(self):
        """Without this, every row reads as marker-free and B1 passes wide."""
        self.balance.MARKERS = ()
        code, text = self.run_check(BALANCED)
        self.assertEqual(code, 2)
        self.assertIn("marker matcher cannot find", text)

    def test_markers_match_on_word_boundaries(self):
        self.assertEqual(self.balance.markers_in("the actual invoice"), [])
        self.assertEqual(self.balance.markers_in("nothing is booked"), [])
        self.assertIn("no", self.balance.markers_in("no take the bus"))
        self.assertIn("actually", self.balance.markers_in("actually the blue one"))


class B1BareRestatements(FixtureCase):
    def test_too_few_bare_restatements_fails(self):
        """Drop the three r1 rows and the resolutions are all marked."""
        code, text = self.run_check(BALANCED[3:])
        self.assertEqual(code, 1)
        self.assertIn("fewer than a third", text)

    def test_an_r1_row_carrying_a_marker_fails_rather_than_being_believed(self):
        lines = list(BALANCED)
        lines[0] = row("X01", "tuesday or friday actually book the tuesday slot",
                       "choice-time-r1")
        code, text = self.run_check(lines)
        self.assertEqual(code, 1)
        self.assertIn("tagged r1 but carries a resolution marker", text)
        self.assertIn("X01", text)

    def test_an_allowance_clears_that_row_and_names_it(self):
        lines = list(BALANCED)
        lines[0] = row("X01", "tuesday or friday actually book the tuesday slot",
                       "choice-time-r1")
        lines.insert(0, "# allow-marker X01 `actually` here means in fact\n")
        code, text = self.run_check(lines)
        self.assertEqual(code, 0)
        self.assertIn("marker allowances        1", text)

    def test_an_allowance_without_a_reason_is_not_an_allowance(self):
        lines = list(BALANCED)
        lines[0] = row("X01", "tuesday or friday actually book the tuesday slot",
                       "choice-time-r1")
        lines.insert(0, "# allow-marker X01\n")
        code, _ = self.run_check(lines)
        self.assertEqual(code, 1)


class B2Decoys(FixtureCase):
    def test_a_set_with_no_decoy_marker_fails(self):
        lines = [r for r in BALANCED if "no rush" not in r]
        lines = [r.replace("i genuinely cannot decide", "i cannot decide")
                 for r in lines]
        code, text = self.run_check(lines)
        self.assertEqual(code, 1)
        self.assertIn("resolves nothing", text)


class B3Slots(FixtureCase):
    def test_a_missing_slot_fails_and_names_it(self):
        lines = [r for r in BALANCED if "-place-" not in r]
        code, text = self.run_check(lines)
        self.assertEqual(code, 1)
        self.assertIn("no captures for slot(s): place", text)

    def test_one_slot_over_half_fails(self):
        lines = list(BALANCED) + [
            row(f"Y{n:02d}", "tuesday or friday book the tuesday slot",
                "choice-time-r1") for n in range(6)]
        code, text = self.run_check(lines)
        self.assertEqual(code, 1)
        self.assertIn("over half", text)


class TagGrammar(FixtureCase):
    def test_a_tag_outside_the_grammar_fails_rather_than_being_skipped(self):
        lines = list(BALANCED) + [row("X99", "a or b, b", "choice-mood-r1")]
        code, text = self.run_check(lines)
        self.assertEqual(code, 1)
        self.assertIn("outside the grammar", text)
        self.assertIn("X99", text)


class TheCheckerAndTheDefinitionStayInStep(FixtureCase):
    """The document says which rules this script checks. That sentence is a
    claim about a file, and a claim about a file decays silently.

    The totality test is the one that matters: every rule the definition
    states must be either checked here or named here as unchecked. A rule that
    is in neither list is a rule nobody is responsible for, and the checker
    would go on printing a clean bill beside it.
    """

    DOC = HERE.parents[1] / "Docs" / "CHOICE_FAMILY_EVALUATION.md"

    def rules_in_the_definition(self):
        import re
        return set(re.findall(r"\*\*(B\d)\.\*\*", self.DOC.read_text()))

    def test_the_definition_names_this_script_by_its_real_path(self):
        named = "Tools/CorpusRunner/choice-balance.py"
        self.assertIn(named, self.DOC.read_text())
        self.assertTrue((HERE.parents[1] / named).exists())

    def test_every_rule_in_the_definition_is_checked_here_or_named_unchecked(self):
        _, text = self.run_check(BALANCED)
        unaccounted = set()
        for rule in self.rules_in_the_definition():
            checked = f"{rule} " in text or f"{rule}  " in text
            if not checked:
                unaccounted.add(rule)
        self.assertEqual(unaccounted, set(),
                         "rules in the definition that this checker neither "
                         "checks nor declares unchecked")

    def test_the_definition_has_not_quietly_emptied(self):
        """Zero rules parsed would satisfy the test above perfectly."""
        self.assertGreaterEqual(len(self.rules_in_the_definition()), 5)


class TheMarkedFigureIsRecomputed(FixtureCase):
    """A number in prose is a measurement nobody re-runs.

    The definition says how many of the readable decision rows resolve by
    restating their own clean twin, which is the evidence for B4 existing at
    all. The first draft of that sentence said four of five, carried over from
    `KNOWN_ISSUES.md` and already stale: this thread had added rows since. So
    the figure is marked in the document and recomputed here.

    The limit is worth stating because it is the same shape as everything else
    in this directory: **this catches a marked figure that drifts, and cannot
    catch a claim nobody marked.**
    """

    DOC = HERE.parents[1] / "Docs" / "CHOICE_FAMILY_EVALUATION.md"
    SET = HERE / "devsets" / "rambling.tsv"
    MARKER = r"<!--\s*recomputed:\s*twin-restatement\s+(\d+)\s+of\s+(\d+)\s*-->"

    def rows(self):
        out = {}
        for line in self.SET.read_text().splitlines():
            if line.startswith("#") or not line.strip():
                continue
            cells = line.split("\t")
            if len(cells) >= 3 and cells[0] != "id":
                out[cells[0]] = (cells[1], cells[2])
        return out

    def measure(self):
        """(restating, total) over decision rows that have a clean twin."""
        rows = self.rows()
        rambling = [k for k, v in rows.items()
                    if v[1].startswith("decision-") and k.endswith("R")]
        pairs = [(k, k[:-1] + "C") for k in rambling if k[:-1] + "C" in rows]
        restating = [k for k, twin in pairs if rows[twin][0] in rows[k][0]]
        return len(restating), len(pairs)

    def claimed(self):
        import re
        found = re.findall(self.MARKER, self.DOC.read_text())
        return [(int(a), int(b)) for a, b in found]

    def test_the_document_still_carries_the_marker(self):
        """No marker means the test below checks nothing, silently."""
        self.assertEqual(len(self.claimed()), 1)

    def test_the_marked_figure_matches_the_set_it_describes(self):
        self.assertEqual(self.claimed()[0], self.measure())

    def test_the_measurement_is_over_something(self):
        """Zero pairs would make any claim of `0 of 0` agree perfectly."""
        _, total = self.measure()
        self.assertGreaterEqual(total, 5)


class SealedSetsAreRefused(FixtureCase):
    def test_every_sealed_set_is_refused_by_path(self):
        """The checker prints ids, and a set being shaped would be read."""
        import sys
        sys.path.insert(0, str(HERE))
        import corpus_paths
        for path in corpus_paths.sealed():
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = self.balance.check(path)
            self.assertEqual(code, 2, path.name)
            self.assertIn("is a sealed set", out.getvalue())


if __name__ == "__main__":
    unittest.main(verbosity=1)
