"""Validated JSONL exchange with external AI/human generation workflows."""
import json
from pathlib import Path

from .contracts import VERSION, read_jsonl, rendering_identity, validate_renderings, write_json, write_jsonl
from .coverage import report


def export_for_ai(blueprints, renderings, phenomena, output, *, batch_size=50):
    output = Path(output); output.mkdir(parents=True, exist_ok=True)
    covered = {p for r in renderings.values() for p in r['phenomena']}
    uncovered = [p['id'] for p in phenomena if p['id'] not in covered]
    ranked = sorted(blueprints.values(), key=lambda b: (len(b['difficulty_dimensions']), b['blueprint_id']), reverse=True)[:batch_size]
    forbidden = ['Do not add/drop items, facts, polarity, dates, people, locations, recurrence, or operations.',
                 'Do not turn questions or completed actions into obligations.']
    targets = uncovered or [p['id'] for p in phenomena]
    batch_rows = [dict(blueprint=bp, required_phenomena=[targets[i % len(targets)]], forbidden_meaning_changes=forbidden,
                       requested_diversity=['speaker style', 'disfluency position', 'syntax', 'capture length'],
                       number_of_candidates=3, style_speaker_constraints={'voice': 'plausible spontaneous speech', 'avoid_template_echo': True})
                  for i, bp in enumerate(ranked)]
    write_jsonl(output / 'blueprint-batch.jsonl', batch_rows)
    write_json(output / 'uncovered-dimensions.json', {'phenomena': uncovered})
    request = dict(format_version=VERSION, task='Generate meaning-preserving natural-speech renderings',
                   requested_diversity=['speaker style', 'disfluency position', 'syntax', 'capture length'],
                   candidates_per_blueprint=3,
                   forbidden_meaning_changes=forbidden,
                   required_output_fields=['blueprint_id', 'text', 'phenomena', 'meaning_preservation', 'generator', 'provenance', 'seed', 'mutation_lineage', 'equivalence_class'],
                   style_constraints={'voice': 'messy but plausible spontaneous speech', 'no_explanations': True})
    write_json(output / 'generation-request.json', request)
    write_json(output / 'coverage-summary.json', {'blueprints_available': len(blueprints), 'renderings_available': len(renderings), 'uncovered_phenomena': uncovered})
    failure = output / 'failure-pack.jsonl'
    if not failure.exists(): failure.write_text('')
    return {'blueprints': len(ranked), 'path': str(output)}


def import_renderings(path, blueprints, existing, phenomenon_ids, output):
    rows = []
    for row in read_jsonl(path):
        row = dict(row)
        row.setdefault('generator', {'kind': 'external_ai', 'name': 'external', 'version': 'unspecified'})
        row.setdefault('provenance', {'imported_from': str(path)})
        row.setdefault('seed', None); row.setdefault('mutation_lineage', [])
        row.setdefault('equivalence_class', row['blueprint_id']); row.setdefault('meaning_preservation', 'uncertain')
        row['rendering_id'] = 'rd-' + rendering_identity(row)[:24]
        rows.append(row)
    combined = list(existing.values()) + rows
    validate_renderings(combined, blueprints, phenomenon_ids)
    write_jsonl(output, combined)
    return {'imported': len(rows), 'total': len(combined), 'output': str(output)}


def import_failure_analysis(path, output):
    rows = list(read_jsonl(path))
    for row in rows:
        if not {'normalized_directional', 'analysis'} <= set(row): raise ValueError('Failure analysis needs normalized_directional and analysis')
    write_jsonl(output, rows); return {'imported': len(rows), 'output': str(output)}
