#!/usr/bin/env python3
"""Compile one blind reviewer's complete decisions into review submissions."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))

from Sources.contracts import digest, read_jsonl, validate_schema, write_jsonl


DECISION_KEYS = {
    'case_id', 'naturalness', 'intended_meaning', 'intended_item_count', 'routing',
    'temporal_meaning', 'location_meaning', 'cancellation_negation_scope', 'ambiguity',
    'proposed_contract_correct', 'meaning_preservation', 'notes',
}


def compile_decisions(batch, decisions, reviewer_id, reviewer_kind, reviewed_at, review_schema):
    batch_ids = [row['case_id'] for row in batch]
    if len(batch_ids) != len(set(batch_ids)):
        raise ValueError('duplicate case in reviewer batch')
    decision_by_id = {}
    for decision in decisions:
        if set(decision) != DECISION_KEYS:
            raise ValueError('review decision field mismatch')
        case_id = decision['case_id']
        if case_id in decision_by_id:
            raise ValueError(f'duplicate decision for {case_id}')
        decision_by_id[case_id] = decision
    missing = set(batch_ids) - set(decision_by_id)
    extra = set(decision_by_id) - set(batch_ids)
    if missing or extra:
        raise ValueError(f'incomplete reviewer output: missing={len(missing)} extra={len(extra)}')

    submissions = []
    for case_id in batch_ids:
        decision = decision_by_id[case_id]
        review = {
            'reviewer': {'kind': reviewer_kind, 'identity': reviewer_id},
            'reviewed_at': reviewed_at,
            'independence': 'independent',
            **{key: value for key, value in decision.items() if key != 'case_id'},
        }
        review['review_id'] = 'review-' + digest({'case_id': case_id, **review})[:24]
        validate_schema(review, review_schema)
        submissions.append({'case_id': case_id, 'review': review})
    return submissions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--batch', type=Path, required=True)
    parser.add_argument('--decisions', type=Path, required=True)
    parser.add_argument('--reviewer-id', required=True)
    parser.add_argument('--reviewer-kind', choices=('human', 'external_ai'), required=True)
    parser.add_argument('--reviewed-at', default=None)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    reviewed_at = args.reviewed_at or datetime.now(timezone.utc).isoformat()
    schema = json.loads((LAB / 'schema' / 'review.schema.json').read_text())
    submissions = compile_decisions(
        list(read_jsonl(args.batch)), list(read_jsonl(args.decisions)),
        args.reviewer_id, args.reviewer_kind, reviewed_at, schema,
    )
    write_jsonl(args.output, submissions)
    print(json.dumps({
        'reviewer': args.reviewer_id, 'decisions': len(submissions),
        'independence': 'independent', 'production_parser_invoked': False,
    }, indent=2))


if __name__ == '__main__':
    main()
