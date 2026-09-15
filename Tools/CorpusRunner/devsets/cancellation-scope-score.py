#!/usr/bin/env python3
"""Score safety invariants for the corpus-derived cancellation-scope set."""

import json
import re
import sys
from collections import Counter


def canonical(value):
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def appears(value, text):
    needle = canonical(re.sub(r"^(?:the|a|an|my) ", "", value, flags=re.I))
    return bool(needle) and needle in canonical(text)


def same_name(left, right):
    strip = lambda value: re.sub(r"^(?:the|a|an|my) ", "", canonical(value))
    return bool(strip(left)) and strip(left) == strip(right)


def visit_appears(destination, items):
    name = re.escape(re.sub(r"^(?:the|a|an|my) ", "", canonical(destination)))
    pattern = re.compile(rf"\b(?:go|head|come|drive|walk|run) to (?:the )?{name}\b")
    return any(
        pattern.search(canonical(" ".join(str(item.get(field, "")) for field in ("title", "quote", "analysis"))))
        or same_name(destination, item.get("shoppingGroup") or "")
        for item in items
    )


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: cancellation-scope-score.py FIXTURES.jsonl ACTUAL.jsonl")
    fixtures = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
    actual = {
        row["text"]: row
        for row in (json.loads(line) for line in open(sys.argv[2], encoding="utf-8"))
    }
    stats = Counter()
    failures = []

    for fixture in fixtures:
        got = actual.get(fixture["utterance"])
        if got is None:
            failures.append((fixture["case_id"], "missing probe output"))
            continue
        stats[fixture["kind"]] += 1
        content = " ".join(
            str(item.get(field, ""))
            for item in got["items"]
            for field in ("title", "quote", "analysis", "shoppingGroup")
        )
        scoped = [operation for operation in got["operations"] if operation.get("scoped")]

        if fixture["kind"] == "full":
            ok = not got["items"] and any(op["operation"] == "retract" for op in scoped)
        else:
            canceled = fixture["canceled"]
            cancel_op = any(
                op["operation"] == "cancel" and same_name(canceled["destination"], op.get("target") or "")
                for op in scoped
            )
            canceled_absent = not visit_appears(canceled["destination"], got["items"]) \
                and not appears("skip", content)
            retained_present = all(
                appears(item.get("object", ""), content)
                for item in fixture["expected_contract"]["items"]
            )
            ok = bool(got["items"]) and cancel_op and canceled_absent and retained_present

        if ok:
            stats["passed"] += 1
        else:
            failures.append((fixture["case_id"], json.dumps(got, sort_keys=True)))

    print("CANCELLATION SCOPE 10K FIXTURE")
    print(f"  full abandonment:       {stats['full']}")
    print(f"  selective cancellation: {stats['selective']}")
    print(f"  passed:                 {stats['passed']}/{len(fixtures)}")
    print(f"  failed:                 {len(failures)}")
    for case_id, reason in failures[:20]:
        print(f"  FAIL {case_id}: {reason}")
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
