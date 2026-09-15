#!/usr/bin/env python3
"""Unit tests for deterministic SpeechLab comparison helpers."""

import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).with_name("run.py")
SPEC = importlib.util.spec_from_file_location("speechlab_run", MODULE_PATH)
run = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(run)


class NormalizationTests(unittest.TestCase):
    def test_contract_hash_canonicalization(self):
        contract = {"items": [{"status": "active", "action": "buy"}]}
        self.assertEqual(
            run.sha256_bytes(run.canonical_json(contract).encode())[:20],
            "71584dcae85a7b891e69",
        )

    def test_bare_clock_accepts_am_and_pm(self):
        self.assertEqual(run.clock_candidates("after at 5:30"), [[5, 30], [17, 30]])

    def test_action_equivalence(self):
        self.assertTrue(run.action_matches("grab", "Buy Eggs"))
        self.assertFalse(run.action_matches("email", "Call Nina"))

    def test_ambiguous_rows_are_not_naively_exact_scored(self):
        row = {
            "ambiguity_state": "requires_review", "safety_class": "ordinary",
            "phenomena": ["unresolved_alternative"],
            "utterance": "Maybe visit the mall",
            "expected_contract": {"items": [{"action": "visit", "kind": "task", "polarity": "positive", "status": "active"}]},
        }
        actual = {"items": [{
            "title": "Maybe visit the mall", "analysis": "Maybe visit the mall", "quote": "Maybe the mall",
            "wasRepaired": False, "route": "Today", "person": None, "temporal": "none",
            "needsReview": True, "state": "contested", "recurrenceRule": None,
        }], "operations": []}
        comparison = run.choose_comparison(row, actual)
        self.assertEqual(comparison["result"], "allowed_interpretation")

    def test_negative_title_without_negation_is_unsafe(self):
        row = {"safety_class": "safety_critical", "phenomena": ["negation"]}
        expected = [{"action": "buy", "object": "milk", "polarity": "negative"}]
        actual = [{"title": "Buy milk"}]
        self.assertTrue(run.unsafe_positive_action(row, expected, actual, [], [(0, 0)], set()))


if __name__ == "__main__":
    unittest.main()
