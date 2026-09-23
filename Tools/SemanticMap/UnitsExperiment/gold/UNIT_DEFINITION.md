# Semantic-unit gold: unit definition

Written 2026-09-23 by the independent gold-author session, BEFORE any capture
transcript was received and before any candidate ran. Its sha256 is recorded in
gold.json so it is visibly fixed ahead of the labels. Development evidence only.

## What a unit is

A semantic unit is one complete intention the user would expect to find, act on,
or recall as a single item: one task, reminder or errand; one message to send;
one cancellation or change to something; one idea, note, fact or reflection worth
remembering. A unit includes every piece of source that belongs to that intention:
its operation wording ("remind me to", "I need to"), action, object, qualifiers,
time, place, person, condition, reason, and any reported or quoted content it
carries. Its ranges may be non-contiguous.

The gold records spans only. It does not decide destination (Today or Memory),
type, date, person or reminder. The per-unit `gloss` is a readability aid in the
author's words and is not scored.

## Rules, applied in this order

1. **Separate intentions are separate units.** Two things are separate when each
   could be done, cancelled or recalled on its own: different actions, or the
   same verb aimed at different targets with different times or places
   ("email Jan tomorrow and Sam on Friday" is two).
2. **One errand over a list is one unit.** The same action over a coordinated list
   of objects with no separate time, place or target is one unit
   ("buy milk, eggs and bread").
3. **Deliberation belongs to the decision it resolves.** Weighing, rejected
   alternatives and self-corrections ("maybe Tuesday, no, Thursday") are part of
   the unit they revise or decide, not a unit of their own. Deliberation that
   never reaches a decision is itself one unit (a thought), unless it is only
   filler.
4. **Reported and message content belongs to its carrier.** What someone said, or
   what the user will say in a message, is part of the unit that reports or
   sends it, even when it contains imperatives ("text Sam to grab milk" is one
   unit; "grab milk" is not the user's own task). A report with no carrier action
   ("my boss said the deck is due Friday") is one unit.
5. **Conditions belong to what they condition.** "If it rains, cancel the picnic"
   is one unit.
6. **One subject is one thought.** A long reflection about one subject stays one
   unit across sentences, with its examples, reasons and feelings. A shift to an
   unrelated subject starts a new unit.
7. **Context joins what it motivates.** A fact joined to an action by an explicit
   connective ("so", "because", "for", "since") belongs to that action's unit. A
   fact stated on its own, worth recalling whether or not the task is done, is a
   separate unit. Where the source genuinely supports both readings, the span is
   recorded as ambiguous (below), not forced.
8. **Negated and no-obligation statements are still units** when they carry
   information the user deliberately said ("I don't need to call Sam anymore").
9. **Shared scope.** A modifier that syntactically applies to several units
   ("tomorrow, call mom and email Jan") is recorded once under `shared` with the
   units it applies to. It is not ambiguous; it has several owners.

## Filler and discourse

Filler is source that carries no content of any unit: hesitations ("um", "uh",
filler "like"), discourse markers ("okay", "so", "alright", "anyway", "oh",
"yeah", "right", "I mean", "you know"), connectives standing between units
("and", "and then", "also", "plus"), and talk about the capture itself
("a few things", "what else", "that's it", "let me think").

- Filler lying strictly inside one unit's extent (between its first and last
  content word, and not separating it from another unit) is part of that unit.
- Filler at a unit's edge or between units is recorded under `filler`.

## Ambiguity

A span goes under `ambiguous` only when the source itself supports more than one
reading of who owns it, not when the author is unsure of the rule. Each entry
lists the admissible owners (unit indices, "filler", or "own unit") and a
one-line reason.

## Coverage invariant

Every character of the source that is not whitespace or punctuation belongs to
exactly one of: a unit, `filler`, `shared`, or `ambiguous`. A checker enforces
this before the file is frozen.

## Offsets

`[start, end)` half-open, in Unicode code points of the exact `source` string
(Python `str` indexing). Each range carries its covered text. Ranges are trimmed
of surrounding whitespace. Where a source is pure ASCII, code-point, UTF-8 and
UTF-16 offsets coincide, and gold.json says per capture whether that holds.

## How the gold is meant to be scored (guidance for the experiment, not a rule of the candidates)

- A unit matches when its content words are exactly the gold unit's content
  words. Edge filler, whitespace and punctuation are free: a candidate may leave
  them uncovered or attach them to an adjacent unit.
- A `shared` span may be attached to any one of its listed owners, or to several
  if the representation supports overlap.
- An `ambiguous` span is correct under any of its listed owners.
- Every other content word left outside all units is dropped source; a content
  word placed in the wrong unit is a boundary error.
