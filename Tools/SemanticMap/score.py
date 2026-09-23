#!/usr/bin/env python3
"""Scores what the semantic-map probe writes. Prints counts and closed-vocabulary
reasons only: no capture text, ever, in any mode, so every table below can be
pasted into a thread or a pull request whatever set produced it.

    score.py census  census.jsonl [--labels set.tsv]
    score.py trace   runs.jsonl
    score.py router  census.jsonl --labels set.tsv --report rules.report
    score.py whole   labels.jsonl --report arm.report [--runs runs.jsonl] [--ids]
    score.py select  census.jsonl --labels set.tsv --report rules.report --out diag.in --groups groups.json
    score.py diagnostic --groups groups.json --labels set.tsv --rules rules.report
                     --map map.report --map-records map.jsonl --asked asked.report --asked-records asked.jsonl
    score.py selftest

census  PHASE 1, no model. How production routes every capture: which exit the
        policy takes, how often a structurally complex capture is answered by
        the rules with nothing flagged, by length bucket and by family.
trace   PHASE 1 and 2, from a device run. Production's model route (outcome,
        the unbudgeted outcome, validation rejections, latency and tokens by
        length bucket), the three semantic-map jobs (outcomes, refusals, skips,
        latency, tokens) and the arbiter (verdict x topic, reasons, effects).
router  PHASE 3. Per-capture rules correctness from a labelled 5-column set
        (the held-out scorer's rules, re-implemented and checked against it by
        `selftest`), then each candidate feature's coverage and lift over the
        base failure rate, and production's current policy scored as a router.
        MEASURES, NEVER CHOOSES: a router is picked by a person reading this.
whole   PHASE 5. Whole-capture correctness against the fresh-slice label schema
        in `LABELS.md`, per category A-J, per family and per length bucket,
        with every sub-measure beside it. With `--runs`, the invocation,
        accepted-contribution and fallback rates for the map arm too.
select  The smallest diagnostic model input: every rules failure production
        does not send to the model, every confident-on-complex capture, and
        one matched rules-correct complex control per failure (its C/R twin
        where there is one, else the nearest in atoms). Prints ids and counts.
diagnostic  Reads that run back per group: model availability, each job's
        outcome, the arbiter's contribution, failures improved and correct
        captures damaged (map arm and production's own model as if asked),
        grounding rejections, latency and the final fallback.

Length buckets are in ATOMS (whitespace words of the original transcript),
which every machine can compute. Model tokens are reported beside them from
the run where Apple's tokenizer was reachable, never estimated.
"""
import json
import math
import re
import subprocess
import sys
import tempfile
from collections import Counter, OrderedDict, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent

BUCKETS = [(1, 10, "1-10"), (11, 25, "11-25"), (26, 50, "26-50"),
           (51, 100, "51-100"), (101, 10 ** 9, "101+")]


def bucket(atoms):
    for lo, hi, name in BUCKETS:
        if lo <= atoms <= hi:
            return name
    return "0"


def bucket_order():
    return ["0"] + [name for _, _, name in BUCKETS]


def read_jsonl(path):
    records, bad = [], 0
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                bad += 1
    if bad:
        # A line that does not parse is a schema or write fault, not a capture
        # that produced nothing. Never silently shrinks a denominator.
        print(f"  WARNING: {bad} unreadable line(s) in {path}", file=sys.stderr)
    return records


def percentile(values, q):
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(q * len(ordered)) - 1))
    return ordered[index]


def fmt(value):
    return "—" if value is None else str(value)


def confident_on_complex(features):
    """Mirrors `ComplexityFeatures.confidentOnComplex` in Swift: complex by
    structure (three or more clauses, or forty or more atoms), and the rules
    flagged nothing. Restated here because computed Swift properties are not
    encoded; `selftest` pins both definitions to the same cases in prose."""
    return (features["rulesNeedsReview"] == 0 and features["rulesUnresolvedState"] == 0
            and (features["clauses"] >= 3 or features["atoms"] >= 40))


# --------------------------------------------------------------------- labels

def load_five_column(path):
    """`id, utterance, family, expected_destination, expected_thoughts` --
    the held-out layout the development sets share."""
    rows = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#") or not line.strip():
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 5 and parts[0] != "id":
                rows.append({"id": parts[0], "utterance": parts[1], "family": parts[2].strip() or "untagged",
                             "destination": parts[3], "thoughts": parts[4]})
    return rows


# ------------------------------------------------------------ report parsing
#
# The same regexes `Tools/CorpusRunner/heldout/score.py` uses, so a report this
# reads means what it means there. `selftest` runs that scorer on a fixture and
# checks the aggregates agree.

# Greedy to the end of the header line: a capture containing a double quote
# is otherwise cut at it and never joins its label. `heldout/score.py` still
# uses the non-greedy form; no held-out or development row contains one today,
# and `selftest` pins both the quote case here and agreement on the rest.
HEADER = re.compile(r'── "(.*)"[ \t]*$', re.M)


def parse_report(path):
    blocks = re.split(r'\n(?=── ")', Path(path).read_text(encoding="utf-8"))
    seen = {}
    for block in blocks:
        match = HEADER.match(block)
        if not match:
            continue
        rows = []
        for item in re.split(r"\n(?=   item \d+ of \d+:)", block)[1:]:
            quote = re.search(r"quote:\s+(.*)", item)
            title = re.search(r"row title:\s+(.*)", item)
            person = re.search(r"person:\s+(.*)", item)
            rows.append({
                "title": title.group(1).strip() if title else "",
                "quote": (quote or title).group(1).strip() if (quote or title) else "",
                "route": (re.search(r"route:\s+(\S+)", item) or [None, ""])[1],
                "due": (re.search(r"due:\s+(\S+)", item) or [None, "nil"])[1] != "nil",
                "remind": (re.search(r"remind:\s+(\S+)", item) or [None, "nil"])[1] != "nil",
                "location": "location:" in item,
                "recurs": "recurs:" in item,
                "person": person.group(1).strip() if person else None,
                "review": "needsReview: true" in item,
            })
        seen[match.group(1)] = {
            "rows": rows,
            "routes": re.findall(r"route:\s+(\S+)", block),
            "operations": re.findall(r"operation:\s+(\S+)", block),
            "due": any(v != "nil" for v in re.findall(r"due:\s+(\S+)", block)),
            "remind": any(v != "nil" for v in re.findall(r"remind:\s+(\S+)", block)),
        }
    return seen


# ---------------------------------------------- coarse per-capture correctness

def wanted_today(dest):
    return any(k in dest for k in ("Today", "Shopping", "Event", "Alarm"))


def acceptable_counts(label):
    text = label.strip()
    exact = re.fullmatch(r"(\d+)", text)
    if exact:
        return {int(exact.group(1))}, int(exact.group(1))
    span = re.fullmatch(r"(\d+)\s*-\s*(\d+)", text)
    if span:
        lo, hi = int(span.group(1)), int(span.group(2))
        return set(range(lo, hi + 1)), lo
    lead = re.match(r"^(\d+)", text)
    if lead:
        return {int(lead.group(1))}, int(lead.group(1))
    return set(), None


def coarse_verdict(row, got):
    """The held-out scorer's three measures for one capture.

    Returns a dict of {measure: True/False/None}; None is "not scored here",
    exactly where `heldout/score.py` skips a measure (an Ambiguous capture has
    no destination or count; an operation answer has no count). A capture is
    `rules_failed` when any scored measure is False. The count uses the
    range-aware reading, since a label range is the author saying both are
    correct.
    """
    verdict = {"produced": None, "unsafe": None, "destination": None, "count": None}
    if got is None:
        return verdict
    verdict["produced"] = bool(got["rows"]) or bool(got["operations"])
    dest = row["destination"]
    if "Ambiguous" in dest:
        verdict["unsafe"] = bool(got["operations"]) or got["remind"] or got["due"]
        return verdict
    if "Operation" in dest:
        verdict["destination"] = bool(got["operations"])
    elif wanted_today(dest):
        verdict["destination"] = "Today" in got["routes"]
    else:
        verdict["destination"] = bool(got["routes"]) and "Memory" in got["routes"]
    acceptable, strict = acceptable_counts(row["thoughts"])
    if strict is not None and not got["operations"]:
        verdict["count"] = len(got["rows"]) in acceptable
    return verdict


def failed(verdict):
    return (verdict["produced"] is False or verdict["unsafe"] is True
            or verdict["destination"] is False or verdict["count"] is False)


# ------------------------------------------------------------------- census

def census(args):
    records = read_jsonl(args[0])
    labels = {}
    if "--labels" in args:
        labels = {r["id"]: r for r in load_five_column(args[args.index("--labels") + 1])}
    if not records:
        print("no records")
        return 1
    drift = sum(1 for r in records if r.get("policyDrift"))
    commits = Counter(r.get("commit") for r in records)
    print(f"PRODUCTION ROUTE CENSUS — {len(records)} captures, commit(s) "
          + ", ".join(f"{c} x{n}" for c, n in commits.items()))
    print("=" * 78)
    if drift:
        print(f"  POLICY DRIFT on {drift} capture(s): the decomposed reason disagrees with")
        print("  RefinementPolicy.shouldRefine. Do not quote this table until it is fixed.")
    reasons = Counter(r["policy"] for r in records)
    for reason, n in reasons.most_common():
        print(f"  {reason:<34}{n:>6}  ({100 * n / len(records):5.1f}%)")
    print("-" * 78)
    complex_confident = [r for r in records if confident_on_complex(r["features"])]
    print(f"  structurally complex, rules flagged nothing: {len(complex_confident)}"
          f"  (the model is never asked about these)")
    print("  complex = three or more clauses or forty or more atoms; a SHAPE, not an")
    print("  error. Whether the rules were right about them is `router`'s question.")
    print()
    print(f"{'atoms':<10}{'n':>6}{'eligible':>10}{'noReview':>10}{'operation':>11}{'complex+confident':>19}")
    by_bucket = defaultdict(list)
    for r in records:
        by_bucket[bucket(r["features"]["atoms"])].append(r)
    for name in bucket_order():
        group = by_bucket.get(name)
        if not group:
            continue
        print(f"{name:<10}{len(group):>6}"
              f"{sum(r['policy'] == 'eligible' for r in group):>10}"
              f"{sum(r['policy'] == 'noRowNeedsReview' for r in group):>10}"
              f"{sum(r['policy'] == 'operationPresent' for r in group):>11}"
              f"{sum(confident_on_complex(r['features']) for r in group):>19}")
    if labels:
        print()
        print(f"{'family':<32}{'n':>5}{'eligible':>10}{'complex+confident':>19}")
        by_family = defaultdict(list)
        unlabelled = 0
        for r in records:
            label = labels.get(r.get("id"))
            if label is None:
                unlabelled += 1
                continue
            by_family[label["family"]].append(r)
        for family in sorted(by_family):
            group = by_family[family]
            print(f"{family:<32}{len(group):>5}{sum(r['policy'] == 'eligible' for r in group):>10}"
                  f"{sum(confident_on_complex(r['features']) for r in group):>19}")
        if unlabelled:
            print(f"  {unlabelled} record(s) carry no id matching the labels and are not in this table")
    return 0


# -------------------------------------------------------------------- trace

def trace(args):
    records = read_jsonl(args[0])
    if not records:
        print("no records")
        return 1
    settings = Counter(json.dumps({k: v for k, v in r["settings"].items() if k != "operatingSystem"},
                                  sort_keys=True) for r in records)
    print(f"DEVICE RUN — {len(records)} captures, {len(settings)} distinct setting block(s)")
    if len(settings) > 1:
        print("  WARNING: more than one configuration in one file; figures below mix them.")
    first = records[0]["settings"]
    print(f"  commit {first['commit']}{' (dirty)' if first['treeDirty'] else ''}  locale {first['locale']}"
          f"  atoms {first['atomFormat']}  shadow {first['shadow']}  jobs {first['jobs']}")
    print("=" * 78)

    production = [r["production"] for r in records]
    print("PRODUCTION MODEL ROUTE")
    for drift_key, what in (("policyDrift", "policy"), ("validatorDrift", "validator")):
        n = sum(1 for p in production if p.get(drift_key))
        if n:
            print(f"  {what.upper()} DRIFT on {n} capture(s): the mirror disagrees with production. Stop here.")
    print(f"  {'policy':<32}" + "".join(f"{o:>11}" for o in ("n", "invoked")))
    for reason, n in Counter(p["policy"] for p in production).most_common():
        invoked = sum(1 for p in production if p["policy"] == reason and p.get("latencyMilliseconds") is not None)
        print(f"  {reason:<32}{n:>11}{invoked:>11}")
    print()
    print(f"  {'outcome (with the 2 s budget)':<32}{'n':>11}")
    for outcome, n in Counter(p["outcome"] for p in production).most_common():
        print(f"  {outcome:<32}{n:>11}")
    asked = [p for p in production if p.get("unbudgeted")]
    if asked:
        print()
        print(f"  {'outcome with no budget (asked)':<32}{'n':>11}")
        for outcome, n in Counter(p["unbudgeted"] for p in asked).most_common():
            print(f"  {outcome:<32}{n:>11}")
        lost = sum(1 for p in production if p["outcome"] == "budgetExpired" and p.get("unbudgeted") == "accepted")
        print(f"  the budget discarded {lost} answer(s) validation and the guard would have accepted")
        rejections = Counter(p["validation"] for p in production if p.get("validation"))
        if rejections:
            print("  validation rejections: " + ", ".join(f"{k} {v}" for k, v in rejections.most_common()))
        errors = Counter(p["generationError"] for p in production if p.get("generationError"))
        if errors:
            print("  generation errors: " + ", ".join(f"{k} {v}" for k, v in errors.most_common()))
    print()
    latency_table("production", [(r["features"]["atoms"], r["production"]) for r in records])

    print()
    print("SEMANTIC MAP JOBS")
    maps = [(r["features"]["atoms"], r["map"]) for r in records if r.get("map")]
    if not maps:
        print("  no map in these records (--no-jobs)")
    for job in ("unitsJob", "relationsJob", "entitiesJob"):
        jobs = [m[job] for _, m in maps]
        if not jobs:
            continue
        outcomes = Counter(j["outcome"] for j in jobs)
        print(f"  {job[:-3]:<10} " + ", ".join(f"{k} {v}" for k, v in outcomes.most_common()))
        refusals = Counter(j["refusal"] for j in jobs if j.get("refusal"))
        if refusals:
            print(f"  {'':<10} refused: " + ", ".join(f"{k} {v}" for k, v in refusals.most_common()))
        skips = Counter(j["skip"] for j in jobs if j.get("skip"))
        if skips:
            print(f"  {'':<10} skipped: " + ", ".join(f"{k} {v}" for k, v in skips.most_common()))
        errors = Counter(j["generationError"] for j in jobs if j.get("generationError"))
        if errors:
            print(f"  {'':<10} errors: " + ", ".join(f"{k} {v}" for k, v in errors.most_common()))
    if maps:
        sources = Counter(m["unitSource"] for _, m in maps)
        print("  relations asked over: " + ", ".join(f"{k} {v}" for k, v in sources.most_common()))
        kinds = Counter(rel["kind"] for _, m in maps for rel in (m.get("relations") or []))
        if kinds:
            print("  relations proposed: " + ", ".join(f"{k} {v}" for k, v in kinds.most_common()))
        entity_kinds = Counter(e["kind"] for _, m in maps for e in (m.get("entities") or []))
        if entity_kinds:
            print("  entity kinds: " + ", ".join(f"{k} {v}" for k, v in entity_kinds.most_common()))
            # The temporalRole / locationRole precedent: an enum the model
            # answers with one value is not evidence of anything.
            top, top_n = entity_kinds.most_common(1)[0]
            total = sum(entity_kinds.values())
            if total >= 20 and top_n / total >= 0.9:
                print(f"  DEGENERATE: {top} is {100 * top_n / total:.0f}% of {total} entity answers."
                      " Treat the entity job as uninformative until this moves.")
        for job in ("unitsJob", "relationsJob", "entitiesJob"):
            latency_table(job[:-3], [(atoms, m[job]) for atoms, m in maps])

    print()
    print("ARBITER (standard policy, as recorded; replay recomputes for any policy)")
    decisions = [d for r in records for d in r.get("decisions", [])]
    by_topic = defaultdict(Counter)
    for d in decisions:
        by_topic[d["topic"]][d["verdict"]] += 1
    verdicts = ["agree", "modelAddsStructure", "rulesStronger", "modelViolatesGrounding",
                "modelConflictsSafety", "unresolved"]
    print(f"  {'topic':<16}" + "".join(f"{v[:12]:>13}" for v in verdicts))
    for topic in sorted(by_topic):
        print(f"  {topic:<16}" + "".join(f"{by_topic[topic][v]:>13}" for v in verdicts))
    reasons = Counter((d["topic"], d["reason"]) for d in decisions)
    print("  reasons: " + ", ".join(f"{t}/{r} {n}" for (t, r), n in reasons.most_common()))
    effects = Counter(d["effect"] for d in decisions if d["effect"] != "none")
    print("  effects: " + (", ".join(f"{k} {v}" for k, v in effects.most_common()) or "none"))
    changed = sum(1 for r in records if r.get("mapChangedOutput"))
    print(f"  captures whose output the map changed: {changed}/{len(records)}")
    fell_back = sum(1 for d in decisions if d["reason"] == "executionOutsideRulesReading")
    if fell_back:
        print(f"  STRUCTURAL GUARANTEE FIRED on {fell_back} capture(s): an arbiter bug. Stop here.")
    doubled = [d.get("count") or 0 for d in decisions if d["reason"] == "executingRowsAdded"]
    if doubled:
        print(f"  EXECUTING ROWS ADDED on {len(doubled)} capture(s), {sum(doubled)} row(s): an existing instant"
              " now schedules more than once (S2).")
    removed = [d.get("count") or 0 for d in decisions if d["reason"] == "executingRowsRemoved"]
    if removed:
        print(f"  executing rows removed (withdrawals): {sum(removed)} on {len(removed)} capture(s)")
    return 0


def latency_table(name, pairs):
    rows = defaultdict(lambda: {"ms": [], "prompt": [], "response": [], "n": 0})
    for atoms, job in pairs:
        if job.get("latencyMilliseconds") is None:
            continue
        cell = rows[bucket(atoms)]
        cell["n"] += 1
        cell["ms"].append(job["latencyMilliseconds"])
        if job.get("promptTokens") is not None:
            cell["prompt"].append(job["promptTokens"])
        if job.get("responseTokens") is not None:
            cell["response"].append(job["responseTokens"])
    if not rows:
        return
    print(f"  {name} latency and prompt tokens by atoms bucket")
    print(f"    {'atoms':<10}{'n':>5}{'p50 ms':>9}{'p90 ms':>9}{'max ms':>9}{'>2000':>7}{'tok p50':>9}{'tok max':>9}"
          f"{'out p50':>9}")
    for bucket_name in bucket_order():
        cell = rows.get(bucket_name)
        if not cell:
            continue
        print(f"    {bucket_name:<10}{cell['n']:>5}{fmt(percentile(cell['ms'], .5)):>9}"
              f"{fmt(percentile(cell['ms'], .9)):>9}{fmt(max(cell['ms'])):>9}"
              f"{sum(ms > 2000 for ms in cell['ms']):>7}"
              f"{fmt(percentile(cell['prompt'], .5)):>9}{fmt(max(cell['prompt']) if cell['prompt'] else None):>9}"
              f"{fmt(percentile(cell['response'], .5)):>9}")


# ------------------------------------------------------------------- router

FEATURES = [
    ("atoms>=40", lambda f: f["atoms"] >= 40),
    ("atoms>=25", lambda f: f["atoms"] >= 25),
    ("clauses>=3", lambda f: f["clauses"] >= 3),
    ("clauseItemMismatch", lambda f: f["clauseItemMismatch"] > 0),
    ("rulesItems>=3", lambda f: f["rulesItems"] >= 3),
    ("rulesNeedsReview", lambda f: f["rulesNeedsReview"] > 0),
    ("rulesUnresolvedState", lambda f: f["rulesUnresolvedState"] > 0),
    ("mixedTodayMemory", lambda f: f["rulesActionable"] > 0 and f["rulesMemory"] > 0),
    ("consolidated", lambda f: f["consolidated"]),
    ("correctionRepaired", lambda f: f["correctionRepaired"]),
    ("unresolvedNegativeRepair", lambda f: f["unresolvedNegativeRepair"]),
    ("inCaptureWithdrawal", lambda f: f["inCaptureWithdrawal"]),
    ("reportingClauses", lambda f: f["reportingClauses"] > 0),
    ("communicatingClauses", lambda f: f["communicatingClauses"] > 0),
    ("conditionalClauses", lambda f: f["conditionalClauses"] > 0),
    ("timedClauses>=2", lambda f: f["timedClauses"] >= 2),
    ("personMentions", lambda f: f["personMentions"] > 0),
    ("disfluency", lambda f: f["disfluencyCharactersRemoved"] > 0),
    ("quotationMarks", lambda f: f["quotationMarks"]),
    ("thirdPersonReferences", lambda f: f["thirdPersonReferences"] > 0),
    ("routeDisagreements", lambda f: f["routeDisagreements"] > 0),
    ("confidentOnComplex", confident_on_complex),
]


def router(args):
    records = read_jsonl(args[0])
    labels = load_five_column(args[args.index("--labels") + 1])
    report = parse_report(args[args.index("--report") + 1])
    by_id = {r.get("id"): r for r in records if r.get("id")}
    rows = []
    missing = 0
    for label in labels:
        record = by_id.get(label["id"])
        got = report.get(label["utterance"])
        if record is None or got is None:
            missing += 1
            continue
        verdict = coarse_verdict(label, got)
        rows.append((label, record, failed(verdict)))
    if not rows:
        print("no labelled capture found in both the records and the report")
        return 1
    base = sum(f for _, _, f in rows) / len(rows)
    print(f"ROUTER SIGNALS — {len(rows)} labelled captures, rules failing {sum(f for _, _, f in rows)}"
          f" (base rate {100 * base:.1f}%)")
    if missing:
        print(f"  {missing} labelled capture(s) missing from the records or the report, not scored")
    print("  CORRECTNESS here is the held-out scorer's coarse reading (destination, range-aware")
    print("  count, unsafe on Ambiguous). It is a development measure: a feature chosen on")
    print("  these rows must be re-measured on the fresh slice before it routes anything.")
    print("=" * 78)
    print(f"  {'feature':<26}{'fires':>7}{'coverage':>10}{'fail|fires':>12}{'lift':>7}{'catches':>9}{'of fails':>10}")
    fails = sum(f for _, _, f in rows)
    for name, predicate in FEATURES:
        fired = [(l, r, f) for l, r, f in rows if predicate(r["features"])]
        if not fired:
            print(f"  {name:<26}{0:>7}")
            continue
        rate = sum(f for _, _, f in fired) / len(fired)
        lift = rate / base if base else float("nan")
        caught = sum(f for _, _, f in fired)
        print(f"  {name:<26}{len(fired):>7}{100 * len(fired) / len(rows):>9.1f}%{100 * rate:>11.1f}%"
              f"{lift:>7.2f}{caught:>9}{100 * caught / max(fails, 1):>9.1f}%")
    print("-" * 78)
    eligible = [(l, r, f) for l, r, f in rows if r["policy"] == "eligible"]
    caught = sum(f for _, _, f in eligible)
    print(f"  production policy as a router: asks the model about {len(eligible)} captures,"
          f" {caught} of the {fails} rules failures")
    silent = [(l, r) for l, r, f in rows if f and r["policy"] != "eligible"]
    print(f"  rules failures production never asks about: {len(silent)}")
    for reason, n in Counter(r["policy"] for _, r in silent).most_common():
        print(f"    {reason:<32}{n:>5}")
    families = Counter(l["family"] for l, _ in silent)
    if families:
        print("  by family: " + ", ".join(f"{k} {v}" for k, v in families.most_common()))
    return 0


# -------------------------------------------------------------------- whole

CATEGORIES = OrderedDict([
    ("A", "short simple captures"),
    ("B", "clear multi-task long captures"),
    ("C", "natural rambling long captures"),
    ("D", "coherent long single thoughts"),
    ("E", "mixed task + memory captures"),
    ("F", "corrections / withdrawals"),
    ("G", "quoted / reported speech"),
    ("H", "entity-context ambiguity"),
    ("I", "conditions and location scope"),
    ("J", "beginning / middle / end retention"),
])

MEASURES = ["lost", "invented", "split", "merge", "correction", "scope", "ownership",
            "entity", "temporal", "routing", "unsafe", "review"]

STOP = {"the", "a", "an", "and", "to", "of", "for", "my", "i", "me", "it", "that", "um", "uh",
        "so", "like", "just", "then", "also", "oh", "okay", "yeah", "well"}


def words(text):
    return {w for w in re.sub(r"[^a-z0-9' ]+", " ", text.lower().replace("’", "'")).split() if w not in STOP}


def covers(row_quote, expected_words):
    """How much of an expected thought's own words a row carries."""
    want = words(expected_words)
    if not want:
        return 0.0
    return len(want & words(row_quote)) / len(want)


def match_rows(thoughts, rows, threshold=0.6):
    """Greedy one-to-one matching by coverage, best pairs first. Returns
    {thought index: row index}."""
    pairs = sorted(((covers(r["quote"] + " " + r["title"], t["words"]), ti, ri)
                    for ti, t in enumerate(thoughts) for ri, r in enumerate(rows)), reverse=True)
    matched, used = {}, set()
    for score, ti, ri in pairs:
        if score < threshold or ti in matched or ri in used:
            continue
        matched[ti] = ri
        used.add(ri)
    return matched


def executes(row):
    return row["remind"] or row["due"] or row["location"] or row["recurs"]


def judge_whole(label, got):
    """One capture against the fresh-slice schema (LABELS.md). Returns the set
    of failed measures; an empty set is WHOLE CAPTURE CORRECT."""
    problems = set()
    if got is None:
        return {"lost"}
    rows = got["rows"]
    thoughts = label.get("thoughts", [])
    matched = match_rows(thoughts, rows)
    for ti, thought in enumerate(thoughts):
        if ti not in matched:
            problems.add("lost")
            continue
        row = rows[matched[ti]]
        if (row["route"] == "Today") != (thought["destination"] == "Today"):
            problems.add("routing")
        timed = row["remind"] or row["due"]
        if bool(thought.get("timed", False)) != timed:
            problems.add("temporal")
        if bool(thought.get("located", False)) != row["location"]:
            problems.add("scope")
        if "person" in thought:
            want = (thought["person"] or "").strip().lower()
            have = (row["person"] or "").strip().lower()
            if want != have:
                problems.add("entity")
        if row["review"] and not thought.get("review_ok", False):
            problems.add("review")
    extra = [ri for ri in range(len(rows)) if ri not in matched.values()]
    for ri in extra:
        if not any(covers(rows[ri]["quote"], ignorable) >= 0.6 for ignorable in label.get("ignorable", [])):
            problems.add("invented")
    if len(rows) > len(thoughts) and "invented" in problems:
        problems.add("split")
    if len(rows) < len(thoughts) and "lost" in problems:
        problems.add("merge")
    want_ops = sorted(o["kind"] for o in label.get("operations", []))
    if sorted(got["operations"]) != want_ops:
        problems.add("correction" if label.get("category") == "F" else "invented")
    for guarded in label.get("must_not_execute", []):
        for row in rows:
            if covers(row["quote"], guarded["words"]) >= 0.6 and executes(row):
                problems.add("unsafe")
                problems.add({"correction": "correction", "withdrawal": "correction", "quoted": "ownership",
                              "reported": "ownership", "condition": "scope", "negated": "unsafe"}
                             .get(guarded.get("why"), "unsafe"))
    if label.get("ambiguous") and (got["operations"] or got["remind"] or got["due"]):
        problems.add("unsafe")
    return problems


def whole(args):
    labels = read_jsonl(args[0])
    report = parse_report(args[args.index("--report") + 1])
    runs = read_jsonl(args[args.index("--runs") + 1]) if "--runs" in args else []
    show_ids = "--ids" in args
    results = []
    for label in labels:
        problems = judge_whole(label, report.get(label["utterance"]))
        atoms = len(label["utterance"].split())
        results.append((label, problems, atoms))
    print(f"WHOLE CAPTURE — {len(results)} labelled captures, report {args[args.index('--report') + 1]}")
    print("=" * 100)
    header = f"  {'category':<44}{'n':>4}{'whole':>11}" + "".join(f"{m[:6]:>7}" for m in MEASURES)
    print(header)
    print("-" * 100)

    def line(name, group):
        ok = sum(1 for _, p, _ in group if not p)
        counts = Counter(m for _, p, _ in group for m in p)
        return (f"  {name[:44]:<44}{len(group):>4}{f'{ok}/{len(group)}':>11}"
                + "".join(f"{counts[m]:>7}" for m in MEASURES))

    for code, name in CATEGORIES.items():
        group = [r for r in results if r[0].get("category") == code]
        if group:
            print(line(f"{code} {name}", group))
    uncategorised = [r for r in results if r[0].get("category") not in CATEGORIES]
    if uncategorised:
        print(line("(no A-J category)", uncategorised))
    print("-" * 100)
    families = sorted({r[0].get("family", "untagged") for r in results})
    for family in families:
        print(line(f"family {family}", [r for r in results if r[0].get("family", "untagged") == family]))
    print("-" * 100)
    for name in bucket_order():
        group = [r for r in results if bucket(r[2]) == name]
        if group:
            print(line(f"atoms {name}", group))
    print("=" * 100)
    print("  Columns after `whole` count captures failing that measure; one capture can fail several.")
    print("  There is deliberately no overall row: read each category on its own denominator.")
    if runs:
        by_utterance = {r["utterance"]: r for r in runs}
        joined = [by_utterance.get(r[0]["utterance"]) for r in results]
        present = [r for r in joined if r]
        invoked = sum(1 for r in present if r.get("map") and r["map"]["unitsJob"]["outcome"] != "skipped")
        contributed = sum(1 for r in present if r.get("mapChangedOutput"))
        fallback = sum(1 for r in present if not r.get("mapChangedOutput"))
        print(f"  map arm over {len(present)} joined runs: invoked {invoked}, output changed {contributed},"
              f" rules reading kept {fallback}")
        production_invoked = sum(1 for r in present if r["production"].get("latencyMilliseconds") is not None)
        production_accepted = sum(1 for r in present if r["production"]["outcome"] == "accepted")
        print(f"  production route over the same runs: invoked {production_invoked}, accepted {production_accepted}")
    if show_ids:
        print()
        for label, problems, _ in results:
            if problems:
                print(f"  {label['id']}  {label.get('category', '?')}  {' '.join(sorted(problems))}")
    return 0


# ------------------------------------------------------------------- select

def complex_shape(features):
    """A capture a router would call complex on structure alone, whatever the
    rules flagged: the shape of `confident_on_complex` without its confidence
    half, widened by three or more rows. Used only to draw controls."""
    return features["clauses"] >= 3 or features["atoms"] >= 40 or features["rulesItems"] >= 3


def twin_of(capture_id):
    """The rambling set's pairing convention: RBnnC is the clean twin of
    RBnnR. Any other id has no twin."""
    match = re.fullmatch(r"(.*\d)([CR])", capture_id)
    if not match:
        return None
    return match.group(1) + ("R" if match.group(2) == "C" else "C")


def sha256(path):
    import hashlib
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def select(args):
    census_path = args[0]
    labels_path = args[args.index("--labels") + 1]
    report_path = args[args.index("--report") + 1]
    out_path = args[args.index("--out") + 1]
    groups_path = args[args.index("--groups") + 1]
    records = {r.get("id"): r for r in read_jsonl(census_path) if r.get("id")}
    labels = load_five_column(labels_path)
    report = parse_report(report_path)
    rows = []
    for label in labels:
        record = records.get(label["id"])
        got = report.get(label["utterance"])
        if record is None or got is None:
            continue
        rows.append((label, record, failed(coarse_verdict(label, got))))
    if not rows:
        print("no labelled capture found in both the census and the report")
        return 1

    groups = OrderedDict()

    def add(label, group):
        groups.setdefault(label["id"], {"label": label, "groups": []})["groups"].append(group)

    for label, record, fail in rows:
        # Hidden: production never asks the model, by the policy and, for an
        # operation capture, by the gate its not-found re-extraction meets.
        reaches = record["policy"] == "eligible" or record.get("fallbackPolicy") == "eligible"
        if fail and not reaches:
            add(label, "hidden")
    for label, record, fail in rows:
        if confident_on_complex(record["features"]):
            add(label, "confidentOnComplex")

    by_id = {label["id"]: (label, record, fail) for label, record, fail in rows}
    failing = [i for i in groups if by_id[i][2]]
    already_correct = [i for i in groups if not by_id[i][2]]
    wanted = max(0, len(failing) - len(already_correct))
    pool = {label["id"] for label, record, fail in rows
            if not fail and complex_shape(record["features"]) and label["id"] not in groups}
    controls = []
    for capture_id in sorted(failing):
        if len(controls) >= wanted:
            break
        twin = twin_of(capture_id)
        if twin in pool:
            controls.append((twin, capture_id, "twin"))
            pool.discard(twin)
    matched = {m for _, m, _ in controls}
    for capture_id in sorted(failing):
        if len(controls) >= wanted or not pool:
            break
        if capture_id in matched:
            continue
        atoms = by_id[capture_id][1]["features"]["atoms"]
        nearest = min(pool, key=lambda i: (abs(by_id[i][1]["features"]["atoms"] - atoms), i))
        controls.append((nearest, capture_id, "nearest"))
        pool.discard(nearest)
    for control, _, _ in controls:
        add(by_id[control][0], "control")

    with open(out_path, "w", encoding="utf-8") as handle:
        for capture_id, entry in groups.items():
            handle.write(f"{capture_id}\t{entry['label']['utterance']}\n")
    Path(groups_path).write_text(json.dumps({
        "sources": {"census": sha256(census_path), "labels": sha256(labels_path), "report": sha256(report_path)},
        "groups": {capture_id: entry["groups"] for capture_id, entry in groups.items()},
        "controls": [{"control": c, "matches": m, "how": h} for c, m, h in controls],
    }, indent=1, sort_keys=True) + "\n", encoding="utf-8")

    print(f"DIAGNOSTIC SELECTION — {len(groups)} captures from {len(rows)} labelled")
    print("=" * 78)
    for group in ("hidden", "confidentOnComplex", "control"):
        ids = [i for i, e in groups.items() if group in e["groups"]]
        print(f"  {group:<20}{len(ids):>4}  {' '.join(ids)}")
    both = [i for i, e in groups.items() if len(e["groups"]) > 1]
    print(f"  {'in two groups':<20}{len(both):>4}  {' '.join(both)}")
    hidden = [by_id[i][1] for i, e in groups.items() if "hidden" in e["groups"]]
    print("  hidden by: " + ", ".join(f"{k} {v}" for k, v in Counter(r["policy"] for r in hidden).most_common()))
    print(f"  controls: {sum(h == 'twin' for _, _, h in controls)} twin, "
          f"{sum(h == 'nearest' for _, _, h in controls)} nearest in atoms, wanted {wanted}")
    if len(controls) < wanted:
        print(f"  SHORT by {wanted - len(controls)}: not enough rules-correct complex captures left to match")
    print(f"  wrote {out_path} and {groups_path}")
    print("  Selection used the rules reading and the labels only; no model output chose a row.")
    return 0


# --------------------------------------------------------------- diagnostic

SKIPS_UNAVAILABLE = {"modelUnavailable", "osTooOld", "frameworkMissing", "localeUnsupported"}


def diagnostic(args):
    def arg(flag):
        return args[args.index(flag) + 1]

    meta = json.loads(Path(arg("--groups")).read_text(encoding="utf-8"))
    labels = {l["id"]: l for l in load_five_column(arg("--labels"))}
    reports = {name: parse_report(arg(f"--{name}")) for name in ("rules", "map", "asked")}
    map_records = {r["id"]: r for r in read_jsonl(arg("--map-records")) if r.get("id")}
    asked_records = {r["id"]: r for r in read_jsonl(arg("--asked-records")) if r.get("id")}

    captures = []
    for capture_id, groups in meta["groups"].items():
        label = labels.get(capture_id)
        record = map_records.get(capture_id)
        asked = asked_records.get(capture_id)
        if label is None or record is None or asked is None:
            print(f"  {capture_id}: missing from the labels or the run; not scored")
            continue
        verdicts = {arm: coarse_verdict(label, reports[arm].get(label["utterance"])) for arm in reports}
        captures.append({"id": capture_id, "groups": groups, "record": record, "asked": asked["production"],
                         "verdicts": verdicts, "fail": {arm: failed(v) for arm, v in verdicts.items()},
                         "unscored": [arm for arm, v in verdicts.items() if v["produced"] is None]})

    print(f"DIAGNOSTIC RUN — {len(captures)} captures")
    commits = Counter(c["record"]["settings"]["commit"] for c in captures)
    print("  run commit(s): " + ", ".join(f"{k} x{v}" for k, v in commits.items())
          + ("   SHADOW OFF: the asked arm has no answers" if not all(c["record"]["settings"]["shadow"] for c in captures) else ""))
    missing = [c["id"] for c in captures if c["unscored"]]
    if missing:
        print(f"  NOT IN A REPORT, so not scored on that arm: {' '.join(missing)}")
    print("  DEVELOPMENT EVIDENCE on rows chosen from a development set. Not product accuracy,")
    print("  and not a router: a router is chosen on the fresh slice.")
    print("=" * 78)

    def section(title, group):
        n = len(group)
        print(f"\n{title} — {n} captures")
        print("-" * 78)
        if not n:
            return
        records = [c["record"] for c in group]
        maps = [r["map"] for r in records if r.get("map")]
        unavailable = Counter()
        for c in group:
            skip = c["asked"].get("availability")
            if skip:
                unavailable[f"production:{skip}"] += 1
            for job in ("unitsJob", "relationsJob", "entitiesJob"):
                j = (c["record"].get("map") or {}).get(job) or {}
                if j.get("skip") in SKIPS_UNAVAILABLE:
                    unavailable[f"{job[:-3]}:{j['skip']}"] += 1
        print(f"  model available        {n - len({c['id'] for c in group if c['asked'].get('availability')})}/{n}"
              + (f"   unavailable: {', '.join(f'{k} {v}' for k, v in unavailable.items())}" if unavailable else ""))
        for job in ("unitsJob", "relationsJob", "entitiesJob"):
            jobs = [m[job] for m in maps]
            outcomes = Counter(j["outcome"] for j in jobs)
            refusals = Counter(j["refusal"] for j in jobs if j.get("refusal"))
            skips = Counter(j["skip"] for j in jobs if j.get("skip"))
            line = f"  {job[:-3] + ' job':<22} " + ", ".join(f"{k} {v}" for k, v in outcomes.most_common())
            if refusals:
                line += "   refused: " + ", ".join(f"{k} {v}" for k, v in refusals.most_common())
            if skips:
                line += "   skipped: " + ", ".join(f"{k} {v}" for k, v in skips.most_common())
            print(line)

        decisions = [d for r in records for d in r.get("decisions", [])]
        effects = Counter(d["effect"] for d in decisions if d["effect"] not in ("none", "keptRules"))
        changed = sum(1 for r in records if r.get("mapChangedOutput"))
        print(f"  arbiter contribution   output changed on {changed}/{n}"
              + (f"; effects: {', '.join(f'{k} {v}' for k, v in effects.most_common())}" if effects else "; no effect"))
        proposals = Counter((d["topic"], d["reason"]) for d in decisions if d["topic"] in ("split", "merge", "relation", "entity"))
        if proposals:
            print("  arbiter reasons        " + ", ".join(f"{t}/{r} {v}" for (t, r), v in proposals.most_common()))

        for arm, name in (("map", "semantic map"), ("asked", "production model, as if asked")):
            was_wrong = [c for c in group if c["fail"]["rules"]]
            was_right = [c for c in group if not c["fail"]["rules"]]
            improved = [c["id"] for c in was_wrong if not c["fail"][arm]]
            damaged = [c["id"] for c in was_right if c["fail"][arm]]
            print(f"  {name:<34} improved {len(improved)}/{len(was_wrong)} previously wrong"
                  f"   damaged {len(damaged)}/{len(was_right)} previously correct")
            if improved:
                print(f"    improved: {' '.join(improved)}")
            if damaged:
                print(f"    DAMAGED:  {' '.join(damaged)}")
            unsafe = sum(1 for c in group if c["verdicts"][arm]["unsafe"])
            rules_unsafe = sum(1 for c in group if c["verdicts"]["rules"]["unsafe"])
            if unsafe or rules_unsafe:
                print(f"    unsafe on Ambiguous: rules {rules_unsafe}, {arm} {unsafe}")

        job_refusals = sum(1 for d in decisions if d["reason"] == "jobRefused")
        cut_conflicts = Counter(d["reason"] for d in decisions
                                if d["topic"] == "split" and d["verdict"] == "modelConflictsSafety")
        validation = Counter(c["asked"]["validation"] for c in group if c["asked"].get("validation"))
        guard = sum(1 for c in group if c["asked"].get("unbudgeted") == "guardRejected")
        print(f"  grounding rejection    map jobs refused {job_refusals}"
              + (f"; cuts refused for safety: {', '.join(f'{k} {v}' for k, v in cut_conflicts.items())}" if cut_conflicts else "")
              + f"; production validation {sum(validation.values())}"
              + (f" ({', '.join(f'{k} {v}' for k, v in validation.most_common())})" if validation else "")
              + f", guard {guard}")
        added = sum(d.get("count") or 0 for d in decisions if d["reason"] == "executingRowsAdded")
        removed = sum(d.get("count") or 0 for d in decisions if d["reason"] == "executingRowsRemoved")
        broke = sum(1 for d in decisions if d["reason"] == "executionOutsideRulesReading")
        print(f"  execution              rows added {added} (S2, must be 0), rows removed {removed},"
              f" structural guarantee fired {broke}")

        totals = []
        for m in maps:
            parts = [m[j].get("latencyMilliseconds") for j in ("unitsJob", "relationsJob", "entitiesJob")]
            if any(p is not None for p in parts):
                totals.append(sum(p or 0 for p in parts))
        production_ms = [c["asked"]["latencyMilliseconds"] for c in group if c["asked"].get("latencyMilliseconds") is not None]
        print(f"  latency ms             map (three jobs) p50 {fmt(percentile(totals, .5))} p90 {fmt(percentile(totals, .9))}"
              f" max {fmt(max(totals) if totals else None)};   production p50 {fmt(percentile(production_ms, .5))}"
              f" p90 {fmt(percentile(production_ms, .9))} over 2 s {sum(ms > 2000 for ms in production_ms)}")
        for job in ("unitsJob", "relationsJob", "entitiesJob"):
            ms = [m[job]["latencyMilliseconds"] for m in maps if m[job].get("latencyMilliseconds") is not None]
            out = [m[job]["responseTokens"] for m in maps if m[job].get("responseTokens") is not None]
            if ms:
                print(f"    {job[:-3]:<10} p50 {fmt(percentile(ms, .5))} max {max(ms)}"
                      f"   output tokens p50 {fmt(percentile(out, .5))}")

        kept = [c for c in group if not c["record"].get("mapChangedOutput")]
        why = Counter()
        for c in kept:
            reasons = {d["reason"] for d in c["record"].get("decisions", [])}
            if "noMap" in reasons:
                why["no map"] += 1
            elif "operationOwnedByRules" in reasons:
                why["operation, rules own it"] += 1
            elif "executionOutsideRulesReading" in reasons:
                why["structural guarantee"] += 1
            elif "rowsNotLocatable" in reasons:
                why["rows not locatable"] += 1
            elif "unitsNotAccepted" in reasons and not any(r in reasons for r in ("messageContentExecutes", "withdrawnRowStillExecutes")):
                why["units not accepted"] += 1
            elif "boundariesAgree" in reasons:
                why["model agreed with the rules"] += 1
            else:
                why["proposals refused or inert"] += 1
        print(f"  final fallback         map kept the rules reading on {len(kept)}/{n}"
              + (f": {', '.join(f'{k} {v}' for k, v in why.most_common())}" if why else ""))
        outcomes = Counter(c["asked"].get("outcome") for c in group)
        print("  production as asked    " + ", ".join(f"{k} {v}" for k, v in outcomes.most_common()))

    for group in ("hidden", "confidentOnComplex", "control"):
        section(group.upper(), [c for c in captures if group in c["groups"]])
    section("ALL SELECTED (each capture once)", captures)

    print("\nPER CAPTURE (ids only; F = the coarse scorer fails it; measures failed in brackets)")
    for c in captures:
        def mark(arm):
            v = c["verdicts"][arm]
            bad = [k for k in ("produced", "destination", "count") if v[k] is False] + (["unsafe"] if v["unsafe"] else [])
            return ("F[" + ",".join(bad) + "]") if bad else "ok"
        print(f"  {c['id']:<10}{'+'.join(c['groups']):<32} rules {mark('rules'):<22} map {mark('map'):<22}"
              f" asked {mark('asked')}")
    return 0


# ----------------------------------------------------------------- selftest

def selftest(_args):
    failures = []

    def expect(condition, what):
        if not condition:
            failures.append(what)

    report_text = "\n".join([
        '── "call the vet and buy milk"',
        "   item 1 of 2:",
        "     row title:  Call the vet",
        "     route:      Today   type: task   category: general   priority: 1",
        "     due:        nil",
        "     remind:     nil   delivery: none",
        "     temporal:   none",
        "     state:      resolved",
        "     quote:      call the vet",
        "   item 2 of 2:",
        "     row title:  Buy milk",
        "     route:      Today   type: shopping   category: shopping   priority: 1",
        "     due:        nil",
        "     remind:     nil   delivery: none",
        "     temporal:   none",
        "     state:      resolved",
        "",
        '── "maybe cancel it idk"',
        "   operation:   cancel target=nil",
        "",
        '── "sam said the lease ends friday"',
        "   item 1 of 1:",
        "     row title:  Sam said the lease ends Friday",
        "     route:      Memory   type: note   category: people   priority: 1",
        "     due:        nil",
        "     remind:     Fri Aug 7 09:00   delivery: notification",
        "     temporal:   date",
        "     person:     Sam",
        "     needsReview: true",
        "     state:      resolved",
        "",
    ])
    labels_text = "\n".join([
        "id\tutterance\tfamily\texpected_destination\texpected_thoughts",
        "T1\tcall the vet and buy milk\tlist\tToday\t2",
        "T2\tmaybe cancel it idk\tvague\tAmbiguous\t0-1",
        "T3\tsam said the lease ends friday\treported\tMemory\t1",
        "T4\tnever produced\tlist\tToday\t1",
        "",
    ])
    with tempfile.TemporaryDirectory() as scratch:
        report_path = Path(scratch) / "fixture.report"
        report_path.write_text(report_text, encoding="utf-8")
        labels_path = Path(scratch) / "fixture.tsv"
        labels_path.write_text(labels_text, encoding="utf-8")
        seen = parse_report(report_path)
        expect(len(seen) == 3, "three capture blocks are parsed")
        expect(len(seen["call the vet and buy milk"]["rows"]) == 2, "two rows under the first header")
        expect(seen["call the vet and buy milk"]["rows"][0]["quote"] == "call the vet", "a quote line is read")
        quoted = Path(scratch) / "quoted.report"
        quoted.write_text('── "text Sam "running late" at six"\n   item 1 of 1:\n     row title:  Text Sam\n', encoding="utf-8")
        expect(list(parse_report(quoted)) == ['text Sam "running late" at six'],
               "a capture containing a double quote keeps its whole header")
        expect(seen["call the vet and buy milk"]["rows"][1]["quote"] == "Buy milk", "no quote line falls back to the title")
        third = seen["sam said the lease ends friday"]["rows"][0]
        expect(third["remind"] and third["person"] == "Sam" and third["review"], "remind, person and review are read")

        rows = load_five_column(labels_path)
        verdicts = {r["id"]: coarse_verdict(r, seen.get(r["utterance"])) for r in rows}
        expect(not failed(verdicts["T1"]), "a correct list capture passes")
        expect(verdicts["T2"]["unsafe"] is True and failed(verdicts["T2"]), "an operation on an Ambiguous capture is unsafe")
        expect(verdicts["T3"]["destination"] is True and not failed(verdicts["T3"]), "a Memory route passes")
        expect(verdicts["T4"]["produced"] is None, "an unseen capture is not scored")

        # Agreement with the scorer this re-implements. Its aggregates over the
        # fixture must equal ours; a divergence here means `router` would be
        # measuring a different notion of failure than every published figure.
        heldout = ROOT / "Tools" / "CorpusRunner" / "heldout" / "score.py"
        if heldout.exists():
            out = subprocess.run([sys.executable, str(heldout), str(labels_path), str(report_path)],
                                 capture_output=True, text=True, cwd=str(ROOT)).stdout
            dest = re.search(r"destination correct\s+(\d+)/(\d+)", out)
            count = re.search(r"thought count range-aware\s+(\d+)/(\d+)", out)
            unsafe = re.search(r"ACTED ON ANYWAY\s+(\d+)", out)
            ours_dest = [v["destination"] for v in verdicts.values() if v["destination"] is not None]
            ours_count = [v["count"] for v in verdicts.values() if v["count"] is not None]
            ours_unsafe = sum(1 for v in verdicts.values() if v["unsafe"])
            expect(dest and (int(dest.group(1)), int(dest.group(2))) == (sum(ours_dest), len(ours_dest)),
                   "destination agrees with heldout/score.py")
            expect(count and (int(count.group(1)), int(count.group(2))) == (sum(ours_count), len(ours_count)),
                   "range-aware count agrees with heldout/score.py")
            expect(unsafe and int(unsafe.group(1)) == ours_unsafe, "unsafe agrees with heldout/score.py")
        else:
            failures.append("heldout/score.py not found; the agreement check could not run")

        # Whole-capture judging.
        label = {"id": "W1", "category": "B", "utterance": "call the vet and buy milk",
                 "thoughts": [{"words": "call the vet", "destination": "Today"},
                              {"words": "buy milk", "destination": "Today"}]}
        expect(judge_whole(label, seen[label["utterance"]]) == set(), "a correct capture is whole-correct")
        lost = dict(label, thoughts=label["thoughts"] + [{"words": "email the landlord", "destination": "Today"}])
        expect("lost" in judge_whole(lost, seen[label["utterance"]]), "a missing intention is lost")
        reported = {"id": "W2", "category": "G", "utterance": "sam said the lease ends friday",
                    "thoughts": [{"words": "sam said the lease ends friday", "destination": "Memory",
                                  "person": "Sam", "review_ok": True}],
                    "must_not_execute": [{"words": "the lease ends friday", "why": "reported"}]}
        problems = judge_whole(reported, seen[reported["utterance"]])
        expect({"unsafe", "ownership", "temporal"} <= problems, "a reminder on reported speech is unsafe ownership")
        expect("review" not in problems and "entity" not in problems, "allowed review and the right person pass")

        # Content-free output: no mode may print capture text.
        records = Path(scratch) / "census.jsonl"
        feature = {k: 0 for k in ["characters", "atoms", "sentenceMarks", "rulesItems", "rulesOperations",
                                  "rulesNeedsReview", "rulesUnresolvedState", "rulesActionable", "rulesMemory",
                                  "rulesTimed", "rulesLocated", "rulesWithPerson", "clauses",
                                  "clauseItemMismatch", "reportingClauses", "communicatingClauses",
                                  "conditionalClauses", "timedClauses", "personMentions",
                                  "disfluencyCharactersRemoved", "thirdPersonReferences", "routeDisagreements"]}
        feature.update(consolidated=False, correctionRepaired=False, unresolvedNegativeRepair=False,
                       inCaptureWithdrawal=False, quotationMarks=False)
        census_rows = [
            dict(id="T1", commit="x", features=dict(feature, atoms=6, clauses=2, rulesItems=2),
                 policy="noRowNeedsReview", shouldRefine=False, policyDrift=False, rulesDigest="0"),
            dict(id="T3", commit="x", features=dict(feature, atoms=6, clauses=3, rulesItems=1, rulesNeedsReview=1),
                 policy="eligible", shouldRefine=True, policyDrift=False, rulesDigest="0"),
        ]
        records.write_text("\n".join(json.dumps(r) for r in census_rows) + "\n", encoding="utf-8")
        printed = subprocess.run([sys.executable, __file__, "router", str(records), "--labels", str(labels_path),
                                  "--report", str(report_path)], capture_output=True, text=True).stdout
        expect("ROUTER SIGNALS — 2 labelled captures" in printed, "router joins records, labels and report by id")
        for utterance in ("vet", "milk", "lease", "cancel it"):
            expect(utterance not in printed, "router prints no capture text")
        printed = subprocess.run([sys.executable, __file__, "census", str(records), "--labels", str(labels_path)],
                                 capture_output=True, text=True).stdout
        expect("noRowNeedsReview" in printed and "vet" not in printed, "census prints reasons and no text")

        # Selection: T2 fails and production never asks (an operation with no
        # re-extraction); T1 is the rules-correct complex control, nearest in
        # atoms. Nothing chose a row but the rules reading and the labels.
        census_rows.append(dict(id="T2", commit="x", features=dict(feature, atoms=4, clauses=1),
                                policy="operationPresent", shouldRefine=False, policyDrift=False, rulesDigest="0"))
        census_rows[0]["features"]["rulesItems"] = 3
        records.write_text("\n".join(json.dumps(r) for r in census_rows) + "\n", encoding="utf-8")
        diag_in, groups_path = Path(scratch) / "diag.in", Path(scratch) / "groups.json"
        printed = subprocess.run([sys.executable, __file__, "select", str(records), "--labels", str(labels_path),
                                  "--report", str(report_path), "--out", str(diag_in), "--groups", str(groups_path)],
                                 capture_output=True, text=True).stdout
        groups = json.loads(groups_path.read_text(encoding="utf-8"))["groups"]
        expect(groups == {"T2": ["hidden"], "T1": ["control"]}, f"select picks the hidden failure and one control: {groups}")
        expect(diag_in.read_text(encoding="utf-8").splitlines()[0] == "T2\tmaybe cancel it idk",
               "select writes id<TAB>capture for the run")
        for utterance in ("vet", "milk", "lease", "cancel it"):
            expect(utterance not in printed, "select prints no capture text")
        expect(twin_of("RB07R") == "RB07C" and twin_of("RB07C") == "RB07R" and twin_of("T2") is None,
               "twins are the rambling set's C/R pairs only")

        # The diagnostic scorer over a two-capture run: the map arm turns the
        # hidden failure into no operation (improved on unsafe) and damages the
        # control by losing a row.
        def job(outcome, ms, refusal=None):
            return dict(outcome=outcome, latencyMilliseconds=ms, responseTokens=12, refusal=refusal)
        settings = dict(commit="x", shadow=True)
        run_records = [
            dict(id="T2", utterance="maybe cancel it idk", settings=settings, mapChangedOutput=True,
                 map=dict(unitsJob=job("accepted", 900), relationsJob=job("refused", 700, "selfRelation"),
                          entitiesJob=job("accepted", 600)),
                 decisions=[dict(topic="job", verdict="modelViolatesGrounding", reason="jobRefused", effect="none"),
                            dict(topic="relation", verdict="unresolved", reason="withdrawnRowStillExecutes",
                                 effect="withdrewExecution")],
                 production=dict(outcome="notInvoked")),
            dict(id="T1", utterance="call the vet and buy milk", settings=settings, mapChangedOutput=True,
                 map=dict(unitsJob=job("accepted", 800), relationsJob=job("accepted", 500),
                          entitiesJob=job("accepted", 400)),
                 decisions=[dict(topic="merge", verdict="modelAddsStructure", reason="mergedMemory", effect="mergedRows")],
                 production=dict(outcome="accepted", latencyMilliseconds=2500, validation="ungroundedQuote",
                                 unbudgeted="validationRejected")),
        ]
        map_records = Path(scratch) / "map.jsonl"
        map_records.write_text("\n".join(json.dumps(r) for r in run_records) + "\n", encoding="utf-8")
        map_report = Path(scratch) / "map.report"
        map_report.write_text("\n".join([
            '── "call the vet and buy milk"', "   item 1 of 1:", "     row title:  Call the vet and buy milk",
            "     route:      Today   type: task   category: general   priority: 1",
            "     due:        nil", "     remind:     nil   delivery: none", "",
            '── "maybe cancel it idk"', "   item 1 of 1:", "     row title:  Maybe cancel it",
            "     route:      Memory   type: note   category: general   priority: 1",
            "     due:        nil", "     remind:     nil   delivery: none", "",
        ]), encoding="utf-8")
        printed = subprocess.run([sys.executable, __file__, "diagnostic", "--groups", str(groups_path),
                                  "--labels", str(labels_path), "--rules", str(report_path), "--map", str(map_report),
                                  "--map-records", str(map_records), "--asked", str(report_path),
                                  "--asked-records", str(map_records)], capture_output=True, text=True)
        out = printed.stdout
        expect(printed.returncode == 0, f"diagnostic runs: {printed.stderr[-300:]}")
        expect("semantic map                       improved 1/1 previously wrong   damaged 0/0" in out,
               "the hidden failure the map fixed is counted as improved")
        expect("DAMAGED:  T1" in out, "a control the map breaks is named as damaged")
        expect("refused: selfRelation 1" in out and "map jobs refused 1" in out, "a refused job is a grounding rejection")
        expect("production validation 1 (ungroundedQuote 1)" in out, "production's validation rejection is reported")
        expect("over 2 s 1" in out, "production latency past the budget is counted")
        for utterance in ("vet", "milk", "lease", "cancel it"):
            expect(utterance not in out, "diagnostic prints no capture text")

    expect(confident_on_complex(dict(rulesNeedsReview=0, rulesUnresolvedState=0, clauses=3, atoms=5)),
           "three clauses with nothing flagged is confident-on-complex")
    expect(not confident_on_complex(dict(rulesNeedsReview=1, rulesUnresolvedState=0, clauses=3, atoms=50)),
           "a flagged row is not confident")
    expect(bucket(10) == "1-10" and bucket(11) == "11-25" and bucket(101) == "101+", "buckets are inclusive")

    if failures:
        for failure in failures:
            print(f"score.py selftest FAILED: {failure}")
        return 1
    print("score.py selftest ok")
    return 0


COMMANDS = {"census": census, "trace": trace, "router": router, "whole": whole, "select": select,
            "diagnostic": diagnostic, "selftest": selftest}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        sys.exit(2)
    sys.exit(COMMANDS[sys.argv[1]](sys.argv[2:]))
