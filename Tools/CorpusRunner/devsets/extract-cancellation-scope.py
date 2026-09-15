#!/usr/bin/env python3
"""Extract the immutable 187 cancellation-scope cases from saved 10K results."""

import json
import re
import sys


SELECTIVE_STRUCTURES = {
    "multi.2.8", "multi.3.8", "multi.4.8", "multi.5.8",
    "long.3.2", "long.4.2", "long.5.2",
}


def canonical(value):
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def visits(utterance):
    pattern = re.compile(
        r"\bgo to (.+?) and (pick up|get|buy|return) (.+?)"
        r"(?= and go to|,? actually (?:skip|forget)|$)",
        re.IGNORECASE,
    )
    return [
        {"destination": match.group(1), "action": match.group(2), "object": match.group(3)}
        for match in pattern.finditer(utterance.rstrip("."))
    ]


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: extract-cancellation-scope.py RESULTS.jsonl OUTPUT.jsonl")
    selected = []
    with open(sys.argv[1], encoding="utf-8") as source:
        for line in source:
            row = json.loads(line)
            full = row["semantic_family"] == "correction.full_abandonment"
            selective = row["structure_id"] in SELECTIVE_STRUCTURES
            if row["priority"] != "P0" or not (full or selective):
                continue

            groups = visits(row["utterance"])
            if full:
                assert len(groups) == 1, row["case_id"]
                kind = "full"
                canceled = groups[0]
            else:
                target_match = re.search(
                    r"actually skip (?:the )?(.+?)\.?$", row["utterance"], re.IGNORECASE
                )
                assert target_match, row["case_id"]
                target = canonical(target_match.group(1))
                matches = [
                    group for group in groups
                    if canonical(re.sub(r"^(?:the|a|an|my) ", "", group["destination"], flags=re.I))
                    == target
                ]
                assert len(matches) == 1, (row["case_id"], groups, target)
                kind = "selective"
                canceled = matches[0]

            selected.append({
                "case_id": row["case_id"],
                "kind": kind,
                "structure_id": row["structure_id"],
                "utterance": row["utterance"],
                "canceled": canceled,
                "expected_contract": row["expected_contract"],
            })

    assert len(selected) == 187, len(selected)
    assert sum(row["kind"] == "full" for row in selected) == 126
    assert sum(row["kind"] == "selective" for row in selected) == 61
    with open(sys.argv[2], "w", encoding="utf-8") as destination:
        for row in selected:
            destination.write(json.dumps(row, sort_keys=True, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
