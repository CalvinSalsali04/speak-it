"""Versioned contracts, canonical identity, and offline schema validation."""
import hashlib
import json
import math
import re
import unicodedata
from pathlib import Path

HOME = Path(__file__).resolve().parents[1]
VERSION = 'speechlab-1'
CONTEXT = {'reference_time': '2026-08-03T10:00:00-04:00', 'timezone': 'America/Toronto', 'stored_items': [], 'prior_turns': []}


def dumps(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False)


def digest(value):
    return hashlib.sha256(dumps(value).encode()).hexdigest()


def file_hash(path):
    h = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def norm(value):
    return ' '.join(re.findall(r'\w+', unicodedata.normalize('NFKC', value).casefold().replace("don't", 'do not').replace('don’t', 'do not')))


def canonical(value):
    if isinstance(value, str):
        return norm(value)
    if isinstance(value, dict):
        return {k: canonical(v) for k, v in sorted(value.items())}
    if isinstance(value, list):
        return [canonical(v) for v in value]
    return value


def semantic_identity(blueprint):
    # IDs, family labels, wording, provenance and difficulty cannot create novelty.
    return digest(canonical({'context': blueprint['capture_context'], 'expected': blueprint['expected']}))


def read_jsonl(path):
    with open(path) as stream:
        for number, line in enumerate(stream, 1):
            if line.strip():
                try:
                    yield json.loads(line, parse_constant=lambda s: (_ for _ in ()).throw(ValueError(s)))
                except (ValueError, TypeError) as error:
                    raise ValueError(f'Invalid JSONL at line {number}') from error


def write_jsonl(path, rows):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + '.tmp')
    with tmp.open('w') as stream:
        for row in rows:
            stream.write(dumps(row) + '\n')
    tmp.replace(path)


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n')


def validate_schema(value, schema, root=None, path='$'):
    """Fail-closed validator for the JSON Schema keywords used in this package.

    Schemas are also standard draft 2020-12 documents usable with jsonschema/Ajv.
    Unknown validation keywords fail, rather than silently weakening a contract.
    """
    root = root or schema
    supported = {'$schema', '$id', '$defs', '$ref', 'title', 'description', 'type', 'enum', 'const', 'required', 'properties', 'additionalProperties', 'items', 'minItems', 'maxItems', 'uniqueItems', 'minLength', 'maxLength', 'minimum', 'maximum', 'anyOf', 'pattern'}
    if set(schema) - supported:
        raise ValueError('Unsupported schema keyword')
    if '$ref' in schema:
        target = root
        for part in schema['$ref'].removeprefix('#/').split('/'):
            target = target[part]
        return validate_schema(value, target, root, path)
    if 'anyOf' in schema:
        for option in schema['anyOf']:
            try:
                validate_schema(value, option, root, path)
                return
            except ValueError:
                pass
        raise ValueError(f'{path}: no matching schema')
    types = {'object': lambda x: isinstance(x, dict), 'array': lambda x: isinstance(x, list), 'string': lambda x: isinstance(x, str), 'boolean': lambda x: isinstance(x, bool), 'integer': lambda x: type(x) is int, 'number': lambda x: type(x) in (int, float) and math.isfinite(x), 'null': lambda x: x is None}
    if 'type' in schema:
        allowed = schema['type'] if isinstance(schema['type'], list) else [schema['type']]
        if not any(types[t](value) for t in allowed):
            raise ValueError(f'{path}: invalid type')
    if 'enum' in schema and value not in schema['enum']:
        raise ValueError(f'{path}: invalid enum')
    if 'const' in schema and value != schema['const']:
        raise ValueError(f'{path}: invalid constant')
    if isinstance(value, dict):
        if set(schema.get('required', [])) - set(value):
            raise ValueError(f'{path}: missing required fields')
        props = schema.get('properties', {})
        for key, child in value.items():
            rule = props.get(key, schema.get('additionalProperties', {}))
            if rule is False:
                raise ValueError(f'{path}: unexpected field {key}')
            if isinstance(rule, dict):
                validate_schema(child, rule, root, path + '.' + key)
    if isinstance(value, list):
        if len(value) < schema.get('minItems', 0) or len(value) > schema.get('maxItems', float('inf')):
            raise ValueError(f'{path}: invalid array length')
        if schema.get('uniqueItems') and len({dumps(v) for v in value}) != len(value):
            raise ValueError(f'{path}: duplicate array values')
        for child in value:
            validate_schema(child, schema.get('items', {}), root, path + '[]')
    if isinstance(value, str):
        if not schema.get('minLength', 0) <= len(value) <= schema.get('maxLength', float('inf')):
            raise ValueError(f'{path}: invalid string length')
        if 'pattern' in schema and not re.search(schema['pattern'], value):
            raise ValueError(f'{path}: invalid pattern')
    if type(value) in (int, float):
        if not schema.get('minimum', -float('inf')) <= value <= schema.get('maximum', float('inf')):
            raise ValueError(f'{path}: out of range')


_SCHEMAS = {}

def validate(kind, row):
    if kind not in _SCHEMAS:
        _SCHEMAS[kind] = json.loads((HOME / 'schema' / (kind + '.schema.json')).read_text())
    validate_schema(row, _SCHEMAS[kind])


def validate_blueprints(rows):
    ids, semantics = set(), set()
    for row in rows:
        validate('semantic-blueprint', row)
        identity = semantic_identity(row)
        if row['blueprint_id'] in ids or identity in semantics:
            raise ValueError('Duplicate blueprint ID or semantics')
        ids.add(row['blueprint_id']); semantics.add(identity)
        if row['blueprint_id'] != 'bp-' + identity[:24]:
            raise ValueError('Blueprint identity mismatch')
        expected = row['expected']
        if expected['item_count'] != len(expected['items']):
            raise ValueError('Impossible item count')
        if any(op.get('operation') == 'cancel' for op in expected['operations']) and not row['capture_context']['stored_items']:
            raise ValueError('Cancellation needs an explicitly stored target context')
        for item in expected['items']:
            if set(map(norm, item['facts'])) & set(map(norm, item['forbidden_facts'])):
                raise ValueError('Contradictory facts')
            if item['time'] is not None and item['date'] is None:
                raise ValueError('Time requires resolved date')
            if item['prohibition'] and not item['negation']:
                raise ValueError('Prohibition requires negative polarity')
            if item['route'] == 'Memory' and item['type'] in ['task', 'shopping', 'event', 'personFollowUp']:
                raise ValueError('Actionable type cannot have Memory route')
        if expected['ambiguity_policy'] != 'act' and any(i['date'] or i['time'] or i['recurrence'] or i['location'] for i in expected['items']):
            raise ValueError('Ambiguous/preserve-only capture must not silently schedule')
    return {r['blueprint_id']: r for r in rows}


def rendering_identity(row):
    """Rendering identity includes exact words and their semantic/lineage owner."""
    return digest({
        'blueprint_id': row['blueprint_id'], 'text': row['text'],
        'lineage': row['mutation_lineage'], 'equivalence_class': row['equivalence_class'],
        'phenomena': row['phenomena'], 'generator': row['generator'],
    })


def validate_renderings(rows, blueprints, phenomenon_ids, *, min_length=1, max_length=10000):
    ids, exact, normalized = set(), {}, {}
    for row in rows:
        validate('rendering', row)
        if row['blueprint_id'] not in blueprints:
            raise ValueError(f"Unknown blueprint: {row['blueprint_id']}")
        if row['rendering_id'] in ids:
            raise ValueError('Duplicate rendering ID')
        if not set(row['phenomena']) <= set(phenomenon_ids):
            raise ValueError('Unknown phenomenon tag')
        if row['rendering_id'] != 'rd-' + rendering_identity(row)[:24]:
            raise ValueError('Rendering identity mismatch')
        if not min_length <= len(row['text']) <= max_length or '\x00' in row['text']:
            raise ValueError('Malformed rendering text')
        key = row['text'].strip()
        if key in exact:
            raise ValueError(f"Duplicate rendering text: {row['rendering_id']} and {exact[key]}")
        near = norm(row['text'])
        if near in normalized and normalized[near] != row['blueprint_id']:
            raise ValueError('Near-duplicate text maps to different semantics')
        if len(row['mutation_lineage']) != len(set(row['mutation_lineage'])):
            raise ValueError('Cyclic/duplicate mutation lineage')
        if row['mutation_lineage'] and row['mutation_lineage'][-1] == row['rendering_id']:
            raise ValueError('Rendering cannot descend from itself')
        # Guaranteed variants must retain every explicit lexical anchor. AI/public
        # imports may be reviewed or uncertain instead of gaming this check.
        if row['meaning_preservation'] == 'guaranteed':
            anchors = [fact for item in blueprints[row['blueprint_id']]['expected']['items'] for fact in item['facts']]
            surface = norm(row['text'])
            missing = [a for a in anchors if norm(a) and norm(a) not in surface]
            deletion_tags = {'asr-deletion', 'partial-thought', 'abandoned-thought', 'short-fragment'}
            if missing and not deletion_tags.intersection(row['phenomena']):
                raise ValueError(f"Guaranteed rendering lost semantic anchors: {missing}")
        ids.add(row['rendering_id']); exact[key] = row['rendering_id']; normalized[near] = row['blueprint_id']
    return {r['rendering_id']: r for r in rows}


def load_contracts(blueprint_path, rendering_path, phenomena_path=None):
    phenomena_path = Path(phenomena_path or HOME / 'config/phenomena.json')
    phenomena = json.loads(phenomena_path.read_text())['phenomena']
    blueprints = validate_blueprints(list(read_jsonl(blueprint_path)))
    renderings = validate_renderings(list(read_jsonl(rendering_path)), blueprints, {p['id'] for p in phenomena})
    return blueprints, renderings
