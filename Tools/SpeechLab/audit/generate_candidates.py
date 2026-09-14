#!/usr/bin/env python3
"""Generate a small AI-authored audit cohort from the exported blueprint batch.

The assistant is a rendering generator, never the label source. Every candidate
keeps the pre-existing blueprint and remains ``meaning_preservation=uncertain``
until human review.
"""
import argparse
import json
from pathlib import Path
import re
import sys

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))
from Sources.contracts import VERSION, dumps, write_jsonl


def clean_title(value):
    value = value.strip().rstrip('.')
    return value[:1].lower() + value[1:]


def has_words(text, value):
    return value and ' '.join(re.findall(r'\w+', str(value).casefold())) in ' '.join(re.findall(r'\w+', text.casefold()))


def item_clause(item, style=0):
    title = clean_title(item['title'])
    if item['prohibition']:
        clause = 'do not ' + title.removeprefix('do not ')
    elif item['negation']:
        clause = 'make a note that ' + title.removeprefix('record that ')
    elif item['state'] == 'completed':
        clause = 'I already ' + title.removeprefix('already ')
    elif item['route'] == 'Memory':
        leads = ['remember that ', 'a note for later: ', 'I want to remember that ']
        clause = leads[style % len(leads)] + title.removeprefix('remember that ').removeprefix('remember ')
    elif item['type'] in ('reminder', 'event') or item['date'] or item['time'] or item['recurrence']:
        leads = ['remind me to ', 'I need a reminder to ', 'make sure I remember to ']
        clause = leads[style % len(leads)] + title
    else:
        leads = ['I need to ', 'add this to my list: ', 'make a task to ']
        clause = leads[style % len(leads)] + title
    additions = []
    if item['person'] and not has_words(clause, item['person']): additions.append('with ' + item['person'])
    if item['location'] and not has_words(clause, item['location']): additions.append('at ' + item['location'])
    if item['date'] and not has_words(clause, item['date']): additions.append('on ' + str(item['date']))
    if item['time'] and not has_words(clause, item['time']): additions.append('at ' + str(item['time']))
    if item['recurrence'] and 'every ' not in clause: additions.append('every Tuesday')
    return ' '.join([clause] + additions)


def semantic_core(bp, style=0):
    expected = bp['expected']
    if expected['operations']:
        operation = expected['operations'][0]
        return f"cancel the saved reminder to {clean_title(operation.get('target') or 'that item')}"
    clauses = [item_clause(item, style + i) for i, item in enumerate(expected['items'])]
    if not clauses: return 'keep this capture without creating a task'
    if len(clauses) == 1: core = clauses[0]
    else:
        connectors = ['; and also ', '. One more thing, ', '; then ']
        core = connectors[style % len(connectors)].join(clauses)
    if expected['ambiguity_policy'] in ('review', 'preserve-only'):
        core = "I'm not sure whether this is a task or just something to keep, but " + core
    return core


def variants(bp, index):
    direct = semantic_core(bp, index)
    rows = [(direct[:1].upper() + direct[1:] + '.', [])]

    messy_patterns = [
        ("Um, {core}, uh, that's all.", ['filler-words', 'hesitation', 'sign-off-trailing-noise']),
        ("Okay, so, {core}—yeah, that's what I meant.", ['filler-words', 'rephrasing', 'rambling-ending']),
        ("Right, just getting this out of my head: {core}.", ['rambling-introduction', 'filler-words']),
        ("I nearly forgot— {core}. Thanks, that's it.", ['false-start', 'sign-off-trailing-noise']),
        ("So there's one thing, um, {core}, and that's everything.", ['filler-words', 'hesitation', 'rambling-introduction']),
        ("Before I lose the thought, {core}—okay, done.", ['rambling-introduction', 'sign-off-trailing-noise']),
        ("Uh, quick thing: {core}. Anyway, thanks.", ['hesitation', 'rambling-introduction', 'sign-off-trailing-noise']),
        ("Let me put this down while I remember: {core}.", ['rambling-introduction']),
        ("Okay— {core}. Sorry, that's the whole note.", ['filler-words', 'rambling-ending']),
        ("Hmm, {core}; yeah, keep that for me.", ['hesitation', 'sign-off-trailing-noise'])
    ]
    pattern, messy_tags = messy_patterns[index % len(messy_patterns)]
    rows.append((pattern.format(core=direct), messy_tags))

    expected = bp['expected']; items = expected['items']; tags = ['false-start', 'restart']
    restart_patterns = ["I was going to say— no, let me start over. ", "Wait, scratch that opening. ",
                        "Actually— sorry, starting again. ", "I lost my train of thought; okay, here it is. "]
    prefix = restart_patterns[index % len(restart_patterns)]
    if items and items[0].get('person'):
        person = items[0]['person']
        prefix = f"This is for Sam— sorry, for {person}. "
        tags = ['self-correction-person', 'hesitation']
    elif items and items[0].get('time'):
        prefix = f"At three— no, at {items[0]['time']}. "
        tags = ['self-correction-time', 'hesitation']
    elif items and items[0].get('date'):
        prefix = f"On Wednesday— sorry, on {items[0]['date']}. "
        tags = ['self-correction-date', 'hesitation']
    if expected['ambiguity_policy'] in ('review', 'preserve-only'):
        prefix = "Maybe this is a task, maybe it's only a thought— "
        tags = ['uncertainty', 'change-of-intent']
    elif len(items) > 1:
        prefix = "Okay, two things. First, "
        tags += ['multiple-thoughts' if any(i['route'] == 'Memory' for i in items) else 'multiple-tasks', 'numbered-list']
    corrected = prefix + semantic_core(bp, index + 1) + ", okay that's all."
    rows.append((corrected, list(dict.fromkeys(tags + ['sign-off-trailing-noise']))))
    return rows


def generate(batch_path, output):
    batch = [json.loads(line) for line in Path(batch_path).read_text().splitlines() if line.strip()]
    result = []
    for index, request in enumerate(batch):
        bp = request['blueprint']
        for candidate_index, (text, phenomena) in enumerate(variants(bp, index)):
            result.append({
                'blueprint_id': bp['blueprint_id'], 'text': text,
                'provenance': {'kind': 'audit_ai_generation', 'batch_index': index, 'candidate_index': candidate_index,
                               'label_source': 'pre_existing_blueprint', 'review_status': 'unreviewed'},
                'generator': {'kind': 'external_ai', 'name': 'Codex audit assistant', 'version': '2026-09-13'},
                'seed': None, 'phenomena': phenomena, 'mutation_lineage': [],
                'equivalence_class': bp['blueprint_id'], 'meaning_preservation': 'uncertain'
            })
    write_jsonl(output, result)
    return {'blueprints': len(batch), 'candidates': len(result), 'per_blueprint': 3, 'output': str(output)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--batch', type=Path, default=LAB / 'artifacts/export-for-ai/blueprint-batch.jsonl')
    parser.add_argument('--output', type=Path, default=LAB / 'audit/ai-candidates.jsonl')
    args = parser.parse_args()
    print(json.dumps(generate(args.batch, args.output), indent=2))


if __name__ == '__main__': main()
