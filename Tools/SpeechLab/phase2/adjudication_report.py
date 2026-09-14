#!/usr/bin/env python3
"""Measure independent adjudication without invoking the production parser."""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import statistics
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))
sys.path.insert(0, str(LAB / 'phase2'))

from Sources.contracts import read_jsonl, write_json
from quality import corpus_metrics, gates as phase2_gates, saturation


def independent_reviews(case):
    return [review for review in case['reviews'] if review['independence'] == 'independent']


def positive(review):
    return (review['proposed_contract_correct'] == 'yes'
            and review['meaning_preservation'] == 'appears_preserved')


def adjudication_metrics(original, adjudicated):
    before = {case['case_id']: case for case in original}
    after = {case['case_id']: case for case in adjudicated}
    if len(before) != len(original) or len(after) != len(adjudicated):
        raise ValueError('duplicate case ID')

    completed = []
    reviewed = []
    naturalness = Counter()
    naturalness_assessments = Counter()
    safety_reviews = Counter()
    safety_positive = Counter()
    reviewer_sources = Counter()
    label_changes = []
    label_state_transitions = Counter()
    naturalness_transitions = Counter()
    preservation_transitions = Counter()
    naturalness_changed = 0
    preservation_changed = 0
    contract_judgments = Counter()
    verdict_disagreements = 0
    rating_disagreements = 0
    for case in adjudicated:
        reviews = independent_reviews(case)
        if reviews:
            reviewed.append(case)
        for review in reviews:
            naturalness_assessments[review['naturalness']] += 1
            reviewer_sources[(review['reviewer']['kind'], review['reviewer']['identity'])] += 1
        if reviews:
            if any(review['proposed_contract_correct'] == 'no' for review in reviews):
                contract_judgments['no'] += 1
            elif any(review['proposed_contract_correct'] == 'uncertain' for review in reviews):
                contract_judgments['uncertain'] += 1
            else:
                contract_judgments['yes'] += 1
            verdict_disagreements += len({
                (review['proposed_contract_correct'], review['meaning_preservation'])
                for review in reviews
            }) > 1
            rating_disagreements += len({review['naturalness'] for review in reviews}) > 1
        required = case['required_independent_reviews']
        if len(reviews) >= required:
            completed.append(case)
            naturalness[statistics.median_low(r['naturalness'] for r in reviews)] += 1
        if case['safety_critical']:
            safety_reviews[min(len(reviews), 2)] += 1
            safety_positive[min(sum(positive(review) for review in reviews), 2)] += 1
        old = before.get(case['case_id'])
        if old and any(old[key] != case[key] for key in ('label_state', 'naturalness', 'meaning_preservation', 'trusted')):
            label_state_transitions[(old['label_state'], case['label_state'])] += 1
            naturalness_changed += old['naturalness'] != case['naturalness']
            preservation_changed += old['meaning_preservation'] != case['meaning_preservation']
            naturalness_transitions[(old['naturalness'], case['naturalness'])] += 1
            preservation_transitions[(old['meaning_preservation'], case['meaning_preservation'])] += 1
            label_changes.append({
                'case_id': case['case_id'],
                'label_state': {'before': old['label_state'], 'after': case['label_state']},
                'naturalness': {'before': old['naturalness'], 'after': case['naturalness']},
                'meaning_preservation': {'before': old['meaning_preservation'], 'after': case['meaning_preservation']},
                'trusted': {'before': old['trusted'], 'after': case['trusted']},
            })

    preserved = sum(
        len(independent_reviews(case)) >= case['required_independent_reviews']
        and all(review['meaning_preservation'] == 'appears_preserved'
                for review in independent_reviews(case))
        for case in completed
    )
    contract_correct = sum(
        all(review['proposed_contract_correct'] == 'yes'
            for review in independent_reviews(case))
        for case in completed
    )
    broken = sum(case['naturalness'] <= 2 for case in completed)
    review_records = sum(len(independent_reviews(case)) for case in adjudicated)
    expected_reviews = sum(case['required_independent_reviews'] for case in adjudicated)
    return {
        'corpus_size_before': len(original),
        'final_corpus_size': len(adjudicated),
        'cases_removed': sorted(set(before) - set(after)),
        'independent_review_records': review_records,
        'required_independent_review_records': expected_reviews,
        'independently_reviewed_cases': len(reviewed),
        'review_requirements_completed_cases': len(completed),
        'trusted_cases': sum(case['trusted'] for case in adjudicated),
        'trusted_safety_cases': sum(case['trusted'] and case['safety_critical'] for case in adjudicated),
        'trusted_ordinary_cases': sum(case['trusted'] and not case['safety_critical'] for case in adjudicated),
        'disputed_cases': sum(case['label_state'] == 'disputed' for case in adjudicated),
        'rejected_cases': sum(case['label_state'] == 'rejected' for case in adjudicated),
        'safety_cases_by_completed_reviews': {str(score): safety_reviews[score] for score in range(3)},
        'safety_cases_by_positive_reviews': {str(score): safety_positive[score] for score in range(3)},
        'naturalness_distribution_by_case': {str(score): naturalness[score] for score in range(1, 6)},
        'naturalness_distribution_all_assessments': {str(score): naturalness_assessments[score] for score in range(1, 6)},
        'audited_meaning_preservation': {
            'preserved': preserved, 'audited': len(completed),
            'rate': round(preserved / len(completed), 6) if completed else 0,
        },
        'audited_contract_correctness': {
            'correct': contract_correct, 'audited': len(completed),
            'rate': round(contract_correct / len(completed), 6) if completed else 0,
            'case_judgments': {key: contract_judgments[key] for key in ('yes', 'no', 'uncertain')},
        },
        'audited_broken_language': {
            'broken_or_implausible': broken, 'audited': len(completed),
            'rate': round(broken / len(completed), 6) if completed else 0,
        },
        'reviewer_sources': [
            {'kind': kind, 'identity': identity, 'reviews': count}
            for (kind, identity), count in sorted(reviewer_sources.items())
        ],
        'labels_changed_count': len(label_changes),
        'semantic_assessment_changed_cases': sum(
            old['naturalness'] != after[case_id]['naturalness']
            or old['meaning_preservation'] != after[case_id]['meaning_preservation']
            for case_id, old in before.items() if case_id in after
        ),
        'naturalness_changed_cases': naturalness_changed,
        'meaning_preservation_changed_cases': preservation_changed,
        'label_state_transitions': [
            {'before': before_state, 'after': after_state, 'cases': count}
            for (before_state, after_state), count in sorted(label_state_transitions.items())
        ],
        'naturalness_transitions': [
            {'before': before_score, 'after': after_score, 'cases': count}
            for (before_score, after_score), count in sorted(naturalness_transitions.items())
        ],
        'meaning_preservation_transitions': [
            {'before': before_value, 'after': after_value, 'cases': count}
            for (before_value, after_value), count in sorted(preservation_transitions.items())
        ],
        'verdict_disagreement_cases': verdict_disagreements,
        'naturalness_rating_disagreement_cases': rating_disagreements,
        'labels_changed': label_changes,
    }


def adjudication_gates(base_metrics, snapshots, audited):
    checks = phase2_gates(base_metrics, snapshots)['checks']
    # Replace the author-self-review gates with audited equivalents while
    # retaining the original 14-gate denominator.
    del checks['machine_naturalness_majority_four_or_five']
    del checks['machine_broken_rate_below_five_percent']
    del checks['machine_preservation_at_least_95_percent']
    del checks['independent_semantic_review_exists']
    del checks['safety_has_two_independent_reviews']
    distribution = audited['naturalness_distribution_by_case']
    completed = audited['review_requirements_completed_cases']
    checks['independent_naturalness_majority_four_or_five'] = (
        completed > 0 and (distribution['4'] + distribution['5']) / completed > .50
    )
    checks['audited_broken_rate_below_five_percent'] = (
        audited['audited_broken_language']['rate'] < .05
    )
    checks['audited_preservation_at_least_95_percent'] = (
        audited['audited_meaning_preservation']['rate'] >= .95
    )
    checks['independent_semantic_review_complete'] = (
        audited['independent_review_records'] == audited['required_independent_review_records']
        and audited['review_requirements_completed_cases'] == audited['final_corpus_size']
    )
    checks['safety_has_two_independent_positive_reviews'] = (
        audited['safety_cases_by_positive_reviews']['2']
        == base_metrics['safety']['cases']
    )
    passed = sum(checks.values())
    ready = passed == len(checks) and audited['disputed_cases'] == 0 and audited['rejected_cases'] == 0
    return {
        'checks': checks, 'passed': passed, 'total': len(checks),
        'ready_to_freeze': ready,
        'ready_to_scale_to_10000': ready,
        'decision': ('freeze permitted; bounded corpus quality gates pass'
                     if ready else 'do not freeze or scale; failed gates or unresolved adjudication remain'),
    }


def build_report(original, adjudicated, families, blueprints, taxonomy):
    audited = adjudication_metrics(original, adjudicated)
    base_metrics = corpus_metrics(families, blueprints, adjudicated, taxonomy)
    snapshots = saturation(adjudicated)
    return {
        'methodology': {
            'review_order': 'utterance semantics before production parser output',
            'reviewer_kind': 'external_ai',
            'author_self_review_counted_as_independent': False,
            'production_parser_invoked': False,
            'parser_output_exposed_to_reviewers': False,
            'sealed_failures_read': 0,
            'disagreements_preserved': True,
            'naturalness_case_aggregation': 'lower median of independent ratings',
            'gold_label_used': False,
        },
        'adjudication': audited,
        'corpus_metrics': base_metrics,
        'saturation': snapshots,
        'success_gate': adjudication_gates(base_metrics, snapshots, audited),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original', type=Path, default=LAB / 'phase2' / 'data' / 'cases.jsonl')
    parser.add_argument('--adjudicated', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    phase2 = LAB / 'phase2'
    report = build_report(
        list(read_jsonl(args.original)), list(read_jsonl(args.adjudicated)),
        list(read_jsonl(phase2 / 'data' / 'semantic-families.jsonl')),
        list(read_jsonl(phase2 / 'data' / 'blueprints.jsonl')),
        json.loads((LAB / 'config' / 'taxonomy-v2.json').read_text()),
    )
    write_json(args.output, report)
    print(json.dumps({
        'adjudication': {key: report['adjudication'][key] for key in (
            'independently_reviewed_cases', 'trusted_cases', 'disputed_cases', 'rejected_cases')},
        'success_gate': report['success_gate'],
        'production_parser_invoked': False,
    }, indent=2))


if __name__ == '__main__':
    main()
