#!/usr/bin/env python3
"""Compile fresh blind repair reviews and merge them into a candidate corpus."""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))
sys.path.insert(0, str(LAB / 'phase2'))

from Sources.contracts import digest, read_jsonl, write_json, write_jsonl
from adjudication_report import build_report
from apply_reviews import apply_reviews
from compile_review_decisions import compile_decisions
from prepare_review_batches import contains_forbidden_key
from quality import validate_all


def parse_decisions(values):
    result = {}
    for value in values:
        reviewer, separator, path = value.partition('=')
        if not separator or not reviewer or not path or reviewer in result:
            raise ValueError('--decision must be unique REVIEWER_ID=PATH values')
        result[reviewer] = Path(path)
    return result


def run(candidate_dir, decision_paths, reviewed_at, output_dir):
    batch_dir = candidate_dir / 'review-batches'
    batch_manifest = json.loads((batch_dir / 'manifest.json').read_text())
    reviewers = batch_manifest['reviewers']
    if set(decision_paths) != set(reviewers):
        raise ValueError('decision reviewers differ from assignment manifest')
    if any(not re.fullmatch(r'[A-Za-z0-9._-]+', reviewer) for reviewer in reviewers):
        raise ValueError('unsafe reviewer identity')

    phase2 = LAB / 'phase2'
    repair_cases = list(read_jsonl(candidate_dir / 'repair-cases.jsonl'))
    full_cases = list(read_jsonl(candidate_dir / 'cases.jsonl'))
    repair_ids = {case['case_id'] for case in repair_cases}
    if len(repair_ids) != len(repair_cases):
        raise ValueError('duplicate repair case ID')
    source_by_reviewer = {
        source['identity']: source['kind']
        for source in batch_manifest['reviewer_sources']
    }
    review_schema = json.loads((LAB / 'schema' / 'review.schema.json').read_text())
    submissions_by_reviewer = {}
    all_submissions = []
    assigned_counts = Counter()
    assigned_pairs = set()
    for reviewer in reviewers:
        batch = list(read_jsonl(batch_dir / f'{reviewer}.jsonl'))
        if any(contains_forbidden_key(row) for row in batch):
            raise ValueError('repair review batch exposes parser or implementation information')
        for row in batch:
            case_id = row['case_id']
            if case_id not in repair_ids:
                raise ValueError('review batch contains a non-repair case')
            if (case_id, reviewer) in assigned_pairs:
                raise ValueError('reviewer assigned the same repair case twice')
            assigned_pairs.add((case_id, reviewer))
            assigned_counts[case_id] += 1
        submissions = compile_decisions(
            batch, list(read_jsonl(decision_paths[reviewer])), reviewer,
            source_by_reviewer[reviewer], reviewed_at, review_schema,
        )
        submissions_by_reviewer[reviewer] = submissions
        all_submissions.extend(submissions)
    if len(all_submissions) != batch_manifest['reviews_required']:
        raise ValueError('compiled review count mismatch')
    for case in repair_cases:
        if assigned_counts[case['case_id']] != case['required_independent_reviews']:
            raise ValueError('repair case has the wrong number of blind assignments')

    reviewed_repairs = apply_reviews(repair_cases, all_submissions, review_schema)
    reviewed_by_id = {case['case_id']: case for case in reviewed_repairs}
    reviewed_cases = [
        reviewed_by_id[case['case_id']] if case['case_id'] in repair_ids else case
        for case in full_cases
    ]
    families = list(read_jsonl(phase2 / 'data' / 'semantic-families.jsonl'))
    blueprints = list(read_jsonl(phase2 / 'data' / 'blueprints.jsonl'))
    renderings = list(read_jsonl(candidate_dir / 'renderings.jsonl'))
    taxonomy = json.loads((LAB / 'config' / 'taxonomy-v2.json').read_text())
    review_pack = list(read_jsonl(candidate_dir / 'review-pack.jsonl'))
    validate_all(families, blueprints, renderings, reviewed_cases, taxonomy, review_pack)
    original = list(read_jsonl(phase2 / 'data' / 'cases.jsonl'))
    report = build_report(original, reviewed_cases, families, blueprints, taxonomy)

    output_dir.mkdir(parents=True, exist_ok=True)
    for reviewer, submissions in submissions_by_reviewer.items():
        write_jsonl(output_dir / 'reviews' / f'{reviewer}.jsonl', submissions)
    write_jsonl(output_dir / 'reviews.jsonl', all_submissions)
    write_jsonl(output_dir / 'cases.jsonl', reviewed_cases)
    write_json(output_dir / 'report.json', report)
    outcomes = Counter(
        'trusted' if case['trusted'] else case['label_state']
        for case in reviewed_repairs
    )
    manifest = {
        **batch_manifest,
        'review_round': 'speechlab-repair-review-1',
        'reviewed_at': reviewed_at,
        'completed': True,
        'submission_count': len(all_submissions),
        'submission_digest': digest(all_submissions),
        'reviewed_candidate_digest': digest(reviewed_cases),
        'repair_outcomes': dict(outcomes),
        'production_parser_invoked': False,
        'parser_output_exposed_to_reviewers': False,
        'sealed_failures_read': 0,
    }
    write_json(output_dir / 'manifest.json', manifest)
    return report, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate-dir', type=Path, required=True)
    parser.add_argument('--decision', action='append', required=True, dest='decisions')
    parser.add_argument('--reviewed-at', required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    report, manifest = run(
        args.candidate_dir, parse_decisions(args.decisions),
        args.reviewed_at, args.output_dir,
    )
    print(json.dumps({
        'repair_outcomes': manifest['repair_outcomes'],
        'success_gate': report['success_gate'],
        'production_parser_invoked': False,
    }, indent=2))


if __name__ == '__main__':
    main()
