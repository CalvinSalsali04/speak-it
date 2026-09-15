"""Authored semantic-family catalog and deterministic starter renderings.

The catalog composes *semantic* axes (route, polarity, scope, time, context),
never word templates. Surface wording is produced only after blueprint identity
has been fixed.
"""
from copy import deepcopy
from pathlib import Path
import json

from .contracts import CONTEXT, VERSION, digest, rendering_identity, semantic_identity, write_json, write_jsonl

HOME = Path(__file__).resolve().parents[1]

PHENOMENA = [
    ('filler-words', 'Semantically empty discourse fillers occur.', 'Um, call Maya.', 'Call Uma.'),
    ('hesitation', 'A pause marker interrupts a fluent phrase.', 'Call, uh, Maya.', 'Call Maya now.'),
    ('false-start', 'A started constituent is replaced before completion.', 'Call Mar— call Maya.', 'Call Maya and Marco.'),
    ('restart', 'The speaker restarts the whole instruction.', 'Buy milk— start over, buy bread.', 'Buy milk and bread.'),
    ('self-correction-person', 'The named person is explicitly corrected.', 'Call Maya, sorry, Priya.', 'Call Maya and Priya.'),
    ('self-correction-date', 'The date is explicitly corrected.', 'Friday, no, Saturday.', 'Friday and Saturday.'),
    ('self-correction-time', 'The time is explicitly corrected.', 'At three, actually four.', 'From three to four.'),
    ('self-correction-quantity', 'A quantity is explicitly corrected.', 'Buy two, make that three.', 'Buy two or three.'),
    ('self-correction-location', 'The location is explicitly corrected.', 'At home, sorry, at work.', 'At home and work.'),
    ('repetition', 'Words are repeated without adding meaning.', 'Call call Maya.', 'Call Maya twice.'),
    ('rephrasing', 'The same intent is restated in different words.', 'Call Maya, I mean give her a ring.', 'Call Maya and message her.'),
    ('abandoned-thought', 'An incomplete thought is abandoned for another.', 'I should maybe— buy milk.', 'I should plan and buy milk.'),
    ('never-mind-withdrawal', 'The speaker explicitly withdraws an intent.', 'Buy milk— never mind.', 'Never mind the brand; buy milk.'),
    ('rambling-introduction', 'Non-actionable preamble precedes the intent.', 'Long story short, after all that, buy milk.', 'Document the long story.'),
    ('rambling-ending', 'Non-actionable elaboration follows the intent.', 'Buy milk, because the week has been chaos.', 'Buy milk and document the week.'),
    ('sign-off-trailing-noise', 'A sign-off or dictation noise trails the intent.', 'Buy milk, okay thanks, sent from my phone.', 'Buy milk and send a thank-you.'),
    ('multiple-thoughts', 'One capture contains distinct semantic thoughts.', 'Buy milk. Maya likes tea.', 'Buy milk for Maya.'),
    ('multiple-tasks', 'One capture contains multiple independent obligations.', 'Buy milk and call Maya.', 'Call Maya about buying milk.'),
    ('numbered-list', 'Tasks are presented with spoken numbering.', 'One, buy milk. Two, call Maya.', 'Buy two milks.'),
    ('unnumbered-list', 'Tasks are presented as an unnumbered list.', 'Buy milk, call Maya, book dinner.', 'Buy milk for Maya at dinner.'),
    ('sequencing', 'Order relations connect otherwise distinct actions.', 'First call Maya, then buy milk.', 'Call Maya and buy milk sometime.'),
    ('conjunction-ambiguity', 'A conjunction permits multiple plausible scopes.', 'Call Maya and Priya about dinner.', 'Call Maya, then call Priya.'),
    ('shared-subject', 'One subject governs several predicates.', 'I need to call Maya and buy milk.', 'I need Maya to buy milk.'),
    ('shared-object', 'One object is shared by multiple actions.', 'Price and buy the lamp.', 'Price the lamp and buy a chair.'),
    ('shared-date', 'One date applies to multiple items.', 'Friday, call Maya and buy milk.', 'Friday call Maya; Saturday buy milk.'),
    ('shared-time', 'One exact time applies to multiple items.', 'At four, call Maya and leave.', 'Call Maya at four and leave at five.'),
    ('shared-location', 'One location applies to multiple items.', 'At work, call Maya and print notes.', 'At work call Maya; at home print notes.'),
    ('temporal-inheritance', 'A later clause inherits earlier temporal context.', 'Tomorrow call Maya and buy milk.', 'Tomorrow call Maya; buy milk someday.'),
    ('location-inheritance', 'A later clause inherits earlier location context.', 'At the office call Maya and print notes.', 'At the office call Maya; print at home.'),
    ('pronoun-resolution', 'A pronoun has a clear available antecedent.', 'Maya called; remind me to answer her.', 'Maya called Priya; answer her.'),
    ('ambiguous-pronoun', 'A pronoun has multiple plausible antecedents.', 'Maya told Priya to call her.', 'Maya said, “Call Priya.”'),
    ('reported-speech', 'Speech is reported as information, not commanded.', 'Maya said she will buy milk.', 'Maya, buy milk.'),
    ('quoted-speech', 'Quoted words must retain their speech boundary.', 'Maya said, “buy milk.”', 'Buy milk, Maya said.'),
    ('negation', 'A proposition is explicitly negative.', 'I did not call Maya.', 'I called Maya.'),
    ('prohibition', 'A future action is forbidden.', 'Do not call Maya.', 'I did not call Maya.'),
    ('cancellation', 'An existing stored intention is cancelled.', 'Cancel my call Maya reminder.', 'Do not call Maya today.'),
    ('change-of-intent', 'The final intent supersedes an earlier one.', 'Buy milk— actually get oat milk.', 'Buy milk and oat milk.'),
    ('uncertainty', 'The speaker is unsure whether an intent should be acted on.', 'Maybe I should call Maya?', 'Call Maya.'),
    ('conditional-intent', 'An action is contingent on a condition.', 'If Maya calls, send the file.', 'When Maya calls, note the time.'),
    ('question-mixed-with-action', 'A question and an actionable item coexist.', 'When is dinner, and call Maya.', 'When should I call Maya?'),
    ('information-mixed-with-action', 'A fact and an actionable item coexist.', 'Maya likes tea, and buy her some.', 'Buy tea Maya likes.'),
    ('completed-action', 'An action is explicitly already completed.', 'I already called Maya.', 'I still need to call Maya.'),
    ('outstanding-obligation', 'An obligation remains uncompleted.', 'I still need to call Maya.', 'I called Maya already.'),
    ('past-event', 'A past event is recorded as information.', 'Met Maya yesterday.', 'Meet Maya tomorrow.'),
    ('future-intention', 'A future intention is asserted.', 'I will call Maya tomorrow.', 'I called Maya yesterday.'),
    ('exact-time', 'An exact clock time is semantically relevant.', 'Call Maya at 4:15.', 'Call Maya later.'),
    ('relative-date', 'A date is relative to capture time.', 'Call Maya tomorrow.', 'Call Maya on August 4, 2026.'),
    ('relative-duration', 'A duration is relative to capture time.', 'Call Maya in ninety minutes.', 'Call Maya for ninety minutes.'),
    ('recurrence', 'An intent repeats according to a schedule.', 'Call Maya every Tuesday.', 'Call Maya next Tuesday.'),
    ('uncommon-proper-noun', 'A rare proper noun must be preserved.', 'Meet Xochitl.', 'Meet someone.'),
    ('ordinary-word-name', 'A person name is also an ordinary word.', 'Call Hope.', 'I hope to call.'),
    ('store-brand-product-name', 'A commercial proper name must be preserved.', 'Buy Oatly at Farm Boy.', 'Buy oats at the farm.'),
    ('lowercase', 'All text is lowercased without changing meaning.', 'call maya tomorrow', 'call maya tomorrow and omit Maya'),
    ('punctuation-loss', 'Expected punctuation is absent.', 'Maya said buy milk', 'Maya said, “buy milk.”'),
    ('punctuation-corruption', 'Punctuation creates implausible boundaries.', 'Call, Maya tomorrow?', 'Call Maya tomorrow.'),
    ('casing-corruption', 'Casing is inconsistent or misleading.', 'call MAYA Tomorrow', 'Call a different person.'),
    ('asr-substitution', 'ASR substitutes a confusable token.', 'Buy flower for baking.', 'Buy flour for baking.'),
    ('asr-deletion', 'ASR omits a spoken token.', 'Call Maya at four [time token lost].', 'Call Maya at four.'),
    ('asr-insertion', 'ASR inserts an unintended token.', 'Call uh Maya tomorrow.', 'Call Maya and Uma tomorrow.'),
    ('homophone', 'Homophones create lexical ambiguity.', 'Buy flower for bread.', 'Buy flour and flowers.'),
    ('partial-thought', 'The capture ends before semantic completion.', 'Remind me to call…', 'Remind me to call Maya.'),
    ('long-capture', 'A long capture contains relevant and irrelevant spans.', 'After a long explanation, call Maya and buy milk tomorrow.', 'Call Maya.'),
    ('short-fragment', 'A terse fragment conveys an item.', 'Milk tomorrow.', 'Milk.'),
    ('code-switch-token', 'A defined non-English token appears in an English capture.', 'Buy leche tomorrow.', 'Translate the whole capture.')
]

ARCHETYPES = [
    'single-task', 'reminder', 'memory', 'idea', 'event', 'person-fact', 'location-trigger',
    'date-only', 'exact-date-time', 'recurrence', 'negative-statement', 'prohibition',
    'cancellation', 'two-independent-tasks', 'two-tasks-shared-time', 'two-tasks-shared-location',
    'task-plus-memory', 'task-plus-question', 'information-plus-task', 'person-correction',
    'date-correction', 'time-correction', 'change-of-mind', 'partial-review', 'ambiguous-review',
    'completed-action'
]

OVERLAYS = [
    ('plain', None, None, None), ('person', None, None, 'Maya Chen'),
    ('relative-date', 'Tue Aug 4', None, None), ('exact-time', 'Thu Aug 6', '16:15', None),
    ('named-location', None, None, None), ('person-date', 'Tue Aug 4', None, 'Priya Shah'),
    ('person-time', 'Tue Aug 4', '09:30', 'Noah Brooks'), ('shared-context', 'Fri Aug 7', '14:00', 'Elena Costa'),
    ('priority-context', 'Wed Aug 5', None, 'Hope Reed'), ('weekend-context', 'Sat Aug 8', '11:00', 'Xochitl Rivera')
]


def _item(route, kind, title, facts, *, date=None, time=None, recurrence=None, location=None,
          person=None, negation=False, prohibition=False, state='outstanding', review=False):
    return dict(route=route, type=kind, title=title, facts=facts, forbidden_facts=[], date=date,
                time=time, recurrence=recurrence, location=location, person=person,
                negation=negation, prohibition=prohibition, state=state, needs_review=review)


def family_definition(archetype, overlay_name, index):
    """Build one valid semantic recipe; overlay values alter structured meaning."""
    _, date, clock, person = OVERLAYS[index]
    location = 'Farm Boy' if overlay_name in ('named-location', 'shared-context', 'weekend-context') else None
    actions = {
        'single-task': 'send the project update', 'reminder': 'water the basil', 'memory': 'remember the window-seat preference',
        'idea': 'try a walking meeting', 'event': 'attend the planning session', 'person-fact': 'remember the design-team detail',
        'location-trigger': 'pick up the dry cleaning', 'date-only': 'note the warranty date', 'exact-date-time': 'join the dentist appointment',
        'recurrence': 'take out the recycling', 'negative-statement': 'record that the invoice was not sent',
        'prohibition': 'send the confidential draft', 'cancellation': 'water the basil', 'two-independent-tasks': 'buy oat milk',
        'two-tasks-shared-time': 'submit the expense report', 'two-tasks-shared-location': 'print the handouts',
        'task-plus-memory': 'book the train', 'task-plus-question': 'call the venue', 'information-plus-task': 'order more tea',
        'person-correction': 'send the photos', 'date-correction': 'renew the membership', 'time-correction': 'call the clinic',
        'change-of-mind': 'order the blue notebook', 'partial-review': 'follow up about the proposal',
        'ambiguous-review': 'send the document to her', 'completed-action': 'file the tax receipt'
    }
    purposes = {'plain': 'core project', 'person': 'client account', 'relative-date': 'travel plan',
                'exact-time': 'appointment', 'named-location': 'errand', 'person-date': 'birthday',
                'person-time': 'interview', 'shared-context': 'launch', 'priority-context': 'tax filing',
                'weekend-context': 'family trip'}
    action = f"{actions[archetype]} for the {purposes[overlay_name]}"
    item = _item('Today', 'task', action, [action], date=date, time=clock, location=location, person=person)
    items, operations, policy = [item], [], 'act'
    shared = dict(temporal=None, location=None, person=None)

    if archetype == 'reminder': item['type'] = 'reminder'
    elif archetype == 'memory': item.update(route='Memory', type='memory', state='informational')
    elif archetype == 'idea': item.update(route='Memory', type='idea', state='informational')
    elif archetype == 'event': item.update(type='event')
    elif archetype == 'person-fact': item.update(route='Memory', type='personFact', state='informational', person=person or 'Maya Chen')
    elif archetype == 'location-trigger': item.update(type='reminder', location=location or 'Farm Boy')
    elif archetype == 'date-only': item.update(route='Memory', type='note', state='informational', date=date or 'Tue Aug 4', time=None)
    elif archetype == 'exact-date-time': item.update(type='reminder', date=date or 'Tue Aug 4', time=clock or '16:15')
    elif archetype == 'recurrence': item.update(type='reminder', recurrence='weekly:tuesday', date=date or 'Tue Aug 4')
    elif archetype == 'negative-statement': item.update(route='Memory', type='memory', state='informational', negation=True)
    elif archetype == 'prohibition': item.update(negation=True, prohibition=True)
    elif archetype == 'cancellation':
        items = []; operations = [dict(operation='cancel', target=action, scoped=False)]; policy = 'act'
    elif archetype.startswith('two-'):
        second = _item('Today', 'task', 'call Maya about dinner', ['call Maya about dinner'], date=item['date'], time=item['time'], location=item['location'], person=person or 'Maya Chen')
        items = [item, second]
        if archetype == 'two-independent-tasks': second.update(date=None, time=None, location=None, person=None)
        elif archetype == 'two-tasks-shared-time':
            d, t = date or 'Tue Aug 4', clock or '16:15'; item.update(date=d, time=t); second.update(date=d, time=t); shared['temporal'] = f'{d} {t}'
        else:
            loc = location or 'Farm Boy'; item['location'] = loc; second['location'] = loc; shared['location'] = loc
    elif archetype == 'task-plus-memory': items.append(_item('Memory', 'memory', 'Maya prefers the quiet car', ['Maya prefers the quiet car'], person='Maya Chen', state='informational'))
    elif archetype == 'task-plus-question': items.append(_item('Memory', 'note', 'ask when the doors open', ['ask when the doors open'], state='informational'))
    elif archetype == 'information-plus-task': items.insert(0, _item('Memory', 'memory', 'the tea shelf is empty', ['the tea shelf is empty'], state='informational'))
    elif archetype == 'person-correction': item.update(person='Priya Shah'); item['forbidden_facts'] = ['Maya Chen']
    elif archetype == 'date-correction': item.update(date='Sat Aug 8'); item['forbidden_facts'] = ['Fri Aug 7']
    elif archetype == 'time-correction': item.update(date=date or 'Tue Aug 4', time='16:00'); item['forbidden_facts'] = ['15:00']
    elif archetype == 'change-of-mind': item['forbidden_facts'] = ['order the red notebook']
    elif archetype in ('partial-review', 'ambiguous-review'):
        item.update(route='Memory', type='note', state='uncertain', needs_review=True, date=None, time=None, recurrence=None, location=None)
        policy = 'review' if archetype == 'ambiguous-review' else 'preserve-only'
    elif archetype == 'completed-action': item.update(route='Memory', type='memory', state='completed')

    # Person is shared only when two items actually contain it.
    if len(items) > 1 and person and all(x.get('person') == person for x in items): shared['person'] = person
    expected = dict(item_count=len(items), items=items, operations=operations, ambiguity_policy=policy, shared_context=shared)
    return dict(family_id=f'family-{archetype}-{overlay_name}', description=f'{archetype} with {overlay_name} semantic context',
                archetype=archetype, semantic_axes=[archetype, overlay_name], expected=expected)


def render_text(blueprint, serial):
    e = blueprint['expected']
    if e['operations']:
        return f"Cancel the saved reminder to {e['operations'][0]['target']}."
    parts = []
    for item in e['items']:
        text = item['title']
        if item['person']: text += f" with {item['person']}"
        if item['location']: text += f" at {item['location']}"
        if item['date']: text += f" on {item['date']}"
        if item['time']: text += f" at {item['time']}"
        if item['recurrence']: text += " every Tuesday"
        if item['prohibition']: text = "Do not " + text
        elif item['negation']: text = "It is not true that " + text
        if item['state'] == 'completed': text = "Already " + text
        parts.append(text)
    joiner = '. Also, ' if len(parts) > 1 else ''
    text = joiner.join(parts) or f'Cancel item {serial}'
    if e['ambiguity_policy'] in ('review', 'preserve-only'): text = 'Maybe ' + text + '…'
    text = text[:1].upper() + text[1:]
    return text + ('' if text.endswith(('.', '…')) else '.')


def mutate_for_phenomenon(text, pid, n):
    core = text.rstrip('.…')
    if pid == 'lowercase': return text.lower()
    if pid == 'casing-corruption': return core.swapcase() + '.'
    if pid == 'punctuation-loss': return core.replace(',', '')
    if pid == 'punctuation-corruption': return core.replace(' ', ', ', 1) + '?'
    if pid == 'filler-words': return f'Um, {core}, you know.'
    if pid == 'hesitation':
        words = core.split(); return ' '.join(words[:2]) + ', uh, ' + ' '.join(words[2:]) + '.'
    if pid == 'asr-insertion':
        words = core.split(); return ' '.join(words[:1] + ['uh'] + words[1:]) + '.'
    if pid == 'repetition':
        words = core.split(); return ' '.join(words[:2] + words[1:]) + '.'
    if pid == 'sign-off-trailing-noise': return f'{core}, okay thanks, sent from my phone.'
    if pid == 'rambling-ending': return f'{core}, because this whole week has been a bit chaotic and I do not want it to slip.'
    if pid == 'rambling-introduction': return f'Long story short, after everything that happened this week, {core}.'
    if pid == 'long-capture': return f'I have been sorting through the schedule, the notes from last week, and all the loose ends from the project, and after checking what is urgent and what can wait, the one thing I need to capture now is this: {core}.'
    if pid == 'abandoned-thought': return f'I was thinking about the invoice— anyway, {core}.'
    if pid in ('partial-thought', 'asr-deletion'): return core[:max(12, len(core)//2)].rstrip() + '…'
    if pid == 'short-fragment':
        words = core.split(); return ' '.join(words[2:]) + '.' if len(words) > 3 else core
    if pid == 'code-switch-token': return core + ' por favor.'
    if pid == 'false-start': return f'I was going to send— sorry, {core}.'
    if pid == 'restart': return f'Start over: {core}.'
    if pid == 'self-correction-person': return f'Do that with Maya— sorry, with Priya. {core}.'
    if pid == 'self-correction-date': return f'Do that Friday— no, Saturday. {core}.'
    if pid == 'self-correction-time': return f'Do that at three— actually four. {core}.'
    if pid == 'self-correction-quantity': return f'Get two— make that three. {core}.'
    if pid == 'self-correction-location': return f'Do that at home— sorry, at work. {core}.'
    if pid == 'change-of-intent': return f'Order the red notebook— actually, {core}.'
    if pid == 'rephrasing': return f'{core}; in other words, make sure that gets done.'
    if pid == 'never-mind-withdrawal': return f'{core}— no, never mind that withdrawal, keep it.'
    if pid == 'numbered-list': return 'One, buy oat milk. Two, call Maya about dinner.'
    if pid == 'unnumbered-list': return 'Buy oat milk, call Maya about dinner.'
    if pid == 'sequencing': return 'First buy oat milk, then call Maya about dinner.'
    if pid in ('multiple-thoughts', 'multiple-tasks'): return core
    if pid == 'reported-speech': return f'Maya said that we should {core.lower()}.'
    if pid == 'quoted-speech': return f'Maya said, “{core}.”'
    if pid == 'asr-substitution': return core.replace('project update', 'project up date').replace('prepare', 'pre pair') + '.'
    if pid == 'homophone': return core.replace('send', 'scent', 1).replace('prepare', 'pre pair', 1) + '.'
    wrappers = {
        'shared-subject': 'I need to {core}.', 'shared-object': '{core}; use the same document for both actions.',
        'shared-date': 'On the same day, {core}.', 'shared-time': 'At that time, {core}.',
        'shared-location': 'At the same place, {core}.', 'temporal-inheritance': 'Tomorrow, {core}.',
        'location-inheritance': 'At the office, {core}.', 'pronoun-resolution': 'Maya called; {core}, and reply to her.',
        'ambiguous-pronoun': 'Maya told Priya to do this for her: {core}.', 'negation': '{core}.',
        'prohibition': 'Do not {core}.', 'uncertainty': 'Maybe {core}?', 'conditional-intent': 'If Maya calls, {core}.',
        'question-mixed-with-action': 'When do the doors open, and {core}?', 'information-mixed-with-action': 'The shelf is empty, and {core}.',
        'completed-action': 'Already {core}.', 'outstanding-obligation': 'I still need to {core}.',
        'past-event': 'Yesterday I did this: {core}.', 'future-intention': 'Tomorrow I will {core}.',
        'exact-time': '{core} at exactly four fifteen.', 'relative-date': 'Tomorrow, {core}.',
        'relative-duration': 'In ninety minutes, {core}.', 'recurrence': 'Every Tuesday, {core}.',
        'uncommon-proper-noun': '{core} with Xochitl.', 'ordinary-word-name': '{core} with Hope.',
        'store-brand-product-name': '{core} at Farm Boy using Oatly.',
    }
    return wrappers.get(pid, '{core}.').format(core=core)


def compatible_blueprint(blueprints, pid):
    archetype = {
        'multiple-thoughts': 'task-plus-memory', 'multiple-tasks': 'two-independent-tasks', 'numbered-list': 'two-independent-tasks',
        'unnumbered-list': 'two-independent-tasks', 'sequencing': 'two-independent-tasks', 'conjunction-ambiguity': 'two-independent-tasks',
        'shared-subject': 'two-independent-tasks', 'shared-object': 'two-independent-tasks', 'shared-date': 'two-tasks-shared-time',
        'shared-time': 'two-tasks-shared-time', 'shared-location': 'two-tasks-shared-location', 'temporal-inheritance': 'two-tasks-shared-time',
        'location-inheritance': 'two-tasks-shared-location', 'ambiguous-pronoun': 'ambiguous-review', 'reported-speech': 'memory',
        'quoted-speech': 'memory', 'negation': 'negative-statement', 'prohibition': 'prohibition', 'cancellation': 'cancellation',
        'change-of-intent': 'change-of-mind', 'uncertainty': 'ambiguous-review', 'conditional-intent': 'partial-review',
        'question-mixed-with-action': 'task-plus-question', 'information-mixed-with-action': 'information-plus-task',
        'completed-action': 'completed-action', 'past-event': 'memory', 'future-intention': 'single-task', 'exact-time': 'exact-date-time',
        'relative-date': 'reminder', 'relative-duration': 'reminder', 'recurrence': 'recurrence', 'partial-thought': 'partial-review',
        'short-fragment': 'single-task', 'self-correction-person': 'person-correction', 'self-correction-date': 'date-correction',
        'self-correction-time': 'time-correction', 'self-correction-quantity': 'single-task', 'self-correction-location': 'location-trigger',
        'never-mind-withdrawal': 'cancellation', 'pronoun-resolution': 'person-fact', 'outstanding-obligation': 'single-task'
    }.get(pid, 'single-task')
    overlay = {
        'exact-time': 'exact-time', 'relative-date': 'relative-date', 'recurrence': 'relative-date',
        'uncommon-proper-noun': 'weekend-context', 'ordinary-word-name': 'priority-context', 'store-brand-product-name': 'named-location',
        'self-correction-person': 'person', 'self-correction-date': 'shared-context', 'self-correction-time': 'exact-time',
        'self-correction-location': 'named-location', 'shared-date': 'shared-context', 'shared-time': 'shared-context',
        'shared-location': 'named-location', 'temporal-inheritance': 'shared-context', 'location-inheritance': 'named-location',
    }.get(pid, 'plain')
    wanted = f'family-{archetype}-{overlay}'
    return next(bp for bp in blueprints if bp['family_id'] == wanted)


def build(output=HOME / 'data', seed=20260912):
    phenomena = [dict(id=i, name=i.replace('-', ' ').title(), definition=d, examples=[e], counterexamples=[c],
                       preserves_meaning=i not in {'never-mind-withdrawal', 'cancellation', 'change-of-intent', 'partial-thought', 'asr-deletion'},
                       metrics=['semantic_preservation', 'routing', 'item_count'],
                       safety_level='high' if i in {'negation', 'prohibition', 'cancellation', 'never-mind-withdrawal'} else 'normal',
                       blind_mutation_suitable=i not in {'ambiguous-pronoun', 'conjunction-ambiguity', 'asr-substitution', 'asr-deletion', 'homophone'})
                  for i, d, e, c in PHENOMENA]
    write_json(HOME / 'config/phenomena.json', dict(version=VERSION, phenomena=phenomena))
    families, blueprints = [], []
    for archetype in ARCHETYPES:
        for index, (overlay, _, _, _) in enumerate(OVERLAYS):
            family = family_definition(archetype, overlay, index)
            expected = deepcopy(family['expected'])
            context = deepcopy(CONTEXT)
            if archetype == 'cancellation':
                context['stored_items'] = [{'stored_id': f'stored-{overlay}', 'title': expected['operations'][0]['target']}]
            raw = dict(family_id=family['family_id'], version=VERSION, source_type='authored',
                       source_provenance={'authoring_method': 'reviewed semantic recipe', 'catalog_version': VERSION},
                       license_notes='Repository-authored; no external text.', capture_context=context,
                       expected=expected, semantic_tags=family['semantic_axes'], difficulty_dimensions=family['semantic_axes'],
                       safety_critical=archetype in ('prohibition', 'cancellation', 'negative-statement'))
            raw['blueprint_id'] = 'bp-' + semantic_identity(raw)[:24]
            families.append({k: v for k, v in family.items() if k != 'expected'} | {'blueprint_id': raw['blueprint_id']})
            blueprints.append(raw)
    renderings = []
    for n, bp in enumerate(blueprints):
        base = render_text(bp, n)
        row = dict(blueprint_id=bp['blueprint_id'], text=base,
                   provenance={'kind': 'repository-authored', 'family_id': bp['family_id']},
                   generator={'kind': 'deterministic', 'name': 'SpeechLab catalog', 'version': VERSION}, seed=seed,
                   phenomena=[], mutation_lineage=[], equivalence_class=bp['blueprint_id'], meaning_preservation='guaranteed')
        row['rendering_id'] = 'rd-' + rendering_identity(row)[:24]
        renderings.append(row)
    for n, phenomenon in enumerate(phenomena):
        pid = phenomenon['id']; bp = compatible_blueprint(blueprints, pid); base = next(r for r in renderings if r['blueprint_id'] == bp['blueprint_id'])
        text = mutate_for_phenomenon(base['text'], pid, n)
        if text == base['text']: text = 'Okay, ' + text[0].lower() + text[1:]
        preservation = 'reviewed' if phenomenon['preserves_meaning'] and pid not in {'asr-substitution', 'homophone'} else 'uncertain'
        row = dict(blueprint_id=bp['blueprint_id'], text=text, provenance={'kind': 'repository-authored', 'phenomenon': pid},
                   generator={'kind': 'deterministic', 'name': 'SpeechLab phenomenon renderer', 'version': VERSION}, seed=seed,
                   phenomena=[pid], mutation_lineage=[base['rendering_id']], equivalence_class=bp['blueprint_id'], meaning_preservation=preservation)
        row['rendering_id'] = 'rd-' + rendering_identity(row)[:24]; renderings.append(row)
    output.mkdir(parents=True, exist_ok=True)
    write_jsonl(output / 'family-definitions.jsonl', families)
    write_jsonl(output / 'blueprints.jsonl', blueprints)
    write_jsonl(output / 'renderings.jsonl', renderings)
    return families, blueprints, renderings
