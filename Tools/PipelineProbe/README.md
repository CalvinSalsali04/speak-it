# Pipeline probe

A standalone runner for the rule-based understanding pipeline. It compiles the
real `SpeakIt/Repositories` sources — not a copy — and prints what the app would
do with each utterance you give it: rows, titles, route, type, category,
priority, due, reminder, delivery, temporal kind, recurrence, person, place,
list and quote.

```bash
./Tools/PipelineProbe/build.sh
./Tools/PipelineProbe/build/probe utterances.txt
```

Utterances are one per line; blank lines and lines starting with `#` are
skipped. With no file arguments it reads stdin.

`--partition-coverage` emits one JSON line per capture with the meaningful
post-repair words left without a retained clause, operation, withdrawn local
target, or source-owned connector. It reads the same production repair and
operation-partition code as the app. An empty `unownedWords` list proves only
this boundary; it does not audit words removed earlier by speech repair.

`--repair-coverage` emits the original word occurrence IDs for which the repaired
text has no surviving origin, plus the stage that first removed each ID.
These are **candidates for classification**, not
automatically defects: fillers, corrections, and normalized compounds can all
appear there. The output is useful for building a raw-source disposition audit
without confusing a licensed edit with silent loss.

The frame of reference is fixed at **Monday 2026-08-03 10:00 America/Toronto**,
matching `SemanticCorpusTests` exactly — so anything you observe here reproduces
as a corpus case, and a corpus case reproduces here.

## Why it exists

Answering "what does the app actually do with this sentence?" through the test
suite means a 4-minute simulator run per question. The probe answers in
milliseconds, which is the difference between checking six phrasings and
checking six hundred. Every finding in `Docs/PipelineSweep/` was produced this
way.

`--tagger-disabled` reproduces extraction without Apple lexical/name assets.
This diagnostic switch is never set by the app.

## What it cannot tell you

It runs the **rules path only** — `RuleBasedThoughtExtractor.process`. It does
not run the Foundation Models refinement, and it has no store, so nothing that
depends on existing items is visible here: capture operations resolve their
targets against SwiftData, and the probe has none. Persistence, reminders,
scheduling and routing-into-the-UI all live above it.

Three files import frameworks that cannot be compiled for the host
(`AlarmKit`, `UIKit`, `CoreLocation`) or need the SwiftData models. `build.sh`
slices the relevant part out of each at build time rather than keeping a
duplicate that would drift:

- `ReminderCopy` out of `ReminderScheduler.swift`
- `PersonMention.swift` up to its Memory-reading section marker
- `LocationIntent.swift` up to the region-monitoring section

If a build fails after those files are restructured, the section markers
`build.sh` greps for are what moved.

## Structured output

`probe --json utterances.txt` emits one JSON object per capture, including items,
source wording, dates as Unix seconds, and detected operations. This is the
input to `Tools/UnderstandingLab/lab.py`; its other modes remain unchanged.
Operation output includes review/broad/scope flags, polarity, requested old/new
timing, source quote, and source/local-target/independent-creation word IDs.
These describe the request; they do not prove a saved-row mutation occurred.
