# Semantic corpus — release gate met

> **Superseded 2026-08-19.** This records the 182-case gate. The corpus was
> since expanded to 402 cases, which found 92 further disagreements and forced
> ten repairs to the engine. See **[SEMANTIC_CORPUS_EXPANSION.md](SEMANTIC_CORPUS_EXPANSION.md)**
> for the current state; this file is kept for the history of how the first
> gate was reached.

- Reference instant: **Monday 2026-08-03 10:00 America/Toronto**
- Release gate: **0 CRITICAL, 0 BEHAVIORAL** — **met**, by consequence as well
  as by field.

```
SEMANTIC CORPUS SUMMARY
============================================================
Normal                       22 cases     0 failing  PASS
Natural messy speech         16 cases     0 failing  PASS
Multiple thoughts            15 cases     0 failing  PASS
Negation                     13 cases     0 failing  PASS
Past versus future           21 cases     0 failing  PASS
Temporal ambiguity           26 cases     0 failing  PASS
Numbers that are not times   18 cases     0 failing  PASS
People and names             16 cases     0 failing  PASS
Recurrence                   20 cases     0 failing  PASS
Location                     15 cases     0 failing  PASS
------------------------------------------------------------
TOTAL  182 cases, 0 failing, 182 passing

By severity (release gate: 0 CRITICAL, 0 BEHAVIORAL):
  CRITICAL: 0
  BEHAVIORAL: 0
  METADATA: 0
  COSMETIC: 0
```

Progression: 99/160 passing at the start, 125/160 after the delivery seams,
150/173 after the actionability split, 172/182 after the temporal and location
contracts, **182/182 now**.

Full unit suite: 357 tests, 0 failures, 1 skipped. Release compile: clean.

## How the behavioral failures were closed

| Cluster | Was | Fix |
| --- | --- | --- |
| Classification | 7 | `Actionability` split out from `ItemType` (2026-08-18 decision). |
| Temporal language | 5 | Five contracts written down: capture wall clock, next-future ordinal day, real end-of-month, one morning policy, and "next Friday" as the following calendar week. "Next week" stays Needs review. |
| Recurrence | 3 | Recurrence parsed as recurrence before any instant is resolved; the series owns its clock. `OrdinalWeekday` added for "first Monday every month". |
| Location | 2 | Place names read as grammar: the name ends where the action begins, and "remind me at X" asks whether X is a clock before treating it as a place. |
| People | 9 | One shared `PersonMention` resolver, read by Today and by Memory (2026-08-19 decision). |

## What the consequence audit found, and what closed it

The last nine mismatches were all `person`, which the corpus scores as metadata.
Measuring the consequence rather than trusting the label showed five of them
were behavioral: `MemoryPersonNameResolver` recovered nothing for any failing
Memory note, so "Catherine called me at five" and "I met Alex yesterday" never
appeared under People at all, and "Call Sam, no wait, Sam's assistant" filed a
person called *Wait Sam* — displayed on the row, and used to address a message.

They were one repair, not nine. `PersonMention.swift` now answers "who is this
about?" once:

| Utterance | Was | Now |
| --- | --- | --- |
| `Catherine called me at five` | nil | Catherine, under People |
| `Don't forget Catherine called me` | nil | Catherine, under People |
| `I met Alex yesterday` | nil | Alex, under People |
| `Alex's brother is visiting` | nil | Alex, under People |
| `Call Sam, no wait, Sam's assistant` | `Wait Sam` | `Sam's assistant` |
| `I need to… send Catherine that thing tomorrow morning` | nil | Catherine |
| `Meet Priya at the office` | nil | Priya |
| `Call, uh, call Mom` | nil | Mom |
| `Call Dr. Okonkwo` | `Dr Okonkwo` | `Dr. Okonkwo` |

One corpus expectation was corrected rather than the rule: "Call Sam, no wait,
Sam's assistant" expected `Sam`, which scored a repaired sentence against the
words it had been repaired away from. The correction layer reduces the target to
`Sam's assistant`, and that is who the call is to.

## What keeps the resolver from over-reaching

A person mention requires evidence that the phrase is functioning as a human
participant. Capitalization alone is not evidence, and these name nobody:

```
Buy milk at Walmart
Finish the Alex report
Read about Ada Lovelace
Apple announced something
Meet the deadline Friday
Professor said Chapter 7 is excluded
```

The same guard keeps a name from absorbing what sits beside it, so *Alex
Friday*, *Wait Sam*, *Catherine Tomorrow* and *Mom Five* cannot be produced.

## The tests the corpus could not have caught

`SpeakItTests/PersonMentionTests.swift` asserts the **consequence**, not the
field: capture the sentence through the real pipeline, then look under Memory →
People for the human it named, using the same grouping the screen uses
(`MemoryPeopleIndex`). That is the test that found this problem in the first
place, and it is now the test that holds it closed.

It also pins the distinction between a **missing** target and a **non-named**
one. "Call them tomorrow" is a follow-up with nobody on the other end and asks
who; "Call the dentist tomorrow" describes its target and is left alone.

## Next

The semantic engine is frozen for v1 unless TestFlight exposes a genuine P0 or
P1. The remaining corpus work is a single expansion to roughly 350–500 cases,
built as transformations of concepts already known to work — filler, self
correction, negated, past, future, multi-thought, different name, date,
recurrence and location wording — rather than fresh hand-picked sentences.
