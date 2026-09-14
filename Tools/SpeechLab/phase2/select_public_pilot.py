#!/usr/bin/env python3
"""Select the bounded, text-only public-data pilot from verified sources.

Foreign annotations are retained as provenance only. The explicit
``speakit_mapping`` table below is authored independently for SpeechLab and is
not derived by converting source intents.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import tarfile
import zipfile


PRESTO_IDS = [
    '5ffcf06db8a4473c084eb7e5384b32d4d0059eae51b7c05ab2d8f667a111776b',
    'eddcf47f685ccd8c0546b8d5e1c055a300e9a9d6d658ebe30ee4dfccd5ec1182',
    '3cfa9a810a444ac2f2a8c924e9799d6d59cd999faadb898c9f038a5d59d072e6',
    '1345d4cb04ff89cd4453346a8965aab6ca5f1d639b5bc7e9b6ec790549484d9e',
    '38dcc95a1a3818fa787d60c90e8817d0858eb906c4d60874e29d47a58842c594',
    'e59054c69de33411a996c22884d5bc86d5cf1adab5f6441d434f64191cc18062',
    '0a6941bdc29353f680c4e8fb17d566a7da62b4f365bae17a647dd790b45a3bba',
    'b87f277f99195b7404987f379c73587dc025983e9ef1532718fd73ca48389489',
    '5d1d429b451c89466109211083160b150385e6b2f7ae29848303c7b37df450d6',
    '17ef71f1920e71cd87af80577fb45fe9eebb1891c141fd128099a2f6a8bc2bc3',
    'd89327f803b0074f51d8457b3393f9beb6a50b2983ee76d4b1bc4aa022d1f855',
    '1c2d65042b6bad464d91722d78de1a0bbfe8881115332fe9dd8516abf4791593',
]
MASSIVE_IDS = ['0', '1', '2', '94', '95', '173', '174', '234', '418', '535']
SLURP_IDS = [6744, 6878, 7292, 7916, 7768, 16593, 8642, 7891, 8570, 8251]
TASKMASTER_TURNS = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18]


def mapping(title, *, kind='task', route='Today', facts=None, forbidden=None, date=None, time=None,
            recurrence=None, location=None, person=None, state='outstanding', policy='act',
            negation=False, prohibition=False, safety=False, operation=None):
    return {
        'route': route, 'type': kind, 'title': title, 'facts': facts or [title],
        'forbidden_facts': forbidden or [], 'date': date, 'time': time,
        'recurrence': recurrence, 'location': location, 'person': person,
        'state': state, 'ambiguity_policy': policy, 'negation': negation,
        'prohibition': prohibition, 'safety_critical': safety, 'operation': operation,
    }


MAPPINGS = {
    PRESTO_IDS[0]: mapping('send the screenshot to Mike and copy Josh', person='Mike', forbidden=['copy John']),
    PRESTO_IDS[1]: mapping('email dad', person='dad', forbidden=['email mom']),
    PRESTO_IDS[2]: mapping('email the boss', person='boss', forbidden=['email my sister']),
    PRESTO_IDS[3]: mapping('send the ETA through WhatsApp', forbidden=['send through Snapchat']),
    PRESTO_IDS[4]: mapping('send the video attachment', forbidden=['send the photo attachment']),
    PRESTO_IDS[5]: mapping('text Kelly', person='Kelly', forbidden=['email Kelly']),
    PRESTO_IDS[6]: mapping('text my location to Chloe', person='Chloe', forbidden=['send the ETA']),
    PRESTO_IDS[7]: mapping('email my manager', person='my manager', forbidden=['email all coworkers']),
    PRESTO_IDS[8]: mapping('send Wes a thank-you card by message', person='Wes'),
    PRESTO_IDS[9]: mapping('send Beth a voice message saying I will arrive on time', person='Beth', forbidden=['I will arrive late']),
    PRESTO_IDS[10]: mapping('email Becky that I am on the way', person='Becky', forbidden=['call Becky']),
    PRESTO_IDS[11]: mapping('send the ETA through WhatsApp'),
    'massive:0': mapping('wake up at five this week', kind='note', route='Memory', policy='review', state='uncertain', safety=True),
    'massive:1': mapping('wake up at nine on Friday', kind='reminder', date='Friday', time='09:00', safety=True),
    'massive:2': mapping('wake up in two hours', kind='reminder', date='relative:+2h', safety=True),
    'massive:94': mapping('wake up in forty minutes', kind='reminder', date='relative:+40m', safety=True),
    'massive:95': mapping('wake up at eight every weekday', kind='reminder', date='next weekday', time='08:00', recurrence='weekdays', safety=True),
    'massive:173': mapping('wake up tomorrow at six', kind='reminder', date='tomorrow', time='06:00', safety=True),
    'massive:174': mapping('wake up Thursday at seven', kind='reminder', date='Thursday', time='07:00', safety=True),
    'massive:234': mapping('go to the concert at three', kind='reminder', date='reference day', time='15:00', safety=True),
    'massive:418': mapping('wake up at eight forty-five', kind='reminder', date='reference day', time='08:45', safety=True),
    'massive:535': mapping('wake up at one', kind='reminder', date='reference day', time='13:00', safety=True),
    'slurp:6744': mapping('meeting with Pawel', kind='event', date='tomorrow', time='10:00', person='Pawel', safety=True),
    'slurp:6878': mapping('meeting with the accounting department', kind='event', date='Friday', time='14:30', location='accounting department', safety=True),
    'slurp:7292': mapping('email the boss in one hour', kind='reminder', date='relative:+1h', person='boss', safety=True),
    'slurp:7916': mapping('take out the garbage at six', kind='reminder', date='reference day', time='18:00', safety=True),
    'slurp:7768': mapping('practice at King’s Park', kind='event', date='February 4', time='14:00', location='King’s Park', safety=True),
    'slurp:16593': mapping('answer the last email as soon as possible', kind='note', route='Memory', policy='review', state='uncertain', safety=True),
    'slurp:8642': mapping('conference call at four', kind='reminder', date='today', time='16:00', safety=True),
    'slurp:7891': mapping('cancel dinner tonight', operation='cancel', safety=True),
    'slurp:8570': mapping('busy for an event tomorrow at two', kind='event', date='tomorrow', time='14:00', safety=True),
    'slurp:8251': mapping('lunch next week', kind='event', date='next week', safety=True),
    'taskmaster:0': mapping('book a table for Korean food'),
    'taskmaster:2': mapping('prefer a restaurant in the East Village', kind='note', route='Memory', state='informational', policy='review'),
    'taskmaster:4': mapping('book a table tonight at seven for eight people', facts=['book a table for 8 people'], forbidden=['seat at the bar'], date='tonight', time='19:00', location='East Village', safety=True),
    'taskmaster:6': mapping('ask which reservation times are available', kind='note', route='Memory', state='uncertain', policy='review'),
    'taskmaster:8': mapping('the offered reservation times do not work', kind='memory', route='Memory', state='informational', policy='review', negation=True),
    'taskmaster:10': mapping('check the alternative restaurant choice', kind='note', route='Memory', state='uncertain', policy='preserve-only'),
    'taskmaster:12': mapping('check whether Boka can seat eight people at seven', person=None, date='tonight', time='19:00', location='Boka', safety=True),
    'taskmaster:14': mapping('book the agreed restaurant reservation', policy='review', safety=True),
    'taskmaster:16': mapping('book only the agreed restaurant reservation', policy='review', safety=True),
    'taskmaster:18': mapping('use the open restaurant account', kind='note', route='Memory', state='uncertain', policy='review', safety=True),
}


SOURCES = {
    'PRESTO': {
        'source_url': 'https://github.com/google-research-datasets/presto',
        'version': 'presto_v1.zip; repository fa47167477453afebe698a287409514df5a7dadf',
        'archive_sha256': '1fc671692cceb31fbda17e351e47f2cc52ee8779042f92dc26674cc0cca2167f',
        'license': 'CC BY 4.0',
    },
    'MASSIVE': {
        'source_url': 'https://github.com/alexa/massive',
        'version': '1.0; repository f966f21846043aabef9b0f974fa7970027f43738',
        'archive_sha256': '7df623fd2d300a4d235d6ee5bd396c9a28258d3a0ccb29abdb054506eba153f8',
        'license': 'CC BY 4.0',
    },
    'Taskmaster': {
        'source_url': 'https://github.com/google-research-datasets/Taskmaster/tree/master/TM-1-2019',
        'version': 'TM-1 sample at d92cb6af3005f1dc09c39e75e7daf4a04905e00b',
        'archive_sha256': '83fa11504f6e6a8b32fc4f140db82ed624d0e1fdfd0b48f4f40b60c118ac266d',
        'license': 'CC BY 4.0',
    },
    'SLURP-text': {
        'source_url': 'https://github.com/pswietojanski/slurp',
        'version': 'test.jsonl at 8eb16545762be97ace75334109d73824217311f1',
        'archive_sha256': 'fe3449af69b42fda7163345482556066c35a80f7e552a6d67e212a0e2f0783cc',
        'license': 'CC BY 4.0 for text, as recorded by MASSIVE NOTICE',
    },
}


def base_record(dataset, record_id, utterance, context, foreign_annotation, mapping_key, reason):
    return {
        'source_dataset': dataset,
        **SOURCES[dataset],
        'record_id': str(record_id),
        'utterance': utterance,
        'context': context,
        'foreign_annotation': foreign_annotation,
        'foreign_annotation_is_speakit_truth': False,
        'speakit_mapping': MAPPINGS[mapping_key],
        'mapping_review_state': 'machine-reviewed',
        'selection_reason': reason,
        'audio_used': False,
    }


def select(args):
    rows = []
    with zipfile.ZipFile(args.presto) as archive:
        members = [
            'test_partitions/en-US/en-US_revisions/test.jsonl',
            'test_partitions/en-US/en-US_disfluency/test.jsonl',
        ]
        found = {}
        for member in members:
            with archive.open(member) as stream:
                for raw in stream:
                    row = json.loads(raw)
                    found[row['metadata']['example_id']] = row
        for record_id in PRESTO_IDS:
            row = found[record_id]
            rows.append(base_record(
                'PRESTO', record_id, row['inputs'], {'previous_turns': row['metadata']['previous_turns']},
                {'target': row['targets'], 'linguistic_phenomena': row['metadata']['linguistic_phenomena']},
                record_id, 'natural revision or disfluency with an explicit final action',
            ))

    massive_path = args.massive_en
    if massive_path is None:
        with tarfile.open(args.massive) as archive:
            stream = archive.extractfile('1.0/data/en-US.jsonl')
            massive = [json.loads(raw) for raw in stream]
    else:
        massive = [json.loads(raw) for raw in massive_path.open()]
    by_id = {row['id']: row for row in massive}
    for record_id in MASSIVE_IDS:
        row = by_id[record_id]
        rows.append(base_record(
            'MASSIVE', record_id, row['utt'], {}, {'intent': row['intent'], 'annotated_utterance': row['annot_utt']},
            'massive:' + record_id, 'compact human-authored temporal language',
        ))

    slurp = {row['slurp_id']: row for row in (json.loads(raw) for raw in args.slurp.open())}
    for record_id in SLURP_IDS:
        row = slurp[record_id]
        rows.append(base_record(
            'SLURP-text', record_id, row['sentence'], {},
            {'intent': row['intent'], 'sentence_annotation': row['sentence_annotation']},
            'slurp:' + str(record_id), 'spoken syntax for calendar, reminder, email, or cancellation language',
        ))

    with args.taskmaster.open() as stream:
        taskmaster = json.load(stream)
    conversation = taskmaster if isinstance(taskmaster, dict) else taskmaster[0]
    utterances = conversation['utterances']
    for index in TASKMASTER_TURNS:
        row = utterances[index]
        previous = [{'speaker': item['speaker'], 'text': item['text']} for item in utterances[max(0, index - 4):index]]
        rows.append(base_record(
            'Taskmaster', f'{conversation["conversation_id"]}:{index}', row['text'], {'previous_turns': previous},
            {'segments': row.get('segments', [])}, 'taskmaster:' + str(index),
            'dialogue-derived reference, rejection, preference, or longer request',
        ))
    if len(rows) != 42 or len({(row['source_dataset'], row['record_id']) for row in rows}) != 42:
        raise ValueError('public pilot must contain exactly 42 distinct source records')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('w') as stream:
        for row in rows:
            stream.write(json.dumps(row, sort_keys=True, ensure_ascii=False, separators=(',', ':')) + '\n')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--presto', type=Path, required=True)
    parser.add_argument('--massive', type=Path)
    parser.add_argument('--massive-en', type=Path)
    parser.add_argument('--taskmaster', type=Path, required=True)
    parser.add_argument('--slurp', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not args.massive and not args.massive_en:
        parser.error('one of --massive or --massive-en is required')
    rows = select(args)
    print(json.dumps({'selected': len(rows), 'output': str(args.output)}, indent=2))


if __name__ == '__main__':
    main()
