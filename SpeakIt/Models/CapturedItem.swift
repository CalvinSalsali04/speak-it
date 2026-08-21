import Foundation
import SwiftData

@Model
final class CapturedItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var originalTextSegment: String
    var displayTitle: String
    var itemTypeRawValue: String
    var categoryRawValue: String
    var createdAt: Date
    var dueDate: Date?
    var reminderDate: Date?
    var priorityRawValue: Int
    var personName: String?
    var completedAt: Date?
    var isArchived: Bool
    var archivedAt: Date?
    var processingConfidence: Double
    var needsClarification: Bool
    var isReviewed: Bool
    var lastModifiedAt: Date

    /// What the person actually said about time, kept beside the instant it
    /// resolved to. `dueDate` and `reminderDate` remain the resolved values so
    /// they stay queryable and sortable; this is the meaning behind them.
    ///
    /// Stored encoded rather than as a dozen columns because nothing queries
    /// its interior — the resolved dates cover every predicate the app makes —
    /// and a single blob lets the shape evolve without another schema version.
    var temporalIntentData: Data?

    /// A denormalized copy of `temporalIntent.kind`. Every row in Today reads
    /// it to decide whether it may show a time of day, so it is worth having
    /// without decoding. Always written together with `temporalIntentData`.
    var temporalKindRawValue: String?

    /// What the person said about *where*, when they named a place instead of a
    /// time. Stored separately from `temporalIntentData` because a place trigger
    /// is a sibling of a time trigger, not a variety of one — see
    /// `ReminderTrigger`.
    ///
    /// Deliberately holds no permission state. Whether the device can currently
    /// monitor this region is environmental and is always queried, never saved.
    var locationIntentData: Data?

    /// A denormalized copy of which trigger this item carries, so Today and the
    /// review list can branch without decoding either blob. Always written
    /// together with the intent it describes.
    var reminderTriggerKindRawValue: String?

    var captureSession: CaptureSession?

    init(
        id: UUID = UUID(),
        originalTextSegment: String,
        displayTitle: String,
        itemType: ItemType = .unclear,
        category: ItemCategory = .general,
        createdAt: Date = .now,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        priority: ItemPriority = .normal,
        personName: String? = nil,
        completedAt: Date? = nil,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        processingConfidence: Double = 1,
        needsClarification: Bool = false,
        isReviewed: Bool = false,
        lastModifiedAt: Date = .now,
        temporalIntent: TemporalIntent? = nil,
        locationIntent: LocationIntent? = nil,
        captureSession: CaptureSession? = nil
    ) {
        self.id = id
        self.originalTextSegment = originalTextSegment
        self.displayTitle = displayTitle
        self.itemTypeRawValue = itemType.rawValue
        self.categoryRawValue = category.rawValue
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.priorityRawValue = priority.rawValue
        self.personName = personName
        self.completedAt = completedAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.processingConfidence = processingConfidence
        self.needsClarification = needsClarification
        self.isReviewed = isReviewed
        self.lastModifiedAt = lastModifiedAt
        self.captureSession = captureSession
        self.temporalIntent = temporalIntent
        self.locationIntent = locationIntent
    }

    /// The stored intent, or `nil` for a row written before version 2 that has
    /// not been backfilled yet. Reading it never invents a kind — an absent
    /// intent stays absent so the backfill can tell it still has work to do.
    var temporalIntent: TemporalIntent? {
        get {
            guard let temporalIntentData else { return nil }
            return try? JSONDecoder().decode(TemporalIntent.self, from: temporalIntentData)
        }
        set {
            temporalIntentData = newValue.flatMap { try? JSONEncoder().encode($0) }
            temporalKindRawValue = newValue?.kind.rawValue
            // A time intent that actually expresses a time makes this a time
            // trigger. An intent of kind `.none` — which is what an unsupported
            // place trigger stores — must not claim the item is time-triggered.
            if let newValue, newValue.kind != .none {
                reminderTriggerKindRawValue = ReminderTriggerKind.time.rawValue
            } else if reminderTriggerKindRawValue == ReminderTriggerKind.time.rawValue {
                reminderTriggerKindRawValue = nil
            }
        }
    }

    /// What the person said about *where*, or `nil` when they named no place.
    var locationIntent: LocationIntent? {
        get {
            guard let locationIntentData else { return nil }
            return try? JSONDecoder().decode(LocationIntent.self, from: locationIntentData)
        }
        set {
            locationIntentData = newValue.flatMap { try? JSONEncoder().encode($0) }
            if newValue != nil {
                reminderTriggerKindRawValue = ReminderTriggerKind.location.rawValue
            } else if reminderTriggerKindRawValue == ReminderTriggerKind.location.rawValue {
                reminderTriggerKindRawValue = nil
            }
        }
    }

    /// The trigger this item fires on, as one value.
    ///
    /// A place trigger wins when both are present: "when I get home tonight"
    /// names a place *and* a day, and the place is what decides the moment while
    /// the day only narrows it. Storing both and preferring location here is
    /// what keeps that sentence expressible without a combined rule engine.
    var reminderTrigger: ReminderTrigger? {
        if let locationIntent { return .location(locationIntent) }
        if let temporalIntent, temporalIntent.kind != .none { return .time(temporalIntent) }
        return nil
    }

    var reminderTriggerKind: ReminderTriggerKind? {
        reminderTriggerKindRawValue.flatMap(ReminderTriggerKind.init(rawValue:))
    }

    /// True when this item is waiting on a place rather than on a clock.
    var isLocationTriggered: Bool { locationIntent != nil }

    /// True when the sentence named a place *and* a time, which Speak It can
    /// represent but cannot yet enforce together.
    ///
    /// Both single-constraint readings are wrong in a way the person would
    /// notice — the time half fires away from the place, the place half fires at
    /// the wrong time — so this is surfaced as review rather than being resolved
    /// silently in either direction. It also keeps the item out of both
    /// schedulers, which is what stops "when I get home tonight" from firing
    /// twice once Home is configured.
    var constrainsBothPlaceAndTime: Bool {
        isLocationTriggered && (temporalKind ?? .none) != .none
    }

    /// Whether this item is waiting on the person for anything at all.
    ///
    /// **The one predicate Today and the editor must both use.** They used to
    /// disagree: the editor computed the live location blocker while the home
    /// screen read only the stored `needsClarification`, so "remind me when I
    /// get home" with no Home configured sat under "When you have time" looking
    /// perfectly fine, and only confessed it was stuck once you opened it.
    ///
    /// The two halves are different in kind and that is why they must be joined
    /// here rather than merged into one stored flag: `needsClarification` is
    /// what the *sentence* left unresolved and is persisted, while a location
    /// blocker is what the *device* currently lacks and must never be persisted
    /// (see `LocationAuthorization`). Neither can be derived from the other, and
    /// either one means the item cannot act yet.
    @MainActor
    func requiresReview(authorization: LocationAuthorization) -> Bool {
        guard !isArchived, !isCompleted else { return false }
        return needsClarification || locationBlocker(authorization: authorization) != nil
    }

    /// Today placement, judged against live device state.
    ///
    /// The counterpart of `requiresReview`: an item cannot be both waiting on
    /// the person and ready to act, and computing the two from the same answer
    /// is what stops it appearing in two sections at once.
    @MainActor
    func belongsInToday(authorization: LocationAuthorization) -> Bool {
        belongsInToday && !requiresReview(authorization: authorization)
    }

    /// Memory placement, judged against live device state.
    ///
    /// The authorization-aware counterpart of `belongsInMemory`, and it exists
    /// because the stored form was not the exact complement of `requiresReview`
    /// that this file claims it is. `isLiveThought` excludes `needsClarification`
    /// but knows nothing about a location blocker, so a `.note`-typed place
    /// reminder waiting on a Work address satisfied `belongsInMemory` *and*
    /// `requiresReview` at the same time, and appeared in Today's "Needs review"
    /// and in Memory's "Reference" simultaneously — one item, two destinations.
    ///
    /// Every Memory surface must use this rather than the stored property, for
    /// the same reason Today does.
    @MainActor
    func belongsInMemory(authorization: LocationAuthorization) -> Bool {
        belongsInMemory && !requiresReview(authorization: authorization)
    }

    /// What is stopping this place reminder from working, or `nil` when nothing
    /// is.
    ///
    /// Takes the authorization rather than reading it, because permission is
    /// device state that must not be cached on the item — see
    /// `LocationAuthorization`. The caller queries it once per reconcile and
    /// passes the same answer to every item.
    @MainActor
    func locationBlocker(
        authorization: LocationAuthorization
    ) -> LocationReminderBlocker? {
        guard let locationIntent else { return nil }
        return LocationReminderResolver.resolve(
            locationIntent,
            itemID: id,
            title: displayTitle,
            authorization: authorization
        ).blocker
    }

    /// The monitoring request this item wants, when it can have one.
    @MainActor
    func locationMonitorRequest(
        authorization: LocationAuthorization
    ) -> LocationMonitorRequest? {
        guard let locationIntent else { return nil }
        return LocationReminderResolver.resolve(
            locationIntent,
            itemID: id,
            title: displayTitle,
            authorization: authorization
        ).request
    }

    /// What kind of time this item carries. A row that predates version 2 and
    /// still has no intent reports `nil` rather than guessing, so callers can
    /// keep the older behavior for it instead of showing a time it never had.
    var temporalKind: TemporalKind? {
        temporalKindRawValue.flatMap(TemporalKind.init(rawValue:))
    }

    /// True when this item names a day but no time of day, so no row, editor,
    /// or notification may present an hour for it.
    var isDateOnly: Bool { temporalKind == .dateOnly }

    var itemType: ItemType {
        get { ItemType(rawValue: itemTypeRawValue) ?? .unclear }
        set { itemTypeRawValue = newValue.rawValue }
    }

    var category: ItemCategory {
        get { ItemCategory(rawValue: categoryRawValue) ?? .general }
        set { categoryRawValue = newValue.rawValue }
    }

    var priority: ItemPriority {
        get { ItemPriority(rawValue: priorityRawValue) ?? .normal }
        set { priorityRawValue = newValue.rawValue }
    }

    var isCompleted: Bool { completedAt != nil }

    /// A moment the person asked to be interrupted at.
    ///
    /// Deliberately *not* "this item has a date". A date says when something is
    /// true, and that is as much a property of a fact as of a task: "Priya's
    /// birthday is December 4" and "Alex moved to Toronto in September" both
    /// resolve a date, and neither is something to do. While any date counted,
    /// every dated fact was promoted out of Memory and onto Today no matter how
    /// carefully it had been read — `Actionability` draws the same line one
    /// layer up, and this property was quietly undoing it.
    ///
    /// A reminder is different in kind. Nobody acquires one by accident: it is
    /// either asked for out loud ("remind me on December 4 that it is Priya's
    /// birthday") or set by hand in the editor, and both are the person saying
    /// they want to be interrupted. A `dueDate` needs no such rescue, because
    /// every type that can carry a deadline is already `isActionable`.
    var isTimeCommitted: Bool { reminderDate != nil }

    /// Today is for action. Written as the exact complement of `belongsInMemory`
    /// so no live item can ever fall out of both destinations.
    var belongsInToday: Bool {
        isLiveThought && (itemType.isActionable || isTimeCommitted)
    }

    /// Memory is the durable knowledge layer, not a second task list.
    /// Actionable and completed items remain preserved in Today/Completed.
    var belongsInMemory: Bool {
        isLiveThought && !(itemType.isActionable || isTimeCommitted)
    }

    /// Neither archived, done, nor waiting on the person to resolve something.
    private var isLiveThought: Bool {
        !isArchived && !isCompleted && !needsClarification
    }

    /// What the person has to supply before this item can leave "Needs review".
    ///
    /// `needsClarification` is a single Bool, so the reason extraction had at
    /// capture time is not stored — see `ClarificationRequirement` for what that
    /// costs. This re-derives the most likely reason from the item's own fields
    /// so the review list can name the gap instead of saying "tap to find out".
    var clarificationRequirement: ClarificationRequirement? {
        guard needsClarification else { return nil }

        // A held broad cancel or complete is not a type/date/person gap at
        // all — the review row exists purely to confirm or decline a
        // destructive request, and every field below would ask the wrong
        // question. Checked first because this placeholder also happens to
        // satisfy `itemType == .unclear`. See FINAL_RELEASE_AUDIT.md F-1.
        if PendingOperationStore.record(for: id) != nil { return .pendingOperation }

        // Checked ahead of the plain place trigger: a request that constrained
        // both a place and a time is not a place reminder waiting on setup, it
        // is a request Speak It cannot honour in full. Reporting it as an
        // ordinary place reminder would imply that configuring Home is enough
        // to make it behave, and it is not.
        if constrainsBothPlaceAndTime { return .combinedTimeAndPlace }
        // A place trigger is a different state from not understanding the
        // request, and must never be phrased as a question. What is actually
        // missing — permission, a Home address, which Costco — is named by
        // `locationBlocker(authorization:)`, which needs the device state this
        // pure property cannot see.
        if isLocationTriggered { return .locationTrigger }
        // A row captured before place reminders existed, still carrying the old
        // "understood but unsupported" marker.
        if temporalIntent?.unsupportedTrigger == .location {
            return .unsupportedLocationTrigger
        }
        if temporalIntent?.unsupportedTrigger == .condition {
            return .unsupportedConditionTrigger
        }
        if holdsWholeUnsplitTranscript { return .splitDecision }
        if itemType == .unclear { return .type }
        let hasPerson = personName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        if itemType == .personFollowUp, !hasPerson { return .person }
        if itemType.isActionable, reminderDate == nil { return .time }
        return .confirmation
    }

    /// True when this item still carries its capture's entire transcript and that
    /// transcript reads like it holds more than one intention. Extraction keeps a
    /// capture whole when splitting it would be unsafe (negation, reported speech,
    /// destructive phrasing) and when the person undoes an organization, and both
    /// land here.
    private var holdsWholeUnsplitTranscript: Bool {
        guard let session = captureSession, session.items.count == 1 else { return false }
        let transcript = session.originalTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty,
              originalTextSegment.trimmingCharacters(in: .whitespacesAndNewlines) == transcript else {
            return false
        }
        return transcript.range(
            of: #"(?i)(?:[,;]|\band\b|\balso\b|\bthen\b)"#,
            options: .regularExpression
        ) != nil
    }
}

/// The specific input a flagged item is waiting on.
///
/// These are re-derived from item fields at read time rather than recorded when
/// extraction flags the item, so they are a good guess rather than ground truth.
/// Persisting the reason at capture time (a versioned schema change) would make
/// them exact and would let a row tap jump straight to the field in question.
enum ClarificationRequirement: String, CaseIterable, Sendable {
    /// Extraction wanted to schedule a reminder but could not resolve a time.
    case time
    /// A follow-up whose person never got resolved.
    case person
    /// Extraction could not tell whether this belongs in Today or Memory.
    case type
    /// The capture stayed whole and may hold more than one intention.
    case splitDecision
    /// Flagged on low confidence with no single identifiable gap.
    case confirmation
    /// Understood perfectly, but names a trigger Speak It could not schedule at
    /// the time it was captured. Only reachable for rows older than place
    /// reminders. Deliberately not a form of ambiguity — nothing is unclear.
    case unsupportedLocationTrigger
    /// A clear non-spatial condition (for example payday or another event
    /// completing) that Speak It cannot monitor automatically.
    case unsupportedConditionTrigger
    /// A place reminder that is waiting on something. Which thing is named by
    /// `CapturedItem.locationBlocker(authorization:)`, because the answer
    /// depends on live device state rather than on anything stored.
    case locationTrigger
    /// The sentence constrained both a place and a time — "when I get home
    /// tonight" — and Speak It enforces only one of them. Held for review
    /// rather than reduced to whichever half is easier to honour.
    case combinedTimeAndPlace
    /// A broad cancel or complete request ("cancel everything") that Speak It
    /// never executes automatically. The row exists to confirm or decline it,
    /// not to classify anything. See `PendingOperationStore`.
    case pendingOperation

    /// Shown on the review row. Names the gap in the person's own terms.
    var listLabel: String {
        switch self {
        case .time: "Needs a time"
        case .person: "Needs a person"
        case .type: "Task or note?"
        case .splitDecision: "Might be 2 thoughts"
        case .confirmation: "Needs confirmation"
        case .unsupportedLocationTrigger: "Place reminders not supported yet"
        case .unsupportedConditionTrigger: "Trigger not supported"
        case .locationTrigger: "Place reminder"
        case .combinedTimeAndPlace: "Needs review"
        case .pendingOperation: "Confirm first"
        }
    }

    /// Shown in the editor, above the field carrying the asterisk.
    var editorPrompt: String {
        switch self {
        case .time: "Select a time"
        case .person: "Add who this is about"
        case .type: "Choose a type"
        case .splitDecision: "Split this into separate items, or confirm it is one"
        case .confirmation: "Confirm this is right"
        case .unsupportedLocationTrigger: "Speak It can't remind you by place yet — set a time instead"
        case .unsupportedConditionTrigger:
            "Speak It can't detect that condition yet — choose a time instead"
        case .locationTrigger: "Finish setting up this place reminder"
        case .combinedTimeAndPlace:
            "Place and time conditions aren't supported together yet — choose one"
        case .pendingOperation: "That affects everything — confirm or decline"
        }
    }
}
