import json
from pathlib import Path
import unittest

LAB = Path(__file__).resolve().parents[1]


class DataQualityAuditArtifactTests(unittest.TestCase):
    def test_ai_import_accounting(self):
        report = json.loads((LAB / 'audit/ai-import-report.json').read_text())
        self.assertEqual(report['submitted'], report['accepted'] + report['rejected'])
        self.assertEqual(report['rejection_reasons'], {'exact_duplicate_existing': 2})
        self.assertEqual(report['blueprint_identity_violations'], 0)

    def test_review_set_is_bounded_complete_and_nonsealed(self):
        rows = [json.loads(line) for line in (LAB / 'audit/human-review-set.jsonl').read_text().splitlines()]
        phenomenon_ids = {p['id'] for p in json.loads((LAB / 'config/phenomena.json').read_text())['phenomena']}
        self.assertGreaterEqual(len(rows), 300); self.assertLessEqual(len(rows), 500)
        self.assertEqual({p for row in rows for p in row['phenomena']}, phenomenon_ids)
        self.assertTrue(any(row['blueprint']['safety_critical'] for row in rows))
        self.assertTrue(any(len(row['phenomena']) >= 2 for row in rows))
        self.assertTrue(any('hash_random_fill' in row['selected_because'] for row in rows))
        for row in rows:
            self.assertEqual(set(row), {'id', 'phenomena', 'family', 'blueprint', 'spoken_rendering',
                                        'expected_behavior', 'actual_behavior', 'failure_signature', 'selected_because'})
            self.assertNotIn('sealed', row['id'].casefold())

    def test_audit_does_not_present_parser_output_as_label(self):
        metrics = json.loads((LAB / 'audit/data-quality-metrics.json').read_text())
        self.assertEqual(metrics['methodology']['sealed_cases_read'], 0)
        self.assertFalse(metrics['methodology']['parser_output_used_as_label'])
        self.assertEqual(metrics['current']['multi_phenomenon_renderings'], 0)


if __name__ == '__main__': unittest.main()
