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
    /// Calendar components that let iOS re-fire this reminder on its own
    /// schedule, without the app ever running again to generate the next
    /// occurrence. `nil` for shapes a single `DateComponents` match cannot
    /// express, which keep the existing one-shot-then-regenerate-on-completion
    /// path (see `SwiftDataThoughtRepository.setCompleted`).
    let repeatingComponents: DateComponents?
    /// The named list a shopping row belongs to ("Sobeys"), or `nil` for
    /// everything else. A coalesced notification whose rows all share one
    /// list is titled by that list, so the alert reads the way the person
    /// spoke it: the store, then what to get there.
    let listName: String?
    /// When the item was created. A coalesced notification lists its rows in
    /// spoken order, which creation order preserves; the identifier's own
    /// ordering stays keyed by item ID so it remains stable across launches.
    let createdAt: Date

    @MainActor
    init?(item: CapturedItem) {
        guard let fireDate = item.reminderDate, fireDate > .now else { return nil }
        let originalText = item.originalTextSegment
        // The same memoized reading the rows render from. Today rebuilds these
        // requests on every render pass to keep its scheduling signature live,
        // which made two fresh `ThoughtOrganizer` parses per reminder item here
        // the single largest cost of scrolling that screen.
        let wordedDelivery = ItemPresentation.effectiveReminderDelivery(for: item)

        itemID = item.id
        captureSessionID = item.captureSession?.id
        title = ReminderCopy.action(
            from: item.displayTitle == originalText ? originalText : item.displayTitle
        )
        self.fireDate = fireDate
        delivery = wordedDelivery == .alarm ? .alarm : .notification
        repeatingComponents = Self.repeatingComponents(
            rule: item.temporalIntent?.recurrence,
            fireDate: fireDate
        )
        listName = item.itemType == .shopping
            ? ShoppingGroupStore.group(for: item.id)
            : nil
        createdAt = item.createdAt
    }

    /// Only daily and single-weekday weekly series, anchored to the
    /// scheduled date rather than to completion, reduce to one recurring
    /// `hour`/`minute`[/`weekday`] match. Elapsed-time rules ("every 3
    /// hours"), multi-weekday rules ("every weekday"), ordinal-monthly rules
    /// ("the first Monday every month"), an `interval` above 1, and
    /// completion-anchored rules all depend on state a static calendar match
    /// cannot express, so they are left on the existing path. Internal rather
    /// than private so `SwiftDataThoughtRepository`'s self-healing
    /// reconciliation pass can tell which shapes still need its help — see
    /// `advanceOverdueRecurrences`.
    static func repeatingComponents(
        rule: RecurrenceRule?,
        fireDate: Date
    ) -> DateComponents? {
        guard let rule,
              rule.anchor == .scheduledDate,
              rule.interval == 1,
              !rule.repeatsByElapsedTime,
              rule.ordinalWeekday == nil else { return nil }

        var components = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
        components.timeZone = TimeZone.current

        switch rule.frequency {
        case .daily:
            return components
        case .weekly:
            guard rule.weekdays.count == 1 else { return nil }
            components.weekday = rule.weekdays[0]
            return components
        case .monthly, .yearly:
            return nil
        }
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
    /// A pure function of its input, memoized because Today rebuilds every
    /// pending reminder request per render pass and this strips its title with
    /// a stack of regex passes each time. The cap bounds growth across a long
    /// session; the cache never needs invalidating because equal input always
    /// yields equal output.
    private static let actionCacheLock = NSLock()
    nonisolated(unsafe) private static var actionCache: [String: String] = [:]

    static func action(from transcript: String) -> String {
        actionCacheLock.lock()
        let cached = actionCache[transcript]
        actionCacheLock.unlock()
        if let cached { return cached }

        let result = strippedAction(from: transcript)
        actionCacheLock.lock()
        if actionCache.count >= 512 { actionCache.removeAll(keepingCapacity: true) }
        actionCache[transcript] = result
        actionCacheLock.unlock()
        return result
    }

    /// Removes a fronted day that sits directly in front of a reminder command.
    ///
    /// A day at the front of a capture is the schedule for every clause that
    /// follows it, so it gets carried onto each one — and a reminder clause
    /// arrives here as "Tomorrow remind me that I have a meeting at 4:15 PM".
    /// Every pattern below is anchored at the start of the sentence, so the day
    /// hid the command and the row kept the entire sentence as its title. The
    /// date is already parsed and held on the item, so dropping it costs
    /// nothing. Narrow on purpose: only a day immediately in front of a
    /// reminder command comes off, never one in front of an ordinary errand.
    private static func withoutFrontedDay(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?i)^(?:on\s+)?(?:today|tomorrow|tonight|this\s+(?:morning|afternoon|evening)|next\s+week|monday|tuesday|wednesday|thursday|thurs|friday|saturday|sunday)\s*,?\s+(?=(?:please\s+)?(?:remind|notify|alert)\s+me\b)"#,
            with: "",
            options: [.regularExpression]
        )
    }

    private static func strippedAction(from transcript: String) -> String {
        let original = withoutFrontedDay(normalized(transcript))
        guard !original.isEmpty else { return "Your reminder" }

        // "The report is due Friday but remind me Wednesday" is about the
        // report, not about the reminding. The trailing reminder clause is
        // machinery — the reminder date already captured it — so the title is
        // the statement in front of it, with any trailing timing the statement
        // itself carries stripped the usual way.
        if let reminderClause = original.range(
            // `\b` before the conjunction is load-bearing. Without it the
            // leading `\s*,?\s*` matches nothing and `and` matches *inside* the
            // preceding word, so "when I land remind me to text mom" was titled
            // "When I l" and "call my husband remind me at 6" became "Call my
            // husb". Every word ending -and or -but was affected: band, stand,
            // island, errand, demand, grand, husband, debut.
            of: #"(?i)\s*,?\s*\b(?:but|and)\b\s+(?:please\s+)?(?:remind\s+me|send\s+me\s+a\s+reminder)\b.*$"#,
            options: .regularExpression
        ), reminderClause.lowerBound != original.startIndex {
            let statement = withoutTrailingTiming(
                normalized(String(original[..<reminderClause.lowerBound]))
            ).trimmingCharacters(in: CharacterSet(charactersIn: ",.!?"))
            if !statement.isEmpty {
                return sentenceCased(statement)
            }
        }

        // A place condition can sit in front of the reminder command. Strip
        // both pieces so the title is the shopping/action content rather than
        // the full "When I get to Costco…" sentence.
        if let locationAction = LocationIntentParser.actionBody(in: original) {
            return sentenceCased(locationAction)
        }

        // "Remind Alex to get the wrench in 20 minutes" keeps its command:
        // the owner's action *is* the reminding, so stripping through "to"
        // would retitle Alex's errand as the owner's. Only the trailing
        // timing comes off — the reminder date already holds it.
        if ReminderPhrasing.isDelegated(original) {
            let kept = withoutTrailingTiming(original)
                .trimmingCharacters(in: CharacterSet(charactersIn: ",.!?"))
            if !kept.isEmpty { return sentenceCased(kept) }
        }

        // Both the verb form ("remind me to …") and the noun form ("give me a
        // reminder to …") are requests for a reminder, so both must be stripped
        // before the row title and notification body are built.
        let commandPattern = #"(?i)(?:"# + ReminderPhrasing.sentenceLead
            + #"|^(?:please\s+)?(?:set\s+(?:an?\s+)?(?:alarm|timer)|start\s+(?:an?\s+)?timer|wake\s+me(?:\s+up)?)\b)"#
        guard original.range(of: commandPattern, options: .regularExpression) != nil else {
            return sentenceCased(original)
        }

        var candidate: String

        // A prohibition. English lets the negator sit on either side of the
        // infinitival `to` — "remind me **not to** eat before the blood test"
        // and "remind me **to not** eat before the blood test" are the same
        // sentence, and both negate the complement VP.
        //
        // The connector search below takes everything after the first `to `,
        // so the first form put the negator *in front of* the cut and threw it
        // away: the row read "Eat before the blood test" and a notification
        // fired telling the person to do the thing they asked to be warned
        // against. The second form kept it and read "Not eat before …". One
        // meaning, two renderings, neither of them right.
        //
        // Both are normalised here, before the cut, so the negation survives
        // as a negation rather than as a stray token. Only a negator *adjacent
        // to the connector* counts — "remind me to bring the form not the
        // copy" negates a noun phrase, not the verb, and must not be touched.
        let isProhibitive = ReminderPhrasing.isProhibitive(original)

        // "Remind me that I have a meeting at 4:15" is a reminder *about the
        // meeting*. Without this the row was titled "I have a meeting", which
        // names the speaker's possession of it rather than the thing itself.
        //
        // The complementizer is optional in speech — "remind me I have a
        // meeting at 4:15" is the same sentence — so the elided form is matched
        // too. It is anchored to the reminder command rather than left floating
        // like the `that` form, because a bare "I have" can sit inside a
        // perfectly ordinary reminder: "remind me to tell Bob I have the keys"
        // is about telling Bob, and an unanchored match would retitle it "The
        // keys".
        if let haveConnector = original.range(
            of: #"(?i)(?:\bthat\s+|\b(?:remind|notify|alert)\s+me\s+)(?:i|we)\s+(?:have|['’]ve\s+got|got)\s+(?:an?\s+|the\s+|my\s+)?"#,
            options: .regularExpression
        ) {
            candidate = String(original[haveConnector.upperBound...])
        } else if let actionConnector = original.range(
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

        candidate = withoutTrailingTiming(candidate)

        // A trailing place trigger is machinery the same way trailing timing
        // is: "buy cereal when I get to Costco" is about the cereal, and the
        // place already lives on the item's location intent (or names its
        // shopping list). Only stripped when the sentence parses as a real
        // place trigger, so an ordinary "when" clause is never cut.
        if LocationIntentParser.parse(original) != nil {
            let withoutPlace = candidate.replacingOccurrences(
                of: ##"(?i)\s*,?\s+(?:when|whenever|once|as\s+soon\s+as|next\s+time|every\s+time)\s+(?:i|we)\b[^,;.!?]*$"##,
                with: "",
                options: .regularExpression
            )
            if !normalized(withoutPlace).isEmpty { candidate = withoutPlace }
        }

        // If no “to/about” connector was spoken, remove a leading interval.
        candidate = candidate.replacingOccurrences(
            of: #"(?i)^\s*(?:in\s+(?:\d+|[a-z]+(?:[\s-][a-z]+)?)\s+(?:seconds?|minutes?|hours?|days?|weeks?)|today|tonight|tomorrow|at\s+\S+)\s*[:,.-]?\s*"#,
            with: "",
            options: .regularExpression
        )
        candidate = candidate.replacingOccurrences(
            of: #"(?i)^\s*(?:that\s+|to\s+|about\s+|for\s+|at\s+)"#,
            with: "",
            options: .regularExpression
        )
        candidate = normalized(candidate).trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))

        // Render the prohibition the way English renders a negative imperative.
        // The negator is the person's own; only the auxiliary is supplied, and
        // it is supplied because "Not eat before the blood test" is not a
        // sentence. The untouched wording stays in the capture either way.
        if isProhibitive {
            // The connector cut may have left the negator behind at the front
            // ("to not eat …" → "not eat …"); drop it so it is not said twice.
            candidate = candidate.replacingOccurrences(
                of: #"(?i)^(?:not|never)\s+"#,
                with: "",
                options: .regularExpression
            )
            candidate = normalized(candidate)
            if !candidate.isEmpty {
                return "Don't " + candidate.prefix(1).lowercased() + candidate.dropFirst()
            }
        }

        // "Wake me up at ten to nine" has no action beyond the waking — the
        // "to" inside the spoken clock is not a connector, and titling the row
        // with the leftover "nine" told the person nothing. When everything
        // after the command is just the time, the command itself is the title.
        let clockShape = #"(?i)^(?:\d{1,2}(?::\d{2})?|noon|midnight"#
            + #"|(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"#
            + #"(?:\s+(?:o'?\s?clock|thirty|forty(?:[\s-]five)?|fifteen|twenty(?:[\s-]five)?|ten|five))?)"#
            + #"(?:\s*(?:a\.?m\.?|p\.?m\.?))?$"#
        if candidate.isEmpty || candidate.range(of: clockShape, options: .regularExpression) != nil {
            if original.range(of: #"(?i)\bwake\s+me\b"#, options: .regularExpression) != nil {
                return "Wake up"
            }
            if original.range(of: #"(?i)\balarm\b"#, options: .regularExpression) != nil {
                return "Alarm"
            }
            if original.range(of: #"(?i)\btimer\b"#, options: .regularExpression) != nil {
                return "Timer"
            }
            return "Your reminder"
        }

        return sentenceCased(candidate)
    }

    /// Removes timing language after the action, as in "remind me to call Mum
    /// in ten minutes" or "…tomorrow at six". Shared with the shopping-list
    /// splitter, which must not read "in one hour" as part of a product.
    static func withoutTrailingTiming(_ value: String) -> String {
        let trailingTimingPatterns = [
            #"(?i)\s+in\s+(?:\d+|[a-z]+(?:[\s-][a-z]+)?)\s+(?:seconds?|minutes?|hours?|days?|weeks?)\s*[.!?]*$"#,
            #"(?i)\s+(?:today|tonight|tomorrow)(?:\s+at\s+(?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve))?\s*[.!?]*$"#,
            #"(?i)\s+at\s+(?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s*[.!?]*$"#
        ]
        var result = value
        for pattern in trailingTimingPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return result
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

/// The external systems a reminder actually lives in, behind a substitutable
/// seam.
///
/// Cancellation became a user-facing feature the moment "cancel my dentist
/// reminder" started working, and a passing `delete(_:)` test only proves the
/// SwiftData row went away. What a person actually notices is whether the
/// notification still fires and whether the alarm still goes off, so those two
/// effects need to be observable in a test.
///
/// Production uses `.live`, which is the same `UNUserNotificationCenter` and
/// `AlarmManager` work as before. Tests substitute a recorder and assert on
/// exact identifiers.
///
/// Deliberately **not** `@MainActor`. It holds no main-actor state — both
/// `UNUserNotificationCenter.current()` and `AlarmManager.shared` are their own
/// thread-safe singletons — and isolating it only meant `live` could not be
/// read from the nonisolated `delivery` property below. That mismatch is a
/// warning today and an error under the Swift 6 language mode, on the one code
/// path that tears a reminder down; leaving it in place would mean the next
/// toolchain bump breaks reminder cancellation at compile time.
struct ReminderDeliverySink: Sendable {
    var removeNotifications: @Sendable ([String]) -> Void
    var cancelAlarm: @Sendable (UUID) -> Void
    /// What is currently armed. Reconciliation is defined as "remove everything
    /// pending that no live row asks for", so the pending set has to be readable
    /// through the same seam that the removals go through — otherwise a test can
    /// only observe teardown that was already targeted by id, which is the half
    /// that was never in doubt.
    var pendingIdentifiers: @Sendable () async -> [String]

    static let live = ReminderDeliverySink(
        removeNotifications: { identifiers in
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        },
        cancelAlarm: { itemID in
            if #available(iOS 26.0, *) {
                // `cancel` removes a *scheduled* alarm; one already alerting —
                // or snoozing in its countdown — is only silenced by `stop`.
                // Completing an item must shut its alarm down in every state,
                // so both are issued; each throws harmlessly in the state the
                // other one owns.
                try? AlarmManager.shared.stop(id: itemID)
                try? AlarmManager.shared.cancel(id: itemID)
            }
        },
        pendingIdentifiers: {
            await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
        }
    )
}

enum ReminderScheduler {
    /// Swapped by tests to observe teardown. Never reassigned in production.
    nonisolated(unsafe) static var delivery: ReminderDeliverySink = .live

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

        /// The one named list every request belongs to, or `nil` when the
        /// group mixes lists or contains anything that is not a list row.
        private var sharedListName: String? {
            guard let name = requests.first?.listName else { return nil }
            return requests.allSatisfy { $0.listName == name } ? name : nil
        }

        /// A list's alert is titled by the list — "Sobeys" — because that is
        /// how the person spoke it: the store, then what to get there.
        var title: String {
            if let sharedListName { return sharedListName }
            return requests.count == 1 ? "Reminder" : "\(requests.count) reminders"
        }

        var body: String {
            // Spoken order, not identifier order: the identifier sort keeps
            // the notification stable across launches, but the person said
            // "chicken, eggs and milk" and the alert should read it back.
            let spoken = requests.sorted { $0.createdAt < $1.createdAt }
            if sharedListName != nil {
                let names = spoken.prefix(3).map { Self.productName(from: $0.title) }
                let joined = names.joined(separator: " · ")
                return requests.count > 3 ? "\(joined) · +\(requests.count - 3) more" : joined
            }
            guard requests.count > 1 else { return requests[0].title }
            let titles = spoken.prefix(3).map(\.title).joined(separator: " · ")
            return requests.count > 3 ? "\(titles) · +\(requests.count - 3) more" : titles
        }

        var itemIDs: [UUID] { requests.map(\.itemID) }

        /// "Get chicken" → "Chicken". Under a list title the verb is noise;
        /// the row keeps its own full title everywhere else.
        private static func productName(from title: String) -> String {
            let stripped = title.replacingOccurrences(
                of: #"^(?:buy|get|grab|order|pick\s+up)\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            guard let first = stripped.first else { return title }
            return first.uppercased() + stripped.dropFirst()
        }
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
        delivery.removeNotifications([notificationIdentifier(for: itemID)])
        delivery.cancelAlarm(itemID)
    }

    static func cancel(captureSessionID: UUID) {
        Task {
            let prefix = notificationGroupPrefix(for: captureSessionID)
            let identifiers = await delivery.pendingIdentifiers()
                .filter { $0.hasPrefix(prefix) }
            delivery.removeNotifications(identifiers)
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

        case let .time(date, _, _):
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
        if secondsUntilFire > 60,
           group.requests.count == 1,
           let repeatingComponents = group.requests[0].repeatingComponents,
           let repeatingNextFire = UNCalendarNotificationTrigger(
               dateMatching: repeatingComponents, repeats: true
           ).nextTriggerDate(),
           abs(repeatingNextFire.timeIntervalSince(group.fireDate)) < 60 {
            // A recurring reminder that only ever schedules its next single
            // occurrence stops firing the moment the person misses one — see
            // FINAL_RELEASE_AUDIT.md H-1/E-1. Handing iOS the recurring
            // components instead means the series keeps firing on its own
            // schedule even if the app never runs again to regenerate it; the
            // next `CapturedItem` occurrence, once the app does process a
            // completion, gets its own such trigger and this one is cancelled
            // the normal way `setCompleted` already cancels any reminder.
            //
            // Only when the repeating match's first fire IS this occurrence,
            // though. A repeating hour/minute trigger fires every period from
            // now, so an occurrence further out — a future-dated series, or a
            // DST-shifted fire time the components no longer describe — would
            // alert on the wrong days. Those schedule as an exact one-shot and
            // rejoin the resilient path on the next generated occurrence.
            trigger = UNCalendarNotificationTrigger(dateMatching: repeatingComponents, repeats: true)
        } else if secondsUntilFire <= 60 {
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
        let identifiers = notificationIdentifiersToRemove(
            from: await delivery.pendingIdentifiers(),
            scope: scope
        )
        guard !identifiers.isEmpty else { return }
        delivery.removeNotifications(identifiers)
    }

    /// Internal rather than private so tests can assert that the *exact*
    /// pending request for an item is what gets removed.
    static func notificationIdentifier(for itemID: UUID) -> String {
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
