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
- **Later:** Server-backed referrals with stable user identity, verified App
  Store redemption callbacks, one reward per new person, self-referral and
  replay prevention, a referral credit ledger, and a 12-rewards-per-year cap.
  Do not ship reward language until the end-to-end credit flow is live and
  verified. Creator Offer Codes remain a separate Apple-backed system.
- **Later:** Optional read-only Calendar context inside Today after dedicated privacy and overlap research
- **Later:** Snooze/reschedule, morning notification, data export/delete-all, and optional integrations
