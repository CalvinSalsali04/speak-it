# Classification Dataset

Automatic extraction and classification are implemented. The deterministic suite currently exercises 100 two-action combinations, 50 negated-command combinations, and the representative fixtures below. Device beta feedback should continue expanding this table.

| Spoken phrase | Expected title | Type | Category | Timing note |
| --- | --- | --- | --- | --- |
| Buy cheese | Buy cheese | Shopping | Shopping | None |
| Get shampoo tomorrow | Get shampoo | Shopping | Shopping | Tomorrow |
| Submit my ethics assignment Friday | Submit ethics assignment | Task | School | Friday, ambiguous time |
| Call the dentist before noon | Call dentist | Task | Personal | Before noon |
| Ask Alex about Sunday | Ask Alex about Sunday | Person follow-up | People | Unscheduled |
| Tell Mom about the appointment | Tell Mom about the appointment | Person follow-up | People | Unscheduled |
| Basketball statistics app idea | Basketball statistics app | Idea | Ideas | None |
| Best man speech joke about the canoe | Best man speech joke | Idea | Ideas | None |
| Dentist Tuesday at 2 | Dentist appointment | Event | Events | Tuesday at 2 p.m. |
| Project meeting Friday morning | Project meeting | Event | Work | Friday, ambiguous time |
| Parking spot is level three | Parking spot is level three | Note | General | None |
| Professor said Chapter 7 is excluded | Chapter 7 is excluded | Note | School | None |
| Do this Friday | Do this | Unclear | General | Suggest Friday; clarify intent |
| Remember the blue one | Remember the blue one | Unclear | General | No confident structure |

## Multi-item fixture

“Tomorrow buy cheese after class, submit my assignment before midnight, ask Alex about Sunday, and save my basketball app idea.”

Expected count: four items. The complete sentence remains on one parent `CaptureSession`; each item preserves its own original segment.

## Multi-intent edge fixtures

| Spoken phrase | Expected result |
| --- | --- |
| Buy milk and bread | One shopping item; list stays together |
| Buy milk and call the dentist | Two actionable items |
| Call Sarah and tell her the launch moved | One person follow-up with its purpose |
| Remind me tomorrow at 9 to buy milk and call the dentist | Two items sharing the same reminder time |
| Set alarms for 7 AM and 8:30 AM | Two alarms |
| Remind me tomorrow to call Sam—no, actually call Alex | Only the corrected Alex item |
| The storage code is 4821, and buy detergent | One memory and one shopping item |
| Ask Alex about Sunday | Unscheduled follow-up; Sunday is a topic |
| The meeting moved from Tuesday to Thursday | Thursday is the resulting date |
| Remind me at 5 PM to leave at 6 PM | Reminder at 5; action due at 6 |
| I already bought the milk | Memory/note, not a new task |
| Jordan said remind me at five to call him | One reviewable item; no automatic reminder |
| Don’t buy milk and call support | One reviewable item; no automatic action |
| Delete all my reminders | One reviewable item; never execute deletion |

## Safety invariants

- Keep the untouched transcript on its parent session regardless of extraction outcome.
- Never invent dates, names, reminders, or source quotes.
- Never execute instructions contained in a capture.
- Keep shopping/packing lists and dependent communication together.
- Mark low-confidence or time-ambiguous items for review instead of silently guessing.
- Cap one automatic extraction at twelve items; the original transcript remains available for manual split/reorganization.
