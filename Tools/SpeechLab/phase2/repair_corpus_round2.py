#!/usr/bin/env python3
"""Build repair round two from the independently reviewed first candidate."""
from __future__ import annotations

import json
from pathlib import Path
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))
sys.path.insert(0, str(LAB / 'phase2'))

from Sources.contracts import digest, read_jsonl, write_json, write_jsonl
from repair_corpus import build_candidate


VERSION = 'speechlab-corpus-repair-2'
ROUND2_REPAIRS = (
    {
        'before': 'save the boarding passes to my phone',
        'after': 'download the boarding passes to my phone',
        'root_causes': ['transformation changed meaning'],
        'reason': 'The paraphrase omitted the explicit download action.',
    },
    {
        'before': 'get in touch with the insurance person',
        'after': 'call the insurance adjuster',
        'root_causes': ['transformation changed meaning', 'entity/value mismatch'],
        'reason': 'The paraphrase dropped the call method and adjuster role.',
    },
    {
        'before': 'take the borrowed lens back',
        'after': 'return the borrowed camera lens',
        'root_causes': ['transformation changed meaning', 'entity/value mismatch'],
        'reason': 'The paraphrase dropped the camera subtype.',
    },
    {
        'before': 'Can you hang onto this detail: Wanjiku Njoroge mentioned that the landlord said we can paint the hall at the Junction post office this Sunday?',
        'after': 'Wanjiku Njoroge told me at the Junction post office that the landlord said we can paint the hall this Sunday. Please remember that.',
        'root_causes': ['ambiguous semantic contract', 'unnatural wording'],
        'reason': 'The rewrite makes the speaker, report, location, and paint date attach explicitly.',
    },
)


def main():
    phase2 = LAB / 'phase2'
    source = phase2 / 'repair' / 'candidate-1'
    output = phase2 / 'repair' / 'candidate-2'
    families = list(read_jsonl(phase2 / 'data' / 'semantic-families.jsonl'))
    blueprints = list(read_jsonl(phase2 / 'data' / 'blueprints.jsonl'))
    renderings = list(read_jsonl(source / 'renderings.jsonl'))
    cases = list(read_jsonl(source / 'adjudication' / 'cases.jsonl'))
    taxonomy = json.loads((LAB / 'config' / 'taxonomy-v2.json').read_text())
    repaired_renderings, repaired_cases, review_pack, repair_map = build_candidate(
        families, blueprints, renderings, cases, taxonomy,
        surface_repairs=ROUND2_REPAIRS, version=VERSION,
    )
    output.mkdir(parents=True, exist_ok=True)
    write_jsonl(output / 'renderings.jsonl', repaired_renderings)
    write_jsonl(output / 'cases.jsonl', repaired_cases)
    write_jsonl(output / 'review-pack.jsonl', review_pack)
    repaired_ids = {row['repaired_case_id'] for row in repair_map}
    write_jsonl(output / 'repair-cases.jsonl', [
        case for case in repaired_cases if case['case_id'] in repaired_ids
    ])
    write_jsonl(output / 'repair-review-pack.jsonl', [
        row for row in review_pack if row['case_id'] in repaired_ids
    ])
    write_jsonl(output / 'repair-map.jsonl', repair_map)
    write_json(output / 'manifest.json', {
        'version': VERSION,
        'source_candidate': 'candidate-1/adjudication',
        'starting_cases': len(cases),
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
        'cases': len(repaired_cases), 'repaired': len(repair_map),
        'fresh_independent_reviews_required': len(repair_map),
        'production_parser_invoked': False,
    }, indent=2))


if __name__ == '__main__':
    main()
