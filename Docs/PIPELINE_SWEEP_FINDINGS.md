# Pipeline sweep findings

A seven-lane read-only sweep of the understanding pipeline, run 2026-08-24 over
roughly three thousand probe utterances. Each lane replayed real-shaped speech
through the rules path and diffed the result against what the sentence meant.

The full per-lane write-ups live in [`Docs/PipelineSweep/`](PipelineSweep/).
They were produced in a scratch directory and are checked in here because the
analysis — mechanisms, call sites, utterance counts — is expensive to reproduce
and was one reboot away from being lost.

| Lane | Question it asked | Clusters |
|---|---|---|
| [routing](PipelineSweep/routing.md) | does a thought reach Today or Memory correctly? | R1–R12 |
| [structured](PipelineSweep/structured.md) | do lists, recurrences and places survive? | C1–C11 |
| [domains](PipelineSweep/domains.md) | does it handle the content of adult life? | C1–C11 |
| [rambling](PipelineSweep/rambling.md) | do long unrehearsed captures survive? | C1–C11 |
| [register](PipelineSweep/register.md) | dialect, non-native grammar, accented ASR | C1–C12 |
| [people](PipelineSweep/people.md) | are people identified, attached, never dropped? | — |
| [ai-feasibility](PipelineSweep/ai-feasibility.md) | should a model do the categorizing? | — |

## How to read these

Every finding is stated as a mechanism plus a call site, not as a sentence that
misbehaved. That is deliberate: the same defect usually arrives wearing several
different sentences, and fixing the sentence leaves the defect in place. Where a
line number has drifted, anchor on the quoted code — the sweep ran while the
same files were being edited, and the write-ups say so where it applies.

Severity words in the lane files mean:

- **CRITICAL** — the app does something different from what was said, or content
  is destroyed. Blocks a release.
- **BEHAVIORAL** — the thought survives but reaches the wrong place, or loses a
  schedule. Visible to the person; does not destroy words.
- **METADATA / COSMETIC** — a secondary label or title is wrong.

## Fixed since the sweep

### Structure instead of vocabulary

Three decisions that were gated on a hardcoded word list are now gated on
grammar or meaning. This is a different kind of entry from the ones below it:
each closes a whole *class* of defect rather than a cluster, and each was
measured against a negative set built specifically to break it.

The enabling measurement, which reframed all of them: Apple's `NLTagger` is
useless on an isolated fragment — "chicken", "salt", "juice", "vitamins" and
"soap" all tag as **Verb**, while "text", "book" and "water" tag as **Noun** —
but accurate once it is given the whole sentence. `"buy chicken and salt and
juice"` tags all three as nouns. The vocabularies were not compensating for
English being hard; they were compensating for tagging fragments. Both
`NLTagger` and `NLEmbedding` ship with the OS from iOS 13, need no network and
no Apple Intelligence, so unlike the on-device model they are available to
**every** user.

- **A closed grocery vocabulary decided what a shopping list was.** structured
  C7, domains C9. `ShoppingGroupParser.namesOnlyProducts` required *every* word
  of a phrase to be one of ~150 known grocery words, so any brand, adjective or
  unfamiliar product refused the split: "buy organic shampoo and conditioner",
  "buy 2 percent milk and whole wheat bread", "buy dove soap and colgate
  toothpaste" and "buy tylenol and advil" were each **one uncheckable row**.
  A conjunct now reads as a product structurally — no determiner, no
  preposition, no pronoun, no conjunction, no auxiliary, no temporal cue, four
  words or fewer — with the vocabulary demoted to *positive evidence that can
  only rescue, never refuse*. The closed grammatical classes it tests are
  complete by definition, which is what makes this grammar rather than another
  list. Measured: **21 of 130 positives → 128 of 130, with 0 of 90 negatives
  changed** (including the shopping-verb idioms "buy time", "get some rest",
  "get going", "pick up the pace", "grab a coffee with Priya"). Cost: +0.34 ms
  per capture. Also fixed in passing: a trailing store phrase ("…at Costco")
  made the last conjunct a prepositional phrase and refused the split, even for
  pure-vocabulary lists.

- **Occupations were filed as people.** `PersonMention.commonObjects` listed 63
  words, and every ordinary trade noun outside it became somebody's name:
  **30 of 30** tested — roofer, notary, caterer, locksmith, arborist, glazier,
  appraiser, upholsterer, exterminator — produced `person: Roofer`, shown on
  the row and used to address the Messages composer. This is the worst failure
  shape in the app: a confident, visible, actionable wrong answer. `NLEmbedding`
  answers it by meaning — occupations sit measurably nearer to a dozen
  occupation seeds than personal names do — with agent-noun morphology
  (-er/-or/-ist/-ian/-smith) breaking ties in the overlap band. Measured over 30
  trade nouns and 36 personal names, chosen to include the ones that are
  ordinary English words (Rose, Grace, Will, Dawn, Heather, Sage) and the
  surname-shaped ones ending in -er (Tyler, Parker, Sawyer, Carter):
  **28 of 30 occupations blocked, 0 of 36 names lost.** The asymmetry sets the
  thresholds — failing to block a role leaves today's behaviour, while blocking
  a real name would take a person off a row.

- **Errands needed a determiner to reach Today.** `hasImperativeShape` required
  one ("sharpen *the* knives"), and spoken errands drop it constantly, so a
  112-verb list was all that stood between "sharpen knives" and Memory. Since
  the tagger cannot read a bare fragment, a determiner is *inserted* and the
  tagger asked about the result — paired with a reading of the original, because
  a fragment whose head already tags as a noun is a noun phrase. Two further
  guards were forced by measured regressions: a later token tagging as a verb
  means subject-verb-object rather than imperative-object, and a head the
  embedding does not know is a proper name. Without them "Sarah likes sushi"
  became a task on Today. Shipped as a **union** with the existing tests, so it
  can only ever add an actionable reading. Known boundary: a head verb outside
  the embedding's 57,000 words ("descale") is declined.

- **List commands were one memorised sentence.** `canonicalizedListCommand` knew
  only "add X to my shopping list", so "create a shopping list for Shoppers
  tomorrow to buy shampoo" produced a single generic task titled with the whole
  sentence. It is now parsed as a **frame** into slots — command verb, list
  name, store, time, contents — and rewritten to the errand it means. That is
  legitimate where the shopping vocabulary was not: English has a handful of
  ways to ask for a list, while the things that go *on* one are unbounded. The
  store is attached only to the text the store detector reads, never to a
  segment's analysis text, because a trailing "at Costco" is not a product and
  made the last conjunct unreadable.

Covered by corpus families 42-45 in `SemanticCorpusDataI.swift`. Families
36-38 in `SemanticCorpusDataG.swift` were also given test runners: they had
none, so a blocking regression in them appeared only in the summary report that
never fails — which is how a real regression in `renderingLoss` went unnoticed
during this work.

- **A repair was editing the person's own words.** domains C6. `ClockDigitRepair`
  rewrites a 3-4 digit number after `at|for|by|around|until|till|alarm|timer`
  into `H:MM`. Its guard list named five predicates and no unit of measurement,
  so "the rate holds for 120 days" became `1:20 days` and "we're at 142 on the
  odometer" became `1:42` **with a fabricated due of 13:42**. The rewrite lands
  in `sourceQuote`, so this did not merely mis-schedule a row — it changed what
  someone said. The guard now reads amount nouns in front of the cue
  (`the invoice is for…`), first-person position (`we're at 142`), appliances
  (`set the oven at 450`), and roughly forty units behind the digits; the
  24-hour rule no longer reads `by 2030` as half eight. Measured over 59
  quantity utterances and 40 clock utterances: **42 corruptions before, 4
  after, with no clock reading lost** and zero corpus diffs. The lowercase
  address case (`she lives at 425 king street`) was a rendering-invariance
  break and is fixed with it. Covered by corpus family 43.

  Four holdouts remain, each unfixable without a measured cost: `she shot at
  350 in the tournament` (a `shot` guard silences "get your flu shot at 315"),
  and `bake at 425 for 30 minutes` / `roast the chicken at 400 for an hour` /
  `keep it at 500 for 20 minutes` (cooking-verb guards silence "meet at 630 for
  an hour").

- **Filler was costing whole errands, and the dates on them.** rambling C3.
  `IntentConsolidator` is a deliberate veto that may only collapse a capture to
  one item, and three gaps let ordinary spoken noise trip it: `DisfluencyFilter`
  never stripped a leading "I mean", `leadingFiller` never listed "right",
  "like" glued between an infinitive and its verb hid the verb from both the
  splitter and the obligation reader, and "while I'm thinking about it" made the
  clause behind it look like commentary. So "um right so I mean the meeting is
  uh Thursday at 2 and I still need to like finish the slides" produced **one**
  row and threw away a stated Thursday 2 PM. It now produces two, with the
  meeting on Thursday at 14:00. "…pay the hydro bill it's due the eleventh"
  recovers its August 11. "I always forget to" joins its own family in
  `isUnfulfilledObligation`, so it reaches Today instead of the fallback label.
  The narrative guard still holds: the capture `IntentConsolidation.swift`
  documents itself with is still one row. Covered by corpus family 42.

  Not closed: elided-verb conjuncts still do not split, so "I always forget to
  pay the hydro bill and also the water bill and also the gas bill" is one row
  rather than three. Recorded as a capped case.

- **A hard cap of 12 rows silently destroyed errands.** rambling C4. Two
  separate bounds did it — `prefix(12)` on the segments, and a `break` in
  `expandingPlainShoppingLists` that discarded every item past the limit,
  shopping or not. Fifteen spoken errands became twelve, and errands 13-15
  existed in no field of any row. The bound is now 20 and it folds rather than
  truncates: overflow becomes one review row carrying every remaining quote, so
  the words stay on screen and the person is told there is more to sort. The
  expansion limit no longer governs whether a thought survives at all. Covered
  by `testLongCaptureKeepsEveryErrandUpToTheRowCap` and
  `testOverflowPastTheRowCapFoldsIntoOneReviewRowInsteadOfVanishing`.

- **Verified closed on re-probe, 2026-08-24 evening.** Four clusters the lane
  docs still list as open no longer reproduce — every documented exemplar was
  replayed through the probe:
  - *rambling C1* (segment cleaner ate the first letters of words and names):
    all 8 exemplars intact — "Andrew", "Sonia", "Sophie", "something",
    "sort of", "software" all survive in title, quote, and person.
  - *structured C1* (missing `\b` truncated titles mid-word before "remind
    me"): all 8 exemplars intact — no "When I l", "Call my husb", "St". The
    `\b` now in `ReminderScheduler.swift` is the fix the doc predicted.
  - *structured C2* (digit quantities destroyed in shopping rows): "buy 3
    apples and 2 bananas" keeps its numbers. Downgraded, not closed: the
    comma-less list no longer splits into rows at all (1 row instead of 2),
    which is a BEHAVIORAL split miss rather than CRITICAL destruction.
  - *register C5* ("Oh"/"Ah"/"Er" deleted from inside names): Mr Oh,
    Oh Se-hun, Ah Mei, Ah Ma, Ah Gong all preserved with correct person
    labels. Residual: "Er Tan" keeps title and quote but the person label is
    nil.

- **The complementizer English drops.** Found on a physical iPhone, not by
  replay. `ThoughtExtractor.actionLeadPattern` spelled the reminder lead as
  `remind\s+me\s+(?:to|that|about)`, so the elided form people actually speak —
  "remind me I have a meeting at 4:15" rather than "remind me *that* I have" —
  matched nothing and `splitClauses` found no boundary. In the capture that
  exposed it, the tail of a shopping list absorbed the rest of the sentence:
  "Tomorrow, call dentist at 9 a m and go Costco and get bread, cheese, and
  eggs, and also remind me I have meeting at 415 p.m." produced five rows, the
  last titled "Tomorrow eggs, and also remind me I have a meeting at 4:15 p.m"
  and filed under Events. It now produces six, and the reminder keeps its 4:15.
  The same missing word cost the row its title a second time in
  `ReminderCopy.strippedAction`, which also demanded an explicit "that".
  The replacement admits nominative pronouns ungated, and possessives and
  determiners only behind a finite verb and never on a temporal head noun, so
  "remind me at 5", "remind me the day before it is due" and "remind me my gate
  number" still do not split. Measured over 251 utterances: 69 of 168 positives
  failing before, 6 after, with 0 of 83 negatives and 0 of 731 corpus cases
  changed. Covered by corpus family 40 (`SemanticCorpusDataI.swift`) and
  `testReminderTitleDropsTheHaveFrameWithOrWithoutThat`.

  One shape is **not** fixed and is recorded as a capped case: a comma with no
  connector behind it ("Book the flight, remind me I have a meeting") splits
  correctly with the comma and stays one row without it, because
  `actionLeadPattern` is the only boundary mechanism there. Closing it means
  teaching `ClauseJuxtaposition` a reminder opener gated on a real complement.

- **Proposals wearing a hedge reached Memory as notes.** Related to routing R5,
  from the same device capture. "I think it'd be cool to have a feature that
  integrates Google Calendar" was typed `note`/`general` — the right destination
  but the wrong surface, so a product idea never appeared in Ideas. The
  proposal patterns in `ThoughtOrganizer.readsLikeIdeaProposal` were anchored at
  `^`, which a hedging preamble defeats, and the contraction "it'd" was not
  spelled at all. The anchor is kept — dropping it fires the rule from inside
  subordinate clauses and from the leading day an item inherits, which is
  rendering-dependent by construction — and the hedges are enumerated instead.
  Measured over 146 utterances: positives correct went from 13/80 to 62/80, with
  0 corpus regressions.

  The same change adds a **deadline veto** on the proposal frames, which fixes a
  worse defect in the opposite direction: "maybe I should text Sarah tonight"
  and "maybe I should go to the gym at 6" were filed as ideas, and because
  `idea` is not actionable they lost the time they had already resolved —
  breaking the invariant `Actionability` opens with. The veto is deliberately
  narrower than `ActionabilityReader.calendarCue`, whose bare "today"/"tomorrow"
  word list collides with Speak It's own surface name and vetoes real proposals
  like "a widget that shows today's tasks". Covered by corpus family 41.

  Still open, and outside this rule: `isHedgedAspiration` and
  `readsLikeIdeaProposal` both hardcode "it would be nice to" with opposite
  conclusions, and the knowledge gate runs first, so `it would be nice to add
  dark mode` is a note while `it would be cool to add dark mode` is an idea.

- **One word dictated as two.** The recognizer wrote "Tomorrow" as `To morrow`
  during the first-run tutorial on a physical iPhone. Every temporal alternation
  in the app matches whole tokens, so the fronted time was invisible to
  `ThoughtExtractor.leadingTemporalContext`, its phantom-item guard never fired,
  and one capture became a 9 PM event in Events plus a follow-up with no due
  date. Fixed by `SplitCompoundRepair` in `SpeechRepair.swift`, which runs first
  in the repair chain. Covered by corpus family 39 (`SemanticCorpusDataH.swift`),
  including guards for the spaced pairs that are ordinary English — "some time",
  "after noon", "every day", "day to day" — which must never be rejoined.

- **A misread operation no longer takes the capture with it.** rambling C2,
  domains C5, routing R11. `applyCaptureOperation`'s zero-match branch called
  `discardCaptureItems`, and the call sites took the operation branch *instead
  of* `organizePersistedCapture` — so a clause like "cancel the cable" inside a
  four-errand capture deleted all four. The zero-match branch no longer
  discards; when the same capture also yields creatable items, the caller
  re-reads the **whole transcript** with `permitsOperations: false` and creates
  them. Reading the whole transcript rather than the remainder matters: the
  operation clause is carved out of the remainder, and in some captures those
  words survive nowhere else — not in a title, not in a quote. Covered by
  `testAMisreadCancellationDoesNotDestroyTheOtherErrands` and
  `testAMisreadCancellationKeepsTheDatedErrandBesideIt`.

  **Deliberately still open:** a *single-clause* unmatched operation
  (`cancel my Spotify`, with no Spotify row) still produces no item. The fix
  above is gated on the capture having other creatable content, because
  `testCancelWithNoMatchInventsNothing` and five sibling tests pin the opposite
  contract — "Cancel the dentist reminder" with no dentist reminder must invent
  nothing, and a repeated cancellation must stay harmless. Telling those two
  apart means deciding whether the target names an app row or a real-world
  thing, which is its own piece of work and its own risk. Doing it by widening
  the fallback would break a contract that exists on purpose.

- **"actually" no longer licenses a discard.** domains C1. Most of that
  cluster was already closed by the `mayDiscardWords` guard; what remained was
  `actually`, which sat in `unambiguousMarker` and so let the resolver throw
  away the words in front of it. "Tell Sam the client actually approved it"
  became "Tell Sam approved it"; "check whether the standing desk actually
  helps" became "Check whether helps" — the subject of the sentence, deleted.
  `actually` stays in the *detection* pattern, so a genuine unpunctuated repair
  is still found and placed by `repairSlot` / `echoesThePrefix`; it is now
  absent from the new `discardingMarker`, which is the set allowed to discard.
  Covered by `SpeechRepairTests`.

- **Plurals of common nouns were invented as people.** domains C7, rambling C9,
  routing's secondary observation. `neverName` is written in the singular and
  was looked up exactly, so every plural walked straight past it: "call note
  about the thing" filed nobody while "call notes about the thing" filed a
  person called Notes — and the same singular/plural split held for reports,
  invoices, reminders, packages, deadlines and lists. Membership now folds a
  trailing "s", and the document nouns that sit where a name sits ("meeting
  notes", "meeting agenda") were added to `commonObjects`.

  Only a trailing "s" is folded, deliberately. Richer stemming buys almost
  nothing — the plurals that matter are regular — and costs real names:
  stripping "es" turns "Ames" into "am" and "James" into "jam", which is how a
  stoplist starts rejecting people. Chris, James, Miles, Agnes and Jess are
  pinned in `PersonMentionTests`.

## Convergences worth noting

Several lanes reached the same root cause from different directions. Those are
the highest-value fixes, because one change closes findings in three write-ups
at once.

1. **A capture that names nothing to act on is deleted outright.**
   rambling C2, domains C5, routing R11. `applyCaptureOperation`'s zero-match
   branch calls `discardCaptureItems`, and the call sites take the operation
   branch *instead of* `organizePersistedCapture`, so a misread `cancel …`
   destroys every row of the capture. The transcript survives on
   `CaptureSession`; nothing reaches Today or Memory.

2. **Alternations with no `\b`, followed by a separator that matches nothing,
   cut the opening letters off the next word.** structured C1, rambling C1.
   Partly closed by corpus family 36 (`wordInterior`).

> **Re-validate before working a cluster.** The sweep ran while the same files
> were being edited, so its counts are a snapshot, not the current tree. Every
> cluster has since been re-probed — see [Measured status](#measured-status-2026-08-24)
> below — but the per-lane write-ups still carry their original counts. Use
> `Tools/PipelineProbe/build/probe` to confirm a defect still reproduces before
> designing a fix for it.

3. **Clause splitting fires on nouns whose head word is a verb homograph** —
   "the tax return", "the water filter", "the coffee order". domains C2,
   routing R3, structured C3.


## Measured status (2026-08-24)

Every cluster in all six lanes was re-probed against the tree on 2026-08-24,
replaying the write-ups' own cited utterances through
`Tools/PipelineProbe/build/probe`. This replaces the counts in the lane files,
which were written mid-edit and understate what has since been fixed — and, far
more often, overstate it.

| Lane | Clusters | Fixed | Partial | Still reproduces |
|---|---|---|---|---|
| routing | R1–R12 | 0 | 0 | 12 |
| structured | C1–C11 | 1 (C1) | 2 (C2, C11) | 8 |
| domains | C1–C11 | 1 (C1) | 1 (C11) | 9 |
| rambling | C1–C11 | 1 (C1) | 1 (C2) | 9 |
| register | C1–C12 | 0 | 1 (C5) | 11 |
| people | P1–P14 | 1 (P3) | 0 | 13 |
| **total** | **66** | **4** | **5** | **62** |

So the backlog is roughly **6% closed**. The four genuinely closed clusters are
all of one kind — a regex that matched inside a word, fixed by adding `\b`
(structured C1, rambling C1, people P3) — plus domains C1, which measured 13 of
13 fixed. Everything else in the sweep is live.

Two clusters need a store and are only confirmed up to the rules boundary:
domains C5 / routing R11 (a `cancel …` capture with no matching row) and
structured C5's geofence consequence. The probe has no SwiftData, so the final
outcome there needs the simulator.

One regression surfaced during the audit: the fix that stopped structured C2
deleting digit quantities also made `recognizedProducts` reject the digit token,
so `buy 3 apples and 2 bananas` no longer splits at "and" — it is one row now,
where it used to be two rows with the quantities destroyed. The CRITICAL half is
genuinely fixed; the failure moved into C7(a)'s mechanism.

### How much of this is transcription's fault

Almost none of it, which was the open question.

A 100-utterance holdout of ordinary everyday speech — 60 drawn from families the
sweep already flags, 40 written fresh and checked not to appear anywhere in
`Docs/PipelineSweep/` — was scored on destination only (did the thought reach
Today vs Memory), then replayed through progressively worse transcription.

| | flagged-family set (60) | fresh set (40) |
|---|---|---|
| clean, cased, punctuated | 73% | 78% |
| lowercase, no punctuation, filler, split compound, homophone | 73% | 78% |
| the above plus a self-repair and a dropped article | 75% | — |

The degraded failures are a **strict subset** of the clean ones: across all
three tiers, no utterance was routed correctly when clean and incorrectly when
degraded. The corpus agrees — of its 697 utterances, 6 behave differently
lowercased, and `RenderingInvarianceTests` reports 0 CRITICAL and 0 BEHAVIORAL
for both comma-free and fully unpunctuated rendering.

The conclusion is that **rendering robustness is largely solved and rule
quality is not**. Roughly a quarter of ordinary sentences reach the wrong
surface with a perfect transcript, and making the transcript realistically bad
costs close to nothing on top of that. Work aimed at the recognizer, or at more
repairs, will not move the number that matters; the routing lane will.

The one real exception is **spoken self-repair**. "call sara no wait sarah
tomorrow" keeps the route but files the *first*, misrecognized name, and the
discarded alternative stays in the row title verbatim. Measured over 25
utterances carrying a repair, route and meaning survived 20 times, but only 6
rows were clean enough to accept without editing. The repair machinery fires
reliably for a repeated temporal ("at 9 no wait at 9:30") and not for nouns,
names or list items. That is the highest-value transcription-side work left, and
it is a much smaller job than the routing backlog.
