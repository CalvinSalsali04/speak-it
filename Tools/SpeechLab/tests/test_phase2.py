import json
from copy import deepcopy
from pathlib import Path
import sys
import tempfile
import unittest

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))
sys.path.insert(0, str(LAB / 'phase2'))

from Sources.composition import validate_composition
from Sources.contracts import digest, read_jsonl
from apply_reviews import apply_reviews
from build_corpus import build
from quality import language_lint_results, validate_all


class Phase2CorpusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.phase2 = LAB / 'phase2'
        cls.families = list(read_jsonl(cls.phase2 / 'data' / 'semantic-families.jsonl'))
        cls.blueprints = list(read_jsonl(cls.phase2 / 'data' / 'blueprints.jsonl'))
        cls.renderings = list(read_jsonl(cls.phase2 / 'data' / 'renderings.jsonl'))
        cls.cases = list(read_jsonl(cls.phase2 / 'data' / 'cases.jsonl'))
        cls.taxonomy = json.loads((LAB / 'config' / 'taxonomy-v2.json').read_text())
        cls.review_pack = list(read_jsonl(cls.phase2 / 'review' / 'independent-review-pack.jsonl'))

    def test_taxonomy_is_hierarchical_and_backward_compatible(self):
        self.assertEqual(len(self.taxonomy['categories']), 6)
        self.assertEqual(len(self.taxonomy['legacy_id_map']), 64)
        self.assertTrue(all(key == value for key, value in self.taxonomy['legacy_id_map'].items()))
        ids = {row['id'] for row in self.taxonomy['phenomena']}
        self.assertEqual(len(ids), 83)
        for required in ('correction-chain', 'scoped-withdrawal', 'resolved-alternative',
                         'cross-turn-reference-ambiguity', 'contact-person-ambiguity',
                         'timezone-sensitive', 'dst-transition', 'asr-name-corruption'):
            self.assertIn(required, ids)

    def test_family_collapse_and_corpus_mix(self):
        historical = [family for family in self.families if family['historical_blueprint_ids']]
        public_new = [family for family in self.families if not family['historical_blueprint_ids']]
        self.assertEqual(len(historical), 133)
        self.assertEqual(sum(family['member_count'] for family in historical), 260)
        self.assertEqual(len(public_new), 4)
        self.assertEqual(len(self.cases), 818)
        cardinality = {n: sum(len(case['taxonomy_labels']) == n for case in self.cases) for n in range(5)}
        self.assertEqual(cardinality, {0: 308, 1: 190, 2: 250, 3: 56, 4: 14})

    def test_phase2_artifacts_validate_without_parser_output(self):
        validate_all(self.families, self.blueprints, self.renderings, self.cases, self.taxonomy, self.review_pack)
        forbidden = {'actual', 'actual_behavior', 'parser_output', 'passed', 'failure_signature', 'desired_parser_change'}
        self.assertTrue(all(not (set(row) & forbidden) for row in self.review_pack))
        self.assertTrue(all(case['trusted'] is False for case in self.cases))
        self.assertTrue(all(case['required_independent_reviews'] == 2 for case in self.cases if case['safety_critical']))

    def test_public_pilot_is_bounded_text_only_and_provenanced(self):
        rows = list(read_jsonl(self.phase2 / 'public' / 'source-records.jsonl'))
        self.assertEqual(len(rows), 42)
        self.assertEqual({row['source_dataset'] for row in rows}, {'PRESTO', 'MASSIVE', 'Taskmaster', 'SLURP-text'})
        self.assertTrue(all(row['audio_used'] is False for row in rows))
        self.assertTrue(all(row['foreign_annotation_is_speakit_truth'] is False for row in rows))
        self.assertTrue(all(row['archive_sha256'] and row['record_id'] and row['license'] for row in rows))

    def test_composition_rejects_unsafe_or_misordered_recipes(self):
        safety = next(bp for bp in self.blueprints if bp['safety_critical'] and bp['expected']['items'])
        self.assertFalse(validate_composition(safety, ('asr-dropped-token',))[0])
        ordinary = next(bp for bp in self.blueprints if not bp['safety_critical'] and bp['expected']['item_count'] == 1)
        self.assertFalse(validate_composition(ordinary, ('numbered-list',))[0])
        self.assertFalse(validate_composition(ordinary, ('lowercase', 'filler-words'))[0])

    def _review(self, case, identity, kind='external_ai'):
        expected = case['proposed_contract']
        review = {
            'reviewer': {'kind': kind, 'identity': identity}, 'reviewed_at': '2026-09-13T12:00:00Z',
            'independence': 'independent', 'naturalness': 4,
            'intended_meaning': 'independent test review', 'intended_item_count': expected['item_count'],
            'routing': [item['route'] for item in expected['items']], 'temporal_meaning': None,
            'location_meaning': None, 'cancellation_negation_scope': None, 'ambiguity': 'none',
            'proposed_contract_correct': 'yes', 'meaning_preservation': 'appears_preserved', 'notes': 'test',
        }
        review['review_id'] = 'review-' + digest(review)[:24]
        return {'case_id': case['case_id'], 'review': review}

    def test_review_promotion_requires_independence_and_two_for_safety(self):
        schema = json.loads((LAB / 'schema' / 'review.schema.json').read_text())
        ordinary = deepcopy(next(case for case in self.cases if not case['safety_critical']))
        promoted = apply_reviews([ordinary], [self._review(ordinary, 'reviewer-a')], schema)[0]
        self.assertTrue(promoted['trusted'])
        self.assertEqual(promoted['label_state'], 'independently-reviewed')
        safety = deepcopy(next(case for case in self.cases if case['safety_critical']))
        once = apply_reviews([safety], [self._review(safety, 'reviewer-a')], schema)[0]
        self.assertFalse(once['trusted'])
        twice = apply_reviews([once], [self._review(once, 'reviewer-b', 'human')], schema)[0]
        self.assertTrue(twice['trusted'])
        self.assertEqual(twice['label_state'], 'human-reviewed')

    def test_quality_gate_is_honest(self):
        report = json.loads((self.phase2 / 'artifacts' / 'quality-report.json').read_text())
        metrics = report['metrics']
        self.assertGreaterEqual(metrics['machine_assessed_preservation_rate'], .95)
        self.assertLess(metrics['machine_assessed_broken_rate'], .05)
        self.assertLess(metrics['lexical_near_duplicate_record_rate'], .204)
        self.assertEqual(language_lint_results(self.cases), [])
        self.assertTrue(report['success_gate']['checks']['automated_language_lints_zero'])
        self.assertFalse(report['success_gate']['ready_to_freeze'])
        self.assertFalse(report['success_gate']['ready_to_scale_to_10000'])
        self.assertFalse(report['success_gate']['checks']['safety_has_two_independent_reviews'])
        self.assertFalse(report['success_gate']['checks']['independent_semantic_review_exists'])

    def test_build_is_byte_deterministic(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'phase2'
            build(output, self.phase2 / 'public' / 'source-records.jsonl')
            for relative in ('data/semantic-families.jsonl', 'data/blueprints.jsonl',
                             'data/renderings.jsonl', 'data/cases.jsonl',
                             'review/independent-review-pack.jsonl', 'artifacts/build-manifest.json'):
                self.assertEqual((output / relative).read_bytes(), (self.phase2 / relative).read_bytes())


if __name__ == '__main__':
    unittest.main()
