#!/usr/bin/env python3
"""Strict safety scorer for the saved conditional-intent fixture."""

import json
import sys
from pathlib import Path


def norm(value) -> str:
    return " ".join(str(value or "").lower().split())


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: conditional-intent-score.py fixture.jsonl actual.jsonl")
    expected = [json.loads(x) for x in Path(sys.argv[1]).read_text().splitlines() if x]
    actual = [json.loads(x) for x in Path(sys.argv[2]).read_text().splitlines() if x]
    if len(expected) != len(actual):
        raise SystemExit(f"row count differs: expected {len(expected)}, actual {len(actual)}")

    failures = []
    for source, result in zip(expected, actual):
        items = result.get("items", [])
        condition = norm(source["expected_contract"]["items"][0].get("notes", "")).removeprefix("condition: ")
        consequence = norm(source["expected_contract"]["items"][0].get("object", ""))
        reasons = []
        if len(items) != 1:
            reasons.append(f"item-count={len(items)}")
        else:
            item = items[0]
            visible = norm(" ".join([item.get("analysis", ""), item.get("quote", ""), item.get("title", "")]))
            if condition and condition not in visible:
                reasons.append("condition-lost")
            if consequence and consequence not in visible:
                reasons.append("consequence-lost")
            if item.get("needsReview") is not True:
                reasons.append("not-review")
            if item.get("state") != "unsupported" or item.get("stateGap") != "unsupportedCondition":
                reasons.append("wrong-semantic-state")
            if item.get("unsupportedTrigger") != "condition":
                reasons.append("wrong-trigger")
            if item.get("due") is not None or item.get("reminder") is not None:
                reasons.append("executable-date")
            if item.get("delivery") != "none" or item.get("recurrenceRule") is not None:
                reasons.append("executable-delivery")
        if reasons:
            failures.append((source["case_id"], reasons))

    print("CONDITIONAL INTENT 10K FIXTURE")
    print(f"  passed: {len(expected) - len(failures)}/{len(expected)}")
    print(f"  failed: {len(failures)}")
    for case_id, reasons in failures[:20]:
        print(f"  {case_id}: {', '.join(reasons)}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
