"""SQLite-backed complete-result evaluator for the production probe."""
import hashlib
import json
import os
from pathlib import Path
import platform
import sqlite3
import subprocess
import sys
import time

from .contracts import VERSION, digest, dumps, file_hash, norm, validate

FIELDS = ('route', 'type', 'date', 'time', 'recurrence', 'location', 'person',
          'negation', 'prohibition', 'cancellation', 'state', 'title_content')


def _present(value):
    return value not in (None, '', 'nil')


def score(expected, actual):
    """Compare explicit product contracts to the probe's stable JSON shape."""
    wanted, got = expected['items'], actual.get('items', [])
    metrics = {}
    metrics['item_count'] = len(wanted) == len(got)
    metrics['over_split'] = len(got) <= len(wanted)
    metrics['under_split'] = len(got) >= len(wanted)
    metrics['false_positive_item_creation'] = not (not wanted and got)
    metrics['false_negative_item_creation'] = not (wanted and not got)
    pairs = list(zip(wanted, got))
    metrics['routing'] = len(pairs) == len(wanted) == len(got) and all(a['route'] == b.get('route') for a, b in pairs)
    metrics['type'] = len(pairs) == len(wanted) == len(got) and all(a['type'] == b.get('type') for a, b in pairs)
    metrics['date_preservation'] = all((a['date'] is None) == (not _present(b.get('due')) and not _present(b.get('reminder'))) for a, b in pairs) and len(pairs) == len(wanted)
    metrics['time_preservation'] = all((a['time'] is None) == (not _present(b.get('reminder'))) for a, b in pairs) and len(pairs) == len(wanted)
    metrics['recurrence_preservation'] = all((a['recurrence'] is None) == (not _present(b.get('recurrence'))) for a, b in pairs) and len(pairs) == len(wanted)
    metrics['location_preservation'] = all((a['location'] is None) == (not _present(b.get('location'))) for a, b in pairs) and len(pairs) == len(wanted)
    metrics['person_preservation'] = all((a['person'] is None) == (not _present(b.get('person'))) for a, b in pairs) and len(pairs) == len(wanted)
    actual_text = norm(' '.join(str(i.get('title', '')) + ' ' + str(i.get('quote', '')) for i in got))
    required = [norm(f) for item in wanted for f in item['facts'] if norm(f)]
    forbidden = [norm(f) for item in wanted for f in item['forbidden_facts'] if norm(f)]
    metrics['title_content_preservation'] = all(x in actual_text for x in required) and not any(x in actual_text for x in forbidden)
    metrics['negation_correctness'] = all(not a['negation'] or b.get('state') in ('completed', 'informational', 'uncertain') or 'not' in norm(b.get('title', '')) for a, b in pairs)
    metrics['prohibition_correctness'] = all(not a['prohibition'] or 'not' in norm(b.get('title', '')) or "don t" in norm(b.get('title', '')) for a, b in pairs)
    operations = actual.get('operations', [])
    metrics['cancellation_correctness'] = (not expected['operations'] and not operations) or expected['operations'] == operations
    policy = expected['ambiguity_policy']
    metrics['review_ambiguity_behavior'] = policy not in ('review', 'preserve-only') or any(i.get('needsReview') for i in got)
    metrics['wrong_merge'] = metrics['item_count']
    metrics['lost_information'] = metrics['title_content_preservation'] and metrics['false_negative_item_creation']
    no_temporal = all(i['date'] is None and i['time'] is None and i['recurrence'] is None for i in wanted)
    no_entities = all(i['person'] is None and i['location'] is None for i in wanted)
    metrics['invented_information'] = not ((no_temporal and any(_present(i.get('due')) or _present(i.get('reminder')) or _present(i.get('recurrence')) for i in got)) or
                                          (no_entities and any(_present(i.get('person')) or _present(i.get('location')) for i in got)))
    metrics['passed'] = all(metrics.values())
    changed = sorted(k for k, ok in metrics.items() if not ok and k != 'passed')
    difference = dict(changed_fields=changed,
                      lost_facts=[f for f in required if f not in actual_text],
                      invented_metadata=[] if metrics['invented_information'] else ['temporal_or_entity'],
                      expected_item_count=len(wanted), actual_item_count=len(got))
    return metrics, difference


DDL = """
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS runs (
 run_id TEXT PRIMARY KEY, created_at TEXT NOT NULL, config_json TEXT NOT NULL,
 config_hash TEXT NOT NULL, probe_hash TEXT NOT NULL, dataset_hash TEXT NOT NULL,
 expected_count INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'running'
);
CREATE TABLE IF NOT EXISTS results (
 run_id TEXT NOT NULL REFERENCES runs(run_id), rendering_id TEXT NOT NULL,
 blueprint_id TEXT NOT NULL, passed INTEGER NOT NULL, route TEXT, item_count INTEGER,
 literal_signature TEXT, normalized_signature TEXT, duration_ms REAL NOT NULL,
 payload_json TEXT NOT NULL, payload_hash TEXT NOT NULL,
 PRIMARY KEY(run_id, rendering_id)
);
CREATE INDEX IF NOT EXISTS idx_results_blueprint ON results(run_id, blueprint_id);
CREATE INDEX IF NOT EXISTS idx_results_passed ON results(run_id, passed);
CREATE INDEX IF NOT EXISTS idx_results_signature ON results(run_id, normalized_signature);
"""


def environment(probe):
    return {'speechlab_version': VERSION, 'python': sys.version.split()[0], 'platform': platform.platform(),
            'probe_path': str(Path(probe).resolve()), 'pid': os.getpid()}


def run(blueprints, renderings, db_path, probe, *, preset='diagnostic', phenomena=None,
        worker_index=0, worker_count=1, limit=None, batch_size=100, sealed=False):
    if not 0 <= worker_index < worker_count or worker_count < 1:
        raise ValueError('Invalid worker partition')
    probe = Path(probe).resolve(); db_path = Path(db_path)
    if not probe.exists(): raise FileNotFoundError(f'Build probe first: {probe}')
    selected = [r for r in renderings.values() if not phenomena or set(r['phenomena']) & set(phenomena)]
    selected = [r for r in selected if int(hashlib.sha256(r['rendering_id'].encode()).hexdigest(), 16) % worker_count == worker_index]
    selected.sort(key=lambda r: r['rendering_id'])
    if limit is not None: selected = selected[:limit]
    probe_hash = file_hash(probe)
    dataset_hash = digest([(r['rendering_id'], r['blueprint_id'], digest(blueprints[r['blueprint_id']]['expected'])) for r in selected])
    config = dict(version=VERSION, preset=preset, phenomena=sorted(phenomena or []), worker_index=worker_index,
                  worker_count=worker_count, limit=limit, batch_size=batch_size, sealed=sealed)
    config_hash = digest(config)
    run_id = 'run-' + digest({'config': config_hash, 'probe': probe_hash, 'dataset': dataset_hash})[:24]
    db_path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(db_path, timeout=60); con.executescript(DDL)
    columns = {row[1] for row in con.execute('PRAGMA table_info(runs)')}
    if 'expected_count' not in columns:
        con.execute('ALTER TABLE runs ADD COLUMN expected_count INTEGER NOT NULL DEFAULT 0')
    old = con.execute('SELECT config_hash,probe_hash,dataset_hash FROM runs WHERE run_id=?', (run_id,)).fetchone()
    if old and tuple(old) != (config_hash, probe_hash, dataset_hash): raise ValueError('Run identity/config mismatch')
    con.execute("INSERT OR IGNORE INTO runs(run_id,created_at,config_json,config_hash,probe_hash,dataset_hash,expected_count) VALUES(?,datetime('now'),?,?,?,?,?)",
                (run_id, dumps(config), config_hash, probe_hash, dataset_hash, len(selected)))
    con.execute('UPDATE runs SET expected_count=? WHERE run_id=? AND expected_count=0', (len(selected), run_id)); con.commit()
    completed = {x[0] for x in con.execute('SELECT rendering_id FROM results WHERE run_id=?', (run_id,))}
    todo = [r for r in selected if r['rendering_id'] not in completed]
    env = environment(probe)
    for offset in range(0, len(todo), batch_size):
        batch = todo[offset:offset + batch_size]
        started = time.monotonic()
        proc = subprocess.run([str(probe), '--json'], input='\n'.join(r['text'] for r in batch) + '\n',
                              text=True, capture_output=True, timeout=600)
        elapsed = (time.monotonic() - started) * 1000 / max(1, len(batch))
        outputs = {}
        if proc.returncode == 0:
            for line in proc.stdout.splitlines():
                obj = json.loads(line)
                if obj['text'] in outputs: raise ValueError('Duplicate probe result')
                outputs[obj['text']] = obj
        for rendering in batch:
            expected = blueprints[rendering['blueprint_id']]['expected']
            actual = outputs.get(rendering['text'], {'items': [], 'operations': [], 'error': proc.stderr or 'missing probe output'})
            metrics, difference = score(expected, actual)
            if 'error' in actual: metrics['passed'] = False; difference['changed_fields'].append('probe_error')
            literal = dumps(difference)
            normalized = '|'.join(difference['changed_fields']) or 'pass'
            payload = dict(run_id=run_id, rendering_id=rendering['rendering_id'], blueprint_id=rendering['blueprint_id'],
                           input_text=rendering['text'], expected=expected, actual=actual,
                           expected_hash=digest(expected), actual_hash=digest(actual), metrics=metrics,
                           difference=difference, duration_ms=elapsed, probe_hash=probe_hash, environment=env)
            validate('evaluation-result', payload)
            encoded = dumps(payload)
            con.execute('INSERT INTO results VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                        (run_id, rendering['rendering_id'], rendering['blueprint_id'], int(metrics['passed']),
                         got_route(actual), len(actual.get('items', [])), literal, normalized, elapsed, encoded,
                         hashlib.sha256(encoded.encode()).hexdigest()))
        con.commit()
        if proc.returncode != 0: raise RuntimeError(f'Probe failed; failure rows retained: {proc.stderr}')
    expected_count = len(selected)
    actual_count = con.execute('SELECT count(*) FROM results WHERE run_id=?', (run_id,)).fetchone()[0]
    if actual_count != expected_count: raise ValueError(f'Incomplete run: retained {actual_count}/{expected_count}')
    con.execute("UPDATE runs SET status='complete' WHERE run_id=?", (run_id,)); con.commit()
    summary = summarize(con, run_id)
    con.close()
    return summary


def got_route(actual):
    routes = sorted({i.get('route') for i in actual.get('items', []) if i.get('route')})
    return ','.join(routes)


def summarize(con, run_id):
    total, passed = con.execute('SELECT count(*),sum(passed) FROM results WHERE run_id=?', (run_id,)).fetchone()
    return {'run_id': run_id, 'cases': total, 'passed': passed or 0, 'failed': total - (passed or 0),
            'retained_rows': total, 'complete': con.execute('SELECT status FROM runs WHERE run_id=?', (run_id,)).fetchone()[0] == 'complete'}


def integrity(db_path, run_id=None):
    con = sqlite3.connect(db_path)
    if con.execute('PRAGMA integrity_check').fetchone()[0] != 'ok': raise ValueError('Corrupted SQLite database')
    runs = [run_id] if run_id else [r[0] for r in con.execute('SELECT run_id FROM runs')]
    reports = []
    for rid in runs:
        meta = con.execute('SELECT status,expected_count FROM runs WHERE run_id=?', (rid,)).fetchone()
        if not meta: raise ValueError('Missing run ID')
        rows = con.execute('SELECT rendering_id,payload_json,payload_hash FROM results WHERE run_id=?', (rid,)).fetchall()
        if len({r[0] for r in rows}) != len(rows): raise ValueError('Duplicate case execution')
        if meta[0] == 'complete' and len(rows) != meta[1]: raise ValueError(f'Missing result records: {len(rows)}/{meta[1]}')
        for rendering_id, payload, payload_hash in rows:
            if hashlib.sha256(payload.encode()).hexdigest() != payload_hash: raise ValueError(f'Corrupted result record {rendering_id}')
            validate('evaluation-result', json.loads(payload))
        reports.append({'run_id': rid, 'records': len(rows), 'expected_records': meta[1], 'status': meta[0], 'integrity': 'ok'})
    con.close(); return reports
