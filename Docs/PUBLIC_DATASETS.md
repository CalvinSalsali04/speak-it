# Public datasets — licence and relevance survey

Speak It has never used a public dataset. Project history assumed MASSIVE and
PRESTO work already existed in this repository; it does not, and a grep of the
tree returns only the surname "Preston". This document is the survey that
should have preceded that assumption, so the next session starts from findings
rather than from folklore.

Licences below were read from each project's own licence file or repository
page on 2026-09-11, not recalled. Nothing here has been downloaded or
integrated.

> **Corrected 2026-09-15 — the ranking below was made against a failure
> ranking that measurement has since replaced, and nothing rechecked it.**
> The original order is kept as written, because a ranking quietly reordered
> is worse than a stale one. Read the section *"What the ranking depended on,
> and what has changed under it"* at the foot of this file before reaching for
> any entry here as an unblock. The short version: **no corpus surveyed here
> supplies material for the failures this project has actually traced**, and
> the reason is checkable rather than a matter of taste.

## The constraint that shapes every entry

None of these are thought-capture corpora. They are voice-assistant commands,
task-oriented dialogue, or question answering. **No public dataset knows what
belongs in Today and what belongs in Memory**, because that distinction is
Speak It's product contract and exists nowhere else.

So the rule the charter states — do not treat another dataset's labels as our
ground truth — is not a caution here, it is the whole design. What these
corpora can supply is *language*: phrasings we did not invent, and disfluency
produced by humans rather than by our imagination of humans. Expected
behaviour is authored against our contract, by the thread that owns
expectations, every time.

## Findings, ranked by what they would actually buy us

### 1. Disfl-QA — CC BY 4.0 — highest value, lowest risk

~12,000 pairs, each an original fluent question and a human-written disfluent
rewrite of it: restarts, self-corrections, rephrasing. "Norse found no wait
Normandy" is a published example.

Why it ranks first: it is **paired**. The pair asserts only that two utterances
mean the same thing — a meaning-preservation relation, not a product label — so
it can be used without inheriting a single expectation. That is exactly the
input the invariance instrument needs, and it is grounded in what people
actually did rather than in mutation families I made up.

Honest limit: the content is Wikipedia questions, not captures. Probing Speak It
with these sentences directly would measure out-of-domain behaviour. The
transferable asset is the **fluent → disfluent transformation**, mined as
patterns and applied to our own language.

Relevance to the ranked failure families: restarts and false starts were named
the top family by the diagnosis thread, and this is the only public corpus found
that documents them in human-authored pairs.

### 2. PRESTO — CC BY 4.0 — best domain overlap

Over 550,000 multilingual examples, with test partitions split out specifically
for **disfluencies, revisions and code-switching**, plus structured context of
user contacts, lists and notes.

This is the closest public analogue to Speak It's domain: reminders, lists and
notes phrased by people, with the phenomena we care about deliberately
isolated. The en-US revision and disfluency partitions are the parts worth
adapting.

Their parse labels are not our destinations and must not be imported as such.

### 3. MASSIVE — Apache 2.0 — breadth, not disfluency

Over 1M utterances, 52 languages, 60 intents including reminders, lists and
calendar, 55 slot types. Created by localising SLURP.

What it buys: many different ways to phrase the same intent, which is useful
for routing diversity. What it does not buy: these are clean, well-formed
assistant commands. The messy speech Speak It exists to handle is largely
absent.

Apache 2.0 carries notice-retention obligations rather than CC attribution;
either way anything vendored needs its notice carried.

### 4. SLURP — annotations CC BY 4.0, **audio CC BY-NC 4.0** — text only

The licence split is the finding. Speak It is a commercial product with a paid
tier, so the **non-commercial audio is unusable to us**. The text annotations
are fine. Anyone reaching for SLURP audio later should stop at this line; the
project README offers less restrictive audio terms on request, which would be a
conversation with Emotech, not a download.

### 5. Taskmaster — licence not verified — parked

Multi-turn agent-and-customer dialogue (booking, ordering). Lower relevance:
Speak It captures are single-shot monologue, not negotiation. Not worth
verifying the licence until the higher-ranked sets are exhausted.

### Excluded: Switchboard, ATIS

LDC-distributed and paid, with redistribution restrictions that do not fit a
corpus checked into this repository. Their disfluency annotations are the
academic standard, and they are still not worth the licensing position.

## If anything is integrated

1. Vendored data carries its attribution. CC BY 4.0 requires it and Apache 2.0
   requires notice retention, so a `THIRD-PARTY-DATA.md` recording source,
   licence, retrieval date and what was changed is the minimum.
2. Derived cases live in their own corpus category and **never** in
   `Tools/CorpusRunner/heldout/`. Public language is not held out: it is
   visible to whoever adapts it, which disqualifies it from measuring
   generalisation.
3. Expected behaviour is authored against our contract by the thread that owns
   expectations. Import language; never import answers.
4. Size matters in a repository this size. Adapt a sample with a recorded
   selection rule; do not vendor a 550,000-example corpus.

## What the ranking depended on, and what has changed under it

*Added 2026-09-15.*

**The ranking is a judgement, and it rests on a figure that moves.** Disfl-QA
is first because of one sentence: *"restarts and false starts were named the
top family by the diagnosis thread, and this is the only public corpus found
that documents them in human-authored pairs."* That names its own dependency,
which is what makes it checkable — and nothing checks it. The file was written
at 06:57 on 2026-09-11 and the dependency moved thirteen hours later.

**What replaced it.** Two independent lines of measurement say restarts are
not the top family:

- The rambling development set writes each capture twice, clean and spoken
  under one id stem, so the measurement is the gap between the twins. The
  `restart` family shows **4/4 → 4/4** on both columns, and that section's
  headline is that filler is not the problem. Two caveats travel with that
  figure and both are in `Docs/LANGUAGE_BASELINE.md`: the section already
  records that in three of the four pairs the clean twin is a **literal
  suffix** of its rambling twin, so "return the final clause" scores them for
  free and 4/4 is *consistent with* no cost rather than evidence of it. And
  the figure is **stale as a count**: it was measured over a 57-row set, and
  `rambling.tsv` now carries 85 rows with **six** restart pairs, of which
  three are literal suffixes. The two added pairs have not been scored — that
  needs a macOS run. Neither caveat points at restarts being the top family;
  both mean nobody should quote 4/4 as current.
- Every target traced since is a different phenomenon. The baseline's own
  table of stopped targets names the doubled infinitive frame, the
  retrieval-failure tail and deliberation; connectives the clause splitter
  does not hold, and `incomplete-complement` at 1/10, are traced elsewhere in
  the same document. **None of them is a restart family or a correction
  family.**

**Disfl-QA cannot supply them, and for the abandonment targets the reason is
structural rather than sampling.** From the paper (read 2026-09-15, not
recalled), annotators had to produce a disfluent question that *"(a) is
semantically equivalent to the original question (b) is natural"*. An
abandoned thought is not semantically equivalent to a complete question, so
the retrieval-failure tail and deliberation are excluded **by construction**.
The reported taxonomy is five categories and every one is a restart or a
correction: interrogative restart 30%, entity correction 25.6%, entity-type
correction 21.1%, adverb/adjective correction 20%, other 3.3%.

The nearest thing to a counter-example is worth naming rather than hiding.
INC57, `I was going to call, I mean`, carries a correction marker, so a corpus
of corrections is not *wholly* foreign to it. But the row is an **abandonment**
— the speaker signals a repair and never makes one — and a pair asserting
semantic equivalence to a complete question cannot contain that. The marker
matches; the phenomenon does not.

**One trap, recorded because it points the wrong way.** The Hugging Face
dataset card shows rows with empty answer fields, which reads as abandonment.
That is SQuAD-v2 *unanswerability* — a property of the passage, not of the
question being unfinished. The paper settles it and the card does not. Anyone
sizing this family off the card gets the opposite answer.

**What survives untouched.** The second use this file already names for
Disfl-QA: a paired fluent→disfluent transformation authored by humans rather
than by our imagination of humans, mined as patterns for the invariance
instrument. That is real and the re-ranking does not touch it. Licence
re-verified 2026-09-15, still CC BY 4.0. The other entries' licences have
**not** been re-read since 2026-09-11.

**The larger gap, which is about how this survey was searched.** Every entry
here is a voice-assistant, task-oriented-dialogue or question-answering
corpus, because the search was for **domain** match — reminders, lists, notes.
The question that now matters is a **phenomenon** question: how often anyone
actually says `which means`, `that means` or `because of that`, which
`connective-census.py` reports as zero across all readable material and which
that census explicitly cannot settle, since every row it counts was authored
here. Answering it needs transcripts of spontaneous speech, and **no corpus of
that class was surveyed at all** — Switchboard was excluded on licensing and
the freely-redistributable spoken corpora were never considered. That is a gap
in the search, not a finding about the corpora.

**How to read this whole file, stated once.** Public disfluency data is
frequency and robustness material. It is not Calvin's own captures, it can
never be a sealed set — it is public, so any thread may have read it — and it
closes nothing about the request for real recordings. What the work above does
is narrow that request: we now know *specifically* why the best-ranked public
substitute is not one.

**Before using this ranking, retest its dependency.** Read the current failure
ranking in `Docs/LANGUAGE_BASELINE.md` first and ask whether the corpus you
are reaching for contains the phenomenon behind any open target. That is the
cheapest retest and it is two minutes.

## What this does not establish

No dataset has been downloaded, sampled or measured. Relevance judgements are
from each project's own description of itself and, for Disfl-QA as of
2026-09-15, from its paper — not from reading the data. The next step is a
small, licence-clean sample from Disfl-QA and PRESTO, and a decision from
Calvin on whether third-party data belongs in this repository at all or in a
sibling one. **That decision is not on the critical path**: per the section
above, neither corpus supplies material for an open target, so it should not
be queued as something that would unblock language work.
