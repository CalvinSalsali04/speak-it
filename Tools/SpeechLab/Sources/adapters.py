"""Public-corpus adapter registry. Source labels never become Speak It gold."""
import json
from pathlib import Path

from .contracts import VERSION, digest, norm, write_jsonl

REGISTRY = {
    'MASSIVE': dict(source_url='https://github.com/alexa/massive', license='CC BY 4.0', allowed_usage='Attribution required; author Speak It semantics separately.', text_audio='text+audio', language='multilingual', dialogue='single utterance', relevant_phenomena=['casing-corruption', 'question-mixed-with-action']),
    'PRESTO': dict(source_url='https://github.com/google-research-datasets/presto', license='Check upstream release before import', allowed_usage='Local adapter only until license is reviewed.', text_audio='text', language='multilingual', dialogue='dialogue', relevant_phenomena=['self-correction-person', 'change-of-intent']),
    'Taskmaster': dict(source_url='https://github.com/google-research-datasets/Taskmaster', license='CC BY 4.0', allowed_usage='Attribution required; dialogue turns need authored capture boundaries.', text_audio='text+audio subsets', language='English', dialogue='dialogue', relevant_phenomena=['multiple-tasks', 'pronoun-resolution']),
    'SLURP-text': dict(source_url='https://github.com/pswietojanski/slurp', license='Text CC BY 4.0; audio has different restrictions', allowed_usage='Import text only unless audio terms are separately approved.', text_audio='text', language='English', dialogue='single utterance', relevant_phenomena=['asr-substitution', 'uncommon-proper-noun'])
}


def registry(local_root=None):
    result = []
    for name, meta in REGISTRY.items():
        path = Path(local_root) / name if local_root else None
        result.append(dict(dataset=name, **meta, import_status='available_locally' if path and path.exists() else 'not_imported',
                           local_path=str(path) if path else None, attribution_requirement='Preserve source, license, record ID, and modifications.'))
    return result


def import_jsonl(dataset, input_path, output, *, text_field='text', id_field='id', limit=None):
    if dataset not in REGISTRY: raise ValueError('Unknown registered dataset')
    rows = []
    with open(input_path) as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip(): continue
            source = json.loads(line); text = str(source[text_field]).strip()
            if not text: continue
            source_id = str(source.get(id_field, line_number))
            # Deliberately no expected field: source intent is evidence/provenance,
            # not Speak It ground truth. Review tooling must author a blueprint.
            rows.append({'candidate_id': 'public-' + digest([dataset, source_id, text])[:24], 'dataset': dataset,
                         'source_record_id': source_id, 'text': text, 'normalized_text': norm(text),
                         'source_label': source.get('intent'), 'speak_it_blueprint_id': None,
                         'review_status': 'needs_explicit_product_contract', 'provenance': REGISTRY[dataset]})
            if limit and len(rows) >= limit: break
    write_jsonl(output, rows); return {'imported_candidates': len(rows), 'authored_ground_truth': 0, 'output': str(output)}
