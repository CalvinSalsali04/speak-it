#!/usr/bin/env python3
"""Compile a complete blind-review round and emit auditable adjudication artifacts."""
from __future__ import annotations

import argparse
from datetime import datetime
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
from prepare_review_batches import prepare
from quality import validate_all


def parse_decisions(values):
    result = {}
    for value in values:
        reviewer, separator, path = value.partition('=')
        if not separator or not reviewer or not path or reviewer in result:
            raise ValueError('--decision must be unique REVIEWER_ID=PATH values')
        result[reviewer] = Path(path)
    return result


def run(batch_dir, decision_paths, reviewed_at, output_dir):
    # Requiring an explicit timezone makes the durable review IDs reproducible.
    timestamp = datetime.fromisoformat(reviewed_at.replace('Z', '+00:00'))
    if timestamp.tzinfo is None:
        raise ValueError('--reviewed-at must include a timezone')
    manifest = json.loads((batch_dir / 'manifest.json').read_text())
    reviewers = manifest['reviewers']
    if set(decision_paths) != set(reviewers):
        raise ValueError('decision reviewers differ from assignment manifest')
    if any(not re.fullmatch(r'[A-Za-z0-9._-]+', reviewer) for reviewer in reviewers):
        raise ValueError('reviewer identity is unsafe for an artifact filename')

    phase2 = LAB / 'phase2'
    cases = list(read_jsonl(phase2 / 'data' / 'cases.jsonl'))
    review_pack = list(read_jsonl(phase2 / 'review' / 'independent-review-pack.jsonl'))
    assignments, assigned_by_case = prepare(cases, review_pack, reviewers)
    if digest(assigned_by_case) != manifest['assignment_digest']:
        raise ValueError('assignment manifest digest mismatch')
    if sum(map(len, assigned_by_case.values())) != manifest['reviews_required']:
        raise ValueError('assignment count mismatch')

    review_schema = json.loads((LAB / 'schema' / 'review.schema.json').read_text())
    all_submissions = []
    submissions_by_reviewer = {}
    source_by_reviewer = {
        source['identity']: source['kind'] for source in manifest['reviewer_sources']
    }
    for reviewer in reviewers:
        batch_path = batch_dir / f'{reviewer}.jsonl'
        if list(read_jsonl(batch_path)) != assignments[reviewer]:
            raise ValueError(f'assignment batch mismatch for {reviewer}')
        submissions = compile_decisions(
            assignments[reviewer], list(read_jsonl(decision_paths[reviewer])),
            reviewer, source_by_reviewer[reviewer], reviewed_at, review_schema,
        )
        submissions_by_reviewer[reviewer] = submissions
        all_submissions.extend(submissions)
    if len(all_submissions) != manifest['reviews_required']:
        raise ValueError('compiled review count mismatch')

    adjudicated = apply_reviews(cases, all_submissions, review_schema)
    families = list(read_jsonl(phase2 / 'data' / 'semantic-families.jsonl'))
    blueprints = list(read_jsonl(phase2 / 'data' / 'blueprints.jsonl'))
    renderings = list(read_jsonl(phase2 / 'data' / 'renderings.jsonl'))
    taxonomy = json.loads((LAB / 'config' / 'taxonomy-v2.json').read_text())
    validate_all(families, blueprints, renderings, adjudicated, taxonomy, review_pack)
    report = build_report(cases, adjudicated, families, blueprints, taxonomy)

    output_dir.mkdir(parents=True, exist_ok=True)
    for reviewer, submissions in submissions_by_reviewer.items():
        write_jsonl(output_dir / 'reviews' / f'{reviewer}.jsonl', submissions)
    write_jsonl(output_dir / 'reviews.jsonl', all_submissions)
    write_jsonl(output_dir / 'cases-adjudicated.jsonl', adjudicated)
    durable_manifest = {
        **manifest,
        'reviewed_at': reviewed_at,
        'completed': True,
        'submission_count': len(all_submissions),
        'submission_digest': digest(all_submissions),
        'adjudicated_case_digest': digest(adjudicated),
        'production_parser_invoked': False,
        'parser_output_exposed_to_reviewers': False,
        'sealed_failures_read': 0,
    }
    write_json(output_dir / 'manifest.json', durable_manifest)
    write_json(output_dir / 'report.json', report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--batch-dir', type=Path, required=True)
    parser.add_argument('--decision', action='append', required=True, dest='decisions')
    parser.add_argument('--reviewed-at', required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    report = run(
        args.batch_dir, parse_decisions(args.decisions), args.reviewed_at, args.output_dir,
    )
    print(json.dumps({
        'adjudication': {key: report['adjudication'][key] for key in (
            'independent_review_records', 'independently_reviewed_cases', 'trusted_cases',
            'disputed_cases', 'rejected_cases')},
        'success_gate': report['success_gate'],
        'production_parser_invoked': False,
    }, indent=2))


if __name__ == '__main__':
    main()
