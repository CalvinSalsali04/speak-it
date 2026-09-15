# The choice family: what counts as an instance, and what counts as a pass

**Frozen 2026-09-14, before any example was collected. That ordering is the
point of the document and is checkable in git: this file is added in its own
commit, ahead of every capture that will be scored against it.**

Speak It can represent *"the speaker named alternatives and did not choose."*
It has no representation for *"named alternatives and then chose,"* so someone
thinking aloud and landing on an answer reads as someone who never landed.
`Docs/KNOWN_ISSUES.md` records the source-level cause and why it is a
representation change rather than a rule.

This document is not about that cause. It fixes **how the family will be
measured**, so that a number produced next month is comparable to a number
produced today, and so that the set we collect cannot be shaped — even
unconsciously — by what the implementation turns out to find easy.

The definition is stated in the terms Calvin used: **an open alternative and a
later resolution.** Not dates, and not phrases. The temporal case is one
instance of the family and the reason the family is currently invisible; a
definition written around it would reproduce the defect it is meant to expose.

---

## 1. Membership is decided by the words, never by the output

A capture is in the family if a careful human reading the transcript, who has
never seen this app, would say both of the following happened.

**(a) An alternative set was put forward.** Two or more candidate fillers for
one and the same slot in what the speaker is deciding, live at the moment they
are said — neither yet chosen.

The slot may be a value inside a clause (*which day, which person, which
branch, which item*) or a whole clause (*drive, or take the bus*). **The
definition does not distinguish them.** Where the resolution would have to be
carried is an implementation fact, and letting it into the definition is
exactly how the temporal case came to be the only one handled.

**(b) A resolution followed, in the same capture.** A later stretch of the same
capture that makes exactly one member of that set the one that holds.

Membership is decided before anyone runs anything. A capture the app handles
perfectly is in the family; so is one it mangles. **A definition that admits
only the cases we fail is not a measurement, it is a bug list.**

## 2. The three forms of resolution that count

Only these. A capture resolving in any other way is out of the family, or in
the separately-scored bucket in §3.

| | form | example shape |
|---|---|---|
| **R1** | **restatement** — one alternative is said again alone, in a clause that reads as what the speaker will do | *"… I think Thursday, cook the salmon on Thursday"* |
| **R2** | **marked selection** — a repair or preference marker attaches to one alternative | *"… actually no, take the bus"* / *"… Tuesday is better"* |
| **R3** | **elimination** — every alternative but one is ruled out | *"… not the one on King"* |

## 3. What is deliberately excluded

- **R4, inferred resolution.** Nothing names an alternative; a later clause
  only makes one of them possible — *"… so I'll leave the car at home."*
  Reading that as a resolution needs world knowledge, and a label on it is a
  label on **our** inference rather than on the speaker's words. Captures of
  this shape are worth collecting and are tagged `choice-inferred`. They are
  **scored separately and never inside the family rate.**
- **Silent decisions.** Someone who weighed two options in their head and said
  one of them is indistinguishable from someone who never had a choice. The
  family is only the choices spoken aloud, and that is a limit on what any
  number here can mean, not a gap to be patched.
- **Offering the choice back to the person.** Whether the app should ask, show
  both, or pick, is a product decision. This document measures whether the
  speaker's own resolution survives, and nothing else.

## 4. What a pass is: three judgements, counted separately

Per capture, and never summed into one number.

- **J1 — resolution honoured.** *Scored only on captures that have a
  resolution.* The surviving thought acts on the winning alternative and on no
  other.
- **J2 — openness preserved.** *Scored only on captures with no resolution.*
  No alternative is promoted; nothing commits the speaker to one.
- **J3 — commitment kept.** Whatever the resolution settled is present in the
  thought at all. Today's failure lives here: the date is **dropped entirely**
  rather than chosen wrongly.

J3 is separate from J1 because *"it dropped it"* and *"it picked the wrong
one"* are different failures with different fixes, and a combined rate would
let a change trade one for the other and look flat.

## 5. J2 alone is evidence of nothing, and must never be printed alone

**An engine with no choice logic at all scores J2 at ceiling**, because doing
nothing preserves openness perfectly. This is the same shape as
`bridging-guard` at 4/4 beside `statement-runon` at 0/6, which
`Tools/CorpusRunner/heldout/score.py` prints as `NOT INFORMATIVE` rather than
letting a reader scan it as coverage.

So: **J1 and J2 are always printed side by side.** A J2 at ceiling beside a J1
at zero is marked NOT INFORMATIVE, and the mark clears by itself once J1 leaves
zero. A published J2 rate with no J1 beside it is a reporting defect.

## 6. What a set has to look like before its rate means anything

Requirements on any set claiming to measure this family. The first three are
machine-checked by `Tools/CorpusRunner/choice-balance.py`; the last two are
judgements a checker cannot make, and it says so on every run rather than
reporting a clean bill over five requirements it verified three of.

- **B1.** At least a third of the resolution captures carry **no resolution
  marker at all** — plain R1 restatement. Otherwise a marker list scores the
  family and we learn nothing about whether anything understood the choice.
- **B2.** Some captures contain a resolution-marker word that **resolves
  nothing**: *"no rush"*, *"better call her back"*, *"actually"* meaning *in
  fact*. A marker standing in for the judgement it approximates is this
  project's most repeated bug.
- **B3.** The slot varies — time, person, place, object and whole-clause all
  present, and no single slot type more than half the captures. Otherwise "the
  choice family" quietly means "the date family" again.
- **B4.** The alternatives and the resolution must not be paraphrases of one
  canonical sentence. **Seven of the ten readable decision rows we already have
  fail this** <!-- recomputed: twin-restatement 7 of 10 -->: the clean twin's
  whole sentence sits verbatim inside the rambling row, so a *last clause wins*
  rule scores them as understanding. The other three are two-thought rows whose
  twin is a conjunction, where only the resolved half is restated — nearer to
  failing than to passing. That count is recomputed from `rambling.tsv` by
  `test_choice_balance.py`, and this sentence fails the suite when it drifts;
  the first version of it said four of five, which was the figure in
  `KNOWN_ISSUES.md` from before this thread added rows.
- **B5.** One author's captures never make a published rate on their own.

## 7. Comparability between runs

- This definition is **frozen at the commit that adds this file**. A published
  rate cites that hash.
- A change to §1, §2 or §3 changes **who is in the family**, which changes the
  denominator. Rates either side of such a change are **not subtractable** —
  the same rule `Tools/CorpusRunner/ledger-check.py` enforces on the cost
  ledger, for the same reason.
- A change to §4, §5 or §6 is a scoring change: re-score the whole set, publish
  both numbers, and again do not subtract across.
- **Rates, never rows.** No capture from a sealed set is quoted here or
  anywhere else, and no sealed failure is read.

## 8. What this definition cannot do

Stated here rather than discovered later.

- **It cannot see a resolution carried by tone**, which in real speech is many
  of them and in written captures is none. Every number this definition
  produces is over the subset of resolutions a reader can see in text.
- **Membership is a human judgement.** Two readers will disagree on borderline
  captures. The disagreement rate between two independent readers should be
  measured **before** the family rate is believed, and published beside it; a
  family rate of 60% over a set two readers only agree on 80% of the time is
  not a 60% measurement of anything.
- **It says nothing about frequency.** How often people actually do this in
  real captures is the question that decides whether the representation is
  worth building, and no set we author can answer it. That answer needs the
  real recordings already asked for.
