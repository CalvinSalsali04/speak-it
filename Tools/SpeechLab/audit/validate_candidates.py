#!/usr/bin/env python3
"""Apply SpeechLab import contracts per candidate and retain rejection reasons."""
import argparse
from collections import Counter
import json
from pathlib import Path
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))
from Sources.contracts import load_contracts, norm, read_jsonl, rendering_identity, validate_renderings, write_json, write_jsonl


def validate_candidates(input_path, accepted_path, report_path):
    blueprints, existing = load_contracts(LAB / 'data/blueprints.jsonl', LAB / 'data/renderings.jsonl')
    phenomenon_ids = {p['id'] for p in json.loads((LAB / 'config/phenomena.json').read_text())['phenomena']}
    known_texts = {r['text'] for r in existing.values()}; accepted = []; rejected = []; anchor_violations = []
    for number, source in enumerate(read_jsonl(input_path), 1):
        row = dict(source); row['rendering_id'] = 'rd-' + rendering_identity(row)[:24]
        reason = None
        if row['blueprint_id'] not in blueprints: reason = 'unknown_blueprint'
        elif row['text'] in known_texts: reason = 'exact_duplicate_existing'
        elif not set(row['phenomena']) <= phenomenon_ids: reason = 'unknown_phenomenon'
        else:
            try: validate_renderings([row], blueprints, phenomenon_ids)
            except ValueError as error: reason = str(error)
        if reason:
            rejected.append({'input_line': number, 'blueprint_id': row.get('blueprint_id'), 'reason': reason, 'text': row.get('text')})
            continue
        expected = blueprints[row['blueprint_id']]['expected']
        missing = [fact for item in expected['items'] for fact in item['facts'] if norm(fact) not in norm(row['text'])]
        if missing: anchor_violations.append({'input_line': number, 'blueprint_id': row['blueprint_id'], 'missing': missing})
        known_texts.add(row['text']); accepted.append(source)
    write_jsonl(accepted_path, accepted)
    report = {'submitted': len(accepted) + len(rejected), 'accepted': len(accepted), 'rejected': len(rejected),
              'rejection_rate': round(len(rejected) / max(1, len(accepted) + len(rejected)), 6),
              'rejection_reasons': dict(Counter(r['reason'] for r in rejected)), 'rejections': rejected,
              'blueprint_identity_violations': 0,
              'lexical_anchor_warnings': len(anchor_violations), 'anchor_warning_details': anchor_violations,
              'note': 'Anchor warnings are review signals, not automatic semantic-label verdicts.'}
    write_json(report_path, report); return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=LAB / 'audit/ai-candidates.jsonl')
    parser.add_argument('--accepted', type=Path, default=LAB / 'audit/ai-candidates-accepted.jsonl')
    parser.add_argument('--report', type=Path, default=LAB / 'audit/ai-import-report.json')
    args = parser.parse_args(); print(json.dumps(validate_candidates(args.input, args.accepted, args.report), indent=2))


if __name__ == '__main__': main()
