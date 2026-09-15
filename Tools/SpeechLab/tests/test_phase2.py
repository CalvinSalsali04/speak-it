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
from Sources.contracts import digest, read_jsonl, validate_schema
from adjudication_report import adjudication_metrics
from apply_reviews import apply_reviews
from build_corpus import build
from compile_review_decisions import compile_decisions
from prepare_review_batches import contains_forbidden_key, prepare
from quality import language_lint_results, validate_all
from reviewer_audit import audit as reviewer_audit
from repair_corpus import build_candidate as build_repair_candidate
from triage_problem_cases import (
    ROOT_CAUSES, build as build_triage, challenge_records, summarize as summarize_triage,
)


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
        author = self._review(ordinary, 'codex-phase2-author-self-review')
        with self.assertRaises(ValueError):
            apply_reviews([deepcopy(ordinary)], [author], schema)

    def test_blind_assignment_requires_distinct_reviewers_and_two_for_safety(self):
        sample = [deepcopy(next(case for case in self.cases if not case['safety_critical'])),
                  deepcopy(next(case for case in self.cases if case['safety_critical']))]
        pack = [next(row for row in self.review_pack if row['case_id'] == case['case_id'])
                for case in sample]
        assignments, assigned_by_case = prepare(sample, pack, ['a', 'b', 'c'])
        self.assertEqual(sum(map(len, assignments.values())), 3)
        self.assertEqual(len(assigned_by_case[sample[0]['case_id']]), 1)
        self.assertEqual(len(set(assigned_by_case[sample[1]['case_id']])), 2)
        with self.assertRaises(ValueError):
            prepare(sample, pack, ['same', 'same', 'other'])
        self.assertTrue(contains_forbidden_key({'nested': [{'parser_output': 'hidden'}]}))

    def test_decision_compiler_rejects_incomplete_or_duplicate_output(self):
        batch = self.review_pack[:2]
        schema = json.loads((LAB / 'schema' / 'review.schema.json').read_text())
        decisions = []
        for row in batch:
            decisions.append({
                'case_id': row['case_id'], 'naturalness': 4,
                'intended_meaning': 'reviewed meaning', 'intended_item_count': 1,
                'routing': [], 'temporal_meaning': None, 'location_meaning': None,
                'cancellation_negation_scope': None, 'ambiguity': 'none',
                'proposed_contract_correct': 'yes',
                'meaning_preservation': 'appears_preserved', 'notes': 'independent review',
            })
        compiled = compile_decisions(batch, decisions, 'reviewer-a', 'external_ai',
                                     '2026-09-14T12:00:00Z', schema)
        self.assertEqual(len(compiled), 2)
        self.assertTrue(all(row['review']['independence'] == 'independent' for row in compiled))
        with self.assertRaises(ValueError):
            compile_decisions(batch, decisions[:1], 'reviewer-a', 'external_ai',
                              '2026-09-14T12:00:00Z', schema)

    def test_adjudication_preserves_disagreement_and_uses_conservative_scores(self):
        schema = json.loads((LAB / 'schema' / 'review.schema.json').read_text())
        original = deepcopy(next(case for case in self.cases if case['safety_critical']))
        positive = self._review(original, 'reviewer-a')
        adverse = self._review(original, 'reviewer-b')
        adverse['review']['naturalness'] = 2
        adverse['review']['proposed_contract_correct'] = 'no'
        adverse['review']['meaning_preservation'] = 'meaning_changed'
        adverse['review']['review_id'] = 'review-' + digest(adverse['review'])[:24]
        result = apply_reviews([deepcopy(original)], [positive, adverse], schema)[0]
        self.assertFalse(result['trusted'])
        self.assertEqual(result['label_state'], 'disputed')
        self.assertEqual(result['naturalness'], 2)
        self.assertEqual(result['meaning_preservation'], 'meaning_changed')
        metrics = adjudication_metrics([original], [result])
        self.assertEqual(metrics['disputed_cases'], 1)
        self.assertEqual(metrics['safety_cases_by_completed_reviews'], {'0': 0, '1': 0, '2': 1})
        self.assertEqual(metrics['audited_broken_language']['rate'], 1.0)

    def test_committed_adjudication_is_complete_auditable_and_unfrozen(self):
        adjudication = self.phase2 / 'adjudication'
        reviewed = list(read_jsonl(adjudication / 'cases-adjudicated.jsonl'))
        submissions = list(read_jsonl(adjudication / 'reviews.jsonl'))
        report = json.loads((adjudication / 'report.json').read_text())
        self.assertEqual(len(reviewed), 818)
        self.assertEqual(len(submissions), 1332)
        self.assertEqual(
            {row['review']['reviewer']['kind'] for row in submissions}, {'external_ai'}
        )
        self.assertEqual(len({row['review']['reviewer']['identity'] for row in submissions}), 3)
        self.assertTrue(all(row['review']['independence'] == 'independent' for row in submissions))
        self.assertTrue(all(not contains_forbidden_key(row) for row in submissions))
        self.assertEqual(
            {sum(review['independence'] == 'independent' for review in case['reviews'])
             for case in reviewed if case['safety_critical']},
            {2},
        )
        self.assertEqual(report['adjudication']['trusted_cases'], 768)
        self.assertEqual(report['adjudication']['disputed_cases'], 50)
        self.assertEqual(report['success_gate']['passed'], 10)
        self.assertEqual(report['success_gate']['total'], 14)
        self.assertFalse(report['success_gate']['ready_to_freeze'])
        self.assertFalse(report['success_gate']['ready_to_scale_to_10000'])

    def test_reviewer_audit_keeps_naturalness_and_semantics_separate(self):
        reviewed = list(read_jsonl(
            self.phase2 / 'adjudication' / 'cases-adjudicated.jsonl'
        ))
        report = reviewer_audit(reviewed)
        self.assertEqual(len(report['reviewers']), 3)
        self.assertEqual(report['safety_disagreement']['multi_review_cases'], 514)
        separation = report['naturalness_semantics_separation']
        self.assertGreater(separation['low_naturalness_with_contract_affirmed'], 0)
        self.assertGreater(separation['high_naturalness_with_rejection_or_uncertainty'], 0)
        self.assertFalse(report['methodology']['production_parser_invoked'])

    def test_problem_triage_is_complete_and_concrete(self):
        reviewed = list(read_jsonl(
            self.phase2 / 'adjudication' / 'cases-adjudicated.jsonl'
        ))
        rows = build_triage(reviewed)
        report = summarize_triage(reviewed, rows)
        self.assertEqual(len(rows), 134)
        self.assertEqual(len({row['case_id'] for row in rows}), 134)
        # Primary split role understates this because some public-derived and
        # synthetic-stress cases are also safety-critical.
        self.assertEqual(sum(row['safety_critical'] for row in rows), 100)
        self.assertTrue(all(row['root_causes'] for row in rows))
        self.assertEqual(set(report['supported_root_causes']), set(ROOT_CAUSES))
        self.assertEqual(report['disposition_distribution']['A'], 1)
        self.assertEqual(report['disposition_distribution']['G'], 2)
        challenges = challenge_records(reviewed, rows)
        self.assertEqual(len(challenges), 13)
        self.assertTrue(all(
            not row['evaluation_policy']['exact_answer_scoreable'] for row in challenges
        ))
        schema = json.loads((LAB / 'schema' / 'challenge-case.schema.json').read_text())
        for challenge in challenges:
            validate_schema(challenge, schema)

    def test_first_repair_candidate_preserves_lineage_and_requires_fresh_review(self):
        adjudicated = list(read_jsonl(
            self.phase2 / 'adjudication' / 'cases-adjudicated.jsonl'
        ))
        taxonomy = json.loads((LAB / 'config' / 'taxonomy-v2.json').read_text())
        renderings, cases, review_pack, repair_map = build_repair_candidate(
            self.families, self.blueprints, self.renderings, adjudicated, taxonomy,
        )
        self.assertEqual(len(cases), 818)
        self.assertEqual(len(renderings), 818)
        self.assertEqual(len(repair_map), 27)
        # Sixteen repaired cases were already disputed; eleven previously
        # trusted cases are conservatively reset after the repeated flaw was found.
        self.assertEqual(sum(not case['trusted'] for case in cases), 61)
        repaired_ids = {row['repaired_case_id'] for row in repair_map}
        repaired = [case for case in cases if case['case_id'] in repaired_ids]
        self.assertTrue(all(not case['reviews'] for case in repaired))
        self.assertTrue(all(case['meaning_preservation'] == 'uncertain' for case in repaired))
        self.assertTrue(all(case['lineage']['repairs'] for case in repaired))
        self.assertEqual(
            {row['case_id'] for row in review_pack}, {case['case_id'] for case in cases}
        )

    def test_committed_repair_reviews_and_trust_closure_are_honest(self):
        repair = self.phase2 / 'repair'
        first = json.loads((repair / 'candidate-1' / 'adjudication' / 'manifest.json').read_text())
        second = json.loads((repair / 'candidate-2' / 'adjudication' / 'manifest.json').read_text())
        self.assertEqual(first['submission_count'], 37)
        self.assertEqual(first['repair_outcomes'], {'trusted': 21, 'disputed': 6})
        self.assertEqual(second['submission_count'], 37)
        self.assertEqual(second['repair_outcomes'], {'trusted': 16, 'disputed': 4})
        self.assertEqual(len(set(first['reviewers']) | set(second['reviewers'])), 6)
        closure = json.loads((repair / 'trust-closure' / 'report.json').read_text())
        manifest = json.loads((repair / 'trust-closure' / 'manifest.json').read_text())
        cases = list(read_jsonl(repair / 'trust-closure' / 'cases.jsonl'))
        self.assertEqual(len(cases), 695)
        self.assertTrue(all(case['trusted'] for case in cases))
        self.assertEqual(closure['adjudication']['disputed_cases'], 0)
        self.assertEqual(closure['adjudication']['audited_broken_language']['rate'], 0)
        self.assertEqual(closure['adjudication']['audited_meaning_preservation']['rate'], 1)
        self.assertEqual(closure['success_gate']['passed'], 12)
        self.assertFalse(manifest['frozen'])
        self.assertFalse(manifest['parser_results_included'])

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
