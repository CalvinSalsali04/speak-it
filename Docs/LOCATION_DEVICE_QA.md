# Location reminders — physical iPhone QA

Everything below CoreLocation is covered by the simulator suite. Nothing in this
file can be. Region monitoring is the one part of Speak It where the decisive
question is not "is the code right" but **"does iOS actually deliver the event
under real background conditions"** — cold-launched from a geofence, after a
reboot, with the app suspended or terminated, on a real cellular/Wi-Fi mix.

Run this once Home, Work, and "here" are all set up on the device. Until at
least §3.1a–b and §3.2a–b pass, location reminders are not
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
| 1.9 | Full Precise round trip: active reminder → Precise **off** → foreground Speak It → blocker appears → Precise **on** → foreground | Active again, automatically, with the reminder never edited. Run this as one sequence rather than as 1.6 in isolation — the return leg is the half that is easy to get wrong |

Reduced Accuracy is worth understanding before judging 1.9: it gives a
substantially coarser position and `desiredAccuracy` cannot override it, which is
why a 100–150 m region is refused rather than monitored badly.

Run the same Home arrival route at **100 m, 150 m, and 200 m**, with at least
five crossings per radius. Record successful fires, delay, misses, and any fire
while merely driving nearby. Do not choose 200 m automatically: a larger region
trades fewer missed indoor arrivals for earlier or drive-by notifications. Keep
150 m as the product default until this comparison says otherwise.

For an Xcode-installed Debug build, add the launch-argument pair
`--location-qa-radius 100`, `--location-qa-radius 150`, or
`--location-qa-radius 200` before setting Home. Delete and re-save Home between
runs so the new radius is persisted. The override is compiled out of Release.

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
| 3.1a | Create an arrive-at-Home reminder while **outside**. Background Speak It normally, lock the phone, travel home | **MUST fire** while suspended |
| 3.1b | Repeat after Speak It has been terminated by the system, without swiping it away | **MUST fire**; iOS must relaunch it for the event |
| 3.1c | Repeat after explicitly swiping Speak It away in the App Switcher | **Observe and record** separately; do not classify this result as an architecture pass/fail |
| 3.2a | Create a leave-Work reminder while **inside**. Background normally, lock, then leave | **MUST fire** while suspended |
| 3.2b | Repeat after system termination, without an App Switcher swipe | **MUST fire** on departure |
| 3.2c | Repeat after explicitly swiping Speak It away | **Observe and record** separately |
| 3.3 | Create an arrive reminder while already **inside** the region | Does not fire immediately. Fires on the next genuine entry |
| 3.4 | Reboot → unlock the iPhone once → **do not launch Speak It** → lock → cross the region | Still fires. Monitoring can resume only after the first unlock |
| 3.4b | Reboot → do **not** unlock → cross the region | Record only. A miss is not a Speak It bug because monitoring has not resumed |
| 3.5 | "Next time I get to the gym" — cross twice | Fires once only, then stops being monitored |
| 3.6 | "Every time I get to work" — cross twice | Fires both times |
| 3.7 | Complete a monitored reminder, cross the region | Does not fire |
| 3.8 | Delete a monitored reminder, cross the region | Does not fire, and no orphan region remains |
| 3.9 | Edit a reminder from arrive to leave, cross both ways | Only the new event fires |
| 3.10 | Two separate reminders at Home ("bins" and "feed the dog"), arrive once | **Both** fire, each **once** |
| 3.11 | With an arrive-at-Home reminder armed, stand at home and foreground Speak It several times | No notification. Reconciling must not re-register a region iOS is already watching, or the "next arrival" is reset every time the app is opened |
| 3.12 | Fire a one-shot, then force-quit and reopen Speak It, then cross the region again | Does not fire a second time. This is the one §3.5 cannot catch on its own — the region is rebuilt from the saved reminder at launch, so it is the *saved* reminder that has to remember it fired |
| 3.13 | Walk around the boundary: inside → outside → inside → outside → inside within five minutes | One-shot: exactly one notification. Repeating: no second notification inside the five-minute cooldown |
| 3.14 | Create "when I get Home" → change Home → terminate Speak It → visit old Home → visit new Home | Nothing at old Home; fires at new Home. This proves the old region was retired, not merely hidden |
| 3.15 | Create a Home reminder → remove Home in Settings → terminate → visit old Home | Nothing fires. The saved item remains and says **Set your Home location** |
| 3.16 | Active Home reminder → terminate → iOS Settings: Always → Never → travel Home → reopen Speak It | Nothing fires; the item immediately reports location access off. Re-grant Always, reopen, then leave/return: monitoring restores without an edit |
| 3.17 | Location Always, notifications Off → cross the region | No alert and the editor says **Notifications off**, never Active. A one-shot is not retired; after notifications are restored, a later crossing can still deliver |
| 3.18 | Fire a one-shot → reboot → unlock once → do not launch Speak It → leave and return | Does not fire again. Retirement survives reboot reconstruction |
| 3.19 | "Bins when I arrive Home" plus "gas when I leave Home" | Entry fires only bins; exit fires only gas |
| 3.20 | Cross a region and immediately open Speak It and complete the item | No reminder appears after completion |
| 3.21 | Cross Home and immediately edit the reminder to Work or change arrive/leave | No old-trigger notification. The monitored revision in the callback must still match the saved revision |

Record for each: **how long after crossing** the notification arrived. iOS
debounces region events and can take minutes; a delay is not automatically a
bug, but a delay of more than ~5 minutes at a well-defined boundary is worth
investigating before release.

### Suspension, system termination, and force-quit are different results

Split the terminated case into two results rather than one, because iOS treats
them differently and only one of them is Speak It's to fix:

- **Backgrounded / suspended** — mandatory pass.
- **System terminated** — mandatory pass. Apple documents that iOS tries to
  relaunch an app when a monitored condition changes.
- **Explicit App Switcher swipe** — observation only. Record the OS build and
  device model; do not merge this result with ordinary termination.

Record all three outcomes separately in the release notes for this feature.

## 4. Scale and limits

| # | Step | Expected |
| --- | --- | --- |
| 4.1 | Create 20+ place reminders | The 18 kept are monitored; the rest report "Too many place reminders" rather than failing silently |
| 4.2 | Confirm which are dropped | Repeating reminders are kept in preference to one-shots |
| 4.3 | Complete some, foreground the app | Freed slots are taken by previously blocked reminders |
| 4.4 | With 18 armed, check Settings → Battery and Privacy → Location Services | Speak It shows the geofence arrow, not continuous-use blue. 18 regions is a budget, not a tracker |

Speak It deliberately does **not** deduplicate reminders that share a place: two
reminders at Home are two regions out of the 18. Collapsing them would need a
region identifier that names a coordinate rather than a reminder, and the event
would then have to be fanned back out to several items at delivery time — from a
cold launch, before SwiftData has been read. The budget is prioritised and the
overflow is reported instead, which is honest at every size and needs no mapping
to survive a relaunch. Revisit only if real users actually reach 18.

## 4a. Monitoring that fails rather than being refused up front

`startMonitoring(for:)` does not fail in place — it returns, and the refusal
arrives later on `monitoringDidFailFor`. These check that a reminder iOS is not
watching is never displayed as though it were.

| # | Step | Expected |
| --- | --- | --- |
| 4a.1 | Airplane Mode on, then arm a place reminder | Either it is monitored, or it reports "Couldn't watch this place". Never "active" while iOS has refused it |
| 4a.2 | Airplane Mode off, foreground Speak It | Recovers with no user action. A foreground is the retry point |
| 4a.3 | Wi-Fi off, cellular weak, cross a region | Record the delay. Region reporting needs network reachability to be prompt; a long delay here is expected, a never is not |
| 4a.4 | Settings → Privacy → Location Services **off entirely**, foreground Speak It | Reminders report access turned off. No region is left running |

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
- `UNLocationNotificationTrigger` is UserNotifications' own region trigger, and
  it would let iOS own delivery with When In Use authorization instead of Speak
  It requesting Always. Run **one controlled comparison before launch**, not a
  migration: same iPhone, Home arrival, same radius, current Core Location path
  versus `UNLocationNotificationTrigger`, 5–10 crossings each. Record fire/miss,
  delay, false positives, suspended, system-terminated, force-quit, and required
  permissions. Change architecture only if that evidence shows equal or better
  reliability; the alternative adds a second scheduling store to reconcile.
- Combined place + time ("when I get home tonight") is deliberately routed to
  Needs review and is **not** expected to fire. Confirm it does not.

## Scope and source of truth

This file proves only the **location engine**. Release correctness has three
independent tracks:

1. Temporal engine — midnight, time zones, DST, recurrence, reconciliation.
2. Semantic engine — whether the captured words became the intended fact,
   action, deadline, reminder, correction, or negation.
3. Location engine — whether iOS delivers the real-world crossing.

Passing this checklist does not substitute for the temporal and semantic suites.

Apple references used for the acceptance policy:

- [Monitoring the user's proximity to geographic regions](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions)
- [UNLocationNotificationTrigger](https://developer.apple.com/documentation/usernotifications/unlocationnotificationtrigger)
- [Choosing the Location Services Authorization to Request](https://developer.apple.com/documentation/bundleresources/choosing-the-location-services-authorization-to-request)
