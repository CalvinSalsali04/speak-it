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
SILENT_CUT_CLASSES = {"over-split", "absorbed", "wrong-boundaries"}
MAX_SILENT_CUTS = 3        # captures, view `any`
MAX_BROKEN_SINGLES = 2     # captures the one-unit answer gets exact and the candidate does not
NO_SILENT_CUT_FAMILIES = {"reported-speech", "message-content", "deliberation-decision"}
CLEAR_MARGIN = 3           # exact captures, in BOTH views, for one qualifier to beat the other


def validity(results, inputs):
    """Reasons the run cannot be decided on; empty when it can."""
    reasons = []
    ids = [item["id"] for item in inputs]
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
    return reasons


def gates(arm, table, own_table, golds_any, golds_own, families):
    def exact(source, ids=None):
        return sum(1 for r in source if arm in r and r[arm][0] == "exact" and (ids is None or r["id"] in ids))

    def baseline(source):
        return sum(1 for r in source if r["one-unit"][0] == "exact")

    multi = su.multi_ids(golds_any)
    silent = [r["id"] for r in table if arm in r and r[arm][0] in SILENT_CUT_CLASSES]
    risky = [cid for cid in silent if set(families.get(cid, [])) & NO_SILENT_CUT_FAMILIES]
    broken = [r["id"] for r in table if r["one-unit"][0] == "exact" and arm in r and r[arm][0] != "exact"]
    values = {
        "exact_any": exact(table), "exact_own": exact(own_table),
        "baseline_any": baseline(table), "baseline_own": baseline(own_table),
        "multi_exact": exact(table, multi), "multi_total": len(multi),
        "silent_cuts": silent, "silent_cuts_in_guarded_families": risky, "broken_singles": broken,
    }
    checks = [
        ("material gain over one-unit, view any",
         values["exact_any"] - values["baseline_any"] >= MATERIAL_GAIN,
         f"{values['exact_any']} - {values['baseline_any']} >= {MATERIAL_GAIN}"),
        ("material gain over one-unit, view own",
         values["exact_own"] - values["baseline_own"] >= MATERIAL_GAIN,
         f"{values['exact_own']} - {values['baseline_own']} >= {MATERIAL_GAIN}"),
        ("multi-unit recovery, view any",
         values["multi_exact"] >= MULTI_UNIT_SHARE * values["multi_total"],
         f"{values['multi_exact']} >= {MULTI_UNIT_SHARE} x {values['multi_total']}"),
        ("silent wrong cuts (over-split, absorbed, wrong-boundaries)",
         len(silent) <= MAX_SILENT_CUTS, f"{len(silent)} <= {MAX_SILENT_CUTS}: {', '.join(silent) or 'none'}"),
        ("no silent cut in reported speech, message content or deliberation",
         not risky, ", ".join(risky) or "none"),
        ("single-unit captures broken",
         len(broken) <= MAX_BROKEN_SINGLES, f"{len(broken)} <= {MAX_BROKEN_SINGLES}: {', '.join(broken) or 'none'}"),
    ]
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
        values[arm], checks = gates(arm, table, own_table, golds_any, golds_own, families)
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
    if len(lab["silent_cuts"]) > len(r["silent_cuts"]):
        lines.append("Both qualify within the margin; labels makes more silent wrong cuts, so ranges.")
        return "A", lines
    lines.append("Both qualify within the margin and labels makes no more silent wrong cuts: labels, because its "
                 "cuts can only fall on deterministic clause edges and it has no thought cap (DECISION_PLAN.md).")
    return "B", lines


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
    expect("both perfect: tie goes to labels", perfect_r + perfect_l, "B")
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
    print(f"OUTCOME {outcome}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
