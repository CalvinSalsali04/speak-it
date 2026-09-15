#!/usr/bin/env python3
"""Create a lineage-preserving repair candidate without invoking the parser."""
from __future__ import annotations

import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))
sys.path.insert(0, str(LAB / 'phase2'))

from Sources.contracts import digest, read_jsonl, rendering_identity, write_json, write_jsonl
from quality import validate_all


VERSION = 'speechlab-corpus-repair-1'

SURFACE_REPAIRS = (
    {
        'before': 'sort receipts by project rather than by date',
        'after': 'sort receipts by project instead of by month',
        'root_causes': ['transformation changed meaning', 'entity/value mismatch'],
        'reason': 'The authored paraphrase changed the comparison value from month to date.',
    },
    {
        'before': 'the parcel was left by the side entrance',
        'after': 'the parcel was left behind the side gate',
        'root_causes': ['transformation changed meaning', 'entity/value mismatch'],
        'reason': 'The authored paraphrase changed both the spatial relation and landmark.',
    },
    {
        'before': 'chicken treats do not agree with the dog',
        'after': 'the dog is allergic to chicken treats',
        'root_causes': ['transformation changed meaning'],
        'reason': 'The authored paraphrase weakened a specific allergy into possible intolerance.',
    },
    {
        'before': 'we have permission to paint the hall',
        'after': 'the landlord said we can paint the hall',
        'root_causes': ['transformation changed meaning', 'entity/value mismatch'],
        'reason': 'The authored paraphrase dropped the identity of the approving party.',
    },
)


def repair_text(text, repairs=SURFACE_REPAIRS):
    applied = []
    result = text
    for repair in repairs:
        if repair['before'] in result:
            result = result.replace(repair['before'], repair['after'])
            applied.append(repair)
    if not applied:
        return text, None
    return result, {
        'root_causes': list(dict.fromkeys(
            cause for repair in applied for cause in repair['root_causes']
        )),
        'reason': ' '.join(repair['reason'] for repair in applied),
    }


def review_pack_row(case):
    return {
        'case_id': case['case_id'],
        'utterance': case['utterance'],
        'relevant_context': case['context'],
        'proposed_semantic_contract': case['proposed_contract'],
        'taxonomy_labels': case['taxonomy_labels'],
        'review_questions': [
            'How natural is this from 1 to 5?',
            'What does the speaker intend?',
            'How many items are intended?',
            'Where should each item route?',
            'What temporal and location meaning is expressed?',
            'Treat relevant_context.timezone as the authoritative default timezone; is any spoken timezone preserved there?',
            'What is the cancellation or negation scope?',
            'Is anything ambiguous?',
            'Is the proposed contract correct?',
        ],
    }


def build_candidate(
    families, blueprints, renderings, adjudicated, taxonomy,
    *, surface_repairs=SURFACE_REPAIRS, version=VERSION,
):
    rendering_by_id = {row['rendering_id']: deepcopy(row) for row in renderings}
    if len(rendering_by_id) != len(renderings):
        raise ValueError('duplicate rendering ID')
    output_renderings = []
    output_cases = []
    repair_map = []

    for original in adjudicated:
        case = deepcopy(original)
        new_text, repair = repair_text(case['utterance'], surface_repairs)
        rendering = rendering_by_id.pop(case['rendering_id'])
        if repair is None:
            output_renderings.append(rendering)
            output_cases.append(case)
            continue

        original_case_id = case['case_id']
        original_rendering_id = case['rendering_id']
        rendering['text'] = new_text
        rendering['generator'] = {
            'kind': 'deterministic', 'name': 'SpeechLab corpus repair', 'version': version,
        }
        rendering['mutation_lineage'] = [
            *rendering['mutation_lineage'], original_rendering_id,
        ]
        rendering['meaning_preservation'] = 'uncertain'
        rendering['rendering_id'] = 'rd-' + rendering_identity(rendering)[:24]

        case['utterance'] = new_text
        case['rendering_id'] = rendering['rendering_id']
        case['reviews'] = []
        case['naturalness'] = 3
        case['meaning_preservation'] = 'uncertain'
        case['label_state'] = 'draft'
        case['trusted'] = False
        case['lineage']['repairs'] = [
            *case['lineage'].get('repairs', []),
            {
                'version': version,
                'original_case_id': original_case_id,
                'original_rendering_id': original_rendering_id,
                'action': 'repair-rendering',
                'root_causes': repair['root_causes'],
                'reason': repair['reason'],
            },
        ]
        case['case_id'] = 'case-' + digest({
            'blueprint_id': case['blueprint_id'],
            'rendering_id': case['rendering_id'],
            'semantic_family_id': case['semantic_family_id'],
            'utterance': case['utterance'],
        })[:24]
        output_renderings.append(rendering)
        output_cases.append(case)
        repair_map.append({
            'original_case_id': original_case_id,
            'repaired_case_id': case['case_id'],
            'original_rendering_id': original_rendering_id,
            'repaired_rendering_id': rendering['rendering_id'],
            'before': original['utterance'],
            'after': new_text,
            'action': 'repair-rendering',
            'root_causes': repair['root_causes'],
            'reason': repair['reason'],
            'contract_changed': False,
            'taxonomy_changed': False,
            'fresh_independent_review_required': True,
        })

    if rendering_by_id:
        raise ValueError('adjudicated cases do not cover every rendering')
    full_review_pack = [review_pack_row(case) for case in output_cases]
    validate_all(
        families, blueprints, output_renderings, output_cases, taxonomy, full_review_pack,
    )
    return output_renderings, output_cases, full_review_pack, repair_map


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--output-dir', type=Path,
        default=LAB / 'phase2' / 'repair' / 'candidate-1',
    )
    args = parser.parse_args()
    phase2 = LAB / 'phase2'
    families = list(read_jsonl(phase2 / 'data' / 'semantic-families.jsonl'))
    blueprints = list(read_jsonl(phase2 / 'data' / 'blueprints.jsonl'))
    renderings = list(read_jsonl(phase2 / 'data' / 'renderings.jsonl'))
    adjudicated = list(read_jsonl(phase2 / 'adjudication' / 'cases-adjudicated.jsonl'))
    taxonomy = json.loads((LAB / 'config' / 'taxonomy-v2.json').read_text())
    repaired_renderings, repaired_cases, review_pack, repair_map = build_candidate(
        families, blueprints, renderings, adjudicated, taxonomy,
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_jsonl(args.output_dir / 'renderings.jsonl', repaired_renderings)
    write_jsonl(args.output_dir / 'cases.jsonl', repaired_cases)
    write_jsonl(args.output_dir / 'review-pack.jsonl', review_pack)
    repaired_ids = {row['repaired_case_id'] for row in repair_map}
    write_jsonl(
        args.output_dir / 'repair-cases.jsonl',
        [case for case in repaired_cases if case['case_id'] in repaired_ids],
    )
    write_jsonl(
        args.output_dir / 'repair-review-pack.jsonl',
        [row for row in review_pack if row['case_id'] in repaired_ids],
    )
    write_jsonl(args.output_dir / 'repair-map.jsonl', repair_map)
    write_json(args.output_dir / 'manifest.json', {
        'version': VERSION,
        'starting_cases': len(adjudicated),
        'candidate_cases': len(repaired_cases),
        'repaired_cases': len(repair_map),
        'removed_cases': 0,
        'unchanged_cases': len(repaired_cases) - len(repair_map),
        'repair_map_digest': digest(repair_map),
        'candidate_case_digest': digest(repaired_cases),
        'contracts_changed': 0,
        'fresh_independent_reviews_required': len(repair_map),
        'production_parser_invoked': False,
        'parser_output_read': False,
        'sealed_failures_read': 0,
    })
    print(json.dumps({
        'cases': len(repaired_cases),
        'repaired': len(repair_map),
        'fresh_independent_reviews_required': len(repair_map),
        'production_parser_invoked': False,
    }, indent=2))


if __name__ == '__main__':
    main()
