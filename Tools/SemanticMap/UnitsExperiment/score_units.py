#!/usr/bin/env python3
"""Scores the semantic-unit experiment: whole-capture unit recovery against the
frozen gold, for both candidates, the free reference arms and two constant
baselines.

    score_units.py precheck --gold gold/gold.json --inputs inputs.jsonl
    score_units.py score    --gold gold/gold.json --inputs inputs.jsonl [--results results.jsonl]
                            [--reference DIAG_FOLDER] [--families families.json]
    score_units.py selftest

precheck  NO MODEL. Whether each candidate CAN express each gold answer:
          constructs the best answer the representation allows and scores it
          with the same scorer, so "representable" and "scores exact" cannot
          drift apart. Run this before any generation is read.
score     Every capture, every arm: EXACT or the failure classes, per family,
          per-unit boundary precision and recall, latency and tokens.
          Without --results only the free arms are scored. The constant
          baselines (`one-unit`, `every-line`) cost nothing and a candidate
          must beat both. `--reference` adds the rules rows, the recorded
          split-index units job and the recorded production whole-list
          answer from the diagnostic run's folder.

Prints capture ids, counts and closed-vocabulary classes only: no capture text.

GOLD (gold/gold.json, frozen by an independent author; see gold/README.md).
Per capture `atom_view` holds `units` (atom ranges), `filler` (free anywhere
or nowhere), `shared` (a span several units own) and `ambiguous` (a span with
admissible owners: a 1-based unit index, "own" for a unit of its own, or
"filler"). Both arms return non-overlapping units, so a shared span must sit
whole in ONE of its owners, and an ambiguous span whole under one admissible
reading. Each combination is a READING; an answer is scored under the reading
that treats it best. Two views are reported:
    any   every admissible owner is accepted (the author's rule)
    own   an ambiguous span that may be its own unit must be its own unit
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


def readings(entry, atom_count, view="any"):
    """Every concrete gold the frozen entry admits, as `Gold` objects with no
    ambiguity left: each shared span given whole to one owner, each ambiguous
    span given whole to one admissible owner, a unit of its own, or filler."""
    import itertools
    view_ = entry["atom_view"]
    firm = []
    for unit in view_["units"]:
        atoms = set()
        for first, last in unit["ranges"]:
            atoms.update(range(first, last + 1))
        firm.append(atoms)
    choices = []
    for span in view_["shared"]:
        choices.append([(tuple(span["atoms"]), ("unit", owner - 1)) for owner in span["units"]])
    for span in view_["ambiguous"]:
        options = []
        for owner in span["units"]:
            if owner == "own":
                options.append((tuple(span["atoms"]), ("own",)))
            elif owner == "filler":
                options.append((tuple(span["atoms"]), ("filler",)))
            else:
                options.append((tuple(span["atoms"]), ("unit", owner - 1)))
        if view == "own" and "own" in span["units"]:
            options = [o for o in options if o[1] == ("own",)]
        choices.append(options)
    out, seen = [], set()
    for combo in itertools.product(*choices) if choices else [()]:
        units = [set(u) for u in firm]
        filler = set(view_["filler"])
        for atoms, (kind, *rest) in combo:
            if kind == "unit":
                units[rest[0]].update(atoms)
            elif kind == "own":
                units.append(set(atoms))
            else:
                filler.update(atoms)
        units.sort(key=min)
        key = (tuple(tuple(sorted(u)) for u in units), tuple(sorted(filler)))
        if key in seen:
            continue
        seen.add(key)
        record = {"id": entry["id"], "units": [{"ranges": [[a, a] for a in sorted(u)]} for u in units],
                  "filler": sorted(filler), "ambiguous": []}
        out.append(Gold(record, atom_count))
    return out


def load_gold(path, counts, view="any"):
    frozen = json.loads(Path(path).read_text(encoding="utf-8"))
    return {entry["id"]: readings(entry, counts[entry["id"]], view)
            for entry in frozen["captures"] if entry["id"] in counts}


# Across readings the answer is judged under the reading that treats it best.
SEVERITY = ["exact", "wrong-boundaries", "under-split", "over-split", "absorbed",
            "filler-only", "dropped", "capacity", "representation", "malformed"]


def interleaved(gold):
    """True when some gold unit's content lies inside another's extent, as
    when a shared preamble is given to a later owner."""
    return any(not gap for gap in gold.gaps())


def best_reading(golds, judge):
    """judge(gold) -> (class, flags, ...). Returns (gold, result) for the least
    severe result; on a tie a reading whose units do not interleave, then the
    first."""
    best, best_key = None, None
    for gold in golds:
        result = judge(gold)
        key = (SEVERITY.index(result[0]), interleaved(gold))
        if best is None or key < best_key:
            best, best_key = (gold, result), key
    return best


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


def boundary_hits(gold, units):
    """For each gold boundary in order, 1 when some proposed cut falls inside it."""
    gaps = gold.gaps()
    nonempty = [u for u in units if u]
    cuts = [(max(a), min(b)) for a, b in zip(nonempty, nonempty[1:])]
    return [int(any(left in gap or any(p in gap for p in range(left, right)) for left, right in cuts)) for gap in gaps]


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


def representable(golds, builder):
    """(True, None) when the arm can express some admissible reading exactly,
    else (False, the distinct reasons across readings)."""
    reasons = []
    for gold in golds:
        units, reason = builder(gold)
        if reason is None and classify(gold, units)[0] == "exact":
            return True, None
        why = reason or "does not score exact"
        if why not in reasons:
            reasons.append(why)
    return False, reasons


def unit_count(golds):
    counts = sorted({len(g.units) for g in golds})
    return str(counts[0]) if len(counts) == 1 else f"{counts[0]}-{counts[-1]}"


def precheck(golds_by_id, inputs):
    rows = []
    for item in inputs:
        golds = golds_by_id[item["id"]]
        r_ok, r_why = representable(golds, best_ranges)
        l_ok, l_why = representable(golds, lambda g: best_labels(g, item["lines"]))
        rows.append((item["id"], unit_count(golds), len(item["lines"]),
                     "representable" if r_ok else "; ".join(r_why),
                     "representable" if l_ok else "; ".join(l_why)))
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
    strict (a model's quote): it must appear verbatim, or the whole answer is
    None, since an unplaceable model quote is authored text. Otherwise (a
    rules quote) an in-order subsequence is accepted. None when nothing is
    placed."""
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
        span = (found, found + len(needle) - 1) if found is not None else None
        if span is None and not strict and needle:
            # A rules quote is the source with words removed (fillers, the
            # operation phrase), never invented: place it as the in-order
            # subsequence it is, from its first matched atom to its last.
            placed, at = [], cursor
            for word in needle:
                while at < len(hay) and hay[at] != word:
                    at += 1
                if at == len(hay):
                    break
                placed.append(at)
                at += 1
            if len(placed) == len(needle):
                span = (placed[0], placed[-1])
        if span is None:
            if strict:
                return None
            continue
        units.append(set(range(span[0], span[1] + 1)))
        cursor = span[1] + 1
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

MODEL_ARMS = ("ranges", "labels")
FREE_ARMS = ("one-unit", "every-line", "rules", "units-job", "whole-list")


def model_units(arm, record, item):
    job = record["job"]
    n, lines = len(item["atoms"]), item["lines"]
    if arm == "labels" and job.get("outcome") == "skipped" and job.get("skip") == "tooShortToSplit":
        return whole_from_lines(lines)
    if job.get("outcome") != "accepted" or not record.get("raw"):
        return None
    return ranges_units(record["raw"], n) if arm == "ranges" else labels_units(record["raw"], lines)


def score_run(golds_by_id, inputs, results, reference):
    """One row per capture: arm -> (class, flags, units, the reading judged)."""
    by_arm = defaultdict(dict)
    for record in results:
        by_arm[record["arm"]][record["id"]] = record
    table, meta = [], defaultdict(dict)
    for position, item in enumerate(inputs):
        cid, lines = item["id"], item["lines"]
        golds = golds_by_id[cid]
        row = {"id": cid, "gold": unit_count(golds), "position": position}
        for arm in MODEL_ARMS:
            record = by_arm[arm].get(cid)
            if record is None:
                continue
            units = model_units(arm, record, item)
            builder = best_ranges if arm == "ranges" else (lambda g: best_labels(g, lines))
            cap = RANGES_CAP if arm == "ranges" else None

            def judge(gold, units=units, builder=builder, cap=cap):
                _, reason = builder(gold)
                return classify(gold, units, cap=cap,
                                representable=reason is None or reason.startswith("capacity"))
            gold, result = best_reading(golds, judge)
            row[arm] = result + (units, gold)
            meta[arm][cid] = record
        free = {"one-unit": whole_from_lines(lines),
                "every-line": [set(range(first, last + 1)) for first, last in lines]}
        free.update(reference.get(cid) or {})
        for arm, units in free.items():
            gold, result = best_reading(golds, lambda g, units=units: classify(g, units))
            row[arm] = result + (units, gold)
        table.append(row)
    return table, meta


def pct(values, q):
    values = sorted(v for v in values if v is not None)
    if not values:
        return "-"
    return values[min(len(values) - 1, int(round(q * (len(values) - 1))))]


def arms_in(table):
    return [a for a in MODEL_ARMS + FREE_ARMS if any(a in row for row in table)]


def exact_line(table, arm, ids=None):
    rows = [r for r in table if arm in r and (ids is None or r["id"] in ids)]
    exact = sum(1 for r in rows if r[arm][0] == "exact")
    counts = Counter(r[arm][0] for r in rows)
    return f"exact {exact}/{len(rows)}   " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items()) if k != "exact")


def degenerate(arm, units, lines):
    """Answers with a shape that ignores the content: named, not scored."""
    if units is None:
        return None
    if arm == "labels":
        if len(lines) >= 2 and len(units) == 1:
            return "all continues"
        if len(lines) >= 2 and len(units) == len(lines):
            return "all starts"
        if len(lines) >= 4 and all(len(u) and sum(1 for f, l in lines if f in u) == 2 for u in units[:-1]):
            return "alternating"
        return None
    if len(units) == 1:
        return "one thought"
    widths = [max(u) - min(u) + 1 for u in units]
    if len(units) >= 3 and len(set(widths)) == 1:
        return f"fixed stride {widths[0]}"
    return None


def multi_ids(golds_by_id):
    return {cid for cid, golds in golds_by_id.items() if min(len(g.units) for g in golds) >= 2}


def report(table, own_table, meta, families, golds_by_id, inputs, reference_ids, own_golds):
    arms = arms_in(table)
    width = 17
    print("WHOLE-CAPTURE RESULT, view `any` (primary class; + when there are more flags)")
    print("id".ljust(8) + "gold".rjust(6) + "".join(a.rjust(width) for a in arms))
    for row in table:
        cells = []
        for arm in arms:
            if arm not in row:
                cells.append("n/a".rjust(width))
                continue
            cls, flags = row[arm][0], row[arm][1]
            cells.append((cls + ("+" if len(flags) > 1 else "")).rjust(width))
        print(row["id"].ljust(8) + row["gold"].rjust(6) + "".join(cells))
    for name, source in (("any", table), ("own", own_table)):
        print()
        print(f"EXACT, view `{name}`")
        for arm in arms:
            print(f"  {arm:12} {exact_line(source, arm)}")
    for name, source, golds in (("any", table, golds_by_id), ("own", own_table, own_golds)):
        multi = multi_ids(golds)
        print()
        print(f"EXACT WHERE GOLD HAS >=2 UNITS, view `{name}` ({len(multi)} captures: no admissible reading is one unit)")
        for arm in arms:
            print(f"  {arm:12} {exact_line(source, arm, multi)}")
    print()
    print("EVERY CLASS, view `any`: captures by primary class / captures carrying the class at all")
    print("(an answer can carry several: an over-split that also drops an atom is primarily dropped)")
    print("class".ljust(18) + "".join(a.rjust(12) for a in arms))
    for cls in CLASSES:
        print(cls.ljust(18) + "".join(
            f"{sum(1 for r in table if arm in r and r[arm][0] == cls)}/{sum(1 for r in table if arm in r and cls in r[arm][1])}".rjust(12)
            for arm in arms))
    if reference_ids:
        print()
        print(f"EXACT ON THE {len(reference_ids)} DIAGNOSTIC CAPTURES (the only ones the recorded arms cover), view `any`")
        for arm in arms:
            print(f"  {arm:12} {exact_line(table, arm, reference_ids)}")
    print()
    print("BOUNDARY PRECISION / RECALL, view `any` (pooled; judged against the reading chosen for the capture)")
    for arm in arms:
        mp = pp = mg = gg = 0
        for r in table:
            if arm not in r:
                continue
            a, b, c, d = boundary_counts(r[arm][3], r[arm][2])
            mp, pp, mg, gg = mp + a, pp + b, mg + c, gg + d
        print(f"  {arm:12} precision {mp}/{pp}   recall {mg}/{gg}")
    if families:
        names = sorted({f for fs in families.values() for f in fs})
        for name, source in (("any", table), ("own", own_table)):
            print()
            print(f"PER FAMILY, exact / captures, view `{name}`")
            print("family".ljust(26) + "".join(a.rjust(12) for a in arms))
            for family in names:
                ids = [r for r in source if family in families.get(r["id"], [])]
                cells = []
                for arm in arms:
                    rows = [r for r in ids if arm in r]
                    cells.append(f"{sum(1 for r in rows if r[arm][0] == 'exact')}/{len(rows)}".rjust(12))
                print(family.ljust(26) + "".join(cells))
    print()
    print("UNCOVERED SOURCE, view `any`: capture (content atoms in no unit / whole gold units among them).")
    print("Recorded, never discarded. A partial loss of 1-2 atoms between two rows of one unit is usually a")
    print("connective left between an over-split's pieces; the primary class still says dropped.")
    for arm in arms:
        rows = []
        for r in table:
            if arm not in r or r[arm][2] is None:
                continue
            gold = r[arm][3]
            lost = gold.content - set().union(*r[arm][2])
            if lost:
                rows.append(f"{r['id']} ({len(lost)}/{sum(1 for u in gold.units if u <= lost)})")
        print(f"  {arm:12} {len(rows)}: " + (", ".join(rows) or "none"))
    lines_by_id = {item["id"]: item["lines"] for item in inputs}
    model = [a for a in MODEL_ARMS if meta[a]]
    if not model:
        print()
        print("MODEL ARMS: no results given; only the free arms are scored.")
        return
    print()
    print("SHAPE (named, not scored): non-exact answers whose shape ignores the content. `on multi` counts")
    print("captures where no admissible reading has a single unit, so the shape cannot be right there.")
    for arm in model:
        shapes, on_multi = Counter(), Counter()
        one_word = 0
        for r in table:
            if arm not in r:
                continue
            shape = degenerate(arm, r[arm][2], lines_by_id[r["id"]]) if r[arm][0] != "exact" else None
            if shape:
                shapes[shape] += 1
                if min(len(g.units) for g in golds_by_id[r["id"]]) > 1:
                    on_multi[shape] += 1
            one_word += sum(1 for u in (r[arm][2] or []) if len(u) == 1)
        print(f"  {arm:8} " + (", ".join(f"{k} {v} (on multi {on_multi[k]})" for k, v in sorted(shapes.items()))
                               or "no degenerate shape") + f"; one-atom units {one_word}")
    print()
    print("WHERE INSIDE THE CAPTURE ANSWERS GO WRONG (report only): for non-exact, well-formed answers, the")
    print("index of the first unit that departs from gold; and gold boundary recall by boundary index.")
    for arm in model:
        first = Counter()
        hits, totals = Counter(), Counter()
        for r in table:
            if arm not in r or r[arm][2] is None:
                continue
            gold, units = r[arm][3], r[arm][2]
            if r[arm][0] != "exact":
                content = [u & gold.content for u in units if u & gold.content]
                index = next((k for k, u in enumerate(gold.units) if k >= len(content) or content[k] != u),
                             len(gold.units))
                first[min(index, 5)] += 1
            for g, hit in enumerate(boundary_hits(gold, units)):
                totals[min(g, 5)] += 1
                hits[min(g, 5)] += hit
        label = lambda k: f"{k + 1}" if k < 5 else "6+"
        print(f"  {arm:8} first departing unit: " + (", ".join(f"unit {label(k)} {v}" for k, v in sorted(first.items())) or "none"))
        print(f"  {arm:8} boundary recall: " + ", ".join(f"boundary {label(k)} {hits[k]}/{totals[k]}" for k in sorted(totals)))
    print()
    print("MALFORMED OR REFUSED BY POSITION (run order, and which arm went first)")
    for arm in model:
        records = meta[arm]
        thirds = Counter()
        firsts = Counter()
        for r in table:
            if arm not in r:
                continue
            bad = r[arm][0] == "malformed"
            third = ("early", "middle", "late")[min(2, r["position"] * 3 // len(table))]
            thirds[(third, bad)] += 1
            firsts[(records[r["id"]]["order"], bad)] += 1
        print(f"  {arm:8} " + "  ".join(f"{t} {thirds[(t, True)]}/{thirds[(t, True)] + thirds[(t, False)]}"
                                         for t in ("early", "middle", "late"))
              + "   " + "  ".join(f"{'first' if o == 0 else 'second'} {firsts[(o, True)]}/{firsts[(o, True)] + firsts[(o, False)]}"
                                  for o in (0, 1)))
    print()
    print("LATENCY AND TOKENS (model arms; skipped jobs excluded)")
    for arm in model:
        jobs = [rec["job"] for rec in meta[arm].values() if rec["job"].get("outcome") != "skipped"]
        lat = [j.get("latencyMilliseconds") for j in jobs]
        out = [j.get("responseTokens") for j in jobs]
        inp = [(j.get("promptTokens") or 0) + (j.get("instructionTokens") or 0) + (j.get("schemaTokens") or 0)
               for j in jobs if j.get("promptTokens") is not None]
        outcomes = Counter(rec["job"].get("outcome") for rec in meta[arm].values())
        prints = sorted({rec["promptFingerprint"] for rec in meta[arm].values()})
        print(f"  {arm:8} prompt {','.join(prints)}  asked {len(jobs)}  outcomes {dict(outcomes)}")
        print(f"           latency ms p50 {pct(lat, .5)} p90 {pct(lat, .9)} max {pct(lat, 1)}"
              f"   response tokens p50 {pct(out, .5)} max {pct(out, 1)}   input tokens p50 {pct(inp, .5)} max {pct(inp, 1)}")
    print()
    print("CAPACITY")
    for r in table:
        if int(r["gold"].split("-")[-1]) > RANGES_CAP:
            print(f"  {r['id']} gold {r['gold']} units, ranges cap {RANGES_CAP}: "
                  + ", ".join(f"{arm} {r[arm][0]}" for arm in model if arm in r))
    print()
    print("STRUCTURALLY SATISFIED, NOT MEASURED")
    print("  labels: in bounds, ordered, no overlap and full coverage hold by construction (a partition of the")
    print("          clause lines); an out-of-order or duplicate line number is decoded as malformed.")
    print("  ranges: in bounds by the schema's range guides; order, overlap and coverage ARE measured here")
    print("          (unordered or overlapping -> malformed; uncovered content -> dropped, listed above).")
    print("  both:   no title, wording, date, person, operation or reminder can be returned: no string field.")


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

    # Readings of the frozen gold's shape: shared and ambiguous spans.
    def entry(units, filler=(), shared=(), ambiguous=()):
        return {"id": "e", "atom_view": {"units": [{"ranges": r} for r in units], "filler": list(filler),
                                         "shared": list(shared), "ambiguous": list(ambiguous)}}

    def judged(golds, units):
        return best_reading(golds, lambda gold: classify(gold, units))[1][0]
    own = entry([[[3, 5]]], ambiguous=[{"atoms": [0, 1, 2], "units": ["own", 1]}])
    check("own-or-joined: one unit, view any", judged(readings(own, 6), [set(range(6))]), "exact")
    check("own-or-joined: two units, view any", judged(readings(own, 6), [{0, 1, 2}, {3, 4, 5}]), "exact")
    check("own-or-joined: one unit, view own", judged(readings(own, 6, "own"), [set(range(6))]), "under-split")
    check("own-or-joined: two units, view own", judged(readings(own, 6, "own"), [{0, 1, 2}, {3, 4, 5}]), "exact")
    check("own-or-joined: span split", judged(readings(own, 6), [{0}, {1, 2, 3, 4, 5}]), "over-split")
    check("own-or-joined: span dropped", judged(readings(own, 6), [{3, 4, 5}]), "dropped")
    hedge = entry([[[0, 1]], [[2, 3]]], ambiguous=[{"atoms": [4], "units": [2, "filler"]}])
    check("unit-or-filler: left out", judged(readings(hedge, 5), [{0, 1}, {2, 3}]), "exact")
    check("unit-or-filler: in its unit", judged(readings(hedge, 5), [{0, 1}, {2, 3, 4}]), "exact")
    check("unit-or-filler: alone is cut from its unit", judged(readings(hedge, 5), [{0, 1}, {2, 3}, {4}]), "over-split")
    shared = entry([[[2, 3]], [[4, 5]]], shared=[{"atoms": [0, 1], "units": [1, 2]}])
    check("shared with its first owner", judged(readings(shared, 6), [{0, 1, 2, 3}, {4, 5}]), "exact")
    check("shared split between owners", judged(readings(shared, 6), [{0, 2, 3}, {1, 4, 5}]) != "exact", True)
    check("shared dropped", judged(readings(shared, 6), [{2, 3}, {4, 5}]), "dropped")
    gold_other = readings(shared, 6)
    check("shared given to its second owner is a discontinuous range answer",
          sorted(r for g in gold_other for r in [best_ranges(g)[1]] if r), ["discontinuous: another unit's content lies inside this unit's span"])
    check("labels decode rejects out-of-order lines",
          labels_units('{"lines":[{"line":1,"label":"starts"},{"line":0,"label":"starts"}]}', [[0, 1], [2, 3]]), None)
    check("labels decode rejects a duplicate line",
          labels_units('{"lines":[{"line":0,"label":"starts"},{"line":0,"label":"starts"}]}', [[0, 1], [2, 3]]), None)

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
    golds_by_id = load_gold(options["gold"], counts, "any")
    own_by_id = load_gold(options["gold"], counts, "own")
    missing = [i for i in counts if i not in golds_by_id]
    if missing:
        print(f"no gold for {len(missing)} capture(s): {', '.join(missing)}")
        return 2
    print(f"gold    {sha256(options['gold'])}")
    print(f"inputs  {sha256(options['inputs'])}")
    if command == "precheck":
        for name, source in (("any", golds_by_id), ("own", own_by_id)):
            rows = precheck(source, inputs)
            print()
            print(f"REPRESENTABILITY, view `{name}` (no model)")
            print("id".ljust(8) + "gold".rjust(6) + "lines".rjust(6) + "  " + "candidate 1 (ranges)".ljust(44) + "candidate 2 (labels)")
            for cid, g, l, r, c in rows:
                print(cid.ljust(8) + g.rjust(6) + str(l).rjust(6) + "  " + r.ljust(44) + c)
            print(f"candidate 1 representable {sum(r[3] == 'representable' for r in rows)}/{len(rows)}; "
                  f"candidate 2 representable {sum(r[4] == 'representable' for r in rows)}/{len(rows)}")
        return 0
    if command == "score":
        results = read_jsonl(options["results"]) if options.get("results") else []
        print(f"results {sha256(options['results']) if options.get('results') else 'none (free arms only)'}")
        reference = reference_arms(options["reference"], inputs, golds_by_id) if options.get("reference") else {}
        families = json.loads(Path(options["families"]).read_text()) if options.get("families") else {}
        table, meta = score_run(golds_by_id, inputs, results, reference)
        own_table, _ = score_run(own_by_id, inputs, results, reference)
        report(table, own_table, meta, families, golds_by_id, inputs, set(reference), own_by_id)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
