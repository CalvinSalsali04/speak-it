#!/usr/bin/env python3
"""Validate and measure the bounded SpeechLab Phase 2 corpus."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import itertools
import json
from pathlib import Path
import re
import statistics
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))

from Sources.composition import TRANSFORMS, validate_composition
from Sources.contracts import (digest, dumps, norm, read_jsonl, validate_blueprints,
                               validate_renderings, validate_schema, write_json)


FUNCTION_WORDS = {
    'a', 'about', 'actually', 'again', 'all', 'also', 'am', 'an', 'and', 'any', 'are',
    'as', 'at', 'be', 'before', 'between', 'both', 'but', 'by', 'can', 'could', 'did',
    'do', 'does', 'doing', 'done', 'everything', 'for', 'from', 'got', 'have', 'here',
    'how', 'i', 'if', 'in', 'into', 'is', 'it', 'just', 'keep', 'last', 'let', 'like',
    'me', 'my', 'need', 'no', 'not', 'of', 'on', 'once', 'one', 'only', 'or', 'other',
    'out', 'please', 'really', 'remember', 'said', 'second', 'so', 'something', 'still',
    'than', 'that', 'the', 'then', 'there', 'these', 'thing', 'things', 'this', 'those',
    'to', 'too', 'two', 'up', 'want', 'was', 'way', 'what', 'when', 'while', 'with',
    'would', 'yeah', 'yet', 'you', 'your', 'first', 'plus', 'though', 'instead',
}

LANGUAGE_LINT_PATTERNS = {
    'infinitive_followed_by_clause': re.compile(
        r'\b(?:need|supposed|whether|possibility|reminder|remind me)\s+to\s+(?:the|it is|there is|we have|school lets|lunch at|one checked bag|pickup is|northstar is|chicken treats|smoked paprika|[A-Z][\w’.-]+ mentioned that)\b', re.I
    ),
    'invalid_relative_date_preposition': re.compile(
        r'(?<!turned )\bon (?:tomorrow|next\b|this\b|two days\b|three weeks\b|yesterday\b|last\b|earlier\b)|\bduring (?:tomorrow|next\b|this\b|two days\b|three weeks\b|yesterday\b|last\b|earlier\b)', re.I
    ),
    'double_person_attachment': re.compile(r'\bwith me with\b', re.I),
    'malformed_memory_negation': re.compile(r'\bnot true that [^.?!]{0,100}\bdo not\b', re.I),
    'benchmark_cancellation_noun_phrase': re.compile(r'\breminder (?:about|for) (?:send|pick|buy|call|book|take|bring|make|check|return|cancel|move|pay|print|order|upload|charge|drop|request|clean|sign|collect|replace)\b', re.I),
}


def language_lint_results(cases):
    findings = []
    for case in cases:
        text = case['utterance']
        for lint_id, pattern in LANGUAGE_LINT_PATTERNS.items():
            if pattern.search(text):
                findings.append({'case_id': case['case_id'], 'lint_id': lint_id})
        correction = re.search(r'([^—,.?]{2,60})—sorry,\s*([^,.?]{2,60})', text, re.I)
        if correction and norm(correction.group(1)) == norm(correction.group(2)):
            findings.append({'case_id': case['case_id'], 'lint_id': 'correction_repeats_same_value'})
    return findings


def validate_phenomenon_realization(case):
    labels = set(case['taxonomy_labels'])
    text = case['utterance'].casefold()
    prior_turns = case['context']['prior_turns']
    people = [str(item['person']).casefold() for item in case['proposed_contract']['items'] if item['person']]
    checks = {
        'pronoun-resolution': bool(prior_turns) and (' them' in text or 'they ' in text),
        'ambiguous-pronoun': bool(prior_turns) and (' them' in text or 'they ' in text),
        'cross-turn-reference': bool(prior_turns) and ('that ' in text or ' it' in text),
        'cross-turn-reference-ambiguity': bool(prior_turns) and ('unclear' in text or 'not sure' in text),
        'contact-person-ambiguity': bool(prior_turns) and ('unclear' in text or 'not sure' in text),
        'timezone-sensitive': case['context']['timezone'].casefold() in text,
        'dst-transition': 'clock change' in text,
        'question-mixed-with-action': 'could you remind' in text and 'remember this' in text,
        'information-mixed-with-action': 'detail to' in text and 'reminder' in text,
        'change-of-intent': 'but actually' in text and 'instead' in text,
        'unresolved-alternative': 'deciding whether' in text and ' or ' in text,
        'resolved-alternative': 'deciding whether' in text and 'but i chose' in text,
        'correction-chain': '—no,' in text and '—sorry,' in text,
        'asr-deletion': '[inaudible]' in text,
        'asr-dropped-token': '[inaudible]' in text,
        'asr-insertion': ' uh ' in f' {text} ',
        'asr-substitution': 'meaning' in text or 'chicken' in text,
        'homophone': 'flower' in text,
        'asr-name-corruption': bool(people) and people[0] not in text,
        'asr-partial-recognition': text.endswith('…'),
        'asr-duplicated-token': bool(re.search(r'\b(\w+)(?:,?\s+uh)?\s+\1\b', text, re.I)),
    }
    missing = [label for label in labels & checks.keys() if not checks[label]]
    if missing:
        raise ValueError(f'phenomenon not realized in {case["case_id"]}: {missing}')
    for transformation in case['lineage']['transformations']:
        if transformation['phenomenon_id'].startswith('self-correction-'):
            field = transformation['phenomenon_id'].removeprefix('self-correction-')
            final_values = [str(item[field]) for item in case['proposed_contract']['items'] if item.get(field)]
            if not transformation['discarded_value'] or not any(norm(value) in norm(case['utterance']) for value in final_values):
                raise ValueError(f'self correction lacks discarded or final value in {case["case_id"]}')


def tokens(text):
    return set(re.findall(r"[\w’']+", text.casefold()))


def structural_template(text):
    values = []
    for token in re.findall(r"[\w’']+|[^\w\s]", text.casefold()):
        if token in FUNCTION_WORDS or re.fullmatch(r'[^\w\s]', token):
            values.append(token)
        else:
            values.append('<slot>')
    collapsed = []
    for value in values:
        if value == '<slot>' and collapsed and collapsed[-1] == '<slot>':
            continue
        collapsed.append(value)
    return ' '.join(collapsed)


def pair_metrics(cases):
    normalized = Counter(norm(case['utterance']) for case in cases)
    normalized_groups = [count for count in normalized.values() if count > 1]
    tokenized = [tokens(case['utterance']) for case in cases]
    affected, pairs = set(), 0
    for left, right in itertools.combinations(range(len(cases)), 2):
        union = tokenized[left] | tokenized[right]
        score = len(tokenized[left] & tokenized[right]) / max(1, len(union))
        if score >= .80 and norm(cases[left]['utterance']) != norm(cases[right]['utterance']):
            pairs += 1
            affected.update((left, right))
    return {
        'normalized_duplicate_groups': len(normalized_groups),
        'normalized_duplicate_records': sum(normalized_groups),
        'lexical_jaccard_0_80_pairs': pairs,
        'lexical_near_duplicate_records': len(affected),
        'lexical_near_duplicate_record_rate': round(len(affected) / len(cases), 6),
    }


def review_count(case):
    return sum(review['independence'] == 'independent' and review['proposed_contract_correct'] == 'yes'
               and review['meaning_preservation'] == 'appears_preserved' for review in case['reviews'])


def validate_all(families, blueprints, renderings, cases, taxonomy, review_pack):
    family_ids = {family['semantic_family_id'] for family in families}
    if len(family_ids) != len(families):
        raise ValueError('duplicate semantic family')
    validate_blueprints(blueprints)
    blueprint_map = {row['blueprint_id']: row for row in blueprints}
    phenomenon_ids = {row['id'] for row in taxonomy['phenomena']}
    rendering_map = validate_renderings(renderings, blueprint_map, phenomenon_ids)
    review_schema = json.loads((LAB / 'schema' / 'review.schema.json').read_text())
    case_ids = set()
    required_case_keys = {
        'case_id', 'blueprint_id', 'rendering_id', 'semantic_family_id', 'utterance', 'context',
        'proposed_contract', 'taxonomy_labels', 'lineage', 'provenance', 'label_state', 'reviews',
        'naturalness', 'meaning_preservation', 'safety_critical', 'required_independent_reviews',
        'trusted', 'split_role', 'coverage_contributions',
    }
    for case in cases:
        if set(case) != required_case_keys:
            raise ValueError('case field mismatch')
        identity = {
            'blueprint_id': case['blueprint_id'], 'rendering_id': case['rendering_id'],
            'semantic_family_id': case['semantic_family_id'], 'utterance': case['utterance'],
        }
        if case['case_id'] in case_ids or case['case_id'] != 'case-' + digest(identity)[:24]:
            raise ValueError('duplicate or invalid case ID')
        case_ids.add(case['case_id'])
        if case['semantic_family_id'] not in family_ids:
            raise ValueError('unknown semantic family')
        blueprint = blueprint_map[case['blueprint_id']]
        rendering = rendering_map[case['rendering_id']]
        if case['utterance'] != rendering['text'] or case['context'] != blueprint['capture_context'] or case['proposed_contract'] != blueprint['expected']:
            raise ValueError('case/contract/rendering mismatch')
        if case['lineage']['contract_digest'] != digest(case['proposed_contract']):
            raise ValueError('contract digest mismatch')
        if len(case['taxonomy_labels']) > 4 or not set(case['taxonomy_labels']) <= phenomenon_ids:
            raise ValueError('taxonomy label violation')
        if case['taxonomy_labels']:
            valid, reason = validate_composition(blueprint, case['taxonomy_labels'])
            if not valid:
                raise ValueError('invalid composition: ' + str(reason))
        validate_phenomenon_realization(case)
        for review in case['reviews']:
            validate_schema(review, review_schema)
        independent = review_count(case)
        if case['safety_critical'] and case['required_independent_reviews'] != 2:
            raise ValueError('safety review requirement weakened')
        if case['trusted'] and independent < case['required_independent_reviews']:
            raise ValueError('unreviewed case marked trusted')
        if case['label_state'] in {'human-reviewed', 'independently-reviewed'} and independent == 0:
            raise ValueError('independent label state lacks independent review')
        if not case['coverage_contributions']:
            raise ValueError('case lacks coverage contribution')
    if len(review_pack) != len(cases):
        raise ValueError('review pack/corpus size mismatch')
    forbidden_keys = {'actual', 'actual_behavior', 'parser_output', 'passed', 'failure_signature', 'desired_parser_change'}
    for row in review_pack:
        if set(row) & forbidden_keys:
            raise ValueError('review pack leaks parser behavior')
    return blueprint_map


def corpus_metrics(families, blueprints, cases, taxonomy):
    lengths = [len(re.findall(r'\w+', case['utterance'])) for case in cases]
    templates = Counter(structural_template(case['utterance']) for case in cases)
    structural_groups = [count for count in templates.values() if count > 1]
    family_counts = Counter(case['semantic_family_id'] for case in cases)
    phenomena_counts = Counter(pid for case in cases for pid in case['taxonomy_labels'])
    interactions = Counter(len(case['taxonomy_labels']) for case in cases)
    pairs = Counter(pair for case in cases for pair in itertools.combinations(case['taxonomy_labels'], 2))
    provenance = Counter(case['provenance'].get('source_dataset', 'repository-authored') for case in cases)
    label_states = Counter(case['label_state'] for case in cases)
    naturalness = Counter(case['naturalness'] for case in cases)
    preservation = Counter(case['meaning_preservation'] for case in cases)
    split_roles = Counter(case['split_role'] for case in cases)
    entity_values = defaultdict(Counter)
    direct_facts = 0
    for case in cases:
        utterance = norm(case['utterance'])
        facts = [fact for item in case['proposed_contract']['items'] for fact in item['facts']]
        if facts and all(norm(fact) in utterance for fact in facts):
            direct_facts += 1
        for item in case['proposed_contract']['items']:
            for field in ('person', 'location', 'date', 'time', 'recurrence'):
                if item.get(field):
                    entity_values[field][str(item[field])] += 1
    safety = [case for case in cases if case['safety_critical']]
    safety_trusted = [case for case in safety if case['trusted'] and review_count(case) >= 2]
    language_lints = language_lint_results(cases)
    taxonomy_ids = {row['id'] for row in taxonomy['phenomena']}
    measured = {
        'corpus_size': len(cases), 'semantic_family_count': len(families),
        'historical_semantic_family_count': sum(bool(family['historical_blueprint_ids']) for family in families),
        'public_introduced_semantic_family_count': sum(not family['historical_blueprint_ids'] for family in families),
        'exact_unique_texts': len({case['utterance'] for case in cases}),
        'word_length': {
            'min': min(lengths), 'p25': statistics.quantiles(lengths, n=4)[0],
            'median': statistics.median(lengths), 'mean': round(statistics.mean(lengths), 3),
            'p75': statistics.quantiles(lengths, n=4)[2], 'max': max(lengths),
        },
        'phenomena_per_case': {str(key): value for key, value in sorted(interactions.items())},
        'average_phenomena_per_case': round(sum(len(case['taxonomy_labels']) for case in cases) / len(cases), 6),
        'single_phenomenon_cases': interactions[1],
        'multi_phenomenon_cases': sum(value for key, value in interactions.items() if key >= 2),
        'multi_phenomenon_rate': round(sum(value for key, value in interactions.items() if key >= 2) / len(cases), 6),
        'phenomenon_coverage': {
            'covered': len(phenomena_counts), 'taxonomy_total': len(taxonomy_ids),
            'uncovered': sorted(taxonomy_ids - set(phenomena_counts)), 'counts': dict(phenomena_counts),
        },
        'interaction_coverage': {'distinct_pairs': len(pairs), 'top_pairs': [{'pair': list(pair), 'count': count} for pair, count in pairs.most_common(20)]},
        'structural_templates': len(templates),
        'structural_near_duplicate_groups': len(structural_groups),
        'structural_near_duplicate_records': sum(structural_groups),
        'largest_structural_template': max(templates.values()),
        'largest_structural_template_share': round(max(templates.values()) / len(cases), 6),
        'top_structural_templates': [{'template': template, 'count': count} for template, count in templates.most_common(10)],
        'family_concentration': {
            'min': min(family_counts.values()), 'median': statistics.median(family_counts.values()),
            'max': max(family_counts.values()), 'largest_share': round(max(family_counts.values()) / len(cases), 6),
        },
        'entity_diversity': {
            field: {'unique': len(values), 'top': [{'value': value, 'count': count} for value, count in values.most_common(10)]}
            for field, values in entity_values.items()
        },
        'fact_copy': {'records_copying_all_facts': direct_facts, 'rate': round(direct_facts / len(cases), 6)},
        'provenance_mix': dict(provenance), 'label_confidence_mix': dict(label_states),
        'naturalness_distribution': {str(score): naturalness[score] for score in range(1, 6)},
        'naturalness_four_or_five_rate': round(sum(naturalness[score] for score in (4, 5)) / len(cases), 6),
        'meaning_preservation': dict(preservation),
        'machine_assessed_preservation_rate': round(preservation['appears_preserved'] / len(cases), 6),
        'broken_or_implausible': sum(naturalness[score] for score in (1, 2)),
        'machine_assessed_broken_rate': round(sum(naturalness[score] for score in (1, 2)) / len(cases), 6),
        'automated_language_lints': {
            'findings': len(language_lints),
            'affected_cases': len({finding['case_id'] for finding in language_lints}),
            'by_lint': dict(Counter(finding['lint_id'] for finding in language_lints)),
        },
        'split_roles': dict(split_roles),
        'safety': {
            'cases': len(safety), 'trusted_with_two_independent_reviews': len(safety_trusted),
            'awaiting_two_independent_reviews': len(safety) - len(safety_trusted),
        },
    }
    measured.update(pair_metrics(cases))
    return measured


def saturation(cases, checkpoints=(100, 200, 400, 600, 800)):
    snapshots = []
    previous_units = set()
    previous_n = 0
    for n in [point for point in checkpoints if point <= len(cases)] + ([len(cases)] if len(cases) not in checkpoints else []):
        prefix = cases[:n]
        units = set()
        for case in prefix:
            units.add('family:' + case['semantic_family_id'])
            units.add('template:' + structural_template(case['utterance']))
            units.update('phenomenon:' + pid for pid in case['taxonomy_labels'])
            units.update('pair:' + '|'.join(pair) for pair in itertools.combinations(case['taxonomy_labels'], 2))
            expected = case['proposed_contract']
            units.add(f'shape:items={expected["item_count"]}:policy={expected["ambiguity_policy"]}')
        new_units = units - previous_units
        delta_cases = n - previous_n
        snapshots.append({
            'cases': n, 'coverage_units': len(units), 'new_units_since_previous': len(new_units),
            'marginal_units_per_case': round(len(new_units) / delta_cases, 6),
            'semantic_families': len({case['semantic_family_id'] for case in prefix}),
            'phenomena': len({pid for case in prefix for pid in case['taxonomy_labels']}),
            'interactions': len({pair for case in prefix for pair in itertools.combinations(case['taxonomy_labels'], 2)}),
            'structural_templates': len({structural_template(case['utterance']) for case in prefix}),
        })
        previous_units, previous_n = units, n
    return snapshots


def gates(metrics, snapshots):
    checks = {
        'exact_unique': metrics['exact_unique_texts'] == metrics['corpus_size'],
        'normalized_duplicates_zero': metrics['normalized_duplicate_records'] == 0,
        'near_duplicate_rate_below_original_20_4_percent': metrics['lexical_near_duplicate_record_rate'] < .204,
        'largest_template_below_original_7_7_percent': metrics['largest_structural_template_share'] < .077,
        'fact_copy_substantially_below_original_96_9_percent': metrics['fact_copy']['rate'] < .50,
        'machine_naturalness_majority_four_or_five': metrics['naturalness_four_or_five_rate'] > .50,
        'machine_broken_rate_below_five_percent': metrics['machine_assessed_broken_rate'] < .05,
        'automated_language_lints_zero': metrics['automated_language_lints']['findings'] == 0,
        'machine_preservation_at_least_95_percent': metrics['machine_assessed_preservation_rate'] >= .95,
        'safety_has_two_independent_reviews': metrics['safety']['awaiting_two_independent_reviews'] == 0,
        'independent_semantic_review_exists': metrics['label_confidence_mix'].get('independently-reviewed', 0) + metrics['label_confidence_mix'].get('human-reviewed', 0) > 0,
        'provenance_has_all_four_public_sources': all(source in metrics['provenance_mix'] for source in ('PRESTO', 'MASSIVE', 'Taskmaster', 'SLURP-text')),
        'intentional_multi_phenomenon_coverage': metrics['multi_phenomenon_cases'] >= 300,
        'saturation_measured_through_800': any(snapshot['cases'] == 800 for snapshot in snapshots),
    }
    freeze = all(checks.values())
    return {
        'checks': checks, 'passed': sum(checks.values()), 'total': len(checks),
        'ready_to_freeze': freeze, 'ready_to_scale_to_10000': freeze,
        'decision': 'freeze permitted' if freeze else 'remain below 1,000; independent adjudication and failed gates remain',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase2', type=Path, default=LAB / 'phase2')
    args = parser.parse_args()
    families = list(read_jsonl(args.phase2 / 'data' / 'semantic-families.jsonl'))
    blueprints = list(read_jsonl(args.phase2 / 'data' / 'blueprints.jsonl'))
    renderings = list(read_jsonl(args.phase2 / 'data' / 'renderings.jsonl'))
    cases = list(read_jsonl(args.phase2 / 'data' / 'cases.jsonl'))
    taxonomy = json.loads((LAB / 'config' / 'taxonomy-v2.json').read_text())
    review_pack = list(read_jsonl(args.phase2 / 'review' / 'independent-review-pack.jsonl'))
    validate_all(families, blueprints, renderings, cases, taxonomy, review_pack)
    metrics = corpus_metrics(families, blueprints, cases, taxonomy)
    snapshots = saturation(cases)
    result = {
        'methodology': {
            'parser_output_used_as_label': False, 'production_parser_invoked': False,
            'sealed_cases_read': 0, 'naturalness_ratings_are_independent': False,
            'semantic_reviews_are_independent': False,
            'near_duplicate_definition': 'token-set Jaccard >= 0.80 after Unicode-aware tokenization',
            'structural_template_definition': 'function words and punctuation retained; adjacent content words collapsed to <slot>',
        },
        'metrics': metrics, 'saturation': snapshots,
    }
    result['success_gate'] = gates(metrics, snapshots)
    write_json(args.phase2 / 'artifacts' / 'quality-report.json', result)
    write_json(args.phase2 / 'artifacts' / 'saturation.json', {'snapshots': snapshots})
    write_json(args.phase2 / 'artifacts' / 'split-manifest.json', {
        'frozen': result['success_gate']['ready_to_freeze'],
        'reason': result['success_gate']['decision'],
        'roles': metrics['split_roles'],
        'independent_evaluation_cases': metrics['split_roles'].get('independent-evaluation', 0),
        'parser_results_included': False,
        'sealed_content_included': False,
    })
    print(json.dumps({'cases': len(cases), 'metrics': metrics, 'success_gate': result['success_gate']}, indent=2))


if __name__ == '__main__':
    main()
