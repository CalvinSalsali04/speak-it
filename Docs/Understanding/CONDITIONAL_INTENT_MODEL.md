# Conditional intent model

## Safety invariant

A lost condition must never leave a confident unconditional action. Speak It
either preserves the dependency with a trigger it supports, or keeps one
visible actionable item in Needs Review with `unsupportedCondition`, no due or
reminder date, no delivery, and no recurrence.

## Evidence from the saved 10K result

The immutable post-cancellation result contains 72 unsafe conditional rows.
All 72 are `safety.13` / `safety.conditional_intent`, with expected item count
1 and actual item count 2. Their exact structural distribution is:

| Dimension | Count |
|---|---:|
| condition before action | 72 |
| condition after action | 0 |
| multiple consequences | 0 |
| conditional plus unconditional sibling | 0 |
| person/event condition | 72 |
| temporal condition | 0 |
| location condition | 0 |
| `if` | 72 |
| `when` / `once` / `after` / `unless` | 0 / 0 / 0 / 0 |
| nested correction | 0 |
| filler/discourse wrapper | 0 |
| shared date/time context | 0 |

Every saved failure has the form `If <Name> replies, then remind me to buy
<object>.`

## Representation and scope

A conditional dependency is an ordered pair:

`condition -> consequence`

The condition is a grammatical opener (`if`, `unless`, `when`, `whenever`,
`once`, `after`, `before`, `until`, `till`, `while`, `as soon as`, `next time`,
or `every time`) plus a complete clause, or a bounded event/time adjunct such
as `after lunch`. The consequence must independently read as an instruction.
This is structural; names and action phrases are never enumerated.

A fronted standalone condition scopes over consecutive actionable consequences
in the same sentence. A new condition, a non-action sibling, a semicolon, or a
sentence boundary ends the scope. Conditions never attach backward, and never
continue forever through later speech. A trailing condition scopes over the
action immediately before it.

Supported location and temporal triggers retain their existing behavior.
Unsupported person/event conditions remain attached to their consequences,
carry `UnsupportedTrigger.condition` and
`SemanticState.unsupported(.unsupportedCondition)`, and expose no executable
timing or recurrence fields.

## Required readings

- A. `If Sarah replies, remind me to call Mike.` — one conditional call; no
  unconditional reminder.
- B. `After class, remind me to submit the assignment.` — preserve the event
  dependency; if it cannot be monitored, hold it for review.
- C. `If Sarah replies, call Mike and send the file.` — both consequences
  inherit the condition.
- D. `Buy milk today, and if Sarah replies, call Mike.` — milk is
  unconditional; the call is conditional.
- E. `If something changes, remind me…` — unsupported/review, never a
  confident action.
- F. `If Sarah replies call Mike, actually text him.` — the replacement remains
  under the same condition.
- G. `If Sarah replies call Mike, actually forget that.` — withdraw the whole
  conditional group and create no action from it.

## Production trace

Normalization and repair preserve the saved wording. `splitClauses` is the
first loss point: it emits the fronted condition separately, the old
first-person-only conditional-context reader does not inherit an `if` condition
on a third person, and organization then sees an inert Memory note plus a
fully resolved Today reminder. The repair is therefore shared conditional
scope carried through segmentation, organization, correction, and local
cancellation—not a post-hoc title or keyword blacklist.
