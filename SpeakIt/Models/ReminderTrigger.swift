import Foundation

/// What causes a reminder to fire.
///
/// Speak It has two genuinely different kinds of trigger and no third one on the
/// horizon that resembles either. A time trigger is scheduled against a clock; a
/// place trigger is monitored against a region. They share almost nothing —
/// different resolution, different permission, different failure modes,
/// different reconciliation — so they are siblings here rather than variants of
/// one model.
///
/// This is why location was not added to `TemporalIntent` as another case. Every
/// temporal code path would have grown a branch that could not mean anything:
/// there is no wall clock for "when I get home", no daylight-saving policy, no
/// next occurrence to compute from a previous instant. The one thing they do
/// share is the shape of the pipeline —
///
/// ```text
/// TemporalIntent  → resolved Date      → UNNotificationRequest
/// LocationIntent  → resolved region    → CLCircularRegion
/// ```
///
/// — and that shape is a similarity worth copying, not a type worth merging.
enum ReminderTrigger: Codable, Equatable, Sendable {
    case time(TemporalIntent)
    case location(LocationIntent)

    var temporalIntent: TemporalIntent? {
        if case let .time(intent) = self { return intent }
        return nil
    }

    var locationIntent: LocationIntent? {
        if case let .location(intent) = self { return intent }
        return nil
    }

    /// True when this trigger repeats rather than firing once.
    var repeats: Bool {
        switch self {
        case let .time(intent):
            intent.kind == .calendarRecurrence || intent.kind == .durationRecurrence
        case let .location(intent):
            intent.repeats
        }
    }

    /// True once a person has set this trigger by hand. Both halves honour the
    /// same rule: an explicit edit outranks the sentence, forever.
    var isUserEdited: Bool {
        switch self {
        case let .time(intent): intent.isUserEdited
        case let .location(intent): intent.isUserEdited
        }
    }
}

/// A denormalized tag for the stored trigger, so a list can branch without
/// decoding a blob. Mirrors `CapturedItem.temporalKindRawValue`.
enum ReminderTriggerKind: String, Codable, CaseIterable, Sendable {
    case time
    case location
}

extension ReminderTrigger {
    var kind: ReminderTriggerKind {
        switch self {
        case .time: .time
        case .location: .location
        }
    }
}

/// The device's current ability to monitor places.
///
/// **Never persisted.** Permission is environmental state that changes without
/// the reminder's meaning changing: a reminder that was authorized yesterday and
/// denied today still means "remind me when I get home". Storing the permission
/// beside the intent would freeze a fact about the device into a fact about the
/// request, and the app would then have to decide which one was stale.
///
/// So this is always queried, never saved. If it disappears, the reminder is
/// kept and surfaced as `LocationReminderBlocker.permissionRevoked`; nothing is
/// deleted and nothing is silently disabled.
struct LocationAuthorization: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case notDetermined
        case denied
        case restricted
        case whenInUse
        case always
    }

    var status: Status
    var isPrecise: Bool
    var isRegionMonitoringAvailable: Bool

    /// Regions can only be monitored in the background with Always access, and
    /// a place reminder that only works while the app is open is not a place
    /// reminder.
    var canMonitorRegions: Bool {
        status == .always && isPrecise && isRegionMonitoringAvailable
    }

    /// The blocker this authorization implies, or `nil` when nothing is wrong.
    /// Ordered most-fundamental first, so the person is told the one thing that
    /// actually unblocks them rather than the last check that happened to fail.
    var blocker: LocationReminderBlocker? {
        guard isRegionMonitoringAvailable else { return .monitoringUnavailable }
        switch status {
        case .notDetermined: return .permissionRequired
        case .denied: return .permissionRevoked
        case .restricted: return .monitoringUnavailable
        case .whenInUse: return .alwaysPermissionRequired
        case .always: return isPrecise ? nil : .preciseLocationRequired
        }
    }
}
