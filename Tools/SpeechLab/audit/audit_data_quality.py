#!/usr/bin/env python3
"""Reproducible quantitative audit and bounded human-review-set builder."""
import argparse
from collections import Counter, defaultdict
import csv
import difflib
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import statistics
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))
from Sources.contracts import digest, dumps, load_contracts, norm, read_jsonl, write_json, write_jsonl
from Sources.signatures import normalize_difference

CURRENT_BAD_NATURALNESS = {
    'self-correction-quantity', 'self-correction-location', 'never-mind-withdrawal', 'shared-object',
    'temporal-inheritance', 'location-inheritance', 'pronoun-resolution', 'negation', 'prohibition',
    'uncertainty', 'conditional-intent', 'question-mixed-with-action', 'information-mixed-with-action',
    'completed-action', 'outstanding-obligation', 'past-event', 'future-intention', 'exact-time',
    'recurrence', 'uncommon-proper-noun', 'ordinary-word-name', 'store-brand-product-name', 'homophone'
}
CURRENT_GOOD_NATURALNESS = {
    'filler-words', 'hesitation', 'restart', 'repetition', 'rephrasing', 'abandoned-thought',
    'rambling-introduction', 'rambling-ending', 'sign-off-trailing-noise', 'multiple-tasks',
    'numbered-list', 'unnumbered-list', 'sequencing', 'reported-speech', 'quoted-speech',
    'lowercase', 'punctuation-loss', 'punctuation-corruption', 'asr-substitution', 'asr-insertion',
    'partial-thought', 'long-capture', 'short-fragment', 'code-switch-token'
}
PRESERVATION_FAILURES = {
    'self-correction-quantity': 'adds a new quantity-bearing action absent from the blueprint',
    'self-correction-location': 'adds work while the contracted location remains Farm Boy',
    'shared-object': 'invents a document shared by unrelated milk/call actions',
    'temporal-inheritance': 'adds tomorrow while contracted items are on Friday',
    'location-inheritance': 'adds office while contracted items are at Farm Boy',
    'pronoun-resolution': 'adds a reply action absent from the blueprint',
    'reported-speech': 'adds Maya as source and changes the discourse status',
    'quoted-speech': 'adds Maya as source and quoted imperative scope',
    'conditional-intent': 'adds a Maya-calls condition absent from the blueprint',
    'past-event': 'adds yesterday although the blueprint has no temporal fact',
    'relative-duration': 'adds a 90-minute trigger absent from the blueprint',
    'store-brand-product-name': 'invents Oatly, which is absent from the blueprint'
}


def tokens(text): return set(re.findall(r'\w+', text.casefold()))


def structural_text(rendering, blueprint):
    text = rendering['text'].casefold()
    values = []
    for item in blueprint['expected']['items']:
        values += item['facts'] + [item['title'], item.get('person'), item.get('location'), item.get('date'), item.get('time')]
    for operation in blueprint['expected']['operations']: values.append(operation.get('target'))
    for value in sorted((str(v) for v in values if v), key=len, reverse=True):
        text = text.replace(value.casefold(), '<slot>')
    text = re.sub(r'\b(?:mon|tue|wed|thu|fri|sat|sun)\w*\b', '<date>', text)
    text = re.sub(r'\b\d+(?::\d+)?\b', '<number>', text)
    return ' '.join(re.findall(r'<slot>|<date>|<number>|\w+', text))


def semantic_shape(bp):
    e = bp['expected']
    return dumps({'count': e['item_count'], 'policy': e['ambiguity_policy'],
                  'items': [{'route': i['route'], 'type': i['type'], 'date': i['date'] is not None,
                             'time': i['time'] is not None, 'recurrence': i['recurrence'] is not None,
                             'location': i['location'] is not None, 'person': i['person'] is not None,
                             'negation': i['negation'], 'prohibition': i['prohibition'], 'state': i['state']}
                            for i in e['items']],
                  'operations': [o.get('operation') for o in e['operations']],
                  'shared': {k: v is not None for k, v in e['shared_context'].items()}})


def pair_metrics(renderings):
    normalized = Counter(norm(r['text']) for r in renderings)
    duplicate_groups = [n for n in normalized.values() if n > 1]
    near_pairs = cross_blueprint = 0; affected = set()
    tokenized = [tokens(r['text']) for r in renderings]
    for left in range(len(renderings)):
        for right in range(left + 1, len(renderings)):
            union = tokenized[left] | tokenized[right]
            score = len(tokenized[left] & tokenized[right]) / max(1, len(union))
            if score >= .80 and norm(renderings[left]['text']) != norm(renderings[right]['text']):
                near_pairs += 1; affected.update((left, right))
                if renderings[left]['blueprint_id'] != renderings[right]['blueprint_id']: cross_blueprint += 1
    return {'normalized_duplicate_groups': len(duplicate_groups), 'normalized_duplicate_records': sum(duplicate_groups),
            'lexical_jaccard_0_80_pairs': near_pairs, 'lexical_near_duplicate_records': len(affected),
            'lexical_near_duplicate_record_rate': round(len(affected) / len(renderings), 6),
            'cross_blueprint_near_pairs': cross_blueprint}


def corpus_metrics(blueprints, renderings):
    rows = list(renderings.values()); lengths = [len(re.findall(r'\w+', r['text'])) for r in rows]
    structures = Counter(structural_text(r, blueprints[r['blueprint_id']]) for r in rows)
    interactions = Counter(len(r['phenomena']) for r in rows)
    family_counts = Counter(blueprints[r['blueprint_id']]['family_id'] for r in rows)
    archetypes = Counter(bp['semantic_tags'][0] for bp in blueprints.values())
    overlays = Counter(bp['semantic_tags'][1] for bp in blueprints.values())
    shapes = Counter(semantic_shape(bp) for bp in blueprints.values())
    direct_fact = sum(all(norm(f) in norm(r['text']) for i in blueprints[r['blueprint_id']]['expected']['items'] for f in i['facts']) for r in rows)
    basic = sum(not r['phenomena'] and blueprints[r['blueprint_id']]['expected']['item_count'] <= 1 and blueprints[r['blueprint_id']]['expected']['ambiguity_policy'] == 'act' for r in rows)
    result = {'renderings': len(rows), 'exact_unique_texts': len({r['text'] for r in rows}),
              'families_represented': len(family_counts), 'word_length': {'min': min(lengths), 'median': statistics.median(lengths), 'mean': round(statistics.mean(lengths), 3), 'max': max(lengths)},
              'phenomena_per_rendering': dict(sorted(interactions.items())), 'multi_phenomenon_renderings': sum(v for k, v in interactions.items() if k >= 2),
              'multi_phenomenon_rate': round(sum(v for k, v in interactions.items() if k >= 2) / len(rows), 6),
              'basic_clean_single_item': basic, 'basic_clean_single_item_rate': round(basic / len(rows), 6),
              'semantic_archetypes': len(archetypes), 'context_overlays': len(overlays),
              'archetype_balance': dict(archetypes), 'overlay_balance': dict(overlays),
              'value_agnostic_semantic_shapes': len(shapes),
              'structural_text_templates': len(structures), 'largest_structural_template': max(structures.values()),
              'largest_structural_template_share': round(max(structures.values()) / len(rows), 6),
              'top_structural_templates': [{'template': k, 'count': v} for k, v in structures.most_common(10)],
              'renderings_with_all_facts_verbatim': direct_fact,
              'verbatim_fact_coupling_rate': round(direct_fact / len(rows), 6),
              'family_rendering_count': {'min': min(family_counts.values()), 'median': statistics.median(family_counts.values()), 'max': max(family_counts.values())}}
    result.update(pair_metrics(rows)); return result


def manual_sample(blueprints, current):
    phenomenon = [r for r in current.values() if r['phenomena']]
    bases = [r for r in current.values() if not r['phenomena']]
    bases.sort(key=lambda r: hashlib.sha256(r['rendering_id'].encode()).hexdigest())
    rows = []
    for rendering in phenomenon + bases[:40]:
        pid = rendering['phenomena'][0] if rendering['phenomena'] else None
        if pid in CURRENT_BAD_NATURALNESS: naturalness = 'implausible_or_broken'
        elif pid in CURRENT_GOOD_NATURALNESS: naturalness = 'plausible_spoken'
        else: naturalness = 'plausible_but_synthetic'
        semantic = 'meaning_changed' if pid in PRESERVATION_FAILURES else ('uncertain' if rendering['meaning_preservation'] == 'uncertain' else 'appears_preserved')
        rows.append({'rendering_id': rendering['rendering_id'], 'phenomena': rendering['phenomena'],
                     'family_id': blueprints[rendering['blueprint_id']]['family_id'], 'text': rendering['text'],
                     'naturalness': naturalness, 'semantic_contract_review': semantic,
                     'review_note': PRESERVATION_FAILURES.get(pid, 'No obvious contract change in assistant audit; human review still required.')})
    return rows


def load_results(db, run_id):
    con = sqlite3.connect(db); rows = {}
    for (raw,) in con.execute('SELECT payload_json FROM results WHERE run_id=?', (run_id,)):
        payload = json.loads(raw); rows[payload['rendering_id']] = payload
    con.close(); return rows


def review_set(blueprints, renderings, results, target=350):
    candidates = []
    suspicious = set(CURRENT_BAD_NATURALNESS)
    for rid, rendering in renderings.items():
        bp = blueprints[rendering['blueprint_id']]; payload = results[rid]; reasons = []
        if rendering['phenomena']: reasons.append('phenomenon_coverage')
        if bp['safety_critical']: reasons.append('safety_critical')
        if len(rendering['phenomena']) >= 2: reasons.append('multi_phenomenon')
        if not payload['metrics']['passed']: reasons.append('failure')
        if len(payload['difference']['changed_fields']) >= 5: reasons.append('compound_failure')
        if len(payload['actual'].get('items', [])) != bp['expected']['item_count']: reasons.append('unusual_item_count')
        if rendering['generator']['kind'] == 'external_ai': reasons.append('ai_candidate')
        if suspicious.intersection(rendering['phenomena']): reasons.append('suspicious_synthetic')
        priority = (bool(rendering['phenomena']), bp['safety_critical'], len(rendering['phenomena']) >= 2,
                    'compound_failure' in reasons, 'unusual_item_count' in reasons, rendering['generator']['kind'] == 'external_ai')
        candidates.append((priority, hashlib.sha256(rid.encode()).hexdigest(), rid, reasons))
    mandatory = {rid for _, _, rid, reasons in candidates if any(x in reasons for x in ('phenomenon_coverage', 'safety_critical', 'multi_phenomenon', 'suspicious_synthetic'))}
    selected = list(mandatory); random_fill = set()
    for _, _, rid, _ in sorted(candidates, key=lambda x: x[1]):
        if len(selected) >= target: break
        if rid not in selected: selected.append(rid); random_fill.add(rid)
    selected = sorted(selected[:target], key=lambda rid: hashlib.sha256(rid.encode()).hexdigest())
    reason_map = {rid: reasons for _, _, rid, reasons in candidates}
    output = []
    for rid in selected:
        r = renderings[rid]; bp = blueprints[r['blueprint_id']]; payload = results[rid]
        _, normalized_signature = normalize_difference(payload)
        reasons = list(reason_map[rid])
        if rid in random_fill: reasons.append('hash_random_fill')
        output.append({'id': rid, 'phenomena': r['phenomena'], 'family': bp['family_id'],
                       'blueprint': {'blueprint_id': bp['blueprint_id'], 'semantic_tags': bp['semantic_tags'],
                                     'difficulty_dimensions': bp['difficulty_dimensions'], 'safety_critical': bp['safety_critical'],
                                     'ambiguity_policy': bp['expected']['ambiguity_policy']},
                       'spoken_rendering': r['text'], 'expected_behavior': bp['expected'],
                       'actual_behavior': payload['actual'], 'failure_signature': None if payload['metrics']['passed'] else normalized_signature,
                       'selected_because': reasons})
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', type=Path, required=True); parser.add_argument('--run-id', required=True)
    parser.add_argument('--output', type=Path, default=LAB / 'audit')
    args = parser.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    blueprints, current = load_contracts(LAB / 'data/blueprints.jsonl', LAB / 'data/renderings.jsonl')
    _, combined = load_contracts(LAB / 'data/blueprints.jsonl', LAB / 'audit/combined-renderings.jsonl')
    current_metrics = corpus_metrics(blueprints, current); combined_metrics = corpus_metrics(blueprints, combined)
    sample = manual_sample(blueprints, current); write_jsonl(args.output / 'manual-stratified-sample.jsonl', sample)
    natural = Counter(r['naturalness'] for r in sample); semantic = Counter(r['semantic_contract_review'] for r in sample)
    ai_report = json.loads((args.output / 'ai-import-report.json').read_text())
    ai_rows = list(read_jsonl(args.output / 'ai-candidates-accepted.jsonl'))
    ambiguity_rows = [r for r in ai_rows if blueprints[r['blueprint_id']]['expected']['ambiguity_policy'] != 'act']
    unexpressed_ambiguity = sum('not sure' not in r['text'].casefold() and 'maybe' not in r['text'].casefold() for r in ambiguity_rows)
    report = {'methodology': {'population_measurement': 'all current 324 renderings and all 472 post-import renderings',
                              'manual_stratified_sample': len(sample), 'sample_contents': 'all 64 phenomenon variants plus 40 SHA-256-selected base renderings',
                              'near_duplicate_definition': 'token-set Jaccard >= 0.80, excluding normalized-identical pairs',
                              'sealed_cases_read': 0, 'parser_output_used_as_label': False},
              'current': current_metrics, 'after_ai_import': combined_metrics,
              'manual_sample_naturalness': dict(natural), 'manual_sample_semantic_contract': dict(semantic),
              'reviewed_mutation_preservation': {'reviewed_variants': 57, 'assistant_identified_meaning_changes': len(PRESERVATION_FAILURES),
                                                  'apparent_preservation_rate': round((57-len(PRESERVATION_FAILURES))/57, 6),
                                                  'failures': PRESERVATION_FAILURES},
              'ai_generation': ai_report | {'candidates_requiring_review_or_preserve_only_policy': len(ambiguity_rows),
                                             'candidates_not_lexically_expressing_that_policy': unexpressed_ambiguity,
                                             'semantic_review_note': 'Schema acceptance is not promotion; all AI candidates remain uncertain pending human contract review.'},
              'difficulty_distribution_definition': {'basic': 'zero phenomena, <=1 expected item, act policy',
                                                     'single_phenomenon': 'exactly one tagged phenomenon', 'interaction': 'two or more tagged phenomena'},
              'label_circularity': {'production_parser_used_to_create_expected': False,
                                    'blueprint_and_rendering_share_generator': True,
                                    'risk': 'High for synthetic self-confirmation: expected facts are authored in catalog.py and copied almost verbatim by render_text.'}}
    write_json(args.output / 'data-quality-metrics.json', report)
    results = load_results(args.database, args.run_id)
    review = review_set(blueprints, combined, results, 400); write_jsonl(args.output / 'human-review-set.jsonl', review)
    with (args.output / 'human-review-set.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, lineterminator='\n', fieldnames=['id','phenomena','family','spoken_rendering','expected_summary','actual_summary','failure_signature','selected_because'])
        writer.writeheader()
        for row in review:
            writer.writerow({'id': row['id'], 'phenomena': '|'.join(row['phenomena']), 'family': row['family'],
                             'spoken_rendering': row['spoken_rendering'], 'expected_summary': dumps(row['expected_behavior']),
                             'actual_summary': dumps(row['actual_behavior']), 'failure_signature': row['failure_signature'] or '',
                             'selected_because': '|'.join(row['selected_because'])})
    print(json.dumps({'metrics': str(args.output / 'data-quality-metrics.json'), 'manual_sample': len(sample), 'review_set': len(review)}, indent=2))


if __name__ == '__main__': main()
