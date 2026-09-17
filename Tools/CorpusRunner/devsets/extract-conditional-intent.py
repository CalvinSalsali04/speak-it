#!/usr/bin/env python3
"""Extract the immutable 72 conditional failures from a saved 10K result."""

import argparse
import json
import re
from pathlib import Path


def selected(row: dict) -> bool:
    return (
        row.get("priority") == "P0"
        and row.get("unsafe_positive_action") is True
        and "conditional_intent_failure" in row.get("mismatch_dimensions", [])
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("results", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    rows = [json.loads(line) for line in args.results.read_text().splitlines() if line.strip()]
    rows = [row for row in rows if selected(row)]
    assert len(rows) == 72, f"expected 72 conditional failures, found {len(rows)}"
    for row in rows:
        assert row["structure_id"] == "safety.13"
        assert row["semantic_family"] == "safety.conditional_intent"
        assert row["phenomena"] == ["conditional_intent", "safety_critical"]
        assert row["expected_item_count"] == 1 and row["actual_item_count"] == 2
        assert re.fullmatch(
            r"If [A-Za-z]+ replies, then remind me to buy .+\.", row["utterance"]
        ), row["utterance"]

    args.output.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows))
    print(f"wrote {len(rows)} immutable cases to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
