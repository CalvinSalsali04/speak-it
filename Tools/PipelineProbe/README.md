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

The frame of reference is fixed at **Monday 2026-08-03 10:00 America/Toronto**,
matching `SemanticCorpusTests` exactly — so anything you observe here reproduces
as a corpus case, and a corpus case reproduces here.

## Why it exists

Answering "what does the app actually do with this sentence?" through the test
suite means a 4-minute simulator run per question. The probe answers in
milliseconds, which is the difference between checking six phrasings and
checking six hundred. Every finding in `Docs/PipelineSweep/` was produced this
way.

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
