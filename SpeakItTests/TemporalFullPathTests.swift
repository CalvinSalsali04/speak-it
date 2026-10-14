import SwiftData
import UserNotifications
import XCTest
@testable import SpeakIt

/// Exercises time through the whole application, not through the resolver alone.
///
/// `SwiftDataThoughtRepositoryTests` already proves `TemporalResolver` and
/// `RecurrenceRule` behave correctly when called directly with the arguments
/// they want. That is necessary and not sufficient: every failure this file was
/// written to catch lives in the wiring *between* those correct pieces — an
/// intent that is never carried onto the next item in a series, a reconcile
/// that rebuilds notifications from a stored instant instead of the intent, a
/// backfill that reads a stored day in the wrong zone. Each of those leaves the
/// resolver's own tests green.
///
/// So these tests drive the real repository against a real on-disk store, and
/// assert on what the app would actually schedule.
@MainActor
final class TemporalFullPathTests: XCTestCase {
    static let trainLongCapture = """
Right, about the trip. The train is booked for Friday, October ninth, leaving at ten in the morning. I have the booking already, so I am not buying another ticket. I need to download the actual ticket before the train leaves. The email with a list of journey options is not the ticket; use the attachment in the confirmation. I know I always say I will have a signal at the station, but I would rather not depend on that.

Text Sam to say the train leaves at ten on Friday and ask whether he can meet me at the other end. I have not picked a time to send that text. Ten is the departure time inside the message. Also pack the short charging cable, the one that fits in the small battery pouch. I do not need the long cable from behind the desk. The packing is for this trip, but I have not given it a reminder time.

I thought I might take the big camera, but I have decided to leave it and use my phone. Do not keep a camera packing job from that thought. There is an idea I want to keep separately, though: photograph the same station platform from the same spot every time I visit. It might make an interesting series over a year. I am not setting up a recurring reminder for it, just saving the possible project.

The guest room key is with June, not with Jonah. Remember that. I keep mixing their names up because they both helped last time. Ask June tomorrow whether I can collect the key on Thursday evening. Tomorrow is when I want to ask; Thursday evening is the proposed collection in the question. And remind me at eight tonight to put the railcard in my wallet. That is the last item, and the eight o'clock alert is only for the railcard, not all the trip jobs.
"""

    func testTemporalLongMixedCaptureDoesNotBorrowANominalEveryForWeeklyRecurrence() {
        let source = """
I am sorting the memorial display for the village hall and it is emotionally easier to say this than to make a tidy list, the committee already chose the photographs and the historian will check the dates beneath them, I promised to write a short paragraph about the old railway and take the scanned newspaper page to the print shop, the page is already scanned so that step is done, the shop said the larger print might cost eighteen dollars but they will confirm the quote and I am not authorising the extra size until I see it, if it is more than twenty dollars I will ask for the smaller version, I need a reminder Thursday at half past three in the afternoon to check their message, the display opens on October second according to the committee minutes but there is no reason for an opening-day alarm in this capture, somebody suggested adding every resident's name which we rejected because the records are incomplete, and I want that decision kept so we do not reopen it by accident, the old station name was Millbridge Halt, not Mill Bridge Station, which was the name I used earlier, the photograph of the ticket window belongs to Elsie's family and should be credited that way, I do not know the photographer's name, the brass frame is borrowed from the hall caretaker and will need returning after the display comes down but we do not know that closing date yet, please put returning the frame on my list with that event context rather than making up a date, and remember that the spare clips are in the small tin behind the noticeboard.
"""
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            XCTAssertNil(RecurrenceIntentParser.parse(source.lowercased()))
            let parsed = RuleBasedThoughtExtractor.process(source, referenceDate: anchor, calendar: calendar)
            XCTAssertFalse(parsed.items.isEmpty)
            XCTAssertTrue(parsed.items.allSatisfy { $0.organization.recurrenceRule == nil })
            XCTAssertTrue(parsed.items.allSatisfy { $0.organization.temporalIntent.recurrence == nil })
            let diagnostic = String(reflecting: parsed)
            let ledger = SourceUnitLedger(source)
            let originalIDs = Set(ledger.words.indices)
            var claimedIDs = Set<Int>()
            for item in parsed.items {
                XCTAssertFalse(item.sourceUnitIDs.isEmpty, diagnostic)
                XCTAssertTrue(item.sourceUnitIDs.isSubset(of: originalIDs), diagnostic)
                XCTAssertTrue(claimedIDs.isDisjoint(with: item.sourceUnitIDs), diagnostic)
                claimedIDs.formUnion(item.sourceUnitIDs)
                // Ordinary rules grouping can display noncontiguous original
                // spans with an ellipsis. Prove each original occurrence and
                // its row ownership rather than require one contiguous quote.
                var cursor = source.startIndex
                var displayedIDs = Set<Int>()
                for fragment in item.rawQuote.components(separatedBy: " … ") {
                    guard !fragment.isEmpty,
                          let span = source.range(of: fragment, options: .literal,
                              range: cursor..<source.endIndex) else {
                        XCTFail("Raw fragment is not an exact ordered original span: \(diagnostic)")
                        continue
                    }
                    let fragmentIDs = ledger.ids(in: span)
                    XCTAssertFalse(fragmentIDs.isEmpty, diagnostic)
                    XCTAssertTrue(fragmentIDs.isSubset(of: item.sourceUnitIDs), diagnostic)
                    XCTAssertTrue(displayedIDs.isDisjoint(with: fragmentIDs), diagnostic)
                    XCTAssertEqual(SourceUnitLedger(fragment).words.map(\.text),
                        fragmentIDs.sorted().map { ledger.words[$0].text }, diagnostic)
                    displayedIDs.formUnion(fragmentIDs)
                    cursor = span.upperBound
                }
                XCTAssertEqual(displayedIDs, item.sourceUnitIDs, diagnostic)
            }
            XCTAssertTrue(ledger.unownedMeaningfulIDs(after: parsed.items).isEmpty, diagnostic)
            // This source genuinely requests a one-off reminder. Absence of
            // an invented series does not establish complete organization.
        }
    }

    func testTemporalWeeklyRecurrenceRequiresTemporalRatherThanObjectQuantification() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            for source in [
                "Check the display Thursday and label every photograph.",
                "Check the message on Tuesday and count each visitor's ticket.",
                "I need to inspect the frame Friday; every resident's name belongs in the archive."
            ] {
                XCTAssertNil(RecurrenceIntentParser.parse(source.lowercased()), source)
                let parsed = RuleBasedThoughtExtractor.process(source, referenceDate: anchor, calendar: calendar)
                XCTAssertFalse(parsed.items.isEmpty, source)
                XCTAssertTrue(parsed.items.allSatisfy { $0.organization.recurrenceRule == nil }, source)
                XCTAssertTrue(parsed.items.allSatisfy { $0.organization.temporalIntent.recurrence == nil }, source)
            }
        }
    }

    func testTemporalSupportedWeeklyQuantifiersKeepExistingIntervalsAndWeekdays() throws {
        let schedules: [(String, [Int], Int)] = [
            ("Remind me every Thursday at 3 PM to check the printer quote.", [5], 1),
            ("Check the message weekly on Sundays.", [1], 1),
            ("Check the tray every other Tuesdays.", [3], 2),
            ("Check the tray every second Tuesday.", [3], 2),
            ("Check the tray each Tuesday.", [3], 1),
            ("Check the tray every week on Friday.", [6], 1),
            ("Check the tray every other week on Friday.", [6], 2),
            ("Check the tray every two weeks on Friday.", [6], 2),
            ("Check the tray weekly on Friday and label every other photograph.", [6], 1),
            ("Check the tray every Tuesday and Thursday.", [3, 5], 1),
            ("Remind me every Friday at 5 PM except this Friday.", [6], 1)
        ]
        for (source, days, interval) in schedules {
            let rule = try XCTUnwrap(RecurrenceIntentParser.parse(source.lowercased()), source)
            XCTAssertEqual(rule.frequency, .weekly, source)
            XCTAssertEqual(rule.weekdays, days, source)
            XCTAssertEqual(rule.interval, interval, source)
            XCTAssertEqual(rule.anchor, .scheduledDate, source)
        }
        for source in [
            "Remind me every morning to check whether the Friday deadline moved.",
            "Check the tray every day except Sunday."
        ] {
            let rule = try XCTUnwrap(RecurrenceIntentParser.parse(source.lowercased()), source)
            XCTAssertEqual(rule.frequency, .daily, source)
            XCTAssertTrue(rule.weekdays.isEmpty, source)
        }
    }

    func testTemporalQuantityObjectsDoNotAcquireClockMetadata() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            for source in [
                "Ask the tutor for two possible lesson times.",
                "Prepare notes for three short meetings.",
                "Reserve a table for two people."
            ] {
                let organized = ThoughtOrganizer.organize(source, referenceDate: anchor, calendar: calendar)
                XCTAssertNil(organized.dueDate, source)
                XCTAssertNil(organized.reminderDate, source)
                XCTAssertNil(organized.temporalIntent.time, source)
                XCTAssertNil(organized.recurrenceRule, source)
            }
            let laterClock = ThoughtOrganizer.organize(
                "Reserve a table for two people at 7 PM.", referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(laterClock.dueDate,
                           makeDate(year: 2026, month: 8, day: 3, hour: 19, calendar: calendar))
            let clock = ThoughtOrganizer.organize(
                "Book a table for 7 PM.", referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(clock.temporalIntent.time, WallClockTime(hour: 19, minute: 0))
            let repeatingClock = ThoughtOrganizer.organize(
                "Set an alarm for 7 every morning.", referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(repeatingClock.temporalIntent.time, WallClockTime(hour: 7, minute: 0))
            XCTAssertNotNil(repeatingClock.recurrenceRule)
        }
    }

    func testTemporalExplicitUnsetHourHoldsInsteadOfApplyingADefault() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            for source in [
                "Set a reminder every Sunday evening to review the week's spending, but leave the exact hour unset for now.",
                "Remind me tomorrow to read the notes, and do not choose an exact time.",
                "Remind me every morning to check the tray; keep the time unspecified."
            ] {
                let organized = ThoughtOrganizer.organize(source, referenceDate: anchor, calendar: calendar)
                XCTAssertTrue(organized.needsClarification, source)
                XCTAssertNil(organized.dueDate, source)
                XCTAssertNil(organized.reminderDate, source)
                XCTAssertEqual(organized.reminderDelivery, .none, source)
                XCTAssertNil(organized.recurrenceRule, source)
                XCTAssertNil(organized.temporalIntent.time, source)
                XCTAssertEqual(organized.temporalIntent.sourceText, source.lowercased(), source)
            }
            let ordinary = ThoughtOrganizer.organize(
                "Set a reminder every Sunday evening to review the week's spending.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertFalse(ordinary.needsClarification)
            XCTAssertEqual(ordinary.temporalIntent.time, WallClockTime(hour: 20, minute: 0))
            XCTAssertEqual(ordinary.recurrenceRule?.weekdays, [1])
            XCTAssertNotNil(ordinary.reminderDate)
            let dateOnly = ThoughtOrganizer.organize(
                "Remind me tomorrow to read the notes.", referenceDate: anchor, calendar: calendar
            )
            XCTAssertFalse(dateOnly.needsClarification)
            XCTAssertEqual(dateOnly.temporalIntent.kind, .dateOnly)
            XCTAssertNil(dateOnly.temporalIntent.time)
            XCTAssertNotNil(dateOnly.reminderDate)
            let quoted = ThoughtOrganizer.organize(
                "Remind me tomorrow at 3 PM to read the phrase 'leave the exact hour unset'.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertFalse(quoted.needsClarification)
            XCTAssertEqual(quoted.reminderDate,
                           makeDate(year: 2026, month: 8, day: 4, hour: 15, calendar: calendar))
        }
    }

    func testTemporalUnsupportedRecurrenceBoundsRetainWholeIntentWithoutAnActiveSeries() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            let sources = [
                "I need a reminder on the last day of each month at 5 p.m. to send my volunteer hours.",
                "Remind me every month on the last calendar day at 6 PM to submit the meter reading.",
                "Remind me four hours from now, then every four hours today to check the cooling fan, but stop after eight tonight.",
                "Remind me every ninety minutes today to check the fan.",
                "Remind me every two hours to check the tray, stopping at 6 PM.",
                "Remind me every day at 9 AM to check the tray for the next three weeks."
            ]
            for source in sources {
                let result = ThoughtExtractionEngine.extractWithRules(source, referenceDate: anchor, calendar: calendar)
                XCTAssertFalse(result.items.isEmpty, source)
                XCTAssertTrue(result.operations.isEmpty, source)
                XCTAssertEqual(result.items.flatMap { item in
                    SourceUnitLedger(item.rawQuote).words.map { String(item.rawQuote[$0.range]) }
                }, SourceUnitLedger(source).words.map { String(source[$0.range]) },
                "An unsupported bound must not detach from its owner or lose an original word.")
                for item in result.items {
                    XCTAssertTrue(item.organization.needsClarification, source)
                    XCTAssertNil(item.organization.dueDate, source)
                    XCTAssertNil(item.organization.reminderDate, source)
                    XCTAssertEqual(item.organization.reminderDelivery, .none, source)
                    XCTAssertNil(item.organization.recurrenceRule, source)
                }
            }
            let unbounded = ThoughtOrganizer.organize(
                "Remind me every four hours to check the cooling fan.", referenceDate: anchor, calendar: calendar
            )
            XCTAssertFalse(unbounded.needsClarification)
            XCTAssertEqual(unbounded.recurrenceRule?.intervalSeconds, 14_400)
            XCTAssertEqual(unbounded.reminderDate, anchor.addingTimeInterval(14_400))
            let ordinal = ThoughtOrganizer.organize(
                "Remind me on the last Friday every month at 5 PM to send my hours.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertFalse(ordinal.needsClarification)
            XCTAssertEqual(ordinal.recurrenceRule?.ordinalWeekday, OrdinalWeekday(ordinal: -1, weekday: 6))
            XCTAssertNotNil(ordinal.reminderDate)
        }
    }

    func testTemporalThirtyDayCalendarIntervalPreservesItsStartAndNextOccurrence() throws {
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            for source in [
                "Remind me every thirty days to descale the kettle, starting August 10.",
                "Remind me every 30 days at 11 AM to descale the kettle, beginning on August tenth, 2026."
            ] {
                let organized = ThoughtOrganizer.organize(source, referenceDate: anchor, calendar: calendar)
                let rule = try XCTUnwrap(organized.recurrenceRule, source)
                XCTAssertEqual(rule.frequency, .daily, source)
                XCTAssertEqual(rule.interval, 30, source)
                XCTAssertNil(rule.intervalSeconds, source)
                XCTAssertFalse(organized.needsClarification, source)
                XCTAssertEqual(organized.temporalIntent.day, CalendarDay(year: 2026, month: 8, day: 10), source)
                let first = try XCTUnwrap(organized.reminderDate, source)
                let clock = source.contains("11 AM") ? WallClockTime(hour: 11, minute: 0) : ReminderDefaults.alertTime
                XCTAssertEqual(first, makeDate(year: 2026, month: 8, day: 10, hour: clock.hour,
                                               minute: clock.minute, calendar: calendar), source)
                let restored = try JSONDecoder().decode(RecurrenceRule.self, from: JSONEncoder().encode(rule))
                XCTAssertEqual(restored, rule, "The existing persisted shape must retain a 30-day interval.")
                XCTAssertEqual(restored.nextDate(scheduledDate: first, completedAt: first, calendar: calendar),
                               makeDate(year: 2026, month: 9, day: 9, hour: clock.hour,
                                        minute: clock.minute, calendar: calendar), source)
            }
            for source in [
                "Remind me every thirty days to descale the kettle, starting February 30.",
                "Remind me every thirty days to descale the kettle, starting August 10, 2025.",
                "Remind me every thirty days to descale the kettle, starting August 10 until September 1."
            ] {
                let held = ThoughtOrganizer.organize(source, referenceDate: anchor, calendar: calendar)
                XCTAssertTrue(held.needsClarification, source)
                XCTAssertNil(held.recurrenceRule, source)
                XCTAssertNil(held.reminderDate, source)
            }
        }
    }

    func testTemporalSpokenNinetyMinuteDurationAndRecurrenceUseElapsedTime() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            for (number, seconds) in [("ninety", 5_400.0), ("seventy-five", 4_500.0), ("ninety nine", 5_940.0)] {
                let organized = ThoughtOrganizer.organize(
                    "Remind me in \(number) minutes to change the sprinkler zone.", referenceDate: anchor, calendar: calendar
                )
                XCTAssertFalse(organized.needsClarification, number)
                XCTAssertEqual(organized.temporalIntent.kind, .relativeDuration, number)
                XCTAssertEqual(organized.temporalIntent.relativeSeconds, seconds, number)
                XCTAssertEqual(organized.reminderDate, anchor.addingTimeInterval(seconds), number)
            }
            let series = ThoughtOrganizer.organize(
                "Remind me every ninety minutes to check the sprinkler zone.", referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(series.recurrenceRule?.intervalSeconds, 5_400)
            XCTAssertEqual(series.reminderDate, anchor.addingTimeInterval(5_400))
        }
    }

    func testTemporalIndependentReminderClockKeepsActionOrderAndQuestionsAsContent() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            let cases: [(String, Date)] = [
                ("At four this afternoon, remind me to test the microphone before the workshop.",
                 makeDate(year: 2026, month: 8, day: 3, hour: 16, calendar: calendar)),
                ("Remind me Friday at four to take that folder when I visit.",
                 makeDate(year: 2026, month: 8, day: 7, hour: 16, calendar: calendar)),
                ("Remind me tomorrow to ask when they will be ready.",
                 makeDate(year: 2026, month: 8, day: 4, hour: ReminderDefaults.alertTime.hour,
                          minute: ReminderDefaults.alertTime.minute, calendar: calendar)),
                ("Remind me tomorrow to ask the cleaner when the rugs will be ready.",
                 makeDate(year: 2026, month: 8, day: 4, hour: ReminderDefaults.alertTime.hour,
                          minute: ReminderDefaults.alertTime.minute, calendar: calendar))
            ]
            for (source, alert) in cases {
                let organized = ThoughtOrganizer.organize(source, referenceDate: anchor, calendar: calendar)
                XCTAssertFalse(organized.needsClarification, source)
                XCTAssertNil(organized.temporalIntent.unsupportedTrigger, source)
                XCTAssertEqual(organized.reminderDate, alert, source)
                XCTAssertEqual(organized.reminderDelivery, .notification, source)
            }
            let unfinishedQuestion = ThoughtOrganizer.organize(
                "Remind me tomorrow to ask.", referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(unfinishedQuestion.needsClarification)
            XCTAssertNil(unfinishedQuestion.reminderDate)
        }
    }

    func testTemporalIndependentClockDoesNotEraseRealConditionsOrPlaceConjunctions() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            for source in [
                "If the nurse changes anything, remind me Friday at four to update the paper list.",
                "Remind me Friday at four to update the paper list if the nurse changes anything.",
                "Remind me Friday at four to call only when the results arrive.",
                "Remind me Friday at four to call unless the clinic is closed.",
                "Remind me Friday at four to call when she arrives.",
                "Remind me tomorrow to ask the cleaner when I get home.",
                "Remind me tomorrow to return the key when I get home.",
                "Remind me Friday to call the clinic unless it is closed.",
                "Remind me Friday at four to take the folder when I get home."
            ] {
                let organized = ThoughtOrganizer.organize(source, referenceDate: anchor, calendar: calendar)
                XCTAssertTrue(organized.needsClarification, source)
                XCTAssertNil(organized.reminderDate, source)
                XCTAssertEqual(organized.reminderDelivery, .none, source)
            }
        }
    }

    func testTemporalReminderContentRolesPreserveWholeSourceWordCoverage() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            for source in [
                "At four this afternoon, remind me to test the microphone before the workshop.",
                "The cleaner has already taken the rugs, but remind me tomorrow to ask when they will be ready.",
                "Remind me Friday at four to take that folder when I visit. If the nurse changes anything, I will update the paper list after she tells us.",
                "Add asking the tutor for two possible lesson times, then checking both against my rota."
            ] {
                let result = ThoughtExtractionEngine.extractWithRules(source, referenceDate: anchor, calendar: calendar)
                XCTAssertFalse(result.items.isEmpty, source)
                if source.hasPrefix("The cleaner") {
                    // Complete short perfect facts remain independently in
                    // Memory and also explain the reminder. Shared context
                    // quotes are intentional; this is not a disjoint literal
                    // certificate. The dedicated perfect-fact regression
                    // audits the exact shared occurrence IDs and connector.
                    XCTAssertEqual(result.items.count, 2)
                    XCTAssertEqual(result.items.filter { $0.organization.itemType.isActionable }.count, 1)
                    let ledger = SourceUnitLedger(source)
                    let retainedIDs = result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
                    let connectorIDs = Set(ledger.words.indices.filter { ledger.words[$0].text == "but" })
                    XCTAssertEqual(retainedIDs, Set(ledger.words.indices).subtracting(connectorIDs))
                    XCTAssertTrue(result.items.allSatisfy { !$0.needsReview })
                    // Shared contextual quotes are not literal disjoint
                    // proposals. Persistence must still retain EVERY original
                    // character, including the coordination seam.
                    let saved = try? repository.createCapture(text: source, source: .inAppText,
                        createdAt: anchor, schedulesReminder: false)
                    XCTAssertEqual(saved?.captureSession?.originalTranscription, source)
                } else {
                    XCTAssertEqual(result.items.flatMap { item in
                        SourceUnitLedger(item.rawQuote).words.map { String(item.rawQuote[$0.range]) }
                    }, SourceUnitLedger(source).words.map { String(source[$0.range]) }, source)
                }
            }
        }
    }

    func testCompletedAndForeignRoutineClocksRemainReferenceAcrossTheWholeSource() throws {
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            let sources = [
                "I finished the application at midnight and just want to record how relieved I felt.",
                "We completed the inventory at midnight and felt relieved.",
                "The train we liked last time departed at 06:40.",
                "The ferry we used yesterday arrived at 08:10.",
                "My neighbour works nights from 10 p.m. to 6 a.m.; that explains the blackout curtains.",
                "Her brother sleeps from 11 p.m. to 7 a.m. on weekdays."
            ]
            for source in sources {
                let result = ThoughtExtractionEngine.extractWithRules(
                    source, referenceDate: anchor, calendar: calendar
                )
                XCTAssertFalse(result.items.isEmpty, source)
                XCTAssertTrue(result.operations.isEmpty, source)
                // Row provenance covers word occurrences. Its final span can
                // end at the last word; the saved capture owns exact punctuation.
                let quotedWords = result.items.flatMap { item in
                    let quote = item.rawQuote
                    return SourceUnitLedger(quote).words.map { String(quote[$0.range]) }
                }
                XCTAssertEqual(quotedWords,
                               SourceUnitLedger(source).words.map { String(source[$0.range]) },
                               "Every original word occurrence must survive once and in order.")
                let created = try repository.createCapture(
                    text: source, source: .inAppText, createdAt: anchor, schedulesReminder: false
                )
                XCTAssertEqual(try XCTUnwrap(created.captureSession).originalTranscription, source,
                               "The saved capture must retain exact wording and punctuation.")
                for item in result.items {
                    XCTAssertFalse(item.organization.itemType.isActionable, source)
                    XCTAssertNil(item.organization.dueDate, source)
                    XCTAssertNil(item.organization.reminderDate, source)
                    XCTAssertEqual(item.organization.reminderDelivery, .none, source)
                    XCTAssertNil(item.organization.recurrenceRule, source)
                    XCTAssertEqual(item.organization.temporalIntent, .none, source)
                }
            }
        }
    }

    func testReferenceClockProofPreservesGroundedFutureMemoryDates() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            let sources: [(String, CalendarDay)] = [
                ("Maya's birthday is December 4.", CalendarDay(year: 2026, month: 12, day: 4)),
                ("The office closes December 24.", CalendarDay(year: 2026, month: 12, day: 24)),
                ("I completed the booking for a visit on September 8.",
                 CalendarDay(year: 2026, month: 9, day: 8))
            ]
            for (source, day) in sources {
                let organized = ThoughtOrganizer.organize(
                    source, referenceDate: anchor, calendar: calendar
                )
                XCTAssertFalse(organized.itemType.isActionable, source)
                XCTAssertEqual(organized.temporalIntent.day, day, source)
                XCTAssertNil(organized.dueDate, source)
                XCTAssertNil(organized.reminderDate, source)
                XCTAssertEqual(organized.reminderDelivery, .none, source)
            }
        }
    }

    func testHistoricalOrForeignOwnerProofDeclinesIndependentCurrentActs() {
        let mixedSources = [
            "I finished the inventory at midnight, but I need to send the receipt tomorrow.",
            "The train we liked last time departed at 06:40; call the station tomorrow.",
            "My neighbour works nights, and I will collect the parcel tomorrow.",
            "My neighbour works nights, and my shift starts tomorrow at 10 p.m.",
            "My neighbour works nights; remind me tomorrow at 9 AM to return the key.",
            "The train left last night at 9 PM, arrange the chairs.",
            "My neighbour works nights from 10 PM to 6 AM and rinse the tray.",
            "The train that left last night starts another journey tomorrow.",
            "The parcel I need returned by noon.",
            "The train that left last night meets us at noon.",
            "I finished the application and I felt relieved, and I arrange the chairs tomorrow.",
            "I finished the application and I felt relieved, and I'm arranging the chairs tomorrow.",
            "The neighbour who works nights meets us tomorrow.",
            "The note says the train left last night at 9 PM.",
            "The label says 'I finished the application at midnight'.",
            "I finished the label saying 'the train left last night",
            "I have not finished the application yet.",
            "My shift starts tomorrow at 10 p.m.",
            "The train departs tomorrow at 06:40."
        ]
        for source in mixedSources {
            XCTAssertNil(TemporalReferenceScope.read(source), source)
        }
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            for source in ["My shift starts tomorrow at 10 p.m.",
                           "The train departs tomorrow at 06:40.",
                           "Remind me tomorrow at 9 AM to check the archived departure log."] {
                let organized = ThoughtOrganizer.organize(
                    source, referenceDate: anchor, calendar: calendar
                )
                XCTAssertTrue(organized.itemType.isActionable, source)
                XCTAssertEqual(organized.temporalIntent.day,
                               CalendarDay(year: 2026, month: 8, day: 4), source)
                XCTAssertNotNil(organized.dueDate, source)
            }
        }
    }

    func testHistoricalReferenceDoesNotAbsorbIndependentOwnReminderOrEvent() throws {
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            let source = "The train we liked last time departed at 06:40. "
                + "Remind me tomorrow at 9 AM to call the station. "
                + "My shift starts tomorrow at 10 p.m."
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(result.operations.isEmpty)
            let quotedWords = result.items.flatMap { item in
                let quote = item.rawQuote
                return SourceUnitLedger(quote).words.map { String(quote[$0.range]) }
            }
            XCTAssertEqual(quotedWords,
                           SourceUnitLedger(source).words.map { String(source[$0.range]) },
                           "Independent intentions must preserve every original word occurrence.")
            let created = try repository.createCapture(
                text: source, source: .inAppText, createdAt: anchor, schedulesReminder: false
            )
            XCTAssertEqual(try XCTUnwrap(created.captureSession).originalTranscription, source)
            let historical = result.items.filter {
                $0.analysisText.contains("last time departed")
            }
            XCTAssertEqual(historical.count, 1)
            XCTAssertFalse(historical.first?.organization.itemType.isActionable ?? true)
            XCTAssertEqual(historical.first?.organization.temporalIntent, TemporalIntent.none)
            let reminder = result.items.filter {
                $0.analysisText.contains("call the station")
            }
            XCTAssertEqual(reminder.count, 1)
            XCTAssertTrue(reminder.first?.organization.itemType.isActionable == true)
            XCTAssertEqual(reminder.first?.organization.reminderDate,
                           makeDate(year: 2026, month: 8, day: 4, hour: 9, calendar: calendar))
            let shift = result.items.filter { $0.analysisText.localizedCaseInsensitiveContains("my shift") }
            XCTAssertEqual(shift.count, 1)
            XCTAssertTrue(shift.first?.organization.itemType.isActionable == true)
            XCTAssertEqual(shift.first?.organization.dueDate,
                           makeDate(year: 2026, month: 8, day: 4, hour: 22, calendar: calendar))
        }
    }

    func testWithdrawnSendPlanPersistsOnlyRevisedTargetAndKeepsSourceAcrossRelaunch() throws {
        let source = PersonMentionTests.withdrawnSendSource
        var before: Data!
        var itemID = UUID()
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let rows = try allItems()
            XCTAssertEqual(rows.count, 1)
            let item = try XCTUnwrap(rows.first)
            itemID = item.id
            XCTAssertEqual(item.personName, "Marcus")
            XCTAssertEqual(item.displayTitle, "Send Marcus the reviewed version on Wednesday after Clara comments")
            XCTAssertTrue(item.displayTitle.contains("after Clara comments"))
            XCTAssertEqual(item.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 7))
            XCTAssertNil(item.temporalIntent?.time)
            XCTAssertNil(item.reminderDate)
            XCTAssertTrue(item.belongsInToday)
            XCTAssertFalse(item.needsClarification)
            XCTAssertNil(PendingOperationStore.record(for: item.id))
            XCTAssertEqual(item.captureSession?.originalTranscription, source)
            XCTAssertTrue(item.originalTextSegment.contains("send the draft to Marcus on Monday"))
            before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        }
        try relaunch()
        XCTAssertEqual(try loadItem(withID: itemID).captureSession?.originalTranscription, source)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), before)
    }

    func testOriginalLongCaptureQuestionKeepsMatrixDayAndMessageClockAcrossReopen() throws {
        let source = Self.trainLongCapture
        var id = UUID()
        var before: Data!
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let rows = try allItems()
            let question = try XCTUnwrap(rows.first { $0.originalTextSegment.hasPrefix("Ask June tomorrow whether") })
            id = question.id
            XCTAssertEqual(question.personName, "June")
            XCTAssertEqual(question.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(question.temporalIntent?.time)
            XCTAssertNil(question.reminderDate)
            XCTAssertFalse(question.needsClarification)
            XCTAssertTrue(question.belongsInToday)
            XCTAssertTrue(question.originalTextSegment.contains("Thursday evening"))
            XCTAssertEqual(question.displayTitle, "Ask June tomorrow whether I can collect the key on Thursday evening")
            // The separate explicit alert keeps its own 20:00 clock.
            let railcard = try XCTUnwrap(rows.first { $0.originalTextSegment.lowercased().contains("railcard") && $0.reminderDate != nil })
            XCTAssertEqual(railcard.temporalIntent?.time, WallClockTime(hour: 20, minute: 0))
            before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        }
        try relaunch()
        XCTAssertEqual(try loadItem(withID: id).captureSession?.originalTranscription, source)
        let after = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        XCTAssertEqual(after, before, "full original long-capture states and IDs survive relaunch")
    }

    func testLocalObjectAnswerPreservesKnownDaySourceAndFullSiblingAcrossRelaunch() async throws {
        let source = "I chose two books. Buy it by Friday. Also remember that Nora prefers oat milk."
        var targetID = UUID()
        var siblingBefore: Data!
        var finalState: Data!
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: true)
            let rows = try allItems()
            let target = try XCTUnwrap(rows.first { $0.originalTextSegment.contains("Buy it by Friday") })
            targetID = target.id
            XCTAssertEqual(target.clarificationRequirement, .ambiguousObject)
            XCTAssertEqual(target.itemType, .shopping)
            XCTAssertEqual(target.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 9))
            XCTAssertNil(target.reminderDate)
            let sibling = try XCTUnwrap(rows.first { $0.originalTextSegment.contains("Nora prefers") })
            let siblingID = sibling.id.uuidString
            @MainActor func siblingState() throws -> Data {
                try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
                    .filter { $0["id"] as? String == siblingID }, options: [.sortedKeys])
            }
            siblingBefore = try siblingState()
            XCTAssertNil(ReminderScheduleRequest(item: target))
        }
        await drainScheduler()
        let heldRequests = await pendingRequests(for: targetID)
        XCTAssertTrue(heldRequests.isEmpty, "the unresolved object must not deliver its known day")
        try withFixtureClock { _ in
            let target = try loadItem(withID: targetID)
            let siblingID = try XCTUnwrap(try allItems().first {
                $0.originalTextSegment.contains("Nora prefers")
            }).id.uuidString
            @MainActor func siblingState() throws -> Data {
                try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
                    .filter { $0["id"] as? String == siblingID }, options: [.sortedKeys])
            }
            // The person names the ambiguous object; the date is already stored.
            let edits = ItemEdits(title: "Buy the travel guide", itemType: target.itemType,
                category: target.category, dueDate: target.dueDate, reminderDate: target.reminderDate,
                priority: target.priority, personName: target.personName, needsClarification: false,
                dueDateHasTime: false)
            try repository.update(target, with: edits)
            try repository.update(target, with: edits)
            XCTAssertEqual(target.id, targetID)
            XCTAssertEqual(target.displayTitle, "Buy the travel guide")
            XCTAssertEqual(target.semanticState, .resolved)
            XCTAssertFalse(target.needsClarification)
            XCTAssertTrue(target.belongsInToday)
            XCTAssertEqual(target.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 9))
            XCTAssertNil(target.temporalIntent?.time)
            XCTAssertNil(target.reminderDate)
            XCTAssertEqual(try siblingState(), siblingBefore)
            XCTAssertEqual(try allItems().filter { $0.id == targetID }.count, 1)
            XCTAssertEqual(target.captureSession?.originalTranscription, source)
            finalState = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        }
        await drainScheduler()
        let resolvedRequests = await pendingRequests(for: targetID)
        XCTAssertTrue(resolvedRequests.isEmpty, "naming the object must not invent a reminder clock")
        try relaunch()
        repository.reconcilePendingReminders()
        await drainScheduler()
        let reloadedRequests = await pendingRequests(for: targetID)
        XCTAssertTrue(reloadedRequests.isEmpty)
        XCTAssertEqual(try loadItem(withID: targetID).captureSession?.originalTranscription, source)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), finalState)
    }

    func testManualConditionalTaskPersistsVisibleConditionAndOwnDayAcrossRetryAndRelaunch() async throws {
        let source = IntentConsolidationTests.gardenManualConditionalParagraph
        var anchor: Date!
        var seedIDs = Set<String>()
        var before: Data!
        var captureID = UUID()
        var itemID = UUID()
        try withFixtureClock { calendar in
            anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: "Water the parsley tomorrow at 8 PM", source: .inAppText,
                createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
            seedIDs = Set(try allItems().map { $0.id.uuidString })
            before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
            let first = try repository.createCapture(text: source, source: .inAppText,
                createdAt: anchor, schedulesReminder: false)
            captureID = try XCTUnwrap(first.captureSession).id
            let rows = try allItems().filter { $0.captureSession?.id == captureID }
            XCTAssertEqual(rows.count, 1)
            let item = try XCTUnwrap(rows.first)
            itemID = item.id
            XCTAssertEqual(item.itemType, .task)
            XCTAssertTrue(item.belongsInToday)
            XCTAssertFalse(item.needsClarification)
            XCTAssertTrue(item.displayTitle.localizedCaseInsensitiveContains("parsley"))
            XCTAssertTrue(item.displayTitle.localizedCaseInsensitiveContains("unless"))
            XCTAssertTrue(item.displayTitle.localizedCaseInsensitiveContains("rains"))
            XCTAssertEqual(item.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(item.temporalIntent?.time)
            XCTAssertNil(item.reminderDate)
            XCTAssertTrue(item.originalTextSegment.localizedCaseInsensitiveContains("if it rains before tomorrow morning"))
            XCTAssertTrue(item.originalTextSegment.localizedCaseInsensitiveContains("otherwise water it tomorrow"))
            XCTAssertTrue(item.originalTextSegment.localizedCaseInsensitiveContains("keep that conditional"))
            XCTAssertEqual(item.captureSession?.originalTranscription, source)
            XCTAssertNil(PendingOperationStore.record(for: item.id))
        }
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), before)
        let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        XCTAssertNil(retry.operationOutcome)
        let finalState = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), finalState)
        XCTAssertEqual(try loadItem(withID: itemID).captureSession?.originalTranscription, source)
    }

    /// The canonical S102 context: an empty store, Monday 2026-10-05 09:00
    /// in Toronto. All six meanings are saved through the shipping repository,
    /// nothing is held for review, no clock is invented, and a retry and two
    /// relaunches leave the complete persisted state byte-identical.
    func testCanonicalClubEventSavesItsSixMeaningsAcrossRetryAndRelaunch() async throws {
        let source = IntentConsolidationTests.clubEventLongCapture
        XCTAssertTrue(try allItems().isEmpty)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: Self.fixtureTimeZoneIdentifier)!
        let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
        let dueDays = ["sign": makeDate(year: 2026, month: 10, day: 9, calendar: calendar),
                       "caretaker": makeDate(year: 2026, month: 10, day: 6, calendar: calendar)]
        // Pin the zone for parsing only, through the shipping async path.
        let previousZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        let created = try await repository.createCaptureResult(text: source, source: .inAppVoice,
            createdAt: anchor, schedulesReminders: true)
        NSTimeZone.default = previousZone
        let captureID = created.session.id
        XCTAssertNil(created.operationOutcome)
        let rows = try allItems().filter { $0.captureSession?.id == captureID }
        let summary = rows.map { "\($0.itemType.rawValue): \($0.displayTitle)" }.joined(separator: " | ")
        XCTAssertEqual(rows.count, 6, summary)
        XCTAssertTrue(rows.allSatisfy { !$0.needsClarification && $0.reminderDate == nil }, summary)
        XCTAssertTrue(rows.allSatisfy { PendingOperationStore.record(for: $0.id) == nil })

        let sign = try XCTUnwrap(rows.first { $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("direction sign") }, summary)
        XCTAssertTrue(sign.belongsInToday)
        XCTAssertEqual(sign.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 9))
        XCTAssertNil(sign.temporalIntent?.time)
        XCTAssertEqual(sign.dueDate, dueDays["sign"])
        XCTAssertTrue(sign.displayTitle.localizedCaseInsensitiveContains("before the event starts at six"), sign.displayTitle)
        XCTAssertTrue(sign.originalTextSegment.contains("Use the bigger type version."))
        XCTAssertTrue(sign.originalTextSegment.contains("Last time people kept trying the front doors"))

        let account = try XCTUnwrap(rows.first { $0.originalTextSegment.contains("Asha said") })
        XCTAssertFalse(account.itemType.isActionable)
        XCTAssertTrue(account.belongsInMemory)
        XCTAssertTrue(account.originalTextSegment.contains("I have not agreed to send that message."))

        let caretaker = try XCTUnwrap(rows.first { $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("caretaker") })
        XCTAssertEqual(caretaker.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
        XCTAssertEqual(caretaker.dueDate, dueDays["caretaker"])
        XCTAssertTrue(caretaker.originalTextSegment.contains("before anybody sends a confident message"))

        let badges = try XCTUnwrap(rows.first { $0.displayTitle.localizedCaseInsensitiveContains("name badges") })
        XCTAssertTrue(badges.belongsInMemory)
        XCTAssertFalse(badges.itemType.isActionable)
        XCTAssertTrue(badges.originalTextSegment.contains("The little black marker is with the badges too"))

        let rota = try XCTUnwrap(rows.first { $0.itemType.isActionable && $0.personName == "June" })
        XCTAssertTrue(rota.displayTitle.localizedCaseInsensitiveContains("final volunteer rota"), rota.displayTitle)
        XCTAssertTrue(rota.displayTitle.localizedCaseInsensitiveContains("Priya"), rota.displayTitle)
        XCTAssertFalse(rota.displayTitle.localizedCaseInsensitiveContains("Jonah"), rota.displayTitle)
        XCTAssertTrue(rota.originalTextSegment.contains("she has not said it is approved"))
        XCTAssertNil(rota.dueDate)
        let rotaID = rota.id
        XCTAssertFalse(rows.contains { $0.personName == "Jonah" })

        let idea = try XCTUnwrap(rows.first { $0.itemType == .idea })
        XCTAssertTrue(idea.belongsInMemory)
        XCTAssertNil(idea.dueDate)
        XCTAssertTrue(idea.originalTextSegment.contains("Keep that as an idea"))
        XCTAssertEqual(sign.captureSession?.originalTranscription, source)

        // The actual notification center, in the machine's own zone: no row
        // asked for an alert, so nothing is pending for any of them.
        await drainScheduler()
        for row in rows {
            let requests = await pendingRequests(for: row.id)
            XCTAssertTrue(requests.isEmpty, row.displayTitle)
        }

        NSTimeZone.default = calendar.timeZone
        let retry = try await repository.createCaptureResult(text: source, source: .inAppVoice,
            createdAt: anchor, schedulesReminders: true)
        NSTimeZone.default = previousZone
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        XCTAssertNil(retry.operationOutcome)
        let finalState = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), finalState)
        XCTAssertEqual(try allItems().filter { $0.captureSession?.id == captureID }.count, 6)
        XCTAssertEqual(try loadItem(withID: rotaID).personName, "June")
    }

    // MARK: Saved-item field revision

    private func seedRevisionItems(_ texts: [String], at time: Date) throws -> [String: UUID] {
        var ids: [String: UUID] = [:]
        for text in texts {
            let item = try repository.createCapture(text: text, source: .inAppText,
                                                    createdAt: time, schedulesReminder: false)
            ids[text] = item.id
        }
        return ids
    }

    private func stateSnapshot() throws -> [[String: Any]] {
        try LongCaptureQualificationTests.snapshot(container.mainContext)
    }

    private func rowSnapshot(_ id: UUID) throws -> [String: Any] {
        try XCTUnwrap(try stateSnapshot().first { ($0["id"] as? String) == id.uuidString })
    }

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    /// The person in the recipient role changes; nothing else on the item or
    /// in the store does. A retry and two relaunches change nothing further.
    func testSavedRecipientRevisionChangesOnlyThatFieldAcrossRetryAndRelaunch() async throws {
        let now = Date.now
        let ids = try seedRevisionItems(["Ask Maya for the vegetable box price", "Clean the fridge drawer"],
                                        at: now.addingTimeInterval(-7200))
        let target = try XCTUnwrap(ids["Ask Maya for the vegetable box price"])
        let other = try XCTUnwrap(ids["Clean the fridge drawer"])
        let before = try rowSnapshot(target)
        let otherBefore = try jsonData(try rowSnapshot(other))
        let source = "The vegetable box reminder from yesterday says to ask Maya for the price. "
            + "She is not handling orders this week. Change that same item so I ask Tessa for the price. "
            + "My reminder to clean the fridge drawer is unrelated and still needed."
        let created = try await repository.createCaptureResult(text: source, source: .inAppVoice,
            createdAt: now.addingTimeInterval(60), schedulesReminders: false)
        guard case .performed(.revise, let itemID, _)? = created.operationOutcome else {
            return XCTFail("expected a performed revision, got \(String(describing: created.operationOutcome))")
        }
        XCTAssertEqual(itemID, target)
        let after = try rowSnapshot(target)
        XCTAssertEqual(after["displayTitle"] as? String, "Ask Tessa for the vegetable box price")
        XCTAssertEqual(after["personName"] as? String, "Tessa")
        for key in ["createdAt", "dueDate", "reminderDate", "itemType", "category", "originalTextSegment",
                    "sessionID", "temporalIntent", "recurrenceRule", "locationIntent", "isCompleted", "priority"] {
            XCTAssertEqual(try jsonData([before[key] ?? NSNull()]), try jsonData([after[key] ?? NSNull()]), key)
        }
        XCTAssertEqual(try jsonData(try rowSnapshot(other)), otherBefore)
        // Forbidden effects: no second actionable Tessa row, no Maya row left.
        let rows = try allItems()
        XCTAssertFalse(rows.contains { $0.id != target && $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("Tessa") })
        XCTAssertFalse(rows.contains { $0.itemType.isActionable && $0.displayTitle.contains("Maya") })
        // The change is recorded on the capture that made it.
        let state = try XCTUnwrap(CaptureOperationState.read(from: created.session.operationStateData))
        XCTAssertEqual(state.phase, .performed)
        XCTAssertEqual(state.targetID, target)
        XCTAssertEqual(state.oldFieldValue, "Maya")
        XCTAssertEqual(state.newFieldValue, "Tessa")
        XCTAssertEqual(state.oldTitle, "Ask Maya for the vegetable box price")
        XCTAssertEqual(created.session.originalTranscription, source)
        let final = try jsonData(try stateSnapshot())
        let retry = try await repository.createCaptureResult(text: source, source: .inAppVoice,
            createdAt: now.addingTimeInterval(60), schedulesReminders: false)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(try jsonData(try stateSnapshot()), final)
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try jsonData(try stateSnapshot()), final)
    }

    /// A place change in a mixed capture: the saved pickup moves branch, the
    /// independent new purchase is created, and the unrelated item is untouched.
    func testSavedPlaceRevisionKeepsIndependentNewContent() async throws {
        let now = Date.now
        let ids = try seedRevisionItems(["Pick up the rental van at Central Depot", "Return the packing blankets to Ivo"],
                                        at: now.addingTimeInterval(-7200))
        let target = try XCTUnwrap(ids["Pick up the rental van at Central Depot"])
        let blankets = try XCTUnwrap(ids["Return the packing blankets to Ivo"])
        let blanketsBefore = try jsonData(try rowSnapshot(blankets))
        let source = "The rental van reminder has the wrong collection point; it still says Central Depot. "
            + "Please change the existing pickup item to the north branch on Keel Street. "
            + "Also buy packing tape tomorrow."
        let created = try await repository.createCaptureResult(text: source, source: .inAppVoice,
            createdAt: now.addingTimeInterval(60), schedulesReminders: false)
        guard case .performed(.revise, let itemID, _)? = created.operationOutcome else {
            return XCTFail("expected a performed revision, got \(String(describing: created.operationOutcome))")
        }
        XCTAssertEqual(itemID, target)
        XCTAssertEqual(try loadItem(withID: target).displayTitle, "Pick up the rental van at north branch on Keel Street")
        XCTAssertEqual(try jsonData(try rowSnapshot(blankets)), blanketsBefore)
        let rows = try allItems()
        XCTAssertTrue(rows.contains { $0.itemType.isActionable && $0.displayTitle.localizedCaseInsensitiveContains("packing tape") })
        XCTAssertFalse(rows.contains { $0.id != target && $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("van") })
    }

    /// A pending reminder on the revised item keeps its trigger; only the
    /// person changes. Checked against the real notification center.
    func testSavedRevisionKeepsThePendingReminder() async throws {
        try await requireNotificationAuthorization()
        let now = Date.now
        let seed = try repository.createCapture(text: "Remind me to ask Maya for the vegetable box price tomorrow at 9 AM",
                                                source: .inAppText, createdAt: now.addingTimeInterval(-7200),
                                                schedulesReminder: true)
        let target = seed.id
        await drainScheduler()
        let before = try rowSnapshot(target)
        let triggersBefore = await pendingRequests(for: target).map {
            String(describing: ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        }
        XCTAssertFalse(triggersBefore.isEmpty)
        let source = "The vegetable box reminder says to ask Maya for the price. Change that same reminder so I ask Tessa for the price."
        let created = try await repository.createCaptureResult(text: source, source: .inAppVoice,
            createdAt: now.addingTimeInterval(60), schedulesReminders: true)
        guard case .performed(.revise, let itemID, _)? = created.operationOutcome else {
            return XCTFail("expected a performed revision, got \(String(describing: created.operationOutcome))")
        }
        XCTAssertEqual(itemID, target)
        await drainScheduler()
        let after = try rowSnapshot(target)
        XCTAssertEqual(after["personName"] as? String, "Tessa")
        XCTAssertTrue((after["displayTitle"] as? String ?? "").contains("Tessa"))
        for key in ["dueDate", "reminderDate", "temporalIntent", "reminderTriggerKind"] {
            XCTAssertEqual(try jsonData([before[key] ?? NSNull()]), try jsonData([after[key] ?? NSNull()]), key)
        }
        let triggersAfter = await pendingRequests(for: target).map {
            String(describing: ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        }
        XCTAssertEqual(triggersAfter, triggersBefore)
    }


    /// Records the tagger this run actually has. Evidence, not a gate.
    func testTaggerAvailabilityIsRecorded() {
        let info = SentenceContext.taggerAvailability()
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let record = info.merging(["runtime": os,
                                   "simulator": ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device-or-host"]) { $1 }
        print("TAGGER-AVAILABILITY \(record)")
        let attachment = XCTAttachment(string: String(describing: record))
        attachment.name = "tagger-availability"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertNotNil(info["schemes"])
    }

    /// Every unsafe or unresolved form leaves all saved items byte-identical
    /// and never creates an actionable replacement; the request stays
    /// visible as a review row (or, for quoted/declined speech, as Memory).
    func testUnsafeSavedRevisionsChangeNothing() async throws {
        let cases: [(seeds: [String], source: String, label: String)] = [
            (["Ask Maya for the box price", "Ask Maya about the vegetable box delivery"],
             "The vegetable box reminder says to ask Maya. Change that same item so I ask Tessa instead.", "two similar targets"),
            ([], "The vegetable box reminder says to ask Maya. Change that same item so I ask Tessa instead.", "missing target"),
            (["Ask Maya for the vegetable box price"],
             "Sam said, 'Change that same item so I ask Tessa instead.' I am only noting what he said.", "quoted"),
            (["Ask Maya for the vegetable box price"],
             "The vegetable box reminder says to ask Maya. I do not want to change that same item so I ask Tessa.", "negated"),
            (["Ask Maya for the vegetable box price"],
             "The vegetable box reminder says to ask Maya. If she is away, change that same item so I ask Tessa.", "hypothetical"),
            (["Ask Maya for the vegetable box price"],
             "The vegetable box reminder says to ask Maya. Change that same item so I ask Tessa. Change the existing vegetable box reminder so I ask Priya.", "conflicting"),
            (["Deliver red toolbox to Evan"],
             "The delivery reminder is wrong. Change the existing delivery task to take the blue electrical kit to Evan instead.", "verb phrase is not a place"),
            (["Ask Jonah to tell Jonah's manager about the box"],
             "The box reminder says to ask Jonah. Change that same item so I ask Tessa.", "name in two roles"),
        ]
        for testCase in cases {
            try relaunchFresh()
            let now = Date.now
            _ = try seedRevisionItems(testCase.seeds, at: now.addingTimeInterval(-7200))
            let seedState = try jsonData(try stateSnapshot())
            let seedIDs = Set(try allItems().map(\.id))
            let created = try await repository.createCaptureResult(text: testCase.source, source: .inAppVoice,
                createdAt: now.addingTimeInterval(60), schedulesReminders: false)
            if case .performed? = created.operationOutcome { XCTFail("executed: \(testCase.label)") }
            let seedsAfter = try stateSnapshot().filter { seedIDs.contains(UUID(uuidString: $0["id"] as? String ?? "") ?? UUID()) }
            XCTAssertEqual(try jsonData(seedsAfter), seedState, testCase.label)
            let fresh = try allItems().filter { !seedIDs.contains($0.id) }
            XCTAssertFalse(fresh.contains { $0.itemType.isActionable && !$0.needsClarification
                && $0.displayTitle.localizedCaseInsensitiveContains("Tessa") }, testCase.label)
            XCTAssertFalse(fresh.isEmpty, "the request must stay visible: \(testCase.label)")
            XCTAssertEqual(created.session.originalTranscription, testCase.source)
        }
    }

    /// A target edited after the capture was spoken is newer than the
    /// capture's interpretation and keeps its edit; a deleted target is missing.
    func testStaleAndDeletedSavedRevisionTargetsAreHeld() async throws {
        let spokenAt = Date.now.addingTimeInterval(-600)
        let ids = try seedRevisionItems(["Ask Maya for the vegetable box price"], at: spokenAt.addingTimeInterval(-7200))
        let target = try XCTUnwrap(ids.values.first)
        let item = try loadItem(withID: target)
        try repository.update(item, with: ItemEdits(title: "Ask Maya for the medium box price", itemType: item.itemType,
            category: item.category, dueDate: item.dueDate, reminderDate: item.reminderDate, priority: item.priority,
            personName: item.personName, needsClarification: false))
        let edited = try jsonData(try rowSnapshot(target))
        let source = "The vegetable box reminder says to ask Maya. Change that same item so I ask Tessa."
        let stale = try await repository.createCaptureResult(text: source, source: .inAppVoice,
            createdAt: spokenAt, schedulesReminders: false)
        if case .performed? = stale.operationOutcome { XCTFail("a newer edit was overwritten") }
        XCTAssertEqual(try jsonData(try rowSnapshot(target)), edited)
        try repository.delete(try loadItem(withID: target))
        let deleted = try await repository.createCaptureResult(text: source + " Thanks.", source: .inAppVoice,
            createdAt: Date.now.addingTimeInterval(60), schedulesReminders: false)
        if case .performed? = deleted.operationOutcome { XCTFail("revised a deleted item") }
        XCTAssertFalse(try allItems().contains { $0.itemType.isActionable && !$0.needsClarification
            && $0.displayTitle.localizedCaseInsensitiveContains("Tessa") })
    }

    func testOriginalUnadoptedMessagePreservesSavedTargetsAcrossRetryAndRelaunch() async throws {
        let source = IntentConsolidationTests.clubEventLongCapture
        let anchor = Date.now
        for seed in ["Email Nora the receipt tomorrow at 8 PM", "Dentist appointment tomorrow at noon",
                     "Bring a mug tomorrow at 9 AM"] {
            _ = try repository.createCapture(text: seed, source: .inAppText,
                createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
        }
        let seedIDs = Set(try allItems().map { $0.id.uuidString })
        let before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        let created = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        let captureID = created.session.id
        let owner = try XCTUnwrap(created.items.first { $0.itemType == .note && $0.originalTextSegment.contains("Asha said") })
        XCTAssertTrue(owner.originalTextSegment.contains("I have not agreed to send that message."))
        XCTAssertTrue(owner.originalTextSegment.contains("I want to keep what she said as part of the event notes"))
        XCTAssertFalse(created.items.contains { $0.itemType.isActionable && $0.displayTitle.localizedCaseInsensitiveContains("keep what she said") })
        XCTAssertFalse(owner.needsClarification)
        XCTAssertNil(owner.reminderDate)
        XCTAssertFalse(created.items.contains { $0.itemType.isActionable && $0.displayTitle.hasPrefix("I have not agreed") })
        let rota = try XCTUnwrap(created.items.first { $0.itemType.isActionable && $0.personName == "June" })
        XCTAssertTrue(rota.displayTitle.localizedCaseInsensitiveContains("final volunteer rota"))
        XCTAssertTrue(rota.originalTextSegment.contains("email Jonah the final volunteer rota once Priya has approved it"))
        XCTAssertTrue(rota.originalTextSegment.contains("she has not said it is approved"))
        XCTAssertFalse(rota.needsClarification)
        XCTAssertNil(rota.reminderDate)
        XCTAssertEqual(created.session.originalTranscription, source)
        XCTAssertNil(created.operationOutcome)
        let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        let negative = "I have not agreed to cancel that appointment. Also buy bread."
        let protected = try await repository.createCaptureResult(text: negative, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        XCTAssertEqual(protected.session.originalTranscription, negative)
        XCTAssertNil(protected.operationOutcome)
        XCTAssertTrue(protected.items.contains { $0.itemType.isActionable && $0.displayTitle.localizedCaseInsensitiveContains("buy bread") })
        XCTAssertFalse(protected.items.contains { $0.itemType.isActionable && $0.displayTitle.hasPrefix("I have not agreed") })
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), before)
        let final = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), final)
    }

    func testOriginalTrainIdeaAndSeriesPersistWithoutChangingSavedTravelAcrossRetryAndRelaunch() async throws {
        let source = IntentConsolidationTests.trainIdeaLongCapture
        let anchor = Date.now
        for seed in ["Book the train tomorrow at 10 AM", "Download the actual ticket tomorrow at 8 PM", "Pack the camera tomorrow at 8 PM"] {
            _ = try repository.createCapture(text: seed, source: .inAppText,
                createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
        }
        let seedIDs = Set(try allItems().map { $0.id.uuidString })
        let before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        let created = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        let captureID = created.session.id
        let messages = created.items.filter { $0.itemType.isActionable && $0.displayTitle.hasPrefix("Text Sam") }
        XCTAssertEqual(messages.count, 1)
        let message = try XCTUnwrap(messages.first)
        XCTAssertTrue(message.originalTextSegment.contains("I have not picked a time to send that text."))
        XCTAssertTrue(message.originalTextSegment.contains("Ten is the departure time inside the message."))
        XCTAssertFalse(created.items.contains { $0.displayTitle.hasPrefix("Ten is the departure time") })
        XCTAssertNil(message.reminderDate)
        XCTAssertNil(message.dueDate)
        XCTAssertFalse(message.needsClarification)
        XCTAssertFalse(created.items.contains { $0.itemType.isActionable && $0.displayTitle.hasPrefix("I have not picked a time") })
        let ideas = created.items.filter { $0.itemType == .idea }
        XCTAssertEqual(ideas.count, 1)
        let idea = try XCTUnwrap(ideas.first)
        let ideaID = idea.id
        XCTAssertTrue(idea.belongsInMemory)
        XCTAssertFalse(idea.belongsInToday)
        XCTAssertFalse(idea.needsClarification)
        XCTAssertNil(idea.reminderDate)
        XCTAssertTrue(idea.originalTextSegment.contains("same station platform"))
        XCTAssertTrue(idea.originalTextSegment.contains("interesting series"))
        XCTAssertFalse(idea.originalTextSegment.contains("guest room key"))
        XCTAssertEqual(created.session.originalTranscription, source)
        XCTAssertNil(created.operationOutcome)
        let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), before)
        let final = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), final)
        XCTAssertEqual(try loadItem(withID: ideaID).captureSession?.originalTranscription, source)
    }

    func testGardenIdeaGroupingPersistsWithoutChangingSavedIdeasAcrossRetryAndRelaunch() async throws {
        let source = IntentConsolidationTests.gardenScatteredLongCapture
        let anchor = Date.now
        for seed in ["Keep this as an idea: painting labels for the pots", "Paint the fence tomorrow at 8 PM"] {
            _ = try repository.createCapture(text: seed, source: .inAppText,
                createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
        }
        let seedIDs = Set(try allItems().map { $0.id.uuidString })
        let before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        let created = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        let captureID = created.session.id
        let ideas = created.items.filter { $0.itemType == .idea }
        XCTAssertEqual(ideas.count, 1)
        let idea = try XCTUnwrap(ideas.first)
        let ideaID = idea.id
        XCTAssertTrue(idea.belongsInMemory)
        XCTAssertFalse(idea.belongsInToday)
        XCTAssertFalse(idea.needsClarification)
        XCTAssertNil(idea.dueDate)
        XCTAssertNil(idea.reminderDate)
        for words in ["painting little picture labels", "nice small project", "not decided to spend"] {
            XCTAssertTrue(idea.originalTextSegment.localizedCaseInsensitiveContains(words))
        }
        // Reaffirmation belongs to the ONE tray task; it is not another job.
        // Retain the historical broad-substring failure in frozen73 evidence.
        let trays=created.items.filter { $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("replace the cracked tray") }
        XCTAssertEqual(trays.count,1)
        XCTAssertTrue(trays.first?.originalTextSegment.localizedCaseInsensitiveContains("The tray replacement still stands") ?? false)
        XCTAssertTrue(trays.first?.originalTextSegment.localizedCaseInsensitiveContains("not withdrawn that job") ?? false)
        XCTAssertFalse(created.items.contains { $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("I know the last few sentences")
            && !$0.displayTitle.localizedCaseInsensitiveContains("replace the cracked tray") })
        XCTAssertEqual(created.session.originalTranscription, source)
        XCTAssertNil(created.operationOutcome)
        XCTAssertTrue(created.items.allSatisfy { PendingOperationStore.record(for: $0.id) == nil })
        let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), before)
        let final = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), final)
        XCTAssertEqual(try loadItem(withID: ideaID).captureSession?.originalTranscription, source)
    }

    func testOriginalGardenReturnOwnsItsDetailsWithoutChangingSavedWorkAcrossRelaunch() async throws {
        let source = IntentConsolidationTests.gardenScatteredLongCapture
        var anchor: Date!
        var seedIDs = Set<String>()
        var seedState: Data!
        var captureID = UUID()
        var returnID = UUID()
        try withFixtureClock { calendar in
            anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            for text in ["Return Mira's watering can on Friday", "Water the parsley tomorrow at 8 PM", "Buy mint tomorrow at 8 PM", "Replace the cracked tray on Tuesday"] {
                _ = try repository.createCapture(text: text, source: .inAppText,
                    createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
            }
            seedIDs = Set(try allItems().map { $0.id.uuidString })
            seedState = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
            let first = try repository.createCapture(text: source, source: .inAppText,
                createdAt: anchor, schedulesReminder: false)
            captureID = try XCTUnwrap(first.captureSession).id
            XCTAssertEqual(first.captureSession?.originalTranscription, source)
            let rows = try allItems().filter { $0.captureSession?.id == captureID }
            let trays = rows.filter { $0.itemType.isActionable && $0.displayTitle.localizedCaseInsensitiveContains("replace the cracked tray") }
            XCTAssertEqual(trays.count, 1)
            XCTAssertTrue(trays.first?.originalTextSegment.localizedCaseInsensitiveContains("Only the tray, not the plant or the pot") ?? false)
            XCTAssertFalse(trays.first?.needsClarification ?? true)
            let returns = rows.filter { $0.itemType.isActionable && $0.displayTitle.localizedCaseInsensitiveContains("return Mira") }
            XCTAssertEqual(returns.count, 1)
            let item = try XCTUnwrap(returns.first)
            returnID = item.id
            XCTAssertFalse(item.needsClarification)
            XCTAssertTrue(item.belongsInToday)
            XCTAssertEqual(item.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(item.temporalIntent?.time)
            XCTAssertTrue(item.originalTextSegment.localizedCaseInsensitiveContains("narrow spout"))
            XCTAssertTrue(item.originalTextSegment.localizedCaseInsensitiveContains("detachable rose"))
            XCTAssertFalse(item.originalTextSegment.localizedCaseInsensitiveContains("shed key"))
            XCTAssertTrue(rows.allSatisfy { PendingOperationStore.record(for: $0.id) == nil })
        }
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), seedState)
        let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        XCTAssertNil(retry.operationOutcome)
        let finalState = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), finalState)
        XCTAssertEqual(try loadItem(withID: returnID).captureSession?.originalTranscription, source)
        // Other wrong garden meanings remain independently scored; this is
        // complete persistence/ownership evidence for the demonstrated root.
    }

    func testConditionalNegativeCapturesPreserveSavedTargetsAcrossRetryAndRelaunch() async throws {
        for (seedText, source) in [
            ("Water the parsley tomorrow at 8 PM", "If it rains before tomorrow morning, skip watering the parsley. Otherwise water it tomorrow."),
            ("Nora appointment tomorrow at 8 PM", "Unless Nora confirms, cancel the appointment. Buy the envelopes."),
            ("Finish the draft tomorrow at 8 PM", "When I have checked the invoice, delete the draft task. Call Nora.")
        ] {
            var anchor: Date!
            var before: Data!
            var seedIDs = Set<String>()
            var captureID = UUID()
            try withFixtureClock { calendar in
                anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
                _ = try repository.createCapture(text: seedText, source: .inAppText,
                    createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
                seedIDs = Set(try allItems().map { $0.id.uuidString })
                before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
                let item = try repository.createCapture(text: source, source: .inAppText,
                    createdAt: anchor, schedulesReminder: false)
                captureID = try XCTUnwrap(item.captureSession).id
                XCTAssertEqual(item.captureSession?.originalTranscription, source)
                XCTAssertTrue(try allItems().filter { $0.captureSession?.id == captureID }
                    .allSatisfy { PendingOperationStore.record(for: $0.id) == nil })
            }
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
                .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), before)
            let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
                createdAt: anchor, schedulesReminders: false)
            XCTAssertTrue(retry.isDuplicate)
            XCTAssertEqual(retry.session.id, captureID)
            XCTAssertNil(retry.operationOutcome)
            let finalState = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
            try relaunch()
            try repository.recoverUnorganizedCaptures()
            try repository.recoverUnorganizedCaptures()
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), finalState)
            XCTAssertEqual(try allItems().first { $0.captureSession?.id == captureID }?.captureSession?.originalTranscription, source)
        }
    }

    func testOriginalLateWithdrawalKeepsOlderSavedRowsAndFullOutcomesAcrossRetryAndRelaunch() async throws {
        try await assertLocalWithdrawalPersistence(source: IntentConsolidationTests.studioWithdrawalLongCapture)
    }

    func testPunctuationLossWithdrawalKeepsOlderSavedRowsAndFullOutcomesAcrossRetryAndRelaunch() async throws {
        try await assertLocalWithdrawalPersistence(source: IntentConsolidationTests.studioWithdrawalPunctuationLoss)
    }

    private func assertLocalWithdrawalPersistence(source: String) async throws {
        var anchor: Date!
        var seedIDs = Set<String>()
        var seedsBefore: Data!
        var captureID = UUID()
        var finalState: Data!
        try withFixtureClock { calendar in
            anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            for oldText in ["Replace the cracked mug tomorrow at 8 PM", "Check the printer on Tuesday"] {
                _ = try repository.createCapture(text: oldText, source: .inAppText,
                    createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
            }
            seedIDs = Set(try allItems().map { $0.id.uuidString })
            seedsBefore = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
                .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys])
            let first = try repository.createCapture(text: source, source: .inAppText,
                createdAt: anchor, schedulesReminder: false)
            captureID = try XCTUnwrap(first.captureSession).id
            let current = try allItems().filter { $0.captureSession?.id == captureID }
            XCTAssertFalse(current.contains { $0.itemType.isActionable
                && $0.displayTitle.localizedCaseInsensitiveContains("replac")
                && $0.displayTitle.localizedCaseInsensitiveContains("mug") })
            XCTAssertTrue(current.contains { $0.itemType.isActionable
                && $0.originalTextSegment.localizedCaseInsensitiveContains("I need to check whether") })
            XCTAssertTrue(current.contains { $0.itemType.isActionable
                && $0.originalTextSegment.localizedCaseInsensitiveContains("Send Jules") })
            XCTAssertTrue(current.allSatisfy { PendingOperationStore.record(for: $0.id) == nil })
            XCTAssertEqual(first.captureSession?.originalTranscription, source)
        }
        let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        XCTAssertNil(retry.operationOutcome)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), seedsBefore)
        finalState = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), finalState)
        XCTAssertEqual(try allItems().first { $0.captureSession?.id == captureID }?.captureSession?.originalTranscription, source)
        // Remaining original fragments are still scored as wrong by the cohort;
        // this asserts the complete stored delta, not a whole-capture pass.
    }

#if DEBUG && canImport(FoundationModels)
    private final class NegativeStatusTrace:@unchecked Sendable {
        private let lock=NSLock();private var values:[String]=[]
        func append(_ value:String) { lock.lock();values.append(value);lock.unlock() }
        func text()->String { lock.lock();defer { lock.unlock() };return values.joined(separator:"\n") }
    }
    @available(iOS 26.4, *)
    func testCheckedNegativeStatusPurchaseThroughCurrentValidationSeededSaveRetryReopenAndDisplay() async throws {
        let seed = try repository.createCapture(text: "Buy a replacement mug tomorrow at 8 PM",
            source: .inAppText, createdAt: .now.addingTimeInterval(-60), schedulesReminder: false)
        let seedID = seed.id.uuidString
        let before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { $0["id"] as? String == seedID }, options: [.sortedKeys])
        let source = "Buy one replacement wide handle mug. I have not bought it yet."
        let anchor = Date.now
        // Independently checked complete CURRENT proposal, after generation.
        // One retained purchase, with its current non-completion state, and no
        // command to complete or modify the older saved purchase. Diagnostic only.
        let units=RuntimeIndexedSource(source)
        let proposed:[RuntimeFoundationInterpreter.IndexedItem]=[
            .init(evidence:Array(units.units.indices),purpose:.shopping,currentMeaning:"",directContact:"",needsReview:false)
        ]
        let context=RuntimeCaptureContext(savedItems:try allItems().map {
            .init(id:$0.id.uuidString,title:$0.displayTitle,modifiedAt:$0.lastModifiedAt,
                  originalText:$0.originalTextSegment,itemType:$0.itemType.rawValue,
                  personName:$0.personName,dueDate:$0.dueDate,reminderDate:$0.reminderDate,
                  isReviewed:$0.isReviewed,isArchived:$0.isArchived,isCompleted:$0.completedAt != nil,
                  snapshot:repository.atomicSnapshot($0))
        },hasHome:SavedPlaceStore.place(for:.home) != nil,hasWork:SavedPlaceStore.place(for:.work) != nil)
        let events=NegativeStatusTrace()
        let checked=RuntimeFoundationInterpreter.$developmentObserver.withValue({ events.append($0) }) {
            RuntimeFoundationInterpreter.validateIndexed(.init(items:proposed),source:source,units:units,
                referenceDate:anchor,calendar:.autoupdatingCurrent,
                rules:ThoughtExtractionEngine.extractWithRules(source,referenceDate:anchor,calendar:.autoupdatingCurrent),context:context)
        }
        let attachment=XCTAttachment(string:"CURRENT SOURCE:\n"+source+"\nINDEXED:\n"+units.prompt+"\nACTUAL CONTEXT:\n"+String(describing:context)+"\nPROPOSAL:\n"+String(describing:proposed)+"\nVALIDATION:\n"+String(describing:checked)+"\nEVENTS:\n"+events.text())
        attachment.lifetime = .keepAlways;add(attachment)
        let valid=try XCTUnwrap(checked,"FIRST FAILURE: downstream validation of checked purchase plus non-completion state")
        XCTAssertEqual(valid.items.count,1)
        XCTAssertEqual(valid.items.first?.organization.itemType,.shopping)
        XCTAssertEqual(valid.items.first?.sourceQuote,source)
        XCTAssertFalse(try XCTUnwrap(valid.items.first).needsReview)
        let created=try await RuntimeExampleTestFixtures.withInterpretation(valid) {
            try await repository.createCaptureResult(text:source,source:.inAppText,createdAt:anchor,schedulesReminders:false)
        }
        let row=try XCTUnwrap(created.items.first)
        XCTAssertTrue(row.belongsInToday);XCTAssertFalse(row.belongsInMemory)
        XCTAssertNil(row.dueDate);XCTAssertNil(row.reminderDate);XCTAssertNil(row.completedAt)
        let display=ItemPresentation.make(for:row,authorization:LocationAuthorization(status:.denied,isPrecise:true,isRegionMonitoringAvailable:true),now:anchor,calendar:.autoupdatingCurrent)
        XCTAssertNil(display.reviewRequirement)

        let captureID = created.session.id
        XCTAssertEqual(created.items.count, 1)
        XCTAssertEqual(created.items.first?.itemType, .shopping)
        XCTAssertEqual(created.session.originalTranscription, source)
        XCTAssertNil(created.operationOutcome)
        XCTAssertTrue(created.items.allSatisfy { !$0.needsClarification && PendingOperationStore.record(for: $0.id) == nil })
        let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { $0["id"] as? String == seedID }, options: [.sortedKeys]), before)
        let final = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), final)
        XCTAssertEqual(try allItems().filter { $0.captureSession?.id == captureID }.count, 1)
        XCTAssertEqual(try allItems().first { $0.captureSession?.id == captureID }?.captureSession?.originalTranscription, source)
    }

    @available(iOS 26.4, *)
    func testObservedNegativeStatusDefaultCaptureKeepsOriginalAssertions() async throws {
        let seed = try repository.createCapture(text: "Buy a replacement mug tomorrow at 8 PM",
            source: .inAppText, createdAt: .now.addingTimeInterval(-60), schedulesReminder: false)
        let seedID = seed.id.uuidString
        let before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { $0["id"] as? String == seedID }, options: [.sortedKeys])
        let source = "Buy one replacement wide handle mug. I have not bought it yet."
        let anchor = Date.now
        let events=NegativeStatusTrace()
        defer {
            let attachment=XCTAttachment(string:"CURRENT SOURCE:\n"+source+"\nCLOCK:\n"+anchor.ISO8601Format()+"\nTRACE:\n"+events.text())
            attachment.lifetime = .keepAlways;add(attachment)
        }
        let created=try await RuntimeExampleLibrary.$developmentObserver.withValue({ events.append($0) }) {
            try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ events.append($0) }) {
                try await repository.createCaptureResult(text:source,source:.inAppText,createdAt:anchor,schedulesReminders:false)
            }
        }
        events.append("ACTUAL SAVED ROWS "+String(describing:created.items.map { ($0.itemType,$0.displayTitle,$0.originalTextSegment,$0.needsClarification,$0.completedAt,$0.dueDate,$0.reminderDate) }))

        let captureID = created.session.id
        XCTAssertEqual(created.items.count, 1)
        XCTAssertEqual(created.items.first?.itemType, .shopping)
        XCTAssertEqual(created.session.originalTranscription, source)
        XCTAssertNil(created.operationOutcome)
        XCTAssertTrue(created.items.allSatisfy { !$0.needsClarification && PendingOperationStore.record(for: $0.id) == nil })
        let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { $0["id"] as? String == seedID }, options: [.sortedKeys]), before)
        let final = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), final)
        XCTAssertEqual(try allItems().filter { $0.captureSession?.id == captureID }.count, 1)
        XCTAssertEqual(try allItems().first { $0.captureSession?.id == captureID }?.captureSession?.originalTranscription, source)
    }

    @available(iOS 26.4, *)
    func testObservedCurrentCanonicalClubEventSavesItsSixMeaningsAcrossRetryAndRelaunch() async throws {
        let observer=NegativeStatusTrace()
        defer {
            let attachment=XCTAttachment(string:"ORIGINAL CASE testCanonicalClubEventSavesItsSixMeaningsAcrossRetryAndRelaunch\nTRACE:\n"+observer.text())
            attachment.lifetime = .keepAlways;add(attachment)
        }

        let source = IntentConsolidationTests.clubEventLongCapture
        XCTAssertTrue(try allItems().isEmpty)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: Self.fixtureTimeZoneIdentifier)!
        let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
        let dueDays = ["sign": makeDate(year: 2026, month: 10, day: 9, calendar: calendar),
                       "caretaker": makeDate(year: 2026, month: 10, day: 6, calendar: calendar)]
        // Pin the zone for parsing only, through the shipping async path.
        let previousZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        let created = try await RuntimeExampleLibrary.$developmentObserver.withValue({ observer.append($0) }) {
            try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ observer.append($0) }) {
                try await repository.createCaptureResult(text: source, source: .inAppVoice,
            createdAt: anchor, schedulesReminders: true)
            }
        }
        NSTimeZone.default = previousZone
        let captureID = created.session.id
        XCTAssertNil(created.operationOutcome)
        let rows = try allItems().filter { $0.captureSession?.id == captureID }
        let summary = rows.map { "\($0.itemType.rawValue): \($0.displayTitle)" }.joined(separator: " | ")
        XCTAssertEqual(rows.count, 6, summary)
        XCTAssertTrue(rows.allSatisfy { !$0.needsClarification && $0.reminderDate == nil }, summary)
        XCTAssertTrue(rows.allSatisfy { PendingOperationStore.record(for: $0.id) == nil })

        let sign = try XCTUnwrap(rows.first { $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("direction sign") }, summary)
        XCTAssertTrue(sign.belongsInToday)
        XCTAssertEqual(sign.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 9))
        XCTAssertNil(sign.temporalIntent?.time)
        XCTAssertEqual(sign.dueDate, dueDays["sign"])
        XCTAssertTrue(sign.displayTitle.localizedCaseInsensitiveContains("before the event starts at six"), sign.displayTitle)
        XCTAssertTrue(sign.originalTextSegment.contains("Use the bigger type version."))
        XCTAssertTrue(sign.originalTextSegment.contains("Last time people kept trying the front doors"))

        let account = try XCTUnwrap(rows.first { $0.originalTextSegment.contains("Asha said") })
        XCTAssertFalse(account.itemType.isActionable)
        XCTAssertTrue(account.belongsInMemory)
        XCTAssertTrue(account.originalTextSegment.contains("I have not agreed to send that message."))

        let caretaker = try XCTUnwrap(rows.first { $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("caretaker") })
        XCTAssertEqual(caretaker.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
        XCTAssertEqual(caretaker.dueDate, dueDays["caretaker"])
        XCTAssertTrue(caretaker.originalTextSegment.contains("before anybody sends a confident message"))

        let badges = try XCTUnwrap(rows.first { $0.displayTitle.localizedCaseInsensitiveContains("name badges") })
        XCTAssertTrue(badges.belongsInMemory)
        XCTAssertFalse(badges.itemType.isActionable)
        XCTAssertTrue(badges.originalTextSegment.contains("The little black marker is with the badges too"))

        let rota = try XCTUnwrap(rows.first { $0.itemType.isActionable && $0.personName == "June" })
        XCTAssertTrue(rota.displayTitle.localizedCaseInsensitiveContains("final volunteer rota"), rota.displayTitle)
        XCTAssertTrue(rota.displayTitle.localizedCaseInsensitiveContains("Priya"), rota.displayTitle)
        XCTAssertFalse(rota.displayTitle.localizedCaseInsensitiveContains("Jonah"), rota.displayTitle)
        XCTAssertTrue(rota.originalTextSegment.contains("she has not said it is approved"))
        XCTAssertNil(rota.dueDate)
        let rotaID = rota.id
        XCTAssertFalse(rows.contains { $0.personName == "Jonah" })

        let idea = try XCTUnwrap(rows.first { $0.itemType == .idea })
        XCTAssertTrue(idea.belongsInMemory)
        XCTAssertNil(idea.dueDate)
        XCTAssertTrue(idea.originalTextSegment.contains("Keep that as an idea"))
        XCTAssertEqual(sign.captureSession?.originalTranscription, source)

        // The actual notification center, in the machine's own zone: no row
        // asked for an alert, so nothing is pending for any of them.
        await drainScheduler()
        for row in rows {
            let requests = await pendingRequests(for: row.id)
            XCTAssertTrue(requests.isEmpty, row.displayTitle)
        }

        NSTimeZone.default = calendar.timeZone
        let retry = try await RuntimeExampleLibrary.$developmentObserver.withValue({ observer.append($0) }) {
            try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ observer.append($0) }) {
                try await repository.createCaptureResult(text: source, source: .inAppVoice,
            createdAt: anchor, schedulesReminders: true)
            }
        }
        NSTimeZone.default = previousZone
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        XCTAssertNil(retry.operationOutcome)
        let finalState = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), finalState)
        XCTAssertEqual(try allItems().filter { $0.captureSession?.id == captureID }.count, 6)
        XCTAssertEqual(try loadItem(withID: rotaID).personName, "June")
    }

    // MARK: Saved-item field revision


    @available(iOS 26.4, *)
    func testObservedCurrentDeniedOperationComplementKeepsSavedTargetAndActualNotificationAcrossRetry() async throws {
        let observer=NegativeStatusTrace()
        defer {
            let attachment=XCTAttachment(string:"ORIGINAL CASE testDeniedOperationComplementKeepsSavedTargetAndActualNotificationAcrossRetry\nTRACE:\n"+observer.text())
            attachment.lifetime = .keepAlways;add(attachment)
        }

        try await requireNotificationAuthorization()
        let seed = try repository.createCapture(
            text: "Remind me to attend Nora's appointment tomorrow at 8 PM",
            source: .inAppText, createdAt: .now, schedulesReminder: true)
        let seedID = seed.id
        await drainScheduler()
        let requestsBefore = await pendingRequests(for: seedID)
        XCTAssertEqual(requestsBefore.count, 1, "the protected old target must have a real pending effect")
        @MainActor func seedState() throws -> Data {
            try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
                .filter { $0["id"] as? String == seedID.uuidString }, options: [.sortedKeys])
        }
        let before = try seedState()
        let source = "I am correcting this recording not asking you to call Nora and cancel her appointment but I will wash the windows and clean the kitchen."
        let anchor = Date.now
        let created = try await RuntimeExampleLibrary.$developmentObserver.withValue({ observer.append($0) }) {
            try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ observer.append($0) }) {
                try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: true)
            }
        }
        let captureID = created.session.id
        let createdCount = created.items.count
        XCTAssertNil(created.operationOutcome)
        XCTAssertTrue(created.items.allSatisfy { PendingOperationStore.record(for: $0.id) == nil })
        XCTAssertTrue(created.items.contains { $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("wash the windows") })
        XCTAssertEqual(created.session.originalTranscription, source)
        let retry = try await RuntimeExampleLibrary.$developmentObserver.withValue({ observer.append($0) }) {
            try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ observer.append($0) }) {
                try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: true)
            }
        }
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        await drainScheduler()
        XCTAssertEqual(try seedState(), before)
        try relaunch()
        repository.reconcilePendingReminders()
        await drainScheduler()
        XCTAssertEqual(try seedState(), before)
        let after = await pendingRequests(for: seedID)
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.identifier, requestsBefore.first?.identifier)
        XCTAssertEqual(after.first?.content.title, requestsBefore.first?.content.title)
        XCTAssertEqual(after.first?.content.body, requestsBefore.first?.content.body)
        XCTAssertEqual((after.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents,
                       (requestsBefore.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        XCTAssertEqual(try allItems().filter { $0.captureSession?.id == captureID }.count, createdCount)
    }


    @available(iOS 26.4, *)
    func testObservedCurrentGardenIdeaGroupingPersistsWithoutChangingSavedIdeasAcrossRetryAndRelaunch() async throws {
        let observer=NegativeStatusTrace()
        defer {
            let attachment=XCTAttachment(string:"ORIGINAL CASE testGardenIdeaGroupingPersistsWithoutChangingSavedIdeasAcrossRetryAndRelaunch\nTRACE:\n"+observer.text())
            attachment.lifetime = .keepAlways;add(attachment)
        }

        let source = IntentConsolidationTests.gardenScatteredLongCapture
        let anchor = Date.now
        for seed in ["Keep this as an idea: painting labels for the pots", "Paint the fence tomorrow at 8 PM"] {
            _ = try repository.createCapture(text: seed, source: .inAppText,
                createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
        }
        let seedIDs = Set(try allItems().map { $0.id.uuidString })
        let before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        let created = try await RuntimeExampleLibrary.$developmentObserver.withValue({ observer.append($0) }) {
            try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ observer.append($0) }) {
                try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
            }
        }
        let captureID = created.session.id
        let ideas = created.items.filter { $0.itemType == .idea }
        XCTAssertEqual(ideas.count, 1)
        let idea = try XCTUnwrap(ideas.first)
        let ideaID = idea.id
        XCTAssertTrue(idea.belongsInMemory)
        XCTAssertFalse(idea.belongsInToday)
        XCTAssertFalse(idea.needsClarification)
        XCTAssertNil(idea.dueDate)
        XCTAssertNil(idea.reminderDate)
        for words in ["painting little picture labels", "nice small project", "not decided to spend"] {
            XCTAssertTrue(idea.originalTextSegment.localizedCaseInsensitiveContains(words))
        }
        // Reaffirmation belongs to the ONE tray task; it is not another job.
        // Retain the historical broad-substring failure in frozen73 evidence.
        let trays=created.items.filter { $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("replace the cracked tray") }
        XCTAssertEqual(trays.count,1)
        XCTAssertTrue(trays.first?.originalTextSegment.localizedCaseInsensitiveContains("The tray replacement still stands") ?? false)
        XCTAssertTrue(trays.first?.originalTextSegment.localizedCaseInsensitiveContains("not withdrawn that job") ?? false)
        XCTAssertFalse(created.items.contains { $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("I know the last few sentences")
            && !$0.displayTitle.localizedCaseInsensitiveContains("replace the cracked tray") })
        XCTAssertEqual(created.session.originalTranscription, source)
        XCTAssertNil(created.operationOutcome)
        XCTAssertTrue(created.items.allSatisfy { PendingOperationStore.record(for: $0.id) == nil })
        let retry = try await RuntimeExampleLibrary.$developmentObserver.withValue({ observer.append($0) }) {
            try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ observer.append($0) }) {
                try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
            }
        }
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), before)
        let final = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), final)
        XCTAssertEqual(try loadItem(withID: ideaID).captureSession?.originalTranscription, source)
    }


    @available(iOS 26.4, *)
    func testObservedCurrentOriginalTrainIdeaAndSeriesPersistWithoutChangingSavedTravelAcrossRetryAndRelaunch() async throws {
        let observer=NegativeStatusTrace()
        defer {
            let attachment=XCTAttachment(string:"ORIGINAL CASE testOriginalTrainIdeaAndSeriesPersistWithoutChangingSavedTravelAcrossRetryAndRelaunch\nTRACE:\n"+observer.text())
            attachment.lifetime = .keepAlways;add(attachment)
        }

        let source = IntentConsolidationTests.trainIdeaLongCapture
        let anchor = Date.now
        for seed in ["Book the train tomorrow at 10 AM", "Download the actual ticket tomorrow at 8 PM", "Pack the camera tomorrow at 8 PM"] {
            _ = try repository.createCapture(text: seed, source: .inAppText,
                createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
        }
        let seedIDs = Set(try allItems().map { $0.id.uuidString })
        let before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        let created = try await RuntimeExampleLibrary.$developmentObserver.withValue({ observer.append($0) }) {
            try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ observer.append($0) }) {
                try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
            }
        }
        let captureID = created.session.id
        let messages = created.items.filter { $0.itemType.isActionable && $0.displayTitle.hasPrefix("Text Sam") }
        XCTAssertEqual(messages.count, 1)
        let message = try XCTUnwrap(messages.first)
        XCTAssertTrue(message.originalTextSegment.contains("I have not picked a time to send that text."))
        XCTAssertTrue(message.originalTextSegment.contains("Ten is the departure time inside the message."))
        XCTAssertFalse(created.items.contains { $0.displayTitle.hasPrefix("Ten is the departure time") })
        XCTAssertNil(message.reminderDate)
        XCTAssertNil(message.dueDate)
        XCTAssertFalse(message.needsClarification)
        XCTAssertFalse(created.items.contains { $0.itemType.isActionable && $0.displayTitle.hasPrefix("I have not picked a time") })
        let ideas = created.items.filter { $0.itemType == .idea }
        XCTAssertEqual(ideas.count, 1)
        let idea = try XCTUnwrap(ideas.first)
        let ideaID = idea.id
        XCTAssertTrue(idea.belongsInMemory)
        XCTAssertFalse(idea.belongsInToday)
        XCTAssertFalse(idea.needsClarification)
        XCTAssertNil(idea.reminderDate)
        XCTAssertTrue(idea.originalTextSegment.contains("same station platform"))
        XCTAssertTrue(idea.originalTextSegment.contains("interesting series"))
        XCTAssertFalse(idea.originalTextSegment.contains("guest room key"))
        XCTAssertEqual(created.session.originalTranscription, source)
        XCTAssertNil(created.operationOutcome)
        let retry = try await RuntimeExampleLibrary.$developmentObserver.withValue({ observer.append($0) }) {
            try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ observer.append($0) }) {
                try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
            }
        }
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), before)
        let final = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), final)
        XCTAssertEqual(try loadItem(withID: ideaID).captureSession?.originalTranscription, source)
    }


    @available(iOS 26.4, *)
    func testObservedCurrentOriginalUnadoptedMessagePreservesSavedTargetsAcrossRetryAndRelaunch() async throws {
        let observer=NegativeStatusTrace()
        defer {
            let attachment=XCTAttachment(string:"ORIGINAL CASE testOriginalUnadoptedMessagePreservesSavedTargetsAcrossRetryAndRelaunch\nTRACE:\n"+observer.text())
            attachment.lifetime = .keepAlways;add(attachment)
        }

        let source = IntentConsolidationTests.clubEventLongCapture
        let anchor = Date.now
        for seed in ["Email Nora the receipt tomorrow at 8 PM", "Dentist appointment tomorrow at noon",
                     "Bring a mug tomorrow at 9 AM"] {
            _ = try repository.createCapture(text: seed, source: .inAppText,
                createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
        }
        let seedIDs = Set(try allItems().map { $0.id.uuidString })
        let before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        let created = try await RuntimeExampleLibrary.$developmentObserver.withValue({ observer.append($0) }) {
            try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ observer.append($0) }) {
                try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
            }
        }
        let captureID = created.session.id
        let owner = try XCTUnwrap(created.items.first { $0.itemType == .note && $0.originalTextSegment.contains("Asha said") })
        XCTAssertTrue(owner.originalTextSegment.contains("I have not agreed to send that message."))
        XCTAssertTrue(owner.originalTextSegment.contains("I want to keep what she said as part of the event notes"))
        XCTAssertFalse(created.items.contains { $0.itemType.isActionable && $0.displayTitle.localizedCaseInsensitiveContains("keep what she said") })
        XCTAssertFalse(owner.needsClarification)
        XCTAssertNil(owner.reminderDate)
        XCTAssertFalse(created.items.contains { $0.itemType.isActionable && $0.displayTitle.hasPrefix("I have not agreed") })
        let rota = try XCTUnwrap(created.items.first { $0.itemType.isActionable && $0.personName == "June" })
        XCTAssertTrue(rota.displayTitle.localizedCaseInsensitiveContains("final volunteer rota"))
        XCTAssertTrue(rota.originalTextSegment.contains("email Jonah the final volunteer rota once Priya has approved it"))
        XCTAssertTrue(rota.originalTextSegment.contains("she has not said it is approved"))
        XCTAssertFalse(rota.needsClarification)
        XCTAssertNil(rota.reminderDate)
        XCTAssertEqual(created.session.originalTranscription, source)
        XCTAssertNil(created.operationOutcome)
        let retry = try await RuntimeExampleLibrary.$developmentObserver.withValue({ observer.append($0) }) {
            try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ observer.append($0) }) {
                try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
            }
        }
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        let negative = "I have not agreed to cancel that appointment. Also buy bread."
        let protected = try await RuntimeExampleLibrary.$developmentObserver.withValue({ observer.append($0) }) {
            try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ observer.append($0) }) {
                try await repository.createCaptureResult(text: negative, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
            }
        }
        XCTAssertEqual(protected.session.originalTranscription, negative)
        XCTAssertNil(protected.operationOutcome)
        XCTAssertTrue(protected.items.contains { $0.itemType.isActionable && $0.displayTitle.localizedCaseInsensitiveContains("buy bread") })
        XCTAssertFalse(protected.items.contains { $0.itemType.isActionable && $0.displayTitle.hasPrefix("I have not agreed") })
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), before)
        let final = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), final)
    }

    @available(iOS 26.4, *)
    func testCheckedDeniedRequestAndOwnChoresThroughCurrentValidationSaveNotificationRetryAndReopen() async throws {
        try await requireNotificationAuthorization()
        let seed = try repository.createCapture(
            text: "Remind me to attend Nora's appointment tomorrow at 8 PM",
            source: .inAppText, createdAt: .now, schedulesReminder: true)
        let seedID = seed.id
        await drainScheduler()
        let requestsBefore = await pendingRequests(for: seedID)
        XCTAssertEqual(requestsBefore.count, 1, "the protected old target must have a real pending effect")
        @MainActor func seedState() throws -> Data {
            try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
                .filter { $0["id"] as? String == seedID.uuidString }, options: [.sortedKeys])
        }
        let before = try seedState()
        let source = "I am correcting this recording not asking you to call Nora and cancel her appointment but I will wash the windows and clean the kitchen."
        let anchor = Date.now
        // Correct CURRENT semantic proposal checked independently after
        // generation: clear recording denial and two separately adopted own
        // chores. No invented contact, operation, date or review is supplied.
        let units=RuntimeIndexedSource(source)
        XCTAssertEqual(units.units.count,1)
        let denied="I am correcting this recording not asking you to call Nora and cancel her appointment"
        let proposed:[RuntimeFoundationInterpreter.IndexedItem]=[
            .init(evidence:[0],anchor:denied,purpose:.note,currentMeaning:denied,directContact:"",needsReview:false),
            .init(evidence:[0],anchor:"wash the windows",purpose:.task,currentMeaning:"wash the windows",directContact:"",needsReview:false),
            .init(evidence:[0],anchor:"clean the kitchen",purpose:.task,currentMeaning:"clean the kitchen",directContact:"",needsReview:false)
        ]
        let actualContext=RuntimeCaptureContext(savedItems:try allItems().map {
            .init(id:$0.id.uuidString,title:$0.displayTitle,modifiedAt:$0.lastModifiedAt,
                  originalText:$0.originalTextSegment,itemType:$0.itemType.rawValue,
                  personName:$0.personName,dueDate:$0.dueDate,reminderDate:$0.reminderDate,
                  isReviewed:$0.isReviewed,isArchived:$0.isArchived,isCompleted:$0.completedAt != nil,
                  snapshot:repository.atomicSnapshot($0))
        },hasHome:SavedPlaceStore.place(for:.home) != nil,hasWork:SavedPlaceStore.place(for:.work) != nil)
        let events=NegativeStatusTrace()
        let checked=RuntimeFoundationInterpreter.$developmentObserver.withValue({ events.append($0) }) {
            RuntimeFoundationInterpreter.validateIndexed(.init(items:proposed),source:source,units:units,
                referenceDate:anchor,calendar:.autoupdatingCurrent,
                rules:ThoughtExtractionEngine.extractWithRules(source,referenceDate:anchor,calendar:.autoupdatingCurrent),context:actualContext)
        }
        let attachment=XCTAttachment(string:"CHECKED CURRENT SOURCE:\n"+source+"\nACTUAL CLOCK:\n"+anchor.ISO8601Format()+"\nACTUAL CONTEXT:\n"+String(describing:actualContext)+"\nPROPOSAL:\n"+String(describing:proposed)+"\nVALIDATION:\n"+String(describing:checked)+"\nEVENTS:\n"+events.text())
        attachment.lifetime = .keepAlways;add(attachment)
        let valid=try XCTUnwrap(checked,"FIRST FAILURE: actual validation of complete independently checked denied-request/own-chores proposal")
        XCTAssertEqual(valid.items.map(\.organization.itemType),[.note,.task,.task])
        XCTAssertTrue(valid.items.allSatisfy { !$0.needsReview && $0.organization.personName == nil && $0.organization.dueDate == nil && $0.organization.reminderDate == nil && $0.organization.reminderDelivery == .none && $0.organization.locationIntent == nil && $0.organization.recurrenceRule == nil })
        let created=try await RuntimeExampleTestFixtures.withInterpretation(valid) {
            try await repository.createCaptureResult(text:source,source:.inAppText,createdAt:anchor,schedulesReminders:true)
        }
        XCTAssertEqual(created.items.count,3)
        XCTAssertTrue(created.items[0].belongsInMemory);XCTAssertFalse(created.items[0].belongsInToday)
        for row in created.items {
            let display=ItemPresentation.make(for:row,authorization:LocationAuthorization(status:.denied,isPrecise:true,isRegionMonitoringAvailable:true),now:anchor,calendar:.autoupdatingCurrent)
            XCTAssertNil(display.reviewRequirement)
        }

        let captureID = created.session.id
        let createdCount = created.items.count
        XCTAssertNil(created.operationOutcome)
        XCTAssertTrue(created.items.allSatisfy { PendingOperationStore.record(for: $0.id) == nil })
        XCTAssertTrue(created.items.contains { $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("wash the windows") })
        XCTAssertEqual(created.session.originalTranscription, source)
        let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: true)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        await drainScheduler()
        XCTAssertEqual(try seedState(), before)
        try relaunch()
        repository.reconcilePendingReminders()
        await drainScheduler()
        XCTAssertEqual(try seedState(), before)
        let after = await pendingRequests(for: seedID)
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.identifier, requestsBefore.first?.identifier)
        XCTAssertEqual(after.first?.content.title, requestsBefore.first?.content.title)
        XCTAssertEqual(after.first?.content.body, requestsBefore.first?.content.body)
        XCTAssertEqual((after.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents,
                       (requestsBefore.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        XCTAssertEqual(try allItems().filter { $0.captureSession?.id == captureID }.count, createdCount)
    }

    @available(iOS 26.4, *)
    func testCheckedSeededClubWholeCurrentMeaningThroughValidationSaveDisplayRetryAndReopen() async throws {
        let source = IntentConsolidationTests.clubEventLongCapture
        let anchor = Date.now
        for seed in ["Email Nora the receipt tomorrow at 8 PM", "Dentist appointment tomorrow at noon",
                     "Bring a mug tomorrow at 9 AM"] {
            _ = try repository.createCapture(text: seed, source: .inAppText,
                createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
        }
        let seedIDs = Set(try allItems().map { $0.id.uuidString })
        let before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        // Independently checked complete six-meaning proposal from the
        // prior empty-context diagnostic, revalidated at THIS actual clock
        // and against THIS actual saved-state context before saving.
        let units=RuntimeIndexedSource(source)
        let beginnings=["I am thinking about the club event","Asha said,","My own task is to ask the caretaker","The spare name badges","And email Jonah","There is also an idea"]
        let starts=try beginnings.map { prefix in try XCTUnwrap(units.units.firstIndex { $0.text.hasPrefix(prefix) },prefix) }
        XCTAssertEqual(starts.sorted(),starts);XCTAssertEqual(starts.first,0)
        let groups=starts.indices.map { index in Array(starts[index]..<(index+1 < starts.count ? starts[index+1] : units.units.count)) }
        XCTAssertEqual(groups.flatMap { $0 },Array(units.units.indices))
        let proposed:[RuntimeFoundationInterpreter.IndexedItem]=[
            .init(evidence:groups[0],purpose:.task,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:groups[1],purpose:.note,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:groups[2],purpose:.task,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:groups[3],purpose:.note,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:groups[4],purpose:.task,currentMeaning:"Email June the final volunteer rota once Priya has approved it.",directContact:"June",needsReview:false),
            .init(evidence:groups[5],purpose:.idea,currentMeaning:"",directContact:"",needsReview:false)
        ]
        func actualContext() throws -> RuntimeCaptureContext {
            RuntimeCaptureContext(savedItems:try allItems().map {
                .init(id:$0.id.uuidString,title:$0.displayTitle,modifiedAt:$0.lastModifiedAt,
                    originalText:$0.originalTextSegment,itemType:$0.itemType.rawValue,
                    personName:$0.personName,dueDate:$0.dueDate,reminderDate:$0.reminderDate,
                    isReviewed:$0.isReviewed,isArchived:$0.isArchived,isCompleted:$0.completedAt != nil,
                    snapshot:repository.atomicSnapshot($0))
            },hasHome:SavedPlaceStore.place(for:.home) != nil,hasWork:SavedPlaceStore.place(for:.work) != nil)
        }
        let context=try actualContext(),events=NegativeStatusTrace()
        let checked=RuntimeFoundationInterpreter.$developmentObserver.withValue({ events.append($0) }) {
            RuntimeFoundationInterpreter.validateIndexed(.init(items:proposed),source:source,units:units,
                referenceDate:anchor,calendar:.autoupdatingCurrent,
                rules:ThoughtExtractionEngine.extractWithRules(source,referenceDate:anchor,calendar:.autoupdatingCurrent),context:context)
        }
        let evidence=XCTAttachment(string:"CHECKED CURRENT SOURCE:\n"+source+"\nACTUAL CLOCK:\n"+anchor.ISO8601Format()+"\nACTUAL CONTEXT:\n"+String(describing:context)+"\nINDEXED:\n"+units.prompt+"\nPROPOSAL:\n"+String(describing:proposed)+"\nVALIDATION:\n"+String(describing:checked)+"\nEVENTS:\n"+events.text())
        evidence.lifetime = .keepAlways;add(evidence)
        let valid=try XCTUnwrap(checked,"FIRST FAILURE: actual seeded-context validation of complete independently checked Club six-meaning proposal")
        XCTAssertEqual(valid.items.count,6)
        let created=try await RuntimeExampleTestFixtures.withInterpretation(valid) {
            try await repository.createCaptureResult(text:source,source:.inAppText,createdAt:anchor,schedulesReminders:false)
        }
        for row in created.items {
            let display=ItemPresentation.make(for:row,authorization:LocationAuthorization(status:.denied,isPrecise:true,isRegionMonitoringAvailable:true),now:anchor,calendar:.autoupdatingCurrent)
            XCTAssertNil(display.reviewRequirement)
        }

        let captureID = created.session.id
        let owner = try XCTUnwrap(created.items.first { $0.itemType == .note && $0.originalTextSegment.contains("Asha said") })
        XCTAssertTrue(owner.originalTextSegment.contains("I have not agreed to send that message."))
        XCTAssertTrue(owner.originalTextSegment.contains("I want to keep what she said as part of the event notes"))
        XCTAssertFalse(created.items.contains { $0.itemType.isActionable && $0.displayTitle.localizedCaseInsensitiveContains("keep what she said") })
        XCTAssertFalse(owner.needsClarification)
        XCTAssertNil(owner.reminderDate)
        XCTAssertFalse(created.items.contains { $0.itemType.isActionable && $0.displayTitle.hasPrefix("I have not agreed") })
        let rota = try XCTUnwrap(created.items.first { $0.itemType.isActionable && $0.personName == "June" })
        XCTAssertTrue(rota.displayTitle.localizedCaseInsensitiveContains("final volunteer rota"))
        XCTAssertTrue(rota.originalTextSegment.contains("email Jonah the final volunteer rota once Priya has approved it"))
        XCTAssertTrue(rota.originalTextSegment.contains("she has not said it is approved"))
        XCTAssertFalse(rota.needsClarification)
        XCTAssertNil(rota.reminderDate)
        XCTAssertEqual(created.session.originalTranscription, source)
        XCTAssertNil(created.operationOutcome)
        let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        let negative = "I have not agreed to cancel that appointment. Also buy bread."
        // Reconcile the second negative saved-operation complement against
        // the NEW actual context too. No model or retrieval is evaluated here.
        let negativeUnits=RuntimeIndexedSource(negative),negativeContext=try actualContext()
        XCTAssertEqual(negativeUnits.units.count,2)
        let negativePlan:[RuntimeFoundationInterpreter.IndexedItem]=[
            .init(evidence:[0],purpose:.note,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:[1],purpose:.shopping,currentMeaning:"",directContact:"",needsReview:false)
        ]
        let negativeChecked=RuntimeFoundationInterpreter.validateIndexed(.init(items:negativePlan),source:negative,units:negativeUnits,
            referenceDate:anchor,calendar:.autoupdatingCurrent,
            rules:ThoughtExtractionEngine.extractWithRules(negative,referenceDate:anchor,calendar:.autoupdatingCurrent),context:negativeContext)
        let checkedNegative=try XCTUnwrap(negativeChecked,"FIRST FAILURE: second current negative operation complement proposal against actual newly saved context")
        let protected=try await RuntimeExampleTestFixtures.withInterpretation(checkedNegative) {
            try await repository.createCaptureResult(text:negative,source:.inAppText,createdAt:anchor,schedulesReminders:false)
        }

        XCTAssertEqual(protected.session.originalTranscription, negative)
        XCTAssertNil(protected.operationOutcome)
        XCTAssertTrue(protected.items.contains { $0.itemType.isActionable && $0.displayTitle.localizedCaseInsensitiveContains("buy bread") })
        XCTAssertFalse(protected.items.contains { $0.itemType.isActionable && $0.displayTitle.hasPrefix("I have not agreed") })
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), before)
        let final = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), final)
    }


    @available(iOS 26.4, *)
    func testCheckedGardenWholeCurrentMeaningThroughValidationSaveDisplayRetryAndReopen() async throws {
        let source = IntentConsolidationTests.gardenScatteredLongCapture
        let anchor = Date.now
        for seed in ["Keep this as an idea: painting labels for the pots", "Paint the fence tomorrow at 8 PM"] {
            _ = try repository.createCapture(text: seed, source: .inAppText,
                createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
        }
        let seedIDs = Set(try allItems().map { $0.id.uuidString })
        let before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        // Independently checked COMPLETE current meaning. This diagnostic
        // replaces only generation, after actual validation against current seeds.
        XCTAssertEqual(source,"I am looking around the garden while I talk, so the order is going to be a bit random. The square pot by the back door has mint, and the round one next to it has parsley. Remember that, because the labels have faded. I need to replace the cracked tray under the square mint pot. Only the tray, not the plant or the pot. The other tray is still fine.\n\nI was thinking of painting little picture labels for the plants rather than writing their names. That could be a nice small project, but it is still an idea. I have not decided to spend a weekend on it. A definite job is to return Mira's watering can tomorrow. It is the one with the narrow spout, and the detachable rose belongs with it even though it is currently on the shelf in the shed.\n\nThe shed key has the square blue tag. Keep that as a separate useful fact. The round blue tag is for something else, so the shape matters. Ask the garden coordinator whether we can use the empty bed near the fence. I do not want to assume it is free just because there is nothing growing there at the moment. There is no date for asking.\n\nIf it rains before tomorrow morning, skip watering the parsley. Otherwise water it tomorrow. Keep that conditional rather than treating it as certain that rain will happen. I am not asking the app to monitor the weather; I can check it. Also, I have decided not to buy any more mint. I nearly added that because the square pot looked sparse from this angle, but it is doing fine. The tray replacement still stands. I know the last few sentences doubled back on the first ones, but I have not withdrawn that job.")
        let units=RuntimeIndexedSource(source)
        let expectedUnits:[String]=[
            "I am looking around the garden while I talk, so the order is going to be a bit random.",
            "The square pot by the back door has mint, and the round one next to it has parsley.",
            "Remember that, because the labels have faded.",
            "I need to replace the cracked tray under the square mint pot.",
            "Only the tray, not the plant or the pot.",
            "The other tray is still fine.",
            "I was thinking of painting little picture labels for the plants rather than writing their names.",
            "That could be a nice small project, but it is still an idea.",
            "I have not decided to spend a weekend on it.",
            "A definite job is to return Mira's watering can tomorrow.",
            "It is the one with the narrow spout, and the detachable rose belongs with it even though it is currently on the shelf in the shed.",
            "The shed key has the square blue tag.",
            "Keep that as a separate useful fact.",
            "The round blue tag is for something else, so the shape matters.",
            "Ask the garden coordinator whether we can use the empty bed near the fence.",
            "I do not want to assume it is free just because there is nothing growing there at the moment.",
            "There is no date for asking.",
            "If it rains before tomorrow morning, skip watering the parsley.",
            "Otherwise water it tomorrow.",
            "Keep that conditional rather than treating it as certain that rain will happen.",
            "I am not asking the app to monitor the weather;",
            "I can check it.",
            "Also, I have decided not to buy any more mint.",
            "I nearly added that because the square pot looked sparse from this angle, but it is doing fine.",
            "The tray replacement still stands.",
            "I know the last few sentences doubled back on the first ones, but I have not withdrawn that job."
        ]
        XCTAssertEqual(units.units.map { $0.text },expectedUnits)
        let proposed:[RuntimeFoundationInterpreter.IndexedItem]=[
            .init(evidence:[0,1,2,22,23],purpose:.note,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:[3,4,5,24,25],purpose:.task,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:[6,7,8],purpose:.idea,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:[9,10],purpose:.task,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:[11,12,13],purpose:.note,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:[14,15,16],purpose:.task,currentMeaning:"",directContact:"the garden coordinator",needsReview:false),
            .init(evidence:[17,18,19,20,21],purpose:.task,currentMeaning:"",directContact:"",needsReview:false)
        ]
        XCTAssertEqual(Set(proposed.flatMap { $0.evidence }),Set(units.units.indices))
        let context=RuntimeCaptureContext(savedItems:try allItems().map {
            .init(id:$0.id.uuidString,title:$0.displayTitle,modifiedAt:$0.lastModifiedAt,
                originalText:$0.originalTextSegment,itemType:$0.itemType.rawValue,
                personName:$0.personName,dueDate:$0.dueDate,reminderDate:$0.reminderDate,
                isReviewed:$0.isReviewed,isArchived:$0.isArchived,isCompleted:$0.completedAt != nil,
                snapshot:repository.atomicSnapshot($0))
        },hasHome:SavedPlaceStore.place(for:.home) != nil,hasWork:SavedPlaceStore.place(for:.work) != nil)
        let rules=ThoughtExtractionEngine.extractWithRules(source,referenceDate:anchor,calendar:.autoupdatingCurrent)
        let rulesEvidence=XCTAttachment(string:"ACTUAL RULES AT DIAGNOSTIC BOUNDARY:\n"+String(describing:rules)+"\nPARTITION:\n"+String(describing:CaptureOperationDetector.partitionWithOwnership(source)))
        rulesEvidence.lifetime = .keepAlways;add(rulesEvidence)
        let events=NegativeStatusTrace()
        let checked=RuntimeFoundationInterpreter.$developmentObserver.withValue({ events.append($0) }) {
            RuntimeFoundationInterpreter.validateIndexed(.init(items:proposed),source:source,units:units,
                referenceDate:anchor,calendar:.autoupdatingCurrent,
                rules:rules,context:context)
        }
        let evidence=XCTAttachment(string:"CHECKED COMPLETE GARDEN SOURCE:\n"+source+"\nACTUAL CLOCK:\n"+anchor.ISO8601Format()+"\nACTUAL CONTEXT:\n"+String(describing:context)+"\nINDEXED:\n"+units.prompt+"\nPROPOSAL:\n"+String(describing:proposed)+"\nVALIDATION:\n"+String(describing:checked)+"\nEVENTS:\n"+events.text())
        evidence.lifetime = .keepAlways;add(evidence)
        let valid=try XCTUnwrap(checked,"FIRST FAILURE: actual current saved-context validation of complete independently checked GARDEN seven-meaning proposal")
        XCTAssertEqual(valid.items.count,7)
        // No CaptureCreationResult/CapturedItem from the saved phase survives
        // into the new container. Only immutable value evidence crosses reopen.
        func saveAndRetryPhase() async throws -> (final:Data,ideaID:UUID) {
            let created=try await RuntimeExampleTestFixtures.withInterpretation(valid) {
                try await repository.createCaptureResult(text:source,source:.inAppText,createdAt:anchor,schedulesReminders:false)
            }
            XCTAssertEqual(created.items.count,7)
            var displays:[String]=[]
            for row in created.items {
                let display=ItemPresentation.make(for:row,authorization:LocationAuthorization(status:.denied,isPrecise:true,isRegionMonitoringAvailable:true),now:anchor,calendar:.autoupdatingCurrent)
                displays.append(String(describing:display)+" RAW="+row.originalTextSegment+" SAVED TITLE="+row.displayTitle)
                XCTAssertNil(display.reviewRequirement)
            }
            let saved=XCTAttachment(string:"SAVED COMPLETE GARDEN ROWS AND SHARED DISPLAY:\n"+displays.joined(separator:"\n"))
            saved.lifetime = .keepAlways;add(saved)
            let knowledge=try XCTUnwrap(created.items.first { $0.itemType == .note && $0.originalTextSegment.contains("square pot by the back door") })
            for excluded in ["replace the cracked tray","return Mira","watering the parsley","picture labels"] {
                XCTAssertFalse(knowledge.originalTextSegment.contains(excluded))
                XCTAssertFalse(knowledge.displayTitle.contains(excluded))
            }
            XCTAssertTrue(knowledge.originalTextSegment.contains("decided not to buy any more mint"))
            let conditional=try XCTUnwrap(created.items.first { $0.itemType.isActionable && $0.displayTitle.contains("skip watering the parsley") })
            XCTAssertTrue(conditional.displayTitle.contains("Otherwise water it tomorrow"))
            XCTAssertNil(conditional.reminderDate);XCTAssertNil(conditional.locationIntent)
            XCTAssertNil(RecurrenceStore.rule(for:conditional.id))
            XCTAssertEqual(conditional.temporalIntent?.kind,.dateOnly)
            let returned=try XCTUnwrap(created.items.first { $0.originalTextSegment.hasPrefix("A definite job is to return") })
            XCTAssertNil(returned.personName)
            XCTAssertEqual(returned.temporalIntent?.day,CalendarDay(from:Calendar.autoupdatingCurrent.date(byAdding:.day,value:1,to:anchor)!,calendar:.autoupdatingCurrent))
    
            let captureID = created.session.id
            let ideas = created.items.filter { $0.itemType == .idea }
            XCTAssertEqual(ideas.count, 1)
            let idea = try XCTUnwrap(ideas.first)
            let ideaID = idea.id
            XCTAssertTrue(idea.belongsInMemory)
            XCTAssertFalse(idea.belongsInToday)
            XCTAssertFalse(idea.needsClarification)
            XCTAssertNil(idea.dueDate)
            XCTAssertNil(idea.reminderDate)
            for words in ["painting little picture labels", "nice small project", "not decided to spend"] {
                XCTAssertTrue(idea.originalTextSegment.localizedCaseInsensitiveContains(words))
            }
            // Reaffirmation belongs to the ONE tray task; it is not another job.
            // Retain the historical broad-substring failure in frozen73 evidence.
            let trays=created.items.filter { $0.itemType.isActionable
                && $0.displayTitle.localizedCaseInsensitiveContains("replace the cracked tray") }
            XCTAssertEqual(trays.count,1)
            XCTAssertTrue(trays.first?.originalTextSegment.localizedCaseInsensitiveContains("The tray replacement still stands") ?? false)
            XCTAssertTrue(trays.first?.originalTextSegment.localizedCaseInsensitiveContains("not withdrawn that job") ?? false)
            XCTAssertFalse(created.items.contains { $0.itemType.isActionable
                && $0.displayTitle.localizedCaseInsensitiveContains("I know the last few sentences")
                && !$0.displayTitle.localizedCaseInsensitiveContains("replace the cracked tray") })
            XCTAssertEqual(created.session.originalTranscription, source)
            XCTAssertNil(created.operationOutcome)
            XCTAssertTrue(created.items.allSatisfy { PendingOperationStore.record(for: $0.id) == nil })
            let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
                createdAt: anchor, schedulesReminders: false)
            XCTAssertTrue(retry.isDuplicate)
            XCTAssertEqual(retry.session.id, captureID)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
                .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), before)
            let final = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
            return (final,ideaID)
        }
        let persisted=try await saveAndRetryPhase()
        let final=persisted.final,ideaID=persisted.ideaID
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), final)
        XCTAssertEqual(try loadItem(withID: ideaID).captureSession?.originalTranscription, source)
    }

    @available(iOS 26.4, *)
    func testObservedTrainTwoRowProposalDownstreamDiagnosticWithoutGeneration() async throws {
        let source=IntentConsolidationTests.trainIdeaLongCapture
        var diagnosticCalendar=Calendar(identifier:.gregorian)
        diagnosticCalendar.timeZone=TimeZone(identifier:Self.fixtureTimeZoneIdentifier)!
        let previous=NSTimeZone.default;NSTimeZone.default=diagnosticCalendar.timeZone
        defer { NSTimeZone.default=previous }
        let anchor=try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-08T08:43:30Z"))
        for seed in ["Book the train tomorrow at 10 AM","Download the actual ticket tomorrow at 8 PM","Pack the camera tomorrow at 8 PM"] {
            _ = try repository.createCapture(text:seed,source:.inAppText,createdAt:anchor.addingTimeInterval(-3600),schedulesReminder:false)
        }
        let seeds=Set(try allItems().map(\.id))
        let before=try JSONSerialization.data(withJSONObject:LongCaptureQualificationTests.snapshot(container.mainContext),options:[.sortedKeys])
        let units=RuntimeIndexedSource(source)
        // Exact observed114 response, injected AFTER generation. This is a
        // negative downstream diagnostic, never model evaluation or gold.
        let proposed:[RuntimeFoundationInterpreter.IndexedItem]=[
            .init(evidence:[0,1,2],purpose:.packing,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:Array(3...25),purpose:.task,currentMeaning:"",directContact:"",needsReview:false)
        ]
        let context=RuntimeCaptureContext(savedItems:try allItems().map {
            .init(id:$0.id.uuidString,title:$0.displayTitle,modifiedAt:$0.lastModifiedAt,
                originalText:$0.originalTextSegment,itemType:$0.itemType.rawValue,personName:$0.personName,
                dueDate:$0.dueDate,reminderDate:$0.reminderDate,isReviewed:$0.isReviewed,isArchived:$0.isArchived,
                isCompleted:$0.completedAt != nil,snapshot:repository.atomicSnapshot($0))
        },hasHome:false,hasWork:false)
        let rules=ThoughtExtractionEngine.extractWithRules(source,referenceDate:anchor,calendar:diagnosticCalendar)
        let trace=NegativeStatusTrace()
        let valid=RuntimeFoundationInterpreter.$developmentObserver.withValue({ trace.append($0) }) {
            RuntimeFoundationInterpreter.validateIndexed(.init(items:proposed),source:source,units:units,
                referenceDate:anchor,calendar:diagnosticCalendar,rules:rules,context:context)
        }
        let boundary=XCTAttachment(string:"NEGATIVE OBSERVED114 TRAIN PROPOSAL; MODEL CALLS0; FRESH DISPOSABLE IDS; PINNED CLOCK:\n"+anchor.ISO8601Format()+"\nVALIDATED:\n"+String(describing:valid)+"\nEVENTS:\n"+trace.text())
        boundary.name="observed-two-row-train-validation";boundary.lifetime = .keepAlways;add(boundary)
        XCTAssertNil(valid,"Observed incorrect packing plus merged action/idea proposal must reject before saving")
        if let valid {
            let created=try await RuntimeExampleTestFixtures.withInterpretation(valid) {
                try await repository.createCaptureResult(text:source,source:.inAppText,createdAt:anchor,schedulesReminders:false)
            }
            let displays=created.items.map { row in
                let display=ItemPresentation.make(for:row,authorization:LocationAuthorization(status:.denied,isPrecise:true,isRegionMonitoringAvailable:true),now:anchor,calendar:diagnosticCalendar)
                return """
                ROW \(row.id.uuidString) TYPE=\(row.itemType.rawValue) REVIEW=\(row.needsClarification) TODAY=\(row.belongsInToday) MEMORY=\(row.belongsInMemory) DUE=\(String(describing:row.dueDate)) REMINDER=\(String(describing:row.reminderDate))
                TITLE=\(row.displayTitle)
                ORIGINAL=\(row.originalTextSegment)
                DISPLAY=\(String(describing:display))
                """
            }
            let saved=XCTAttachment(string:displays.joined(separator:"\n\n"));saved.name="observed-two-row-train-actual-save-and-display";saved.lifetime = .keepAlways;add(saved)
            let rows=try LongCaptureQualificationTests.snapshot(container.mainContext).filter { row in
                guard let value=row["id"] as? String,let id=UUID(uuidString:value) else { return false };return !seeds.contains(id)
            }
            let snapshot=XCTAttachment(data:try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]),uniformTypeIdentifier:"public.json");snapshot.name="observed-two-row-train-actual-new-saved-state";snapshot.lifetime = .keepAlways;add(snapshot)
            XCTAssertEqual(created.session.originalTranscription,source)
        }
        let after=try JSONSerialization.data(withJSONObject:LongCaptureQualificationTests.snapshot(container.mainContext).filter { row in
            guard let value=row["id"] as? String,let id=UUID(uuidString:value) else { return false };return seeds.contains(id)
        },options:[.sortedKeys])
        XCTAssertEqual(after,before)
    }

    @available(iOS 26.4, *)
    func testCheckedTrainWholeCurrentMeaningThroughValidationSaveDisplayRetryAndReopen() async throws {
        let source = IntentConsolidationTests.trainIdeaLongCapture
        // This checked proposal contains a future 20:00 reminder. Fix the
        // diagnostic frame rather than letting that premise expire at 20:00.
        // The test saves unscheduled state and has no notification assertions.
        var diagnosticCalendar=Calendar(identifier:.gregorian)
        diagnosticCalendar.timeZone=TimeZone(identifier:Self.fixtureTimeZoneIdentifier)!
        let previousZone=NSTimeZone.default
        NSTimeZone.default=diagnosticCalendar.timeZone
        defer { NSTimeZone.default=previousZone }
        let anchor=makeDate(year:2026,month:10,day:5,hour:9,calendar:diagnosticCalendar)
        for seed in ["Book the train tomorrow at 10 AM", "Download the actual ticket tomorrow at 8 PM", "Pack the camera tomorrow at 8 PM"] {
            _ = try repository.createCapture(text: seed, source: .inAppText,
                createdAt: anchor.addingTimeInterval(-3600), schedulesReminder: false)
        }
        let seedIDs = Set(try allItems().map { $0.id.uuidString })
        let before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        // Independently checked COMPLETE current meaning. This diagnostic
        // replaces only generation, after actual validation against current seeds.
        XCTAssertEqual(source,"Right, about the trip. The train is booked for Friday, October ninth, leaving at ten in the morning. I have the booking already, so I am not buying another ticket. I need to download the actual ticket before the train leaves. The email with a list of journey options is not the ticket; use the attachment in the confirmation. I know I always say I will have a signal at the station, but I would rather not depend on that.\n\nText Sam to say the train leaves at ten on Friday and ask whether he can meet me at the other end. I have not picked a time to send that text. Ten is the departure time inside the message. Also pack the short charging cable, the one that fits in the small battery pouch. I do not need the long cable from behind the desk. The packing is for this trip, but I have not given it a reminder time.\n\nI thought I might take the big camera, but I have decided to leave it and use my phone. Do not keep a camera packing job from that thought. There is an idea I want to keep separately, though: photograph the same station platform from the same spot every time I visit. It might make an interesting series over a year. I am not setting up a recurring reminder for it, just saving the possible project.\n\nThe guest room key is with June, not with Jonah. Remember that. I keep mixing their names up because they both helped last time. Ask June tomorrow whether I can collect the key on Thursday evening. Tomorrow is when I want to ask; Thursday evening is the proposed collection in the question. And remind me at eight tonight to put the railcard in my wallet. That is the last item, and the eight o'clock alert is only for the railcard, not all the trip jobs.")
        let units=RuntimeIndexedSource(source)
        let expectedUnits:[String]=[
            "Right, about the trip.",
            "The train is booked for Friday, October ninth, leaving at ten in the morning.",
            "I have the booking already, so I am not buying another ticket.",
            "I need to download the actual ticket before the train leaves.",
            "The email with a list of journey options is not the ticket;",
            "use the attachment in the confirmation.",
            "I know I always say I will have a signal at the station, but I would rather not depend on that.",
            "Text Sam to say the train leaves at ten on Friday and ask whether he can meet me at the other end.",
            "I have not picked a time to send that text.",
            "Ten is the departure time inside the message.",
            "Also pack the short charging cable, the one that fits in the small battery pouch.",
            "I do not need the long cable from behind the desk.",
            "The packing is for this trip, but I have not given it a reminder time.",
            "I thought I might take the big camera, but I have decided to leave it and use my phone.",
            "Do not keep a camera packing job from that thought.",
            "There is an idea I want to keep separately, though: photograph the same station platform from the same spot every time I visit.",
            "It might make an interesting series over a year.",
            "I am not setting up a recurring reminder for it, just saving the possible project.",
            "The guest room key is with June, not with Jonah.",
            "Remember that.",
            "I keep mixing their names up because they both helped last time.",
            "Ask June tomorrow whether I can collect the key on Thursday evening.",
            "Tomorrow is when I want to ask;",
            "Thursday evening is the proposed collection in the question.",
            "And remind me at eight tonight to put the railcard in my wallet.",
            "That is the last item, and the eight o'clock alert is only for the railcard, not all the trip jobs."
        ]
        XCTAssertEqual(units.units.map { $0.text },expectedUnits)
        let proposed:[RuntimeFoundationInterpreter.IndexedItem]=[
            .init(evidence:[0,1,2,3,4,5,6],purpose:.task,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:[7,8,9],purpose:.task,currentMeaning:"",directContact:"Sam",needsReview:false),
            .init(evidence:[10,11,12,13,14],purpose:.packing,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:[15,16,17],purpose:.idea,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:[18,19,20],purpose:.note,currentMeaning:"",directContact:"",needsReview:false),
            .init(evidence:[21,22,23],purpose:.task,currentMeaning:"",directContact:"June",needsReview:false),
            .init(evidence:[24,25],purpose:.task,currentMeaning:"",directContact:"",needsReview:false)
        ]
        XCTAssertEqual(Set(proposed.flatMap { $0.evidence }),Set(units.units.indices))
        let context=RuntimeCaptureContext(savedItems:try allItems().map {
            .init(id:$0.id.uuidString,title:$0.displayTitle,modifiedAt:$0.lastModifiedAt,
                originalText:$0.originalTextSegment,itemType:$0.itemType.rawValue,
                personName:$0.personName,dueDate:$0.dueDate,reminderDate:$0.reminderDate,
                isReviewed:$0.isReviewed,isArchived:$0.isArchived,isCompleted:$0.completedAt != nil,
                snapshot:repository.atomicSnapshot($0))
        },hasHome:SavedPlaceStore.place(for:.home) != nil,hasWork:SavedPlaceStore.place(for:.work) != nil)
        let rules=ThoughtExtractionEngine.extractWithRules(source,referenceDate:anchor,calendar:.autoupdatingCurrent)
        let rulesEvidence=XCTAttachment(string:"ACTUAL RULES AT DIAGNOSTIC BOUNDARY:\n"+String(describing:rules)+"\nPARTITION:\n"+String(describing:CaptureOperationDetector.partitionWithOwnership(source)))
        rulesEvidence.lifetime = .keepAlways;add(rulesEvidence)
        let events=NegativeStatusTrace()
        let checked=RuntimeFoundationInterpreter.$developmentObserver.withValue({ events.append($0) }) {
            RuntimeFoundationInterpreter.validateIndexed(.init(items:proposed),source:source,units:units,
                referenceDate:anchor,calendar:.autoupdatingCurrent,
                rules:rules,context:context)
        }
        let evidence=XCTAttachment(string:"CHECKED COMPLETE TRAIN SOURCE:\n"+source+"\nPINNED DIAGNOSTIC CLOCK:\n"+anchor.ISO8601Format()+"\nACTUAL CONTEXT:\n"+String(describing:context)+"\nINDEXED:\n"+units.prompt+"\nPROPOSAL:\n"+String(describing:proposed)+"\nVALIDATION:\n"+String(describing:checked)+"\nEVENTS:\n"+events.text())
        evidence.lifetime = .keepAlways;add(evidence)
        let valid=try XCTUnwrap(checked,"FIRST FAILURE: actual current saved-context validation of complete independently checked TRAIN seven-meaning proposal")
        XCTAssertEqual(valid.items.count,7)
        // No CaptureCreationResult/CapturedItem from the saved phase survives
        // into the new container. Only immutable value evidence crosses reopen.
        func saveAndRetryPhase() async throws -> (final:Data,ideaID:UUID) {
            let created=try await RuntimeExampleTestFixtures.withInterpretation(valid) {
                try await repository.createCaptureResult(text:source,source:.inAppText,createdAt:anchor,schedulesReminders:false)
            }
            XCTAssertEqual(created.items.count,7)
            var displays:[String]=[]
            for row in created.items {
                let display=ItemPresentation.make(for:row,authorization:LocationAuthorization(status:.denied,isPrecise:true,isRegionMonitoringAvailable:true),now:anchor,calendar:.autoupdatingCurrent)
                displays.append(String(describing:display)+" RAW="+row.originalTextSegment+" SAVED TITLE="+row.displayTitle)
                XCTAssertNil(display.reviewRequirement)
            }
            let saved=XCTAttachment(string:"SAVED COMPLETE TRAIN ROWS AND SHARED DISPLAY:\n"+displays.joined(separator:"\n"))
            saved.lifetime = .keepAlways;add(saved)
            let download=try XCTUnwrap(created.items.first { $0.itemType.isActionable && $0.originalTextSegment.contains("download the actual ticket") })
            XCTAssertTrue(download.originalTextSegment.contains("use the attachment in the confirmation"))
            XCTAssertNil(download.reminderDate)
            XCTAssertEqual(download.temporalIntent?.kind,.dateOnly)
            XCTAssertEqual(download.temporalIntent?.day,CalendarDay(year:2026,month:10,day:9))
            let packing=try XCTUnwrap(created.items.first { $0.itemType.isActionable && $0.originalTextSegment.hasPrefix("Also pack") })
            for words in ["short charging cable","small battery pouch","do not need the long cable","decided to leave it and use my phone","Do not keep a camera packing job"] {
                XCTAssertTrue(packing.originalTextSegment.localizedCaseInsensitiveContains(words))
            }
            XCTAssertNil(packing.dueDate);XCTAssertNil(packing.reminderDate)
            let ask=try XCTUnwrap(created.items.first { $0.itemType.isActionable && $0.originalTextSegment.hasPrefix("Ask June tomorrow") })
            XCTAssertEqual(ask.personName,"June");XCTAssertNil(ask.temporalIntent?.time)
            XCTAssertEqual(ask.temporalIntent?.day,CalendarDay(from:Calendar.autoupdatingCurrent.date(byAdding:.day,value:1,to:anchor)!,calendar:.autoupdatingCurrent))
            let railcard=try XCTUnwrap(created.items.first { $0.originalTextSegment.hasPrefix("And remind me at eight tonight") })
            let railTime=Calendar.autoupdatingCurrent.date(bySettingHour:20,minute:0,second:0,of:anchor)
            XCTAssertEqual(railcard.reminderDate,railTime)
            XCTAssertTrue(created.items.filter { $0.id != railcard.id }.allSatisfy { $0.reminderDate == nil })
    
            let captureID = created.session.id
            let messages = created.items.filter { $0.itemType.isActionable && $0.displayTitle.hasPrefix("Text Sam") }
            XCTAssertEqual(messages.count, 1)
            let message = try XCTUnwrap(messages.first)
            XCTAssertTrue(message.originalTextSegment.contains("I have not picked a time to send that text."))
            XCTAssertTrue(message.originalTextSegment.contains("Ten is the departure time inside the message."))
            XCTAssertFalse(created.items.contains { $0.displayTitle.hasPrefix("Ten is the departure time") })
            XCTAssertNil(message.reminderDate)
            XCTAssertNil(message.dueDate)
            XCTAssertFalse(message.needsClarification)
            XCTAssertFalse(created.items.contains { $0.itemType.isActionable && $0.displayTitle.hasPrefix("I have not picked a time") })
            let ideas = created.items.filter { $0.itemType == .idea }
            XCTAssertEqual(ideas.count, 1)
            let idea = try XCTUnwrap(ideas.first)
            let ideaID = idea.id
            XCTAssertTrue(idea.belongsInMemory)
            XCTAssertFalse(idea.belongsInToday)
            XCTAssertFalse(idea.needsClarification)
            XCTAssertNil(idea.reminderDate)
            XCTAssertTrue(idea.originalTextSegment.contains("same station platform"))
            XCTAssertTrue(idea.originalTextSegment.contains("interesting series"))
            XCTAssertFalse(idea.originalTextSegment.contains("guest room key"))
            XCTAssertEqual(created.session.originalTranscription, source)
            XCTAssertNil(created.operationOutcome)
            let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
                createdAt: anchor, schedulesReminders: false)
            XCTAssertTrue(retry.isDuplicate)
            XCTAssertEqual(retry.session.id, captureID)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
                .filter { seedIDs.contains($0["id"] as? String ?? "") }, options: [.sortedKeys]), before)
            let final = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
            return (final,ideaID)
        }
        let persisted=try await saveAndRetryPhase()
        let final=persisted.final,ideaID=persisted.ideaID
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), final)
        XCTAssertEqual(try loadItem(withID: ideaID).captureSession?.originalTranscription, source)
    }
#endif

    func testNegativeStatusReferencePreservesOneCaptureIdentityAcrossRetryAndRelaunch() async throws {
        let seed = try repository.createCapture(text: "Buy a replacement mug tomorrow at 8 PM",
            source: .inAppText, createdAt: .now.addingTimeInterval(-60), schedulesReminder: false)
        let seedID = seed.id.uuidString
        let before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { $0["id"] as? String == seedID }, options: [.sortedKeys])
        let source = "Buy one replacement wide handle mug. I have not bought it yet."
        let anchor = Date.now
        let created = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        let captureID = created.session.id
        XCTAssertEqual(created.items.count, 1)
        XCTAssertEqual(created.items.first?.itemType, .shopping)
        XCTAssertEqual(created.session.originalTranscription, source)
        XCTAssertNil(created.operationOutcome)
        XCTAssertTrue(created.items.allSatisfy { !$0.needsClarification && PendingOperationStore.record(for: $0.id) == nil })
        let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: false)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
            .filter { $0["id"] as? String == seedID }, options: [.sortedKeys]), before)
        let final = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        try relaunch()
        try repository.recoverUnorganizedCaptures()
        try repository.recoverUnorganizedCaptures()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys]), final)
        XCTAssertEqual(try allItems().filter { $0.captureSession?.id == captureID }.count, 1)
        XCTAssertEqual(try allItems().first { $0.captureSession?.id == captureID }?.captureSession?.originalTranscription, source)
    }

    func testDeniedOperationComplementKeepsSavedTargetAndActualNotificationAcrossRetry() async throws {
        try await requireNotificationAuthorization()
        let seed = try repository.createCapture(
            text: "Remind me to attend Nora's appointment tomorrow at 8 PM",
            source: .inAppText, createdAt: .now, schedulesReminder: true)
        let seedID = seed.id
        await drainScheduler()
        let requestsBefore = await pendingRequests(for: seedID)
        XCTAssertEqual(requestsBefore.count, 1, "the protected old target must have a real pending effect")
        @MainActor func seedState() throws -> Data {
            try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext)
                .filter { $0["id"] as? String == seedID.uuidString }, options: [.sortedKeys])
        }
        let before = try seedState()
        let source = "I am correcting this recording not asking you to call Nora and cancel her appointment but I will wash the windows and clean the kitchen."
        let anchor = Date.now
        let created = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: true)
        let captureID = created.session.id
        let createdCount = created.items.count
        XCTAssertNil(created.operationOutcome)
        XCTAssertTrue(created.items.allSatisfy { PendingOperationStore.record(for: $0.id) == nil })
        XCTAssertTrue(created.items.contains { $0.itemType.isActionable
            && $0.displayTitle.localizedCaseInsensitiveContains("wash the windows") })
        XCTAssertEqual(created.session.originalTranscription, source)
        let retry = try await repository.createCaptureResult(text: source, source: .inAppText,
            createdAt: anchor, schedulesReminders: true)
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, captureID)
        await drainScheduler()
        XCTAssertEqual(try seedState(), before)
        try relaunch()
        repository.reconcilePendingReminders()
        await drainScheduler()
        XCTAssertEqual(try seedState(), before)
        let after = await pendingRequests(for: seedID)
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.identifier, requestsBefore.first?.identifier)
        XCTAssertEqual(after.first?.content.title, requestsBefore.first?.content.title)
        XCTAssertEqual(after.first?.content.body, requestsBefore.first?.content.body)
        XCTAssertEqual((after.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents,
                       (requestsBefore.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        XCTAssertEqual(try allItems().filter { $0.captureSession?.id == captureID }.count, createdCount)
    }

    func testLongCaptureBeneficiaryPersistsVisiblyWithoutChangingSourceOrSiblings() throws {
        let source = IntentConsolidationTests.displaySetupLongCapture
        var before: Data!
        var purchaseID = UUID()
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let rows = try allItems()
            let setup = try XCTUnwrap(rows.first { $0.originalTextSegment.contains("display setup") })
            XCTAssertEqual(setup.itemType, .note)
            XCTAssertTrue(setup.belongsInMemory)
            XCTAssertFalse(setup.needsClarification)
            XCTAssertNil(setup.dueDate)
            XCTAssertNil(setup.reminderDate)
            XCTAssertTrue(setup.originalTextSegment.contains("taller board"))
            XCTAssertTrue(setup.originalTextSegment.contains("lamps point"))
            XCTAssertTrue(setup.originalTextSegment.contains("Keep those as setup facts"))
            XCTAssertEqual(rows.filter { $0.originalTextSegment.contains("taller board") }.count, 1)

            let page = try XCTUnwrap(rows.first { $0.originalTextSegment.contains("Add making that page") })
            XCTAssertEqual(page.itemType, .task)
            XCTAssertEqual(page.displayTitle, "Make a simple web page")
            XCTAssertTrue(page.belongsInToday)
            XCTAssertFalse(page.belongsInMemory)
            XCTAssertFalse(page.needsClarification)
            XCTAssertTrue(page.originalTextSegment.contains("decided on a simple web page"))
            XCTAssertTrue(page.originalTextSegment.contains("Use the final display captions as the content"))
            XCTAssertEqual(rows.filter { $0.originalTextSegment.contains("Use the final display captions") }.count, 1)
            XCTAssertNil(page.personName)
            XCTAssertNil(page.dueDate)
            XCTAssertNil(page.reminderDate)
            XCTAssertNil(PendingOperationStore.record(for: page.id))

            let purchase = try XCTUnwrap(rows.first { $0.originalTextSegment.contains("Buy oat milk") })
            purchaseID = purchase.id
            XCTAssertEqual(purchase.personName, "Amira")
            XCTAssertTrue(purchase.displayTitle.contains("for Amira"), purchase.displayTitle)
            XCTAssertTrue(purchase.originalTextSegment.contains("for her"))
            XCTAssertTrue(purchase.belongsInToday)
            XCTAssertFalse(purchase.needsClarification)
            XCTAssertNil(purchase.dueDate)
            XCTAssertNil(purchase.reminderDate)
            let email = try XCTUnwrap(rows.first { $0.originalTextSegment.hasPrefix("Email Ben") })
            XCTAssertEqual(email.personName, "Ben")
            XCTAssertEqual(email.temporalIntent?.day?.day, 6)
            before = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        }
        try relaunch()
        let after = try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(container.mainContext), options: [.sortedKeys])
        XCTAssertEqual(after, before, "full persisted states and stable IDs survive relaunch")
        XCTAssertEqual(try loadItem(withID: purchaseID).captureSession?.originalTranscription, source)
    }

    func testLongCaptureStructuredRecipientEditPreservesOtherFieldsAndSiblings() async throws {
        try await requireNotificationAuthorization()
        // S102's addressee is now read automatically. Correct that local
        // field to Juniper through the same persisted editor path; no full
        // capture reparse or timing answer is supplied.
        let source = """
I am thinking about the club event on Friday, October ninth. The room itself is already confirmed, so that is one less thing to chase. I need to print the direction sign, the one with the arrow to the courtyard entrance. Last time people kept trying the front doors and then messaging us because they were locked. Use the bigger type version. Get that printed before the event starts at six in the evening; I do not want the reminder to happen only when people are arriving.

Asha said, 'Tell everyone to bring a mug,' in the committee chat. I have not agreed to send that message. I want to keep what she said as part of the event notes because we still need to decide whether the room has enough cups. My own task is to ask the caretaker how many cups are there. That needs doing tomorrow, before anybody sends a confident message about what people should bring.

The spare name badges are in the orange envelope inside the supplies bag. Remember that. I wasted a ridiculous amount of time looking in the box of cables last time. I do not need a task to move them, I just need to find them when we pack. The little black marker is with the badges too, so that detail belongs in the same note.

And email Jonah the final volunteer rota once Priya has approved it. She has looked at it, but she has not said it is approved. That difference matters because I think two people are still swapping slots. No, actually, the person collecting the rota is June, not Jonah. Email June after Priya approves. I am not changing any of the shifts myself in this recording. There is also an idea for next time, having a quiet corner where people can step away from the noise. Keep that as an idea rather than adding another job for Friday.
"""
        var id = UUID()
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: true)
            // The restated "Email June after Priya approves" is owned by the
            // corrected rota task, not saved as a second objectless email.
            let target = try XCTUnwrap(try allItems().first {
                $0.itemType.isActionable
                    && $0.originalTextSegment.contains("Email June after Priya approves")
            })
            XCTAssertTrue(target.displayTitle.localizedCaseInsensitiveContains("final volunteer rota"))
            id = target.id
            XCTAssertEqual(target.personName, "June")
            XCTAssertFalse(target.needsClarification)
            XCTAssertNil(target.reminderDate)
        }
        await drainScheduler()
        let before = try LongCaptureQualificationTests.snapshot(container.mainContext)
        let captureIDs = try allItems().map(\.id)
        func notificationStates() async throws -> [String] {
            var states = Set<String>()
            for itemID in captureIDs {
                for request in await pendingRequests(for: itemID) {
                    let values: [String: Any] = ["id": request.identifier,
                        "title": request.content.title, "body": request.content.body,
                        "userInfo": request.content.userInfo,
                        "trigger": (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents.description
                            ?? String(describing: request.trigger)]
                    states.insert(String(decoding: try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]), as: UTF8.self))
                }
            }
            return states.sorted()
        }
        let notificationBefore = try await notificationStates()
        let target = try loadItem(withID: id)
        let semantics = ItemEditSemanticReconciler.reconcile(
            title: target.displayTitle, itemType: target.itemType, category: target.category,
            personName: "Juniper", originalTitle: target.displayTitle,
            originalItemType: target.itemType, originalCategory: target.category,
            originalPersonName: target.personName)
        let editedTitle = semantics.title
        XCTAssertTrue(editedTitle.contains("Juniper"), editedTitle)
        XCTAssertFalse(editedTitle.contains("June "), editedTitle)
        XCTAssertTrue(editedTitle.localizedCaseInsensitiveContains("final volunteer rota"), editedTitle)
        let edits = ItemEdits(title: editedTitle, itemType: semantics.itemType,
            category: semantics.category, dueDate: target.dueDate, reminderDate: target.reminderDate,
            priority: target.priority, personName: semantics.personName, needsClarification: false,
            recurrenceRule: RecurrenceStore.rule(for: id), dueDateHasTime: !target.isDateOnly)
        try repository.update(target, with: edits)
        try repository.update(target, with: edits)
        await drainScheduler()
        let notificationAfter = try await notificationStates()
        XCTAssertEqual(notificationAfter, notificationBefore)
        try relaunch()
        await drainScheduler()
        let reopenedNotifications = try await notificationStates()
        XCTAssertEqual(reopenedNotifications, notificationBefore)
        let updated = try loadItem(withID: id)
        XCTAssertEqual(updated.personName, "Juniper")
        XCTAssertEqual(updated.displayTitle, editedTitle)
        XCTAssertEqual(updated.captureSession?.originalTranscription, source)
        let after = try LongCaptureQualificationTests.snapshot(container.mainContext)
        XCTAssertEqual(after.count, before.count)
        for old in before {
            let next = try XCTUnwrap(after.first { ($0["id"] as? String) == (old["id"] as? String) })
            var expected = old
            if (old["id"] as? String) == id.uuidString {
                expected["personName"] = "Juniper"
                expected["displayTitle"] = editedTitle
                // Match ItemEditorView's person-field completion: the
                // satisfied local question clears its existing review flag.
                XCTAssertTrue(old["clarificationRequirement"] is NSNull)
                XCTAssertTrue(next["clarificationRequirement"] is NSNull)
                XCTAssertEqual(next["needsClarification"] as? Bool, false)
                expected["clarificationRequirement"] = NSNull()
                expected["needsClarification"] = false
                expected["isReviewed"] = next["isReviewed"]
                expected["lastModifiedAt"] = next["lastModifiedAt"]
            }
            let delta = Set(next.keys).union(expected.keys).filter { key in
                String(describing: next[key] ?? NSNull()) != String(describing: expected[key] ?? NSNull())
            }.sorted().map { "\($0): \(String(describing: expected[$0] ?? NSNull())) → \(String(describing: next[$0] ?? NSNull()))" }.joined(separator: " | ")
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: next, options: [.sortedKeys]),
                           try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys]),
                           "only selected recipient and its dependent visible title change; unexpected delta: \(delta)")
        }
    }

    func testSeparatedTimingRestrictionsNeverLeaveAnUnrestrictedReminder() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            for source in [
                "Remind me every day at 9 AM to check the oven. Starting next Monday.",
                "Remind me every day at 9 AM to check the oven. Except this Friday.",
                "Remind me every weekday at 9 AM to check the invoice. Until December.",
                "Remind me at seven to call Mom. Not sure if AM or PM. Only on weekdays."
            ].flatMap({ source -> [String] in
                let sentences = source.components(separatedBy: ". ")
                guard sentences.count == 2 else { return [source] }
                let reversed = sentences.reversed().map {
                    $0.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                }.joined(separator: ". ") + "."
                return [source, reversed]
            }) {
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: anchor, calendar: calendar)
                XCTAssertTrue(result.operations.isEmpty, source)
                XCTAssertEqual(result.items.count, 1, source)
                let item = result.items.first
                XCTAssertEqual(item?.rawQuote, source)
                XCTAssertEqual(item?.needsReview, true, source)
                XCTAssertNil(item?.organization.reminderDate, source)
                XCTAssertNil(item?.organization.recurrenceRule, source)
            }
        }
    }

    func testIndependentSentencesDoNotInventATimingRestriction() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            for source in [
                "Remind me every day at 9 AM to check the oven. Buy milk.",
                "Remind me every day at 9 AM to check the oven. Every Friday buy eggs."
            ] {
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: anchor, calendar: calendar)
                XCTAssertEqual(result.items.count, 2, source)
                XCTAssertTrue(result.items.allSatisfy { !$0.needsReview }, source)
                XCTAssertEqual(result.items.filter { $0.organization.reminderDate != nil }.count, 1, source)
                XCTAssertTrue(result.items.contains { $0.organization.itemType == .shopping }, source)
            }
        }
    }

    func testUnresolvedTimeAndPlaceCommentaryStaysWithItsTask() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9,
                                  calendar: calendar)
            let bareHour = "Remind me to send the form at seven tomorrow. "
                + "I have not said morning or evening, and there is no established preference in this test that settles that. "
                + "Do not choose an hour just to avoid asking me, because a twelve hour error would matter for this form. "
                + "Keep the task and tomorrow's date, but hold the notification time until I answer. "
                + "I also need to buy a folder, which has no date. "
                + "The time question should be about the form only, not a reason to make me repeat the folder purchase or the whole capture."
            let timeResult = ThoughtExtractionEngine.extractWithRules(
                bareHour, referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(timeResult.items.count, 2,
                           timeResult.items.map(\.sourceQuote).joined(separator: " | "))
            let form = timeResult.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("send the form")
            }
            XCTAssertEqual(form?.organization.state,
                           .underspecified(.ambiguousTemporalScope))
            XCTAssertNil(form?.organization.reminderDate)
            XCTAssertTrue(timeResult.items.contains {
                $0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("buy a folder")
            })

            let missingHome = "Remind me to take the bins out when I get home. "
                + "There is no saved Home place in this test. "
                + "Keep the task and explain the missing requirement rather than choosing a location or clock time for me. "
                + "The request should remain visible if I close the permission screen. "
                + "I do not want to repeat what I said after fixing the setup, and I do not want a check mark that falsely says an arrival or departure notification is already working. "
                + "There are no other tasks or saved places to modify in this recording."
            let placeResult = ThoughtExtractionEngine.extractWithRules(
                missingHome, referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(placeResult.items.count, 1,
                           placeResult.items.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(placeResult.items.first?.sourceQuote
                .localizedCaseInsensitiveContains("take the bins out") == true)
            XCTAssertNotNil(placeResult.items.first?.organization.locationIntent)
            XCTAssertNil(placeResult.items.first?.organization.reminderDate)

            let independent = ThoughtExtractionEngine.extractWithRules(
                "Remind me to take the bins out when I get home. Also buy a folder.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(independent.items.filter {
                $0.organization.itemType.isActionable
            }.count, 2)
        }
    }

    func testUnpunctuatedMissingHomeExplanationDoesNotTurnReminderIntoMemory() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9,
                                  calendar: calendar)
            let source = "remind me to take the bins out when i get home there is no saved home place in this test "
                + "keep the task and explain the missing requirement rather than choosing a location or clock time for me "
                + "the request should remain visible if i close the permission screen "
                + "i do not want to repeat what i said after fixing the setup and i do not want a check mark that falsely says an arrival or departure notification is already working "
                + "there are no other tasks or saved places to modify in this recording"
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(result.items.count, 1,
                           result.items.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(result.items.first?.organization.itemType.isActionable == true)
            XCTAssertNotNil(result.items.first?.organization.locationIntent)
            XCTAssertTrue(result.items.first?.sourceQuote
                .localizedCaseInsensitiveContains("missing requirement") == true)

            let fact = ThoughtExtractionEngine.extractWithRules(
                "Remember that there is no saved Home place in this test.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertFalse(fact.items.contains { $0.organization.itemType.isActionable })

        }
    }

    func testLowercaseBareHourScopeDoesNotSwallowIndependentFolderPurchase() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9,
                                  calendar: calendar)
            let source = "remind me to send the form at seven tomorrow. "
                + "i have not said morning or evening, and there is no established preference in this test that settles that. "
                + "do not choose an hour just to avoid asking me, because a twelve hour error would matter for this form.\n\n"
                + "keep the task and tomorrow's date, but hold the notification time until i answer. "
                + "i also need to buy a folder, which has no date. "
                + "the time question should be about the form only, not a reason to make me repeat the folder purchase or the whole capture."
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(result.items.count, 2,
                           result.items.map(\.sourceQuote).joined(separator: " | "))
            let form = result.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("send the form")
            }
            XCTAssertEqual(form?.organization.state,
                           .underspecified(.ambiguousTemporalScope))
            XCTAssertNil(form?.organization.reminderDate)
            XCTAssertTrue(result.items.contains {
                $0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("buy a folder")
            })

            let separate = ThoughtExtractionEngine.extractWithRules(
                "Remember that the keys are on the shelf. i also need to buy a folder.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(separate.items.contains {
                $0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("buy a folder")
            })
        }
    }

    func testPunctuationLossBareHourScopeKeepsIndependentFolderPurchase() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9,
                                  calendar: calendar)
            let source = "remind me to send the form at seven tomorrow i have not said morning or evening "
                + "and there is no established preference in this test that settles that do not choose an hour just to avoid asking me because a twelve hour error would matter for this form\n\n"
                + "keep the task and tomorrow's date but hold the notification time until i answer i also need to buy a folder which has no date the time question should be about the form only not a reason to make me repeat the folder purchase or the whole capture"
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(result.items.count, 2,
                           result.items.map(\.sourceQuote).joined(separator: " | "))
            let form = result.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("send the form")
            }
            XCTAssertEqual(form?.organization.state,
                           .underspecified(.ambiguousTemporalScope))
            XCTAssertNil(form?.organization.reminderDate)
            XCTAssertTrue(result.items.contains {
                $0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("buy a folder")
            })
        }
    }

    func testElapsedIntervalExplanationDoesNotCreateCalendarRecurrence() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 31, hour: 9,
                                  calendar: calendar)
            let source = "Remind me to check the equipment logger every twenty four hours, starting twenty four hours from now. "
                + "I mean an elapsed interval, not a particular local clock time every day. "
                + "I am checking whether it is still recording data, not asking the app to control or restart the equipment. "
                + "Keep that distinction even when the clock changes. "
                + "This test starts on October thirty first at nine in the morning in Toronto, so the next twenty four hour point may display a different local hour. "
                + "Do not quietly replace the interval with a daily calendar reminder just because the phrases sound similar. "
                + "If that interval cannot be represented, show the limitation without claiming it is scheduled."
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(result.items.count, 1,
                           result.items.map(\.sourceQuote).joined(separator: " | "))
            let logger = result.items.first
            XCTAssertEqual(logger?.organization.temporalIntent.kind,
                           .durationRecurrence)
            XCTAssertEqual(logger?.organization.reminderDate,
                           makeDate(year: 2026, month: 11, day: 1, hour: 8,
                                    calendar: calendar))
            XCTAssertTrue(logger?.sourceQuote
                .localizedCaseInsensitiveContains("elapsed interval") == true)

            let independent = ThoughtExtractionEngine.extractWithRules(
                "Remind me every twenty four hours to check the logger. "
                    + "I mean an elapsed interval, not a daily clock time. "
                    + "Also email Asha the chart.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(independent.items.contains {
                $0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("email Asha")
            })
            let fact = ThoughtExtractionEngine.extractWithRules(
                "Remember that the clock changes on Sunday.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertFalse(fact.items.contains { $0.organization.itemType.isActionable })

            let concise = ThoughtExtractionEngine.extractWithRules(
                "Remind me every 24 elapsed hours, first after that interval, to check whether the equipment logger is still recording.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(concise.items.count, 1)
            XCTAssertEqual(concise.items.first?.organization.temporalIntent.kind,
                           .durationRecurrence)
            XCTAssertEqual(concise.items.first?.organization.reminderDate,
                           makeDate(year: 2026, month: 11, day: 1, hour: 8,
                                    calendar: calendar))
        }
    }

    func testPairedFrontedReminderClocksStayOnTheirOwnTasksWithLowercaseCommentary() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let result = ThoughtExtractionEngine.extractWithRules(
                "tomorrow at nine in the morning remind me to phone the bike shop, "
                    + "and at three in the afternoon remind me to collect the repaired wheel. "
                    + "both are tomorrow, but they are not the same event.",
                referenceDate: anchor, calendar: calendar
            )
            let call = result.items.first {
                $0.analysisText.localizedCaseInsensitiveContains("phone the bike shop")
            }
            let collection = result.items.first {
                $0.analysisText.localizedCaseInsensitiveContains("collect the repaired wheel")
            }
            XCTAssertEqual(call?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 9,
                                    calendar: calendar))
            XCTAssertEqual(collection?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 15,
                                    calendar: calendar))

            let reported = ThoughtExtractionEngine.extractWithRules(
                "Sam said tomorrow at nine in the morning remind me to phone the bike shop, "
                    + "and at three in the afternoon remind me to collect the wheel.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertFalse(reported.items.contains { $0.organization.itemType.isActionable })
        }
    }

    func testUnpunctuatedBikeShopCaptureKeepsTwoClocksAndNoInventedJobs() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let source = "tomorrow at nine in the morning remind me to phone the bike shop and at three in the afternoon remind me to collect the repaired wheel both are tomorrow but they are not the same event the first is a phone call to check it is ready the second is the actual collection i am not asking you to call the shop yourself for the call ask whether the new spokes are fitted for collection take the repair receipt i am adding those details to the two jobs not asking for separate tasks called spokes and receipt neither reminder should replace the other just because both concern the wheel"
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            let actions = result.items.filter { $0.organization.itemType.isActionable }
            XCTAssertEqual(actions.count, 2, result.items.map(\.sourceQuote).joined(separator: " | "))
            let call = actions.first { $0.sourceQuote.localizedCaseInsensitiveContains("phone the bike shop") }
            let collection = actions.first { $0.sourceQuote.localizedCaseInsensitiveContains("collect the repaired wheel") }
            XCTAssertEqual(call?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 9, calendar: calendar))
            XCTAssertEqual(collection?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 15, calendar: calendar))
            XCTAssertEqual(result.items.count, 2, result.items.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(call?.sourceQuote.localizedCaseInsensitiveContains("new spokes") == true)
            XCTAssertTrue(collection?.sourceQuote.localizedCaseInsensitiveContains("repair receipt") == true)
            XCTAssertFalse(collection?.sourceQuote.localizedCaseInsensitiveContains("new spokes") == true)
            XCTAssertFalse(call?.sourceQuote.localizedCaseInsensitiveContains("repair receipt") == true)

            let independent = ThoughtExtractionEngine.extractWithRules(
                "Remind me tomorrow at nine to call the shop. Also email Maya the receipt.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(independent.items.contains {
                $0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("email Maya")
            })

            let laterAction = ThoughtExtractionEngine.extractWithRules(
                source + " also email Asha the receipt",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(laterAction.items.contains {
                $0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("email Asha")
            }, "A later independent action cannot become paired-reminder context")
        }
    }

    func testDottedMeridiemAndTorontoTimeStayWithEachReminder() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let source = "Remind me on October 06, 2026 at 9:00 a.m. Toronto time to phone the bike shop to check the new spokes are fitted. "
                + "Remind me on October 06, 2026 at 3:00 p.m. Toronto time to collect the repaired wheel and take the repair receipt."
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(result.items.count, 2,
                           "clauses: \(RuleBasedThoughtExtractor.splitClauses(source)); items: \(result.items.map(\.sourceQuote).joined(separator: " | "))")
            let call = result.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("phone the bike shop")
            }
            let collection = result.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("collect the repaired wheel")
            }
            XCTAssertTrue(call?.organization.itemType.isActionable == true)
            XCTAssertTrue(collection?.organization.itemType.isActionable == true)
            XCTAssertEqual(call?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 9, calendar: calendar))
            XCTAssertEqual(collection?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 15, calendar: calendar))
            XCTAssertTrue(collection?.sourceQuote.localizedCaseInsensitiveContains("repair receipt") == true)
            XCTAssertFalse(call?.sourceQuote.localizedCaseInsensitiveContains("repair receipt") == true)

            let independent = ThoughtExtractionEngine.extractWithRules(
                "Remind me at 3:00 p.m. Call Asha at five.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(independent.items.contains {
                $0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("Call Asha")
            })
            let separateReceiptAction = ThoughtExtractionEngine.extractWithRules(
                "Remind me tomorrow at three to collect the repaired wheel and email Asha the receipt.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(separateReceiptAction.items.filter {
                $0.organization.itemType.isActionable
            }.count, 2)
        }
    }

    func testTravelMessageExplanationsStayWithTheirTwoTasks() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let source = "Text Sam to say that the train leaves at seven tomorrow evening. "
                + "The seven o'clock time is what I need to tell Sam; it is not when I want a reminder to send the text. "
                + "I have not chosen a time to text him, so please do not wait until the train is leaving. "
                + "Separately, remind me at eleven this morning to print the ticket. "
                + "Use the booking confirmation attachment, not a screenshot of the journey search. "
                + "The text and printing task are both about travel, but the printing reminder should not get copied onto the text or onto a new train event."
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(result.items.count, 2,
                           result.items.map(\.sourceQuote).joined(separator: " | "))
            let text = result.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("Text Sam to say")
            }
            let printing = result.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("print the ticket")
            }
            XCTAssertTrue(text?.organization.itemType.isActionable == true)
            XCTAssertTrue(printing?.organization.itemType.isActionable == true)
            XCTAssertNil(text?.organization.reminderDate)
            XCTAssertEqual(printing?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 5, hour: 11,
                                    calendar: calendar))
            XCTAssertTrue(text?.sourceQuote.localizedCaseInsensitiveContains("seven o'clock time") == true)
            XCTAssertTrue(printing?.sourceQuote.localizedCaseInsensitiveContains("booking confirmation attachment") == true)

            let lowercased = "text sam to say that the train leaves at seven tomorrow evening. "
                + "the seven o'clock time is what i need to tell sam; it is not when i want a reminder to send the text. "
                + "i have not chosen a time to text him, so please do not wait until the train is leaving.\n\n"
                + "separately, remind me at eleven this morning to print the ticket. "
                + "use the booking confirmation attachment, not a screenshot of the journey search. "
                + "the text and printing task are both about travel, but the printing reminder should not get copied onto the text or onto a new train event."
            let punctuationLoss = "text sam to say that the train leaves at seven tomorrow evening the seven o'clock time is what i need to tell sam it is not when i want a reminder to send the text i have not chosen a time to text him so please do not wait until the train is leaving\n\n"
                + "separately remind me at eleven this morning to print the ticket use the booking confirmation attachment not a screenshot of the journey search the text and printing task are both about travel but the printing reminder should not get copied onto the text or onto a new train event"
            let withFillers = "Um, let me think. " + source.replacingOccurrences(
                of: "Separately, remind me",
                with: "Right, okay. Separately, remind me"
            )
            for variant in [lowercased, punctuationLoss, withFillers] {
                let parsed = ThoughtExtractionEngine.extractWithRules(
                    variant, referenceDate: anchor, calendar: calendar
                )
                XCTAssertEqual(parsed.items.count, 2,
                               parsed.items.map(\.sourceQuote).joined(separator: " | "))
                XCTAssertTrue(parsed.items.contains {
                    $0.organization.itemType.isActionable
                        && $0.sourceQuote.localizedCaseInsensitiveContains("print the ticket")
                        && $0.organization.reminderDate == makeDate(
                            year: 2026, month: 10, day: 5, hour: 11, calendar: calendar
                        )
                })
            }

            let extraAction = ThoughtExtractionEngine.extractWithRules(
                source + " Also email Asha the receipt.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(extraAction.items.contains {
                $0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("email Asha")
            })
            let sendAtSeven = ThoughtExtractionEngine.extractWithRules(
                "Text Sam at seven tomorrow evening to say the train is delayed.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(sendAtSeven.items.first?.organization.dueDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 19,
                                    calendar: calendar))
            let remindAtSeven = ThoughtExtractionEngine.extractWithRules(
                "Remind me at seven tomorrow evening to text Sam that the train is delayed.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(remindAtSeven.items.first?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 19,
                                    calendar: calendar))
        }
    }

    func testProhibitedAppointmentMutationKeepsLaterAddressQuestionAsTask() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let source = "Do not cancel my appointment. I only want to ask the office whether they can email the address again. "
                + "Make that question a task for tomorrow. The word cancel is in a prohibition, not in an authorized saved item operation. "
                + "I am keeping the appointment exactly as it is. The address email would help me find the right entrance, "
                + "and I do not want a new appointment or a changed date. Preserve the existing saved appointment if there is one, "
                + "and do not invent a cancellation just because that word appeared early in the recording."
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(result.operations.isEmpty)
            XCTAssertEqual(result.items.count, 1, result.items.map(\.sourceQuote).joined(separator: " | "))
            let question = result.items.first
            XCTAssertTrue(question?.organization.itemType.isActionable == true)
            XCTAssertTrue(question?.suggestedTitle?.localizedCaseInsensitiveContains("ask the office") == true)
            XCTAssertEqual(question?.organization.dueDate,
                           makeDate(year: 2026, month: 10, day: 6, calendar: calendar))
            XCTAssertNil(question?.organization.reminderDate)
            XCTAssertTrue(question?.sourceQuote.localizedCaseInsensitiveContains("do not cancel") == true)
            XCTAssertTrue(question?.sourceQuote.localizedCaseInsensitiveContains("do not invent a cancellation") == true)

            let concise = ThoughtExtractionEngine.extractWithRules(
                "On October 06, 2026, ask the office to email the appointment address again.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(concise.items.count, 1,
                           concise.items.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertEqual(concise.items.first?.organization.itemType, .task,
                           concise.items.map { "\($0.analysisText) => \($0.organization.itemType)" }.joined(separator: " | "))
            XCTAssertEqual(concise.items.first?.organization.dueDate,
                           makeDate(year: 2026, month: 10, day: 6, calendar: calendar),
                           "instruction=" + ClauseScope.instructionText("On October 06, 2026, ask the office to email the appointment address again.")
                            + " | direct=" + String(describing: ThoughtOrganizer.organize("On October 06, 2026, ask the office to email the appointment address again.", referenceDate: anchor, calendar: calendar).dueDate)
                            + " | " + concise.items.map { "analysis=\($0.analysisText) quote=\($0.sourceQuote) temporal=\($0.organization.temporalIntent)" }.joined(separator: " | "))

            let prohibitionOnly = ThoughtExtractionEngine.extractWithRules(
                "Do not cancel my appointment.", referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(prohibitionOnly.operations.isEmpty)
            XCTAssertTrue(prohibitionOnly.items.allSatisfy(\.needsReview))
            let unrelatedLaterAction = ThoughtExtractionEngine.extractWithRules(
                source + " Also email Ben the directions.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(unrelatedLaterAction.operations.isEmpty)
            XCTAssertFalse(unrelatedLaterAction.items.contains {
                $0.organization.itemType.isActionable && !$0.needsReview
                    && $0.sourceQuote.localizedCaseInsensitiveContains("email Ben")
                    && $0.sourceQuote.localizedCaseInsensitiveContains("ask the office")
            })
            let taskNotMutation = ThoughtExtractionEngine.extractWithRules(
                "Add a task for me to cancel my appointment with the office. "
                    + "Do not cancel a calendar event automatically.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(taskNotMutation.operations.isEmpty)
            XCTAssertEqual(taskNotMutation.items.count, 1,
                           taskNotMutation.items.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertEqual(taskNotMutation.items.first?.organization.itemType, .task)
            XCTAssertFalse(taskNotMutation.items.first?.needsReview ?? true)
            XCTAssertTrue(taskNotMutation.items.first?.sourceQuote.localizedCaseInsensitiveContains(
                "Do not cancel a calendar event automatically") == true)
        }
    }

    func testPunctuatedBikeShopDetailsBelongToTwoExistingReminders() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let source = "Tomorrow at nine in the morning remind me to phone the bike shop, "
                + "and at three in the afternoon remind me to collect the repaired wheel. "
                + "Both are tomorrow, but they are not the same event. "
                + "The first is a phone call to check it is ready; the second is the actual collection. "
                + "I am not asking you to call the shop yourself. "
                + "For the call, ask whether the new spokes are fitted. "
                + "For collection, take the repair receipt. "
                + "I am adding those details to the two jobs, not asking for separate tasks called spokes and receipt. "
                + "Neither reminder should replace the other just because both concern the wheel."
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(result.items.count, 2,
                           result.items.map(\.sourceQuote).joined(separator: " | "))
            let call = result.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("phone the bike shop")
            }
            let collection = result.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("collect the repaired wheel")
            }
            XCTAssertEqual(call?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 9, calendar: calendar))
            XCTAssertEqual(collection?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 15, calendar: calendar))
            XCTAssertTrue(call?.sourceQuote.localizedCaseInsensitiveContains("new spokes") == true)
            XCTAssertTrue(collection?.sourceQuote.localizedCaseInsensitiveContains("repair receipt") == true)

            let laterAction = ThoughtExtractionEngine.extractWithRules(
                "Remind me tomorrow to call the shop. For the call, ask whether the spokes are fitted. "
                    + "Also email Asha the receipt.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(laterAction.items.contains {
                $0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("email Asha")
            })
        }
    }

    func testLowercaseBikeShopSentenceStopsKeepNamedDetailsLocal() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let source = "tomorrow at nine in the morning remind me to phone the bike shop, "
                + "and at three in the afternoon remind me to collect the repaired wheel. "
                + "both are tomorrow, but they are not the same event. "
                + "the first is a phone call to check it is ready; the second is the actual collection. "
                + "i am not asking you to call the shop yourself.\n\n"
                + "for the call, ask whether the new spokes are fitted. "
                + "for collection, take the repair receipt. "
                + "i am adding those details to the two jobs, not asking for separate tasks called spokes and receipt. "
                + "neither reminder should replace the other just because both concern the wheel."
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(result.items.count, 2,
                           result.items.map(\.sourceQuote).joined(separator: " | "))
            let call = result.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("phone the bike shop")
            }
            let collection = result.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("collect the repaired wheel")
            }
            XCTAssertEqual(call?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 9, calendar: calendar))
            XCTAssertEqual(collection?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 15, calendar: calendar))
            XCTAssertTrue(call?.sourceQuote.localizedCaseInsensitiveContains("new spokes") == true)
            XCTAssertTrue(collection?.sourceQuote.localizedCaseInsensitiveContains("repair receipt") == true)
        }
    }

    func testPhotoAndAvailabilityExplanationsNeedUniqueTaskOwners() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let source = "Remind me at six tonight to send Maya the kitchen photos. "
                + "I mean the new photographs that show the cupboard damage, not the blurry set from last week. "
                + "The old set would make it look as though I had never taken a closer look. "
                + "Actually, seven tonight for the photos. "
                + "Call the dentist tomorrow to ask whether I can move my appointment. "
                + "I am only asking about availability. Do not change the appointment itself. "
                + "The call is the thing I need to remember."
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(result.items.count, 2,
                           result.items.map(\.sourceQuote).joined(separator: " | "))
            let photo = result.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("send Maya the kitchen photos")
            }
            let call = result.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("call the dentist")
            }
            XCTAssertEqual(photo?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 5, hour: 19, calendar: calendar))
            XCTAssertTrue(photo?.sourceQuote.localizedCaseInsensitiveContains("new photographs") == true)
            XCTAssertTrue(call?.sourceQuote.localizedCaseInsensitiveContains("availability") == true)
            XCTAssertTrue(call?.sourceQuote.localizedCaseInsensitiveContains("do not change") == true)

            let twoPhotoOwners = ThoughtExtractionEngine.extractWithRules(
                "Remind me to send Maya the photos. Remind me to send Nina the photos. "
                    + "I mean the new photographs, not the blurry set.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(twoPhotoOwners.items.contains {
                $0.sourceQuote.localizedCaseInsensitiveContains("new photographs")
                    && $0.needsReview
            }, "Two plausible photos must not receive a guessed clarification")

            let independentFact = ThoughtExtractionEngine.extractWithRules(
                "Remind me to send Maya the photos. Remember the old photographs are in the archive.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(independentFact.items.contains {
                !$0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("old photographs")
            })
        }
    }

    func testAdjacentThatReminderArmsOnlyItsOwnExplicitlyTimedTask() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let result = ThoughtExtractionEngine.extractWithRules(
                "Water the parsley tomorrow morning at eight. "
                    + "Please set a reminder for that. Buy milk.",
                referenceDate: anchor, calendar: calendar
            )
            let parsley = result.items.first {
                $0.analysisText.localizedCaseInsensitiveContains("water the parsley")
            }
            XCTAssertEqual(parsley?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 8,
                                    calendar: calendar))
            XCTAssertFalse(result.items.contains {
                $0.analysisText.localizedCaseInsensitiveContains("reminder for that")
                    && $0.organization.itemType.isActionable
            })
            XCTAssertTrue(result.items.contains {
                $0.organization.itemType == .shopping
                    && $0.analysisText.localizedCaseInsensitiveContains("milk")
            })

            let differentTarget = ThoughtExtractionEngine.extractWithRules(
                "Water the parsley tomorrow morning at eight. "
                    + "Please set a reminder for the mint.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertNil(differentTarget.items.first {
                $0.analysisText.localizedCaseInsensitiveContains("water the parsley")
            }?.organization.reminderDate)

            let reportedRequest = ThoughtExtractionEngine.extractWithRules(
                "Water the parsley tomorrow morning at eight. "
                    + "Maya said, 'Please set a reminder for that.'",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertNil(reportedRequest.items.first {
                $0.analysisText.localizedCaseInsensitiveContains("water the parsley")
            }?.organization.reminderDate,
            "A reported request must not arm the speaker's task")
        }
    }

    func testNamedRevisionExplanationRequiresItsActualCorrectionOwner() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let source = "Remind me at eight tonight to water the basil. Buy envelopes. Actually, nine tonight for the basil. That replaces the time I said earlier; it is still the same pot of basil. Remember the cupboard key is in the drawer."
            let items = ThoughtExtractionEngine.extractWithRules(source, referenceDate: anchor, calendar: calendar).items
            XCTAssertEqual(items.count, 3)
            let basil = items.first { $0.analysisText.contains("water the basil") }
            XCTAssertTrue(basil?.sourceQuote.contains("That replaces") == true)
            XCTAssertTrue(basil?.sourceQuote.contains("same pot of basil") == true)
            XCTAssertEqual(basil?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 5, hour: 21, calendar: calendar))
            XCTAssertTrue(items.contains { $0.organization.itemType == .shopping
                && !$0.sourceQuote.contains("That replaces") })
            XCTAssertTrue(items.contains { $0.organization.itemType == .note
                && $0.analysisText.contains("cupboard key") })
            let ambiguous = ThoughtExtractionEngine.extractWithRules(
                "Remind me at six tonight to collect the red folder. Remind me at six tonight to bring the blue folder. Actually, seven tonight for the folder. That replaces the time I said earlier; it is still the same folder.",
                referenceDate: anchor, calendar: calendar).items
            XCTAssertFalse(ambiguous.contains { $0.organization.reminderDate
                == makeDate(year: 2026, month: 10, day: 5, hour: 19, calendar: calendar) })
            XCTAssertTrue(ambiguous.contains { $0.needsReview
                && $0.sourceQuote.contains("Actually") && $0.sourceQuote.contains("That replaces") })
            let noRevision = ThoughtExtractionEngine.extractWithRules(
                "Buy envelopes. That replaces the time I said earlier.",
                referenceDate: anchor, calendar: calendar).items
            XCTAssertTrue(noRevision.contains { $0.needsReview && $0.sourceQuote.contains("That replaces") })
            let physical = ThoughtExtractionEngine.extractWithRules(
                "Remember the new pump is installed. That replaces the old pump.",
                referenceDate: anchor, calendar: calendar).items
            XCTAssertTrue(physical.allSatisfy { $0.organization.itemType == .note && !$0.needsReview })
            XCTAssertTrue(physical.contains { $0.sourceQuote.contains("old pump") })
        }
    }

    func testCompleteNamedClockCorrectionOwnsItsContinuationAcrossShoppingAndRelaunch() throws {
        let source = "Right, before I lose the thread, remind me at six tonight to send Maya the kitchen photos. I mean the new photographs that show the cupboard damage, not the blurry set from last week. The old set would make it look as though I had never taken a closer look.\n\nI also need oat milk and eggs. They can go on the same shopping list. This is one trip, not a separate reminder for each shop, and I have not chosen a shopping time.\n\nActually, seven tonight for the photos, because I will not be home at six. That replaces the time I said earlier; it is still the same set of pictures for Maya.\n\nCall the dentist tomorrow to ask whether I can move my appointment. I am only asking about availability. Do not change the appointment itself. The call is the thing I need to remember."
        var ids = Set<UUID>()
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let items = try allItems()
            XCTAssertEqual(items.count, 3, items.map { "\($0.itemType):\($0.displayTitle):\($0.originalTextSegment)" }.joined(separator: " | "))
            XCTAssertTrue(items.allSatisfy { !$0.needsClarification
                && $0.captureSession?.originalTranscription == source })
            let photo = try XCTUnwrap(items.first { $0.displayTitle.contains("Send Maya") })
            XCTAssertEqual(photo.reminderDate,
                           makeDate(year: 2026, month: 10, day: 5, hour: 19, calendar: calendar))
            XCTAssertTrue(photo.originalTextSegment.contains("That replaces the time I said earlier"))
            XCTAssertTrue(photo.originalTextSegment.contains("same set of pictures for Maya"))
            let shopping = try XCTUnwrap(items.first { $0.itemType == .shopping })
            XCTAssertTrue(shopping.displayTitle.contains("oat milk") && shopping.displayTitle.contains("eggs"))
            XCTAssertNil(shopping.dueDate)
            XCTAssertNil(shopping.reminderDate)
            XCTAssertFalse(shopping.originalTextSegment.contains("That replaces"))
            XCTAssertFalse(shopping.originalTextSegment.contains("pictures for Maya"))
            let call = try XCTUnwrap(items.first { $0.displayTitle.contains("Call the dentist") })
            XCTAssertEqual(call.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertFalse(call.originalTextSegment.contains("pictures for Maya"))
            ids = Set(items.map(\.id))
        }
        try relaunch()
        XCTAssertEqual(Set(try allItems().map(\.id)), ids)
        XCTAssertEqual(try allItems().count, 3)
        XCTAssertTrue(try allItems().allSatisfy { $0.captureSession?.originalTranscription == source })
    }

    func testNamedClockCorrectionAfterNoTimeAsideReplacesOldAlert() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let source = "remind me at six tonight to send maya the kitchen photos. i also need eggs. i have not chosen a shopping time. actually, seven tonight for the photos, because i will not be home at six."
            let result = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: anchor, calendar: calendar
            )
            let photo = result.items.first {
                $0.analysisText.localizedCaseInsensitiveContains("send maya")
            }
            XCTAssertEqual(photo?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 5, hour: 19,
                                    calendar: calendar),
                           result.items.map { "\($0.organization.reminderDate as Any):\($0.sourceQuote)" }
                            .joined(separator: " | "))
            XCTAssertFalse(result.items.contains {
                $0.organization.reminderDate == makeDate(
                    year: 2026, month: 10, day: 5, hour: 18, calendar: calendar
                )
            })
            XCTAssertEqual(result.items.count, 2)
            let shopping = result.items.first { $0.organization.itemType == .shopping }
            XCTAssertNotNil(shopping)
            XCTAssertNil(shopping?.organization.dueDate)
            XCTAssertNil(shopping?.organization.reminderDate)
            XCTAssertFalse(shopping?.sourceQuote.localizedCaseInsensitiveContains("photos") ?? true)
            let opposite = ThoughtExtractionEngine.extractWithRules(
                "Remind me at six tonight to send Maya the photos. "
                    + "Remind me at six tonight to send Nina the photos. "
                    + "Actually, seven tonight for the photos.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertFalse(opposite.items.contains {
                $0.organization.reminderDate == makeDate(
                    year: 2026, month: 10, day: 5, hour: 19, calendar: calendar
                )
            })
            let paragraphs = "right, before i lose the thread, remind me at six tonight to send maya the kitchen photos. i mean the new photographs that show the cupboard damage, not the blurry set from last week. the old set would make it look as though i had never taken a closer look.\n\ni also need oat milk and eggs. they can go on the same shopping list. this is one trip, not a separate reminder for each shop, and i have not chosen a shopping time.\n\nactually, seven tonight for the photos, because i will not be home at six. that replaces the time i said earlier; it is still the same set of pictures for maya.\n\ncall the dentist tomorrow to ask whether i can move my appointment. i am only asking about availability. do not change the appointment itself. the call is the thing i need to remember."
            let full = ThoughtExtractionEngine.extractWithRules(
                paragraphs, referenceDate: anchor, calendar: calendar
            )
            let fullPhoto = full.items.first {
                $0.sourceQuote.localizedCaseInsensitiveContains("send maya the kitchen photos")
            }
            XCTAssertEqual(fullPhoto?.organization.reminderDate,
                           makeDate(year: 2026, month: 10, day: 5, hour: 19,
                                    calendar: calendar),
                           full.items.map { "\($0.organization.reminderDate as Any):\($0.sourceQuote)" }
                            .joined(separator: " | "))
            XCTAssertTrue(full.items.contains {
                $0.organization.itemType == .shopping
                    && $0.analysisText.localizedCaseInsensitiveContains("oat milk")
                    && $0.analysisText.localizedCaseInsensitiveContains("eggs")
            }, "The independent shopping intention must not be absorbed by the photo reminder")
            XCTAssertEqual(full.items.count, 3,
                           full.items.map { "\($0.organization.itemType):\($0.sourceQuote)" }
                            .joined(separator: " | "))
            XCTAssertTrue(full.items.contains {
                $0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("call the dentist")
                    && $0.sourceQuote.localizedCaseInsensitiveContains("availability")
                    && $0.sourceQuote.localizedCaseInsensitiveContains("do not change")
            })
            XCTAssertTrue(fullPhoto?.sourceQuote.localizedCaseInsensitiveContains("new photographs") == true)

            let separateMemory = ThoughtExtractionEngine.extractWithRules(
                "Remind me to send Maya the photos. Remember the old photographs are in the archive.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(separateMemory.items.contains {
                !$0.organization.itemType.isActionable
                    && $0.sourceQuote.localizedCaseInsensitiveContains("old photographs")
            })

            let ambiguousAppointment = ThoughtExtractionEngine.extractWithRules(
                "Call the dentist about my appointment. Call the optometrist about my appointment. "
                    + "Do not change the appointment itself.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(ambiguousAppointment.items.filter {
                $0.organization.itemType.isActionable
            }.count, 2)
            XCTAssertTrue(ambiguousAppointment.items.contains {
                $0.sourceQuote.localizedCaseInsensitiveContains("do not change the appointment")
                    && $0.needsReview
            }, "An ambiguous constraint must not choose one of two appointment calls")

            let reportedShopping = ThoughtExtractionEngine.extractWithRules(
                "Remind me at six tonight to send Maya the photos. "
                    + "Maya said, 'I also need oat milk and eggs.' "
                    + "Actually, seven tonight for the photos.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertFalse(reportedShopping.items.contains {
                $0.organization.itemType == .shopping
            }, "Reported shopping words are not a new commitment by the speaker")
        }
    }

    func testMessageToSayThatTrainTimeStaysInContentWhileSendTimeStaysActionable() throws {
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let content = "Text Sam to say that the train leaves at seven tomorrow evening"
            XCTAssertEqual(ClauseScope.read(content).act, .communicating)
            let message = try repository.createCapture(
                text: content, source: .inAppText, createdAt: anchor,
                schedulesReminder: false
            )
            XCTAssertTrue(message.belongsInToday)
            XCTAssertNil(message.dueDate)
            XCTAssertNil(message.reminderDate)
            XCTAssertTrue(message.displayTitle.localizedCaseInsensitiveContains("train leaves"))

            let sendTime = try repository.createCapture(
                text: "Text Sam at seven tomorrow evening to say that the train leaves",
                source: .inAppText, createdAt: anchor,
                schedulesReminder: false
            )
            XCTAssertEqual(sendTime.dueDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 19,
                                    calendar: calendar))
            let explicitReminder = try repository.createCapture(
                text: "Remind me tomorrow at seven in the evening to text Sam",
                source: .inAppText, createdAt: anchor,
                schedulesReminder: false
            )
            XCTAssertEqual(explicitReminder.reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 19,
                                    calendar: calendar))
            let reported = try repository.createCapture(
                text: "Sarah said to text Sam at seven tomorrow evening",
                source: .inAppText, createdAt: anchor,
                schedulesReminder: false
            )
            XCTAssertTrue(reported.belongsInMemory)
            XCTAssertNil(reported.reminderDate)

            let wrappedContent = try repository.createCapture(
                text: "Add my task to text Sam that the train leaves at 7:00 pm tomorrow",
                source: .inAppText, createdAt: anchor, schedulesReminder: false
            )
            XCTAssertNil(wrappedContent.dueDate)
            let wrappedSend = try repository.createCapture(
                text: "Add my task to text Sam at 7:00 pm tomorrow",
                source: .inAppText, createdAt: anchor, schedulesReminder: false
            )
            XCTAssertEqual(wrappedSend.dueDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 19,
                                    calendar: calendar))
        }
    }

    func testHyphenatedOrdinalModifiersDoNotBecomeCalendarDays() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            for speech in [
                "Hang the first-aid sign in the hallway",
                "Buy the second-hand chair for the studio",
                "Read the third-party report before the meeting"
            ] {
                let result = ThoughtExtractionEngine.extractWithRules(
                    speech, referenceDate: anchor, calendar: calendar
                )
                XCTAssertEqual(result.items.count, 1, speech)
                XCTAssertNil(result.items.first?.organization.dueDate, speech)
                XCTAssertEqual(result.items.first?.organization.temporalIntent.kind, TemporalKind.none, speech)
            }

            let explicitDate = ThoughtExtractionEngine.extractWithRules(
                "Pay rent on the first", referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(explicitDate.items.count, 1)
            XCTAssertNotNil(explicitDate.items.first?.organization.dueDate)
        }
    }

    func testRelatedEventClockIsVisibleWithoutSchedulingActionAtEventTime() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            let result = ThoughtExtractionEngine.extractWithRules(
                "I want to remember that the train goes at 6:40—sorry, that was last month's "
                    + "timetable. The current ticket says 7:15 from platform four on Saturday. "
                    + "I need to pack the blue folder on Friday night and leave for the station "
                    + "early enough for that train. Keep the corrected ticket detail as reference; "
                    + "don't act on the superseded time.",
                referenceDate: anchor, calendar: calendar
            )
            let departure = result.items.first {
                $0.analysisText.localizedCaseInsensitiveContains("leave for the station")
            }
            XCTAssertNotNil(departure)
            XCTAssertTrue(departure?.suggestedTitle?.contains("7:15") == true)
            XCTAssertTrue(departure?.suggestedTitle?.contains("Saturday") == true)
            XCTAssertFalse(departure?.suggestedTitle?.contains("6:40") == true)
            XCTAssertNil(departure?.organization.dueDate)
            XCTAssertNil(departure?.organization.reminderDate)
            XCTAssertEqual(departure?.organization.temporalIntent.kind, TemporalKind.none)
        }
    }

    func testSharedAppointmentClockDoesNotReplaceAnActionsOwnTonightTime() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            let result = ThoughtExtractionEngine.extractWithRules(
                "For tomorrow, call the plumber—wait, no, I already called and the visit is "
                    + "booked. What I actually need is photograph the leak before the plumber "
                    + "arrives and clear the cabinet under the sink tonight. The appointment is "
                    + "at ten in the morning, which is context for those steps. Please don't "
                    + "leave me a second call-the-plumber job just because I said it first.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(result.items.count, 2)
            let photograph = result.items.first {
                $0.analysisText.localizedCaseInsensitiveContains("photograph the leak")
            }
            let cabinet = result.items.first {
                $0.analysisText.localizedCaseInsensitiveContains("clear the cabinet")
            }
            XCTAssertTrue(photograph?.suggestedTitle?.contains("ten in the morning") == true)
            XCTAssertTrue(cabinet?.suggestedTitle?.contains("ten in the morning") == true)
            XCTAssertNil(photograph?.organization.dueDate)
            XCTAssertNil(photograph?.organization.reminderDate)
            XCTAssertEqual(cabinet?.organization.temporalIntent.time?.hour, 20)
            XCTAssertNil(cabinet?.organization.reminderDate)
        }
    }

    func testUniqueVisitReferentScopesLaterActionAcrossMemory() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            let visit = ThoughtExtractionEngine.extractWithRules(
                "For Amira's visit next Tuesday, wash the guest towels, put fresh sheets on "
                    + "the bed, and check that the spare room lamp works. She is allergic to "
                    + "lavender, so remember that as a lasting fact about her. Pick up unscented "
                    + "soap before she arrives. The allergy explains the soap choice; I want "
                    + "the fact retained, not a free-standing reminder about lavender.",
                referenceDate: anchor, calendar: calendar
            )
            let soap = visit.items.first {
                $0.analysisText.localizedCaseInsensitiveContains("unscented soap")
            }
            XCTAssertTrue(soap?.suggestedTitle?.contains("Amira's visit next Tuesday") == true)
            XCTAssertNil(soap?.organization.dueDate)
            XCTAssertNil(soap?.organization.reminderDate)
        }
    }

    func testDatedTopicFrameWithActionInSameIOSSegmentOwnsTheActionGroup() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            let screening = ThoughtExtractionEngine.extractWithRules(
                "At the start of this recording I want to keep a detail: the old cinema used "
                    + "velvet green seats and projected a little moon logo before each film. "
                    + "Now my mind is on Monday's screening, and in the middle of the week I "
                    + "need to email the venue about wheelchair seating and send Omar the "
                    + "ticket link. I'm probably overexplaining, but the cinema detail is a "
                    + "memory, not an instruction to contact them. Right at the end: bring "
                    + "the portable charger on Monday. Please don't lose the last step because "
                    + "of the story.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(screening.items.count, 4)
            for phrase in ["email the venue", "send Omar"] {
                let action = screening.items.first {
                    $0.analysisText.localizedCaseInsensitiveContains(phrase)
                }
                XCTAssertTrue(action?.suggestedTitle?.contains("Monday's screening") == true,
                              screening.items.map { "\($0.analysisText) => \($0.suggestedTitle ?? "nil")" }
                                .joined(separator: " | "))
                XCTAssertNil(action?.organization.reminderDate)
            }
            XCTAssertFalse(screening.items.contains {
                $0.analysisText.hasPrefix("Now my mind")
            })
        }
    }

    func testReferentRolesWorkAcrossOtherSurfaceFormsAndLeaveFactsIndependent() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            let topic = ThoughtExtractionEngine.extractWithRules(
                "Turning to Wednesday's workshop: email the host and send Priya the slides.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(topic.items.count, 2)
            XCTAssertTrue(topic.items.allSatisfy {
                $0.organization.itemType.isActionable
                    && $0.suggestedTitle?.contains("Wednesday's workshop") == true
                    && $0.organization.reminderDate == nil
            })

            let arrival = ThoughtExtractionEngine.extractWithRules(
                "For Ravi's arrival Friday, clean the guest room. Buy flowers before Ravi arrives.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertTrue(arrival.items.contains {
                $0.analysisText.localizedCaseInsensitiveContains("flowers")
                    && $0.suggestedTitle?.contains("Ravi's arrival Friday") == true
                    && $0.organization.reminderDate == nil
            })

            let fact = ThoughtExtractionEngine.extractWithRules(
                "Remember that Wednesday's workshop is in the library.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(fact.items.count, 1)
            XCTAssertFalse(fact.items[0].organization.itemType.isActionable)
        }
    }

    func testTemporalAnchorOppositesKeepDirectTimingAndRejectCompetingContext() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            let direct = ThoughtExtractionEngine.extractWithRules(
                "The ferry leaves Saturday at 7:15. Leave for the station at 6:30 AM on "
                    + "Saturday in time for that ferry.",
                referenceDate: anchor, calendar: calendar
            )
            let leave = direct.items.last
            XCTAssertEqual(leave?.organization.temporalIntent.time?.hour, 6)
            XCTAssertEqual(leave?.organization.temporalIntent.time?.minute, 30)
            XCTAssertTrue(leave?.suggestedTitle?.contains("7:15") == true)

            let competing = ThoughtExtractionEngine.extractWithRules(
                "For Amira's visit next Tuesday, wash towels. For Amira's arrival Thursday, "
                    + "change sheets. Pick up soap before Amira arrives.",
                referenceDate: anchor, calendar: calendar
            )
            let soap = competing.items.last
            XCTAssertFalse(soap?.suggestedTitle?.contains("next Tuesday") == true)
            XCTAssertFalse(soap?.suggestedTitle?.contains("Thursday") == true)
            XCTAssertNil(soap?.organization.reminderDate)
            XCTAssertTrue(soap?.needsReview == true)

            let otherPerson = ThoughtExtractionEngine.extractWithRules(
                "For Amira's visit next Tuesday, wash towels. Buy soap before Sarah arrives.",
                referenceDate: anchor, calendar: calendar
            )
            let otherSoap = otherPerson.items.last
            XCTAssertFalse(otherSoap?.suggestedTitle?.contains("Amira's visit") == true)
            XCTAssertNil(otherSoap?.organization.reminderDate)

            let simple = ThoughtExtractionEngine.extractWithRules(
                "Call Mom tomorrow", referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(simple.items.count, 1)
            XCTAssertEqual(simple.items[0].organization.temporalIntent.kind, .dateOnly)
            XCTAssertEqual(ThoughtTitleFormatter.polished(simple.items[0].suggestedTitle ?? simple.items[0].analysisText,
                itemType: simple.items[0].organization.itemType), "Call Mom tomorrow")

            let idea = ThoughtExtractionEngine.extractWithRules(
                "Remember that Amira's idea for next Tuesday is a garden mural.",
                referenceDate: anchor, calendar: calendar
            )
            XCTAssertEqual(idea.items.count, 1)
            XCTAssertFalse(idea.items[0].organization.itemType.isActionable)
        }
    }

    func testCommunicationContentTimeDoesNotBecomeTheMessageDeadline() throws {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            for source in [
                "Message Jo that dinner is at seven",
                "I should message Jo that dinner is at seven",
                "While I am talking I should message Jo that dinner is at seven"
            ] {
                let message = ThoughtOrganizer.organize(
                    source, referenceDate: anchor, calendar: calendar
                )
                XCTAssertTrue(message.itemType.isActionable, source)
                XCTAssertNil(message.dueDate, source)
                XCTAssertNil(message.reminderDate, source)
            }

            let scheduled = ThoughtOrganizer.organize(
                "Message Jo tomorrow at noon", referenceDate: anchor,
                calendar: calendar
            )
            XCTAssertEqual(scheduled.temporalIntent.kind, .exactDateTime)
            XCTAssertEqual(scheduled.temporalIntent.time?.hour, 12)

            let reported = ThoughtOrganizer.organize(
                "Jo said dinner is at seven", referenceDate: anchor,
                calendar: calendar
            )
            XCTAssertFalse(reported.itemType.isActionable)
            XCTAssertNil(reported.dueDate)

            // Exposed U19 remains a development regression, not qualification.
            // Its message content must not schedule the act of messaging.
            let mixed = ThoughtExtractionEngine.extractWithRules(
                "Put milk on the shopping list. Actually scratch milk; there's an "
                    + "unopened carton in the fridge. We do need eggs and rice, and "
                    + "while I am talking I should message Jo that dinner is at seven. "
                    + "The thing about the milk is useful as the reason I changed "
                    + "my mind, not a purchase. If the list hears my first sentence "
                    + "only, it would be wrong.",
                referenceDate: anchor, calendar: calendar
            )
            let message = mixed.items.first {
                $0.organization.itemType == .personFollowUp
                    && $0.analysisText.localizedCaseInsensitiveContains("message Jo")
            }
            XCTAssertNotNil(message, mixed.items.map {
                "\($0.organization.itemType): \($0.analysisText)"
            }.joined(separator: " | "))
            XCTAssertNil(message?.organization.dueDate)
        }
    }

    func testFrontedCommitmentOpensAClauseOnlyOutsideReportedContent() {
        let direct = RuleBasedThoughtExtractor.splitClauses(
            "Buy eggs and while I am away I should message Jo that dinner is at seven"
        )
        XCTAssertEqual(direct.count, 2)
        XCTAssertTrue(direct[0].localizedCaseInsensitiveContains("buy eggs"))
        XCTAssertTrue(direct[1].localizedCaseInsensitiveContains("message Jo"))

        XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses("Buy eggs and rice").count, 1)
        let embedded = RuleBasedThoughtExtractor.splitClauses(
            "Message Jo that I should buy eggs and while I am away I should call Bea"
        )
        XCTAssertEqual(embedded.count, 1)
    }

    func testCalendarWeekWindowStaysUsableWithoutInventingADueDayOrAlert() throws {
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
            let task = try repository.createCapture(
                text: "Book the car for its tire change next week",
                source: .inAppText,
                createdAt: anchor,
                schedulesReminder: false
            )
            let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: anchor))
            let start = week.end
            let nextEnd = try XCTUnwrap(calendar.date(byAdding: .weekOfYear, value: 1, to: start))
            let last = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: nextEnd))
            XCTAssertEqual(task.temporalIntent?.kind, .calendarWindow)
            XCTAssertEqual(task.temporalIntent?.day, CalendarDay(from: start, calendar: calendar))
            XCTAssertEqual(task.temporalIntent?.windowEndDay, CalendarDay(from: last, calendar: calendar))
            XCTAssertNil(task.dueDate)
            XCTAssertNil(task.reminderDate)
            XCTAssertNil(task.reminderTrigger)
            XCTAssertFalse(task.needsClarification)
            XCTAssertEqual(TodayActionTiming.group(for: task, relativeTo: anchor, calendar: calendar), .comingUp)
            XCTAssertEqual(TodayActionTiming.group(for: task, relativeTo: start, calendar: calendar), .today)
            XCTAssertEqual(TodayActionTiming.group(for: task, relativeTo: nextEnd, calendar: calendar), .overdue)

            let authorization = LocationAuthorization(
                status: .always, isPrecise: true, isRegionMonitoringAvailable: true
            )
            let presentation = ItemPresentation.make(
                for: task, authorization: authorization, now: anchor, calendar: calendar
            )
            XCTAssertEqual(presentation.destination, .comingUp)
            XCTAssertNotNil(presentation.primaryTimingText)
            XCTAssertFalse(presentation.reminderState.isArmed)

            let reminder = try repository.createCapture(
                text: "Remind me to book the car next week",
                source: .inAppText,
                createdAt: anchor,
                schedulesReminder: false
            )
            XCTAssertTrue(reminder.needsClarification)
            XCTAssertNil(reminder.reminderDate)

            let clockWithoutDay = try repository.createCapture(
                text: "Remind me to book the car next week at 5",
                source: .inAppText,
                createdAt: anchor,
                schedulesReminder: false
            )
            XCTAssertTrue(clockWithoutDay.needsClarification)
            XCTAssertNil(clockWithoutDay.dueDate)
            XCTAssertNil(clockWithoutDay.reminderDate)

            let namedDay = try repository.createCapture(
                text: "Book the car next week Tuesday",
                source: .inAppText,
                createdAt: anchor,
                schedulesReminder: false
            )
            XCTAssertEqual(namedDay.temporalIntent?.kind, .dateOnly)
            XCTAssertNotNil(namedDay.dueDate)

            let ordinal = try repository.createCapture(
                text: "Book the car next week on the 10th",
                source: .inAppText,
                createdAt: anchor,
                schedulesReminder: false
            )
            XCTAssertEqual(ordinal.temporalIntent?.kind, .dateOnly)
            XCTAssertEqual(ordinal.temporalIntent?.day, CalendarDay(year: 2026, month: 8, day: 10))

            let namedZone = ThoughtOrganizer.organize(
                "Book the car next week London time",
                referenceDate: anchor,
                calendar: calendar
            )
            XCTAssertEqual(namedZone.temporalIntent.kind, .calendarWindow)
            XCTAssertEqual(namedZone.temporalIntent.timeZoneBehavior, .fixed)
            XCTAssertEqual(namedZone.temporalIntent.timeZoneIdentifier, "Europe/London")

            let taskID = task.id
            try relaunch()
            let reloaded = try loadItem(withID: taskID)
            XCTAssertEqual(reloaded.temporalIntent?.kind, .calendarWindow)
            XCTAssertEqual(reloaded.temporalIntent?.windowEndDay, CalendarDay(from: last, calendar: calendar))
        }
    }

    func testListPlacementScopesDayWithoutAlertAndNoDeadlineIsOnlyMetadata() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let result = ThoughtExtractionEngine.extractWithRules(
                "Send Pat the address. I have not picked a deadline for this first task. Return the projector to Noor. The projector has a cable in its case; return that too. Put this one on tomorrow's list.",
                referenceDate: anchor, calendar: calendar).items
            XCTAssertEqual(result.count, 2, result.map(\.sourceQuote).joined(separator: " | "))
            let message = result.first { $0.analysisText.contains("Send Pat") }
            XCTAssertNil(message?.organization.dueDate)
            XCTAssertTrue(message?.sourceQuote.contains("not picked a deadline") == true)
            let returned = result.first { $0.analysisText.contains("Return the projector") }
            XCTAssertEqual(returned?.organization.temporalIntent.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(returned?.organization.reminderDate)
            XCTAssertTrue(returned?.sourceQuote.contains("tomorrow's list") == true)
            let opposite = ThoughtExtractionEngine.extractWithRules(
                "Return the projector on Friday. Put this one on tomorrow's list.",
                referenceDate: anchor, calendar: calendar).items
            XCTAssertTrue(opposite.contains { $0.needsReview && $0.sourceQuote.contains("tomorrow's list") })
            XCTAssertTrue(opposite.contains { $0.organization.temporalIntent.day?.day == 9 })
            let factBoundary = ThoughtExtractionEngine.extractWithRules(
                "Return the projector. Remember the cupboard key is in the drawer. Put this one on tomorrow's list.",
                referenceDate: anchor, calendar: calendar).items
            XCTAssertTrue(factBoundary.contains { $0.needsReview && $0.sourceQuote.contains("tomorrow's list") })
            XCTAssertFalse(factBoundary.contains { $0.organization.temporalIntent.day?.day == 6 && !$0.needsReview })
            let literal = ThoughtExtractionEngine.extractWithRules(
                "Put the milk on tomorrow's shopping list.", referenceDate: anchor, calendar: calendar).items
            XCTAssertTrue(literal.contains { $0.organization.itemType.isActionable && $0.sourceQuote.contains("milk") })
        }
    }

    private var completeMovingCaptureSource: String { "I am trying to get the moving thoughts down in the order they come to me. Send Tessa the new address. The address should be sent as text as well as a photo because the small handwriting in the photograph is hard to read. I have not picked a deadline for this first task.\n\nI am pausing to think because I do not want to repeat the same job under a different title. The details I just added belong with that first action. They explain what a correct result would look like; they are not instructions to create a separate task for every object in the sentence.\n\nA fact I want to keep in the middle of this: The spare moving labels are in the orange envelope. That is where it is now. I am not asking to move it or to set a location reminder, just to preserve the information so I can search for it later.\n\nI am still thinking about the same collection of practical things, but this sentence is only about making the recording. A pause here should not mean I have finished speaking. There is one final obligation coming after this, and I want it to be as accessible as the first one.\n\nThe final task is this: Return the borrowed hand trolley to Gabe. The trolley has the removable strap tucked under its handle; return that too. Put this one on tomorrow's list. The first task still has no date, and the fact in the middle is still a Memory. Do not lose this last obligation just because the capture was already fairly long." }

    func testUnresolvedObjectEditKeepsClearDateAndUnrelatedItemsAcrossReopen() throws {
        let source = "Return that tomorrow. Buy eggs."
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let rows = try allItems()
            let held = try XCTUnwrap(rows.first { $0.originalTextSegment.contains("Return") })
            let eggs = try XCTUnwrap(rows.first { $0.itemType == .shopping })
            let eggsID = eggs.id
            let eggsTitle = eggs.displayTitle
            XCTAssertEqual(held.itemType, .task)
            XCTAssertEqual(held.semanticGapRawValue, "ambiguousObject")
            XCTAssertEqual(held.clarificationRequirement?.editorPrompt, "Name what this action refers to")
            XCTAssertEqual(held.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertTrue(held.needsClarification)
            XCTAssertNil(held.reminderDate)
            let id = held.id
            let original = held.originalTextSegment
            try repository.update(held, with: ItemEdits(
                title: "Return the blue photography book", itemType: .task,
                category: held.category, dueDate: held.dueDate, reminderDate: held.reminderDate,
                priority: held.priority, personName: held.personName, needsClarification: false,
                dueDateHasTime: false
            ))
            try relaunch()
            let updated = try loadItem(withID: id)
            XCTAssertFalse(updated.needsClarification)
            XCTAssertEqual(updated.semanticState, .resolved)
            XCTAssertEqual(updated.displayTitle, "Return the blue photography book")
            XCTAssertEqual(updated.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertEqual(updated.originalTextSegment, original)
            XCTAssertEqual(updated.captureSession?.originalTranscription, source)
            XCTAssertEqual(try allItems().count, 2)
            XCTAssertEqual(try loadItem(withID: eggsID).displayTitle, eggsTitle)
            XCTAssertNil(try loadItem(withID: eggsID).dueDate)
        }
    }

    func testUnresolvedObjectKeepsClockButCannotScheduleUntilEdited() throws {
        let source = "Remind me to return that tomorrow at 8 PM. Buy eggs."
        try withFixtureClock { calendar in
            // The scheduler correctly declines expired instants. Keep this
            // fixture ahead of the actual run while pinning the parsing zone.
            let anchor = Date.now
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let held = try XCTUnwrap(try allItems().first { $0.originalTextSegment.localizedCaseInsensitiveContains("return") })
            let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: anchor))
            let date = try XCTUnwrap(calendar.date(bySettingHour: 20, minute: 0, second: 0, of: tomorrow))
            XCTAssertEqual(held.reminderDate, date)
            XCTAssertTrue(held.needsClarification)
            XCTAssertNil(ReminderScheduleRequest(item: held), "a known clock must not arm an unresolved action")
            let id = held.id
            try repository.update(held, with: ItemEdits(
                title: "Return the projector", itemType: .task,
                category: held.category, dueDate: held.dueDate, reminderDate: held.reminderDate,
                priority: held.priority, personName: held.personName, needsClarification: false,
                dueDateHasTime: true
            ))
            try relaunch()
            let edited = try loadItem(withID: id)
            XCTAssertEqual(edited.semanticState, .resolved)
            XCTAssertEqual(edited.reminderDate, date)
            XCTAssertEqual(try XCTUnwrap(ReminderScheduleRequest(item: edited)).itemID, id)
            XCTAssertEqual(edited.captureSession?.originalTranscription, source)
            XCTAssertEqual(try allItems().count, 2)
        }
    }

    func testAmbiguousRecipientCorrectionCanBeLocallySplitWithoutLosingClocksAcrossReopen() throws {
        let source = "Remind me tomorrow at 9 AM to email the scan to Farah. Remind me tomorrow at 10 AM to text Farah about the keys. Actually, send it to Fariha, not Farah. Buy eggs."
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let session = try XCTUnwrap(repository.createCapture(
                text: source, source: .inAppText, createdAt: anchor, schedulesReminder: false).captureSession)
            let rows = try allItems()
            XCTAssertEqual(rows.count, 2, "only dependent communications wait; the eggs remain separate")
            let held = try XCTUnwrap(rows.first { $0.semanticState == .contested(.uncertainClauseBoundary) })
            let eggs = try XCTUnwrap(rows.first { $0.itemType == .shopping })
            let eggsID = eggs.id
            let eggsTitle = eggs.displayTitle
            let sessionID = session.id
            let heldID = held.id
            XCTAssertTrue(held.needsClarification)
            XCTAssertNil(ReminderScheduleRequest(item: held))
            for detail in ["9 AM", "10 AM", "scan", "keys", "not Farah"] {
                XCTAssertTrue(held.originalTextSegment.contains(detail), detail)
            }
            try relaunch()
            let reopened = try loadItem(withID: heldID)
            XCTAssertEqual(reopened.captureSession?.originalTranscription, source)
            // An explicit edit of only this dependent group identifies which
            // communication changed; the separate purchase is untouched.
            try repository.split(reopened, into: [
                "Remind me tomorrow at 9 AM to email the scan to Fariha",
                "Remind me tomorrow at 10 AM to text Farah about the keys"
            ])
            try relaunch()
            let saved = try allItems()
            XCTAssertEqual(saved.count, 3)
            let email = try XCTUnwrap(saved.first { $0.displayTitle.localizedCaseInsensitiveContains("email the scan") })
            let text = try XCTUnwrap(saved.first { $0.displayTitle.localizedCaseInsensitiveContains("text Farah") })
            XCTAssertTrue(email.displayTitle.contains("Fariha"))
            XCTAssertFalse(email.displayTitle.contains("Farah"))
            XCTAssertEqual(email.reminderDate, makeDate(year: 2026, month: 10, day: 6, hour: 9, calendar: calendar))
            XCTAssertEqual(text.reminderDate, makeDate(year: 2026, month: 10, day: 6, hour: 10, calendar: calendar))
            XCTAssertFalse(email.needsClarification)
            XCTAssertFalse(text.needsClarification)
            XCTAssertEqual(email.captureSession?.id, sessionID)
            XCTAssertEqual(text.captureSession?.originalTranscription, source)
            XCTAssertEqual(try loadItem(withID: eggsID).displayTitle, eggsTitle)
            XCTAssertNil(try loadItem(withID: eggsID).dueDate)
            let resolvedIDs = Set(saved.map(\.id))
            let unchangedTextID = text.id
            // A repeated submission from this resolved local editor must not
            // create a second copy of the unchanged communication.
            try repository.split(try loadItem(withID: heldID), into: [
                "Remind me tomorrow at 9 AM to email the scan to Fariha",
                "Remind me tomorrow at 10 AM to text Farah about the keys"
            ])
            try relaunch()
            XCTAssertEqual(Set(try allItems().map(\.id)), resolvedIDs)
            XCTAssertEqual(try allItems().count, 3)
            // A genuinely different explicit edit remains available.
            try repository.split(try loadItem(withID: heldID), into: [
                "Remind me tomorrow at 9 AM to email both scan pages to Fariha",
                "Call the studio tomorrow"
            ])
            try relaunch()
            XCTAssertEqual(try allItems().count, 4)
            XCTAssertEqual(try loadItem(withID: unchangedTextID).reminderDate,
                           makeDate(year: 2026, month: 10, day: 6, hour: 10, calendar: calendar))
            XCTAssertEqual(try loadItem(withID: eggsID).displayTitle, eggsTitle)
            XCTAssertEqual(try loadItem(withID: heldID).captureSession?.originalTranscription, source)
        }
    }

    func testExplicitRecipientCorrectionKeepsOneConditionalCommunicationAcrossReopen() throws {
        let source = "Email the scan to Farah once I have checked that both pages are readable. Actually, send it to Fariha, not Farah."
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let session = try XCTUnwrap(repository.createCapture(
                text: source, source: .inAppText, createdAt: anchor, schedulesReminder: false).captureSession)
            XCTAssertEqual(session.items.count, 1, session.items.map(\.displayTitle).joined(separator: " | "))
            let message = try XCTUnwrap(session.items.first { $0.itemType.isActionable })
            XCTAssertTrue(message.displayTitle.contains("Fariha"))
            XCTAssertFalse(message.displayTitle.contains("Farah"))
            XCTAssertEqual(message.personName, "Fariha")
            XCTAssertTrue(message.originalTextSegment.contains("both pages are readable"))
            XCTAssertTrue(message.originalTextSegment.contains("not Farah"), "the withdrawn recipient remains source evidence")
            XCTAssertFalse(message.needsClarification)
            XCTAssertNil(message.dueDate)
            XCTAssertNil(message.reminderDate)
            let id = message.id
            try relaunch()
            let reloaded = try loadItem(withID: id)
            XCTAssertEqual(reloaded.captureSession?.originalTranscription, source)
            XCTAssertEqual(reloaded.personName, "Fariha")
            XCTAssertEqual(try allItems().count, 1)
        }
    }

    func testRetainedIdeasAndPhysicalSaveKeepDifferentDestinationsAcrossReopen() throws {
        let source = "Keep web page and booklet as undecided ideas; do not create either as a task. Save the signed file to the project folder tomorrow. Buy eggs."
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let session = try XCTUnwrap(repository.createCapture(
                text: source, source: .inAppText, createdAt: anchor, schedulesReminder: false).captureSession)
            XCTAssertEqual(session.items.count, 3, session.items.map(\.displayTitle).joined(separator: " | "))
            let idea = try XCTUnwrap(session.items.first { $0.itemType == .idea })
            let file = try XCTUnwrap(session.items.first { $0.displayTitle.localizedCaseInsensitiveContains("signed file") })
            let eggs = try XCTUnwrap(session.items.first { $0.itemType == .shopping })
            XCTAssertTrue(idea.belongsInMemory)
            XCTAssertFalse(idea.belongsInToday)
            XCTAssertFalse(idea.needsClarification)
            XCTAssertTrue(idea.originalTextSegment.contains("web page and booklet"))
            XCTAssertTrue(idea.originalTextSegment.contains("do not create either as a task"))
            XCTAssertNil(idea.reminderDate)
            XCTAssertEqual(file.itemType, .task)
            XCTAssertTrue(file.belongsInToday)
            XCTAssertEqual(file.dueDate, makeDate(year: 2026, month: 10, day: 6, calendar: calendar))
            XCTAssertNil(file.reminderDate)
            let ideaID = idea.id
            let fileID = file.id
            let eggsID = eggs.id
            let ids = Set(session.items.map(\.id))
            try relaunch()
            XCTAssertEqual(Set(try allItems().map(\.id)), ids)
            XCTAssertEqual(try loadItem(withID: ideaID).itemType, .idea)
            XCTAssertEqual(try loadItem(withID: fileID).dueDate, makeDate(year: 2026, month: 10, day: 6, calendar: calendar))
            XCTAssertEqual(try loadItem(withID: eggsID).itemType, .shopping)
            XCTAssertEqual(try loadItem(withID: ideaID).captureSession?.originalTranscription, source)
        }
    }

    func testSequentialPrerequisiteTaskStaysAccessibleAcrossReopenWithoutAlert() async throws {
        let source = "Reprint the caption. Then ask Amira to check the new caption after I have printed it, not before. The printer is in the studio."
        var itemIDs: [UUID] = []
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let session = try XCTUnwrap(repository.createCapture(
                text: source, source: .inAppText, createdAt: anchor, schedulesReminder: true).captureSession)
            XCTAssertEqual(session.items.count, 3)
            let task = try XCTUnwrap(session.items.first { $0.originalTextSegment.contains("ask Amira") })
            XCTAssertTrue(task.belongsInToday)
            XCTAssertFalse(task.needsClarification)
            XCTAssertTrue(task.originalTextSegment.contains("after I have printed it, not before"))
            XCTAssertNil(task.temporalIntent?.unsupportedTrigger)
            XCTAssertNil(task.dueDate)
            XCTAssertNil(task.reminderDate)
            let taskID = task.id
            itemIDs = session.items.map(\.id)
            try relaunch()
            XCTAssertEqual(Set(try allItems().map(\.id)), Set(itemIDs))
            let reopened = try loadItem(withID: taskID)
            XCTAssertTrue(reopened.belongsInToday)
            XCTAssertFalse(reopened.needsClarification)
            XCTAssertEqual(reopened.captureSession?.originalTranscription, source)
            XCTAssertTrue(reopened.originalTextSegment.contains("after I have printed it, not before"))
        }
        await drainScheduler()
        for id in itemIDs {
            let requests = await pendingRequests(for: id)
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func testEmbeddedRecipientCorrectionKeepsSourceConditionAndIndependentTaskAcrossReopen() throws {
        let source = "email the scan to farah once i have checked that both pages are readable actually send it to fariha not farah they are different people the check matters because i sent a cropped scan once. Buy eggs."
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let session = try XCTUnwrap(repository.createCapture(
                text: source, source: .inAppText, createdAt: anchor, schedulesReminder: false).captureSession)
            XCTAssertEqual(session.items.count, 2, session.items.map(\.displayTitle).joined(separator: " | "))
            let email = try XCTUnwrap(session.items.first { $0.displayTitle.localizedCaseInsensitiveContains("email the scan") })
            let eggs = try XCTUnwrap(session.items.first { $0.itemType == .shopping })
            XCTAssertTrue(email.itemType.isActionable)
            XCTAssertFalse(email.needsClarification)
            XCTAssertTrue(email.displayTitle.localizedCaseInsensitiveContains("fariha"))
            XCTAssertFalse(email.displayTitle.localizedCaseInsensitiveContains("farah"))
            XCTAssertEqual(email.personName?.lowercased(), "fariha")
            XCTAssertTrue(email.originalTextSegment.contains("both pages are readable"))
            XCTAssertTrue(email.originalTextSegment.contains("not farah"))
            XCTAssertTrue(email.originalTextSegment.contains("cropped scan once"))
            XCTAssertNil(email.dueDate)
            XCTAssertNil(email.reminderDate)
            let emailID = email.id
            let eggsID = eggs.id
            let title = email.displayTitle
            try relaunch()
            XCTAssertEqual(try loadItem(withID: emailID).displayTitle, title)
            XCTAssertEqual(try loadItem(withID: emailID).captureSession?.originalTranscription, source)
            XCTAssertEqual(try loadItem(withID: eggsID).itemType, .shopping)
            XCTAssertEqual(try allItems().count, 2)
        }
    }

    func testRecipientCorrectionCorrectIntermediateKeepsConditionAndIndependentReturn() throws {
        // Diagnostic source substitutions only; the original assertion above
        // remains on the actual speech. This locates the missing relationship
        // independently of any later row/store representation failure.
        let sources = [
            "Email the scan to Fariha once I have checked that both pages are readable.",
            "Email Dana the budget spreadsheet tomorrow. Also return the extension cable to the equipment cupboard when I have a chance, without a reminder date."
        ]
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            for (index, source) in sources.enumerated() {
                let session = try XCTUnwrap(repository.createCapture(
                    text: source, source: .inAppText, createdAt: anchor.addingTimeInterval(Double(index * 30)),
                    schedulesReminder: false).captureSession)
                XCTAssertEqual(session.items.count, index == 0 ? 1 : 2)
                let message = try XCTUnwrap(session.items.first { $0.displayTitle.hasPrefix("Email") })
                XCTAssertTrue(message.displayTitle.contains(index == 0 ? "Fariha" : "Dana"))
                XCTAssertNil(message.reminderDate)
                if index == 0 {
                    XCTAssertTrue(message.originalTextSegment.contains("both pages are readable"))
                    XCTAssertNil(message.dueDate)
                } else {
                    XCTAssertEqual(message.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
                    let returned = try XCTUnwrap(session.items.first { $0.displayTitle.hasPrefix("Return") })
                    XCTAssertNil(returned.dueDate)
                    XCTAssertNil(returned.reminderDate)
                    XCTAssertFalse(returned.needsClarification)
                }
                XCTAssertEqual(session.originalTranscription, source)
            }
        }
    }

    func testNamedRecipientRevisionKeepsIndependentReturnAndDoesNotAmendOlderEmail() throws {
        let source = "Email Daniel the budget spreadsheet tomorrow. Also return the extension cable to the equipment cupboard when I have a chance, without a reminder date. Sorry, send the spreadsheet to Dana, not Daniel."
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let seed = try repository.createCapture(
                text: "Email Daniel about the old invoice next Monday", source: .inAppText,
                createdAt: anchor.addingTimeInterval(-60), schedulesReminder: false)
            let seedID = seed.id
            let seedTitle = seed.displayTitle
            let seedDate = seed.dueDate
            let seedModified = seed.lastModifiedAt
            let session = try XCTUnwrap(repository.createCapture(
                text: source, source: .inAppText, createdAt: anchor,
                schedulesReminder: false).captureSession)
            XCTAssertEqual(session.items.count, 2, session.items.map(\.displayTitle).joined(separator: " | "))
            let email = try XCTUnwrap(session.items.first { $0.displayTitle.hasPrefix("Email") })
            let returned = try XCTUnwrap(session.items.first { $0.displayTitle.hasPrefix("Return") })
            XCTAssertTrue(email.displayTitle.contains("Dana"))
            XCTAssertFalse(email.displayTitle.contains("Daniel"))
            XCTAssertEqual(email.personName, "Dana")
            XCTAssertEqual(email.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(email.reminderDate)
            XCTAssertNil(returned.dueDate)
            XCTAssertNil(returned.reminderDate)
            let emailID = email.id
            let returnID = returned.id
            try relaunch()
            XCTAssertEqual(try loadItem(withID: emailID).captureSession?.originalTranscription, source)
            XCTAssertEqual(try loadItem(withID: returnID).captureSession?.originalTranscription, source)
            let unchanged = try loadItem(withID: seedID)
            XCTAssertEqual(unchanged.displayTitle, seedTitle)
            XCTAssertEqual(unchanged.dueDate, seedDate)
            XCTAssertEqual(unchanged.lastModifiedAt, seedModified)
            XCTAssertEqual(try allItems().count, 3)
        }
    }

    func testDeclaredCommunicationQuestionPersistsWithoutContentDeadline() throws {
        let source = "Remember that the spare key is in the drawer. The last definite thing is to text Laila about borrowing the folding table. Ask whether she needs it back by Saturday. That is the question, not when I need to send the text."
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let rows = try allItems()
            XCTAssertEqual(rows.count, 2, rows.map(\.originalTextSegment).joined(separator: " | "))
            let message = try XCTUnwrap(rows.first { $0.belongsInToday })
            XCTAssertTrue(message.displayTitle.localizedCaseInsensitiveContains("text Laila"))
            XCTAssertTrue(message.originalTextSegment.contains("Ask whether she needs it back by Saturday"))
            XCTAssertTrue(message.originalTextSegment.contains("That is the question"))
            XCTAssertFalse(message.originalTextSegment.contains("spare key"))
            XCTAssertFalse(message.needsClarification)
            XCTAssertNil(message.dueDate)
            XCTAssertNil(message.reminderDate)
            XCTAssertNil(message.locationIntent)
            XCTAssertEqual(message.captureSession?.originalTranscription, source)
            let ids = Set(rows.map(\.id))
            let id = message.id
            try relaunch()
            XCTAssertEqual(Set(try allItems().map(\.id)), ids)
            XCTAssertEqual(try loadItem(withID: id).captureSession?.originalTranscription, source)
        }
    }

    func testLocatedBookReferencePersistsIdentityDetailAndDateWithoutAlert() throws {
        let source = "Then there is the library book. The blue photography book is still on the arm of the sofa under the folded blanket, which is probably why I kept missing it. Return that tomorrow."
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let rows = try allItems()
            XCTAssertEqual(rows.count, 1, rows.map(\.originalTextSegment).joined(separator: " | "))
            let returned = try XCTUnwrap(rows.first { $0.belongsInToday })
            XCTAssertTrue(returned.displayTitle.localizedCaseInsensitiveContains("blue photography book"))
            XCTAssertTrue(returned.originalTextSegment.contains("under the folded blanket"))
            XCTAssertFalse(returned.needsClarification)
            XCTAssertEqual(returned.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(returned.reminderDate)
            XCTAssertNil(returned.locationIntent)
            XCTAssertEqual(returned.captureSession?.originalTranscription, source)
            let id = returned.id
            try relaunch()
            XCTAssertEqual(try allItems().map(\.id), [id])
            XCTAssertEqual(try loadItem(withID: id).captureSession?.originalTranscription, source)
        }
    }

    func testProspectiveReminderCopulaIntermediateThroughPersistence() throws {
        // Test-only equivalent copula: the complete original failing input
        // keeps its original assertion elsewhere. This is stage evidence,
        // not success for the original future-copula capture.
        let original = "Email Jo the draft. I was going to say remind me at six tonight, but I will be away. Make it eight tonight."
        let intermediate = original.replacingOccurrences(of: "I will be away", with: "I am away")
        let diagnostic = XCTAttachment(string: "original clauses="
            + RuleBasedThoughtExtractor.splitClauses(original).joined(separator: " | ")
            + "\nintermediate clauses=" + RuleBasedThoughtExtractor.splitClauses(intermediate).joined(separator: " | "))
        diagnostic.name = "Prospective reminder copula stage differential"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: intermediate, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let rows = try allItems()
            XCTAssertEqual(rows.count, 1, rows.map(\.originalTextSegment).joined(separator: " | "))
            let email = try XCTUnwrap(rows.first)
            XCTAssertTrue(email.displayTitle.localizedCaseInsensitiveContains("email jo"))
            XCTAssertEqual(email.reminderDate, makeDate(year: 2026, month: 10, day: 5, hour: 20, calendar: calendar))
            XCTAssertTrue(email.originalTextSegment.contains("I am away"))
            XCTAssertEqual(email.captureSession?.originalTranscription, intermediate)
            XCTAssertFalse(email.needsClarification)
        }
    }

    func testProspectiveReminderRevisionKeepsCompleteOwnedPhotoOutcome() throws {
        let source = "I need to send the landlord the pictures of the patch beside the kitchen window. "
            + "Not the window itself, the paint underneath it where it has started bubbling again. "
            + "I took a better picture this morning with the blind open, so use that one rather than the dark picture from last night. "
            + "I was going to say remind me at six tonight, but I am out until late. "
            + "Make it eight tonight. Same pictures, same landlord."
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let rows = try allItems()
            XCTAssertEqual(rows.count, 1, rows.map { "\($0.itemType):\($0.originalTextSegment)" }.joined(separator: " | "))
            let photo = try XCTUnwrap(rows.first { $0.displayTitle.localizedCaseInsensitiveContains("send") })
            XCTAssertTrue(photo.belongsInToday)
            XCTAssertFalse(photo.needsClarification)
            XCTAssertTrue(photo.originalTextSegment.contains("paint underneath"))
            XCTAssertTrue(photo.originalTextSegment.contains("better picture this morning"))
            XCTAssertTrue(photo.originalTextSegment.contains("Make it eight"))
            XCTAssertEqual(photo.originalTextSegment, source, "Owned source must keep spoken order, including final identity confirmation")
            let finalTime = makeDate(year: 2026, month: 10, day: 5, hour: 20, calendar: calendar)
            XCTAssertEqual(photo.dueDate, finalTime)
            XCTAssertEqual(photo.reminderDate, finalTime)
            XCTAssertEqual(photo.captureSession?.originalTranscription, source)
            let id = photo.id
            try relaunch()
            XCTAssertEqual(try allItems().map(\.id), [id])
            XCTAssertEqual(try loadItem(withID: id).reminderDate, finalTime)
        }
    }

    func testContrastObjectRefinementPersistsWithItsActionAndOriginalSource() throws {
        let source = "I need to send the landlord the pictures of the patch beside the kitchen window. "
            + "Not the window itself, the paint underneath it where it has started bubbling again. "
            + "I took a better picture this morning with the blind open, so use that one rather than the dark picture from last night. "
            + "Email Jo tomorrow."
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let items = try allItems()
            XCTAssertEqual(items.count, 2, items.map(\.originalTextSegment).joined(separator: " | "))
            let sent = try XCTUnwrap(items.first { $0.displayTitle.localizedCaseInsensitiveContains("send") })
            XCTAssertTrue(sent.belongsInToday)
            XCTAssertTrue(sent.originalTextSegment.contains("Not the window itself"))
            XCTAssertTrue(sent.originalTextSegment.contains("paint underneath"))
            XCTAssertTrue(sent.originalTextSegment.contains("better picture this morning"))
            XCTAssertNil(sent.dueDate)
            XCTAssertNil(sent.reminderDate)
            XCTAssertFalse(sent.needsClarification)
            let email = try XCTUnwrap(items.first { $0.displayTitle.localizedCaseInsensitiveContains("email jo") })
            XCTAssertEqual(email.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertFalse(email.originalTextSegment.contains("paint"))
            XCTAssertTrue(items.allSatisfy { $0.captureSession?.originalTranscription == source })
            let ids = Set(items.map(\.id))
            let sourceBefore = sent.originalTextSegment
            let sentID = sent.id
            try relaunch()
            let reopened = try allItems()
            XCTAssertEqual(Set(reopened.map(\.id)), ids)
            XCTAssertEqual(try loadItem(withID: sentID).originalTextSegment, sourceBefore)
            XCTAssertTrue(reopened.allSatisfy { $0.captureSession?.originalTranscription == source })
        }
    }

    func testComponentAndOutputBoundaryIntermediateThroughPersistence() throws {
        // Test-only boundary substitution: identical words, three supplied
        // stops. This proves downstream ownership/persistence capability,
        // not success for the actual unpunctuated capture or microphone.
        let original = "i am trying to get the moving thoughts down in the order they come to me send tessa the new address the address should be sent as text as well as a photo because the small handwriting in the photograph is hard to read i have not picked a deadline for this first task\n\ni am pausing to think because i do not want to repeat the same job under a different title the details i just added belong with that first action they explain what a correct result would look like they are not instructions to create a separate task for every object in the sentence\n\na fact i want to keep in the middle of this the spare moving labels are in the orange envelope that is where it is now i am not asking to move it or to set a location reminder just to preserve the information so i can search for it later\n\ni am still thinking about the same collection of practical things but this sentence is only about making the recording a pause here should not mean i have finished speaking there is one final obligation coming after this and i want it to be as accessible as the first one\n\nthe final task is this return the borrowed hand trolley to gabe the trolley has the removable strap tucked under its handle return that too put this one on tomorrow's list the first task still has no date and the fact in the middle is still a memory do not lose this last obligation just because the capture was already fairly long"
        let intermediate = original
            .replacingOccurrences(of: "to gabe the trolley", with: "to gabe. the trolley")
            .replacingOccurrences(of: "list the first task", with: "list. the first task")
            .replacingOccurrences(of: "memory do not lose", with: "memory. do not lose")
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: intermediate, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let items = try allItems()
            XCTAssertEqual(items.count, 3, items.map { "\($0.itemType):\($0.originalTextSegment)" }.joined(separator: " | "))
            XCTAssertTrue(items.allSatisfy { !$0.needsClarification && $0.captureSession?.originalTranscription == intermediate })
            let address = try XCTUnwrap(items.first { $0.displayTitle.lowercased().hasPrefix("send tessa") })
            XCTAssertTrue(address.belongsInToday)
            XCTAssertTrue(address.originalTextSegment.contains("as text as well as a photo"))
            XCTAssertTrue(address.originalTextSegment.contains("first action"))
            XCTAssertNil(address.dueDate)
            let fact = try XCTUnwrap(items.first { $0.itemType == .note && $0.originalTextSegment.contains("orange envelope") })
            XCTAssertTrue(fact.belongsInMemory)
            let returned = try XCTUnwrap(items.first { $0.displayTitle.lowercased().hasPrefix("return the borrowed") })
            XCTAssertTrue(returned.belongsInToday)
            XCTAssertTrue(returned.originalTextSegment.contains("strap"))
            XCTAssertEqual(returned.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(returned.reminderDate)
        }
    }

    func testPunctuationLossMovingCaptureKeepsCompleteOwnedResults() throws {
        let source = "i am trying to get the moving thoughts down in the order they come to me send tessa the new address the address should be sent as text as well as a photo because the small handwriting in the photograph is hard to read i have not picked a deadline for this first task\n\ni am pausing to think because i do not want to repeat the same job under a different title the details i just added belong with that first action they explain what a correct result would look like they are not instructions to create a separate task for every object in the sentence\n\na fact i want to keep in the middle of this the spare moving labels are in the orange envelope that is where it is now i am not asking to move it or to set a location reminder just to preserve the information so i can search for it later\n\ni am still thinking about the same collection of practical things but this sentence is only about making the recording a pause here should not mean i have finished speaking there is one final obligation coming after this and i want it to be as accessible as the first one\n\nthe final task is this return the borrowed hand trolley to gabe the trolley has the removable strap tucked under its handle return that too put this one on tomorrow's list the first task still has no date and the fact in the middle is still a memory do not lose this last obligation just because the capture was already fairly long"
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let items = try allItems()
            let frame = source.range(of: "(?i)" + ActionabilityReader.nominalFactRecordingFramePattern, options: .regularExpression)
            let before = frame.map { String(source[..<$0.lowerBound]) } ?? "NO FRAME"
            let diagnostic = "scope=\(ClauseScope.read(source).act) before=\(ActionabilityReader.read(before)) pieces=" + ClauseJuxtaposition.pieces(in: before).map { "\(ActionabilityReader.read($0)):\($0)" }.joined(separator: " | ")
            XCTAssertEqual(items.count, 3, diagnostic + " rows=" + items.map { "\($0.itemType):\($0.originalTextSegment)" }.joined(separator: " | "))
            XCTAssertTrue(items.allSatisfy { !$0.needsClarification && $0.captureSession?.originalTranscription == source })
            let address = try XCTUnwrap(items.first { $0.displayTitle.lowercased().hasPrefix("send tessa") })
            XCTAssertTrue(address.belongsInToday)
            XCTAssertTrue(address.originalTextSegment.contains("as text as well as a photo"))
            XCTAssertTrue(address.originalTextSegment.contains("first action"))
            XCTAssertNil(address.dueDate)
            let fact = try XCTUnwrap(items.first { $0.itemType == .note && $0.originalTextSegment.contains("orange envelope") })
            XCTAssertTrue(fact.belongsInMemory)
            XCTAssertTrue(fact.originalTextSegment.contains("not asking to move"))
            let returned = try XCTUnwrap(items.first { $0.displayTitle.lowercased().hasPrefix("return the borrowed") })
            XCTAssertTrue(returned.belongsInToday)
            XCTAssertTrue(returned.originalTextSegment.contains("strap"))
            XCTAssertEqual(returned.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(returned.reminderDate)
        }
    }

    func testMovingFactOppositePersistsAsMemoryWithoutInventedTask() throws {
        let source = "Keep only this fact as a note, not a task: The spare moving labels are in the orange envelope."
        _ = try repository.createCapture(text: source, source: .inAppText, createdAt: .now, schedulesReminder: false)
        let items = try allItems()
        XCTAssertEqual(items.count, 1)
        let fact = try XCTUnwrap(items.first)
        XCTAssertEqual(fact.itemType, .note)
        XCTAssertTrue(fact.belongsInMemory)
        XCTAssertFalse(fact.belongsInToday)
        XCTAssertFalse(fact.needsClarification)
        XCTAssertEqual(fact.captureSession?.originalTranscription, source)
        XCTAssertNil(fact.dueDate)
        XCTAssertNil(fact.reminderDate)
    }

    func testConciseMovingCaptureOwnsDeclaredTasksAndDatedReturn() throws {
        let source = "Add my task to send Tessa the new address. The address should be sent as text as well as a photo because the small handwriting in the photograph is hard to read.. Keep this as a fact in Memory: The spare moving labels are in the orange envelope. On October 06, 2026, return the borrowed hand trolley to Gabe. The trolley has the removable strap tucked under its handle; return that too.."
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let items = try allItems()
            XCTAssertEqual(items.count, 3, items.map { "\($0.itemType):\($0.originalTextSegment)" }.joined(separator: " | "))
            XCTAssertTrue(items.allSatisfy { !$0.needsClarification && $0.captureSession?.originalTranscription == source })
            let address = try XCTUnwrap(items.first { $0.originalTextSegment.contains("send Tessa") })
            XCTAssertTrue(address.belongsInToday)
            XCTAssertTrue(address.originalTextSegment.contains("as text as well as a photo"))
            XCTAssertNil(address.dueDate)
            let fact = try XCTUnwrap(items.first { $0.itemType == .note && $0.originalTextSegment.contains("orange envelope") })
            XCTAssertFalse(fact.originalTextSegment.contains("return the borrowed"))
            let returned = try XCTUnwrap(items.first { $0.displayTitle.lowercased().contains("return the borrowed") })
            XCTAssertTrue(returned.belongsInToday)
            XCTAssertTrue(returned.originalTextSegment.contains("strap"))
            XCTAssertEqual(returned.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(returned.reminderDate)
        }
    }

    func testFilledMovingCaptureKeepsCompleteOwnedResults() throws {
        let prefixes = ["Um, let me think. ", "Right, okay. ", "Uh, one moment. ", "Well, let me get this down. ", "Um, let me think. "]
        let source = zip(prefixes, completeMovingCaptureSource.components(separatedBy: "\n\n"))
            .map { $0 + $1 }.joined(separator: "\n\n")
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let items = try allItems()
            XCTAssertEqual(items.count, 3, items.map { "\($0.itemType):\($0.originalTextSegment)" }.joined(separator: " | "))
            XCTAssertTrue(items.allSatisfy { !$0.needsClarification && $0.captureSession?.originalTranscription == source })
            let address = try XCTUnwrap(items.first { $0.displayTitle.hasPrefix("Send Tessa") })
            XCTAssertTrue(address.originalTextSegment.contains("as text as well as a photo"))
            XCTAssertTrue(address.originalTextSegment.contains("first action"))
            XCTAssertNil(address.dueDate)
            let fact = try XCTUnwrap(items.first { $0.itemType == .note && $0.originalTextSegment.contains("orange envelope") })
            XCTAssertTrue(fact.originalTextSegment.contains("not asking to move"))
            let returned = try XCTUnwrap(items.first { $0.displayTitle.hasPrefix("Return the borrowed") })
            XCTAssertTrue(returned.originalTextSegment.contains("strap"))
            XCTAssertEqual(returned.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(returned.reminderDate)
        }
    }

    func testLowercaseMovingCaptureKeepsCompleteOwnedResults() throws {
        let source = completeMovingCaptureSource.lowercased()
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let items = try allItems()
            XCTAssertEqual(items.count, 3, items.map { "\($0.itemType):\($0.originalTextSegment)" }.joined(separator: " | "))
            XCTAssertTrue(items.allSatisfy { !$0.needsClarification && $0.captureSession?.originalTranscription == source })
            let address = try XCTUnwrap(items.first { $0.displayTitle.lowercased().hasPrefix("send tessa") })
            XCTAssertTrue(address.originalTextSegment.contains("as text as well as a photo"))
            XCTAssertTrue(address.originalTextSegment.contains("first action"))
            XCTAssertNil(address.dueDate)
            let fact = try XCTUnwrap(items.first { $0.itemType == .note && $0.originalTextSegment.contains("orange envelope") })
            XCTAssertTrue(fact.originalTextSegment.contains("not asking to move"))
            let returned = try XCTUnwrap(items.first { $0.displayTitle.lowercased().hasPrefix("return the borrowed") })
            XCTAssertTrue(returned.originalTextSegment.contains("strap"))
            XCTAssertEqual(returned.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(returned.reminderDate)
        }
    }

    func testCompleteMovingCaptureKeepsResultDetailsMemoryAndFinalReturnAcrossRelaunch() throws {
        let source = completeMovingCaptureSource
        var ids = Set<UUID>()
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            // A test-only correctly scoped intermediate distinguishes missing
            // relationship interpretation from unsupported final meanings.
            let intermediate = ThoughtExtractionEngine.extractWithRules(
                "Send Tessa the new address as text with a photo. Remember the spare moving labels are in the orange envelope. Return the borrowed hand trolley and its strap to Gabe tomorrow.",
                referenceDate: anchor, calendar: calendar).items
            XCTAssertEqual(intermediate.count, 3, intermediate.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(intermediate.contains { $0.organization.itemType == .note
                && $0.analysisText.contains("orange envelope") })
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let items = try allItems()
            XCTAssertEqual(items.count, 3, items.map { "\($0.itemType):\($0.displayTitle):\($0.originalTextSegment)" }.joined(separator: " | "))
            XCTAssertTrue(items.allSatisfy { !$0.needsClarification
                && $0.captureSession?.originalTranscription == source })
            let address = try XCTUnwrap(items.first { $0.displayTitle.hasPrefix("Send Tessa") })
            XCTAssertNil(address.dueDate)
            XCTAssertNil(address.reminderDate)
            XCTAssertEqual(address.personName, "Tessa")
            XCTAssertTrue(address.originalTextSegment.contains("as text as well as a photo"))
            XCTAssertTrue(address.originalTextSegment.contains("handwriting"))
            let memory = try XCTUnwrap(items.first { $0.itemType == .note
                && $0.originalTextSegment.contains("orange envelope") })
            XCTAssertTrue(memory.displayTitle.contains("spare moving labels"))
            XCTAssertTrue(memory.belongsInMemory)
            XCTAssertFalse(memory.belongsInToday)
            let returned = try XCTUnwrap(items.first { $0.displayTitle.hasPrefix("Return the borrowed hand trolley") })
            XCTAssertEqual(returned.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(returned.reminderDate)
            XCTAssertTrue(returned.originalTextSegment.contains("removable strap"))
            XCTAssertTrue(returned.originalTextSegment.contains("return that too"))
            XCTAssertTrue(returned.originalTextSegment.contains("tomorrow's list"))
            ids = Set(items.map(\.id))
        }
        try relaunch()
        XCTAssertEqual(Set(try allItems().map(\.id)), ids)
        XCTAssertEqual(try allItems().count, 3)
        XCTAssertTrue(try allItems().allSatisfy { $0.captureSession?.originalTranscription == source })
    }

    func testCompoundNamesKeepPurchasesAndReferenceFactAccessibleAcrossRelaunch() throws {
        let source = "Buy a first aid kit for the club cupboard. I mean a basic kit to keep with the event supplies, and I have not given a purchase date. The words first aid are the name of the thing, not an instruction to buy something on the first day of a month.\n\nAlso look for a second hand monitor stand. Second hand means used, not the second day of a month. Keep those two purchases separate and do not interpret third party in this next sentence as a date either: remember that the club booking system is run by a third party provider."
        var ids: Set<UUID> = []
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            // Test-only synonymous search head proves the downstream types
            // and store can represent the intended three roots.
            let correctIntermediate = ThoughtExtractionEngine.extractWithRules(
                "Buy a first aid kit for the club cupboard. Find a second hand monitor stand. Remember that the club booking system is run by a third party provider.",
                referenceDate: anchor, calendar: calendar
            ).items
            XCTAssertEqual(correctIntermediate.count, 3)
            XCTAssertEqual(correctIntermediate.filter { $0.organization.itemType.isActionable }.count, 2)
            let repair = SpeechRepairPipeline.run(source, trackOrigins: true)
            let attachment = XCTAttachment(string: repair.corrected + "\nActual boundaries:\n"
                + RuleBasedThoughtExtractor.splitClauses(repair.corrected).joined(separator: "\n---\n"))
            attachment.name = "S082 actual repair and root differential"
            attachment.lifetime = .keepAlways
            add(attachment)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let items = try allItems()
            let saved = XCTAttachment(string: items.map {
                "\($0.itemType): \($0.displayTitle) time=\(String(describing: $0.temporalIntent?.kind)) quote=\($0.originalTextSegment)"
            }.joined(separator: "\n"))
            saved.name = "S082 complete saved meaning differential"
            saved.lifetime = .keepAlways
            add(saved)
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items.filter { $0.itemType.isActionable }.count, 2)
            XCTAssertTrue(items.allSatisfy { !$0.needsClarification && $0.personName == nil
                && $0.temporalIntent?.kind == TemporalKind.none && $0.dueDate == nil && $0.reminderDate == nil
                && $0.captureSession?.originalTranscription == source
                && $0.captureSession?.operationStateData == nil })
            let kit = try XCTUnwrap(items.first { $0.displayTitle.lowercased().contains("first aid kit") })
            XCTAssertTrue(kit.itemType.isActionable)
            XCTAssertTrue(kit.originalTextSegment.lowercased().contains("basic kit"))
            let stand = try XCTUnwrap(items.first { $0.displayTitle.lowercased().contains("monitor stand") })
            XCTAssertTrue(stand.itemType.isActionable)
            XCTAssertTrue(stand.displayTitle.lowercased().contains("look for"))
            XCTAssertTrue(stand.originalTextSegment.lowercased().contains("means used"))
            let provider = try XCTUnwrap(items.first { $0.displayTitle.lowercased().contains("booking system") })
            XCTAssertEqual(provider.itemType, .note)
            XCTAssertTrue(provider.displayTitle.lowercased().contains("third party provider"))
            ids = Set(items.map(\.id))
        }
        try relaunch()
        XCTAssertEqual(Set(try allItems().map(\.id)), ids)
        XCTAssertEqual(try allItems().count, 3)
        XCTAssertTrue(try allItems().allSatisfy { $0.captureSession?.originalTranscription == source
            && !$0.needsClarification && $0.temporalIntent?.kind == TemporalKind.none })
    }

    func testLowercaseCompoundExplanationRetainsCompleteIndependentMeanings() throws {
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let source = "buy a first aid kit for the club cupboard. i mean a basic kit to keep with the event supplies, and i have not given a purchase date. the words first aid are the name of the thing, not an instruction to buy something on the first day of a month. also look for a second hand monitor stand. second hand means used, not the second day of a month. keep those two purchases separate and do not interpret third party in this next sentence as a date either: remember that the club booking system is run by a third party provider."
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let items = try allItems()
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items.filter { $0.itemType.isActionable }.count, 2)
            XCTAssertTrue(items.allSatisfy { !$0.needsClarification && $0.dueDate == nil
                && $0.reminderDate == nil && $0.personName == nil })
            let search = try XCTUnwrap(items.first { $0.displayTitle.contains("monitor stand") })
            XCTAssertEqual(search.itemType, .task)
            XCTAssertFalse(search.displayTitle.contains("means"))
            XCTAssertTrue(search.originalTextSegment.contains("means used"))
            let kit = try XCTUnwrap(items.first { $0.displayTitle.contains("first aid kit") })
            XCTAssertFalse(kit.displayTitle.contains("mean"))
            XCTAssertTrue(kit.originalTextSegment.contains("basic kit"))
            XCTAssertTrue(items.contains { $0.itemType == .note
                && $0.displayTitle.contains("third party provider") })
            XCTAssertTrue(items.allSatisfy { $0.captureSession?.originalTranscription == source })
        }
    }

    func testDistinctCallsDoNotCreateTasksFromSharedOutputConstraints() throws {
        let source = "Call the equipment desk tomorrow to ask whether the tripod is available. Then call the same desk on Friday, October ninth, to confirm the collection slot. These are two calls for different purposes on different days, not a correction that replaces the first call with the second.\n\nThe first call is about availability and the second assumes I still need to settle the pickup details. Keep both accessible. They should not be collapsed merely because the recipient and action verb match, and no actual phone call should be placed by the app as part of saving these tasks."
        var ids: [UUID] = []
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            let repaired = SpeechRepairPipeline.run(source, trackOrigins: true)
            let stages = XCTAttachment(string: "Actual repaired source:\n" + repaired.corrected
                + "\nActual clause boundaries:\n"
                + RuleBasedThoughtExtractor.splitClauses(repaired.corrected).joined(separator: "\n---\n"))
            stages.name = "S097 actual repair and clause boundary differential"
            stages.lifetime = .keepAlways
            add(stages)
            // Test-only correct root/recipient intermediate proves that the
            // existing downstream pipeline can represent the required result.
            let intermediate = ThoughtExtractionEngine.extractWithRules(
                "Call the equipment desk tomorrow to ask whether the tripod is available. Then call the equipment desk on Friday, October ninth, to confirm the collection slot.",
                referenceDate: anchor, calendar: calendar
            ).items
            XCTAssertEqual(intermediate.count, 2)
            XCTAssertEqual(Set(intermediate.compactMap { $0.organization.temporalIntent.day?.day }), [6, 9])
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let items = try allItems()
            XCTAssertEqual(items.count, 2, "Only the two stated calls are new intentions.")
            for day in [6, 9] {
                let matches = items.filter { $0.temporalIntent?.day == CalendarDay(year: 2026, month: 10, day: day) }
                XCTAssertEqual(matches.count, 1)
                let item = try XCTUnwrap(matches.first)
                ids.append(item.id)
                XCTAssertTrue(item.itemType.isActionable)
                XCTAssertFalse(item.needsClarification)
                XCTAssertTrue(item.displayTitle.lowercased().contains("equipment desk"),
                              "The same-desk reference must keep the unique named recipient.")
                XCTAssertTrue(item.displayTitle.lowercased().contains(day == 6 ? "available" : "collection slot"))
                XCTAssertNil(item.personName)
                XCTAssertNil(item.reminderDate)
                XCTAssertEqual(item.captureSession?.originalTranscription, source)
                XCTAssertNil(item.captureSession?.operationStateData)
            }
        }
        try relaunch()
        XCTAssertEqual(try allItems().count, 2)
        for id in ids {
            let item = try loadItem(withID: id)
            XCTAssertEqual(item.captureSession?.originalTranscription, source)
            XCTAssertNil(item.reminderDate)
            XCTAssertFalse(item.needsClarification)
        }
    }

    func testDistinctCallRenderingsAndReplacementKeepTheirOwnMeanings() throws {
        let base = "Call the equipment desk tomorrow to ask whether the tripod is available. Then call the same desk on Friday, October ninth, to confirm the collection slot. These are two calls for different purposes on different days, not a correction that replaces the first call with the second.\n\nThe first call is about availability and the second assumes I still need to settle the pickup details. Keep both accessible. They should not be collapsed merely because the recipient and action verb match, and no actual phone call should be placed by the app as part of saving these tasks."
        let cases = [base.lowercased(),
                     "Um, let me think. " + base.replacingOccurrences(of: "The first call", with: "Right, okay. The first call"),
                     base.lowercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")]
        var ids: Set<UUID> = []
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            // These are distinct fixture captures, beyond the intentional
            // short retry deduplication window, with the same calendar day.
            for (index, source) in cases.enumerated() {
                let receipt = try repository.createCapture(text: source, source: .inAppText,
                                                          createdAt: anchor.addingTimeInterval(TimeInterval(index * 60)), schedulesReminder: false)
                let items = try allItems().filter { $0.captureSession?.id == receipt.captureSession?.id }
                XCTAssertEqual(items.count, 2, source)
                XCTAssertEqual(Set(items.compactMap { $0.temporalIntent?.day?.day }), [6, 9], source)
                XCTAssertTrue(items.allSatisfy { $0.displayTitle.lowercased().contains("equipment desk")
                    && $0.itemType.isActionable && !$0.needsClarification && $0.personName == nil
                    && $0.reminderDate == nil && $0.captureSession?.originalTranscription == source }, source)
                ids.formUnion(items.map(\.id))
            }
            let opposite = "Call the equipment desk on October ninth instead of tomorrow; it is the same availability call."
            let receipt = try repository.createCapture(text: opposite, source: .inAppText,
                                                      createdAt: anchor, schedulesReminder: false)
            let items = try allItems().filter { $0.captureSession?.id == receipt.captureSession?.id }
            XCTAssertEqual(items.count, 1)
            let call = try XCTUnwrap(items.first)
            XCTAssertEqual(call.temporalIntent?.day, CalendarDay(year: 2026, month: 10, day: 9))
            XCTAssertTrue(call.displayTitle.lowercased().contains("equipment desk"))
            XCTAssertFalse(call.needsClarification)
            XCTAssertEqual(call.captureSession?.originalTranscription, opposite)
            ids.insert(call.id)
        }
        try relaunch()
        XCTAssertEqual(Set(try allItems().map(\.id)), ids)
        XCTAssertEqual(try allItems().count, 7)
    }

    func testAdoptedObjectKeepsOwnScheduleAndIdentityAcrossRelaunch() throws {
        // Existing quote/adoption lineage, audited coverage gap: an explicitly
        // contrasting own day cannot be replaced by the reported instruction.
        let cases: [(String, Int?, String?, String)] = [
            ("The instructor said to bring the blue folder tomorrow. I agree and will bring it myself Friday.", 9, "tomorrow", "blue folder"),
            ("The instructor said to bring the blue folder tomorrow. I agree and will bring the blue folder myself Friday.", 9, "tomorrow", "blue folder"),
            ("The instructor said to bring the blue folder Friday. I agree and will bring it myself tomorrow.", 6, "friday", "blue folder"),
            ("The instructor said to bring the blue folder. I agree and will bring it myself tomorrow.", 6, nil, "blue folder"),
            ("The instructor said to bring the blue folder tomorrow. I agree and will bring it myself, but I have not chosen a day.", nil, "tomorrow", "blue folder"),
            ("The instructor said to bring the folder named Friday. I agree and will bring it myself tomorrow.", 6, nil, "folder named friday")
        ]
        var ids: [UUID] = []
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            for (index, entry) in cases.enumerated() {
                let item = try repository.createCapture(text: entry.0, source: .inAppText,
                    createdAt: anchor.addingTimeInterval(Double(index)), schedulesReminder: false)
                ids.append(item.id)
                XCTAssertEqual(item.captureSession?.items.count, 1, entry.0)
                XCTAssertEqual(item.captureSession?.originalTranscription, entry.0)
                XCTAssertTrue(item.itemType.isActionable, entry.0)
                XCTAssertFalse(item.needsClarification, entry.0)
                XCTAssertTrue(item.displayTitle.lowercased().contains(entry.3), entry.0)
                XCTAssertEqual(item.temporalIntent?.day?.day, entry.1, entry.0)
                XCTAssertNil(item.reminderDate, entry.0)
                if let wrongDay = entry.2 {
                    XCTAssertFalse(item.displayTitle.lowercased().contains(wrongDay),
                                   "The reported schedule must not become the own-task title: \(entry.0)")
                }
            }
        }
        try relaunch()
        XCTAssertEqual(try allItems().count, cases.count)
        for (index, entry) in cases.enumerated() {
            let item = try loadItem(withID: ids[index])
            XCTAssertEqual(item.captureSession?.originalTranscription, entry.0)
            XCTAssertEqual(item.temporalIntent?.day?.day, entry.1, entry.0)
            XCTAssertNil(item.reminderDate, entry.0)
        }
    }

    func testCompleteBareHourCaptureAndAnswerKeepIndependentShoppingAcrossReopen() throws {
        let source = "Remind me to send the form at seven tomorrow. I have not said morning or evening, and there is no established preference in this test that settles that. Do not choose an hour just to avoid asking me, because a twelve hour error would matter for this form.\n\nKeep the task and tomorrow's date, but hold the notification time until I answer. I also need to buy a folder, which has no date. The time question should be about the form only, not a reason to make me repeat the folder purchase or the whole capture."
        var formID = UUID()
        var folderID = UUID()
        var expected = Date.distantPast
        var folderSource = ""
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9, calendar: calendar)
            _ = try repository.createCapture(text: source, source: .inAppText,
                                             createdAt: anchor, schedulesReminder: false)
            let items = try allItems()
            XCTAssertEqual(items.count, 2)
            let form = try XCTUnwrap(items.first { $0.originalTextSegment.contains("send the form") })
            let folder = try XCTUnwrap(items.first { $0.originalTextSegment.contains("buy a folder") })
            formID = form.id
            folderID = folder.id
            folderSource = folder.originalTextSegment
            XCTAssertEqual(folder.itemType, .shopping)
            XCTAssertNil(folder.dueDate)
            XCTAssertNil(folder.reminderDate)
            XCTAssertFalse(folder.needsClarification)
            XCTAssertNil(form.reminderDate)
            XCTAssertEqual(form.semanticState, .underspecified(.ambiguousTemporalScope))
            let question = try XCTUnwrap(BareHourQuestion(item: form))
            expected = try XCTUnwrap(question.date(for: .evening))
            XCTAssertEqual(calendar.component(.hour, from: expected), 19)
            XCTAssertEqual(calendar.component(.day, from: expected), 6)
            let edits = ItemEdits(title: form.displayTitle, itemType: form.itemType,
                category: form.category, dueDate: expected, reminderDate: expected,
                priority: form.priority, personName: form.personName,
                needsClarification: false, dueDateHasTime: true)
            try repository.update(form, with: edits)
            try repository.update(form, with: edits)
            XCTAssertEqual(try allItems().count, 2)
            XCTAssertEqual(folder.originalTextSegment, folderSource)
            XCTAssertEqual(folder.id, folderID)
            XCTAssertNil(folder.dueDate)
            XCTAssertNil(folder.reminderDate)
        }
        try relaunch()
        let form = try loadItem(withID: formID)
        let folder = try loadItem(withID: folderID)
        XCTAssertEqual(try allItems().count, 2)
        XCTAssertEqual(form.dueDate, expected)
        XCTAssertEqual(form.reminderDate, expected)
        XCTAssertEqual(form.semanticState, .resolved)
        XCTAssertEqual(form.captureSession?.originalTranscription, source)
        XCTAssertEqual(folder.originalTextSegment, folderSource)
        XCTAssertEqual(folder.itemType, .shopping)
        XCTAssertNil(folder.dueDate)
        XCTAssertNil(folder.reminderDate)
        XCTAssertFalse(folder.needsClarification)
    }

    func testBareHourAnswerEditsOnlySavedTaskAndSurvivesRelaunch() throws {
        let source = "Remind me to send the form at seven tomorrow. "
            + "I have not said morning or evening. Also buy a folder."
        var formID = UUID()
        var expected = Date.distantPast
        try withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 10, day: 5, hour: 9,
                                  calendar: calendar)
            _ = try repository.createCapture(
                text: source, source: .inAppText, createdAt: anchor,
                schedulesReminder: false
            )
            let items = try allItems()
            let form = try XCTUnwrap(items.first {
                $0.originalTextSegment.contains("send the form")
            })
            formID = form.id
            let question = try XCTUnwrap(BareHourQuestion(item: form))
            XCTAssertEqual(question.hour, 7)
            XCTAssertNil(form.reminderDate)
            XCTAssertEqual(form.semanticState,
                           .underspecified(.ambiguousTemporalScope))
            expected = try XCTUnwrap(question.date(for: .evening))
            XCTAssertEqual(calendar.component(.hour, from: expected), 19)

            let edits = ItemEdits(
                title: form.displayTitle, itemType: form.itemType,
                category: form.category, dueDate: expected,
                reminderDate: expected, priority: form.priority,
                personName: form.personName, needsClarification: false,
                dueDateHasTime: true
            )
            try repository.update(form, with: edits)
            try repository.update(form, with: edits)
            XCTAssertEqual(try allItems().filter { $0.id == formID }.count, 1)
            XCTAssertTrue(form.originalTextSegment.contains(
                "Remind me to send the form at seven tomorrow"))
            XCTAssertTrue(form.originalTextSegment.contains(
                "I have not said morning or evening"))
            XCTAssertEqual(form.semanticState, .resolved)
        }
        try relaunch()
        let reloaded = try loadItem(withID: formID)
        XCTAssertEqual(reloaded.dueDate, expected)
        XCTAssertEqual(reloaded.reminderDate, expected)
        XCTAssertFalse(reloaded.needsClarification)
        XCTAssertEqual(reloaded.semanticState, .resolved)
        XCTAssertEqual(reloaded.captureSession?.originalTranscription, source)
    }

    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!
    private var storeURL: URL!
    private var previousRecurrences: [RecurrenceRecordSnapshot] = []
    private var scheduledCheck: (id: UUID, fireDate: Date)?

    /// The one zone this file writes its wall-clock expectations in.
    ///
    /// Only ever reached through `withFixtureClock`, which pins the device to
    /// it and hands out the matching calendar in the same breath.
    private static let fixtureTimeZoneIdentifier = "America/Toronto"

    override func setUpWithError() throws {
        previousRecurrences = RecurrenceStore.snapshots()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakItFullPath-\(UUID().uuidString).store")
        try openStore()
    }

    override func tearDownWithError() throws {
        RecurrenceStore.restore(previousRecurrences)
        repository = nil
        container = nil
        for suffix in ["", "-shm", "-wal"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Relaunch

    /// Opens the store the way the app does, through the real migration plan.
    private func openStore() throws {
        let configuration = ModelConfiguration(url: storeURL)
        container = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self,
            configurations: [configuration]
        )
        repository = SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            requestsReminderAuthorization: false
        )
    }

    /// The closest a test process can get to the app being killed and launched
    /// again: the container and every live model object are released, the store
    /// is reopened from disk, and the same recovery pass the app runs at launch
    /// runs again. Only the system clock is not moved, because no simulator
    /// facility can move it independently of the host.
    /// A brand-new empty persistent store, for loops over independent cases.
    private func relaunchFresh() throws {
        repository = nil
        container = nil
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakItFullPath-\(UUID().uuidString).store")
        try openStore()
    }

    private func relaunch() throws {
        repository = nil
        container = nil
        try openStore()
        repository.recoverUnorganizedCaptures()
        repository.reconcilePendingReminders()
    }

    private func allItems() throws -> [CapturedItem] {
        try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
    }

    private func loadItem(withID id: UUID) throws -> CapturedItem {
        try XCTUnwrap(try allItems().first { $0.id == id })
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    /// Runs `body` with the device pinned to `fixtureTimeZoneIdentifier`,
    /// handing it the calendar for that same zone.
    ///
    /// The pin and the calendar are only reachable together, and both come from
    /// one constant, so they cannot disagree. That pairing is the point: a test
    /// that builds its expectation in Toronto while the app under test resolves
    /// through `Calendar.autoupdatingCurrent` — which follows the machine — is
    /// not testing the app, it is testing where the developer lives. Six tests
    /// here were written that way and passed only on a Mac set to Toronto.
    ///
    /// Deliberately scoped rather than hoisted into `setUp`. Pinning the whole
    /// test case also pins the stretch where `ReminderScheduler` builds its
    /// `UNCalendarNotificationTrigger`, and that path does not follow
    /// `NSTimeZone.default`: the wall clock it writes into the trigger is then
    /// read back in the machine's own zone, moving every scheduled reminder by
    /// the offset between the two and silently dropping the ones that land in
    /// the past. Anything asserting on `UNUserNotificationCenter` has to run in
    /// the machine's zone, so the pin stops where scheduling starts.
    private func withFixtureClock(_ body: (Calendar) throws -> Void) rethrows {
        try withDeviceTimeZone(Self.fixtureTimeZoneIdentifier) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: Self.fixtureTimeZoneIdentifier)!
            try body(calendar)
        }
    }

    /// `ReminderScheduler.synchronize` is deliberately fire-and-forget, ordered
    /// behind a serial tail task. Reading the pending set without waiting for
    /// that tail is a race, and a racing assertion that something is *absent*
    /// passes for the wrong reason. Draining with an empty, empty-scoped request
    /// waits for the tail and removes nothing.
    private func drainScheduler() async {
        _ = await ReminderScheduler.synchronizeAndVerify(
            [],
            requestAuthorizationIfNeeded: false,
            scope: ReminderSynchronizationScope()
        )
    }

    private func pendingRequests(for itemID: UUID) async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().filter { request in
            request.identifier.contains(itemID.uuidString) ||
                (request.content.userInfo["itemIDs"] as? [String])?
                    .contains(itemID.uuidString) == true
        }
    }

    /// A fresh test install can grant provisional authorization without a
    /// system prompt. This exercises actual notification-center scheduling
    /// instead of silently skipping every integration assertion on fresh CI.
    /// A deliberately denied installation is still skipped, not overridden.
    private func requireNotificationAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
        }
        let status = await center.notificationSettings().authorizationStatus
        try XCTSkipUnless(
            status == .authorized || status == .provisional || status == .ephemeral,
            "notification permission is not granted on this simulator"
        )
    }

    // MARK: Recurrence intent survival through the real series

    /// The generated occurrence of a series must carry the same intent as the
    /// one it replaces.
    ///
    /// Without it the series has no intended wall clock from its second
    /// occurrence onward, and `nextRecurrenceDate` falls back to deriving each
    /// occurrence from the previous resolved instant — which is exactly the
    /// permanent daylight-saving drift `preferredWallClock` exists to prevent.
    /// The resolver's own tests cannot see this, because they are handed the
    /// intended clock directly.
    func testGeneratedOccurrenceInheritsTheSeriesIntent() throws {
        let item = try repository.createCapture(
            text: "Take my pills every day at 2:30 AM",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(item.temporalKind, .calendarRecurrence)
        XCTAssertEqual(item.temporalIntent?.time, WallClockTime(hour: 2, minute: 30))

        try repository.setCompleted(item, completed: true)

        let nextID = try XCTUnwrap(
            RecurrenceStore.generatedNextItemID(for: item.id),
            "completing a recurring item should generate the next occurrence"
        )
        let next = try loadItem(withID: nextID)

        XCTAssertEqual(
            next.temporalKind,
            .calendarRecurrence,
            "the next occurrence is still a repeating wall clock"
        )
        XCTAssertEqual(
            next.temporalIntent?.time,
            WallClockTime(hour: 2, minute: 30),
            "the intended clock must survive onto the generated occurrence, or the series drifts"
        )
        XCTAssertEqual(next.temporalIntent?.recurrence, item.temporalIntent?.recurrence)
    }

    /// The consequence of the above, measured where it actually hurts: a series
    /// completed repeatedly across a spring-forward must come back to 2:30 AM.
    ///
    /// March 14 2027 is a real future transition, so this runs against the real
    /// tzdata rules rather than a hand-built fixture.
    func testDailySeriesReturnsToItsClockAfterSpringForward() throws {
        try withFixtureClock { calendar in
            let captureTime = makeDate(year: 2027, month: 3, day: 13, hour: 1, calendar: calendar)

            var current = try repository.createCapture(
                text: "Take my pills every day at 2:30 AM",
                source: .inAppText,
                createdAt: captureTime,
                schedulesReminder: false
            )
            XCTAssertEqual(
                calendar.dateComponents([.day, .hour, .minute], from: try XCTUnwrap(current.dueDate)),
                DateComponents(day: 13, hour: 2, minute: 30)
            )

            // Occurrence on the transition day: 2:30 does not exist, so the policy
            // is the first instant that does.
            try repository.setCompleted(current, completed: true)
            var nextID = try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: current.id))
            current = try loadItem(withID: nextID)
            var components = calendar.dateComponents(
                [.month, .day, .hour, .minute],
                from: try XCTUnwrap(current.dueDate)
            )
            XCTAssertEqual(components.day, 14)
            XCTAssertEqual(components.hour, 3, "2:30 AM does not exist on a spring-forward day")
            XCTAssertEqual(components.minute, 0)

            // And the day after must return to 2:30, not stay at 3:00 forever.
            try repository.setCompleted(current, completed: true)
            nextID = try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: current.id))
            current = try loadItem(withID: nextID)
            components = calendar.dateComponents(
                [.month, .day, .hour, .minute],
                from: try XCTUnwrap(current.dueDate)
            )
            XCTAssertEqual(components.day, 15)
            XCTAssertEqual(
                components.hour,
                2,
                "the series must return to the clock it was asked for, not adopt the transition-day nudge"
            )
            XCTAssertEqual(components.minute, 30)
        }
    }

    /// The fall-back half of the policy, through the same real path. November 1
    /// 2026 has two 1:30 AMs; the series must take the first and stay on 1:30.
    func testDailySeriesFiresOnceAcrossFallBack() throws {
        try withFixtureClock { calendar in
            let captureTime = makeDate(year: 2026, month: 10, day: 31, hour: 1, calendar: calendar)

            var current = try repository.createCapture(
                text: "Log the meter reading every day at 1:30 AM",
                source: .inAppText,
                createdAt: captureTime,
                schedulesReminder: false
            )
            let firstDue = try XCTUnwrap(current.dueDate)
            XCTAssertEqual(
                calendar.dateComponents([.day, .hour, .minute], from: firstDue),
                DateComponents(day: 31, hour: 1, minute: 30)
            )

            try repository.setCompleted(current, completed: true)
            let nextID = try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: current.id))
            current = try loadItem(withID: nextID)
            let transitionDue = try XCTUnwrap(current.dueDate)
            let components = calendar.dateComponents([.day, .hour, .minute], from: transitionDue)
            XCTAssertEqual(components.day, 1)
            XCTAssertEqual(components.hour, 1)
            XCTAssertEqual(components.minute, 30)
            XCTAssertEqual(
                transitionDue.timeIntervalSince(firstDue),
                24 * 60 * 60,
                "the first of the two 1:30s is 24 hours later; landing on the second would be 25"
            )
        }
    }

    // MARK: Invariants

    /// Resolving an intent must never modify the intent. Asserted over every
    /// kind rather than one example, because the failure is silent.
    func testResolvingNeverMutatesTheIntent() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 20, hour: 10, calendar: calendar)
            let intents: [TemporalIntent] = [
                .none,
                TemporalIntent(kind: .dateOnly, day: CalendarDay(year: 2026, month: 8, day: 21)),
                TemporalIntent(
                    kind: .exactDateTime,
                    day: CalendarDay(year: 2026, month: 8, day: 21),
                    time: WallClockTime(hour: 15, minute: 0)
                ),
                TemporalIntent(kind: .relativeDuration, relativeSeconds: 3600),
                TemporalIntent(
                    kind: .calendarRecurrence,
                    day: CalendarDay(year: 2026, month: 8, day: 21),
                    time: WallClockTime(hour: 9, minute: 0),
                    recurrence: RecurrenceRule(frequency: .daily)
                ),
                TemporalIntent(
                    kind: .durationRecurrence,
                    relativeSeconds: 86_400,
                    recurrence: RecurrenceRule(frequency: .daily, intervalSeconds: 86_400)
                )
            ]

            for intent in intents {
                let before = intent
                for wantsReminder in [true, false] {
                    _ = TemporalResolver.resolve(
                        intent,
                        anchor: anchor,
                        calendar: calendar,
                        wantsReminder: wantsReminder
                    )
                }
                _ = TemporalResolver.nextOccurrence(of: intent, after: anchor, calendar: calendar)
                XCTAssertEqual(intent, before, "resolution must be a pure read of \(intent.kind)")
            }
        }
    }

    /// The 9 AM default is a property of the notification. A date-only item may
    /// alert at 9, but must still say it carries no time of day — otherwise the
    /// editor, the row, and the next reparse all start believing the person
    /// said nine o'clock.
    func testDateOnlyReminderDefaultIsNeverWrittenIntoTheIntent() throws {
        try withFixtureClock { calendar in
            let createdAt = makeDate(year: 2026, month: 8, day: 20, hour: 10, calendar: calendar)

            let plain = try repository.createCapture(
                text: "Buy milk tomorrow",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            XCTAssertEqual(plain.temporalKind, .dateOnly)
            XCTAssertNil(plain.temporalIntent?.time, "no time of day was expressed")
            XCTAssertNil(plain.reminderDate, "a bare date-only item schedules nothing")

            let reminded = try repository.createCapture(
                text: "Remind me to buy milk tomorrow",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            XCTAssertEqual(reminded.temporalKind, .dateOnly, "still a day, not a moment")
            XCTAssertNil(
                reminded.temporalIntent?.time,
                "the derived 9 AM belongs to the notification, never to the intent"
            )
            let reminderDate = try XCTUnwrap(reminded.reminderDate)
            XCTAssertEqual(
                calendar.dateComponents([.hour, .minute], from: reminderDate),
                DateComponents(hour: TemporalResolver.dateOnlyAlertHour, minute: 0)
            )
        }
    }

    /// The moment a bare day alerts at is the person's to choose. Setting it
    /// moves "remind me tomorrow" and nothing else: the intent still says no
    /// time was expressed, and "tomorrow morning" keeps meaning the morning.
    func testDefaultReminderTimeIsAPreference() throws {
        XCTAssertEqual(ReminderDefaults.alertTime, ReminderDefaults.fallback, "9:00 until set")
        ReminderDefaults.alertTime = WallClockTime(hour: 7, minute: 30)
        defer { ReminderDefaults.reset() }
        XCTAssertEqual(TemporalResolver.dateOnlyAlertHour, 7)
        XCTAssertEqual(TemporalResolver.dateOnlyAlertMinute, 30)

        try withFixtureClock { calendar in
            let createdAt = try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026, month: 8, day: 3, hour: 10
            )))
            let reminded = try repository.createCapture(
                text: "Remind me to buy milk tomorrow",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            XCTAssertEqual(reminded.temporalKind, .dateOnly)
            XCTAssertNil(reminded.temporalIntent?.time, "the preference is the notification's, not the intent's")
            let reminderDate = try XCTUnwrap(reminded.reminderDate)
            XCTAssertEqual(
                calendar.dateComponents([.hour, .minute], from: reminderDate),
                DateComponents(hour: 7, minute: 30)
            )

            let morning = try repository.createCapture(
                text: "Tomorrow morning call Dave",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            let due = try XCTUnwrap(morning.dueDate)
            XCTAssertEqual(
                calendar.dateComponents([.hour, .minute], from: due),
                DateComponents(hour: TemporalResolver.morningHour, minute: 0),
                "morning is a fact about English, not the preference"
            )
        }

        ReminderDefaults.reset()
        XCTAssertEqual(ReminderDefaults.alertTime, ReminderDefaults.fallback)
    }

    /// A location phrase is understood, not unclear — the guarantee that
    /// predates place reminders and outlived them. It is now recorded as a place
    /// trigger rather than as an unsupported one, and still never as ambiguity.
    func testLocationPhraseIsATriggerNotAmbiguity() throws {
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(item.locationIntent?.place, .home)
        XCTAssertEqual(item.reminderTriggerKind, .location)
        XCTAssertNil(item.temporalIntent?.unsupportedTrigger)
        XCTAssertNotEqual(
            item.clarificationRequirement,
            .time,
            "asking 'what did you mean?' about a perfectly clear sentence is the bug"
        )
    }

    // MARK: Manual edits

    /// A hand-set date outranks the sentence forever. Relaunching runs the
    /// backfill and the recovery pass again; neither may reparse the wording
    /// back over the correction.
    func testManualEditSurvivesRelaunchAndRecovery() throws {
        try withFixtureClock { calendar in
            let createdAt = makeDate(year: 2026, month: 8, day: 20, hour: 10, calendar: calendar)
            let item = try repository.createCapture(
                text: "Remind me to call the dentist tomorrow at 3 PM",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            let itemID = item.id

            let corrected = makeDate(year: 2026, month: 9, day: 4, hour: 18, minute: 45, calendar: calendar)
            try repository.update(item, with: ItemEdits(
                title: "Call the dentist",
                itemType: .task,
                category: .personal,
                dueDate: corrected,
                reminderDate: corrected,
                priority: .normal,
                personName: nil,
                needsClarification: false
            ))
            XCTAssertEqual(item.temporalIntent?.isUserEdited, true)

            try relaunch()

            let reloaded = try loadItem(withID: itemID)
            XCTAssertEqual(reloaded.dueDate, corrected)
            XCTAssertEqual(reloaded.reminderDate, corrected)
            XCTAssertEqual(reloaded.temporalIntent?.isUserEdited, true)
            XCTAssertEqual(reloaded.temporalIntent?.day, CalendarDay(year: 2026, month: 9, day: 4))
            XCTAssertEqual(reloaded.temporalIntent?.time, WallClockTime(hour: 18, minute: 45))
            XCTAssertEqual(
                reloaded.temporalIntent?.sourceText?.isEmpty,
                false,
                "the original wording stays as provenance"
            )
        }
    }

    // MARK: Stale notification reconciliation

    func testObjectReviewKeepsClockAndCancelsThenRestoresActualNotification() async throws {
        try await requireNotificationAuthorization()
        let source = "Remind me to return that tomorrow at 8 PM. Buy eggs."
        _ = try repository.createCapture(text: source, source: .inAppText,
                                         createdAt: .now, schedulesReminder: true)
        let held = try XCTUnwrap(try allItems().first {
            $0.originalTextSegment.localizedCaseInsensitiveContains("return")
        })
        let id = held.id
        let date = try XCTUnwrap(held.reminderDate)
        XCTAssertEqual(held.semanticState, .underspecified(.ambiguousObject))
        await drainScheduler()
        let initial = await pendingRequests(for: id)
        XCTAssertTrue(initial.isEmpty, "the unresolved object must not deliver")
        func edit(review: Bool) throws {
            try repository.update(held, with: ItemEdits(
                title: "Return the projector", itemType: .task, category: held.category,
                dueDate: held.dueDate, reminderDate: date, priority: held.priority,
                personName: held.personName, needsClarification: review, dueDateHasTime: true))
        }
        try edit(review: false)
        await drainScheduler()
        let resolved = await pendingRequests(for: id)
        XCTAssertEqual(resolved.count, 1, "prove a real notification exists before testing withdrawal")
        try edit(review: true)
        await drainScheduler()
        let withheld = await pendingRequests(for: id)
        XCTAssertTrue(withheld.isEmpty, "holding an existing reminder must withdraw it despite its retained clock")
        XCTAssertEqual(held.reminderDate, date)
        try edit(review: false)
        await drainScheduler()
        try relaunch()
        repository.reconcilePendingReminders()
        await drainScheduler()
        let restored = await pendingRequests(for: id)
        XCTAssertEqual(restored.count, 1, "resolving and relaunching must not duplicate delivery")
        let reloaded = try loadItem(withID: id)
        XCTAssertEqual(reloaded.displayTitle, "Return the projector")
        XCTAssertEqual(reloaded.reminderDate, date)
        XCTAssertEqual(reloaded.captureSession?.originalTranscription, source)
        XCTAssertEqual(try allItems().count, 2)
    }

    /// Editing an item must leave no notification behind for the moment it used
    /// to fire at.
    func testEditingAReminderLeavesNoStalePendingNotification() async throws {
        try await requireNotificationAuthorization()
        let createdAt = Date.now
        let item = try repository.createCapture(
            text: "Remind me to call Sam in 3 hours",
            source: .inAppText,
            createdAt: createdAt,
            schedulesReminder: true
        )
        let itemID = item.id
        let originalReminder = try XCTUnwrap(item.reminderDate)

        // Prove the notification really exists before asserting it goes away,
        // so this cannot pass by never having scheduled anything.
        await drainScheduler()
        let before = await pendingRequests(for: itemID)
        XCTAssertEqual(before.count, 1, "the original reminder should be pending")

        let moved = originalReminder.addingTimeInterval(48 * 60 * 60)
        try repository.update(item, with: ItemEdits(
            title: "Call Sam",
            itemType: .personFollowUp,
            category: .people,
            dueDate: moved,
            reminderDate: moved,
            priority: .normal,
            personName: "Sam",
            needsClarification: false
        ))

        await drainScheduler()
        let after = await pendingRequests(for: itemID)
        let fireDates = after.compactMap {
            ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        }

        XCTAssertFalse(
            fireDates.contains { abs($0.timeIntervalSince(originalReminder)) < 60 },
            "the notification for the old time must be withdrawn, not merely superseded"
        )
        XCTAssertEqual(after.count, 1, "exactly one reminder, at the corrected time")
        XCTAssertTrue(
            fireDates.contains { abs($0.timeIntervalSince(moved)) < 60 },
            "the corrected time must actually be scheduled"
        )
    }

    /// The end of the path the whole temporal system exists to serve: an
    /// intended wall clock, carried through interpretation, persistence, the
    /// repository and recurrence, arriving as a real `UNNotificationRequest`
    /// whose trigger fires at that clock — across a real daylight-saving
    /// transition.
    ///
    /// March 14 2027 is a genuine future spring-forward, so this is scheduled by
    /// the real notification centre against the real tzdata rules.
    func testIntendedWallClockReachesTheNotificationTriggerAcrossSpringForward() async throws {
        try await requireNotificationAuthorization()
        try withFixtureClock { calendar in
            let item = try repository.createCapture(
                text: "Remind me to take my pills every day at 2:30 AM",
                source: .inAppText,
                createdAt: makeDate(year: 2027, month: 3, day: 13, hour: 1, calendar: calendar),
                schedulesReminder: true
            )
            XCTAssertEqual(item.temporalKind, .calendarRecurrence)
            XCTAssertEqual(item.temporalIntent?.time, WallClockTime(hour: 2, minute: 30))

            // Advance the series onto the transition day through the real path.
            try repository.setCompleted(item, completed: true)
            let transition = try loadItem(
                withID: try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: item.id))
            )
            let transitionFire = try XCTUnwrap(transition.reminderDate)
            XCTAssertEqual(
                calendar.dateComponents([.day, .hour, .minute], from: transitionFire),
                DateComponents(day: 14, hour: 3, minute: 0),
                "2:30 does not exist; the policy is the first instant that does"
            )

            // And the day after returns to the clock that was asked for.
            try repository.setCompleted(transition, completed: true)
            let recovered = try loadItem(
                withID: try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: transition.id))
            )
            let recoveredFire = try XCTUnwrap(recovered.reminderDate)
            XCTAssertEqual(
                calendar.dateComponents([.day, .hour, .minute], from: recoveredFire),
                DateComponents(day: 15, hour: 2, minute: 30)
            )

            self.scheduledCheck = (recovered.id, recoveredFire)
        }

        // The scheduler is what finally has to honour it.
        let (itemID, expectedFire) = try XCTUnwrap(scheduledCheck)
        repository.reconcilePendingReminders()
        await drainScheduler()

        let pending = await pendingRequests(for: itemID)
        XCTAssertEqual(pending.count, 1, "the recovered occurrence must be scheduled")
        let fire = try XCTUnwrap(
            (pending.first?.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        )
        XCTAssertEqual(
            fire.timeIntervalSince(expectedFire),
            0,
            accuracy: 1,
            "the notification must fire at the intended wall clock, not the drifted one"
        )
    }

    /// Deleting an item must withdraw its notification, whatever the app does
    /// next. A reminder for a thought that no longer exists is the worst kind
    /// of stale.
    func testDeletingAnItemWithdrawsItsNotification() async throws {
        try await requireNotificationAuthorization()
        let item = try repository.createCapture(
            text: "Remind me to send the invoice in 4 hours",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        let itemID = item.id

        await drainScheduler()
        let before = await pendingRequests(for: itemID)
        XCTAssertEqual(before.count, 1, "the reminder should be pending before deletion")

        try repository.delete(item)
        await drainScheduler()

        let after = await pendingRequests(for: itemID)
        XCTAssertTrue(
            after.isEmpty,
            "a deleted thought must not keep a pending notification"
        )
    }

    /// A timed shopping list's one coalesced notification is titled by the
    /// list and names the items in spoken order — "Sobeys: Chicken · Eggs ·
    /// Milk" — instead of the generic "3 reminders" copy.
    func testTimedListNotificationIsTitledByTheListAndNamesTheItems() async throws {
        try await requireNotificationAuthorization()
        let previousGroups = ShoppingGroupStore.snapshot()
        defer { ShoppingGroupStore.restore(previousGroups) }

        let first = try repository.createCapture(
            text: "Remind me in one hour to go to Sobeys and get chicken, eggs and milk",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        await drainScheduler()

        let items = try allItems().sorted { $0.createdAt < $1.createdAt }
        defer {
            for item in items { try? repository.delete(item) }
        }
        XCTAssertEqual(items.count, 3, "got \(items.map(\.displayTitle))")

        let pending = await pendingRequests(for: first.id)
        XCTAssertEqual(pending.count, 1, "the rows coalesce into one notification")
        let request = try XCTUnwrap(pending.first)
        XCTAssertEqual(request.content.title, "Sobeys")
        XCTAssertEqual(request.content.body, "Chicken · Eggs · Milk")
    }

    /// The reconcile pass is the app's self-healing step, and it must be
    /// idempotent: running it after a relaunch must not resurrect a withdrawn
    /// reminder or duplicate a live one.
    func testReconcileAfterRelaunchDoesNotResurrectDeletedReminders() async throws {
        try await requireNotificationAuthorization()
        let kept = try repository.createCapture(
            text: "Remind me to water the plants in 5 hours",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        let removed = try repository.createCapture(
            text: "Remind me to move the car in 6 hours",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        let removedID = removed.id
        let keptID = kept.id
        try repository.delete(removed)

        try relaunch()
        await drainScheduler()

        let resurrected = await pendingRequests(for: removedID)
        XCTAssertTrue(
            resurrected.isEmpty,
            "reconcile must not rebuild a notification for a deleted item"
        )
        let keptRequests = await pendingRequests(for: keptID)
        XCTAssertEqual(
            keptRequests.count,
            1,
            "the surviving reminder is rescheduled exactly once, never duplicated"
        )
    }

    /// Completing a recurring item late must schedule the next occurrence in the
    /// future, never in the past where iOS would silently drop it.
    func testRecurringItemCompletedLateSchedulesAFutureOccurrence() throws {
        try withFixtureClock { calendar in
            let createdAt = calendar.date(byAdding: .day, value: -9, to: .now)!
            let item = try repository.createCapture(
                text: "Water the plants every day at 8 AM",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            XCTAssertEqual(item.temporalKind, .calendarRecurrence)

            try repository.setCompleted(item, completed: true)
            let nextID = try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: item.id))
            let next = try loadItem(withID: nextID)
            let due = try XCTUnwrap(next.dueDate)

            XCTAssertGreaterThan(due, .now, "a late completion must not schedule into the past")
            XCTAssertEqual(
                calendar.dateComponents([.hour, .minute], from: due),
                DateComponents(hour: 8, minute: 0),
                "catching up must not move the clock the series repeats at"
            )
        }
    }

    /// Editing one occurrence of a live series must become the series' new
    /// meaning, and must not be reverted by the original wording.
    func testEditingOneOccurrenceRetimesTheRestOfTheSeries() throws {
        try withFixtureClock { calendar in
            let item = try repository.createCapture(
                text: "Water the plants every day at 8 AM",
                source: .inAppText,
                createdAt: .now,
                schedulesReminder: false
            )
            let itemID = item.id

            // The person moves this occurrence to 6:45 PM and keeps it repeating.
            let retimed = calendar.date(
                bySettingHour: 18,
                minute: 45,
                second: 0,
                of: try XCTUnwrap(item.dueDate)
            )!
            try repository.update(item, with: ItemEdits(
                title: "Water the plants",
                itemType: .task,
                category: .personal,
                dueDate: retimed,
                reminderDate: nil,
                priority: .normal,
                personName: nil,
                needsClarification: false,
                recurrenceRule: RecurrenceRule(frequency: .daily)
            ))
            XCTAssertEqual(item.temporalIntent?.isUserEdited, true)
            XCTAssertEqual(item.temporalIntent?.time, WallClockTime(hour: 18, minute: 45))

            try repository.setCompleted(item, completed: true)
            let next = try loadItem(
                withID: try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: itemID))
            )

            XCTAssertEqual(
                calendar.dateComponents([.hour, .minute], from: try XCTUnwrap(next.dueDate)),
                DateComponents(hour: 18, minute: 45),
                "the rest of the series follows the correction, not the original sentence"
            )
            XCTAssertEqual(
                next.temporalIntent?.isUserEdited,
                true,
                "the correction stays authoritative for every later occurrence"
            )
            XCTAssertNotEqual(
                next.temporalIntent?.time,
                WallClockTime(hour: 8, minute: 0),
                "reparsing 'every day at 8 AM' must never win over a manual correction"
            )
        }
    }

    // MARK: Travel and device environment

    /// Runs `body` with the process reporting a different device time zone.
    ///
    /// `NSTimeZone.default` is the real switch behind `TimeZone.current` and
    /// `Calendar.autoupdatingCurrent`, so this is the same change the app sees
    /// when someone lands in another country — not a mock handed to one
    /// function.
    ///
    /// `withFixtureClock` is built on it, and the travel tests below use it
    /// directly to move somewhere that is not the fixture zone.
    private func withDeviceTimeZone(_ identifier: String, _ body: () throws -> Void) rethrows {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: identifier)!
        defer { NSTimeZone.default = previous }
        try body()
    }

    /// "August 15" is August 15 in Toronto and in Tokyo. The recorded day must
    /// come from `CalendarDay`, never from re-reading a stored midnight instant
    /// in whatever zone the device is now in.
    func testDateOnlyDayNeverShiftsWhenTravelling() throws {
        var item: CapturedItem!
        var itemID: UUID!
        try withFixtureClock { calendar in
            item = try repository.createCapture(
                text: "Renew the passport on August 15",
                source: .inAppText,
                createdAt: makeDate(
                    year: 2026, month: 8, day: 10, hour: 9, calendar: calendar
                ),
                schedulesReminder: false
            )
            itemID = item.id
            XCTAssertEqual(item.temporalKind, .dateOnly)
            XCTAssertEqual(item.temporalIntent?.day, CalendarDay(year: 2026, month: 8, day: 15))
        }

        // Fly west-to-east far enough that a Toronto midnight is the previous
        // calendar day in the new zone.
        try withDeviceTimeZone("Asia/Tokyo") {
            let travelled = try loadItem(withID: itemID)
            XCTAssertEqual(
                travelled.temporalIntent?.day,
                CalendarDay(year: 2026, month: 8, day: 15),
                "the day the person named cannot change because they got on a plane"
            )
        }
    }

    /// The same guarantee across a relaunch, because the launch path runs the
    /// backfill and the recovery pass — the two places most likely to re-derive
    /// a day from a stored instant in the wrong zone.
    func testDateOnlyDaySurvivesATimeZoneChangeWhileTerminated() throws {
        var itemID: UUID!
        try withFixtureClock { calendar in
            let item = try repository.createCapture(
                text: "Renew the passport on August 15",
                source: .inAppText,
                createdAt: makeDate(
                    year: 2026, month: 8, day: 10, hour: 9, calendar: calendar
                ),
                schedulesReminder: false
            )
            itemID = item.id
        }

        try withDeviceTimeZone("Pacific/Kiritimati") {
            try relaunch()
            let reloaded = try loadItem(withID: itemID)
            XCTAssertEqual(
                reloaded.temporalIntent?.day,
                CalendarDay(year: 2026, month: 8, day: 15)
            )
            XCTAssertEqual(reloaded.temporalKind, .dateOnly)
            XCTAssertNil(reloaded.temporalIntent?.time, "travel must not invent a time of day")
        }
    }

    /// A row written before schema version 2 gets its intent from the backfill.
    /// If that reconstruction reads the stored day in the device's *current*
    /// zone, someone who captured in Toronto and opened the app in Tokyo would
    /// have August 15 rewritten to August 14 — and, worse, rewritten as an exact
    /// time the person never said.
    func testLegacyRowBackfilledAfterTravelKeepsItsDay() throws {
        var itemID: UUID!
        try withFixtureClock { calendar in
            let item = try repository.createCapture(
                text: "Renew the passport on August 15",
                source: .inAppText,
                createdAt: makeDate(
                    year: 2026, month: 8, day: 10, hour: 9, calendar: calendar
                ),
                schedulesReminder: false
            )
            itemID = item.id
            // Return the row to exactly the shape version 1 stored: resolved
            // dates, no intent at all.
            item.temporalIntentData = nil
            item.temporalKindRawValue = nil
            try container.mainContext.save()
        }

        try withDeviceTimeZone("Asia/Tokyo") {
            try relaunch()
            let reloaded = try loadItem(withID: itemID)
            XCTAssertEqual(
                reloaded.temporalKind,
                .dateOnly,
                "the wording said a day, so the reconstruction must say a day"
            )
            XCTAssertEqual(
                reloaded.temporalIntent?.day,
                CalendarDay(year: 2026, month: 8, day: 15),
                "the backfill must not move the day into the zone the device is in now"
            )
            XCTAssertNil(
                reloaded.temporalIntent?.time,
                "the backfill must not invent a time of day that was never spoken"
            )
        }
    }

    /// A named zone travels with the request. "9 AM London time" is 9 AM in
    /// London whatever the device thinks the local zone is.
    func testFixedZoneIntentIgnoresTheDeviceZone() throws {
        var itemID: UUID!
        try withFixtureClock { calendar in
            let item = try repository.createCapture(
                text: "Remind me to join the standup at 9 AM London time tomorrow",
                source: .inAppText,
                createdAt: makeDate(
                    year: 2026, month: 8, day: 20, hour: 9, calendar: calendar
                ),
                schedulesReminder: false
            )
            itemID = item.id
            XCTAssertEqual(item.temporalIntent?.timeZoneBehavior, .fixed)
            XCTAssertEqual(item.temporalIntent?.timeZoneIdentifier, "Europe/London")
        }

        try withDeviceTimeZone("Asia/Tokyo") {
            let travelled = try loadItem(withID: itemID)
            XCTAssertEqual(
                travelled.temporalIntent?.timeZoneIdentifier,
                "Europe/London",
                "a zone the person named is part of the request, not a device setting"
            )
            var london = Calendar(identifier: .gregorian)
            london.timeZone = TimeZone(identifier: "Europe/London")!
            XCTAssertEqual(
                london.dateComponents([.hour, .minute], from: try XCTUnwrap(travelled.dueDate)),
                DateComponents(hour: 9, minute: 0),
                "still 9 AM in London after the device moved to Tokyo"
            )
        }
    }

    /// A bare "9 AM" follows the person. The stored behavior must stay
    /// `deviceLocal` so nothing later mistakes it for a pinned zone.
    func testBareClockTimeStaysDeviceLocal() throws {
        try withDeviceTimeZone(Self.fixtureTimeZoneIdentifier) {
            let item = try repository.createCapture(
                text: "Remind me to stretch every day at 9 AM",
                source: .inAppText,
                createdAt: .now,
                schedulesReminder: false
            )
            XCTAssertEqual(item.temporalIntent?.timeZoneBehavior, .deviceLocal)
            XCTAssertEqual(item.temporalIntent?.time, WallClockTime(hour: 9, minute: 0))
        }
    }

    /// The device's 12/24-hour setting is a display preference. It must not
    /// reach interpretation or scheduling.
    func testTwentyFourHourDisplayPreferenceDoesNotChangeScheduling() throws {
        let key = "AppleICUForce24HourTime"
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else {
                defaults.removeObject(forKey: key)
            }
        }

        try withFixtureClock { calendar in
            let createdAt = makeDate(year: 2026, month: 8, day: 20, hour: 9, calendar: calendar)

            defaults.set(false, forKey: key)
            let twelveHour = try repository.createCapture(
                text: "Remind me to call the bank tomorrow at 3 PM",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            let twelveHourIntent = twelveHour.temporalIntent

            defaults.set(true, forKey: key)
            let twentyFourHour = try repository.createCapture(
                text: "Remind me to call the credit union tomorrow at 3 PM",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )

            XCTAssertEqual(twelveHourIntent?.time, WallClockTime(hour: 15, minute: 0))
            XCTAssertEqual(
                twentyFourHour.temporalIntent?.time,
                twelveHourIntent?.time,
                "3 PM is 15:00 whichever way the device prefers to print it"
            )
            XCTAssertEqual(twentyFourHour.reminderDate, twelveHour.reminderDate)
        }
    }

    /// Numeric dates ask only when both readings are genuinely possible.
    /// Asking about "13/5" would be asking a question with one answer.
    func testNumericDatesOnlyAskWhenBothReadingsSurvive() throws {
        XCTAssertEqual(ThoughtOrganizer.numericDate(in: "meet on 4/5"), .ambiguous)
        XCTAssertEqual(
            ThoughtOrganizer.numericDate(in: "meet on 13/5"),
            .resolved(month: 5, day: 13)
        )
        XCTAssertEqual(
            ThoughtOrganizer.numericDate(in: "meet on 5/13"),
            .resolved(month: 5, day: 13)
        )
        XCTAssertEqual(
            ThoughtOrganizer.numericDate(in: "meet on 5/5"),
            .resolved(month: 5, day: 5),
            "both readings agree, so there is nothing to ask"
        )
    }

    /// Changing the device language must not change which instant a reminder
    /// fires at. Only presentation may follow the locale.
    func testDeviceLanguageChangeDoesNotMoveAScheduledInstant() throws {
        let key = "AppleLanguages"
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else {
                defaults.removeObject(forKey: key)
            }
        }

        try withFixtureClock { calendar in
            let createdAt = makeDate(year: 2026, month: 8, day: 20, hour: 9, calendar: calendar)

            defaults.set(["en-US"], forKey: key)
            let first = try repository.createCapture(
                text: "Remind me to call the bank tomorrow at 3 PM",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            let firstReminder = first.reminderDate
            let firstIntent = first.temporalIntent

            defaults.set(["en-GB"], forKey: key)
            let second = try repository.createCapture(
                text: "Remind me to call the building society tomorrow at 3 PM",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )

            XCTAssertEqual(second.temporalIntent?.time, firstIntent?.time)
            XCTAssertEqual(second.temporalIntent?.day, firstIntent?.day)
            XCTAssertEqual(second.reminderDate, firstReminder)
        }
    }

    // MARK: Permission and background state

    /// Notification permission is environment, not meaning. Losing it must
    /// leave every thought and every time intact, so granting it again can
    /// simply reschedule.
    func testWithoutNotificationPermissionThoughtsAndTimesAreStillKept() async throws {
        let status = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
        try XCTSkipIf(
            status == .authorized || status == .provisional || status == .ephemeral,
            "this test describes the unauthorized device; permission is granted here"
        )

        let item = try repository.createCapture(
            text: "Remind me to call the pharmacy in 3 hours",
            source: .inAppText,
            createdAt: .now,
            // The test repository suppresses only the system prompt; scheduling
            // still observes the simulator's unauthorized notification state.
            schedulesReminder: true
        )
        let itemID = item.id
        let reminder = try XCTUnwrap(item.reminderDate)

        // The launch reconcile is the path that runs after permission changes.
        try relaunch()
        await drainScheduler()

        let reloaded = try loadItem(withID: itemID)
        XCTAssertEqual(
            reloaded.reminderDate,
            reminder,
            "a revoked permission must never erase the time the person asked for"
        )
        XCTAssertFalse(reloaded.isArchived)
        XCTAssertNil(reloaded.completedAt)
        XCTAssertNotNil(reloaded.temporalIntent, "the meaning survives the permission")
    }

    /// Reconcile is the app's self-healing pass and runs on every foreground.
    /// It has to be safe to run repeatedly — which is what makes it a correct
    /// answer to Low Power Mode, disabled Background App Refresh, and a phone
    /// that was simply off: none of them need their own recovery path, because
    /// the next foreground rebuilds the pending set from the saved items.
    func testRepeatedReconcileIsStable() async throws {
        try await requireNotificationAuthorization()
        let item = try repository.createCapture(
            text: "Remind me to take the bins out in 5 hours",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        let itemID = item.id
        let reminder = try XCTUnwrap(item.reminderDate)

        for _ in 0..<3 {
            repository.reconcilePendingReminders()
        }
        await drainScheduler()

        let reloaded = try loadItem(withID: itemID)
        XCTAssertEqual(reloaded.reminderDate, reminder, "reconcile must not move a reminder")
        XCTAssertEqual(reloaded.temporalIntent, item.temporalIntent, "nor rewrite its meaning")

        let mine = await pendingRequests(for: itemID)
        XCTAssertEqual(mine.count, 1, "reconcile must never accumulate duplicates")
    }

    /// The app is closed before midnight and opened days later. Nothing about
    /// the stored request may change, and no reminder whose moment has passed
    /// may be left pending.
    func testRelaunchAfterSeveralDaysLeavesNoPastReminderPending() async throws {
        let staleFire = Date.now.addingTimeInterval(-3 * 24 * 60 * 60)
        let item = try repository.createCapture(
            text: "Remind me to call the vet tomorrow at 3 PM",
            source: .inAppText,
            createdAt: staleFire.addingTimeInterval(-6 * 60 * 60),
            schedulesReminder: false
        )
        let itemID = item.id
        let intentBefore = item.temporalIntent

        try relaunch()
        await drainScheduler()

        let reloaded = try loadItem(withID: itemID)
        XCTAssertEqual(
            reloaded.temporalIntent,
            intentBefore,
            "a relaunch days later must not reinterpret what was already understood"
        )

        let pending = await pendingRequests(for: itemID)
        XCTAssertTrue(
            pending.isEmpty,
            "a moment that has already passed must not stay scheduled"
        )
    }
}
