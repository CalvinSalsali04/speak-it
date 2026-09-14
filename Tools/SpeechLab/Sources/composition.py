"""Constrained, coverage-guided SpeechLab composition.

The engine exposes explicit recipes and compatibility checks. It never forms a
Cartesian product of taxonomy labels and never treats a surface mutation as a
semantic oracle.
"""
from __future__ import annotations

from dataclasses import dataclass
import itertools
import re

from .contracts import digest, norm


@dataclass(frozen=True)
class Transform:
    phenomenon_id: str
    category: str
    order: int
    destructive: bool = False


TRANSFORMS = {
    # Semantic/context labels describe meaning already present in the blueprint.
    **{pid: Transform(pid, 'semantic-state', 1, pid in {
        'cancellation', 'change-of-intent', 'conditional-intent', 'resolved-alternative',
        'unresolved-alternative', 'scoped-withdrawal', 'never-mind-withdrawal',
    }) for pid in [
        'negation', 'prohibition', 'cancellation', 'change-of-intent', 'uncertainty',
        'conditional-intent', 'completed-action', 'outstanding-obligation', 'past-event',
        'future-intention', 'resolved-alternative', 'unresolved-alternative',
        'never-mind-withdrawal', 'scoped-withdrawal',
    ]},
    **{pid: Transform(pid, 'contextual-product', 2, pid in {
        'ambiguous-pronoun', 'cross-turn-reference-ambiguity', 'contact-person-ambiguity',
        'timezone-sensitive', 'dst-transition', 'cancellation-scope',
    }) for pid in [
        'shared-date', 'shared-time', 'shared-location', 'temporal-inheritance',
        'location-inheritance', 'pronoun-resolution', 'ambiguous-pronoun', 'exact-time',
        'relative-date', 'relative-duration', 'recurrence', 'uncommon-proper-noun',
        'ordinary-word-name', 'store-brand-product-name', 'cross-turn-reference',
        'cross-turn-reference-ambiguity', 'contact-person-ambiguity', 'timezone-sensitive',
        'dst-transition', 'cancellation-scope',
    ]},
    **{pid: Transform(pid, 'discourse-structure', 2, pid in {
        'conjunction-ambiguity', 'reported-speech', 'quoted-speech', 'abandoned-thought',
    }) for pid in [
        'multiple-thoughts', 'multiple-tasks', 'numbered-list', 'unnumbered-list',
        'sequencing', 'conjunction-ambiguity', 'shared-subject', 'shared-object',
        'abandoned-thought', 'reported-speech', 'quoted-speech',
        'question-mixed-with-action', 'information-mixed-with-action',
    ]},
    **{pid: Transform(pid, 'repair-deliberation', 3, pid in {
        'resolved-alternative', 'unresolved-alternative', 'scoped-withdrawal',
        'never-mind-withdrawal',
    }) for pid in [
        'false-start', 'restart', 'self-correction-person', 'self-correction-date',
        'self-correction-time', 'self-correction-quantity', 'self-correction-location',
        'rephrasing', 'correction-chain',
    ]},
    **{pid: Transform(pid, 'surface-speech', 4, pid in {'incomplete-clause', 'partial-thought'}) for pid in [
        'filler-words', 'hesitation', 'repetition', 'stutter-like-repetition',
        'casual-grammar', 'incomplete-clause', 'discourse-marker', 'partial-thought',
        'long-capture', 'short-fragment', 'code-switch-token', 'rambling-introduction',
        'rambling-ending', 'sign-off-trailing-noise',
    ]},
    **{pid: Transform(pid, 'asr-transcription', 5, pid in {
        'asr-substitution', 'asr-deletion', 'homophone', 'asr-name-corruption',
        'asr-partial-recognition', 'asr-dropped-token',
    }) for pid in [
        'lowercase', 'punctuation-loss', 'punctuation-corruption', 'casing-corruption',
        'asr-substitution', 'asr-deletion', 'asr-insertion', 'homophone',
        'asr-name-corruption', 'asr-boundary-error', 'asr-partial-recognition',
        'asr-duplicated-token', 'asr-dropped-token',
    ]},
}


STRUCTURAL = [
    'multiple-thoughts', 'multiple-tasks', 'numbered-list', 'unnumbered-list',
    'sequencing', 'shared-subject', 'shared-date', 'shared-time', 'shared-location',
    'temporal-inheritance', 'location-inheritance', 'question-mixed-with-action',
    'information-mixed-with-action',
]
REPAIR = [
    'false-start', 'restart', 'self-correction-person', 'self-correction-date',
    'self-correction-time', 'self-correction-location', 'rephrasing',
    'correction-chain', 'scoped-withdrawal', 'resolved-alternative',
]
DISCOURSE = [
    'filler-words', 'hesitation', 'repetition', 'stutter-like-repetition',
    'casual-grammar', 'discourse-marker', 'rambling-introduction', 'rambling-ending',
    'sign-off-trailing-noise', 'long-capture', 'code-switch-token',
]
ASR_SAFE = ['lowercase', 'punctuation-loss', 'casing-corruption', 'asr-insertion', 'asr-boundary-error', 'asr-duplicated-token']
ASR_LOSSY = ['asr-substitution', 'asr-deletion', 'homophone', 'asr-name-corruption', 'asr-partial-recognition', 'asr-dropped-token']


def _items(blueprint):
    return blueprint['expected']['items']


def _has(blueprint, field):
    return any(item.get(field) not in (None, False, '') for item in _items(blueprint))


def _strip_qualified_context(surface, *values):
    """Remove already-rendered shared values before lifting them into a clause."""
    text = surface
    for value in sorted((str(value) for value in values if value), key=len, reverse=True):
        forms = (
            f' when I am at {value}', f' while I am at {value}',
            f' on {value}', f' at {value}', f' {value}',
        )
        for form in forms:
            if form in text:
                text = text.replace(form, '', 1)
                break
    return re.sub(r'\s+', ' ', text).strip(' ,;')


def _date_lead(date):
    value = str(date)
    if value.startswith(('tomorrow', 'next ', 'this ', 'two ', 'three ', 'yesterday', 'last ', 'earlier ', 'the previous ', 'the morning ')):
        return value.capitalize()
    return 'On ' + value


def compatible(blueprint, phenomenon_id):
    """Return whether one phenomenon is meaningful for this semantic contract."""
    e = blueprint['expected']
    items = e['items']
    count = e['item_count']
    operations = e['operations']
    policy = e['ambiguity_policy']
    if phenomenon_id not in TRANSFORMS:
        return False
    if phenomenon_id in {'multiple-thoughts', 'numbered-list'}:
        return count >= 2
    if phenomenon_id in {'multiple-tasks', 'unnumbered-list', 'sequencing', 'shared-subject'}:
        return count >= 2 and all(item['route'] == 'Today' for item in items)
    if phenomenon_id == 'shared-object':
        return count >= 2 and len({item['facts'][0] for item in items if item['facts']}) == 1
    if phenomenon_id in {'shared-date', 'temporal-inheritance'}:
        return count >= 2 and all(item['route'] == 'Today' for item in items) and e['shared_context']['temporal'] is not None
    if phenomenon_id == 'shared-time':
        times = {item['time'] for item in items}
        dates = {item['date'] for item in items if item['date'] is not None}
        return count >= 2 and all(item['route'] == 'Today' for item in items) and None not in times and len(times) == 1 and len(dates) <= 1
    if phenomenon_id in {'shared-location', 'location-inheritance'}:
        return count >= 2 and all(item['route'] == 'Today' for item in items) and e['shared_context']['location'] is not None
    if phenomenon_id in {'question-mixed-with-action', 'information-mixed-with-action'}:
        return count == 2 and {item['route'] for item in items} == {'Today', 'Memory'}
    if phenomenon_id == 'self-correction-person':
        return _has(blueprint, 'person')
    if phenomenon_id == 'pronoun-resolution':
        return _has(blueprint, 'person') and bool(blueprint['capture_context']['prior_turns'])
    if phenomenon_id == 'self-correction-date':
        return _has(blueprint, 'date')
    if phenomenon_id == 'self-correction-time':
        return _has(blueprint, 'time')
    if phenomenon_id == 'self-correction-location':
        return _has(blueprint, 'location')
    if phenomenon_id == 'self-correction-quantity':
        return any(re.search(r'\b\d+\b', fact) for item in items for fact in item['facts'])
    if phenomenon_id == 'correction-chain':
        return any(_has(blueprint, field) for field in ('person', 'date', 'time', 'location'))
    if phenomenon_id in {'scoped-withdrawal', 'never-mind-withdrawal'}:
        return count == 1 and policy == 'act' and not operations
    if phenomenon_id == 'resolved-alternative':
        return count == 1 and policy == 'act' and all(item['route'] == 'Today' and item['type'] != 'event' for item in items)
    if phenomenon_id == 'conditional-intent':
        # The current semantic contract has no condition field. A surface-only
        # condition would invent meaning, so this stays an explicit gap.
        return False
    if phenomenon_id in {'ambiguous-pronoun', 'cross-turn-reference-ambiguity', 'contact-person-ambiguity'}:
        return policy != 'act' and bool(blueprint['capture_context']['prior_turns'])
    if phenomenon_id == 'unresolved-alternative':
        return policy != 'act' and count == 1 and all(item['route'] == 'Today' and item['type'] != 'event' for item in items)
    if phenomenon_id == 'uncertainty':
        return policy != 'act'
    if phenomenon_id == 'cross-turn-reference':
        return bool(blueprint['capture_context']['prior_turns']) and policy == 'act'
    if phenomenon_id in {'negation', 'prohibition'}:
        return any(item['negation'] for item in items) and (phenomenon_id != 'prohibition' or any(item['prohibition'] for item in items))
    if phenomenon_id in {'cancellation', 'cancellation-scope'}:
        return bool(operations) and all(op.get('operation') == 'cancel' for op in operations)
    if phenomenon_id == 'completed-action':
        return any(item['state'] == 'completed' for item in items)
    if phenomenon_id == 'outstanding-obligation':
        return any(item['state'] == 'outstanding' for item in items)
    if phenomenon_id == 'past-event':
        return any(item['state'] == 'completed' for item in items)
    if phenomenon_id == 'future-intention':
        return any(item['state'] == 'outstanding' for item in items)
    if phenomenon_id == 'exact-time':
        return _has(blueprint, 'time')
    if phenomenon_id == 'relative-duration':
        return any(item['date'] and re.search(r'\b(?:from now|ago)\b', str(item['date']), re.I) for item in items)
    if phenomenon_id == 'relative-date':
        return any(item['date'] and not re.search(r'\b(?:September|October|November|December|January|August)\s+\d+\b', str(item['date'])) for item in items)
    if phenomenon_id == 'recurrence':
        return _has(blueprint, 'recurrence')
    if phenomenon_id == 'ordinary-word-name':
        return any(item['person'] and str(item['person']).split()[0] in {'Hope', 'River', 'April', 'Rose', 'Mark'} for item in items)
    if phenomenon_id == 'uncommon-proper-noun':
        return any(item['person'] == 'Wanjiku Njoroge' for item in items)
    if phenomenon_id == 'store-brand-product-name':
        return any('Northstar' in fact for item in items for fact in item['facts'])
    if phenomenon_id == 'homophone':
        return any(re.search(r'\bflour\b', fact, re.I) for item in items for fact in item['facts'])
    if phenomenon_id == 'asr-substitution':
        return any(re.search(r'\bmeeting\b', fact, re.I) for item in items for fact in item['facts'])
    if phenomenon_id == 'asr-name-corruption':
        return _has(blueprint, 'person')
    if phenomenon_id == 'timezone-sensitive':
        return _has(blueprint, 'time') and blueprint['capture_context']['timezone'] != 'America/Toronto'
    if phenomenon_id == 'dst-transition':
        return _has(blueprint, 'time') and all(item['state'] != 'completed' for item in items) and any('clock change' in turn['text'].casefold() for turn in blueprint['capture_context']['prior_turns'])
    if phenomenon_id in {'incomplete-clause', 'partial-thought'}:
        return policy != 'act'
    if phenomenon_id == 'change-of-intent':
        return count == 1 and policy == 'act' and all(item['route'] == 'Today' and item['type'] != 'event' for item in items)
    if phenomenon_id == 'conjunction-ambiguity':
        return count == 2 and policy == 'review'
    if phenomenon_id in {'reported-speech', 'quoted-speech'}:
        return items and all(item['route'] == 'Memory' for item in items)
    return True


def validate_composition(blueprint, phenomenon_ids):
    """Validate ordering, scope, and safety without looking at parser output."""
    ids = list(phenomenon_ids)
    if not 1 <= len(ids) <= 4:
        return False, 'composition must contain one to four phenomena'
    if len(ids) != len(set(ids)):
        return False, 'duplicate phenomenon'
    unknown = set(ids) - set(TRANSFORMS)
    if unknown:
        return False, 'unknown transformation: ' + ','.join(sorted(unknown))
    if any(not compatible(blueprint, pid) for pid in ids):
        return False, 'incompatible semantic contract'
    orders = [TRANSFORMS[pid].order for pid in ids]
    if orders != sorted(orders):
        return False, 'invalid transformation order'
    fields = [pid.rsplit('-', 1)[-1] for pid in ids if pid.startswith('self-correction-')]
    if len(fields) != len(set(fields)):
        return False, 'two corrections target the same field'
    if blueprint['safety_critical'] and any(TRANSFORMS[pid].destructive and TRANSFORMS[pid].order == 5 for pid in ids):
        return False, 'destructive ASR is forbidden for safety-critical meaning'
    if 'ambiguous-pronoun' in ids and blueprint['expected']['ambiguity_policy'] == 'act':
        return False, 'unresolved pronoun cannot silently act'
    if 'cancellation' in ids and not blueprint['capture_context']['stored_items']:
        return False, 'cancellation lacks stored target'
    if any(pid in ids for pid in ('punctuation-loss', 'punctuation-corruption')) and any(
        pid == 'correction-chain' or pid.startswith('self-correction-') for pid in ids
    ):
        return False, 'punctuation noise would erase a repair boundary'
    return True, None


def approved_recipes(blueprint, cardinality):
    """Build a bounded recipe list; this deliberately is not a product."""
    semantic = [pid for pid in TRANSFORMS if TRANSFORMS[pid].order <= 2 and compatible(blueprint, pid)]
    repair = [pid for pid in REPAIR if compatible(blueprint, pid)]
    discourse = [pid for pid in DISCOURSE if compatible(blueprint, pid)]
    asr = [pid for pid in ASR_SAFE + ASR_LOSSY if compatible(blueprint, pid)]
    candidates = []
    if cardinality == 1:
        for pid in semantic + repair + discourse + asr:
            candidates.append((pid,))
    elif cardinality == 2:
        # High-risk and lossy transforms are isolated single-review cases until
        # independent adjudication exists. They do not compound automatically.
        semantic = [pid for pid in semantic if not TRANSFORMS[pid].destructive]
        repair = [pid for pid in repair if not TRANSFORMS[pid].destructive]
        discourse = [pid for pid in discourse if not TRANSFORMS[pid].destructive]
        asr = [pid for pid in ASR_SAFE if compatible(blueprint, pid)]
        lanes = [(semantic, discourse), (semantic, asr), (repair, discourse), (repair, asr), (discourse, asr)]
        for left, right in lanes:
            for index in range(max(len(left), len(right), 0)):
                if left and right:
                    candidates.append(tuple(sorted((left[index % len(left)], right[(index * 5 + 1) % len(right)]), key=lambda p: TRANSFORMS[p].order)))
    else:
        semantic = [pid for pid in semantic if not TRANSFORMS[pid].destructive]
        repair = [pid for pid in repair if not TRANSFORMS[pid].destructive]
        discourse = [pid for pid in discourse if not TRANSFORMS[pid].destructive]
        asr = [pid for pid in ASR_SAFE if compatible(blueprint, pid)]
        lanes = [(semantic, repair, discourse), (semantic, discourse, asr), (repair, discourse, asr)]
        for lane in lanes:
            if all(lane):
                width = max(map(len, lane))
                for index in range(width):
                    recipe = [values[(index * (position * 2 + 1)) % len(values)] for position, values in enumerate(lane)]
                    if cardinality == 4 and asr:
                        recipe.append(asr[(index * 7 + 2) % len(asr)])
                    candidates.append(tuple(sorted(recipe, key=lambda p: TRANSFORMS[p].order)))
    unique = []
    for recipe in candidates:
        if recipe not in unique and validate_composition(blueprint, recipe)[0]:
            unique.append(recipe)
    return unique


class CoverageTracker:
    def __init__(self):
        self.seen = set()

    @staticmethod
    def keys(blueprint, semantic_family_id, phenomenon_ids):
        e = blueprint['expected']
        entity_shape = ':'.join(field for field in ('person', 'location', 'date', 'time', 'recurrence') if any(item.get(field) for item in e['items'])) or 'none'
        keys = {
            f'family:{semantic_family_id}',
            f'shape:items={e["item_count"]}:policy={e["ambiguity_policy"]}:entities={entity_shape}',
            f'cardinality:{len(phenomenon_ids)}',
        }
        keys.update(f'phenomenon:{pid}' for pid in phenomenon_ids)
        keys.update(f'family-phenomenon:{semantic_family_id}:{pid}' for pid in phenomenon_ids)
        keys.update('pair:' + '|'.join(pair) for pair in itertools.combinations(phenomenon_ids, 2))
        if len(phenomenon_ids) >= 3:
            keys.add('interaction:' + '|'.join(phenomenon_ids))
        for item in e['items']:
            for field in ('person', 'location', 'date', 'time', 'recurrence'):
                if item.get(field):
                    keys.add(f'entity:{field}:{norm(str(item[field]))}')
        return keys

    def choose(self, blueprint, semantic_family_id, recipes):
        scored = []
        for recipe in recipes:
            keys = self.keys(blueprint, semantic_family_id, recipe)
            new = keys - self.seen
            weighted = sum(5 if key.startswith(('pair:', 'interaction:')) else 2 if key.startswith('family-phenomenon:') else 1 for key in new)
            scored.append((weighted, digest({'family': semantic_family_id, 'recipe': recipe}), recipe, keys, new))
        if not scored:
            return None
        weighted, _, recipe, keys, new = max(scored)
        if weighted <= 0:
            return None
        self.seen.update(keys)
        return recipe, sorted(new)


def transformation_lineage(phenomenon_ids, discarded_values):
    return [{
        'phenomenon_id': pid,
        'category': TRANSFORMS[pid].category,
        'order': TRANSFORMS[pid].order,
        'discarded_value': discarded_values.get(pid),
    } for pid in phenomenon_ids]


def apply_transformations(base_text, blueprint, item_surfaces, phenomenon_ids, alternates):
    """Render a validated composition and return text plus discarded values."""
    valid, reason = validate_composition(blueprint, phenomenon_ids)
    if not valid:
        raise ValueError(reason)
    text = base_text
    discarded = {}
    e = blueprint['expected']

    for pid in phenomenon_ids:
        if pid == 'change-of-intent' and len(item_surfaces) == 1:
            withdrawn = alternates['withdrawn_action']
            text = f'I was going to {withdrawn}, but actually I need to {item_surfaces[0]} instead.'
            discarded[pid] = withdrawn
        elif pid == 'unresolved-alternative' and len(item_surfaces) == 1:
            withdrawn = alternates['withdrawn_action']
            text = f'I am still deciding whether to {item_surfaces[0]} or {withdrawn}; please do not act on either yet.'
            discarded[pid] = withdrawn
        elif pid == 'numbered-list' and len(item_surfaces) >= 2:
            text = 'Okay, two things: first, ' + item_surfaces[0] + '; second, ' + item_surfaces[1] + '.'
        elif pid == 'unnumbered-list' and len(item_surfaces) >= 2:
            text = 'I need to ' + item_surfaces[0] + ', and also ' + item_surfaces[1] + '.'
        elif pid == 'sequencing' and len(item_surfaces) >= 2:
            text = 'First ' + item_surfaces[0] + '; once that is done, ' + item_surfaces[1] + '.'
        elif pid == 'multiple-thoughts' and len(item_surfaces) >= 2:
            text = item_surfaces[0].capitalize() + '. Oh, and one unrelated thing: ' + item_surfaces[1] + '.'
        elif pid == 'multiple-tasks' and len(item_surfaces) >= 2:
            text = 'I have two things: ' + item_surfaces[0] + ', then ' + item_surfaces[1] + '.'
        elif pid == 'shared-subject' and len(item_surfaces) >= 2:
            text = 'I need to ' + item_surfaces[0] + ' and ' + item_surfaces[1] + '.'
        elif pid == 'shared-date' and len(item_surfaces) >= 2:
            date = next(item['date'] for item in e['items'] if item['date'])
            time = next((item['time'] for item in e['items'] if item['time']), None)
            clean = [_strip_qualified_context(surface, date, time) for surface in item_surfaces]
            lead = _date_lead(date) + (f' at {time}' if time else '')
            text = f'{lead}, I need to {clean[0]} and {clean[1]}.'
        elif pid == 'shared-time' and len(item_surfaces) >= 2:
            item = next(item for item in e['items'] if item['time'])
            clean = [_strip_qualified_context(surface, item['date'], item['time']) for surface in item_surfaces]
            if item['date']:
                date_clause = ' ' + str(item['date']) if str(item['date']).startswith(('tomorrow', 'next ', 'this ', 'two ', 'three ', 'yesterday', 'last ', 'earlier ')) else f' on {item["date"]}'
            else:
                date_clause = ''
            text = f'At {item["time"]}{date_clause}, {clean[0]}, and then {clean[1]}.'
        elif pid == 'shared-location' and len(item_surfaces) >= 2:
            location = next(item['location'] for item in e['items'] if item['location'])
            clean = [_strip_qualified_context(surface, location) for surface in item_surfaces]
            text = f'When I get to {location}, I need to {clean[0]} and {clean[1]}.'
        elif pid == 'temporal-inheritance' and len(item_surfaces) >= 2:
            date = next(item['date'] for item in e['items'] if item['date'])
            time = next((item['time'] for item in e['items'] if item['time']), None)
            clean = [_strip_qualified_context(surface, date, time) for surface in item_surfaces]
            lead = _date_lead(date) + (f' at {time}' if time else '')
            text = f'{lead}, {clean[0]}, and {clean[1]} too.'
        elif pid == 'location-inheritance' and len(item_surfaces) >= 2:
            location = next(item['location'] for item in e['items'] if item['location'])
            clean = [_strip_qualified_context(surface, location) for surface in item_surfaces]
            text = f'At {location}, {clean[0]}, and while I am there, {clean[1]}.'
        elif pid in {'question-mixed-with-action', 'information-mixed-with-action'} and len(item_surfaces) == 2:
            today_index = next(index for index, item in enumerate(e['items']) if item['route'] == 'Today')
            memory_index = 1 - today_index
            action = item_surfaces[today_index]
            detail = item_surfaces[memory_index]
            if pid == 'question-mixed-with-action':
                text = f'Could you remind me to {action}? Also, can you remember this: {detail}?'
            else:
                text = f'One detail to keep is that {detail}. I also need a reminder to {action}.'
        elif pid == 'conjunction-ambiguity' and len(item_surfaces) == 2:
            text = f'I am not sure how this groups: {item_surfaces[0]} and {item_surfaces[1]}. Please keep the wording for review.'
        elif pid == 'pronoun-resolution':
            person = next(item['person'] for item in e['items'] if item['person'])
            if f'{person} mentioned that' in text:
                text = text.replace(f'{person} mentioned that', 'They mentioned that', 1)
            else:
                text = text.replace(person, 'them', 1)
        elif pid in {'ambiguous-pronoun', 'cross-turn-reference-ambiguity', 'contact-person-ambiguity'}:
            if e['items'] and e['items'][0]['route'] == 'Today':
                text = 'Could you remind me about that thing with them? I am not sure which person or item I meant.'
            else:
                text = 'Please save what they said about that, but flag it because the reference is unclear.'
        elif pid == 'cross-turn-reference':
            if e['items'] and e['items'][0]['route'] == 'Today':
                text = 'About that task I mentioned earlier—please remind me about it.'
            else:
                text = 'Please remember that detail I mentioned in the previous message.'
        elif pid == 'timezone-sensitive':
            text = text.rstrip('.?') + f'. Use the time in {blueprint["capture_context"]["timezone"]}.'
        elif pid == 'dst-transition':
            text = text.rstrip('.?') + f'. That is in {blueprint["capture_context"]["timezone"]} during the clock change.'
        elif pid == 'false-start':
            text = 'I was going to ask— wait, ' + text[0].lower() + text[1:]
        elif pid == 'restart':
            text = 'No, let me start that again. ' + text
        elif pid == 'rephrasing':
            text = text.rstrip('.?') + '—basically, I just want that captured.'
        elif pid.startswith('self-correction-'):
            field = pid.removeprefix('self-correction-')
            if field == 'quantity':
                final = re.search(r'\b\d+\b', text)
                if final:
                    old = 'two' if final.group() != '2' else 'three'
                    text = text[:final.start()] + old + '—sorry, ' + final.group() + text[final.end():]
                    discarded[pid] = old
            else:
                final = next(str(item[field]) for item in e['items'] if item.get(field))
                old = next(value for value in (
                    alternates[field], alternates[field + '_second'], alternates[field + '_third']
                ) if value != final)
                if final in text:
                    if field == 'date':
                        matched = False
                        for prefix in (' during ', ' on ', ' starting ', ' '):
                            token = prefix + final
                            if token in text:
                                text = text.replace(token, f' for {old}—sorry, {final}', 1)
                                matched = True
                                break
                        if not matched:
                            text = text.replace(final, old + '—sorry, ' + final, 1)
                    else:
                        text = text.replace(final, old + '—sorry, ' + final, 1)
                else:
                    connector = {'person': ' with ', 'date': ' on ', 'time': ' at ', 'location': ' at '}[field]
                    text = text.rstrip('.?') + connector + old + '—sorry, ' + final + '.'
                discarded[pid] = old
        elif pid == 'correction-chain':
            field = next(field for field in ('person', 'date', 'time', 'location') if _has(blueprint, field))
            final = next(str(item[field]) for item in e['items'] if item.get(field))
            candidates = []
            for value in (alternates[field], alternates[field + '_second'], alternates[field + '_third']):
                if value != final and value not in candidates:
                    candidates.append(value)
            old, older = candidates[:2]
            if field == 'date':
                matched = False
                for prefix in (' during ', ' on ', ' starting ', ' '):
                    token = prefix + final
                    if token in text:
                        text = text.replace(token, f' for {older}—no, {old}—sorry, {final}', 1)
                        matched = True
                        break
                if not matched:
                    text = text.replace(final, older + '—no, ' + old + '—sorry, ' + final, 1)
            else:
                text = text.replace(final, older + '—no, ' + old + '—sorry, ' + final, 1)
            discarded[pid] = older + ' | ' + old
        elif pid in {'scoped-withdrawal', 'never-mind-withdrawal'}:
            withdrawn = alternates['withdrawn_action']
            text = text.rstrip('.?') + f', and {withdrawn}—actually, never mind that last part; just the first thing.'
            discarded[pid] = withdrawn
        elif pid == 'resolved-alternative':
            withdrawn = alternates['withdrawn_action']
            discarded[pid] = withdrawn
            text = f'I was deciding whether to {withdrawn} or {item_surfaces[0]}, but I chose the second one: {item_surfaces[0]}.'
        elif pid == 'filler-words':
            text = 'Uh, ' + text[0].lower() + text[1:]
        elif pid == 'hesitation':
            text = re.sub(r'\b(to|that)\b', r'\1, um,', text, count=1)
        elif pid == 'repetition':
            text = re.sub(r'^([A-Za-z]+)', r'\1, \1', text, count=1)
        elif pid == 'stutter-like-repetition':
            match = re.match(r'^([A-Za-z])([A-Za-z]+)', text)
            if match:
                text = match.group(1) + '-' + match.group(1) + match.group(2) + text[match.end():]
        elif pid == 'casual-grammar':
            text = text.replace('I have to', 'I gotta').replace('I need to', 'I gotta')
        elif pid == 'discourse-marker':
            text = 'Anyway, ' + text[0].lower() + text[1:]
        elif pid == 'rambling-introduction':
            text = 'Okay, so this came up while I was sorting out the rest of the week, and before I lose the thread, ' + text[0].lower() + text[1:]
        elif pid == 'rambling-ending':
            text = text.rstrip('.?') + ', because otherwise it is going to disappear from my head again.'
        elif pid == 'sign-off-trailing-noise':
            text = text.rstrip('.?') + '. Okay, that is everything, thanks.'
        elif pid == 'long-capture':
            text = 'I have been bouncing between a few different things today and none of them are related, but the one bit I actually need to keep track of is this: ' + text[0].lower() + text[1:]
        elif pid == 'code-switch-token':
            text = text.rstrip('.?') + ', por favor.'
        elif pid == 'lowercase':
            text = text.lower()
        elif pid == 'punctuation-loss':
            text = re.sub(r'[^\w\s’\-]', '', text)
        elif pid == 'casing-corruption':
            words = text.split()
            if len(words) > 3:
                words[2] = words[2].upper()
            text = ' '.join(words)
        elif pid == 'asr-insertion':
            changed = re.sub(r'\b(to|and)\b', r'\1 uh', text, count=1)
            text = changed if changed != text else re.sub(r'^(\S+)', r'\1 uh', text, count=1)
        elif pid == 'asr-boundary-error':
            changed = text.replace(';', ' ', 1).replace('. ', ' ', 1)
            if changed == text:
                for boundary in (',', ':', '—'):
                    changed = text.replace(boundary, '', 1)
                    if changed != text:
                        break
            text = changed if changed != text else text.rstrip('.')
        elif pid == 'asr-duplicated-token':
            text = re.sub(r'\b(the|to|and)\b', r'\1 \1', text, count=1)
        elif pid == 'asr-substitution':
            changed = re.sub(r'\bmeeting\b', 'meaning', text, count=1)
            text = changed if changed != text else re.sub(r'\bcheck-in\b', 'chicken', text, count=1)
        elif pid in {'asr-deletion', 'asr-dropped-token'}:
            changed = re.sub(r'\b(tomorrow|today|not|don’t|do not)\b', '[inaudible]', text, count=1, flags=re.I)
            text = changed if changed != text else re.sub(r'\b([A-Za-z]{5,})\b', '[inaudible]', text, count=1)
        elif pid == 'homophone':
            text = re.sub(r'\bflour\b', 'flower', text, count=1, flags=re.I)
        elif pid == 'asr-name-corruption':
            person = next((item['person'] for item in e['items'] if item['person']), None)
            if person:
                text = text.replace(person, alternates['corrupt_person'], 1)
        elif pid in {'asr-partial-recognition', 'partial-thought'}:
            text = text[:max(18, len(text) * 2 // 3)].rstrip() + '…'
        elif pid == 'short-fragment':
            text = text.replace('Before I forget, ', '').replace('I need to ', '').rstrip('.?')
        elif pid == 'punctuation-corruption':
            text = text.replace(',', '?', 1)
        elif pid == 'incomplete-clause':
            text = 'And then that other thing— ' + text
        elif pid == 'abandoned-thought':
            text = 'I was thinking about the rent, but— anyway, ' + text[0].lower() + text[1:]
        elif pid == 'reported-speech':
            text = 'They told me this earlier, and I want to remember it: ' + text[0].lower() + text[1:]
        elif pid == 'quoted-speech':
            text = 'Their exact words were, “' + text.rstrip('.?') + '.”'
    return re.sub(r'\s+', ' ', text).strip(), discarded
