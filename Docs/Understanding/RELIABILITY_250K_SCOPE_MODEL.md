# 250K reliability: capture frames and entity phrases

**Historical development record.** The campaign is closed at Candidate47;
[the final report](FINAL_RELIABILITY_REPORT.md) supersedes pending gates and
promotion instructions below. Rejected candidates remain evidence only.

The immutable baseline is stored separately under the original workspace's
`output/reliability-250k/baseline`. Its source snapshot includes the existing
conditional-intent patch. Neither the bank nor that baseline is modified.

## Explicit memory scope

First loss: clause splitting treats an imperative inside an explicitly framed
idea as a new action. Operation extraction can likewise treat a refusal to
create a reminder as a cancellation of a stored reminder. Actionability then
sees the content without its governing frame.

Invariant: explicit thought/idea/note framing owns its content, including
imperatives, negation, dates and recurrence. It creates no executable timing or
capture operation. An independently addressed task request ends that scope.
General framing vocabulary is shared across extraction and organization.

Modal-perfect reflections, unreal past and explicitly abandoned plans remain
knowledge. This does not change the existing interpretation of an outstanding
obligation or an instruction addressed to the user through reported speech.
The bank's blanket note contracts for reported user instructions require
adjudication; they are not sufficient reason to erase established tasks.

## Entity phrase evidence

First loss: the personal-name reader truncates a target to one/two tokens before
consulting organization evidence. A communication verb is compatible with a
business, department, service or person and cannot establish personhood.

Invariant: resolve the whole bounded nominal target before selecting a personal
name. Institution/department/topic heads and native organization tags outweigh
capitalization. A following `at <organization>` adjunct does not erase the
person before it. No brand names or full failed utterances are enumerated.

Native organization evidence is corroborated in a neutral sentence before it
overrides a personal name. Conflicting evidence holds the item for review and
clears execution timing. This protects people whose names can also be brands.
The particle in acquisition/transport verbs belongs to the predicate; its
following object is not a second communication command.

## Withdrawal, condition and exact-value scope

Terminal withdrawals apply to their in-capture group, including unfinished
date-fronted instructions. Attributed speech and names containing withdrawal
words retain their existing protection. Trailing conditions remain attached to
their consequence; temporal prefixes are not mistaken for a second condition.
Formatting constraints after a dictated identifier do not act as corrections,
while an actual replacement identifier still replaces the earlier value.

## Batch validation

The 1,891-case development subset is selected deterministically from frozen
baseline differences, with no bank edits. On build 8, task/object-person flags
fell from 1,331 to 154, non-person/person flags from 358 to 214, and confident
non-actionable flags from 111 to 37. These are candidate differences on a
targeted sample, not global accuracy or confirmed-defect counts. The tested
negation, lost-condition and empty-contract confident-action flags reached zero.

All 43 independent contrastive controls passed. Cancellation remains 187/187;
conditional intent remains 72/72. The trusted corpus remains 1,434 cases with
zero critical, behavioral or metadata failures and one pre-existing cosmetic
mismatch. The Release build and full frozen 250K comparison are separate gates.
Simulator NaturalLanguage asset failures remain an infrastructure issue; no
parser accommodation or repeated simulator repair was attempted.

## Consolidated follow-up batch

The next batch extends the same invariants:

- Recording a number/code or an explicitly framed fact remains Memory through speech repair. Recurring factual schedules never arm reminders.
- Unsupported recurrence bounds, event-relative offsets without a known event time, and reminder time windows remain visible for review without executable timing.
- Explicit named time zones use the system time-zone database; relative calendar days with an explicit clock preserve that wall clock.
- Missing action objects and unfinished conjunctions remain incomplete. Closing discourse and reaffirmations do not invent replacement objects.
- Proper-name interpretation uses neutral NaturalLanguage evidence without requiring uncommon human names to appear in a dictionary. Unresolved organization-like identifiers remain reviewable.
- Fronted dates inherit only where a sibling has no day of its own. Spoken calendar ordinals are not discourse enumerators.
- A single purchase can retain an immediately preceding generic destination as one errand. Multi-product lists keep their checkable rows; merging cannot demote an actionable purchase.
- Ordinal repair references to prior items are preserved for review instead of being misread as replacement calendar dates. This is safely unsupported reference binding, not a claim of resolved intent.

All source and raw-output identities are recorded in the campaign artifacts. Candidate 13 passed the protected fixtures, trusted CorpusRunner, unsigned Release and whitespace checks. Later consolidated-candidate results are recorded in their validation JSON; pending gates are not passes.

The first full post-baseline campaign was superseded after a partial run revealed additional root causes. Its raw outputs remain diagnostic evidence only. The next full run uses a separately frozen source snapshot and the unchanged bank and evaluator. Its six independent parser workers are a throughput setting, not a change in product interpretation. Local model readings remain blinded until the comparison stage.

## Message ownership and event binding

The communication request belongs to the user; its attributed content does not
become an app instruction. Temporal organization reads the matrix request
separately from explicit, implicit, quoted and delegated message content.
Operation partitioning and thought splitting share quotation and attributed-actor
boundaries. Coordinated commands retain their reported or delegated actor.
A new explicit reminder or a completed sentence can establish an independent
request. Apostrophes and numeric unit marks do not open quotations.

Established reminder conventions remain intact: “remind Alex” notifies the phone
owner, and a bare outer reminder may inherit an implicit trailing clock.
The first actual reminder/alarm request determines delivery; an alarm mentioned
inside a reminder's action cannot change a notification into an alarm. A day-only
implicit delegation deadline may govern the communication without licensing an
embedded clock, recurrence, location trigger or operation.

Restoring content also restores its semantic scope. When an event cannot be
bound, retained actions remain together for review without executable timing;
known actionable type and recipient metadata survive. An explicitly independent
request is processed separately. A location trigger elsewhere in a capture
cannot absorb earlier actions into a shared reminder prefix or supply their
recipient.

A coarse calendar modifier does not supply the missing time of an unobservable
event. “After class tomorrow morning” still has no class-end time. Clausal event
binding requires a concrete clock or anchored duration; bare temporal noun
phrases retain their established calendar/day-part meanings. Unknown nominal
events remain conditional, while anaphoric sequencing and incomplete action
objects are not mistaken for trailing event conditions.

The frozen corpus is unchanged. The later context-preserving review title adds
one intentional cosmetic difference to the existing punctuation difference;
critical and metadata gates remain zero-tolerance. One behavioral expectation is explicitly qualified: a notification before an office-closing event stated only by date must instead retain its words in review without executable timing. The unchanged corpus expectation conflicts with the unknown-event invariant; all other behavioral differences remain blocking. Candidate-level
validation files distinguish completed gates, rejected candidates and isolated
prototypes. A passed gate alone never promotes a candidate with a confirmed
remaining safety failure.

## Candidate33 residual architecture

Speech-act labels survive introductory discourse and fillers: an explicit thought, question or literal-value storage request stays in Memory. Prefix-only normalization avoids recursively invoking the full speech repair pass. Independently framed dated or clocked actions close that scope. Genuine future instructions to save a thought remain reminders.

Clause splitting cannot cut a determiner/adjective object from its verb-shaped noun. This keeps prohibitions on a hard drive, portable drive, expensive watch or new iron intact. Bare product-list inference checks the spoken subject/predicate before prepending an artificial buy verb; factual comma clauses remain notes. Both changes use grammatical scope rather than bank phrases.

A fronted calendar adjunct before a reminder is that reminder's day, not a separate action deadline. Relative day/week prefixes obey the same rule. When a user genuinely states a separate deadline and alert, the alert keeps its own temporal intent: a date-only deadline cannot overwrite an explicit five-o'clock notification with a default morning or evening hour.

Immediate demonstratives after a preposition keep their grammatical role even if the host tagger calls them conjunctions. This makes restored after-that actions independent of the recipient's spelling while preserving inherited clock context. With no supplied context, the same deictic instruction remains in review.

All immutable snapshots and rejected-candidate evidence remain separate. Candidate33 promotion requires protected187/72, same2044 comparisons, focused residual/control suites, qualified unchangedCorpusRunner, Release and diff checks. The actual250K original baseline is never repeated.

## Candidate34 inherited calendar identity

The action reader and the splitter now share one complete calendar-prefix reader. A structural peel is retained when it exposes a trusted action verb; otherwise the full calendar prefix is removed from the action reading. This keeps first-buy sequencing working while preventing end-of-month or long day/clock prefixes from turning restored actions into notes.

A bounded calendar phrase after the before-I-forget discourse idiom remains a shared date, including for sibling actions. The idiom reader accepts only a complete recognized calendar suffix; an actual unobservable forgetting event still requires review. The exact spoken context remains in the source quote, while the display copy can omit discourse wording.


## Candidate35 cancellation ownership
The candidate34 full-run early check exposed a real selective-cancellation regression, preserved in iteration-3 partial evidence. A later independent action must not provide the subject/predicate that falsely turns a preceding topical message into a clausal message. Read the initial complement before independent command coordinators; retain genuine reported/quoted/delegated propositions.
Explicit restart-marked cancellations are resolved before object repair only when the action description matches exactly one sibling. Ties remain intact for review with no executable timing. Removing a first sibling transfers its original framing to survivors; a canceled visit owns adjacent acquisitions but not an independent call. Quoted and attributed corrections remain content. This is local capture association, not permission to operate on unrelated stored items.


## Candidate36 calendar slot ownership
A calendar correction is not a replacement noun object. Match whole named dates, prefixed weekdays, ordinal month dates and relative day/week values before clock/object repair. Preserve explicit clocks and carry relative calendar context and dayparts to every sibling. A remaining unknown event condition stays in review even when its calendar day is stated. Purpose-for introduces a nominal object rather than a bare contact imperative. The isolated full1298 correction.date study improved656cases with12 qualified new differences; optimized and broad regression validation remains required. Candidate35 full bank stays frozen and independent.
