#!/usr/bin/env python3
"""Freeze the experiment's model input: each capture's atoms and candidate 2's
clause lines, from the transcript-only gold input.

    make_inputs.py captures.jsonl > inputs.jsonl

Prints nothing but the inputs; the probe re-atomizes every transcript and
refuses the whole run if a single atom or line differs.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clause_lines  # noqa: E402

for raw in open(sys.argv[1], encoding="utf-8"):
    if not raw.strip():
        continue
    record = json.loads(raw)
    atoms = record["transcript"].split()
    if atoms != record["atoms"]:
        sys.exit(f"{record['id']}: atoms do not match a whitespace split of the transcript")
    print(json.dumps({"id": record["id"], "transcript": record["transcript"], "atoms": atoms,
                      "lines": clause_lines.lines(atoms)}, ensure_ascii=False))
