# Independent semantic-review protocol

Review must happen before any production-parser result is revealed. Reviewers
receive only `review/independent-review-pack.jsonl`, which contains utterance,
relevant context, proposed contract, taxonomy labels, and neutral questions.

For every case the reviewer records:

- naturalness from 1 to 5;
- intended meaning and intended item count;
- route or destination for each item;
- temporal and location meaning;
- cancellation or negation scope;
- whether ambiguity is absent, intentional, unintended, or uncertain;
- whether the proposed contract is correct;
- whether the rendering preserves that contract;
- reviewer identity/source and review timestamp.

Judge naturalness and semantic correctness independently. Awkward wording may
still preserve the proposed meaning, and fluent wording may still contradict
the contract. Do not use one score as a proxy for the other.

`relevant_context` is part of the proposed semantic representation, not merely
background prose. In particular, `relevant_context.timezone` is the
authoritative default timezone. A spoken timezone is preserved when that field
matches even if it is not duplicated inside every item. Prior turns may resolve
a reference only when the referent and its required values are actually present
in the supplied window.

Mark ambiguity explicitly when the utterance or context supports multiple
material outcomes. Do not affirm a contract that silently chooses an AM/PM
value, cancellation target, pronoun referent, DST fold, or other branch that the
speaker did not resolve. Conversely, do not call a field missing when it is
already represented in the supplied context.

The review object must validate against `schema/review.schema.json`. Submit one
JSONL row per review in this shape:

```json
{"case_id":"case-…","review":{"review_id":"review-…","reviewer":{"kind":"human","identity":"reviewer-identifier"},"reviewed_at":"2026-09-13T12:00:00Z","independence":"independent","naturalness":4,"intended_meaning":"…","intended_item_count":1,"routing":["Today"],"temporal_meaning":null,"location_meaning":null,"cancellation_negation_scope":null,"ambiguity":"none","proposed_contract_correct":"yes","meaning_preservation":"appears_preserved","notes":"…"}}
```

Apply reviews with:

```sh
python3 Tools/SpeechLab/phase2/apply_reviews.py \
  --reviews /path/to/independent-reviews.jsonl \
  --output /path/to/cases-reviewed.jsonl
```

One independent approval is required for ordinary cases. Safety-critical cases
require two positive reviews from distinct identities. Any adverse or uncertain
independent review changes the label state to `disputed` and blocks trust.
Calling the same model/session twice is not independence. Human review is never
inferred or fabricated.

Only after semantics are frozen may parser output be joined by `case_id` in a
separate results store. Parser output must never be written back as semantic
truth.
