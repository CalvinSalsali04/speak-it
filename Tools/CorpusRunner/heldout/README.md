# Held-out set

389 utterances, scored separately from the corpus the rules are tuned against.
What that separation is actually worth is set out in "What this set's history
does and does not support" below — read it before quoting the number as
generalisation.

```bash
./Tools/CorpusRunner/heldout/score.sh
./Tools/CorpusRunner/heldout/score.sh --verbose   # only at release
```

## Why it is separate from the corpus

`SpeakItTests/SemanticCorpus*` is authored from the product contract by the same
person who writes the rules. That makes it an excellent regression net and a
poor progress meter: it can tell you the app still agrees with itself, and it
cannot tell you whether the app generalises. It currently runs at 999 of 1,022
clean with zero blocking failures, so as an instrument it is at ceiling.

This set is the other half — that is the intent behind it, and it is the reason
the number is worth printing. How far the repository actually backs that intent
is the next section, and the honest answer is: less far than this file used to
claim.

## What this set's history does and does not support

This file used to open by saying the 389 utterances were written "before anyone
read the parser, from the product description alone." That sentence is the whole
reason the destination rate reads as generalisation rather than memorisation, and
nothing in the repository supports it.

`heldout.tsv` arrived on 2026-08-25 at 20:30 in commit `cb2b630`, which in the
same commit rewrote six parser sources — `Actionability`, `PersonMention`,
`ReminderScheduler`, `SpeechRepair`, `ThoughtExtractor`, `ThoughtOrganizer` —
and added 307 lines to the gating corpus. Seventeen hours earlier, at 03:28 on
the same day, the seven `Docs/PipelineSweep/*.md` analyses landed, each a table
of this parser's answers on example utterances.

Commit order is not authoring order, so none of that proves the sentence false.
It proves it **uncheckable**, which is the relevant fact about a claim that a
benchmark's meaning rests on. It is replaced here rather than restated smaller,
because a provenance claim nobody can check should not be swapped for a milder
provenance claim nobody can check.

**Five of the 389 are demonstrably not unseen**, and two of them sit in the
gating corpus itself — the regression net the rules are deliberately tuned to
pass. There are two ways a capture stops being unseen and they have to be
counted as a union, not a column:

| id | in tuned material | verbatim in a document |
|---|---|---|
| `C049` | `SemanticCorpusDataQ.swift`, `devsets/routed.tsv` (RC02), `devsets/coordination.tsv` (RS04) | — |
| `C100` | four `SemanticCorpusData*.swift` files and six hand-written test files | — |
| `C342` | `SpeakItTests/LocationReminderTests.swift` | five App Store and hand-QA documents |
| `C236` | — | `Docs/PipelineSweep/routing.md` |
| `C358` | — | `Docs/AMBIGUITY_TAXONOMY.md` |

C100 is not an incidental duplicate; it is a workhorse fixture the suite reaches
for in ten places. C342 is the only capture compromised both ways, and has been
the standard location-reminder demo in hand-QA documents for weeks. Eight more
captures match tuned material at a Jaccard of 0.70 or above without being
identical.

**This count said three until 2026-09-11 19:54, and the way it was wrong is the
point.** The exact-match column was computed and the prose column was not, so
the total was a column rather than a union — and `C342` appearing in both is
what let the mistake look consistent. The same slip was made independently in
PR #55's body on the same day. A count over a definition with two limbs needs
the union computed and printed as such, or whichever limb nobody re-ran becomes
the number everybody quotes. Reproduce with:

```
python3 - <<'EOF'
# prints ids and sources only, never a capture
import re, glob, unicodedata
norm = lambda s: re.sub(r"\s+"," ",re.sub(r"[^a-z0-9 ]+"," ",
        unicodedata.normalize("NFKD",s).lower())).strip()
caps = [(c[0], norm(c[1])) for c in
        (l.rstrip("\n").split("\t") for l in open("Tools/CorpusRunner/heldout/heldout.tsv"))
        if len(c) >= 2 and not c[0].startswith("#") and c[0].lower() != "id"]
docs = {p: norm(open(p, errors="ignore").read())
        for p in glob.glob("**/*.md", recursive=True) if "/heldout/" not in p}
for cid, t in caps:
    if len(t.split()) >= 6:
        hit = [p for p, b in docs.items() if t in b]
        if hit: print(cid, "->", ", ".join(sorted(hit)))
EOF
```

Those rows are still scored and still counted. Retiring them would treat a
provenance problem as a data problem: it opens a new generation, breaks
comparability with every figure already published, and destroys the evidence.
The denominator carries them, and a reader quoting the rate should know it.

### Incidental exposure, 2026-09-11

**One capture in this set was printed into a working session's context on
2026-09-11.** An evaluation session answering a question about what *readable*
material contains wrote an ad-hoc scan over every `*.tsv` under
`Tools/CorpusRunner/`, which is wider than the question, and one held-out
capture's text came back with the results. The session reported it unprompted;
nothing else would have surfaced it.

What is known, from that report: the capture's text was seen, its pass or fail
state was not looked up, and it played no part in the analysis the scan was
for.

**The capture is named by id in `EXPOSED_WITHOUT_INSPECTION` in
`leak-check.py`, which owns this population** — landing with PR #55, which is
where that constant was added; until it merges the id lives only in this
paragraph. This section will not restate it once #55 is in: two records of one
fact drift, and the one that drifted here said "unnamed by design" for eight
commits after it had been named.

Recording the **id** is right and recording the **text** would not be, and the
distinction is worth stating because it is easy to re-derive the wrong answer
from a sensible instinct. An id grants no access that listing the file does
not — getting from `C283` to its words means opening `heldout.tsv`, which is
the act the rule forbids and which the id does not help with. What the id buys
is the only thing this record is for: a recount can subtract a named row, and
a second exposure of the same capture can be recognised as the same one
instead of counted twice. `OVERLAP_DOCUMENTED` and `PROSE_DOCUMENTED` name ids
for that reason, and today's correction of the compromised count from three to
five was possible **because** they do. An unnamed exposure is a denominator
nobody can check.

That reasoning is recorded here rather than assumed, because the first version
of this section argued the other way, and an argument nobody wrote down is one
the next reader has to lose again.

**Second exposure of the same capture, 2026-09-11 ~20:45, and it was caused by
this section.** Writing the paragraph above, the core session ran
`grep -rn "EXPOSED_WITHOUT_INSPECTION\|C283" Tools/` to check the constant
existed. `heldout.tsv` is under `Tools/`, so the id matched its own row and the
capture's text was printed a second time. Same conditions as the first: text
seen, pass/fail state not looked up, no part in any analysis.

**Distinct captures exposed is still one; exposure events are two.** That
sentence is only writable because the capture has an id in the record, which is
the argument above making its own case within the hour — an unnamed first
exposure would have made this indistinguishable from a second capture, and the
count would now be wrong in the direction that overstates the damage.

The new hazard is specific and was not anticipated when the id was recorded:
**an id is safe to store and unsafe to grep**, because the sealed file is the
one place the id appears next to its text, and every plain recursive search
over `Tools/` includes it. Naming the row is still right — the alternative
loses the denominator — but the id is a lookup key into the sealed set for
anyone who searches a tree containing it, including by accident. Check a
constant in the file that defines it, or search through
`corpus_paths.readable()`; never `grep -r` an id from the repository root. This
is the same lesson as the scan that caused the first exposure, arriving through
the mitigation rather than around it, which is the part worth remembering: a
fix can carry the defect it was written for.

It is recorded because this section's subject is which captures have stopped
being unseen and how, and "a session that works on the parser has seen it" is
that, whether or not anyone acted on it. An exposure nobody writes down is
indistinguishable from one that never happened, which is the same property that
made the original provenance claim unfalsifiable.

**The mitigation is now a rule, and was not when this was written.** Both
threads wrote ad-hoc scanners that day, and the one that stayed inside readable
material did so because its author happened to be thinking about it — luck with
a good outcome, not a property. `Tools/CorpusRunner/corpus_paths.py` makes it a
property: `readable()` cannot return a sealed path even if the list behind it is
mis-edited, because the filter runs at the point of return, and reaching sealed
material takes naming `sealed()`.

The part worth keeping is what the check claims. Two lists that do not overlap
are satisfied perfectly by a list that has silently lost a whole corpus — which
is how `rambling.tsv` once reached one runner and not the other. So the claim is
**totality**, not disjointness: `unclassified()` fails the run if any `*.tsv`
under `Tools/CorpusRunner/` is in neither list, so adding a corpus and
forgetting to classify it is a failure rather than a silent gap.

**Evidence the other way, so this note does not overstate.** Compared against
`SemanticCorpusDataI.swift` — the 307 lines added in that very commit, the
material most in front of whoever wrote this set — there is no exact match at
all. The single hit at the 0.70 threshold is a three-word capture sharing three
words with a four-word corpus string, which is what short reminder phrasings do
to a set-overlap measure, not a fingerprint. If this set had been assembled out
of what its author was looking at, that is where it would show.

Reproduce all of it:

```bash
git log --diff-filter=A --format='%ad %H' --date=iso -- Tools/CorpusRunner/heldout/heldout.tsv
git log --diff-filter=A --format='%ad' --date=iso -- Docs/PipelineSweep/domains.md
git show --stat cb2b630
```

## The rule

**Do not read the failures while you are changing rules.**

Score it, record the number, move on. The moment one of these sentences is used
to steer a fix, it stops being held out and this directory is worth nothing.
`--verbose` exists for release review, not for development.

If a held-out failure looks important enough to fix, write a *new* case for it
in the gating corpus, in its own family, and fix that. The held-out sentence
stays untouched and keeps measuring.

## Reading the per-family table

The scorer prints a family row for every tag, worst destination rate first, and
that ordering is what triage starts from. Two things decide whether a row can
carry the weight of being read that way.

**`n` is not the denominator.** `n` counts captures carrying the tag; the
destination rate is computed only over captures the set commits to a
destination. A capture labelled `Ambiguous-*` is excluded by design — the
contract for an unpinnable capture is to keep it and not act on it, which
`ACTED ON ANYWAY` measures instead. Sixty-nine of the 389 captures are labelled
that way, and they are not spread evenly: seventeen of the thirty-two families
have a destination denominator below their row count. Read the denominator from
its own column, never from `n`.

**Five families cannot be ranked on destination, or barely can.**

| family | captures | scorable for destination |
|---|---|---|
| `ambiguous` | 14 | **0** |
| `sarcasm` | 1 | **0** |
| `hypothetical` | 4 | **1** |
| `question` | 12 | **1** |
| `ellipsis` | 12 | **4** |

`ambiguous` and `sarcasm` are unrankable by construction and the scorer now
prints them under `NOT RANKED` rather than in the list; they are measured by
`ACTED ON ANYWAY`. `hypothetical` and `question` produce a rate that one
capture decides. Quote those as named cases — "0 of 1" — and never as a
percentage; a single capture is a direction, not a measurement.

That is also why `ellipsis` 0 of 4 is worth what it is worth. It is the worst
destination row in the set and it rests on four captures, which is enough to
say the stage is weak and not enough to size the work.

Until this was fixed the ordering misled twice over: a family with nothing
scorable scored 1.0 and sorted to the bottom, where a family that passes
everything belongs, and ties broke alphabetically, so a rate over one capture
could sit above a rate over twenty-one. Ranking is now rate first, then
denominator descending, and `Tools/CorpusRunner/test_score.py` holds both.

None of this needs the engine: it is the composition of the label file, so it
changes only when the set does. A retag moves these denominators without
opening a generation — see below.

## Generations

A generation opens when a capture's **text** changes — edited, added or
removed. Numbers never compare across one. A retagged family, a changed note
or a rewritten README is not a generation; family denominators move
independently and are tracked separately where that applies.

| generation | recorded | captures | what changed |
|---|---|---|---|
| 1 | 2026-09-11 | 389 | first record. Generation 1 is this set as it stands today, not a reconstruction of its history. |

`Tools/CorpusRunner/generations.tsv` holds the same number for every sealed
set, and `everyday/generation-check.py` reports whether a capture here has changed
without a new row above. **It does not run in CI yet.** Wiring it into the
Linux job is a one-step change to `.github/workflows/ci.yml`, which needs a
permission this repository's automation does not currently hold, so it was
split into its own pull request. Until that merges the check is a command
somebody has to remember to run, which is exactly the state it exists to end —
so read the row above as the claim and this file as unenforced. Run it with

    python3 Tools/CorpusRunner/everyday/generation-check.py

What it proves once wired is narrow and worth stating: it cannot tell a
legitimate new generation from a quiet edit, because they are the same diff.
The row above does the real work — the check only makes the edit impossible to
make silently.

## Baseline

Recorded 2026-08-25, after the contextual-semantic (Phase 2) work. The previous
column is the speech-act scope and prohibitive-reminder baseline it replaced.

| measure | before | after | 2026-09-08 |
|---|---|---|---|
| destination correct | 229/320 (71.6%) | 229/320 (71.6%) | 231/320 (72.2%) |
| thought count correct | 252/310 (81.3%) | 251/310 (81.0%) | 250/310 (80.6%) |
| captures producing nothing | 0 | 0 | 0 |
| genuinely ambiguous captures | 69 | 69 | 69 |
| **acted on anyway** | **9 (13.0%)** | **8 (11.6%)** | **8 (11.6%)** |

The 2026-09-08 column was scored once, non-verbose, after the arguable corpus
cases were decided (`Docs/DECISIONS.md`, same date). The failures were not
read: the one-count movement is recorded, not chased. Scored once more on
2026-09-09 after the development-set pass: identical on every row. Scored a
third time the same day after the forty-capture batch (`Docs/DECISIONS.md`):
destination 230/320, thought count 251/310, nothing produced 0, acted on
anyway 8 — one case each way, not read. Scored again after the two agent
rounds of 2026-09-09 (`Docs/DECISIONS.md`, same date): destination 233/320
(72.8%), thought count 255/310 (82.3%), nothing produced 0, acted on anyway
7 (10.1%). All three rows moved the right way; still not read.

The rules that moved the last row were developed against
`Tools/CorpusRunner/devsets/`, not against these sentences. On that development
set the same change took unsafe actions from 8/22 to 2/32, and only one of them
carried here — which is the honest reading of how much the development families
overlap the ambiguity this set contains, and is worth knowing.

The last row is the one to watch. It counts captures whose meaning a careful
human reader could not pin down, on which the app nevertheless scheduled
something, dated something, or modified stored data. Destination accuracy can
move either way for defensible reasons; that number should only ever fall.

`Ambiguous-preserve` labels come from the original author marking, honestly,
that they could not tell what the speaker meant. They are not parser failures by
construction — they are the cases where guessing is worse than abstaining.

September 9 continuation: one non-verbose evaluation after the date-topic guard
returned the same final baseline: 233/320 destination, 255/310 thought count,
7/69 ambiguous captures acted on, zero missing outputs and zero captures lost.
The scorer now reports dataset origin and actual size rather than calling every
input held-out, and includes empty ambiguous captures in the content-loss count.
The held-out examples and individual failures were not read.
