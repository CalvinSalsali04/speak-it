#!/usr/bin/env python3
"""Audit independent reviewer behavior without reading parser or sealed output."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import statistics
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))

from Sources.contracts import read_jsonl, write_json


def verdict(review):
    return review['proposed_contract_correct'], review['meaning_preservation']


def audit(cases):
    independent = {
        case['case_id']: [
            review for review in case['reviews']
            if review['independence'] == 'independent'
        ]
        for case in cases
    }
    stats = defaultdict(lambda: {
        'reviews': 0, 'safety_reviews': 0, 'naturalness': Counter(),
        'contract': Counter(), 'preservation': Counter(), 'multi_review_cases': 0,
        'verdict_disagreement_cases': 0, 'naturalness_disagreement_cases': 0,
    })
    by_phenomenon = defaultdict(lambda: {
        'cases': 0, 'multi_review_cases': 0, 'verdict_disagreement_cases': 0,
        'naturalness_disagreement_cases': 0,
    })
    cross_tab = Counter()
    multi_reviewed = 0
    safety_multi_reviewed = 0
    safety_verdict_disagreement = 0
    safety_naturalness_disagreement = 0

    for case in cases:
        reviews = independent[case['case_id']]
        verdict_disagreement = len({verdict(review) for review in reviews}) > 1
        naturalness_disagreement = len({review['naturalness'] for review in reviews}) > 1
        if len(reviews) > 1:
            multi_reviewed += 1
            if case['safety_critical']:
                safety_multi_reviewed += 1
                safety_verdict_disagreement += verdict_disagreement
                safety_naturalness_disagreement += naturalness_disagreement
        for review in reviews:
            identity = review['reviewer']['identity']
            row = stats[identity]
            row['reviews'] += 1
            row['safety_reviews'] += case['safety_critical']
            row['naturalness'][review['naturalness']] += 1
            row['contract'][review['proposed_contract_correct']] += 1
            row['preservation'][review['meaning_preservation']] += 1
            cross_tab[(review['naturalness'], review['proposed_contract_correct'])] += 1
            if len(reviews) > 1:
                row['multi_review_cases'] += 1
                row['verdict_disagreement_cases'] += verdict_disagreement
                row['naturalness_disagreement_cases'] += naturalness_disagreement
        for phenomenon in case['taxonomy_labels']:
            row = by_phenomenon[phenomenon]
            row['cases'] += 1
            if len(reviews) > 1:
                row['multi_review_cases'] += 1
                row['verdict_disagreement_cases'] += verdict_disagreement
                row['naturalness_disagreement_cases'] += naturalness_disagreement

    reviewer_rows = []
    for identity, row in sorted(stats.items()):
        scores = [score for score, count in row['naturalness'].items() for _ in range(count)]
        multi = row['multi_review_cases']
        reviewer_rows.append({
            'identity': identity,
            'reviews': row['reviews'],
            'safety_reviews': row['safety_reviews'],
            'naturalness_distribution': {
                str(score): row['naturalness'][score] for score in range(1, 6)
            },
            'mean_naturalness': round(statistics.mean(scores), 6),
            'broken_or_implausible_rate': round(
                sum(row['naturalness'][score] for score in (1, 2)) / row['reviews'], 6
            ),
            'contract_judgments': {
                key: row['contract'][key] for key in ('yes', 'no', 'uncertain')
            },
            'semantic_rejection_rate': round(row['contract']['no'] / row['reviews'], 6),
            'semantic_uncertainty_rate': round(
                row['contract']['uncertain'] / row['reviews'], 6
            ),
            'preservation_judgments': {
                key: row['preservation'][key]
                for key in ('appears_preserved', 'meaning_changed', 'uncertain')
            },
            'multi_review_cases': multi,
            'verdict_disagreement_cases': row['verdict_disagreement_cases'],
            'verdict_disagreement_rate': round(
                row['verdict_disagreement_cases'] / multi, 6
            ) if multi else 0,
            'naturalness_disagreement_cases': row['naturalness_disagreement_cases'],
            'naturalness_disagreement_rate': round(
                row['naturalness_disagreement_cases'] / multi, 6
            ) if multi else 0,
        })

    low_naturalness = sum(
        count for (score, _), count in cross_tab.items() if score <= 2
    )
    low_but_affirmed = sum(
        cross_tab[(score, 'yes')] for score in (1, 2)
    )
    high_naturalness = sum(
        count for (score, _), count in cross_tab.items() if score >= 4
    )
    high_but_rejected = sum(
        cross_tab[(score, 'no')] + cross_tab[(score, 'uncertain')] for score in (4, 5)
    )
    return {
        'methodology': {
            'production_parser_invoked': False,
            'parser_output_read': False,
            'sealed_failures_read': 0,
            'disagreement_unit': 'same case, distinct independent reviewers',
        },
        'reviewers': reviewer_rows,
        'safety_disagreement': {
            'multi_review_cases': safety_multi_reviewed,
            'verdict_disagreement_cases': safety_verdict_disagreement,
            'verdict_disagreement_rate': round(
                safety_verdict_disagreement / safety_multi_reviewed, 6
            ) if safety_multi_reviewed else 0,
            'naturalness_disagreement_cases': safety_naturalness_disagreement,
            'naturalness_disagreement_rate': round(
                safety_naturalness_disagreement / safety_multi_reviewed, 6
            ) if safety_multi_reviewed else 0,
        },
        'all_multi_review_cases': multi_reviewed,
        'phenomena': [
            {
                'phenomenon_id': phenomenon,
                **row,
                'verdict_disagreement_rate': round(
                    row['verdict_disagreement_cases'] / row['multi_review_cases'], 6
                ) if row['multi_review_cases'] else 0,
                'naturalness_disagreement_rate': round(
                    row['naturalness_disagreement_cases'] / row['multi_review_cases'], 6
                ) if row['multi_review_cases'] else 0,
            }
            for phenomenon, row in sorted(by_phenomenon.items())
        ],
        'naturalness_semantics_separation': {
            'low_naturalness_reviews': low_naturalness,
            'low_naturalness_with_contract_affirmed': low_but_affirmed,
            'low_naturalness_affirmation_rate': round(
                low_but_affirmed / low_naturalness, 6
            ) if low_naturalness else 0,
            'high_naturalness_reviews': high_naturalness,
            'high_naturalness_with_rejection_or_uncertainty': high_but_rejected,
            'high_naturalness_adverse_rate': round(
                high_but_rejected / high_naturalness, 6
            ) if high_naturalness else 0,
            'interpretation': (
                'Naturalness and semantic correctness were scored separately: '
                'low-naturalness cases were often semantically affirmed and some '
                'high-naturalness cases still received adverse semantic judgments.'
            ),
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--cases', type=Path,
        default=LAB / 'phase2' / 'adjudication' / 'cases-adjudicated.jsonl',
    )
    parser.add_argument(
        '--output', type=Path,
        default=LAB / 'phase2' / 'adjudication' / 'reviewer-audit.json',
    )
    args = parser.parse_args()
    report = audit(list(read_jsonl(args.cases)))
    write_json(args.output, report)
    print(json.dumps({
        'reviewers': len(report['reviewers']),
        'safety_disagreement': report['safety_disagreement'],
        'production_parser_invoked': False,
    }, indent=2))


if __name__ == '__main__':
    main()
