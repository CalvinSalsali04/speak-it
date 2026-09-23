#!/usr/bin/env python3
"""Scores the semantic-unit experiment: whole-capture unit recovery against a
frozen gold, for either candidate and for the free reference arms.

    score_units.py precheck --gold gold.jsonl --inputs inputs.jsonl
    score_units.py score    --gold gold.jsonl --inputs inputs.jsonl --results results.jsonl
                            [--reference DIAG_FOLDER] [--families families.json]
    score_units.py selftest

precheck  NO MODEL. Whether each candidate CAN express each gold answer:
          constructs the best answer the representation allows and scores it
          with the same scorer, so "representable" and "scores exact" cannot
          drift apart. Run this before any generation is read.
score     Every capture, every arm: EXACT or the failure classes, per family,
          per-unit boundary precision and recall, latency and tokens.
          `--reference` adds three arms that cost no model call: the rules
          rows, the recorded split-index units job and the recorded
          production whole-list answer, from the diagnostic run's folder.

Prints capture ids, counts and closed-vocabulary classes only: no capture text.

GOLD CONTRACT (one JSON object per line):
    {"id": ..., "units": [{"ranges": [[first, last], ...]}, ...],
     "filler": [atom, ...], "ambiguous": [{"atoms": [...], "units": [k, ...]}]}
A unit's CONTENT is its atoms minus filler and ambiguous atoms. Filler atoms
may sit in any unit or in none. An ambiguous atom may sit in any unit it
names, or in none. Everything else must be exactly where the gold puts it.
"""
import hashlib
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

RANGES_CAP = 20  # unitsExperimentThoughtCap in Sources/UnitsExperiment.swift

CLASSES = [
    "exact",
    "malformed",            # refused, failed, undecodable, out of bounds, unordered or overlapping
    "representation",       # this arm cannot express the gold answer at all
    "capacity",             # more gold units than the arm may return
    "dropped",              # a content atom is in no unit
    "filler-only",          # a unit holds no content atom
    "absorbed",             # a unit takes part of one gold unit and part of another
    "over-split",           # more units than gold, every unit inside one gold unit
    "under-split",          # fewer units than gold, whole gold units merged
    "wrong-boundaries",     # anything else, including the right number in the wrong place
]


# ------------------------------------------------------------------ gold

def read_jsonl(path):
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class Gold:
    def __init__(self, record, atom_count):
        self.id = record["id"]
        self.n = atom_count
        self.filler = set(record.get("filler", []))
        self.ambiguous = {}
        for entry in record.get("ambiguous", []):
            for atom in entry["atoms"]:
                self.ambiguous[atom] = set(entry.get("units", []))
        self.units = []
        for unit in record["units"]:
            atoms = set()
            for first, last in unit["ranges"]:
                if not (0 <= first <= last < atom_count):
                    raise ValueError(f"{self.id}: gold range {first}-{last} out of bounds")
                atoms.update(range(first, last + 1))
            self.units.append(atoms - self.filler - set(self.ambiguous))
        owners = Counter(a for unit in self.units for a in unit)
        if any(count > 1 for count in owners.values()):
            raise ValueError(f"{self.id}: an atom is content of two gold units")
        if any(not unit for unit in self.units):
            raise ValueError(f"{self.id}: a gold unit has no content atom")
        self.owner = {a: k for k, unit in enumerate(self.units) for a in unit}
        self.content = set(self.owner)
        # Every atom must be content, filler or ambiguous: nothing unowned.
        unowned = set(range(atom_count)) - self.content - self.filler - set(self.ambiguous)
        if unowned:
            raise ValueError(f"{self.id}: atoms {sorted(unowned)} are in no unit and not filler or ambiguous")

    def gaps(self):
        """For each boundary between gold unit k and k+1, the atom positions a
        cut may fall after: from the last content atom of k to one before the
        first content atom of k+1. Units are ordered by first content atom."""
        order = sorted(range(len(self.units)), key=lambda k: min(self.units[k]))
        out = []
        for a, b in zip(order, order[1:]):
            out.append(set(range(max(self.units[a]), min(self.units[b]))))
        return out


# ------------------------------------------------------------ an answer

def classify(gold, units, cap=None, representable=True):
    """units: list of atom sets in proposed order, or None for malformed.
    Returns (primary class, sorted flags)."""
    if units is None:
        return "malformed", ["malformed"]
    flags = set()
    if not representable:
        flags.add("representation")
    if cap is not None and len(gold.units) > cap:
        flags.add("capacity")
    covered = set().union(*units) if units else set()
    if gold.content - covered:
        flags.add("dropped")
    for unit in units:
        if not (unit & gold.content):
            flags.add("filler-only")
        for atom in unit & set(gold.ambiguous):
            pass  # checked below per unit index
    # Map proposed units to gold units by content.
    touched = [sorted({gold.owner[a] for a in unit & gold.content}) for unit in units]
    content_units = [t for t in touched if t]
    exact = (not flags and len(units) == len(gold.units)
             and all(len(t) == 1 for t in touched))
    if exact:
        for j, unit in enumerate(units):
            k = touched[j][0]
            if unit & gold.content != gold.units[k] or k != j:
                exact = False
                break
            if any(k not in gold.ambiguous[a] for a in unit & set(gold.ambiguous)):
                exact = False
                break
    if exact:
        return "exact", ["exact"]
    # Crossing: a proposed unit takes part (not all) of a gold unit together
    # with content of another gold unit.
    for j, unit in enumerate(units):
        if len(touched[j]) > 1 and any(not gold.units[k] <= unit for k in touched[j]):
            flags.add("absorbed")
    split_gold = [k for k in range(len(gold.units))
                  if sum(1 for t in touched if k in t) > 1]
    merged = [t for t in touched if len(t) > 1]
    if split_gold:
        flags.add("over-split")
    if merged:
        flags.add("under-split")
    n_proposed = len(content_units)
    if n_proposed == len(gold.units) and not (flags & {"absorbed", "dropped", "filler-only", "representation", "capacity"}):
        flags.discard("over-split")
        flags.discard("under-split")
        flags.add("wrong-boundaries")
    if not flags:
        flags.add("wrong-boundaries")  # right partition, an ambiguous atom given to a unit it may not join
    for name in CLASSES:
        if name in flags:
            return name, sorted(flags)
    return "wrong-boundaries", sorted(flags)


def boundary_counts(gold, units):
    """(matched proposed boundaries, proposed boundaries, matched gold boundaries, gold boundaries)."""
    if units is None:
        return 0, 0, 0, len(gold.units) - 1
    gaps = gold.gaps()
    cuts = []
    nonempty = [u for u in units if u]
    for a, b in zip(nonempty, nonempty[1:]):
        cuts.append((max(a), min(b)))
    matched_cuts = 0
    hit = set()
    for left, right in cuts:
        # a proposed boundary lies after `left` and before `right`
        found = [g for g, gap in enumerate(gaps) if left in gap or any(p in gap for p in range(left, right))]
        if found:
            matched_cuts += 1
            hit.update(found)
    return matched_cuts, len(cuts), len(hit), len(gaps)


# ------------------------------------------------------------ the arms

def ranges_units(raw, n):
    """Candidate 1: [{"firstAtom", "lastAtom"}] -> atom sets, or None."""
    try:
        thoughts = json.loads(raw)["thoughts"]
        spans = [(int(t["firstAtom"]), int(t["lastAtom"])) for t in thoughts]
    except (TypeError, KeyError, ValueError, json.JSONDecodeError):
        return None
    previous = -1
    units = []
    for first, last in spans:
        if not (0 <= first <= last < n) or first <= previous:
            return None
        previous = last
        units.append(set(range(first, last + 1)))
    return units or None


def labels_units(raw, lines):
    """Candidate 2: exactly one {"line", "label"} per line, in order -> atom
    sets, or None. Line 0 always begins a thought whatever it is labelled."""
    try:
        entries = json.loads(raw)["lines"]
        labels = [(int(e["line"]), e["label"]) for e in entries]
    except (TypeError, KeyError, ValueError, json.JSONDecodeError):
        return None
    if [line for line, _ in labels] != list(range(len(lines))):
        return None
    if any(label not in ("starts", "continues") for _, label in labels):
        return None
    units = []
    for (index, label), (first, last) in zip(labels, lines):
        if index == 0 or label == "starts":
            units.append(set())
        units[-1].update(range(first, last + 1))
    return units


def whole_from_lines(lines):
    return [set(range(lines[0][0], lines[-1][1] + 1))]


# ------------------------------------------------------ representability

def best_ranges(gold):
    """The best candidate-1 answer: each gold unit as the one range from its
    first to its last content atom. Returns (units, reason) where reason is
    None when that answer is legal for the arm."""
    order = sorted(range(len(gold.units)), key=lambda k: min(gold.units[k]))
    if order != list(range(len(gold.units))):
        return None, "gold units are not in spoken order"
    units = [set(range(min(u), max(u) + 1)) for u in gold.units]
    for j, unit in enumerate(units):
        foreign = {a for a in unit & gold.content if gold.owner[a] != j}
        if foreign:
            return units, "discontinuous: another unit's content lies inside this unit's span"
    if len(units) > RANGES_CAP:
        return units[:RANGES_CAP], f"capacity: {len(units)} gold units, cap {RANGES_CAP}"
    return units, None


def best_labels(gold, lines):
    """The best candidate-2 answer. A line whose content belongs to two gold
    units needs a boundary inside a clause line; a gold unit whose lines are
    not contiguous needs structure the lines cannot express."""
    owners = []
    for first, last in lines:
        atoms = set(range(first, last + 1))
        owned = {gold.owner[a] for a in atoms & gold.content}
        if len(owned) > 1:
            return None, "boundary inside a clause line"
        owners.append(next(iter(owned)) if owned else None)
    sequence = [o for o in owners if o is not None]
    collapsed = [k for k in range(len(gold.units)) if k not in sequence]
    runs = [k for i, k in enumerate(sequence) if i == 0 or sequence[i - 1] != k]
    if len(runs) != len(set(runs)) or collapsed:
        return None, "unit not contiguous in clause lines (structure collapsed)"
    units, current = [], None
    for (first, last), owner in zip(lines, owners):
        if not units or (owner is not None and current is not None and owner != current):
            units.append(set())
        units[-1].update(range(first, last + 1))
        if owner is not None:
            current = owner
    return units, None


def precheck(gold_by_id, inputs):
    rows = []
    for item in inputs:
        gold = gold_by_id[item["id"]]
        r_units, r_reason = best_ranges(gold)
        r_class = "representable" if r_reason is None and classify(gold, r_units)[0] == "exact" else (r_reason or "does not score exact")
        l_units, l_reason = best_labels(gold, item["lines"])
        l_class = "representable" if l_reason is None and classify(gold, l_units)[0] == "exact" else (l_reason or "does not score exact")
        rows.append((item["id"], len(gold.units), len(item["lines"]), r_class, l_class))
    return rows


# ------------------------------------------------------------- reference arms

def reference_arms(folder, inputs, gold_by_id):
    """Rules rows, recorded units job and recorded production answer, located
    on the atoms. Only for captures the diagnostic run holds."""
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    import score  # noqa: E402  Tools/SemanticMap/score.py
    folder = Path(folder)
    rules = score.parse_report(str(folder / "rules.report"))
    runs = {r["id"]: r for r in read_jsonl(folder / "runs.jsonl")}
    asked = {r["id"]: r for r in read_jsonl(folder / "asked.jsonl")}
    out = defaultdict(dict)
    for item in inputs:
        cid, atoms = item["id"], item["atoms"]
        if cid not in runs:
            continue
        utterance = runs[cid]["utterance"]
        if utterance.split() != atoms:
            continue
        out[cid]["rules"] = locate_all([row["quote"] for row in rules[utterance]["rows"]], atoms)
        splits = (((runs[cid].get("map") or {}).get("unitsJob") or {}).get("rawUnits") or {}).get("splitsAfter")
        out[cid]["units-job"] = splits_units(splits, len(atoms)) if splits is not None else None
        raw = asked[cid]["production"].get("rawResponse")
        items = json.loads(raw)["items"] if raw else []
        out[cid]["whole-list"] = locate_all([it["sourceQuote"] for it in items], atoms, strict=True)
    return out


def fold(word):
    return "".join(c for c in word.lower() if c.isalnum())


def locate_all(quotes, atoms, strict=False):
    """Each quote as the first whole-atom match at or after the previous one.
    None when any quote cannot be placed (strict) or when nothing is placed."""
    hay = [fold(a) for a in atoms]
    units, cursor = [], 0
    for quote in quotes:
        needle = [w for w in (fold(x) for x in quote.split()) if w]
        found = None
        if needle:
            for start in range(cursor, len(hay) - len(needle) + 1):
                if hay[start:start + len(needle)] == needle:
                    found = start
                    break
        if found is None:
            if strict:
                return None
            continue
        units.append(set(range(found, found + len(needle))))
        cursor = found + len(needle)
    return units or None


def splits_units(splits, n):
    units, start = [], 0
    for cut in list(splits) + [n - 1]:
        if not (start <= cut < n):
            return None
        units.append(set(range(start, cut + 1)))
        start = cut + 1
    return units


# --------------------------------------------------------------------- score

def score_run(gold_by_id, inputs, results, reference, families):
    by_arm = defaultdict(dict)
    meta = defaultdict(dict)
    for record in results:
        by_arm[record["arm"]][record["id"]] = record
    table = []
    for item in inputs:
        cid, n, lines = item["id"], len(item["atoms"]), item["lines"]
        gold = gold_by_id[cid]
        _, r_reason = best_ranges(gold)
        _, l_reason = best_labels(gold, lines)
        row = {"id": cid, "gold": len(gold.units)}
        for arm in ("ranges", "labels"):
            record = by_arm[arm].get(cid)
            if record is None:
                row[arm] = ("missing", ["missing"], None)
                continue
            job = record["job"]
            if arm == "labels" and job.get("outcome") == "skipped" and job.get("skip") == "tooShortToSplit":
                units = whole_from_lines(lines)
            elif job.get("outcome") != "accepted" or not record.get("raw"):
                units = None
            else:
                units = ranges_units(record["raw"], n) if arm == "ranges" else labels_units(record["raw"], lines)
            reason = r_reason if arm == "ranges" else l_reason
            cls, flags = classify(gold, units, cap=RANGES_CAP if arm == "ranges" else None,
                                  representable=reason is None or reason.startswith("capacity"))
            row[arm] = (cls, flags, units)
            meta[arm][cid] = job
        for arm, units in (reference.get(cid) or {}).items():
            row[arm] = classify(gold, units) + (units,)
        table.append(row)
    return table, meta


def pct(values, q):
    values = sorted(v for v in values if v is not None)
    if not values:
        return "-"
    return values[min(len(values) - 1, int(round(q * (len(values) - 1))))]


def report(table, meta, families, gold_by_id):
    arms = [a for a in ("ranges", "labels") if any(meta[a] for _ in [0])] + [a for a in ("rules", "units-job", "whole-list")
                                   if any(a in row for row in table)]
    print("WHOLE-CAPTURE RESULT (primary class; flags in brackets when more than one)")
    print("id".ljust(8) + "gold".rjust(5) + "".join(a.rjust(20) for a in arms))
    for row in table:
        cells = []
        for arm in arms:
            if arm not in row:
                cells.append("n/a".rjust(20))
                continue
            cls, flags = row[arm][0], row[arm][1]
            extra = "+" if len(flags) > 1 else ""
            cells.append((cls + extra).rjust(20))
        print(row["id"].ljust(8) + str(row["gold"]).rjust(5) + "".join(cells))
    print()
    print("EXACT COUNTS")
    for arm in arms:
        rows = [r for r in table if arm in r]
        exact = sum(1 for r in rows if r[arm][0] == "exact")
        counts = Counter(r[arm][0] for r in rows)
        print(f"  {arm:12} exact {exact}/{len(rows)}   " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items()) if k != "exact"))
    print()
    print("BOUNDARY PRECISION / RECALL (pooled over captures)")
    for arm in arms:
        mp = pp = mg = gg = 0
        for r in table:
            if arm not in r:
                continue
            a, b, c, d = boundary_counts(gold_by_id[r["id"]], r[arm][2])
            mp, pp, mg, gg = mp + a, pp + b, mg + c, gg + d
        print(f"  {arm:12} precision {mp}/{pp}   recall {mg}/{gg}")
    if families:
        print()
        print("PER FAMILY (exact / captures)")
        names = sorted({f for fs in families.values() for f in fs})
        print("family".ljust(28) + "".join(a.rjust(14) for a in arms))
        for name in names:
            ids = [r for r in table if name in families.get(r["id"], [])]
            cells = []
            for arm in arms:
                rows = [r for r in ids if arm in r]
                cells.append(f"{sum(1 for r in rows if r[arm][0] == 'exact')}/{len(rows)}".rjust(14))
            print(name.ljust(28) + "".join(cells))
    print()
    print("LATENCY AND TOKENS (model arms)")
    for arm in ("ranges", "labels"):
        jobs = [j for j in meta[arm].values() if j.get("outcome") != "skipped"]
        lat = [j.get("latencyMilliseconds") for j in jobs]
        out = [j.get("responseTokens") for j in jobs]
        inp = [(j.get("promptTokens") or 0) + (j.get("instructionTokens") or 0) + (j.get("schemaTokens") or 0)
               for j in jobs if j.get("promptTokens") is not None]
        outcomes = Counter(j.get("outcome") for j in meta[arm].values())
        print(f"  {arm:8} asked {len(jobs)}  outcomes {dict(outcomes)}  latency ms p50 {pct(lat, .5)} p90 {pct(lat, .9)} max {pct(lat, 1)}"
              f"  response tokens p50 {pct(out, .5)} max {pct(out, 1)}  input tokens p50 {pct(inp, .5)} max {pct(inp, 1)}")


# ------------------------------------------------------------------ selftest

def selftest():
    import itertools
    import random
    failures = 0

    def check(name, got, want):
        nonlocal failures
        if got != want:
            failures += 1
            print(f"FAIL {name}: got {got}, want {want}")

    g = Gold({"id": "t", "units": [{"ranges": [[1, 3]]}, {"ranges": [[5, 7]]}], "filler": [0, 4],
              "ambiguous": []}, 8)
    check("exact", classify(g, [set(range(0, 4)), set(range(4, 8))])[0], "exact")
    check("exact, filler left out", classify(g, [set(range(1, 4)), set(range(5, 8))])[0], "exact")
    check("dropped", classify(g, [set(range(1, 4)), set(range(5, 7))])[0], "dropped")
    check("under-split", classify(g, [set(range(0, 8))])[0], "under-split")
    check("over-split", classify(g, [{1}, {2, 3}, set(range(5, 8))])[0], "over-split")
    check("absorbed", classify(g, [set(range(0, 6)), {6, 7}])[0], "absorbed")
    check("filler-only", classify(g, [{0}, set(range(1, 4)), set(range(4, 8))])[0], "filler-only")
    check("malformed", classify(g, None)[0], "malformed")
    check("ranges decode rejects overlap", ranges_units('{"thoughts":[{"firstAtom":0,"lastAtom":3},{"firstAtom":3,"lastAtom":7}]}', 8), None)
    check("ranges decode rejects out of bounds", ranges_units('{"thoughts":[{"firstAtom":0,"lastAtom":8}]}', 8), None)
    check("labels decode rejects misnumbered", labels_units('{"lines":[{"line":1,"label":"starts"}]}', [[0, 7]]), None)
    a = Gold({"id": "a", "units": [{"ranges": [[0, 1]]}, {"ranges": [[3, 4]]}], "filler": [],
              "ambiguous": [{"atoms": [2], "units": [0, 1]}, {"atoms": [5], "units": [1]}]}, 6)
    check("ambiguous with first unit", classify(a, [{0, 1, 2}, {3, 4, 5}])[0], "exact")
    check("ambiguous with second unit", classify(a, [{0, 1}, {2, 3, 4}])[0], "exact")
    check("ambiguous left out", classify(a, [{0, 1}, {3, 4}])[0], "exact")
    check("ambiguous in a unit it may not join", classify(a, [{0, 1}, {3, 4}, {5}])[0], "filler-only")
    b = Gold({"id": "b", "units": [{"ranges": [[0, 1]]}, {"ranges": [[3, 4]]}], "filler": [],
              "ambiguous": [{"atoms": [2], "units": [1]}]}, 5)
    check("ambiguous given to a unit it may not join", classify(b, [{0, 1, 2}, {3, 4}])[0], "wrong-boundaries")
    check("labels group",labels_units('{"lines":[{"line":0,"label":"continues"},{"line":1,"label":"starts"}]}', [[0, 3], [4, 7]]),
          [set(range(0, 4)), set(range(4, 8))])

    # Exhaustive agreement between the precheck and the scorer: on random gold
    # over up to 7 atoms, candidate 2 has an exact answer among ALL labelings
    # exactly when best_labels says it is representable, and candidate 1 among
    # ALL ordered disjoint range lists exactly when best_ranges says so.
    rng = random.Random(7)
    for trial in range(400):
        n = rng.randint(1, 7)
        roles = [rng.choice(["u", "u", "u", "f"]) for _ in range(n)]
        if all(r == "f" for r in roles):
            roles[0] = "u"
        k_units = rng.randint(1, max(1, roles.count("u")))
        content = [i for i, r in enumerate(roles) if r == "u"]
        assign = sorted(rng.choice(range(k_units)) for _ in content) if rng.random() < 0.7 else [rng.choice(range(k_units)) for _ in content]
        used = sorted(set(assign))
        remap = {u: i for i, u in enumerate(used)}
        # order units by first atom so gold is in spoken order
        first_seen = []
        for a in assign:
            if remap[a] not in first_seen:
                first_seen.append(remap[a])
        order = {u: i for i, u in enumerate(first_seen)}
        units = defaultdict(list)
        for atom, a in zip(content, assign):
            units[order[remap[a]]].append(atom)
        record = {"id": "r", "units": [{"ranges": [[x, x] for x in units[i]]} for i in range(len(units))],
                  "filler": [i for i, r in enumerate(roles) if r == "f"], "ambiguous": []}
        gold = Gold(record, n)
        cuts_all = list(range(1, n))
        lines = []
        chosen = [c for c in cuts_all if rng.random() < 0.5]
        starts = [0] + chosen
        lines = [[s, (starts[i + 1] - 1) if i + 1 < len(starts) else n - 1] for i, s in enumerate(starts)]
        any_exact = False
        for labels in itertools.product([False, True], repeat=len(lines) - 1):
            grouped = []
            for index, (first, last) in enumerate(lines):
                if index == 0 or labels[index - 1]:
                    grouped.append(set())
                grouped[-1].update(range(first, last + 1))
            if classify(gold, grouped)[0] == "exact":
                any_exact = True
                break
        _, reason = best_labels(gold, lines)
        check(f"labels precheck agrees (trial {trial})", reason is None, any_exact)
        any_exact = False
        for mask in itertools.product([0, 1, 2], repeat=n):  # 0 outside, 1 continue, 2 start
            grouped, open_ = [], False
            for atom, m in enumerate(mask):
                if m == 2 or (m == 1 and not open_):
                    grouped.append(set())
                    open_ = True
                if m == 0:
                    open_ = False
                    continue
                grouped[-1].add(atom)
            if grouped and classify(gold, grouped)[0] == "exact":
                any_exact = True
                break
        _, reason = best_ranges(gold)
        check(f"ranges precheck agrees (trial {trial})", reason is None, any_exact)
    print("selftest", "ok" if not failures else f"FAILED ({failures})")
    return failures == 0


# ---------------------------------------------------------------------- main

def args_map(argv):
    out, key = {}, None
    for token in argv:
        if token.startswith("--"):
            key = token[2:]
            out[key] = True
        elif key:
            out[key] = token
            key = None
    return out


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    command, options = sys.argv[1], args_map(sys.argv[2:])
    if command == "selftest":
        return 0 if selftest() else 1
    inputs = read_jsonl(options["inputs"])
    counts = {item["id"]: len(item["atoms"]) for item in inputs}
    gold_by_id = {g["id"]: Gold(g, counts[g["id"]]) for g in read_jsonl(options["gold"]) if g["id"] in counts}
    missing = [i for i in counts if i not in gold_by_id]
    if missing:
        print(f"no gold for {len(missing)} capture(s): {', '.join(missing)}")
        return 2
    print(f"gold    {sha256(options['gold'])}")
    print(f"inputs  {sha256(options['inputs'])}")
    if command == "precheck":
        rows = precheck(gold_by_id, inputs)
        print()
        print("REPRESENTABILITY (no model)")
        print("id".ljust(8) + "gold".rjust(5) + "lines".rjust(6) + "  candidate 1 (ranges)".ljust(58) + "candidate 2 (labels)")
        for cid, g, l, r, c in rows:
            print(cid.ljust(8) + str(g).rjust(5) + str(l).rjust(6) + "  " + r.ljust(56) + c)
        print()
        print(f"candidate 1 representable {sum(r[3] == 'representable' for r in rows)}/{len(rows)}; "
              f"candidate 2 representable {sum(r[4] == 'representable' for r in rows)}/{len(rows)}")
        return 0
    if command == "score":
        results = read_jsonl(options["results"]) if options.get("results") else []
        print(f"results {sha256(options['results']) if options.get('results') else 'none (reference arms only)'}")
        reference = reference_arms(options["reference"], inputs, gold_by_id) if options.get("reference") else {}
        families = json.loads(Path(options["families"]).read_text()) if options.get("families") else {}
        table, meta = score_run(gold_by_id, inputs, results, reference, families)
        report(table, meta, families, gold_by_id)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
