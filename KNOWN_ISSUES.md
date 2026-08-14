# Known Issues

## Physical-device voice validation

The project builds and launches on an iPhone 13, passes Xcode static analysis, and all 95 repository, extraction, routing, sync, reminder, draft, integration, and reliability tests pass on an iPhone 17 Pro simulator. The capture subset also passed 175 repeated executions, and the previous complete 93-test baseline passes both Address Sanitizer and Thread Sanitizer. Microphone quality, speech accuracy, true Back Tap recognition, interruptions, AirPods, and locked-device behavior still require the physical-iPhone matrix in `CAPTURE_STRESS_TEST_PLAN.md`; iOS does not expose the hardware Back Tap gesture to automated tests.

## Back Tap setup

iOS does not allow Speak It to assign Back Tap automatically or deep-link directly to the Back Tap choice. The user must add the ready-made one-action **Speak It Capture** shortcut and select it under Accessibility → Touch → Back Tap → Double Tap. The shortcut now foregrounds Speak It directly into an auto-starting capture instead of attempting a fragile cold background microphone start. The app opens as close as the public Accessibility API permits and explains the remaining taps; the physical Back Tap gesture still needs end-to-end device testing across supported iOS versions.

## Personal-team iCloud signing

The optional iCloud synchronization entitlement is enabled in Release builds, but Apple does not allow that entitlement on a free personal development team. Device builds signed with the current personal team therefore use the Debug configuration and keep iCloud disabled. A paid Apple Developer team is required to install or distribute the iCloud-enabled configuration.

## Scheduled messages

Apple does not expose its Messages **Send Later** queue to third-party apps. Speak It can recognize a scheduled-message request, alert at the requested time, prepare the message in Apple's composer, and complete the task after a confirmed send. It cannot silently send or place a message into Apple's encrypted Send Later queue.

## Today rows have no swipe-to-complete

Today's sections are a `LazyVStack`, not a `List`, so the swipe action was a custom `DragGesture`. Layered over scrolling content it won the touch outright and vertical swipes that started on a row did not scroll, so it was removed. Completion is unchanged through the circle on each row and through the editor. Memory, Inbox, and the completed log are `List`-based and keep their native swipe actions. Bringing the shortcut back to Today needs a native implementation, not another gesture.

## User preferences

Appearance, setup completion, and reminder permissions have UI. The broader modeled `UserPreferences` fields do not yet have a dedicated settings screen.

## Future data migrations — version 3 is not frozen yet

The store is at schema version 3. `SpeakItSchemaV1` and `SpeakItSchemaV2` in `SchemaV1.swift` are frozen snapshots: each nests its own `@Model` copies of `CaptureSession`, `CapturedItem`, and `UserPreferences`, so `CaptureSession.self` inside those enums resolves to the historical shape. They must never be edited — they are what later versions migrate *from*, so changing one rewrites history and can make an existing device's store unreachable.

**`SpeakItSchemaV3` nests nothing.** Its `models` array names the live global classes, so version 3 is currently defined as "whatever the models are right now".

This is harmless *today*, because version 3 is the newest version and the live shape and the version 3 shape are genuinely the same object. It becomes a launch-time crash the moment a version 4 is added: adding an attribute to the live `CapturedItem` would silently redefine version 3 to include it too, both versions in the migration plan would describe the same schema, and opening any existing store would abort inside CoreData — which is exactly the failure that had to be fixed for version 2.

**Therefore: freezing version 3 is a prerequisite for any future persisted-model change, not a follow-up to it.** Give `SpeakItSchemaV3` its own nested model copies first, then add the version 4 snapshot and an explicit migration stage. Doing them in the other order reproduces the original bug.

Note this is a latent trap rather than a live defect, so it is safe to ship and safe to run device QA against. It is only unsafe to *extend*.

## UI validation

Standard-size Today and Memory layouts now have clean-state simulator visual coverage. VoiceOver, the largest accessibility Dynamic Type sizes, rotation policy, and a complete dark-mode pass still require hands-on device QA. The implementation uses semantic system controls and colours, but automated unit tests cannot replace that pass.

## Clarification reasons are inferred, not recorded

`CapturedItem.needsClarification` is a single `Bool`, so the reason extraction had at capture time is discarded. `ThoughtOrganizer` knows when it wanted a reminder and could not parse a time, `ThoughtExtractor` knows when it kept a capture whole because splitting it looked unsafe, and the on-device model path knows when it was simply unconfident — all three collapse into one flag.

`ClarificationRequirement` re-derives the likely reason from the item's own fields so Needs review can name the gap. It is right for the common cases and covered by unit tests, but it is a good guess rather than ground truth. Two limits follow. "Might be 2 thoughts" is inferred from a capture still holding its whole transcript with a clause connector in it, so a whole capture kept for a safety reason can read as a split candidate. And a low-confidence flag with no identifiable gap falls back to "Needs confirmation" even when extraction had a more specific doubt.

Storing the reason on `CapturedItem` at capture time would make these exact and would let a row tap open straight to the field in question rather than the generic editor. It is a persisted-model change, so it needs a new schema version and an explicit migration stage.

## Temporal intent is stored; two kinds of trigger are still missing

Schema version 2 records what a person said about time (`TemporalIntent`) beside the instant it resolved to, so `dateOnly`, `exactDateTime`, `relativeDuration`, `calendarRecurrence`, and `durationRecurrence` are now distinct all the way into storage. Named time zones are stored as identifiers. What is still not modelled:

- **Location triggers.** *Superseded.* "Remind me to buy milk when I get home" is now modelled: `ReminderTrigger` has `time` and `location` cases, `LocationIntent` records the place reference, and `LocationReminderMonitor` handles permission and region monitoring. `UnsupportedTrigger.location` survives only on rows captured before that landed. What remains unfinished is the *product* around it — see "Location reminders — architecture complete, feature not" below.
- **Compound triggers.** "When I get home after 6" carries both a place and a time constraint. Both are now parsed and stored, and neither is acted on: the request is held in Needs review rather than reduced to one half. Enforcing the combination — a place trigger gated by a time window — is still unbuilt.
- **Floating versus fixed recurrence across travel.** `TimeZoneBehavior` distinguishes `fixed` from `deviceLocal` and is stored, but nothing yet lets a person *choose* which one a recurring reminder uses. "Every day at 9 AM", carried from Toronto to Hong Kong, currently follows the device. That is the better default; it is not yet a decision the person can make.
- **Locale-driven numeric dates.** "4/5" is flagged as ambiguous and sent to Needs review; "13/5" and "5/13" resolve without asking, because 13 cannot be a month and the order is therefore forced. The ambiguous case does not yet offer the two candidate dates as a choice, which is what the clarification UI should eventually present.

- **The date-only alert hour is a constant, not a setting.** `TemporalResolver.dateOnlyAlertHour` is 9 AM, and it is the stated policy for "remind me tomorrow" — a day with no time still needs a moment to alert at. It should become a "Default reminder time" preference. Note the distinction it already enforces: *"buy milk tomorrow"* schedules nothing at all, while *"remind me to buy milk tomorrow"* alerts at the default hour, and neither writes a time into the intent.

## The free capture ledger is per-device, not per-person

`FreeCaptureLedger` writes the lifetime count to the Keychain, which survives deleting and reinstalling Speak It, and the higher of Keychain and `UserDefaults` always wins so the count cannot move backwards. That closes the ordinary reinstall path.

It does not make the allowance follow a person across devices, and it does not survive a full device erase or a restore onto new hardware without Keychain restore. Genuinely per-person accounting would need a server or an iCloud-backed identifier, which the local-first model does not currently have. This is a deliberate ceiling rather than a bug: the current design is the strongest guarantee available without accounts.

## Location reminders — architecture complete, feature not

The distinction matters, because the two are easy to confuse from the test
suite alone. What is finished:

| Layer | State |
| --- | --- |
| Parsing / semantic representation | Done |
| Persistence | Done |
| Trigger architecture | Done |
| Permission-state architecture | Done |
| Reconciliation architecture | Done |
| Home / Work semantic recognition | Done |
| Home / Work user configuration | Done |
| "Here" coordinate capture | Done |
| Named-place resolution | **Not started** |
| Combined time + place enforcement | **Held for review, not enforced** |
| Real-device geofence execution | **Unverified** — see `LOCATION_DEVICE_QA.md` |

Home and Work can now be configured, so `"when I get home"` and `"when I leave
work"` are the first place reminders with a complete path from sentence to
monitored region. They remain unverified on hardware.

The specifics:

- **There is no Home/Work settings UI.** *Resolved.* `Settings → Capture &
  reminders → Places` sets both, by map, address search, or current location,
  and the same picker is reachable directly from a blocked reminder in Needs
  review so nobody has to leave the thought to fix it. `.home` and `.work` stay
  semantic pointers: changing one re-resolves every reminder that mentions it.
- **Named places are not geocoded.** "When I get to Costco" parses to
  `.named("costco")` and correctly reports `ambiguousPlace`, but nothing searches
  for it yet. Resolving it needs `MKLocalSearch`, a disambiguation UI for the
  several plausible Costcos, and a decision about the network round trip in a
  local-first app. Until then these reminders are stored, explained, and inert.
- **"Here" is a frozen snapshot.** *Resolved.* `.currentLocation` resolves once,
  just after the thought is persisted, and never again — said at McMaster and
  carried to Toronto it still means McMaster. Deliberately fire-and-forget:
  capture never waits on a location fix, and an unresolved "here" reports
  `locationUnavailable` rather than saving a wrong place. It is also refused when
  the only available fix is too old or too imprecise to mean "here" — a suitable
  fix, not merely a present one. Naming the spot is opt-in (**Name this place**
  in the editor) rather than automatic, so speaking a "here" thought never sends
  a coordinate off the device; the reminder fires on the coordinate alone.
- **Combined place and time is represented, held, and not enforced.** "When I get
  home tonight" stores both intents and fires on *neither*. It is surfaced in
  Needs review as *"Place and time conditions aren't supported together yet —
  choose one"*, and setting a time in the editor commits to the clock half.

  This replaced an earlier design that kept both halves live independently. That
  version scheduled the 8pm notification *and* monitored the region, so the
  person would have been told at 8pm whether or not they were home, and told
  again when they walked in. It was latent only because no Home can be
  configured yet; shipping Home/Work configuration would have activated it.
  Preferring the place instead was also wrong — it fires on a 2pm arrival that
  "tonight" explicitly ruled out. Neither half alone is what was asked for, so
  the request waits rather than being silently halved.
- **Region monitoring is unverified on hardware.** Everything below CoreLocation
  is tested on the simulator, but geofence entry/exit, background wake, and
  Always-permission behaviour need a physical device.
