#!/usr/bin/env python3
"""Whole-capture correctness for a sealed, externally authored evaluation set.

Every other scorer in this directory reports one measure at a time: routing
over here, count over there, loss and invention somewhere else. A capture can
pass each of those tables separately and still be wrong as a whole, because
no table asks the one question a person asks of a capture: **did everything
it produced come out right?** This does, and only that, per family.

A capture is CORRECT when its output matches the contract on every field that
is not cosmetic -- the item count, each item's destination, type, timing,
delivery, recurrence, person, place, list and title constraints, and every
operation with its target. Severity follows `CorpusSeverity.forField` in
`SpeakItTests/SemanticCorpus.swift` so a finding here reads the same as one
from the corpus gate:

  critical     count, operation, operation_target
  behavioral   destination, due, remind, delivery, recurs, place
  metadata     type, person, list, title_has, title_lacks
  cosmetic     title hygiene (reported, never fails a capture)

Any critical, behavioral or metadata mismatch fails the capture. Severity only
decides how a failure is reported; it never rescues one.

THE CONTRACT (one JSON object per line)

  id          unique string
  family      exactly one name from FAMILIES below
  tags        optional list of further phenomena (reported, overlapping)
  input       "asr" (transcribed speech, as dictation produces it) or "typed"
  utterance   the text the pipeline is given
  items       expected rows, each with EVERY field in REQUIRED_ITEM_FIELDS
  operations  expected operations, default [] -- {"operation", "target"?}
  alternatives  optional list of {"items", "operations"}: other readings a
              careful author accepts; the capture passes if any one passes
  note        optional, printed beside a failure at release review

Item fields. `null` asserts absence; a field left out of a contract is refused
by `validate`, because an unasserted field is a field that passes silently.

  destination "Today" | "Memory" | "NeedsReview"
  type        an ItemType raw value, or a list of acceptable ones
  due, remind null | "any" | "YYYY-MM-DD" (day only) | "YYYY-MM-DD *" (any time
              that day) | "YYYY-MM-DDTHH:MM" (exact, America/Toronto)
  delivery    "none" | "notification" | "alarm"
  person      null | "Name" | ["Name", "Other acceptable name"]
  place       null | {"event": "arrive"|"leave", "place": "home"|"work"|
              "current"|"<name>"}
  recurs      null | {"frequency": "daily"|"weekly"|"monthly"|"yearly",
              "interval"?: n, "weekdays"?: ["mon", ...]}
  list        optional: null | "<shopping group>"
  title_has   optional list of spans the shown title must carry
  title_lacks optional list of spans the shown title must not carry

Times are read in the probe's fixed frame, Monday 2026-08-03 10:00
America/Toronto; authors write expectations in that frame.

THE OUTPUT IT READS

`Tools/PipelineProbe/build/probe --json`, one object per line with `text`,
`items` and `operations`. A line may also carry `id`, which is how an ASR
transcript, a Foundation Models run or a hand-recorded app result is matched
to its contract when its text is not the contract's utterance.

SEALED BY DEFAULT

The default report prints family names, ids never, text never. `--failures`
prints expected against actual for every failing capture and exists for the
one release review that follows the one scoring run. See the phase 13
protocol for who may run which subcommand and when.

    score.py validate CONTRACT
    score.py seal     CONTRACT --out SEAL.json
    score.py verify   CONTRACT --seal SEAL.json [--receipt RECEIPT.json ...]
    score.py score    CONTRACT ACTUAL --seal SEAL.json --receipt RECEIPT.json
                      --commit SHA --path rules|fm|app|asr [--failures]
    score.py score    CONTRACT ACTUAL --unsealed        (toy data only)
"""
import argparse
import hashlib
import importlib.util
import itertools
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

# The span matcher and the title-hygiene rules are the everyday scorer's, not
# a second implementation of them: two matchers would make a whole-capture
# failure and an everyday failure disagree about the same title.
_spec = importlib.util.spec_from_file_location(
    "everyday_score", HERE.parent / "everyday" / "score.py")
everyday = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(everyday)
norm, carries, title_defects = everyday.norm, everyday.carries, everyday.title_defects

ZONE = ZoneInfo("America/Toronto")
SEAL_FORMAT = "speakit-wholecapture-seal-1"

#: Phase 13 families. The first eight are the V1 exit-gate P0 families; a
#: failure in one of them is a harm, not an inaccuracy, and is marked so.
P0_FAMILIES = (
    "negation-becomes-action",
    "quoted-or-reported-command",
    "message-content-creates-alarm-or-cancel",
    "condition-executed-unconditionally",
    "cancellation-hits-wrong-item",
    "unresolved-semantics-executed",
    "thought-becomes-reminder",
    "invented-executable-info",
)
EVERYDAY_FAMILIES = (
    "single-task",
    "multi-item",
    "memory-only",
    "time-and-date",
    "place",
    "people",
    "mixed-action-and-memory",
    "long-rambling",
)
FAMILIES = P0_FAMILIES + EVERYDAY_FAMILIES

REQUIRED_ITEM_FIELDS = ("destination", "type", "due", "remind", "delivery",
                        "person", "place", "recurs")
OPTIONAL_ITEM_FIELDS = ("list", "title_has", "title_lacks")
DESTINATIONS = {"Today", "Memory", "NeedsReview"}
ITEM_TYPES = {"task", "shopping", "idea", "personFollowUp", "event", "note",
              "unclear"}
DELIVERIES = {"none", "notification", "alarm"}
OPERATIONS = {"create", "cancel", "complete", "reschedule", "retract"}
FREQUENCIES = {"daily", "weekly", "monthly", "yearly"}
#: Calendar weekday numbering, as `RecurrenceRule.weekdays` stores it.
WEEKDAYS = {"sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7}

SEVERITY = {
    "count": "critical", "operation": "critical", "operation_target": "critical",
    "destination": "behavioral", "due": "behavioral", "remind": "behavioral",
    "delivery": "behavioral", "recurs": "behavioral", "place": "behavioral",
    "type": "metadata", "person": "metadata", "list": "metadata",
    "title_has": "metadata", "title_lacks": "metadata",
}
RANK = {"critical": 3, "behavioral": 2, "metadata": 1}
TIME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}(?: \*|T\d{2}:\d{2})?$")


# --- contract ---------------------------------------------------------------

def load_jsonl(path):
    rows = []
    for number, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        if line.strip():
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as error:
                raise SystemExit(f"{path}:{number}: not JSON ({error.msg})")
    return rows


def item_problems(item, where):
    out = []
    if not isinstance(item, dict):
        return [f"{where}: an item must be an object"]
    for field in REQUIRED_ITEM_FIELDS:
        if field not in item:
            out.append(f"{where}: `{field}` is not asserted (write null for none)")
    unknown = set(item) - set(REQUIRED_ITEM_FIELDS) - set(OPTIONAL_ITEM_FIELDS)
    if unknown:
        out.append(f"{where}: unknown fields {sorted(unknown)}")
    if item.get("destination") not in DESTINATIONS:
        out.append(f"{where}: destination must be one of {sorted(DESTINATIONS)}")
    types = item.get("type")
    types = types if isinstance(types, list) else [types]
    if not types or any(t not in ITEM_TYPES for t in types):
        out.append(f"{where}: type must be one of {sorted(ITEM_TYPES)} or a list of them")
    for field in ("due", "remind"):
        value = item.get(field)
        if value is not None and value != "any" and not (
                isinstance(value, str) and TIME_RE.match(value)):
            out.append(f"{where}: {field} must be null, \"any\", or a dated form")
    if item.get("delivery") not in DELIVERIES:
        out.append(f"{where}: delivery must be one of {sorted(DELIVERIES)}")
    if item.get("remind") is None and item.get("delivery") not in (None, "none"):
        out.append(f"{where}: a delivery without a reminder cannot be observed")
    place = item.get("place")
    if place is not None and not (isinstance(place, dict)
                                  and place.get("event") in ("arrive", "leave")
                                  and isinstance(place.get("place"), str)):
        out.append(f"{where}: place must be null or {{event: arrive|leave, place}}")
    recurs = item.get("recurs")
    if recurs is not None:
        if not isinstance(recurs, dict) or recurs.get("frequency") not in FREQUENCIES:
            out.append(f"{where}: recurs must be null or carry a frequency")
        elif any(d not in WEEKDAYS for d in recurs.get("weekdays", [])):
            out.append(f"{where}: weekdays are {sorted(WEEKDAYS)}")
    for field in ("title_has", "title_lacks"):
        if field in item and not (isinstance(item[field], list)
                                  and all(isinstance(s, str) and s for s in item[field])):
            out.append(f"{where}: {field} must be a list of non-empty spans")
    return out


def reading_problems(reading, where):
    out = []
    if not isinstance(reading.get("items"), list):
        return [f"{where}: `items` must be a list (empty for none)"]
    for index, item in enumerate(reading["items"]):
        out += item_problems(item, f"{where} item {index + 1}")
    for index, op in enumerate(reading.get("operations", [])):
        if not isinstance(op, dict) or op.get("operation") not in OPERATIONS:
            out.append(f"{where} operation {index + 1}: must be one of {sorted(OPERATIONS)}")
    return out


def validate(rows):
    """Every reason the contract cannot be sealed. Names ids, never text."""
    problems, seen = [], set()
    for number, row in enumerate(rows, 1):
        cid = row.get("id")
        where = f"row {number} ({cid})" if cid else f"row {number}"
        if not isinstance(cid, str) or not cid:
            problems.append(f"{where}: missing id")
        elif cid in seen:
            problems.append(f"{where}: duplicate id")
        seen.add(cid)
        if row.get("family") not in FAMILIES:
            problems.append(f"{where}: family must be one of the {len(FAMILIES)} phase 13 families")
        if row.get("input") not in ("asr", "typed"):
            problems.append(f"{where}: input must be \"asr\" or \"typed\"")
        if not isinstance(row.get("utterance"), str) or not row["utterance"].strip():
            problems.append(f"{where}: missing utterance")
        problems += reading_problems(row, where)
        for index, alternative in enumerate(row.get("alternatives", [])):
            problems += reading_problems(alternative, f"{where} alternative {index + 1}")
    return problems


def readings(row):
    primary = {"items": row["items"], "operations": row.get("operations", [])}
    return [primary] + [{"items": a["items"], "operations": a.get("operations", [])}
                        for a in row.get("alternatives", [])]


# --- actual output ------------------------------------------------------------

def local(epoch):
    return None if epoch is None else datetime.fromtimestamp(epoch, ZONE)


def time_ok(expected, epoch):
    moment = local(epoch)
    if expected is None:
        return moment is None
    if moment is None:
        return False
    if expected == "any":
        return True
    if expected.endswith(" *"):
        return moment.strftime("%Y-%m-%d") == expected[:-2]
    if "T" in expected:
        return moment.strftime("%Y-%m-%dT%H:%M") == expected
    return moment.strftime("%Y-%m-%d") == expected and (moment.hour, moment.minute) == (0, 0)


def bare(text):
    return re.sub(r"^(?:the|a|an|my) ", "", norm(text or ""))


def place_ok(expected, actual):
    actual = actual if actual and actual != "nil" else None
    if expected is None:
        return actual is None
    if actual is None:
        return False
    match = re.match(r"(arrive|leave) (?:named\((.*)\)|(\S+))", actual)
    if not match or match.group(1) != expected["event"]:
        return False
    return bare(match.group(2) or match.group(3)) == bare(expected["place"])


def recurs_ok(expected, rule):
    if expected is None:
        return rule is None
    if rule is None or rule.get("frequency") != expected["frequency"]:
        return False
    if rule.get("interval", 1) != expected.get("interval", 1):
        return False
    if "weekdays" in expected:
        return sorted(rule.get("weekdays") or []) == sorted(WEEKDAYS[d] for d in expected["weekdays"])
    return True


def destination(item):
    return "NeedsReview" if item.get("needsReview") else item.get("route")


def item_mismatches(want, got):
    """Every non-cosmetic field of one expected item that the actual row misses."""
    out = []
    if destination(got) != want["destination"]:
        out.append("destination")
    types = want["type"] if isinstance(want["type"], list) else [want["type"]]
    if got.get("type") not in types:
        out.append("type")
    if not time_ok(want["due"], got.get("due")):
        out.append("due")
    if not time_ok(want["remind"], got.get("reminder")):
        out.append("remind")
    if (got.get("delivery") or "none") != want["delivery"]:
        out.append("delivery")
    people = want["person"] if isinstance(want["person"], list) else [want["person"]]
    if not any((p is None and not got.get("person")) or
               (p is not None and norm(p) == norm(got.get("person") or "")) for p in people):
        out.append("person")
    if not place_ok(want["place"], got.get("location")):
        out.append("place")
    if not recurs_ok(want["recurs"], got.get("recurrenceRule")):
        out.append("recurs")
    if "list" in want and (norm(want["list"] or "") != norm(got.get("shoppingGroup") or "")):
        out.append("list")
    title = norm(got.get("title") or "")
    if any(not carries(span, title) for span in want.get("title_has", [])):
        out.append("title_has")
    if any(carries(span, title) for span in want.get("title_lacks", [])):
        out.append("title_lacks")
    return out


def align(expected, actual):
    """Pairs (e, a) maximising agreement; exhaustive while that is cheap."""
    cost = [[len(item_mismatches(e, a)) for a in actual] for e in expected]
    small = min(len(expected), len(actual))
    if small == 0:
        return []
    if max(len(expected), len(actual)) <= 7:
        if len(expected) <= len(actual):
            options = ([(e, a) for e, a in enumerate(chosen)]
                       for chosen in itertools.permutations(range(len(actual)), small))
        else:
            options = ([(e, a) for a, e in enumerate(chosen)]
                       for chosen in itertools.permutations(range(len(expected)), small))
        return min(options, key=lambda pairs: sum(cost[e][a] for e, a in pairs))
    pairs, free = [], set(range(len(actual)))
    for e in range(len(expected)):
        if free:
            a = min(sorted(free), key=lambda j: cost[e][j])
            free.remove(a)
            pairs.append((e, a))
    return pairs


def op_target_ok(want, got):
    if "target" not in want or want["target"] is None:
        return True
    have = set(bare(got.get("target") or "").split())
    need = set(bare(want["target"]).split())
    return bool(need) and need <= have


def judge_reading(reading, got):
    """Failed fields (with severity) and cosmetic notes for one accepted reading."""
    failed = []
    expected, actual = reading["items"], got.get("items", [])
    if len(expected) != len(actual):
        failed.append("count")
    for e, a in align(expected, actual):
        failed += item_mismatches(expected[e], actual[a])
    want_ops = sorted(reading["operations"], key=lambda o: o["operation"])
    have_ops = sorted(got.get("operations", []), key=lambda o: o.get("operation", ""))
    if [o["operation"] for o in want_ops] != [o.get("operation") for o in have_ops]:
        failed.append("operation")
    else:
        failed += ["operation_target" for w, h in zip(want_ops, have_ops) if not op_target_ok(w, h)]
    return failed


def judge(row, got):
    if got is None:
        return {"missing": True, "correct": False, "failed": ["no output"],
                "worst": "critical", "cosmetic": [], "reading": None}
    results = [judge_reading(r, got) for r in readings(row)]
    index = min(range(len(results)), key=lambda i: (len(results[i]), i))
    failed = results[index]
    cosmetic = sorted({d.split(":")[0] for item in got.get("items", [])
                       for d in title_defects(item.get("title") or "", row["utterance"])})
    worst = max((SEVERITY[f] for f in failed), key=RANK.get, default=None)
    return {"missing": False, "correct": not failed, "failed": sorted(set(failed)),
            "worst": worst, "cosmetic": cosmetic, "reading": index}


def index_actual(rows):
    by_id, by_text = {}, {}
    for row in rows:
        if row.get("id"):
            by_id[row["id"]] = row
        if row.get("text") is not None:
            by_text[row["text"]] = row
    return by_id, by_text


# --- sealing ------------------------------------------------------------------

def canonical(row):
    return json.dumps(row, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def digest(data):
    return hashlib.sha256(data).hexdigest()


def seal_record(path, rows):
    return {
        "format": SEAL_FORMAT,
        "set_sha256": digest(Path(path).read_bytes()),
        "captures": {row["id"]: digest(canonical(row).encode()) for row in rows},
        "families": dict(sorted(Counter(row["family"] for row in rows).items())),
        "sealed_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def changes(path, rows, record):
    """How the set differs from a recorded seal, in counts and ids only."""
    now = {row.get("id"): digest(canonical(row).encode()) for row in rows}
    then = record.get("captures", {})
    edited = sorted(i for i in now if i in then and now[i] != then[i])
    added = sorted(i for i in now if i not in then)
    removed = sorted(i for i in then if i not in now)
    same = digest(Path(path).read_bytes()) == record.get("set_sha256")
    return same, edited, added, removed


def inside_repository(path):
    return Path(path).resolve().is_relative_to(ROOT)


# --- report -------------------------------------------------------------------

def pct(k, n):
    return f"{k:>3}/{n:<3} ({100 * k / n:5.1f}%)" if n else "      —      "


def report(rows, results, minimum, path_label):
    by_family = defaultdict(list)
    for row in rows:
        by_family[row["family"]].append((row, results[row["id"]]))
    print()
    print(f"WHOLE CAPTURE CORRECT — path `{path_label}` — per family, never averaged")
    print("=" * 86)
    print(f"{'family':<42}{'n':>4}{'miss':>5}{'correct':>17}{'crit':>6}{'beh':>5}{'meta':>5}")
    print("-" * 86)
    for family in FAMILIES:
        pairs = by_family.get(family, [])
        n = len(pairs)
        ok = sum(r["correct"] for _, r in pairs)
        worst = Counter(r["worst"] for _, r in pairs if not r["correct"])
        marks = (" P0" if family in P0_FAMILIES else "") + (
            f"  UNDER MINIMUM ({n}<{minimum})" if n < minimum else "")
        print(f"{family:<42}{n:>4}{sum(r['missing'] for _, r in pairs):>5}{pct(ok, n):>17}"
              f"{worst['critical']:>6}{worst['behavioral']:>5}{worst['metadata']:>5}{marks}")
    print("-" * 86)
    print("A capture is correct only when every non-cosmetic field matches.")
    print("crit/beh/meta count failing captures by their WORST mismatch; `miss`")
    print("is captures with no output at all, counted as incorrect.")

    print()
    print("WHICH FIELDS FAILED — captures per family failing each field")
    print("-" * 86)
    for family in FAMILIES:
        fields = Counter(f for _, r in by_family.get(family, []) for f in r["failed"])
        if fields:
            print(f"{family:<42}" + ", ".join(f"{f} {c}" for f, c in
                                              sorted(fields.items(), key=lambda kv: (-kv[1], kv[0]))))

    print()
    print("BY INPUT KIND — the same captures split by how the text was produced")
    print("-" * 86)
    print(f"{'family':<42}{'typed':>20}{'asr':>20}")
    for family in FAMILIES:
        pairs = by_family.get(family, [])
        cells = []
        for kind in ("typed", "asr"):
            subset = [r for row, r in pairs if row["input"] == kind]
            cells.append(pct(sum(r["correct"] for r in subset), len(subset)))
        if pairs:
            print(f"{family:<42}{cells[0]:>20}{cells[1]:>20}")

    tags = sorted({t for row in rows for t in row.get("tags", [])})
    if tags:
        print()
        print("BY TAG — overlapping; one capture can carry several")
        print("-" * 86)
        for tag in tags:
            subset = [results[row["id"]] for row in rows if tag in row.get("tags", [])]
            print(f"{tag:<42}{len(subset):>4}{pct(sum(r['correct'] for r in subset), len(subset)):>22}")

    cosmetic = Counter(d for r in results.values() for d in r["cosmetic"])
    print()
    print("COSMETIC — title hygiene, reported separately and never failing a capture")
    print("-" * 86)
    clean = sum(not r["cosmetic"] for r in results.values() if not r["missing"])
    print(f"  captures whose titles carry no removable material  "
          f"{clean}/{sum(not r['missing'] for r in results.values())}")
    for defect, count in sorted(cosmetic.items(), key=lambda kv: -kv[1]):
        print(f"    {count:>4}  {defect}")
    print()
    print(f"{len(rows)} captures in {len(by_family)} families. No aggregate rate is printed:")
    print("read the family rows, and the P0 rows first.")


def print_failures(rows, results, actual_for):
    print()
    print("#" * 86)
    print("# FAILURES — release review only. Never an input to a production change.")
    print("#" * 86)
    for row in rows:
        result = results[row["id"]]
        if result["correct"]:
            continue
        print()
        print(f"{row['id']}  [{row['family']}]  input={row['input']}  failed: "
              f"{', '.join(result['failed'])}")
        print(f"  said:     {json.dumps(row['utterance'], ensure_ascii=False)}")
        print(f"  expected: {json.dumps(readings(row)[0], ensure_ascii=False, sort_keys=True)}")
        if row.get("note"):
            print(f"  note:     {row['note']}")
        got = actual_for(row)
        if got is not None:
            print(f"  actual:   {json.dumps({'items': got.get('items', []), 'operations': got.get('operations', [])}, ensure_ascii=False, sort_keys=True)}")


# --- commands -----------------------------------------------------------------

def load_valid(path):
    rows = load_jsonl(path)
    problems = validate(rows)
    if problems:
        for line in problems:
            print("CONTRACT: " + line, file=sys.stderr)
        raise SystemExit(f"{len(problems)} contract problem(s); nothing scored or sealed")
    return rows


def cmd_validate(args):
    rows = load_valid(args.contract)
    families = Counter(row["family"] for row in rows)
    print(f"valid: {len(rows)} captures, {len(families)} of {len(FAMILIES)} families")
    thin = [f for f in FAMILIES if families[f] < args.min_per_family]
    if thin:
        print(f"under {args.min_per_family} captures: {', '.join(thin)}")
        return 1
    return 0


def cmd_seal(args):
    if inside_repository(args.contract) or inside_repository(args.out):
        raise SystemExit("refusing: a sealed set and its seal live outside the repository")
    if Path(args.out).exists():
        raise SystemExit("refusing: a seal already exists; a set is sealed once")
    rows = load_valid(args.contract)
    record = seal_record(args.contract, rows)
    Path(args.out).write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    print(f"sealed {len(rows)} captures, sha256 {record['set_sha256']}")
    return 0


def cmd_verify(args):
    rows = load_jsonl(args.contract)
    status = 0
    for label, path in [("seal", args.seal)] + [("receipt", r) for r in args.receipt]:
        record = json.loads(Path(path).read_text())
        if label == "receipt":
            record = {"set_sha256": record["set_sha256"], "captures": record["captures"]}
        same, edited, added, removed = changes(args.contract, rows, record)
        if same:
            print(f"{label} {path}: unchanged")
            continue
        status = 1
        print(f"{label} {path}: CHANGED — {len(edited)} edited, {len(added)} added, "
              f"{len(removed)} removed" + ("" if edited or added or removed
                                           else " (bytes only)"))
    return status


def cmd_score(args):
    rows = load_valid(args.contract)
    if not args.unsealed:
        missing = [n for n in ("seal", "receipt", "commit", "path") if not getattr(args, n)]
        if missing:
            raise SystemExit("a sealed score needs --" + ", --".join(missing)
                             + " (or --unsealed for toy data)")
        if inside_repository(args.contract):
            raise SystemExit("refusing: the sealed set must live outside the repository")
        if Path(args.receipt).exists():
            raise SystemExit("refusing: this set was already scored on this path; "
                             "scoring is one-shot")
        same, edited, added, removed = changes(
            args.contract, rows, json.loads(Path(args.seal).read_text()))
        if not same:
            raise SystemExit(f"refusing: the set differs from its seal ({len(edited)} "
                             f"edited, {len(added)} added, {len(removed)} removed)")
    actual_rows = load_jsonl(args.actual)
    by_id, by_text = index_actual(actual_rows)

    def actual_for(row):
        return by_id.get(row["id"]) or by_text.get(row["utterance"])

    results = {row["id"]: judge(row, actual_for(row)) for row in rows}
    label = args.path or "unsealed"
    if args.unsealed:
        print("UNSEALED — a dry run on data that is not the phase 13 set. Not a result.")
    report(rows, results, args.min_per_family, label)
    if args.failures:
        print_failures(rows, results, actual_for)
    if not args.unsealed:
        receipt = {
            "format": SEAL_FORMAT,
            "set_sha256": digest(Path(args.contract).read_bytes()),
            "captures": {row["id"]: digest(canonical(row).encode()) for row in rows},
            "actual_sha256": digest(Path(args.actual).read_bytes()),
            "commit": args.commit,
            "path": args.path,
            "scored_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "results": {cid: {k: r[k] for k in ("correct", "worst", "failed", "missing")}
                        for cid, r in results.items()},
        }
        Path(args.receipt).write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    v = sub.add_parser("validate")
    v.add_argument("contract")
    v.add_argument("--min-per-family", type=int, default=15)
    s = sub.add_parser("seal")
    s.add_argument("contract")
    s.add_argument("--out", required=True)
    c = sub.add_parser("verify")
    c.add_argument("contract")
    c.add_argument("--seal", required=True)
    c.add_argument("--receipt", action="append", default=[])
    r = sub.add_parser("score")
    r.add_argument("contract")
    r.add_argument("actual")
    r.add_argument("--seal")
    r.add_argument("--receipt")
    r.add_argument("--commit")
    r.add_argument("--path", choices=("rules", "fm", "app", "asr"))
    r.add_argument("--unsealed", action="store_true")
    r.add_argument("--failures", action="store_true")
    r.add_argument("--min-per-family", type=int, default=15)
    args = parser.parse_args(argv)
    return {"validate": cmd_validate, "seal": cmd_seal, "verify": cmd_verify,
            "score": cmd_score}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
