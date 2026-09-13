"""Coverage, set-cover diagnostics, and saturation accounting."""
from collections import Counter
from pathlib import Path

from .contracts import digest, write_json, write_jsonl


def features(blueprint, rendering):
    e = blueprint['expected']; items = e['items']
    found = {'phenomenon:' + p for p in rendering['phenomena']}
    found |= {'tag:' + t for t in blueprint['semantic_tags']}
    found.add('items:' + str(e['item_count'])); found.add('ambiguity:' + e['ambiguity_policy'])
    for item in items:
        found |= {f'route:{item["route"]}', f'type:{item["type"]}', f'state:{item["state"]}'}
        for key in ('date', 'time', 'recurrence', 'location', 'person'):
            if item[key] is not None: found.add(key + ':present')
        if item['negation']: found.add('polarity:negation')
        if item['prohibition']: found.add('polarity:prohibition')
    if e['operations']: found.add('operation:' + e['operations'][0].get('operation', 'other'))
    return found


def greedy_set_cover(blueprints, renderings, required=None):
    case_features = {rid: features(blueprints[r['blueprint_id']], r) for rid, r in renderings.items()}
    uncovered = set(required or set().union(*case_features.values()))
    selected = []
    while uncovered:
        rid, covered = max(case_features.items(), key=lambda pair: (len(pair[1] & uncovered), pair[0]))
        gain = covered & uncovered
        if not gain: break
        selected.append({'rendering_id': rid, 'new_features': sorted(gain)})
        uncovered -= gain
    return selected, sorted(uncovered)


def report(blueprints, renderings, phenomena, output):
    output = Path(output); output.mkdir(parents=True, exist_ok=True)
    counts = Counter()
    combos = Counter()
    for rid, rendering in renderings.items():
        f = features(blueprints[rendering['blueprint_id']], rendering)
        counts.update(f); combos[digest(sorted(f))[:16]] += 1
    required = {'phenomenon:' + p['id'] for p in phenomena}
    selected, gaps = greedy_set_cover(blueprints, renderings, required)
    uncovered = sorted(required - set(counts))
    summary = dict(blueprints=len(blueprints), semantic_families=len({b['family_id'] for b in blueprints.values()}),
                   renderings=len(renderings), phenomena_defined=len(phenomena),
                   phenomena_covered=len(required) - len(uncovered), uncovered_phenomena=uncovered,
                   semantic_feature_combinations=len(combos), diagnostic_cases=len(selected),
                   diagnostic_uncovered=gaps,
                   known_gaps=['permissioned production speech', 'human-recorded audio and measured ASR distributions',
                               'reviewed public-corpus-to-Speak-It contracts', 'SwiftData-backed cancellation execution',
                               'Foundation Models refinement path', 'sealed adversarial cases'],
                   feature_counts=dict(sorted(counts.items())))
    write_json(output / 'coverage-summary.json', summary)
    write_jsonl(output / 'diagnostic-renderings.jsonl', [renderings[x['rendering_id']] for x in selected])
    write_json(output / 'diagnostic-selection.json', {'algorithm': 'deterministic greedy set cover', 'selection': selected})
    write_json(output / 'saturation-snapshots.json', {'measures': [
        'new semantic families', 'new semantic feature combinations', 'new normalized rendering structures',
        'new failure signatures', 'new broad failure families', 'marginal failures per 10K/100K',
        'marginal novel failures per compute hour'], 'snapshots': saturation_snapshots(blueprints, renderings)})
    return summary


def saturation_snapshots(blueprints, renderings, failure_signatures=None):
    seen_families, seen_combos, seen_structures = set(), set(), set(); rows = []
    failures = failure_signatures or {}
    for n, rendering in enumerate(sorted(renderings.values(), key=lambda r: r['rendering_id']), 1):
        bp = blueprints[rendering['blueprint_id']]
        seen_families.add(bp['family_id'])
        seen_combos.add(digest(sorted(features(bp, rendering))))
        seen_structures.add(digest({'phenomena': rendering['phenomena'], 'lineage': rendering['mutation_lineage']}))
        if n <= 10 or n % 100 == 0 or n == len(renderings):
            rows.append({'cases': n, 'semantic_families': len(seen_families),
                         'semantic_feature_combinations': len(seen_combos),
                         'normalized_rendering_structures': len(seen_structures),
                         'failure_signatures': len({failures.get(r['rendering_id']) for r in list(renderings.values())[:n] if failures.get(r['rendering_id'])}),
                         'broad_failure_families': None, 'marginal_failures_per_10k': None,
                         'marginal_novel_failures_per_compute_hour': None})
    return rows
