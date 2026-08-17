import AlarmKit
import Foundation
import SwiftUI
import UIKit
import UserNotifications

struct ReminderScheduleRequest: Hashable, Sendable {
    let itemID: UUID
    let captureSessionID: UUID?
    let title: String
    let fireDate: Date
    let delivery: ReminderDelivery

    @MainActor
    init?(item: CapturedItem) {
        guard let fireDate = item.reminderDate, fireDate > .now else { return nil }
        let originalText = item.originalTextSegment
        let segmentDelivery = ThoughtOrganizer.organize(
            originalText,
            referenceDate: item.createdAt
        ).reminderDelivery
        let sessionDelivery = item.captureSession.map {
            ThoughtOrganizer.organize(
                $0.originalTranscription,
                referenceDate: $0.createdAt
            ).reminderDelivery
        } ?? .none

        itemID = item.id
        captureSessionID = item.captureSession?.id
        title = ReminderCopy.action(
            from: item.displayTitle == originalText ? originalText : item.displayTitle
        )
        self.fireDate = fireDate
        delivery = segmentDelivery == .alarm || (segmentDelivery == .none && sessionDelivery == .alarm)
            ? .alarm
            : .notification
    }
}

struct ReminderSynchronizationScope: Equatable, Sendable {
    var itemIDs: Set<UUID>
    var captureSessionIDs: Set<UUID>
    var replacesAllSpeakItReminders: Bool

    init(
        itemIDs: Set<UUID> = [],
        captureSessionIDs: Set<UUID> = [],
        replacesAllSpeakItReminders: Bool = false
    ) {
        self.itemIDs = itemIDs
        self.captureSessionIDs = captureSessionIDs
        self.replacesAllSpeakItReminders = replacesAllSpeakItReminders
    }

    init(requests: [ReminderScheduleRequest]) {
        itemIDs = Set(requests.map(\.itemID))
        captureSessionIDs = Set(requests.compactMap(\.captureSessionID))
        replacesAllSpeakItReminders = false
    }

    mutating func include(_ requests: [ReminderScheduleRequest]) {
        itemIDs.formUnion(requests.map(\.itemID))
        captureSessionIDs.formUnion(requests.compactMap(\.captureSessionID))
    }
}

/// Turns a spoken instruction into the action a person actually needs to see.
/// The full transcript remains stored on the capture session; this copy is only
/// used for the organized item and its reminder presentation.
enum ReminderCopy {
    static func action(from transcript: String) -> String {
        let original = normalized(transcript)
        guard !original.isEmpty else { return "Your reminder" }

        // Both the verb form ("remind me to …") and the noun form ("give me a
        // reminder to …") are requests for a reminder, so both must be stripped
        // before the row title and notification body are built.
        let commandPattern = #"(?i)(?:"# + ReminderPhrasing.sentenceLead
            + #"|^(?:please\s+)?(?:set\s+(?:an?\s+)?(?:alarm|timer)|start\s+(?:an?\s+)?timer|wake\s+me(?:\s+up)?)\b)"#
        guard original.range(of: commandPattern, options: .regularExpression) != nil else {
            return sentenceCased(original)
        }

        var candidate: String
        if let actionConnector = original.range(
            of: #"(?i)\bto\s+"#,
            options: .regularExpression
        ) {
            candidate = String(original[actionConnector.upperBound...])
        } else if let aboutConnector = original.range(
            of: #"(?i)\babout\s+"#,
            options: .regularExpression
        ) {
            candidate = String(original[aboutConnector.upperBound...])
        } else {
            candidate = original.replacingOccurrences(
                of: commandPattern,
                with: "",
                options: .regularExpression
            )
        }

        // Remove timing language when it appears after the action, as in
        // “remind me to call Mum in ten minutes” or “...tomorrow at six”.
        let trailingTimingPatterns = [
            #"(?i)\s+in\s+(?:\d+|[a-z]+(?:[\s-][a-z]+)?)\s+(?:seconds?|minutes?|hours?|days?|weeks?)\s*[.!?]*$"#,
            #"(?i)\s+(?:today|tonight|tomorrow)(?:\s+at\s+(?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve))?\s*[.!?]*$"#,
            #"(?i)\s+at\s+(?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s*[.!?]*$"#
        ]
        for pattern in trailingTimingPatterns {
            candidate = candidate.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        // If no “to/about” connector was spoken, remove a leading interval.
        candidate = candidate.replacingOccurrences(
            of: #"(?i)^\s*(?:in\s+(?:\d+|[a-z]+(?:[\s-][a-z]+)?)\s+(?:seconds?|minutes?|hours?|days?|weeks?)|today|tonight|tomorrow|at\s+\S+)\s*[:,.-]?\s*"#,
            with: "",
            options: .regularExpression
        )
        candidate = candidate.replacingOccurrences(
            of: #"(?i)^\s*(?:that\s+|to\s+|about\s+)"#,
            with: "",
            options: .regularExpression
        )
        candidate = normalized(candidate).trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))

        return candidate.isEmpty ? "Your reminder" : sentenceCased(candidate)
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func sentenceCased(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + String(value.dropFirst())
    }
}

enum ReminderAccessStatus: Equatable {
    case ready
    case needsPermission
    case denied
}

enum ReminderSchedulingResult: Equatable, Sendable {
    case scheduled
    case needsPermission
    case denied
    case failed
}

@MainActor
enum ReminderScheduler {
    static let reminderCategoryIdentifier = "SpeakIt.reminder-actions"
    static let completeActionIdentifier = "SpeakIt.reminder.complete"
    static let snoozeActionIdentifier = "SpeakIt.reminder.snooze-ten"
    static let tomorrowActionIdentifier = "SpeakIt.reminder.tomorrow"
    private static var synchronizationTail: Task<Void, Never>?

    static func requestNotificationAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private struct SpeakItAlarmMetadata: AlarmMetadata {
        let itemID: UUID
    }

    /// Delivers a place reminder now, because its region has just been crossed.
    ///
    /// Place triggers have no fire date to schedule against — the trigger *is*
    /// the arrival — so this is a short interval trigger rather than a calendar
    /// one. It carries the same category and payload as a time reminder, so the
    /// Done/Snooze actions and the tap-through behave identically: from the
    /// person's side a reminder is a reminder, whatever caused it.
    @discardableResult
    static func deliverPlaceReminder(
        itemID: UUID,
        title: String,
        placeDescription: String,
        notificationIdentifier: String
    ) async -> ReminderSchedulingResult {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            return .denied
        default:
            // Notification permission may legitimately be absent while location
            // permission is present. The reminder is not lost — the item keeps
            // its intent and the next foreground reconcile will still show it.
            return .needsPermission
        }

        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body = "\(title) — \(placeDescription)"
        content.sound = .default
        content.threadIdentifier = "speak-it-reminders"
        content.categoryIdentifier = reminderCategoryIdentifier
        content.userInfo = ["itemIDs": [itemID.uuidString]]
        if settings.timeSensitiveSetting == .enabled {
            content.interruptionLevel = .timeSensitive
        }

        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await center.add(request)
            return .scheduled
        } catch {
            return .failed
        }
    }

    /// Withdraws a just-scheduled place delivery when a post-scheduling
    /// revalidation finds that the item was completed, deleted, or edited while
    /// UserNotifications was accepting the request.
    static func cancelPlaceDelivery(notificationIdentifier: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
    }

    private struct NotificationGroup {
        let identifier: String
        let requests: [ReminderScheduleRequest]

        var fireDate: Date { requests[0].fireDate }
        var title: String { requests.count == 1 ? "Reminder" : "\(requests.count) reminders" }
        var body: String {
            guard requests.count > 1 else { return requests[0].title }
            let titles = requests.prefix(3).map(\.title).joined(separator: " · ")
            return requests.count > 3 ? "\(titles) · +\(requests.count - 3) more" : titles
        }
        var itemIDs: [UUID] { requests.map(\.itemID) }
    }

    static func registerNotificationCategories() {
        let complete = UNNotificationAction(
            identifier: completeActionIdentifier,
            title: "Done",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: "10 min",
            options: []
        )
        let tomorrow = UNNotificationAction(
            identifier: tomorrowActionIdentifier,
            title: "Tomorrow",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: reminderCategoryIdentifier,
            actions: [complete, snooze, tomorrow],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func synchronize(
        _ request: ReminderScheduleRequest,
        requestAuthorizationIfNeeded: Bool
    ) {
        synchronize(
            [request],
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded,
            scope: ReminderSynchronizationScope(requests: [request])
        )
    }

    static func synchronize(
        _ requests: [ReminderScheduleRequest],
        requestAuthorizationIfNeeded: Bool,
        scope: ReminderSynchronizationScope? = nil,
        onCompletion: (([ReminderSchedulingResult]) -> Void)? = nil
    ) {
        let predecessor = synchronizationTail
        synchronizationTail = Task {
            // Repository mutations can arrive back-to-back (for example a
            // grouped notification action). Preserve their order so an older
            // scheduling pass can never finish after and overwrite a newer one.
            await predecessor?.value
            let results = await scheduleBatch(
                requests,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded,
                scope: scope
            )
            onCompletion?(results)
        }
    }

    static func synchronizeAndVerify(
        _ requests: [ReminderScheduleRequest],
        requestAuthorizationIfNeeded: Bool,
        scope: ReminderSynchronizationScope? = nil
    ) async -> [ReminderSchedulingResult] {
        await synchronizationTail?.value
        return await scheduleBatch(
            requests,
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded,
            scope: scope
        )
    }

    static func scheduleAndVerify(
        _ request: ReminderScheduleRequest,
        requestAuthorizationIfNeeded: Bool
    ) async -> ReminderSchedulingResult {
        await schedule(
            request,
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
        )
    }

    static func scheduleDeliveryTest(after delay: TimeInterval = 5) async -> ReminderSchedulingResult {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            return .denied
        default:
            return .needsPermission
        }

        let identifier = "SpeakIt.notification-test"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Speak It reminder"
        content.body = "Notifications are ready."
        content.sound = .default
        content.interruptionLevel = .active

        let notification = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(delay, 1),
                repeats: false
            )
        )

        do {
            try await center.add(notification)
            let pending = await center.pendingNotificationRequests()
            return pending.contains(where: { $0.identifier == identifier })
                ? .scheduled
                : .failed
        } catch {
            return .failed
        }
    }

    static func cancel(itemID: UUID) {
        let identifier = notificationIdentifier(for: itemID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])

        if #available(iOS 26.0, *) {
            try? AlarmManager.shared.cancel(id: itemID)
        }
    }

    static func cancel(captureSessionID: UUID) {
        Task {
            let center = UNUserNotificationCenter.current()
            let prefix = notificationGroupPrefix(for: captureSessionID)
            let identifiers = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    static func accessStatus(for requests: [ReminderScheduleRequest]) async -> ReminderAccessStatus {
        guard !requests.isEmpty else { return .ready }

        var needsPermission = false
        var denied = false

        if requests.contains(where: { $0.delivery == .notification }) || !supportsAlarmKit(for: requests) {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            case .notDetermined:
                needsPermission = true
            case .denied:
                denied = true
            @unknown default:
                needsPermission = true
            }
        }

        if #available(iOS 26.0, *), requests.contains(where: { $0.delivery == .alarm }) {
            switch AlarmManager.shared.authorizationState {
            case .authorized:
                break
            case .notDetermined:
                needsPermission = true
            case .denied:
                denied = true
            @unknown default:
                needsPermission = true
            }
        }

        if denied { return .denied }
        if needsPermission { return .needsPermission }
        return .ready
    }

    @discardableResult
    static func requestAccessAndSchedule(_ requests: [ReminderScheduleRequest]) async -> Bool {
        let needsNotificationPermission = requests.contains(where: { $0.delivery == .notification })
            || !supportsAlarmKit(for: requests)

        if needsNotificationPermission {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
            }
        }

        if #available(iOS 26.0, *), requests.contains(where: { $0.delivery == .alarm }),
           AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }

        let results = await scheduleBatch(
            requests,
            requestAuthorizationIfNeeded: false,
            scope: nil
        )
        return !results.isEmpty && results.allSatisfy { $0 == .scheduled }
    }

    /// What to tell the person their capture became, immediately after saving.
    ///
    /// This used to re-run `ThoughtOrganizer` over the original text and decide
    /// a destination from that fresh parse, which made it a second opinion
    /// rather than a report: it never looked at `locationIntent` or at the live
    /// location blocker, so "take the bins out when I get home" with no Home
    /// configured was announced as "Today · When you have time" while the item
    /// it had just saved went to Needs review. The receipt now reads the same
    /// derivation Today reads, so the two cannot disagree.
    ///
    /// The only thing still parsed is alarm-vs-notification wording, because
    /// `ReminderDelivery` is not stored on the item — `ReminderScheduleRequest`
    /// re-derives it the same way for the same reason.
    @MainActor
    static func confirmationContext(for item: CapturedItem) -> String {
        confirmationContext(
            for: item,
            authorization: LocationReminderMonitor.shared.authorization
        )
    }

    /// The deterministic form used when a caller has already taken a snapshot
    /// of device authorization. Passing the same snapshot to every presentation
    /// surface prevents a permission change between reads from producing two
    /// answers for one item, and keeps the contract directly testable.
    @MainActor
    static func confirmationContext(
        for item: CapturedItem,
        authorization: LocationAuthorization
    ) -> String {
        let presentation = ItemPresentation.make(
            for: item,
            authorization: authorization
        )

        // Review outranks every other description. An item that cannot act yet
        // must say so here, where the person is still looking at the screen.
        if presentation.requiresReview {
            guard let requirement = presentation.reviewRequirement else {
                return presentation.destination.announcement
            }
            return "\(presentation.destination.announcement) · \(requirement)"
        }

        switch presentation.reminderState {
        case .place:
            guard let trigger = presentation.triggerSummary else {
                return presentation.destination.announcement
            }
            return "Place reminder · \(trigger)"

        case .blockedPlace:
            // Unreachable in practice: a blocked place reminder requires review
            // and is handled above. Kept explicit so a future change to the
            // blocker rules cannot silently fall through to a timing string.
            return presentation.destination.announcement

        case let .time(date, _):
            let kind = deliveryKindLabel(for: item)
            if let recurrence = presentation.recurrenceSummary {
                return "\(kind) · \(friendlyDate(date)) · \(recurrence)"
            }
            return "\(kind) · \(friendlyDate(date))"

        case .none:
            if presentation.destination == .memory {
                return "Memory · \(item.category.displayName)"
            }
            return presentation.destination.announcement
        }
    }

    @MainActor
    private static func deliveryKindLabel(for item: CapturedItem) -> String {
        guard item.reminderDate != nil else { return "Timeline" }
        let delivery = ThoughtOrganizer.organize(
            item.originalTextSegment,
            referenceDate: item.createdAt
        ).reminderDelivery
        return delivery == .alarm ? "Alarm" : "Reminder"
    }

    private static func schedule(
        _ request: ReminderScheduleRequest,
        requestAuthorizationIfNeeded: Bool
    ) async -> ReminderSchedulingResult {
        guard request.fireDate > .now else {
            cancel(itemID: request.itemID)
            return .failed
        }

        cancel(itemID: request.itemID)

        if request.delivery == .alarm, #available(iOS 26.0, *) {
            let manager = AlarmManager.shared
            var authorization = manager.authorizationState
            if authorization == .notDetermined, requestAuthorizationIfNeeded {
                authorization = (try? await manager.requestAuthorization()) ?? .notDetermined
            }

            if authorization == .authorized {
                do {
                    let alert: AlarmPresentation.Alert
                    if #available(iOS 26.1, *) {
                        alert = AlarmPresentation.Alert(
                            title: LocalizedStringResource(stringLiteral: request.title)
                        )
                    } else {
                        alert = AlarmPresentation.Alert(
                            title: LocalizedStringResource(stringLiteral: request.title),
                            stopButton: AlarmButton(
                                text: "Stop",
                                textColor: .white,
                                systemImageName: "stop.fill"
                            )
                        )
                    }
                    let attributes = AlarmAttributes(
                        presentation: AlarmPresentation(alert: alert),
                        metadata: SpeakItAlarmMetadata(itemID: request.itemID),
                        tintColor: .black
                    )
                    let configuration = AlarmManager.AlarmConfiguration.alarm(
                        schedule: .fixed(request.fireDate),
                        attributes: attributes
                    )
                    _ = try await manager.schedule(id: request.itemID, configuration: configuration)
                    return .scheduled
                } catch {
                    // A normal notification is a safe fallback when an alarm
                    // cannot be registered (for example, the system limit).
                }
            } else if authorization == .notDetermined {
                return .needsPermission
            } else if authorization == .denied {
                // Respect the alarm decision. Use an already-authorized normal
                // notification as a fallback, but don't immediately show a
                // second permission prompt after the person declined alarms.
                return await scheduleNotification(
                    request,
                    requestAuthorizationIfNeeded: false
                )
            }
        }

        let group = NotificationGroup(
            identifier: notificationIdentifier(for: request.itemID),
            requests: [request]
        )
        return await scheduleNotification(
            group,
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
        )
    }

    private static func scheduleNotification(
        _ request: ReminderScheduleRequest,
        requestAuthorizationIfNeeded: Bool
    ) async -> ReminderSchedulingResult {
        await scheduleNotification(
            NotificationGroup(
                identifier: notificationIdentifier(for: request.itemID),
                requests: [request]
            ),
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
        )
    }

    private static func scheduleNotification(
        _ group: NotificationGroup,
        requestAuthorizationIfNeeded: Bool
    ) async -> ReminderSchedulingResult {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        var authorizationStatus = settings.authorizationStatus
        var isAuthorized = switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }

        if authorizationStatus == .notDetermined, requestAuthorizationIfNeeded {
            isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
            settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
        guard isAuthorized else {
            return authorizationStatus == .denied ? .denied : .needsPermission
        }

        let content = UNMutableNotificationContent()
        content.title = group.title
        content.body = group.body
        content.sound = .default
        content.threadIdentifier = "speak-it-reminders"
        content.categoryIdentifier = reminderCategoryIdentifier
        content.userInfo = ["itemIDs": group.itemIDs.map(\.uuidString)]
        if settings.timeSensitiveSetting == .enabled {
            content.interruptionLevel = .timeSensitive
        }

        let secondsUntilFire = group.fireDate.timeIntervalSinceNow
        let trigger: UNNotificationTrigger
        if secondsUntilFire <= 60 {
            // Relative reminders such as “in 10 seconds” should count down
            // from the moment the thought is saved. A time-interval trigger
            // also avoids missing the requested calendar second while iOS is
            // finishing authorization or registering the request.
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(secondsUntilFire, 1),
                repeats: false
            )
        } else {
            // Deliberately a concrete snapshot, not `autoupdatingCurrent`: this
            // resolves the stored instant into fixed components once, at
            // scheduling time. Without a pinned zone, iOS re-reads these
            // wall-clock components in whatever zone the device is in when the
            // trigger fires, so flying somewhere would move the reminder off
            // the moment Today shows for it. An autoupdating zone here would
            // reintroduce exactly that drift.
            var components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: group.fireDate
            )
            components.timeZone = TimeZone.current
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        let notification = UNNotificationRequest(
            identifier: group.identifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(notification)
            let pending = await center.pendingNotificationRequests()
            return pending.contains(where: { $0.identifier == notification.identifier })
                ? .scheduled
                : .failed
        } catch {
            return .failed
        }
    }

    private static func scheduleBatch(
        _ requests: [ReminderScheduleRequest],
        requestAuthorizationIfNeeded: Bool,
        scope: ReminderSynchronizationScope?
    ) async -> [ReminderSchedulingResult] {
        let futureRequests = requests.filter { $0.fireDate > .now }
        var resolvedScope = scope ?? ReminderSynchronizationScope(requests: requests)
        resolvedScope.include(requests)

        for itemID in resolvedScope.itemIDs {
            cancel(itemID: itemID)
        }
        await clearExistingNotifications(scope: resolvedScope)

        var results: [ReminderSchedulingResult] = []
        for request in futureRequests where request.delivery == .alarm {
            results.append(await schedule(
                request,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
            ))
        }
        for group in notificationGroups(
            from: futureRequests.filter { $0.delivery == .notification }
        ) {
            results.append(await scheduleNotification(
                group,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
            ))
        }
        return results
    }

    private static func notificationGroups(
        from requests: [ReminderScheduleRequest]
    ) -> [NotificationGroup] {
        let grouped = Dictionary(grouping: requests) { request -> String in
            if let sessionID = request.captureSessionID {
                return "\(sessionID.uuidString)-\(Int(request.fireDate.timeIntervalSince1970.rounded()))"
            }
            return request.itemID.uuidString
        }
        return grouped.map { key, groupedRequests in
            let ordered = groupedRequests.sorted { $0.itemID.uuidString < $1.itemID.uuidString }
            let identifier: String
            if let sessionID = ordered.first?.captureSessionID {
                identifier = "\(notificationGroupPrefix(for: sessionID))\(key)"
            } else {
                identifier = notificationIdentifier(for: ordered[0].itemID)
            }
            return NotificationGroup(identifier: identifier, requests: ordered)
        }
    }

    static func notificationIdentifiersToRemove(
        from identifiers: [String],
        scope: ReminderSynchronizationScope
    ) -> [String] {
        let itemIdentifiers = Set(scope.itemIDs.map { notificationIdentifier(for: $0) })
        let sessionPrefixes = Set(scope.captureSessionIDs.map { notificationGroupPrefix(for: $0) })
        return identifiers.filter { identifier in
            (scope.replacesAllSpeakItReminders && isSpeakItReminderIdentifier(identifier))
                || itemIdentifiers.contains(identifier)
                || sessionPrefixes.contains(where: identifier.hasPrefix)
        }
    }

    private static func clearExistingNotifications(scope: ReminderSynchronizationScope) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = notificationIdentifiersToRemove(
            from: await center.pendingNotificationRequests().map(\.identifier),
            scope: scope
        )
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private static func notificationIdentifier(for itemID: UUID) -> String {
        "SpeakIt.reminder.\(itemID.uuidString)"
    }

    private static func notificationGroupPrefix(for sessionID: UUID) -> String {
        "SpeakIt.session.\(sessionID.uuidString)."
    }

    private static func isSpeakItReminderIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("SpeakIt.reminder.") || identifier.hasPrefix("SpeakIt.session.")
    }

    private static func supportsAlarmKit(for requests: [ReminderScheduleRequest]) -> Bool {
        if #available(iOS 26.0, *) {
            return !requests.contains(where: { $0.delivery == .notification })
        }
        return false
    }

    private static func friendlyDate(_ date: Date) -> String {
        let secondsUntilDate = date.timeIntervalSinceNow
        if secondsUntilDate > 0, secondsUntilDate <= 60 {
            let seconds = max(1, Int(ceil(secondsUntilDate)))
            return "in \(seconds) \(seconds == 1 ? "second" : "seconds")"
        }
        if secondsUntilDate <= 0, secondsUntilDate > -60 {
            return "now"
        }

        // Tracks the person's live calendar and time-zone settings, so this
        // reads "Today" from where they are now, not where they were.
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) {
            return "Today \(date.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
