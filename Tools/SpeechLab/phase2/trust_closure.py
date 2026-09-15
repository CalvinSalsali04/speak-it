#!/usr/bin/env python3
"""Build the high-trust scoreable subset and preserve every exclusion."""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))
sys.path.insert(0, str(LAB / 'phase2'))

from Sources.contracts import digest, file_hash, read_jsonl, write_json, write_jsonl
from adjudication_report import build_report
from quality import corpus_metrics, validate_all


def positive(review):
    return (review['independence'] == 'independent'
            and review['proposed_contract_correct'] == 'yes'
            and review['meaning_preservation'] == 'appears_preserved')


def trustworthy(case):
    reviews = [
        review for review in case['reviews']
        if review['independence'] == 'independent'
    ]
    return (
        case['trusted']
        and case['naturalness'] >= 3
        and case['meaning_preservation'] == 'appears_preserved'
        and all(review['proposed_contract_correct'] == 'yes' for review in reviews)
        and all(review['meaning_preservation'] == 'appears_preserved' for review in reviews)
        and sum(map(positive, reviews)) >= case['required_independent_reviews']
    )


def build(candidate_dir, output_dir):
    phase2 = LAB / 'phase2'
    cases = list(read_jsonl(candidate_dir / 'adjudication' / 'cases.jsonl'))
    renderings = list(read_jsonl(candidate_dir / 'renderings.jsonl'))
    blueprints = list(read_jsonl(phase2 / 'data' / 'blueprints.jsonl'))
    families = list(read_jsonl(phase2 / 'data' / 'semantic-families.jsonl'))
    taxonomy = json.loads((LAB / 'config' / 'taxonomy-v2.json').read_text())
    triage = {
        row['case_id']: row for row in read_jsonl(phase2 / 'repair' / 'triage.jsonl')
    }
    scoreable = [case for case in cases if trustworthy(case)]
    scoreable_ids = {case['case_id'] for case in scoreable}
    blueprint_ids = {case['blueprint_id'] for case in scoreable}
    rendering_ids = {case['rendering_id'] for case in scoreable}
    scoreable_blueprints = [row for row in blueprints if row['blueprint_id'] in blueprint_ids]
    scoreable_renderings = [row for row in renderings if row['rendering_id'] in rendering_ids]
    scoreable_review_pack = [{
        'case_id': case['case_id'], 'utterance': case['utterance'],
        'relevant_context': case['context'],
        'proposed_semantic_contract': case['proposed_contract'],
        'taxonomy_labels': case['taxonomy_labels'],
        'review_questions': [
            'How natural is this from 1 to 5?', 'What does the speaker intend?',
            'How many items are intended?', 'Where should each item route?',
            'What temporal and location meaning is expressed?',
            'Treat relevant_context.timezone as the authoritative default timezone; is any spoken timezone preserved there?',
            'What is the cancellation or negation scope?', 'Is anything ambiguous?',
            'Is the proposed contract correct?',
        ],
    } for case in scoreable]
    validate_all(
        families, scoreable_blueprints, scoreable_renderings, scoreable,
        taxonomy, scoreable_review_pack,
    )

    exclusions = []
    for case in cases:
        if case['case_id'] in scoreable_ids:
            continue
        original_id = case.get('lineage', {}).get('repairs', [{}])[0].get(
            'original_case_id', case['case_id']
        )
        disposition = triage.get(original_id, {}).get('disposition')
        if disposition == 'E':
            destination = 'ambiguity-challenge'
        elif disposition == 'G':
            destination = 'representation-deferred'
        elif case['naturalness'] <= 2:
            destination = 'removed-broken-or-implausible'
        else:
            destination = 'repair-backlog'
        reasons = []
        if case['naturalness'] <= 2:
            reasons.append(f'naturalness-{case["naturalness"]}')
        if not case['trusted']:
            reasons.append(case['label_state'])
        if case['meaning_preservation'] != 'appears_preserved':
            reasons.append(case['meaning_preservation'])
        exclusions.append({
            'case_id': case['case_id'], 'original_case_id': original_id,
            'destination': destination, 'reasons': reasons,
            'utterance': case['utterance'], 'taxonomy_labels': case['taxonomy_labels'],
            'semantic_family_id': case['semantic_family_id'],
            'lineage': case['lineage'],
        })

    output_dir.mkdir(parents=True, exist_ok=True)
    write_jsonl(output_dir / 'semantic-families.jsonl', families)
    write_jsonl(output_dir / 'blueprints.jsonl', scoreable_blueprints)
    write_jsonl(output_dir / 'renderings.jsonl', scoreable_renderings)
    write_jsonl(output_dir / 'cases.jsonl', scoreable)
    write_jsonl(output_dir / 'review-pack.jsonl', scoreable_review_pack)
    write_jsonl(output_dir / 'exclusions.jsonl', exclusions)

    original = list(read_jsonl(phase2 / 'data' / 'cases.jsonl'))
    report = build_report(original, scoreable, families, scoreable_blueprints, taxonomy)
    baseline_metrics = corpus_metrics(families, blueprints, original, taxonomy)
    final_metrics = report['corpus_metrics']
    coverage = {
        'semantic_families_before': baseline_metrics['semantic_family_count'],
        'semantic_families_represented_after': len({c['semantic_family_id'] for c in scoreable}),
        'phenomena_before': baseline_metrics['phenomenon_coverage']['covered'],
        'phenomena_after': final_metrics['phenomenon_coverage']['covered'],
        'phenomena_lost': sorted(
            set(baseline_metrics['phenomenon_coverage']['counts'])
            - set(final_metrics['phenomenon_coverage']['counts'])
        ),
        'interaction_pairs_before': baseline_metrics['interaction_coverage']['distinct_pairs'],
        'interaction_pairs_after': final_metrics['interaction_coverage']['distinct_pairs'],
        'coverage_gained_by_repairs': [],
    }
    report['trust_closure'] = {
        'starting_corpus_size': len(cases),
        'final_scoreable_corpus_size': len(scoreable),
        'removed_from_scoreable_corpus': len(exclusions),
        'repaired_and_retained': sum(bool(c['lineage'].get('repairs')) for c in scoreable),
        'unchanged_and_retained': sum(not c['lineage'].get('repairs') for c in scoreable),
        'exclusion_destinations': dict(Counter(row['destination'] for row in exclusions)),
        'all_trusted': all(case['trusted'] for case in scoreable),
        'all_safety_cases_satisfy_review_policy': all(
            not case['safety_critical']
            or sum(positive(review) for review in case['reviews']) >= 2
            for case in scoreable
        ),
        'coverage': coverage,
    }
    write_json(output_dir / 'report.json', report)
    hashes = {
        name: file_hash(output_dir / name) for name in (
            'semantic-families.jsonl', 'blueprints.jsonl', 'renderings.jsonl',
            'cases.jsonl', 'review-pack.jsonl', 'exclusions.jsonl', 'report.json',
        )
    }
    manifest = {
        'version': 'speechlab-trust-closure-1',
        'frozen': False,
        'reason': report['success_gate']['decision'],
        'starting_cases': len(cases), 'scoreable_cases': len(scoreable),
        'excluded_cases': len(exclusions),
        'roles': dict(Counter(case['split_role'] for case in scoreable)),
        'hashes': hashes,
        'manifest_digest': digest(hashes),
        'production_parser_invoked': False,
        'parser_results_included': False,
        'sealed_content_included': False,
    }
    write_json(output_dir / 'manifest.json', manifest)
    return report, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--candidate-dir', type=Path,
        default=LAB / 'phase2' / 'repair' / 'candidate-2',
    )
    parser.add_argument(
        '--output-dir', type=Path,
        default=LAB / 'phase2' / 'repair' / 'trust-closure',
    )
    args = parser.parse_args()
    report, manifest = build(args.candidate_dir, args.output_dir)
    print(json.dumps({
        'scoreable_cases': manifest['scoreable_cases'],
        'excluded_cases': manifest['excluded_cases'],
        'gates': report['success_gate'],
        'frozen': manifest['frozen'],
        'production_parser_invoked': False,
    }, indent=2))


if __name__ == '__main__':
    main()
