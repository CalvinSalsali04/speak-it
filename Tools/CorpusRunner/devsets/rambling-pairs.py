#!/usr/bin/env python3
"""The paired invariants for the rambling set, fixed before the run.

`rambling.tsv` is 41 clean/messy pairs plus three unpaired long captures. Every
pair carries the same expected destination and thought count, so the question
the set exists to answer is not "what is the score" but "does the messy twin
get the same answer as its clean twin". An aggregate hides exactly that: two
arms can score the same total while failing on different halves of the set.

    ./Tools/CorpusRunner/devsets/rambling-pairs.py rambling.tsv baseline.out
    ./Tools/CorpusRunner/devsets/rambling-pairs.py rambling.tsv baseline.out --candidate new.out
    ./Tools/CorpusRunner/devsets/rambling-pairs.py --selftest

The probe report format is the one `heldout/score.py` reads, and the block and
row regexes here are deliberately the same ones, so a change to the emitter
breaks both together rather than making them disagree quietly.

SPAN CRITERIA. Criteria 5 to 8 are about atom spans, which the probe does not
emit yet: they are read from a `--spans` JSONL whose shape is documented in
`span_findings` and exercised by the self-test. The emitter arrives with the
Phase B prototype; the metric is frozen here so it cannot be chosen afterwards.
"""
import json
import pathlib
import re
import sys

# The corpus reader every scan in this repository is required to go through;
# `test_score.EveryCorpusReaderIsDeclared` refuses a file that slices a corpus
# its own way.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
import corpus_paths as paths

BLOCK = re.compile(r'\n(?=── ")')
HEAD = re.compile(r'── "(.*?)"')

# Markers whose loss changes what the sentence commits the speaker to. Not a
# filler list: every entry here is meaning, and none may disappear between a
# clean twin and its messy twin.
MARKERS = re.compile(
    r"\b(?:not|never|no|none|don'?t|doesn'?t|didn'?t|won'?t|can'?t|cannot|without"
    r"|might|maybe|perhaps|possibly|probably|should|could|would|unsure|undecided"
    r"|whether|considering|deciding|thinking)\b",
    re.I,
)

# Sounds and openers that SHOULD be gone from a stored row. Kept to the ones
# that cannot be content in any position, so a row keeping "like" or "so" is
# not counted against.
FILLERS = re.compile(r"\b(?:um+|uh+|erm|hmm+|mm+|mhm|y'?know|you know)\b", re.I)

STOPWORDS = {
    "a", "an", "and", "the", "to", "of", "for", "in", "on", "at", "it", "its",
    "is", "are", "was", "were", "be", "i", "my", "me", "we", "our", "you",
    "your", "that", "this", "with", "so", "but", "or", "as", "if", "then",
}


def parse_report(path):
    """{utterance: {rows, routes, operation, text}} from a probe report."""
    seen = {}
    for block in BLOCK.split(open(path).read()):
        head = HEAD.match(block)
        if not head:
            continue
        seen[head.group(1)] = {
            "rows": len(re.findall(r"row title:", block)),
            "routes": re.findall(r"route:\s+(\S+)", block),
            "operation": bool(re.search(r"operation:", block)),
            # Everything the user would actually see or keep, which is what the
            # marker and content criteria are about.
            "text": " ".join(
                re.findall(r"row title:\s+(.*)", block) + re.findall(r"quote:\s+(.*)", block)
            ),
        }
    return seen


#: The label columns this set carries, beyond the id and the utterance that
#: `corpus_paths` knows about for every corpus.
COLUMNS = ("id", "utterance", "family", "expected_destination", "expected_thoughts")


def read_set(path):
    """Pairs and unpaired rows, read through the shared corpus reader.

    This used to open the file and split on tabs itself, taking the first
    non-comment line as the header. That passes on `rambling.tsv` by luck --
    its header really is the first uncommented line, at line 98 -- and it is
    the reader the gate in `test_score.py` exists to refuse, because the same
    two assumptions have been wrong elsewhere in this directory. `data_rows`
    finds the header by the cells it names, and `column_of` finds a column by
    its name rather than by counting.
    """
    lines = pathlib.Path(path).read_text(encoding="utf-8").splitlines()
    index = {name: paths.column_of(lines, name) for name in COLUMNS}
    pairs, unpaired = {}, []
    for _, row in paths.data_rows(path):
        match = re.match(r"^(RB\d+)([CR])$", row[index["id"]])
        if match:
            pairs.setdefault(match.group(1), {})[match.group(2)] = row
        else:
            unpaired.append(row)
    complete = {k: v for k, v in pairs.items() if "C" in v and "R" in v}
    return index, complete, unpaired


def content_words(text):
    return {w for w in re.findall(r"[a-z']+", text.lower()) if w not in STOPWORDS and len(w) > 2}


def pair_findings(clean_utterance, messy_utterance, clean, messy):
    """Criteria 1, 2, 3, 4, 8 and 9, as {name: bool}."""
    findings = {
        "1 same thought count": clean["rows"] == messy["rows"],
        "2 same destination": clean["routes"] == messy["routes"],
        "3 same operation status": clean["operation"] == messy["operation"],
    }
    # 4: a marker the messy twin SAID must survive into what it kept, whenever
    # the clean twin's own marker survived. A marker never spoken is not a loss.
    said = {m.lower().replace("’", "'") for m in MARKERS.findall(messy_utterance)}
    kept = {m.lower().replace("’", "'") for m in MARKERS.findall(messy["text"])}
    findings["4 markers survive"] = said <= kept if said else True
    # 8: every content word of the CLEAN twin reaches some row of the messy one.
    findings["8 no lost content"] = content_words(clean_utterance) <= content_words(messy["text"])
    # 9: no pure filler survives into a stored row.
    findings["9 filler removed"] = not FILLERS.search(messy["text"])
    return findings


def span_findings(record, atom_count):
    """Criteria 5, 6 and 7 over one capture's spans.

    `record` is `{"segments": [{"startAtom": int, "endAtom": int}, ...]}`.
    Criterion 3 of Calvin's falsifier list — over-wide spans — is reported as a
    count rather than a pass, because "too wide" needs a label to be a failure
    and this set does not carry span labels.
    """
    segments = record.get("segments", [])
    spans = [(s["startAtom"], s["endAtom"]) for s in segments]
    in_range = all(0 <= a <= b < atom_count for a, b in spans)
    nested = any(
        i != j and a >= c and b <= d
        for i, (a, b) in enumerate(spans)
        for j, (c, d) in enumerate(spans)
        if i != j
    )
    overlapping = any(
        max(a, c) <= min(b, d)
        for i, (a, b) in enumerate(spans)
        for j, (c, d) in enumerate(spans)
        if i < j
    )
    covered = set()
    for a, b in spans:
        if 0 <= a <= b < atom_count:
            covered |= set(range(a, b + 1))
    return {
        "5 no fabricated span": in_range,
        "6 no invalid span": in_range,
        "7 no nested or overlapping span": not (nested or overlapping),
        "widest span (atoms)": max((b - a + 1 for a, b in spans), default=0),
        "atoms in no segment": atom_count - len(covered),
    }


# ---------------------------------------------------------------------------
# The report-only semantic-boundary diagnostic (Calvin's item 3, 2026-09-16).
#
# The boundary representation makes overlap, nesting and uncovered atoms
# impossible, so criteria 5, 6 and 7 become structurally satisfied and stop
# measuring anything. What it does NOT make impossible is a boundary in a
# semantically wrong place, and the spike produced one with the right thought
# count:
#
#     I was thinking I should call | Mike but actually email him instead
#
# Two segments, every atom once, and the cut falls between a verb and its
# object. Nothing frozen catches that, because the row count is right.
#
# This is a COUNT, never a pass. It is a deterministic proxy over closed word
# lists, not a parser: it UNDER-reports, because it cannot see an open-class
# verb it does not list. Read it as "at least this many boundaries are
# suspect", and read the named rows by eye.

# Words that cannot be the last word of a finished thought because they require
# something after them. Closed classes, plus the handful of transitive verbs
# this corpus actually uses.
NEEDS_A_COMPLEMENT = {
    # determiners and possessives
    "the", "a", "an", "my", "our", "your", "his", "her", "their", "its",
    # prepositions and the infinitival marker
    "to", "of", "for", "with", "at", "in", "on", "from", "about", "into",
    # conjunctions and auxiliaries
    "and", "or", "but", "so", "because", "that", "is", "are", "was", "were",
    "am", "be", "been", "will", "would", "should", "could", "can", "must",
    "need", "needs", "have", "has", "had", "do", "does", "did", "going",
    # the transitive verbs this corpus is made of
    "call", "email", "text", "message", "buy", "get", "grab", "pick", "send",
    "tell", "ask", "remind", "book", "order", "collect", "cancel", "check",
    "bring", "take", "pay", "return", "renew", "confirm", "schedule",
}


def boundary_diagnostic(segment_texts):
    """Suspect boundaries in one reading. Counts and reasons, never a verdict."""
    findings = []
    for position, text in enumerate(segment_texts):
        words = re.findall(r"[a-z']+", text.lower())
        if not words:
            findings.append((position, "segment has no word in it"))
            continue
        if not [w for w in words if w not in STOPWORDS]:
            findings.append((position, "segment is entirely function words"))
        # The last segment ending on a complement-taking word is the sentence
        # trailing off, which is abandonment rather than a bad cut.
        if position < len(segment_texts) - 1 and words[-1] in NEEDS_A_COMPLEMENT:
            findings.append((position, f"ends on {words[-1]!r}, which needs what follows it"))
        if len(words) == 1 and position < len(segment_texts) - 1:
            findings.append((position, f"single-word segment {words[0]!r}"))
    return findings


def report(name, index, pairs, produced):
    tally, missing = {}, 0
    for stem, twins in sorted(pairs.items()):
        clean_utterance = twins["C"][index["utterance"]]
        messy_utterance = twins["R"][index["utterance"]]
        clean, messy = produced.get(clean_utterance), produced.get(messy_utterance)
        if not clean or not messy:
            missing += 1
            continue
        for criterion, passed in pair_findings(clean_utterance, messy_utterance, clean, messy).items():
            tally.setdefault(criterion, 0)
            tally[criterion] += 1 if passed else 0
    total = len(pairs) - missing
    print(f"{name}: {total} of {len(pairs)} pairs scored" + (f" ({missing} not found in the report)" if missing else ""))
    for criterion in sorted(tally):
        print(f"   {criterion:<32}{tally[criterion]:>4} / {total}")
    return tally


def selftest():
    fixture = '''── "call the dentist and email Priya"
   item 1 of 2:
     row title:  Call the dentist
     route:      Today   type: task   category: none   priority: normal
   item 2 of 2:
     row title:  Email Priya
     route:      Today   type: task   category: none   priority: normal

── "um so I might call the dentist y'know and email Priya"
   item 1 of 2:
     row title:  Might call the dentist
     route:      Today   type: task   category: none   priority: normal
   item 2 of 2:
     row title:  Email Priya
     route:      Today   type: task   category: none   priority: normal
'''
    import tempfile, os
    handle, path = tempfile.mkstemp(suffix=".out")
    with os.fdopen(handle, "w") as out:
        out.write(fixture)
    produced = parse_report(path)
    os.unlink(path)
    assert len(produced) == 2, produced
    clean = produced["call the dentist and email Priya"]
    messy = produced["um so I might call the dentist y'know and email Priya"]
    assert clean["rows"] == 2 and messy["rows"] == 2
    good = pair_findings("call the dentist and email Priya",
                         "um so I might call the dentist y'know and email Priya", clean, messy)
    assert all(good.values()), good

    # Each criterion must be able to FAIL, or it is not measuring anything.
    dropped = dict(messy, text="Call the dentist Email Priya")
    assert pair_findings("call the dentist and email Priya",
                         "um so I might call the dentist y'know and email Priya",
                         clean, dropped)["4 markers survive"] is False
    kept_filler = dict(messy, text=messy["text"] + " um")
    assert pair_findings("a", "b", clean, kept_filler)["9 filler removed"] is False
    fewer = dict(messy, rows=1)
    assert pair_findings("a", "b", clean, fewer)["1 same thought count"] is False
    elsewhere = dict(messy, routes=["Memory"])
    assert pair_findings("a", "b", clean, elsewhere)["2 same destination"] is False
    lost = dict(messy, text="Call the dentist")
    assert pair_findings("call the dentist and email Priya", "x", clean, lost)["8 no lost content"] is False

    clean_spans = span_findings({"segments": [{"startAtom": 0, "endAtom": 2}, {"startAtom": 3, "endAtom": 5}]}, 6)
    assert clean_spans["5 no fabricated span"] and clean_spans["7 no nested or overlapping span"]
    assert clean_spans["atoms in no segment"] == 0 and clean_spans["widest span (atoms)"] == 3
    out_of_range = span_findings({"segments": [{"startAtom": 0, "endAtom": 9}]}, 6)
    assert out_of_range["5 no fabricated span"] is False
    nested = span_findings({"segments": [{"startAtom": 0, "endAtom": 5}, {"startAtom": 1, "endAtom": 2}]}, 6)
    assert nested["7 no nested or overlapping span"] is False
    wide = span_findings({"segments": [{"startAtom": 0, "endAtom": 5}]}, 6)
    assert wide["widest span (atoms)"] == 6


    # The boundary diagnostic: silent on a clean cut, and it must actually fire
    # on the spike's case, which has the RIGHT thought count and a wrong cut.
    assert boundary_diagnostic(["call the dentist tomorrow", "pick up the prescription"]) == []
    spike = boundary_diagnostic(["I was thinking I should call", "Mike but actually email him instead"])
    assert any("needs what follows it" in reason for _, reason in spike), spike
    # A trailing complement-taking word in the LAST segment is the sentence
    # trailing off, not a bad boundary, so it must not be reported.
    assert boundary_diagnostic(["buy milk", "and then I need to"]) == []
    assert any("entirely function words" in r for _, r in boundary_diagnostic(["and then", "buy milk"]))
    assert any("single-word" in r for _, r in boundary_diagnostic(["tomorrow", "buy milk"]))

    # Last, so a green line cannot print while a later assertion is still to run.
    print("selftest: every criterion passes on a good pair and fails on a broken one,\n          and the boundary diagnostic is silent on a clean cut and fires on a bad one")


def main():
    if "--selftest" in sys.argv:
        selftest()
        return
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    set_path, baseline_path = sys.argv[1], sys.argv[2]
    index, pairs, unpaired = read_set(set_path)
    print(f"{set_path}: {len(pairs)} complete pairs, {len(unpaired)} unpaired "
          f"({', '.join(r[index['id']] for r in unpaired)})")
    print()
    baseline = report("baseline", index, pairs, parse_report(baseline_path))
    if "--candidate" in sys.argv:
        candidate_path = sys.argv[sys.argv.index("--candidate") + 1]
        print()
        candidate = report("candidate", index, pairs, parse_report(candidate_path))
        print()
        print("change, candidate minus baseline")
        for criterion in sorted(baseline):
            delta = candidate.get(criterion, 0) - baseline[criterion]
            print(f"   {criterion:<32}{delta:>+4}")


if __name__ == "__main__":
    main()
