# Long-capture mechanism research — September 25, 2026

This is design input, not release evidence. The September 24 long-capture gate
is a development set. A new independently authored set is still required after
the production candidate is frozen.

## Findings that affect the current failure families

- Speech-repair research separates the **reparandum** (replaced words), the
  **interregnum** (editing cue), and the **repair** (replacement words). That
  structure is useful for a typed local edit receipt: the old intention,
  correction marker, and new intention must each retain source occurrence IDs.
  It also explains why a marker such as “actually” alone cannot justify
  deleting the preceding action. See [LARD, LREC 2022](https://aclanthology.org/2022.lrec-1.249.pdf)
  and the [deep_disfluency annotation format](https://github.com/clp-research/deep_disfluency).
- [TheirStory's transcript aligner](https://github.com/theirstory/ts-aligner)
  demonstrates edit-distance mapping from corrected words back to ASR words.
  Speak It already uses local word-occurrence provenance. Its stronger product
  requirement is to **audit what alignment did not explain**; a plausible
  alignment is not itself proof that a deleted spoken intention was withdrawn.
  No JavaScript dependency is needed for that invariant.
- [Audio MultiChallenge, ACL 2026](https://aclanthology.org/2026.acl-long.1654/)
  evaluates instruction retention and mid-utterance backtracking in natural
  speech. This supports scoring whole captures, including edits and tail
  retention, rather than averaging isolated sentence accuracy. Its reported
  benchmark scores do not estimate Speak It's quality and cannot replace a
  fresh product-specific gate.
- [Otter's action-item view](https://help.otter.ai/hc/en-us/articles/5093228433687-Conversation-Page-Overview)
  links generated actions back to their place in the transcript. The useful
  product pattern for Speak It is reviewable source evidence beside each
  extracted row, especially when an action was corrected or held for review.
  [Voicenotes](https://help.voicenotes.com/en/articles/15391456-how-to-use-voicenotes-on-android)
  likewise exposes the full transcript alongside generated structure. These
  are interface references, not evidence that either product meets this gate.

## Product application

1. Keep each source word occurrence and clause owner through repairs.
2. Let a correction replace only its identified local intention. Chain edits
   in spoken order so the final replacement supersedes the same intention.
3. Carry reporting and quotation ownership into operation detection. An
   imperative inside another speaker's report must not become executable.
4. Keep ambiguous or unexplained source in a visible review row.
5. Evaluate 10–25 and longer independent intentions as individually reachable
   rows, with no silent count cap.

These are local representation and release-gate rules. They do not motivate a
new broad semantic-map architecture or Foundation Models segmentation pass.

## Completion reports with a following result clause

The current development candidate now has a bounded local completion
receipt for a unique same-verb/action-object antecedent followed by a
result-state clause (for example, a booked visit or confirmed appointment).
Without a spoken replacement group, it records the completed action and result
as one grounded Memory with the whole original prefix in its quote. With an
explicit replacement group, it attaches that source to every resolved member
action and creates no extra Memory or saved-task operation. A duplicate-output
warning is attached only when it names the withdrawn target. Competing action
objects, actors, and duplicate same-verb antecedents remain in visible review.
This is development regression progress, not long-capture qualification.

The original local-completion problem was structural: the matcher
passed every word after “already called” as though it were the called object.
In “already called and the visit is booked”, that tail is a second proposition;
in “already called and the electrician answered”, it introduces another
participant. A replacement decision needs a typed report with a past action,
an optional explicit object, and one or more result or independent clauses.
On the pre-change shipping-rules probe, three different implicit-result reports
(visit booked, appointment confirmed, reply in), an explicit-object report
with an added result, and four competing-object/actor controls all remained
visible in review. A separately punctuated “I already called. The visit is
booked.” withdraws the local call and retains factual Memory rows. This
matrix shows a general tail-boundary failure rather than one missing phrase.
A bounded result-clause split was prototyped and reverted: it withdrew the
just-spoken call but then emitted separate resolved “I already called” and
“the visit is booked” notes with no plumber identity. Source survived in the
capture, yet the structured meanings were unusable. A valid fix must carry the
withdrawn action's object and source occurrence IDs into a typed local edit
receipt, then bind the completion report and its result to that identity before
row creation. Splitting the tail alone does not satisfy the invariant.
[Universal Dependencies' coordination guidance](https://universaldependencies.org/v2/enhanced.html)
distinguishes shared arguments from separate subjects, and its
[relation inventory](https://universaldependencies.org/u/dep/all) distinguishes
passive auxiliaries from active predicates. This is useful as a representation
check, not a parser to ship. Apple's [NLTagger](https://developer.apple.com/documentation/naturallanguage/nltagger)
offers token lexical classes and lemmas, but does not document dependency or
coreference edges. [Stanford OpenIE](https://stanfordnlp.github.io/CoreNLP/openie.html)
splits entailed clauses, yet a Java server/model pipeline is not a suitable
local-first iOS 17 dependency here. Any deterministic rule must prove its
opposite case: a new actor or competing object cannot authorize withdrawal of
the just-spoken action. Until it can, the existing visible review hold is the
safe outcome.

## Source ownership across nonadjacent speech

- The [GUM annotation layers](https://gucorpling.org/gum/annotations.html)
  distinguish source spans, entity coreference and bridging, and discourse
  relations such as elaboration and explanation. They also allow secondary
  edges when a relation crosses the ordinary sentence tree. That is the
  relevant design pattern for Speak It: a later detail may attach to an
  earlier Memory across an intervening task, while one event context may own
  several separate actions. The app needs only a small typed edge vocabulary
  with exact source occurrence IDs, not a general RST parser.
- [DISRPT's public task format](https://github.com/disrpt/sharedtask2021)
  represents discourse units as nonoverlapping source spans and relations as
  directed links with token indices. Its treatment of discontinuous units
  reinforces the need to keep a Memory's source evidence as several ranges
  when later elaboration is separated by another intention. A concatenated
  quote is a display aid, not a substitute for those ownership edges.
- [Incremental Coreference Resolution in Constant Memory](https://nlp.jhu.edu/incremental-coref/)
  publishes an open implementation, but its linked best checkpoint is a
  1.7 GB PyTorch model. That is not a drop-in iOS 17 dependency for this V1
  path. We should first represent bounded explicit references
  deterministically, review ambiguous links, and measure whole-capture
  behavior before considering any narrow on-device adjudicator.
- Apple's [Natural Language framework](https://developer.apple.com/documentation/naturallanguage)
  documents segmentation, lexical tags, language and named-entity features;
  it does not supply a documented coreference resolver. The open-source
  [Coreferee](https://github.com/richardpaulhudson/coreferee) and
  [fastcoref](https://github.com/shon-otmazgin/fastcoref) projects show possible
  coreference approaches, but both are Python/model pipelines rather than
  ready Swift/iOS 17 components. They are research inputs for the narrow
  owner-link question, not dependencies to add to this release candidate.

## Remaining group-owner invariant

The exposed development captures now show one recurring representation gap:
source that describes a **group** of distinct intentions becomes an extra
resolved Memory because each segment is organized as a row before its owner is
known. This includes a forward event frame, a retrospective explanation, and
one deadline said once for several steps. The same gap can also assign a date
to the nearest action when the speaker meant the whole group.

The next mechanism should give every source unit a role and a stable target
set before row creation: independent intention, context for a named group,
detail of one Memory, correction/withdrawal of an identified intention, or
unresolved source. A context edge may point to several intentions without
merging them. Timing is interpreted only after those targets are fixed;
individually stated dates override the shared date. If count, referent, or
episode boundaries do not identify the same group, retain the context in a
visible review row. Opposite controls need an unrelated Memory between tasks,
two competing groups, a later task with its own date, and an ordinary fact
about the event that the user wants to retrieve separately. This is a small
typed ownership graph over the existing occurrence ledger, not a new semantic
map or a Foundation Models segmentation experiment.

## September 26 development clustering after the source-edge work

The 40 already exposed September 24 captures were run again through the
production-source rules probe. **Only ordered row count and Today/Memory
destination** were compared; this is not a whole-capture score and cannot be
release evidence. The matching counts by family are: clear multi-task 4/4,
natural rambling 0/4, coherent single Memory 4/4, mixed Today/Memory 3/4,
corrections 2/4, shared context 4/4, quote/report 4/4, alternatives 1/4,
capacity 4/4, and beginning/middle/end 0/4. The clear and capacity cases
still need semantic, timing, source-owner and integrated-device scoring.

The remaining excess rows cluster across rambling, alternatives and
beginning/middle/end captures. A proposed/rejected option, speech about the
capture's output, and a recap of a preceding Memory are currently eligible
to become standalone Memory or Today rows before their discourse role is
settled. The same failure shape appears at different positions and with
different nouns; adding those nouns to a sentence matcher would only tune
this development set. The next general invariant is that every discourse
unit carries an explicit role and a target occurrence set **before** row
creation. A rejected option cannot be a committed Today action, a recap
cannot become another retrieval target, and a source unit with no unique
owner remains visible in Needs Review. A separate explicit recording request
must still open a distinct Memory; a real new action after a recap must still
open its own Today row. The existing post-row discourse attachment is too
late to prevent all phantom rows or undo an erroneous operation safely.

## Product pattern check

Apple Voice Memos exposes the transcript during and after recording, makes
transcript words searchable, and links a selected word back to its point in
the recording ([Apple support](https://support.apple.com/en-au/guide/iphone/iph00953a982/ios)).
Pixel Recorder allows word-level transcript correction and transcript search;
its generated summaries are a separate feature with stated language and
length limits ([Google support](https://support.google.com/pixelphone/answer/16267698)).
The useful inference for Speak It is a source-first recovery contract: the
structured Today/Memory rows may be edited or held for review, but the
complete original capture must remain accessible, searchable, and traceable
from every derived row. These product documents do not establish their
semantic accuracy, so they provide a recovery design pattern rather than a
release-quality benchmark. Speak It's existing immutable `CaptureSession`
supports the source side; the long-capture gate still must prove row-level
coverage and usable review on the integrated app.

## Choice state must precede generic outstanding-action rules

The current actionability reader treats the bare negative perfect “I haven't
…” as an outstanding action, whatever verb follows. A generic control matrix
found that “I have not chosen” became a Today row, although “Mara chose …”
stayed Memory and an explicit later repair task stayed Today. The failure is
not the word *chosen*: an unresolved selection state has no committed option
to execute. Tightening every negative-perfect sentence to the existing
completed-verb list would lose legitimate short actions whose verbs are not
in that list. The first implementation now reads explicit first-person
nonselection as an unresolved state before the generic outstanding-action
rule. It also keeps the two options under “between” in one clause and splits
a direct contrasting command from that state. Opposite controls cover unpaid
and unbooked work, a third-party selection report, a separate command, and a
between-place phrase with a subsequent command. Proposed and rejected option
ownership, later decision changes, and a travel goal that merely frames an
itinerary still need a typed source role. The exposed gate remains development
evidence.

## September 26 destination-day ownership check

The former museum alternative case exposed a temporal ownership defect after
the selected tram was resolved: “at eleven” inherited the reference day even
though the preceding dated trip goal scoped the meeting. The general fix
assigns a pre-row destination-day edge from a dated first-person goal to
clock-only actions explicitly at that destination. Each action keeps its own
clock and source identity; intervening ticket or preparation tasks keep their
own dates. The goal's exact source span appears on each scoped row and the
redundant broad goal row is removed only when a resolved action entails it.
Controls retain independent travel goals when the later action is at another
place, has its own day, or follows a differently timed arrival; an
intervening Memory closes scope. A generic two-meeting example checks
propagation across multiple independently usable actions. The exposed museum
sentence is regression evidence, not qualification. The focused simulator
class, 1,403-case corpus, and unsigned Release compile passed; the full iOS
unit suite is still running.

## Remaining rambling source-role boundary

The already exposed rambling development set still fails whole-capture shape
for a common reason across different topics: narration about the speaker's
current thinking, a tentative unchosen possibility, and remarks about what
the capture should contain become resolved retrieval rows before their source
role is assigned. Meanwhile, elaborations of one fact or idea can be split
into several rows. These are not evidence that the words disappeared; they
are evidence that the structured intention identity is wrong. A general
next step is a pre-row role for discourse framing and tentative content,
with an explicit owner set when the speaker points to a committed action or
one Memory. A clause with no determinate owner must stay reviewable. A new
explicit recording request or independent action is an opposite-direction
control and must not be absorbed. This is a bounded role/identity mechanism,
not a reason to reopen broad semantic-map research or tune individual
sentences from the exposed set.

The repair-coverage probe isolated one upstream structural contributor: a
filler removed immediately after sentence punctuation left a malformed
`.,` connector, so the next factual sentence joined the prior purchase.
The disfluency pass now restores the sentence boundary for this general
punctuation class. It preserves a comma between two genuine coordinated
commands. This repair does not solve the broader row-role problem above.

An explicit negative scheduling clause followed by a reference-information
classification has a deterministic Memory owner only when its named referent
matches exactly one prior fact. The pre-row routing edge now consumes that
pair and retains their exact source on the fact. Missing clarification,
multiple owners, a different referent, and a positive reminder are controls.
The exposed cafe capture loses its phantom routing rows, but its two cafe
details remain separate because “its back room” could refer to the cafe or
the hotel. That is a stable identity gap, not permission to attach it to the
nearest noun. The old capture is regression evidence only.

## Narrow on-device classifier option, deferred

Apple's [Natural Language `NLModel`](https://developer.apple.com/documentation/naturallanguage/nlmodel)
can run a custom text classifier inside the app, and
[Create ML's text-classifier guide](https://developer.apple.com/documentation/createml/creating-a-text-classifier-model)
requires labeled training examples and separate validation data. A model
labeling each clause as committed action, knowledge, tentative possibility,
or capture commentary could be a local-first way to adjudicate an unresolved
role on iOS versions without Foundation Models. It would not itself provide
source occurrence ownership or pronoun targets. Speak It has no independent
labeled corpus large enough to train and validate those roles without using
the exposed gate as training material. Adding such a classifier now would
replace an explicit uncertainty hold with an unmeasured prediction, so it is
deferred. This is a narrow adjudication option only if the deterministic
source-role and identity rules prove insufficient on a fresh development set;
it is not a new segmentation architecture or release evidence.

The mixed development family also exposed a routing-order error rather than
an ambiguous proposal: an explicit speaker-owned “thought ... is an idea”
became a plain note because the organizer returned at the knowledge verdict
before reading its type. The new precedence rule changes the Memory subtype,
not the Today decision. Third-party ideas, “no idea” knowledge gaps, and
short commands are opposite controls. The exposed garden capture is a
regression case, not fresh qualification.

The cake preference in the exposed rambling case had a separate clause
structure defect: the iOS tagger could treat a coordinated modifier phrase
as another predicate. The deterministic control now distinguishes one finite
fact with a noun/modifier continuation, two explicitly finite facts with
different named subjects, and a same-subject pronoun continuation. It also
excludes actionable obligation frames, which the corpus caught when two
car-maintenance needs were incorrectly merged. The old rambling capture
still fails whole-capture correctness because unrelated narration and recap
remain extra rows; this rule is only a partial identity fix.

## Current freeze blockers and next general mechanism

The latest candidate passes the focused iOS intention-consolidation class,
the 1,403-case host corpus, and the unsigned Release compile. The full iOS
suite passed on the immediately preceding candidate, before the final
coordinated-fact boundary and idea-authorship adjustments; it must run again
on frozen code. These checks show regression health, not long-capture quality.

The bounded completion receipt now owns either one grounded Memory or an
explicit replacement action group. Its raw quote and source occurrence IDs
follow each group member, and no operation on an older saved task is emitted.
A remaining semantic freeze blocker is the broader discourse-role problem
below. The receipt itself still needs qualification on fresh speech forms;
passing the exposed development case cannot establish its release accuracy.

Natural rambling still has a separate discourse-role gap. Explicitly
uncommitted possibilities, scene-setting narration, output recap, and one
coherent idea can become extra rows or split retrieval identities. The next
work must assign a source role and owner set before rows are considered. It
must not merely suppress words from the original transcript or attach them
to the nearest unrelated task. These exposed captures remain development
evidence. Do not ask an independent author for the sealed release set until
the general mechanisms are frozen; do not score this development set as
qualification.

The four exposed rambling captures show three recurring boundary classes,
rather than four isolated wording failures. First, scene narration and
explicitly uncommitted possibilities are being promoted to standalone Memory
rows before the speaker's later commitment can scope them. Second, output
questions and recaps become rows even though their referents are the capture's
existing intentions. Third, two clauses of one Memory identity split when a
pronoun or definite description carries the same subject forward (the nurse
and her explanation; the park image and the four-season series). The invariant
for the next mechanism is: assign each clause a source role and a defensible
owner set before routing or creating a row. A non-row role needs an explicit
grounded source disposition, and an uncertain owner needs visible review;
proximity alone cannot license either suppression or attachment.
