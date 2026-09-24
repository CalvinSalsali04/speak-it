#!/usr/bin/env python3
"""Compile the authored gold spec into gold.json with character offsets, and
enforce the coverage invariant from UNIT_DEFINITION.md.

usage: build_gold.py captures.jsonl gold_spec.json gold.json

Offsets are authored against `transcript`; the whitespace-atom view is derived from them.

Spans in the spec are written as source text: "text" (must occur exactly once in
the source) or ["text", n] (the n-th occurrence, 0-based). Nothing here reads any
model output.
"""
import hashlib, json, re, sys

def sha(b): return hashlib.sha256(b).hexdigest()

def locate(src, spec, cid):
    text, occ = (spec, None) if isinstance(spec, str) else (spec[0], spec[1])
    pat = ('(?<!\\w)' if text[:1].isalnum() else '') + re.escape(text) + ('(?!\\w)' if text[-1:].isalnum() else '')
    hits = [m.start() for m in re.finditer(pat, src)]
    if not hits: sys.exit(f"{cid}: span not found: {text!r}")
    if occ is None:
        if len(hits) != 1: sys.exit(f"{cid}: span {text!r} occurs {len(hits)}x; give an occurrence index")
        occ = 0
    s = hits[occ]; e = s + len(text)
    if src[s:e] != src[s:e].strip(): sys.exit(f"{cid}: span has edge whitespace: {text!r}")
    if s > 0 and src[s-1].isalnum() and src[s].isalnum(): sys.exit(f"{cid}: span starts mid-word: {text!r}")
    if e < len(src) and src[e-1].isalnum() and src[e].isalnum(): sys.exit(f"{cid}: span ends mid-word: {text!r}")
    return [s, e, src[s:e]]

def main(cap_path, spec_path, out_path):
    cap_bytes = open(cap_path, 'rb').read()
    caps = [json.loads(l) for l in cap_bytes.decode().splitlines() if l.strip()]
    spec_bytes = open(spec_path, 'rb').read()
    spec = json.loads(spec_bytes)
    defn = open(__file__.rsplit('/', 1)[0] + '/UNIT_DEFINITION.md', 'rb').read()
    by_id = {c['id']: c for c in spec['captures']}
    if set(by_id) != {c['id'] for c in caps}:
        sys.exit(f"id mismatch: missing {sorted({c['id'] for c in caps}-set(by_id))}, extra {sorted(set(by_id)-{c['id'] for c in caps})}")
    out = []
    for cap in caps:
        cid, src, g = cap['id'], cap['transcript'], by_id[cap['id']]
        if cap['atoms'] != src.split(): sys.exit(f'{cid}: atoms are not the whitespace split')
        owner = [None] * len(src)
        def claim(r, who):
            for i in range(r[0], r[1]):
                if owner[i] is not None: sys.exit(f"{cid}: overlap at {i} ({src[r[0]:r[1]]!r}) between {owner[i]} and {who}")
                owner[i] = who
        units = []
        for k, u in enumerate(g['units'], 1):
            rs = [locate(src, s, cid) for s in u['spans']]
            if [r[0] for r in rs] != sorted(r[0] for r in rs): sys.exit(f"{cid}: unit {k} ranges out of order")
            for r in rs: claim(r, f"unit{k}")
            units.append({'index': k, 'ranges': [[r[0], r[1]] for r in rs], 'text': [r[2] for r in rs], 'gloss': u.get('gloss', '')})
        firsts = [u['ranges'][0][0] for u in units]
        if firsts != sorted(firsts): sys.exit(f"{cid}: units not ordered by first range")
        filler = []
        for s in g.get('filler', []):
            r = locate(src, s, cid); claim(r, 'filler'); filler.append(r)
        shared = []
        for s in g.get('shared', []):
            r = locate(src, s['span'], cid); claim(r, 'shared')
            shared.append({'range': r[:2], 'text': r[2], 'owners': s['owners'], 'reason': s.get('reason', '')})
        amb = []
        for s in g.get('ambiguous', []):
            r = locate(src, s['span'], cid); claim(r, 'ambiguous')
            amb.append({'range': r[:2], 'text': r[2], 'owners': s['owners'], 'reason': s['reason']})
        uncovered = [i for i, ch in enumerate(src) if ch.isalnum() and owner[i] is None]
        if uncovered:
            i = uncovered[0]; sys.exit(f"{cid}: uncovered content at {i}: {src[max(0,i-20):i+20]!r}")
        # Project onto whitespace atoms (the split the probe uses). Derived, not authored.
        atoms, pos = [], 0
        for tok in src.split():
            a = src.index(tok, pos); atoms.append((a, a + len(tok))); pos = a + len(tok)
        atom_owner = []
        for j, (a, b) in enumerate(atoms):
            ws = {owner[i] for i in range(a, b) if src[i].isalnum()} or {owner[i] for i in range(a, b) if owner[i]}
            if len(ws) != 1: sys.exit(f"{cid}: atom {j} {src[a:b]!r} split between {ws}")
            atom_owner.append(ws.pop())
        def atom_ranges(key):
            ids = [j for j, o in enumerate(atom_owner) if o == key]
            rs = []
            for j in ids:
                if rs and rs[-1][1] == j - 1: rs[-1][1] = j
                else: rs.append([j, j])
            return rs
        def atoms_in(r): return [j for j, (a, b) in enumerate(atoms) if a >= r[0] and b <= r[1] or (a < r[1] and b > r[0])]
        atom_view = {
            'units': [{'ranges': atom_ranges(f"unit{u['index']}"), 'note': u['gloss']} for u in units],
            'filler': [j for j, o in enumerate(atom_owner) if o == 'filler'],
            'shared': [{'atoms': atoms_in(x['range']), 'units': x['owners']} for x in shared],
            'ambiguous': [{'atoms': atoms_in(x['range']), 'units': x['owners'], 'reason': x['reason']} for x in amb],
        }
        out.append({
            'id': cid, 'families': g['families'],
            'source_sha256': sha(src.encode()), 'source_is_ascii': src.isascii(),
            'source_length': len(src), 'unit_count': len(units),
            'units': units,
            'filler': [{'range': r[:2], 'text': r[2]} for r in sorted(filler)],
            'shared': shared, 'ambiguous': amb, 'note': g.get('note', ''),
            'atom_view': atom_view,
        })
    doc = {
        'schema': 'speakit-semantic-unit-gold/1',
        'evidence_class': 'development evidence, not unseen launch accuracy',
        'offsets': 'half-open [start,end) in Unicode code points of the exact source string',
        'unit_definition_sha256': sha(defn),
        'captures_input_sha256': sha(cap_bytes),
        'spec_sha256': sha(spec_bytes),
        'author': spec.get('author', ''), 'written_at': spec.get('written_at', ''),
        'independence': spec.get('independence', ''),
        'capture_count': len(out), 'unit_count': sum(c['unit_count'] for c in out),
        'captures': out,
    }
    with open(out_path, 'w') as f: json.dump(doc, f, indent=1, ensure_ascii=False); f.write('\n')
    print(f"ok: {len(out)} captures, {doc['unit_count']} units")

if __name__ == '__main__': main(*sys.argv[1:4])
