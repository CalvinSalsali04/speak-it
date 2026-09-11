# Public datasets — licence and relevance survey

Speak It has never used a public dataset. Project history assumed MASSIVE and
PRESTO work already existed in this repository; it does not, and a grep of the
tree returns only the surname "Preston". This document is the survey that
should have preceded that assumption, so the next session starts from findings
rather than from folklore.

Licences below were read from each project's own licence file or repository
page on 2026-09-11, not recalled. Nothing here has been downloaded or
integrated.

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

## What this does not establish

No dataset has been downloaded, sampled or measured. Relevance judgements are
from each project's own description of itself, not from reading the data. The
next step is a small, licence-clean sample from Disfl-QA and PRESTO, and a
decision from Calvin on whether third-party data belongs in this repository at
all or in a sibling one.
