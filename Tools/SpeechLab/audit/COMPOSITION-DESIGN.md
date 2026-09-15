# Constrained multi-phenomenon generation

SpeechLab needs a compositional layer: the original corpus has zero renderings
with two or more phenomena. The layer must select compatible transformations
against a blueprint, not multiply all 64 tags.

## Transformation classes

- **Low-risk discourse wrappers:** fillers, hesitation, trailing noise,
  rambling openings/endings, casing and punctuation loss. These can compose
  blindly only when they do not alter quoted-speech or name boundaries.
- **Structure-dependent:** lists, multiple tasks/thoughts, shared subject/object,
  temporal/location inheritance, pronouns. Require matching multi-item or shared
  context in the blueprint.
- **Value corrections:** person/date/time/quantity/location corrections. Require
  exactly one contracted final value and a generated discarded value that is
  recorded in lineage but absent from expected output.
- **Scope-changing/high-risk:** negation, prohibition, cancellation,
  never-mind withdrawal, conditionals, uncertainty, completed/past action.
  These must originate in the blueprint; they are never blind mutations.
- **Lossy ASR:** substitution/deletion/insertion/homophone/partial thought.
  Meaning preservation cannot be guaranteed automatically.

## Compatibility and ordering

Use at most four phenomena initially: one discourse wrapper, one structural
form, one correction, and one trailing/ASR form. Apply structure first, then
correction, then discourse noise, then ASR/punctuation. Reject:

- two corrections of the same semantic field;
- two contradictory dates, times, people, locations, or polarities;
- cancellation without an explicit scoped target;
- a shared-context transform without two compatible items;
- pronouns without a unique antecedent unless the blueprint policy is review;
- quoted/reported speech whose actionability changes;
- lossy transforms on safety-critical cases without human review;
- repeated fillers/corrections that make the sentence performative or bizarre;
- any candidate that loses an anchor or adds a fact outside a deliberately
  lossy/uncertain policy.

## Coverage-guided selection

Maintain counts for compatible phenomenon pairs/triads crossed with semantic
shape, route, item count, safety, and difficulty. Greedily generate the valid
candidate with the largest weighted coverage gain, discounting common patterns
and near duplicates. Weight the target distribution from permissioned product
speech; until that exists, use a declared provisional distribution rather than
uniform 64-way balance.

Every composed candidate remains uncertain until semantic review. Promote only
after comparing it to the pre-existing blueprint, never to parser output. Stop
when new valid interaction structures and normalized failure families saturate.
