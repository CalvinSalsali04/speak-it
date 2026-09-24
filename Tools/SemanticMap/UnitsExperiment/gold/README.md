# Frozen semantic-unit gold (development evidence, not unseen launch accuracy)

**gold.json sha256 `d8d4a4363c411ae50cfcb8d7b63d9695b6320651e5fa03004db1ba9a006d345c`**, frozen 2026-09-23 before either candidate ran.
30 captures, 83 firm units, 6 shared-scope spans, 11 ambiguous spans. Input: `gold-input/captures.jsonl` sha256 `9c0f500d…d12cfb`.

- `UNIT_DEFINITION.md`: the rules, written and hashed before any transcript was received (`23afc1d5…`).
- `author_gold.py`: the gold as authored, an ordered tiling of each transcript. It emits `gold_spec.json`.
- `build_gold.py`: re-locates every span, rejects overlap, uncovered content words and atoms split between owners, and writes `gold.json`.
- `SHA256SUMS`: hashes of all of the above. `python3 build_gold.py ../gold-input/captures.jsonl gold_spec.json /tmp/g.json && cmp /tmp/g.json gold.json` reproduces it byte for byte.

## Reading gold.json

Per capture: `units` (ordered code-point ranges plus covered text; `gloss` is not scored), `filler`, `shared` (one span, several owning units), and `ambiguous` (admissible owners: unit indices, `"own"` for a unit of its own, or `"filler"`), each with a reason. `atom_view` is the same answer projected onto the whitespace atoms (`transcript.split()`), in the shape the experiment thread asked for. It is derived from the offsets, not authored separately, and the build fails if any atom would be split between two owners.

## Families

Assigned by the author from structure, possibly several per capture. The "dropped intention" and "correct complex control" buckets are not assigned here: they depend on past system behaviour this author deliberately did not see, so the experiment thread supplies them.

## Frozen

Never edited after freezing. A correction goes in a new file with its own hash and a reason.
