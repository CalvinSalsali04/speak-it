"""Hierarchical SpeechLab taxonomy with stable legacy-ID mappings."""
from __future__ import annotations

import json
from pathlib import Path

from .contracts import HOME, VERSION, write_json


CATEGORIES = {
    'semantic-state': {
        'name': 'Semantic state',
        'description': 'What the speaker ultimately means the product to retain or act on.',
        'members': [
            'negation', 'prohibition', 'cancellation', 'change-of-intent', 'uncertainty',
            'conditional-intent', 'completed-action', 'outstanding-obligation', 'past-event',
            'future-intention', 'resolved-alternative', 'unresolved-alternative',
        ],
    },
    'discourse-structure': {
        'name': 'Discourse structure',
        'description': 'How one or more thoughts are arranged in the capture.',
        'members': [
            'multiple-thoughts', 'multiple-tasks', 'numbered-list', 'unnumbered-list',
            'sequencing', 'conjunction-ambiguity', 'shared-subject', 'shared-object',
            'abandoned-thought', 'rambling-introduction', 'rambling-ending',
            'sign-off-trailing-noise', 'question-mixed-with-action',
            'information-mixed-with-action', 'reported-speech', 'quoted-speech',
        ],
    },
    'repair-deliberation': {
        'name': 'Repair and deliberation',
        'description': 'How a speaker revises, replaces, withdraws, or weighs an expression.',
        'members': [
            'false-start', 'restart', 'self-correction-person', 'self-correction-date',
            'self-correction-time', 'self-correction-quantity', 'self-correction-location',
            'rephrasing', 'never-mind-withdrawal', 'correction-chain', 'scoped-withdrawal',
            'resolved-alternative', 'unresolved-alternative',
        ],
    },
    'surface-speech': {
        'name': 'Surface speech',
        'description': 'Meaning-neutral or locally incomplete properties of spontaneous speech.',
        'members': [
            'filler-words', 'hesitation', 'repetition', 'stutter-like-repetition',
            'casual-grammar', 'incomplete-clause', 'discourse-marker', 'partial-thought',
            'long-capture', 'short-fragment', 'code-switch-token',
        ],
    },
    'asr-transcription': {
        'name': 'ASR and transcription',
        'description': 'Observed transcript effects, distinct from authored speech behavior.',
        'members': [
            'lowercase', 'punctuation-loss', 'punctuation-corruption', 'casing-corruption',
            'asr-substitution', 'asr-deletion', 'asr-insertion', 'homophone',
            'asr-name-corruption', 'asr-boundary-error', 'asr-partial-recognition',
            'asr-duplicated-token', 'asr-dropped-token',
        ],
    },
    'contextual-product': {
        'name': 'Contextual and product',
        'description': 'Resolution behavior that depends on time, place, people, or product context.',
        'members': [
            'shared-date', 'shared-time', 'shared-location', 'temporal-inheritance',
            'location-inheritance', 'pronoun-resolution', 'ambiguous-pronoun',
            'exact-time', 'relative-date', 'relative-duration', 'recurrence',
            'uncommon-proper-noun', 'ordinary-word-name', 'store-brand-product-name',
            'cross-turn-reference', 'cross-turn-reference-ambiguity',
            'contact-person-ambiguity', 'timezone-sensitive', 'dst-transition',
            'cancellation-scope',
        ],
    },
}


NEW_PHENOMENA = {
    'correction-chain': ('Repair chain', 'Two or more explicit repairs resolve to one final value.', True, 'high'),
    'scoped-withdrawal': ('Scoped withdrawal', 'One candidate intent is explicitly withdrawn while another remains.', False, 'high'),
    'resolved-alternative': ('Resolved alternative', 'Alternatives are stated and one is explicitly selected.', False, 'high'),
    'unresolved-alternative': ('Unresolved alternative', 'Multiple live alternatives remain and must not be silently resolved.', False, 'high'),
    'stutter-like-repetition': ('Stutter-like repetition', 'A short sound or token onset repeats without adding meaning.', True, 'normal'),
    'casual-grammar': ('Casual grammar', 'Colloquial grammar occurs without changing the intended contract.', True, 'normal'),
    'incomplete-clause': ('Incomplete clause', 'A locally incomplete clause is interpretable from explicit context.', False, 'high'),
    'discourse-marker': ('Discourse marker', 'A marker such as “anyway” or “so” organizes the capture.', True, 'normal'),
    'cross-turn-reference': ('Cross-turn reference', 'A phrase intentionally resolves to a unique prior-turn referent.', False, 'high'),
    'cross-turn-reference-ambiguity': ('Cross-turn reference ambiguity', 'A phrase has multiple plausible prior-turn referents.', False, 'high'),
    'contact-person-ambiguity': ('Contact/person ambiguity', 'A name or relationship matches multiple plausible people.', False, 'high'),
    'timezone-sensitive': ('Timezone-sensitive language', 'The intended time depends on an explicit timezone or travel context.', False, 'high'),
    'dst-transition': ('DST transition', 'A local time lies near a daylight-saving transition and requires review.', False, 'high'),
    'asr-name-corruption': ('ASR name corruption', 'A person or proper name is transcribed incorrectly.', False, 'high'),
    'asr-boundary-error': ('ASR boundary error', 'Clause or item boundaries are lost or inserted.', False, 'normal'),
    'asr-partial-recognition': ('ASR partial recognition', 'Only part of the spoken capture is recognized.', False, 'high'),
    'asr-duplicated-token': ('ASR duplicated token', 'The transcript contains an accidental duplicate token.', True, 'normal'),
    'asr-dropped-token': ('ASR dropped token', 'The transcript omits a spoken token.', False, 'high'),
    'cancellation-scope': ('Cancellation scope', 'A cancellation targets one explicit item or a stated set of items.', False, 'high'),
}


ALIASES = {
    'self-correction': 'change-of-intent',
    'value-correction': 'change-of-intent',
    'capitalization-loss': 'lowercase',
    'name-corruption': 'asr-name-corruption',
    'boundary-errors': 'asr-boundary-error',
    'partial-recognition': 'asr-partial-recognition',
    'duplicated-token': 'asr-duplicated-token',
    'dropped-token': 'asr-dropped-token',
    'asr-token-deletion': 'asr-deletion',
    'person-ambiguity': 'contact-person-ambiguity',
}


SEMANTIC_STATES = {
    'intent_kind': ['action', 'memory', 'idea', 'person-fact', 'location-related-intent', 'temporal-intent'],
    'operation': ['none', 'cancellation'],
    'polarity': ['positive', 'negation', 'prohibition'],
    'certainty': ['resolved', 'uncertain', 'resolved-alternative', 'unresolved-alternative'],
}


def build_taxonomy(output: Path | None = None):
    legacy = json.loads((HOME / 'config' / 'phenomena.json').read_text())['phenomena']
    old_by_id = {row['id']: row for row in legacy}
    primary = {}
    for category, definition in CATEGORIES.items():
        for phenomenon_id in definition['members']:
            primary.setdefault(phenomenon_id, category)

    rows = []
    for phenomenon_id in sorted(set(old_by_id) | set(NEW_PHENOMENA)):
        if phenomenon_id in old_by_id:
            old = old_by_id[phenomenon_id]
            name = old['name']
            definition = old['definition']
            preserves = old['preserves_meaning']
            safety = old['safety_level']
            legacy_ids = [phenomenon_id]
        else:
            name, definition, preserves, safety = NEW_PHENOMENA[phenomenon_id]
            legacy_ids = []
        categories = [category for category, value in CATEGORIES.items() if phenomenon_id in value['members']]
        rows.append({
            'id': phenomenon_id,
            'name': name,
            'definition': definition,
            'primary_category': primary[phenomenon_id],
            'secondary_categories': [category for category in categories if category != primary[phenomenon_id]],
            'preserves_meaning_by_default': preserves,
            'safety_level': safety,
            'legacy_ids': legacy_ids,
            'aliases': sorted(alias for alias, canonical in ALIASES.items() if canonical == phenomenon_id),
        })

    result = {
        'version': 'speechlab-taxonomy-2',
        'historical_taxonomy_version': VERSION,
        'semantic_states': SEMANTIC_STATES,
        'categories': [dict(id=category, **{k: v for k, v in value.items() if k != 'members'}) for category, value in CATEGORIES.items()],
        'phenomena': rows,
        'legacy_id_map': {phenomenon_id: phenomenon_id for phenomenon_id in old_by_id},
        'alias_map': ALIASES,
        'compatibility_note': 'All 64 speechlab-1 IDs remain canonical and readable; aliases are input-only mappings.',
    }
    if output is not None:
        write_json(output, result)
    return result


if __name__ == '__main__':
    build_taxonomy(HOME / 'config' / 'taxonomy-v2.json')
