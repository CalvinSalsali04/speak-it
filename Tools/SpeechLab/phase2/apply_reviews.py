#!/usr/bin/env python3
"""Apply genuinely independent semantic reviews to Phase 2 cases.

Input is JSONL with ``case_id`` and ``review``. The review must satisfy
``schema/review.schema.json`` and declare ``independence=independent``. This
tool never invokes or reads the production parser.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import json
from pathlib import Path
import statistics
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))

from Sources.contracts import read_jsonl, validate_schema, write_jsonl


def positive(review):
    return review['independence'] == 'independent' and review['proposed_contract_correct'] == 'yes' and review['meaning_preservation'] == 'appears_preserved'


def apply_reviews(cases, submissions, review_schema):
    # Do not mutate the authored snapshot. Keeping before/after artifacts
    # distinct is required for an auditable adjudication diff.
    by_id = {case['case_id']: deepcopy(case) for case in cases}
    seen_reviews = {review['review_id'] for case in cases for review in case['reviews']}
    author_identities = {
        review['reviewer']['identity']
        for case in cases for review in case['reviews']
        if review['independence'] == 'author_self_review'
    }
    reviewer_case_pairs = {(case['case_id'], review['reviewer']['identity']) for case in cases for review in case['reviews'] if review['independence'] == 'independent'}
    for submission in submissions:
        if set(submission) != {'case_id', 'review'}:
            raise ValueError('review submission requires exactly case_id and review')
        case_id, review = submission['case_id'], submission['review']
        if case_id not in by_id:
            raise ValueError(f'unknown case ID: {case_id}')
        validate_schema(review, review_schema)
        if review['independence'] != 'independent':
            raise ValueError('review submission is not independent')
        if review['reviewer']['kind'] == 'machine':
            raise ValueError('machine review cannot be submitted as independent')
        if review['reviewer']['identity'] in author_identities:
            raise ValueError('author self-review cannot be resubmitted as independent')
        if review['review_id'] in seen_reviews:
            raise ValueError('duplicate review ID')
        pair = (case_id, review['reviewer']['identity'])
        if pair in reviewer_case_pairs:
            raise ValueError('same independent reviewer submitted twice for one case')
        by_id[case_id]['reviews'].append(review)
        seen_reviews.add(review['review_id'])
        reviewer_case_pairs.add(pair)

    for case in by_id.values():
        independent = [review for review in case['reviews'] if review['independence'] == 'independent']
        adverse = [review for review in independent if review['proposed_contract_correct'] == 'no' or review['meaning_preservation'] == 'meaning_changed']
        uncertain = [review for review in independent if review['proposed_contract_correct'] == 'uncertain' or review['meaning_preservation'] == 'uncertain']
        approvals = [review for review in independent if positive(review)]
        if independent:
            # Keep the adjudicated surface fields conservative and deterministic.
            # Individual reviewer judgments remain intact in ``reviews``.
            case['naturalness'] = statistics.median_low(
                review['naturalness'] for review in independent
            )
            preservation = {review['meaning_preservation'] for review in independent}
            if 'meaning_changed' in preservation:
                case['meaning_preservation'] = 'meaning_changed'
            elif 'uncertain' in preservation:
                case['meaning_preservation'] = 'uncertain'
            else:
                case['meaning_preservation'] = 'appears_preserved'
        if adverse or uncertain:
            case['label_state'] = 'disputed'
            case['trusted'] = False
        elif len(approvals) >= case['required_independent_reviews']:
            case['label_state'] = 'human-reviewed' if any(review['reviewer']['kind'] == 'human' for review in approvals) else 'independently-reviewed'
            case['trusted'] = True
        else:
            case['trusted'] = False
    return list(by_id.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cases', type=Path, default=LAB / 'phase2' / 'data' / 'cases.jsonl')
    parser.add_argument('--reviews', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    cases = list(read_jsonl(args.cases))
    submissions = list(read_jsonl(args.reviews))
    review_schema = json.loads((LAB / 'schema' / 'review.schema.json').read_text())
    result = apply_reviews(cases, submissions, review_schema)
    write_jsonl(args.output, result)
    print(json.dumps({
        'cases': len(result), 'reviews_applied': len(submissions),
        'trusted': sum(case['trusted'] for case in result),
        'disputed': sum(case['label_state'] == 'disputed' for case in result),
        'production_parser_invoked': False,
    }, indent=2))


if __name__ == '__main__':
    main()
