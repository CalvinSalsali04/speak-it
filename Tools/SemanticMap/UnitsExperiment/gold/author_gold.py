#!/usr/bin/env python3
"""The authored gold, written as an ordered tiling of each transcript.

Each capture is a list of (source text, owner) segments in source order that
together cover the whole transcript. Owner is a unit number, "F" (filler or
discourse), ("S", [units]) for shared scope, or ("A", [admissible owners],
reason) for genuinely ambiguous ownership, where "own" means the span would be
a unit of its own. This script turns the tiling into gold_spec.json; build_gold.py
then re-locates every span independently and enforces the coverage invariant.

Written from transcript text alone. No model output, candidate output, analysis
report or existing label was read while writing it.
"""
import json, re, sys

F = "F"
def S(*u): return ("S", list(u))
def A(owners, reason): return ("A", owners, reason)

MIXED = "a recall-worthy fact that also motivates or anchors the action after it; it can stand as its own unit or be the action's context"
HEDGE = "epistemic hedge at the unit's edge; it qualifies the claim but carries no content of its own"

GOLD = {
"RB13R": dict(families=["deliberation + final decision"], glosses={1: "take the bus to the airport on Sunday (drive considered, then corrected)"},
  tiles=[("I could drive to the airport Sunday or take the bus actually no take the bus to the airport on Sunday", 1)]),
"RB14C": dict(families=["coherent single thought"], note="single simple action", glosses={1: "give Dimitri the blue chair"},
  tiles=[("give Dimitri the blue chair", 1)]),
"RB16R": dict(families=["deliberation + final decision"], glosses={1: "book the afternoon session (two sessions weighed)"},
  tiles=[("there's a morning session and an afternoon one and honestly the afternoon is better so book the afternoon session", 1)]),
"RB17R": dict(families=["mixed action + Memory", "reported speech"], glosses={1: "book the furnace service before the warranty ends"},
  tiles=[("so", F), ("the guy said the furnace warranty expires in November which is sooner than I thought", A(["own", 1], MIXED)),
         ("so", F), ("I need to book the service before then", 1)]),
"RB19R": dict(families=["mixed action + Memory", "reported speech"], glosses={1: "draft the lease renewal at some point"},
  tiles=[("the property manager mentioned the tenant's lease ends in March", A(["own", 1], MIXED)),
         ("so", F), ("I should draft the renewal at some point", 1)]),
"RB21R": dict(families=["rambling multiple tasks"], glosses={1: "drop the donation bags off", 2: "fill the car up while out"},
  tiles=[("drop the donation bags off", 1), ("and", F), ("while I'm out there fill the car up", 2)]),
"RB28C": dict(families=["clean multiple tasks", "mixed action + Memory"],
  glosses={1: "move the bikes before the contractor arrives", 2: "get a second quote from the company Rosa used, because the first seemed high"},
  tiles=[("the contractor is coming Tuesday morning to look at the back steps", A(["own", 1], MIXED)), ("and", F),
         ("I need to move the bikes out of the way before he arrives", 1), ("and", F),
         ("I should also get a second quote from the company Rosa used because his first number seemed high", 2), ("and", F),
         ("the deck boards need pricing separately", A(["own", 2], "a new clause that reads either as its own pricing task or as an instruction for the second quote"))]),
"RB28R": dict(families=["rambling multiple tasks", "mixed action + Memory"],
  glosses={1: "move the bikes before the contractor arrives", 2: "get a second quote from the company Rosa used, because the first seemed high"},
  tiles=[("okay so um", F), ("the contractor is coming Tuesday morning to look at the back steps", A(["own", 1], MIXED)), ("so", F),
         ("I need to like move the bikes out of the way before he arrives", 1), ("and uh", F),
         ("I should also get a second quote from the company Rosa used because honestly his first number seemed high", 2), ("and yeah", F),
         ("the deck boards need pricing separately", A(["own", 2], "a new clause that reads either as its own pricing task or as an instruction for the second quote"))]),
"RB29C": dict(families=["clean multiple tasks", "mixed action + Memory"],
  glosses={1: "sign the trip form the school sent home", 2: "trip payment due by end of month", 3: "ask whether Nadia can sit with Priya on the coach, and why"},
  tiles=[("the school sent the trip form home today and it needs signing", 1), ("and", F),
         ("the payment is due by the end of the month", 2), ("and", F),
         ("I want to ask whether Nadia can sit with Priya on the coach because last year she was on her own the whole way", 3)]),
"RB29R": dict(families=["rambling multiple tasks", "mixed action + Memory"],
  glosses={1: "sign the trip form the school sent home", 2: "trip payment due by end of month", 3: "ask whether Nadia can sit with Priya on the coach, and why"},
  tiles=[("so", F), ("the school sent the trip form home today and it um it needs signing", 1), ("and", F),
         ("I think", A([2, "filler"], HEDGE)), ("the payment is due by the end of the month", 2), ("and", F),
         ("I also want to ask whether Nadia can sit with Priya on the coach because you know last year she was on her own the whole way", 3)]),
"RB30C": dict(families=["clean multiple tasks", "mixed action + Memory"],
  glosses={1: "book a follow up with Doctor Adeyemi", 2: "start the supplements again", 3: "tell Mum, because hers was the same"},
  tiles=[("I picked up the blood work results and the iron is low again", A(["own", 1, 2], MIXED)), ("so", F),
         ("I need to", S(1, 2)), ("book a follow up with Doctor Adeyemi", 1), ("and", F), ("start the supplements again", 2), ("and", F),
         ("I should tell Mum because hers was the same thing two years ago", 3)]),
"RB30R": dict(families=["rambling multiple tasks", "mixed action + Memory"],
  glosses={1: "book a follow up with Doctor Adeyemi", 2: "start the supplements again", 3: "tell Mum, because hers was the same"},
  tiles=[("right so", F), ("I picked up the blood work results and um the iron is low again", A(["own", 1, 2], MIXED)), ("so", F),
         ("I need to", S(1, 2)), ("book a follow up with Doctor Adeyemi", 1), ("and uh", F), ("start the supplements again", 2), ("and", F),
         ("I should probably tell Mum because I mean hers was the same thing two years ago", 3)]),
"RB31C": dict(families=["coherent single thought"], note="long single Memory explanation", glosses={1: "why the back steps rot and why the downspout must move"},
  tiles=[("the reason the back steps are rotting is that the downspout empties straight onto them rather than into the drain so every time it rains the bottom two boards sit in water for a day and the contractor said that is why replacing them without moving the downspout would just start the whole thing over", 1)]),
"RB31R": dict(families=["coherent single thought"], note="long single Memory explanation", glosses={1: "why the back steps rot and why the downspout must move"},
  tiles=[("um so", F), ("the reason the back steps are rotting is that you know the downspout empties straight onto them rather than into the drain so basically every time it rains the bottom two boards sit in water for a day and the contractor said that's why I mean replacing them without moving the downspout would just start the whole thing over", 1)]),
"RB33R": dict(families=["rambling multiple tasks", "deliberation + final decision"],
  glosses={1: "order the projector bulb", 2: "pay the framing invoice now (waiting considered, then rejected)"},
  tiles=[("order the projector bulb", 1), ("and then,", F),
         ("I could pay the framing invoice now or wait for the purchase order, no, now, so pay the framing invoice", 2)]),
"RB38C": dict(families=["coherent single thought"], note="single Memory explanation", glosses={1: "why the nursery keeps asking for the second form"},
  tiles=[("the reason the nursery keeps asking for the second form is that the funding year restarts in April and the one on file was signed against the old year", 1)]),
"RB41R": dict(families=["deliberation + final decision"], glosses={1: "book the Tuesday physio slot (Friday weighed), because off that afternoon"},
  tiles=[("I could do the Tuesday slot with the physio or the Friday one and Tuesday is better so book the Tuesday slot with the physio because I'm off that afternoon anyway", 1)]),
"RB43R": dict(families=["deliberation + final decision", "rambling multiple tasks"],
  glosses={1: "call the dentist before they shut", 2: "call the optician before they shut"},
  note="one deliberation resolves into two calls; the deliberation, the verb and the deadline are shared",
  tiles=[("I thought it was the dentist or the optician today but there's time for both", S(1, 2)), ("so", F),
         ("call", S(1, 2)), ("the dentist", 1), ("and then", F), ("the optician", 2), ("before they shut", S(1, 2))]),
"RB44R": dict(families=["deliberation + final decision", "rambling multiple tasks"],
  glosses={1: "book the van for Saturday", 2: "ask Theo to help load it"},
  note="one deliberation resolves into two actions; the deliberation is shared",
  tiles=[("I can't decide if I need the van or just Theo's car and thinking about it it's both", S(1, 2)), ("so", F),
         ("book the van for Saturday", 1), ("and", F), ("ask Theo to help me load it", 2)]),
"RB45R": dict(families=["deliberation + final decision"], note="deliberation with no decision; one thought", glosses={1: "undecided between the March intake and September"},
  tiles=[("I keep going back and forth on whether to do the March intake or wait for September and I genuinely don't know yet", 1)]),
"RB46R": dict(families=["deliberation + final decision"], note="uncertain diagnosis resolved into one action", glosses={1: "get someone to look at the chimney or gable before deciding"},
  tiles=[("so", F), ("the chimney needs repointing or maybe it's the whole gable that needs re-rendering and I'll have to get someone to look before I can call it", 1)]),
"RB17C": dict(families=["mixed action + Memory"], glosses={1: "book the furnace service before then"},
  tiles=[("the furnace warranty expires in November", A(["own", 1], MIXED)), ("and", F), ("I need to book the service before then", 1)]),
"RB21C": dict(families=["clean multiple tasks"], glosses={1: "drop the donation bags off", 2: "fill the car up"},
  tiles=[("drop the donation bags off", 1), ("and", F), ("fill the car up", 2)]),
"CM04": dict(families=["message content"], note="both clauses are the message's content", glosses={1: "text Dana: running late, will call after"},
  tiles=[("text Dana that I am running late and will call after", 1)]),
"CM06": dict(families=["message content", "clean multiple tasks"], glosses={1: "text Mike that the meeting is cancelled", 2: "remind me to call Sarah"},
  tiles=[("text Mike that the meeting is cancelled", 1), ("and", F), ("remind me to call Sarah", 2)]),
"CM07": dict(families=["message content", "clean multiple tasks"], glosses={1: "tell Priya I will be late"},
  tiles=[("tell Priya I will be late", 1), ("and", F),
         ("book the room", A(["own", 1], "a bare imperative after a message complement: the user's own task, or part of what Priya is told"))]),
"RS03": dict(families=["reported speech"], glosses={1: "Mike's news: deal closed, team celebrating"},
  tiles=[("Mike told me the deal closed and the team is celebrating", 1)]),
"RS04": dict(families=["reported speech"], note="a reported command; whether it is the user's task is a destination question, not a span question", glosses={1: "Sarah said call Mike tomorrow"},
  tiles=[("Sarah said call Mike tomorrow", 1)]),
}
for n in (14, 25):
    tiles = []
    for i in range(1, n + 1):
        if i > 1: tiles.append(("and", F))
        tiles.append((f"Call person{i}", i))
    GOLD[f"CAP{n}"] = dict(families=["clean multiple tasks", "capacity"], note=f"capacity stress: {n} separate units",
                           glosses={i: f"call person{i}" for i in range(1, n + 1)}, tiles=tiles)

def word_occ(src, text, start):
    pat = ('(?<!\\w)' if text[:1].isalnum() else '') + re.escape(text) + ('(?!\\w)' if text[-1:].isalnum() else '')
    hits = [m.start() for m in re.finditer(pat, src)]
    assert start in hits, (text, start)
    return [text, hits.index(start)]

def main(cap_path, out_path):
    caps = [json.loads(l) for l in open(cap_path) if l.strip()]
    spec = {'author': 'independent gold-author thread session (not the experiment author, not a grader of #118)',
            'written_at': '2026-09-23',
            'independence': ('Written from the transcript text in gold-input/captures.jsonl only. Not read while writing: any model output '
                             '(runs.jsonl, map.jsonl, asked.jsonl, diag.zip), the bottleneck, six-rejection and whole-list reports, the #118 '
                             'grade files, the experiment thread\'s messages, and Candidate 1 or 2 outputs or schemas. Disclosure: the project '
                             'memory loaded into this session names some of these capture ids and summarises failure mechanisms at family '
                             'level (for example that some production answers dropped a deliberation); it holds no per-capture units or '
                             'model outputs. The unit definition was hashed before any transcript was received. Families for the '
                             '"dropped-intention" and "correct complex control" buckets are not assigned here: they depend on past system '
                             'behaviour this author deliberately did not see, so the experiment thread supplies them.'),
            'captures': []}
    for cap in caps:
        src, g = cap['transcript'], GOLD[cap['id']]
        cur, units, filler, shared, amb = 0, {}, [], [], []
        for text, own in g['tiles']:
            pos = src.find(text, cur)
            if pos < 0 or src[cur:pos].strip(): sys.exit(f"{cap['id']}: tiling breaks before {text!r}")
            ref = word_occ(src, text, pos); cur = pos + len(text)
            if own == F: filler.append(ref)
            elif isinstance(own, int): units.setdefault(own, []).append(ref)
            elif own[0] == 'S': shared.append({'span': ref, 'owners': own[1]})
            else: amb.append({'span': ref, 'owners': own[1], 'reason': own[2]})
        if src[cur:].strip(): sys.exit(f"{cap['id']}: tiling stops early at {src[cur:]!r}")
        if sorted(units) != list(range(1, len(units) + 1)): sys.exit(f"{cap['id']}: unit numbers not contiguous")
        spec['captures'].append({'id': cap['id'], 'families': g['families'], 'note': g.get('note', ''),
            'units': [{'spans': units[k], 'gloss': g['glosses'][k]} for k in sorted(units)],
            'filler': filler, 'shared': shared, 'ambiguous': amb})
    if set(GOLD) != {c['id'] for c in caps}: sys.exit("gold ids differ from input ids")
    json.dump(spec, open(out_path, 'w'), indent=1); print(f"spec: {len(spec['captures'])} captures")

if __name__ == '__main__': main(*sys.argv[1:3])
