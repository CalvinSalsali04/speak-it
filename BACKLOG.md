# Backlog

Status values: **Done**, **Next**, **Later**.

## Phase 1 — Local foundation

- **Done:** SwiftUI app and shared scheme
- **Done:** SwiftData models for sessions, items, and preferences
- **Done:** Repository protocol and SwiftData implementation
- **Done:** Today, Inbox, Capture, and item editor
- **Done:** Edit, complete/undo, archive/restore, and confirmed deletion
- **Done:** Empty and persistence-error states
- **Done:** Accessibility labels and hints for interactive controls
- **Done:** Durable first-capture onboarding, non-expiring accessible first receipt, and cancellation recovery
- **Done:** Delayed and dismissible capture-anywhere discovery, educational empty states, and replayable Learn Speak It guide
- **Done:** In-memory sample preview data
- **Done:** Repository unit test source
- **Done:** Device SDK build in Xcode 26.6
- **Done:** Versioned SwiftData schema and protected storage-failure state
- **Done:** 304 repository, extraction, routing, sync, reminder, draft, integration, and reliability tests on an iPhone 17 simulator
- **Done:** Final 1024×1024 production app icon (opaque PNG, no alpha)
- **Next:** Real-device VoiceOver and large Dynamic Type review
- **Next:** Moderated first-run usability test covering Welcome → first capture → receipt → Today/Memory guide

## Phase 2 — In-app voice capture

- **Done:** Microphone and speech permission education
- **Done:** Live Speech framework transcription with on-device recognition when supported
- **Done:** Reactive listening pulse and partial transcription
- **Done:** Listening, finalizing, saved, denied, unavailable, and failure states
- **Done:** Persist raw transcription before any future organization
- **Done:** Haptic saved confirmation
- **Next:** Validate transcription accuracy, interruptions, AirPods, and permission denial on physical iPhones

## Phase 3 — External capture

- **Done:** Save Thought App Intent and preconfigured App Shortcut phrases
- **Done:** In-app Back Tap, Siri, and Action Button setup guidance
- **Done:** Immediate Memory Pulse completion without delaying the Shortcut result
- **Done:** Short-window identical-text deduplication for external captures
- **Next:** Validate Back Tap and Siri completion while the app is terminated on a physical iPhone
- **Done:** Lock Screen widget and iOS 18 Control Center control
- **Done:** Today widget on the Lock Screen (inline, circular, rectangular), counts-only unless the user opts into task names

## Phase 4 — Local organization

- **Done:** Local keyword, person, category, type, and priority organization
- **Done:** Interrupted-organization recovery from the durable raw capture
- **Done:** Sentence splitting and local date parsing with regression fixtures
- **Later:** Broader confidence evaluator and classification dataset
- **Later:** Review UI for uncertain results
- **Later:** 150-phrase classification dataset and regression suite

## Subsequent phases

- **Later:** Structured language-model organization behind an explicit privacy boundary
- **Done:** Today prioritization and Memory search
- **Done:** Optional record-level iCloud merge with deletion tombstones and metadata synchronization
- **Done:** Approval-based Messages handoff and native Calendar event editor for timed tasks
- **Connected, launch-gated:** Server-backed referrals now use a Keychain UUID,
  StoreKit `appAccountToken`, Apple-signed transaction verification, a durable
  reward ledger, self/duplicate/expired-offer protection, and a 12-rewards-per-
  year cap. The app and website switches remain off until Apple offers, code
  inventory, hosting, and Sandbox end-to-end redemption have passed. Creator
  Offer Codes remain a separate Apple-backed system.
- **Later:** Consider whether capture deduplication should span capture sources.
  It is currently per-source, so the same words arriving by Siri and the in-app
  button at the same moment produce two rows. Pinned by
  `testTheSameWordsArrivingByTwoRoutesAtOnce`; see
  [DURABILITY_FINDINGS.md](DURABILITY_FINDINGS.md).
- **Later:** Optional read-only Calendar context inside Today after dedicated privacy and overlap research
- **Later:** Snooze/reschedule, morning notification, data export/delete-all, and optional integrations
- **Later:** Give a knowledge item a structured fact date of its own —
  a `knowledgeDate`, distinct from `dueDate` and `reminderDate`. Today a dated
  fact routes correctly to Memory and keeps the person's original wording, but
  the date it named is not retained in structured form, because the only date
  fields available mean "deadline" and "interrupt me" and neither is true of
  "Priya's birthday is December 4". Accepted for v1: the wording survives and
  the routing is right. What it would unlock is showing the date on the Memory
  row, sorting people by upcoming dates, and offering to turn a remembered date
  into a reminder later. Needs a versioned schema change and migration.
