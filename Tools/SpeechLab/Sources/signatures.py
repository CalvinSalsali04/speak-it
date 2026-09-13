"""Stable failure clustering and compact failure-pack export."""
from collections import defaultdict
import json
import re
import sqlite3

from .contracts import digest, dumps, norm, validate


def normalize_difference(payload):
    diff = payload['difference']; expected = payload['expected']
    replacements = []
    for item in expected['items']:
        replacements += [item.get('person'), item.get('location')] + item.get('facts', [])
    literal = dumps(diff); normalized = literal.casefold()
    for value in sorted((str(v) for v in replacements if v), key=len, reverse=True):
        normalized = re.sub(re.escape(value.casefold()), '<entity>', normalized)
    normalized = re.sub(r'\b\d+(?::\d+)?\b', '<number>', normalized)
    direction = '|'.join(diff['changed_fields']) or 'pass'
    return literal, direction + ':' + digest(normalized)[:16]


def broad_family(fields):
    values = set(fields)
    if values & {'negation_correctness', 'prohibition_correctness', 'cancellation_correctness'}: return 'polarity-or-operation'
    if values & {'date_preservation', 'time_preservation', 'recurrence_preservation'}: return 'temporal'
    if values & {'location_preservation', 'person_preservation'}: return 'entity'
    if values & {'item_count', 'over_split', 'under_split', 'wrong_merge'}: return 'segmentation'
    if values & {'routing', 'type'}: return 'route-or-type'
    if values & {'lost_information', 'invented_information', 'title_content_preservation'}: return 'content'
    return 'other'


def cluster(db_path, run_id, representative_limit=3):
    con = sqlite3.connect(db_path)
    groups = defaultdict(list); passes = []
    for (raw,) in con.execute('SELECT payload_json FROM results WHERE run_id=? ORDER BY rendering_id', (run_id,)):
        payload = json.loads(raw)
        if payload['metrics']['passed']: passes.append(payload); continue
        literal, normalized = normalize_difference(payload); groups[(literal, normalized)].append(payload)
    result = []
    for (literal, normalized), rows in sorted(groups.items(), key=lambda x: (-len(x[1]), x[0][1])):
        fields = rows[0]['difference']['changed_fields']
        signature = dict(literal=literal, normalized_directional=normalized, family=broad_family(fields),
                         changed_fields=fields, count=len(rows), first_seen=rows[0]['rendering_id'],
                         representatives=[{'rendering_id': r['rendering_id'], 'text': r['input_text'], 'difference': r['difference']} for r in rows[:representative_limit]],
                         counterexamples=[{'rendering_id': r['rendering_id'], 'text': r['input_text']} for r in passes[:1]])
        validate('failure-signature', signature)
        result.append(signature)
    con.close(); return result


def failure_pack(db_path, run_id, path):
    rows = cluster(db_path, run_id)
    with open(path, 'w') as stream:
        for row in rows: stream.write(dumps(row) + '\n')
    return {'signatures': len(rows), 'failed_cases': sum(r['count'] for r in rows), 'path': str(path)}
