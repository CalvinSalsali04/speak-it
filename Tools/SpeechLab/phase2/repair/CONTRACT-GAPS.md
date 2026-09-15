# Contract gaps for the five uncovered concepts

No cases were added for these concepts. Nominal taxonomy coverage would be
misleading until the contract can state the meaning that a reviewer must judge.

## Conditional intent

- Meaning: an action is contingent on a condition.
- Required representation: a structured condition plus the indices or operation it governs.
- Current support: no; free text cannot distinguish a conditional action from an unconditional action plus a note.
- Realistic speech: “If the package still isn’t here Friday, remind me to call.”
- Genuine ambiguity: the condition may govern one action or a following list.
- Measurable now: escalation to review, not execution correctness.

## Conjunction ambiguity

- Meaning: “and” or “or” permits more than one plausible grouping or scope.
- Required representation: alternative parse trees and an unresolved/resolved status.
- Current support: no; a flat `items` array commits to one grouping.
- Realistic speech: “Remind me to call Sam and Lee or Priya.”
- Genuine ambiguity: `Sam and (Lee or Priya)` versus `(Sam and Lee) or Priya`.
- Measurable now: detection or review behavior, not a single exact answer.

## Self-correction quantity

- Meaning: the speaker replaces an earlier numeric value with a final value.
- Required representation: quantity and unit fields plus discarded-quantity lineage.
- Current support: no; quantities occur only inside free-text facts.
- Realistic speech: “Get two—sorry, three—cartons of oat milk.”
- Genuine ambiguity: a repair boundary can be unclear when several items have quantities.
- Measurable now: repair presence, not corrected quantity accuracy.

## Shared object

- Meaning: two actions operate on the same entity without repeating its name.
- Required representation: object/reference identity and governed item indices.
- Current support: no; equality of free-text facts is not object identity.
- Realistic speech: “Open the invoice, check it, and send it to Maya.”
- Genuine ambiguity: a pronoun can refer to the invoice or an intervening item.
- Measurable now: reference-ambiguity review, not shared-object resolution.

## Unresolved alternative

- Meaning: multiple live choices remain and none may be silently selected.
- Required representation: structured alternatives, their scopes, and preserve/clarify policy.
- Current support: no; one proposed item necessarily chooses a branch.
- Realistic speech: “I’m deciding whether to renew it or cancel—don’t do either yet.”
- Genuine ambiguity: alternatives may be mutually exclusive, nested, or partially shared.
- Measurable now: preserving both branches and avoiding action, not a chosen-item answer.

Decision: defer all five. Add schema support and focused independent review
before granting coverage credit.
