# Consequence set — captures written before anything was measured

A sealed set of natural captures of one phenomenon: **a person states a fact,
and then the errand that fact creates.** "The lease ends in March, I need to
draft the renewal."

Calvin asked for evidence about the resultive-`so` boundary (#57) that was not
authored to fit the implementation — "broader natural variants... preferably
from another writer, public language data where appropriate, or blinded
generation/rewrite". This is the blinded-generation half. The other halves are
his to commission.

## What "blind" means here, stated exactly, because a provenance claim that overstates is worse than a weaker true one

**What is true:**

- The captures were written by the evaluation thread, which has **not** read
  any output of the parser on any of them. The engine needs Apple's
  `NaturalLanguage` and does not build in this container, so there is no way
  to see what passes from here. That is a property of the machine rather than
  a promise about the author, which is the only reason it is worth much.
- The generation parameters below were **fixed and committed before any
  capture was written**, in a separate commit. Check the order in git rather
  than believing this paragraph. That is the whole value of the set, and it is
  exactly the kind of claim this repository has watched decay.
- No capture was added, removed, reworded or relabelled after any measurement.
  If that ever stops being true, this set is finished as evidence and the
  paragraph saying so must be written here, not deleted.

**What is NOT true, and matters:**

- **The author had read the rule under test.** #57 admits a resultive `so`
  before a first-person obligation when what precedes it already stands alone.
  Knowing that cannot be undone, and calling this set "blind" without saying so
  would be the same overstatement as a build date standing in for evidence of
  unseen content.
- The mitigation is structural, not willpower. The connectors and destinations
  were drawn from the fixed list below rather than chosen per capture, so the
  set cannot drift toward the rule's trigger shape one row at a time. Whether
  it worked is checkable: count how many rows use each connector and compare
  against the plan.
- These are written captures, not transcribed speech. Register is the standing
  weakness of every set we author ourselves, and it is the reason public
  language data would be worth more as a control than another set by us.

## The parameters, fixed in advance

Written before the first capture, unchanged afterwards.

| | |
| --- | --- |
| connectors, in fixed rotation | `and`, `so`, `which means`, bare comma, `then`, `that means`, `because of that`, none (juxtaposition) |
| captures per connector | 5 |
| total | 40, amended to 56 on 2026-09-14 (see the amendment section) |
| must stay ONE thought | 16 of 40, then 24 of 56, written in the same pass, spread across every connector |
| destinations | drawn from the product contract, not from what a parser would do: an action is Today, a fact worth keeping is Memory |
| domains | household, work, health, family, money — one row each per connector block |

The one-thought share is not decoration. A set of fact-plus-errand captures
that all want two thoughts is passed by a parser that splits everything, which
is the same defect as a guard family passed by a parser that never splits.

## Reading this set

**Scored once, against the rate, never row by row.** It is sealed: the three
existing sealed sets plus this one are `corpus_paths.sealed()`, so the leak
check compares it against tuned material on every run and the classification
guard fails the run if it is ever left unclassified.

If it disagrees with the readable evidence for #57, the disagreement is the
finding. A set written to confirm a rule is not evidence for it.

## Amendment, 2026-09-14, before anything was measured

**The parameters above were amended once, and this section is why that is not
the same as tuning.**

The original forty are written register. That was a stated weakness from the
first version of this file, and it stopped being a footnote when the core
language thread corrected a figure it had published: a scan reporting that the
everyday set contained no instance of the word "so" had hard-coded column two,
and `everyday.tsv` keeps its utterance in column **three**. The corrected
numbers make everyday the **most** spoken-sounding corpus we have, not the
least, with roughly a quarter of its captures carrying a spoken marker against
about a tenth of the development sets.

So a set written entirely in clean prose is testing the wrong register for the
thing it is evidence about. Sixteen captures were added, `CQ41`-`CQ56`, two per
connector block as before, eight that must split and eight that must stay one
thought, in the register people actually dictate in: fillers, discourse
openers, hedges, a false start, "I mean".

**Why this is an amendment and not tuning, stated so it can be checked rather
than believed:**

- It happened **before any measurement of any kind**. Nothing has been scored
  against this set, on any machine, at any generation. There is no result to
  have steered it.
- It changes the **register**, which the original parameters never mentioned.
  It does not change the phenomenon, the connectors, the domain rotation, or
  the split/whole balance, and it does not move toward the rule's trigger
  shape: the new rows use the same fixed connector rotation as the old ones.
- It was prompted by a corrected fact about a corpus, not by anything about
  what the parser does.

If that reasoning is wrong, the remedy is to score `CQ01`-`CQ40` and
`CQ41`-`CQ56` separately and compare, which the family names make possible
without touching the file.

**One thing not to over-read.** Counting spoken markers in the amended set with
my own list of markers gives about 23%, which looks like everyday's 24%. Those
two numbers are **not comparable**: they were produced by different marker
lists, and mine does not count a bare "so" used as a discourse opener, which
two of the new rows rely on. Treat the register change as qualitative until
one list has been run over both sets.

## Generations

**Generation 1, recorded 2026-09-14.** The set as first written: 40 captures
in written register, nothing scored against it.

**Generation 2, recorded 2026-09-14.** 56 captures: the original forty
unchanged, plus `CQ41`-`CQ56` in spoken register, for the reason in the
amendment above. Opened the same day, before any measurement, so no published
figure compares across it and none ever will -- generation 1 was never scored.
That is the cheapest a generation boundary will ever be, and it is worth
saying out loud that the reason it was cheap is that nothing had been measured
yet, not that generations are cheap.

A generation opens when a capture's text changes, and numbers never compare
across one. If that happens, the row saying what changed and which figures stop
comparing goes here, before the new number is published anywhere.

## If this set is ever edited after being scored

Say so here, in full, and treat every published figure from generation 1 as
belonging to a set that no longer exists. That is the expensive answer and it
is the honest one: the alternative is a rate whose denominator quietly changed,
which is how a sealed set degrades without anybody lying.
