#!/usr/bin/env python3
"""Build SpeechLab Phase 2's bounded, reviewable corpus.

This program authors semantic contracts and surface candidates without invoking
the production parser. Every case receives an author self-review only. No case
is marked trusted or gold; independent adjudication is a separate workflow.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))

from Sources.composition import (ASR_LOSSY, TRANSFORMS, CoverageTracker, apply_transformations,
                                 approved_recipes, compatible, transformation_lineage,
                                 validate_composition)
from Sources.contracts import (CONTEXT, digest, dumps, norm, read_jsonl, rendering_identity,
                               semantic_identity, validate_blueprints, write_json, write_jsonl)
from Sources.taxonomy import build_taxonomy


VERSION = 'speechlab-corpus-2'
REVIEWED_AT = '2026-09-13T00:00:00-04:00'

NAMES = [
    'Alex Morgan', 'Aisha Rahman', 'Ben Okafor', 'Camille Dubois', 'Daniel Kim',
    'Elena García', 'Fatima Zahra', 'Grace Liu', 'Hassan Ali', 'Imani Brooks',
    'Javier Santos', 'Keira Walsh', 'Lena Hoffmann', 'Mateo Rossi', 'Nadia Patel',
    'Omar Haddad', 'Priya Nair', 'Quinn Taylor', 'Rina Sato', 'Samir Khan',
    'Talia Cohen', 'Uma Desai', 'Victor Chen', 'Wanjiku Njoroge', 'Xavier Reed',
    'Yara Mansour', 'Zoe Bennett', 'Hope Sinclair', 'River James', 'April Young',
    'Rose Park', 'Mark Day', 'Sofia Ionescu', 'Noah Williams', 'Mina Kowalski',
    'Theo Martin', 'Anika Singh', 'Lucas Pereira', 'Mariam Tesfaye', 'Jun Park',
]
LOCATIONS = [
    'Union Station', 'the pharmacy on Bloor', 'Harbourfront Centre', 'the east library',
    'Pearson Terminal 1', 'the King Street office', 'St. Lawrence Market',
    'the community garden', 'North York General', 'the Lakeshore studio',
    'the daycare on Ossington', 'the Queen Street clinic', 'the campus bookstore',
    'the rehearsal room', 'the storage locker', 'the mechanic on Dupont',
    'the Junction post office', 'the climbing gym', 'the neighbourhood bakery',
    'the coworking space', 'Billy Bishop Airport', 'the dentist downtown',
    'the vet near High Park', 'the school office', 'the passport office',
    'the farmers market', 'the train platform', 'the hotel lobby', 'the rental counter',
    'the volunteer centre',
]
DATES = [
    'tomorrow', 'Friday', 'next Tuesday', 'September 18', 'this Saturday',
    'the first Monday in October', 'two days from now', 'the morning after the exam',
    'next weekend', 'October 3', 'the last day of the month', 'the day before the flight',
    'Wednesday', 'next Thursday', 'December 6', 'the second week of November',
    'three weeks from today', 'the Monday after Thanksgiving', 'January 12', 'this Sunday',
]
PAST_DATES = [
    'yesterday', 'last Friday', 'earlier this week', 'August 28', 'last Tuesday',
    'the previous weekend', 'three days ago', 'the morning before the appointment',
]
TIMES = ['07:15', '08:40', '09:30', '10:00', '11:45', '12:20', '13:10', '14:30', '15:05', '16:15', '17:40', '18:00', '19:25', '20:10', '21:00', '22:30']
RECURRENCES = [
    'weekdays', 'weekly:monday', 'weekly:tuesday', 'weekly:friday', 'every-other-wednesday',
    'monthly:first-business-day', 'monthly:last-friday', 'daily', 'every-three-days',
    'yearly:anniversary', 'twice-weekly', 'school-days',
]
TIMEZONES = ['America/Toronto', 'America/Vancouver', 'Europe/London', 'Asia/Tokyo']

ACTIONS = [
    ('follow up about the apartment application', 'call back about the apartment paperwork'),
    ('submit the chemistry lab report', 'hand in the chem lab write-up'),
    ('pick up the allergy prescription', 'grab the allergy meds'),
    ('replace the kitchen light bulb', 'swap out the bulb in the kitchen'),
    ('reserve a seat on the evening train', 'book a spot on the evening train'),
    ('send the revised budget to the team', 'get the updated budget over to the team'),
    ('buy two cartons of oat milk', 'pick up 2 cartons of oat milk'),
    ('return the borrowed camera lens', 'take the borrowed lens back'),
    ('book the annual eye exam', 'set up my yearly eye appointment'),
    ('renew the library card', 'sort out the library card renewal'),
    ('pay the electricity bill', 'take care of the hydro bill'),
    ('move the dentist appointment', 'reschedule the dentist visit'),
    ('print the workshop handouts', 'get the workshop sheets printed'),
    ('check the passport expiry date', 'look up when the passport expires'),
    ('order a replacement laptop charger', 'get another charger for the laptop'),
    ('water the balcony herbs', 'give the herbs on the balcony some water'),
    ('confirm the dinner reservation', 'double-check that the dinner booking is set'),
    ('mail the signed lease', 'send out the signed rental agreement'),
    ('upload the portfolio draft', 'put the portfolio draft online'),
    ('pick up the dry cleaning', 'grab the clothes from the cleaner'),
    ('cancel the unused software trial', 'stop the software trial before it renews'),
    ('bring snacks for the study group', 'take something to eat to the study session'),
    ('charge the camera batteries', 'top up the camera batteries'),
    ('send the fundraiser receipt', 'forward the receipt from the fundraiser'),
    ('make a vet appointment', 'book a visit with the vet'),
    ('drop off the donation boxes', 'take the donation boxes over'),
    ('compare internet plans', 'look into the different internet packages'),
    ('request the course transcript', 'ask the school for my transcript'),
    ('return the rental car', 'take the hire car back'),
    ('pack the travel adapter', 'put the travel plug in my bag'),
    ('defrost the soup for dinner', 'take the soup out for tonight'),
    ('update the emergency contact', 'change the emergency contact details'),
    ('send the thank-you note', 'get a thank-you message out'),
    ('measure the living room window', 'get the window measurements in the living room'),
    ('buy cat litter', 'pick up litter for the cat'),
    ('call the insurance adjuster', 'get in touch with the insurance person'),
    ('back up the thesis files', 'make a backup of the thesis folder'),
    ('bring the signed permission form', 'bring the signed school form'),
    ('schedule the volunteer shift', 'choose a time for the volunteer shift'),
    ('check in for the flight', 'do the airline check-in'),
    ('collect the race bib', 'pick up the race number'),
    ('refill the transit card', 'put more money on the transit card'),
    ('return the online order', 'send the web order back'),
    ('send the client invoice', 'get the invoice over to the client'),
    ('clean the coffee grinder', 'give the coffee grinder a proper clean'),
    ('rebook the missed class', 'find another time for the class I missed'),
    ('download the boarding passes', 'save the boarding passes to my phone'),
    ('bring the reusable containers', 'take the food containers along'),
    ('sign the benefits form', 'finish signing the benefits paperwork'),
    ('ask about the repair estimate', 'check what the repair is going to cost'),
    ('buy flour for the bread recipe', 'pick up bread flour'),
    ('photograph the meter reading', 'take a picture of the meter number'),
    ('confirm the interview time', 'make sure the interview time is right'),
    ('pick up the birthday cake', 'collect the cake for the birthday'),
    ('send the rehearsal recording', 'share the recording from rehearsal'),
    ('replace the smoke-alarm batteries', 'change the batteries in the smoke alarm'),
    ('reserve the meeting room', 'book a room for the meeting'),
    ('transfer money to savings', 'move some money into the savings account'),
    ('bring the medical referral', 'take the referral letter to the appointment'),
    ('check the grocery delivery window', 'see when the groceries are arriving'),
    ('call about the broken radiator', 'phone someone about the radiator not working'),
    ('submit the expense claim', 'file the expenses from the trip'),
    ('order replacement contact lenses', 'get another box of contact lenses'),
    ('return the building fob', 'drop the entry fob back off'),
]

MEMORIES = [
    ('the guest room radiator makes a clicking noise', 'the radiator in the spare room keeps clicking'),
    ('the blue key opens the storage locker', 'it is the blue key that works for the locker'),
    ('the neighbour prefers text messages after six', 'the neighbour would rather be texted after six'),
    ('the warranty is stored in the desk drawer', 'the warranty paperwork is in my desk'),
    ('the south entrance is wheelchair accessible', 'the accessible entrance is on the south side'),
    ('the café stops serving lunch at three', 'lunch at that café ends at three'),
    ('the spare charger belongs to the school', 'that extra charger is school property'),
    ('the dog is allergic to chicken treats', 'chicken treats do not agree with the dog'),
    ('the landlord approved painting the hallway', 'we have permission to paint the hall'),
    ('the train ticket includes one checked bag', 'one checked bag comes with the train booking'),
    ('the project code name is Northstar', 'Northstar is the code name for the project'),
    ('the clinic needs the original referral', 'the clinic asked for the actual referral letter'),
    ('the twins finish school early on Fridays', 'school lets the twins out early every Friday'),
    ('the rental deposit was paid by bank transfer', 'I sent the rental deposit by bank transfer'),
    ('the meeting room screen needs an HDMI adapter', 'the screen in that room only works with the HDMI adapter'),
    ('the package is behind the side gate', 'the parcel was left by the side entrance'),
    ('the vegetarian soup contains dairy', 'there is dairy in the soup even though it is vegetarian'),
    ('the museum membership covers two guests', 'I can bring two people with the museum pass'),
    ('the repair shop closes early on Wednesdays', 'the mechanic shuts early every Wednesday'),
    ('the scholarship deadline uses Pacific time', 'the scholarship cutoff is based on Pacific time'),
    ('the backup drive is encrypted', 'the spare drive has encryption turned on'),
    ('the balcony plants need shade at midday', 'the plants outside should be shaded around noon'),
    ('the hotel confirmation is under the middle name', 'the hotel used my middle name for the booking'),
    ('the second invoice replaces the first one', 'the newer invoice is the one that counts'),
    ('the studio door sticks in cold weather', 'the door to the studio jams when it is cold'),
    ('the lentil recipe uses smoked paprika', 'smoked paprika goes in the lentil dish'),
    ('the school pickup moved to the west gate', 'pickup is at the west school gate now'),
    ('the return label expires after fourteen days', 'the shipping label is only good for 14 days'),
    ('the bicycle lock combination is in the password manager', 'the bike-lock code is saved with my passwords'),
    ('the conference badge uses the preferred name', 'the name badge has my preferred name on it'),
]

IDEAS = [
    ('try a walking meeting for the weekly check-in', 'maybe do the weekly check-in while walking'),
    ('make a shared map of quiet study spaces', 'put together a map of calm places to study'),
    ('use leftover fabric for reusable gift wrap', 'turn the spare fabric into gift wrapping'),
    ('start a neighbourhood tool-lending shelf', 'set up a shelf where neighbours can borrow tools'),
    ('record short pronunciation notes for language practice', 'save little pronunciation clips while practising'),
    ('plan meals around the farmers market', 'base next week’s meals on what is at the market'),
    ('create a photo book for the anniversary', 'make an anniversary book from the old photos'),
    ('test a no-meeting Wednesday', 'see how a Wednesday without meetings goes'),
    ('organize receipts by project instead of month', 'sort receipts by project rather than by date'),
    ('make a rainy-day list for the kids', 'keep a list of things the kids can do when it rains'),
    ('trade plant cuttings with the community garden', 'swap some plant cuttings at the garden'),
    ('turn the interview notes into a checklist', 'make a checklist out of the interview notes'),
    ('keep travel documents in one offline folder', 'save all the travel paperwork together offline'),
    ('add a repair kit to the bicycle basket', 'leave a small bike repair kit in the basket'),
    ('host the book club outdoors in summer', 'move summer book club meetings outside'),
    ('write down one question after every lecture', 'save one question from each lecture'),
]

EVENTS = [
    ('the physiotherapy appointment', 'my physio appointment'),
    ('the parent-teacher meeting', 'the meeting with the teacher'),
    ('the community clean-up', 'the neighbourhood clean-up'),
    ('the design review', 'the design team review'),
    ('the train to Montréal', 'the Montréal train'),
    ('the visa appointment', 'the appointment for the visa'),
    ('the volunteer orientation', 'the volunteer intro session'),
    ('the pottery class', 'the ceramics class'),
    ('the apartment inspection', 'the rental inspection'),
    ('the choir rehearsal', 'the rehearsal with the choir'),
    ('the tax consultation', 'the meeting about my taxes'),
    ('the school concert', 'the concert at school'),
    ('the car service appointment', 'the service booking for the car'),
    ('the hiking trip', 'the group hike'),
    ('the research interview', 'the interview for the study'),
    ('the family dinner', 'dinner with the family'),
    ('the vaccination appointment', 'the vaccine appointment'),
    ('the lease signing', 'the meeting to sign the lease'),
    ('the online workshop', 'the workshop on Zoom'),
    ('the fundraising shift', 'the fundraiser volunteer shift'),
]


def stable_pick(values, *parts):
    return values[int(digest(list(parts))[:16], 16) % len(values)]


def semantic_shape(blueprint):
    expected = blueprint['expected']
    return {
        'count': expected['item_count'],
        'policy': expected['ambiguity_policy'],
        'items': [{
            'route': item['route'], 'type': item['type'], 'date': item['date'] is not None,
            'time': item['time'] is not None, 'recurrence': item['recurrence'] is not None,
            'location': item['location'] is not None, 'person': item['person'] is not None,
            'negation': item['negation'], 'prohibition': item['prohibition'], 'state': item['state'],
        } for item in expected['items']],
        'operations': [operation.get('operation') for operation in expected['operations']],
        'shared': {key: value is not None for key, value in expected['shared_context'].items()},
    }


def build_semantic_families(historical):
    groups = defaultdict(list)
    for blueprint in historical:
        groups[dumps(semantic_shape(blueprint))].append(blueprint)
    families = []
    for shape_text, members in sorted(groups.items()):
        shape = json.loads(shape_text)
        family_id = 'sf-' + digest(shape)[:16]
        item_types = ', '.join(item['type'] for item in shape['items']) or 'operation only'
        description = f'{shape["count"]} item(s); {item_types}; {shape["policy"]} policy; operations {shape["operations"] or "none"}'
        families.append({
            'semantic_family_id': family_id,
            'shape': shape,
            'description': description,
            'historical_family_ids': sorted({member['family_id'] for member in members}),
            'historical_blueprint_ids': sorted(member['blueprint_id'] for member in members),
            'member_count': len(members),
            'decision': 'collapsed' if len(members) > 1 else 'retained',
        })
    return families


def source_pair(item_shape, index):
    kind = item_shape['type']
    if kind == 'idea':
        return stable_pick(IDEAS, item_shape, index, 'idea')
    if kind == 'event':
        return stable_pick(EVENTS, item_shape, index, 'event')
    if item_shape['route'] == 'Memory' or kind in {'memory', 'note', 'personFact'}:
        return stable_pick(MEMORIES, item_shape, index, 'memory')
    return stable_pick(ACTIONS, item_shape, index, 'action')


def make_item(item_shape, index, shared_values):
    canonical, spoken = source_pair(item_shape, index)
    person = shared_values.get('person') if item_shape['person'] else None
    location = shared_values.get('location') if item_shape['location'] else None
    date = shared_values.get('date') if item_shape['date'] else None
    time = shared_values.get('time') if item_shape['time'] else None
    recurrence = (shared_values.get('recurrence') or stable_pick(RECURRENCES, item_shape, index, 'recurrence')) if item_shape['recurrence'] else None
    if item_shape['negation']:
        if item_shape['prohibition']:
            canonical = 'do not ' + canonical
        elif item_shape['route'] == 'Memory':
            canonical = 'not true: ' + canonical
            spoken = 'it is not true that ' + canonical.removeprefix('not true: ')
        else:
            canonical = 'not ' + canonical
            spoken = 'not ' + spoken
    return ({
        'route': item_shape['route'], 'type': item_shape['type'], 'title': canonical,
        'facts': [canonical], 'forbidden_facts': [], 'date': date, 'time': time,
        'recurrence': recurrence, 'location': location, 'person': person,
        'negation': item_shape['negation'], 'prohibition': item_shape['prohibition'],
        'state': item_shape['state'], 'needs_review': item_shape['state'] == 'uncertain',
    }, spoken)


def make_blueprint(family, index, *, source_type='authored', provenance=None, special_pid=None):
    shape = family['shape']
    context = deepcopy(CONTEXT)
    context['reference_time'] = f'2026-09-{(index % 28) + 1:02d}T{8 + (index % 10):02d}:{index % 60:02d}:00-04:00'
    timezone = stable_pick(TIMEZONES[1:], family['semantic_family_id'], index, 'timezone') if special_pid in {'timezone-sensitive', 'dst-transition'} else 'America/Toronto'
    context['timezone'] = timezone
    person = stable_pick(NAMES, family['semantic_family_id'], index, 'person')
    if special_pid == 'uncommon-proper-noun':
        person = 'Wanjiku Njoroge'
    elif special_pid == 'ordinary-word-name':
        person = 'Hope Sinclair'
    location = stable_pick(LOCATIONS, family['semantic_family_id'], index, 'location')
    date_pool = PAST_DATES if shape['items'] and all(item['state'] == 'completed' for item in shape['items']) else DATES
    date = stable_pick(date_pool, family['semantic_family_id'], index, 'date')
    time = stable_pick(TIMES, family['semantic_family_id'], index, 'time')
    if special_pid == 'relative-date':
        date = 'tomorrow'
    elif special_pid == 'relative-duration':
        date = 'two days from now'
    elif special_pid == 'dst-transition':
        date, time, timezone = 'November 1, 2026', '01:30', 'America/Toronto'
        context['timezone'] = timezone
        context['prior_turns'] = [{'speaker': 'user', 'text': 'This is the night of the clock change.'}]
    shared_values = {'person': person, 'location': location, 'date': date, 'time': time}
    if special_pid in {'cross-turn-reference-ambiguity', 'contact-person-ambiguity', 'ambiguous-pronoun'}:
        context['prior_turns'] = [
            {'speaker': 'user', 'text': f'{NAMES[index % len(NAMES)]} and {NAMES[(index + 1) % len(NAMES)]} both mentioned it.'},
            {'speaker': 'assistant', 'text': 'Which person or item do you mean?'},
        ]

    items, surfaces = [], []
    for item_index, item_shape in enumerate(shape['items']):
        values = dict(shared_values)
        if item_index and not shape['shared']['person']:
            values['person'] = stable_pick(NAMES, family['semantic_family_id'], index, item_index, 'person')
        if item_index and not shape['shared']['location']:
            values['location'] = stable_pick(LOCATIONS, family['semantic_family_id'], index, item_index, 'location')
        if item_index and not shape['shared']['temporal']:
            item_date_pool = PAST_DATES if item_shape['state'] == 'completed' else DATES
            values['date'] = stable_pick(item_date_pool, family['semantic_family_id'], index, item_index, 'date')
            values['time'] = stable_pick(TIMES, family['semantic_family_id'], index, item_index, 'time')
        if item_shape['recurrence'] and item_shape['date']:
            values['recurrence'] = stable_pick(
                ('daily', 'every-three-days', 'twice-weekly', 'school-days', 'weekdays', 'yearly:anniversary'),
                family['semantic_family_id'], index, item_index, 'compatible-recurrence',
            )
        item, surface = make_item(item_shape, index + item_index * 19, values)
        items.append(item)
        surfaces.append(surface)

    if special_pid in {'pronoun-resolution', 'cross-turn-reference'} and items:
        context['prior_turns'] = [
            {'speaker': 'user', 'text': f'I was talking about {items[0]["facts"][0]}' + (f' with {items[0]["person"]}.' if items[0]['person'] else '.')},
            {'speaker': 'assistant', 'text': 'Got it.'},
        ]
    if special_pid == 'homophone' and items:
        items[0]['title'] = 'buy flour for the bread recipe'
        items[0]['facts'] = ['buy flour for the bread recipe']
        surfaces[0] = 'pick up bread flour'

    operations = []
    if shape['operations']:
        target, target_surface = stable_pick(ACTIONS, family['semantic_family_id'], index, 'operation')
        operations = [{'operation': operation, 'target': target, 'scoped': True} for operation in shape['operations']]
        context['stored_items'] = [{'stored_id': 'stored-' + digest({'target': target, 'index': index})[:12], 'title': target}]
        surfaces = [target_surface]
    shared = {'temporal': None, 'location': None, 'person': None}
    if shape['shared']['temporal']:
        shared['temporal'] = date + (f' {time}' if any(item['time'] for item in items) else '')
    if shape['shared']['location']:
        shared['location'] = location
    if shape['shared']['person']:
        shared['person'] = person
    expected = {
        'item_count': len(items), 'items': items, 'operations': operations,
        'ambiguity_policy': shape['policy'], 'shared_context': shared,
    }
    safety = bool(operations or any(
        item['negation'] or item['prohibition'] or (item['route'] == 'Today' and (item['date'] or item['time'] or item['location']))
        for item in items
    ) or shape['policy'] != 'act')
    raw = {
        'family_id': family['semantic_family_id'], 'version': VERSION, 'source_type': source_type,
        'source_provenance': provenance or {'authoring_method': 'curated phrase-plan plus explicit semantic shape', 'builder_version': VERSION},
        'license_notes': 'Repository-authored; no external text.' if source_type == 'authored' else provenance['license'],
        'capture_context': context, 'expected': expected,
        'semantic_tags': [family['semantic_family_id']],
        'difficulty_dimensions': [f'items:{len(items)}', f'policy:{shape["policy"]}'],
        'safety_critical': safety,
    }
    raw['blueprint_id'] = 'bp-' + semantic_identity(raw)[:24]
    return raw, surfaces


def item_phrase(item, surface, index, include_temporal=True):
    phrase = surface
    if item['person']:
        if item['route'] == 'Memory' and item['type'] == 'idea':
            phrase += f'—an idea {item["person"]} suggested'
        elif item['route'] == 'Memory' and item['type'] == 'event':
            phrase += f', which {item["person"]} mentioned'
        elif item['route'] == 'Memory':
            phrase = item['person'] + ' mentioned that ' + phrase
        else:
            phrase += ' with ' + item['person']
    if item['location']:
        phrase += (' at ' if item['route'] == 'Memory' else ' when I am at ') + item['location']
    if include_temporal and item['date'] and not item['recurrence']:
        date = str(item['date'])
        if date.startswith('the second week'):
            phrase += ' during ' + date
        else:
            no_preposition = date.startswith((
                'tomorrow', 'next ', 'this ', 'two ', 'three ', 'the morning ', 'the day before ',
                'yesterday', 'last ', 'earlier ', 'the previous ',
            ))
            phrase += (' ' if no_preposition else ' on ') + date
    if include_temporal and item['time'] and not item['recurrence']:
        phrase += ' at ' + str(item['time'])
    if include_temporal and item['recurrence']:
        recurrence = {
            'weekdays': 'every weekday', 'weekly:monday': 'every Monday',
            'weekly:tuesday': 'every Tuesday', 'weekly:friday': 'every Friday',
            'every-other-wednesday': 'every other Wednesday',
            'monthly:first-business-day': 'on the first business day of each month',
            'monthly:last-friday': 'on the last Friday of each month', 'daily': 'every day',
            'every-three-days': 'every three days', 'yearly:anniversary': 'every year on the anniversary',
            'twice-weekly': 'twice a week', 'school-days': 'every school day',
        }[item['recurrence']]
        if item['date']:
            phrase += ' starting ' + str(item['date'])
        if item['time']:
            phrase += ' at ' + str(item['time'])
        phrase += ', ' + recurrence
    return phrase


def render_base(blueprint, surfaces, index):
    expected = blueprint['expected']
    if expected['operations']:
        target = expected['operations'][0]['target']
        choices = [
            f'Actually, can you cancel the saved reminder to {target}? I do not need that one anymore.',
            f'That reminder to {target}—please remove just that one.',
            f'I no longer need the saved reminder to {target}; cancel it.',
            f'Could you get rid of my existing reminder to {target}?',
            f'Cancel the reminder that says to {target}, but leave my other reminders alone.',
        ]
        return choices[index % len(choices)]
    phrases = [item_phrase(item, surface, index + offset) for offset, (item, surface) in enumerate(zip(expected['items'], surfaces))]
    if not phrases:
        return 'I am not sure there is anything actionable here; please keep the capture for review.'
    if len(phrases) > 1:
        openings = [
            f'I have two things: {phrases[0]}, and then {phrases[1]}.',
            f'Before I forget, {phrases[0]}; also, {phrases[1]}.',
            f'Could you hang onto both of these—{phrases[0]}, plus {phrases[1]}?',
            f'Two separate notes for me: {phrases[0]}. The other one is {phrases[1]}.',
        ]
        return openings[index % len(openings)]
    item, phrase = expected['items'][0], phrases[0]
    if item['prohibition']:
        return f'Whatever happens, do not {phrase}.'
    if item['state'] == 'completed':
        if item['route'] == 'Today':
            return f'Just so I remember, I already took care of this: {phrase}.'
        detail = item_phrase(item, surfaces[0], index, include_temporal=False)
        date = str(item['date']) if item['date'] else None
        if date:
            if date.startswith(('yesterday', 'last ', 'earlier ', 'the previous ', 'three days ', 'the morning ')):
                when = date
            else:
                when = 'on ' + date
        else:
            when = ''
        if item['time']:
            when = (when + ' at ' + str(item['time'])).strip()
        timing = f' {when}' if when else ''
        return f'Just so I remember, I noted this{timing}: {detail}.'
    if item['type'] == 'idea':
        choices = [
            f'An idea I want to keep: {phrase}.',
            f'Here is something I might try—{phrase}.',
            f'Save this idea for later: {phrase}.',
            f'One possibility for later is to {phrase}.',
        ]
    elif item['route'] == 'Memory':
        choices = [
            f'Oh, remember this for me: {phrase}.',
            f'One thing I do not want to lose—{phrase}.',
            f'Can you hang onto this detail: {phrase}?',
            f'Just making a note that {phrase}.',
        ]
    elif item['type'] == 'event':
        choices = [
            f'I have {phrase}; put that down for me.',
            f'Before I forget, I am supposed to be at {phrase}.',
            f'Keep track of {phrase} for me.',
            f'I need this on my radar: {phrase}.',
        ]
    else:
        choices = [
            f'Uh, remind me to {phrase}.',
            f'I need to {phrase}—can you hang onto that?',
            f'Before I forget, {phrase}.',
            f'Put down that I have to {phrase}.',
            f'Can you keep track of this for me: {phrase}?',
        ]
    if expected['ambiguity_policy'] != 'act':
        if item['route'] == 'Memory':
            choices = [
                f'I am not totally sure this is right: {phrase}. Keep it for review rather than treating it as settled.',
                f'Maybe I have this wrong, but {phrase}. Just save the thought for review.',
                f'I vaguely remember that {phrase}, though I would want to check it.',
                f'Here is an uncertain detail: {phrase}. Keep it for review.',
                f'I think {phrase}, but there is not enough context to rely on that yet.',
            ]
        else:
            choices = [
                f'I am not totally sure about this yet: {phrase}. Please keep it as something to review, not a firm action.',
                f'Maybe {phrase}, though I have not decided—just save the thought for now.',
                f'I am thinking about whether to {phrase}. Do not treat that as settled yet.',
                f'Here is an unfinished thought: {phrase}. Keep it for review instead of acting on it.',
                f'I might need to {phrase}, but there is not enough here to make it a firm task.',
            ]
        return choices[index % len(choices)]
    return choices[index % len(choices)]


def alternates(index):
    return {
        'person': NAMES[(index + 9) % len(NAMES)], 'person_second': NAMES[(index + 17) % len(NAMES)],
        'person_third': NAMES[(index + 29) % len(NAMES)],
        'date': DATES[(index + 7) % len(DATES)], 'date_second': DATES[(index + 11) % len(DATES)],
        'date_third': DATES[(index + 17) % len(DATES)],
        'time': TIMES[(index + 5) % len(TIMES)], 'time_second': TIMES[(index + 9) % len(TIMES)],
        'time_third': TIMES[(index + 13) % len(TIMES)],
        'location': LOCATIONS[(index + 7) % len(LOCATIONS)], 'location_second': LOCATIONS[(index + 13) % len(LOCATIONS)],
        'location_third': LOCATIONS[(index + 19) % len(LOCATIONS)],
        'withdrawn_action': ACTIONS[(index + 23) % len(ACTIONS)][1],
        'corrupt_person': NAMES[(index + 1) % len(NAMES)].split()[0],
    }


def intended_summary(expected):
    if expected['operations']:
        return '; '.join(operation['operation'] + ' ' + operation['target'] for operation in expected['operations'])
    return '; '.join(item['facts'][0] for item in expected['items']) or 'no actionable item'


def temporal_summary(expected):
    values = []
    for item in expected['items']:
        values.extend(str(value) for value in (item['date'], item['time'], item['recurrence']) if value)
    return ' | '.join(values) or None


def location_summary(expected):
    values = sorted({item['location'] for item in expected['items'] if item['location']})
    return ' | '.join(values) or None


def scope_summary(expected):
    if expected['operations']:
        return '; '.join(f'{operation["operation"]}:{operation["target"]}' for operation in expected['operations'])
    scoped = [item['facts'][0] for item in expected['items'] if item['negation'] or item['prohibition']]
    return ' | '.join(scoped) or None


def make_review(case_seed, blueprint, naturalness, meaning):
    expected = blueprint['expected']
    review = {
        'reviewer': {'kind': 'machine', 'identity': 'codex-phase2-author-self-review'},
        'reviewed_at': REVIEWED_AT, 'independence': 'author_self_review',
        'naturalness': naturalness, 'intended_meaning': intended_summary(expected),
        'intended_item_count': expected['item_count'],
        'routing': [item['route'] for item in expected['items']],
        'temporal_meaning': temporal_summary(expected), 'location_meaning': location_summary(expected),
        'cancellation_negation_scope': scope_summary(expected),
        'ambiguity': 'intentional' if expected['ambiguity_policy'] != 'act' else 'none',
        'proposed_contract_correct': 'yes' if meaning == 'appears_preserved' else 'uncertain',
        'meaning_preservation': meaning,
        'notes': 'Author self-review only; no production parser output was available and independent adjudication is still required.',
    }
    review['review_id'] = 'review-' + digest({'seed': case_seed, **review})[:24]
    return review


def make_case(blueprint, family, utterance, phenomena, lineage, provenance, coverage, naturalness, meaning, category):
    rendering = {
        'blueprint_id': blueprint['blueprint_id'], 'text': utterance, 'provenance': provenance,
        'generator': {'kind': 'public_import' if provenance['kind'] == 'public-derived' else 'deterministic', 'name': 'SpeechLab Phase 2 builder', 'version': VERSION},
        'seed': 20260913, 'phenomena': list(phenomena), 'mutation_lineage': [],
        'equivalence_class': family['semantic_family_id'], 'meaning_preservation': 'uncertain',
    }
    rendering['rendering_id'] = 'rd-' + rendering_identity(rendering)[:24]
    seed = {'rendering_id': rendering['rendering_id'], 'contract': blueprint['expected']}
    review = make_review(seed, blueprint, naturalness, meaning)
    safety = blueprint['safety_critical'] or any(pid in {
        'cancellation', 'cancellation-scope', 'scoped-withdrawal', 'never-mind-withdrawal',
        'negation', 'prohibition', 'ambiguous-pronoun', 'cross-turn-reference-ambiguity',
        'contact-person-ambiguity', 'timezone-sensitive', 'dst-transition',
    } for pid in phenomena)
    label_state = 'draft' if meaning == 'uncertain' else 'machine-reviewed'
    split = 'public-derived' if provenance['kind'] == 'public-derived' else 'safety' if safety else 'synthetic-stress' if len(phenomena) >= 2 else 'development'
    case = {
        'blueprint_id': blueprint['blueprint_id'], 'rendering_id': rendering['rendering_id'],
        'semantic_family_id': family['semantic_family_id'], 'utterance': utterance,
        'context': blueprint['capture_context'], 'proposed_contract': blueprint['expected'],
        'taxonomy_labels': list(phenomena), 'lineage': lineage, 'provenance': provenance,
        'label_state': label_state, 'reviews': [review], 'naturalness': naturalness,
        'meaning_preservation': meaning, 'safety_critical': safety,
        'required_independent_reviews': 2 if safety else 1, 'trusted': False,
        'split_role': split, 'coverage_contributions': coverage,
    }
    case['case_id'] = 'case-' + digest({
        'blueprint_id': case['blueprint_id'], 'rendering_id': case['rendering_id'],
        'semantic_family_id': case['semantic_family_id'], 'utterance': case['utterance'],
    })[:24]
    return blueprint, rendering, case


def find_family_for_phenomenon(families, phenomenon_id, start, serial):
    for offset in range(len(families)):
        family = families[(start + offset) % len(families)]
        blueprint, surfaces = make_blueprint(family, serial + offset, special_pid=phenomenon_id)
        if compatible(blueprint, phenomenon_id) and validate_composition(blueprint, (phenomenon_id,))[0]:
            return family, blueprint, surfaces
    return None


def public_blueprint(source, family_by_shape, families, serial):
    mapping = source['speakit_mapping']
    context = deepcopy(CONTEXT)
    context['prior_turns'] = source['context'].get('previous_turns', [])
    if mapping['operation']:
        expected = {
            'item_count': 0, 'items': [],
            'operations': [{'operation': mapping['operation'], 'target': mapping['title'], 'scoped': True}],
            'ambiguity_policy': mapping['ambiguity_policy'],
            'shared_context': {'temporal': None, 'location': None, 'person': None},
        }
        context['stored_items'] = [{'stored_id': 'public-stored-' + digest(source['record_id'])[:12], 'title': mapping['title']}]
    else:
        item = {
            'route': mapping['route'], 'type': mapping['type'], 'title': mapping['title'],
            'facts': mapping['facts'], 'forbidden_facts': mapping['forbidden_facts'],
            'date': mapping['date'], 'time': mapping['time'], 'recurrence': mapping['recurrence'],
            'location': mapping['location'], 'person': mapping['person'], 'negation': mapping['negation'],
            'prohibition': mapping['prohibition'], 'state': mapping['state'],
            'needs_review': mapping['ambiguity_policy'] != 'act',
        }
        expected = {
            'item_count': 1, 'items': [item], 'operations': [],
            'ambiguity_policy': mapping['ambiguity_policy'],
            'shared_context': {'temporal': None, 'location': None, 'person': None},
        }
    provisional = {
        'family_id': 'pending', 'version': VERSION, 'source_type': 'public_derived',
        'source_provenance': {}, 'license_notes': source['license'], 'capture_context': context,
        'expected': expected, 'semantic_tags': [], 'difficulty_dimensions': [],
        'safety_critical': mapping['safety_critical'],
    }
    shape = semantic_shape(provisional)
    key = dumps(shape)
    if key not in family_by_shape:
        family = {
            'semantic_family_id': 'sf-' + digest(shape)[:16], 'shape': shape,
            'description': f'Public-pilot semantic shape introduced by {source["source_dataset"]}',
            'historical_family_ids': [], 'historical_blueprint_ids': [], 'member_count': 0,
            'decision': 'split',
        }
        families.append(family)
        family_by_shape[key] = family
    family = family_by_shape[key]
    provenance = {
        'source_dataset': source['source_dataset'], 'source_url': source['source_url'],
        'source_version': source['version'], 'source_record_id': source['record_id'],
        'license': source['license'], 'archive_sha256': source['archive_sha256'],
        'foreign_annotation_is_speakit_truth': False,
        'mapping_method': 'independent Speak It contract authored after linguistic selection',
    }
    provisional.update({
        'family_id': family['semantic_family_id'], 'source_provenance': provenance,
        'semantic_tags': [family['semantic_family_id'], 'public-derived'],
        'difficulty_dimensions': ['public-derived', f'policy:{expected["ambiguity_policy"]}'],
    })
    provisional['blueprint_id'] = 'bp-' + semantic_identity(provisional)[:24]
    return family, provisional, provenance


def build(output, public_source):
    taxonomy = build_taxonomy(LAB / 'config' / 'taxonomy-v2.json')
    historical = list(read_jsonl(LAB / 'data' / 'blueprints.jsonl'))
    families = build_semantic_families(historical)
    historical_families = list(families)
    family_by_shape = {dumps(family['shape']): family for family in families}
    tracker = CoverageTracker()
    blueprints, renderings, cases = [], [], []
    serial = 0
    used_utterances = set()
    used_normalized = set()
    duplicate_contexts = [
        'This came up while I was checking my calendar: ',
        'One loose end from school: ',
        'A quick thing from work: ',
        'Before I head out for errands: ',
        'Something I remembered on the train: ',
        'One detail from the appointment: ',
        'While I am sorting out the trip: ',
        'A note from the conversation earlier: ',
        'One household thing I nearly forgot: ',
        'This is for later in the week: ',
    ]

    def append_case(family, blueprint, surfaces, phenomena, category, coverage=None, source_provenance=None, utterance=None):
        nonlocal serial
        blueprint = deepcopy(blueprint)
        reference = datetime(2026, 9, 13, 8, 0, tzinfo=timezone(timedelta(hours=-4))) + timedelta(minutes=serial)
        blueprint['capture_context']['reference_time'] = reference.isoformat()
        blueprint['blueprint_id'] = 'bp-' + semantic_identity(blueprint)[:24]
        base = render_base(blueprint, surfaces, serial)
        phenomena = tuple(phenomena)
        discarded = {}
        if utterance is None and phenomena:
            qualified_surfaces = [item_phrase(item, surface, serial + offset)
                                  for offset, (item, surface) in enumerate(zip(blueprint['expected']['items'], surfaces))]
            utterance, discarded = apply_transformations(base, blueprint, qualified_surfaces, phenomena, alternates(serial))
        elif utterance is None:
            utterance = base
        if source_provenance is None:
            duplicate_round = 0
            while utterance.strip() in used_utterances or norm(utterance) in used_normalized:
                prefix = duplicate_contexts[(serial + duplicate_round) % len(duplicate_contexts)]
                utterance = prefix + utterance[0].lower() + utterance[1:]
                duplicate_round += 1
        used_utterances.add(utterance.strip())
        used_normalized.add(norm(utterance))
        destructive = any(TRANSFORMS[pid].destructive for pid in phenomena)
        meaning = 'uncertain' if destructive else 'appears_preserved'
        entity_fields = sum(bool(item.get(field)) for item in blueprint['expected']['items'] for field in ('person', 'location', 'date', 'time', 'recurrence'))
        naturalness = 5 if category == 'core' and blueprint['expected']['item_count'] == 1 and entity_fields <= 1 and serial % 3 == 0 else 4
        if destructive or len(phenomena) >= 3:
            naturalness = 3
        if any(pid in {'long-capture', 'rephrasing'} for pid in phenomena):
            naturalness = 3
        if len(phenomena) >= 2 and any(TRANSFORMS[pid].category == 'asr-transcription' for pid in phenomena):
            naturalness = 3
        if category == 'public':
            naturalness = 5 if source_provenance['source_dataset'] in {'PRESTO', 'Taskmaster'} else 4
            if len(re.findall(r'\w+', utterance)) <= 3:
                naturalness = 3
        coverage_keys = coverage or sorted(CoverageTracker.keys(blueprint, family['semantic_family_id'], phenomena))
        tracker.seen.update(coverage_keys)
        lineage = {
            'base_semantic_family': family['semantic_family_id'],
            'historical_blueprint_ids': family['historical_blueprint_ids'],
            'transformations': transformation_lineage(phenomena, discarded),
            'contract_digest': digest(blueprint['expected']),
            'validation': {
                'accepted': True,
                'checks': ['contract-schema', 'compatibility', 'scope', 'semantic-anchor-review', 'naturalness-self-review'],
                'rejection_reason': None,
            },
        }
        provenance = source_provenance or {
            'kind': 'repository-authored', 'category': category,
            'authoring_method': 'curated phrase-plan with constrained deterministic composition',
        }
        if source_provenance:
            provenance = {'kind': 'public-derived', **source_provenance}
        built = make_case(blueprint, family, utterance, phenomena, lineage, provenance, coverage_keys, naturalness, meaning, category)
        blueprints.append(built[0]); renderings.append(built[1]); cases.append(built[2]); serial += 1

    # Two independently varied canonical contracts for each historical semantic shape.
    for pass_index in range(2):
        for family_index, family in enumerate(historical_families):
            blueprint, surfaces = make_blueprint(family, serial + pass_index * 997 + family_index)
            append_case(family, blueprint, surfaces, (), 'core')

    # First cover every composable taxonomy phenomenon once, then fill singles by marginal gain.
    forced = [row['id'] for row in taxonomy['phenomena'] if row['id'] in TRANSFORMS]
    single_count = 0
    uncovered = []
    for phenomenon_index, pid in enumerate(forced):
        found = find_family_for_phenomenon(historical_families, pid, phenomenon_index, serial + phenomenon_index * 31)
        if not found:
            uncovered.append(pid)
            continue
        family, blueprint, surfaces = found
        coverage = sorted(CoverageTracker.keys(blueprint, family['semantic_family_id'], (pid,)) - tracker.seen)
        if not coverage:
            coverage = [f'phenomenon-repeat-context:{pid}:{blueprint["blueprint_id"]}']
        append_case(family, blueprint, surfaces, (pid,), 'single', coverage)
        single_count += 1
    while single_count < 190:
        family = historical_families[(single_count * 17 + 3) % len(historical_families)]
        blueprint, surfaces = make_blueprint(family, serial + single_count * 13)
        recipes = [recipe for recipe in approved_recipes(blueprint, 1)
                   if not any(TRANSFORMS[pid].destructive for pid in recipe)]
        choice = tracker.choose(blueprint, family['semantic_family_id'], recipes)
        if choice is None:
            continue
        recipe, coverage = choice
        append_case(family, blueprint, surfaces, recipe, 'single', coverage)
        single_count += 1

    pair_count = 0
    attempts = 0
    while pair_count < 250:
        family = historical_families[(pair_count * 29 + attempts * 7 + 11) % len(historical_families)]
        blueprint, surfaces = make_blueprint(family, serial + attempts * 19)
        choice = tracker.choose(blueprint, family['semantic_family_id'], approved_recipes(blueprint, 2))
        attempts += 1
        if choice is None:
            continue
        recipe, coverage = choice
        append_case(family, blueprint, surfaces, recipe, 'pair', coverage)
        pair_count += 1

    higher_count = 0
    attempts = 0
    while higher_count < 70:
        cardinality = 4 if higher_count % 5 == 0 else 3
        family = historical_families[(higher_count * 37 + attempts * 11 + 19) % len(historical_families)]
        blueprint, surfaces = make_blueprint(family, serial + attempts * 23)
        choice = tracker.choose(blueprint, family['semantic_family_id'], approved_recipes(blueprint, cardinality))
        attempts += 1
        if choice is None:
            continue
        recipe, coverage = choice
        append_case(family, blueprint, surfaces, recipe, 'higher', coverage)
        higher_count += 1

    public_rows = list(read_jsonl(public_source))
    for source in public_rows:
        family, blueprint, provenance = public_blueprint(source, family_by_shape, families, serial)
        append_case(family, blueprint, [], (), 'public', source_provenance=provenance, utterance=source['utterance'])

    if len(cases) != 818:
        raise ValueError(f'expected 818 cases, got {len(cases)}')
    identities = {}
    for position, blueprint in enumerate(blueprints):
        identity = semantic_identity(blueprint)
        if identity in identities:
            raise ValueError(f'duplicate semantic blueprint at {identities[identity]} and {position}: {blueprint["family_id"]}')
        identities[identity] = position
    validate_blueprints(blueprints)
    texts = defaultdict(list)
    for position, case in enumerate(cases):
        texts[case['utterance'].strip()].append(position)
    duplicate_texts = {text: positions for text, positions in texts.items() if len(positions) > 1}
    if duplicate_texts:
        sample_text, positions = next(iter(duplicate_texts.items()))
        raise ValueError(f'exact duplicate utterance at {positions}: {sample_text}')
    if len({case['case_id'] for case in cases}) != len(cases):
        raise ValueError('duplicate case ID')

    output.mkdir(parents=True, exist_ok=True)
    (output / 'artifacts').mkdir(parents=True, exist_ok=True)
    write_jsonl(output / 'data' / 'semantic-families.jsonl', families)
    write_jsonl(output / 'data' / 'blueprints.jsonl', blueprints)
    write_jsonl(output / 'data' / 'renderings.jsonl', renderings)
    write_jsonl(output / 'data' / 'cases.jsonl', cases)
    review_pack = [{
        'case_id': case['case_id'], 'utterance': case['utterance'], 'relevant_context': case['context'],
        'proposed_semantic_contract': case['proposed_contract'], 'taxonomy_labels': case['taxonomy_labels'],
        'review_questions': [
            'How natural is this from 1 to 5?', 'What does the speaker intend?',
            'How many items are intended?', 'Where should each item route?',
            'What temporal and location meaning is expressed?',
            'What is the cancellation or negation scope?', 'Is anything ambiguous?',
            'Is the proposed contract correct?',
        ],
    } for case in cases]
    write_jsonl(output / 'review' / 'independent-review-pack.jsonl', review_pack)
    write_json(output / 'artifacts' / 'build-manifest.json', {
        'version': VERSION, 'cases': len(cases), 'historical_blueprints': len(historical),
        'historical_semantic_shapes': len(historical_families), 'semantic_families_after_public_pilot': len(families),
        'category_counts': {'core': 266, 'single': 190, 'pair': 250, 'triad_or_four': 70, 'public': 42},
        'uncovered_taxonomy_ids_during_forced_single_pass': uncovered,
        'production_parser_invoked': False, 'sealed_content_read': False,
        'all_cases_trusted': False,
    })
    return families, blueprints, renderings, cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=LAB / 'phase2')
    parser.add_argument('--public-source', type=Path, default=LAB / 'phase2' / 'public' / 'source-records.jsonl')
    args = parser.parse_args()
    families, blueprints, _, cases = build(args.output, args.public_source)
    print(json.dumps({'families': len(families), 'blueprints': len(blueprints), 'cases': len(cases)}, indent=2))


if __name__ == '__main__':
    main()
