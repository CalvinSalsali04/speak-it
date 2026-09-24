# Changelog

Notable changes to Speak It, newest first. Build numbers are
`CURRENT_PROJECT_VERSION`; every shipped build is also a `build-N-rc` tag.
Entries before September 2026 were reconstructed from the commit history and
`Docs/DECISIONS.md`, so they are summaries rather than a contemporaneous record.

## Unreleased

- A repeating reminder at a bare hour now fires in the same half of the day
  as the same words without the repeat. "Every Friday at five remind me to
  submit the report" fired at 5 AM every Friday; it now fires at 5 PM, as
  "remind me Friday at five" does. The same goes for every day, for a
  weekday of the month, and for every few days, weeks or months; that last
  kind also ignored an hour said as a word ("every other day at five") and
  used the time it was saved. "5 AM", an alarm ("wake me every weekday at 6") and
  "every morning at 7" keep the morning. A series also keeps the time of its
  first occurrence after it is completed: "Every Monday at 3 call Mom" could
  come due at 3 AM once and at 3 PM every week after. Series saved before
  this build keep the time they were given.
- Opening the app no longer erases a repeating reminder's saved timing
  details when this version cannot read them. The launch pass that moves an
  overdue series to its next occurrence wrote over them, and so did a restore
  from iCloud. Both now leave them as the launch check already did.
- The pass that runs at every launch and foreground no longer stops or
  cancels the alarm of a row that rang in the last 30 minutes. It used to stop
  and cancel every alarm before re-arming the ones still ahead. So by reading,
  opening the app silenced an alarm ringing at that moment, or a snoozed
  alarm ringing under its own ID, and did not put it back. Completed, held,
  removed and disarmed rows are still cancelled. Whether a ringing alarm now
  keeps ringing has not been observed on an iPhone (device check D17).
- With VoiceOver on, Speak It says what happened: the save result
  ("Remembered", "Can you clarify?"), that a recording stopped because nothing
  was heard, that voice failed or recovery is running, a capture recovered on
  Today or at launch, and whether a share reached Speak It. It never says any
  of it while the microphone is open. There is no echo cancellation, so
  "Listening" and "Still listening", which used to be spoken into the open
  microphone, could have become part of the person's original words.
  "Listening" is now spoken before the microphone opens, and the microphone
  waits for it to finish. "Still listening" is now a haptic. With VoiceOver
  off, nothing waits.
- The voice screen no longer says "Tap to speak" while it is still saving the
  thought you just spoke. Finishing a recording returns the recognizer to idle
  before the save starts, and the orb, the heading and the button's VoiceOver
  label all read that idle state — so the longest pause in a capture, the one
  where on-device refinement runs, was described as nothing happening.
- A cancelled recording can no longer put its words into the next one. A late
  result from an abandoned run passed the transcriber's state check and
  replaced the live transcript; "Try saying it again", "Type instead" and the
  tutorial retries all reach that path.
- The capture review list shows what each item will actually do: its date or
  time, a bell or alarm when something is armed, a pin for a place trigger, and
  the specific reason a row is held instead of a bare question mark. It was
  showing only a title and "Category · Type", so a task due Friday and a task
  that rings on Friday looked identical on the one screen built for checking.
- A capture receipt no longer counts a plain dated task as a reminder. "Buy
  milk tomorrow" arms nothing, but it was announced as a reminder *and* as an
  action, so the parts could add up to more than the number of things saved.
- Speaking after typing is protected like any other recording. A voice
  capture that reused a typed draft (after "Speak instead", or "Try saying it
  again" after a typed save that asked for clarification) had no protected
  recording, so a call or a failed recognizer fell back to typing instead of
  recovering the words, and a kill could lose them. The retry is also dated
  from the recording, not from the save before it, and a typed save no longer
  leaves an empty draft behind.
- Words typed before "Speak instead" are kept. The saved thought is what you
  typed and then what you said, whether it is saved live, recovered in the
  capture screen, recovered at launch or from Today. If the recording cannot
  be read, "Type it" starts from the typed words, and deleting the recording
  keeps them as a thought of their own. The voice screen shows the typed
  words above what you are saying, so what is saved is what is on screen,
  and words you erase before leaving stay erased.

- A spoken cancel, complete or move whose one match is a knowledge row held
  in Needs review (reported speech, a note waiting on a question) is held for
  the person instead of acted on. A cancel used to delete the row, and the
  capture's original words with its last row (DEL-26).
- A confirmed broad request such as "cancel all my reminders" reaches only
  Today's action rows (tasks, errands, follow-ups, events, and anything with
  a reminder). Memory's notes, ideas and people facts, and knowledge rows
  waiting in Needs review, are no longer counted or deleted with them. The
  noun is not read, so "reminders" and "tasks" reach the same rows (DEL-25).
- Build 19.
- Merge and Undo in Capture details no longer fold open rows into one already
  ticked done or archived. The result stays open unless every row was
  closed, and a merged reminder is scheduled again. The capture
  screen also re-reads its rows after a Split, Merge or Undo instead of
  showing ones that were deleted.
- When this iPhone's language model cannot read sentence structure (every
  word comes back unclassified, as on the hosted CI simulator), captures still
  save, but every row now waits in Needs review as "Not fully read". A row
  keeps a time, series or place only if its own words said it, so a fact can
  no longer inherit "remind me every Friday" from the sentence around it.
  Refinement is skipped in that state, and no cancel, complete, reschedule
  or "never mind" is carried out: each waits in Needs review with its words.
  Nothing changes on a healthy device.
- A place reminder iOS is not watching no longer looks armed. Past the limit of
  18 places, or when iOS refuses a place, the reminder now waits in Needs review
  as Too many place reminders or Couldn’t watch this place instead of saying
  Next time you arrive. Finishing, archiving or deleting a place reminder hands
  its slot to the next one straight away, and a place reminder captured in the
  app or with Siri is watched as soon as it is saved rather than the next time
  Speak It is opened.
- Adding a due date to a place reminder no longer leaves it looking armed. The
  date pauses the place, as place-and-time combinations always have, but the
  row kept its pin and the editor said Active. The row now shows the date, the
  editor says the place is off while a date is set, and removing the date
  brings the place reminder back.
- A row Speak It holds for review no longer rings, alarms or geofences until
  you confirm it, and its Needs review row shows the time or place it would use.
- A shopping row Speak It holds for review is now listed in Needs review, as the
  save receipt says, and its list row shows what it is waiting for.
- A capture sent to Apple Intelligence for a second reading now waits at
  most the two-second budget. The old race waited for the model call to
  finish even after the timer won, so a slow model held the capture.
- Beta analytics tell capture endings apart without content:
  `speech_capture_quality` carries `finalized_by` and `stop_trigger`, a new
  `capture_recovery` event says whether a recording was recovered or the
  closed kind of failure (a pass that timed out or stopped after partial
  words has a kind of its own), and `capture_failed` now reports `speech`,
  `storage` and `organization` at the stage that failed. Finishing with no
  words under VoiceOver is the person's choice and sends nothing. What is
  saved and shown is unchanged.
- Advice somebody else gave you ("Sarah said I should call Mike tomorrow at
  3", "my doctor thinks I ought to book a follow-up") is now a Needs review row
  marked "Someone else's words", with no date and nothing armed. It used to be a
  confident task on Today, often dated. What people ask you to do ("Sarah asked
  me to call Mike") and what you commit to yourself ("…, so I need to call him
  today") are still errands. This is case 4 of the 2026-09-16 reported-speech
  ruling.
- Advice passed on by a reminder or a message ("Sarah reminded me I should
  call Mike", "Sarah texted me that I should call Mike tomorrow at 3") is held
  for review the same way. "Sarah reminded me to call Mike" is still an errand.
- On iPhones with Apple Intelligence, the on-device model can no longer turn
  held advice back into a dated task by splitting "Sarah said" off from the
  rest. A refinement that would date, remind, repeat, place or confidently
  action a row held as someone else's words is discarded, and the held row is
  kept.
- Choosing System under Appearance now follows the iPhone's light and dark
  switch immediately. After the app had been in Light, picking System left a
  light window in place until the next launch.
- A collapsed Today disclosure section (Coming up, No date) no longer leaves
  its rows in the accessibility tree. `.accessibilityHidden` is a no-op on
  iOS 26.5, so a closed section's rows stayed reachable as inert buttons to
  VoiceOver and XCUITest; `TodayDisclosureContent` now builds rows only while
  expanded, keeps the measured height so later opens still animate, and
  honours Reduce Motion.
- Build 18. "Every time I sneeze" and "as soon as I can" no longer crash the
  app at save time: a fronted condition with no body ran a closed range
  backwards in the rules pipeline, on every capture path.
- A capture whose words trap the pipeline can no longer become a crash at
  every launch. Launch recovery counts its attempts per capture; after two
  lost launches the capture keeps its words as a Needs review row and is not
  read again. Interrupted drafts get the same guard.
- Recovering a protected recording never sends audio to Apple: a language
  with no on-device speech model now refuses with a clear alert instead of
  uploading, so "stays on this iPhone" is true. Live dictation is unchanged
  and may still use Apple's speech service, as the privacy policy says.
- Onboarding no longer offers the Location card; When In Use and then Always
  are asked for only from the place-reminder editor, matching the Review
  Notes and the privacy policy.
- The privacy manifest declares Performance Data and Other Diagnostic Data
  for the capture-timing and capture-failed analytics events, and a test
  reads the built manifest so it cannot drift again.
- Inert `INFOPLIST_KEY_*` build settings, including a `location` background
  mode the app never shipped, are gone from the project; `SpeakIt/Info.plist`
  is the only Info.plist source and declares only the `audio` mode.
- Store listing copy, the App Review package, and a repeatable 6.9-inch
  screenshot script (`Tools/Screenshots/capture.sh`) are in `Docs/` and
  `Tools/` for the first submission.
- A date used as a vague topic ("that Thursday thing") is kept for review
  without inventing a deadline. Explicitly timed actions keep their dates.
- A recurring alarm ("wake me up every weekday at 6:30 with an alarm") now
  repeats by itself on iOS 26. It used to ring once and arm nothing for the
  next day until Speak It was opened again. Daily and weekly-on-named-days
  series repeat; monthly, every-other-week and every-few-hours series still
  ring once per app run (see `Docs/KNOWN_ISSUES.md`).

- Tapping the morning brief opens Today and clears its unanswered count, even
  for an older brief. Dismissal does not count as an answer.

- Nine captures the corpus had recorded as "arguable" are decided: "pay the
  invoice within 30 days" is due on the last day of the window; "every second
  Tuesday" is every other Tuesday; "standup moved from 9 to 9:30" is an event
  at the new time, not a person called Standup; "Catherine's husband is called
  David" files under Catherine; "give Mom's recipe to Catherine" is a task with
  Catherine, as is any hand-over "to" somebody; "Catherine said I need to call
  Alex Friday" names Alex; "pick up the prescription at the pharmacy and gas at
  the station" is two errands; "descale kettle" is a task; "don't forget to
  call Mom" is a follow-up with Mom.
- "Meeting from 9 to 9:30" starts at 9. It used to read "9 to 9" as nine
  minutes to nine and land at 8:51 PM. "Dinner moved to 7" is an event at 7
  instead of a note.
- Appointments keep business hours: "dentist at 8" and "meeting at 9" are
  the morning, and tomorrow's when the hour has passed, instead of tonight's.
  "Meeting at 7", "dinner at 8" and "call Sam at 9" are unchanged.
- "Tuesday is book club" is one thought. It used to be cut into a note called
  "Tuesday is" and a task called "Book club".
- Today's undated rows keep a fixed order between refreshes: priority, then
  the older capture first. Equal rows could previously trade places.
- "Standup 9am" and "dentist 2pm" are events; a clock with am or pm no
  longer needs an "at". "The parcel arrived Friday" is a note, not next
  Friday's event. "Gym at 6 and dinner at 8" is two events, and "lunch at 12
  and dinner at 8 tomorrow" puts both on tomorrow.
- Flattened transcripts resolve the same person as cased ones in three more
  shapes: "jean-luc" is Jean-Luc in the title as well as the person, "wish
  grandma happy birthday" is a wish for Grandma rather than a person called
  Grandma Happy, and "call catherine tomorrow, actually alex" is a call to
  Alex instead of to "Catherine Alex".
- "Don't fix the sink" cancels a matching reminder the way "don't call the
  plumber" already did; the operation detector now reads the shared errand
  vocabulary instead of a private list of 31 verbs.
- "Cancel my Netflix subscription" and "cancel the gym membership before the
  end of the month" are tasks to do, not requests to delete a stored
  reminder. "Cancel the dentist appointment" still removes the appointment.
- Three domain batches of everyday captures (work, family, money) were read
  one by one. Departments ("legal", "accounts payable", "recruiting") and
  pets are no longer filed as people; "I told Sarah I'd drop off the dish
  Sunday" is a Sunday task with Sarah, not a note about "Sarah I'd"; "call
  Mom tomorrow and my sister Friday" is two calls (it was one, and "text
  Alex tonight and my brother tomorrow" moved Alex's call to tomorrow);
  "Maya's swim lesson moved to Thursday" is Thursday's event, not a person
  called Swim Lesson; "schedule the dog's grooming appointment" and "finish
  the slides for the board meeting" are tasks, not events; "the standup moved
  to nine fifteen" keeps its fifteen; "tell Nina the brunch is moved to 11"
  no longer schedules the telling at 11; "the lease ends in November" is a
  note rather than a dateless event; "the midterm is on the 15th" is on
  Today; "Costco run tonight: milk, eggs, coffee" and "groceries tonight:
  eggs, milk" are shopping rows; "call the bank about the $89 charge",
  "before the Friday sign off", "Great idea from the offsite:", "with Tom and
  Alice, it's $1200 total" and "a travel adapter before we leave" are no
  longer cut in two; "unload the dishwasher", "transfer $400" and "cc Dana"
  are recognised errands; and "used to work at Shopify before this" is no
  longer held as an unfinished thought.
- A second round of authored batches (a freelancer, fitness and errands, and
  row titles). "Chase it" and "get it back by Friday" stay with the thought
  they point back at; "Marcus prefers phone calls" is no longer cut before
  "phone"; "I need to buy a mic stand and a pop filter" shares its "buy";
  "invite Tom and Rachel over for dinner" is one invitation; "Northwind
  accounting" and "unit 4" are not people, nor is "rain" in "it's supposed
  to rain"; "I keep forgetting that the team signs off on Wednesdays" is a
  note and "I keep forgetting to call Mom" is a call; "let's order the
  filters" is a task titled without the "let's"; "or whatever", "I think"
  and "if I can" leave titles; "max's medication" is Max's in the title;
  "about five quarts" keeps its "about"; "we need eggs milk and olive oil"
  is a shopping row; "end of quarter" and "end of year" are deadlines; "the
  nursery closes at 6 on weekdays" is a note and no longer a 6 AM series;
  "while I'm out there grab stamps" reaches Today; and "dont forget to"
  without its apostrophe is read like "don't forget to".
- "Book a table for four at 7" is at 7, not 4. "Physio Wednesday 10:15"
  keeps its clock. "Movie night Friday" no longer invents 8 PM. "The parking
  pass expires Friday" is on Today for Friday; "my passport expires in March"
  stays a note. "Idea for the app: let people share lists" is one idea, and
  "Note to self:" no longer leaves its colon on the title.

- Clarified the ten free captures need no subscription and never expire. Guarded annual launch discount claims against mismatched StoreKit prices and currencies; removed an unverified renewal-rate promise.

- Morning brief counts now include dated shopping lists, once per Today card,
  using the earliest open entry’s reminder or due date.

- Past comparisons such as "I had better luck last time" now go to Memory
  instead of creating tasks. Genuine "had better" actions and explicit reminders
  retain their existing behavior.

- Clear "I had better" tasks now get concise titles, while uncertain comparisons,
  negation, historical wording, and manually edited titles keep their frame.

- Seven small dots beside the date on Today, one per day of the week, filled
  on the days you kept a thought or finished a task. They appear from your
  second active day, carry no number, and never report a loss. A clear day
  with things still coming up now reads "All clear for today."
- An optional morning brief: one silent notification with what's due ("2 due
  today · 1 overdue") at a time you choose, switched on under Settings →
  Capture & reminders next to the default reminder time. It stays inside any
  Focus, sends nothing when nothing is due, and turns itself off after five
  unanswered mornings.
- A phrase fronted before the verb is context, not a thought: "On the 1st
  renew the car insurance", "By Friday send the invoice", "After dinner call
  Mom" and "At the store buy milk" each produce one dated, actionable row
  instead of a phantom "On the 1st" event beside an undated task, or a Memory
  note. With a comma after the day, the day leaves the title as it already
  did for "Tomorrow at 9, call Sarah". The same holds after an "and": "Book
  the dentist and before dinner call Mom" is two rows split at the "and", and
  "Tomorrow morning email the landlord and then in the afternoon pick up the
  prescription" is two dated tasks instead of three rows.
- A condition in front of an errand no longer hides it: "When I finish the
  essay call Dave", "After I get paid book the trip" and "As soon as I land
  text Mom" are Today rows held in Needs review with the condition named,
  instead of Memory notes. "Before I forget call Dave" is a plain task.
- "We're at five" and "I'm at 5 already" are notes, not five o'clock events;
  "we're meeting at five" is still an event.
- Correcting a fact keeps the fact: "Remember Alex likes golf, actually
  tennis" is a note about Alex liking tennis instead of a note reading
  "tennis", and "allergic to peanuts, actually tree nuts" keeps its "to". A
  replacement that merely starts with a spoken number, like "tennis", is no
  longer refused as a clock.
- People facts and delegation name their person: "Sarah has no pets" files
  under People, "Don't let Alex forget the passports" records Alex, and "Call
  Priya at 2 and Marcus at 4" gives Marcus his own call instead of an event.
- "And then" between two items or two recipients is the same boundary as
  "and": "Buy milk and then bread" is two shopping rows instead of a row
  titled "Buy then bread", and "Email the landlord and then the plumber" is
  two rows.
- Two recipients of one verb are two rows: "Ask Sam and Priya about the
  invoice" and "Email the landlord and the plumber" each give two Today rows
  titled with the verb, instead of a Memory note or one row. An "and" inside
  the topic ("ask Priya about the invoice and the receipt") stays one row.
- A row that shares the verb of the one before it is titled with that verb:
  "Call Mom tomorrow and Alex Friday" titles its second row "Call Alex
  Friday" instead of "Alex Friday". The spoken words are kept as spoken.
- Fetching a person is an errand, not a purchase: "Pick up Alex from
  school", "Drop off Sam at practice" and "Get Mom from the airport" are tasks
  about that person instead of shopping rows. Parcels ("pick up milk", "Pick
  up Tylenol") are unchanged.
- A dictated lowercase brand no longer ends a shopping list early: "get coke
  and sprite" is two shopping rows like "Get Coke and Sprite", and the
  lowercased corpus rendering has no blocking disagreements left.
- Settings → Capture & reminders has a **Default reminder time**. It is the
  moment a reminder that names a day but no time alerts at ("remind me
  tomorrow"), 9:00 until changed. "Tomorrow morning" and "first thing" still
  mean the morning.
- Dictated names keep their casing in row titles: a row whose person resolved
  to Dave no longer reads "Don't text dave". The title writes the resolved name
  the way the resolver displays it, whole words only, and never flattens a name
  the speaker cased themselves.
- "Let priya know the meeting moved" resolves the person as Priya, not "Priya
  Know": the frame's own anchor closes the name.

- Social meal plans such as "Grab lunch with Sam at noon" are events instead
  of shopping items, preserving their date and companion without adding an alert.
  Grocery purchases and past-tense captures keep their existing classification.

- The landing page opens on the ring of spoken thoughts again, turning around
  the headline with the listening indicator in the break in it. The thoughts are
  liquid-glass capsules, and no thought is ever drawn over the words: one fades
  out as its edge reaches them and back in on the far side, which is what lets
  the ring work on a phone as well as a desktop. Reduced motion settles the ring
  in place; reduced transparency and increased contrast render it as solid
  paper.
- The site explains how Speak It understands a capture: its own rules on every
  supported iPhone, and Apple Intelligence as a second reading of the ambiguous
  ones, on device. It states what the refinement cannot do — lose your words,
  invent them, set your dates, or hold up a capture — and which iPhones and iOS
  version it needs. No latency number is claimed, because none has been measured
  on an Apple Intelligence device.
- Trying a thought in the browser is one row instead of five controls: three
  example thoughts, then a field carrying typing and the microphone together,
  with the microphone inside the field. What was heard now fills the field too,
  so it can be edited rather than only reflected in the result.
- The two app screenshots show the whole screen in a whole phone, including the
  tab bar and the capture button, instead of being cut off part way down.
- Quick capture leads with the Action Button, Back Tap and the widget; Control
  Center, Siri, the share sheet and Live Activities moved under "More ways to
  capture".
- The site sets *Speak It* in the page's own typeface beside the unchanged
  five-bar mark. The app icon and the other brand surfaces are untouched.
- Pro monthly is $2.99, and the annual plan is now guaranteed to cost less than
  twelve monthly payments. The scheduled annual increase to $29.99 would have
  made the plan the paywall pre-selects and badges `BEST VALUE` more expensive
  than paying monthly. Monthly carries no sale price: the paywall only ever
  strikes a regular price through for annual.
- The launch-price caption says the offer ends on October 22, not the
  subscriber's rate. The previous wording read as though $14.99 expired for
  people already paying it.
- Speak It now makes its case twice before the free allowance runs out, instead
  of only at the wall: once after the first capture that spends part of the
  allowance, and once when three remain. Each appears at most once for the life
  of the install, each is dismissible with "Continue using Speak It free", and
  neither blocks anything. Practice captures during the tutorial stay
  complimentary and never trigger either. A moment earned through Siri, Back
  Tap, or the share extension waits for the next launch rather than being lost,
  and none appear while onboarding, practice, a capture, the free-limit wall, or
  a referral invitation is on screen — or before Speak It has confirmed the
  Apple Account is not already subscribed.
- Preserve new items alongside capture operations, including a separate review row for ambiguous operations; mixed captures count toward the free allowance when they create items.
- Carry complete portable item semantics and shopping groups through iCloud, including explicit clearing and compatibility with older payloads.
- Preserve stacked errands and preparatory clauses; constrain optional model refinement to uncertain readings with stronger action and metadata preservation.
- Reduce repeated Today/Memory projection and widget work; rank exact people/title search matches ahead of incidental mentions.
- Bring missing-person/time controls forward, allow longer accessibility titles, and use native iOS 26 glass on the capture dock with accessible fallbacks.
- Improve the website's phone layouts, visible primary action, readable examples, keyboard focus and reduced-motion behavior without adding a framework.

- The logo is the five bars raised out of paper: the app icon is now black
  capsules embossed on light paper (`Tools/Brand/generate_emboss.mjs`), the
  favicon is black bars on a white tile, the website's topbar and footer glyph
  and every brand master use the same clean capsules, and the site gained a
  social card. The hand-inked bar edges from the 3 September refresh are
  retired (`Bars.inkedByHand`).
- The clock and calendar as the rest of the English-speaking world says them:
  "15 August" no longer resolves to today, "06:20 tomorrow" is morning rather
  than evening, "half five" is 5:30, "seventeen thirty" and "eighteen hundred"
  are read, "ten pass six" is 6:10 rather than 10 PM, "remind me at half five"
  is a reminder rather than a place trigger, "Sunday week" is the Sunday after
  next, "last Tuesday" no longer dates a task to the coming Tuesday, and "the
  first draft" no longer means the 1st of next month. The router reads the
  same forms, so "my flight is on 22 September" and "lunch at half one" are
  events rather than notes, and "get up at 6" is a task rather than a shopping
  row. Corpus families 52-54.
- Two stale UI tests refreshed for the guided first capture and the seeded
  Today screen, which now waits on the app's own launch-finished signal.
- Slim simulators for test runs: a checked-in SimSlim profile
  (`Tools/CI/simslim-profile.json`) cuts a simulator from 3.7 GB to 0.9 GB,
  `Tools/CI/simulator-pool.sh` keeps a named pool of them, and
  `SPEAKIT_SHARDS=N` runs the unit suite across the pool.
- Brand refresh: the five-bar mark and a drawn wordmark, generated by
  `Tools/Brand/generate_brand.swift`.
- Release-readiness fixes found by walking the app: paywall link labels,
  dark-mode contrast on the setup screen, Dynamic Type on the smallest badges,
  a dedicated tint for on switches.
- Repository hygiene: design documents moved under `Docs/`, GitHub Actions CI
  for the Node projects and (on a self-hosted or dispatched Mac) the iOS app,
  shared check scripts under `Tools/CI/`, Dependabot, a pull-request template,
  and a secret scan of the full history.

## Build 17 — 2026-08-26

- Incomplete-thought recovery: the app notices when a sentence stopped rather
  than finishing it for the person, and a withdrawn thought is actually
  withdrawn.
- Abandonment handling closed out for the release candidate.

## Build 16 — 2026-08-26

- The finished-sentence pause settles at 1.9 seconds
  (`Docs/VOICE_ENDPOINTING_DECISION.md`).

## Build 15 — 2026-08-26

- A finished sentence gets its two seconds back before capture ends.

## Build 14 — 2026-08-26

- The interpreter's verdict is stored with the capture instead of re-guessed.
- SwiftData schema version 3 frozen against a store a shipped build wrote.
- The original transcript is kept beside what the repairs read.
- Speech-act scope, ownership, and sentence-level coordination are read from
  structure instead of keyword lists.

## Build 13 — 2026-08-23

- Place-and-time review, dictation repairs, and the introductory sale to
  October 22.

## Build 12 — 2026-08-22

- `SpeechAnalyzer` engine on iOS 26, shopping lists, alarm QA fixes, and the
  guided first capture.
- The iOS app, website, founder dashboard, referral service, and marketing
  assets consolidated into one repository.

## Earlier — 2026-08-14 to 2026-08-17

- Location-reminder architecture complete; review routing and blocker
  precedence fixed; launch hardening checkpoint.
