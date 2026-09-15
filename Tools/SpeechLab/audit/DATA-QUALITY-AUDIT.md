# SpeechLab data-quality audit

Date: 2026-09-13
Scope: measurement system only; no production parser changes; no sealed content read.

## Verdict

**Scaling decision: A — stay below 1,000 until data quality improves.**

SpeechLab's storage, provenance, identity, resumability, and failure-retention
infrastructure are useful. Its current synthetic language is not yet a
trustworthy correctness benchmark or a sound substrate for 10,000+ cases.
There are genuine semantic distinctions, but the advertised 260 families come
from a perfectly even 26-archetype × 10-context construction; the language is
mostly rendered by copying canonical facts into a small set of forms. The
original set contains no multi-phenomenon case, and 12 of 57 variants marked as
meaning-preserving changed the intended contract in this assistant audit.

The right next target is **about 800 adjudicated renderings**, not 10,000. A
carefully reviewed 800 would teach more than millions of repetitions of the
current generator.

## Methodology

- Measured all 260 blueprints and all 324 current renderings.
- Reviewed all 64 phenomenon variants plus 40 SHA-256-selected base renderings
  (104-case stratified assistant audit). These are audit judgements, not an
  independent human gold standard.
- Computed exact/normalized duplicates, token-set Jaccard near duplicates,
  value-agnostic semantic shapes, structural surface templates, family balance,
  word lengths, fact-copying, difficulty, and phenomenon interaction counts.
- Generated three candidate realizations for each of the 50 exported
  blueprints; ran the existing import validator; evaluated the 472-row combined
  set only to populate review records. Parser output was never used as a label.
- Built a 400-row non-sealed human-review set containing all 64 phenomena, 50
  safety-critical rows, 95 multi-phenomenon rows, 218 families, failures,
  suspicious examples, unusual item counts, and 202 hash-random fill rows.
- Verified public-data claims against upstream project pages; downloaded no
  corpus and inspected no sealed case.

Full measurements are in `data-quality-metrics.json` and the reviewed sample is
in `manual-stratified-sample.jsonl`.

## Quantitative findings

### Current 324-rendering corpus

| Measure | Result |
|---|---:|
| Exact unique strings | 324 / 324 |
| Normalized duplicate groups / records | 3 / 9 |
| Token-Jaccard ≥0.80 near-duplicate pairs | 77 |
| Records participating in a lexical near duplicate | 66 / 324 (20.4%) |
| Cross-blueprint near-duplicate pairs | 20 |
| Structural surface templates after slot replacement | 134 |
| Largest structural template | 25 rows (7.7%) |
| Value-agnostic expected semantic shapes | 133 |
| Renderings containing every expected fact verbatim | 314 / 324 (96.9%) |
| No phenomena | 260 / 324 (80.2%) |
| Exactly one phenomenon | 64 / 324 (19.8%) |
| Two or more phenomena | 0 |
| Basic clean, single-item, act-policy cases | 180 / 324 (55.6%) |
| Word length | 4–48, median 15, mean 16.7 |

The 260 blueprint IDs are semantically hash-distinct, but “family” overstates
their independence: there are 26 top-level archetypes, each repeated exactly 10
times, and 10 overlays, each repeated exactly 26 times. Once literal values are
ignored, 260 blueprints collapse to 133 structured shapes.

Entity and temporal variety is narrow: six person values, one location (`Farm
Boy`), five dates, five times, one recurrence (`weekly:tuesday`), and one
operation (`cancel`). There is no actual `shopping` item type despite oat-milk
language, and no `personFollowUp` item. Ten examples per archetype is generator
convenience, not evidence of a realistic usage distribution.

### Stratified naturalness and semantic review

Among the 104 reviewed cases:

- 24 were plausible spoken language;
- 57 were plausible but conspicuously synthetic;
- 23 were implausible or broken;
- 85 appeared contract-preserving;
- 12 changed the contracted meaning;
- 7 were already marked uncertain.

Of the 57 variants labelled `reviewed` meaning-preserving, 12 (21.1%) failed
the assistant semantic check, leaving an apparent preservation rate of 78.9%.
Human adjudication may revise individual calls, but that error rate is already
too high for scale.

### Good current examples

- `rd-6373e84a54a6091be7c3fb71`: “Send the, uh, project update for the core
  project.” A compact, believable hesitation.
- `rd-07bc54aae85101b47e3cc763`: “Send the project update … because this whole
  week has been a bit chaotic…” A plausible trailing explanation.
- `rd-68387f0ec0346ca6bfeac981`: “One, buy oat milk. Two, call Maya about dinner.”
  A clear spoken list with two actions.
- `rd-90da97909e306cb613208755`: a 48-word preamble before the actual capture. It
  is authored, but exercises long irrelevant lead-in better than the base set.

### Bad or misleading current examples

- `rd-c1257996f9e1c59b05be9303`: “Do not Do not send…” duplicates prohibition.
- `rd-2b97cb69b95349d575dd6474`: says “Tomorrow” and later “Fri Aug 7”; these are
  different dates from the fixed Monday reference.
- `rd-8cb41a36b32bf217d1047d0c`: invents “the same document” for buying milk and
  calling Maya.
- `rd-8a0d1ae4729cc14800474a9e`: repeats Farm Boy and invents Oatly, neither
  represented correctly in the expected contract.
- `rd-154c3459c1e8f3abc80f2f7f`: tagged `homophone` but contains no homophone.
- `rd-16b1698aaeaba8b47d3ca82d`: adds “in ninety minutes” to a blueprint with no
  temporal value.

Other meaning changes occur in quantity/location correction, pronoun
resolution, reported/quoted speech, conditional intent, past-event, and
location inheritance. The exact list and explanations are in the metrics JSON.

## Linguistic and product realism

The strongest pieces are simple reminders/tasks, direct memories, basic
date/time/location slots, fillers, hesitation, lists, casing/punctuation damage,
and some long/partial captures. The weakest pieces are scoped cancellation,
correction chains, shared context, reported/quoted speech actionability,
conditionality, ambiguity, and ASR substitutions.

Most bases still read like benchmark commands: canonical title plus `with`,
`at`, `on`, and `at` slot appendages. Syntax, information order, clause
embedding, discourse context, and register vary much less than the distinct ID
count suggests. The 96.9% verbatim fact-copy rate also means preservation
metrics reward the renderer's own wording rather than robust semantic recovery.

The taxonomy's 64 entries are a good initial inventory, but they mix semantic
states (completed action), discourse phenomena (false starts), surface damage
(punctuation), corpus length, and ASR errors at one level. They need a hierarchy,
scope rules, empirical weights, and interaction coverage. Important practical
extensions include multi-step correction chains, scoped subtask withdrawal,
cross-turn/deictic context, contact ambiguity, DST/time-zone conflicts, and
measured audio/ASR conditions.

## Label quality and circularity

Expected outputs are not derived from the production parser, so this is not
direct parser-label circularity. However, blueprint creation and rendering are
implemented in the same module, and `render_text` copies authored facts nearly
verbatim. That is strong generator-label coupling. Internal schema validity is
high; product truth is not independently established.

Base labels are useful as draft contracts. They are not trustworthy enough for
an accuracy benchmark until a separate reviewer adjudicates them. Safety,
ambiguity, cancellation, and meaning-changing mutation labels require two-person
review. Synthetic consistency must remain separate from correctness.

## AI candidate generation and import

The 50-blueprint export produced 150 candidates, three per blueprint:

- 148 passed schema/import validation;
- 2 (1.33%) were rejected as exact duplicates of current renderings;
- 0 referenced an invalid blueprint identity;
- 33 (22.3% of accepted candidates) raised lexical-anchor warnings caused by
  genuine paraphrasing of `remember`/`record` facts;
- 21 represented review/preserve-only blueprints, and all 21 explicitly retained
  uncertainty language;
- every accepted candidate remains `meaning_preservation: uncertain`.

The combined set has 95 multi-phenomenon cases (20.1%) and 266 structural text
templates, up from 134. However, near-duplicate participation rises from 20.4%
to 28.8% because each selected blueprint gets a small cluster of related
realizations. More generations do add discourse structures, but naïve
three-per-blueprint expansion also concentrates lexical neighborhoods.

The AI cohort is a review queue, not new gold and not evidence of parser
accuracy. The 472-case run retained every result; its 18 strict passes and 454
failures describe disagreement with draft contracts under a deliberately harsh
metric, not product accuracy.

## Multi-phenomenon conclusion

A compositional layer is necessary. The policy in `COMPOSITION-DESIGN.md`
separates low-risk discourse wrappers, structure-dependent transforms, value
corrections, scope-changing semantics, and lossy ASR effects. It caps initial
compositions at four phenomena, applies them in a defined order, rejects
contradictory values/scope, and chooses cases by weighted coverage gain instead
of a Cartesian product.

The AI audit cohort proves interactions can be added without millions of rows,
but its provisional distribution is not a substitute for production-derived
weights or human review.

## Public-data status

PRESTO, MASSIVE, Taskmaster, and SLURP are **not integrated**. SpeechLab has a
registry and generic flat-JSONL staging adapter only. PRESTO needs native nested
field/context support; Taskmaster needs release-specific license and dialogue
boundary handling; MASSIVE and SLURP labels do not map directly to Speak It;
SLURP audio remains out of scope until its exact terms are verified. See
`PUBLIC-DATA-AUDIT.md` for sources, licenses, contributions, and the required
Speak It contract-authoring workflow.

## Improvements required before scaling

1. Human-review the 400-row set; use a second reviewer for safety and ambiguity.
2. Remove or relabel the 12 known meaning-changing “reviewed” mutations and the
   broken synthetic language before using any score as correctness.
3. Separate semantic blueprint authoring from rendering implementation and add
   an adjudicator identity/status to each contract.
4. Implement the constrained composition policy and require semantic-delta
   checks after each transformation.
5. Replace uniform archetype/overlay weights with a declared provisional mix,
   then permissioned usage-derived weights.
6. Add lexical/entity/temporal breadth: real locations, varied recurrence,
   timezone edges, contacts, shopping types, and scoped operations.
7. Add native public-data readers, but promote examples only after independent
   Speak It contract review.
8. Gate promotion on naturalness, semantic preservation, novelty, and reviewer
   agreement—not merely schema acceptance.

## Recommended next corpus

Stay at **approximately 800 reviewed cases**:

- 260 rewritten/adjudicated semantic cores;
- about 190 high-quality single-phenomenon cases;
- about 250 coverage-selected compatible pairs;
- about 70 high-value triads/quadruples, concentrated on correction, shared
  context, scoped cancellation, and safety;
- about 30 reviewed public/human examples once licensing and contracts are done.

Do not move to 10,000 until audited meaning preservation is at least 95%, broken
language is below 5%, every safety contract has two reviewers, multi-phenomenon
coverage is deliberate rather than templated, and novelty remains material at
the 800-case checkpoint.

## Reproduction commands

```sh
python3 Tools/SpeechLab/audit/generate_candidates.py
python3 Tools/SpeechLab/audit/validate_candidates.py
python3 Tools/SpeechLab/speechlab.py import-renderings \
  Tools/SpeechLab/audit/ai-candidates-accepted.jsonl \
  --output Tools/SpeechLab/audit/combined-renderings.jsonl

python3 Tools/SpeechLab/speechlab.py evaluate \
  --renderings Tools/SpeechLab/audit/combined-renderings.jsonl \
  --preset stress --database output/speechlab/data-quality-audit.sqlite

python3 Tools/SpeechLab/audit/audit_data_quality.py \
  --database output/speechlab/data-quality-audit.sqlite \
  --run-id run-1821f5a97714af13c739c4e5

python3 Tools/SpeechLab/speechlab.py integrity \
  --database output/speechlab/data-quality-audit.sqlite \
  --run-id run-1821f5a97714af13c739c4e5

PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s Tools/SpeechLab/tests -v
```
