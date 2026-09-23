#!/usr/bin/env python3
"""The decision rule for the semantic-unit experiment, written and pinned
before any generation. It reads only what score_units.py reads and prints one
outcome with every gate's value, so the decision is a computation, not a
reading of the numbers after the fact.

    decide.py --gold gold/gold.json --inputs inputs.jsonl --results results.jsonl --families families.json
    decide.py selftest

Outcomes: RUN INVALID (no decision), A (candidate 1, ranges, wins),
B (candidate 2, labels, wins), C (neither). There is no fourth outcome.
The rule and its reasons are in DECISION_PLAN.md.
"""
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import score_units as su  # noqa: E402

EXPECTED_FINGERPRINTS = {"ranges": "df4c6e25", "labels": "71e026b5"}
CANDIDATES = {"ranges": "A", "labels": "B"}

MATERIAL_GAIN = 4          # exact captures over the constant one-unit answer, in BOTH views
MULTI_UNIT_SHARE = 0.5     # of captures whose gold has >= 2 units, view `any`
# Counted by flag, not primary class: an over-split that also drops an atom is
# primarily "dropped" and must still count as a cut (grader round 8, F1).
# Filler-only is silent too: nothing at runtime knows which atoms are filler.
SILENT_CUT_CLASSES = {"over-split", "absorbed", "wrong-boundaries", "filler-only"}
# The guarded-family gate is about separating content from its carrier, so a
# unit that is only filler counts there only when it also cuts content (round 9).
GUARDED_CUT_CLASSES = {"over-split", "absorbed", "wrong-boundaries"}
MAX_SILENT_CUTS = 3        # captures, view `any`
MAX_BROKEN_SINGLES = 2     # captures the one-unit answer gets exact and the candidate does not
NO_SILENT_CUT_FAMILIES = {"reported-speech", "message-content", "deliberation-decision"}
CLEAR_MARGIN = 3           # exact captures, in BOTH views, for one qualifier to beat the other
MIN_LABELS_REPRESENTABLE = 29   # of 30, in both views (Calvin's condition for candidate 2)

# GenerationError case names that are the model's own behaviour, scored as
# malformed or refused. Any other failure (an infrastructure case such as rate
# limiting, concurrent requests or missing assets, our schema construction, or
# a name not listed here) makes the run invalid. The names are from memory and
# were not checked against Apple's documentation; a wrong or missing name fails
# safe, as RUN INVALID, never as a scored failure.
MODEL_BEHAVIOUR_ERRORS = {"guardrailViolation", "refusal", "decodingFailure", "exceededContextWindowSize", "decode"}


def validity(results, inputs):
    """Reasons the run cannot be decided on; empty when it can."""
    reasons = []
    ids = [item["id"] for item in inputs]
    lines = {item["id"]: len(item["lines"]) for item in inputs}
    stray = sorted({f"{r.get('arm')}:{r.get('id')}" for r in results
                    if r.get("arm") not in EXPECTED_FINGERPRINTS or r.get("id") not in lines})
    if stray:
        reasons.append(f"records for an unknown arm or capture: {', '.join(stray)}")
    for arm, fingerprint in EXPECTED_FINGERPRINTS.items():
        records = [r for r in results if r.get("arm") == arm]
        counts = Counter(r["id"] for r in records)
        missing = [i for i in ids if counts[i] == 0]
        doubled = [i for i in ids if counts[i] > 1]
        if missing:
            reasons.append(f"{arm}: no record for {len(missing)} capture(s): {', '.join(missing)}")
        if doubled:
            reasons.append(f"{arm}: more than one record for {', '.join(doubled)} (an unrecorded retry)")
        prints = {r.get("promptFingerprint") for r in records}
        if records and prints != {fingerprint}:
            reasons.append(f"{arm}: prompt fingerprint {sorted(map(str, prints))}, pinned {fingerprint}")
        if any(r.get("job", {}).get("outcome") == "skipped" and r.get("job", {}).get("skip") != "tooShortToSplit"
               for r in records):
            reasons.append(f"{arm}: a job was skipped for a reason other than a one-line capture (model unavailable?)")
        short = [r["id"] for r in records if r.get("job", {}).get("skip") == "tooShortToSplit"
                 and (arm != "labels" or lines.get(r["id"], 0) >= 2)]
        if short:
            reasons.append(f"{arm}: skipped as one line but is not: {', '.join(short)}")
        infra = sorted({str(r["job"].get("generationError")) for r in records
                        if r.get("job", {}).get("outcome") == "generationFailed"
                        and r["job"].get("generationError") not in MODEL_BEHAVIOUR_ERRORS})
        if infra:
            reasons.append(f"{arm}: generation failed for a reason that is not the model's answer: {', '.join(infra)}")
    return reasons


def representable_labels(inputs, golds):
    return sum(1 for row in su.precheck(golds, inputs) if row[4] == "representable")


def gates(arm, table, own_table, golds_any, golds_own, families, inputs):
    def exact(source, ids=None):
        return sum(1 for r in source if arm in r and r[arm][0] == "exact" and (ids is None or r["id"] in ids))

    def baseline(source, name="one-unit"):
        return sum(1 for r in source if r[name][0] == "exact")

    multi = su.multi_ids(golds_any)
    silent = [r["id"] for r in table if arm in r and set(r[arm][1]) & SILENT_CUT_CLASSES]
    risky = [r["id"] for r in table if arm in r and set(r[arm][1]) & GUARDED_CUT_CLASSES
             and set(families.get(r["id"], [])) & NO_SILENT_CUT_FAMILIES]
    broken = [r["id"] for r in table if r["one-unit"][0] == "exact" and arm in r and r[arm][0] != "exact"]
    values = {
        "exact_any": exact(table), "exact_own": exact(own_table),
        "baseline_any": baseline(table), "baseline_own": baseline(own_table),
        "multi_exact": exact(table, multi), "multi_total": len(multi),
        "every_line_any": baseline(table, "every-line"), "every_line_own": baseline(own_table, "every-line"),
        "silent_cuts": silent, "silent_cuts_in_guarded_families": risky, "broken_singles": broken,
    }
    checks = [
        # Implied by the multi-unit and broken-single gates (one-unit is exact on
        # exactly the non-multi captures), kept so the report shows the number.
        ("material gain over one-unit, view any",
         values["exact_any"] - values["baseline_any"] >= MATERIAL_GAIN,
         f"{values['exact_any']} - {values['baseline_any']} >= {MATERIAL_GAIN}"),
        ("material gain over one-unit, view own",
         values["exact_own"] - values["baseline_own"] >= MATERIAL_GAIN,
         f"{values['exact_own']} - {values['baseline_own']} >= {MATERIAL_GAIN}"),
        ("multi-unit recovery, view any",
         values["multi_exact"] >= MULTI_UNIT_SHARE * values["multi_total"],
         f"{values['multi_exact']} >= {MULTI_UNIT_SHARE} x {values['multi_total']}"),
        ("silent wrong cuts (over-split, absorbed, wrong-boundaries, filler-only)",
         len(silent) <= MAX_SILENT_CUTS, f"{len(silent)} <= {MAX_SILENT_CUTS}: {', '.join(silent) or 'none'}"),
        ("no content cut in reported speech, message content or deliberation",
         not risky, ", ".join(risky) or "none"),
        ("single-unit captures broken",
         len(broken) <= MAX_BROKEN_SINGLES, f"{len(broken)} <= {MAX_BROKEN_SINGLES}: {', '.join(broken) or 'none'}"),
        ("beats every-line in both views",
         values["exact_any"] > values["every_line_any"] and values["exact_own"] > values["every_line_own"],
         f"{values['exact_any']} > {values['every_line_any']}, {values['exact_own']} > {values['every_line_own']}"),
    ]
    if arm == "labels":
        counts = (representable_labels(inputs, golds_any), representable_labels(inputs, golds_own))
        checks.append(("clause lines can express the gold, both views",
                       min(counts) >= MIN_LABELS_REPRESENTABLE,
                       f"{counts[0]}, {counts[1]} >= {MIN_LABELS_REPRESENTABLE} of {len(inputs)}"))
    return values, checks


def decide(results, inputs, golds_any, golds_own, families):
    """Returns (outcome, lines)."""
    lines = []
    invalid = validity(results, inputs)
    if invalid:
        return "RUN INVALID", ["The run cannot be decided on:"] + [f"  - {r}" for r in invalid]
    table, _ = su.score_run(golds_any, inputs, results, {})
    own_table, _ = su.score_run(golds_own, inputs, results, {})
    qualified, values = {}, {}
    for arm in CANDIDATES:
        values[arm], checks = gates(arm, table, own_table, golds_any, golds_own, families, inputs)
        qualified[arm] = all(ok for _, ok, _ in checks)
        lines.append(f"{arm} (candidate {'1' if arm == 'ranges' else '2'}): {'QUALIFIES' if qualified[arm] else 'does not qualify'}")
        for name, ok, detail in checks:
            lines.append(f"  {'pass' if ok else 'FAIL'}  {name}: {detail}")
    lines.append("")
    both = [arm for arm in CANDIDATES if qualified[arm]]
    if not both:
        lines.append("Neither candidate passes every gate.")
        return "C", lines
    if len(both) == 1:
        lines.append(f"Only {both[0]} passes every gate.")
        return CANDIDATES[both[0]], lines
    r, lab = values["ranges"], values["labels"]
    if all(r[k] - lab[k] >= CLEAR_MARGIN for k in ("exact_any", "exact_own")):
        lines.append(f"Both qualify; ranges leads by >= {CLEAR_MARGIN} in both views.")
        return "A", lines
    if all(lab[k] - r[k] >= CLEAR_MARGIN for k in ("exact_any", "exact_own")):
        lines.append(f"Both qualify; labels leads by >= {CLEAR_MARGIN} in both views.")
        return "B", lines
    lines.append(f"NO CLEAR WINNER: both qualify and neither leads by >= {CLEAR_MARGIN} in both views. "
                 "Candidate 1's conditions hold; candidate 2's do not, because it does not materially "
                 "outperform candidate 1 and its simplification is not measured here. So A, by the stated "
                 "conditions and not by a clear margin (DECISION_PLAN.md).")
    return "A", lines


def load(options):
    import json
    inputs = su.read_jsonl(options["inputs"])
    counts = {item["id"]: len(item["atoms"]) for item in inputs}
    families = json.loads(Path(options["families"]).read_text())
    return (su.read_jsonl(options["results"]), inputs, su.load_gold(options["gold"], counts, "any"),
            su.load_gold(options["gold"], counts, "own"), families)


# ------------------------------------------------------------------ selftest

def selftest():
    """Synthetic runs with a known right outcome, built from the real frozen
    gold and inputs so every gate sees the real families and unit counts."""
    import json
    here = Path(__file__).resolve().parent
    results_unused, inputs, golds_any, golds_own, families = load({
        "inputs": here / "inputs.jsonl", "gold": here / "gold" / "gold.json",
        "families": here / "families.json", "results": here / "inputs.jsonl"})
    del results_unused

    def best_own(cid):
        # A contiguous reading from the `own` view, as ranges.
        for gold in golds_own[cid]:
            units, reason = su.best_ranges(gold)
            if reason is None or reason.startswith("capacity"):
                return [(min(u), max(u)) for u in units]
        raise AssertionError(cid)

    def job(**extra):
        return dict({"outcome": "accepted", "latencyMilliseconds": 100}, **extra)

    def ranges_record(item, spans):
        return {"id": item["id"], "arm": "ranges", "order": 0, "promptFingerprint": "df4c6e25",
                "job": job(), "raw": json.dumps({"thoughts": [{"firstAtom": a, "lastAtom": b} for a, b in spans]})}

    def labels_record(item, starts):
        lines = item["lines"]
        if len(lines) < 2:
            return {"id": item["id"], "arm": "labels", "order": 1, "promptFingerprint": "71e026b5",
                    "job": {"outcome": "skipped", "skip": "tooShortToSplit"}, "raw": None}
        raw = {"lines": [{"line": i, "label": "starts" if (i == 0 or first in starts) else "continues"}
                         for i, (first, _) in enumerate(lines)]}
        return {"id": item["id"], "arm": "labels", "order": 1, "promptFingerprint": "71e026b5",
                "job": job(), "raw": json.dumps(raw)}

    def perfect_starts(item):
        # A representable `own` reading, as the clause lines that begin its units.
        for gold in golds_own[item["id"]]:
            units, reason = su.best_labels(gold, item["lines"])
            if reason is None:
                return {min(u) for u in units}
        raise AssertionError(item["id"])

    def whole(item):
        return [(0, len(item["atoms"]) - 1)]

    failures = 0

    def expect(name, results, want):
        nonlocal failures
        got, lines = decide(results, inputs, golds_any, golds_own, families)
        if got != want:
            failures += 1
            print(f"FAIL {name}: got {got}, want {want}")
            print("\n".join(lines))

    perfect_r = [ranges_record(i, best_own(i["id"])) for i in inputs]
    perfect_l = [labels_record(i, perfect_starts(i)) for i in inputs]
    whole_r = [ranges_record(i, whole(i)) for i in inputs]
    whole_l = [labels_record(i, set()) for i in inputs]
    every_l = [labels_record(i, {a for a, _ in i["lines"]}) for i in inputs]

    expect("both constant (one unit)", whole_r + whole_l, "C")
    expect("perfect ranges, constant labels", perfect_r + whole_l, "A")
    expect("constant ranges, perfect labels", whole_r + perfect_l, "B")
    expect("constant ranges, every line starts", whole_r + every_l, "C")
    expect("both perfect: no clear margin, A by the conditions", perfect_r + perfect_l, "A")
    expect("a missing record", perfect_r[1:] + perfect_l, "RUN INVALID")
    expect("a changed prompt", [dict(r, promptFingerprint="00000000") for r in perfect_r] + perfect_l, "RUN INVALID")
    expect("an unrecorded retry", perfect_r + perfect_r[:1] + perfect_l, "RUN INVALID")
    # Perfect ranges except that every reported-speech capture is cut in two.
    cut = []
    for item, record in zip(inputs, perfect_r):
        if "reported-speech" in families.get(item["id"], []) and len(item["atoms"]) >= 4:
            n = len(item["atoms"])
            record = ranges_record(item, [(0, n // 2 - 1), (n // 2, n - 1)])
        cut.append(record)
    expect("reported speech cut: ranges disqualified", cut + whole_l, "C")
    expect("reported speech cut, perfect labels", cut + perfect_l, "B")

    multi = sorted(su.multi_ids(golds_any))
    by_id = {i["id"]: i for i in inputs}

    def replace(records, ids, make):
        return [make(by_id[r["id"]]) if r["id"] in ids else r for r in records]

    # F1: a guarded cut that also leaves one atom out is primarily "dropped";
    # the flag still counts it.
    for cid in ("RS03", "CM06", "RB33R"):
        item = by_id[cid]
        spans = best_own(cid)
        a, b = spans[0]
        if b - a >= 2:
            masked = [(a, a + (b - a) // 2 - 1), (a + (b - a) // 2 + 1, b)] + spans[1:]
            run = replace(perfect_r, {cid}, lambda i, m=masked: ranges_record(i, m))
            expect(f"guarded cut masked by a dropped atom ({cid})", run + whole_l, "C")
    # A filler-only unit: one extra start on a filler line. It spends the silent
    # budget but, alone, is not a content cut in a guarded family.
    def extra_filler_start(item):
        for gold in golds_any[item["id"]]:
            for first, last in item["lines"]:
                if first and set(range(first, last + 1)) <= gold.filler:
                    return perfect_starts(item) | {first}
        return None
    filler_ids = [i["id"] for i in inputs if extra_filler_start(i) is not None]
    guarded = [c for c in filler_ids if set(families.get(c, [])) & NO_SILENT_CUT_FAMILIES]
    unguarded = [c for c in filler_ids if c not in guarded]
    if guarded:
        run = replace(perfect_l, {guarded[0]}, lambda i: labels_record(i, extra_filler_start(i)))
        expect(f"one filler-only unit in a guarded family ({guarded[0]}) does not disqualify", whole_r + run, "B")
    run = replace(perfect_l, set(unguarded[:4]), lambda i: labels_record(i, extra_filler_start(i)))
    expect("four filler-only units exceed the silent budget", whole_r + run, "C")
    # Outright wins inside both-qualify.
    expect("A outright: labels all-continues on 4 multi-unit captures",
           perfect_r + replace(perfect_l, set(multi[:4]), lambda i: labels_record(i, set())), "A")
    expect("B outright: ranges one unit on 3 multi-unit captures",
           replace(perfect_r, set(multi[:3]), lambda i: ranges_record(i, whole(i))) + perfect_l, "B")
    # Validity.
    other_skip = [dict(r, job={"outcome": "skipped", "skip": "modelUnavailable"}) if r["id"] == "RB13R" else r
                  for r in perfect_l]
    expect("a skip that is not a one-line capture", perfect_r + other_skip, "RUN INVALID")
    infra = [dict(r, job={"outcome": "generationFailed", "generationError": "rateLimited"}, raw=None)
             if r["id"] == "RB13R" else r for r in perfect_r]
    expect("an infrastructure failure", infra + perfect_l, "RUN INVALID")
    refused = [dict(r, job={"outcome": "generationFailed", "generationError": "guardrailViolation"}, raw=None)
               if r["id"] == "RB13R" else r for r in perfect_r]
    expect("a model refusal is scored, not invalid", refused + whole_l, "A")
    expect("a record for an unknown capture", perfect_r + perfect_l + [dict(perfect_r[0], id="XX99")], "RUN INVALID")
    fake_short = [dict(r, job={"outcome": "skipped", "skip": "tooShortToSplit"}, raw=None) if r["id"] == "RB13R" else r
                  for r in perfect_l]
    expect("a one-line skip on a capture with several lines", perfect_r + fake_short, "RUN INVALID")
    print("decide selftest", "ok" if not failures else f"FAILED ({failures})")
    return failures == 0


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "selftest":
        return 0 if selftest() else 1
    options = su.args_map(sys.argv[1:])
    if not all(k in options for k in ("gold", "inputs", "results", "families")):
        print(__doc__)
        return 2
    outcome, lines = decide(*load(options))
    print("\n".join(lines))
    print()
    clear = " (no clear winner)" if any(line.startswith("NO CLEAR WINNER") for line in lines) else ""
    print(f"OUTCOME {outcome}{clear}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
