#!/usr/bin/env python3
"""Create deterministic blind review assignments for independent adjudication."""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))

from Sources.contracts import digest, read_jsonl, write_json, write_jsonl


FORBIDDEN_KEYS = {
    'actual', 'actual_behavior', 'parser_output', 'passed', 'failure_signature',
    'desired_parser_change',
}


def contains_forbidden_key(value):
    if isinstance(value, dict):
        return bool(set(value) & FORBIDDEN_KEYS) or any(
            contains_forbidden_key(child) for child in value.values()
        )
    if isinstance(value, list):
        return any(contains_forbidden_key(child) for child in value)
    return False


def prepare(cases, review_pack, reviewer_ids):
    if len(reviewer_ids) < 3 or len(reviewer_ids) != len(set(reviewer_ids)):
        raise ValueError('at least three distinct reviewer identities are required')
    case_by_id = {case['case_id']: case for case in cases}
    if len(case_by_id) != len(cases):
        raise ValueError('duplicate case ID')
    pack_by_id = {row['case_id']: row for row in review_pack}
    if set(pack_by_id) != set(case_by_id):
        raise ValueError('review pack and corpus case sets differ')
    if any(contains_forbidden_key(row) for row in review_pack):
        raise ValueError('review pack exposes parser or implementation information')
    prior_identities = {
        review['reviewer']['identity']
        for case in cases for review in case['reviews']
    }
    if prior_identities & set(reviewer_ids):
        raise ValueError('assigned reviewer previously reviewed or authored a case')

    assignments = {reviewer_id: [] for reviewer_id in reviewer_ids}
    assigned_by_case = {}
    for index, case in enumerate(cases):
        if case['safety_critical']:
            selected = (reviewer_ids[index % len(reviewer_ids)], reviewer_ids[(index + 1) % len(reviewer_ids)])
        else:
            selected = (reviewer_ids[index % len(reviewer_ids)],)
        assigned_by_case[case['case_id']] = list(selected)
        for reviewer_id in selected:
            assignments[reviewer_id].append(pack_by_id[case['case_id']])

    for case in cases:
        expected = 2 if case['safety_critical'] else 1
        selected = assigned_by_case[case['case_id']]
        if len(selected) != expected or len(selected) != len(set(selected)):
            raise ValueError('invalid independent-review assignment')
    return assignments, assigned_by_case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cases', type=Path, default=LAB / 'phase2' / 'data' / 'cases.jsonl')
    parser.add_argument('--review-pack', type=Path, default=LAB / 'phase2' / 'review' / 'independent-review-pack.jsonl')
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--reviewer', action='append', required=True, dest='reviewers')
    parser.add_argument('--reviewer-kind', choices=('human', 'external_ai'), default='external_ai')
    args = parser.parse_args()
    cases = list(read_jsonl(args.cases))
    review_pack = list(read_jsonl(args.review_pack))
    assignments, assigned_by_case = prepare(cases, review_pack, args.reviewers)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for reviewer_id, rows in assignments.items():
        write_jsonl(args.output_dir / f'{reviewer_id}.jsonl', rows)
    counts = Counter(len(reviewers) for reviewers in assigned_by_case.values())
    write_json(args.output_dir / 'manifest.json', {
        'review_round': 'speechlab-independent-review-1',
        'reviewers': args.reviewers,
        'reviewer_sources': [
            {'identity': reviewer, 'kind': args.reviewer_kind}
            for reviewer in args.reviewers
        ],
        'case_count': len(cases),
        'assignments_per_case': {str(key): value for key, value in sorted(counts.items())},
        'reviews_required': sum(len(reviewers) for reviewers in assigned_by_case.values()),
        'reviewer_counts': {reviewer: len(rows) for reviewer, rows in assignments.items()},
        'assignment_digest': digest(assigned_by_case),
        'parser_output_included': False,
        'production_behavior_included': False,
    })
    print(json.dumps({
        'cases': len(cases), 'reviews_required': sum(map(len, assigned_by_case.values())),
        'reviewer_counts': {reviewer: len(rows) for reviewer, rows in assignments.items()},
    }, indent=2))


if __name__ == '__main__':
    main()
