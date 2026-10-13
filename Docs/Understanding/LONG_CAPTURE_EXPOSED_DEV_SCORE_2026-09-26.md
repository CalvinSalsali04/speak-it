# Exposed long-capture development score — September 26–27, 2026

**Development evidence only. V1 remains blocked.** This is a manual semantic
review of the 40 September 24 captures after they had become exposed
regressions. It is neither a fresh gate nor a measurement of the complete
shipping path. The production-source host probe compiled from the uncommitted
working tree during active development; the tree was not frozen. This score
cannot be converted into an unseen accuracy or launch-readiness estimate.

## Method and reproducibility

The input is `long_capture_unseen_2026-09-24.jsonl`, SHA-256
`43b5f94b72dbc0fc2a129cac1ea32c1c1766b32273e86a1308f9e12254285415`.
The September 26 isolated host binary at `/private/tmp/speakit-dev-score-probe/probe` has
SHA-256 `73d99876ec46e99b011badd1972b0ed061bc23d5e48bd1fd7f67ef6bf2e527bd`.
Its 40 JSON outputs are in `/private/tmp/speakit-dev-score-current.jsonl`,
SHA-256 `25aca1b18dddf4e1883a0571a163456d3e8936e13706e312c839540254a082bb`.
The rules-only probe uses Monday August 3, 2026 at 10 a.m. in Toronto. Its
first build failed in the sandbox because the Foundation Models macro plugin
could not launch; an isolated build with the necessary execution permission
completed. No app source was changed for this score.

On September 27, after the recent code changes, a separate isolated build at
`/private/tmp/speakit-dev-score-20260927/probe` (SHA-256
`d61b435c6ec3f7739e2797742a538e65654003a25edef1584882d9826647108e`)
produced `/private/tmp/speakit-dev-score-20260927.jsonl` (SHA-256
`71790ef2ba61616aa772e87f1f7d50a1fadcfdc08eb1f668c3bebcc2ae4fd6a3`).
Both files contain 40 records. Comparing complete JSON objects, **38/40 outputs
were unchanged**. Only U15 and U19 changed in that intermediate run. The
working tree still was not frozen, so the binary hashes identify these
development snapshots more precisely than a commit would.

After the final current-source probe rebuild on September 27, the binary at
`Tools/PipelineProbe/build/probe` had SHA-256
`9df39c88fbd04c2d718010e5e2620916e5b14fa1459f22d521e04c40b5f7c0d2`.
It produced `/private/tmp/speakit-dev-score-20260927-frozen.jsonl`, SHA-256
`68ba57254ddb5d31e6b630954453349f3309f24d4aee68d8cae43ad0d1e3c961`.
This was the intermediate score before the later clause-role and event-context
passes. It remains exposed development
evidence, not a release qualification or an immutable commit build.

After the final clause-role and event-context passes, the rebuilt host probe
at `Tools/PipelineProbe/build/probe` had SHA-256
`94e235cc3d67b16e8416cfc10e69cd4e75334186246b5923d2e67cf3dcd51899`.
The 40 outputs at `/private/tmp/speakit-dev-score-20260927-final-v2.jsonl`
had SHA-256 `d69d5598c6c908e2e4bb3ff45542d6ab57a3add8355000cc16c9d9e28c359078`.
This is the **latest development snapshot scored below**. The exact app-source
working tree was held stable for the host gate and this probe run, but it has
no immutable commit identifier.

I compared **every expected intention** with actual route, title, source
quote, review flag, timing, and operation, and checked for extra rows. A correct
verdict requires the entire capture to remain semantically usable, not merely
the expected row count or Today/Memory sequence. `Incorrect` is the locked
gate's unsafe/silent-incomplete bucket for an incorrect interpretation; it does
**not** assert that every such case executed an unsafe operation or silently
lost source. A source quote containing the right words does not by itself make
an unresolved person, time, or action owner correct. A single coherent Memory
whose title is brief but whose complete original source is on the same row is
counted correct provisionally because the Memory search includes the source
text. These are human judgments by a development participant, with borderline
title-usability decisions called out below.

| Family | Correct | Safe incomplete | Incorrect | Defect concentration |
| --- | ---: | ---: | ---: | --- |
| Clear multi-task | 4/4 | 0 | 0 | Titles often retain prefaces, but actions and scopes are present. |
| Natural rambling | 0/4 | 0 | 4 | Narration and uncommitted thought become extra rows; one idea splits. |
| Coherent single Memory | 4/4 | 0 | 0 | One row with full source for each; titles are sometimes generic. |
| Mixed Today + Memory | 3/4 | 0 | 1 | U15 splits one cafe fact into two Memory rows; the latest run no longer treats Theo's possible Monday collection as the ask deadline. |
| Corrections / withdrawals | 3/4 | 0 | 1 | U17/U20 now display the owned event day/time; U19 still adds explanation Memories and unnecessary review. |
| Shared context | 4/4 | 0 | 0 | U22's soap row now carries Amira's next-Tuesday visit context. |
| Quoted / reported speech | 4/4 | 0 | 0 | No executable quote action observed in these exposed cases. |
| Resolved alternatives | 3/4 | 0 | 1 | U32 saves the abandoned deliberation as a separate Memory. |
| 10–25 intention capacity | 4/4 | 0 | 0 | 10, 15, 20, and 25 separate Today rows; no observed tail fallback. |
| Beginning / middle / end | 3/4 | 1/4 | 0 | U37's background is source-owned; U38's Monday screening context reaches both middle actions. |
| **Total** | **32/40** | **1/40** | **7/40** | Exposed development set only. |

## Case-level adjudication

`C` = provisional whole-capture correct; `S` = safe but incomplete; `I` =
incorrect. Case IDs refer to the exposed input and the JSON output above.

| Case | Verdict | Whole-capture evidence |
| --- | --- | --- |
| U01 | C | Five independent Today actions; morning, evening, and date scopes stay with their actions. |
| U02 | C | Five Today actions, each carrying its stated timing or condition in title/source. |
| U03 | C | Six separate Today actions; Saturday applies to curtain and batteries, not earlier actions. |
| U04 | C | Six separate workshop actions; shared workshop and after-event context is on the relevant rows. |
| U05 | I | Cake and bakery jobs remain, but walking-home, birthday narration, undecided walk, and self-commentary create extra Memory rows; cake preference is embedded among them. |
| U06 | I | Tin fact and two jobs remain; kitchen narration and the non-task question no longer form rows. A tentative shelf reorganization still becomes Memory despite “not a task yet” and no request to save it. |
| U07 | I | Checked appointment status is no longer a Today action, but becomes an extra Memory; Amara's one fact still duplicates across a Memory and review row, and closing commentary also gets review. |
| U08 | I | One park-photo concept still splits: a framing Memory contains the rain/photo-series source, while the four-season elaboration and repetition commentary become separate review rows. |
| U09 | C | One Memory contains the entire soup method in its source; no cooking task. |
| U10 | C | One Memory contains Ellis's preferences and availability in its source; no meeting task. Generic title merits UI review. |
| U11 | C | One Memory contains mural details and history in its source. Generic title merits UI review. |
| U12 | C | One Memory contains the family-history concept and room organization; no outreach task. |
| U13 | C | Two Today actions, two separate Memories, and microphone test retain intended routes and context. |
| U14 | C | Three Today jobs and three distinct Memories remain, including Asha's irrigation knowledge and undecided fence idea. |
| U15 | I | Two Memories separate the Marigold cafe name from the quiet back-room fact that should form one independently usable memory. In the September 27 output, Theo's Monday action keeps “Monday” in its title/source but no longer assigns that day as the deadline to ask him. |
| U16 | C | Two Today actions and two Memories reflect the distinct commitment and knowledge/idea roles. |
| U17 | C | Prior plumber call is removed; the photograph and cabinet actions remain separate, with the confirmed appointment's tomorrow 10 a.m. context visible on both titles and source quotes. No appointment time is turned into the cabinet's due time. |
| U18 | C | Prior Monday send and print job are removed; the final standalone action now names Marcus and retains Wednesday after Clara's comments. |
| U19 | I | Milk is retracted and eggs/rice plus Jo action survive, but milk explanations become extra Memories. The September 27 output removes the incorrect 7 p.m. due time from the message to Jo, while marking that direct action Needs Review for an unsupported condition. |
| U20 | C | Corrected ticket fact and two tasks survive; the leave task now displays the current train's 7:15 Saturday departure, without acting on superseded 6:40. |
| U21 | C | Four school-fair jobs remain separate, with Thursday/Friday and after-fair context assigned. A dangling “and I want” fragment on each title is a quality defect, not a wrong action or date. |
| U22 | C | Five expected routes remain, with Amira named in the allergy Memory and soap action. The soap row now displays the shared next-Tuesday visit context; no false scheduled due time is inferred. |
| U23 | C | Three grant steps inherit the end-of-month deadline; PDF preference remains a separate Memory. |
| U24 | C | One Memory retains the whole market routine; no shopping or Saturday alarm. Its generic title merits UI review. |
| U25 | C | Rosa's quoted commands remain Memory source, while the direct Monday email to Rosa is the only Today action. |
| U26 | C | Proverb remains Memory; the speaker's explicit agreement produces only the photo-album action. |
| U27 | C | Fictional instructions remain attached to the staging Memory; key return is the only Today action. |
| U28 | C | Hypothetical safety steps remain Memory; update and inquiry are two Today actions. |
| U29 | C | Chosen lentils and spinach are actions; preferred preparation is Memory; rejected pasta is not an action. |
| U30 | C | Tram ticket and Hana meeting are actions; south-entrance fact is Memory; rejected driving is not an action. |
| U31 | C | Online submission and receipt filing are actions; portal-email fact is Memory; rejected mailing is not an action. |
| U32 | I | Buy and wrap correctly resolve to sketchbook and scarf fact remains Memory, but the discarded scarf-versus-sketchbook deliberation becomes a separate Memory. |
| U33 | C | Ten independently accessible Today rows, in order. |
| U34 | C | Fifteen independently accessible Today rows, in order. |
| U35 | C | Twenty independently accessible Today rows, in order. |
| U36 | C | Twenty-five independently accessible Today rows, in order; tail is a separate action. |
| U37 | C | First, middle, and last actions survive; wet-shelf background and handwritten coastal notes are in the atlas Memory's source, and the project idea is a separate Memory. The atlas title remains generic. |
| U38 | C | Cinema detail remains one Memory; venue email, Omar link, and charger are three Today actions. Both middle titles now show Monday screening context, and no standalone screening task survives. This counts context in the title as sufficient, without a due date. |
| U39 | C | Three actions and two Memories have the expected route and scope; Tessa is named in her preference Memory, and the compost title no longer includes rejected weather commentary. |
| U40 | S | Porto Memory and postcard action survive, including bookshop details in the Memory source, but explicit “I do not need tasks” creates an unnecessary visible Needs Review row. |

## September 27 changed-case adjudication

- **U15: still incorrect, with a better temporal distinction.** The prior six rows and
  their titles are unchanged. “Ask Theo whether he can collect the keys on
  Monday” changed from `dateOnly` with August 10 due metadata to `none` with no
  due metadata. Monday most naturally scopes Theo's possible collection, not
  the deadline for asking him. The title and source retain that context, so
  removing the due is a semantic improvement. The cafe fact remains split
  across two Memories.
- **U19: still incorrect, with one safer date decision.** The message to Jo no
  longer acquires the dinner's 7 p.m. as its own due time. It now has
  `needsReview: true` and `unsupportedTrigger: condition`. The condition
  detector matches the fronted discourse phrase “while I am talking” and
  treats it as an unsupported event trigger (`ThoughtOrganizer.swift`, near
  `unsupportedCondition`); the direct message action is clear, so this review
  is unnecessary. The separate milk-explanation Memories remain. The milk
  retraction operation is unchanged.

No other captured item, source quote, operation, or metadata field differed in
the 40-record JSON comparison. The whole-capture score therefore remains
**26 correct, 1 safe incomplete, 13 incorrect**. The change is a tradeoff
within one already-failing correction case and a better temporal distinction
within an already-failing mixed case; it is not a family-level improvement.

## Final September 27 current-source comparison

Compared with the September 27 intermediate JSON, the final rebuilt probe
changed U18, U22, U32, U38, and U39. Against the earlier scored September 27
snapshot, only U18, U22, U38, and U39 differ: U32 returned exactly to its
previous four-row output after a projection conflict was corrected. Full JSON
objects for the other 36 cases are unchanged.

- **U18: incorrect → correct.** The final send row now reads “send Marcus,”
  retaining Wednesday and Clara's comment dependency. The withdrawn Monday
  draft and print proposal remain absent. This repairs the local person owner
  needed for a standalone action.
- **U22: improved but still incorrect under the locked whole-capture rule.**
  The allergy Memory says “Amira is allergic to lavender,” and the soap action
  says “before Amira arrives.” Its own title, source quote, and temporal fields
  still omit **next Tuesday**, although that is the shared visit date in the
  source. The soap action is not independently usable with its full timing.
- **U32: no net change.** An intermediate build briefly made the already
  incorrect choice case worse by creating another Memory for the settled
  selection. Person-display grounding had changed the proposition used by
  later choice ownership. The final rebuild restores the previous four rows;
  the separate stale-deliberation Memory still keeps the whole capture
  incorrect. This diagnosis is about a general projection boundary, not a
  sentence-specific choice rule.
- **U38: still incorrect, with better source ownership.** The redundant cinema
  recap is now attached to the original Memory source instead of becoming a
  new Memory row. The phantom Today row for thinking about Monday's screening
  remains, and the venue/Omar middle actions still lack the Monday screening
  scope on their own rows.
- **U39: remains correct.** The preference Memory now names Tessa in its title;
  the three actions and two Memories retain their earlier meanings. The
  weather preface in the compost title remains a quality issue.

That intermediate exposed development score was **27 correct, 1 safe incomplete, 12
incorrect**. One newly correct correction case does not change the release
decision. Natural rambling remains 0/4, and retention remains 1/4 on these
exposed regressions.

## Final September 27 clause-role and event-context snapshot

The latest binary and output hashes are recorded in **Method and
reproducibility** above. Comparing complete JSON objects with the previous
published development snapshot, **10/40 cases changed**: U06, U07, U08,
U17, U20, U21, U22, U37, U38, and U39. The other 30 are structurally
identical as parsed JSON. No operation count changed.

| Case | Changed result | Whole-capture verdict |
| --- | --- | --- |
| U06 | Situational kitchen narration and the planning question no longer create rows. A tentative shelf reorganization still creates a Memory. | Incorrect → incorrect. |
| U07 | The checked appointment is no longer an action, but it is still an extra Memory; Amara's single fact duplicates into a Memory and review row, with another commentary review. | Incorrect → incorrect. |
| U08 | The single photo-series idea remains split between a framing Memory and a review row; repetition commentary is another review. | Incorrect → incorrect. |
| U17 | The withdrawn call stays absent and the related action titles now show the confirmed appointment at 10 a.m. tomorrow. | Incorrect → correct, **provided visible title/source event context counts without a generated due date**. |
| U20 | The leave action now names the corrected Saturday 7:15 train on its own title; 6:40 remains only superseded source. | Incorrect → correct. |
| U21 | School-fair context appears on all four actions, but as the awkward fragment “Friday is the school fair, and I want.” | Correct → correct; title-quality issue. |
| U22 | The soap action now displays Amira's next-Tuesday visit alongside “before she arrives”; the allergy Memory names Amira. | Incorrect → correct. |
| U37 | Wet-shelf background joins the atlas Memory source; the capture has exactly the three jobs and two Memories expected. | Incorrect → correct; generic atlas title. |
| U38 | The screening preface ceases to be a phantom Today row and supplies Monday context to the email and link actions. | Incorrect → correct, **provided title-level shared context is sufficient**. |
| U39 | Rejected weather preface is removed from the compost action title. | Correct → correct. |

An **intermediate**, unreported host build briefly regressed U30: it created
three extra rows and assigned the Hana meeting to the fixture's current day
instead of Sunday. The causal-tail repair restored its prior three-row output
and Sunday 11 a.m. meeting **exactly** in the latest JSON. This transient
regression is not part of the final score, but illustrates why every code
change must be rescored for opposite-direction damage.

Latest exposed development score: **32/40 correct, 1/40 safe incomplete,
7/40 incorrect**. The seven incorrect cases are U05–U08, U15, U19, and U32.
Natural rambling remains **0/4**, despite fewer phantom rows. The remaining
failure mechanism is assigning framing, incidental past experience, tentative
uncommitted ideas, and capture commentary their own saved row, or splitting
one Memory idea into separate row/review fragments. U15 still splits one cafe
fact, U19 still makes milk explanations into Memories and unnecessarily reviews
the direct message to Jo, and U32 still saves discarded gift deliberation as
an extra Memory. U40 remains a safe-but-incomplete unnecessary review of an
explicit no-task statement. These are not evidence of silent tail truncation;
the host probe cannot certify original-source coverage or persistence.

U17 and U38 are judgment-sensitive: their dates are owned by visible row
titles/source, not by scheduled `due` metadata. A stricter release scorer may
reject them if independent usability requires a computed deadline. The
September 24 cases are exposed and cannot settle that product question. The
new sealed gate should state the timing acceptance rule before output is seen.

## What this result should drive

The repeated defect is assigning a new row before deciding whether a clause is
an independent commitment, durable fact, context belonging to another
intention, reported/rejected proposal, or capture commentary. Even when row
count is right, anaphoric person and temporal context may remain in a different
row or only in the original quote. The next bounded invariant should give
every meaningful original clause a role and owner, and require person/time
context to be materialized on the owned intention before output. These are
general mechanisms across U05–08, U17–20, U22, U32, U37–40; the case wording
must not become a list of special rules.

The probe cannot establish complete source coverage, integrated saved-item
operation safety, persistence, optional Foundation Models behavior, microphone
endpointing, or app UI usability. The working tree was not frozen during this
run. Re-run the development diagnostic on the frozen candidate, then use a
new independently authored and sealed set for any release decision.
