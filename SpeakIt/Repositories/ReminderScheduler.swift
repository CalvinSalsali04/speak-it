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
    /// The series' own repeating trigger, armed *beside* this request's fire
    /// when a snooze has displaced it, or *instead of* it once that fire has
    /// passed (see `forScheduling`). `nil` for everything else.
    ///
    /// A snoozed occurrence cannot use `repeatingComponents` for its own fire:
    /// the snooze is not the series' time. Arming only the one-shot left
    /// nothing armed for the series once the snooze fired, until the app next
    /// ran, which is a missed reminder for anyone who snoozes and does not
    /// open Speak It. So a displaced occurrence gets two notifications: the
    /// one-shot at the snooze, and this repeating match under
    /// `ReminderScheduler.seriesNotificationIdentifier(for:)`.
    let seriesContinuation: SeriesContinuation?
    /// True when this request's own fire had already passed when it was built,
    /// so it arms `seriesContinuation` and nothing else. Only `forScheduling`
    /// builds one.
    let continuesSeriesOnly: Bool
    /// The series an AlarmKit alarm can repeat on its own, or `nil` for a
    /// rule AlarmKit cannot express. Wider than `repeatingComponents`,
    /// because one relative alarm takes a set of weekdays where one
    /// notification trigger takes a single match: "every weekday at 6:30" is
    /// one repeating alarm but not one repeating notification. See
    /// `alarmRepetition(rule:fireDate:calendar:)`.
    let alarmRepetition: ReminderAlarmRepetition?
    /// Where the series put the occurrence a snooze displaced, for an alarm
    /// AlarmKit repeats (`alarmRepetition`); `nil` when nothing is displaced.
    /// While it is set, the series stays armed under the item ID and the
    /// snoozed occurrence rings once under `ReminderScheduler.snoozeAlarmID(for:)`.
    let displacedAlarmOccurrence: Date?
    /// The named list a shopping row belongs to ("Sobeys"), or `nil` for
    /// everything else. A coalesced notification whose rows all share one
    /// list is titled by that list, so the alert reads the way the person
    /// spoke it: the store, then what to get there.
    let listName: String?
    /// When the item was created. A coalesced notification lists its rows in
    /// spoken order, which creation order preserves; the identifier's own
    /// ordering stays keyed by item ID so it remains stable across launches.
    let createdAt: Date

    /// A request for an alert still ahead, or `nil` once it has fired, except
    /// for an alarm AlarmKit repeats, whose next ring is still ahead (see
    /// `nextRingOfFiredAlarm`).
    ///
    /// This is the definition of "still ahead", and nothing more. No
    /// production code calls it. Every scheduling pass, and Today's pending
    /// reminders, use `forScheduling`, which also keeps an alerted series
    /// armed. It stays because `forScheduling` is described against it, the
    /// distinction is worth a name, and tests assert on it.
    @MainActor
    init?(item: CapturedItem) {
        self.init(item: item, now: .now, continuingPastFire: false)
    }

    /// The request a scheduling pass arms for an item.
    ///
    /// The same request as `init?(item:)` while the alert is ahead. Once it has
    /// fired, `init?(item:)` returns `nil`, and any pass that included the item
    /// in its scope removed its triggers and re-added nothing. That covered a
    /// native repeating series whose alert had fired (DEL-12), and a snoozed
    /// series whose one-shot had fired, whose repeating trigger was then
    /// removed with it. For a series iOS can repeat, this returns a request
    /// whose own fire has passed and which arms only `seriesContinuation`, the
    /// series' repeating trigger, until the app rolls the row forward.
    @MainActor
    static func forScheduling(_ item: CapturedItem, now: Date = .now) -> ReminderScheduleRequest? {
        ReminderScheduleRequest(item: item, now: now, continuingPastFire: true)
    }

    @MainActor
    private init?(item: CapturedItem, now: Date, continuingPastFire: Bool) {
        guard let storedFireDate = item.reminderDate else { return nil }
        // The series' own alert, not a snoozed one. Taken from a snoozed fire
        // date, the repeating match's first fire *was* the snoozed occurrence,
        // so iOS was handed "every Monday at 9:10" for a series asked for at 9.
        // From the series' alert, the match no longer describes this one fire,
        // which is then armed as an exact one-shot, and the series' repeating
        // match is armed beside it as `seriesContinuation`.
        let seriesFireDate = item.seriesReminderDate ?? storedFireDate
        let seriesComponents = Self.repeatingComponents(
            rule: item.temporalIntent?.recurrence,
            fireDate: seriesFireDate
        )
        // The series' own alert, like `seriesComponents` above, never a
        // snoozed one. Read from a snoozed fire date, the repetition's first
        // ring is the snooze itself, so `alarmSchedule` would hand AlarmKit a
        // repeating "every Monday at 9:10" for a series asked for at 9. Read
        // from the series' alert, its first ring is not this fire, and the
        // snoozed occurrence stays a `.fixed` one-shot at the snooze.
        let repetition = Self.alarmRepetition(
            rule: item.temporalIntent?.recurrence,
            fireDate: seriesFireDate
        )
        // F2: a relative alarm is still scheduled for its next match after it
        // rings, so a fired occurrence of a series AlarmKit repeats is not spent.
        // Its request is for that next ring, the alarm AlarmKit already holds.
        let storedFireHasPassed = storedFireDate <= now
        let nextRing: Date? = storedFireHasPassed && repetition != nil
            ? Self.nextRingOfFiredAlarm(
                delivery: ItemPresentation.scheduledDelivery(for: item),
                repetition: repetition,
                continuedBySuccessor: RecurrenceStore.generatedNextItemID(for: item.id) != nil,
                now: now
            )
            : nil
        let fireDate = nextRing ?? storedFireDate
        let fireHasPassed = storedFireHasPassed && nextRing == nil
        if fireHasPassed {
            guard continuingPastFire, seriesComponents != nil else { return nil }
        }
        // A snooze moved this occurrence off the series' alert, and it has not
        // rung yet. A request rolled to its next ring is displaced by nothing.
        let displaced = nextRing == nil && seriesFireDate != storedFireDate
        // The same function the row's bell reads, so what a row says is armed
        // and what iOS is handed cannot disagree. It is memoized underneath:
        // Today rebuilds these requests on every render pass to keep its
        // scheduling signature live, which made two fresh `ThoughtOrganizer`
        // parses per reminder item here the single largest cost of scrolling
        // that screen.
        //
        // `.none` with a `reminderDate` present means the system is holding
        // the row for review (`ItemPresentation.mayArmTime`), so no request is
        // made. This is the only gate between a held row and iOS: every
        // builder (foreground reconcile, per-session sync, the all-reminders
        // sync, Siri, and Today's permission card) goes through this init.
        // It also covers a clock beside a place the person has not chosen
        // between (`CapturedItem.awaitsPlaceOrTimeChoice`, read by `mayArmTime`),
        // so such a row neither rings at its stored clock nor shows a bell.
        let scheduledDelivery = ItemPresentation.scheduledDelivery(for: item)
        guard scheduledDelivery != .none else { return nil }
        let originalText = item.originalTextSegment

        itemID = item.id
        captureSessionID = item.captureSession?.id
        title = ReminderCopy.action(
            from: item.displayTitle == originalText ? originalText : item.displayTitle
        )
        self.fireDate = fireDate
        delivery = scheduledDelivery
        repeatingComponents = seriesComponents
        continuesSeriesOnly = fireHasPassed
        seriesContinuation = fireHasPassed || displaced
            ? seriesComponents.map {
                SeriesContinuation(occurrenceFireDate: seriesFireDate, components: $0)
            }
            : nil
        alarmRepetition = repetition
        // F1: see `ReminderScheduler.alarmSchedule(for:now:calendar:)`.
        displacedAlarmOccurrence = displaced && repetition != nil ? seriesFireDate : nil
        listName = item.itemType == .shopping
            ? ShoppingGroupStore.group(for: item.id)
            : nil
        createdAt = item.createdAt
    }

    /// What a displaced occurrence needs to keep its series armed.
    struct SeriesContinuation: Hashable, Sendable {
        /// Where the series put this occurrence's alert before the snooze.
        let occurrenceFireDate: Date
        /// The series' repeating match, from `occurrenceFireDate`.
        let components: DateComponents
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

    /// The part of a recurrence rule an AlarmKit relative schedule can carry.
    ///
    /// `Alarm.Schedule.Relative` is an hour and a minute on the device's
    /// current clock, plus `Recurrence.never` or `.weekly([Locale.Weekday])`.
    /// That is every series whose occurrences are "this time of day, on these
    /// days of the week, every week":
    ///
    /// - daily, every day → all seven weekdays;
    /// - weekly on named days ("every Monday", "every weekday", "every
    ///   weekend") → those days;
    /// - weekly with no day named ("every week") → the fire date's weekday,
    ///   which is where `RecurrenceRule.nextDate` puts every later occurrence.
    ///
    /// Everything else returns `nil` and stays a one-shot `.fixed` alarm that
    /// the foreground self-healing pass re-arms: an `interval` above 1 ("every
    /// other Tuesday", "every 2 days"), monthly and yearly rules, ordinal
    /// weekdays ("the first Monday every month"), elapsed-time rules ("every 3
    /// hours"), and completion-anchored rules, whose next date does not exist
    /// until the person completes this one.
    static func alarmRepetition(
        rule: RecurrenceRule?,
        fireDate: Date,
        calendar: Calendar = .current
    ) -> ReminderAlarmRepetition? {
        guard let rule,
              rule.anchor == .scheduledDate,
              rule.interval == 1,
              !rule.repeatsByElapsedTime,
              rule.ordinalWeekday == nil else { return nil }

        let clock = calendar.dateComponents([.hour, .minute, .weekday], from: fireDate)
        guard let hour = clock.hour, let minute = clock.minute else { return nil }

        let weekdayNumbers: [Int]
        switch rule.frequency {
        case .daily:
            weekdayNumbers = Array(1...7)
        case .weekly:
            if !rule.weekdays.isEmpty {
                weekdayNumbers = rule.weekdays
            } else if let weekday = clock.weekday {
                weekdayNumbers = [weekday]
            } else {
                return nil
            }
        case .monthly, .yearly:
            return nil
        }

        let weekdays = weekdayNumbers.compactMap(ReminderAlarmRepetition.weekday(number:))
        guard !weekdays.isEmpty, weekdays.count == weekdayNumbers.count else { return nil }
        return ReminderAlarmRepetition(
            hour: hour,
            minute: minute,
            weekdayNumbers: weekdayNumbers,
            weekdays: weekdays
        )
    }

    /// When a recurring alarm whose stored occurrence has already rung rings
    /// next, or `nil` when that occurrence was the row's last alert.
    ///
    /// A one-shot alarm is spent once it rings, and so is a notification this
    /// branch does not reach. A relative AlarmKit alarm is not: it stays
    /// scheduled for its next weekday match, so the row it belongs to is still
    /// armed until the foreground pass (`advanceOverdueRecurrences`) rolls it
    /// forward. Its request is built for that match, which is the alarm
    /// AlarmKit already holds, so a pass that cancels and re-arms the row
    /// re-arms the same repetition instead of leaving nothing.
    ///
    /// Not when the series has moved on to a successor row
    /// (`continuedBySuccessor`, a `RecurrenceStore` link): that row owns the
    /// next occurrence under its own alarm ID, and arming this one as well
    /// would ring twice. The same answer holds if the fired alarm was a
    /// `.fixed` one-shot, because the series' next occurrence is still this
    /// match; re-arming it is what the foreground pass would do.
    static func nextRingOfFiredAlarm(
        delivery: ReminderDelivery,
        repetition: ReminderAlarmRepetition?,
        continuedBySuccessor: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard delivery == .alarm,
              let repetition,
              !continuedBySuccessor else { return nil }
        return repetition.nextOccurrence(after: now, calendar: calendar)
    }
}

/// "This time of day, on these days of the week, every week": the only kind of
/// series an AlarmKit alarm repeats by itself. Holds no AlarmKit type, so the
/// decision can be made and tested on any OS.
struct ReminderAlarmRepetition: Hashable, Sendable {
    let hour: Int
    let minute: Int
    /// `Calendar` weekday numbers, 1 being Sunday, in the rule's order.
    let weekdayNumbers: [Int]
    /// The same days in the type `Alarm.Schedule.Relative.Recurrence.weekly`
    /// takes.
    let weekdays: [Locale.Weekday]

    /// `Calendar`'s weekday numbering, where 1 is Sunday, to `Locale.Weekday`.
    /// Fixed by Gregorian numbering, not by the locale's first day of the week.
    static func weekday(number: Int) -> Locale.Weekday? {
        switch number {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }

    /// The first instant after `now` this repetition rings at, read in
    /// `calendar`.
    func nextOccurrence(after now: Date, calendar: Calendar) -> Date? {
        weekdayNumbers.compactMap { weekday in
            calendar.nextDate(
                after: now,
                matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday),
                matchingPolicy: .nextTime,
                direction: .forward
            )
        }.min()
    }
}

/// What `ReminderScheduler` asks AlarmKit to ring: `.fixed(date)` once, or a
/// relative schedule that repeats weekly on `weekdays` with no app run in
/// between.
enum ReminderAlarmSchedule: Equatable, Sendable {
    case fixed(Date)
    case weekly(hour: Int, minute: Int, weekdays: [Locale.Weekday])
}

/// One notification the scheduler will add, decided before anything touches
/// `UNUserNotificationCenter`, so what is armed can be tested as a value.
struct PlannedReminderNotification: Equatable {
    enum Trigger: Equatable {
        /// A calendar match iOS re-fires on its own.
        case repeating(DateComponents)
        /// A countdown, for a fire less than a minute away.
        case afterInterval(TimeInterval)
        /// One exact wall-clock moment, pinned to the zone it was set in.
        case exact(DateComponents)

        var notificationTrigger: UNNotificationTrigger {
            switch self {
            case let .repeating(components):
                return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            case let .afterInterval(seconds):
                return UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            case let .exact(components):
                return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            }
        }
    }

    let identifier: String
    let itemIDs: [UUID]
    let trigger: Trigger
}

struct ReminderSynchronizationScope: Equatable, Sendable {
    var itemIDs: Set<UUID>
    var captureSessionIDs: Set<UUID>
    var replacesAllSpeakItReminders: Bool
    /// Items whose AlarmKit alarms this pass neither stops, cancels nor
    /// re-arms, under the item ID or the snooze ID. Their notifications are
    /// still removed and re-added like any other item's. Only the foreground
    /// reconcile sets it, to the rows whose alarm may be ringing
    /// (`ReminderScheduler.alarmMayBeAlerting`, DEL-23).
    var alarmsLeftAlone: Set<UUID>

    init(
        itemIDs: Set<UUID> = [],
        captureSessionIDs: Set<UUID> = [],
        replacesAllSpeakItReminders: Bool = false,
        alarmsLeftAlone: Set<UUID> = []
    ) {
        self.itemIDs = itemIDs
        self.captureSessionIDs = captureSessionIDs
        self.replacesAllSpeakItReminders = replacesAllSpeakItReminders
        self.alarmsLeftAlone = alarmsLeftAlone
    }

    init(requests: [ReminderScheduleRequest]) {
        itemIDs = Set(requests.map(\.itemID))
        captureSessionIDs = Set(requests.compactMap(\.captureSessionID))
        replacesAllSpeakItReminders = false
        alarmsLeftAlone = []
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
    /// The AlarmKit alarms still waiting to ring. The alarm half of
    /// `pendingIdentifiers`: without it, an alarm could only ever be cancelled
    /// by an item ID somebody already held, so an alarm whose row was removed
    /// by iCloud, or by a kill between `delete`'s save and its teardown, was
    /// never cancelled by anyone. Only the `.scheduled` state is reported; an
    /// alarm that is already alerting is in front of the person, who can stop
    /// it. Defaults to none, so a test double that does not model alarms can
    /// never make the orphan sweep cancel one.
    var scheduledAlarmIDs: @Sendable () async -> [UUID] = { return [] }

    static let live = ReminderDeliverySink(
        removeNotifications: { identifiers in
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        },
        cancelAlarm: { itemID in
            if #available(iOS 26.0, *) {
                // `cancel` removes an alarm that is not alerting; one already
                // alerting is only silenced by `stop`. (Speak It's alarms carry
                // no countdown presentation, so they never enter `.countdown`
                // or `.paused`; if one ever does, `cancel` covers it.)
                // Completing an item must shut its alarm down in every state,
                // so both are issued; each throws harmlessly in the state the
                // other one owns.
                try? AlarmManager.shared.stop(id: itemID)
                try? AlarmManager.shared.cancel(id: itemID)
            }
        },
        pendingIdentifiers: {
            await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
        },
        scheduledAlarmIDs: {
            // Listing arrived with AlarmKit itself, so there is no OS on which
            // Speak It can hold an alarm it cannot read back. Below iOS 26 the
            // alarm path falls back to a `SpeakIt.reminder.` notification,
            // which the prefix sweep already heals.
            guard #available(iOS 26.0, *) else { return [] }
            // `alarms` lists only this app's alarms. It throws when the daemon
            // cannot answer, and an unreadable list must mean "cancel
            // nothing", never "every alarm is an orphan".
            guard let alarms = try? AlarmManager.shared.alarms else { return [] }
            // Every state but `.alerting`: an alerting alarm is in front of
            // the person, while a scheduled, counting-down or paused orphan
            // will still alert and nobody can reach it but this sweep.
            return alarms.filter { $0.state != .alerting }.map(\.id)
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
        removeNotifications(for: itemID)
        delivery.cancelAlarm(itemID)
        delivery.cancelAlarm(snoozeAlarmID(for: itemID))
    }

    /// The notification half of `cancel(itemID:)`, for an item whose alarm a
    /// pass leaves alone (`ReminderSynchronizationScope.alarmsLeftAlone`).
    private static func removeNotifications(for itemID: UUID) {
        delivery.removeNotifications([
            notificationIdentifier(for: itemID),
            seriesNotificationIdentifier(for: itemID)
        ])
    }

    /// How long after a ring the foreground reconcile treats that row's alarm
    /// as possibly still alerting. A guess: nothing here knows how long an
    /// unattended AlarmKit alarm alerts, and device check D17 measures it.
    /// Longer only delays the re-arm or cancel of a row that has just rung,
    /// until the first reconcile after the window.
    static let alertingWindow: TimeInterval = 30 * 60

    /// Whether this row's AlarmKit alarm may be ringing at `now`, read from
    /// the row alone (DEL-23).
    ///
    /// Every reconcile used to stop and cancel every row's alarm, under the
    /// item ID and the snooze ID, before re-arming the rows still ahead. So
    /// opening the app while an alarm rang silenced it: a one-shot whose fire
    /// had just passed (no request, never put back), a snoozed occurrence
    /// under its snooze ID (the series is re-armed, the snooze is not), and a
    /// repeating series (re-armed for its next ring, today's silenced).
    ///
    /// It asks nothing of AlarmKit. A ring is the row's stored fire, which is
    /// the snooze for a snoozed occurrence, or a match of a series AlarmKit
    /// repeats, from the series' own alert on, since a relative alarm rings
    /// whether or not the app ran. Either within `alertingWindow` before
    /// `now`. Read before `advanceOverdueRecurrences` rolls a rung series
    /// forward, which erases the ring from the row.
    ///
    /// Only for a row that arms an alarm: a completed, archived, held or
    /// disarmed row, or one delivered as a notification, answers `false` and
    /// is cancelled as before, and so is a row that is gone (the orphan
    /// sweep).
    @MainActor
    static func alarmMayBeAlerting(_ item: CapturedItem, now: Date) -> Bool {
        guard !item.isArchived, !item.isCompleted else { return false }
        let seriesFireDate = item.seriesReminderDate
        return alarmMayBeAlerting(
            delivery: ItemPresentation.scheduledDelivery(for: item),
            fireDate: item.reminderDate,
            seriesFireDate: seriesFireDate,
            repetition: seriesFireDate.flatMap {
                ReminderScheduleRequest.alarmRepetition(
                    rule: item.temporalIntent?.recurrence,
                    fireDate: $0
                )
            },
            now: now
        )
    }

    /// The decision behind `alarmMayBeAlerting(_:now:)`, with no store in it.
    static func alarmMayBeAlerting(
        delivery: ReminderDelivery,
        fireDate: Date?,
        seriesFireDate: Date?,
        repetition: ReminderAlarmRepetition?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard delivery == .alarm, let fireDate else { return false }
        let windowStart = now.addingTimeInterval(-alertingWindow)
        if fireDate > windowStart, fireDate <= now { return true }
        guard let repetition,
              let seriesFireDate,
              let ring = repetition.nextOccurrence(after: windowStart, calendar: calendar)
        else { return false }
        return ring >= seriesFireDate && ring <= now
    }

    /// The AlarmKit ID of a snoozed occurrence's one-shot, which rings beside
    /// the series alarm kept under the item ID. Derived from the item ID alone
    /// (every bit of the last byte flipped), so `cancel(itemID:)` reaches it
    /// and the orphan sweep maps it back to its row. It is its own inverse.
    static func snoozeAlarmID(for itemID: UUID) -> UUID {
        var bytes = itemID.uuid
        bytes.15 ^= 0xFF
        return UUID(uuid: bytes)
    }

    /// Cancels every scheduled alarm that no row in the store accounts for,
    /// after every scheduling pass already queued has finished.
    ///
    /// Notifications are healed by the `replacesAllSpeakItReminders` prefix
    /// sweep, which removes whatever it finds. Alarms had no such sweep: they
    /// were only cancelled by an item ID in some scope, and a row that is gone
    /// is in no scope. The AlarmKit ID of a reminder alarm is its item ID, or
    /// its snooze ID (`snoozeAlarmID(for:)`), which its row accounts for, and
    /// `schedule` is the only place Speak It creates an AlarmKit alarm, so an
    /// alarm whose ID names no row belongs to a reminder that no longer exists.
    ///
    /// `accountedFor` is read on the main actor *after* the alarm list, not
    /// captured when the pass was queued. A row saved before the read protects
    /// its alarm even if it was created while this pass waited in the tail,
    /// and an alarm listed before the read cannot belong to a row saved after
    /// it, because rows are saved before they are scheduled. `nil` means the
    /// rows could not be read, and cancels nothing.
    static func cancelOrphanedAlarms(
        accountedFor: @escaping @MainActor @Sendable () -> Set<UUID>?
    ) {
        let predecessor = synchronizationTail
        synchronizationTail = Task {
            await predecessor?.value
            let scheduled = await delivery.scheduledAlarmIDs()
            guard !scheduled.isEmpty,
                  let rowIDs = await accountedFor() else { return }
            for alarmID in orphanedAlarmIDs(scheduled: scheduled, accountedFor: rowIDs) {
                delivery.cancelAlarm(alarmID)
            }
        }
    }

    /// The decision behind `cancelOrphanedAlarms`, with no AlarmKit and no
    /// store in it: every scheduled alarm ID that is not one of `accountedFor`,
    /// in the order AlarmKit listed them. A snoozed occurrence's alarm is
    /// accounted for by its row, through `snoozeAlarmID(for:)`.
    static func orphanedAlarmIDs(
        scheduled: [UUID],
        accountedFor: Set<UUID>
    ) -> [UUID] {
        scheduled.filter {
            !accountedFor.contains($0) && !accountedFor.contains(snoozeAlarmID(for: $0))
        }
    }

    /// The AlarmKit schedule under the item ID, decided with no AlarmKit in
    /// it. For a snoozed occurrence of a series AlarmKit repeats, that is the
    /// series itself (`snoozedSeriesSchedule`); otherwise see
    /// `alarmSchedule(repeating:fireDate:now:calendar:)`.
    static func alarmSchedule(
        for request: ReminderScheduleRequest,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ReminderAlarmSchedule {
        if let series = snoozedSeriesSchedule(for: request, now: now, calendar: calendar) {
            return series
        }
        return alarmSchedule(
            repeating: request.alarmRepetition,
            fireDate: request.fireDate,
            now: now,
            calendar: calendar
        )
    }

    /// The series' own `.weekly` schedule for a snoozed occurrence, or `nil`.
    ///
    /// Snoozing used to replace the series with a `.fixed` one-shot at the
    /// snooze, so the next occurrence rang only if the app ran in between.
    /// Refused, leaving today's one-shot under the item ID, when the series'
    /// first ring would be the displaced occurrence itself (a snooze pressed
    /// before its alert; #129's `seriesContinuationTrigger` rule), or is a
    /// minute away or less (the `> 60` rule of `alarmSchedule(repeating:...)`).
    static func snoozedSeriesSchedule(
        for request: ReminderScheduleRequest,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ReminderAlarmSchedule? {
        guard let displaced = request.displacedAlarmOccurrence,
              let repetition = request.alarmRepetition,
              let firstRing = repetition.nextOccurrence(after: now, calendar: calendar),
              firstRing.timeIntervalSince(displaced) >= 60,
              firstRing.timeIntervalSince(now) > 60 else { return nil }
        return .weekly(
            hour: repetition.hour,
            minute: repetition.minute,
            weekdays: repetition.weekdays
        )
    }

    /// When the snoozed occurrence rings, once, under `snoozeAlarmID(for:)`:
    /// `request.fireDate` whenever the series is kept under the item ID, and
    /// `nil` otherwise (the item ID's own `.fixed` alarm is then the snooze).
    /// Pass the same `now` as to `alarmSchedule(for:now:calendar:)`: both
    /// read one decision, and two reads of the clock can straddle its 60 s
    /// boundary.
    static func snoozeAlarmFireDate(
        for request: ReminderScheduleRequest,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        snoozedSeriesSchedule(for: request, now: now, calendar: calendar) == nil
            ? nil
            : request.fireDate
    }

    /// The same decision from the rule a request is built from, so a test can
    /// reach it without a store.
    static func alarmSchedule(
        rule: RecurrenceRule?,
        fireDate: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ReminderAlarmSchedule {
        alarmSchedule(
            repeating: ReminderScheduleRequest.alarmRepetition(
                rule: rule,
                fireDate: fireDate,
                calendar: calendar
            ),
            fireDate: fireDate,
            now: now,
            calendar: calendar
        )
    }

    /// A repeating alarm when the series is one AlarmKit can repeat and its
    /// next ring *is* this occurrence; the one-shot `.fixed(fireDate)`
    /// otherwise.
    ///
    /// A one-shot alarm for a recurring item rang once and armed nothing for
    /// the next occurrence until the app ran again, so "wake me up every
    /// weekday at 6:30" missed Tuesday whenever Monday's alarm was the last
    /// thing that happened. A relative schedule rings again by itself.
    ///
    /// It rings from now on, though, not from `fireDate`, so it is used only
    /// when its first ring lands within a minute of `fireDate`, the same rule
    /// the repeating notification trigger follows. A series whose next
    /// occurrence is further out (created for next month, or rolled past a
    /// day by completing early) stays a one-shot, and rejoins the repeating
    /// path when the foreground pass re-arms its next occurrence.
    ///
    /// So does an occurrence a minute away or less, and the reason is not the
    /// race itself, which both branches share: the two branches lose it
    /// differently. A `.fixed` alarm whose moment passes while AlarmKit is
    /// still registering it just does not fire, and the foreground pass
    /// re-arms the series. A `.relative` one has no date to miss: it rings at
    /// the next match instead, tomorrow or next week, while the row still
    /// claims today, and nothing notices until the app next runs. The
    /// `> 60` clause keeps that failure on the `.fixed` side. Do not delete it
    /// on the grounds that `.fixed` is exposed to the same race.
    static func alarmSchedule(
        repeating repetition: ReminderAlarmRepetition?,
        fireDate: Date,
        now: Date,
        calendar: Calendar
    ) -> ReminderAlarmSchedule {
        guard let repetition,
              fireDate.timeIntervalSince(now) > 60,
              let firstRing = repetition.nextOccurrence(after: now, calendar: calendar),
              abs(firstRing.timeIntervalSince(fireDate)) < 60 else {
            return .fixed(fireDate)
        }
        return .weekly(
            hour: repetition.hour,
            minute: repetition.minute,
            weekdays: repetition.weekdays
        )
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

        case .blockedPlace, .heldPlace:
            // Unreachable in practice: a blocked or held place reminder
            // requires review and is handled above. Kept explicit so a future
            // change to the review rules cannot silently fall through to a
            // timing string.
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
        switch ItemPresentation.scheduledDelivery(for: item) {
        case .none: return "Timeline"
        case .alarm: return "Alarm"
        case .notification: return "Reminder"
        }
    }

    private static func schedule(
        _ request: ReminderScheduleRequest,
        requestAuthorizationIfNeeded: Bool,
        leavingAlarmAlone: Bool = false
    ) async -> ReminderSchedulingResult {
        guard request.fireDate > .now else {
            if leavingAlarmAlone {
                removeNotifications(for: request.itemID)
            } else {
                cancel(itemID: request.itemID)
            }
            return .failed
        }

        if leavingAlarmAlone {
            removeNotifications(for: request.itemID)
        } else {
            cancel(itemID: request.itemID)
        }

        if request.delivery == .alarm, #available(iOS 26.0, *) {
            let manager = AlarmManager.shared
            var authorization = manager.authorizationState
            if authorization == .notDetermined, requestAuthorizationIfNeeded {
                authorization = (try? await manager.requestAuthorization()) ?? .notDetermined
            }

            // DEL-23: the alarm AlarmKit holds for this row may be ringing,
            // and re-arming it starts with a stop. It is left as it is; the
            // first reconcile after `alertingWindow` re-arms it. `.scheduled`
            // here means "left as AlarmKit holds it", not "armed for this
            // request": a `.fixed` row rolled forward in place has nothing
            // armed for its next occurrence until then (KNOWN_ISSUES).
            if authorization == .authorized, leavingAlarmAlone {
                return .scheduled
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
                    // A series AlarmKit can repeat rings again by itself; see
                    // `alarmSchedule(repeating:fireDate:now:calendar:)`. The
                    // clock is read once: the series and its snooze are one
                    // decision, and two reads can straddle its 60 s boundary.
                    let now = Date.now
                    let alarmKitSchedule: Alarm.Schedule
                    switch alarmSchedule(for: request, now: now) {
                    case let .fixed(date):
                        alarmKitSchedule = .fixed(date)
                    case let .weekly(hour, minute, weekdays):
                        alarmKitSchedule = .relative(Alarm.Schedule.Relative(
                            time: Alarm.Schedule.Relative.Time(hour: hour, minute: minute),
                            repeats: .weekly(weekdays)
                        ))
                    }
                    let configuration = AlarmManager.AlarmConfiguration.alarm(
                        schedule: alarmKitSchedule,
                        attributes: attributes
                    )
                    // The alarm ID stays the item ID for a repeating alarm too:
                    // `cancel(itemID:)` and the orphan sweep both find an
                    // alarm by the row it belongs to; a snoozed occurrence
                    // rings under `snoozeAlarmID(for:)` beside it.
                    _ = try await manager.schedule(id: request.itemID, configuration: configuration)
                    if let snoozeFire = snoozeAlarmFireDate(for: request, now: now) {
                        do {
                            _ = try await manager.schedule(
                                id: snoozeAlarmID(for: request.itemID),
                                configuration: AlarmManager.AlarmConfiguration.alarm(
                                    schedule: .fixed(snoozeFire),
                                    attributes: attributes
                                )
                            )
                        } catch {
                            // Both or neither, as `addAllOrNone` does for the
                            // two notifications: the series alone would skip
                            // the ring the person snoozed. This holds only if
                            // the cancel succeeds (see DECISIONS, "not covered").
                            try? manager.cancel(id: request.itemID)
                            throw error
                        }
                    }
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

        let notifications = plannedNotifications(for: group, now: .now).map { planned -> UNNotificationRequest in
            let content = UNMutableNotificationContent()
            content.title = planned.group.title
            content.body = planned.group.body
            content.sound = .default
            content.threadIdentifier = "speak-it-reminders"
            content.categoryIdentifier = reminderCategoryIdentifier
            content.userInfo = ["itemIDs": planned.group.itemIDs.map(\.uuidString)]
            if settings.timeSensitiveSetting == .enabled {
                content.interruptionLevel = .timeSensitive
            }
            return UNNotificationRequest(
                identifier: planned.group.identifier,
                content: content,
                trigger: planned.trigger.notificationTrigger
            )
        }
        // An empty plan is reported as `.failed`, never as `.scheduled`. A
        // group of fired series only plans nothing when its continuation is
        // refused, and the pending check below is an `allSatisfy`, which
        // passes over nothing. `.scheduled` is the one answer a pass must
        // never give falsely: the caller tells the person the reminder is
        // set, and nothing retries it. A false `.failed` costs a retry and an
        // honest "couldn't be scheduled". No reachable path is known to plan
        // nothing; this decides which way it errs if one ever does.
        guard !notifications.isEmpty else { return .failed }
        let addedAll = await addAllOrNone(
            notifications,
            add: { try await center.add($0) },
            remove: { delivery.removeNotifications($0) }
        )
        guard addedAll else { return .failed }
        let pending = Set(await center.pendingNotificationRequests().map(\.identifier))
        return notifications.allSatisfy { pending.contains($0.identifier) } ? .scheduled : .failed
    }

    /// Adds every request, or leaves none of them behind.
    ///
    /// A snoozed occurrence is two requests, the one-shot and the series, and
    /// the one-shot alone is the missed reminder the second exists to prevent.
    /// So when an add throws, everything this call already added is withdrawn
    /// again, together with the request that threw in case it was half
    /// registered, and the pass reports failure for the next pass to retry.
    /// Takes its effects as arguments so the rollback can be tested without
    /// the notification center.
    static func addAllOrNone(
        _ notifications: [UNNotificationRequest],
        add: (UNNotificationRequest) async throws -> Void,
        remove: ([String]) -> Void
    ) async -> Bool {
        var added: [String] = []
        for notification in notifications {
            do {
                try await add(notification)
            } catch {
                remove(added + [notification.identifier])
                return false
            }
            added.append(notification.identifier)
        }
        return true
    }

    /// What `scheduleNotification` adds for a group, as values.
    ///
    /// Exposed for tests over requests rather than the private group, and
    /// grouped exactly the way `scheduleBatch` groups them.
    static func plannedNotifications(
        for requests: [ReminderScheduleRequest],
        now: Date = .now
    ) -> [PlannedReminderNotification] {
        notificationGroups(from: batchSelection(requests, now: now).notifications)
            .flatMap { plannedNotifications(for: $0, now: now) }
            .map {
                PlannedReminderNotification(
                    identifier: $0.group.identifier,
                    itemIDs: $0.group.itemIDs,
                    trigger: $0.trigger
                )
            }
            .sorted { $0.identifier < $1.identifier }
    }

    private static func plannedNotifications(
        for group: NotificationGroup,
        now: Date
    ) -> [(group: NotificationGroup, trigger: PlannedReminderNotification.Trigger)] {
        // A group of requests built after their fire had passed holds only
        // series continuations (`forScheduling`), and arms only their series
        // triggers. Decided by how the request was built rather than by
        // comparing with `now` again, so an alert that slips into the past
        // between the batch and this call still gets its own one-second fire.
        var planned: [(group: NotificationGroup, trigger: PlannedReminderNotification.Trigger)] = []
        if !group.requests.allSatisfy(\.continuesSeriesOnly) {
            planned.append((group: group, trigger: trigger(for: group, now: now)))
        }
        for request in group.requests {
            guard let continuation = seriesContinuationTrigger(for: request, now: now) else { continue }
            planned.append((
                group: NotificationGroup(
                    identifier: seriesNotificationIdentifier(for: request.itemID),
                    requests: [request]
                ),
                trigger: continuation
            ))
        }
        return planned
    }

    /// What a scheduling pass arms, as a value. `scheduleBatch` and
    /// `plannedNotifications` both select through this, so the selection a
    /// pass actually makes is the one the tests read.
    struct BatchSelection: Equatable {
        /// Alarms still ahead. A repeating alarm whose occurrence has rung
        /// counts: its request is built for its next ring
        /// (`nextRingOfFiredAlarm`). Any other alarm whose fire has passed has
        /// nothing left to arm.
        let alarms: [ReminderScheduleRequest]
        /// Notification requests still ahead, and every request that only
        /// continues a series (`continuesSeriesOnly`). Leaving the second kind
        /// out is DEL-12: the pass has already cancelled their triggers.
        let notifications: [ReminderScheduleRequest]
    }

    static func batchSelection(
        _ requests: [ReminderScheduleRequest],
        now: Date
    ) -> BatchSelection {
        BatchSelection(
            alarms: requests.filter { $0.delivery == .alarm && $0.fireDate > now },
            notifications: requests.filter {
                $0.delivery == .notification && ($0.fireDate > now || $0.continuesSeriesOnly)
            }
        )
    }

    private static func trigger(
        for group: NotificationGroup,
        now: Date
    ) -> PlannedReminderNotification.Trigger {
        let secondsUntilFire = group.fireDate.timeIntervalSince(now)
        if secondsUntilFire > 60,
           group.requests.count == 1,
           group.requests[0].seriesContinuation == nil,
           let repeatingComponents = group.requests[0].repeatingComponents,
           let repeatingNextFire = UNCalendarNotificationTrigger(
               dateMatching: repeatingComponents, repeats: true
           ).nextTriggerDate(),
           abs(repeatingNextFire.timeIntervalSince(group.fireDate)) < 60 {
            // A recurring reminder that only ever schedules its next single
            // occurrence stops firing the moment the person misses one — see
            // Docs/FINAL_RELEASE_AUDIT.md H-1/E-1. Handing iOS the recurring
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
            // rejoin the resilient path on the next generated occurrence. A
            // snoozed occurrence is never this case: its fire is the snooze,
            // and the series is armed separately beside it.
            return .repeating(repeatingComponents)
        } else if secondsUntilFire <= 60 {
            // Relative reminders such as “in 10 seconds” should count down
            // from the moment the thought is saved. A time-interval trigger
            // also avoids missing the requested calendar second while iOS is
            // finishing authorization or registering the request.
            return .afterInterval(max(secondsUntilFire, 1))
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
            return .exact(components)
        }
    }

    /// The series' repeating trigger for a snoozed occurrence, or `nil`.
    ///
    /// A repeating calendar trigger first fires at the first match after it
    /// is added. A snooze is pressed on an occurrence's own alert, so that
    /// occurrence's slot has already passed and the first match is the next
    /// occurrence. The one case where it has not passed, a snooze pressed
    /// before the series' alert, would make the repeating trigger fire this
    /// same occurrence a second time. It is refused, and the one-shot alone
    /// covers that occurrence until the next pass.
    private static func seriesContinuationTrigger(
        for request: ReminderScheduleRequest,
        now: Date
    ) -> PlannedReminderNotification.Trigger? {
        guard let continuation = request.seriesContinuation,
              let firstMatch = nextMatch(of: continuation.components, after: now),
              firstMatch.timeIntervalSince(continuation.occurrenceFireDate) >= 60 else { return nil }
        return .repeating(continuation.components)
    }

    /// The first moment after `date` that `components` match, read in the zone
    /// the components carry. Plain calendar arithmetic, so it is the same
    /// answer on a simulator pinned to another zone.
    static func nextMatch(of components: DateComponents, after date: Date) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = components.timeZone ?? .current
        var matching = components
        matching.timeZone = nil
        return calendar.nextDate(
            after: date,
            matching: matching,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private static func scheduleBatch(
        _ requests: [ReminderScheduleRequest],
        requestAuthorizationIfNeeded: Bool,
        scope: ReminderSynchronizationScope?
    ) async -> [ReminderSchedulingResult] {
        let selection = batchSelection(requests, now: .now)
        var resolvedScope = scope ?? ReminderSynchronizationScope(requests: requests)
        resolvedScope.include(requests)

        for itemID in resolvedScope.itemIDs {
            if resolvedScope.alarmsLeftAlone.contains(itemID) {
                removeNotifications(for: itemID)
            } else {
                cancel(itemID: itemID)
            }
        }
        await clearExistingNotifications(scope: resolvedScope)

        var results: [ReminderSchedulingResult] = []
        for request in selection.alarms {
            results.append(await schedule(
                request,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded,
                leavingAlarmAlone: resolvedScope.alarmsLeftAlone.contains(request.itemID)
            ))
        }
        // Includes a series whose alert has fired, which keeps only its
        // repeating trigger. The cancel above removed it for every item in
        // scope, so leaving it out here is what used to disarm the series.
        for group in notificationGroups(from: selection.notifications) {
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
        let itemIdentifiers = Set(scope.itemIDs.flatMap {
            [notificationIdentifier(for: $0), seriesNotificationIdentifier(for: $0)]
        })
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

    /// The second notification a snoozed recurring occurrence keeps armed,
    /// the series' own repeating trigger. Derived from the item alone, so
    /// every path that removes an item's reminder removes this too:
    /// `cancel(itemID:)`, a scoped pass through
    /// `notificationIdentifiersToRemove`, and a full reconcile, whose
    /// `SpeakIt.reminder.` prefix already covers it and which re-adds it only
    /// while the row is still snoozed.
    static func seriesNotificationIdentifier(for itemID: UUID) -> String {
        "SpeakIt.reminder.\(itemID.uuidString).series"
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
