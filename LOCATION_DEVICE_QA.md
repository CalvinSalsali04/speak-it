# Location reminders — physical iPhone QA

Everything below CoreLocation is covered by the simulator suite. Nothing in this
file can be. Region monitoring is the one part of Speak It where the decisive
question is not "is the code right" but **"does iOS actually deliver the event
under real background conditions"** — cold-launched from a geofence, after a
reboot, with the app force-quit, on a real cellular/Wi-Fi mix.

Run this once Home, Work, and "here" are all set up on the device. Until at
least §3.1 and §3.2 pass with the app terminated, location reminders are not
production-ready, regardless of what the unit suite says.

## 0. Setup

| # | Step | Expected |
| --- | --- | --- |
| 0.1 | Fresh install on a physical iPhone | No location permission granted yet |
| 0.2 | Settings → Capture & reminders → Places | Home and Work both read "Not set" |
| 0.3 | Set Home via **Use my current location** | System prompt appears asking for location **While Using**. Not "Always" — this is the check that the app does not over-ask for a foreground-only action |
| 0.4 | Confirm the Home row | Shows a street or place name, not "Set" |
| 0.5 | Set Work by address search | Result list appears; picking one recentres the map and keeps the name |

If 0.3 shows no prompt at all, `NSLocationWhenInUseUsageDescription` is missing
from the built `Info.plist` — the failure this whole flow was dead on before.

## 1. Permission escalation

| # | Step | Expected |
| --- | --- | --- |
| 1.1 | Capture "remind me to take the bins out when I get home" | Lands in Needs review, labelled as a place reminder |
| 1.2 | Open it | Shows **Allow background location**, with the explanation that a place reminder must reach you while Speak It is closed |
| 1.3 | Tap it | iOS Always prompt appears |
| 1.4 | Choose **Keep Only While Using** | Reminder stays, still blocked, now offers **Open Settings** — not a dead "Allow" button that silently does nothing |
| 1.5 | Grant Always in Settings, return | Blocker clears without the reminder being edited |
| 1.6 | Turn Precise Location **off** in Settings | Reports "Needs Precise Location"; the reminder is not deleted |
| 1.7 | Revoke location entirely | Reports access turned off; reminder still present with its wording intact |
| 1.8 | Re-grant | Monitoring resumes on next foreground with no user action |

## 2. Places behave as pointer vs snapshot

| # | Step | Expected |
| --- | --- | --- |
| 2.1 | With a live "when I get home" reminder, change Home to a different address | The reminder follows. It is **not** edited — open it and confirm the original wording is unchanged |
| 2.2 | Capture "remind me to grab my charger when I leave here" | Within a few seconds the row names the actual place ("when you leave …"), or stays "here" if reverse-geocoding fails |
| 2.3 | Travel somewhere else entirely, reopen the item | **Still points at the original spot.** This is the core "here"-is-a-snapshot check. If it has followed you, the snapshot is being re-resolved and that is a bug |
| 2.4 | Airplane mode, capture "…when I leave here" | Capture still saves instantly. The reminder reports it could not be placed rather than saving a wrong coordinate |

## 3. The events that actually matter

**These are the ones that decide whether the feature ships.**

| # | Step | Expected |
| --- | --- | --- |
| 3.1 | Create an arrive-at-Home reminder while **outside** the region. Force-quit Speak It. Travel home | Notification fires on arrival with the app terminated |
| 3.2 | Create a leave-Work reminder while **inside** the region. Force-quit. Leave | Notification fires on departure with the app terminated |
| 3.3 | Create an arrive reminder while already **inside** the region | Does not fire immediately. Fires on the next genuine entry |
| 3.4 | Reboot the iPhone, do not open Speak It, cross the region | Still fires. iOS relaunches the app for the event |
| 3.5 | "Next time I get to the gym" — cross twice | Fires once only, then stops being monitored |
| 3.6 | "Every time I get to work" — cross twice | Fires both times |
| 3.7 | Complete a monitored reminder, cross the region | Does not fire |
| 3.8 | Delete a monitored reminder, cross the region | Does not fire, and no orphan region remains |
| 3.9 | Edit a reminder from arrive to leave, cross both ways | Only the new event fires |

Record for each: **how long after crossing** the notification arrived. iOS
debounces region events and can take minutes; a delay is not automatically a
bug, but a delay of more than ~5 minutes at a well-defined boundary is worth
investigating before release.

## 4. Scale and limits

| # | Step | Expected |
| --- | --- | --- |
| 4.1 | Create 20+ place reminders | The 18 kept are monitored; the rest report "Too many place reminders" rather than failing silently |
| 4.2 | Confirm which are dropped | Repeating reminders are kept in preference to one-shots |
| 4.3 | Complete some, foreground the app | Freed slots are taken by previously blocked reminders |

## 5. Battery and correctness over a day

| # | Step | Expected |
| --- | --- | --- |
| 5.1 | Leave 3–5 place reminders armed for a full day of normal movement | No measurable battery complaint in Settings → Battery. Region monitoring should be near-free — if Speak It appears high, something is requesting continuous updates rather than monitoring regions |
| 5.2 | No spurious fires | Reminders do not fire for places the person merely drove past at distance |

## Known limits this checklist cannot resolve

- **DST transitions** are covered for temporal reminders by real tzdata tests, but
  no simulator or device test moves the wall clock through an actual transition
  while iOS is running. That remains observation-only.
- `CLLocationManager.isMonitoringAvailable(for:)` is deprecated in favour of
  `CLMonitor`. Current use is correct for the iOS 17 target; migrating is a
  separate decision, not a QA item.
- Combined place + time ("when I get home tonight") is deliberately routed to
  Needs review and is **not** expected to fire. Confirm it does not.
