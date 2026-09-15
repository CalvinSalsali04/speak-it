#!/usr/bin/env python3
"""Classify every independently observed SpeechLab quality problem."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))

from Sources.contracts import read_jsonl, write_json, write_jsonl


ROOT_CAUSES = (
    'unnatural wording', 'broken grammar', 'benchmark-like language',
    'transformation changed meaning', 'incorrect semantic contract',
    'ambiguous semantic contract', 'invalid phenomenon composition',
    'cancellation-scope ambiguity', 'negation-scope ambiguity',
    'temporal contradiction', 'reference/pronoun ambiguity',
    'bad shared context', 'bad ASR/noise mutation', 'taxonomy mismatch',
    'public-derived mapping issue', 'entity/value mismatch',
    'reviewer disagreement with legitimate ambiguity',
    'reviewer disagreement caused by bad instructions', 'other',
)

DISPOSITIONS = {
    'A': 'keep unchanged',
    'B': 'repair rendering',
    'C': 'repair contract',
    'D': 'repair taxonomy/phenomenon metadata',
    'E': 'move to ambiguity/challenge',
    'F': 'remove',
    'G': 'defer because representation is insufficient',
}


def ids(*values):
    return set(values)


RECEIPT_VALUE = ids(
    'case-7f6be5608be2e206b2240779', 'case-f28b3be579752eab3d1d86aa',
)
SIDE_ENTRANCE_VALUE = ids(
    'case-58edb0035294595df18e9154', 'case-e6da41181f547673a5e04b83',
    'case-487febdd4f1783cbfaebf3d2', 'case-756f8be625d7dd89dcf1dba2',
    'case-28754f6747c5e35346b641de', 'case-8ae43addd60ccdb34227079c',
)
INTOLERANCE_VALUE = ids(
    'case-505a744df1211e4b92fd2347', 'case-afdb9144698a32bc5c253bbc',
    'case-22c7bba843b7082959c296a9', 'case-54abc8ab3fb3e4b53554ddc5',
)
PERMISSION_VALUE = ids(
    'case-f0614774c45dceedadcb2d8a', 'case-530ac2d9335ce558c25dc3d2',
    'case-37c69b9d977554df4d471a2b', 'case-1b3bea9c1190d5d391adb13f',
)
TEMPORAL_CONTRADICTIONS = ids(
    'case-1c755b9e2667964b1c0a3862', 'case-abff9023022199585b4e1a29',
    'case-0c4a73ebd9c01c18ee521a18', 'case-09f9989e5f6f8f66fffd6204',
    'case-0c8b3d03d71d09c30c7bd20e', 'case-2d128b38de38bc9459e19e2d',
    'case-ed1ba4914f5489b597eb4dfa',
)
REFERENCE_CHALLENGES = ids(
    'case-55e360569d058267c6374751', 'case-f455dac339c1d4353593e627',
    'case-65ae5d91892c246bd2bf8b6a',
)
ASR_REPAIRS = ids(
    'case-dbeec01900af09ee8699edba', 'case-e8382e71eefaf320e5cff828',
    'case-e7041f278fa1b89a944c7e10', 'case-01f44faad05c8b39391470aa',
)
LEGITIMATE_CHALLENGES = ids(
    'case-f6cc7f7abfc5cc78bcbc005d', 'case-099dc2c219ee636b03dcfc7e',
    'case-529d4526bb942a551b963b58',
)
TIMEZONE_INSTRUCTION = ids('case-1d491885557d06d2f46ae4ff')
PUBLIC_CHALLENGES = ids(
    'case-3515b3ffc6adb07b08740895', 'case-bb73192576a7d82f8fbbd96c',
    'case-20aa2d011a5bf71f6de53e8d', 'case-ee6c2a4674e03522c0e7c669',
    'case-2b4a93727b7debb3658b2f53', 'case-f2ac18aaf73ae694b283c575',
    'case-fd24dca378fd422d4520c858',
)
PUBLIC_CONTRACT_REPAIRS = ids(
    'case-168bd5d1515691ecead7dfed', 'case-d77755a30981f2dd838e4a15',
    'case-b641e05b0113451509f4dd27', 'case-df3ab653978df237b3157609',
    'case-6fa4122f635e49c2c242532d', 'case-7c2275d97df8e78a8d280e35',
    'case-6b5890c99cfdb6d09ae70257',
)
REPRESENTATION_GAPS = ids(
    'case-cda5032cf127eafe3e2eed53', 'case-c4ece8a922849a44c8cd946a',
)


def is_positive(review):
    return (review['independence'] == 'independent'
            and review['proposed_contract_correct'] == 'yes'
            and review['meaning_preservation'] == 'appears_preserved')


def is_problematic(case):
    independent = [
        review for review in case['reviews']
        if review['independence'] == 'independent'
    ]
    return (
        case['naturalness'] <= 2
        or case['meaning_preservation'] != 'appears_preserved'
        or case['label_state'] in {'disputed', 'rejected'}
        or any(review['proposed_contract_correct'] != 'yes' for review in independent)
        or any(review['meaning_preservation'] != 'appears_preserved' for review in independent)
        or (case['safety_critical'] and sum(map(is_positive, independent)) < 2)
    )


def independent_evidence(case):
    notes = []
    for review in case['reviews']:
        if review['independence'] != 'independent':
            continue
        adverse = (review['proposed_contract_correct'] != 'yes'
                   or review['meaning_preservation'] != 'appears_preserved')
        if adverse and review['notes'] not in notes:
            notes.append(review['notes'])
    if notes:
        return ' | '.join(notes)
    return (
        f'Independent reviewers assigned a conservative naturalness score of '
        f'{case["naturalness"]}/5.'
    )


def disputed_classification(case):
    case_id = case['case_id']
    if case_id in RECEIPT_VALUE | SIDE_ENTRANCE_VALUE | PERMISSION_VALUE:
        # These are repository-authored paraphrase pairs. Preserve the existing
        # semantic family and repair the divergent spoken rendering.
        return ['transformation changed meaning', 'entity/value mismatch'], 'B'
    if case_id in INTOLERANCE_VALUE:
        causes = ['transformation changed meaning']
        if case_id == 'case-22c7bba843b7082959c296a9':
            causes.insert(0, 'bad ASR/noise mutation')
        return causes, 'B'
    if case_id in TEMPORAL_CONTRADICTIONS:
        causes = ['temporal contradiction', 'invalid phenomenon composition']
        if case['naturalness'] <= 2:
            causes.insert(0, 'unnatural wording')
        return causes, 'B'
    if case_id in REFERENCE_CHALLENGES:
        return [
            'reference/pronoun ambiguity', 'bad shared context',
            'incorrect semantic contract',
        ], 'E'
    if case_id in ASR_REPAIRS:
        causes = ['bad ASR/noise mutation']
        if case_id in {'case-e8382e71eefaf320e5cff828'}:
            causes.append('entity/value mismatch')
        elif case_id in {'case-e7041f278fa1b89a944c7e10'}:
            causes.append('incorrect semantic contract')
        elif case_id in {'case-01f44faad05c8b39391470aa'}:
            causes.append('transformation changed meaning')
        else:
            causes.append('ambiguous semantic contract')
        return causes, 'B'
    if case_id in LEGITIMATE_CHALLENGES:
        causes = ['ambiguous semantic contract', 'reviewer disagreement with legitimate ambiguity']
        if case_id == 'case-099dc2c219ee636b03dcfc7e':
            causes.insert(0, 'bad ASR/noise mutation')
        return causes, 'E'
    if case_id in TIMEZONE_INSTRUCTION:
        return ['reviewer disagreement caused by bad instructions'], 'A'
    if case_id in PUBLIC_CHALLENGES:
        causes = ['ambiguous semantic contract', 'public-derived mapping issue']
        if case_id == 'case-3515b3ffc6adb07b08740895':
            causes = [
                'negation-scope ambiguity',
                'reviewer disagreement with legitimate ambiguity',
                'public-derived mapping issue',
            ]
        elif case_id == 'case-bb73192576a7d82f8fbbd96c':
            causes = [
                'ambiguous semantic contract', 'unnatural wording',
                'reviewer disagreement with legitimate ambiguity',
                'public-derived mapping issue',
            ]
        elif case_id in {
            'case-ee6c2a4674e03522c0e7c669', 'case-2b4a93727b7debb3658b2f53',
        }:
            causes.insert(1, 'reviewer disagreement with legitimate ambiguity')
        elif case_id == 'case-f2ac18aaf73ae694b283c575':
            causes = [
                'cancellation-scope ambiguity',
                'reviewer disagreement with legitimate ambiguity',
                'public-derived mapping issue',
            ]
        elif case_id == 'case-fd24dca378fd422d4520c858':
            causes.insert(0, 'bad shared context')
        return causes, 'E'
    if case_id in PUBLIC_CONTRACT_REPAIRS:
        causes = ['incorrect semantic contract', 'public-derived mapping issue']
        if case_id == 'case-168bd5d1515691ecead7dfed':
            causes.insert(0, 'entity/value mismatch')
        elif case_id == 'case-b641e05b0113451509f4dd27':
            causes.insert(0, 'broken grammar')
        return causes, 'C'
    if case_id in REPRESENTATION_GAPS:
        return ['public-derived mapping issue', 'other'], 'G'
    raise ValueError(f'unclassified disputed case: {case_id}')


def naturalness_classification(case):
    labels = set(case['taxonomy_labels'])
    causes = ['unnatural wording']
    if labels & {
        'long-capture', 'rambling-introduction', 'rambling-ending', 'rephrasing',
        'numbered-list', 'unnumbered-list', 'multiple-tasks', 'multiple-thoughts',
    } or len(case['utterance'].split()) > 30:
        causes.append('benchmark-like language')
    if labels & {
        'casual-grammar', 'punctuation-loss', 'punctuation-corruption',
        'asr-duplicated-token', 'asr-insertion', 'asr-boundary-error',
        'incomplete-clause', 'partial-thought',
    }:
        causes.append('broken grammar')
    if any(label.startswith('asr-') for label in labels):
        causes.append('bad ASR/noise mutation')
    if len(labels) >= 3:
        causes.append('invalid phenomenon composition')
    return causes, 'B'


def build(cases):
    rows = []
    for case in cases:
        if not is_problematic(case):
            continue
        if case['label_state'] == 'disputed':
            causes, disposition = disputed_classification(case)
        else:
            causes, disposition = naturalness_classification(case)
        if not set(causes) <= set(ROOT_CAUSES):
            raise ValueError(f'unknown root cause for {case["case_id"]}')
        rows.append({
            'case_id': case['case_id'],
            'root_causes': causes,
            'disposition': disposition,
            'disposition_name': DISPOSITIONS[disposition],
            'explanation': independent_evidence(case),
            'utterance': case['utterance'],
            'safety_critical': case['safety_critical'],
            'split_role_before': case['split_role'],
            'taxonomy_labels': case['taxonomy_labels'],
        })
    if len(rows) != 134:
        raise ValueError(f'expected 134 problematic cases, found {len(rows)}')
    return rows


def summarize(cases, rows):
    root_counts = Counter(cause for row in rows for cause in row['root_causes'])
    disposition_counts = Counter(row['disposition'] for row in rows)
    examples = defaultdict(list)
    for row in rows:
        for cause in row['root_causes']:
            if len(examples[cause]) < 3:
                examples[cause].append({
                    'case_id': row['case_id'], 'utterance': row['utterance'],
                    'explanation': row['explanation'],
                })
    return {
        'methodology': {
            'starting_corpus_size': len(cases),
            'problematic_cases': len(rows),
            'production_parser_invoked': False,
            'parser_output_read': False,
            'sealed_failures_read': 0,
            'root_cause_counts_are_multi_label': True,
        },
        'supported_root_causes': list(ROOT_CAUSES),
        'supported_dispositions': DISPOSITIONS,
        'root_cause_distribution': {
            cause: root_counts[cause] for cause in ROOT_CAUSES
        },
        'disposition_distribution': {
            code: disposition_counts[code] for code in DISPOSITIONS
        },
        'safety_problematic_cases': sum(row['safety_critical'] for row in rows),
        'representative_examples': dict(examples),
    }


def challenge_records(cases, rows):
    case_by_id = {case['case_id']: case for case in cases}
    records = []
    for row in rows:
        if row['disposition'] != 'E':
            continue
        case = case_by_id[row['case_id']]
        records.append({
            'case_id': case['case_id'],
            'utterance': case['utterance'],
            'relevant_context': case['context'],
            'current_proposed_contract': case['proposed_contract'],
            'taxonomy_labels': case['taxonomy_labels'],
            'root_causes': row['root_causes'],
            'ambiguity_evidence': row['explanation'],
            'evaluation_policy': {
                'role': 'ambiguity-challenge',
                'exact_answer_scoreable': False,
                'scoring': 'explicit-review-required',
                'acceptable_outcomes_status': 'not-yet-adjudicated',
            },
        })
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--cases', type=Path,
        default=LAB / 'phase2' / 'adjudication' / 'cases-adjudicated.jsonl',
    )
    parser.add_argument(
        '--output-dir', type=Path, default=LAB / 'phase2' / 'repair',
    )
    args = parser.parse_args()
    cases = list(read_jsonl(args.cases))
    rows = build(cases)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_jsonl(args.output_dir / 'triage.jsonl', rows)
    write_json(args.output_dir / 'triage-report.json', summarize(cases, rows))
    write_jsonl(args.output_dir / 'challenge-candidates.jsonl', challenge_records(cases, rows))
    write_jsonl(
        args.output_dir / 'representation-deferred.jsonl',
        [row for row in rows if row['disposition'] == 'G'],
    )
    print(json.dumps({
        'problematic_cases': len(rows),
        'dispositions': dict(Counter(row['disposition'] for row in rows)),
        'production_parser_invoked': False,
    }, indent=2))


if __name__ == '__main__':
    main()
