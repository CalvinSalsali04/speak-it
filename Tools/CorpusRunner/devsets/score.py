#!/usr/bin/env python3
"""Scores a clause-segmentation development set.

Compares `probe --clauses` output against the expected segmentation, ignoring
cosmetic differences (case, surrounding punctuation) so the number reported is
about where the boundaries fell and nothing else.

    ./Tools/CorpusRunner/devsets/score.sh coordination
    ./Tools/CorpusRunner/devsets/score.sh coordination --verbose
"""
import re
import sys
from collections import OrderedDict


def canonical(clause: str) -> str:
    """Case- and punctuation-insensitive form of one clause."""
    text = clause.strip().lower()
    text = re.sub(r"[‘’]", "'", text)
    text = re.sub(r"[^a-z0-9' ]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def segmentation(value: str) -> list:
    return [c for c in (canonical(p) for p in value.split("|")) if c]


def load_expected(path):
    rows = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 4 or fields[0] == "id":
                continue
            rows.append({
                "id": fields[0],
                "utterance": fields[1],
                "expected": fields[2],
                "family": fields[3],
            })
    return rows


def load_actual(path):
    actual = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or "\t" not in line:
                continue
            utterance, clauses = line.split("\t", 1)
            actual[utterance.strip()] = clauses
    return actual


def main():
    expected_path, actual_path = sys.argv[1], sys.argv[2]
    verbose = "--verbose" in sys.argv[3:]

    rows = load_expected(expected_path)
    actual = load_actual(actual_path)

    families = OrderedDict()
    failures = []
    for row in rows:
        got_raw = actual.get(row["utterance"])
        want = segmentation(row["expected"])
        got = segmentation(got_raw) if got_raw is not None else None

        stats = families.setdefault(row["family"], {"cases": 0, "fail": 0,
                                                    "over": 0, "under": 0})
        stats["cases"] += 1
        if got == want:
            continue

        stats["fail"] += 1
        # Over-split: more boundaries than the reader expected. Under-split:
        # fewer. They are different defects — one invents rows, the other
        # buries a thought inside another one — so they are counted apart.
        kind = "wrong"
        if got is not None:
            if len(got) > len(want):
                stats["over"] += 1
                kind = "over-split"
            elif len(got) < len(want):
                stats["under"] += 1
                kind = "under-split"
        failures.append((row, got_raw, kind))

    total = len(rows)
    failed = len(failures)
    print(f"CLAUSE SEGMENTATION — {expected_path.rsplit('/', 1)[-1]}")
    print("=" * 74)
    print(f"{'FAMILY':<28}{'CASES':>7}{'FAIL':>7}{'OVER':>7}{'UNDER':>7}")
    print("-" * 74)
    for family, stats in sorted(families.items(), key=lambda kv: -kv[1]["fail"]):
        print(f"{family:<28}{stats['cases']:>7}{stats['fail']:>7}"
              f"{stats['over']:>7}{stats['under']:>7}")
    print("-" * 74)
    print(f"TOTAL {total} cases, {failed} failing, {total - failed} correct "
          f"({100.0 * (total - failed) / total:.1f}%)")

    if verbose and failures:
        print()
        for row, got_raw, kind in failures:
            print(f"[{row['id']}] {kind}  ({row['family']})")
            print(f"   said:  {row['utterance']}")
            print(f"   want:  {row['expected']}")
            print(f"   got:   {got_raw if got_raw is not None else '(no output)'}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
