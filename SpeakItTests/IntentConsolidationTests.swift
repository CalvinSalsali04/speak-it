import XCTest
import SwiftData
import NaturalLanguage
@testable import SpeakIt

/// Pins the asymmetry that makes `IntentConsolidator` safe to have at all.
///
/// The semantic corpus already proves the outcomes — how many rows a paragraph
/// becomes, what the row says. These tests sit one level down, on the verdict
/// itself, for the same reason `ActionabilityTests` does: the corpus can report
/// that a capture split into three, but not *which* of the two questions was
/// answered badly. Here the two questions are asked separately.
///
/// The invariant under test is that this stage is a **veto, never a splitter**:
/// it either collapses to one item or has no opinion, and having no opinion is
/// the default whenever the wording is not positively narrative.
@MainActor
final class IntentConsolidationTests: XCTestCase {
    func testExplicitDayClockBoundaryPreservesOwnedActionAndLeavesRequestedAlertsUnscheduled() throws {
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone=try XCTUnwrap(TimeZone(identifier:"America/Toronto"))
        let previous=SentenceContext.taggerDisabledForEvaluation,zone=NSTimeZone.default
        NSTimeZone.default=calendar.timeZone
        defer { SentenceContext.taggerDisabledForEvaluation=previous;SentenceContextCache.invalidate();NSTimeZone.default=zone }
        let reference=try XCTUnwrap(calendar.date(from:DateComponents(year:2026,month:11,day:17,hour:9)))
        let lateWednesday=try XCTUnwrap(calendar.date(from:DateComponents(year:2026,month:11,day:18,hour:19)))
        let cases:[(String,ClockBoundary,Int,Int,ItemType,Bool)]=[
            ("Pick up the costume rack from Lorraine's garage on Wednesday after six.",.after,18,0,.task,false),
            ("Clean the shelving before 8 PM on Wednesday.",.before,20,0,.task,false),
            ("Before 8 PM on Wednesday, clean the shelving.",.before,20,0,.task,false),
            ("Remind me on Wednesday after six to clean the shelving.",.after,18,0,.task,true),
            ("Remind me to clean the shelving on Wednesday after six.",.after,18,0,.task,true),
            ("Call Mom on Wednesday after six.",.after,18,0,.personFollowUp,false),
            ("Buy milk on Wednesday before 7:30 PM.",.before,19,30,.shopping,false),
            ("Clean the qavren panel tomorrow after 8 PM.",.after,20,0,.task,false),
            ("Return the hedge trimmer to Marcus Wednesday after 7 PM.",.after,19,0,.task,false),
            ("Clean the shelving before 3:30 in the afternoon on Wednesday.",.before,15,30,.task,false),
            ("Remind me on Wednesday after eight in the evening to clean the shelving.",.after,20,0,.task,true),
            ("Before eleven thirty PM on Wednesday, clean the shelving.",.before,23,30,.task,false),
            ("Remind me on Wednesday before 8 PM to clean the shelving.",.before,20,0,.task,true)
        ]
        for disabled in [false,true] {
            SentenceContext.taggerDisabledForEvaluation=disabled;SentenceContextCache.invalidate()
            for (source,boundary,hour,minute,kind,requestsAlert) in cases {
                let proved=try XCTUnwrap(ThoughtOrganizer.clockBoundaryTiming(in:source,referenceDate:reference,calendar:calendar),source)
                let organization=ThoughtOrganizer.organize(source,referenceDate:reference,calendar:calendar)
                XCTAssertEqual(organization.itemType,kind,source)
                XCTAssertEqual(organization.temporalIntent,proved.intent,source)
                XCTAssertEqual(organization.temporalIntent.clockBoundary,boundary,source)
                XCTAssertEqual(organization.temporalIntent.day,CalendarDay(year:2026,month:11,day:18),source)
                XCTAssertEqual(organization.temporalIntent.time,WallClockTime(hour:hour,minute:minute),source)
                XCTAssertEqual(organization.dueDate,proved.dueDate,source)
                XCTAssertNil(organization.reminderDate,source);XCTAssertEqual(organization.reminderDelivery,.none,source)
                XCTAssertNil(organization.recurrenceRule,source);XCTAssertNil(organization.locationIntent,source)
                XCTAssertEqual(organization.needsClarification,requestsAlert,source)
                XCTAssertEqual(organization.state,requestsAlert ? .underspecified(.ambiguousTemporalScope) : .resolved,source)
                let resolution=TemporalResolver.resolve(proved.intent,anchor:reference,calendar:calendar,wantsReminder:true)
                XCTAssertEqual(resolution.dueDate,proved.dueDate);XCTAssertNil(resolution.reminderDate)
            }
            let monthNamed=ThoughtOrganizer.organize("Clean the shelving on November 20 after 7 PM.",referenceDate:reference,calendar:calendar)
            XCTAssertEqual(monthNamed.itemType,.task)
            XCTAssertEqual(monthNamed.temporalIntent.clockBoundary,.after)
            XCTAssertEqual(monthNamed.temporalIntent.day,CalendarDay(year:2026,month:11,day:20))
            XCTAssertEqual(monthNamed.temporalIntent.time,WallClockTime(hour:19,minute:0))
            XCTAssertEqual(monthNamed.dueDate,calendar.date(from:DateComponents(year:2026,month:11,day:20,hour:19)))
            XCTAssertNil(monthNamed.reminderDate);XCTAssertFalse(monthNamed.needsClarification)
            let heldEvent=ThoughtOrganizer.organize("Attend the vendor meeting on Wednesday after 9 AM.",referenceDate:reference,calendar:calendar)
            XCTAssertEqual(heldEvent.itemType,.event,"Unsupported event boundaries retain the existing classification")
            XCTAssertNil(heldEvent.temporalIntent.clockBoundary);XCTAssertNil(heldEvent.dueDate)
            XCTAssertNil(heldEvent.reminderDate);XCTAssertTrue(heldEvent.needsClarification)
            let stillWednesday=ThoughtOrganizer.organize(cases[0].0,referenceDate:lateWednesday,calendar:calendar)
            XCTAssertEqual(stillWednesday.temporalIntent.day,CalendarDay(year:2026,month:11,day:18))
            XCTAssertEqual(stillWednesday.temporalIntent.clockBoundary,.after)
            XCTAssertEqual(stillWednesday.temporalIntent.time,WallClockTime(hour:18,minute:0))
            for source in ["Clean the shelving after six.","Clean the shelving on Wednesday after six and before nine.",
                           "Clean the shelving on Wednesday after 6 PM unknownzone time.",
                           "Clean the shelving London time on Wednesday after six.",
                           "Clean the shelving on Wednesday before 6 AM in the evening.",
                           "Clean the shelving on Wednesday before 7 PM in the morning."] {
                XCTAssertNil(ThoughtOrganizer.clockBoundaryTiming(in:source,referenceDate:reference,calendar:calendar),source)
                let held=ThoughtOrganizer.organize(source,referenceDate:reference,calendar:calendar)
                XCTAssertNil(held.temporalIntent.clockBoundary,source);XCTAssertNil(held.dueDate,source)
                XCTAssertNil(held.reminderDate,source);XCTAssertTrue(held.needsClarification,source)
            }
            for source in ["Mara said clean the shelving on Wednesday after six.",
                           "If Mara agrees, clean the shelving on Wednesday after six.",
                           "Don't clean the shelving on Wednesday after six.",
                           "Clean the shelving and call Mom on Wednesday after six.",
                           "Return the trimmer to repair the handle on Wednesday after six.",
                           "Buy milk for Wednesday after six.",
                           "Call Sam about the meeting on Wednesday after six.",
                           "Call Sam regarding the meeting on Wednesday after six.",
                           "Call Sam concerning the meeting on Wednesday after six.",
                           "Text Mom that we can meet on Wednesday after six.",
                           "\"Clean the shelving on Wednesday after six.\""] {
                XCTAssertNil(ThoughtOrganizer.clockBoundaryTiming(in:source,referenceDate:reference,calendar:calendar),source)
                XCTAssertNil(ThoughtOrganizer.organize(source,referenceDate:reference,calendar:calendar).temporalIntent.clockBoundary,source)
            }
            let exact=ThoughtOrganizer.organize("Clean the shelving on Wednesday at six.",referenceDate:reference,calendar:calendar)
            XCTAssertNil(exact.temporalIntent.clockBoundary);XCTAssertEqual(exact.temporalIntent.time,WallClockTime(hour:18,minute:0))
            let arithmetic=ThoughtOrganizer.organize("Clean the shelving on Wednesday at quarter after six.",referenceDate:reference,calendar:calendar)
            XCTAssertNil(arithmetic.temporalIntent.clockBoundary);XCTAssertEqual(arithmetic.temporalIntent.time,WallClockTime(hour:18,minute:15))
            for source in ["Clean the shelving on Wednesday at twenty after seven.",
                           "Clean the shelving on November 20 at twenty after seven."] {
                let arithmetic=ThoughtOrganizer.organize(source,referenceDate:reference,calendar:calendar)
                XCTAssertNil(arithmetic.temporalIntent.clockBoundary,source)
                XCTAssertEqual(arithmetic.temporalIntent.kind,.exactDateTime,source)
                XCTAssertEqual(arithmetic.temporalIntent.time,WallClockTime(hour:19,minute:20),source)
                XCTAssertNotNil(arithmetic.dueDate,source);XCTAssertFalse(arithmetic.needsClarification,source)
            }
            for source in ["Clean the shelving on November 20 after 7 PM and before 9 PM.",
                           "Clean the shelving on November 20 after 7 PM and November 21 before 8 PM.",
                           "Clean the shelving on November 31 after 7 PM."] {
                XCTAssertNil(ThoughtOrganizer.clockBoundaryTiming(in:source,referenceDate:reference,calendar:calendar),source)
                let held=ThoughtOrganizer.organize(source,referenceDate:reference,calendar:calendar)
                XCTAssertNil(held.temporalIntent.clockBoundary,source);XCTAssertNil(held.dueDate,source)
                XCTAssertNil(held.reminderDate,source);XCTAssertTrue(held.needsClarification,source)
            }
            let mismatch=ThoughtOrganizer.organize(cases[0].0,referenceDate:reference,calendar:calendar,
                sourceText:cases[0].0.replacingOccurrences(of:"Wednesday",with:"Thursday"))
            XCTAssertNil(mismatch.temporalIntent.clockBoundary);XCTAssertNil(mismatch.dueDate);XCTAssertTrue(mismatch.needsClarification)
        }
    }

    func testClockBoundaryCodableLegacyAbsenceAndInvalidPresenceNeverBecomeExactAppointments() throws {
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone=try XCTUnwrap(TimeZone(identifier:"America/Toronto"))
        let anchor=try XCTUnwrap(calendar.date(from:DateComponents(year:2026,month:11,day:18,hour:9)))
        let endpoint=try XCTUnwrap(calendar.date(from:DateComponents(year:2026,month:11,day:18,hour:18)))
        let intent=TemporalIntent(kind:.exactDateTime,day:.init(year:2026,month:11,day:18),
            time:.init(hour:18,minute:0),sourceText:"on Wednesday after six",clockBoundary:.after)
        let encoder=JSONEncoder(),decoder=JSONDecoder()
        XCTAssertEqual(try decoder.decode(TemporalIntent.self,from:encoder.encode(intent)),intent)
        XCTAssertEqual(intent.clockBoundaryDate(calendar:calendar),endpoint)
        let interval=try XCTUnwrap(intent.clockBoundaryDayInterval(calendar:calendar))
        XCTAssertEqual(interval.start,calendar.startOfDay(for:anchor))
        XCTAssertEqual(interval.end,calendar.date(byAdding:.day,value:1,to:interval.start))
        for (month,day,expectedHours) in [(3,8,23),(11,1,25)] {
            var transition=intent;transition.day = .init(year:2026,month:month,day:day)
            let ownedDay=try XCTUnwrap(transition.clockBoundaryDayInterval(calendar:calendar))
            XCTAssertEqual(ownedDay.duration,TimeInterval(expectedHours*3600))
            XCTAssertNotNil(transition.clockBoundaryDate(calendar:calendar))
        }
        let encoded=try XCTUnwrap(JSONSerialization.jsonObject(with:encoder.encode(intent)) as? [String:Any])
        var legacy=encoded;legacy.removeValue(forKey:"clockBoundary")
        let old=try decoder.decode(TemporalIntent.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertNil(old.clockBoundary)
        XCTAssertEqual(TemporalResolver.resolve(old,anchor:anchor,calendar:calendar,wantsReminder:true),
            .init(dueDate:endpoint,reminderDate:endpoint))
        for raw in ["future-value",NSNull(),true,17] as [Any] {
            var invalid=encoded;invalid["clockBoundary"]=raw
            let decoded=try decoder.decode(TemporalIntent.self,from:JSONSerialization.data(withJSONObject:invalid))
            XCTAssertNotNil(decoded.clockBoundary)
            XCTAssertNil(decoded.clockBoundaryDate(calendar:calendar))
            XCTAssertEqual(TemporalResolver.resolve(decoded,anchor:anchor,calendar:calendar,wantsReminder:true),
                .init(dueDate:nil,reminderDate:nil))
        }
        var invalidShapes:[TemporalIntent]=[]
        var wrong=intent;wrong.day = .init(year:2026,month:2,day:30);invalidShapes.append(wrong)
        wrong=intent;wrong.time = .init(hour:24,minute:0);invalidShapes.append(wrong)
        wrong=intent;wrong.deadlineBoundary = .endOfNamedDay;invalidShapes.append(wrong)
        wrong=intent;wrong.windowEndDay = intent.day;invalidShapes.append(wrong)
        wrong=intent;wrong.relativeSeconds = 60;invalidShapes.append(wrong)
        wrong=intent;wrong.unsupportedTrigger = .condition;invalidShapes.append(wrong)
        wrong=intent;wrong.isUserEdited = true;invalidShapes.append(wrong)
        wrong=intent;wrong.timeZoneBehavior = .fixed;wrong.timeZoneIdentifier="unknown/zone";invalidShapes.append(wrong)
        for invalid in invalidShapes {
            XCTAssertNil(invalid.clockBoundaryDate(calendar:calendar))
            XCTAssertEqual(TemporalResolver.resolve(invalid,anchor:anchor,calendar:calendar,wantsReminder:true),
                .init(dueDate:nil,reminderDate:nil))
            XCTAssertNil(TemporalResolver.nextOccurrence(of:invalid,after:anchor,calendar:calendar))
        }
        let edited=TemporalIntent.userEdited(dueDate:endpoint,reminderDate:nil,recurrence:nil,
            sourceText:intent.sourceText,calendar:calendar,dueDateHasTime:true)
        XCTAssertTrue(edited.isUserEdited);XCTAssertNil(edited.clockBoundary)
        XCTAssertEqual(intent.clockBoundary,.after,"A separate explicit edit never mutates the original intent")
    }

    static let displaySetupLongCapture = """
I want a note about the display setup, because I keep forgetting why we arranged it this way. The taller board goes at the back so it does not block the smaller labels. The lamps point across the table rather than straight down because the glossy photographs reflect the light. Keep those as setup facts. I am not asking to move the furniture again today; this is the arrangement we already tested.

For the things I still need to do, reprint the caption for the river photograph. The place name is spelt incorrectly on the current version. Then ask Amira to check the new caption after I have printed it, not before. It needs a second pair of eyes because I have looked at the same word so many times that I am no longer seeing it properly. There is no time for either job yet.

Remember that Amira prefers oat milk rather than soy. I was going to get drinks for the setup volunteers and that detail came back to me. Buy oat milk for her as a task. Ben is helping with the lights, but the milk preference belongs to Amira. Email Ben tomorrow to ask whether he can bring the extension lead. I am not making Ben responsible for drinks just because I said his name near the end.

There was a suggestion from the committee to print a booklet for everyone. I considered it, but I have decided on a simple web page instead because we can fix mistakes without printing everything again. Add making that page to my list. Use the final display captions as the content. The booklet is the rejected option, not another thing to produce. This is turning into quite a scattered list, but the caption correction at the start is still the first practical job.
"""

    func testCompleteFollowUpRetainsMatterAndReferenceLocationWithoutEffects() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-16T14:00:00Z"))
        let previous = SentenceContext.taggerDisabledForEvaluation, previousZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate(); NSTimeZone.default = previousZone }
        let original = "Follow up with Sun Life about the Kowalski family's rejected claim, the reference number is in the blue folder."
        let cases = [
            (original, "Sun Life"),
            ("Follow up with Mara about the pending invoice, the reference number is in the red folder.", "Mara"),
            ("Please follow up with Sam about our claim.", "Sam"),
            ("Follow up with Dr. Neris about the Rivera family's rejected letter, the reference number is in the green file.", "Dr. Neris")
        ]
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            for (source, recipient) in cases {
                let proof = try XCTUnwrap(ClauseScope.completeFollowUpReference(in: source), source)
                XCTAssertEqual(String(source[proof.endpointRange]), recipient)
                XCTAssertTrue(source[proof.topicRange].contains("claim") || source[proof.topicRange].contains("invoice") || source[proof.topicRange].contains("letter"))
                XCTAssertEqual(proof.contextRange != nil, source.contains("reference number"))
                XCTAssertEqual(proof.storageRange != nil, source.contains("reference number"))
                let result = try XCTUnwrap(RuntimeShortSourceCertificate.interpret(source, referenceDate: reference, calendar: calendar), source)
                XCTAssertEqual(result.items.count, 1); XCTAssertTrue(result.operations.isEmpty)
                let item = try XCTUnwrap(result.items.first)
                XCTAssertEqual(item.sourceQuote, source); XCTAssertEqual(item.rawQuote, source)
                XCTAssertEqual(item.analysisText, source); XCTAssertFalse(item.wasRepaired)
                XCTAssertEqual(item.sourceUnitIDs, Set(SourceUnitLedger(source).words.indices))
                XCTAssertTrue(item.organization.itemType.isActionable)
                XCTAssertEqual(item.organization.personName, recipient)
                XCTAssertFalse(item.needsReview); XCTAssertFalse(item.organization.needsClarification)
                XCTAssertEqual(item.organization.state, .resolved)
                XCTAssertNil(item.organization.dueDate); XCTAssertEqual(item.organization.temporalIntent, .none)
                XCTAssertNil(item.organization.reminderDate); XCTAssertEqual(item.organization.reminderDelivery, .none)
                XCTAssertNil(item.organization.locationIntent); XCTAssertNil(item.organization.recurrenceRule)
                XCTAssertNil(item.shoppingGroup)
                let title = try XCTUnwrap(item.suggestedTitle)
                XCTAssertTrue(title.localizedCaseInsensitiveContains(recipient))
                if source.contains("reference number") { XCTAssertTrue(title.contains("reference number")); XCTAssertTrue(title.contains("folder") || title.contains("file")) }
            }
            let fallback = await ThoughtExtractionEngine.extract(original, referenceDate: reference,
                calendar: calendar, permitsOnDeviceIntelligence: false)
            XCTAssertEqual(fallback.items.count, 1); XCTAssertTrue(fallback.operations.isEmpty)
            let kept = try XCTUnwrap(fallback.items.first)
            XCTAssertEqual(kept.rawQuote, original); XCTAssertEqual(kept.sourceUnitIDs, Set(SourceUnitLedger(original).words.indices))
            XCTAssertTrue(kept.organization.itemType.isActionable); XCTAssertEqual(kept.organization.personName, "Sun Life")
            XCTAssertFalse(kept.needsReview); XCTAssertNil(kept.organization.dueDate); XCTAssertNil(kept.organization.reminderDate)
            let separate = original + " Call Mom tomorrow."
            XCTAssertNil(ClauseScope.completeFollowUpReference(in: separate), "A whole-source role cannot swallow a separate act")
            let two = try XCTUnwrap(RuntimeShortSourceCertificate.interpret(separate, referenceDate: reference, calendar: calendar))
            XCTAssertEqual(two.items.count, 2)
            XCTAssertEqual(two.items.first?.rawQuote, original)
            XCTAssertEqual(two.items.last?.rawQuote, "Call Mom tomorrow.")
            XCTAssertEqual(two.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }, Set(SourceUnitLedger(separate).words.indices))
            for source in [
                "Sam said, '" + original + "'",
                "Do not " + original.lowercased(),
                "If approved, " + original.lowercased(),
                original.replacingOccurrences(of: ", the reference number is in the blue folder.", with: ", and call Mom."),
                original.replacingOccurrences(of: "rejected claim", with: "rejected claim and the invoice"),
                original.replacingOccurrences(of: "rejected claim", with: "call Mom claim"),
                original.replacingOccurrences(of: "in the blue folder.", with: "in the blue folder and send the invoice."),
                original.replacingOccurrences(of: "in the blue folder.", with: "in the blue folder if approved."),
                original.replacingOccurrences(of: "Follow up with Sun Life", with: "Follow up with them"),
                original.replacingOccurrences(of: "the reference number is", with: "keep a separate note that the reference number is")
            ] {
                XCTAssertNil(RuntimeShortSourceCertificate.interpret(source, referenceDate: reference, calendar: calendar), source)
            }
        }
    }

    func testCompletePaymentBeforeDayPreservesObjectDeadlineAndHasNoEffects() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-16T14:00:00Z"))
        let previous = SentenceContext.taggerDisabledForEvaluation, previousZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate(); NSTimeZone.default = previousZone }
        let original = "Pay the cleaning company's invoice before Friday."
        let cases: [(String, Int)] = [
            (original, 4),
            ("Please pay the plumber's invoice before Thursday.", 3),
            ("Pay my invoice before tomorrow.", 1),
            ("Pay the library's invoice before November twentieth.", 4),
            ("Pay the Ahmed family's invoice before Saturday.", 5),
            ("Pay our overdue invoice before Friday.", 4)
        ]
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            for (source, days) in cases {
                let proof = try XCTUnwrap(ClauseScope.completePaymentBeforeDay(in: source), source)
                XCTAssertTrue(source[proof.deadlineRange].hasPrefix("before "))
                XCTAssertTrue(source[proof.objectRange].hasSuffix("invoice"))
                XCTAssertFalse(source[proof.calendarRange].isEmpty)
                let result = try XCTUnwrap(RuntimeShortSourceCertificate.interpret(source, referenceDate: reference, calendar: calendar), source)
                XCTAssertEqual(result.items.count, 1); XCTAssertTrue(result.operations.isEmpty)
                let item = try XCTUnwrap(result.items.first)
                XCTAssertEqual(item.sourceQuote, source); XCTAssertEqual(item.rawQuote, source)
                XCTAssertEqual(item.analysisText, source); XCTAssertFalse(item.wasRepaired)
                XCTAssertEqual(item.sourceUnitIDs, Set(SourceUnitLedger(source).words.indices))
                XCTAssertEqual(item.organization.itemType, .task); XCTAssertNil(item.organization.personName)
                XCTAssertEqual(RuntimeShortSourceCertificate.purpose(source), .task)
                XCTAssertEqual(item.organization.dueDate, calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: reference)))
                XCTAssertEqual(item.organization.temporalIntent.kind, .dateOnly); XCTAssertNil(item.organization.temporalIntent.time)
                XCTAssertFalse(item.needsReview); XCTAssertFalse(item.organization.needsClarification)
                XCTAssertEqual(item.organization.state, .resolved)
                XCTAssertNil(item.organization.reminderDate); XCTAssertEqual(item.organization.reminderDelivery, .none)
                XCTAssertNil(item.organization.locationIntent); XCTAssertNil(item.organization.recurrenceRule); XCTAssertNil(item.shoppingGroup)
                XCTAssertTrue(item.suggestedTitle?.contains("before") == true)
                XCTAssertTrue(item.suggestedTitle?.contains(String(source[proof.objectRange])) == true)
            }
            let fallback = await ThoughtExtractionEngine.extract(original, referenceDate: reference,
                calendar: calendar, permitsOnDeviceIntelligence: false)
            XCTAssertEqual(fallback.items.count, 1); XCTAssertTrue(fallback.operations.isEmpty)
            let kept = try XCTUnwrap(fallback.items.first)
            XCTAssertEqual(kept.rawQuote, original); XCTAssertEqual(kept.sourceQuote, original)
            XCTAssertEqual(kept.analysisText, "Pay the cleaning company's invoice before Friday")
            XCTAssertEqual(SourceUnitLedger(kept.analysisText).words.map(\.text), SourceUnitLedger(original).words.map(\.text))
            XCTAssertEqual(kept.sourceUnitIDs, Set(SourceUnitLedger(original).words.indices))
            XCTAssertEqual(kept.organization.itemType, .task); XCTAssertNil(kept.organization.personName)
            XCTAssertFalse(kept.needsReview); XCTAssertNil(kept.organization.reminderDate)
            XCTAssertEqual(kept.organization.dueDate, calendar.date(byAdding: .day, value: 4, to: calendar.startOfDay(for: reference)))
            let separate = original + " Call Mom tomorrow."
            XCTAssertNil(ClauseScope.completePaymentBeforeDay(in: separate))
            let two = try XCTUnwrap(RuntimeShortSourceCertificate.interpret(separate, referenceDate: reference, calendar: calendar))
            XCTAssertEqual(two.items.count, 2); XCTAssertEqual(two.items.first?.rawQuote, original)
            XCTAssertEqual(two.items.last?.rawQuote, "Call Mom tomorrow.")
            XCTAssertEqual(two.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }, Set(SourceUnitLedger(separate).words.indices))
            for source in [
                "Mom said, '" + original + "'",
                "Do not " + original.lowercased(),
                "If approved, " + original.lowercased(),
                "Pay the invoice before Friday or Saturday.",
                "Pay the invoice before Friday and call Mom.",
                "Pay the invoice before I call Mom.",
                "Pay the invoice before Friday at 9 AM.",
                "Pay the invoice before February thirtieth.",
                "Pay the invoice before Friday, actually pay the plumber instead.",
                "Pay the invoice before Friday if approved.",
                "Pay the invoice before Friday, keep a separate note about the roof."
            ] {
                XCTAssertNil(RuntimeShortSourceCertificate.interpret(source, referenceDate: reference, calendar: calendar), source)
            }
        }
    }

    func testCompletePhoneReorderOwnsProductDistributionAndStockWithoutEffects() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-16T14:00:00Z"))
        let previous = SentenceContext.taggerDisabledForEvaluation, previousZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate(); NSTimeZone.default = previousZone }
        let original = "Call Henry Schein and reorder the nitrile gloves, two cases each of medium and large, we're down to the last box."
        let cases = [
            (original, "Henry Schein", "two", ["medium", "large"], true),
            ("Call Ibis Supply and reorder the rubber gloves, three boxes each of small and large, we are down to the last carton.", "Ibis Supply", "three", ["small", "large"], true),
            ("Please call Dr. Neris and reorder the socks, four packs each of S and L.", "Dr. Neris", "four", ["S", "L"], false),
            ("Call Mica Supply and reorder the socks, 5 packs each of small and medium, we are down to the last bag.", "Mica Supply", "5", ["small", "medium"], true)
        ]
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            for (source, recipient, quantity, sizes, stock) in cases {
                let proof = try XCTUnwrap(ClauseScope.completePhoneReorder(in: source), source)
                XCTAssertEqual(String(source[proof.recipientRange]), recipient)
                XCTAssertEqual(String(source[proof.quantityRange]), quantity)
                XCTAssertEqual(proof.sizeRanges.map { String(source[$0]) }, sizes)
                XCTAssertEqual(proof.stockContextRange != nil, stock)
                let result = try XCTUnwrap(RuntimeShortSourceCertificate.interpret(source, referenceDate: reference, calendar: calendar), source)
                XCTAssertEqual(result.items.count, 1); XCTAssertTrue(result.operations.isEmpty)
                let item = try XCTUnwrap(result.items.first)
                XCTAssertEqual(item.sourceQuote, source); XCTAssertEqual(item.rawQuote, source)
                XCTAssertEqual(item.analysisText, source); XCTAssertFalse(item.wasRepaired)
                XCTAssertEqual(item.sourceUnitIDs, Set(SourceUnitLedger(source).words.indices))
                XCTAssertEqual(item.organization.itemType, .personFollowUp); XCTAssertEqual(item.organization.personName, recipient)
                XCTAssertEqual(RuntimeShortSourceCertificate.purpose(source), .personFollowUp)
                XCTAssertNil(item.organization.dueDate); XCTAssertEqual(item.organization.temporalIntent, .none)
                XCTAssertFalse(item.needsReview); XCTAssertFalse(item.organization.needsClarification); XCTAssertEqual(item.organization.state, .resolved)
                XCTAssertNil(item.organization.reminderDate); XCTAssertEqual(item.organization.reminderDelivery, .none)
                XCTAssertNil(item.organization.locationIntent); XCTAssertNil(item.organization.recurrenceRule); XCTAssertNil(item.shoppingGroup)
                let title = try XCTUnwrap(item.suggestedTitle)
                XCTAssertTrue(title.contains(String(source[proof.productRange])))
                XCTAssertTrue(title.contains(String(source[proof.quantityRange])))
                if let context = proof.stockContextRange { XCTAssertTrue(title.contains(String(source[context]))) }
            }
            let fallback = await ThoughtExtractionEngine.extract(original, referenceDate: reference,
                calendar: calendar, permitsOnDeviceIntelligence: false)
            XCTAssertEqual(fallback.items.count, 1); XCTAssertTrue(fallback.operations.isEmpty)
            let kept = try XCTUnwrap(fallback.items.first)
            XCTAssertEqual(kept.rawQuote, original)
            XCTAssertEqual(SourceUnitLedger(kept.analysisText).words.map(\.text), SourceUnitLedger(original).words.map(\.text))
            XCTAssertEqual(kept.sourceUnitIDs, Set(SourceUnitLedger(original).words.indices))
            XCTAssertTrue(kept.organization.itemType.isActionable); XCTAssertEqual(kept.organization.personName, "Henry Schein")
            XCTAssertFalse(kept.needsReview); XCTAssertNil(kept.organization.dueDate); XCTAssertNil(kept.organization.reminderDate)
            // A complete source role cannot erase preprocessing or prior
            // timing/alert/list effects. Exercise the same admission directly.
            let whole = try XCTUnwrap(RuntimeShortSourceCertificate.interpret(original,
                referenceDate: reference, calendar: calendar)?.items.first)
            func baseline(_ organization: OrganizedThought, repaired: Bool = false,
                          group: String? = nil) -> ThoughtExtractionResult {
                .init(items: [.init(sourceQuote: whole.sourceQuote, rawQuote: whole.rawQuote,
                    wasRepaired: repaired, analysisText: whole.analysisText,
                    suggestedTitle: whole.suggestedTitle, organization: organization,
                    confidence: whole.confidence, needsReview: whole.needsReview,
                    sourceUnitIDs: whole.sourceUnitIDs, shoppingGroup: group)], method: .rules)
            }
            func withEffect(due: Date? = nil, reminder: Date? = nil,
                            delivery: ReminderDelivery = .none,
                            temporal: TemporalIntent = .none) -> OrganizedThought {
                let value = whole.organization
                return .init(itemType: value.itemType, category: value.category,
                    priority: value.priority, personName: value.personName,
                    dueDate: due, reminderDate: reminder, reminderDelivery: delivery,
                    recurrenceRule: value.recurrenceRule, needsClarification: value.needsClarification,
                    temporalIntent: temporal, locationIntent: value.locationIntent, state: value.state)
            }
            var edited = whole.organization.temporalIntent
            edited.isUserEdited = true
            for prior in [baseline(whole.organization, repaired: true),
                baseline(withEffect(due: reference)),
                baseline(withEffect(reminder: reference, delivery: .notification)),
                baseline(withEffect(temporal: edited))] {
                XCTAssertNil(RuntimeCompleteLiteralCertificate.interpret(original,
                    referenceDate: reference, calendar: calendar, rules: prior))
            }
            // Generic alignment retains a prior group rather than erasing
            // it through the new no-effects phone handoff.
            let grouped = try XCTUnwrap(RuntimeCompleteLiteralCertificate.interpret(original,
                referenceDate: reference, calendar: calendar,
                rules: baseline(whole.organization, group: "Groceries")))
            XCTAssertEqual(grouped.items.first?.shoppingGroup, "Groceries")
            XCTAssertEqual(grouped.items.first?.rawQuote, original)
            // Exercise the actual configured runtime path, without injecting
            // a result: this whole source certificate precedes context/bank/SDK.
            let configuration = RuntimeExampleConfiguration(
                libraryURL: URL(fileURLWithPath: "/unused-complete-phone-source-certificate"),
                allowProposed: false, retrievalEnabled: false)
            let configured = await RuntimeExampleConfiguration.$testConfiguration.withValue(configuration) {
                await ThoughtExtractionEngine.extract(original, referenceDate: reference,
                    calendar: calendar, permitsOnDeviceIntelligence: true,
                    runtimeContextProvider: {
                        XCTFail("Complete phone source must return before loading context")
                        return .empty
                    })
            }
            XCTAssertEqual(configured, fallback)
            XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(original,
                referenceDate: reference, calendar: calendar), fallback)
            let separate = original + " Call Mom tomorrow."
            XCTAssertNil(ClauseScope.completePhoneReorder(in: separate))
            let two = try XCTUnwrap(RuntimeShortSourceCertificate.interpret(separate, referenceDate: reference, calendar: calendar))
            XCTAssertEqual(two.items.count, 2); XCTAssertEqual(two.items.first?.rawQuote, original)
            XCTAssertEqual(two.items.last?.rawQuote, "Call Mom tomorrow.")
            XCTAssertEqual(two.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }, Set(SourceUnitLedger(separate).words.indices))
            for source in [
                "Mom said, '" + original + "'",
                "Do not " + original.lowercased(),
                "If approved, " + original.lowercased(),
                original.replacingOccurrences(of: "medium and large", with: "m and medium"),
                original.replacingOccurrences(of: "medium and large", with: "large and L"),
                original.replacingOccurrences(of: "medium and large", with: "medium and medium"),
                original.replacingOccurrences(of: "the nitrile gloves", with: "the socks gloves"),
                original.replacingOccurrences(of: "the nitrile gloves", with: "the shirts gloves"),
                original.replacingOccurrences(of: "the nitrile gloves", with: "the qavren hues"),
                original.replacingOccurrences(of: "two cases", with: "zero cases"),
                original.replacingOccurrences(of: "the last box.", with: "the last box of socks."),
                original.replacingOccurrences(of: "we're down", with: "he's down"),
                original.replacingOccurrences(of: "the last box.", with: "the last box, and call Mom."),
                original.replacingOccurrences(of: "Henry Schein", with: "them"),
                original + " Actually don't reorder anything."
            ] {
                XCTAssertNil(RuntimeShortSourceCertificate.interpret(source, referenceDate: reference, calendar: calendar), source)
            }
        }
    }

    func testCompleteAddressedChoiceQuestionOwnsWholePayloadAndOnlyMatrixTiming() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-16T14:00:00Z"))
        let previous = SentenceContext.taggerDisabledForEvaluation, previousZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone
        defer { SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate(); NSTimeZone.default = previousZone }
        let original = "Ask Dr. Patel whether she wants the staff lunch on December eleventh or the eighteenth, she gets the final say."
        let cases: [(String, String, ItemType, Bool)] = [
            (original, "Dr. Patel", .personFollowUp, false),
            ("Check with Dr. Chen if he needs the rehearsal on April ninth or the sixteenth, he has the final say.", "Dr. Chen", .task, false),
            ("Please ask Sam if they want the meeting on Monday or if they need the appointment on Tuesday, they have the final say.", "Sam", .personFollowUp, false),
            ("Ask Mom tomorrow whether she wants the lunch on Friday or Saturday, she gets the final say.", "Mom", .personFollowUp, true),
            ("Ask Sam whether he wants the rehearsal on Monday or tomorrow.", "Sam", .personFollowUp, false)
        ]
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            for (source, recipient, kind, hasMatrixDay) in cases {
                let proof = try XCTUnwrap(ClauseScope.completeAddressedChoiceQuestion(in: source), source)
                XCTAssertNil(TemporalCommitment.unsettled(in: source),
                    "Question alternatives do not unsettle the independently owned asking day: " + source)
                XCTAssertEqual(String(source[proof.recipientRange]), recipient)
                XCTAssertEqual(proof.alternativeRanges.count, 2)
                XCTAssertTrue(proof.alternativeRanges.allSatisfy {
                    proof.questionRange.lowerBound <= $0.lowerBound && $0.upperBound <= proof.questionRange.upperBound
                })
                XCTAssertEqual(proof.matrixTimingRange != nil, hasMatrixDay)
                XCTAssertEqual(ClauseScope.instructionText(source), String(source[proof.executionRange]).trimmingCharacters(in: .whitespacesAndNewlines))
                let reading = try XCTUnwrap(RuntimeShortSourceCertificate.interpret(source, referenceDate: reference, calendar: calendar), source)
                XCTAssertEqual(reading.items.count, 1); XCTAssertTrue(reading.operations.isEmpty)
                let item = try XCTUnwrap(reading.items.first)
                XCTAssertEqual(item.sourceQuote, source); XCTAssertEqual(item.rawQuote, source)
                XCTAssertEqual(item.analysisText, source); XCTAssertFalse(item.wasRepaired)
                XCTAssertEqual(item.sourceUnitIDs, Set(SourceUnitLedger(source).words.indices))
                XCTAssertEqual(item.organization.itemType, kind); XCTAssertEqual(item.organization.personName, recipient)
                XCTAssertEqual(RuntimeShortSourceCertificate.purpose(source), kind)
                XCTAssertFalse(item.needsReview); XCTAssertFalse(item.organization.needsClarification)
                XCTAssertEqual(item.organization.state, .resolved)
                XCTAssertNil(item.organization.reminderDate); XCTAssertEqual(item.organization.reminderDelivery, .none)
                XCTAssertNil(item.organization.locationIntent); XCTAssertNil(item.organization.recurrenceRule)
                XCTAssertNil(item.shoppingGroup)
                XCTAssertTrue(item.suggestedTitle?.contains(String(source[proof.questionRange])) == true)
                if let context = proof.decisionContextRange {
                    XCTAssertTrue(item.suggestedTitle?.contains(String(source[context])) == true)
                }
                if hasMatrixDay {
                    XCTAssertEqual(item.organization.dueDate, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference)))
                    XCTAssertEqual(item.organization.temporalIntent.kind, .dateOnly)
                    XCTAssertNil(item.organization.temporalIntent.time)
                } else {
                    XCTAssertNil(item.organization.dueDate); XCTAssertEqual(item.organization.temporalIntent, .none)
                }
            }
            let unsettledMatrix = "Ask Mom Friday or Saturday whether she wants the lunch on Monday or Tuesday."
            XCTAssertNil(ClauseScope.completeAddressedChoiceQuestion(in: unsettledMatrix))
            XCTAssertEqual(TemporalCommitment.unsettled(in: unsettledMatrix), .competingDays,
                "An unchosen matrix day cannot borrow settled status from its question")
            let held = ThoughtOrganizer.organize(unsettledMatrix, referenceDate: reference, calendar: calendar)
            XCTAssertTrue(held.needsClarification); XCTAssertEqual(held.state, .underspecified(.ambiguousTemporalScope))
            XCTAssertNil(held.dueDate); XCTAssertNil(held.reminderDate)
            XCTAssertNil(RuntimeShortSourceCertificate.interpret(unsettledMatrix, referenceDate: reference, calendar: calendar))

            // Exercise the actual no-model Engine fallback, including the
            // comma and dotted title that its generic literal reader declines.
            let fallback = await ThoughtExtractionEngine.extract(original, referenceDate: reference,
                calendar: calendar, permitsOnDeviceIntelligence: false)
            XCTAssertEqual(fallback.items.count, 1); XCTAssertTrue(fallback.operations.isEmpty)
            let kept = try XCTUnwrap(fallback.items.first)
            XCTAssertEqual(kept.rawQuote, original); XCTAssertEqual(kept.sourceQuote, original)
            XCTAssertEqual(kept.sourceUnitIDs, Set(SourceUnitLedger(original).words.indices))
            XCTAssertEqual(kept.organization.personName, "Dr. Patel")
            XCTAssertTrue(kept.organization.itemType.isActionable)
            XCTAssertNil(kept.organization.dueDate); XCTAssertNil(kept.organization.reminderDate)
            XCTAssertEqual(kept.organization.temporalIntent, .none); XCTAssertFalse(kept.needsReview)

            for source in [
                "Sam said, '" + original + "'",
                "Sam asked Dr. Patel whether she wants the staff lunch on December eleventh or the eighteenth.",
                "Do not ask Dr. Patel whether she wants the staff lunch on December eleventh or the eighteenth.",
                "If Sam agrees, ask Dr. Patel whether she wants the staff lunch on December eleventh or the eighteenth.",
                "Ask Sam whether he wants the rehearsal on Monday or Tuesday, and email Mom.",
                "Ask Sam whether he wants the rehearsal on Monday or Tuesday, keep a separate note about the roof.",
                "Ask Sam whether he wants the rehearsal on Monday or Tuesday, she gets the final say.",
                "Ask Sam whether he wants the rehearsal on Monday or",
                "Ask Sam whether he wants the rehearsal on Monday or the eighteenth.",
                "Ask Sam whether he wants the call Mom rehearsal on Monday or Tuesday."
            ] {
                XCTAssertNil(ClauseScope.completeAddressedChoiceQuestion(in: source), source)
                XCTAssertNil(RuntimeShortSourceCertificate.interpret(source, referenceDate: reference, calendar: calendar), source)
            }
            let unresolved = "Ask them whether they want the rehearsal on Monday or Tuesday."
            XCTAssertNil(RuntimeShortSourceCertificate.interpret(unresolved, referenceDate: reference, calendar: calendar),
                "A syntactic question slot cannot invent a resolved contact")
        }
    }

    func testMultiwordFiniteCauseKeepsSpeakersResultiveCommitmentSeparate() {
        for source in [
            "The furnace warranty expires in November so I should book the service",
            "The guy said the furnace warranty expires in November so I need to book the service",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertEqual(result.items.count, 2, source)
            XCTAssertTrue(result.items.contains { !$0.organization.itemType.isActionable
                && $0.sourceQuote.contains("furnace warranty") }, source)
            XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.contains("book the service") }, source)
        }
        for source in ["Buy milk so the kids have breakfast", "Okay so I need to call Catherine tomorrow",
                       "Sarah said I need to rebook the service"] {
            XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(source).items.count, 1, source)
        }
    }

    func testAcceptedMemoryContinuationSuppliesLocalPurchaseBeneficiary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        let original = Self.displaySetupLongCapture
        let reductions = [
            ("original-long", original),
            ("intervening-recall", "Remember that Amira prefers oat milk rather than soy. I was going to get drinks for the setup volunteers and that detail came back to me. Buy oat milk for her as a task."),
            ("adjacent-antecedent", "Remember that Amira prefers oat milk rather than soy. Buy oat milk for her as a task."),
            ("antecedent-removed-UNRESOLVED", "Buy oat milk for her as a task.")
        ]
        for (label, source) in reductions {
            let rows = ThoughtExtractionEngine.extractWithRules(source, referenceDate: reference, calendar: calendar).items
            let purchase = rows.first { $0.sourceQuote.contains("Buy oat milk") }
            XCTAssertNotNil(purchase)
            if label != "antecedent-removed-UNRESOLVED" {
                XCTAssertEqual(purchase?.organization.personName, "Amira")
            } else {
                XCTAssertNil(purchase?.organization.personName)
            }
        }
    }

    func testAcceptedMemoryOwnerDoesNotCrossUnrelatedOrAttributedScope() {
        let samples: [(String, String?)] = [
            ("Remember that Kai prefers sparkling water. I was going to collect drinks and that detail came back to me. Buy sparkling water for him as a task.", "Kai"),
            ("Remember that Kai prefers sparkling water. I was going to collect drinks and that detail came back to me. Buy a notebook labelled 'For him'.", nil),
            ("Remember that Kai prefers sparkling water. The printer is in the studio. Buy sparkling water for him as a task.", nil),
            ("Remember that Kai prefers sparkling water. I was going to collect drinks and that detail came back to me. Call the clinic tomorrow. Buy sparkling water for him as a task.", nil),
            ("Remember that Kai prefers sparkling water. Remember that Nora prefers juice. Buy juice for her as a task.", "Nora"),
            ("Remember that Kai prefers sparkling water. I was going to collect drinks and that detail came back to me. Buy sparkling water for them as a task.", nil)
        ]
        for (source, expected) in samples {
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            let purchase = rows.first { $0.organization.itemType == .shopping }
            XCTAssertNotNil(purchase, source)
            XCTAssertEqual(purchase?.organization.personName, expected, source)
            XCTAssertNil(purchase?.organization.dueDate, source)
            XCTAssertNil(purchase?.organization.reminderDate, source)
        }
        let attributed = "Remember that Kai prefers sparkling water. I was going to collect drinks and that detail came back to me. Nora said, 'Buy sparkling water for him as a task.'"
        let report = ThoughtExtractionEngine.extractWithRules(attributed).items
        XCTAssertFalse(report.contains { $0.organization.itemType == .shopping })
    }

    func testExplicitPluralFactRetentionOwnsItsDeclaredNoteGroup() {
        let original = ThoughtExtractionEngine.extractWithRules(Self.displaySetupLongCapture).items
        let setup = original.filter { $0.sourceQuote.contains("display setup") }
        XCTAssertEqual(setup.count, 1)
        XCTAssertTrue(setup.first?.sourceQuote.contains("taller board") == true)
        XCTAssertTrue(setup.first?.sourceQuote.contains("lamps point") == true)
        XCTAssertTrue(setup.first?.sourceQuote.contains("Keep those as setup facts") == true)
        XCTAssertEqual(original.filter { $0.sourceQuote.contains("taller board") }.count, 1)
        let distinct = "I want a note about the workshop arrangement. The cabinet opens towards the wall. The stool goes beside the bench. Keep these as arrangement facts. Call Nora tomorrow."
        let rows = ThoughtExtractionEngine.extractWithRules(distinct).items
        XCTAssertEqual(rows.count, 2, rows.map(\.sourceQuote).joined(separator: " | "))
        XCTAssertTrue(rows.first?.sourceQuote.contains("cabinet opens") == true)
        XCTAssertTrue(rows.first?.sourceQuote.contains("stool goes") == true)
        XCTAssertEqual(rows.first?.organization.itemType, .note)
        XCTAssertEqual(rows.last?.organization.personName, "Nora")
        let independent = ThoughtExtractionEngine.extractWithRules("I want a note about the workshop arrangement. The cabinet opens towards the wall. Remember that Priya is allergic to sesame. Keep those as arrangement facts.").items
        XCTAssertTrue(independent.contains { $0.sourceQuote.contains("Remember that Priya") && !$0.sourceQuote.contains("cabinet opens") })
        let newTopic = ThoughtExtractionEngine.extractWithRules("I want a note about the workshop arrangement. The cabinet opens towards the wall. The stool goes beside the bench. Separately, the cafe opens early. Keep these as arrangement facts.").items
        XCTAssertTrue(newTopic.contains { $0.sourceQuote.contains("cafe opens") && !$0.sourceQuote.contains("workshop arrangement") && $0.organization.itemType == .note && !$0.needsReview && $0.organization.dueDate == nil })
        let interrupted = ThoughtExtractionEngine.extractWithRules("I want a note about the workshop arrangement. The cabinet opens towards the wall. Check the fire alarm. The stool goes beside the bench. Keep these as arrangement facts.").items
        XCTAssertTrue(interrupted.contains { $0.organization.itemType.isActionable && $0.analysisText.lowercased().contains("check the fire alarm") })
        XCTAssertFalse(interrupted.contains { $0.sourceQuote.contains("workshop arrangement") && $0.sourceQuote.contains("Check the fire alarm") })
        let reported = ThoughtExtractionEngine.extractWithRules("I want a note about the briefing. Asha said, 'Open the cabinet tomorrow.' The stool goes beside the bench. Keep these as briefing facts.").items
        XCTAssertTrue(reported.allSatisfy { !$0.organization.itemType.isActionable && $0.organization.reminderDate == nil })
    }

    func testListContentsDistinguishActionsFromNominalProducts() {
        let actions = [
            ("Add making the display page to my list.", "make the display page"),
            ("Put washing the windows on my list.", "wash the windows"),
            ("Add calling the dentist to my task list.", "call the dentist"),
            ("Add making a shopping list to my list.", "make a shopping list")
        ]
        for (source, body) in actions {
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(rows.count, 1, source)
            XCTAssertEqual(rows.first?.organization.itemType, .task, source)
            XCTAssertEqual(rows.first?.analysisText.lowercased(), body, source)
            XCTAssertFalse(rows.first?.needsReview ?? true, source)
            XCTAssertNil(rows.first?.organization.dueDate, source)
            XCTAssertNil(rows.first?.organization.reminderDate, source)
            XCTAssertEqual(rows.first?.sourceQuote, source)
        }
        for product in ["icing sugar", "cleaning spray", "running shoes", "washing powder"] {
            let source = "Add \(product) to my shopping list."
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(rows.count, 1, source)
            XCTAssertEqual(rows.first?.organization.itemType, .shopping, source)
            XCTAssertTrue(rows.first?.analysisText.lowercased().contains(product) == true, source)
            XCTAssertEqual(rows.first?.sourceQuote, source)
        }
        let original = ThoughtExtractionEngine.extractWithRules(Self.displaySetupLongCapture).items
        let page = original.filter { $0.sourceQuote.contains("Add making that page") }
        XCTAssertEqual(page.count, 1)
        XCTAssertEqual(page.first?.organization.itemType, .task)
        XCTAssertFalse(page.first?.needsReview ?? true)
        XCTAssertTrue(page.first?.analysisText.lowercased().hasPrefix("make ") == true)
        XCTAssertNil(page.first?.organization.dueDate)
        XCTAssertNil(page.first?.organization.reminderDate)
    }

    func testResolvedChoiceSuppliesMatchingCreationObjectWithoutAdoptingReports() {
        let previousTaggerMode = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previousTaggerMode
            SentenceContextCache.invalidate()
        }
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            let original = ThoughtExtractionEngine.extractWithRules(Self.displaySetupLongCapture).items
            let page = original.first { $0.sourceQuote.contains("Add making that page") }
            XCTAssertEqual(page?.organization.itemType, .task)
            XCTAssertTrue(page?.analysisText.lowercased().contains("simple web page") == true)
            XCTAssertTrue(page?.sourceQuote.contains("decided on a simple web page") == true)
            XCTAssertTrue(page?.sourceQuote.contains("Use the final display captions as the content") == true)
            XCTAssertFalse(original.contains { $0.sourceQuote.contains("Use the final display captions") && !$0.sourceQuote.contains("Add making that page") })

            let selected = ThoughtExtractionEngine.extractWithRules("I decided on a small wooden cabinet. Add making that cabinet to my list. Use oak panels as the material.").items
            let cabinet = selected.first { $0.organization.itemType == .task }
            XCTAssertEqual(selected.count, 1)
            XCTAssertTrue(cabinet?.analysisText.lowercased().contains("small wooden cabinet") == true)
            XCTAssertTrue(cabinet?.sourceQuote.contains("oak panels") == true)
            XCTAssertNil(cabinet?.organization.dueDate)
            XCTAssertNil(cabinet?.organization.reminderDate)
            let selection = "I decided on a small wooden cabinet. Add making that cabinet to my list. "
            for source in [
                selection + "Use the cabinet in the workshop.",
                selection + "Use oak panels as the material tomorrow.",
                "Make a cabinet. Use oak panels as the material."
            ] {
                let rows = ThoughtExtractionEngine.extractWithRules(source).items
                XCTAssertTrue(rows.contains { $0.sourceQuote.contains("Use ")
                    && !$0.sourceQuote.contains("Add making")
                    && !$0.sourceQuote.contains("Make a cabinet") }, source)
            }
            let extra = ThoughtExtractionEngine.extractWithRules(
                selection + "Use oak panels as the material and call Nora."
            ).items
            XCTAssertTrue(extra.contains { $0.organization.itemType.isActionable
                && $0.organization.personName == "Nora" }, String(reflecting: extra))
            XCTAssertFalse(extra.contains { $0.sourceQuote.contains("Add making")
                && $0.sourceQuote.contains("call Nora") }, String(reflecting: extra))
            for source in [
                "Nora said, 'I decided on a red cabinet.' Add making that cabinet to my list.",
                "I decided on a small wooden cabinet. Add making that shelf to my list.",
                "I decided on a cabinet and shelf. Add making that shelf to my list.",
                "I decided on a small wooden cabinet. Call Nora tomorrow. Add making that cabinet to my list."
            ] {
                let rows = ThoughtExtractionEngine.extractWithRules(source).items
                let action = rows.first { $0.sourceQuote.contains("Add making") }
                XCTAssertNotNil(action)
                XCTAssertFalse(action?.analysisText.lowercased().contains("small wooden cabinet") == true, source)
                XCTAssertFalse(action?.analysisText.lowercased().contains("red cabinet") == true, source)
                XCTAssertFalse(action?.analysisText.lowercased().contains("cabinet and shelf") == true, source)
            }
        }
    }

    func testCommunicationMatrixAdjunctBeforeQuestionKeepsRecipientAndSeparateClocks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        let samples: [(String, String, Int)] = [
            ("Ask June tomorrow whether I can collect the key on Thursday evening.", "June", 6),
            ("Ask Nora on Friday whether the room opens at ten on Monday.", "Nora", 9),
            ("Text Sam tomorrow that the train leaves at ten on Friday.", "Sam", 6)
        ]
        for (source, person, day) in samples {
            let reading = ClauseScope.read(source)
            XCTAssertEqual(reading.act, .communicating, source + " matrix=" + reading.matrix)
            XCTAssertEqual(reading.recipient, person, source)
            let rows = ThoughtExtractionEngine.extractWithRules(source, referenceDate: reference, calendar: calendar).items
            XCTAssertEqual(rows.count, 1, source)
            let row = rows.first
            XCTAssertEqual(row?.organization.personName, person, source)
            XCTAssertEqual(row?.organization.temporalIntent.day?.day, day, source)
            XCTAssertNil(row?.organization.temporalIntent.time, source)
            XCTAssertNil(row?.organization.reminderDate, source)
            XCTAssertEqual(row?.needsReview, false, source)
        }
        for event in ["The game starts at 7:30 tonight", "The train leaves at 06:20 tomorrow", "The train leaves at 08:45 tomorrow"] {
            XCTAssertEqual(ActionabilityReader.read(event), .event, event)
            let rows = ThoughtExtractionEngine.extractWithRules(event, referenceDate: reference, calendar: calendar).items
            XCTAssertEqual(rows.count, 1, event)
            XCTAssertNotNil(rows.first?.organization.dueDate, event)
            XCTAssertTrue(rows.first?.organization.itemType.isActionable == true, event)
        }
        XCTAssertEqual(ActionabilityReader.read("Open the document."), .actionable)
        XCTAssertEqual(ActionabilityReader.read("The document opens in a new window."), .knowledge)
        for source in ["  Ask June tomorrow whether I can collect the key.", "\n\tAsk April tomorrow whether I can bring the folder in June."] {
            let reading = ClauseScope.read(source)
            let expected = source.contains("Ask June") ? "June" : "April"
            XCTAssertEqual(reading.recipientRange.map { String(source[$0]) }, expected)
            if case .person(let person) = PersonMentionResolver.followUpTarget(in: source) {
                XCTAssertEqual(person.label, expected)
                XCTAssertEqual(String(source[person.sourceRange]), expected)
            } else { XCTFail("Established recipient missing: " + source) }
        }
        XCTAssertEqual(ClauseScope.read("Ask April tomorrow whether I can bring the folder in June.").recipient, "April")
        XCTAssertEqual(PersonMentionResolver.followUpTarget(in: "Text support tomorrow that the form is ready."), .described("support"))
        let errand = ThoughtExtractionEngine.extractWithRules("Text Sam tomorrow at five PM.", referenceDate: reference, calendar: calendar).items
        XCTAssertEqual(errand.first?.organization.temporalIntent.time, WallClockTime(hour: 17, minute: 0))
        let content = ThoughtExtractionEngine.extractWithRules("Text Sam that the train leaves at ten tomorrow morning.", referenceDate: reference, calendar: calendar).items
        XCTAssertNil(content.first?.organization.dueDate)
        XCTAssertNil(content.first?.organization.reminderDate)
        let report = ThoughtExtractionEngine.extractWithRules("Nora said, 'Ask June tomorrow whether I can collect the key on Thursday evening.'", referenceDate: reference, calendar: calendar).items
        XCTAssertTrue(report.allSatisfy { !$0.organization.itemType.isActionable && $0.organization.reminderDate == nil })
    }

    func testQuestionDateOwnershipDifferential() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        let correctIntermediate = "Tomorrow I need to ask the caretaker which entrance is open."
        let represented = ThoughtExtractionEngine.extractWithRules(
            correctIntermediate, referenceDate: reference, calendar: calendar
        ).items
        XCTAssertEqual(represented.count, 1)
        XCTAssertEqual(represented.first?.organization.temporalIntent.day?.day, 6)
        let contextual = ThoughtOrganizer.organize(
            "I need to ask the caretaker which entrance is open on Friday.",
            referenceDate: reference, calendar: calendar
        )
        XCTAssertNil(contextual.dueDate, "the entrance's opening day is question content")
        let datedAction = ThoughtOrganizer.organize(
            "On Friday I need to ask the caretaker which entrance is open.",
            referenceDate: reference, calendar: calendar
        )
        XCTAssertEqual(datedAction.temporalIntent.day?.day, 9)
    }

    func testReportedQuestionTaskKeepsAttributedSourceAndNoInventedOperations() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        let source = "Remember this conversation with Jo. Jo said, 'Delete the old draft and send everyone the final one.' I am recording what Jo said, not asking this app to delete anything or send any files. Keep the attribution because otherwise it will look like a direct instruction from me.\n\nI do need to ask Jo which version is final before I decide what to do. Make that question a task for tomorrow. There is no permission to delete the old draft in the meantime, and the quoted send everyone instruction should not become a second task of mine."
        let result = ThoughtExtractionEngine.extractWithRules(source, referenceDate: reference, calendar: calendar)
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertEqual(result.items.count, 2, result.items.map { "\($0.analysisText) review=\($0.needsReview)" }.joined(separator: " | "))
        let task = result.items.filter { $0.organization.itemType.isActionable }
        XCTAssertEqual(task.count, 1)
        XCTAssertTrue(task.first?.analysisText.contains("ask Jo") == true)
        XCTAssertEqual(task.first?.organization.temporalIntent.day?.day, 6)
        XCTAssertTrue(result.items.allSatisfy { !$0.needsReview })
        XCTAssertTrue(result.items.contains {
            $0.organization.itemType == .note && $0.sourceQuote.contains("Jo said")
                && $0.sourceQuote.contains("Delete the old draft")
        })
    }

    func testQuestionTaskDeclarationAttachesDateOnlyToUniqueOwnQuestion() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 5, hour: 9
        ))!
        func extract(_ text: String) -> [ExtractedThought] {
            ThoughtExtractionEngine.extractWithRules(
                text, referenceDate: reference, calendar: calendar
            ).items
        }
        let question = "I need to ask the caretaker which entrance is open."
        let declaration = "Make that question a task for tomorrow."
        let result = extract(question + " " + declaration + " Buy batteries.")
        XCTAssertEqual(result.count, 2, result.map(\.analysisText).joined(separator: " | "))
        let ask = result.first { $0.analysisText.contains("ask") }
        XCTAssertEqual(ask?.organization.temporalIntent.kind, .dateOnly)
        XCTAssertEqual(ask?.organization.temporalIntent.day?.day, 6)
        XCTAssertTrue(ask?.sourceQuote.contains(declaration) == true)
        XCTAssertFalse(ask?.needsReview == true)
        XCTAssertNil(result.first { $0.analysisText.contains("batteries") }?.organization.dueDate)
        for source in [
            declaration,
            question + " I need to ask the plumber what the valve controls. " + declaration,
            "The caretaker said to ask which entrance is open. " + declaration,
            "On Friday I need to ask the caretaker which entrance is open. " + declaration
        ] {
            let unresolved = extract(source)
            XCTAssertTrue(unresolved.contains { $0.needsReview }, source)
            XCTAssertFalse(unresolved.contains {
                $0.analysisText.contains("ask")
                    && $0.organization.temporalIntent.day?.day == 6
            }, source)
        }
    }

    static let clubEventLongCapture = """
I am thinking about the club event on Friday, October ninth. The room itself is already confirmed, so that is one less thing to chase. I need to print the direction sign, the one with the arrow to the courtyard entrance. Last time people kept trying the front doors and then messaging us because they were locked. Use the bigger type version. Get that printed before the event starts at six in the evening; I do not want the reminder to happen only when people are arriving.

Asha said, 'Tell everyone to bring a mug,' in the committee chat. I have not agreed to send that message. I want to keep what she said as part of the event notes because we still need to decide whether the room has enough cups. My own task is to ask the caretaker how many cups are there. That needs doing tomorrow, before anybody sends a confident message about what people should bring.

The spare name badges are in the orange envelope inside the supplies bag. Remember that. I wasted a ridiculous amount of time looking in the box of cables last time. I do not need a task to move them, I just need to find them when we pack. The little black marker is with the badges too, so that detail belongs in the same note.

And email Jonah the final volunteer rota once Priya has approved it. She has looked at it, but she has not said it is approved. That difference matters because I think two people are still swapping slots. No, actually, the person collecting the rota is June, not Jonah. Email June after Priya approves. I am not changing any of the shifts myself in this recording. There is also an idea for next time, having a quiet corner where people can step away from the noise. Keep that as an idea rather than adding another job for Friday.
"""

    func testFramedReportRetentionKeepsItsExistingAttributedAccount() {
        let retention = "I want to keep what she said as part of the event notes because we still need to decide whether the room has enough cups."
        XCTAssertEqual(ActionabilityReader.read(retention), .knowledge)
        let short = "Asha said, 'Tell everyone to bring a mug,' in the committee chat. I have not agreed to send that message. " + retention + " My own task is to ask the caretaker how many cups are there."
        for source in [short, Self.clubEventLongCapture] {
            let result = ThoughtExtractionEngine.extractWithRules(source, permitsOperations: false)
            let owner = result.items.first { $0.organization.itemType == .note && $0.sourceQuote.contains("Asha said") }
            XCTAssertTrue(owner?.sourceQuote.contains(retention) ?? false)
            XCTAssertFalse(owner?.needsReview ?? true)
            XCTAssertNil(owner?.organization.reminderDate)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("keep what she said") })
            XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("ask the caretaker")
                && !$0.sourceQuote.contains("Asha said") })
        }
        for source in [
            "Asha said, 'Bring a mug.' Mina said, 'Bring a plate.' " + retention,
            "Asha said, 'Bring a mug.' Keep what Nora said as a note."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertTrue(result.items.contains { $0.needsReview && ($0.sourceQuote.contains(retention)
                || $0.sourceQuote.contains("what Nora said")) }, source)
            XCTAssertFalse(result.items.contains { $0.sourceQuote.contains("Asha said")
                && ($0.sourceQuote.contains(retention) || $0.sourceQuote.contains("what Nora said")) }, source)
        }
        let separatedFact = ThoughtExtractionEngine.extractWithRules(
            "Asha said, 'Bring a mug.' The shed key has a blue tag. " + retention)
        XCTAssertEqual(separatedFact.items.count, 2)
        XCTAssertTrue(separatedFact.items.contains { $0.sourceQuote.contains("Asha said")
            && $0.sourceQuote.contains(retention) && !$0.sourceQuote.contains("shed key") && !$0.needsReview })
        XCTAssertTrue(separatedFact.items.contains { $0.sourceQuote.contains("shed key")
            && !$0.sourceQuote.contains("Asha said") && !$0.needsReview })
        let named = ThoughtExtractionEngine.extractWithRules("Asha said, 'Bring a mug.' Keep what Asha said as a note.")
        XCTAssertEqual(named.items.count, 1)
        XCTAssertFalse(named.items.first?.needsReview ?? true)
        let independent = ThoughtExtractionEngine.extractWithRules("Asha said, 'Bring a mug.' "
            + "I want to keep what she said as part of the event notes, and I will email Nora the receipt.")
        XCTAssertTrue(independent.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("email Nora") })
        XCTAssertFalse(independent.items.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Asha said") && $0.sourceQuote.contains("email Nora") })
        for source in ["I want to save the note PDF in my Projects folder", "Keep the reflection notebook on the shelf"] {
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
        }
    }

    func testUncommittedProjectRetentionDoesNotEnterQuotedAgreementRouting() {
        let retention = "I have not committed to making it, but I would like to keep the idea."
        XCTAssertFalse(ActionabilityReader.isUnadoptedAction(retention))
        for source in [retention,
            "There was a possible project idea too. Maybe a small photo guide showing where the shared equipment lives would save everyone time. I can imagine a picture of each drawer with a short caption rather than a long document nobody reads. " + retention] {
            let result = ThoughtExtractionEngine.extractWithRules(source, permitsOperations: false)
            let owner = result.items.first { $0.sourceQuote.contains(retention) }
            XCTAssertEqual(owner?.organization.itemType, .idea)
            XCTAssertFalse(owner?.needsReview ?? true)
            XCTAssertFalse(owner?.organization.itemType.isActionable ?? true)
        }
    }

    /// The canonical S102 frame: Monday 2026-10-05 09:00 in Toronto.
    private static func clubFrame() -> (Date, Calendar) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        return (reference, calendar)
    }

    func testClubEventCaptureKeepsItsSixMeaningsThroughDiscourseOwnership() throws {
        let (reference, calendar) = Self.clubFrame()
        // The lowercase rendering is not covered: without capitals the
        // sentence tokenizer fuses neighbouring sentences (see KNOWN_ISSUES).
        for source in [Self.clubEventLongCapture,
                       Self.clubEventLongCapture.replacingOccurrences(of: ". ", with: ".\n")] {
            let items = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: reference, calendar: calendar, permitsOperations: false
            ).items
            let summary = items.map { "\($0.organization.itemType.rawValue): \($0.analysisText)" }
                .joined(separator: " | ")
            XCTAssertEqual(items.count, 6, summary)
            XCTAssertTrue(items.allSatisfy { !$0.needsReview && $0.organization.reminderDate == nil }, summary)
            XCTAssertFalse(items.contains { $0.organization.itemType == .event }, summary)

            let sign = try XCTUnwrap(items.first { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("direction sign") }, summary)
            XCTAssertEqual(sign.organization.temporalIntent.day, CalendarDay(year: 2026, month: 10, day: 9))
            XCTAssertNil(sign.organization.temporalIntent.time)
            XCTAssertTrue(sign.suggestedTitle?.localizedCaseInsensitiveContains("before the event starts at six") ?? false)
            for words in ["bigger type version", "front doors", "do not want the reminder", "october ninth"] {
                XCTAssertTrue(sign.sourceQuote.localizedCaseInsensitiveContains(words), words)
            }

            let account = try XCTUnwrap(items.first { $0.sourceQuote.localizedCaseInsensitiveContains("asha said") })
            XCTAssertFalse(account.organization.itemType.isActionable)
            XCTAssertTrue(account.sourceQuote.localizedCaseInsensitiveContains("i have not agreed to send that message"))

            let caretaker = try XCTUnwrap(items.first { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("caretaker") })
            XCTAssertEqual(caretaker.organization.temporalIntent.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertTrue(caretaker.sourceQuote.localizedCaseInsensitiveContains("before anybody sends a confident message"))
            XCTAssertFalse(caretaker.sourceQuote.localizedCaseInsensitiveContains("asha said"))

            let badges = try XCTUnwrap(items.first { $0.analysisText.localizedCaseInsensitiveContains("name badges") })
            XCTAssertEqual(badges.organization.itemType, .note)
            for words in ["little black marker", "box of cables", "do not need a task to move them"] {
                XCTAssertTrue(badges.sourceQuote.localizedCaseInsensitiveContains(words), words)
            }
            XCTAssertFalse(badges.sourceQuote.localizedCaseInsensitiveContains("email jonah"))

            let rota = try XCTUnwrap(items.first { $0.organization.itemType.isActionable
                && $0.organization.personName == "June" })
            XCTAssertTrue(rota.analysisText.localizedCaseInsensitiveContains("final volunteer rota"))
            XCTAssertFalse(rota.analysisText.localizedCaseInsensitiveContains("jonah"))
            XCTAssertTrue(rota.analysisText.localizedCaseInsensitiveContains("once priya has approved it"))
            for words in ["she has not said it is approved", "june, not jonah", "not changing any of the shifts"] {
                XCTAssertTrue(rota.sourceQuote.localizedCaseInsensitiveContains(words), words)
            }
            XCTAssertFalse(items.contains { $0.organization.personName == "Jonah" }, summary)

            let idea = try XCTUnwrap(items.first { $0.organization.itemType == .idea })
            XCTAssertTrue(idea.analysisText.localizedCaseInsensitiveContains("quiet corner"))
            XCTAssertTrue(idea.sourceQuote.localizedCaseInsensitiveContains("keep that as an idea"))
            XCTAssertNil(idea.organization.temporalIntent.day)
        }
    }


    func testNegatedOwnCommitmentIsNeverItselfAJob() {
        for text in ["I will not try to dry them with a hair dryer because the pages are fragile.",
                     "No one asked me to restore it or display it.",
                     "I have not promised a publication date.",
                     "I will not bake the chocolate cake as a backup.",
                     "We will not need the van.",
                     "I have decided not to buy any more mint.",
                     "I almost scheduled a second drop-off because the old task was still showing.",
                     "I was going to cut a third key for the cleaner, but she no longer needs one."] {
            XCTAssertFalse(ThoughtExtractionEngine.extractWithRules(text, permitsOperations: false).items
                .contains { $0.organization.itemType.isActionable }, text)
        }
        // Opposite direction: still owed, deferred, or followed by an own commitment.
        for (text, words) in [("I haven't submitted the report yet", "submitted the report"),
                              ("I didn't get around to the laundry", "laundry"),
                              ("I will not send it until I hear from the ranger.", "send it"),
                              ("I will not bake the cake, but I will buy candles.", "buy candles"),
                              ("I was going to call Sam, but I will email him instead.", "email"),
                              ("Don't forget to buy milk.", "milk"),
                              ("Remind me not to call Sam after nine tonight.", "call Sam"),
                              ("I haven't paid the rent, remind me tonight at eight.", "rent"),
                              ("I won't forget to call Mum on Sunday.", "call Mum"),
                              ("Do not let me forget the parcel tomorrow.", "parcel"),
                              ("Mina asked me to bring the chairs on Friday and I agreed.", "chairs")] {
            XCTAssertTrue(ThoughtExtractionEngine.extractWithRules(text, permitsOperations: false).items
                .contains { $0.organization.itemType.isActionable
                    && $0.analysisText.localizedCaseInsensitiveContains(words) }, text)
        }
    }


    func testOneAccountMemoryNeedsADeclaredAccountAndNoCommitmentForm() {
        let account = ["I want to remember how the reading garden began.", "Hester put a bench by her gate.",
                       "Neighbours waiting for the bus stopped to talk.", "Malik later asked the owner for permission.",
                       "The first plants came from cuttings.", "The council only added a sign years later.",
                       "Nobody planned it as a garden at first."]
        func read(_ text: String) -> [ExtractedThought] {
            ThoughtExtractionEngine.extractWithRules(text, permitsOperations: false).items
        }
        // Five, six and seven sentences, and capitalization/line-break renderings.
        for count in [5, 6, 7] {
            let text = account.prefix(count).joined(separator: " ")
            for rendering in [text, text.lowercased(), text.replacingOccurrences(of: ". ", with: ".\n")] {
                let items = read(rendering)
                XCTAssertEqual(items.count, 1, "\(count): " + items.map(\.analysisText).joined(separator: " | "))
                XCTAssertFalse(items.contains { $0.organization.itemType.isActionable }, rendering)
            }
        }
        // Unpunctuated: whatever the grouping, no task should be invented.
        // Known defect (KNOWN_ISSUES: long captures without punctuation):
        // without stops "Hester put a bench" is cut after the name and the
        // rest reads as a job. Recorded as an expected failure, not removed.
        XCTExpectFailure("Unpunctuated account still invents a task at a name+past-verb boundary") {
            XCTAssertFalse(read(account.joined(separator: " ").replacingOccurrences(of: ".", with: ""))
                .contains { $0.organization.itemType.isActionable })
        }
        // A commitment inside the account survives as its own task, by
        // imperative head or by first-person obligation, in each rendering.
        for tail in ["Count the cuttings in the shed tomorrow.", "I need to send Malik the photos."] {
            let text = account.prefix(6).joined(separator: " ") + " " + tail
            for rendering in [text, text.replacingOccurrences(of: ". ", with: ".\n")] {
                let items = read(rendering)
                let words = tail.contains("Count") ? "count the cuttings" : "send malik the photos"
                XCTAssertTrue(items.contains { $0.organization.itemType.isActionable
                    && $0.analysisText.lowercased().contains(words) }, rendering)
                XCTAssertFalse(items.contains { !$0.organization.itemType.isActionable
                    && $0.sourceQuote.lowercased().contains(words) }, rendering)
            }
        }
    }

    func testRejectedActionsStayAbsentAndProhibitionsSurvive() {
        let (reference, calendar) = Self.clubFrame()
        func read(_ text: String) -> [ExtractedThought] {
            ThoughtExtractionEngine.extractWithRules(text, referenceDate: reference, calendar: calendar,
                                                     permitsOperations: false).items
        }
        // Rejected or abandoned actions: no actionable row carries them.
        for (text, rejected) in [("I will not dry the pages with a hair dryer. Buy blotting paper.", "hair dryer"),
                                 ("I was going to cut a third key, but the cleaner no longer needs one. Call the locksmith on Friday.", "third key"),
                                 ("I have decided not to buy any more mint. Water the basil tonight.", "mint")] {
            let items = read(text)
            XCTAssertFalse(items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains(rejected) }, text)
            XCTAssertTrue(items.count >= 2, text)
            // The unrelated valid commitment in the same capture survives.
            XCTAssertTrue(items.contains { $0.organization.itemType.isActionable
                && !$0.analysisText.localizedCaseInsensitiveContains(rejected) }, text)
        }
        // A negative reminder keeps its prohibition in the saved wording.
        let negative = read("Remind me not to call Sam after nine tonight.")
        XCTAssertEqual(negative.count, 1)
        XCTAssertTrue(negative.first?.organization.itemType.isActionable ?? false)
        XCTAssertTrue((negative.first?.suggestedTitle ?? negative.first?.analysisText ?? "")
            .localizedCaseInsensitiveContains("not to call"), negative.first?.analysisText ?? "")
        XCTAssertNotNil(negative.first?.organization.reminderDate)
    }

    func testDiscourseOwnershipLeavesIndependentNeighboursAlone() throws {
        let (reference, calendar) = Self.clubFrame()
        func read(_ text: String) -> [ExtractedThought] {
            ThoughtExtractionEngine.extractWithRules(
                text, referenceDate: reference, calendar: calendar, permitsOperations: false).items
        }
        // The opposite control: approval already given, recipient never corrected.
        let opposite = read("Priya has approved the rota. Email Jonah the final rota.")
        // A complete short perfect fact stays findable in Memory and also
        // supplies literal context to the one current communication.
        XCTAssertEqual(opposite.count, 2, opposite.map(\.analysisText).joined(separator: " | "))
        let communication = try XCTUnwrap(opposite.first { $0.organization.itemType.isActionable })
        XCTAssertEqual(communication.organization.personName, "Jonah")
        XCTAssertTrue(communication.sourceQuote.contains("Priya has approved the rota."))
        XCTAssertFalse(communication.needsReview)
        XCTAssertTrue(opposite.contains { $0.organization.itemType == .note
            && !$0.needsReview && $0.sourceQuote == "Priya has approved the rota." })
        // A genuinely separate second email keeps its own recipient and object.
        let two = read("Email Jonah the rota once Priya approves. Email Nora the budget.")
        XCTAssertTrue(two.contains { $0.organization.personName == "Jonah" && $0.analysisText.contains("rota") })
        XCTAssertTrue(two.contains { $0.organization.personName == "Nora" && $0.analysisText.contains("budget") })
        // A correction inside someone else's quote revises nothing of mine.
        let quoted = read("Email Nora the minutes. Mina said, 'No, actually, it is Sam, not Nora.'")
        XCTAssertTrue(quoted.contains { $0.organization.itemType.isActionable && $0.organization.personName == "Nora" })
        XCTAssertFalse(quoted.contains { $0.organization.personName == "Sam" })
        // A correction that names nobody the action is for stays its own row.
        let unrelated = read("Email Jonah the rota. Actually it is June, not Mina.")
        XCTAssertTrue(unrelated.contains { $0.organization.itemType.isActionable && $0.organization.personName == "Jonah" })
        // A plain fact after a task, and a pronoun fact without a shared object, stay independent.
        XCTAssertEqual(read("Buy batteries. The door code is 3812.").count, 2)
        XCTAssertEqual(read("Water the ferns. They are on the back porch.").count, 2)
        // A committed task after a retained idea is its own task with its own day.
        let ideaThenTask = read("There is an idea for next time, a quiet corner. Keep that as an idea. Book the hall for Friday.")
        XCTAssertEqual(ideaThenTask.count, 2)
        XCTAssertTrue(ideaThenTask.contains { $0.organization.itemType == .idea && $0.organization.temporalIntent.day == nil })
        XCTAssertTrue(ideaThenTask.contains { $0.organization.itemType == .task
            && $0.organization.dueDate == nil && $0.organization.reminderDate == nil
            && $0.organization.temporalIntent.kind == .none
            && ($0.suggestedTitle ?? $0.analysisText).localizedCaseInsensitiveContains("for Friday") })
        // A pronoun restatement supplies its day to the action it repeats.
        let restated = read("Call the plumber about the leak. Do that tomorrow.")
        XCTAssertEqual(restated.count, 1)
        XCTAssertEqual(restated.first?.organization.temporalIntent.day, CalendarDay(year: 2026, month: 10, day: 6))
        // An unresolvable event reference stays visible instead of borrowing a day.
        let unknownEvent = read("Print the agenda. Get that printed before the meeting starts at six.")
        XCTAssertFalse(unknownEvent.contains { $0.organization.temporalIntent.day != nil && !$0.needsReview })
        // Declining one of Speak It's outputs is context, not a review row or task.
        let declined = read("The spare key is under the mat. I do not need a task for that.")
        XCTAssertEqual(declined.count, 1)
        XCTAssertEqual(declined.first?.organization.itemType, .note)
        // A cataphoric retention declaration is not folded into the previous row.
        let declared = read("Buy batteries. Keep this as an idea: a shared tool shelf.")
        XCTAssertTrue(declared.contains { $0.organization.itemType == .idea || $0.analysisText.contains("tool shelf") })
        XCTAssertTrue(declared.contains { $0.organization.itemType.isActionable && $0.analysisText.contains("batteries")
            && !$0.sourceQuote.contains("tool shelf") })
    }

    func testClubRotaKeepsItsObjectAndApprovalContextThroughRecipientCorrection() {
        let reduced = Self.clubEventLongCapture.components(separatedBy: "\n\n").suffix(2)
            .joined(separator: "\n\n")
        let fullRepeat = "Email June the final volunteer rota once Priya has approved it."
        for source in [reduced, Self.clubEventLongCapture,
                       reduced.replacingOccurrences(of: "Email June after Priya approves.", with: fullRepeat),
                       Self.clubEventLongCapture.replacingOccurrences(of: "Email June after Priya approves.", with: fullRepeat)] {
            let result = ThoughtExtractionEngine.extractWithRules(source, permitsOperations: false)
            let emails = result.items.filter { $0.organization.itemType.isActionable
                && $0.organization.personName == "June" }
            XCTAssertEqual(emails.count, 1)
            let owner = emails.first
            XCTAssertTrue(owner?.analysisText.localizedCaseInsensitiveContains("final volunteer rota") ?? false)
            XCTAssertTrue(owner?.sourceQuote.contains("email Jonah the final volunteer rota once Priya has approved it") ?? false)
            XCTAssertTrue(owner?.sourceQuote.contains("she has not said it is approved") ?? false)
            XCTAssertFalse(owner?.needsReview ?? true)
            XCTAssertNil(owner?.organization.reminderDate)
            XCTAssertFalse(result.items.contains { $0.needsReview
                && $0.analysisText.localizedCaseInsensitiveContains("email June") }, source)
            XCTAssertFalse(result.items.contains { $0.organization.itemType == .note
                && $0.sourceQuote.contains("little black marker")
                && $0.sourceQuote.contains("email Jonah") })
        }
    }

    func testAttributedAccountRetainsExactOccurrenceOwnership() throws {
        let report = "Asha said, 'Tell everyone to bring a mug,' in the committee chat."
        let refusal = "I have not agreed to send that message."
        let retention = "I want to keep what she said as part of the event notes because we still need to decide whether the room has enough cups."
        let source = report + " " + refusal + " " + retention + " Buy batteries."
        let result = ThoughtExtractionEngine.extractWithRules(source, permitsOperations: false)
        let owner = try XCTUnwrap(result.items.first { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Asha said") })
        let ledger = SourceUnitLedger(source)
        for piece in [report, refusal, retention] {
            let range = try XCTUnwrap(source.range(of: piece))
            XCTAssertTrue(ledger.ids(in: range).isSubset(of: owner.sourceUnitIDs))
        }
        let independent = try XCTUnwrap(source.range(of: "Buy batteries."))
        XCTAssertTrue(ledger.ids(in: independent).isDisjoint(with: owner.sourceUnitIDs))
        XCTAssertEqual(ledger.unownedMeaningfulIDs(after: result.items), [])
    }

    func testUnadoptedMessageAgreementKeepsTheQuotedAccountWithoutInventingWork() {
        let denial = "I have not agreed to send that message."
        XCTAssertEqual(ActionabilityReader.read(denial), .knowledge)
        let short = "Asha said, 'Tell everyone to bring a mug,' in the committee chat. " + denial + " Buy batteries."
        for source in [short, Self.clubEventLongCapture] {
            let result = ThoughtExtractionEngine.extractWithRules(source, permitsOperations: false)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.hasPrefix("I have not agreed") }, source)
            let owner = result.items.first { $0.organization.itemType == .note
                && $0.sourceQuote.contains("Asha said") }
            XCTAssertTrue(owner?.sourceQuote.contains(denial) ?? false, source)
            XCTAssertFalse(owner?.needsReview ?? true)
            XCTAssertNil(owner?.organization.reminderDate)
        }
        for source in ["I agreed to email Nora", "I have agreed to email Nora",
                       "We have committed to bring the projector"] {
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
        }
        let denied = "I have not agreed to send that message."
        for source in [
            "Asha said, 'Tell everyone to bring a mug.' Mina said, 'Bring a plate.' " + denied,
            "Asha said, 'Tell everyone to bring a mug.' I will email Nora the receipt. " + denied
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertFalse(result.items.contains { $0.sourceQuote.contains("Asha said") && $0.sourceQuote.contains(denied) }, source)
            XCTAssertTrue(result.items.contains { $0.needsReview && $0.sourceQuote.contains(denied) }, source)
        }
        let independent = ThoughtExtractionEngine.extractWithRules("I have not agreed to email Nora, but I will buy batteries.")
        XCTAssertTrue(independent.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("buy batteries") })
        XCTAssertFalse(independent.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.hasPrefix("I have not agreed") })
    }

    func testDeniedAgreementIndependentTaskDifferential() {
        let statement = "It does not mean I agreed to lock anything, and I will buy batteries."
        let repaired = SpeechRepairPipeline.run(statement).corrected
        XCTAssertTrue(repaired.contains("I will buy batteries"), repaired)
        let clauses = RuleBasedThoughtExtractor.splitClauses(repaired)
        XCTAssertTrue(clauses.contains { $0.contains("buy batteries") && !$0.contains("agreed") }, clauses.joined(separator: " | "))
        let own = ThoughtExtractionEngine.extractWithRules("I will buy batteries.").items
        XCTAssertTrue(own.first?.organization.itemType.isActionable == true)
        XCTAssertFalse(own.first?.needsReview == true)
    }

    func testDeniedAgreementImplicationRequiresAdjacentUniqueQuotedOwner() {
        let report = "The letter from Dana says, 'I agree: lock the gate.'"
        let denied = "It does not mean I agreed to lock anything."
        let items = ThoughtExtractionEngine.extractWithRules(report + " " + denied + " Buy batteries.").items
        XCTAssertEqual(items.count, 2, items.map(\.analysisText).joined(separator: " | "))
        XCTAssertTrue(items.first?.sourceQuote.contains(denied) == true)
        XCTAssertTrue(items.allSatisfy { !$0.needsReview })
        for source in [
            denied,
            report + " I will lock the shed. " + denied,
            report + " The message from Noor says, 'I agree: lock the shed.' " + denied
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertTrue(result.contains { $0.needsReview }, source + " => " + result.map(\.analysisText).joined(separator: " | "))
        }
        let coordinated = ThoughtExtractionEngine.extractWithRules(
            report + " It does not mean I agreed to lock anything, and I will buy batteries."
        ).items
        XCTAssertTrue(coordinated.contains { $0.organization.itemType.isActionable && $0.analysisText.contains("batteries") }, coordinated.map(\.analysisText).joined(separator: " | "))
        let independent = ThoughtExtractionEngine.extractWithRules(report + " " + denied + " The door code is 3812.").items
        XCTAssertTrue(independent.contains { $0.analysisText.contains("3812") && !$0.analysisText.contains("Dana") }, independent.map(\.analysisText).joined(separator: " | "))
    }

    func testReportedAgreementAccountDifferential() {
        let account = "The note from Casey says, 'I agree: bring the spare projector.' That agreement belongs to Casey inside the message. It does not mean I agreed to bring anything."
        let represented = ThoughtExtractionEngine.extractWithRules(account).items
        XCTAssertEqual(represented.count, 1, represented.map(\.analysisText).joined(separator: " | "))
        XCTAssertEqual(represented.first?.organization.itemType, .note)
        XCTAssertFalse(represented.first?.needsReview == true)
        XCTAssertTrue(represented.first?.sourceQuote.contains("It does not mean I agreed") == true)
        let separated = RuleBasedThoughtExtractor.splitClauses(
            account + " I will take the extension lead myself."
        )
        XCTAssertTrue(separated.contains { $0.hasPrefix("It does not mean I agreed") }, separated.joined(separator: " | "))
        XCTAssertTrue(separated.contains { $0.contains("I will take the extension lead") }, separated.joined(separator: " | "))
    }

    func testReferenceMessagePointersRequireSupportedSpeakerObjectAndUniqueOwner() {
        let report = "The email from Noor says, 'Bring the handout.'"
        let retain = "Save the message as a reference note with Noor as the speaker."
        let own = "I will take the torch myself."
        let source = report + " " + retain + " " + own
            + " Keep the handout with Noor's message and the torch with my task."
        let items = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(items.count, 2, items.map(\.analysisText).joined(separator: " | "))
        XCTAssertTrue(items.allSatisfy { !$0.needsReview })
        XCTAssertTrue(items.contains { $0.organization.itemType == .note && $0.sourceQuote.contains(retain) })
        for text in [
            retain,
            report + " Save the message as a reference note with Mara as the speaker.",
            report + " Keep the ladder with Noor's message.",
            own + " I will repair the torch. The torch with my task.",
            "Noor said, 'Bring the handout.' Noor said, 'Bring the invoice.' " + retain
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(text).items
            XCTAssertTrue(result.contains { $0.needsReview }, text + " => " + result.map(\.analysisText).joined(separator: " | "))
        }
        let physical = ThoughtExtractionEngine.extractWithRules("Keep the torch with the spare batteries.").items
        XCTAssertTrue(physical.first?.organization.itemType.isActionable == true)
        let later = ThoughtExtractionEngine.extractWithRules(source + " Buy batteries. The door code is 3812.").items
        XCTAssertTrue(later.contains { $0.organization.itemType.isActionable && $0.analysisText.contains("batteries") })
        XCTAssertTrue(later.contains { $0.analysisText.contains("3812") && !$0.analysisText.contains("Noor") })
    }

    func testQuotedAgreementKeepsOneAttributedAccountAndOneOwnCommitment() {
        let source = "The note from Casey says, 'I agree: bring the spare projector.' That agreement belongs to Casey inside the message. It does not mean I agreed to bring anything. Save the message as a reference note with Casey as the speaker, including the projector detail.\n\nI will take the extension lead myself, though. That is a separate commitment from me, and it should become a task. I have not specified a day or reminder time. Keep the projector with Casey's message and the extension lead with my task rather than copying the apparent agreement across the boundary."
        let result = ThoughtExtractionEngine.extractWithRules(source)
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertEqual(result.items.count, 2, result.items.map { "\($0.organization.itemType.rawValue): \($0.analysisText) review=\($0.needsReview)" }.joined(separator: " | "))
        XCTAssertTrue(result.items.allSatisfy { !$0.needsReview })
        let tasks = result.items.filter { $0.organization.itemType.isActionable }
        XCTAssertEqual(tasks.count, 1)
        XCTAssertTrue(tasks.first?.analysisText.contains("extension lead") == true)
        XCTAssertNil(tasks.first?.organization.dueDate)
        XCTAssertTrue(result.items.contains {
            $0.organization.itemType == .note && $0.sourceQuote.contains("Casey")
                && $0.sourceQuote.contains("spare projector")
        })
    }

    func testAnaphoricCommitmentDeclarationDoesNotInventAnotherTask() {
        let previousTaggerMode = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previousTaggerMode
            SentenceContextCache.invalidate()
        }
        // Exercise the system's actual tags and the explicit missing-assets
        // path without allowing a cached reading to stand in for either.
        for disablesTagger in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disablesTagger
            SentenceContextCache.invalidate()
            let metadata = "That is a separate commitment from me, and it should become a task."
            XCTAssertEqual(ActionabilityReader.read(metadata), .knowledge)
            XCTAssertEqual(RuleBasedThoughtExtractor.splitIndependentConjuncts(metadata), [metadata],
                "A complete anaphoric declaration cannot manufacture an independent task at its coordinator")
            let task = "I will take the extension lead myself."
            let items = ThoughtExtractionEngine.extractWithRules(
                task + " " + metadata + " I have not specified a day or reminder time."
            ).items
            XCTAssertEqual(items.count, 1, items.map(\.analysisText).joined(separator: " | "))
            XCTAssertTrue(items.first?.organization.itemType.isActionable == true)
            XCTAssertFalse(items.first?.needsReview == true)
            XCTAssertNil(items.first?.organization.dueDate)
            XCTAssertTrue(items.first?.sourceQuote.contains(metadata) == true)
            for source in [
                metadata,
                "Mara said to take the torch. " + metadata,
                task + " I will return the keys. " + metadata
            ] {
                XCTAssertTrue(ThoughtExtractionEngine.extractWithRules(source).items.contains { $0.needsReview }, source)
            }
            let independent = ThoughtExtractionEngine.extractWithRules(
                task + " " + metadata + " Buy batteries. The door code is 3812."
            ).items
            XCTAssertTrue(independent.contains { $0.organization.itemType.isActionable && $0.analysisText.contains("batteries") })
            XCTAssertTrue(independent.contains { $0.analysisText.contains("3812") && !$0.analysisText.contains("extension lead") })
            XCTAssertFalse(ActionabilityReader.isAnaphoricTaskDeclaration(
                "That is a separate commitment from me: I will bring a ladder."
            ))
            let independentCommitment = "That is a separate commitment from me, and I will print the form."
            XCTAssertFalse(ActionabilityReader.isAnaphoricTaskDeclaration(independentCommitment))
            XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses(independentCommitment),
                ["That is a separate commitment from me", "I will print the form"],
                "An explicit independent commitment must still split from the preceding declaration")
        }
    }

    func testDocumentReportedAgreementDoesNotAdoptItsQuotedSpeaker() {
        for source in [
            "The note from Casey says, 'I agree: bring the spare projector.'",
            "That email from Noor says, 'I agree: send the handout.'",
            "The message from the caretaker says, 'I agree: lock the gate.'"
        ] {
            XCTAssertEqual(ClauseScope.read(source).act, .reporting, source)
            XCTAssertEqual(QuotedSpeechScope.matrixVoice(in: source), .reported, source)
            XCTAssertNil(ClauseScope.explicitAdoption(in: source), source)
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, source)
            XCTAssertEqual(items.first?.organization.itemType, .note, source)
            XCTAssertFalse(items.first?.needsReview == true, source)
        }
        let source = "The note from Casey says, 'I agree: bring the spare projector.' I will take the extension lead myself."
        let mixed = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(mixed.count, 2, mixed.map(\.analysisText).joined(separator: " | "))
        XCTAssertEqual(mixed.filter { $0.organization.itemType.isActionable }.count, 1)
        XCTAssertTrue(mixed.contains { $0.organization.itemType.isActionable && $0.analysisText.contains("extension lead") })
        let direct = ThoughtExtractionEngine.extractWithRules("Email the note from Casey to the caretaker.").items
        XCTAssertTrue(direct.first?.organization.itemType.isActionable == true)
        XCTAssertNotEqual(ClauseScope.read("I will send the message from the caretaker.").act, .reporting)
    }

    func testDeniedCitationBoundaryDifferential() {
        let note = "Remember this conversation. Mara said, 'Send everyone the minutes.'"
        let denial = "The quoted send everyone instruction should not become my task."
        let source = note + " " + denial + " The door code is 3812."
        let clauses = RuleBasedThoughtExtractor.splitClauses(source)
        XCTAssertTrue(clauses.contains { $0.contains("3812") && !$0.contains("Mara") }, clauses.joined(separator: " | "))
        XCTAssertTrue(clauses.contains { ClauseScope.isDeniedCitedAction($0) }, clauses.joined(separator: " | "))
        let fact = ThoughtExtractionEngine.extractWithRules("The door code is 3812.").items
        XCTAssertEqual(fact.count, 1)
        XCTAssertFalse(fact.first?.needsReview == true)
        XCTAssertEqual(fact.first?.organization.itemType, .note)
        let report = ThoughtExtractionEngine.extractWithRules(note).items
        XCTAssertEqual(report.count, 1)
        XCTAssertFalse(report.first?.needsReview == true)
    }

    func testDeniedCitationOwnershipDoesNotAbsorbIndependentSpeechOrChooseBetweenReports() {
        let note = "Remember this conversation. Mara said, 'Send everyone the minutes.'"
        let denial = "The quoted send everyone instruction should not become my task."
        let own = ThoughtExtractionEngine.extractWithRules(note + " " + denial + " Buy batteries.").items
        XCTAssertEqual(own.count, 2, own.map(\.analysisText).joined(separator: " | "))
        XCTAssertTrue(own.contains { $0.organization.itemType == .note && $0.sourceQuote.contains(denial) })
        XCTAssertTrue(own.contains { $0.organization.itemType.isActionable && $0.analysisText.contains("batteries") })
        let fact = ThoughtExtractionEngine.extractWithRules(note + " " + denial + " The door code is 3812.").items
        XCTAssertTrue(fact.contains { $0.analysisText.contains("3812") && !$0.analysisText.contains("Mara") }, fact.map(\.analysisText).joined(separator: " | "))
        let unresolved = ThoughtExtractionEngine.extractWithRules(
            "Mara said, 'Send everyone the minutes.' Tomas said, 'Send everyone the invoice.' " + denial
        ).items
        XCTAssertTrue(unresolved.contains { $0.needsReview }, unresolved.map(\.analysisText).joined(separator: " | "))
        XCTAssertFalse(unresolved.contains { $0.organization.itemType.isActionable })
        XCTAssertTrue(ThoughtExtractionEngine.extractWithRules(denial).items.contains { $0.needsReview })
    }

    func testDeniedQuotedActionIsMentionedWhileDirectAndAdoptedActionsStayActive() {
        let denied = "The quoted send everyone instruction should not become a task of mine."
        XCTAssertEqual(ActionabilityReader.read(denied), .knowledge)
        XCTAssertEqual(ClauseJuxtaposition.pieces(in: denied), [denied])
        let mentioned = ThoughtExtractionEngine.extractWithRules(denied).items
        XCTAssertFalse(mentioned.contains { $0.organization.itemType.isActionable })
        XCTAssertTrue(mentioned.first?.sourceQuote.contains("quoted send everyone instruction") == true)
        let clause = "There is no permission to delete the old draft, and the quoted send everyone instruction should not become my task."
        XCTAssertFalse(RuleBasedThoughtExtractor.splitClauses(clause).contains {
            $0.lowercased().hasPrefix("send everyone")
        })
        let direct = ThoughtExtractionEngine.extractWithRules("Send everyone the final draft tomorrow.").items
        XCTAssertTrue(direct.first?.organization.itemType.isActionable == true)
        let adopted = ThoughtExtractionEngine.extractWithRules(
            "Vera said to send everyone the final draft. I agree: I will send everyone the final draft tomorrow."
        ).items
        XCTAssertEqual(adopted.count, 1)
        XCTAssertTrue(adopted.first?.organization.itemType.isActionable == true)
        XCTAssertFalse(ClauseScope.isDeniedCitedAction(
            "The quoted send everyone instruction is my own task tomorrow."
        ))
        let independent = ThoughtExtractionEngine.extractWithRules(
            denied + " I will buy batteries."
        ).items
        XCTAssertTrue(independent.contains {
            $0.organization.itemType.isActionable && $0.analysisText.contains("batteries")
        })
    }

    func testLowercaseDeclaredReportBoundaryDifferential() {
        let source = "Keep a note about what happened in the workshop. The instructor told the new volunteers, 'Call the coordinator tomorrow and bring the blue folder.' That was an instruction to the volunteers, not to me. I was only taking notes, and I am repeating the wording because it explains what they were expected to do.\n\nMy own task is to email the instructor a photo of the damaged sign. The sign near the side door is the one I mean. I have not said when to send that email. Do not turn tomorrow from the quoted instruction into a deadline for my message, and do not create a folder task for me."
        for (name, text) in [("canonical", source), ("lowercase", source.lowercased()),
                             ("report boundary only", source.lowercased().replacingOccurrences(
                                of: ". the instructor", with: ". The instructor"))] {
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = text
            var sentences: [String] = []
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                sentences.append(String(text[range]))
                return true
            }
            let items = ThoughtExtractionEngine.extractWithRules(text).items
            let trace = XCTAttachment(string: name + "\nTokenizer:\n" + sentences.joined(separator: "\n---\n")
                + "\nProtected ranges:\n" + RuleBasedThoughtExtractor.quotePreservingSentenceRanges(in: text)
                    .map { String(text[$0]) }.joined(separator: "\n---\n")
                + "\nShipping outputs:\n" + items.map {
                    "\($0.organization.itemType): \($0.analysisText) [review=\($0.needsReview)]"
                }.joined(separator: "\n"))
            trace.name = "Reported note boundary " + name
            trace.lifetime = .keepAlways
            add(trace)
            XCTAssertEqual(items.count, 2, name)
            XCTAssertFalse(items.contains(where: \.needsReview), name)
        }
    }

    func testUnpunctuatedDeclaredReportKeepsOwnTaskAndOwnerDetails() throws {
        let source = "keep a note about what happened in the workshop the instructor told the new volunteers 'call the coordinator tomorrow and bring the blue folder ' that was an instruction to the volunteers not to me i was only taking notes and i am repeating the wording because it explains what they were expected to do\n\nmy own task is to email the instructor a photo of the damaged sign the sign near the side door is the one i mean i have not said when to send that email do not turn tomorrow from the quoted instruction into a deadline for my message and do not create a folder task for me"
        let items = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(items.count, 2)
        XCTAssertFalse(items.contains(where: \.needsReview))
        let note = try XCTUnwrap(items.first { $0.organization.itemType == .note })
        let task = try XCTUnwrap(items.first { $0.organization.itemType.isActionable })
        XCTAssertTrue(note.sourceQuote.contains("instruction to the volunteers"))
        XCTAssertTrue(note.sourceQuote.contains("do not create a folder task"))
        XCTAssertFalse(note.sourceQuote.contains("email the instructor"))
        XCTAssertTrue(task.sourceQuote.contains("the sign near the side door"))
        XCTAssertTrue(task.sourceQuote.contains("i have not said when"))
        XCTAssertTrue(task.sourceQuote.contains("deadline for my message"))
        XCTAssertNil(task.organization.dueDate)
        XCTAssertNil(task.organization.reminderDate)
    }

    func testQuotedRetentionAndOwnDeclarationProtectOppositeVoices() {
        let own = ThoughtExtractionEngine.extractWithRules(
            "keep a note about the rehearsal the director said 'bring scarves tomorrow' i was taking notes my own task is to email the stage manager a photo"
        ).items
        XCTAssertEqual(own.count, 2)
        XCTAssertEqual(own.filter { $0.organization.itemType == .note }.count, 1)
        XCTAssertEqual(own.filter { $0.organization.itemType.isActionable }.count, 1)
        XCTAssertFalse(own.contains(where: \.needsReview))
        for source in [
            "keep a note about the rehearsal the director said 'my own task is to email the stage manager' i was taking notes",
            "keep a note about the rehearsal the director said 'bring scarves' she said that my own task is to email the stage manager",
            "keep a note about the rehearsal the director said 'bring scarves' Casey said that my own task is to email the stage manager"
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, source)
            XCTAssertEqual(items.first?.organization.itemType, .note, source)
            XCTAssertFalse(items.first?.needsReview ?? true, source)
        }
        let message = ThoughtExtractionEngine.extractWithRules(
            "Text Dora to say 'my own task is to email the stage manager'"
        ).items
        XCTAssertEqual(message.count, 1)
        XCTAssertTrue(message.first?.organization.itemType.isActionable == true)
        let adoption = ThoughtExtractionEngine.extractWithRules(
            "The director said, 'Bring scarves.' I agree: bring scarves tomorrow."
        ).items
        XCTAssertEqual(adoption.count, 1)
        XCTAssertTrue(adoption.first?.organization.itemType.isActionable == true)
    }

    func testUnpunctuatedRetainedConversationKeepsEmphaticOwnQuestion() throws {
        let source = "remember this conversation with jo jo said 'delete the old draft and send everyone the final one ' i am recording what jo said not asking this app to delete anything or send any files keep the attribution because otherwise it will look like a direct instruction from me i do need to ask jo which version is final before i decide what to do make that question a task for tomorrow there is no permission to delete the old draft in the meantime and the quoted send everyone instruction should not become a second task of mine"
        let items = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(items.count, 2)
        XCTAssertFalse(items.contains(where: \.needsReview))
        let task = try XCTUnwrap(items.first { $0.organization.itemType.isActionable })
        let note = try XCTUnwrap(items.first { $0.organization.itemType == .note })
        XCTAssertTrue(task.sourceQuote.contains("ask jo which version is final"))
        XCTAssertFalse(note.sourceQuote.contains("i do need to ask"))
        XCTAssertTrue(note.sourceQuote.contains("delete the old draft"))
        XCTAssertTrue(note.organization.personName == nil || note.organization.personName == "Jo",
                      "Quoted output prohibition must not invent a person from any files.")
        XCTAssertEqual(task.organization.temporalIntent.kind, .dateOnly)
        XCTAssertNil(task.organization.reminderDate)
        for quoted in [
            "remember this conversation the chair said 'i do need to ask jo tomorrow' i was taking notes",
            "remember this conversation the chair said 'delete the draft' Casey said that i do need to ask jo tomorrow"
        ] {
            let outputs = ThoughtExtractionEngine.extractWithRules(quoted).items
            XCTAssertEqual(outputs.count, 1)
            XCTAssertEqual(outputs.first?.organization.itemType, .note)
        }
    }

    func testUnpunctuatedPivotStageDifferential() {
        for text in [
            "keep a note about the rehearsal the director said 'bring scarves tomorrow' i was taking notes my own task is to email the stage manager a photo",
            "The director said, 'Bring scarves.' I agree: bring scarves tomorrow."
        ] {
            let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let repair = SpeechRepairPipeline.run(normalized, trackOrigins: true)
            let pivot = QuotedSpeechScope.directActionAfterQuote(repair.corrected)
            let items = ThoughtExtractionEngine.extractWithRules(text).items
            let trace = XCTAttachment(string: "Repair stages:\n" + repair.stages.map {
                "\($0.kind): \($0.output)"
            }.joined(separator: "\n") + "\nVoice: \(String(describing: QuotedSpeechScope.matrixVoice(in: repair.corrected)))"
                + "\nPivot: \(String(describing: pivot))\nOutputs:\n"
                + items.map { "\($0.organization.itemType): \($0.analysisText) | \($0.sourceQuote)" }.joined(separator: "\n"))
            trace.name = "Unpunctuated pivot stage differential"
            trace.lifetime = .keepAlways
            add(trace)
        }
        let independent = ThoughtExtractionEngine.extractWithRules(
            "My own task is to email the stage manager a photo."
        ).items
        XCTAssertEqual(independent.count, 1)
        XCTAssertTrue(independent.first?.organization.itemType.isActionable == true)
        XCTAssertNil(independent.first?.organization.dueDate)
    }

    func testWrittenReportBoundaryKeepsIndependentCommitmentAndFact() {
        for source in [
            "keep a note about the rehearsal. the director told the cast, 'bring the scarves tomorrow.' i was taking notes. i will email the stage manager a photo.",
            "keep a note about the meeting. the chair said, 'print the agenda tomorrow.' i was taking notes. remember that the spare key is in the drawer."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 2, items.map(\.analysisText).joined(separator: " | "))
            XCTAssertFalse(items.contains(where: \.needsReview), source)
            XCTAssertTrue(items.contains { $0.sourceQuote.contains("taking notes") && $0.organization.itemType == .note })
            if source.contains("email") {
                XCTAssertTrue(items.contains { $0.analysisText.contains("email the stage manager") && $0.organization.itemType.isActionable })
            } else {
                XCTAssertTrue(items.allSatisfy { $0.organization.itemType == .note })
                XCTAssertTrue(items.contains { $0.analysisText.contains("spare key") && !$0.sourceQuote.contains("chair said") })
            }
        }
        let quoted = "keep a note about the rehearsal. the actor read, 'my own task is to email the stage manager. i will bring the scarves tomorrow.' i was taking notes."
        let items = ThoughtExtractionEngine.extractWithRules(quoted).items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.organization.itemType, .note)
        XCTAssertFalse(items.first?.needsReview ?? true)
    }

    func testReportedNoteAndOwnTaskKeepTheirOutputConstraints() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10))!
        let source = "Keep a note about what happened in the workshop. The instructor told the new volunteers, 'Call the coordinator tomorrow and bring the blue folder.' That was an instruction to the volunteers, not to me. I was only taking notes, and I am repeating the wording because it explains what they were expected to do.\n\nMy own task is to email the instructor a photo of the damaged sign. The sign near the side door is the one I mean. I have not said when to send that email. Do not turn tomorrow from the quoted instruction into a deadline for my message, and do not create a folder task for me."
        let items = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(items.count, 2, items.map(\.analysisText).joined(separator: " | "))
        XCTAssertTrue(items.allSatisfy { !$0.needsReview })
        let note = items.first { $0.organization.itemType == .note }
        let task = items.first { $0.organization.itemType.isActionable }
        XCTAssertTrue(note?.sourceQuote.contains("volunteers") == true)
        XCTAssertTrue(note?.sourceQuote.contains("folder task") == true)
        XCTAssertTrue(task?.sourceQuote.contains("near the side door") == true)
        XCTAssertTrue(task?.sourceQuote.contains("deadline for my message") == true)
        XCTAssertNil(task?.organization.dueDate)
        XCTAssertNil(task?.organization.reminderDate)
        let protected = ThoughtExtractionEngine.extractWithRules("Text Sam to say that the train leaves at seven tomorrow evening. The seven o'clock time is what I need to tell Sam; it is not when I want a reminder to send the text. I have not chosen a time to text him, so please do not wait until the train is leaving.\n\nSeparately, remind me at eleven this morning to print the ticket. Use the booking confirmation attachment, not a screenshot of the journey search. The text and printing task are both about travel, but the printing reminder should not get copied onto the text or onto a new train event.", referenceDate: reference, calendar: calendar).items
        XCTAssertEqual(protected.count, 2, protected.map(\.analysisText).joined(separator: " | "))
        XCTAssertTrue(protected.allSatisfy { !$0.needsReview && $0.organization.itemType.isActionable })
        let noOwner = ThoughtExtractionEngine.extractWithRules("Do not create a folder task for me.").items
        XCTAssertTrue(noOwner.contains { $0.needsReview })
        let twoMessages = ThoughtExtractionEngine.extractWithRules(
            "Email Vera the timetable. Text Omar the address. Do not turn tomorrow from the quoted instruction into a deadline for my message."
        ).items
        XCTAssertEqual(twoMessages.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertTrue(twoMessages.contains { $0.needsReview })
    }

    func testMessageTimingContextConsumesAnAlreadyOwnedNoTimeStatement() {
        let message = "Text Sam to say the train leaves at ten on Friday."
        let noTime = "I have not picked a time to send that text."
        let recognized = "That is the message, not when I want to send the text."
        // Existing typed message-timing reference, first directly adjacent,
        // then following an already owned no-time context occurrence.
        for source in [message + " " + recognized,
                       message + " " + noTime + " " + recognized] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, source)
            XCTAssertTrue(items.first?.sourceQuote.contains(recognized) ?? false, source)
            XCTAssertFalse(items.first?.needsReview ?? true, source)
            XCTAssertNil(items.first?.organization.reminderDate)
        }
        for source in [
            message + " The shed key has a blue tag. " + recognized,
            message + " Text June the address. " + noTime + " " + recognized
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertFalse(items.contains { $0.analysisText.localizedCaseInsensitiveContains("text Sam")
                && $0.sourceQuote.contains(recognized) }, source)
            XCTAssertTrue(items.contains { $0.needsReview && $0.sourceQuote.contains(recognized) }, source)
        }
        let independent = ThoughtExtractionEngine.extractWithRules(message + " " + noTime
            + " Ten is the departure time inside the message. Also buy envelopes.")
        XCTAssertTrue(independent.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("buy envelopes") })
        let original = ThoughtExtractionEngine.extractWithRules(Self.trainIdeaLongCapture, permitsOperations: false)
        let owner = original.items.first { $0.analysisText.localizedCaseInsensitiveContains("Text Sam") }
        XCTAssertTrue(owner?.sourceQuote.contains("Ten is the departure time inside the message.") ?? false)
        XCTAssertFalse(original.items.contains { $0.analysisText.hasPrefix("Ten is the departure time") })
    }

    func testNamedUnchosenTimeKeepsItsExistingCommunicationOwner() {
        let status = "I have not picked a time to send that text."
        XCTAssertTrue(ActionabilityReader.isUnchosenActionTime(status))
        XCTAssertEqual(ActionabilityReader.read(status), .knowledge)
        for source in ["I have not picked the photographs", "I still need to select the invitation",
                       "I still need to pick a time to send that text"] {
            XCTAssertFalse(ActionabilityReader.isUnchosenActionTime(source))
            XCTAssertTrue(ActionabilityReader.read(source).belongsOnToday, source)
        }
        // Unresolved selection is not an explicit obligation to decide.
        XCTAssertFalse(ActionabilityReader.isUnchosenActionTime("I have not selected the invitation"))
        XCTAssertEqual(ActionabilityReader.read("I have not selected the invitation"), .knowledge)
        let independent = "I have not picked a time, but I will email Nora tomorrow."
        XCTAssertFalse(ActionabilityReader.isUnchosenActionTime(independent))
        XCTAssertTrue(ThoughtExtractionEngine.extractWithRules(independent).items.contains {
            $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("email Nora")
        })
        let short = "Text Sam to say the train leaves at ten on Friday. " + status + " Also pack the short charging cable."
        for source in [short, Self.trainIdeaLongCapture] {
            let result = ThoughtExtractionEngine.extractWithRules(source, permitsOperations: false)
            let messages = result.items.filter { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("text Sam") }
            XCTAssertEqual(messages.count, 1, source)
            XCTAssertTrue(messages.first?.sourceQuote.contains(status) ?? false)
            XCTAssertNil(messages.first?.organization.reminderDate)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.hasPrefix("I have not picked a time") })
        }
        // Diagnostic substitution only: the established grammar should let
        // the unchanged downstream owner path succeed with the same meaning.
        let recognized = ThoughtExtractionEngine.extractWithRules(short.replacingOccurrences(of: "picked", with: "chosen"))
        XCTAssertEqual(recognized.items.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertTrue(recognized.items.contains { $0.analysisText.localizedCaseInsensitiveContains("text Sam")
            && $0.sourceQuote.contains("not chosen a time") })
        let competing = ThoughtExtractionEngine.extractWithRules("Text Sam the platform number. Text June the address. " + status)
        XCTAssertEqual(competing.items.filter { $0.organization.itemType.isActionable
            && !$0.analysisText.hasPrefix("I have not picked") }.count, 2)
        XCTAssertFalse(competing.items.contains { $0.analysisText.localizedCaseInsensitiveContains("text Sam")
            && $0.sourceQuote.contains(status) })
        XCTAssertTrue(competing.items.contains { $0.needsReview && $0.sourceQuote.contains(status) })
    }

    func testTaskReferentAndUnchosenTimeAreOwnedDetailsNotNewIntentions() {
        let source = "Email the caretaker a photo of the damaged panel. The panel beside the stairs is the one I mean. I have not said when to send that email."
        XCTAssertEqual(ActionabilityReader.read("I have not said when to send that email."), .knowledge)
        let independent = "I have not chosen a time, but I will email the caretaker tomorrow."
        XCTAssertFalse(ActionabilityReader.isUnchosenActionTime(independent))
        XCTAssertTrue(ThoughtExtractionEngine.extractWithRules(independent).items.contains {
            $0.organization.itemType.isActionable && $0.analysisText.contains("email the caretaker")
        })
        let items = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(items.count, 1, items.map(\.analysisText).joined(separator: " | "))
        XCTAssertTrue(items.first?.organization.itemType.isActionable == true)
        XCTAssertFalse(items.first?.needsReview == true)
        XCTAssertNil(items.first?.organization.dueDate)
        XCTAssertTrue(items.first?.sourceQuote.contains("beside the stairs") == true)
        XCTAssertTrue(items.first?.sourceQuote.contains("not said when") == true)
        let fact = ThoughtExtractionEngine.extractWithRules(
            "Email the caretaker a photo of the damaged panel. The cabinet has a green door."
        ).items
        XCTAssertEqual(fact.count, 2)
        let competing = ThoughtExtractionEngine.extractWithRules(
            "Email the caretaker a photo of the panel. Ask the builder to replace the panel. The panel beside the stairs is the one I mean."
        ).items
        XCTAssertEqual(competing.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertTrue(competing.contains { $0.needsReview && $0.sourceQuote.contains("beside the stairs") })
    }

    func testDeclaredReportNoteStopsBeforeIndependentCommitmentOrFact() {
        let report = "Keep a note about the safety briefing. The steward said, 'Bring a whistle tomorrow.' That was an instruction to the helpers, not to me. I was only taking notes."
        let ownTask = ThoughtExtractionEngine.extractWithRules(report + " I will email the steward a question.").items
        XCTAssertEqual(ownTask.count, 2, ownTask.map(\.analysisText).joined(separator: " | "))
        XCTAssertEqual(ownTask.first?.organization.itemType, .note)
        XCTAssertFalse(ownTask.first?.needsReview == true)
        XCTAssertTrue(ownTask.first?.sourceQuote.contains("helpers, not to me") == true)
        XCTAssertTrue(ownTask.last?.organization.itemType.isActionable == true)
        XCTAssertNil(ownTask.last?.organization.dueDate)
        let fact = ThoughtExtractionEngine.extractWithRules(report + " The cabinet has a green door.").items
        XCTAssertEqual(fact.count, 2)
        XCTAssertTrue(fact.last?.analysisText.contains("green door") == true)
        XCTAssertFalse(fact.first?.analysisText.contains("green door") == true)
        let adoption = ThoughtExtractionEngine.extractWithRules(report + " I agree: I will bring a whistle.").items
        XCTAssertTrue(adoption.contains { $0.organization.itemType.isActionable })
        let sameSentence = ThoughtExtractionEngine.extractWithRules(
            "Keep a note about the briefing. The steward said to bring a whistle. I am recording what the steward said, and I will buy batteries."
        ).items
        XCTAssertTrue(sameSentence.contains {
            $0.organization.itemType.isActionable && $0.analysisText.contains("batteries")
        })
        let separate = ThoughtExtractionEngine.extractWithRules(
            "Remember this conversation with Vera. Vera said to check the invoice. I am recording what Vera said, not asking the app to check it. Keep the attribution because it identifies the speaker. I need to ask Vera a question."
        ).items
        XCTAssertEqual(separate.count, 2, separate.map(\.analysisText).joined(separator: " | "))
        XCTAssertEqual(separate.first?.organization.itemType, .note)
        XCTAssertFalse(separate.first?.needsReview == true)
        XCTAssertTrue(separate.last?.organization.itemType.isActionable == true)
    }

    func testExplicitAdoptionKeepsItsActorObjectAndLaterIndependentSpeech() {
        let source = "The instructor said to bring the blue folder. I agree and will bring it myself tomorrow."
        XCTAssertNotNil(ClauseScope.explicitAdoption(in: source))
        if let intermediate = ClauseScope.explicitAdoption(in: source) {
            let isolated = ThoughtExtractionEngine.extractWithRules(intermediate.action).items
            XCTAssertEqual(isolated.count, 1)
            XCTAssertTrue(isolated.first?.organization.itemType.isActionable == true,
                          "Differential: the adoption action must be representable downstream.")
            XCTAssertFalse(isolated.first?.needsReview == true)
            XCTAssertEqual(ClauseScope.explicitAdoption(in: SpeechRepairPipeline.run(source).corrected)?.action,
                           intermediate.action, "Differential: repair must retain the adoption frame.")
        }
        let adopted = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(adopted.count, 1, adopted.map(\.analysisText).joined(separator: " | "))
        XCTAssertTrue(adopted.first?.organization.itemType.isActionable == true,
                      adopted.map { "\($0.organization.itemType.rawValue):\($0.analysisText)" }.joined(separator: " | "))
        XCTAssertTrue(adopted.first?.analysisText.contains("blue folder") == true)
        XCTAssertTrue(adopted.first?.rawQuote.contains("instructor said") == true)
        XCTAssertFalse(adopted.first?.needsReview == true)

        let suggestion = ThoughtExtractionEngine.extractWithRules(
            "Casey suggested bringing the spare projector. I agree: I will bring the spare projector."
        ).items
        XCTAssertEqual(suggestion.count, 1)
        XCTAssertTrue(suggestion.first?.organization.itemType.isActionable == true)

        let quotedSource = "The guide said, 'Wear waterproof boots tomorrow.' I agree: I will wear waterproof boots. Also buy a map."
        XCTAssertNotNil(ClauseScope.explicitAdoption(in: quotedSource),
                        "Quoted differential: explicit commitment must be found outside the quotation.")
        let quoted = ThoughtExtractionEngine.extractWithRules(quotedSource).items
        XCTAssertEqual(quoted.count, 2, quoted.map(\.analysisText).joined(separator: " | "))
        XCTAssertTrue(quoted.allSatisfy { $0.organization.itemType.isActionable })
        XCTAssertTrue(quoted.first?.analysisText.contains("waterproof boots") == true)
        XCTAssertNil(quoted.first?.organization.dueDate, "The report's tomorrow does not date the user's commitment.")
        XCTAssertTrue(quoted.last?.analysisText.localizedCaseInsensitiveContains("buy a map") == true)

        let fact = ThoughtExtractionEngine.extractWithRules(
            "The guide said, 'Wear waterproof boots.' I agree: I will wear waterproof boots. The room has a blue door."
        ).items
        XCTAssertEqual(fact.count, 2)
        XCTAssertTrue(fact.last?.organization.itemType == .note)
        XCTAssertTrue(fact.last?.analysisText.contains("blue door") == true)

        for report in [
            "Mara said, 'I agree: I will bring the notebook.'",
            "The organiser said the event was delayed. I agree: it sounds sensible.",
            "The organiser said the event was delayed. I agree: I will be unavailable.",
            "The teacher said to bring a binder and a calculator. I agree and will bring it tomorrow.",
            "'Bring the notebook.' I agree and will bring it tomorrow."
        ] {
            XCTAssertNil(ClauseScope.explicitAdoption(in: report), report)
        }
        let attributedAgreement = ThoughtExtractionEngine.extractWithRules(
            "Mara said, 'I agree: I will bring the notebook.'"
        ).items
        XCTAssertTrue(attributedAgreement.allSatisfy { !$0.organization.itemType.isActionable })
    }

    func testBareExplicitAdoptionRequiresOwnCommandAndKeepsIndependentRemainder() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous
            SentenceContextCache.invalidate()
        }
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            for source in [
                "Pat said to photograph the resin flange. I agree: photograph the resin flange.",
                "Pat said, 'Photograph the resin flange tomorrow.' I agree: photograph it.",
                "Pat said to measure the cork disk. We commit: please measure the cork disk."
            ] {
                let proof = try XCTUnwrap(ClauseScope.explicitAdoption(in: source), source)
                XCTAssertEqual(proof.sourceQuote, source)
                XCTAssertTrue(proof.remainder.isEmpty)
                XCTAssertFalse(proof.action.lowercased().hasPrefix("i photograph"))
                let items = ThoughtExtractionEngine.extractWithRules(source).items
                XCTAssertEqual(items.count, 1, source)
                XCTAssertTrue(items.first?.organization.itemType.isActionable == true, source)
                XCTAssertFalse(items.first?.needsReview ?? true, source)
                XCTAssertEqual(items.first?.rawQuote, source)
                XCTAssertNil(items.first?.organization.dueDate, "A reported tomorrow cannot date the adopted command")
            }
            let source = "Pat said to photograph the resin flange. I agree: photograph the resin flange. Call Noor tomorrow. The cabinet has a blue door."
            let proof = try XCTUnwrap(ClauseScope.explicitAdoption(in: source))
            XCTAssertEqual(proof.remainder.trimmingCharacters(in: .whitespacesAndNewlines), "Call Noor tomorrow. The cabinet has a blue door.")
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(rows.count, 3)
            XCTAssertTrue(rows.contains { $0.organization.itemType.isActionable && $0.analysisText.contains("Call Noor") })
            XCTAssertTrue(rows.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("blue door") && !$0.sourceQuote.contains("photograph") })
            for opposed in [
                "Pat said to photograph the flange. I agree: the photograph is clear.",
                "Pat said to photograph the flange. I agree: I photograph it every week.",
                "Pat said to photograph the flange. I agree: if it is safe photograph the flange.",
                "Pat said to photograph the flange. I do not agree: photograph the flange.",
                "Pat said to photograph the flange. Nora agrees: photograph the flange.",
                "Pat said, 'Bring the flange. I agree: photograph the flange.'",
                "Pat said to photograph the flange and the disk. I agree: photograph it.",
                "'Photograph the flange.' I agree: photograph it.",
                "Pat said to photograph the flange. The cabinet is locked. I agree: photograph the flange."
            ] {
                XCTAssertNil(ClauseScope.explicitAdoption(in: opposed), opposed)
            }
        }
    }

    func testOneReferenceNoteOwnsItsInstructionStepsAndWarningButNotLaterErrand() {
        let source = "I want one reference note for the shelf assembly instructions. First lay out the side panels. Second attach the shelf. The booklet says not to overtighten the small screws. Keep that warning attached to the assembly note. The order matters inside the reference note."
        let result = ThoughtExtractionEngine.extractWithRules(source)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.organization.itemType, .note)
        XCTAssertTrue(result.items.first?.rawQuote.contains("overtighten") == true)
        XCTAssertTrue(result.items.first?.rawQuote.contains("order matters") == true)
        let hesitant = ThoughtExtractionEngine.extractWithRules(
            "Um, let me think. " + source.replacingOccurrences(
                of: "The booklet says", with: "Right, okay. The booklet says"
            )
        )
        XCTAssertEqual(hesitant.items.count, 1)
        XCTAssertEqual(hesitant.items.first?.organization.itemType, .note)
        let flat = source.replacingOccurrences(of: #"[.!?]"#, with: "",
                                                  options: .regularExpression)
        let unpunctuated = ThoughtExtractionEngine.extractWithRules(flat)
        XCTAssertEqual(unpunctuated.items.count, 1)
        XCTAssertEqual(unpunctuated.items.first?.organization.itemType, .note)
        let flatOpposite = ThoughtExtractionEngine.extractWithRules(
            flat + " also buy replacement screws"
        )
        XCTAssertTrue(flatOpposite.items.contains {
            $0.organization.itemType == .shopping
                && $0.analysisText.localizedCaseInsensitiveContains("replacement screws")
        })

        let opposite = ThoughtExtractionEngine.extractWithRules(
            source + " Also buy replacement screws."
        )
        XCTAssertTrue(opposite.items.contains {
            $0.organization.itemType == .shopping
                && $0.analysisText.localizedCaseInsensitiveContains("replacement screws")
        })
    }

    func testActionQuestionOwnsOnlyItsContiguousResolvedGroup() {
        let source = "What do I have to do? Wash the mugs tomorrow. "
            + "Put the passport in the drawer tonight. The lock code is 1234."
        let rows = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertTrue(rows[0].sourceQuote.contains("What do I have to do?"))
        XCTAssertFalse(rows[2].sourceQuote.contains("What do I have to do?"))
        XCTAssertTrue(rows[2].sourceQuote.contains("1234"))
        let owned = rows.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
        XCTAssertEqual(owned.count, SourceUnitLedger(source).words.count)

        let unowned = ThoughtExtractionEngine.extractWithRules(
            "What do I have to do?"
        ).items
        XCTAssertEqual(unowned.count, 1)
        XCTAssertTrue(unowned[0].needsReview)
        let reported = ThoughtExtractionEngine.extractWithRules(
            "Mara asked, 'What do I have to do?' Wash the mugs tomorrow."
        ).items
        XCTAssertTrue(reported.contains { $0.sourceQuote.contains("Mara asked") })
        let independent = ThoughtExtractionEngine.extractWithRules(
            "What did I do? Wash the mugs tomorrow."
        ).items
        XCTAssertTrue(independent.contains { $0.sourceQuote.contains("What did I do?") })
        let short = ThoughtExtractionEngine.extractWithRules("Wash the mugs tomorrow.").items
        XCTAssertEqual(short.count, 1)
        XCTAssertTrue(short[0].organization.itemType.isActionable)
    }

    func testDefiniteIdeaContinuationAcrossActionNeedsUniqueTopic() {
        let source = "I had an idea for a photo series: follow the park path. "
            + "Call Jo tomorrow. The series could include winter snow."
        let rows = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.contains { $0.organization.itemType == .idea
            && $0.analysisText.contains("winter snow")
            && $0.sourceQuote.contains("The series") })
        XCTAssertTrue(rows.contains { $0.organization.itemType.isActionable
            && !$0.sourceQuote.contains("winter snow") })

        let unrelated = ThoughtExtractionEngine.extractWithRules(
            "I had an idea for a photo series: follow the park path. "
                + "Call Jo tomorrow. The garden could use more rainwater."
        ).items
        XCTAssertEqual(unrelated.count, 3)
        XCTAssertTrue(unrelated.last?.sourceQuote.contains("rainwater") == true)

        let competing = ThoughtExtractionEngine.extractWithRules(
            "I had an idea for a photo series: follow the park path. "
                + "I had another idea for a concert series: record local bands. "
                + "Call Jo tomorrow. The series could include winter snow."
        ).items
        XCTAssertTrue(competing.contains { $0.needsReview
            && $0.sourceQuote.contains("winter snow") })
    }

    func testExplicitIdeaFocusKeepsFullSourceAndIndependentFacts() {
        let source = "I had an idea for a photo series: follow the park path in four seasons. "
            + "The series could include winter snow."
        let owned = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(owned.count, 1)
        XCTAssertEqual(owned[0].organization.itemType, .idea)
        XCTAssertTrue(owned[0].analysisText.contains("follow the park path"))
        XCTAssertTrue(owned[0].analysisText.contains("winter snow"))
        XCTAssertTrue(owned[0].sourceQuote.contains("I had an idea"))
        XCTAssertEqual(owned[0].sourceUnitIDs.count, SourceUnitLedger(source).words.count)

        let separate = ThoughtExtractionEngine.extractWithRules(
            "The park path gets beautiful light after rain. "
                + "I had an idea for a photo series: follow that path in four seasons."
        ).items
        XCTAssertEqual(separate.count, 2)
        XCTAssertEqual(separate[0].organization.itemType, .note)
        XCTAssertEqual(separate[1].organization.itemType, .idea)
        XCTAssertTrue(separate[0].sourceQuote.contains("beautiful light"))
        XCTAssertFalse(separate[1].sourceQuote.contains("beautiful light"))

        let distinct = ThoughtExtractionEngine.extractWithRules(
            "I had an idea for the garden: plant herbs there. The lock code is 1234."
        ).items
        XCTAssertEqual(distinct.count, 2)
        XCTAssertTrue(distinct.last?.sourceQuote.contains("1234") == true)

        let mixedFrame = ThoughtExtractionEngine.extractWithRules(
            "The park is wet and my idea: follow the path in four seasons."
        ).items
        XCTAssertTrue(mixedFrame.contains { $0.needsReview
            && $0.sourceQuote.contains("The park is wet") })
        let firstPersonMixedFrame = ThoughtExtractionEngine.extractWithRules(
            "I had an idea and the park is wet: follow the path in four seasons."
        ).items
        XCTAssertTrue(firstPersonMixedFrame.contains(where: \.needsReview))
        let coordinatedNouns = ThoughtExtractionEngine.extractWithRules(
            "I had an idea for cats and dogs: make a shared shelter."
        ).items
        XCTAssertEqual(coordinatedNouns.count, 1)
        XCTAssertEqual(coordinatedNouns[0].organization.itemType, .idea)
        XCTAssertFalse(coordinatedNouns[0].needsReview)
    }

    func testChoiceFocusOwnsOnlyPureAlternativesWithUniqueAction() {
        let selected = ThoughtExtractionEngine.extractWithRules(
            "I was considering the bus or the train, but I chose the bus. "
                + "Buy the bus ticket tonight."
        ).items
        XCTAssertEqual(selected.count, 1)
        XCTAssertTrue(selected[0].organization.itemType.isActionable)
        XCTAssertTrue(selected[0].sourceQuote.contains("considering the bus"))
        XCTAssertTrue(selected[0].sourceQuote.contains("Buy the bus ticket"))

        let reason = ThoughtExtractionEngine.extractWithRules(
            "I was considering the bus or the train, but I chose the bus "
                + "because parking costs more. Buy the bus ticket tonight."
        ).items
        XCTAssertEqual(reason.count, 1)
        XCTAssertTrue(reason[0].sourceQuote.contains("parking costs more"))
        XCTAssertTrue(reason[0].organization.itemType.isActionable)

        let separateFact = ThoughtExtractionEngine.extractWithRules(
            "I was considering the bus or the train, but I chose the bus; "
                + "the lock code is 1234. Buy the bus ticket tonight."
        ).items
        XCTAssertTrue(separateFact.contains { $0.sourceQuote.contains("1234") })

        let independentReason = ThoughtExtractionEngine.extractWithRules(
            "I was considering the bus or the train. "
                + "Mara said the train is delayed, so I chose the bus. "
                + "Buy the bus ticket tonight."
        ).items
        XCTAssertEqual(independentReason.count, 3)
        XCTAssertTrue(independentReason.contains { $0.sourceQuote.contains("Mara said") })
        XCTAssertTrue(independentReason.contains { $0.organization.itemType.isActionable })

        let ambiguous = ThoughtExtractionEngine.extractWithRules(
            "I was considering the bus or the train, but I chose the bus. "
                + "Buy the bus ticket tonight. Reserve the bus seat tomorrow."
        ).items
        XCTAssertTrue(ambiguous.contains { $0.needsReview
            && $0.sourceQuote.contains("considering the bus") })
        XCTAssertEqual(ambiguous.filter { $0.organization.itemType.isActionable }.count, 2)

        let tentative = ThoughtExtractionEngine.extractWithRules(
            "I might paint the room, not today. Buy screws tomorrow."
        ).items
        XCTAssertEqual(tentative.count, 2)
        XCTAssertEqual(tentative[0].organization.itemType, .note)
        let quoted = ThoughtExtractionEngine.extractWithRules(
            "Mara said, \"I had an idea: buy milk.\" Call Jo tomorrow."
        ).items
        XCTAssertEqual(quoted.count, 2)
        XCTAssertEqual(quoted[0].organization.itemType, .note)
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(
            "Buy screws tomorrow."
        ).items.count, 1)
    }

    func testAttributedQuotedCommandKeepsReporterAndOwnVoiceActions() {
        let archive = ThoughtExtractionEngine.extractWithRules(
            "The archive volunteer read a note in the margin of a diary: "
                + "“Hide the silver in the garden.” I should photograph the page with permission."
        ).items
        XCTAssertEqual(archive.count, 2)
        XCTAssertEqual(archive[0].organization.itemType, .note)
        XCTAssertTrue(archive[0].sourceQuote.contains("archive volunteer read"))
        XCTAssertTrue(archive[0].sourceQuote.contains("Hide the silver"))
        XCTAssertTrue(archive[1].organization.itemType.isActionable)

        let briefing = ThoughtExtractionEngine.extractWithRules(
            "At the food-bank briefing the coordinator read an example from a training card: "
                + "“Give every family the same parcel.” "
                + "I need to check the blank intake sheets tomorrow."
        ).items
        XCTAssertEqual(briefing.count, 2)
        XCTAssertEqual(briefing[0].organization.itemType, .note)
        XCTAssertTrue(briefing[1].organization.itemType.isActionable)

        let direct = ThoughtExtractionEngine.extractWithRules(
            "Read the note “Hide the silver in the garden.”"
        ).items
        XCTAssertEqual(direct.count, 1)
        XCTAssertTrue(direct[0].organization.itemType.isActionable)

        let quotedMessage = ThoughtExtractionEngine.extractWithRules(
            "Text Maya “Hide the silver in the garden.”"
        ).items
        XCTAssertEqual(quotedMessage.count, 1)
        XCTAssertTrue(quotedMessage[0].organization.itemType.isActionable)

        let adopted = ThoughtExtractionEngine.extractWithRules(
            "The volunteer read a note: “Hide the silver in the garden,” "
                + "and I should photograph the page."
        ).items
        XCTAssertEqual(adopted.count, 2)
        XCTAssertEqual(adopted[0].organization.itemType, .note)
        XCTAssertTrue(adopted[1].organization.itemType.isActionable)

        let explainedButNotAdopted = ThoughtExtractionEngine.extractWithRules(
            "The volunteer read a note: “Hide the silver in the garden,” "
                + "and I agree: that was a strange instruction."
        ).items
        XCTAssertFalse(explainedButNotAdopted.contains {
            $0.organization.itemType.isActionable
        })

        let adoptionOnlyInsideAnotherQuote = ThoughtExtractionEngine.extractWithRules(
            "The volunteer read the first note: “Wait here.” "
                + "She then quoted a second note: “I agree: call Ben tomorrow.”"
        ).items
        XCTAssertFalse(adoptionOnlyInsideAnotherQuote.contains {
            $0.organization.itemType.isActionable
        })
        XCTAssertNil(QuotedSpeechScope.directActionAfterQuote(
            "The volunteer read two notes: “Wait here,” and “No, I agree: call Ben tomorrow.”"
        ))
    }

    func testNumberedProcedureWithoutSpeakerCommitmentRemainsReviewable() {
        for source in [
            "Recipe steps: 1 add two teaspoons of salt 2 stir until thick "
                + "3 let it cool.",
            "The training manual lists steps: 1 call the customer "
                + "2 send the form 3 close the case."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 3, source)
            XCTAssertTrue(items.allSatisfy(\.needsReview), source)
            XCTAssertFalse(items.contains { $0.organization.itemType.isActionable }, source)
        }

        let owned = ThoughtExtractionEngine.extractWithRules(
            "My steps today: 1 call Maya 2 buy milk 3 send the invoice."
        ).items
        XCTAssertEqual(owned.count, 3)
        XCTAssertTrue(owned.allSatisfy { $0.organization.itemType.isActionable })
    }

    func testSeparateExplicitTemporalScopesKeepTheirActionOwners() {
        for connector in [", then", "and"] {
            let items = ThoughtExtractionEngine.extractWithRules(
                "I need to call Lena today \(connector) hand the banners to Leni Saturday."
            ).items
            XCTAssertEqual(items.count, 2, connector)
            XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable },
                          connector)
            if items.count == 2 {
                XCTAssertNotEqual(items[0].organization.dueDate,
                                  items[1].organization.dueDate, connector)
                XCTAssertTrue(items[0].sourceQuote.contains("Lena today"), connector)
                XCTAssertTrue(items[1].sourceQuote.contains("Leni Saturday"), connector)
            }
        }
        let shared = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow, call Lena and email Pavel."
        ).items
        XCTAssertEqual(shared.count, 2)
        XCTAssertEqual(shared[0].organization.dueDate,
                       shared[1].organization.dueDate)
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(
            "I go to the gym every Tuesday and Thursday"
        ).items.count, 1)
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(
            "Meeting at 2 and at 4"
        ).items.count, 1)
    }

    func testSourcePropositionPlanKeepsMixedSegmentOccurrences() {
        let source = "The porch is wet. It may need paint; call Mara tomorrow."
        let plan = RuleBasedThoughtExtractor.SourcePropositionPlan(
            source: source, segmentQuotes: [source]
        )
        XCTAssertEqual(plan.propositions.count, 3)
        XCTAssertTrue(plan.unassignedSourceUnitIDs.isEmpty)
        XCTAssertTrue(plan.unmatchedSegmentIndices.isEmpty)
        XCTAssertEqual(
            Set(plan.propositions.flatMap(\.sourceUnitIDs)).count,
            plan.ledger.words.count
        )
        XCTAssertTrue(plan.propositions.allSatisfy { $0.segmentIndex == 0 })
    }

    func testSourcePropositionPlanDoesNotMergeIndependentFactsOrRepeatedWords() {
        let first = "The bank charges high fees."
        let second = "My dog likes the bank path."
        let source = "\(first) \(second)"
        let plan = RuleBasedThoughtExtractor.SourcePropositionPlan(
            source: source, segmentQuotes: [first, second]
        )
        XCTAssertEqual(plan.propositions.count, 2)
        XCTAssertTrue(plan.unassignedSourceUnitIDs.isEmpty)
        XCTAssertTrue(plan.propositions[0].sourceUnitIDs.isDisjoint(
            with: plan.propositions[1].sourceUnitIDs
        ))
        let bankIDs = plan.ledger.words.indices.filter { plan.ledger.words[$0].text == "bank" }
        XCTAssertEqual(bankIDs.count, 2)
        XCTAssertTrue(plan.propositions[0].sourceUnitIDs.contains(bankIDs[0]))
        XCTAssertTrue(plan.propositions[1].sourceUnitIDs.contains(bankIDs[1]))
    }

    func testSourcePropositionPlanExposesUnmatchedMeaningfulSource() {
        let source = "The lock code is 1234. Buy screws."
        let plan = RuleBasedThoughtExtractor.SourcePropositionPlan(
            source: source, segmentQuotes: ["Buy screws.", "missing segment"]
        )
        XCTAssertEqual(plan.unmatchedSegmentIndices, [1])
        XCTAssertTrue(plan.unassignedSourceUnitIDs.contains {
            plan.ledger.words[$0].text == "1234"
        })
        XCTAssertTrue(plan.propositions[0].sourceUnitIDs.contains {
            plan.ledger.words[$0].text == "screws"
        })
    }

    func testSourcePropositionPlanRetainsTentativeAndReportedWordsAsEvidence() {
        let tentative = "I might paint the room, not today."
        let report = "Mara said, \"buy milk.\" She was quoting Jo."
        let source = "\(tentative) \(report)"
        let plan = RuleBasedThoughtExtractor.SourcePropositionPlan(
            source: source, segmentQuotes: [tentative, report]
        )
        XCTAssertTrue(plan.unassignedSourceUnitIDs.isEmpty)
        XCTAssertTrue(plan.unmatchedSegmentIndices.isEmpty)
        XCTAssertEqual(
            Set(plan.propositions.flatMap(\.sourceUnitIDs)).count,
            plan.ledger.words.count
        )
        let reportedWords = Set(plan.propositions
            .filter { $0.segmentIndex == 1 }
            .flatMap(\.sourceUnitIDs))
        XCTAssertTrue(plan.ledger.words.indices.contains {
            plan.ledger.words[$0].text == "buy" && reportedWords.contains($0)
        })
        let output = ThoughtExtractionEngine.extractWithRules(tentative).items
        XCTAssertEqual(output.count, 1)
        XCTAssertTrue(output[0].sourceQuote.contains("paint the room"))
    }

    func testSourcePropositionPlanAccountsForThirtyIndependentListEntries() {
        let quotes = (1...30).map { "\($0): Buy item \($0)." }
        let source = quotes.joined(separator: " ")
        let plan = RuleBasedThoughtExtractor.SourcePropositionPlan(
            source: source, segmentQuotes: quotes
        )
        XCTAssertEqual(plan.propositions.count, 30)
        XCTAssertTrue(plan.unassignedSourceUnitIDs.isEmpty)
        XCTAssertTrue(plan.unmatchedSegmentIndices.isEmpty)
    }

    func testSourceRolesKeepIndependentFactsAndTentativeIdeas() {
        let lock = ThoughtExtractionEngine.extractWithRules(
            "The lock code is 1234. Anyway, call Mary tomorrow."
        ).items
        XCTAssertEqual(lock.count, 2)
        XCTAssertEqual(lock[0].organization.itemType, .note)
        XCTAssertTrue(lock[0].sourceQuote.contains("1234"))
        XCTAssertTrue(lock[1].organization.itemType.isActionable)

        let tentative = ThoughtExtractionEngine.extractWithRules(
            "I might paint the room, not today. Buy screws tomorrow."
        ).items
        XCTAssertEqual(tentative.count, 2)
        XCTAssertEqual(tentative[0].organization.itemType, .note)
        XCTAssertTrue(tentative[0].sourceQuote.contains("paint the room"))

        let unsupportedNegative = ThoughtExtractionEngine.extractWithRules(
            "I do not need a reminder for the library."
        ).items
        XCTAssertEqual(unsupportedNegative.count, 1)
        XCTAssertTrue(unsupportedNegative[0].needsReview)
    }

    func testSourceRolesOwnOnlyExplicitBackgroundAndUniquePersonContinuation() {
        let person = ThoughtExtractionEngine.extractWithRules(
            "The botanist's name is Lena. She knows the moss species well. Call Jo tomorrow."
        ).items
        XCTAssertEqual(person.count, 2)
        XCTAssertEqual(person[0].organization.itemType, .note)
        XCTAssertTrue(person[0].analysisText.contains("Lena"))
        XCTAssertTrue(person[0].analysisText.contains("moss species"))
        XCTAssertTrue(person[0].sourceQuote.contains("botanist's name is Lena"))
        XCTAssertTrue(person[0].rawQuote.contains("She knows"))

        let background = ThoughtExtractionEngine.extractWithRules(
            "A little background: the attic box is dusty. "
                + "The box contains Mara's old drawings. Call Jo tomorrow."
        ).items
        XCTAssertEqual(background.count, 2)
        XCTAssertTrue(background[0].sourceQuote.contains("attic box is dusty"))
        XCTAssertTrue(background[0].sourceQuote.contains("old drawings"))

        let separate = ThoughtExtractionEngine.extractWithRules(
            "The shed needs a new lock. Call Jo tomorrow. Buy screws Friday."
        ).items
        XCTAssertEqual(separate.count, 3)
        XCTAssertEqual(separate[0].organization.itemType, .note)
        XCTAssertEqual(separate.filter { $0.organization.itemType.isActionable }.count, 2)
    }

    func testPropositionEdgesRequireOneNamedAntecedent() {
        let single = "The botanist's name is Lena. She knows the moss species well."
        let owned = ThoughtExtractionEngine.extractWithRules(single).items
        XCTAssertEqual(owned.count, 1)
        XCTAssertEqual(owned[0].sourceUnitIDs.count, SourceUnitLedger(single).words.count)
        XCTAssertTrue(owned[0].analysisText.contains("Lena"))
        XCTAssertTrue(owned[0].analysisText.contains("moss species"))

        let competing = ThoughtExtractionEngine.extractWithRules(
            "The botanist's name is Lena. The teacher's name is Mara. "
                + "She knows the moss species well."
        ).items
        XCTAssertEqual(competing.count, 3)
        XCTAssertTrue(competing[2].needsReview)
        XCTAssertFalse(competing[0].analysisText.contains("moss species"))
        XCTAssertFalse(competing[1].analysisText.contains("moss species"))

        let newLocalSubject = ThoughtExtractionEngine.extractWithRules(
            "The botanist's name is Lena. Call Jo tomorrow. "
                + "The teacher's name is Mara. She knows the moss species well."
        ).items
        XCTAssertEqual(newLocalSubject.count, 3)
        XCTAssertFalse(newLocalSubject.contains(where: \.needsReview))
        XCTAssertTrue(newLocalSubject[2].analysisText.contains("Mara"))
        XCTAssertTrue(newLocalSubject[2].analysisText.contains("moss species"))

        let unrelated = ThoughtExtractionEngine.extractWithRules(
            "The botanist's name is Lena. The teacher's name is Mara. Call Jo tomorrow."
        ).items
        XCTAssertEqual(unrelated.count, 3)
        XCTAssertFalse(unrelated.contains(where: \.needsReview))
    }

    func testCaptureOnlyNarrationRequiresAnotherRetainedIntention() {
        let withTask = ThoughtExtractionEngine.extractWithRules(
            "I am just narrating this. Buy screws tomorrow."
        ).items
        XCTAssertEqual(withTask.count, 1)
        XCTAssertTrue(withTask[0].organization.itemType.isActionable)

        let alone = ThoughtExtractionEngine.extractWithRules(
            "I am just narrating this."
        ).items
        XCTAssertEqual(alone.count, 1)
        XCTAssertTrue(alone[0].needsReview)

        let substantive = ThoughtExtractionEngine.extractWithRules(
            "I am narrating my son's first steps. Buy screws tomorrow."
        ).items
        XCTAssertEqual(substantive.count, 2)
        XCTAssertTrue(substantive[0].sourceQuote.contains("first steps"))
    }

    func testCoordinatedFactObjectKeepsOneMemoryIdentity() {
        let one = ThoughtExtractionEngine.extractWithRules(
            "Remember that Mara likes mint and lemon tea, not coffee."
        ).items
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one[0].organization.itemType, .note)
        XCTAssertTrue(one[0].sourceQuote.contains("mint and lemon tea"))
        let independent = ThoughtExtractionEngine.extractWithRules(
            "Mara likes mint tea and Nora keeps lemon tea at work."
        ).items
        XCTAssertEqual(independent.count, 2)
        let sameSubject = ThoughtExtractionEngine.extractWithRules(
            "The train was late and then it was cancelled."
        ).items
        XCTAssertEqual(sameSubject.count, 1)
        let action = ThoughtExtractionEngine.extractWithRules(
            "Mara likes mint tea and call Nora Friday."
        ).items
        XCTAssertEqual(action.count, 2)
        XCTAssertTrue(action.contains { $0.organization.itemType.isActionable })
        let short = ThoughtExtractionEngine.extractWithRules("Buy mint tea Friday.").items
        XCTAssertEqual(short.count, 1)
        XCTAssertTrue(short[0].organization.itemType.isActionable)

        let exposed = ThoughtExtractionEngine.extractWithRules(
            "I'm walking home and I keep thinking about the birthday thing, "
                + "because last year I left it to the last second and that was awkward. "
                + "Anyway the actual thing is, order a cake for Dad by Thursday "
                + "and check whether the bakery can write his name with the accent. "
                + "I might go for a walk later, but I haven't decided. Also remember "
                + "that Dad likes the orange and almond cake, not the chocolate one. "
                + "I said cake about three times; it's one order, plus the question for the bakery."
        ).items
        let cakeFacts = exposed.filter { $0.analysisText.contains("Dad likes") }
        XCTAssertEqual(cakeFacts.count, 1)
        XCTAssertTrue(cakeFacts[0].sourceQuote.contains("orange and almond cake"))
        XCTAssertTrue(cakeFacts[0].sourceQuote.contains("not the chocolate one"))
    }

    func testExplicitOwnIdeaTypeDoesNotBecomeAnActionOrAPlainFact() {
        let idea = ThoughtExtractionEngine.extractWithRules(
            "The thought of repainting the porch is just an idea for someday."
        ).items
        XCTAssertEqual(idea.count, 1)
        XCTAssertEqual(idea[0].organization.itemType, .idea)
        XCTAssertNil(idea[0].organization.dueDate)
        let firstPerson = ThoughtExtractionEngine.extractWithRules(
            "I had an idea to make a neighborhood map."
        ).items
        XCTAssertEqual(firstPerson.first?.organization.itemType, .idea)
        let someoneElse = ThoughtExtractionEngine.extractWithRules(
            "Mara had an idea to make a neighborhood map."
        ).items
        XCTAssertEqual(someoneElse.first?.organization.itemType, .note)
        let noIdea = ThoughtExtractionEngine.extractWithRules(
            "I have no idea where the map went."
        ).items
        XCTAssertEqual(noIdea.first?.organization.itemType, .note)
        let short = ThoughtExtractionEngine.extractWithRules("Paint the porch Friday.").items
        XCTAssertTrue(short.first?.organization.itemType.isActionable == true)

        let exposed = ThoughtExtractionEngine.extractWithRules(
            "At the garden meeting I learned that the north bed keeps moisture "
                + "longer than the beds by the fence, and the volunteer Asha knows "
                + "the irrigation system really well. Put those facts somewhere "
                + "findable. For action, buy two bags of compost on Saturday, "
                + "email Asha a photo of the broken valve tonight, and book the "
                + "tool shed for next weekend. The thought of painting the fence "
                + "is just an idea for someday."
        ).items
        XCTAssertEqual(exposed.filter { $0.organization.itemType.isActionable }.count, 3)
        XCTAssertEqual(exposed.filter { $0.organization.itemType == .idea }.count, 1)
        XCTAssertFalse(exposed.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("painting the fence") })
    }

    func testExplicitReferenceRoutingOwnsOnlyUniqueMemory() {
        let routed = ThoughtExtractionEngine.extractWithRules(
            "The library's west room is quiet. Call Nora Friday. "
                + "I don't need an alarm for the library. It is reference information."
        ).items
        XCTAssertEqual(routed.count, 2)
        let memory = routed.first { $0.organization.itemType == .note }
        XCTAssertTrue(memory?.sourceQuote.contains("west room is quiet") == true)
        XCTAssertTrue(memory?.sourceQuote.contains("don't need an alarm") == true)
        XCTAssertTrue(memory?.sourceQuote.contains("reference information") == true)
        XCTAssertFalse(routed.contains(where: \.needsReview))
        XCTAssertTrue(routed.contains { $0.organization.itemType.isActionable
            && $0.analysisText.contains("Call Nora") })

        let noClarification = ThoughtExtractionEngine.extractWithRules(
            "The library's west room is quiet. I don't need an alarm for the library."
        ).items
        XCTAssertTrue(noClarification.contains(where: \.needsReview))
        let wrongReferent = ThoughtExtractionEngine.extractWithRules(
            "The library's west room is quiet. I don't need an alarm for the museum. "
                + "It is reference information."
        ).items
        XCTAssertTrue(wrongReferent.contains(where: \.needsReview))
        let twoOwners = ThoughtExtractionEngine.extractWithRules(
            "The library's west room is quiet. The library's east room is bright. "
                + "I don't need an alarm for the library. It is reference information."
        ).items
        XCTAssertTrue(twoOwners.contains(where: \.needsReview))
        let positive = ThoughtExtractionEngine.extractWithRules(
            "The library's west room is quiet. Remind me to visit the library Friday."
        ).items
        XCTAssertEqual(positive.count, 2)
        XCTAssertTrue(positive.contains { $0.organization.itemType.isActionable })
        let simple = ThoughtExtractionEngine.extractWithRules(
            "The library's west room is quiet."
        ).items
        XCTAssertEqual(simple.count, 1)
        XCTAssertEqual(simple[0].organization.itemType, .note)

        // The exposed mixed capture remains development evidence. This
        // assertion covers only the routing-commentary defect, not the
        // unresolved identity of its two cafe facts.
        let exposed = ThoughtExtractionEngine.extractWithRules(
            "For the trip, check in online the night before departure and download "
                + "the offline map before I get on the plane. The cafe beside the hotel "
                + "is called Marigold, and the person at reception said its back room "
                + "is quiet enough to work in; remember that for later. Also ask Theo "
                + "whether he can collect the keys on Monday, and put a charger in "
                + "the carry-on. I don't need an alarm for the cafe; it is reference information."
        ).items
        XCTAssertFalse(exposed.contains(where: \.needsReview))
        XCTAssertFalse(exposed.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("alarm for the cafe") })
        XCTAssertTrue(exposed.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("reference information") })
    }

    func testDestinationDayScopesOnlyActionsAtThatPlace() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let frame = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 10
        ))!
        func read(_ text: String) -> [ExtractedThought] {
            ThoughtExtractionEngine.extractWithRules(
                text, referenceDate: frame, calendar: calendar
            ).items
        }
        let scoped = read(
            "I need to get to the archive on Thursday. "
                + "I could take the bus or cycle; I chose the bus. "
                + "Buy the bus ticket before Thursday. "
                + "Meet Kai at the archive door at eleven. "
                + "Meet Jo at the archive desk at noon."
        )
        XCTAssertEqual(scoped.count, 3)
        XCTAssertTrue(scoped[0].sourceQuote.contains("I chose the bus"))
        XCTAssertFalse(scoped[0].sourceQuote.contains("get to the archive"))
        for (item, hour) in zip(scoped.dropFirst(), [11, 12]) {
            XCTAssertTrue(item.sourceQuote.contains("get to the archive on Thursday"))
            XCTAssertEqual(item.organization.temporalIntent.day,
                           CalendarDay(year: 2026, month: 8, day: 6))
            XCTAssertEqual(item.organization.temporalIntent.time?.hour, hour)
            XCTAssertEqual(calendar.component(.hour, from: item.organization.dueDate!), hour)
        }

        let otherPlace = read(
            "I need to get to the archive on Thursday. Meet Kai at the museum at eleven."
        )
        XCTAssertEqual(otherPlace.count, 2)
        XCTAssertFalse(otherPlace[1].sourceQuote.contains("get to the archive"))
        let otherDay = read(
            "I need to get to the archive on Thursday. "
                + "Meet Kai at the archive door on Friday at eleven."
        )
        XCTAssertEqual(otherDay.count, 2)
        XCTAssertEqual(otherDay[1].organization.temporalIntent.day,
                       CalendarDay(year: 2026, month: 8, day: 7))
        let ownArrival = read(
            "I need to get to the archive on Thursday at nine. "
                + "Meet Kai at the archive door at eleven."
        )
        XCTAssertEqual(ownArrival.count, 2)
        let interrupted = read(
            "I need to get to the archive on Thursday. The filing code is blue. "
                + "Meet Kai at the archive door at eleven."
        )
        XCTAssertEqual(interrupted.count, 3)
        XCTAssertFalse(interrupted[2].sourceQuote.contains("get to the archive"))
        let twoTrips = read(
            "I need to get to the archive on Thursday. "
                + "I need to get to the archive on Friday. "
                + "Meet Kai at the archive door at eleven."
        )
        XCTAssertEqual(twoTrips.count, 2)
        XCTAssertTrue(twoTrips[0].sourceQuote.contains("Thursday"))
        XCTAssertFalse(twoTrips[1].sourceQuote.contains("Thursday"))
        XCTAssertEqual(twoTrips[1].organization.temporalIntent.day,
                       CalendarDay(year: 2026, month: 8, day: 7))
        let simple = read("Meet Kai at the archive door at eleven.")
        XCTAssertEqual(simple.count, 1)
        XCTAssertEqual(simple[0].organization.temporalIntent.day,
                       CalendarDay(year: 2026, month: 8, day: 3))
    }

    func testFormerLongGateDestinationAndChoiceRemainDistinct() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let frame = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 10
        ))!
        let items = ThoughtExtractionEngine.extractWithRules(
            "I need to get to the museum on Sunday. "
                + "I could drive or take the tram; I chose the tram because parking is expensive. "
                + "Buy the tram ticket before Sunday and meet Hana at the museum entrance at eleven. "
                + "Remember that the south entrance has the step-free route. "
                + "Driving was a considered option, not an action to save or a second itinerary.",
            referenceDate: frame, calendar: calendar
        ).items
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.filter { $0.organization.itemType.isActionable }.count, 2)
        let meeting = items.first {
            $0.analysisText.lowercased().contains("meet hana")
        }
        XCTAssertNotNil(meeting)
        XCTAssertEqual(meeting?.organization.temporalIntent.day,
                       CalendarDay(year: 2026, month: 8, day: 9))
        XCTAssertEqual(meeting?.organization.temporalIntent.time?.hour, 11)
        XCTAssertTrue(meeting?.sourceQuote.contains("get to the museum on Sunday") == true)
        XCTAssertFalse(items.contains { $0.analysisText.lowercased().contains("drive to")
            && $0.organization.itemType.isActionable })
    }

    func testCoordinatedTransportNamesDoNotBecomeShoppingProductsOnIOS() {
        XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses("Pick up Alex and Sam").count, 1)
        let people = ThoughtExtractionEngine.extractWithRules("Pick up Alex and Sam").items
        XCTAssertEqual(people.count, 1)
        XCTAssertEqual(people.first?.organization.itemType, .task)
        XCTAssertEqual(people.first?.organization.personName, "Alex")
        XCTAssertTrue(people.first?.sourceQuote.contains("Alex and Sam") == true)

        let places = ThoughtExtractionEngine.extractWithRules(
            "Pick up Alex at school and Sam at the airport"
        ).items
        XCTAssertEqual(places.count, 2)
        let products = ThoughtExtractionEngine.extractWithRules(
            "Pick up Tylenol and Advil"
        ).items
        XCTAssertEqual(products.count, 2)
        XCTAssertTrue(products.allSatisfy { $0.organization.itemType == .shopping })
        let otherProducts = ThoughtExtractionEngine.extractWithRules(
            "Pick up Coke and Sprite"
        ).items
        XCTAssertEqual(otherProducts.count, 2)
        XCTAssertTrue(otherProducts.allSatisfy { $0.organization.itemType == .shopping })
        let short = ThoughtExtractionEngine.extractWithRules("Pick up Alex from school").items
        XCTAssertEqual(short.count, 1)
        XCTAssertEqual(short.first?.organization.itemType, .task)
    }

    func testUniqueTimedEventOwnsOnlyItsDeicticActionContext() {
        let referenceDate = ISO8601DateFormatter().date(from: "2026-10-05T13:00:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        func read(_ text: String) -> ThoughtExtractionResult {
            ThoughtExtractionEngine.extractWithRules(
                text, referenceDate: referenceDate, calendar: calendar
            )
        }
        let linked = read(
            "The ferry departs at 8:10 on Saturday. Pack the camera on Friday. "
                + "Leave for the dock in time for that ferry."
        ).items
        XCTAssertEqual(linked.count, 3)
        XCTAssertEqual(linked[0].organization.itemType, .event)
        XCTAssertEqual(linked[1].organization.itemType, .task)
        XCTAssertFalse(linked[1].sourceQuote.contains("ferry departs"))
        XCTAssertEqual(linked[2].organization.itemType, .task)
        XCTAssertFalse(linked[2].needsReview)
        XCTAssertTrue(linked[2].sourceQuote.contains("ferry departs at 8:10"))
        XCTAssertTrue(linked[2].sourceQuote.contains("Leave for the dock"))
        XCTAssertNil(linked[2].organization.dueDate)
        XCTAssertNil(linked[2].organization.reminderDate)

        let competing = read(
            "The morning ferry departs at 8:10 on Saturday. "
                + "The evening ferry departs at 6:30 on Saturday. "
                + "Leave for the dock in time for that ferry."
        ).items
        XCTAssertEqual(competing.count, 3)
        XCTAssertTrue(competing[2].needsReview)
        XCTAssertFalse(competing[0].needsReview)
        XCTAssertFalse(competing[1].needsReview)

        let missing = read(
            "The bus departs at 8:10 on Saturday. "
                + "Leave for the dock in time for that ferry."
        ).items
        XCTAssertEqual(missing.count, 2)
        XCTAssertEqual(missing[1].organization.itemType, .task)
        XCTAssertFalse(missing[1].needsReview)
        XCTAssertFalse(missing[1].sourceQuote.contains("bus departs"))

        let impossible = read(
            "The ferry departs at 8:10 AM on Saturday. "
                + "Leave for the dock at 9 AM Saturday in time for that ferry."
        ).items
        XCTAssertEqual(impossible.count, 2)
        XCTAssertTrue(impossible[1].needsReview)
        XCTAssertNil(impossible[1].organization.dueDate)
        let feasible = read(
            "The ferry departs at 8:10 AM on Saturday. "
                + "Leave for the dock at 7 AM Saturday in time for that ferry."
        ).items
        XCTAssertEqual(feasible.count, 2)
        XCTAssertFalse(feasible[1].needsReview)
        XCTAssertNotNil(feasible[1].organization.dueDate)

        let simple = read(
            "Leave for the dock on Saturday."
        ).items
        XCTAssertEqual(simple.count, 1)
        XCTAssertFalse(simple[0].needsReview)
        XCTAssertNotNil(simple[0].organization.dueDate)

        let exposed = read(
            "I want to remember that the train goes at 6:40—sorry, that was last month's timetable. "
                + "The current ticket says 7:15 from platform four on Saturday. "
                + "I need to pack the blue folder on Friday night and leave for the station "
                + "early enough for that train. Keep the corrected ticket detail as reference; "
                + "don't act on the superseded time."
        ).items
        let departure = exposed.first {
            $0.organization.itemType.isActionable
                && $0.analysisText.contains("leave for the station")
        }
        XCTAssertNotNil(departure)
        XCTAssertTrue(departure?.sourceQuote.contains("current ticket says 7:15") == true)
        XCTAssertNil(departure?.organization.dueDate)
    }

    func testExplicitObsoleteFactIsOwnedByOneSettledReplacement() {
        let referenceDate = ISO8601DateFormatter().date(from: "2026-10-05T13:00:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        func read(_ text: String) -> ThoughtExtractionResult {
            ThoughtExtractionEngine.extractWithRules(
                text, referenceDate: referenceDate, calendar: calendar
            )
        }
        let corrected = read(
            "I remember the bell rang at 6:40—sorry, that was the old log. "
                + "The current log says 7:15. Keep the corrected detail as reference. "
                + "Don't use the superseded time."
        )
        XCTAssertTrue(corrected.operations.isEmpty)
        XCTAssertEqual(corrected.items.count, 1)
        XCTAssertEqual(corrected.items[0].organization.itemType, .note)
        XCTAssertFalse(corrected.items[0].needsReview)
        XCTAssertTrue(corrected.items[0].sourceQuote.contains("6:40"))
        XCTAssertTrue(corrected.items[0].sourceQuote.contains("7:15"))
        XCTAssertTrue(corrected.items[0].sourceQuote.contains("corrected detail"))
        XCTAssertTrue(corrected.items[0].sourceQuote.contains("superseded time"))
        XCTAssertTrue((corrected.items[0].suggestedTitle ?? "").contains("7:15"))

        let unrelated = read(
            "The old service log said 6:40. The current weather report says 7:15."
        ).items
        XCTAssertEqual(unrelated.count, 2)
        let separated = read(
            "I remember the bell rang at 6:40—sorry, that was the old log. "
                + "Separately, the current weather report says 7:15."
        ).items
        XCTAssertEqual(separated.count, 2)
        XCTAssertTrue(separated[0].needsReview)
        let unsettled = read(
            "I remember the bell rang at 6:40—sorry, that was the old log. "
                + "The current log might say 7:15 or 7:45."
        ).items
        XCTAssertTrue(unsettled.allSatisfy(\.needsReview))
        let reported = read(
            "Maya said the bell rang at 6:40—sorry, that was the old log. "
                + "The current log says 7:15."
        ).items
        XCTAssertEqual(reported.count, 2)

        let exposed = read(
            "I want to remember that the train goes at 6:40—sorry, that was last month's timetable. "
                + "The current ticket says 7:15 from platform four on Saturday. "
                + "I need to pack the blue folder on Friday night and leave for the station "
                + "early enough for that train. Keep the corrected ticket detail as reference; "
                + "don't act on the superseded time."
        )
        XCTAssertTrue(exposed.operations.isEmpty)
        XCTAssertEqual(exposed.items.filter { $0.organization.itemType == .note }.count, 1)
        XCTAssertEqual(exposed.items.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertFalse(exposed.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("keep the corrected") })
    }

    func testClauseBoundaryRequiresCompleteHeadAndIndependentAction() {
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses(
                "Please don't leave me a second call-the-plumber job just because I said it first"
            ).count, 1
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses("Buy milk second call Mom").count, 2
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses(
                "I need to pack the blue folder and leave for the station"
            ).count, 2
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses(
                "I need to pack the blue folder and leave it by the door"
            ).count, 1
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses(
                "Maya said pack the blue folder and leave for the station"
            ).count, 1
        )

        let correction = ThoughtExtractionEngine.extractWithRules(
            "The current ticket says 7:15 from platform four on Saturday. "
                + "I need to pack the blue folder on Friday night and leave for the station "
                + "early enough for that train."
        ).items
        let actions = correction.filter { $0.organization.itemType.isActionable }
        XCTAssertEqual(actions.count, 2)
        XCTAssertTrue(actions.contains { $0.analysisText.lowercased().contains("pack the blue folder") })
        XCTAssertTrue(actions.contains { $0.analysisText.lowercased().contains("leave for the station") })
    }

    func testReportedFilingWordsRemainASeparateMemory() {
        let reported = ThoughtExtractionEngine.extractWithRules(
            "Maya said keep the consent form for review. Call Maya tomorrow."
        ).items
        XCTAssertEqual(reported.count, 2)
        XCTAssertEqual(reported[0].organization.itemType, .note)
        XCTAssertTrue(reported[0].sourceQuote.contains("consent form"))
        XCTAssertTrue(reported[1].organization.itemType.isActionable)

        let direct = ThoughtExtractionEngine.extractWithRules(
            "Please keep the consent form for review. Call Maya tomorrow."
        ).items
        XCTAssertEqual(direct.count, 1)
        XCTAssertTrue(direct[0].sourceQuote.contains("consent form"))
    }

    func testNarrativePivotLeavesOneExplicitIntention() {
        let source = "I keep telling myself I'll get to it and I never do, anyway I have to renew my passport"
        let clauses = RuleBasedThoughtExtractor.splitClauses(source)
        XCTAssertEqual(clauses.last, "anyway I have to renew my passport")
        XCTAssertEqual(IntentConsolidator.consolidate(source, clauses: clauses)?.analysisText,
                       "I have to renew my passport")

        let unpunctuated = source.replacingOccurrences(of: ",", with: "")
        let flattened = ThoughtExtractionEngine.extractWithRules(unpunctuated).items
        XCTAssertEqual(flattened.count, 1)
        if let item = flattened.first {
            XCTAssertTrue(item.organization.itemType.isActionable)
            XCTAssertFalse(item.needsReview)
            XCTAssertEqual(item.analysisText, "I have to renew my passport")
        }

        let unresolved = ThoughtExtractionEngine.extractWithRules(
            "I keep telling myself I'll get to it and I never do anyway it is not urgent"
        ).items
        XCTAssertFalse(unresolved.contains {
            $0.organization.itemType.isActionable && !$0.needsReview
        })

        let independent = ThoughtExtractionEngine.extractWithRules(
            "I have to renew my passport and buy milk"
        ).items
        XCTAssertEqual(independent.count, 2)
    }

    func testCaptureOutputInstructionsAttachWithoutInventingTasks() {
        let facts = ThoughtExtractionEngine.extractWithRules(
            "Mina prefers labels under diagrams. Put those facts somewhere findable."
        ).items
        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts[0].organization.itemType, .note)
        XCTAssertTrue(facts[0].sourceQuote.contains("Put those facts somewhere findable"))

        let tasks = ThoughtExtractionEngine.extractWithRules(
            "Call the dentist and pay the fee. Please keep the two errands and the two memories distinct."
        ).items
        XCTAssertEqual(tasks.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertFalse(tasks.contains { $0.suggestedTitle?.contains("two errands") == true })

        let concrete = ThoughtExtractionEngine.extractWithRules(
            "Put those facts into the report"
        ).items
        XCTAssertEqual(concrete.count, 1)
        XCTAssertTrue(concrete[0].organization.itemType.isActionable)
    }

    func testDeicticRetentionOwnsPriorFactWithoutSwallowingNewContent() {
        for source in [
            "She is allergic to lavender, so remember that as a lasting fact about her.",
            "The back room is quiet enough to work in; remember that for later.",
            "The north bed stays moist. Keep that in my notes.",
            "Mara prefers voice notes. Remember that about her."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, source)
            XCTAssertEqual(items[0].organization.itemType, .note, source)
            XCTAssertFalse(items[0].needsReview, source)
            XCTAssertEqual(items[0].rawQuote.trimmingCharacters(in: .punctuationCharacters),
                           source.trimmingCharacters(in: .punctuationCharacters), source)
        }

        let newFact = ThoughtExtractionEngine.extractWithRules(
            "The back room is quiet. Remember that the front room has a desk."
        ).items
        XCTAssertEqual(newFact.count, 2)
        XCTAssertTrue(newFact.allSatisfy { $0.organization.itemType == .note })

        let mixed = ThoughtExtractionEngine.extractWithRules(
            "Call Mara tomorrow. She prefers voice notes. Remember that about her. "
                + "Send the invitation Friday."
        ).items
        XCTAssertEqual(mixed.count, 3)
        XCTAssertEqual(mixed.map { $0.organization.itemType.isActionable }, [true, false, true])
        XCTAssertTrue(mixed[1].sourceQuote.contains("Remember that about her"))
        XCTAssertFalse(mixed.contains(where: \.needsReview))

        for dangling in [
            "Remember that about her.",
            "Call Mara tomorrow. Remember that about her."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(dangling).items
            XCTAssertTrue(items.contains { $0.needsReview
                && $0.sourceQuote.contains("Remember that about her") }, dangling)
        }

        let newAction = ThoughtExtractionEngine.extractWithRules(
            "The back room is quiet. Remember that tomorrow I need to call Mia."
        ).items
        XCTAssertEqual(newAction.count, 2)
        XCTAssertTrue(newAction.last?.organization.itemType.isActionable == true)

        let learnedOwnObligation = ThoughtExtractionEngine.extractWithRules(
            "I learned that I need to call Mia tomorrow."
        ).items
        XCTAssertEqual(learnedOwnObligation.count, 1)
        XCTAssertTrue(learnedOwnObligation[0].organization.itemType.isActionable)
        let learnedOtherObligation = ThoughtExtractionEngine.extractWithRules(
            "I learned that Mia needs to call me tomorrow."
        ).items
        XCTAssertEqual(learnedOtherObligation.count, 1)
        XCTAssertEqual(learnedOtherObligation[0].organization.itemType, .note)

        let changedDestination = ThoughtExtractionEngine.extractWithRules(
            "The back room is quiet. Keep that as a task."
        ).items
        XCTAssertFalse(changedDestination.isEmpty)
        XCTAssertFalse(changedDestination.count == 1
            && changedDestination[0].organization.itemType == .note
            && !changedDestination[0].needsReview)
    }

    func testDeicticFindabilityRequestOwnsOnlyAnAdjacentMemory() {
        let owned = ThoughtExtractionEngine.extractWithRules(
            "The portal account uses my work email. Keep that fact findable. "
                + "Submit the forms tomorrow."
        ).items
        XCTAssertEqual(owned.count, 2)
        XCTAssertEqual(owned[0].organization.itemType, .note)
        XCTAssertTrue(owned[0].sourceQuote.contains("Keep that fact findable"))
        XCTAssertFalse((owned[0].suggestedTitle ?? "").contains("findable"))
        XCTAssertTrue(owned[1].organization.itemType.isActionable)

        let unowned = ThoughtExtractionEngine.extractWithRules(
            "Buy stamps. Keep that fact findable."
        ).items
        XCTAssertTrue(unowned.contains { $0.needsReview
            && $0.sourceQuote.contains("Keep that fact findable") })
        XCTAssertTrue(unowned.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("buy stamps") })

        for physical in ["Keep that file in the drawer", "Put those facts into the report"] {
            let items = ThoughtExtractionEngine.extractWithRules(physical).items
            XCTAssertEqual(items.count, 1, physical)
            XCTAssertTrue(items[0].organization.itemType.isActionable, physical)
        }
    }

    func testPlainCoordinatedCommitmentEndsUncommittedSpeechActOwner() {
        for source in [
            "I was thinking of buying milk, and I need to call Mom.",
            "I have an idea to buy milk, and I have to call Mom.",
            "I might buy milk and I need to call Mom."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 2, source)
            XCTAssertFalse(items[0].organization.itemType.isActionable, source)
            XCTAssertTrue(items[1].organization.itemType.isActionable, source)
            XCTAssertTrue(items[1].sourceQuote.lowercased().contains("call mom"), source)
        }
        let sharedIdea = ThoughtExtractionEngine.extractWithRules(
            "I have an idea to buy milk and call Mom."
        ).items
        XCTAssertEqual(sharedIdea.count, 1)
        XCTAssertEqual(sharedIdea[0].organization.itemType, .idea)
        let direct = ThoughtExtractionEngine.extractWithRules(
            "I need to buy milk and call Mom."
        ).items
        XCTAssertEqual(direct.count, 2)
        XCTAssertTrue(direct.allSatisfy { $0.organization.itemType.isActionable })
    }

    func testSectionLeadsOwnTheFollowingAction() {
        let previousTaggerMode = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previousTaggerMode
            SentenceContextCache.invalidate()
        }
        for disablesTagger in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disablesTagger
            SentenceContextCache.invalidate()
            for source in [
                "For action, schedule the pickup tomorrow",
                "First, before I forget, call the contractor",
                "Right at the end: bring the spare cable"
            ] {
                let items = ThoughtExtractionEngine.extractWithRules(source).items
                XCTAssertEqual(items.count, 1, source)
                XCTAssertTrue(items[0].organization.itemType.isActionable, source)
                XCTAssertEqual(items[0].rawQuote, source, source)
            }
            let ordinaryFact = ThoughtExtractionEngine.extractWithRules(
                "The first action film club met yesterday"
            ).items
            XCTAssertEqual(ordinaryFact.count, 1)
            XCTAssertTrue(ordinaryFact.allSatisfy { !$0.organization.itemType.isActionable })
        }
    }

    func testExplicitDiscourseFramesRouteTheirContentBeforeTheFrame() {
        let sectionAction = ThoughtExtractionEngine.extractWithRules(
            "Beginning: pay the water bill tomorrow"
        ).items
        XCTAssertEqual(sectionAction.count, 1)
        XCTAssertTrue(sectionAction[0].organization.itemType.isActionable)
        XCTAssertTrue(sectionAction[0].analysisText.lowercased().hasPrefix("pay the water bill"))
        XCTAssertTrue(sectionAction[0].sourceQuote.contains("Beginning:"))

        let selfNarratedFact = ThoughtExtractionEngine.extractWithRules(
            "I'm going to talk around this topic now: the paper statement is below the kettle"
        ).items
        XCTAssertEqual(selfNarratedFact.count, 1)
        XCTAssertEqual(selfNarratedFact[0].organization.itemType, .note)
        XCTAssertTrue(selfNarratedFact[0].analysisText.lowercased().hasPrefix("the paper statement"))
        XCTAssertTrue(selfNarratedFact[0].sourceQuote.contains("talk around"))

        let conditionalFact = ThoughtExtractionEngine.extractWithRules(
            "I'm going to talk around the topic now: the paper statement is below "
                + "the kettle, which might help if I have to find it again"
        ).items
        XCTAssertEqual(conditionalFact.count, 1)
        XCTAssertEqual(conditionalFact[0].organization.itemType, .note)
        XCTAssertFalse(conditionalFact[0].needsReview)
        let conditionalAction = ThoughtExtractionEngine.extractWithRules(
            "Beginning: call Maya if she is free"
        ).items
        XCTAssertEqual(conditionalAction.count, 1)
        XCTAssertTrue(conditionalAction[0].organization.itemType.isActionable)

        let realConversation = ThoughtExtractionEngine.extractWithRules(
            "I need to talk to Maya tomorrow about the lease"
        ).items
        XCTAssertTrue(realConversation.contains { $0.organization.itemType.isActionable })
        let literalBeginning = ThoughtExtractionEngine.extractWithRules(
            "The beginning of the story is in Porto"
        ).items
        XCTAssertEqual(literalBeginning.count, 1)
        XCTAssertEqual(literalBeginning[0].organization.itemType, .note)
        let coordinated = ThoughtExtractionEngine.extractWithRules(
            "Beginning: pay the bill and call Maya"
        ).items
        XCTAssertEqual(coordinated.count, 2)
        XCTAssertTrue(coordinated.allSatisfy { $0.organization.itemType.isActionable })
        XCTAssertTrue(coordinated.first?.sourceQuote.contains("Beginning:") == true)

        let bareQuote = ThoughtExtractionEngine.extractWithRules(
            "Beginning: \"Cancel my appointment\""
        )
        XCTAssertTrue(bareQuote.operations.isEmpty)
        XCTAssertEqual(bareQuote.items.count, 1)
        XCTAssertTrue(bareQuote.items[0].needsReview)
        XCTAssertEqual(bareQuote.items[0].rawQuote,
                       "Beginning: \"Cancel my appointment\"")

        let direct = ThoughtExtractionEngine.extractWithRules(
            "Beginning: call Maya tomorrow"
        ).items
        XCTAssertEqual(direct.count, 1)
        XCTAssertTrue(direct[0].organization.itemType.isActionable)
        XCTAssertFalse(direct[0].needsReview)

        let attributed = ThoughtExtractionEngine.extractWithRules(
            "Beginning: Mom said \"call Maya\". Then email Ben tomorrow"
        ).items
        XCTAssertTrue(attributed.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Mom said") })
        XCTAssertTrue(attributed.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("email Ben") })
        XCTAssertFalse(attributed.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("call maya") })
        let directQuoted = ThoughtExtractionEngine.extractWithRules(
            "Beginning: text Maya \"call me after lunch\" tomorrow"
        ).items
        XCTAssertTrue(directQuoted.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("text Maya") })
        let sequencedFact = ThoughtExtractionEngine.extractWithRules(
            "Then the train carries bicycles"
        ).items
        XCTAssertEqual(sequencedFact.count, 1)
        XCTAssertEqual(sequencedFact[0].organization.itemType, .note)
    }

    func testIndefiniteProposedCreationCannotCancelASavedItem() {
        let proposal = ThoughtExtractionEngine.extractWithRules(
            "The path might make a good photo series. I could ask someone to join me. "
                + "No, don't make an outing for me yet; I am only keeping the idea."
        )
        XCTAssertTrue(proposal.operations.isEmpty)
        XCTAssertTrue(proposal.items.contains {
            $0.sourceQuote.localizedCaseInsensitiveContains("don't make an outing")
        })

        let existingTarget = ThoughtExtractionEngine.extractWithRules(
            "Don't call Maya"
        )
        XCTAssertEqual(existingTarget.operations.first?.operation, .cancel)
    }

    func testDeclaredFactColonRoutesContentAndKeepsIndependentActions() {
        let source = "Add my task to buy a first aid kit for the club supplies cupboard. Add my task to look for a second hand monitor stand. Keep this as a fact in Memory: The club booking system is run by a third party provider."
        let items = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertTrue(items.contains { $0.organization.itemType == .note
            && $0.analysisText.contains("third party provider") })
        let independent = ThoughtExtractionEngine.extractWithRules(
            "Keep this as a fact in Memory: The café opens at nine, and email Mara tomorrow."
        ).items
        XCTAssertEqual(independent.count, 2)
        XCTAssertTrue(independent.contains { $0.organization.itemType == .note
            && $0.analysisText.contains("café opens") })
        XCTAssertTrue(independent.contains { $0.organization.itemType.isActionable
            && $0.analysisText.contains("email Mara") })
        for text in ["Keep the file on the memory card tomorrow", "Keep this as a task: send the invoice tomorrow",
                     "Save this as a note: I still need to send the invoice tomorrow"] {
            XCTAssertTrue(ThoughtExtractionEngine.extractWithRules(text).items.contains {
                $0.organization.itemType.isActionable
            }, text)
        }
    }

    func testHistoricalReasonDoesNotReplaceAnExplicitCommunicationCommitment() {
        for source in [
            "email the scan to fariha once i have checked that both pages are readable the check matters because i sent a cropped scan once",
            "text Rowan the corrected address because i gave the old address last time",
            "email Alex the signed form because i did not send both pages yesterday"
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, items.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(items.first?.organization.itemType.isActionable == true, source)
            XCTAssertFalse(items.first?.needsReview == true, source)
            XCTAssertNil(items.first?.organization.reminderDate)
            XCTAssertTrue(items.first?.sourceQuote.contains("because") == true)
        }
        for source in [
            "I emailed the scan to Fariha because she requested it",
            "I did not email the scan because it was unreadable",
            "Mina said to email the scan because she sent the wrong copy",
            "If I get the scan I might email Fariha once I have checked it"
        ] {
            XCTAssertFalse(ThoughtExtractionEngine.extractWithRules(source).items.contains {
                $0.organization.itemType.isActionable && !$0.needsReview
            }, source)
        }
        let completed = ThoughtExtractionEngine.extractWithRules(
            "Email Alex the form. Actually I already emailed it this morning.").items
        XCTAssertFalse(completed.contains { $0.organization.itemType.isActionable && !$0.needsReview })
    }

    func testRecipientReversalSurvivesMissingStopsWithoutLosingItsCondition() {
        for (source, corrected, withdrawn, detail) in [
            ("email the scan to farah once i have checked that both pages are readable actually send it to fariha not farah", "fariha", "farah", "both pages are readable"),
            ("text Rowan about the revised address after i confirm the house number actually message it to Alex not Rowan", "Alex", "Rowan", "confirm the house number")
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, items.map(\.sourceQuote).joined(separator: " | "))
            let actions = items.filter { $0.organization.itemType.isActionable && !$0.needsReview }
            XCTAssertEqual(actions.count, 1)
            XCTAssertTrue(actions.first?.analysisText.localizedCaseInsensitiveContains(corrected) == true)
            XCTAssertFalse(actions.first?.analysisText.localizedCaseInsensitiveContains(withdrawn) == true,
                           "only the final recipient belongs in the action, while source retains the reversal")
            XCTAssertTrue(actions.first?.sourceQuote.contains(detail) == true)
            XCTAssertTrue(actions.first?.sourceQuote.localizedCaseInsensitiveContains("not " + withdrawn) == true)
            XCTAssertNil(actions.first?.organization.reminderDate)
            // A written stop changes only the recognizer's boundary evidence.
            // This diagnostic never supplies a corrected name to production.
            let separated = source.replacingOccurrences(of: " actually ", with: ". Actually ") + "."
            let control = ThoughtExtractionEngine.extractWithRules(separated).items
            XCTAssertEqual(control.count, 1)
            XCTAssertTrue(control.first?.analysisText.localizedCaseInsensitiveContains(corrected) == true)
            XCTAssertFalse(control.first?.analysisText.localizedCaseInsensitiveContains(withdrawn) == true)
        }
        let report = ThoughtExtractionEngine.extractWithRules(
            "Mina said 'email the scan to Farah actually send it to Fariha not Farah'. Pack the tripod tomorrow.").items
        XCTAssertEqual(report.filter { $0.organization.itemType.isActionable && !$0.needsReview }.count, 1)
        XCTAssertTrue(report.contains { $0.analysisText.localizedCaseInsensitiveContains("pack the tripod") })
        let ambiguous = ThoughtExtractionEngine.extractWithRules(
            "email the scan to Farah text Farah about the keys actually send it to Fariha not Farah").items
        XCTAssertFalse(ambiguous.contains { $0.organization.itemType.isActionable && !$0.needsReview },
                       "missing stops do not identify which of two communications changes recipient")
        XCTAssertTrue(ambiguous.contains { $0.needsReview && $0.sourceQuote.contains("scan")
            && $0.sourceQuote.contains("keys") && $0.sourceQuote.contains("not Farah") })
    }

    func testContentRetentionClassificationKeepsIdeasAndFactsOutOfToday() {
        for source in [
            "Keep web page and booklet as undecided ideas; do not create either as a task.",
            "Save the photo guide and map as possible ideas."
        ] {
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(rows.count, 1, rows.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertEqual(rows.first?.organization.itemType, .idea)
            XCTAssertFalse(rows.contains { $0.organization.itemType.isActionable || $0.needsReview })
            XCTAssertTrue(rows.first?.sourceQuote.localizedCaseInsensitiveContains("ideas") == true)
        }
        XCTAssertFalse(ActionabilityReader.read("Keep those as setup facts.").belongsOnToday)
        for source in ["Save this note: the spare key is under the flowerpot.",
                       "Save this as a fact: the cupboard door sticks in damp weather."] {
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.organization.itemType, .note)
            XCTAssertFalse(rows.contains { $0.organization.itemType.isActionable || $0.needsReview }, source)
        }
        for source in ["Keep the printed booklet in the supplies cupboard.",
                       "Save the signed file to the project folder tomorrow.",
                       "Save this note: I still need to email the signed form tomorrow.",
                       "Keep making the web page as a task."] {
            XCTAssertTrue(ThoughtExtractionEngine.extractWithRules(source).items.contains {
                $0.organization.itemType.isActionable && !$0.needsReview
            }, source)
        }
        let separate = ThoughtExtractionEngine.extractWithRules(
            "Save the photo guide and map as possible ideas. Buy eggs. The printer is in the studio.").items
        XCTAssertEqual(separate.count, 3)
        XCTAssertEqual(separate.filter { $0.organization.itemType == .idea }.count, 1)
        XCTAssertEqual(separate.filter { $0.organization.itemType.isActionable }.count, 1)
        XCTAssertTrue(separate.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("printer") })
        let report = ThoughtExtractionEngine.extractWithRules(
            "Mina said 'Keep the printed booklet in the cupboard.' I am only recording what she said.").items
        XCTAssertFalse(report.contains { $0.organization.itemType.isActionable && !$0.needsReview })
    }

    func testRetentionModifiersDoNotOwnIndependentTasksOrFacts() {
        XCTAssertEqual(ActionabilityReader.retainedContentKind(
            "Save the message as a reference note with the caretaker as the speaker, including the gate detail."), .note)
        XCTAssertEqual(ActionabilityReader.retainedContentKind(
            "Keep the guide and map as possible ideas for the exhibition."), .idea)
        for source in [
            "Keep the guide and map as possible ideas for the exhibition and call Jo tomorrow.",
            "Keep the guide and map as possible ideas for the exhibition and the printer is in the studio."
        ] {
            XCTAssertNil(ActionabilityReader.retainedContentKind(source), source)
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertTrue(rows.contains { $0.organization.itemType == .idea }, source)
            if source.contains("call Jo") {
                XCTAssertTrue(rows.contains { $0.organization.itemType.isActionable && $0.analysisText.contains("Jo") }, source)
            } else {
                XCTAssertTrue(rows.contains { $0.organization.itemType == .note && $0.analysisText.contains("printer") }, source)
            }
        }
    }

    func testExplicitReflectionRetentionIsKnowledgeAndPhysicalSavingIsAction() {
        for source in ["Save that as a reflection.",
                       "Record my journal entry as a reflection about the move."] {
            XCTAssertEqual(ActionabilityReader.retainedContentKind(source), .note)
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertFalse(rows.contains { $0.organization.itemType.isActionable }, source)
        }
        let rows = ThoughtExtractionEngine.extractWithRules(
            "Save the signed file to the project folder tomorrow. Record my journal entry as a reflection about the move. Call Jo tomorrow.").items
        XCTAssertEqual(rows.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertTrue(rows.contains { $0.organization.itemType == .note && $0.analysisText.contains("journal") })
    }

    func testStepMarkerKeepsTrailingPrerequisiteTaskAccessibleWithoutEventAlert() {
        for source in [
            "Reprint the caption. Then ask Amira to check the new caption after I have printed it, not before.",
            "Check both pages. Then email Nora the scan once I have checked that both pages are readable."
        ] {
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(rows.count, 2, rows.map(\.analysisText).joined(separator: " | "))
            XCTAssertTrue(rows.allSatisfy { $0.organization.itemType.isActionable && !$0.needsReview },
                          source + " => " + rows.map {
                "\($0.organization.itemType): \($0.analysisText) review=\($0.needsReview) trigger=\(String(describing: $0.organization.temporalIntent.unsupportedTrigger))"
            }.joined(separator: " | "))
            XCTAssertTrue(rows.allSatisfy { $0.organization.reminderDate == nil }, source)
        }
        XCTAssertEqual(ActionabilityReader.read("Then ask Amira to check the new caption"), .actionable)
        XCTAssertEqual(ActionabilityReader.read("Then call records are archived in the cupboard"), .knowledge)
        XCTAssertEqual(ActionabilityReader.read("Reprint editions are stored in the cupboard"), .knowledge)
        let alert = ThoughtExtractionEngine.extractWithRules(
            "Remind me to email Nora the scan once I have checked that both pages are readable.").items
        XCTAssertTrue(alert.contains { $0.needsReview })
        XCTAssertTrue(alert.allSatisfy { $0.organization.reminderDate == nil })
        let report = ThoughtExtractionEngine.extractWithRules(
            "Mina said, 'Then ask Amira to check the caption after I have printed it.'").items
        XCTAssertFalse(report.contains { $0.organization.itemType.isActionable && !$0.needsReview })
    }

    func testRecipientRepairEditingPartsKeepKnownMessagesAndRejectForeignContent() {
        let email = "Remind me tomorrow at 9 AM to email the scan to Farah."
        let text = "Remind me tomorrow at 10 AM to text Farah about the keys."
        XCTAssertEqual(RuleBasedThoughtExtractor.recipientRevisionEditingParts(
            in: email + "\n" + text + "\nActually, send it to Fariha, not Farah."), [email, text])
        XCTAssertEqual(RuleBasedThoughtExtractor.recipientRevisionEditingParts(
            in: email + "\n" + text + "\nActually\nsend it to Fariha, not Farah"), [email, text])
        for source in [
            email + "\nBuy eggs.\nActually, send it to Fariha, not Farah.",
            email + "\nMina said 'Text Farah about the keys.'\nActually, send it to Fariha, not Farah.",
            email + "\n" + text + "\nActually, send it to Fariha, not Farah. Buy eggs.",
            email + "\n" + text
        ] {
            XCTAssertNil(RuleBasedThoughtExtractor.recipientRevisionEditingParts(in: source), source)
        }
    }

    func testQuotedSentenceStopsAndCommunicationTopicsPreserveOwnership() {
        let report = "Mina said, 'Email the draft. Send the receipt tomorrow.'"
        let rows = ThoughtExtractionEngine.extractWithRules(report + " Pack the tripod tomorrow.").items
        let actions = rows.filter { $0.organization.itemType.isActionable && !$0.needsReview }
        XCTAssertEqual(actions.count, 1, rows.map(\.sourceQuote).joined(separator: " | "))
        XCTAssertTrue(actions.first?.analysisText.localizedCaseInsensitiveContains("pack the tripod") == true)
        XCTAssertTrue(rows.contains { $0.sourceQuote.contains("Email the draft") && $0.sourceQuote.contains("Send the receipt") })
        for source in ["Email Alex about the old invoice next Monday",
                       "Text Rowan regarding the damaged return tomorrow"] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.filter { $0.organization.itemType.isActionable }.count, 1,
                           items.map(\.sourceQuote).joined(separator: " | "))
        }
        for source in ["Email Sam about the deck submit the report",
                       "Text Rowan regarding the draft mail the signed form"] {
            let independent = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(independent.filter { $0.organization.itemType.isActionable }.count, 2,
                           independent.map(\.sourceQuote).joined(separator: " | "))
        }
        let commands = ThoughtExtractionEngine.extractWithRules("Email Alex and invoice Rowan tomorrow.").items
        XCTAssertEqual(commands.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules("Invoice Rowan tomorrow.").items
            .filter { $0.organization.itemType.isActionable }.count, 1)
    }

    func testRecipientReversalDoesNotCombineIndependentOrReportedCommunications() {
        let independent = ThoughtExtractionEngine.extractWithRules(
            "Email the scan to Farah. Send the form to Fariha.").items
        XCTAssertEqual(independent.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertTrue(independent.contains { $0.analysisText.contains("scan to Farah") })
        XCTAssertTrue(independent.contains { $0.analysisText.contains("form to Fariha") })
        let report = ThoughtExtractionEngine.extractWithRules(
            "Isha said, 'Email the scan to Farah. Actually, send it to Fariha, not Farah.'").items
        XCTAssertFalse(report.contains { $0.organization.itemType.isActionable && !$0.needsReview })
        XCTAssertTrue(report.contains { $0.sourceQuote.contains("Farah") && $0.sourceQuote.contains("Fariha") })
        let ambiguous = ThoughtExtractionEngine.extractWithRules(
            "Email the scan to Farah. Text Farah about the keys. Actually, send it to Fariha, not Farah.").items
        XCTAssertFalse(ambiguous.contains {
            $0.analysisText.hasPrefix("Email") && $0.organization.personName == "Fariha"
        }, "two prior communications cannot be chosen by recency")
        XCTAssertTrue(ambiguous.contains { $0.sourceQuote.contains("not Farah") })
        XCTAssertFalse(ambiguous.contains { $0.organization.itemType.isActionable && !$0.needsReview },
                       "neither competing communication nor objectless correction can execute before local editing")
        XCTAssertEqual(ambiguous.count, 1)
        XCTAssertEqual(ambiguous.first?.organization.state, .contested(.uncertainClauseBoundary))
    }

    func testNominalCommitmentConnectiveDoesNotCreateAnotherThought() {
        let rows = ThoughtExtractionEngine.extractWithRules(
            "And the final definite thing is to return the folding table tomorrow."
        ).items
        XCTAssertEqual(rows.count, 1, rows.map(\.sourceQuote).joined(separator: " | "))
        XCTAssertTrue(rows.first?.organization.itemType.isActionable == true)
    }

    func testNominalCommitmentOpensUnpunctuatedMemoryBoundary() {
        let memory = "I had a possible idea of putting a shelf by the door nothing decided just a thought "
        for declaration in ["the last definite thing is to text Laila about the table",
                            "the next definite thing is to email Jo the draft",
                            "the first actual action is to call the caretaker"] {
            let original = memory + declaration
            let intermediate = memory.trimmingCharacters(in: .whitespaces) + ". " + declaration
            let corrected = ThoughtExtractionEngine.extractWithRules(intermediate).items
            XCTAssertEqual(corrected.filter { $0.organization.itemType.isActionable }.count, 1)
            let actual = ThoughtExtractionEngine.extractWithRules(original).items
            let actions = actual.filter { $0.organization.itemType.isActionable }
            XCTAssertEqual(actions.count, 1, actual.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(actions.first?.sourceQuote.contains(declaration) == true)
            XCTAssertFalse(actions.first?.sourceQuote.contains("possible idea") == true)
            XCTAssertTrue(actual.contains { !$0.organization.itemType.isActionable && $0.sourceQuote.contains("possible idea") })
            let diagnostic = XCTAttachment(string: "original clauses=" + RuleBasedThoughtExtractor.splitClauses(original).joined(separator: " | ")
                + "\ncorrect-boundary clauses=" + RuleBasedThoughtExtractor.splitClauses(intermediate).joined(separator: " | "))
            diagnostic.name = "Nominal commitment source boundary differential"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
        }
        for source in ["Pat said the last definite thing is to text Laila about the table",
                       "Remember Pat's words: 'the next definite thing is to email Jo the draft'",
                       "I had a possible idea that the first action would be to call the caretaker"] {
            XCTAssertFalse(ThoughtExtractionEngine.extractWithRules(source).items.contains {
                $0.organization.itemType.isActionable
            }, source)
        }
    }

    func testDeclaredCommunicationClosesPrecedingMemoryScope() {
        let memory = "Remember the idea of a small shelf by the door. Nothing decided, just a thought."
        for declaration in ["The last definite thing is to text Laila about borrowing the folding table.",
                            "The next definite thing is to email Jo the draft.",
                            "The first actual action is to call the caretaker."] {
            let rows = ThoughtExtractionEngine.extractWithRules(memory + " " + declaration).items
            XCTAssertEqual(rows.filter { $0.organization.itemType.isActionable }.count, 1,
                           rows.map(\.analysisText).joined(separator: " | "))
            XCTAssertTrue(rows.contains { $0.organization.itemType == .note || $0.organization.itemType == .idea })
            XCTAssertFalse(rows.contains { !$0.organization.itemType.isActionable && $0.sourceQuote.contains(declaration) })
            XCTAssertTrue(rows.filter { $0.organization.itemType.isActionable }.allSatisfy { !$0.needsReview && $0.organization.dueDate == nil })
        }
    }

    func testAnaphoricQuestionKeepsItsCommunicationOwnerAndContentDate() {
        for (action, question, scope) in [
            ("Text Laila about borrowing the folding table.", "Ask whether she needs it back by Saturday.", "That is the question, not when I need to send the text."),
            ("Email Jo about the draft.", "Ask whether she can review it on Tuesday.", "This is the question, not when I need to send the email."),
            ("Call the caretaker about the lights.", "Ask whether they can inspect them on Friday.", "That is the question, not when I need to make the call.")
        ] {
            let rows = ThoughtExtractionEngine.extractWithRules(action + " " + question + " " + scope).items
            XCTAssertEqual(rows.count, 1, rows.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(rows.first?.organization.itemType.isActionable == true)
            XCTAssertTrue(rows.first?.sourceQuote.contains(question) == true)
            XCTAssertTrue(rows.first?.sourceQuote.contains(scope) == true)
            XCTAssertNil(rows.first?.organization.dueDate)
            XCTAssertNil(rows.first?.organization.reminderDate)
            XCTAssertFalse(rows.first?.needsReview ?? true)
        }
        let separate = ThoughtExtractionEngine.extractWithRules(
            "Text Jo about the form. Ask Pat tomorrow about the room. The gate is locked. Buy eggs."
        ).items
        XCTAssertEqual(separate.filter { $0.organization.itemType.isActionable }.count, 3)
        XCTAssertTrue(separate.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("gate is locked") })
        XCTAssertTrue(separate.contains { $0.analysisText.contains("Pat") && $0.organization.dueDate != nil })
        for source in ["Text Jo about the draft. Email Amy about the room. Ask whether she is available on Friday.",
                       "Pat said text Jo about the draft. Ask whether she is available on Friday."] {
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertFalse(rows.contains { !$0.needsReview && $0.organization.itemType.isActionable
                && $0.sourceQuote.contains("text Jo") && $0.sourceQuote.contains("Ask whether") })
        }
    }

    func testLocatedObjectAndChoiceCorrectIntermediateDifferential() {
        let original = "I was considering a scarf or a sketchbook. I settled on the sketchbook. Buy it by Friday and wrap it before Saturday."
        let intermediate = original.replacingOccurrences(of: "Buy it", with: "Buy the sketchbook")
            .replacingOccurrences(of: "wrap it", with: "wrap the sketchbook")
        let rows = ThoughtExtractionEngine.extractWithRules(intermediate).items
        XCTAssertEqual(rows.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertTrue(rows.filter { $0.organization.itemType.isActionable }.allSatisfy {
            $0.analysisText.localizedCaseInsensitiveContains("sketchbook")
        })
        let source = "Then there is the library book. The blue photography book is still on the arm of the sofa under the folded blanket, which is probably why I kept missing it. Return that tomorrow."
        let actual = ThoughtExtractionEngine.extractWithRules(source).items
        let canonical = ThoughtExtractionEngine.extractWithRules(source.replacingOccurrences(of: "Return that", with: "Return the blue photography book")).items
        let diagnostic = XCTAttachment(string: (["original choice clauses=" + RuleBasedThoughtExtractor.splitClauses(original).joined(separator: " | ")]
            + actual.map { "actual source=\($0.sourceQuote) raw=\($0.rawQuote) analysis=\($0.analysisText)" }
            + canonical.map { "explicit intermediate source=\($0.sourceQuote) raw=\($0.rawQuote) analysis=\($0.analysisText)" }).joined(separator: "\n"))
        diagnostic.name = "Located object and chosen action stage differential"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        XCTAssertEqual(actual.count, 1)
        XCTAssertTrue(actual[0].rawQuote.contains("Then there is the library book"))
    }

    func testLocatedObjectReferenceKeepsIdentifyingContextOnItsOwnAction() {
        for (context, action, name) in [
            ("Then there is the library book. The blue photography book is still on the arm of the sofa under the folded blanket, which is probably why I kept missing it.", "Return that tomorrow.", "blue photography book"),
            ("The canvas bag is on the hallway hook.", "Pack it tomorrow.", "canvas bag"),
            ("The signed consent form is in the blue folder.", "Scan that tomorrow.", "signed consent form")
        ] {
            let rows = ThoughtExtractionEngine.extractWithRules(context + " " + action).items
            XCTAssertEqual(rows.count, 1, rows.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(rows.first?.analysisText.localizedCaseInsensitiveContains(name) == true)
            XCTAssertTrue(rows.first?.sourceQuote.contains(context) == true)
            XCTAssertTrue(rows.first?.sourceQuote.contains(action) == true)
            XCTAssertTrue(rows.first?.organization.itemType.isActionable == true)
            XCTAssertNil(rows.first?.organization.locationIntent)
            XCTAssertNil(rows.first?.organization.reminderDate)
        }
        for source in ["Return that tomorrow.",
                       "The blue book is on the sofa. The red book is on the desk. Return that tomorrow.",
                       "The paperwork is on the desk. The heating is broken. Scan it tomorrow."] {
            XCTAssertTrue(ThoughtExtractionEngine.extractWithRules(source).items.contains {
                $0.needsReview && $0.sourceQuote.localizedCaseInsensitiveContains("tomorrow")
            }, source)
        }
        let explicitMemory = ThoughtExtractionEngine.extractWithRules(
            "Remember that the canvas bag is on the hallway hook. Pack it tomorrow."
        ).items
        XCTAssertTrue(explicitMemory.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("Remember") })
        XCTAssertTrue(explicitMemory.contains { $0.organization.itemType.isActionable && $0.analysisText.contains("canvas bag") })
        let reportedCommand = ThoughtExtractionEngine.extractWithRules(
            "Pat said, 'Return the blue book tomorrow.' Return that tonight."
        ).items
        XCTAssertTrue(reportedCommand.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("Pat said") })
        XCTAssertFalse(reportedCommand.contains { !$0.needsReview && $0.organization.itemType.isActionable && $0.analysisText.contains("blue book") })
    }

    func testProspectiveReminderTimeIsMetadataForOneEstablishedAction() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        let final = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 20))!
        let timing = "I was going to say remind me at six tonight, but I will be away. Make it eight tonight."
        for action in ["Email Jo the draft.", "Return the table to the caretaker."] {
            let rows = ThoughtExtractionEngine.extractWithRules(action + " " + timing,
                referenceDate: anchor, calendar: calendar).items
            XCTAssertEqual(rows.count, 1, rows.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertEqual(rows.first?.organization.reminderDate, final)
            XCTAssertTrue(rows.first?.sourceQuote.contains("Make it eight") == true)
        }
        for source in [timing, "Email Jo the draft. Buy milk. " + timing,
                       "Pat said email Jo the draft. " + timing] {
            let rows = ThoughtExtractionEngine.extractWithRules(source,
                referenceDate: anchor, calendar: calendar).items
            XCTAssertTrue(rows.contains { $0.needsReview && $0.sourceQuote.contains("Make it eight") }, source)
            XCTAssertFalse(rows.contains { $0.organization.reminderDate != nil }, source)
        }
        let newCommitment = ThoughtExtractionEngine.extractWithRules(
            "Email Jo the draft. I was going to say remind me at six tonight, but I will call Pat. Make it eight tonight.",
            referenceDate: anchor, calendar: calendar).items
        XCTAssertTrue(newCommitment.contains { $0.organization.itemType.isActionable && $0.sourceQuote.contains("I will call Pat") })
        XCTAssertFalse(newCommitment.contains { $0.organization.reminderDate != nil })
        let separate = ThoughtExtractionEngine.extractWithRules(
            "Email Jo the draft. " + timing + " The café opens at nine. Buy eggs.",
            referenceDate: anchor, calendar: calendar).items
        XCTAssertEqual(separate.filter { $0.organization.reminderDate == final }.count, 1)
        XCTAssertTrue(separate.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("café opens") })
        XCTAssertTrue(separate.contains { $0.organization.itemType == .shopping && $0.sourceQuote.contains("eggs") && $0.organization.dueDate == nil })
    }

    func testNamedIdentityConfirmationDoesNotInventPurchasesOrChooseCompetingOwners() {
        for (action, identity) in [
            ("Email Jo the draft.", "Same draft, same Jo."),
            ("Return the table to the caretaker.", "Same table, same caretaker."),
            ("Send the landlord the pictures.", "Same pictures, same landlord.")
        ] {
            let rows = ThoughtExtractionEngine.extractWithRules(action + " " + identity).items
            XCTAssertEqual(rows.count, 1, rows.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(rows.first?.organization.itemType.isActionable == true)
            XCTAssertTrue(rows.first?.sourceQuote.contains(identity) == true)
        }
        for source in ["Same draft, same Jo.",
                       "Email Jo the draft. Print the draft for Jo. Same draft, same Jo."] {
            let rows = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertTrue(rows.contains { $0.needsReview && $0.sourceQuote.contains("Same draft") }, source)
            XCTAssertFalse(rows.contains { $0.organization.itemType == .shopping }, source)
        }
        let independent = ThoughtExtractionEngine.extractWithRules(
            "Email Jo the draft. Same draft, same Jo. Buy milk and eggs."
        ).items
        XCTAssertTrue(independent.contains { $0.organization.itemType == .shopping && $0.sourceQuote.contains("milk") })
        XCTAssertTrue(independent.contains { $0.organization.itemType.isActionable && $0.sourceQuote.contains("Same draft") })
        let reported = ThoughtExtractionEngine.extractWithRules(
            "Pat said email Jo the draft. Same draft, same Jo."
        ).items
        XCTAssertFalse(reported.contains { $0.organization.itemType.isActionable })
    }

    func testSelectedArtifactDetailUsesUniqueOwnerWithoutCopyingHistoricalDate() {
        for (action, detail) in [
            ("Send the landlord the pictures of the patch beside the kitchen window.",
             "I took a better picture this morning with the blind open, so use that one rather than the dark picture from last night."),
            ("Email the draft to Jo.",
             "I wrote a new draft yesterday with the corrected figures, so use that one rather than the old draft."),
            ("Upload the receipt.",
             "I scanned a clearer receipt today at the office, so use that one rather than the faded receipt.")
        ] {
            let rows = ThoughtExtractionEngine.extractWithRules(action + " " + detail).items
            XCTAssertEqual(rows.count, 1, rows.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(rows.first?.organization.itemType.isActionable == true)
            XCTAssertTrue(rows.first?.sourceQuote.contains(detail) == true)
            XCTAssertNil(rows.first?.organization.dueDate)
            XCTAssertNil(rows.first?.organization.reminderDate)
        }
        let competing = ThoughtExtractionEngine.extractWithRules(
            "Email the draft to Jo. Print the draft for Pat. I wrote a new draft yesterday with the corrected figures, so use that one rather than the old draft."
        ).items
        XCTAssertTrue(competing.contains { $0.needsReview && $0.sourceQuote.contains("corrected figures") })
        let missing = ThoughtExtractionEngine.extractWithRules(
            "I scanned a clearer receipt today at the office, so use that one rather than the faded receipt."
        ).items
        XCTAssertTrue(missing.contains { $0.needsReview })
        let independent = ThoughtExtractionEngine.extractWithRules(
            "Upload the receipt. I scanned a clearer receipt today at the office. Email Jo tomorrow."
        ).items
        XCTAssertTrue(independent.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("scanned") }, String(describing: independent.map { ($0.analysisText, $0.organization.itemType, $0.needsReview) }))
        XCTAssertTrue(independent.contains { $0.organization.itemType.isActionable && $0.sourceQuote.contains("Email Jo") })
    }

    func testContrastObjectRefinementRequiresUniqueEstablishedOwner() {
        for (action, detail) in [
            ("Send the landlord the pictures of the patch beside the kitchen window.",
             "Not the window itself, the paint underneath it where it has started bubbling again."),
            ("Photograph the damage beside the garage door.",
             "Not the door itself, the brickwork beside it where the crack runs."),
            ("Clean the stain around the bathroom tap.",
             "Not the tap itself, the tiles around it where the water collects.")
        ] {
            let source = action + " " + detail
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, String(describing: items.map { ($0.analysisText, $0.needsReview) }))
            XCTAssertTrue(items.first?.organization.itemType.isActionable == true)
            XCTAssertTrue(items.first?.sourceQuote.contains(detail) == true)
        }
        for tail in ["Email Jo tomorrow.", "The tiles are blue."] {
            let items = ThoughtExtractionEngine.extractWithRules(
                "Clean the stain around the bathroom tap. Not the tap itself, the tiles around it where the water collects. " + tail
            ).items
            XCTAssertEqual(items.count, 2, tail)
            XCTAssertTrue(items.contains { $0.sourceQuote.contains(tail) }, tail)
        }
        for source in [
            "Not the tap itself, the tiles around it where the water collects.",
            "Clean the stain around the bathroom tap. Photograph the tap. Not the tap itself, the tiles around it where the water collects."
        ] {
            XCTAssertTrue(ThoughtExtractionEngine.extractWithRules(source).items.contains {
                $0.needsReview && $0.sourceQuote.contains("Not the tap itself")
            }, source)
        }
        let finiteFact = ThoughtExtractionEngine.extractWithRules(
            "Clean the stain around the bathroom tap. Not the tap itself, the tiles are blue."
        ).items
        XCTAssertTrue(finiteFact.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("tiles are blue") })
        for report in ["Pat said photograph the damage beside the garage door.",
                       "Pat said, 'Photograph the damage beside the garage door.'"] {
            for commitment in ["I agree: photograph the damage beside the garage door.",
                               "I agree: I will photograph the damage beside the garage door."] {
                let source = report + " " + commitment + " Not the door itself, the brickwork beside it where the crack runs."
                let adoption = ThoughtExtractionEngine.extractWithRules(source).items
                XCTAssertEqual(adoption.filter { $0.organization.itemType.isActionable }.count, 1, source)
                XCTAssertTrue(adoption.contains { $0.organization.itemType.isActionable && $0.sourceQuote.contains("brickwork") }, source)
            }
        }
        let reported = ThoughtExtractionEngine.extractWithRules(
            "Pat said clean the stain around the bathroom tap. Not the tap itself, the tiles around it where the water collects."
        ).items
        XCTAssertFalse(reported.contains { $0.organization.itemType.isActionable })
    }

    func testLiteralObjectExplanationsRequireUniqueOwnersAndKeepIndependentContent() {
        let owned = ThoughtExtractionEngine.extractWithRules(
            "Buy a spare key. I mean a brass key for the back entrance."
        ).items
        XCTAssertEqual(owned.count, 1)
        XCTAssertTrue(owned.first?.sourceQuote.contains("brass key") == true)
        XCTAssertTrue(owned.first?.organization.itemType.isActionable == true)
        for tail in ["I mean a brass key, and email Mara tomorrow.",
                     "I mean a brass key, and the café opens at nine."] {
            let items = ThoughtExtractionEngine.extractWithRules("Buy a spare key. " + tail).items
            XCTAssertEqual(items.count, 2, tail)
            XCTAssertTrue(items.contains { $0.analysisText.contains("Mara")
                || $0.analysisText.contains("café opens") }, tail)
        }
        let ambiguous = ThoughtExtractionEngine.extractWithRules(
            "Buy a door key. Buy a locker key. I mean a brass key for the entrance."
        ).items
        XCTAssertTrue(ambiguous.contains { $0.needsReview && $0.sourceQuote.contains("brass key") })
        let definition = ThoughtExtractionEngine.extractWithRules(
            "Buy a next generation router. The words next generation are the name of the technology, not an instruction to wait until next month."
        ).items
        XCTAssertEqual(definition.count, 1)
        XCTAssertTrue(definition.first?.sourceQuote.contains("technology") == true)
        let fact = ThoughtExtractionEngine.extractWithRules("A spare key means access to the cupboard.").items
        XCTAssertEqual(fact.count, 1)
        XCTAssertEqual(fact.first?.organization.itemType, .note)
        let future = ThoughtExtractionEngine.extractWithRules(
            "Do not interpret next generation in this next sentence as a date: remember that the network uses a next generation router."
        ).items
        let futureSource = "Do not interpret next generation in this next sentence as a date: remember that the network uses a next generation router."
        let stage = XCTAttachment(string: "Boundaries: "
            + RuleBasedThoughtExtractor.splitClauses(futureSource).joined(separator: " | ")
            + "\nItems: " + future.map {
                "\($0.organization.itemType): \($0.analysisText) quote=\($0.sourceQuote) review=\($0.needsReview)"
            }.joined(separator: "\n"))
        stage.name = "Forward literal-term actual boundary differential"
        stage.lifetime = .keepAlways
        add(stage)
        XCTAssertEqual(future.count, 1)
        XCTAssertEqual(future.first?.organization.itemType, .note)
        XCTAssertFalse(future.contains(where: \.needsReview))
        let missing = ThoughtExtractionEngine.extractWithRules(
            "Do not interpret next generation in this next sentence as a date: remember that the cupboard is locked."
        ).items
        XCTAssertTrue(missing.contains { $0.needsReview && $0.sourceQuote.contains("interpret") })
        let intention = ThoughtExtractionEngine.extractWithRules("I mean to buy a spare key tomorrow.").items
        XCTAssertEqual(intention.count, 1)
        XCTAssertTrue(intention.first?.organization.itemType.isActionable == true)
        let reported = ThoughtExtractionEngine.extractWithRules(
            "Jo said that a brass key means access, not a time."
        ).items
        XCTAssertEqual(reported.count, 1)
        XCTAssertFalse(reported.contains { $0.organization.itemType.isActionable })
    }

    func testSearchActionAndOrdinalCompoundBoundariesKeepTheirHeads() {
        for text in ["Look for a used bicycle", "I need to look for a spare key"] {
            XCTAssertTrue(ActionabilityReader.read(text).belongsOnToday, text)
            let items = ThoughtExtractionEngine.extractWithRules(text).items
            XCTAssertEqual(items.count, 1, text)
            XCTAssertTrue(items.first?.organization.itemType.isActionable == true, text)
        }
        for text in ["First aid supplies are in the cupboard", "Second hand means used",
                     "Third party support is available"] {
            XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses(text).first, text, text)
            XCTAssertFalse(ActionabilityReader.read(text).belongsOnToday, text)
        }
        let steps = ThoughtExtractionEngine.extractWithRules(
            "First, buy batteries. Second, call the supplier. Third, collect the parcel."
        ).items
        let diagnostic = XCTAttachment(string: steps.map {
            "\($0.organization.itemType): \($0.analysisText) quote=\($0.sourceQuote)"
        }.joined(separator: "\n"))
        diagnostic.name = "Numbered action actual boundary differential"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        XCTAssertEqual(steps.count, 3)
        XCTAssertTrue(steps.allSatisfy { $0.organization.itemType.isActionable })
        for text in ["I look forward to the meeting", "I looked for the spare key yesterday"] {
            XCTAssertFalse(ActionabilityReader.read(text).belongsOnToday, text)
        }
    }

    func testPairedOutputReferencesOwnOnlyEstablishedActions() {
        let roots = "Pay the invoice tomorrow. Collect the parcel Friday. "
        let items = ThoughtExtractionEngine.extractWithRules(roots
            + "These are two tasks for different purposes. Keep both visible.").items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable && !$0.needsReview })
        XCTAssertTrue(items.allSatisfy { $0.sourceQuote.contains("Keep both visible") })

        let independent = ThoughtExtractionEngine.extractWithRules(roots
            + "Keep both keys in the drawer. The reception desk is closed Sunday.").items
        XCTAssertEqual(independent.count, 4)
        XCTAssertEqual(independent.filter { $0.organization.itemType.isActionable }.count, 3)
        XCTAssertTrue(independent.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("reception desk") })

        for source in ["Keep both accessible.", "Pay rent tomorrow. Keep both visible.",
                       "Pay rent. Buy milk. Call Amy. Keep both visible."] {
            XCTAssertTrue(ThoughtExtractionEngine.extractWithRules(source).items.contains {
                $0.needsReview && $0.sourceQuote.contains("both")
            }, source)
        }
        let reported = ThoughtExtractionEngine.extractWithRules(roots
            + "The supervisor said, 'Keep both visible.'").items
        XCTAssertEqual(reported.count, 3)
        XCTAssertTrue(reported.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("supervisor") })
    }

    func testExplicitSchedulingComparisonExcludesOnlyRejectedDay() {
        let previousZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Toronto")!
        defer { NSTimeZone.default = previousZone }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = NSTimeZone.default
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        for (source, day) in [("Call Amy Friday instead of tomorrow", 9),
                              ("Call Amy tomorrow instead of Friday", 6),
                              ("Call Amy on October ninth instead of tomorrow", 9)] {
            let item = ThoughtExtractionEngine.extractWithRules(source, referenceDate: anchor, calendar: calendar).items.first
            XCTAssertEqual(item?.organization.temporalIntent.day, CalendarDay(year: 2026, month: 10, day: day), source)
        }
        let object = ThoughtExtractionEngine.extractWithRules("Buy milk instead of bread tomorrow", referenceDate: anchor, calendar: calendar).items
        XCTAssertEqual(object.first?.organization.temporalIntent.day, CalendarDay(year: 2026, month: 10, day: 6))
        let reference = ThoughtExtractionEngine.extractWithRules(
            "Pay rent tomorrow. It is the same payment task."
        ).items
        XCTAssertEqual(reference.count, 1)
        XCTAssertTrue(reference.first?.sourceQuote.contains("same payment task") == true)
        let ambiguous = ThoughtExtractionEngine.extractWithRules(
            "Pay rent tomorrow. Collect parcel Friday. It is the same task."
        ).items
        XCTAssertTrue(ambiguous.contains { $0.needsReview && $0.sourceQuote.contains("same task") })
    }

    func testUnpunctuatedOutputReferenceDoesNotOwnIndependentFactOrSpeech() {
        let cases: [(String, Int)] = [
            ("Print the report the first task still has no date", 1),
            ("Water the planter the details I just added belong with that first task they explain how a correct result would look", 1),
            ("Email Noor the form a fact I want to keep in the middle of this the cabinet is locked", 2)
        ]
        for (source, count) in cases {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, count, items.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertFalse(items.contains { $0.needsReview }, source)
        }
        let declared = ThoughtExtractionEngine.extractWithRules("Email Noor the form a fact I want to keep in the middle of this the cabinet is locked").items
        XCTAssertTrue(declared.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("cabinet") })
        XCTAssertFalse(declared.contains { $0.organization.itemType.isActionable && $0.sourceQuote.contains("cabinet") })
        let quotedFact = ThoughtExtractionEngine.extractWithRules("Tell Noor that a fact I want to keep the cabinet is locked").items
        XCTAssertEqual(quotedFact.count, 1)
        XCTAssertTrue(quotedFact.first?.organization.itemType.isActionable == true)
        let message = ThoughtExtractionEngine.extractWithRules("Tell Noor that the first task still has no date").items
        XCTAssertEqual(message.count, 1)
        XCTAssertTrue(message.first?.organization.itemType.isActionable == true)
        XCTAssertTrue(message.first?.sourceQuote.contains("first task") == true)
        let report = ThoughtExtractionEngine.extractWithRules("Pat said the details I just added belong with that first task").items
        XCTAssertEqual(report.count, 1)
        XCTAssertTrue(report.first?.organization.itemType == .note)
        let missing = ThoughtExtractionEngine.extractWithRules("the first task still has no date").items
        XCTAssertFalse(missing.isEmpty)
        XCTAssertTrue(missing.contains { $0.needsReview })
        let independent = ThoughtExtractionEngine.extractWithRules("Print the form the details I just added belong with that first task and call Lee").items
        XCTAssertEqual(independent.filter { $0.organization.itemType.isActionable }.count, 2)
    }

    func testOutputStateAndRetentionOnlyDescribeExistingIntentions() {
        let previousTaggerMode = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previousTaggerMode
            SentenceContextCache.invalidate()
        }
        for disablesTagger in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disablesTagger
            SentenceContextCache.invalidate()
            let metadata = "The first task still has no date, and the note above is still a Memory."
            XCTAssertEqual(RuleBasedThoughtExtractor.splitIndependentConjuncts(metadata), [metadata],
                "A complete output-state reference must reach ownership before generic coordination")
            let complete = ThoughtExtractionEngine.extractWithRules(
                "Print the form. Remember the cabinet is locked. Call Amy. The first task still has no date, and the note above is still a Memory. Do not lose this last obligation.").items
            XCTAssertEqual(complete.count, 3, complete.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(complete.allSatisfy { !$0.needsReview })
            XCTAssertTrue(complete.contains { $0.organization.itemType.isActionable && $0.sourceQuote.contains("Print") && $0.sourceQuote.contains("first task still") })
            XCTAssertTrue(complete.contains { $0.organization.itemType.isActionable && $0.sourceQuote.contains("Call Amy") && $0.sourceQuote.contains("last obligation") })
            let conflict = ThoughtExtractionEngine.extractWithRules(
                "Print the form tomorrow. The first task still has no date.").items
            XCTAssertTrue(conflict.contains { $0.needsReview })
            XCTAssertTrue(conflict.contains { $0.organization.dueDate != nil })
            let physical = ThoughtExtractionEngine.extractWithRules("Do not lose the passport.").items
            XCTAssertTrue(physical.contains { $0.sourceQuote.contains("passport") })
            let independent = ThoughtExtractionEngine.extractWithRules(
                "Print the form. Do not lose this last task and call Amy.").items
            XCTAssertTrue(independent.contains { $0.organization.itemType.isActionable && $0.sourceQuote.lowercased().contains("call amy") })
            let missing = ThoughtExtractionEngine.extractWithRules("Do not omit the final task.").items
            XCTAssertTrue(missing.contains { $0.needsReview })
            let ambiguousMemory = ThoughtExtractionEngine.extractWithRules(
                "Print the form. Remember the cabinet is locked. Remember the gate code is 3421. The first task still has no date, and the note above is still a Memory.").items
            XCTAssertTrue(ambiguousMemory.contains { $0.needsReview })
        }
    }

    func testOrdinalDetailsAndExplanationsRequireEstablishedOwner() {
        for (action, detail) in [
            ("Print the form.", "The requirements belong with the first task."),
            ("Call the caretaker.", "The context I gave goes with that first action."),
            ("Send the draft.", "The details we mentioned belong to this first task.")
        ] {
            let source = action + " " + detail + " They explain what a correct result would look like."
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, items.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(items.first?.sourceQuote.contains(detail) == true)
            XCTAssertTrue(items.first?.sourceQuote.contains("They explain") == true)
            XCTAssertFalse(items.first?.needsReview ?? true)
        }
        let independent = ThoughtExtractionEngine.extractWithRules(
            "Print the form. The details belong with the first task. Remember the cabinet is locked. Call Amy.").items
        XCTAssertEqual(independent.count, 3)
        XCTAssertTrue(independent.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("cabinet") })
        let missing = ThoughtExtractionEngine.extractWithRules(
            "Print the form. The details belong with the second task.").items
        XCTAssertTrue(missing.contains { $0.needsReview })
        let orphan = ThoughtExtractionEngine.extractWithRules(
            "Print the form. They explain what a correct result would look like.").items
        XCTAssertTrue(orphan.contains { $0.needsReview })
        let reported = ThoughtExtractionEngine.extractWithRules(
            "Print the form. Remember Pat said 'The details belong with the first task.'").items
        XCTAssertTrue(reported.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("Pat said") })
    }

    func testFactObjectFrameKeepsIndependentActionAndReportedSource() {
        for (frame, fact) in [
            ("Keep only this fact as a note, not a task: ", "The cabinet is locked."),
            ("Save that information as a memory: ", "The access code is 3421."),
            ("Retain the detail as a note, not a reminder: ", "Pat prefers green tea.")
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(frame + fact + " Email Lee the draft.").items
            XCTAssertEqual(items.count, 2, items.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(items.contains { $0.organization.itemType == .note && $0.sourceQuote.contains(fact) })
            XCTAssertTrue(items.contains { $0.organization.itemType.isActionable && $0.sourceQuote.contains("Email Lee") && !$0.sourceQuote.contains(fact) })
            XCTAssertTrue(items.allSatisfy { !$0.needsReview })
        }
        let own = ThoughtExtractionEngine.extractWithRules("Keep this fact as a note: I need to call Amy.").items
        XCTAssertTrue(own.contains { $0.organization.itemType.isActionable })
        let quoted = ThoughtExtractionEngine.extractWithRules("Remember Pat said 'Keep this fact as a note: the cabinet is locked.'").items
        XCTAssertTrue(quoted.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("Pat said") })
        XCTAssertFalse(quoted.contains { $0.organization.itemType.isActionable })
    }

    func testBriefHesitationsDoNotOwnFactsOrPhysicalInstructions() {
        for source in ["Print the form. Uh, one moment. Remember the gate code is 3421.",
                       "Call Amy. Well, let me get this down. Remember the cabinet is locked."] {
            let result = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(result.count, 2, result.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(result.allSatisfy { !$0.needsReview })
        }
        let physical = ThoughtExtractionEngine.extractWithRules("Get this down from the shelf.").items
        XCTAssertTrue(physical.contains { $0.organization.itemType.isActionable })
        let fact = ThoughtExtractionEngine.extractWithRules("Remember one moment of silence was observed at the meeting.").items
        XCTAssertTrue(fact.contains { $0.organization.itemType == .note })
        let commitment = ThoughtExtractionEngine.extractWithRules("One moment, I will print the form.").items
        XCTAssertTrue(commitment.contains { $0.organization.itemType.isActionable && $0.sourceQuote.contains("print") })
        let lone = ThoughtExtractionEngine.extractWithRules("Uh, one moment.").items
        XCTAssertTrue(lone.contains { $0.needsReview })
        let quote = ThoughtExtractionEngine.extractWithRules("Remember Pat said 'One moment. Let me get this down.'").items
        XCTAssertTrue(quote.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("Pat said") })
    }

    func testRecordingNarrationDoesNotInventTasksOrHideIndependentCommitments() {
        for source in [
            "I am pausing to think. Buy flour.",
            "I am trying to get my ideas down. Remember the gate code is 3421.",
            "A pause should not mean I have finished speaking. Call Amy.",
            "There is one final task coming next. The final task is this: Print the form."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, items.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertFalse(items.first?.needsReview ?? true)
        }
        let own = ThoughtExtractionEngine.extractWithRules(
            "I am pausing to think and I will print the form.").items
        XCTAssertTrue(own.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("print the form") })
        let fact = ThoughtExtractionEngine.extractWithRules(
            "Remember the interview pauses were awkward.").items
        XCTAssertTrue(fact.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("interview pauses") })
        let physical = ThoughtExtractionEngine.extractWithRules(
            "Take a pause before printing the form.").items
        XCTAssertTrue(physical.contains { $0.organization.itemType.isActionable })
        let missing = ThoughtExtractionEngine.extractWithRules(
            "There is one final obligation coming next.").items
        XCTAssertTrue(missing.contains { $0.needsReview })
        let alone = ThoughtExtractionEngine.extractWithRules("I am pausing to think.").items
        XCTAssertTrue(alone.contains { $0.needsReview && $0.sourceQuote.contains("pausing") })
    }

    func testAdditiveComponentDetailRequiresSameActAndUniqueOwner() {
        for source in [
            "Return the projector to Noor. The projector has the cable in its case; return that too.",
            "Bring the tent to Lee. The tent comes with the poles; bring those as well.",
            "Pack the camera bag. The camera bag contains a charger; pack that too."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, items.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(items.first?.organization.itemType.isActionable == true)
            XCTAssertFalse(items.first?.needsReview ?? true)
            XCTAssertTrue(items.first?.sourceQuote.contains("too") == true
                || items.first?.sourceQuote.contains("as well") == true)
        }
        let fact = ThoughtExtractionEngine.extractWithRules(
            "Return the projector to Noor. The projector has a cable in its case.").items
        XCTAssertEqual(fact.count, 2)
        let differentAct = ThoughtExtractionEngine.extractWithRules(
            "Return the projector to Noor. The projector has a cable in its case. Clean the cable.").items
        XCTAssertTrue(differentAct.contains { $0.organization.itemType.isActionable
            && $0.analysisText.contains("Clean the cable") })
        XCTAssertFalse(differentAct.first?.sourceQuote.contains("Clean the cable") ?? true)
        let ambiguous = ThoughtExtractionEngine.extractWithRules(
            "Return the projector to Noor. Return the projector to Lee. The projector has a cable in its case; return that too.").items
        XCTAssertTrue(ambiguous.contains { $0.needsReview && $0.sourceQuote.contains("return that too") })
        let reported = ThoughtExtractionEngine.extractWithRules(
            "Return the projector to Noor. The projector has a cable in its case. Lee said return that too.").items
        XCTAssertTrue(reported.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Lee said") })
    }

    func testDeterminedCopularFactDoesNotSwallowFollowingCommand() {
        for source in [
            "The east gate is locked and email Pat.",
            "The blue notebook is in the drawer and call Amy.",
            "Our spare key has a red tag and print the form."
        ] {
            let parts = RuleBasedThoughtExtractor.splitIndependentConjuncts(source)
            XCTAssertEqual(parts.count, 2, parts.joined(separator: " | "))
        }
        XCTAssertEqual(RuleBasedThoughtExtractor.splitIndependentConjuncts(
            "The blue notebook is red and green").count, 1)
        let reported = ThoughtExtractionEngine.extractWithRules(
            "Pat said the blue notebook is in the drawer and email Amy.").items
        XCTAssertFalse(reported.contains { $0.organization.itemType.isActionable })
        let quoted = ThoughtExtractionEngine.extractWithRules(
            "Remember Pat's words: 'The blue notebook is in the drawer and email Amy.'").items
        XCTAssertFalse(quoted.contains { $0.organization.itemType.isActionable })
    }

    func testFactObjectBeforeRetentionRelativeClauseOwnsItsContent() {
        for source in [
            "A fact I want to keep in the middle of this: The spare labels are in the envelope.",
            "One detail we need to remember: The access code is 4321.",
            "This note that I would like to preserve: The east gate is locked."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, source)
            XCTAssertEqual(items.first?.organization.itemType, .note, source)
            XCTAssertFalse(items.first?.needsReview ?? true, source)
            XCTAssertFalse(items.first?.analysisText.lowercased().contains("want to keep") ?? true)
        }
        let independent = ThoughtExtractionEngine.extractWithRules(
            "A fact I want to keep: The east gate is locked and email Pat.").items
        XCTAssertTrue(independent.contains { $0.organization.itemType == .note
            && $0.analysisText.contains("gate is locked") })
        XCTAssertTrue(independent.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("email pat") }, independent.map { "\($0.organization.itemType):\($0.analysisText):\($0.sourceQuote):review=\($0.needsReview)" }.joined(separator: " | ")
            + " bodyParts=" + RuleBasedThoughtExtractor.splitIndependentConjuncts("The east gate is locked and email Pat.").joined(separator: " / ")
            + " voice=" + String(describing: ClauseScope.read("The east gate is locked and email Pat.").act)
            + " left=" + String(describing: ActionabilityReader.read("The east gate is locked"))
            + " right=" + String(describing: ActionabilityReader.read("email Pat.")))
        let newFact = ThoughtExtractionEngine.extractWithRules(
            "Remember the workshop notes are useful. A fact I want to keep: The spare labels are in the drawer. That is where they are now.").items
        XCTAssertEqual(newFact.count, 2, newFact.map(\.sourceQuote).joined(separator: " | "))
        XCTAssertTrue(newFact.contains { $0.suggestedTitle?.contains("spare labels") == true
            && !$0.sourceQuote.contains("workshop notes") })
        let ownAction = ThoughtExtractionEngine.extractWithRules(
            "A fact I want to keep: I need to email Pat.").items
        XCTAssertTrue(ownAction.contains { $0.organization.itemType.isActionable })
        let realTask = ThoughtExtractionEngine.extractWithRules(
            "A task I want to keep: Check the west gate tomorrow.").items
        XCTAssertTrue(realTask.contains { $0.organization.itemType.isActionable })
        XCTAssertNil(PersonMentionResolver.primary(in: "The address should be sent as text"))
        XCTAssertEqual(PersonMentionResolver.primary(in: "Send Amy the address")?.label, "Amy")
    }

    func testPassiveResultDetailRequiresSameActAndUniqueObject() {
        for source in [
            "Send Priya the address. The address should be sent as text with a photo.",
            "Print the form. The form should be printed on blue paper.",
            "Write the report. The report must be written in plain language.",
            "Copy the recipe. The recipe needs to be copied using large lettering."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, items.map(\.sourceQuote).joined(separator: " | "))
            XCTAssertTrue(items.first?.organization.itemType.isActionable == true)
            XCTAssertFalse(items.first?.needsReview ?? true)
            XCTAssertTrue(items.first?.sourceQuote.contains("The") == true)
        }
        let differentAct = ThoughtExtractionEngine.extractWithRules(
            "Print the form. The form should be sent as text.").items
        XCTAssertEqual(differentAct.filter { $0.organization.itemType.isActionable }.count, 2)
        let ambiguous = ThoughtExtractionEngine.extractWithRules(
            "Send Pat the address. Send Lee the address. The address should be sent as text.").items
        XCTAssertTrue(ambiguous.contains { $0.needsReview && $0.sourceQuote.contains("should be sent") })
        let independent = ThoughtExtractionEngine.extractWithRules(
            "Print the form. The form should be printed on blue paper and email Pat. Remember the paper is in the drawer.").items
        XCTAssertTrue(independent.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("email pat") })
        XCTAssertTrue(independent.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("paper is in the drawer") })
        let report = ThoughtExtractionEngine.extractWithRules(
            "Print the form. Pat said the form should be printed on blue paper.").items
        XCTAssertTrue(report.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Pat said") })
    }

    func testSharedShoppingListReferenceRequiresUniquePrecedingGroup() {
        let grouped = ThoughtExtractionEngine.extractWithRules(
            "Buy flour and yeast. Those items should be kept in a single shopping list.").items
        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped.first?.organization.itemType, .shopping)
        XCTAssertTrue(grouped.first?.sourceQuote.contains("single shopping list") == true)
        let independent = ThoughtExtractionEngine.extractWithRules(
            "Buy flour and yeast. They can go on the same shopping list and email Pat. Remember the flour tin is blue.").items
        XCTAssertTrue(independent.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("email pat") })
        XCTAssertTrue(independent.contains { $0.organization.itemType == .note
            && $0.analysisText.contains("tin is blue") })
        let ambiguous = ThoughtExtractionEngine.extractWithRules(
            "Buy flour at the bakery. Buy batteries at the hardware store. They can go on the same shopping list.").items
        XCTAssertTrue(ambiguous.contains { $0.needsReview
            && $0.sourceQuote.contains("same shopping list") })
        let wrongAntecedent = ThoughtExtractionEngine.extractWithRules(
            "Buy flour. Call Pat and Lee. They can go on the same shopping list.").items
        XCTAssertTrue(wrongAntecedent.contains { $0.needsReview
            && $0.sourceQuote.contains("same shopping list") })
        let report = ThoughtExtractionEngine.extractWithRules(
            "Buy flour. Pat said they can go on the same shopping list.").items
        XCTAssertTrue(report.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Pat said") })
    }

    func testPairedOutputStatementDoesNotAbsorbIndependentConjuncts() {
        let roots = "Pay the invoice tomorrow. Collect the parcel Friday. "
        let correctIntermediate = ThoughtExtractionEngine.extractWithRules(
            roots + "Email Mara tomorrow."
        ).items
        XCTAssertEqual(correctIntermediate.count, 3)
        for suffix in ["These are two tasks for different purposes, and email Mara tomorrow.",
                       "these are two tasks for different purposes, and email Mara tomorrow.",
                       "These are two tasks, and the café opens at nine.",
                       "They should not be merged as tasks, and email Mara tomorrow."] {
            let conjunctions = RuleBasedThoughtExtractor.splitIndependentConjuncts(suffix)
            let diagnostic = XCTAttachment(string: "Source: " + suffix
                + "\nConjuncts: " + conjunctions.joined(separator: " | ")
                + "\nReadings: " + conjunctions.map {
                    "\($0):\(ActionabilityReader.read($0)) body=\(ActionabilityReader.actionBody($0))"
                }.joined(separator: " | ")
                + "\nMatrix: \(ClauseScope.read(suffix).act)")
            diagnostic.name = "Paired-reference actual conjunction differential"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            let items = ThoughtExtractionEngine.extractWithRules(roots + suffix).items
            XCTAssertEqual(items.count, 3, suffix)
            if suffix.contains("email") {
                XCTAssertTrue(items.contains { $0.organization.itemType.isActionable
                    && $0.analysisText.localizedCaseInsensitiveContains("email Mara") }, suffix)
            } else {
                XCTAssertTrue(items.contains { $0.organization.itemType == .note
                    && $0.analysisText.localizedCaseInsensitiveContains("café opens") }, suffix)
            }
            XCTAssertFalse(items.contains(where: \.needsReview), suffix)
        }
    }

    func testSameNounReferenceRequiresUniqueDirectActionObject() {
        let grounded = ThoughtExtractionEngine.extractWithRules(
            "Return the red folder tomorrow. Then bring the same folder Friday."
        ).items
        XCTAssertEqual(grounded.count, 2)
        XCTAssertTrue(grounded[1].analysisText.contains("red folder"))
        XCTAssertTrue(grounded[1].sourceQuote.contains("same folder"))
        XCTAssertFalse(grounded[1].needsReview)
        for source in ["Bring the same folder Friday.",
                       "Return the red folder. Return the blue folder. Bring the same folder Friday.",
                       "Maya said to return the red folder. Bring the same folder Friday."] {
            XCTAssertTrue(ThoughtExtractionEngine.extractWithRules(source).items.contains {
                $0.needsReview && $0.sourceQuote.contains("same folder")
            }, source)
        }
    }

    func testCaptureCommentaryRequiresAnOwnedAntecedent() {
        let lastStep = ThoughtExtractionEngine.extractWithRules(
            "Pay rent tomorrow. Call Maya Friday. "
                + "Please don't lose the last step because of this story."
        ).items
        XCTAssertEqual(lastStep.count, 2)
        XCTAssertTrue(lastStep.allSatisfy { $0.organization.itemType.isActionable })
        XCTAssertTrue(lastStep[1].sourceQuote.contains("last step"))

        let uniqueMemory = ThoughtExtractionEngine.extractWithRules(
            "The café has blue tiles. I am repeating it because I don't want to lose it."
        ).items
        XCTAssertEqual(uniqueMemory.count, 1)
        XCTAssertEqual(uniqueMemory[0].organization.itemType, .note)
        XCTAssertTrue(uniqueMemory[0].sourceQuote.contains("repeating it"))

        let ambiguous = ThoughtExtractionEngine.extractWithRules(
            "The café has blue tiles. The station has a red clock. "
                + "I am repeating it because I don't want to lose it."
        ).items
        XCTAssertTrue(ambiguous.contains { $0.needsReview
            && $0.sourceQuote.contains("repeating it") })
        XCTAssertFalse(ambiguous.contains { $0.organization.itemType.isActionable })

        let interveningAction = ThoughtExtractionEngine.extractWithRules(
            "The café has blue tiles. Call Maya tomorrow. "
                + "I am repeating it because I don't want to lose it."
        ).items
        XCTAssertTrue(interveningAction.contains { $0.needsReview
            && $0.sourceQuote.contains("repeating it") })
        XCTAssertTrue(interveningAction.contains { $0.organization.itemType.isActionable
            && $0.analysisText.contains("Call Maya") })

        let physicalKey = ThoughtExtractionEngine.extractWithRules(
            "Please don't lose the house key"
        ).items
        XCTAssertEqual(physicalKey.count, 1)
        XCTAssertTrue(physicalKey[0].sourceQuote.contains("house key"))
    }

    func testExplicitOutputRoutingCommentaryHasOneMemoryOwner() {
        let named = ThoughtExtractionEngine.extractWithRules(
            "The old cinema had green seats. Call Omar Friday. "
                + "I'm probably overexplaining, but the cinema detail is a memory, "
                + "not an instruction to contact them."
        ).items
        XCTAssertEqual(named.count, 2)
        XCTAssertTrue(named.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("cinema detail is a memory") })
        XCTAssertTrue(named.contains { $0.organization.itemType.isActionable
            && $0.analysisText.contains("Call Omar") })

        let past = ThoughtExtractionEngine.extractWithRules(
            "We walked uphill past a bakery and found a bookshop. "
                + "Send the owner a thank-you card Friday. "
                + "I do not need tasks for walking uphill or finding the shop."
        ).items
        XCTAssertTrue(past.contains { $0.sourceQuote.contains("do not need tasks") })
        XCTAssertTrue(past.contains { $0.organization.itemType.isActionable
            && $0.analysisText.contains("Send the owner") })

        let competing = ThoughtExtractionEngine.extractWithRules(
            "The cinema had green seats. The cinema had a moon logo. "
                + "The cinema detail is a memory, not an instruction."
        ).items
        XCTAssertTrue(competing.contains { $0.needsReview
            && $0.sourceQuote.contains("cinema detail") })
        let actionWithSameSubject = ThoughtExtractionEngine.extractWithRules(
            "The cinema had green seats. Contact the cinema Friday. "
                + "The cinema detail is a memory, not an instruction."
        ).items
        XCTAssertTrue(actionWithSameSubject.contains { $0.needsReview
            && $0.sourceQuote.contains("cinema detail") })

        let independent = ThoughtExtractionEngine.extractWithRules(
            "The cinema has green seats. The cinema also has a moon logo."
        ).items
        XCTAssertTrue(independent.contains { $0.sourceQuote.contains("moon logo") })
        let simple = ThoughtExtractionEngine.extractWithRules("Buy milk Friday.").items
        XCTAssertEqual(simple.count, 1)
        XCTAssertTrue(simple[0].organization.itemType.isActionable)
    }

    func testMixedDestinationRecapOwnsItsSourceWithoutAnotherRow() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Call Maya tomorrow. The key is in the drawer. "
                + "These details have different destinations."
        ).items
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].organization.itemType.isActionable)
        XCTAssertEqual(result[1].organization.itemType, .note)
        XCTAssertTrue(result.allSatisfy {
            $0.sourceQuote.contains("different destinations")
        })

        let literal = ThoughtExtractionEngine.extractWithRules(
            "These details have different destinations in the shipping ledger"
        ).items
        XCTAssertEqual(literal.count, 1)
        XCTAssertEqual(literal[0].organization.itemType, .note)
    }

    func testExposedRamblingProposalKeepsUnresolvedRecapVisibleWithoutCancellation() {
        let source = "This is one of those half-formed thoughts. The park path behind the "
            + "school gets beautiful light just after rain, and that could be a nice "
            + "setting for a photo series. I could ask someone to join me, maybe. "
            + "No, don't make an outing for me yet; I am just keeping the image and "
            + "the idea that the series could follow the same path in four seasons. "
            + "I am repeating it because I don't want to lose it."
        let result = ThoughtExtractionEngine.extractWithRules(source)
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertTrue(result.items.contains { $0.needsReview
            && $0.sourceQuote.contains("I am repeating it") })
        XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("I am repeating it") })
    }

    func testExposedEndStepAndConditionalFactKeepTheirSeparateOwners() {
        let endStep = "At the start of this recording I want to keep a detail: the old "
            + "cinema used velvet green seats and projected a little moon logo "
            + "before each film. Now my mind is on Monday's screening, and in the "
            + "middle of the week I need to email the venue about wheelchair "
            + "seating and send Omar the ticket link. I'm probably overexplaining, "
            + "but the cinema detail is a memory, not an instruction to contact "
            + "them. Right at the end: bring the portable charger on Monday. "
            + "Please don't lose the last step because of the story."
        let rows = ThoughtExtractionEngine.extractWithRules(endStep).items
        XCTAssertTrue(rows.contains { $0.organization.itemType.isActionable
            && $0.analysisText.contains("bring the portable charger")
            && $0.sourceQuote.contains("last step") })
        XCTAssertFalse(rows.contains { $0.analysisText.hasPrefix("Please don't lose") })

        let conditional = "Beginning: pay the water bill tomorrow. I'm going to "
            + "talk around the topic now: the paper statement is in the drawer "
            + "below the kettle, which might be useful if I have to find it "
            + "again. Midway, call Tessa to ask how her recovery is going."
        let mixed = ThoughtExtractionEngine.extractWithRules(conditional).items
        XCTAssertTrue(mixed.contains { $0.organization.itemType == .note
            && $0.analysisText.contains("paper statement") })
        XCTAssertTrue(mixed.contains { $0.organization.itemType.isActionable
            && $0.analysisText.contains("pay the water bill") })
    }

    func testCountedOutputRequestOwnsItsFragments() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "Pay rent tomorrow. Call Dana Friday. Lock the shed Sunday. "
                + "I want the first, middle, and last action kept, plus the note."
        ).items
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable })
        XCTAssertTrue(items.last?.sourceQuote.contains("last action kept") == true)
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(
            "I want the first edition and the last edition of the book"
        ).items.count, 1)
    }

    func testExplicitSharedContextDoesNotBecomeAnExecutableEvent() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "Photograph the wall. Clear the shelf. "
                + "The inspection is at three, which is context for those steps."
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable })
        XCTAssertTrue(items.allSatisfy { $0.organization.dueDate == nil })
        XCTAssertTrue(items.allSatisfy { $0.sourceQuote.contains("inspection is at three") })
        XCTAssertTrue(items.allSatisfy { $0.rawQuote.contains("inspection is at three") })

        let otherEvent = ThoughtExtractionEngine.extractWithRules(
            "Print the labels. Pack the sample box. "
                + "The audit is at ten, which is context for those steps."
        ).items
        XCTAssertEqual(otherEvent.count, 2)
        XCTAssertTrue(otherEvent.allSatisfy { $0.sourceQuote.contains("audit is at ten") })
        XCTAssertTrue(otherEvent.allSatisfy { $0.organization.dueDate == nil })

        let interrupted = ThoughtExtractionEngine.extractWithRules(
            "Print the labels. Remember the north wall is damp. Pack the sample box. "
                + "The audit is at ten, which is context for those steps."
        ).items
        XCTAssertTrue(interrupted.contains { $0.needsReview
            && $0.sourceQuote.contains("audit is at ten") })
        XCTAssertFalse(interrupted.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("audit is at ten") })

        let event = ThoughtExtractionEngine.extractWithRules(
            "The inspection is at three"
        ).items
        XCTAssertEqual(event.count, 1)
        XCTAssertFalse(event[0].needsReview)
        XCTAssertTrue(event[0].sourceQuote.contains("inspection is at three"))
    }

    func testDefiniteMemoryDetailReturnsToUniqueOwnerAcrossAnAction() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "I found an old camera in the attic. Send Lee the invoice tomorrow. "
                + "Back to the camera, the camera has a cracked leather case."
        ).items
        XCTAssertEqual(items.count, 2)
        let memory = items.first { $0.organization.itemType == .note }
        XCTAssertTrue(memory?.sourceQuote.contains("cracked leather case") == true)
        XCTAssertTrue(memory?.sourceQuote.contains("…") == true)
        XCTAssertFalse(memory?.sourceQuote.contains("Send Lee") == true)
        XCTAssertTrue(memory?.rawQuote.contains("cracked leather case") == true)
        XCTAssertTrue(items.contains { $0.organization.itemType.isActionable })

        // Same referent, different speech act: a possible project is a new
        // idea, and an imperative remains an action.
        let proposal = ThoughtExtractionEngine.extractWithRules(
            "I found an old camera in the attic. Send Lee the invoice tomorrow. "
                + "The camera could become an art project."
        ).items
        XCTAssertEqual(proposal.count, 3)
        let action = ThoughtExtractionEngine.extractWithRules(
            "I found an old camera in the attic. Clean the camera tomorrow."
        ).items
        XCTAssertEqual(action.count, 2)
        XCTAssertTrue(action.last?.organization.itemType.isActionable == true)
    }

    func testDefiniteMemoryDetailDoesNotGuessBetweenTwoOwners() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "The camera in the attic was red. Send Lee the invoice tomorrow. "
                + "Another memory: the camera in the cellar was blue. "
                + "Call Pat on Friday. Back to the camera, the camera had a leather case."
        ).items
        XCTAssertEqual(items.count, 5)
        XCTAssertTrue(items.last?.sourceQuote.contains("leather case") == true)
        XCTAssertFalse(items.first?.sourceQuote.contains("leather case") == true)

        let adjacentAmbiguity = ThoughtExtractionEngine.extractWithRules(
            "The camera in the attic was red. Send Lee the invoice tomorrow. "
                + "Another memory: the camera in the cellar was blue. "
                + "The camera had a leather case."
        ).items
        XCTAssertEqual(adjacentAmbiguity.count, 4)
        XCTAssertFalse(adjacentAmbiguity[2].sourceQuote.contains("leather case"))

        let newMemory = ThoughtExtractionEngine.extractWithRules(
            "I found an old camera in the attic. Another memory: the camera was a gift."
        ).items
        XCTAssertEqual(newMemory.count, 2)

        let repeated = ThoughtExtractionEngine.extractWithRules(
            "The camera was red. The camera was red."
        ).items
        XCTAssertEqual(repeated.count, 2)
    }

    func testExposedLongCaptureMemoryOwnershipRegressions() {
        let atlas = ThoughtExtractionEngine.extractWithRules(
            "First, before I forget, submit the insurance claim by Wednesday. "
                + "Then a little background: the basement shelf got wet when a pipe dripped, "
                + "and I found the old family atlas there; the atlas has notes in my "
                + "grandfather's handwriting along the coast. Halfway through this thought, "
                + "I also need to ask Bea for the repair invoice. The rest is me wondering "
                + "whether that atlas could become a small family project. Finally, set "
                + "the dehumidifier timer tonight. I want the first, middle, and last action "
                + "kept, plus the atlas memory and idea."
        ).items
        XCTAssertTrue(atlas.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("found the old family atlas")
            && $0.sourceQuote.contains("grandfather's handwriting") })
        XCTAssertTrue(atlas.contains { $0.sourceQuote.contains("small family project")
            && !$0.sourceQuote.contains("grandfather's handwriting") })
        XCTAssertEqual(atlas.filter { $0.organization.itemType.isActionable }.count, 3)

        let porto = ThoughtExtractionEngine.extractWithRules(
            "This is mostly a memory: on the first morning in Porto we walked uphill "
                + "past a tiled bakery, got lost beside a small square, and found a bookshop "
                + "where the owner marked quiet places on our map. In the middle of the story "
                + "I remember one present obligation: send the owner a thank-you postcard "
                + "this week. I do not need tasks for walking uphill or finding the shop; "
                + "those already happened. The detail I most want at the end is that the "
                + "bookshop was called Papel Azul and had a blue door, so I can find it again."
        ).items
        if !porto.contains(where: { $0.organization.itemType == .note
            && $0.sourceQuote.contains("bookshop where the owner")
            && $0.sourceQuote.contains("Papel Azul") }) {
            XCTFail("Porto ownership rows: \(porto.map { "\($0.organization.itemType): \($0.sourceQuote)" })")
        }
        XCTAssertTrue(porto.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("thank-you postcard") },
            "Postcard rows: \(porto.map { "\($0.organization.itemType): \($0.sourceQuote)" })")
        // The negative capture directive is still visible as source and may
        // not create a walking/finding task. It is not yet folded into the
        // original Memory on every platform.
        XCTAssertTrue(porto.contains { $0.sourceQuote.contains("do not need tasks") })
        XCTAssertFalse(porto.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("walking uphill") })
    }

    func testCurrentCommitmentFrameSeparatesTaskFromMemory() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "The orchard had a stone wall and a wooden gate. "
                + "I remember one current obligation: send Mara the photo tomorrow."
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map { $0.organization.itemType.isActionable }, [false, true])
        XCTAssertTrue(items[1].sourceQuote.contains("current obligation"))
        XCTAssertTrue(items[1].analysisText.contains("send Mara"))

        let reported = ThoughtExtractionEngine.extractWithRules(
            "Mara said she had a current obligation: send the photo tomorrow."
        ).items
        XCTAssertFalse(reported.contains { $0.organization.itemType.isActionable })
        let past = ThoughtExtractionEngine.extractWithRules(
            "I remembered one past obligation: send the photo yesterday."
        ).items
        XCTAssertFalse(past.contains { $0.organization.itemType.isActionable })

        let speakerPivot = ThoughtExtractionEngine.extractWithRules(
            "Mara said the photo is ready; I remember one current obligation: "
                + "send it to Lee tomorrow."
        ).items
        XCTAssertEqual(speakerPivot.count, 2)
        XCTAssertEqual(speakerPivot.map { $0.organization.itemType.isActionable },
                       [false, true])
        let reportedFirstPerson = ThoughtExtractionEngine.extractWithRules(
            "Mara said I remember one current obligation: send it to Lee tomorrow."
        ).items
        XCTAssertFalse(reportedFirstPerson.contains {
            $0.organization.itemType.isActionable
        })
    }

    func testCountedGroupDeadlineOwnsDistinctActionsAndExactSource() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let referenceDate = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 10
        ))!
        func extract(_ speech: String) -> [ExtractedThought] {
            ThoughtExtractionEngine.extractWithRules(
                speech, referenceDate: referenceDate, calendar: calendar
            ).items
        }
        let grant = extract(
            "At the end of the month I am submitting the grant application. "
                + "For that same application, ask Dev for the budget figures, get Lucia "
                + "to read the summary, and upload the signed consent form. The grant "
                + "office prefers PDFs smaller than ten megabytes; keep that as reference "
                + "information for future applications too. I need all three steps done "
                + "before the month closes, even though I only said the deadline once."
        )
        XCTAssertEqual(grant.count, 4)
        let actions = grant.filter { $0.organization.itemType.isActionable }
        XCTAssertEqual(actions.count, 3)
        XCTAssertTrue(actions.allSatisfy { $0.organization.temporalIntent.day
            == CalendarDay(year: 2026, month: 8, day: 31) })
        XCTAssertTrue(actions.allSatisfy { $0.sourceQuote.contains("grant application")
            && $0.sourceQuote.contains("all three steps")
            && $0.sourceQuote.contains("…") })
        XCTAssertTrue(grant.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("PDFs smaller than ten megabytes") })
        XCTAssertFalse(grant.contains(where: \.needsReview))

        let direct = extract(
            "Buy milk. The shop closes at six. Call Sam. "
                + "I need all two tasks done by Friday."
        )
        XCTAssertEqual(direct.count, 3)
        XCTAssertEqual(direct.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertTrue(direct.filter { $0.organization.itemType.isActionable }
            .allSatisfy { $0.organization.temporalIntent.day
                == CalendarDay(year: 2026, month: 8, day: 7) })
        XCTAssertTrue(direct.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("shop closes") })

        let override = extract(
            "Buy milk Tuesday. Call Sam. I need all two tasks done by Friday."
        )
        XCTAssertEqual(override.count, 2)
        XCTAssertEqual(override[0].organization.temporalIntent.day,
                       CalendarDay(year: 2026, month: 8, day: 4))
        XCTAssertEqual(override[1].organization.temporalIntent.day,
                       CalendarDay(year: 2026, month: 8, day: 7))

        let mismatch = extract(
            "Buy milk. Call Sam. I need all three tasks done by Friday."
        )
        XCTAssertEqual(mismatch.count, 3)
        XCTAssertTrue(mismatch.last?.needsReview == true)
        XCTAssertTrue(mismatch.prefix(2).allSatisfy { $0.organization.dueDate == nil })

        let competingGroups = extract(
            "Buy milk. Call Sam. I need all two tasks done by Friday. "
                + "Email Lee. Pay rent. I need all two tasks done by Saturday."
        )
        XCTAssertEqual(competingGroups.count, 5)
        XCTAssertEqual(competingGroups[0].organization.temporalIntent.day,
                       CalendarDay(year: 2026, month: 8, day: 7))
        XCTAssertTrue(competingGroups.last?.needsReview == true)
        XCTAssertTrue(competingGroups[2..<4].allSatisfy {
            $0.organization.dueDate == nil
        })

        let reported = extract(
            "Mara said all two tasks are due by Friday. Buy milk. Call Sam."
        )
        XCTAssertEqual(reported.count, 3)
        XCTAssertTrue(reported.dropFirst().allSatisfy {
            $0.organization.dueDate == nil
        })
        let completed = extract(
            "Buy milk. Call Sam. All two tasks were done by Friday."
        )
        XCTAssertEqual(completed.count, 3)
        XCTAssertTrue(completed.prefix(2).allSatisfy {
            $0.organization.dueDate == nil
        })

        let short = extract("Buy milk tomorrow.")
        XCTAssertEqual(short.count, 1)
        XCTAssertEqual(short[0].organization.temporalIntent.day,
                       CalendarDay(year: 2026, month: 8, day: 4))
    }

    func testExplicitEventContextOwnsSeparateActionsWithoutChangingTheirDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let referenceDate = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 10
        ))!
        func extract(_ speech: String) -> [ExtractedThought] {
            ThoughtExtractionEngine.extractWithRules(
                speech, referenceDate: referenceDate, calendar: calendar
            ).items
        }
        let fair = extract(
            "Friday is the school fair, and I want everything tied to that event "
                + "without dropping separate jobs. Thursday evening bake the oat cookies "
                + "and charge the camera. Friday morning bring the raffle tickets, the "
                + "cookie box, and the camera to school. After the fair, send the photos "
                + "to the parent group. The date and event are shared context, but "
                + "baking, charging, bringing, and sending are different actions."
        )
        XCTAssertEqual(fair.count, 4, "\(fair.map { "\($0.organization.itemType): \($0.sourceQuote)" })")
        XCTAssertTrue(fair.allSatisfy { $0.organization.itemType.isActionable
            && !$0.needsReview && $0.sourceQuote.contains("school fair")
            && $0.sourceQuote.contains("shared context") })
        XCTAssertEqual(fair[0].organization.temporalIntent.day,
                       CalendarDay(year: 2026, month: 8, day: 6))
        XCTAssertEqual(fair[1].organization.temporalIntent.day,
                       CalendarDay(year: 2026, month: 8, day: 6))
        XCTAssertEqual(fair[2].organization.temporalIntent.day,
                       CalendarDay(year: 2026, month: 8, day: 7))
        XCTAssertNil(fair[3].organization.dueDate)

        let ordinaryFact = extract(
            "Friday is the school fair. Bake cookies. Charge the camera."
        )
        XCTAssertTrue(ordinaryFact.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("school fair") })

        let reportedDirective = extract(
            "Friday is the school fair. Maya said everything should be tied to "
                + "that event. Bake cookies. Charge the camera. The date and event "
                + "are shared context, but baking and charging are different actions."
        )
        XCTAssertTrue(reportedDirective.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Maya said") })
        XCTAssertTrue(reportedDirective.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("school fair") })

        let competingEvents = extract(
            "Friday is the school fair. Saturday is the fundraiser, and I want "
                + "everything tied to that event without merging the jobs. "
                + "Bake cookies and charge the camera. Bring the raffle tickets "
                + "and send the photos. The date and event are shared context, "
                + "but baking, charging, bringing, and sending are different actions."
        )
        XCTAssertTrue(competingEvents.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("school fair") })
        XCTAssertFalse(competingEvents.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("school fair") })
        XCTAssertEqual(competingEvents.filter { $0.organization.itemType.isActionable }.count, 4)
        XCTAssertTrue(competingEvents.filter { $0.organization.itemType.isActionable }
            .allSatisfy { $0.sourceQuote.contains("Saturday is the fundraiser") })

        let unrelated = extract(
            "Friday is the school fair. I want everything tied to that event. "
                + "Bake cookies. The cafeteria serves soup. Charge the camera. "
                + "The date and event are shared context, but baking and charging "
                + "are different actions."
        )
        XCTAssertTrue(unrelated.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("cafeteria serves soup") })
        XCTAssertTrue(unrelated.contains(where: \.needsReview))
        XCTAssertFalse(unrelated.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("cafeteria serves soup") })
    }

    func testExplicitExplanationHasUniqueFactAndActionOwners() {
        let visit = ThoughtExtractionEngine.extractWithRules(
            "For Amira's visit next Tuesday, wash the guest towels, put fresh "
                + "sheets on the bed, and check that the spare room lamp works. "
                + "She is allergic to lavender, so remember that as a lasting "
                + "fact about her. Pick up unscented soap before she arrives. "
                + "The allergy explains the soap choice; I want the fact retained, "
                + "not a free-standing reminder about lavender."
        ).items
        XCTAssertEqual(visit.count, 5)
        XCTAssertEqual(visit.filter { $0.organization.itemType.isActionable }.count, 4)
        XCTAssertTrue(visit.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("allergic to lavender")
            && $0.sourceQuote.contains("allergy explains") })
        XCTAssertTrue(visit.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("unscented soap")
            && $0.sourceQuote.contains("allergy explains") })
        XCTAssertFalse(visit.contains(where: \.needsReview))

        let other = ThoughtExtractionEngine.extractWithRules(
            "The winter storm is coming. Buy storm shutters. "
                + "The storm explains the shutters choice; keep that fact as reference."
        ).items
        XCTAssertEqual(other.count, 2)
        XCTAssertTrue(other.allSatisfy { $0.sourceQuote.contains("storm explains") })

        let standalone = ThoughtExtractionEngine.extractWithRules(
            "The storm explains the shutters choice."
        ).items
        XCTAssertEqual(standalone.count, 1)
        XCTAssertEqual(standalone[0].organization.itemType, .note)

        let reported = ThoughtExtractionEngine.extractWithRules(
            "Maya said the storm explains the shutters choice; keep that fact "
                + "as reference. Buy storm shutters."
        ).items
        XCTAssertTrue(reported.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Maya said") })
        XCTAssertFalse(reported.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("Maya said") })

        let laterReport = ThoughtExtractionEngine.extractWithRules(
            "The winter storm is coming. Buy shutters. "
                + "The storm explains the shutters choice. "
                + "Maya said keep that fact as reference."
        ).items
        XCTAssertFalse(laterReport.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("Maya said") })
        XCTAssertTrue(laterReport.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Maya said") })

        let twoActions = ThoughtExtractionEngine.extractWithRules(
            "The winter storm is coming. Buy shutters for the garage. "
                + "Buy shutters for the cabin. The storm explains the shutters "
                + "choice; keep that fact as reference."
        ).items
        XCTAssertTrue(twoActions.contains(where: \.needsReview))
        XCTAssertFalse(twoActions.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("storm explains") })
    }

    func testPreRowProjectionHoldsConflictingSuppressionInEitherEdgeOrder() {
        let rows = ThoughtExtractionEngine.extractWithRules(
            "The ferry leaves Friday at nine. Buy snacks. Pack bags."
        ).items
        XCTAssertEqual(rows.count, 3)
        XCTAssertFalse(rows.contains(where: \.needsReview))

        let first = RuleBasedThoughtExtractor.GroupContextPlan.Edge(
            claimIndex: 0, sourceIndices: [0], targetIndices: [1],
            kind: .captureDiscourse
        )
        let second = RuleBasedThoughtExtractor.GroupContextPlan.Edge(
            claimIndex: 0, sourceIndices: [0], targetIndices: [2],
            kind: .captureDiscourse
        )
        for edges in [[first, second], [second, first]] {
            var plan = RuleBasedThoughtExtractor.GroupContextPlan()
            plan.edges = edges
            let projected = RuleBasedThoughtExtractor.applyingGroupContextPlan(
                plan, to: rows, calendar: .current
            )
            XCTAssertEqual(projected.count, 3)
            XCTAssertTrue(projected[0].needsReview)
            XCTAssertFalse(projected[1].sourceQuote.contains("ferry leaves"))
            XCTAssertFalse(projected[2].sourceQuote.contains("ferry leaves"))
        }

        var sharedExplanation = RuleBasedThoughtExtractor.GroupContextPlan()
        sharedExplanation.edges = [.init(
            claimIndex: 0, sourceIndices: [0], targetIndices: [1, 2],
            kind: .explanation,
            sourceOccurrenceIDs: rows[0].sourceUnitIDs,
            targetOccurrenceIDs: rows[1].sourceUnitIDs.union(rows[2].sourceUnitIDs)
        )]
        var staleRows = rows
        staleRows[2].sourceUnitIDs.insert(100_000)
        let declined = RuleBasedThoughtExtractor.applyingGroupContextPlan(
            sharedExplanation, to: staleRows, calendar: .current)
        XCTAssertEqual(declined.count, 3)
        XCTAssertTrue(declined[0].needsReview)
        XCTAssertEqual(declined[1].sourceQuote, rows[1].sourceQuote)
        XCTAssertEqual(declined[2].sourceQuote, rows[2].sourceQuote)
        let explained = RuleBasedThoughtExtractor.applyingGroupContextPlan(
            sharedExplanation, to: rows, calendar: .current
        )
        XCTAssertEqual(explained.count, 2)
        XCTAssertTrue(explained.allSatisfy {
            !$0.needsReview && $0.sourceQuote.contains("ferry leaves")
        })

        var retained = RuleBasedThoughtExtractor.GroupContextPlan()
        retained.edges = [first, second].map { edge in
            .init(claimIndex: edge.claimIndex, sourceIndices: edge.sourceIndices,
                  targetIndices: edge.targetIndices, kind: .eventReference)
        }
        let referenced = RuleBasedThoughtExtractor.applyingGroupContextPlan(
            retained, to: rows, calendar: .current
        )
        XCTAssertEqual(referenced.count, 3)
        XCTAssertFalse(referenced.contains(where: \.needsReview))
        XCTAssertTrue(referenced.dropFirst().allSatisfy {
            $0.sourceQuote.contains("ferry leaves")
        })

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let friday = CalendarDay(year: 2026, month: 8, day: 7)
        let saturday = CalendarDay(year: 2026, month: 8, day: 8)
        var competingDates = RuleBasedThoughtExtractor.GroupContextPlan()
        competingDates.edges = [
            .init(claimIndex: 0, sourceIndices: [0], targetIndices: [1],
                  kind: .deadline(friday.startOfDay(in: calendar)!,
                                  TemporalIntent(kind: .dateOnly, day: friday))),
            .init(claimIndex: 2, sourceIndices: [2], targetIndices: [1],
                  kind: .deadline(saturday.startOfDay(in: calendar)!,
                                  TemporalIntent(kind: .dateOnly, day: saturday)))
        ]
        let dated = RuleBasedThoughtExtractor.applyingGroupContextPlan(
            competingDates, to: rows, calendar: calendar
        )
        XCTAssertEqual(dated.count, 3)
        XCTAssertTrue(dated[1].needsReview)
        XCTAssertNil(dated[1].organization.dueDate)
        XCTAssertFalse(dated[1].sourceQuote.contains("ferry leaves"))
    }

    func testTwoReminderDescriptionsBelongToNamedEarlierTasks() {
        let source = "Tomorrow at nine remind me to phone the bike shop, and at three remind me to collect the repaired wheel. "
            + "Both are tomorrow, but they are not the same event. "
            + "The first is a phone call to check it is ready; the second is the actual collection."
        let rows = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(rows.count, 2, rows.map { $0.suggestedTitle ?? $0.analysisText }.joined(separator: " | "))
        XCTAssertTrue(rows.contains { $0.sourceQuote.contains("The first is a phone call")
            && $0.analysisText.localizedCaseInsensitiveContains("phone the bike shop") })
        XCTAssertTrue(rows.contains { $0.sourceQuote.contains("the second is the actual collection")
            && $0.analysisText.localizedCaseInsensitiveContains("collect the repaired wheel") })

        let independent = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow at nine remind me to phone the bike shop, and at three remind me to collect the wheel. "
                + "Also email Asha the receipt. Also buy eggs."
        ).items
        XCTAssertTrue(independent.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("email Asha") })
        XCTAssertTrue(independent.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("buy eggs") })

        let noPunctuation = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow at nine remind me to phone the bike shop and at three remind me to collect the wheel. "
                + "Both are tomorrow but they are not the same event also email Asha the receipt"
        ).items
        XCTAssertTrue(noPunctuation.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("email Asha") },
            noPunctuation.map(\.analysisText).joined(separator: " | "))
    }

    func testNamedShoppingAndCallCommentaryDoesNotBecomeAnotherTask() {
        let shopping = ThoughtExtractionEngine.extractWithRules(
            "I also need oat milk and eggs. They can go on the same shopping list. "
                + "This is one trip, not a separate reminder for each shop, and I have not chosen a shopping time. "
                + "Also call Maya tomorrow."
        ).items
        XCTAssertFalse(shopping.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("one trip") })
        XCTAssertTrue(shopping.contains { $0.organization.itemType == .shopping
            && $0.sourceQuote.localizedCaseInsensitiveContains("one trip") })
        XCTAssertTrue(shopping.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("call Maya") })

        let call = ThoughtExtractionEngine.extractWithRules(
            "Call the dentist tomorrow to ask whether I can move my appointment. "
                + "The call is the thing I need to remember."
        ).items
        XCTAssertEqual(call.filter { $0.organization.itemType.isActionable }.count, 1)
        XCTAssertTrue(call.first { $0.organization.itemType.isActionable }?
            .sourceQuote.localizedCaseInsensitiveContains("thing I need to remember") == true)

        let ambiguousCalls = ThoughtExtractionEngine.extractWithRules(
            "Call Maya tomorrow. Call Omar tomorrow. The call is the thing I need to remember."
        ).items
        XCTAssertTrue(ambiguousCalls.contains { $0.needsReview
            && $0.sourceQuote.localizedCaseInsensitiveContains("thing I need to remember") })
    }

    func testDisclaimedReportedCommandHasOneSelectedMemoryOwner() {
        let exposed = ThoughtExtractionEngine.extractWithRules(
            "In the interview, Rosa said, 'Call me after lunch and send me the file tonight,' "
                + "but she was describing what her former manager used to demand, not asking "
                + "me to do either thing. What I actually want to keep is that Rosa prefers "
                + "advance notice before deadlines and dislikes last-minute requests. "
                + "I should email her the interview transcript on Monday for approval. "
                + "Her quoted line must stay in the source, not become two jobs."
        ).items
        XCTAssertEqual(exposed.count, 2, String(describing: exposed.map(\.sourceQuote)))
        XCTAssertEqual(exposed.filter { $0.organization.itemType == .note }.count, 1)
        XCTAssertEqual(exposed.filter { $0.organization.itemType.isActionable }.count, 1)
        XCTAssertTrue(exposed[0].sourceQuote.contains("Rosa said"))
        XCTAssertTrue(exposed[0].sourceQuote.contains("Rosa prefers advance notice"))
        XCTAssertTrue(exposed[1].sourceQuote.contains("email her the interview transcript"))
        XCTAssertFalse(exposed.contains(where: \.needsReview))

        let reported = "Rosa said, 'Call me after lunch.' She was describing "
            + "her manager's old demand, not asking me to do it. "
        let selected = ThoughtExtractionEngine.extractWithRules(
            reported + "What I really want to keep is that Rosa prefers early notice."
        ).items
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.organization.itemType, .note)
        XCTAssertTrue(selected.first?.sourceQuote.contains("Rosa said") == true)

        let additive = ThoughtExtractionEngine.extractWithRules(
            reported + "What I also want to keep is that Rosa prefers early notice."
        ).items
        XCTAssertEqual(additive.count, 2)
        XCTAssertTrue(additive.allSatisfy { $0.organization.itemType == .note })

        let differentOwner = ThoughtExtractionEngine.extractWithRules(
            reported + "What I actually want to keep is that Maya prefers early notice."
        ).items
        XCTAssertEqual(differentOwner.count, 2)
        XCTAssertTrue(differentOwner.allSatisfy { $0.organization.itemType == .note })

        let explicitlySavedQuote = ThoughtExtractionEngine.extractWithRules(
            "Rosa said, 'Call me after lunch.' She was describing her manager's old "
                + "demand, not asking me to do it; remember that quote. "
                + "What I actually want to keep is that Rosa prefers early notice."
        ).items
        XCTAssertEqual(explicitlySavedQuote.count, 3)
        XCTAssertTrue(explicitlySavedQuote.allSatisfy { $0.organization.itemType == .note })
        XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses(
            "Rosa said, 'Call me after lunch.' She was describing an old demand; remember that quote."
        ).count, 2)
        XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses(
            "Rosa said, 'Call me after lunch'; she said to remember that quote."
        ).count, 1)
    }
    func testIndependentActionConjunctDoesNotDependOnDeviceVerbTag() {
        let separate = ThoughtExtractionEngine.extractWithRules(
            "Buy milk and don't forget to call Mom"
        ).items
        XCTAssertEqual(separate.count, 2)
        XCTAssertTrue(separate.allSatisfy { $0.organization.itemType.isActionable })

        let sharedObject = ThoughtExtractionEngine.extractWithRules(
            "Buy milk and bread"
        ).items
        XCTAssertFalse(sharedObject.contains { $0.organization.itemType == .note })
        let anaphoricContinuation = ThoughtExtractionEngine.extractWithRules(
            "Email the contract to legal and get it back by Friday"
        ).items
        XCTAssertEqual(anaphoricContinuation.count, 1)

        let reportedCommands = ThoughtExtractionEngine.extractWithRules(
            "The instructor said, 'close the door and walk to the assembly point.'"
        ).items
        XCTAssertEqual(reportedCommands.count, 1)
        XCTAssertEqual(reportedCommands.first?.organization.itemType, .note)

        let unquotedReport = ThoughtExtractionEngine.extractWithRules(
            "Maya said call Ben and then email Jo."
        ).items
        XCTAssertEqual(unquotedReport.count, 1)
        XCTAssertEqual(unquotedReport.first?.organization.itemType, .note)
        XCTAssertTrue(unquotedReport.first?.sourceQuote.contains("email Jo") == true)

        let speakerReturns = ThoughtExtractionEngine.extractWithRules(
            "Maya said call Ben. Email Jo."
        ).items
        XCTAssertEqual(speakerReturns.count, 2)
        XCTAssertEqual(speakerReturns.first?.organization.itemType, .note)
        XCTAssertTrue(speakerReturns.last?.organization.itemType.isActionable == true)
    }

    func testConditionalActionAndNewFiniteFactKeepTheirOwnRows() {
        let conditioned = ThoughtExtractionEngine.extractWithRules(
            "Go to the bank Thursday to deposit the cheque and while I'm out there grab stamps"
        ).items
        XCTAssertEqual(conditioned.count, 2)
        XCTAssertTrue(conditioned.allSatisfy { $0.organization.itemType.isActionable })

        let newFact = ThoughtExtractionEngine.extractWithRules(
            "Remind me every Friday to submit the report and Catherine needs a copy"
        ).items
        XCTAssertEqual(newFact.count, 2)
        XCTAssertEqual(newFact.last?.organization.itemType, .note,
                       String(describing: newFact.map { ($0.analysisText, ActionabilityReader.read($0.analysisText)) }))
        XCTAssertEqual(ActionabilityReader.read("Catherine needs a copy"), .knowledge)
        XCTAssertEqual(ActionabilityReader.read("I need to send Catherine a copy"), .actionable)

        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules("Meeting at 2 and at 4").items.count, 1)
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(
            "I called the plumber yesterday and he never showed"
        ).items.count, 1)
    }

    func testSharedShoppingVerbKeepsDeterminedObjectsSeparateFromTransportErrands() {
        for source in [
            "Buy sunscreen and a travel adapter before we leave",
            "I need to buy a new mic stand and a pop filter for client calls"
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 2, source)
            XCTAssertTrue(items.allSatisfy { $0.organization.itemType == .shopping }, source)
        }
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(
            "Pick up the kids and the dog tomorrow"
        ).items.count, 1)
        let purchases = ThoughtExtractionEngine.extractWithRules("Buy milk and the newspaper").items
        XCTAssertEqual(purchases.count, 2)
        XCTAssertTrue(purchases.allSatisfy { $0.organization.itemType == .shopping && !$0.needsReview })
        XCTAssertEqual(purchases.map(\.analysisText), ["buy milk", "buy the newspaper"])
        XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(
            "Buy milk and then also bread"
        ).items.count, 2)
    }

    func testContactNounCompoundStaysInsideItsAction() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "I promised to update the staff contact sheet by Friday and contact Sarah tomorrow"
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].analysisText.contains("staff contact sheet"))
        XCTAssertTrue(items[1].analysisText.lowercased().contains("contact sarah"))
        XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable })
    }

    func testPossessedModifiedNounCannotOpenAPhantomInstruction() {
        let fact = ThoughtExtractionEngine.extractWithRules(
            "It has a handwritten label inside the lid saying 1978"
        ).items
        XCTAssertEqual(fact.count, 1)
        XCTAssertFalse(fact[0].organization.itemType.isActionable)
        let action = ThoughtExtractionEngine.extractWithRules("Label the storage box tomorrow").items
        XCTAssertEqual(action.count, 1)
        XCTAssertTrue(action[0].organization.itemType.isActionable)
    }

    func testPeopleContextDirectiveOwnsTheAdjacentFact() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "Sam's daughter is learning violin. Keep that as people context, not a task for me. "
                + "Call the pharmacy Thursday."
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].organization.itemType, .note)
        XCTAssertTrue(items[0].sourceQuote.contains("people context"))
        XCTAssertTrue(items[1].organization.itemType.isActionable)
        let concrete = ThoughtExtractionEngine.extractWithRules("Keep the folder in the desk").items
        XCTAssertEqual(concrete.count, 1)
        XCTAssertTrue(concrete[0].organization.itemType.isActionable)
    }

    func testDeferredIdeaAndDistinctOutputRequestDoNotBecomeTasks() {
        let text = "I should return the cookbook and call the pharmacy. "
            + "Sam's daughter is learning violin; keep that as people context, not a task for me. "
            + "There is a possible idea for a neighborhood recipe swap. "
            + "I should not schedule it yet. Please keep the two errands and two pieces of memory distinct."
        let items = ThoughtExtractionEngine.extractWithRules(text).items
        XCTAssertEqual(items.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertEqual(items.filter { $0.organization.itemType == .idea }.count, 1)
        XCTAssertFalse(items.contains { $0.analysisText.contains("I should not schedule") })
        XCTAssertTrue(items.last?.sourceQuote.contains("pieces of memory distinct") == true)
        let realTask = ThoughtExtractionEngine.extractWithRules("Keep the folders separate").items
        XCTAssertTrue(realTask.first?.organization.itemType.isActionable == true)
    }

    func testSharedEventRelativeTimeIsVisibleOnEachAction() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "After the workshop, send the notes and return the projector"
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable })
        XCTAssertTrue(items.allSatisfy { ($0.suggestedTitle ?? $0.analysisText)
            .lowercased().contains("after the workshop") })
        let independent = ThoughtExtractionEngine.extractWithRules(
            "After the workshop, send the notes and return the projector tomorrow"
        ).items
        XCTAssertEqual(independent.count, 2)
        XCTAssertTrue((independent[0].suggestedTitle ?? independent[0].analysisText)
            .lowercased().contains("after the workshop"))
        // Its own day does not revoke the shared prerequisite. Preserve the
        // condition on both actions, and do not invent an unconditional alert.
        XCTAssertTrue((independent[1].suggestedTitle ?? independent[1].analysisText)
            .lowercased().contains("after the workshop"))
        XCTAssertTrue(independent.allSatisfy { $0.organization.reminderDate == nil })
    }

    func testExposedReportedSafetyProcedureOwnsQuotedContextBeforeActions() {
        XCTAssertEqual(QuotedSpeechScope.matrixVoice(
            in: "During training, the instructor said, 'Close the door.'"
        ), .reported)
        XCTAssertEqual(QuotedSpeechScope.matrixVoice(
            in: "In the interview, Rosa said, 'Send me the file.'"
        ), .reported)
        XCTAssertEqual(QuotedSpeechScope.matrixVoice(
            in: "I am rehearsing lines for a play: 'Open the window.'"
        ), .reported)
        XCTAssertEqual(QuotedSpeechScope.matrixVoice(
            in: "Text Rosa, 'Send me the file.'"
        ), .direct)
        let spoken = "During the safety training, the instructor said, 'If the alarm sounds, "
            + "close the door and walk to the assembly point.' That's the procedure to remember, "
            + "not a current alarm or two immediate tasks. Separately, I promised to update "
            + "the staff contact sheet by Friday and ask the instructor whether the west exit "
            + "is accessible. The hypothetical alarm instructions should stay as reference material."
        let items = ThoughtExtractionEngine.extractWithRules(spoken).items
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].organization.itemType, .note)
        XCTAssertTrue(items[0].sourceQuote.contains("assembly point"))
        XCTAssertTrue(items[0].sourceQuote.contains("reference material"))
        XCTAssertTrue(items[1].organization.itemType.isActionable)
        XCTAssertTrue(items[1].analysisText.contains("update the staff contact sheet"))
        XCTAssertTrue(items[2].organization.itemType.isActionable)
        XCTAssertTrue(items[2].analysisText.contains("ask the instructor"))
        XCTAssertFalse(items.contains { $0.organization.itemType.isActionable
            && ($0.analysisText.contains("close the door") || $0.analysisText.contains("walk to the assembly")) })

        let separateFacts = ThoughtExtractionEngine.extractWithRules(
            "The guide said 'Keep the map.' The room has a blue door."
        ).items
        XCTAssertEqual(separateFacts.count, 2)
    }

    func testExplicitlyUnsettledBareHourKeepsTaskButWithholdsAlert() {
        let source = "Remind me to send the form at seven tomorrow. "
            + "I have not said morning or evening. Also buy a folder."
        let items = ThoughtExtractionEngine.extractWithRules(source).items
        let form = items.filter { $0.sourceQuote.contains("send the form") }
        XCTAssertEqual(form.count, 1)
        XCTAssertTrue(form[0].organization.itemType.isActionable)
        XCTAssertEqual(form[0].organization.temporalIntent.kind, .dateOnly)
        XCTAssertNotNil(form[0].organization.temporalIntent.day)
        XCTAssertNil(form[0].organization.reminderDate)
        XCTAssertTrue(form[0].organization.needsClarification)
        XCTAssertEqual(form[0].organization.state,
                       .underspecified(.ambiguousTemporalScope))
        XCTAssertTrue(items.contains { $0.sourceQuote.contains("buy a folder")
            && $0.organization.itemType.isActionable })
        XCTAssertFalse(items.contains { $0.analysisText.hasPrefix("I have not said")
            && $0.organization.itemType.isActionable })
        XCTAssertTrue(form[0].sourceQuote.contains("I have not said morning or evening"))

        let extended = ThoughtExtractionEngine.extractWithRules(
            "Remind me to send the form at seven tomorrow. "
                + "I have not said morning or evening, and there is no established "
                + "preference that settles that. Also buy a folder."
        ).items
        XCTAssertFalse(extended.contains { $0.analysisText.hasPrefix("I have not said") })
        XCTAssertTrue(extended.contains { $0.sourceQuote.contains("buy a folder")
            && $0.organization.itemType.isActionable })

        let unpunctuated = ThoughtExtractionEngine.extractWithRules(
            "remind me to send the form at seven tomorrow i have not said morning or evening also buy a folder"
        ).items
        let unpunctuatedForm = unpunctuated.first { $0.sourceQuote.contains("send the form") }
        XCTAssertNil(unpunctuatedForm?.organization.reminderDate)
        XCTAssertEqual(unpunctuatedForm?.organization.state,
                       .underspecified(.ambiguousTemporalScope))
        XCTAssertTrue(unpunctuated.contains { $0.sourceQuote.contains("buy a folder")
            && $0.organization.itemType.isActionable })

        let settled = ThoughtExtractionEngine.extractWithRules(
            "Remind me to send the form at seven tomorrow evening. "
                + "I have not said morning or evening for the other task."
        ).items
        let settledForm = settled.first { $0.sourceQuote.contains("send the form") }
        XCTAssertNotNil(settledForm?.organization.reminderDate)

        let reported = ThoughtExtractionEngine.extractWithRules(
            "Maya said, also buy a folder. The folder is blue."
        ).items
        XCTAssertFalse(reported.contains { $0.organization.itemType.isActionable })
    }

    func testNamedClockCorrectionCrossesUnrelatedErrandWithoutDuplicatingReminder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 5, hour: 9
        ))!
        let source = "Remind me at six tonight to send Maya the kitchen photos. "
            + "Buy eggs. Actually, seven tonight for the photos, because I will not "
            + "be home at six."
        let rows = ThoughtExtractionEngine.extractWithRules(
            source, referenceDate: reference, calendar: calendar
        ).items
        let photo = rows.filter { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("kitchen photos") }
        XCTAssertEqual(photo.count, 1)
        XCTAssertTrue(photo[0].sourceQuote.contains("seven tonight for the photos"))
        XCTAssertEqual(photo[0].organization.reminderDate.map {
            calendar.component(.hour, from: $0)
        }, 19)
        XCTAssertFalse(rows.contains { $0.organization.reminderDate.map {
            calendar.component(.hour, from: $0)
        } == 18 })
        XCTAssertTrue(rows.contains { $0.sourceQuote.contains("Buy eggs")
            && $0.organization.itemType.isActionable })

        let other = ThoughtExtractionEngine.extractWithRules(
            "Remind me at six tonight to send Maya the kitchen photos. "
                + "Actually, seven tonight for the dentist call.",
            referenceDate: reference, calendar: calendar
        ).items
        XCTAssertEqual(other.first { $0.sourceQuote.contains("kitchen photos") }?
            .organization.reminderDate.map { calendar.component(.hour, from: $0) }, 18)
        XCTAssertTrue(other.contains { $0.sourceQuote.contains("dentist call")
            && $0.needsReview })
    }

    func testQuotedSourceRetentionTargetsUniqueQuotedMemoryAcrossAnAction() {
        let owned = ThoughtExtractionEngine.extractWithRules(
            "The actor said, 'Open the gate.' Lock the shed tomorrow. "
                + "Keep the quoted words verbatim in the recording."
        ).items
        XCTAssertEqual(owned.count, 2)
        XCTAssertTrue(owned.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Open the gate")
            && $0.sourceQuote.contains("quoted words verbatim") })
        XCTAssertTrue(owned.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("Lock the shed")
            && !$0.sourceQuote.contains("quoted words verbatim") })

        let ambiguous = ThoughtExtractionEngine.extractWithRules(
            "The actor said, 'Open the gate.' The guide said, 'Close the hatch.' "
                + "Lock the shed. Keep the quoted words verbatim in the recording."
        ).items
        XCTAssertTrue(ambiguous.contains { $0.needsReview
            && $0.sourceQuote.contains("quoted words verbatim") })
        XCTAssertFalse(ambiguous.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("quoted words verbatim") })

        let noQuote = ThoughtExtractionEngine.extractWithRules(
            "Lock the shed. Keep the quoted words verbatim in the recording."
        ).items
        XCTAssertTrue(noQuote.contains { $0.needsReview
            && $0.sourceQuote.contains("quoted words verbatim") })

        let rehearsal = ThoughtExtractionEngine.extractWithRules(
            "I am rehearsing lines for a play: 'Open the window, hide the "
                + "letter, and run to the bridge.' Those are instructions "
                + "spoken by a fictional character, not things for my day. "
                + "The director wants the second line slower and a pause "
                + "before bridge; remember that staging note. I do need to "
                + "return the rehearsal key to the theatre office tomorrow. "
                + "Keep the scene's words intact in the capture, without "
                + "turning them into actions."
        ).items
        XCTAssertEqual(rehearsal.count, 2)
        XCTAssertFalse(rehearsal.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("scene's words intact") })
        XCTAssertTrue(rehearsal.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("scene's words intact")
            && $0.sourceQuote.contains("Open the window") })
        XCTAssertTrue(rehearsal.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("staging note")
            && $0.sourceQuote.contains("Open the window") })

        let directEvidence = ThoughtExtractionEngine.extractWithRules(
            "The actor said, 'Cross the river by the stone bridge.' These "
                + "are script words, not jobs for me. The director wants "
                + "bridge spoken quietly; remember that staging note."
        ).items
        XCTAssertEqual(directEvidence.count, 1)
        XCTAssertEqual(directEvidence[0].organization.itemType, .note)
        XCTAssertTrue(directEvidence[0].sourceQuote.contains("stone bridge"))
        XCTAssertTrue(directEvidence[0].sourceQuote.contains("staging note"))

        let quotedKeep = ThoughtExtractionEngine.extractWithRules(
            "The actor said, 'Keep the bridge clear.' These are script "
                + "words, not jobs for me. The director wants bridge spoken "
                + "quietly; remember that staging note."
        ).items
        XCTAssertEqual(quotedKeep.count, 1)
        XCTAssertTrue(quotedKeep[0].sourceQuote.contains("Keep the bridge clear"))

        let unrelatedMemory = ThoughtExtractionEngine.extractWithRules(
            "The actor said, 'Cross the river by the stone bridge.' These "
                + "are script words, not jobs for me. Remember the lighting "
                + "cue: the amber lamp dims."
        ).items
        XCTAssertEqual(unrelatedMemory.count, 2)

        let separatelySavedQuote = ThoughtExtractionEngine.extractWithRules(
            "The actor said, 'Cross the river by the stone bridge.' These "
                + "are script words, not jobs for me; I want the quote saved. "
                + "The director wants bridge spoken quietly; remember that staging note."
        ).items
        XCTAssertEqual(separatelySavedQuote.count, 2)
    }

    func testCoordinatedPossessiveFactRemainsOneRetentionRequest() {
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses(
                "I want the family saying and its origin remembered"
            ).count, 1
        )
        XCTAssertEqual(
            RuleBasedThoughtExtractor.splitClauses(
                "I want the family saying and call its author tomorrow"
            ).count, 2
        )
        let family = ThoughtExtractionEngine.extractWithRules(
            "My aunt told me the old family saying, 'Buy the good shoes and "
                + "mend the coat,' and then explained it came from her "
                + "grandmother when money was tight. I want the saying and "
                + "its origin remembered. She also said, 'Don't forget the "
                + "photographs,' by which she meant I should bring the album "
                + "to our gathering on Sunday, and I agree: bring the photo "
                + "album. The shoe buying and coat mending are proverb text, "
                + "not errands."
        ).items
        XCTAssertEqual(family.count, 2)
        XCTAssertFalse(family.contains { $0.analysisText == "its origin remembered" })
        XCTAssertTrue(family.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("its origin remembered")
            && $0.sourceQuote.contains("old family saying")
            && $0.sourceQuote.contains("proverb text") })
        XCTAssertTrue(family.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("bring the photo album")
            && !$0.sourceQuote.contains("proverb text") })

        let attributed = ThoughtExtractionEngine.extractWithRules(
            "The guide said, 'Turn left and stop.' Those were his words. "
                + "Put the map away. The quoted commands are script text, "
                + "not tasks for me."
        ).items
        XCTAssertEqual(attributed.count, 2)
        XCTAssertTrue(attributed.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("quoted commands") })
        XCTAssertFalse(attributed.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("quoted commands") })

        let noQuote = ThoughtExtractionEngine.extractWithRules(
            "Put the map away. The quoted commands are script text, "
                + "not tasks for me."
        ).items
        XCTAssertTrue(noQuote.contains { $0.needsReview
            && $0.sourceQuote.contains("quoted commands") })
    }


    func testNumberedIndependentIntentionsRemainIndividuallyAccessible() {
        let actions = ["scan the receipt", "file the warranty", "email the office",
                       "buy batteries", "wash the thermos", "call the optician"]
        let spoken = "Six separate errands: " + actions.enumerated().map {
            "\($0.offset + 1): \($0.element)."
        }.joined(separator: " ") + " These were separate jobs I said in one pass."
        let items = ThoughtExtractionEngine.extractWithRules(spoken).items
        XCTAssertEqual(items.count, actions.count)
        XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable && !$0.needsReview })
        for (item, action) in zip(items, actions) {
            XCTAssertEqual(item.analysisText.lowercased(), action)
        }
        XCTAssertTrue(items.first?.sourceQuote.contains("Six separate errands") == true)
        XCTAssertTrue(items.last?.sourceQuote.contains("one pass") == true)
    }

    func testExposedTwentyFiveIntentionCapacityCaseKeepsItsTail() {
        let actions = capacityActions
        let spoken = "I am reading twenty-five independent items from the paper list: "
            + actions.enumerated().map { "\($0.offset + 1): \($0.element)." }.joined(separator: " ")
            + " They are separate things I intend to do."
        let items = ThoughtExtractionEngine.extractWithRules(spoken).items
        XCTAssertEqual(items.count, 25)
        XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable && !$0.needsReview })
        XCTAssertEqual(items.last?.analysisText.lowercased(), "confirm the dinner time")
        XCTAssertTrue(items.last?.sourceQuote.contains("intend to do") == true)
    }

    func testUnnumberedTwentyFiveActionsKeepEveryIndependentTail() {
        for spoken in [
            capacityActions.map { $0.capitalized }.joined(separator: ". ") + ".",
            capacityActions.joined(separator: ", and ") + "."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(spoken).items
            XCTAssertEqual(items.count, 25, spoken)
            XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable && !$0.needsReview })
            XCTAssertTrue(items.last?.analysisText.lowercased().contains("confirm the dinner time") == true)
        }
    }

    func testThirtyIndependentIntentionsHaveNoExtractionCap() {
        let actions = capacityActions + [
            "mail the invitation", "check the smoke alarm", "fold the blankets",
            "photograph the receipt", "replace the air filter"
        ]
        let spoken = actions.map { $0.capitalized }.joined(separator: ". ") + "."
        let items = ThoughtExtractionEngine.extractWithRules(spoken).items
        XCTAssertEqual(items.count, actions.count)
        XCTAssertTrue(items.allSatisfy {
            $0.organization.itemType.isActionable && !$0.needsReview
        })
        XCTAssertTrue(items.first?.analysisText.lowercased().contains("scan the receipt") == true)
        XCTAssertTrue(items.last?.analysisText.lowercased().contains("replace the air filter") == true)
    }

    func testDictatedBareNumberMarkersKeepEveryActionAccessible() {
        let actions = capacityActions + [
            "mail the invitation", "check the smoke alarm", "fold the blankets",
            "photograph the receipt", "replace the air filter"
        ]
        for spoken in [
            actions.enumerated().map { "\($0.offset + 1) \($0.element)" }.joined(separator: "; "),
            actions.enumerated().map { "\($0.offset + 1), \($0.element)" }.joined(separator: ". ")
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(
                "Here are thirty separate jobs: " + spoken + "."
            ).items
            XCTAssertEqual(items.count, 30, spoken)
            XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable && !$0.needsReview })
            XCTAssertEqual(items.first?.analysisText.lowercased(), actions.first)
            XCTAssertEqual(items.last?.analysisText.lowercased(), actions.last)
        }
    }

    func testBareQuantitiesDoNotMasqueradeAsNumberedActions() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "I have 1 spare key and 2 blank cards in the desk drawer."
        )
        XCTAssertFalse(result.items.contains { $0.suggestedTitle?.lowercased() == "spare key and" })
        XCTAssertFalse(result.items.contains { $0.suggestedTitle?.lowercased() == "blank cards in the desk drawer" })
    }

    func testNumberedNeighbouringActionsKeepSeparateSourceIdentities() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Four separate checks: 1. count clean cups. 2. count marked cups. "
                + "3. inspect draft forms. 4. inspect signed forms."
        )
        XCTAssertEqual(result.items.count, 4)
        for (index, item) in result.items.enumerated() {
            XCTAssertTrue(item.sourceQuote.contains("\(index + 1)."))
            XCTAssertFalse(item.sourceQuote.contains("\(index + 2)."))
        }
    }

    func testOneUnfamiliarNumberedBodyKeepsItsOwnReviewSlot() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Three separate jobs: 1 call Mira; 2 brief the helpers; "
                + "3 buy batteries."
        )
        XCTAssertEqual(result.items.count, 3)
        guard result.items.count == 3 else { return }
        XCTAssertTrue(result.items[0].organization.itemType.isActionable)
        XCTAssertTrue(result.items[2].organization.itemType.isActionable)
        XCTAssertTrue(result.items[1].organization.itemType.isActionable
            || result.items[1].needsReview)
        XCTAssertTrue(result.items[1].sourceQuote.contains("2 brief the helpers"))
    }

    func testDeclaredActionListDoesNotPromoteDeclarativeFactOrQuotedCommand() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Three jobs from the desk list: 1 count the spare badges; "
                + "2 the access code is 418; 3 call Mira."
        ).items
        XCTAssertEqual(result.count, 3)
        guard result.count == 3 else { return }
        XCTAssertTrue(result[0].organization.itemType.isActionable)
        XCTAssertFalse(result[1].organization.itemType.isActionable)
        XCTAssertTrue(result[1].sourceQuote.contains("access code"))
        XCTAssertTrue(result[2].organization.itemType.isActionable)

        let quoted = ThoughtExtractionEngine.extractWithRules(
            "Three jobs: 1 check the latch; 2 Jo said, \"cancel the alarm\"; "
                + "3 call Mira."
        ).items
        XCTAssertEqual(quoted.count, 3)
        XCTAssertFalse(quoted[1].organization.itemType.isActionable)
    }

    func testFreshThirtyJobGateRegressionNeverSilentlyCollapsesTheTail() {
        // Exact formerly unseen gate input, retained as development evidence
        // only. The release set itself can no longer qualify a changed build.
        let transcript = "The junior sports day is Saturday and I have thirty jobs across the registration table, field edge and close-down. Coaches run games and first aid staff handle injuries; I am on logistics. "
            + "1 count the participant badges; 2 sort badges by team; 3 print the field map; 4 place the map at registration; 5 charge the scoreboard tablet; 6 test the tablet screen; 7 bring the spare whistle; 8 label the water station; 9 fill the drinking-water containers; 10 check the shade tent ropes; "
            + "11 put the lost-property box at the desk; 12 place the allergy notice by snacks; 13 count the oranges; 14 wash the serving tongs; 15 bring paper cups; 16 mark the quiet seating area; 17 check the accessible path; 18 test the announcer microphone; 19 put the schedule by each field; 20 ask the coach for the final team count; "
            + "21 copy the emergency contact sheet for authorised staff; 22 brief volunteers on check-in; 23 photograph the opening field layout; 24 record the starting cash for food sales; 25 check the recycling bins; 26 count leftover badges after games; 27 collect the field maps; 28 wipe the registration table; 29 lock the equipment cage; 30 return the borrowed megaphone. The contact sheet is for authorised staff, not a public board. I can ask the coach for numbers without choosing teams. I borrowed the megaphone from the scouts, who need it back for their own event next week."
        let items = ThoughtExtractionEngine.extractWithRules(transcript).items
        XCTAssertEqual(items.count, 30)
        guard items.count == 30 else { return }
        for (index, item) in items.enumerated() {
            XCTAssertNotNil(item.sourceQuote.range(
                of: #"(?<!\d)\#(index + 1)\s"#, options: .regularExpression
            ))
        }
        XCTAssertTrue(items.last?.sourceQuote.contains("30 return the borrowed megaphone") == true)
        XCTAssertFalse(items.contains { $0.suggestedTitle?.localizedCaseInsensitiveContains("buy snacks") == true },
                       items.compactMap(\.suggestedTitle).joined(separator: " | "))
        XCTAssertTrue(items.allSatisfy {
            $0.organization.itemType.isActionable && !$0.needsReview
        }, items.filter(\.needsReview).map(\.analysisText).joined(separator: " | "))
    }

    func testDeclaredSingleAccountOwnsItsHistoricalClausesBeforeRouting() {
        let spoken = "I want to remember how the old room became a reading corner. "
            + "Nadia moved a bench there after the library closed. "
            + "The caretaker told her to leave the fire exit clear. "
            + "She asked the owner before adding planters. "
            + "I watched the change, but I did not agree to maintain the space."
        let items = ThoughtExtractionEngine.extractWithRules(spoken).items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.organization.itemType, .note)
        XCTAssertEqual(items.first?.sourceQuote, spoken)
        XCTAssertFalse(items.first?.needsReview ?? true)
    }

    func testARealNewTaskClosesTheSingleAccountScope() {
        let spoken = "I want to remember how Nadia moved the reading bench. "
            + "She asked the owner first. Call Mira tomorrow about the room."
        let items = ThoughtExtractionEngine.extractWithRules(spoken).items
        XCTAssertTrue(items.contains { $0.organization.itemType == .note })
        XCTAssertTrue(items.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.localizedCaseInsensitiveContains("Call Mira") })
        XCTAssertFalse(items.count == 1 && items[0].organization.itemType == .note)

        let obligationInOpening = ThoughtExtractionEngine.extractWithRules(
            "I learned that I need to call Mira tomorrow. The office closes early."
        ).items
        XCTAssertTrue(obligationInOpening.contains {
            $0.organization.itemType.isActionable
                && $0.sourceQuote.localizedCaseInsensitiveContains("call Mira")
        })
    }

    func testFreshSingleMemoryGateRegressionKeepsTheWholeAccount() {
        // Exact formerly unseen gate input, retained as development evidence.
        let transcript = "I want to remember the explanation for the pale square on the wall of our rehearsal room. I thought a picture had been removed recently, but caretaker Mo said the square comes from an old noticeboard that was taken down when the room became a music space. "
            + "The board had covered the plaster for years while the rest of the wall darkened. He found its mounting holes behind the current coat hooks. The room used to host evening language classes, and the board held schedules in several languages. Mo knows that from photographs in the building office, not because he worked there then. He moved into this job later. "
            + "I looked at the holes and they line up with the pale patch, which makes the account convincing, but I have not seen the office photographs myself. The point is that the mark records a change in the room's use. I am not asking for repainting, and the coat hooks are fine."
        let items = ThoughtExtractionEngine.extractWithRules(transcript).items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.organization.itemType, .note)
        XCTAssertEqual(items.first?.sourceQuote, transcript)
        XCTAssertFalse(items.first?.needsReview ?? true)
    }

    private var capacityActions: [String] {
        ["scan the receipt", "file the warranty", "email the building office",
                       "buy batteries", "wash the thermos", "refill the soap", "call the optician",
                       "book the haircut", "return the parcel", "print the tickets",
                       "charge the camera", "update the address book", "water the fern",
                       "sort the recycling", "back up the photos", "pick up the prescription",
                       "check the bicycle tires", "mend the blue shirt", "send the meeting notes",
                       "clean the coffee grinder", "reserve a library room", "copy the key",
                       "buy postage stamps", "pack the raincoat", "confirm the dinner time"]
    }

    func testIsolatedNumbersAndTimesDoNotBecomeListBoundaries() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "Remember the meeting is at 1:30 and the door code is 2:45"
        ).items
        XCTAssertFalse(items.contains { $0.suggestedTitle == "30" || $0.suggestedTitle == "45" })
    }

    func testFrontedDaypartOwnsFollowingActionWithoutAnExtraRow() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow morning, photograph the stain and call the landlord"
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable })
        XCTAssertFalse(items.contains { $0.suggestedTitle == "Tomorrow morning" })
    }

    func testNewEverydayVerbsAreActionsOnlyWhenRequested() {
        let action = ThoughtExtractionEngine.extractWithRules("Photograph the stain").items
        let history = ThoughtExtractionEngine.extractWithRules("Mira photographed the stain").items
        XCTAssertEqual(action.count, 1)
        XCTAssertTrue(action[0].organization.itemType.isActionable)
        XCTAssertEqual(history.count, 1)
        XCTAssertFalse(history[0].organization.itemType.isActionable)
    }

    func testCaptureFramingOwnsSourceWithoutBecomingAnExtraMemory() {
        let text = "I want to get these errands out of my head. Tomorrow call the dentist. "
            + "Buy batteries. That's the whole list."
        let items = ThoughtExtractionEngine.extractWithRules(text).items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable })
        XCTAssertTrue(items.first?.sourceQuote.contains("out of my head") == true)
        XCTAssertTrue(items.last?.sourceQuote.contains("whole list") == true)
    }

    func testExplanatoryPhraseAndVisibleStepRequestAreContext() {
        let text = "For the workshop, print the sheets, charge the speaker, and buy tape. "
            + "The phrase 'bring everyone together' is just my reason for doing it. "
            + "The three concrete steps are the pieces I need to see."
        let items = ThoughtExtractionEngine.extractWithRules(text).items
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable })
        XCTAssertTrue(items.last?.sourceQuote.contains("three concrete steps") == true)
    }

    func testAQuotedPhraseWithAnIndependentFactRemainsMemory() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "The phrase 'bring everyone together' is printed on the poster. Buy tape."
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("printed on the poster") })

        let label = ThoughtExtractionEngine.extractWithRules(
            "The label 'keep gate closed' is printed on the box. Buy tape."
        ).items
        XCTAssertTrue(label.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("printed on the box") })

        let direct = ThoughtExtractionEngine.extractWithRules(
            "Text Mara the phrase 'bring everyone together' tomorrow."
        ).items
        XCTAssertTrue(direct.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("Text Mara") })
    }

    func testActualFactAboutATrainRemainsMemoryBesideAnAction() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "I just got off the train and saw a mural. Tomorrow call the dentist."
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("mural") })
    }

    func testExplicitSingularMemoryOwnsItsElaboration() {
        let text = "I want to remember how Mum makes the soup. She softens onions and fennel. "
            + "She adds white beans and finishes with lemon. This is a recipe memory."
        let items = ThoughtExtractionEngine.extractWithRules(text).items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.organization.itemType, .note)
        XCTAssertEqual(items.first?.sourceQuote, text)
    }

    func testExplicitStoryAndOneAccountRemainOneMemoryThroughHistoricalActions() {
        for text in [
            "I want to keep the story of fixing my grandfather's gate. He told me to hold the torch higher. We straightened the strip and went in for tea. Keep the account together.",
            "I want to keep one account of yesterday's walk. I crossed the footbridge and met a dog carrying a wide stick. Keep it as one reflection."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(text).items
            XCTAssertEqual(items.count, 1, text)
            XCTAssertEqual(items.first?.organization.itemType, .note, text)
            XCTAssertEqual(items.first?.sourceQuote, text, text)
            XCTAssertFalse(items.first?.needsReview ?? true, text)
        }
    }

    func testLaterRealTaskClosesExplicitStoryAndOneAccountScope() {
        for text in [
            "I want to keep the story of fixing my grandfather's gate. We went in for tea. Call Mira tomorrow about the hinge.",
            "I want to keep one account of yesterday's walk. I crossed the footbridge. I also need to call Pat tomorrow."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(text).items
            XCTAssertTrue(items.contains { $0.organization.itemType.isActionable
                && $0.sourceQuote.localizedCaseInsensitiveContains("tomorrow") }, text)
            XCTAssertFalse(items.count == 1 && items[0].organization.itemType == .note, text)
        }
    }


    func testAnIndependentActionPreventsSingularMemoryMerge() {
        let text = "I want to remember how Mum makes soup. She uses fennel. "
            + "I need to cook soup tonight. This is a recipe memory."
        let items = ThoughtExtractionEngine.extractWithRules(text).items
        XCTAssertTrue(items.contains { $0.organization.itemType.isActionable })
        XCTAssertFalse(items.count == 1 && items[0].organization.itemType == .note)
    }

    func testDescribedRoutineWithHypotheticalQuotedVerbStaysOneMemory() {
        let text = "I'm describing my Saturday market routine so I can find it later. "
            + "I visit the bread stall and then the flower stand. "
            + "The shared context belongs on the whole note. "
            + "If I say 'pick up' while describing that routine, it is not a shopping task."
        let items = ThoughtExtractionEngine.extractWithRules(text).items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.organization.itemType, .note)
        XCTAssertEqual(items.first?.sourceQuote, text)
    }

    func testTwoDistinctFactsRemainSeparateWithoutSingularScope() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "Mum makes soup with fennel. Dad stores the spare key in the shed."
        ).items
        XCTAssertEqual(items.count, 2)
    }

    func testResolvedChoiceKeepsDependentActionsAndGroundsTheirObject() {
        let text = "I was considering a scarf or a sketchbook. I settled on the sketchbook. "
            + "Buy it by Friday and wrap it before Saturday."
        let items = ThoughtExtractionEngine.extractWithRules(text).items
        let actions = items.filter { $0.organization.itemType.isActionable }
        XCTAssertEqual(actions.count, 2)
        XCTAssertTrue(actions.allSatisfy { $0.analysisText.lowercased().contains("sketchbook") })
        XCTAssertFalse(actions.contains { $0.analysisText.lowercased().contains("scarf") })

        let ownChoice = ThoughtExtractionEngine.extractWithRules(
            "I was weighing the tram or the bus. I chose the tram. Buy the tram ticket tomorrow."
        ).items
        XCTAssertEqual(ownChoice.count, 1)
        XCTAssertEqual(ownChoice[0].organization.itemType, .shopping)
        XCTAssertTrue(ownChoice[0].rawQuote.contains("I was weighing"))
        XCTAssertTrue(ownChoice[0].sourceQuote.contains("I chose the tram"))

        let reported = ThoughtExtractionEngine.extractWithRules(
            "Mara was weighing the tram or the bus. Mara chose the tram. "
                + "Buy the tram ticket tomorrow."
        ).items
        XCTAssertEqual(reported.filter { $0.organization.itemType.isActionable }.count, 1)
        XCTAssertTrue(reported.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Mara chose") })
        XCTAssertFalse(reported.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("Mara chose") })
    }

    func testExplicitChoiceContextBindsOnlyOneCommittedAction() {
        let sameSentence = ThoughtExtractionEngine.extractWithRules(
            "I considered the ferry or the tram, but I decided to take the tram. "
                + "Buy the tram ticket tomorrow. Call Mira Friday."
        ).items
        XCTAssertEqual(sameSentence.count, 2)
        XCTAssertTrue(sameSentence[0].sourceQuote.contains("considered the ferry"))
        XCTAssertTrue(sameSentence[0].sourceQuote.contains("Buy the tram ticket"))
        XCTAssertFalse(sameSentence[1].sourceQuote.contains("considered the ferry"))

        let otherChooser = ThoughtExtractionEngine.extractWithRules(
            "Mara considered the ferry or the tram, but she decided to take the tram. "
                + "Buy the tram ticket tomorrow."
        ).items
        XCTAssertTrue(otherChooser.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Mara considered") })
        XCTAssertFalse(otherChooser.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("Mara considered") })

        let selected = ThoughtExtractionEngine.extractWithRules(
            "We talked about whether to mail the forms or submit them online. "
                + "Online is our final choice. Submit the forms online Friday. "
                + "Call the accountant Saturday."
        ).items
        XCTAssertEqual(selected.count, 2)
        XCTAssertTrue(selected[0].organization.itemType.isActionable)
        XCTAssertTrue(selected[0].sourceQuote.contains("whether to mail"))
        XCTAssertTrue(selected[0].sourceQuote.contains("final choice"))
        XCTAssertTrue(selected[0].rawQuote.contains("whether to mail"))
        XCTAssertFalse(selected[1].sourceQuote.contains("whether to mail"))

        let unchosen = ThoughtExtractionEngine.extractWithRules(
            "I was considering the ferry or the bus. I have not chosen. "
                + "Buy batteries tomorrow."
        ).items
        XCTAssertTrue(unchosen.contains { $0.sourceQuote.contains("considering the ferry") })
        XCTAssertTrue(unchosen.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("Buy batteries") })
        XCTAssertFalse(unchosen.contains { $0.sourceQuote.contains("considering the ferry")
            && $0.sourceQuote.contains("Buy batteries") })

        let reported = ThoughtExtractionEngine.extractWithRules(
            "Mara considered the ferry or the bus. Mara chose the ferry. "
                + "Buy the ferry ticket tomorrow."
        ).items
        XCTAssertTrue(reported.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Mara chose") })
        XCTAssertFalse(reported.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("Mara chose") })

        let contested = ThoughtExtractionEngine.extractWithRules(
            "I was considering the ferry or the bus. I chose the ferry. "
                + "Buy the ferry ticket and reserve a ferry seat."
        ).items
        XCTAssertTrue(contested.contains { $0.needsReview
            && $0.sourceQuote.contains("considering the ferry") })
        XCTAssertTrue(contested.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("buy the ferry ticket") })
        XCTAssertTrue(contested.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("reserve a ferry seat") })

        let embedded = ThoughtExtractionEngine.extractWithRules(
            "I was considering noodles or lentils. I checked the cupboard, "
                + "so the decision is made: cook lentils tonight and buy spinach."
        ).items
        XCTAssertEqual(embedded.count, 2)
        XCTAssertTrue(embedded[0].analysisText.lowercased().contains("cook lentils"))
        XCTAssertTrue(embedded[0].sourceQuote.contains("considering noodles"))
        XCTAssertTrue(embedded[1].analysisText.lowercased().contains("buy spinach"))
    }

    func testPairedAlternativesStayOneDeliberationUntilAnActionIsSpoken() {
        let unresolved = ThoughtExtractionEngine.extractWithRules(
            "Mara has not chosen between the ferry and the tram. "
                + "Buy batteries tomorrow."
        ).items
        XCTAssertEqual(unresolved.count, 2)
        XCTAssertEqual(unresolved[0].organization.itemType, .note)
        XCTAssertTrue(unresolved[0].sourceQuote.contains("ferry and the tram"))
        XCTAssertTrue(unresolved[1].organization.itemType.isActionable)

        let own = ThoughtExtractionEngine.extractWithRules(
            "I have not chosen between the ferry and the tram. "
                + "Call the mechanic tomorrow."
        ).items
        XCTAssertEqual(own.count, 2)
        XCTAssertFalse(own[0].organization.itemType.isActionable)
        XCTAssertTrue(own[1].organization.itemType.isActionable)

        let independent = ThoughtExtractionEngine.extractWithRules(
            "Stand between the ferry terminal and the tram stop and call Mara."
        ).items
        XCTAssertTrue(independent.contains {
            $0.organization.itemType.isActionable
                && $0.analysisText.lowercased().contains("call mara")
        })

        let committedAfterContrast = ThoughtExtractionEngine.extractWithRules(
            "I have not chosen a train, but buy the ticket anyway."
        ).items
        XCTAssertTrue(committedAfterContrast.contains {
            $0.organization.itemType.isActionable
                && $0.analysisText.lowercased().contains("buy the ticket")
                && $0.sourceQuote.contains("have not chosen")
        })
        XCTAssertFalse(committedAfterContrast.contains {
            $0.organization.itemType.isActionable
                && $0.analysisText.lowercased().contains("chosen")
        })

        let dependentReminder = ThoughtExtractionEngine.extractWithRules(
            "Finish the report but remind me to email Sam first"
        ).items
        XCTAssertEqual(dependentReminder.count, 1)
        XCTAssertTrue(dependentReminder[0].sourceQuote.contains("email Sam"))
    }

    func testRejectedOptionCommentaryKeepsTheChosenActionsOwner() {
        let selected = ThoughtExtractionEngine.extractWithRules(
            "I was considering the tram or the bus. I chose the tram. "
                + "Buy the tram ticket tomorrow. The bus was only the rejected option. "
                + "Remember the bus timetable is useful next summer."
        ).items
        XCTAssertEqual(selected.count, 2)
        XCTAssertTrue(selected[0].organization.itemType.isActionable)
        XCTAssertTrue(selected[0].sourceQuote.contains("rejected option"))
        XCTAssertTrue(selected[0].rawQuote.contains("rejected option"))
        XCTAssertEqual(selected[1].organization.itemType, .note)
        XCTAssertTrue(selected[1].sourceQuote.contains("timetable"))

        let reported = ThoughtExtractionEngine.extractWithRules(
            "Mara said the bus was only the rejected option. Buy batteries tomorrow."
        ).items
        XCTAssertTrue(reported.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Mara said") })
        XCTAssertFalse(reported.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("Mara said") })

        let withoutOwner = ThoughtExtractionEngine.extractWithRules(
            "The bus was only the rejected option. Buy batteries tomorrow."
        ).items
        XCTAssertTrue(withoutOwner.contains { $0.needsReview
            && $0.sourceQuote.contains("rejected option") })

        let outputConstraint = ThoughtExtractionEngine.extractWithRules(
            "For breakfast I considered oats or eggs. I chose oats. Buy oats tomorrow. "
                + "I don't want two competing breakfast plans."
        ).items
        XCTAssertEqual(outputConstraint.count, 1)
        XCTAssertTrue(outputConstraint[0].organization.itemType.isActionable)
        XCTAssertTrue(outputConstraint[0].rawQuote.contains("competing breakfast plans"))

        let unrelatedConstraint = ThoughtExtractionEngine.extractWithRules(
            "I considered the ferry or the tram. I chose the tram. "
                + "Buy the tram ticket. I don't want two competing dinner plans."
        ).items
        XCTAssertTrue(unrelatedConstraint.contains { $0.needsReview
            && $0.sourceQuote.contains("competing dinner plans") })
        XCTAssertTrue(unrelatedConstraint.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("buy the tram ticket") })
    }

    func testAmbiguousChosenObjectPronounIsVisibleForReview() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "I chose two books. Buy it by Friday"
        ).items
        XCTAssertTrue(items.contains { $0.needsReview })
        let short = ThoughtExtractionEngine.extractWithRules("Send it before the first").items
        XCTAssertEqual(short.count, 1)
        XCTAssertFalse(short[0].needsReview)
    }

    func testChosenObjectConflictAsksForObjectRatherThanActor() {
        for source in [
            "I chose two books. Buy it.",
            "I decided on a cabinet and shelf. Add making that shelf to my list."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            let held = items.first { $0.needsReview }
            XCTAssertNotNil(held, source)
            XCTAssertEqual(held?.organization.state, .contested(.ambiguousObject), source)
            XCTAssertNil(held?.organization.dueDate, source)
            XCTAssertNil(held?.organization.reminderDate, source)
            XCTAssertTrue(held?.sourceUnitIDs.isEmpty == false, source)
        }
        let reported = ThoughtExtractionEngine.extractWithRules("Nora said, 'I chose a cabinet.' Make that cabinet.").items
        XCTAssertFalse(reported.contains { $0.organization.itemType.isActionable && $0.analysisText.lowercased().contains("a cabinet") })
    }

    func testObjectReviewKeepsAnAlreadyResolvedDayWithoutArmingAnEffect() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        let direct = ThoughtOrganizer.organize("Buy it by Friday", referenceDate: reference, calendar: calendar)
        XCTAssertEqual(direct.itemType, .shopping)
        XCTAssertEqual(direct.temporalIntent.day, CalendarDay(year: 2026, month: 10, day: 9))
        XCTAssertNil(direct.temporalIntent.time)
        let held = ThoughtExtractionEngine.extractWithRules("I chose two books. Buy it by Friday.",
            referenceDate: reference, calendar: calendar).items.first { $0.needsReview }
        XCTAssertEqual(held?.organization.state, .contested(.ambiguousObject))
        XCTAssertEqual(held?.organization.itemType, .shopping)
        XCTAssertEqual(held?.organization.temporalIntent.day, CalendarDay(year: 2026, month: 10, day: 9))
        XCTAssertEqual(held?.organization.dueDate, direct.dueDate)
        XCTAssertNil(held?.organization.temporalIntent.time)
        XCTAssertNil(held?.organization.reminderDate)
        XCTAssertTrue(held?.sourceQuote.contains("Buy it by Friday") == true)
    }

    static let gardenScatteredLongCapture = """
I am looking around the garden while I talk, so the order is going to be a bit random. The square pot by the back door has mint, and the round one next to it has parsley. Remember that, because the labels have faded. I need to replace the cracked tray under the square mint pot. Only the tray, not the plant or the pot. The other tray is still fine.

I was thinking of painting little picture labels for the plants rather than writing their names. That could be a nice small project, but it is still an idea. I have not decided to spend a weekend on it. A definite job is to return Mira's watering can tomorrow. It is the one with the narrow spout, and the detachable rose belongs with it even though it is currently on the shelf in the shed.

The shed key has the square blue tag. Keep that as a separate useful fact. The round blue tag is for something else, so the shape matters. Ask the garden coordinator whether we can use the empty bed near the fence. I do not want to assume it is free just because there is nothing growing there at the moment. There is no date for asking.

If it rains before tomorrow morning, skip watering the parsley. Otherwise water it tomorrow. Keep that conditional rather than treating it as certain that rain will happen. I am not asking the app to monitor the weather; I can check it. Also, I have decided not to buy any more mint. I nearly added that because the square pot looked sparse from this angle, but it is doing fine. The tray replacement still stands. I know the last few sentences doubled back on the first ones, but I have not withdrawn that job.
"""

    func testConditionalNegativeActionCannotBecomeAnUnconditionalSavedOperation() {
        for source in [
            "If it rains before tomorrow morning, skip watering the parsley. Otherwise water it tomorrow.",
            "Unless Nora confirms, cancel the appointment. Buy the envelopes.",
            "When I have checked the invoice, delete the draft task. Call Nora."
        ] {
            let partition = CaptureOperationDetector.partitionWithOwnership(source)
            XCTAssertTrue(partition.operations.isEmpty, source)
            XCTAssertTrue(partition.unownedMeaningfulIDs(in: source).isEmpty, source)
            XCTAssertNotNil(partition.remainder, source)
            XCTAssertNil(ThoughtExtractionEngine.extractWithRules(source).pendingOperation, source)
        }
        let direct = CaptureOperationDetector.partitionWithOwnership("Cancel the appointment. Buy envelopes.")
        XCTAssertTrue(direct.operations.contains { $0.operation == .cancel }, "Explicit immediate saved operation remains reachable")
    }

    func testDeicticObjectDescriptionUsesOnlyItsAdjacentPhysicalAction() {
        let direct = ThoughtExtractionEngine.extractWithRules("Return the jug. It is the one with the blue handle. The shed key has a square tag.")
        let action = direct.items.first { $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("return the jug") }
        XCTAssertTrue(action?.sourceQuote.localizedCaseInsensitiveContains("blue handle") ?? false)
        XCTAssertFalse(action?.sourceQuote.localizedCaseInsensitiveContains("shed key") ?? true)
        XCTAssertTrue(direct.items.contains { $0.organization.itemType == .note && $0.sourceQuote.localizedCaseInsensitiveContains("shed key") })
        for source in [
            "Call Nora. It is the one with the blue handle.",
            "Return the jug. Nora has the keys. It is the one with the blue handle.",
            "Return the jug and the mug. It is the one with the blue handle.",
            "Return the jug. Nora said, 'It is the one with the blue handle.'"
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable
                && $0.sourceQuote.localizedCaseInsensitiveContains("blue handle") }, source)
            XCTAssertNil(result.pendingOperation, source)
        }
    }

    func testNamedObjectRestrictionOwnsOnlyItsUniqueTask() {
        for source in [
            "Replace the cracked tray under the mint pot. Only the tray, not the plant or the pot.",
            Self.gardenScatteredLongCapture
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            let tray = result.items.filter { $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("replace the cracked tray") }
            XCTAssertEqual(tray.count, 1, source)
            XCTAssertTrue(tray.first?.sourceQuote.localizedCaseInsensitiveContains("Only the tray") ?? false, source)
            XCTAssertFalse(tray.first?.needsReview ?? true)
            XCTAssertFalse(result.items.contains { !$0.organization.itemType.isActionable && $0.sourceQuote.hasPrefix("Only the tray") }, source)
            XCTAssertNil(result.pendingOperation)
        }
        for source in [
            "Replace the cracked tray. Clean the tray. Only the tray, not the plant or the pot.",
            "Nora said, 'Replace the cracked tray.' Only the tray, not the plant or the pot.",
            "Call Nora. Only the tray, not the plant or the pot."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable && $0.sourceQuote.localizedCaseInsensitiveContains("Only the tray") }, source)
            XCTAssertNil(result.pendingOperation)
        }
        let independent = ThoughtExtractionEngine.extractWithRules("Replace the cracked tray. Only the tray, not the plant or the pot. Also buy bread.")
        XCTAssertEqual(independent.items.filter { $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("buy bread") }.count, 1)
        XCTAssertFalse(independent.items.first { $0.analysisText.localizedCaseInsensitiveContains("buy bread") }?.sourceQuote.localizedCaseInsensitiveContains("Only the tray") ?? true)
    }

    func testOriginalGardenCaptureStatusCannotInventAnotherTask() {
        let result = ThoughtExtractionEngine.extractWithRules(Self.gardenScatteredLongCapture)
        let reaffirmed = result.items.filter { $0.organization.itemType.isActionable
            && $0.sourceQuote.localizedCaseInsensitiveContains("not withdrawn that job") }
        XCTAssertEqual(reaffirmed.count, 1)
        XCTAssertTrue(reaffirmed.first?.analysisText.localizedCaseInsensitiveContains("replace the cracked tray") == true)
        XCTAssertTrue(reaffirmed.first?.sourceQuote.localizedCaseInsensitiveContains("The tray replacement still stands") == true)
        let ambiguous = ThoughtExtractionEngine.extractWithRules("Replace the cracked tray. Replace the broken tray. The tray replacement still stands. I have not withdrawn that job.")
        XCTAssertFalse(ambiguous.items.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.localizedCaseInsensitiveContains("still stands") })
        XCTAssertEqual(result.items.filter { $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("replace the cracked tray") }.count, 1)
        XCTAssertNil(result.pendingOperation)
        let direct = CaptureOperationDetector.partitionWithOwnership("Cancel that task.")
        XCTAssertEqual(direct.operations.first?.operation, .cancel)
        let message = ThoughtExtractionEngine.extractWithRules("Text Nora that I have not cancelled this reminder. Also buy bread.")
        XCTAssertNil(message.pendingOperation)
        XCTAssertTrue(message.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("text Nora") })
        XCTAssertTrue(message.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("buy bread") })

    }

    static let trainIdeaLongCapture = """
Right, about the trip. The train is booked for Friday, October ninth, leaving at ten in the morning. I have the booking already, so I am not buying another ticket. I need to download the actual ticket before the train leaves. The email with a list of journey options is not the ticket; use the attachment in the confirmation. I know I always say I will have a signal at the station, but I would rather not depend on that.

Text Sam to say the train leaves at ten on Friday and ask whether he can meet me at the other end. I have not picked a time to send that text. Ten is the departure time inside the message. Also pack the short charging cable, the one that fits in the small battery pouch. I do not need the long cable from behind the desk. The packing is for this trip, but I have not given it a reminder time.

I thought I might take the big camera, but I have decided to leave it and use my phone. Do not keep a camera packing job from that thought. There is an idea I want to keep separately, though: photograph the same station platform from the same spot every time I visit. It might make an interesting series over a year. I am not setting up a recurring reminder for it, just saving the possible project.

The guest room key is with June, not with Jonah. Remember that. I keep mixing their names up because they both helped last time. Ask June tomorrow whether I can collect the key on Thursday evening. Tomorrow is when I want to ask; Thursday evening is the proposed collection in the question. And remind me at eight tonight to put the railcard in my wallet. That is the last item, and the eight o'clock alert is only for the railcard, not all the trip jobs.
"""

    func testExistentialIdeaFrameKeepsItsContentAndTentativeContinuationWithoutExtraReview() {
        let frame = "There is an idea I want to keep separately, though"
        XCTAssertEqual(ThoughtOrganizer.organize(frame).itemType, .idea)
        let paragraph = frame + ": photograph the same station platform from the same spot every time I visit. It might make an interesting series over a year. I am not setting up a recurring reminder for it, just saving the possible project."
        for source in [paragraph, Self.trainIdeaLongCapture] {
            // Match the shipping repository's creation replay after the
            // unrelated possession report finds no saved completion target.
            // Its operation path is checked by the native stored test.
            let result = ThoughtExtractionEngine.extractWithRules(source, permitsOperations: false)
            let ideas = result.items.filter { $0.organization.itemType == .idea }
            XCTAssertEqual(ideas.count, 1, source)
            XCTAssertTrue(ideas.first?.sourceQuote.localizedCaseInsensitiveContains("same station platform") ?? false)
            XCTAssertTrue(ideas.first?.sourceQuote.localizedCaseInsensitiveContains("interesting series") ?? false)
            XCTAssertTrue(ideas.first?.sourceQuote.localizedCaseInsensitiveContains("not setting up a recurring reminder") ?? false)
            XCTAssertNil(ideas.first?.organization.reminderDate)
            XCTAssertFalse(ideas.first?.needsReview ?? true)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable && $0.sourceQuote.localizedCaseInsensitiveContains("same station platform") })
            XCTAssertNil(result.pendingOperation)
        }
    }

    static let gardenIdeaParagraph = "I was thinking of painting little picture labels for the plants rather than writing their names. That could be a nice small project, but it is still an idea. I have not decided to spend a weekend on it."

    func testDeicticIdeaContinuationDoesNotChooseCompetingOrReportedOwners() {
        for source in [
            "I had an idea for a photo series. I had another idea for a concert series. That could be a nice small project, but it is still an idea.",
            "I had an idea for a photo series. The shed key has a blue tag. That could be a nice small project, but it is still an idea."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertFalse(result.items.contains { $0.sourceQuote.contains("photo series") && $0.sourceQuote.contains("nice small project") }, source)
            XCTAssertTrue(result.items.contains { $0.needsReview && $0.sourceQuote.contains("nice small project") }, source)
        }
        let reported = ThoughtExtractionEngine.extractWithRules("Nora said, 'I had an idea for a photo series. That could be a nice small project, but it is still an idea.' Call Nora tomorrow.")
        XCTAssertFalse(reported.items.contains { $0.organization.itemType.isActionable && $0.sourceQuote.contains("photo series") })
        XCTAssertTrue(reported.items.contains { $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("call Nora") })
    }

    func testGardenIdeaContinuationRetainsOneIdeaAndItsUndecidedStatus() {
        for source in [Self.gardenIdeaParagraph, Self.gardenScatteredLongCapture] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            let ideas = result.items.filter { $0.organization.itemType == .idea }
            XCTAssertEqual(ideas.count, 1, source)
            let owner = ideas.first { $0.sourceQuote.localizedCaseInsensitiveContains("painting little picture labels") }
            XCTAssertNotNil(owner)
            XCTAssertTrue(owner?.sourceQuote.localizedCaseInsensitiveContains("nice small project") ?? false)
            XCTAssertTrue(owner?.sourceQuote.localizedCaseInsensitiveContains("not decided to spend") ?? false)
            XCTAssertFalse(owner?.needsReview ?? true)
            XCTAssertNil(owner?.organization.reminderDate)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable && $0.sourceQuote.localizedCaseInsensitiveContains("painting little picture labels") })
            XCTAssertNil(result.pendingOperation)
        }
        let independent = ThoughtExtractionEngine.extractWithRules(Self.gardenIdeaParagraph + " I have decided to paint the fence tomorrow. Also call Nora.")
        XCTAssertEqual(independent.items.filter { $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("paint the fence") }.count, 1)
        XCTAssertEqual(independent.items.filter { $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("call Nora") }.count, 1)
        XCTAssertFalse(independent.items.filter { $0.organization.itemType.isActionable }.contains { $0.sourceQuote.localizedCaseInsensitiveContains("nice small project") })
    }

    static let gardenManualConditionalParagraph = "If it rains before tomorrow morning, skip watering the parsley. Otherwise water it tomorrow. Keep that conditional rather than treating it as certain that rain will happen."

    func testManualConditionDoesNotAdoptReportedOrDifferentActions() {
        XCTAssertEqual(ClauseScope.read("Text Nora that if it rains, skip watering the parsley").act, .communicating)
        XCTAssertEqual(ClauseScope.read("Text Nora tomorrow at five").act, .direct)
        for source in [
            "Nora said, 'If it rains, skip watering the parsley. Otherwise water it tomorrow.'",
            "Text Nora that if it rains, skip watering the parsley. Otherwise water it tomorrow.",
            "If it rains, skip watering the parsley. Otherwise buy fertilizer tomorrow."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable
                && ActionabilityReader.actionBody($0.analysisText).lowercased().hasPrefix("water") }, source)
            XCTAssertNil(result.pendingOperation, source)
        }
        let independent = ThoughtExtractionEngine.extractWithRules(Self.gardenManualConditionalParagraph + " Buy bread.")
        XCTAssertEqual(independent.items.filter { $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("buy bread") }.count, 1)
        XCTAssertFalse(independent.items.first { $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("buy bread") }?.sourceQuote.localizedCaseInsensitiveContains("rains") ?? true)
    }

    func testManualConditionalAlternativeRetainsOneActionItsConditionAndOwnDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        for source in [Self.gardenManualConditionalParagraph, Self.gardenScatteredLongCapture] {
            let result = ThoughtExtractionEngine.extractWithRules(source, referenceDate: reference, calendar: calendar)
            let water = result.items.filter { $0.organization.itemType.isActionable
                && ActionabilityReader.actionBody($0.analysisText).lowercased().hasPrefix("water") }
            XCTAssertEqual(water.count, 1, source)
            XCTAssertTrue(water.first?.analysisText.localizedCaseInsensitiveContains("parsley") ?? false)
            XCTAssertFalse(water.first?.needsReview ?? true)
            XCTAssertEqual(water.first?.organization.temporalIntent.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(water.first?.organization.temporalIntent.time)
            XCTAssertNil(water.first?.organization.reminderDate)
            XCTAssertTrue(water.first?.sourceQuote.localizedCaseInsensitiveContains("if it rains before tomorrow morning") ?? false)
            XCTAssertTrue(water.first?.sourceQuote.localizedCaseInsensitiveContains("otherwise water it tomorrow") ?? false)
            XCTAssertTrue(water.first?.sourceQuote.localizedCaseInsensitiveContains("keep that conditional") ?? false)
            let visible = water.first?.suggestedTitle ?? water.first?.analysisText ?? ""
            XCTAssertTrue(visible.localizedCaseInsensitiveContains("unless") || visible.localizedCaseInsensitiveContains("if not"), visible)
            XCTAssertFalse(result.items.contains { $0.organization.itemType == .event && $0.sourceQuote.localizedCaseInsensitiveContains("rains") })
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("keep that conditional") })
            XCTAssertNil(result.pendingOperation)
        }
    }

    func testExplicitCommittedNominalJobClosesOnlyItsPriorUndecidedScope() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        for source in [
            Self.gardenScatteredLongCapture,
            "I have not decided to spend a weekend on the labels. A definite job is to return Mira's watering can tomorrow. It is the one with the narrow spout, and the detachable rose belongs with it."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source, referenceDate: reference, calendar: calendar)
            let returns = result.items.filter { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("return Mira") }
            XCTAssertEqual(returns.count, 1, source)
            XCTAssertFalse(returns.first?.needsReview ?? true)
            XCTAssertEqual(returns.first?.organization.temporalIntent.day, CalendarDay(year: 2026, month: 10, day: 6))
            XCTAssertNil(returns.first?.organization.temporalIntent.time)
            XCTAssertTrue(returns.first?.sourceQuote.localizedCaseInsensitiveContains("narrow spout") ?? false)
            XCTAssertTrue(returns.first?.sourceQuote.localizedCaseInsensitiveContains("detachable rose") ?? false)
            XCTAssertFalse(returns.first?.sourceQuote.localizedCaseInsensitiveContains("shed key") ?? true)
            XCTAssertNil(result.pendingOperation)
        }
        for source in [
            "Nora said, 'A definite job is to return Mira's watering can tomorrow.'",
            "Text Nora that a definite job is to return Mira's watering can tomorrow.",
            "A possible job is to return Mira's watering can tomorrow, but I have not decided.",
            "An example task is to return Mira's watering can tomorrow."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source, referenceDate: reference, calendar: calendar)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable
                && ActionabilityReader.actionBody($0.analysisText).lowercased().hasPrefix("return") }, source)
            XCTAssertNil(result.pendingOperation, source)
        }
        let independent = ThoughtExtractionEngine.extractWithRules("An actual task is to print the caption. Then call Nora.")
        XCTAssertTrue(independent.items.contains { $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("print the caption") })
        XCTAssertTrue(independent.items.contains { $0.organization.itemType.isActionable && $0.analysisText.localizedCaseInsensitiveContains("call Nora") })
    }

    static let studioWithdrawalLongCapture = """
I am sorting out the little things for the studio, not planning a whole new project. Put replacing the cracked mug on my list. I only need one replacement, and I want the wide handle because the small handles are awkward to hold.

Then there is the printer. I need to check whether it takes the cartridge ending in eighty two or eighty three before ordering anything. Looking up the cartridge is the task; buying both would be a mistake.

Send Jules the photograph of the wall measurements as well. It is the picture with the tape measure still visible, so the numbers can be checked rather than trusted from my memory.

Actually, I already replaced the mug this morning. Take that purchase out of what I just said. Keep the printer check and the message to Jules. I am correcting this recording, not asking you to search for and delete any older mug reminders.
"""

    func testLateCompletedListActionWithdrawsOnlyItsCurrentOccurrence() {
        let source = Self.studioWithdrawalLongCapture
        let repair = SpeechRepairPipeline.run(source, trackOrigins: true)
        let partition = CaptureOperationDetector.partitionWithOwnership(repair.corrected)
        let result = ThoughtExtractionEngine.extractWithRules(source)
        let withdrawal = partition.operations.first { $0.operation == .retract && $0.isScoped }
        XCTAssertNotNil(withdrawal)
        XCTAssertFalse(withdrawal?.needsReview ?? true)
        XCTAssertTrue(withdrawal?.localTargetUnitIDs.isEmpty == false)
        XCTAssertTrue(partition.unownedMeaningfulIDs(in: repair.corrected).isEmpty)
        XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("replac")
            && $0.analysisText.localizedCaseInsensitiveContains("mug") })
        XCTAssertNil(result.pendingOperation, "correcting this capture must never target older saved rows")
        XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("printer") })
        XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("Send Jules") })

        for (text, completed) in [
            ("Put replacing the cracked lid on my list. Check the kettle. Actually, I already replaced the lid this morning. Take that task out of this recording.", true),
            ("Replace the cracked lid. Check the kettle. Actually, I already replaced the lid this morning. Take that task out of this recording.", true),
            ("Put replacing the cracked lid on my list. I have not replaced it yet. Check the kettle.", false),
            ("Put replacing the cracked lid on my list. Nora said, 'I already replaced the lid this morning.' Check the kettle.", false)
        ] {
            let capture = ThoughtExtractionEngine.extractWithRules(text)
            let active = capture.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("replac")
                && $0.analysisText.localizedCaseInsensitiveContains("lid") }
            XCTAssertEqual(active, !completed, text)
            XCTAssertNil(capture.pendingOperation, text)
            XCTAssertTrue(capture.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("check the kettle") }, text)
        }
    }
    static let studioWithdrawalPunctuationLoss = """
i am sorting out the little things for the studio not planning a whole new project put replacing the cracked mug on my list i only need one replacement and i want the wide handle because the small handles are awkward to hold

then there is the printer i need to check whether it takes the cartridge ending in eighty two or eighty three before ordering anything looking up the cartridge is the task buying both would be a mistake

send jules the photograph of the wall measurements as well it is the picture with the tape measure still visible so the numbers can be checked rather than trusted from my memory

actually i already replaced the mug this morning take that purchase out of what i just said keep the printer check and the message to jules i am correcting this recording not asking you to search for and delete any older mug reminders
"""

    func testParagraphSeparatedLocalWithdrawalRetainsItsOriginalActionOwnership() {
        let source = Self.studioWithdrawalPunctuationLoss
        let repair = SpeechRepairPipeline.run(source, trackOrigins: true)
        let partition = CaptureOperationDetector.partitionWithOwnership(repair.corrected)
        let result = ThoughtExtractionEngine.extractWithRules(source)
        XCTAssertTrue(partition.operations.contains { $0.operation == .retract && $0.isScoped && !$0.needsReview })
        XCTAssertTrue(partition.unownedMeaningfulIDs(in: repair.corrected).isEmpty)
        XCTAssertNil(result.pendingOperation)
        XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("mug") })
        XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("check")
            && $0.analysisText.localizedCaseInsensitiveContains("printer") })
        XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("send jules") })
    }

    func testUnpunctuatedCompletionScopeCannotAdoptReportedOrConditionalWords() {
        for source in [
            "Replace the cracked lid. Nora said I already replaced the lid this morning take that task out of this recording",
            "Replace the cracked lid. Text Nora that I already replaced the lid this morning take that task out of this recording",
            "Replace the cracked lid. If I already replaced the lid this morning take that task out of this recording",
            "Replace the cracked lid. Check the kettle. I have not replaced the lid take that task out of this recording"
        ] {
            let partition = CaptureOperationDetector.partitionWithOwnership(source)
            XCTAssertFalse(partition.operations.contains { $0.operation == .retract && $0.isScoped && !$0.needsReview }, source)
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("replace the cracked lid") }, source)
            XCTAssertNil(result.pendingOperation, source)
        }
    }

    func testAmbiguousLocalCompletedWithdrawalKeepsCandidatesAndCannotTargetSavedWork() {
        for source in [
            "Replace the cracked lid. Replace the missing lid. Check the kettle. Actually, I already replaced the lid this morning. Take that task out of this recording.",
            "Replace the cracked lid. Check the kettle. Actually, I already replaced the handle this morning. Take that task out of this recording."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertNil(result.pendingOperation, source)
            XCTAssertTrue(result.items.contains(where: \.needsReview), source)
            XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("check the kettle") }, source)
            XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("replace the cracked lid") }, source)
            XCTAssertTrue(result.operations.allSatisfy { $0.isScoped && $0.needsReview }, source)
        }
    }


    func testUnrelatedScopedWithdrawalCannotLicenseAnUnresolvedCompletion() {
        let source = "Replace the cracked lid. Buy eggs. Skip eggs. Actually, I already replaced the handle this morning. Buy bread."
        let result = ThoughtExtractionEngine.extractWithRules(source)
        XCTAssertTrue(result.items.contains(where: \.needsReview))
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("buy bread") })
        XCTAssertNil(result.pendingOperation)
    }

    func testDeniedEmbeddedOperationKeepsItsComplementScope() {
        let source = "I am correcting this recording, not asking you to search for and delete any older mug reminders."
        let reading = ClauseScope.read(source)
        XCTAssertTrue(reading.deniesComplement)
        let result = ThoughtExtractionEngine.extractWithRules(source)
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertFalse(result.items.contains(where: \.needsReview))
        XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable })
        let original = ThoughtExtractionEngine.extractWithRules(Self.studioWithdrawalLongCapture)
        XCTAssertFalse(original.items.contains { $0.needsReview
            && $0.sourceQuote.localizedCaseInsensitiveContains("delete any older") })
        let messageSource = "Text Nora that I am correcting this recording, not asking you to call and cancel her appointment at eight."
        XCTAssertEqual(ClauseScope.read(messageSource).act, .communicating)
        let message = ThoughtExtractionEngine.extractWithRules(messageSource)
        XCTAssertNil(message.pendingOperation)
        XCTAssertFalse(message.items.contains(where: \.needsReview))
        XCTAssertTrue(message.items.allSatisfy { $0.organization.reminderDate == nil
            && $0.organization.dueDate == nil })
        for text in [
            "I am not asking you to call Nora and cancel her appointment. Also wash the windows.",
            "I am correcting this recording, not asking you to search for and delete older reminders, but I will wash the windows and clean the kitchen."
        ] {
            let capture = ThoughtExtractionEngine.extractWithRules(text)
            XCTAssertNil(capture.pendingOperation, text)
            XCTAssertFalse(capture.items.contains { $0.needsReview
                && $0.sourceQuote.localizedCaseInsensitiveContains("cancel her appointment") }, text)
            XCTAssertTrue(capture.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("wash the windows") }, text)
            if text.contains("clean the kitchen") {
                XCTAssertTrue(capture.items.contains { $0.organization.itemType.isActionable
                    && $0.analysisText.localizedCaseInsensitiveContains("clean the kitchen") }, text)
            }
        }
    }

    func testNegativePerfectStatusContinuesItsOwnActionWithoutInventingWork() {
        for source in [
            "Buy one replacement wide handle mug. I have not bought it yet.",
            "Pack the umbrella. I have not packed it yet."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertEqual(result.items.count, 1, source)
            XCTAssertTrue(result.items.first?.organization.itemType.isActionable ?? false)
            XCTAssertFalse(result.items.contains(where: \.needsReview))
            XCTAssertTrue(result.items.first?.sourceQuote.localizedCaseInsensitiveContains("have not") ?? false)
            XCTAssertNil(result.pendingOperation)
        }
        let independent = ThoughtExtractionEngine.extractWithRules("Buy the mug. I have not packed the umbrella yet.")
        XCTAssertEqual(independent.items.filter { $0.organization.itemType.isActionable }.count, 2)
        let incompatible = ThoughtExtractionEngine.extractWithRules("Call Nora. I have not bought it yet.")
        XCTAssertTrue(incompatible.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("call Nora") })
        XCTAssertTrue(incompatible.items.contains(where: \.needsReview))
        let reported = ThoughtExtractionEngine.extractWithRules("Buy the mug. Nora said, 'I have not bought it yet.'")
        XCTAssertEqual(reported.items.filter { $0.organization.itemType.isActionable }.count, 1)
        XCTAssertTrue(reported.items.contains { $0.organization.itemType == .note && $0.sourceQuote.contains("Nora") })
        XCTAssertNil(reported.pendingOperation)
    }

    func testPhotoIdentityAndNamedOutputRecapKeepTheirExistingOwners() throws {
        let original = ThoughtExtractionEngine.extractWithRules(Self.studioWithdrawalLongCapture)
        let photo = try XCTUnwrap(original.items.first { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("send Jules") })
        XCTAssertTrue(photo.sourceQuote.localizedCaseInsensitiveContains("tape measure still visible"))
        XCTAssertFalse(original.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("keep the printer check") })
        XCTAssertFalse(original.items.contains { $0.needsReview
            && $0.sourceQuote.localizedCaseInsensitiveContains("keep the printer check") })
        let lowercase = ThoughtExtractionEngine.extractWithRules(Self.studioWithdrawalLongCapture.lowercased())
        XCTAssertFalse(lowercase.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("keep the printer check") })
        XCTAssertFalse(lowercase.items.contains { $0.needsReview
            && $0.sourceQuote.localizedCaseInsensitiveContains("keep the printer check") })
        for source in [
            "Send Nora the photograph of the roof. I mean the photograph, not the screenshot.",
            "Send Nora the photograph of the roof. It is the picture with the blue ladder visible."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertEqual(result.items.filter { $0.organization.itemType.isActionable }.count, 1)
            XCTAssertTrue(result.items.first?.sourceQuote.localizedCaseInsensitiveContains(source.contains("screenshot") ? "screenshot" : "blue ladder") ?? false)
            XCTAssertFalse(result.items.contains(where: \.needsReview))
        }
        let retained = ThoughtExtractionEngine.extractWithRules("Check the scanner. Send Nora the photograph of the roof. Keep the scanner check and the message to Nora. Also buy bread.")
        XCTAssertEqual(retained.items.filter { $0.organization.itemType.isActionable }.count, 3)
        XCTAssertFalse(retained.items.contains(where: \.needsReview))
        XCTAssertFalse(retained.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("keep the scanner") })
        for source in [
            "Check the scanner. Send Nora the photograph. Keep the scanner check and the message to Nora in the project folder.",
            "Keep the cupboard and the window closed."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("keep") }, source)
        }
        let quoted = ThoughtExtractionEngine.extractWithRules("Send Nora the photograph. Maya said, 'It is the picture with the blue ladder visible.'")
        XCTAssertTrue(quoted.items.contains { $0.organization.itemType == .note
            && $0.sourceQuote.contains("Maya") })
        XCTAssertNil(quoted.pendingOperation)
    }

    func testExplicitObjectTopicKeepsItsBoundaryAndOwnsOnlyTheAdjacentAction() throws {
        let remainder = try XCTUnwrap(CaptureOperationDetector.partition(Self.studioWithdrawalLongCapture).remainder)
        let parts = RuleBasedThoughtExtractor.splitClauses(remainder)
        XCTAssertFalse(parts.contains { $0.localizedCaseInsensitiveContains("wide handle")
            && $0.localizedCaseInsensitiveContains("there is the printer") })
        let original = ThoughtExtractionEngine.extractWithRules(Self.studioWithdrawalLongCapture)
        XCTAssertTrue(original.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("printer")
            && $0.analysisText.localizedCaseInsensitiveContains("check whether") })
        for source in [
            "There is the scanner. Check whether it needs cleaning.",
            "I prefer a wide handle. Then there is the printer. Check whether it needs ink."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            let target = try XCTUnwrap(result.items.first { $0.organization.itemType.isActionable })
            XCTAssertTrue(target.analysisText.localizedCaseInsensitiveContains(source.contains("scanner") ? "scanner" : "printer"))
            XCTAssertTrue(target.sourceQuote.localizedCaseInsensitiveContains("there is the"))
            XCTAssertFalse(target.sourceQuote.localizedCaseInsensitiveContains("wide handle"))
            XCTAssertFalse(target.needsReview)
            XCTAssertNil(target.organization.dueDate)
            XCTAssertNil(target.organization.reminderDate)
        }
        for source in [
            "There is the printer. Nora prefers oat milk. Check whether it needs ink.",
            "There is the printer and the scanner. Check whether it needs cleaning.",
            "Maya said, 'There is the scanner. Check whether it needs cleaning.'"
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("check whether the") }, source)
            XCTAssertNil(result.pendingOperation)
        }
    }

    func testRecipientOccurrenceSurvivesAnActionAdjunctWithoutBecomingMessageTime() {
        for source in ["Email June after Priya approves.", "Email June the final volunteer rota once Priya has approved it.", "Call May tomorrow at 8 PM."] {
            let scope = ClauseScope.read(source)
            let span = scope.recipientRange
            XCTAssertNotNil(span, source)
            if let span { XCTAssertEqual(String(source[span]), source.contains("June") ? "June" : "May") }
            XCTAssertEqual(scope.act, .direct, "a scheduling adjunct is not message content")
            let result = ThoughtExtractionEngine.extractWithRules(source)
            let item = result.items.first
            XCTAssertEqual(item?.organization.personName, source.contains("June") ? "June" : "May")
            if source.contains("June") {
                XCTAssertFalse(item?.needsReview ?? true)
                XCTAssertNil(item?.organization.dueDate)
                XCTAssertNil(item?.organization.reminderDate)
                XCTAssertTrue(item?.analysisText.contains(source.contains("once") ? "once Priya has approved it" : "after Priya approves") ?? false)
            } else {
                XCTAssertNotNil(item?.organization.dueDate)
            }
        }
        let calendarObject = PersonMentionResolver.followUpTarget(in: "Call June 12 at 8 PM.")
        if case .person(let target) = calendarObject { XCTFail("calendar phrase is not a named addressee: \(target.label)") }
        let calendar = ThoughtExtractionEngine.extractWithRules("Remind me to submit the report on June 12 at 8 PM.")
        XCTAssertNil(calendar.items.first?.organization.personName)
        XCTAssertNotNil(calendar.items.first?.organization.dueDate)
        let message = ThoughtExtractionEngine.extractWithRules("Email June that Priya approves the rota at 8 PM.")
        XCTAssertEqual(message.items.first?.organization.personName, "June")
        XCTAssertNil(message.items.first?.organization.reminderDate)
    }

    func testCommunicationObjectConditionKeepsFiniteMessagesDistinctWithAndWithoutTags() {
        let previousTaggerMode = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previousTaggerMode
            SentenceContextCache.invalidate()
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10))!
        let cases: [(String, ClauseScope.SpeechAct)] = [
            ("Email June the final volunteer rota once Priya has approved it.", .direct),
            ("Email June that Priya has approved the rota on Tuesday.", .communicating),
            ("Email June the printer has failed after Priya replaced it on Tuesday.", .communicating)
        ]
        for disablesTagger in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disablesTagger
            SentenceContextCache.invalidate()
            for (source, expectedAct) in cases {
                let scope = ClauseScope.read(source)
                XCTAssertEqual(scope.act, expectedAct, source)
                XCTAssertEqual(scope.recipient, "June", source)
                XCTAssertEqual(scope.recipientRange.map { String(source[$0]) }, "June", source)
                XCTAssertEqual(scope.complementRange == nil, expectedAct == .direct, source)
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: reference, calendar: calendar)
                XCTAssertTrue(result.operations.isEmpty, source)
                XCTAssertEqual(result.items.count, 1, source)
                let item = result.items.first
                XCTAssertEqual(item?.organization.personName, "June", source)
                XCTAssertFalse(item?.needsReview ?? true, source)
                XCTAssertEqual(item?.sourceQuote, source, source)
                XCTAssertNil(item?.organization.dueDate,
                    "The approval condition and historical message date cannot schedule sending: " + source)
                XCTAssertNil(item?.organization.reminderDate, source)
            }
        }
    }

    func testDeniedComplementOccurrencesSurviveMissingMatrixPunctuation() {
        let source = "i am sorting out the little things for the studio not planning a whole new project put replacing the cracked mug on my list i only need one replacement and i want the wide handle because the small handles are awkward to hold\n\nthen there is the printer i need to check whether it takes the cartridge ending in eighty two or eighty three before ordering anything looking up the cartridge is the task buying both would be a mistake\n\nsend jules the photograph of the wall measurements as well it is the picture with the tape measure still visible so the numbers can be checked rather than trusted from my memory\n\nactually i already replaced the mug this morning take that purchase out of what i just said keep the printer check and the message to jules i am correcting this recording not asking you to search for and delete any older mug reminders"
        let ranges = ClauseScope.deniedRequestComplementRanges(in: source)
        XCTAssertTrue(ranges.contains { source[$0].localizedCaseInsensitiveContains("search for and delete") })
        let result = ThoughtExtractionEngine.extractWithRules(source)
        XCTAssertNil(result.pendingOperation)
        XCTAssertFalse(result.items.contains { $0.needsReview
            && $0.sourceQuote.localizedCaseInsensitiveContains("delete any older") })
        for text in [
            "I am correcting this recording not asking you to call Nora and cancel her appointment but I will wash the windows and clean the kitchen.",
            "I need to email Max and I am not asking you to call Nora and cancel her appointment but I will clean the kitchen."
        ] {
            let capture = ThoughtExtractionEngine.extractWithRules(text)
            XCTAssertNil(capture.pendingOperation, text)
            XCTAssertFalse(capture.items.contains { $0.needsReview
                && $0.sourceQuote.localizedCaseInsensitiveContains("cancel her appointment") }, text)
            XCTAssertTrue(capture.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("clean the kitchen") }, text)
            if text.contains("email Max") {
                XCTAssertTrue(capture.items.contains { $0.organization.itemType.isActionable
                    && $0.analysisText.localizedCaseInsensitiveContains("email Max") }, text)
            }
        }
        let affirmative = ThoughtExtractionEngine.extractWithRules("Call Nora and cancel her appointment.")
        XCTAssertTrue(affirmative.pendingOperation != nil || affirmative.items.contains(where: \.needsReview))
    }

    func testLocallyWithdrawnCompletedActionDoesNotCompleteOlderSavedWork() {
        let text = "Call the plumber—wait, no, I already called. "
            + "What I actually need is photograph the leak and clear the cabinet."
        let result = ThoughtExtractionEngine.extractWithRules(text)
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertFalse(result.items.contains { $0.analysisText.lowercased().hasPrefix("call the plumber")
            && $0.organization.itemType.isActionable })
        XCTAssertTrue(result.items.contains { $0.analysisText.lowercased().contains("photograph the leak")
            && $0.organization.itemType.isActionable })
        let fronted = ThoughtExtractionEngine.extractWithRules(
            "For tomorrow, call the plumber—wait, no, I already called. "
                + "Photograph the leak."
        )
        XCTAssertTrue(fronted.operations.isEmpty)
        XCTAssertFalse(fronted.items.contains(where: \.needsReview))
        XCTAssertTrue(fronted.items.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("Photograph the leak") })
        XCTAssertFalse(fronted.items.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("call the plumber") })
        let ambiguousContinuation = ThoughtExtractionEngine.extractWithRules(
            "Call the plumber—wait, no, I already called and the electrician "
                + "answered. Photograph the leak."
        )
        XCTAssertTrue(ambiguousContinuation.items.contains(where: \.needsReview))
        XCTAssertTrue(ambiguousContinuation.items.contains {
            $0.rawQuote.contains("Call the plumber")
        })
        XCTAssertTrue(ambiguousContinuation.items.contains { $0.organization.itemType.isActionable
            && $0.sourceQuote.contains("Photograph the leak") })
        let standalone = ThoughtExtractionEngine.extractWithRules("I already called the plumber")
        XCTAssertEqual(standalone.operations.first?.operation, .complete)
        for prefix in ["Buy ink and call the plumber", "Call the plumber and buy ink"] {
            let mixed = ThoughtExtractionEngine.extractWithRules(
                "\(prefix)—wait, no, I already called. Email the landlord."
            )
            XCTAssertTrue(mixed.operations.isEmpty, prefix)
            XCTAssertTrue(mixed.items.contains { $0.analysisText.lowercased().contains("buy ink")
                && $0.organization.itemType.isActionable }, prefix)
            XCTAssertFalse(mixed.items.contains { $0.analysisText.lowercased().contains("call the plumber")
                && $0.organization.itemType.isActionable }, prefix)
        }
        let ambiguous = ThoughtExtractionEngine.extractWithRules(
            "Call the plumber and call the electrician—wait, no, I already called. Email the landlord."
        )
        XCTAssertTrue(ambiguous.operations.isEmpty)
        XCTAssertEqual(ambiguous.items.count, 2)
        XCTAssertTrue(ambiguous.items[0].needsReview)
        XCTAssertTrue(ambiguous.items[0].rawQuote.contains("call the electrician"))
        XCTAssertTrue(ambiguous.items[1].organization.itemType.isActionable)
        XCTAssertTrue(ambiguous.items[1].sourceQuote.contains("Email the landlord"))
        let noIndependentTail = ThoughtExtractionEngine.extractWithRules(
            "Call the plumber—wait, no, I already called and the electrician answered. "
                + "The electrician sounded tired."
        )
        XCTAssertEqual(noIndependentTail.items.count, 1)
        XCTAssertTrue(noIndependentTail.items[0].needsReview)
        let dependentTail = ThoughtExtractionEngine.extractWithRules(
            "Call the plumber—wait, no, I already called and the electrician answered. "
                + "Email her the invoice."
        )
        XCTAssertTrue(dependentTail.operations.isEmpty)
        XCTAssertEqual(dependentTail.items.count, 2)
        XCTAssertTrue(dependentTail.items.allSatisfy(\.needsReview))
        let independentFact = ThoughtExtractionEngine.extractWithRules(
            "Call the plumber—wait, no, I already called and the electrician answered. "
                + "Remember that the cellar wall is damp."
        )
        XCTAssertEqual(independentFact.items.count, 2)
        XCTAssertTrue(independentFact.items[0].needsReview)
        XCTAssertEqual(independentFact.items[1].organization.itemType, .note)
        XCTAssertFalse(independentFact.items[1].needsReview)
    }

    func testCompletedActionReportCannotWithdrawADifferentLocalTarget() {
        for source in [
            "Call the plumber and buy ink—wait, no, I already called the electrician. Email the landlord.",
            "Buy ink and call the plumber—wait, no, I already called Mom. Email the landlord."
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertTrue(result.operations.isEmpty, source)
            XCTAssertTrue(result.items.contains { $0.rawQuote.lowercased().contains("call the plumber") }, source)
            XCTAssertTrue(result.items.contains(where: \.needsReview), source)
        }
        let matching = ThoughtExtractionEngine.extractWithRules(
            "Call the plumber and buy ink—wait, no, I already called the plumber. Email the landlord."
        )
        XCTAssertTrue(matching.operations.isEmpty)
        XCTAssertFalse(matching.items.contains { $0.analysisText.lowercased().hasPrefix("call the plumber")
            && $0.organization.itemType.isActionable })
        XCTAssertTrue(matching.items.contains { $0.analysisText.lowercased().contains("buy ink")
            && $0.organization.itemType.isActionable })
    }

    func testUncertainLocalCompletionKeepsLaterIndependentIntentsAccessible() {
        let source = "For tomorrow, call the plumber—wait, no, I already called and the visit is booked. "
            + "What I actually need is photograph the leak before the plumber arrives "
            + "and clear the cabinet under the sink tonight. The appointment is at ten "
            + "in the morning, which is context for those steps. Please don't leave me "
            + "a second call-the-plumber job just because I said it first."
        let result = ThoughtExtractionEngine.extractWithRules(source)
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.allSatisfy { !$0.needsReview
            && $0.organization.itemType.isActionable
            && $0.rawQuote.contains("call the plumber")
            && $0.rawQuote.contains("visit is booked")
            && $0.rawQuote.contains("second call-the-plumber job") })
        XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("photograph the leak") })
        XCTAssertTrue(result.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("clear the cabinet") })
        XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().hasPrefix("call the plumber") })
        XCTAssertTrue(result.items.allSatisfy {
            $0.suggestedTitle?.localizedCaseInsensitiveContains("tomorrow") == true
                && $0.suggestedTitle?.localizedCaseInsensitiveContains("ten in the morning") == true
        })
        let photograph = result.items.first {
            $0.analysisText.localizedCaseInsensitiveContains("photograph the leak")
        }
        XCTAssertNil(photograph?.organization.dueDate)
        XCTAssertNil(photograph?.organization.reminderDate)
        XCTAssertEqual(SourceUnitLedger(source).unownedMeaningfulIDs(after: result.items), [])
    }

    func testConfirmedEventDayFromLocalReceiptStaysDisplayContextOnly() {
        let source = "For tomorrow, call the contractor—wait, no, I already called and the visit is booked. "
            + "What I actually need is photograph the damage and move the boxes tonight. "
            + "The visit is at ten in the morning, which is context for those steps."
        let rows = ThoughtExtractionEngine.extractWithRules(source).items
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.organization.itemType.isActionable
            && !$0.needsReview
            && $0.suggestedTitle?.localizedCaseInsensitiveContains("tomorrow") == true
            && $0.suggestedTitle?.localizedCaseInsensitiveContains("ten in the morning") == true })
        let photograph = rows.first { $0.analysisText.localizedCaseInsensitiveContains("photograph") }
        XCTAssertNotNil(photograph)
        XCTAssertNil(photograph?.organization.dueDate)
        XCTAssertNil(photograph?.organization.reminderDate)
        let boxes = rows.first { $0.analysisText.localizedCaseInsensitiveContains("boxes") }
        XCTAssertNotNil(boxes?.organization.dueDate)

        let competing = ThoughtExtractionEngine.extractWithRules(
            "For tomorrow, call the contractor—wait, no, I already called and the visit is booked. "
                + "What I actually need is photograph the damage and move the boxes tonight. "
                + "Another visit is Friday. The visit is at ten in the morning, "
                + "which is context for those steps."
        ).items
        XCTAssertFalse(competing.filter { $0.analysisText.localizedCaseInsensitiveContains("photograph") }
            .contains { $0.suggestedTitle?.localizedCaseInsensitiveContains("tomorrow") == true })
        let differentEvent = ThoughtExtractionEngine.extractWithRules(
            "For tomorrow, call the contractor—wait, no, I already called and the visit is booked. "
                + "What I actually need is photograph the damage and move the boxes tonight. "
                + "The delivery is at ten in the morning, which is context for those steps."
        ).items
        XCTAssertFalse(differentEvent.filter { $0.analysisText.localizedCaseInsensitiveContains("photograph") }
            .contains { $0.suggestedTitle?.localizedCaseInsensitiveContains("tomorrow") == true })
    }

    func testRecordedCalendarStatusDoesNotCreateANewTodayEvent() {
        let status = ThoughtExtractionEngine.extractWithRules(
            "I checked and the visit is still on my calendar. Buy envelopes."
        )
        XCTAssertTrue(status.items.contains { $0.organization.itemType == .note
            && $0.rawQuote.localizedCaseInsensitiveContains("visit") })
        XCTAssertFalse(status.items.contains { $0.organization.itemType == .event })
        XCTAssertTrue(status.items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.localizedCaseInsensitiveContains("buy envelopes") })

        let direct = ThoughtExtractionEngine.extractWithRules(
            "The visit is tomorrow at ten in the morning."
        )
        XCTAssertTrue(direct.items.contains { $0.organization.itemType == .event })
        let request = ThoughtExtractionEngine.extractWithRules(
            "Remind me about the visit tomorrow at ten in the morning."
        )
        XCTAssertTrue(request.items.contains { $0.organization.itemType.isActionable })
        let uncertain = ThoughtExtractionEngine.extractWithRules(
            "I checked whether the visit is on the calendar."
        )
        XCTAssertFalse(uncertain.items.isEmpty)
    }

    func testLocalCompletionResultKeepsWithdrawnIdentityWithoutOperatingOnSavedTask() {
        for result in ["the visit is booked", "the appointment is confirmed", "the reply came"] {
            let source = "Call the plumber—wait, no, I already called and \(result). Photograph the leak."
            let reading = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertTrue(reading.operations.isEmpty, source)
            XCTAssertEqual(reading.items.count, 2, source)
            XCTAssertEqual(reading.items[0].organization.itemType, .note, source)
            XCTAssertFalse(reading.items[0].needsReview, source)
            XCTAssertTrue(reading.items[0].analysisText.contains("called the plumber"), source)
            XCTAssertTrue(reading.items[0].analysisText.contains(result), source)
            XCTAssertTrue(reading.items[0].rawQuote.contains("Call the plumber"), source)
            XCTAssertTrue(reading.items[1].organization.itemType.isActionable, source)
        }
        for source in [
            "Call the plumber—wait, no, I already called and the electrician answered. Photograph the leak.",
            "Call the plumber—wait, no, I already called the electrician and the visit is booked. Photograph the leak.",
            "Call the plumber and call the electrician—wait, no, I already called and the visit is booked. Photograph the leak."
        ] {
            let reading = ThoughtExtractionEngine.extractWithRules(source)
            XCTAssertTrue(reading.operations.isEmpty, source)
            XCTAssertTrue(reading.items.contains { $0.needsReview
                && $0.rawQuote.contains("Call the plumber") }, source)
            XCTAssertTrue(reading.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.contains("Photograph the leak") }, source)
        }
        let short = ThoughtExtractionEngine.extractWithRules("Call the plumber tomorrow")
        XCTAssertEqual(short.items.count, 1)
        XCTAssertTrue(short.items[0].organization.itemType.isActionable)
    }

    func testCompletionReceiptBelongsToExplicitReplacementGroup() {
        let replacement = ThoughtExtractionEngine.extractWithRules(
            "Email the landlord—wait, no, I already emailed and the reply came. "
                + "What I need instead is file the receipt and call the tenant. "
                + "Don't add another email-the-landlord task."
        )
        XCTAssertTrue(replacement.operations.isEmpty)
        XCTAssertEqual(replacement.items.count, 2)
        XCTAssertTrue(replacement.items.allSatisfy { $0.organization.itemType.isActionable
            && !$0.needsReview && $0.rawQuote.contains("emailed and the reply came")
            && $0.rawQuote.contains("another email-the-landlord task") })

        let competing = ThoughtExtractionEngine.extractWithRules(
            "Call the plumber—wait, no, I already called and the electrician answered. "
                + "What I need instead is photograph the leak."
        )
        XCTAssertTrue(competing.operations.isEmpty)
        XCTAssertTrue(competing.items.contains { $0.needsReview
            && $0.rawQuote.contains("electrician answered") })
        let twoTargets = ThoughtExtractionEngine.extractWithRules(
            "Call the plumber and call the electrician—wait, no, I already called "
                + "and the visit is booked. What I need instead is photograph the leak."
        )
        XCTAssertTrue(twoTargets.operations.isEmpty)
        XCTAssertTrue(twoTargets.items.contains { $0.needsReview
            && $0.rawQuote.contains("call the electrician") })
        let unrelatedOutput = ThoughtExtractionEngine.extractWithRules(
            "Call the plumber—wait, no, I already called and the visit is booked. "
                + "What I need instead is buy milk. Don't add another electrician reminder."
        )
        XCTAssertTrue(unrelatedOutput.items.contains { $0.rawQuote.contains("electrician") })
        XCTAssertFalse(unrelatedOutput.items.contains { $0.organization.itemType.isActionable
            && $0.rawQuote.contains("electrician") })
        let short = ThoughtExtractionEngine.extractWithRules("Instead I need to file the receipt")
        XCTAssertEqual(short.items.count, 1)
        XCTAssertTrue(short.items[0].organization.itemType.isActionable)
    }

    func testCompletionReceiptMapsRepairedTailToOriginalWordOccurrences() {
        let source = "Email the landlord—wait, no, I already emailed and the reply came. "
            + "What I need instead is um file the receipt and call the tenant. "
            + "Don't add another email-the-landlord task."
        let reading = ThoughtExtractionEngine.extractWithRules(source)
        XCTAssertTrue(reading.operations.isEmpty)
        XCTAssertEqual(reading.items.count, 2)
        let words = SourceUnitLedger(source).words
        let fileID = words.firstIndex { $0.text == "file" }
        let callID = words.firstIndex { $0.text == "call" }
        let fillerID = words.firstIndex { $0.text == "um" }
        let file = reading.items.first { $0.analysisText.localizedCaseInsensitiveContains("file the receipt") }
        let call = reading.items.first { $0.analysisText.localizedCaseInsensitiveContains("call the tenant") }
        XCTAssertNotNil(fileID)
        XCTAssertNotNil(callID)
        XCTAssertNotNil(fillerID)
        if let fileID { XCTAssertTrue(file?.sourceUnitIDs.contains(fileID) == true) }
        if let callID { XCTAssertTrue(call?.sourceUnitIDs.contains(callID) == true) }
        if let fillerID { XCTAssertFalse(file?.sourceUnitIDs.contains(fillerID) == true) }
    }

    func testProposalAndKnowledgeOwnActionShapedComplements() {
        for source in [
            "I might buy milk and call Mom",
            "I have an idea to buy milk and call Mom"
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 1, source)
            XCTAssertFalse(items[0].organization.itemType.isActionable, source)
            XCTAssertNil(items[0].organization.dueDate, source)
            XCTAssertTrue(items[0].rawQuote.lowercased().contains("call mom"), source)
        }
        // A knowledge or retention frame does not erase an explicit
        // obligation whose actor is the speaker. The two independent actions
        // remain independently available on Today.
        for source in [
            "Remember that I should buy milk and call Mom",
            "I learned that I need to buy milk and call Mom"
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(source).items
            XCTAssertEqual(items.count, 2, source)
            XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable }, source)
            XCTAssertTrue(items[0].sourceQuote.lowercased().contains("buy milk"), source)
            XCTAssertTrue(items[1].sourceQuote.lowercased().contains("call mom"), source)
        }
        let reportedOther = ThoughtExtractionEngine.extractWithRules(
            "I learned that Mom needs to buy milk and call me"
        ).items
        XCTAssertEqual(reportedOther.count, 1)
        XCTAssertEqual(reportedOther[0].organization.itemType, .note)
        let direct = ThoughtExtractionEngine.extractWithRules("I will buy milk and call Mom").items
        XCTAssertEqual(direct.count, 2)
        XCTAssertTrue(direct.allSatisfy { $0.organization.itemType.isActionable })
        let pivot = ThoughtExtractionEngine.extractWithRules(
            "I might buy milk, but I will call Mom"
        ).items
        XCTAssertEqual(pivot.count, 2)
        XCTAssertFalse(pivot[0].organization.itemType.isActionable)
        XCTAssertTrue(pivot[1].organization.itemType.isActionable)
    }

    func testUnrelatedClockRepairDoesNotSuppressAnExistingTaskCompletion() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow at 230, buy milk. Wait, no, I already called Mom."
        )
        XCTAssertEqual(result.operations.first?.operation, .complete)
    }

    private func clauses(_ text: String) -> [String] {
        RuleBasedThoughtExtractor.splitClauses(text)
    }

    private func verdict(_ text: String) -> IntentConsolidator.Consolidation? {
        IntentConsolidator.consolidate(text, clauses: clauses(text))
    }

    func testHedgedIndependentErrandsRemainIndependent() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "I keep meaning to book the dentist and I have to call the bank about the fee and honestly I should just cancel the gym membership"
        )
        XCTAssertEqual(result.items.count, 3)
        for word in ["dentist", "bank", "gym"] {
            XCTAssertTrue(result.items.contains { $0.sourceQuote.contains(word) })
        }
        XCTAssertTrue(result.items.allSatisfy { $0.organization.itemType.isActionable })
    }

    func testPreparatoryPostureAndModalAdverbStayWithTheirAction() {
        for text in [
            "I think I need to sit down and finally do my taxes this weekend",
            "I should rarely call Dana about the refund"
        ] {
            XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(text).items.count, 1, text)
        }
    }

    // MARK: It collapses narrative

    func testNarrativeElaborationCollapsesToItsHeadIntention() {
        let text = "Okay so I've been meaning to do this forever, I keep forgetting, "
            + "and I really need to remember to call the dentist tomorrow "
            + "because I need to ask about my appointment"
        let result = verdict(text)

        XCTAssertNotNil(result, "three clauses, one phone call")
        XCTAssertEqual(result?.title, "call the dentist tomorrow")
        XCTAssertEqual(result?.requiresReview, false)
        XCTAssertEqual(
            result?.analysisText,
            "I really need to remember to call the dentist tomorrow",
            "the reason is dropped: it can carry a date of its own"
        )
    }

    func testAPreambleInsideOneClauseIsStillAPreamble() {
        let result = verdict(
            "honestly the main thing is I just need to call the contractor about the quote"
        )
        XCTAssertEqual(result?.title, "call the contractor about the quote")
    }

    func testATrailingAsideIsDroppedFromTheTitle() {
        let result = verdict(
            "Honestly the thing is I just need to book the hotel, I've been putting it off for ages"
        )
        XCTAssertEqual(result?.title, "book the hotel")
    }

    /// Rambling that never arrives anywhere still becomes one item, but the
    /// paragraph itself must not become an enormous, confidently filed row.
    func testRamblingWithNoIntentionBecomesAShortReviewItem() {
        let text = "So I was thinking earlier today about the whole thing with the garage, "
            + "and how it's been kind of a mess for a while now"
        let result = verdict(text)

        XCTAssertEqual(result?.analysisText, text)
        XCTAssertEqual(result?.title, "Review captured thought")
        XCTAssertEqual(result?.requiresReview, true)
    }

    // MARK: It stands aside for anything else

    func testTwoIndependentIntentionsAreLeftToTheSplitter() {
        XCTAssertNil(verdict("Call the dentist tomorrow, buy milk, and remember Catherine is allergic to peanuts"))
        XCTAssertNil(verdict("The storage code is 4821, and buy detergent"))
        XCTAssertNil(verdict("Remember Alex likes golf and Catherine likes sushi"))
    }

    /// The case that rules out counting substantive clauses on its own.
    ///
    /// "Alex Friday" is not an intention by itself — it has no verb — so a rule
    /// that collapsed whenever it found fewer than two would merge two calls
    /// into one. Nothing here is elaborative, so this stage declines instead.
    func testAnEllipticalSecondClauseIsNotTreatedAsElaboration() {
        XCTAssertNil(verdict("Call Mom tomorrow and Alex Friday"))
    }

    func testAReasonAloneNeverLicensesCollapsing() {
        XCTAssertNil(
            verdict("Call the contractor because I need the quote"),
            "a reason attached to a single intention changes nothing about how many there are"
        )
    }

    func testAListOfObjectsIsUntouched() {
        XCTAssertNil(verdict("Buy milk, eggs and bread"))
    }

    // MARK: Substance

    func testSubstanceIgnoresLeadingDiscourseMarkers() {
        XCTAssertTrue(
            IntentConsolidator.isSubstantive("anyway I want to remember that her birthday is December 4"),
            "\"anyway\" is not what the clause is about"
        )
        XCTAssertTrue(IntentConsolidator.isSubstantive("so buy milk"))
    }

    /// An action pointing back at something already said is not an intention
    /// anybody could act on, and a fact needs far less to stand on than an
    /// action does.
    func testAnActionOnAPronounIsNotSubstantiveButAFactAboutOneIs() {
        XCTAssertFalse(IntentConsolidator.isSubstantive("I've been meaning to do this forever"))
        XCTAssertFalse(IntentConsolidator.isSubstantive("how it's been kind of a mess for a while now"))
        XCTAssertTrue(IntentConsolidator.isSubstantive("remember her birthday is December 4"))
        XCTAssertTrue(IntentConsolidator.isSubstantive("the storage code is 4821"))
    }

    func testCoordinatedSendTargetsShareOneSpokenObject() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous
            SentenceContextCache.invalidate()
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9))!
        let due = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 20))!
        let original = "For the marketing group project, send Jordan and Aisha my slides on competitor pricing by Tuesday night so they can merge everything."
        let opaque = "send velan and sorin my sketches by Tuesday night so they can merge everything."
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            for (source, targets) in [(original, "Jordan and Aisha"), (opaque, "velan and sorin")] {
                XCTAssertEqual(RuleBasedThoughtExtractor.splitIndependentConjuncts(source), [source])
                let result = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: anchor, calendar: calendar)
                XCTAssertEqual(result.items.count, 1, source)
                let row = try XCTUnwrap(result.items.first, source)
                XCTAssertEqual(row.organization.itemType, .task, source)
                XCTAssertEqual(row.organization.state, .resolved, source)
                XCTAssertFalse(row.needsReview, source)
                XCTAssertFalse(row.organization.needsClarification, source)
                XCTAssertEqual(row.organization.dueDate, due, source)
                XCTAssertEqual(row.organization.temporalIntent.kind, .exactDateTime, source)
                XCTAssertNil(row.organization.reminderDate, source)
                XCTAssertNil(row.organization.locationIntent, source)
                XCTAssertNil(row.organization.recurrenceRule, source)
                XCTAssertNil(row.shoppingGroup, source)
                XCTAssertNotEqual(row.organization.personName, targets, "No composite contact identity")
                XCTAssertTrue(row.analysisText.contains(targets), source)
                XCTAssertTrue(row.analysisText.contains("so they can merge everything"), source)
                XCTAssertTrue(row.sourceQuote.contains(targets), source)
                let literal = try XCTUnwrap(source.range(of: row.sourceQuote), source)
                let ledger = SourceUnitLedger(source)
                XCTAssertEqual(ledger.ids(in: literal), Set(ledger.words.indices), source)
                XCTAssertEqual(row.sourceUnitIDs, ledger.ids(in: literal), source)
                XCTAssertEqual(SourceUnitLedger(row.rawQuote).words.map(\.text), ledger.words.map(\.text), source)
                XCTAssertTrue(result.operations.isEmpty, source)
            }
            let originalRow = try XCTUnwrap(ThoughtExtractionEngine.extractWithRules(original,
                referenceDate: anchor, calendar: calendar).items.first)
            XCTAssertEqual(originalRow.sourceQuote.lowercased()
                .components(separatedBy: "for the marketing group project").count - 1, 1)
            XCTAssertEqual((originalRow.suggestedTitle ?? originalRow.analysisText).lowercased()
                .components(separatedBy: "for the marketing group project").count - 1, 1)
            let shipment = "Send Jordan and Aisha a parcel tomorrow."
            let shipped = ThoughtExtractionEngine.extractWithRules(shipment,
                referenceDate: anchor, calendar: calendar)
            let single = try XCTUnwrap(ThoughtExtractionEngine.extractWithRules(
                "Send Jordan a parcel tomorrow.", referenceDate: anchor, calendar: calendar).items.first)
            XCTAssertEqual(shipped.items.count, 1)
            let parcel = try XCTUnwrap(shipped.items.first)
            XCTAssertEqual(parcel.organization.itemType, .task)
            XCTAssertEqual(parcel.organization.personName, single.organization.personName)
            XCTAssertEqual(parcel.organization.dueDate, single.organization.dueDate)
            XCTAssertEqual(parcel.organization.temporalIntent.kind, single.organization.temporalIntent.kind)
            XCTAssertNil(parcel.organization.reminderDate)
            XCTAssertNil(parcel.organization.locationIntent)
            XCTAssertNil(parcel.organization.recurrenceRule)
            XCTAssertNil(parcel.shoppingGroup)
            XCTAssertEqual(ClauseScope.read(shipment).act, .direct)
            XCTAssertNil(ClauseScope.read(shipment).complementRange)
            XCTAssertEqual(ClauseScope.instructionText(shipment), shipment)
            for source in ["Call Alex and email Casey.",
                           "Send Jordan and Aisha my slides and email Casey my notes.",
                           "Send Jordan my slides and email Aisha my notes.",
                           "Send Jordan my slides and Aisha my notes."] {
                XCTAssertEqual(RuleBasedThoughtExtractor.splitIndependentConjuncts(source).count, 2, source)
                XCTAssertEqual(ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: anchor, calendar: calendar).items.count, 2, source)
            }
            for source in ["Send Jordan and then Aisha my slides.",
                           "Send Jordan and drop off my slides.",
                           "Send Jordan and pick up my slides.",
                           "Send Jordan, and Aisha my slides.",
                           "Send Jordan and I will bring my slides.",
                           "Send Jordan and Aisha is bringing her slides.",
                           "Send Jordan and Aisha tomorrow."] {
                let boundary = try XCTUnwrap(source.range(
                    of: #"(?i)\s+and\s+(?:(?:then|also)\s+)?"#, options: .regularExpression))
                XCTAssertFalse(RuleBasedThoughtExtractor.isSendRecipientCoordinator(in: source,
                    boundary: boundary, head: source.startIndex..<boundary.lowerBound,
                    right: boundary.upperBound..<source.endIndex, reading: ClauseScope.read(source)), source)
                // The initial native run kept and-then, comma-and and the
                // no-object-tomorrow case as one through other existing paths.
                // This local guard promises only to decline those shapes.
                if !["Send Jordan and then Aisha my slides.", "Send Jordan, and Aisha my slides.",
                     "Send Jordan and Aisha tomorrow."].contains(source) {
                    XCTAssertEqual(RuleBasedThoughtExtractor.splitIndependentConjuncts(source).count, 2, source)
                }
            }
            for source in ["Sarah said, \"Send Jordan and Aisha my slides by Tuesday.\"",
                           "The note reads, \"Send Jordan and Aisha my slides by Tuesday.\"",
                           "I will not send Jordan and Aisha my slides by Tuesday.",
                           "We won't send Jordan and Aisha my slides by Tuesday.",
                           "If it rains, send Jordan and Aisha my slides by Tuesday."] {
                let held = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: anchor, calendar: calendar)
                XCTAssertFalse(held.items.contains { $0.organization.itemType.isActionable && !$0.needsReview }, source)
                XCTAssertTrue(held.items.allSatisfy { $0.organization.reminderDate == nil }, source)
                XCTAssertTrue(held.operations.isEmpty, source)
            }
            let denied = "I will not send Jordan and Aisha my slides by Tuesday."
            let deniedBoundary = try XCTUnwrap(denied.range(of: " and "))
            XCTAssertFalse(RuleBasedThoughtExtractor.isSendRecipientCoordinator(in: denied,
                boundary: deniedBoundary, head: denied.startIndex..<deniedBoundary.lowerBound,
                right: deniedBoundary.upperBound..<denied.endIndex, reading: ClauseScope.read(denied)))
            XCTAssertTrue(ThoughtOrganizer.isNegatedOwnCommitment(denied.lowercased()))
            XCTAssertEqual(ClauseScope.read(denied).act, .direct)
            XCTAssertFalse(ClauseScope.read(denied).deniesComplement)
            XCTAssertEqual(RuleBasedThoughtExtractor.splitIndependentConjuncts(denied), [denied])
            let deniedPlural = "We won't send Jordan and Aisha my slides by Tuesday."
            XCTAssertEqual(RuleBasedThoughtExtractor.splitIndependentConjuncts(deniedPlural), [deniedPlural])
            let later = "I will not send Jordan and Aisha my slides, and email Casey my notes on Friday."
            let laterRows = ThoughtExtractionEngine.extractWithRules(later,
                referenceDate: anchor, calendar: calendar).items
            XCTAssertEqual(laterRows.count, 2, later)
            XCTAssertTrue(laterRows.contains { $0.organization.itemType.isActionable
                && $0.analysisText.localizedCaseInsensitiveContains("email Casey") }, later)
            XCTAssertFalse(laterRows.contains { $0.organization.itemType.isActionable
                && $0.analysisText.contains("Aisha") }, later)
            let deferred = "I will not send Jordan and Aisha my slides until I hear from them."
            XCTAssertFalse(ThoughtOrganizer.isNegatedOwnCommitment(deferred.lowercased()))
            let question = "Call Sam and ask if the office is open, and pay rent on Friday."
            let questionRows = ThoughtExtractionEngine.extractWithRules(question,
                referenceDate: anchor, calendar: calendar).items
            XCTAssertEqual(questionRows.count, 2, question)
            XCTAssertEqual(questionRows.filter { $0.organization.personName == "Sam" }.count, 1)
            XCTAssertEqual(questionRows.filter { $0.analysisText.localizedCaseInsensitiveContains("pay rent") }.count, 1)
            for source in ["While I am at home I should call Sam and ask if the office is open, and pay rent on Friday.",
                           "Call Sam and ask if the office is open and pay rent on Friday.",
                           "Call Sam and ask if the office is open, and tell him I'm late.",
                           "Call Sam and ask if the office is open, and he can pay rent.",
                           "Call Sam and ask if the office is open, and will pay rent.",
                           "Call Sam and ask if the office is open, and open.",
                           "Call Sam and ask if the office is open, and open on Friday.",
                           "Call Sam and ask if the office is open, and pay rent if it rains."] {
                let boundary = try XCTUnwrap(source.range(of: " and ", options: .backwards))
                XCTAssertFalse(ClauseScope.hasCoordinatedQuestionCommandBoundary(boundary,
                    rightConjunct: boundary.upperBound..<source.endIndex,
                    in: SentenceContextCache.context(for: source), reading: ClauseScope.read(source)), source)
            }
            for source in ["Jordan and Aisha have my slides.", "Pick up Jordan and Aisha from school."] {
                let rows = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: anchor, calendar: calendar).items
                XCTAssertFalse(rows.contains { $0.organization.itemType == .shopping }, source)
                XCTAssertTrue(rows.allSatisfy { $0.organization.reminderDate == nil
                    && $0.organization.locationIntent == nil && $0.shoppingGroup == nil }, source)
                XCTAssertNotEqual(ClauseScope.read(source).act, .communicating, source)
            }
        }
    }


    func testDeterminedObjectCoordinatorKeepsSharedDirectionalComplement() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous
            SentenceContextCache.invalidate()
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9))!
        let positive: [(String, [String])] = [
            ("Move the towels and the hamper into the hall closet.", ["the towels", "the hamper", "into the hall closet"]),
            ("Put the clean towels and the laundry hamper into the hall closet.", ["the clean towels", "the laundry hamper", "into the hall closet"]),
            ("Please carry my winter coats and the spare blankets onto the top shelf.", ["my winter coats", "the spare blankets", "onto the top shelf"]),
            ("Transfer the velan and the sorin into the quara chamber.", ["the velan", "the sorin", "into the quara chamber"]),
        ]
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            func groupingProof(_ source: String) throws -> Bool {
                let boundary = try XCTUnwrap(source.range(of: " and "))
                return RuleBasedThoughtExtractor.isCoordinatedObjectLocativeBoundary(in: source,
                    boundary: boundary, head: source.startIndex..<boundary.lowerBound,
                    right: boundary.upperBound..<source.endIndex, reading: ClauseScope.read(source))
            }
            for (source, arguments) in positive {
                XCTAssertTrue(try groupingProof(source), source)
                XCTAssertEqual(RuleBasedThoughtExtractor.splitIndependentConjuncts(source), [source])
                let result = ThoughtExtractionEngine.extractWithRules(source, referenceDate: anchor, calendar: calendar)
                XCTAssertEqual(result.items.count, 1, source)
                let row = try XCTUnwrap(result.items.first, source)
                XCTAssertEqual(row.organization.itemType, .task, source)
                XCTAssertEqual(row.organization.state, .resolved, source)
                XCTAssertFalse(row.needsReview, source)
                XCTAssertFalse(row.organization.needsClarification, source)
                for argument in arguments {
                    XCTAssertTrue(row.sourceQuote.localizedCaseInsensitiveContains(argument), source)
                    XCTAssertTrue(row.analysisText.localizedCaseInsensitiveContains(argument), source)
                    XCTAssertTrue((row.suggestedTitle ?? row.analysisText).localizedCaseInsensitiveContains(argument), source)
                }
                let ledger = SourceUnitLedger(source)
                XCTAssertEqual(row.sourceUnitIDs, Set(ledger.words.indices), source)
                XCTAssertEqual(SourceUnitLedger(row.rawQuote).words.map(\.text), ledger.words.map(\.text), source)
                XCTAssertNil(row.organization.personName, source)
                XCTAssertNil(row.organization.dueDate, source)
                XCTAssertNil(row.organization.reminderDate, source)
                XCTAssertEqual(row.organization.temporalIntent.kind, .none, source)
                XCTAssertNil(row.organization.locationIntent, source)
                XCTAssertNil(row.organization.recurrenceRule, source)
                XCTAssertNil(row.shoppingGroup, source)
                XCTAssertTrue(result.operations.isEmpty, source)
            }
            let later = "Put the clean towels and the laundry hamper into the hall closet and call the plumber."
            let parts = RuleBasedThoughtExtractor.splitIndependentConjuncts(later)
            XCTAssertEqual(parts.count, 2, later)
            XCTAssertTrue(parts[0].contains("the clean towels and the laundry hamper into the hall closet"))
            XCTAssertTrue(parts[1].localizedCaseInsensitiveContains("call the plumber"))
            let result = ThoughtExtractionEngine.extractWithRules(later, referenceDate: anchor, calendar: calendar)
            XCTAssertEqual(result.items.count, 2, later)
            XCTAssertTrue(result.items.allSatisfy { $0.organization.itemType == .task && !$0.needsReview })
            let grouped = try XCTUnwrap(result.items.first { $0.analysisText.localizedCaseInsensitiveContains("put the clean towels") })
            let literal = try XCTUnwrap(later.range(of: grouped.sourceQuote))
            XCTAssertEqual(grouped.sourceUnitIDs, SourceUnitLedger(later).ids(in: literal))
            XCTAssertTrue(grouped.sourceQuote.contains(" and the laundry hamper into the hall closet"))
            XCTAssertTrue(result.items.contains { $0.analysisText.localizedCaseInsensitiveContains("call the plumber") })
            XCTAssertTrue(result.operations.isEmpty)
            // Refusal controls make no claim about unsupported legacy outputs.
            for source in [
                "Move the tray and the old guard walks into the storage room.",
                "Take the dog and the kids get into the car.",
                "Move the bags and the boys load into the van.",
                "Move the tray and the pedestal is broken into the storage room.",
                "Move the tray Monday and the pedestal Thursday into the storage room.",
                "Move the tray and clean the pedestal into the storage room.",
                "Move the tray from the kitchen and the pedestal into the storage room.",
                "Move the tray and the pedestal to the storage room.",
                "Move the tray, actually the board and the pedestal into the storage room.",
                "Do not move the tray and the pedestal into the storage room.",
                "I will not move the tray and the pedestal into the storage room.",
                "I need to move the tray and the pedestal into the storage room.",
                "Pat said to move the tray and the pedestal into the storage room.",
                "The note says \"Move the tray and the pedestal into the storage room.\"",
                "If Pat agrees, move the tray and the pedestal into the storage room.",
                "Remember to move the tray and the pedestal into the storage room.",
                "Move the steel files and the pedestal into the storage room.",
            ] { XCTAssertFalse(try groupingProof(source), source) }
        }
    }

    func testOwnedCommunicationQuestionsKeepVisiblePayloadAndScopedTime() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer { SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9))!
        let original = "Call Marco the tile guy to confirm he's starting Thursday at eight, and ask whether he needs the old vanity out first."
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            for source in [original,
                "Call Amina the electrician to confirm she's arriving Monday at nine, and ask whether she needs the fuse board cleared.",
                "Phone Dev the surveyor to check he has the permit, and ask if he wants the side gate unlocked first."] {
                var trace: RuntimeRuleTrace?
                let result = RuleBasedThoughtExtractor.process(source, referenceDate: anchor, calendar: calendar,
                    traceObserver: { trace = $0 })
                XCTAssertEqual(result.items.count, 1, source)
                let item = try XCTUnwrap(result.items.first, source)
                let gap = try XCTUnwrap(source.range(of: #"(?i),?\s+and\s+(?=ask\b)"#, options: .regularExpression))
                let question = String(source[gap.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                let edgeCount = trace?.group?.edges.filter { $0.kind == "communicationQuestion" }.count ?? 0
                if edgeCount != 1 {
                    XCTAssertEqual(edgeCount, 0, "An inline proved purpose needs no synthetic grouping edge")
                    let inline = try XCTUnwrap(ClauseScope.finiteContactPurpose(in: item.sourceQuote))
                    let raw = try XCTUnwrap(ClauseScope.finiteContactPurpose(in: item.rawQuote))
                    XCTAssertTrue(inline.matchesOriginal(raw,
                        normalizedSource: item.sourceQuote, originalSource: item.rawQuote))
                    XCTAssertEqual(SourceUnitLedger(item.sourceQuote).words.map(\.text),
                        SourceUnitLedger(source).words.map(\.text))
                    XCTAssertEqual(item.sourceUnitIDs, Set(SourceUnitLedger(source).words.indices))
                }
                XCTAssertTrue(item.analysisText.contains(question), source)
                let title = ThoughtTitleFormatter.polished(item.suggestedTitle ?? item.sourceQuote,
                    itemType: item.organization.itemType, personName: item.organization.personName)
                XCTAssertTrue(title.localizedCaseInsensitiveContains(question.trimmingCharacters(in: .punctuationCharacters)), source)
                let ledger = SourceUnitLedger(source)
                let ids = ledger.ids(in: source.startIndex..<gap.lowerBound)
                    .union(ledger.ids(in: gap.upperBound..<source.endIndex))
                XCTAssertTrue(ids.isSubset(of: item.sourceUnitIDs), source)
                XCTAssertTrue(item.sourceUnitIDs.subtracting(ids).isSubset(of: ledger.ids(in: gap)), source)
                XCTAssertEqual(SourceUnitLedger(item.rawQuote).words.map(\.text), item.sourceUnitIDs.sorted().map { ledger.words[$0].text })
                XCTAssertTrue(item.organization.itemType.isActionable); XCTAssertFalse(item.needsReview)
                XCTAssertEqual(item.organization.state, .resolved); XCTAssertFalse(item.organization.needsClarification)
                XCTAssertNil(item.organization.dueDate); XCTAssertNil(item.organization.reminderDate)
                XCTAssertEqual(item.organization.temporalIntent.kind, .none)
                XCTAssertNil(item.organization.locationIntent); XCTAssertNil(item.organization.recurrenceRule)
                XCTAssertNil(item.shoppingGroup); XCTAssertTrue(result.operations.isEmpty)
            }
            let timed = "Call Amina tomorrow to confirm she's starting Thursday at nine, and ask whether she needs the garage empty first."
            let owner = try XCTUnwrap(ThoughtExtractionEngine.extractWithRules(
                "Call Amina tomorrow to confirm she's starting Thursday at nine.", referenceDate: anchor, calendar: calendar).items.first)
            let timedResult = ThoughtExtractionEngine.extractWithRules(timed,
                referenceDate: anchor, calendar: calendar)
            let timedMode = disabled ? "forcedMissing" : "native"
            let timedMessage = "\(timedMode): \(timedResult.items.map(\.analysisText))"
            XCTAssertEqual(timedResult.items.count, 1, timedMessage)
            let combined = try XCTUnwrap(timedResult.items.first)
            XCTAssertTrue(combined.analysisText.contains("ask whether she needs the garage empty first"), timedMessage)
            XCTAssertTrue((combined.suggestedTitle ?? combined.sourceQuote)
                .localizedCaseInsensitiveContains("ask whether she needs the garage empty first"), timedMessage)
            XCTAssertEqual(SourceUnitLedger(combined.rawQuote).words.map(\.text),
                combined.sourceUnitIDs.sorted().map { SourceUnitLedger(timed).words[$0].text })
            XCTAssertEqual(combined.organization, owner.organization, "Question contents cannot reschedule the call")
            XCTAssertEqual(combined.organization.temporalIntent.kind, .dateOnly)
            XCTAssertEqual(combined.organization.temporalIntent.day, CalendarDay(year: 2026, month: 11, day: 17))
            for contact in [
                "Call Noor to confirm he’s starting Thursday at eight.",
                "Phone Ellis to check she’s arriving Monday at nine."] {
                let proof = try XCTUnwrap(ClauseScope.finiteContactPurpose(in: contact))
                XCTAssertFalse(proof.executionText(in: contact).contains("Thursday"))
                let item = try XCTUnwrap(ThoughtExtractionEngine.extractWithRules(contact,
                    referenceDate: anchor, calendar: calendar).items.first)
                XCTAssertNil(item.organization.dueDate)
                XCTAssertEqual(item.organization.temporalIntent.kind, .none)
            }
            let outerClock = "Call Amina tomorrow at nine to confirm she's starting Thursday at eight."
            let clocked = try XCTUnwrap(ThoughtExtractionEngine.extractWithRules(outerClock,
                referenceDate: anchor, calendar: calendar).items.first)
            XCTAssertEqual(clocked.organization.temporalIntent.kind, .exactDateTime)
            XCTAssertEqual(clocked.organization.temporalIntent.day, CalendarDay(year: 2026, month: 11, day: 17))
            XCTAssertEqual(clocked.organization.dueDate.map { calendar.component(.hour, from: $0) }, 9)
            let portable = "Call Amina tomorrow to confirm she's starting Thursday at nine."
            let proof = try XCTUnwrap(ClauseScope.finiteContactPurpose(in: portable))
            XCTAssertTrue(proof.matchesOriginal(proof, normalizedSource: portable, originalSource: portable))
            let different = "Call Amina tomorrow to confirm she's starting Monday at eight."
            let differentProof = try XCTUnwrap(ClauseScope.finiteContactPurpose(in: different))
            XCTAssertFalse(proof.matchesOriginal(differentProof,
                normalizedSource: portable, originalSource: different))
            let bodyDigit = "Call Marco to confirm he's coming at 9."
            let bodyWord = "Call Marco to confirm he's coming at nine."
            for (normalized, raw) in [(bodyDigit, bodyWord), (bodyWord, bodyDigit)] {
                let normalizedProof = try XCTUnwrap(ClauseScope.finiteContactPurpose(in: normalized))
                let rawProof = try XCTUnwrap(ClauseScope.finiteContactPurpose(in: raw))
                XCTAssertFalse(normalizedProof.matchesOriginal(rawProof,
                    normalizedSource: normalized, originalSource: raw))
                XCTAssertTrue(normalizedProof.sameExecutionScope(rawProof,
                    normalizedSource: normalized, originalSource: raw))
                let organized = ThoughtOrganizer.organize(normalized,
                    referenceDate: anchor, calendar: calendar, sourceText: raw)
                XCTAssertNil(organized.dueDate)
                XCTAssertNil(organized.reminderDate)
                XCTAssertEqual(organized.temporalIntent.kind, .none)
                XCTAssertEqual(organized.reminderDelivery, .none)
            }
            let ownDigit = "Call Marco at 9 to confirm he's coming."
            let ownWord = "Call Marco at nine to confirm he's coming."
            let ownDigitProof = try XCTUnwrap(ClauseScope.finiteContactPurpose(in: ownDigit))
            let ownWordProof = try XCTUnwrap(ClauseScope.finiteContactPurpose(in: ownWord))
            XCTAssertFalse(ownDigitProof.sameExecutionScope(ownWordProof,
                normalizedSource: ownDigit, originalSource: ownWord))
            let thatMarker = "Call Marco to confirm that he's coming at 9."
            let thatProof = try XCTUnwrap(ClauseScope.finiteContactPurpose(in: thatMarker))
            let bareProof = try XCTUnwrap(ClauseScope.finiteContactPurpose(in: bodyDigit))
            XCTAssertFalse(thatProof.sameExecutionScope(bareProof,
                normalizedSource: thatMarker, originalSource: bodyDigit))
            for declined in [
                "Maya said call Amina to confirm she's starting Thursday at nine.",
                "\"Call Amina to confirm she's starting Thursday at nine.\"",
                "Don't call Amina to confirm she's starting Thursday at nine.",
                "If Maya agrees, call Amina to confirm she's starting Thursday at nine.",
                "Call Amina if she agrees to confirm she's starting Thursday at nine.",
                "Remind me to call Amina to confirm she's starting Thursday at nine.",
                "Call Amina to confirm the appointment at eight.",
                "Call Amina to check on the tile at five.",
                "Call Amina to confirm that's fine at eight.",
                "Call Amina to confirm she's starting Thursday at nine, then call Noor at five.",
                "Call Amina to confirm she's starting Thursday at nine and ask him tomorrow whether he has the keys."
            ] { XCTAssertNil(ClauseScope.finiteContactPurpose(in: declined), declined) }
            // Complete outer frames retain their existing authority. The
            // explicit reminder keeps its literal outer clock; an external
            // prerequisite stays held and cannot authorize an alert.
            for (source, isConditional) in [
                ("Remind me to call Marco to confirm he's coming at eight.", false),
                ("If he's late, call Marco to confirm he's coming at 9.", true)
            ] {
                let held = ThoughtExtractionEngine.extractWithRules(source,
                    referenceDate: anchor, calendar: calendar)
                XCTAssertEqual(held.items.count, 1, source)
                XCTAssertTrue(held.operations.isEmpty, source)
                let item = try XCTUnwrap(held.items.first, source)
                if isConditional {
                    XCTAssertTrue(item.needsReview, source)
                    XCTAssertNil(item.organization.dueDate, source)
                    XCTAssertNil(item.organization.reminderDate, source)
                    XCTAssertEqual(item.organization.reminderDelivery, .none, source)
                } else {
                    let simple = ThoughtExtractionEngine.extractWithRules(
                        "Remind me to call Marco at eight.", referenceDate: anchor, calendar: calendar)
                    XCTAssertEqual(simple.items.count, 1)
                    let literalReminder = try XCTUnwrap(simple.items.first)
                    XCTAssertFalse(item.needsReview, source)
                    XCTAssertEqual(item.organization.state, .resolved, source)
                    let due = try XCTUnwrap(item.organization.dueDate, source)
                    XCTAssertNotNil(item.organization.reminderDate, source)
                    XCTAssertEqual(item.organization.dueDate, literalReminder.organization.dueDate, source)
                    XCTAssertEqual(item.organization.reminderDate, literalReminder.organization.reminderDate, source)
                    XCTAssertEqual(item.organization.reminderDelivery, .notification, source)
                    XCTAssertEqual(calendar.component(.hour, from: due), 20, source)
                }
                let ledger = SourceUnitLedger(source)
                XCTAssertEqual(SourceUnitLedger(item.rawQuote).words.map(\.text),
                    ledger.words.map(\.text), source)
                XCTAssertEqual(item.sourceUnitIDs, Set(ledger.words.indices), source)
                if isConditional {
                    XCTAssertEqual(item.organization.state, .unsupported(.unsupportedCondition), source)
                }
            }
            let later = String(original.dropLast()) + ", and print the invoice."
            let rows = ThoughtExtractionEngine.extractWithRules(later, referenceDate: anchor, calendar: calendar).items
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows.filter { $0.analysisText.contains("ask whether he needs the old vanity out first") }.count, 1)
            XCTAssertEqual(rows.filter { $0.analysisText.localizedCaseInsensitiveContains("print the invoice") }.count, 1)
            for opposed in [
                "Maya said, " + original, "The note says \"" + original + "\"",
                "I will not call Marco the tile guy to confirm he's starting Thursday at eight, and ask whether he needs the old vanity out first.",
                "If Maya agrees, " + original,
                "Call Amina the electrician, and ask Priya whether she has the permit."
            ] {
                var trace: RuntimeRuleTrace?
                _ = RuleBasedThoughtExtractor.process(opposed, referenceDate: anchor, calendar: calendar, traceObserver: { trace = $0 })
                XCTAssertFalse(trace?.group?.edges.contains { $0.kind == "communicationQuestion" } == true, opposed)
            }
        }
    }


    func testOutgoingArtifactDeadlineRestatementKeepsItsOwnTemporalSpan() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        let previousZone = NSTimeZone.default
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        NSTimeZone.default = calendar.timeZone
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous
            SentenceContextCache.invalidate()
            NSTimeZone.default = previousZone
        }
        let anchor = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        let original = "Email the condo board the renovation notice; they want forty-eight hours' warning, so it has to go out by Tuesday morning."
        let fresh = "Email the housing committee the inspection summary; they need two days' notice, so it must go out by Friday morning."
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            for (source, day) in [(original, 17), (fresh, 20)] {
                let proof = try XCTUnwrap(ClauseScope.outgoingArtifactDeadline(in: source), source)
                XCTAssertTrue(proof.matchesOriginal(proof,
                    normalizedSource: source, originalSource: source))
                XCTAssertTrue(String(source[proof.deadlineRange]).hasPrefix("by "))
                XCTAssertFalse(proof.executionText(in: source).contains("they "))
                var trace: RuntimeRuleTrace?
                let result = RuleBasedThoughtExtractor.process(source, referenceDate: anchor,
                    calendar: calendar, traceObserver: { trace = $0 })
                XCTAssertTrue(result.operations.isEmpty)
                XCTAssertEqual(result.items.count, 1, String(reflecting: result))
                let row = try XCTUnwrap(result.items.first)
                XCTAssertEqual(row.organization.itemType, .task)
                XCTAssertFalse(row.needsReview)
                XCTAssertEqual(row.sourceQuote, source)
                XCTAssertEqual(row.rawQuote, source)
                XCTAssertTrue(row.analysisText.contains(String(source[proof.artifactRange])))
                XCTAssertTrue(row.analysisText.contains(String(source[proof.reasonRange])))
                XCTAssertEqual(row.organization.temporalIntent.day,
                    CalendarDay(year: 2026, month: 11, day: day))
                // Existing morning convention resolves 9 AM; the source/gold
                // states a morning deadline, not an explicitly spoken hour.
                XCTAssertEqual(row.organization.dueDate, calendar.date(from:
                    DateComponents(year: 2026, month: 11, day: day, hour: 9)))
                XCTAssertNil(row.organization.reminderDate)
                XCTAssertNil(row.organization.recurrenceRule)
                XCTAssertNil(row.organization.locationIntent)
                let traced = try XCTUnwrap(trace)
                XCTAssertEqual(traced.segmentQuotes.count, 1)
                let ledger = SourceUnitLedger(traced.creating)
                XCTAssertEqual(row.sourceUnitIDs, Set(ledger.words.indices))
                XCTAssertTrue(ledger.unownedMeaningfulIDs(after: result.items).isEmpty)
            }
            let changed = original.replacingOccurrences(of: "Tuesday", with: "Friday")
            let originalProof = try XCTUnwrap(ClauseScope.outgoingArtifactDeadline(in: original))
            let changedProof = try XCTUnwrap(ClauseScope.outgoingArtifactDeadline(in: changed))
            XCTAssertFalse(changedProof.matchesOriginal(originalProof,
                normalizedSource: changed, originalSource: original))
            let changedReason = original.replacingOccurrences(of: "forty-eight", with: "two")
            let changedReasonProof = try XCTUnwrap(ClauseScope.outgoingArtifactDeadline(in: changedReason))
            XCTAssertFalse(changedReasonProof.matchesOriginal(originalProof,
                normalizedSource: changedReason, originalSource: original),
                "An independently valid reason cannot replace the original witness")
            for opposed in [
                "Email the board that the notice is ready; they want two days' warning, so it has to go out by Tuesday morning.",
                "Mara said, Email the board the notice; they want two days' warning, so it has to go out by Tuesday morning.",
                "Email the board ‘the notice’; they want two days' warning, so it has to go out by Tuesday morning.",
                "Email the board the notice; they want the contractor to start by Tuesday morning.",
                "Email the board the notice; they need the old bathtub outside, so it has to go out by Tuesday morning.",
                "Email the board the notice; they need two days' notice and the old bathtub outside, so it has to go out by Tuesday morning.",
                "Email the board the notice; they need zero days' warning, so it has to go out by Tuesday morning.",
                "Email the board the notice; they want two days' warning, so the contractor has to go out by Tuesday morning.",
                "Email the board the notice; they want two days' warning, so it does not have to go out by Tuesday morning.",
                "Email the board the notice; they want two days' warning, so if approved, it has to go out by Tuesday morning.",
                "Email the board the notice; they want two days' warning, so it might go out by Tuesday morning.",
                "Email the board the notice at 9 AM on Wednesday; they want two days' warning, so it has to go out by Tuesday morning.",
                "Email the board the notice and the draft; they want two days' warning, so it has to go out by Tuesday morning.",
                "Email the board the notice; print the flyer; they want two days' warning, so it has to go out by Tuesday morning.",
                "Email the board the notice in two days; they want two days' warning, so it has to go out by Tuesday morning.",
                "Email the board the notice next week; they want two days' warning, so it has to go out by Tuesday morning.",
                "Email the board the notice in an hour; they want two days' warning, so it has to go out by Tuesday morning.",
                "Email the board the notice later; they want two days' warning, so it has to go out by Tuesday morning.",
                "Email the Friday crew the notice; they want two days' warning, so it has to go out by Tuesday morning.",
                "Email the board the two notices; they want two days' warning, so it has to go out by Tuesday morning.",
                "Email the board the notice; they want two days' warning, so it has to go out by after the plumber leaves.",
                "Email the board the notice; they want two days' warning, so it has to go out by before the plumber leaves.",
                "Email the board the notice; they want two days' warning, so it has to go out by during the meeting.",
                "Email the board the notice; they want two days' warning, so it has to go out by every Tuesday morning.",
                "Email the board the notice; they want two days' warning, so it has to go out by each Tuesday morning."
            ] {
                XCTAssertNil(ClauseScope.outgoingArtifactDeadline(in: opposed), opposed)
            }
        }
    }
}


extension IntentConsolidationTests {
    func testPartialNumberedWorkKeepsLiteralObjectAndOwnedDeadline() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation, previousZone = NSTimeZone.default
        defer { NSTimeZone.default = previousZone; SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        NSTimeZone.default = calendar.timeZone
        let anchor = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        let original = "The stats problem set is due Wednesday at midnight and I've only done questions one through four, so I need to finish five through nine."
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            let mode = "taggerDisabled=\(disabled)"
            for (source, artifact, unit, remaining, day, hour) in [
                (original, "The stats problem set", "questions", "five through nine", 18, 0),
                ("My calculus assignment is due Friday at noon and I have only completed exercises one through two, so I need to finish three through six.",
                 "My calculus assignment", "exercises", "three through six", 20, 12),
                ("Our algebra problem set is due Thursday at noon and we've only finished questions two through five, so we have to complete six through eight.",
                 "Our algebra problem set", "questions", "six through eight", 19, 12)
            ] {
                let message = mode + ": " + source
                let role = try XCTUnwrap(ClauseScope.partialNumberedWork(in: source), message)
                XCTAssertEqual(String(source[role.artifactRange]), artifact, message)
                XCTAssertEqual(String(source[role.unitRange]), unit, message)
                XCTAssertEqual(String(source[role.remainingRange]), remaining, message)
                var trace: RuntimeRuleTrace?
                let result = RuleBasedThoughtExtractor.process(source, referenceDate: anchor,
                    calendar: calendar, traceObserver: { trace = $0 })
                XCTAssertEqual(result.items.count, 1, message)
                let row = try XCTUnwrap(result.items.first, message)
                XCTAssertEqual(row.organization.itemType, .task, message)
                XCTAssertEqual(row.organization.state, .resolved, message)
                XCTAssertFalse(row.needsReview, message)
                XCTAssertFalse(row.organization.needsClarification, message)
                XCTAssertEqual(row.sourceQuote, source, message)
                XCTAssertEqual(row.rawQuote, source, message)
                XCTAssertEqual(row.analysisText, source, message)
                let title = try XCTUnwrap(row.suggestedTitle, message)
                XCTAssertTrue(title.localizedCaseInsensitiveContains(artifact), message)
                XCTAssertTrue(title.localizedCaseInsensitiveContains(unit + " " + remaining), message)
                // Intentional deadline contract: the spoken day remains the
                // named day; literal midnight resolves at its exclusive end.
                XCTAssertEqual(row.organization.dueDate, calendar.date(from:
                    DateComponents(year: 2026, month: 11, day: hour == 0 ? day + 1 : day, hour: hour)), message)
                XCTAssertEqual(row.organization.temporalIntent.deadlineBoundary,
                    hour == 0 ? .endOfNamedDay : nil, message)
                XCTAssertEqual(row.organization.temporalIntent.day,
                    CalendarDay(year: 2026, month: 11, day: day), message)
                XCTAssertEqual(row.organization.temporalIntent.time,
                    WallClockTime(hour: hour, minute: 0), message)
                XCTAssertNil(row.organization.reminderDate, message)
                XCTAssertEqual(row.organization.reminderDelivery, .none, message)
                XCTAssertNil(row.organization.personName, message)
                XCTAssertNil(row.organization.locationIntent, message)
                XCTAssertNil(row.organization.recurrenceRule, message)
                XCTAssertNil(row.shoppingGroup, message)
                XCTAssertTrue(result.operations.isEmpty, message)
                let proof = try XCTUnwrap(trace, message)
                XCTAssertEqual(proof.output, result.items, message)
                XCTAssertEqual(proof.segmentQuotes.count, 1, message)
                let ledger = SourceUnitLedger(proof.creating)
                XCTAssertEqual(row.sourceUnitIDs, Set(ledger.words.indices), message)
                XCTAssertTrue(ledger.unownedMeaningfulIDs(after: result.items).isEmpty, message)
            }
            let changed = original.replacingOccurrences(of: "five through nine", with: "five through ten")
            let sourceProof = try XCTUnwrap(ClauseScope.partialNumberedWork(in: original), mode)
            let changedProof = try XCTUnwrap(ClauseScope.partialNumberedWork(in: changed), mode)
            XCTAssertFalse(changedProof.matchesOriginal(sourceProof,
                normalizedSource: changed, originalSource: original), mode)
            let mismatched = ThoughtOrganizer.organize(changed, referenceDate: anchor,
                calendar: calendar, sourceText: original)
            XCTAssertTrue(mismatched.needsClarification, mode)
            XCTAssertNil(mismatched.dueDate, mode)
            for opposed in [
                "Mara said, " + original,
                "\"" + original + "\"",
                "If approved, " + original,
                original.replacingOccurrences(of: "I've only done", with: "Mara has only done"),
                original.replacingOccurrences(of: "I need to finish", with: "Mara needs to finish"),
                original.replacingOccurrences(of: "I've only done", with: "I haven't done"),
                original.replacingOccurrences(of: "I need to finish", with: "I do not need to finish"),
                original.replacingOccurrences(of: "problem set is", with: "problem set and the assignment is"),
                original.replacingOccurrences(of: "so I need", with: "actually, so I need"),
                original.replacingOccurrences(of: "one through four", with: "four through one"),
                original.replacingOccurrences(of: "Wednesday at midnight", with: "Monday and Tuesday"),
                original.replacingOccurrences(of: "Wednesday at midnight", with: "Friday or Monday"),
                original.replacingOccurrences(of: "Wednesday at midnight", with: "before Monday and Tuesday"),
                original.replacingOccurrences(of: "Wednesday at midnight", with: "after Monday or Tuesday"),
                original.replacingOccurrences(of: "five through nine", with: "four through nine"),
                original.replacingOccurrences(of: "five through nine", with: "nine through five"),
                original.replacingOccurrences(of: "I need to finish", with: "we need to finish"),
                "The library book is due Wednesday at midnight and I've only done chapters one through four, so I need to finish five through nine.",
                "The stats problem set is due Wednesday at midnight and I've only done hours one through four, so I need to finish five through nine.",
                original + " Call Pat."
            ] {
                // These are source-role refusals, not new claims about old
                // unsupported pipeline outcomes.
                XCTAssertNil(ClauseScope.partialNumberedWork(in: opposed), mode + ": " + opposed)
            }
            let later = original + " Call Pat."
            let result = RuleBasedThoughtExtractor.process(later, referenceDate: anchor, calendar: calendar)
            XCTAssertEqual(result.items.count, 2, mode)
            let work = try XCTUnwrap(result.items.first { ClauseScope.partialNumberedWork(in: $0.sourceQuote) != nil }, mode)
            let call = try XCTUnwrap(result.items.first { $0.analysisText.localizedCaseInsensitiveContains("call Pat") }, mode)
            XCTAssertEqual(work.sourceQuote, original, mode)
            XCTAssertTrue(work.sourceUnitIDs.isDisjoint(with: call.sourceUnitIDs), mode)
            XCTAssertEqual(work.sourceUnitIDs.union(call.sourceUnitIDs), Set(SourceUnitLedger(later).words.indices), mode)
            XCTAssertTrue(result.operations.isEmpty, mode)
        }
    }
    func testOwnedRetailCartBindsOnlyItsExactResolvedPurchaseGroup() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation, previousZone = NSTimeZone.default
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate()
            NSTimeZone.default = previousZone
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        NSTimeZone.default = calendar.timeZone
        let anchor = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        let original = "Order the thirty-six inch white vanity that's sitting in my Wayfair cart today, because shipping says five to seven days."
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            let mode = "disabled=\(disabled)"
            for (source, store) in [
                (original, "Wayfair"),
                ("Buy batteries in my Costco cart today.", "Costco"),
                ("Order a lamp that's sitting in our IKEA cart today.", "Ikea"),
                ("Buy batteries in my Amazon shopping cart today.", "Amazon")
            ] {
                let cart = try XCTUnwrap(ShoppingGroupParser.ownedRetailCartContext(in: source), mode)
                XCTAssertEqual(cart.store.caseInsensitiveCompare(store), .orderedSame, mode)
                XCTAssertTrue(cart.matchesOriginal(cart, source: source, originalSource: source), mode)
                XCTAssertTrue(String(source[cart.cartRange]).contains("cart"), mode)
                var trace: RuntimeRuleTrace?
                let result = RuleBasedThoughtExtractor.process(source, referenceDate: anchor,
                    calendar: calendar, traceObserver: { trace = $0 })
                XCTAssertEqual(result.items.count, 1, mode + String(reflecting: result))
                let row = try XCTUnwrap(result.items.first, mode)
                XCTAssertEqual(row.organization.itemType, .shopping, mode)
                XCTAssertFalse(row.needsReview, mode)
                XCTAssertEqual(row.organization.state, .resolved, mode)
                XCTAssertEqual(row.shoppingGroup, cart.store, mode)
                XCTAssertEqual(row.sourceQuote, source, mode); XCTAssertEqual(row.rawQuote, source, mode)
                XCTAssertEqual(row.organization.temporalIntent.kind, .dateOnly, mode)
                XCTAssertEqual(row.organization.temporalIntent.day, CalendarDay(year: 2026, month: 11, day: 16), mode)
                XCTAssertNil(row.organization.temporalIntent.time, mode)
                XCTAssertEqual(row.organization.dueDate, calendar.startOfDay(for: anchor), mode)
                XCTAssertNil(row.organization.reminderDate, mode); XCTAssertNil(row.organization.personName, mode)
                XCTAssertNil(row.organization.locationIntent, mode); XCTAssertNil(row.organization.recurrenceRule, mode)
                XCTAssertTrue(result.operations.isEmpty, mode)
                let traced = try XCTUnwrap(trace, mode)
                XCTAssertEqual(row.sourceUnitIDs, Set(SourceUnitLedger(traced.creating).words.indices), mode)
                var proposed = row; proposed.shoppingGroup = "Home Depot"
                let regrouped = ThoughtExtractionEngine.shapingShoppingResult(
                    .init(items: [proposed], method: .appleIntelligence), transcript: source)
                XCTAssertEqual(regrouped.items, [row], mode + ": grouping is the only changed row field")
                var generic = row; generic.shoppingGroup = ShoppingGroupStore.fallbackGroup
                let fabricated = ThoughtExtractionEngine.shapingShoppingResult(
                    .init(items: [generic], method: .appleIntelligence), transcript: "Print the invoice.")
                XCTAssertEqual(fabricated.items.first?.shoppingGroup, ShoppingGroupStore.fallbackGroup,
                    mode + ": matching row quote fields cannot invent a capture occurrence")
            }
            for merchant in ["Wayfair", "Etsy", "eBay", "Chewy", "Best Buy", "No Frills"] {
                XCTAssertTrue(ShoppingGroupParser.isRecognizedStoreName(merchant), mode + ": " + merchant)
                XCTAssertNotNil(ShoppingGroupParser.ownedRetailCartContext(
                    in: "Buy batteries in my \(merchant) cart today."), mode + ": " + merchant)
            }
            let raw = try XCTUnwrap(ShoppingGroupParser.ownedRetailCartContext(in: original), mode)
            for changed in [original.replacingOccurrences(of: "Wayfair", with: "Costco"),
                            original.replacingOccurrences(of: "today", with: "tomorrow"),
                            original.replacingOccurrences(of: "thirty-six", with: "forty-eight")] {
                let current = try XCTUnwrap(ShoppingGroupParser.ownedRetailCartContext(in: changed), mode)
                XCTAssertFalse(current.matchesOriginal(raw, source: changed, originalSource: original), mode)
            }
            for opposed in [
                "Buy batteries in my Cartwood cart today.",
                "Buy batteries in Mom's Costco cart today.",
                "Buy batteries in my Mom's Costco cart today.",
                "Buy batteries in my red Costco cart today.",
                "Buy batteries in my red grocery cart today.",
                "Buy batteries in my Costco grocery cart today.",
                "Buy batteries in my Alice Hardware cart today.",
                "Buy batteries actually in my No Frills cart today.",
                "Buy batteries wait in my No Frills cart today.",
                "Buy batteries from IKEA in my Costco cart today.",
                "Buy new batteries, not the ones in my Costco cart today.",
                "Mara said, Buy batteries in my Costco cart today.",
                "\"Buy batteries in my Costco cart today.\"",
                "Do not buy batteries in my Costco cart today.",
                "Buy batteries in my Costco cart today if approved.",
                "Buy batteries in my Costco cart today and call Mom.",
                "Buy the lamp in my IKEA cart today, so email Lee.",
                "Buy the lamp in my IKEA cart today call Lee.",
                "Buy the lamp in my Wayfair cart on Amazon.",
                "Buy the lamp in my Wayfair cart for the cabin list.",
                "Buy the lamp in my Wayfair cart today, Sam cancels the mirror.",
                "Buy the lamp in my Wayfair cart today, because shipping is from Amazon.",
                "Buy the lamp in my Wayfair cart today, because this is for the cabin list.",
                "The Costco cart is packed for Friday."
            ] {
                XCTAssertNil(ShoppingGroupParser.ownedRetailCartContext(in: opposed), mode + opposed)
            }
            let mixed = original + " Buy screws at Home Depot. Call Mom tomorrow."
            let result = ThoughtExtractionEngine.extractWithRules(mixed, referenceDate: anchor, calendar: calendar)
            let vanity = try XCTUnwrap(result.items.first { $0.sourceQuote == original }, mode)
            let screws = try XCTUnwrap(result.items.first { $0.analysisText.localizedCaseInsensitiveContains("buy screws") }, mode)
            XCTAssertEqual(vanity.shoppingGroup, "Wayfair", mode)
            XCTAssertEqual(screws.shoppingGroup, "Home Depot", mode)
            XCTAssertTrue(vanity.sourceUnitIDs.isDisjoint(with: screws.sourceUnitIDs), mode)
            XCTAssertTrue(result.items.contains { $0.organization.personName == "Mom" && $0.shoppingGroup == nil }, mode)
        }
    }

}


extension IntentConsolidationTests {
    func testLiteralMidnightDeadlineKeepsSpokenDayAndRequiresGoverningRole() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation, previousZone = NSTimeZone.default
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate()
            NSTimeZone.default = previousZone
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        NSTimeZone.default = calendar.timeZone
        let monday = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        let wednesday = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 11, day: 18, hour: 0, minute: 30)))
        let endpoint = try XCTUnwrap(calendar.date(from:
            DateComponents(year: 2026, month: 11, day: 19, hour: 0)))
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            for source in [
                "Submit the report by Wednesday at midnight.",
                "I need to finish the draft no later than Wednesday midnight.",
                "Submit the report by November eighteenth at midnight."
            ] {
                let message = "taggerDisabled=\(disabled): " + source
                let proof = try XCTUnwrap(ClauseScope.midnightDeadline(in: source), message)
                XCTAssertTrue(String(source[proof.deadlineRange]).localizedCaseInsensitiveContains("midnight"), message)
                XCTAssertFalse(String(source[proof.calendarRange]).localizedCaseInsensitiveContains("midnight"), message)
                for anchor in [monday, wednesday] {
                    let direct = ThoughtOrganizer.organize(source, referenceDate: anchor,
                        calendar: calendar, sourceText: source)
                    XCTAssertEqual(direct.itemType, .task, message)
                    XCTAssertEqual(direct.state, .resolved, message)
                    XCTAssertFalse(direct.needsClarification, message)
                    XCTAssertEqual(direct.temporalIntent.deadlineBoundary, .endOfNamedDay, message)
                    XCTAssertEqual(direct.temporalIntent.day, CalendarDay(year: 2026, month: 11, day: 18), message)
                    XCTAssertEqual(direct.temporalIntent.time, WallClockTime(hour: 0, minute: 0), message)
                    XCTAssertEqual(direct.dueDate, endpoint, message)
                    XCTAssertNil(direct.reminderDate, message)
                    XCTAssertEqual(direct.reminderDelivery, .none, message)
                    XCTAssertNil(direct.recurrenceRule, message); XCTAssertNil(direct.locationIntent, message)
                    let result = RuleBasedThoughtExtractor.process(source, referenceDate: anchor, calendar: calendar)
                    XCTAssertEqual(result.items.count, 1, message)
                    let row = try XCTUnwrap(result.items.first, message)
                    XCTAssertEqual(row.sourceQuote, source, message); XCTAssertEqual(row.rawQuote, source, message)
                    XCTAssertEqual(row.organization.temporalIntent, direct.temporalIntent, message)
                    XCTAssertEqual(row.organization.dueDate, endpoint, message)
                    XCTAssertFalse(row.needsReview, message); XCTAssertTrue(result.operations.isEmpty, message)
                    XCTAssertEqual(row.sourceUnitIDs, Set(SourceUnitLedger(source).words.indices), message)
                }
                let drift = source.replacingOccurrences(of: "Wednesday", with: "Thursday")
                    .replacingOccurrences(of: "eighteenth", with: "nineteenth")
                XCTAssertNil(ThoughtOrganizer.organize(source, referenceDate: monday,
                    calendar: calendar, sourceText: drift).temporalIntent.deadlineBoundary, message)
            }
            // A complete primary IS DUE source role does not grant task
            // typing. This existing Event remains outside the Task-only
            // deadline-boundary contract in both lexical modes.
            let eventSource = "The assignment is due at midnight Wednesday."
            let eventProof = try XCTUnwrap(ClauseScope.midnightDeadline(in: eventSource))
            XCTAssertEqual(String(eventSource[eventProof.calendarRange]), "Wednesday")
            for anchor in [monday, wednesday] {
                let event = ThoughtOrganizer.organize(eventSource, referenceDate: anchor,
                    calendar: calendar, sourceText: eventSource)
                XCTAssertEqual(event.itemType, .event)
                XCTAssertNil(event.temporalIntent.deadlineBoundary)
                let eventRows = RuleBasedThoughtExtractor.process(eventSource,
                    referenceDate: anchor, calendar: calendar)
                XCTAssertEqual(eventRows.items.count, 1)
                XCTAssertEqual(eventRows.items.first?.organization.itemType, .event)
                XCTAssertNil(eventRows.items.first?.organization.temporalIntent.deadlineBoundary)
            }
            let outsideMarker = "I need to finish the draft actually no later than Wednesday midnight."
            XCTAssertTrue(SelfCorrectionResolver.hasCorrectionJunction(in: outsideMarker))
            XCTAssertNil(ClauseScope.midnightDeadline(in: outsideMarker),
                "only the governing no-later-than occurrence is exempt")
            let next = ThoughtOrganizer.organize("Submit the report by next Wednesday at midnight.",
                referenceDate: wednesday, calendar: calendar)
            XCTAssertEqual(next.temporalIntent.deadlineBoundary, .endOfNamedDay)
            XCTAssertEqual(next.temporalIntent.day, CalendarDay(year: 2026, month: 11, day: 25))
            XCTAssertEqual(next.dueDate, calendar.date(from:
                DateComponents(year: 2026, month: 11, day: 26, hour: 0)))
            for source in [
                "Remind me at midnight Wednesday.",
                "Book a table for Wednesday at midnight.",
                "The event starts Wednesday at midnight.",
                "Submit the report by Wednesday at 12 AM.",
                "Submit the report by Wednesday at 11:59 PM.",
                "Submit the report by every Wednesday at midnight.",
                "Submit the report by Wednesday or Thursday at midnight.",
                "Submit the report by the beginning of Wednesday at midnight.",
                "Submit the report before Wednesday at midnight.",
                "Submit the report by Wednesday at midnight Pacific time.",
                "Photocopy the letter that's due Wednesday at midnight.",
                "The form that is due Wednesday at midnight.",
                "Sam said submit the report by Wednesday at midnight.",
                "If Sam agrees, submit the report by Wednesday at midnight.",
                "I will not submit the report by Wednesday at midnight.",
                "Record 'Submit the report by Wednesday at midnight.'",
                "Submit the report at 9 AM by Wednesday at midnight.",
                "Submit the report actually by Wednesday midnight.",
                "I need to finish the draft actually no later than Wednesday midnight."
            ] {
                let message = "taggerDisabled=\(disabled): opposed " + source
                XCTAssertNil(ClauseScope.midnightDeadline(in: source), message)
                XCTAssertNil(ThoughtOrganizer.organize(source, referenceDate: monday,
                    calendar: calendar, sourceText: source).temporalIntent.deadlineBoundary, message)
            }
        }
    }
}


extension IntentConsolidationTests {
    func testReservationForTimingIsAValidatedVisibleTargetNotExecution() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation, previousZone = NSTimeZone.default
        defer { NSTimeZone.default = previousZone; SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        NSTimeZone.default = calendar.timeZone
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10)))
        let original = "Book a study room at the engineering library for Friday afternoon for the three of us."
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            let message = "taggerDisabled=\(disabled)"
            let proof = try XCTUnwrap(ClauseScope.bookingTarget(in: original), message)
            XCTAssertEqual(proof.targetRanges.map { String(original[$0]) }, ["for Friday afternoon"], message)
            XCTAssertEqual(proof.partyRange.map { String(original[$0]).trimmingCharacters(in: .whitespaces) },
                "for the three of us", message)
            XCTAssertEqual(String(original[proof.objectRange]).trimmingCharacters(in: .whitespaces),
                "a study room at the engineering library", message)
            let result = ThoughtExtractionEngine.extractWithRules(original, referenceDate: anchor, calendar: calendar)
            XCTAssertEqual(result.items.count, 1, message)
            let row = try XCTUnwrap(result.items.first, message)
            XCTAssertEqual(row.organization.itemType, .task, message)
            XCTAssertEqual(row.organization.state, .resolved, message); XCTAssertFalse(row.needsReview, message)
            XCTAssertEqual(row.organization.temporalIntent, .none, message)
            XCTAssertNil(row.organization.dueDate, message); XCTAssertNil(row.organization.reminderDate, message)
            XCTAssertEqual(row.organization.reminderDelivery, .none, message)
            XCTAssertNil(row.organization.recurrenceRule, message); XCTAssertNil(row.organization.locationIntent, message)
            XCTAssertEqual(row.sourceQuote, original, message); XCTAssertEqual(row.rawQuote, original, message)
            XCTAssertEqual(row.sourceUnitIDs, Set(SourceUnitLedger(original).words.indices), message)
            XCTAssertTrue((row.suggestedTitle ?? row.analysisText).contains("Friday afternoon"), message)
            XCTAssertTrue((row.suggestedTitle ?? row.analysisText).contains("for the three of us"), message)
            XCTAssertTrue(result.operations.isEmpty, message)
            for source in ["Reserve a zorblax for Saturday.", "Book a table for 7 PM.",
                           "Book the hall for Sunday this week.", "Book the hotel for next week.",
                           "Book the room for Friday for four people.", "Reserve the court for 8 tonight.",
                           "Book a table for Friday at Nobu.", "Book a table for 8 tonight at Nobu.",
                           "Book a table for Friday for 4 people at 7 PM.",
                           "Book the Morning Glory room for Friday."] {
                let target = try XCTUnwrap(ClauseScope.bookingTarget(in: source), message + source)
                XCTAssertNotNil(ThoughtOrganizer.bookingTargetTiming(String(source[target.targetRanges[0]]),
                    referenceDate: anchor, calendar: calendar), source)
                let item = ThoughtOrganizer.organize(source, referenceDate: anchor, calendar: calendar, sourceText: source)
                XCTAssertEqual(item.itemType, .task, source); XCTAssertFalse(item.needsClarification, source)
                XCTAssertEqual(item.temporalIntent, .none, source); XCTAssertNil(item.dueDate, source)
                XCTAssertNil(item.reminderDate, source); XCTAssertEqual(item.reminderDelivery, .none, source)
                if source.contains("Morning Glory") {
                    XCTAssertEqual(String(source[target.objectRange]).trimmingCharacters(in: .whitespaces),
                        "the Morning Glory room", source)
                    XCTAssertTrue(target.executionRanges.isEmpty, source)
                    XCTAssertEqual(target.targetRanges.map { String(source[$0]) }, ["for Friday"], source)
                }
            }
            // Date validity remains tested even though a valid reservation
            // target never becomes a booking-execution date.
            for (literal, day) in [
                ("February 29", CalendarDay(year: 2028, month: 2, day: 29)),
                ("February 28", CalendarDay(year: 2027, month: 2, day: 28)),
                ("June 30", CalendarDay(year: 2027, month: 6, day: 30)),
                ("15th August", CalendarDay(year: 2026, month: 8, day: 15)),
                ("the twelfth", CalendarDay(year: 2026, month: 8, day: 12))
            ] {
                let target = try XCTUnwrap(ThoughtOrganizer.bookingTargetTiming("for " + literal,
                    referenceDate: anchor, calendar: calendar), literal)
                XCTAssertEqual(target.day, day, literal)
                let source = "Book the zorblax for " + literal + "."
                let item = ThoughtOrganizer.organize(source, referenceDate: anchor, calendar: calendar, sourceText: source)
                XCTAssertFalse(item.needsClarification, source); XCTAssertNil(item.dueDate, source)
                XCTAssertEqual(item.temporalIntent, .none, source)
            }
            for source in ["Book the appointment for June 31.", "Book the appointment for February 30.",
                           "Book the room for Friday for Monday.", "Book the Friday room for Saturday.",
                           "Book a room at Friday Harbor for Sunday.",
                           "Book a room for Sunday at Friday Harbor."] {
                XCTAssertNotNil(ClauseScope.bookingTarget(in: source), source)
                let item = ThoughtOrganizer.organize(source, referenceDate: anchor, calendar: calendar, sourceText: source)
                XCTAssertTrue(item.needsClarification, source)
                XCTAssertEqual(item.state, .underspecified(.ambiguousTemporalScope), source)
                XCTAssertNil(item.dueDate, source); XCTAssertNil(item.reminderDate, source)
                XCTAssertEqual(item.reminderDelivery, .none, source)
            }
            for (source, day, hour) in [
                ("Book the room on Friday.", 7, Optional<Int>.none),
                ("Book the room by Wednesday for Friday.", 5, Optional<Int>.none),
                ("Book the room tomorrow at 10 AM for Friday afternoon.", 4, Optional(10)),
                ("Book the room Wednesday.", 5, Optional<Int>.none),
                ("Book the room at 9 AM for Friday.", 4, Optional(9))
            ] {
                let item = ThoughtOrganizer.organize(source, referenceDate: anchor, calendar: calendar, sourceText: source)
                XCTAssertEqual(item.temporalIntent.day, CalendarDay(year: 2026, month: 8, day: day), source)
                XCTAssertEqual(item.temporalIntent.time, hour.map { WallClockTime(hour: $0, minute: 0) }, source)
                XCTAssertNotNil(item.dueDate, source); XCTAssertNil(item.reminderDate, source)
            }
            let window = ThoughtOrganizer.organize("Book the car for the tire change next week.",
                referenceDate: anchor, calendar: calendar)
            XCTAssertEqual(window.temporalIntent.kind, .calendarWindow); XCTAssertNil(window.dueDate)
            let count = "Reserve a table for two people at 7 PM."
            XCTAssertNil(ClauseScope.bookingTarget(in: count))
            XCTAssertEqual(ThoughtOrganizer.organize(count, referenceDate: anchor, calendar: calendar)
                .temporalIntent.time, WallClockTime(hour: 19, minute: 0))
            for source in ["Sam said book the room for Friday.", "Sam will book the room for Friday.",
                           "Do not book the room for Friday.", "I will not book the room for Friday.",
                           "If Sam agrees, book the room for Friday.", "Book the room for Friday if Sam agrees.",
                           "Record 'Book the room for Friday.'", "Book 'Friday Night Lights' tomorrow.",
                           "Book the room for Friday and call Sam.", "Reserve a table for two people.",
                           "Buy wine for 9 AM.", "Prepare slides for Monday.", "Did I book the dentist for Tuesday?",
                           "Book report for Friday.", "Reserve fund for Saturday.", "Book that room for Friday."] {
                XCTAssertNil(ClauseScope.bookingTarget(in: source), message + source)
            }
            for source in ["Book the Room 7 for Friday.", "Please book suite 12 for Friday."] {
                let role = try XCTUnwrap(ClauseScope.bookingTarget(in: source), source)
                XCTAssertTrue(role.executionRanges.isEmpty, source)
                XCTAssertTrue(String(source[role.objectRange]).contains(source.contains("Room") ? "Room 7" : "suite 12"), source)
                let heldOrUntimed = ThoughtOrganizer.organize(source, referenceDate: anchor,
                    calendar: calendar, sourceText: source)
                XCTAssertEqual(heldOrUntimed.itemType, .task, source)
                XCTAssertNil(heldOrUntimed.dueDate, source); XCTAssertNil(heldOrUntimed.reminderDate, source)
                XCTAssertEqual(heldOrUntimed.temporalIntent.kind, .none, source)
            }
            let retained = ThoughtOrganizer.organize("Book the appointment for June 31.",
                referenceDate: anchor, calendar: calendar, contentScopeIsMemory: true)
            XCTAssertEqual(retained.itemType, .note)
            XCTAssertEqual(retained.state, .resolved); XCTAssertFalse(retained.needsClarification)
            XCTAssertNil(retained.dueDate); XCTAssertNil(retained.reminderDate)
            for rawMismatch in ["Book the room for Thursday.", "Dana already booked the room for Friday."] {
                let held = ThoughtOrganizer.organize("Book the room for Friday.",
                    referenceDate: anchor, calendar: calendar, sourceText: rawMismatch)
                XCTAssertEqual(held.itemType, .task)
                XCTAssertTrue(held.needsClarification); XCTAssertFalse(held.state.permitsAction)
                XCTAssertEqual(held.state, .underspecified(.ambiguousTemporalScope))
                XCTAssertNil(held.dueDate); XCTAssertNil(held.reminderDate)
                XCTAssertNil(held.recurrenceRule); XCTAssertNil(held.locationIntent)
            }
            let raw = "Book the room at 9 AM for Friday."
            let same = try XCTUnwrap(ClauseScope.bookingTarget(in: raw))
            for changed in ["Book the room at 10 AM for Friday.", "Book the room for Friday.",
                            "Book the room at 9 AM for Saturday."] {
                let other = try XCTUnwrap(ClauseScope.bookingTarget(in: changed))
                XCTAssertFalse(other.matchesOriginal(same, normalizedSource: changed, originalSource: raw), changed)
            }
        }
    }
}

#if DEBUG
extension IntentConsolidationTests {
    func testContactTimingPreferenceKeepsCallContextWithoutBorrowingItsClock() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation, previousZone = NSTimeZone.default
        defer { NSTimeZone.default = previousZone; SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        NSTimeZone.default = calendar.timeZone
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        let original = "Call Grandma Ruth on Saturday morning because it's her birthday, and she likes a call before ten."
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            let mode = "taggerDisabled=\(disabled)"
            for (source, execution, person, day, hour) in [
                (original, "Call Grandma Ruth on Saturday morning", "Grandma Ruth", 21, 9),
                ("Phone Uncle Luis on Friday morning because it's his day off, and he prefers a phone call before eleven.",
                    "Phone Uncle Luis on Friday morning", "Uncle Luis", 20, 9),
                ("Call Catherine tomorrow at eleven AM, and Catherine prefers a call before ten.",
                    "Call Catherine tomorrow at eleven AM", "Catherine", 17, 11)
            ] {
                let message = mode + ": " + source
                let relation = try XCTUnwrap(ClauseScope.contactTimingPreference(in: source), message)
                XCTAssertEqual(relation.executionText(in: source), execution, message)
                XCTAssertTrue(relation.matchesOriginal(relation, normalizedSource: source, originalSource: source), message)
                let result = ThoughtExtractionEngine.extractWithRules(source, referenceDate: anchor, calendar: calendar)
                XCTAssertEqual(result.items.count, 1, message)
                let item = try XCTUnwrap(result.items.first, message)
                XCTAssertEqual(item.sourceQuote, source, message)
                XCTAssertEqual(item.analysisText, source, message)
                XCTAssertEqual(SourceUnitLedger(item.rawQuote).words.map(\.text), SourceUnitLedger(source).words.map(\.text), message)
                XCTAssertEqual(item.sourceUnitIDs, Set(SourceUnitLedger(source).words.indices), message)
                XCTAssertEqual(item.organization.itemType, .personFollowUp, message)
                XCTAssertEqual(item.organization.personName, person, message)
                XCTAssertEqual(item.organization.state, .resolved, message)
                XCTAssertFalse(item.needsReview, message); XCTAssertFalse(item.organization.needsClarification, message)
                XCTAssertEqual(item.organization.dueDate, calendar.date(from:
                    DateComponents(year: 2026, month: 11, day: day, hour: hour)), message)
                XCTAssertEqual(item.organization.temporalIntent.sourceText, execution.lowercased(), message)
                XCTAssertNil(item.organization.reminderDate, message)
                XCTAssertEqual(item.organization.reminderDelivery, .none, message)
                XCTAssertNil(item.organization.locationIntent, message); XCTAssertNil(item.organization.recurrenceRule, message)
                XCTAssertNil(item.shoppingGroup, message); XCTAssertTrue(result.operations.isEmpty, message)
                let title = ThoughtTitleFormatter.polished(item.suggestedTitle ?? item.sourceQuote,
                    itemType: item.organization.itemType, personName: item.organization.personName)
                let preference = String(source[relation.preferenceRange]).trimmingCharacters(in: .punctuationCharacters)
                XCTAssertTrue(title.localizedCaseInsensitiveContains(preference), message)
                if source == original { XCTAssertTrue(title.contains("birthday"), message) }
            }
            // Independent knowledge and later commitments keep their own rows.
            let sushi = "Call Catherine tomorrow, and she likes sushi."
            XCTAssertNil(ClauseScope.contactTimingPreference(in: sushi), mode)
            let independent = ThoughtExtractionEngine.extractWithRules(sushi, referenceDate: anchor, calendar: calendar)
            XCTAssertEqual(independent.items.count, 2, mode)
            XCTAssertTrue(independent.items.contains { $0.organization.itemType.isActionable }, mode)
            XCTAssertTrue(independent.items.contains { !$0.organization.itemType.isActionable
                && $0.sourceQuote.contains("she likes sushi") }, mode)
            let later = String(original.dropLast()) + " and call Pat tomorrow."
            let continued = ThoughtExtractionEngine.extractWithRules(later, referenceDate: anchor, calendar: calendar)
            XCTAssertEqual(continued.items.count, 2, mode + ": " + later)
            let call = try XCTUnwrap(continued.items.first { $0.organization.personName == "Grandma Ruth" }, mode)
            XCTAssertTrue(call.analysisText.contains("she likes a call before ten"), mode)
            XCTAssertEqual(call.organization.dueDate, calendar.date(from:
                DateComponents(year: 2026, month: 11, day: 21, hour: 9)), mode)
            let pat = try XCTUnwrap(continued.items.first { $0.organization.personName == "Pat" }, mode)
            XCTAssertTrue(call.sourceUnitIDs.isDisjoint(with: pat.sourceUnitIDs), mode)
            let independentLink = try XCTUnwrap(later.range(of: " and call Pat", options: .backwards), mode)
            let linkEnd = later.index(independentLink.lowerBound, offsetBy: " and ".count)
            let ledger = SourceUnitLedger(later)
            let connectiveIDs = ledger.ids(in: independentLink.lowerBound..<linkEnd)
            XCTAssertEqual(connectiveIDs.sorted().map { ledger.words[$0].text }, ["and"], mode)
            XCTAssertEqual(SourceUnitLedger(call.sourceQuote).words.map(\.text),
                SourceUnitLedger(original).words.map(\.text), mode)
            XCTAssertEqual(SourceUnitLedger(pat.sourceQuote).words.map(\.text), ["call", "pat", "tomorrow"], mode)
            XCTAssertEqual(continued.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) },
                Set(ledger.words.indices).subtracting(connectiveIDs), mode)
            for declined in [
                "Call Catherine tomorrow, and she likes a call before ten.",
                "Call the florist on Saturday morning because it's her birthday, and she likes a call before ten.",
                "Call Grandma Ruth on Saturday morning because it's his birthday, and he likes a call before ten.",
                "Call her mom tomorrow, and she likes a call before ten.",
                "Call their uncle tomorrow, and he likes a call before ten.",
                "Call our sisters tomorrow, and they prefer a call before ten.",
                "Call Grandma Ruth tomorrow because it's her friend pat, and she likes a call before ten.",
                "Call Catherine tomorrow, and she prefers emails before ten.",
                "Call Catherine tomorrow, and Noor likes a call before ten.",
                "Call Catherine tomorrow, and it likes a call before ten.",
                "Call Catherine and Noor tomorrow, and she likes a call before ten.",
                "Call Catherine tomorrow and print the invoice, and she likes a call before ten.",
                "Call Catherine tomorrow because it's his day off, and she likes a call before ten.",
                "Call Catherine tomorrow because it's her meeting with Noor, and she likes a call before ten.",
                "Mara said to call Catherine tomorrow, and she likes a call before ten.",
                "\"Call Catherine tomorrow, and she likes a call before ten.\"",
                "If she's home, call Catherine tomorrow, and she likes a call before ten.",
                "Do not call Catherine tomorrow, and she likes a call before ten."
            ] { XCTAssertNil(ClauseScope.contactTimingPreference(in: declined), mode + ": " + declined) }
            for (pronoun, recipient, expected) in [
                ("she", "my mom", true), ("he", "our uncle", true), ("they", "my mother", true),
                ("he", "Grandma Ruth", false), ("she", "Uncle Luis", false),
                ("she", "Catherine", false), ("she", "her mom", false), ("they", "our sisters", false)
            ] {
                XCTAssertEqual(PersonMentionResolver.communicationRelationSupportsPronoun(pronoun,
                    recipient: recipient), expected, mode + ": " + recipient + " / " + pronoun)
            }
            let foreign = "Dad is visiting. Call Grandma Ruth on Saturday morning because it's his birthday, and he likes a call before ten."
            let foreignResult = ThoughtExtractionEngine.extractWithRules(foreign, referenceDate: anchor, calendar: calendar)
            XCTAssertTrue(foreignResult.items.contains { !$0.organization.itemType.isActionable
                && $0.analysisText.contains("he likes a call before ten") }, mode + ": " + foreign)
            XCTAssertFalse(foreignResult.items.contains { $0.organization.itemType.isActionable
                && $0.analysisText.contains("he likes a call before ten") }, mode + ": " + foreign)
            let changed = original.replacingOccurrences(of: "before ten", with: "before eleven")
            let originalProof = try XCTUnwrap(ClauseScope.contactTimingPreference(in: original))
            let changedProof = try XCTUnwrap(ClauseScope.contactTimingPreference(in: changed))
            XCTAssertFalse(originalProof.matchesOriginal(changedProof, normalizedSource: original, originalSource: changed), mode)
            let mismatch = ThoughtOrganizer.organize(original, referenceDate: anchor, calendar: calendar, sourceText: changed)
            XCTAssertTrue(mismatch.needsClarification, mode)
            XCTAssertNil(mismatch.dueDate, mode); XCTAssertNil(mismatch.reminderDate, mode)
        }
    }
}
#endif


extension IntentConsolidationTests {
    func testOriginalSentenceLexicalProjectionPreservesOwnedObjectContext() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer { SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        let sentence = "Cover the barbecue and the patio set."
        let part = String(sentence.dropLast())
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            let mode = "taggerDisabled=\(disabled)"
            let parent = SentenceContext(sentence)
            let set = try XCTUnwrap(parent.tokens.last { $0.text == "set" }, mode)
            // This milestone needs the real sentence's native noun reading;
            // missing or different native evidence must fail, not be skipped.
            XCTAssertEqual(set.lexicalClass, disabled ? .otherWord : .noun, mode)
            func project(_ source: String, _ literal: String, _ range: Range<String.Index>) throws -> SentenceContext {
                let context = SentenceContext(source)
                let original = NSRange(range, in: source)
                let projected = try XCTUnwrap(context.projectingLiteralPart(literal, range: original), mode)
                XCTAssertEqual(Data(projected.text.utf8), Data(literal.utf8), mode)
                let expected = context.tokens.filter {
                    let token = NSRange($0.range, in: source)
                    return token.location >= original.location && NSMaxRange(token) <= NSMaxRange(original)
                }
                XCTAssertEqual(projected.tokens.count, expected.count, mode)
                for (actual, retained) in zip(projected.tokens, expected) {
                    let before = NSRange(retained.range, in: source)
                    let after = NSRange(actual.range, in: literal)
                    XCTAssertEqual(actual.text, retained.text, mode)
                    XCTAssertEqual(actual.lexicalClass, retained.lexicalClass, mode)
                    XCTAssertEqual(actual.isPersonalName, retained.isPersonalName, mode)
                    XCTAssertEqual(actual.isOrganizationName, retained.isOrganizationName, mode)
                    XCTAssertEqual(after, NSRange(location: before.location - original.location, length: before.length), mode)
                    XCTAssertGreaterThanOrEqual(after.location, 0, mode)
                    XCTAssertLessThanOrEqual(NSMaxRange(after), literal.utf16.count, mode)
                    XCTAssertEqual(String(literal[actual.range]), retained.text, mode)
                }
                return projected
            }
            let literalRange = try XCTUnwrap(sentence.range(of: part, options: .literal), mode)
            let projected = try project(sentence, part, literalRange)
            XCTAssertEqual(RuleBasedThoughtExtractor.splitIndependentConjuncts(part, lexicalContext: projected), [part], mode)
            let unicodeParent = "🧭 Café note. " + sentence + " Call Vera."
            let unicodeRange = try XCTUnwrap(unicodeParent.range(of: part, options: .literal), mode)
            XCTAssertNotEqual(NSRange(unicodeRange, in: unicodeParent).location,
                unicodeParent[..<unicodeRange.lowerBound].utf8.count, mode)
            _ = try project(unicodeParent, part, unicodeRange)
            let partial = try XCTUnwrap(sentence.range(of: "arbecue", options: .literal), mode)
            XCTAssertNil(parent.projectingLiteralPart("arbecue", range: NSRange(partial, in: sentence)), mode)
            XCTAssertNil(parent.projectingLiteralPart("Call Vera", range: NSRange(literalRange, in: sentence)), mode)
            XCTAssertNil(parent.projectingLiteralPart("x", range: NSRange(location: sentence.utf16.count + 1, length: 1)), mode)
            XCTAssertNil(parent.projectingLiteralPart("", range: NSRange(location: 0, length: 0)), mode)
            let fallback = RuleBasedThoughtExtractor.splitIndependentConjuncts(part)
            XCTAssertEqual(RuleBasedThoughtExtractor.splitIndependentConjuncts(part,
                lexicalContext: SentenceContext("Call Vera.")), fallback, mode)
            let repeated = sentence + " " + sentence
            let first = try XCTUnwrap(repeated.range(of: part, options: .literal), mode)
            let second = try XCTUnwrap(repeated.range(of: part, options: .literal,
                range: first.upperBound..<repeated.endIndex), mode)
            _ = try project(repeated, part, first)
            _ = try project(repeated, part, second)
            // Unique-source lookup declines repeated literals; its existing
            // fragment reading remains the fallback for both occurrences.
            XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses(repeated), fallback + fallback, mode)
            var providerReads = 0
            func suppliedContext() -> SentenceContext? { providerReads += 1; return projected }
            XCTAssertEqual(RuleBasedThoughtExtractor.splitIndependentConjuncts("Call Vera",
                lexicalContext: suppliedContext()), ["Call Vera"], mode)
            XCTAssertEqual(providerReads, 0, mode)
            _ = RuleBasedThoughtExtractor.splitIndependentConjuncts(part, lexicalContext: suppliedContext())
            XCTAssertEqual(providerReads, 1, mode)
            for source in [sentence, "The café is closed. " + sentence + " Call Vera."] {
                let result = ThoughtExtractionEngine.extractWithRules(source, referenceDate: anchor, calendar: calendar)
                let covers = result.items.filter { $0.analysisText.localizedCaseInsensitiveContains("cover the barbecue") }
                XCTAssertEqual(covers.count, 1, mode + ": " + source)
                let row = try XCTUnwrap(covers.first, mode)
                XCTAssertEqual(row.organization.itemType, .task, mode)
                XCTAssertEqual(row.organization.state, .resolved, mode)
                XCTAssertFalse(row.needsReview, mode); XCTAssertFalse(row.organization.needsClarification, mode)
                XCTAssertEqual(SourceUnitLedger(row.sourceQuote).words.map(\.text), SourceUnitLedger(sentence).words.map(\.text), mode)
                XCTAssertEqual(SourceUnitLedger(row.rawQuote).words.map(\.text), SourceUnitLedger(sentence).words.map(\.text), mode)
                for words in ["the barbecue", "the patio set"] {
                    XCTAssertTrue(row.analysisText.contains(words), mode)
                    XCTAssertTrue((row.suggestedTitle ?? row.analysisText).contains(words), mode)
                }
                let occurrence = try XCTUnwrap(source.range(of: sentence, options: .literal), mode)
                XCTAssertEqual(row.sourceUnitIDs, SourceUnitLedger(source).ids(in: occurrence), mode)
                XCTAssertNil(row.organization.dueDate, mode); XCTAssertNil(row.organization.reminderDate, mode)
                XCTAssertEqual(row.organization.temporalIntent.kind, .none, mode)
                XCTAssertNil(row.organization.personName, mode); XCTAssertNil(row.organization.locationIntent, mode)
                XCTAssertNil(row.organization.recurrenceRule, mode); XCTAssertNil(row.shoppingGroup, mode)
                XCTAssertTrue(result.operations.isEmpty, mode)
                if source != sentence {
                    let call = try XCTUnwrap(result.items.first { $0.analysisText.localizedCaseInsensitiveContains("call Vera") }, mode)
                    XCTAssertEqual(call.organization.itemType, .personFollowUp, mode)
                    XCTAssertEqual(call.organization.personName, "Vera", mode)
                    XCTAssertTrue(row.sourceUnitIDs.isDisjoint(with: call.sourceUnitIDs), mode)
                } else { XCTAssertEqual(result.items.count, 1, mode) }
            }
            for source in ["Cover the bicycle and call Vera.", "Cover the bicycle and Sarah hates rain."] {
                XCTAssertEqual(RuleBasedThoughtExtractor.splitClauses(source).count, 2, mode + ": " + source)
            }
            let finite = "Cover the bicycle and the patio set is broken."
            let finitePart = String(finite.dropLast())
            _ = try project(finite, finitePart, try XCTUnwrap(finite.range(of: finitePart, options: .literal), mode))
            // Multiword copula behavior without tagging assets is not qualified
            // by this projection change. A following explicit act still owns
            // its separate source component in either configuration.
            let withCall = finite + " Call Vera."
            let finiteRows = ThoughtExtractionEngine.extractWithRules(withCall, referenceDate: anchor, calendar: calendar)
            let call = try XCTUnwrap(finiteRows.items.first { $0.analysisText.localizedCaseInsensitiveContains("call Vera") }, mode)
            XCTAssertEqual(SourceUnitLedger(call.sourceQuote).words.map(\.text), ["call", "vera"], mode)
            XCTAssertTrue(finiteRows.items.filter { $0.sourceQuote.contains("patio") }.allSatisfy {
                $0.sourceUnitIDs.isDisjoint(with: call.sourceUnitIDs)
            }, mode)
        }
    }
}


extension IntentConsolidationTests {
    func testBookingBarePartySizeLeavesAdjacentAtClockWithTheEstablishedParser() throws {
        let previous=SentenceContext.taggerDisabledForEvaluation,oldZone=NSTimeZone.default
        defer { NSTimeZone.default=oldZone;SentenceContext.taggerDisabledForEvaluation=previous;SentenceContextCache.invalidate() }
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone=try XCTUnwrap(TimeZone(identifier:"America/Toronto"))
        NSTimeZone.default=calendar.timeZone
        let anchor=try XCTUnwrap(calendar.date(from:DateComponents(year:2026,month:8,day:3,hour:10)))
        for disabled in [false,true] {
            SentenceContext.taggerDisabledForEvaluation=disabled;SentenceContextCache.invalidate()
            let mode="taggerDisabled=\(disabled)"
            for (source,count,day,hour) in [
                ("Book a table for four at 7 on Friday","four",7,19),
                ("Book a table for 4 at 7 PM.","4",3,19),
                ("Reserve a table for 3 at 8 PM on Thursday.","3",6,20),
                ("Book a table for six at nine PM on Wednesday.","six",5,21)
            ] {
                let message=mode+": "+source
                XCTAssertNil(ClauseScope.bookingTarget(in:source),message)
                let organization=ThoughtOrganizer.organize(source,referenceDate:anchor,calendar:calendar,sourceText:source)
                let due=try XCTUnwrap(calendar.date(from:DateComponents(year:2026,month:8,day:day,hour:hour)))
                XCTAssertEqual(organization.itemType,.task,message)
                XCTAssertEqual(organization.state,.resolved,message);XCTAssertFalse(organization.needsClarification,message)
                XCTAssertEqual(organization.dueDate,due,message)
                XCTAssertEqual(organization.temporalIntent.kind,.exactDateTime,message)
                XCTAssertEqual(organization.temporalIntent.day,CalendarDay(year:2026,month:8,day:day),message)
                XCTAssertEqual(organization.temporalIntent.time,WallClockTime(hour:hour,minute:0),message)
                XCTAssertNil(organization.reminderDate,message)
                XCTAssertEqual(organization.reminderDelivery,.none,message)
                let result=ThoughtExtractionEngine.extractWithRules(source,referenceDate:anchor,calendar:calendar)
                XCTAssertEqual(result.items.count,1,message)
                let item=try XCTUnwrap(result.items.first,message)
                XCTAssertEqual(item.organization.itemType,.task,message)
                XCTAssertEqual(item.organization.dueDate,due,message)
                XCTAssertFalse(item.needsReview,message);XCTAssertFalse(item.organization.needsClarification,message)
                XCTAssertNil(item.organization.reminderDate,message);XCTAssertNil(item.organization.personName,message)
                XCTAssertNil(item.organization.locationIntent,message);XCTAssertNil(item.organization.recurrenceRule,message)
                XCTAssertNil(item.shoppingGroup,message);XCTAssertTrue(result.operations.isEmpty,message)
                XCTAssertEqual(SourceUnitLedger(item.sourceQuote).words.map(\.text),SourceUnitLedger(source).words.map(\.text),message)
                XCTAssertEqual(SourceUnitLedger(item.rawQuote).words.map(\.text),SourceUnitLedger(source).words.map(\.text),message)
                XCTAssertEqual(item.sourceUnitIDs,Set(SourceUnitLedger(source).words.indices),message)
                XCTAssertTrue((item.suggestedTitle ?? item.analysisText).localizedCaseInsensitiveContains("for "+count),message)
                XCTAssertTrue((item.suggestedTitle ?? item.analysisText).localizedCaseInsensitiveContains("table"),message)
            }
            // A bare FOR clock remains the deliberate reservation target;
            // explicit meridiem, colon time and calendar target do too.
            for source in ["Book a table for 7.","Book a table for 7 PM.",
                           "Book a table for 7:30.","Book a table for Friday at 7 PM."] {
                XCTAssertNotNil(ClauseScope.bookingTarget(in:source),mode+": "+source)
                let item=ThoughtOrganizer.organize(source,referenceDate:anchor,calendar:calendar,sourceText:source)
                XCTAssertEqual(item.itemType,.task,source);XCTAssertFalse(item.needsClarification,source)
                XCTAssertEqual(item.temporalIntent.kind,.none,source)
                XCTAssertNil(item.dueDate,source);XCTAssertNil(item.reminderDate,source)
            }
            // Existing zip-gap proof declines these optional multi-FOR
            // roles: AT material separates the slots. No held/execution
            // outcome is newly asserted for the ordinary fallback parser.
            for source in ["Book a table for four at 7 for 4 PM.",
                           "Book a table for four at 7 for Saturday."] {
                XCTAssertNil(ClauseScope.bookingTarget(in:source),mode+": "+source)
            }
            let conflict="Book a table for 4 PM at 7 PM."
            XCTAssertNotNil(ClauseScope.bookingTarget(in:conflict),mode)
            let held=ThoughtOrganizer.organize(conflict,referenceDate:anchor,calendar:calendar,sourceText:conflict)
            XCTAssertEqual(held.itemType,.task,mode)
            XCTAssertEqual(held.state,.underspecified(.ambiguousTemporalScope),mode)
            XCTAssertTrue(held.needsClarification,mode)
            XCTAssertNil(held.dueDate,mode);XCTAssertNil(held.reminderDate,mode)
            for source in ["Sam said book a table for four at 7 on Friday.",
                           "Book Sam for four at 7 on Friday.",
                           "\"Book a table for four at 7 on Friday.\"",
                           "If Sam agrees, book a table for four at 7 on Friday.",
                           "I will not book a table for four at 7 on Friday.",
                           "Book a table for four at 7 on Friday, actually at 8."] {
                // Optional-role refusals retain the existing ordinary path;
                // these assert no new permission or source-grammar expansion.
                XCTAssertNil(ClauseScope.bookingTarget(in:source),mode+": "+source)
            }
        }
    }
}


extension IntentConsolidationTests {
    func testDeclaredFactCanCloseOnlyACompleteDirectCommunicationObject() throws {
        let previous=SentenceContext.taggerDisabledForEvaluation
        defer { SentenceContext.taggerDisabledForEvaluation=previous;SentenceContextCache.invalidate() }
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone=try XCTUnwrap(TimeZone(identifier:"America/Toronto"))
        let anchor=try XCTUnwrap(calendar.date(from:DateComponents(year:2026,month:11,day:16,hour:9)))
        let cases=[
            ("Email Noor the form","a fact I want to keep in the middle of this the cabinet is locked","the cabinet is locked","Noor"),
            ("Email Mira the receipt","a note I want to save the gate is closed","the gate is closed","Mira"),
            ("Text Sam the map","one fact I need to retain the shed is locked","the shed is locked","Sam")
        ]
        for disabled in [false,true] {
            SentenceContext.taggerDisabledForEvaluation=disabled;SentenceContextCache.invalidate()
            let mode="taggerDisabled=\(disabled)"
            for (prefix,frame,body,person) in cases {
                let source=prefix+" "+frame,message=mode+": "+source
                XCTAssertEqual(ClauseScope.read(prefix).act,.direct,message)
                XCTAssertTrue(ActionabilityReader.read(prefix).belongsOnToday,message)
                XCTAssertNil(ThoughtCompletion.unfinished(in:prefix),message)
                XCTAssertNotNil(ClauseScope.communicationArgumentCandidate(in:prefix),message)
                XCTAssertEqual(ActionabilityReader.declaredFactRecordingBody(frame),body,message)
                let result=ThoughtExtractionEngine.extractWithRules(source,referenceDate:anchor,calendar:calendar)
                XCTAssertEqual(result.items.count,2,message)
                let communication=try XCTUnwrap(result.items.first { $0.organization.itemType == .personFollowUp },message)
                let fact=try XCTUnwrap(result.items.first { $0.organization.itemType == .note },message)
                XCTAssertEqual(communication.sourceQuote,prefix,message);XCTAssertEqual(communication.rawQuote,prefix,message)
                XCTAssertEqual(communication.analysisText,prefix,message)
                XCTAssertEqual(communication.organization.personName,person,message)
                XCTAssertEqual(fact.sourceQuote,frame,message);XCTAssertEqual(fact.rawQuote,frame,message)
                XCTAssertEqual(fact.analysisText,body,message);XCTAssertNil(fact.organization.personName,message)
                XCTAssertTrue((fact.suggestedTitle ?? fact.analysisText).localizedCaseInsensitiveContains(body),message)
                let ledger=SourceUnitLedger(source)
                let prefixRange=try XCTUnwrap(source.range(of:prefix,options:.literal),message)
                let frameRange=try XCTUnwrap(source.range(of:frame,options:.literal),message)
                XCTAssertEqual(communication.sourceUnitIDs,ledger.ids(in:prefixRange),message)
                XCTAssertEqual(fact.sourceUnitIDs,ledger.ids(in:frameRange),message)
                XCTAssertTrue(communication.sourceUnitIDs.isDisjoint(with:fact.sourceUnitIDs),message)
                XCTAssertEqual(communication.sourceUnitIDs.union(fact.sourceUnitIDs),Set(ledger.words.indices),message)
                XCTAssertTrue(communication.organization.itemType.isActionable,message)
                XCTAssertFalse(fact.organization.itemType.isActionable,message)
                XCTAssertTrue(result.operations.isEmpty,message)
                for item in result.items {
                    XCTAssertEqual(item.organization.state,.resolved,message);XCTAssertFalse(item.needsReview,message)
                    XCTAssertFalse(item.organization.needsClarification,message)
                    XCTAssertNil(item.organization.dueDate,message);XCTAssertNil(item.organization.reminderDate,message)
                    XCTAssertEqual(item.organization.temporalIntent.kind,.none,message)
                    XCTAssertEqual(item.organization.reminderDelivery,.none,message)
                    XCTAssertNil(item.organization.locationIntent,message);XCTAssertNil(item.organization.recurrenceRule,message)
                    XCTAssertNil(item.shoppingGroup,message)
                }
            }
            for source in [
                "Tell Noor that a fact I want to keep the cabinet is locked",
                "Email Noor the form is ready a fact I want to keep in the middle of this the cabinet is locked",
                "Email Noor \"the form is ready\" a fact I want to keep the cabinet is locked"
            ] {
                let result=ThoughtExtractionEngine.extractWithRules(source,referenceDate:anchor,calendar:calendar)
                XCTAssertEqual(result.items.count,1,mode+": "+source)
                let item=try XCTUnwrap(result.items.first,mode)
                XCTAssertEqual(item.organization.itemType,.personFollowUp,mode)
                XCTAssertEqual(item.organization.personName,"Noor",mode)
                XCTAssertFalse(item.needsReview,mode)
                XCTAssertEqual(SourceUnitLedger(item.sourceQuote).words.map(\.text),SourceUnitLedger(source).words.map(\.text),mode)
                XCTAssertTrue(item.sourceQuote.contains("cabinet"),mode)
                XCTAssertNil(item.organization.dueDate,mode);XCTAssertNil(item.organization.reminderDate,mode)
                XCTAssertTrue(result.operations.isEmpty,mode)
            }
            XCTAssertTrue(ClauseScope.opensMessageComplement("Tell Noor that"),mode)
            XCTAssertEqual(ClauseScope.read("Email Noor the form is ready").act,.communicating,mode)
            // A recipient alone has no object slot. Check that exact existing
            // gate, without inventing a legacy whole-output count in the
            // non-communicating path that this change deliberately leaves alone.
            XCTAssertEqual(ClauseScope.read("Email Noor").act,.direct,mode)
            XCTAssertNil(ClauseScope.communicationArgumentCandidate(in:"Email Noor"),mode)
            for source in [
                "\"Email Noor the form a fact I want to keep the cabinet is locked\"",
                "Pat said email Noor the form a fact I want to keep the cabinet is locked"
            ] {
                let result=ThoughtExtractionEngine.extractWithRules(source,referenceDate:anchor,calendar:calendar)
                XCTAssertEqual(result.items.count,1,mode+": "+source)
                XCTAssertFalse(result.items.contains { $0.organization.itemType.isActionable && !$0.needsReview },mode)
                XCTAssertTrue(result.items.allSatisfy { $0.sourceQuote.contains("cabinet")
                    && $0.organization.dueDate == nil && $0.organization.reminderDate == nil },mode)
                XCTAssertTrue(result.operations.isEmpty,mode)
            }
        }
    }
}


extension IntentConsolidationTests {
    func testForcedMissingTaggerSuppressesBothNameTypesWithoutChangingTokenSpans() {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous
            SentenceContextCache.invalidate()
        }
        let sources = [
            "Email Mira the receipt", "I spoke with Mira", "Costco sells milk",
            "Email Noor the form", "I spoke with Noor", "IKEA sells tables"
        ]
        for source in sources {
            SentenceContext.taggerDisabledForEvaluation = false
            SentenceContextCache.invalidate()
            let native = SentenceContextCache.context(for: source)
            XCTAssertFalse(native.tokens.isEmpty, source)
            XCTAssertEqual(native.text, source)

            SentenceContext.taggerDisabledForEvaluation = true
            SentenceContextCache.invalidate()
            let missing = SentenceContextCache.context(for: source)
            XCTAssertEqual(missing.text, source)
            XCTAssertEqual(missing.tokens.map(\.text), native.tokens.map(\.text), source)
            XCTAssertEqual(missing.tokens.map { NSRange($0.range, in: source) },
                           native.tokens.map { NSRange($0.range, in: source) }, source)
            for token in missing.tokens {
                XCTAssertEqual(token.lexicalClass, .otherWord, source + ": " + token.text)
                XCTAssertFalse(token.isPersonalName, source + ": " + token.text)
                XCTAssertFalse(token.isOrganizationName, source + ": " + token.text)
                XCTAssertEqual(String(source[token.range]), token.text, source)
            }

            // Returning to the ordinary mode restores its actual local reading;
            // this contract does not require any tagging assets to be installed.
            SentenceContext.taggerDisabledForEvaluation = false
            SentenceContextCache.invalidate()
            let restored = SentenceContextCache.context(for: source)
            XCTAssertEqual(restored.tokens.map(\.text), native.tokens.map(\.text), source)
            XCTAssertEqual(restored.tokens.map { NSRange($0.range, in: source) },
                           native.tokens.map { NSRange($0.range, in: source) }, source)
            XCTAssertEqual(restored.tokens.map(\.lexicalClass), native.tokens.map(\.lexicalClass), source)
            XCTAssertEqual(restored.tokens.map(\.isPersonalName), native.tokens.map(\.isPersonalName), source)
            XCTAssertEqual(restored.tokens.map(\.isOrganizationName), native.tokens.map(\.isOrganizationName), source)
        }
    }
}

@MainActor
final class HypotheticalQuotedReferenceTests: XCTestCase {
    private let original = "I'm describing my Saturday market routine so I can find it later. "
        + "I visit the bread stall and then the flower stand. "
        + "The shared context belongs on the whole note. "
        + "If I say 'pick up' while describing that routine, it is not a shopping task."

    func testCompleteCitedWordFrameKeepsOriginalMemoryAndIndependentCall() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation, previousZone = NSTimeZone.default
        defer { NSTimeZone.default = previousZone; SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        NSTimeZone.default = calendar.timeZone
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        let leaf = "If I say 'pick up' while describing that routine, it is not a shopping task."
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            let mode = "taggerDisabled=\(disabled)"
            for source in [leaf,
                "When I say ‘rinse the jar’, it is not an instruction.",
                "If I say “email Noor” while describing our blue daxen, that is not a request.",
                "If I say 'pick up,' while describing my violet quorven, this is not a shopping task."] {
                XCTAssertTrue(QuotedSpeechScope.citesQuoteAsNonAction(source), mode + source)
                XCTAssertEqual(QuotedSpeechScope.matrixVoice(in: source), .reported, mode + source)
                let quote = try XCTUnwrap(QuotedSpeechScope.ranges(in: source).first, mode)
                XCTAssertTrue("'‘“".contains(source[quote.lowerBound]), mode)
                XCTAssertTrue("'’”".contains(source[source.index(before: quote.upperBound)]), mode)
            }
            XCTAssertEqual(ClauseScope.read(leaf).act, .direct, "If I is still not a reporter: " + mode)
            XCTAssertNil(ShoppingGroupParser.frontedAcquisitionContext(in: leaf), mode)
            XCTAssertNil(QuotedSpeechScope.directActionAfterQuote(leaf), mode)
            let reading = ThoughtExtractionEngine.extractWithRules(original, referenceDate: anchor, calendar: calendar)
            XCTAssertEqual(reading.items.count, 1, mode)
            let item = try XCTUnwrap(reading.items.first, mode)
            XCTAssertEqual(item.organization.itemType, .note, mode)
            XCTAssertFalse(item.needsReview, mode); XCTAssertFalse(item.organization.needsClarification, mode)
            XCTAssertEqual(item.organization.state, .resolved, mode)
            XCTAssertEqual(Data(item.sourceQuote.utf8), Data(original.utf8), mode)
            XCTAssertEqual(Data(item.rawQuote.utf8), Data(original.utf8), mode)
            XCTAssertEqual(item.analysisText, original, mode)
            XCTAssertEqual(item.sourceUnitIDs, Set(SourceUnitLedger(original).words.indices), mode)
            XCTAssertNil(item.organization.dueDate, mode); XCTAssertNil(item.organization.reminderDate, mode)
            XCTAssertEqual(item.organization.reminderDelivery, .none, mode)
            XCTAssertNil(item.organization.personName, mode); XCTAssertNil(item.organization.locationIntent, mode)
            XCTAssertNil(item.organization.recurrenceRule, mode); XCTAssertTrue(reading.operations.isEmpty, mode)
            for source in [
                "If I say 'call Noor', remind me to call her.",
                "If I say 'x', I will call Noor, it is not a task.",
                "If I say 'x', it is not a task, call Noor.",
                "If I say 'x', it is not a task and I need to call Noor.",
                "If I say 'x' while describing that I need groceries, it is not a task.",
                "If I say 'x' while describing the routine that I call Noor, it is not a task.",
                "If I say 'x' while describing my call routine, it is not a task.",
                "If I say 'x' while describing our routine, it is a task.",
                "If Sam says 'x', it is not a task.",
                "Tell Sam 'x', that is not a task.",
                "If I say 'x' and 'y', it is not a task.",
                "If I say 'x, it is not a task.",
                "If I say 'x', it's not a task.",
                "First: If I say 'x', it is not a task."] {
                XCTAssertFalse(QuotedSpeechScope.citesQuoteAsNonAction(source), mode + source)
            }
            XCTAssertEqual(QuotedSpeechScope.matrixVoice(in: "Tell Sam 'x', that is not a task."), .direct, mode)
            let withCall = original + " Call Vera."
            let separate = ThoughtExtractionEngine.extractWithRules(withCall, referenceDate: anchor, calendar: calendar)
            let calls = separate.items.filter { $0.organization.itemType.isActionable }
            XCTAssertEqual(calls.count, 1, mode)
            XCTAssertEqual(calls.first?.sourceQuote, "Call Vera.", mode)
            XCTAssertEqual(calls.first?.organization.personName, "Vera", mode)
            XCTAssertFalse(calls.first?.needsReview ?? true, mode)
            XCTAssertEqual(separate.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) },
                Set(SourceUnitLedger(withCall).words.indices), mode)
            XCTAssertTrue(separate.operations.isEmpty, mode)
        }
    }

    func testOriginalRoutineMemorySurvivesSaveDuplicateFreshOpenAndRecovery() async throws {
        let previous = SentenceContext.taggerDisabledForEvaluation, previousZone = NSTimeZone.default
        defer { NSTimeZone.default = previousZone; SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        func snapshot(_ context: ModelContext) throws -> Data {
            try JSONSerialization.data(withJSONObject: LongCaptureQualificationTests.snapshot(context), options: [.sortedKeys])
        }
        func assertSaved(_ context: ModelContext, sessionID: UUID, itemID: UUID, mode: String) throws {
            let sessions = try context.fetch(FetchDescriptor<CaptureSession>())
            XCTAssertEqual(sessions.count, 1, mode)
            XCTAssertEqual(sessions.first?.id, sessionID, mode)
            XCTAssertEqual(sessions.first.map { Data($0.originalTranscription.utf8) }, Data(original.utf8), mode)
            XCTAssertEqual(sessions.first?.processingStatus, .complete, mode)
            let rows = try context.fetch(FetchDescriptor<CapturedItem>())
            XCTAssertEqual(rows.count, 1, mode)
            let row = try XCTUnwrap(rows.first, mode)
            XCTAssertEqual(row.id, itemID, mode); XCTAssertEqual(row.captureSession?.id, sessionID, mode)
            XCTAssertEqual(Data(row.originalTextSegment.utf8), Data(original.utf8), mode)
            XCTAssertEqual(row.itemType, .note, mode); XCTAssertEqual(row.semanticState, .resolved, mode)
            XCTAssertTrue(row.belongsInMemory, mode); XCTAssertFalse(row.belongsInToday, mode)
            XCTAssertFalse(row.needsClarification, mode)
            XCTAssertNil(row.personName, mode); XCTAssertNil(row.dueDate, mode); XCTAssertNil(row.reminderDate, mode)
            XCTAssertEqual(ItemPresentation.configuredReminderDelivery(for: row), .none, mode); XCTAssertNil(row.locationIntent, mode)
            XCTAssertNil(RecurrenceStore.rule(for: row.id), mode)
        }
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            let mode = "taggerDisabled=\(disabled)"
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SpeakItCitedRoutine-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = ModelConfiguration(url: directory.appendingPathComponent("capture.store"), cloudKitDatabase: .none)
            var disk: ModelContainer? = try ModelContainer(for: PersistenceController.schema,
                migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
            var repository: SwiftDataThoughtRepository? = SwiftDataThoughtRepository(modelContext: try XCTUnwrap(disk).mainContext,
                requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
            NSTimeZone.default = calendar.timeZone
            var saved: CaptureCreationResult? = try await XCTUnwrap(repository).createCaptureResult(text: original,
                source: .inAppText, createdAt: anchor, schedulesReminders: false)
            NSTimeZone.default = previousZone
            let sessionID = try XCTUnwrap(saved).session.id, itemID = try XCTUnwrap(saved?.items.first).id
            XCTAssertNil(saved?.operationOutcome, mode)
            try assertSaved(try XCTUnwrap(disk).mainContext, sessionID: sessionID, itemID: itemID, mode: mode)
            let before = try snapshot(try XCTUnwrap(disk).mainContext)
            var duplicate: CaptureCreationResult? = try await XCTUnwrap(repository).createCaptureResult(text: original,
                source: .inAppText, createdAt: anchor.addingTimeInterval(1), schedulesReminders: false)
            XCTAssertFalse(try XCTUnwrap(duplicate).createdNewCapture, mode)
            XCTAssertEqual(duplicate?.session.id, sessionID, mode); XCTAssertEqual(duplicate?.items.map(\.id), [itemID], mode)
            XCTAssertEqual(try snapshot(try XCTUnwrap(disk).mainContext), before, mode)
            saved = nil; duplicate = nil; repository = nil; disk = nil
            let reopened = try ModelContainer(for: PersistenceController.schema,
                migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
            let fresh = ModelContext(reopened)
            let recovery = SwiftDataThoughtRepository(modelContext: fresh,
                requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
            try assertSaved(fresh, sessionID: sessionID, itemID: itemID, mode: mode)
            XCTAssertEqual(try snapshot(fresh), before, mode)
            for _ in 0..<2 {
                recovery.recoverUnorganizedCaptures()
                try assertSaved(fresh, sessionID: sessionID, itemID: itemID, mode: mode)
                XCTAssertEqual(try snapshot(fresh), before, mode)
            }
        }
    }
}


extension IntentConsolidationTests {
    func testCompleteNominalRestatementKeepsTimingAsideWithMatchingOwnerOnly() throws {
        let oldMode = SentenceContext.taggerDisabledForEvaluation
        let oldZone = NSTimeZone.default
        defer {
            NSTimeZone.default = oldZone
            SentenceContext.taggerDisabledForEvaluation = oldMode
            SentenceContextCache.invalidate()
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        NSTimeZone.default = calendar.timeZone
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9)))
        let detail = "I mean a basic kit to keep with the event supplies, and I have not given a purchase date."
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            let mode = "taggerDisabled=\(disabled)"
            for complete in [detail, detail.lowercased(),
                "We mean a basic cable to keep in the repair box, and we haven't chosen a day or reminder time."] {
                XCTAssertTrue(RuleBasedThoughtExtractor.hasCompleteNominalTimingRestatement(in: complete), mode + complete)
            }
            XCTAssertTrue(ActionabilityReader.isCompleteUnchosenActionTimeFrame("I have not given a purchase date."), mode)
            // The existing late reader recognizes a prefix. That prefix alone
            // must never authorize the new early whole-component preservation.
            for residual in [
                "I have not given a purchase date and the lantern glows.",
                "I have not given a purchase date, call Vera.",
                "I have not given a purchase date for the kit."] {
                XCTAssertTrue(ActionabilityReader.isUnchosenActionTime(residual), mode + residual)
                XCTAssertFalse(ActionabilityReader.isCompleteUnchosenActionTimeFrame(residual), mode + residual)
                XCTAssertFalse(RuleBasedThoughtExtractor.hasCompleteNominalTimingRestatement(
                    in: "I mean a basic kit to keep with the event supplies, and " + residual), mode + residual)
            }
            for source in [
                "I mean a kit to keep the gauge safe; Call Dad and I have not given a purchase date.",
                "I mean a kit to keep the gauge safe, Call Dad and I have not given a purchase date.",
                "I mean a kit to keep the gauge safe call Dad and I have not given a purchase date.",
                "I mean a basic kit to keep with the event supplies, and call Vera.",
                "I mean a basic kit to keep with the event supplies, and the cupboard is locked."] {
                XCTAssertFalse(RuleBasedThoughtExtractor.hasCompleteNominalTimingRestatement(in: source), mode + source)
            }
            let source = "Buy a first aid kit for the club cupboard. Call Vera. " + detail
            let reading = ThoughtExtractionEngine.extractWithRules(source, referenceDate: anchor, calendar: calendar)
            XCTAssertEqual(reading.items.count, 2, mode + reading.items.map(\.sourceQuote).joined(separator: " | "))
            let kit = try XCTUnwrap(reading.items.first { $0.sourceQuote.contains("Buy a first aid kit") }, mode)
            let call = try XCTUnwrap(reading.items.first { $0.sourceQuote.contains("Call Vera") }, mode)
            XCTAssertTrue(kit.organization.itemType.isActionable, mode)
            XCTAssertFalse(kit.needsReview, mode)
            XCTAssertTrue(kit.sourceQuote.contains(detail), mode)
            XCTAssertTrue(kit.rawQuote.contains(detail), mode)
            XCTAssertFalse(call.sourceQuote.contains("I mean"), mode)
            XCTAssertFalse(call.rawQuote.contains("purchase date"), mode)
            XCTAssertEqual(call.organization.personName, "Vera", mode)
            XCTAssertTrue(kit.sourceUnitIDs.isDisjoint(with: call.sourceUnitIDs), mode)
            let ledger = SourceUnitLedger(source)
            let detailRange = try XCTUnwrap(source.range(of: detail), mode)
            XCTAssertTrue(ledger.ids(in: detailRange).isSubset(of: kit.sourceUnitIDs), mode)
            XCTAssertEqual(kit.sourceUnitIDs.union(call.sourceUnitIDs), Set(ledger.words.indices), mode)
            XCTAssertTrue(reading.operations.isEmpty, mode)
            for row in reading.items {
                XCTAssertNil(row.organization.dueDate, mode)
                XCTAssertNil(row.organization.reminderDate, mode)
                XCTAssertEqual(row.organization.reminderDelivery, .none, mode)
            }
            for (tail, actionable) in [("call Vera.", true), ("the cupboard is locked.", false)] {
                let opposite = "Buy a first aid kit for the club cupboard. I mean a basic kit to keep with the event supplies, and " + tail
                let result = ThoughtExtractionEngine.extractWithRules(opposite, referenceDate: anchor, calendar: calendar)
                let independent = try XCTUnwrap(result.items.first {
                    $0.sourceQuote.lowercased().contains(tail.lowercased().dropLast())
                        && !$0.sourceQuote.lowercased().contains("i mean")
                }, mode + opposite)
                XCTAssertEqual(independent.organization.itemType.isActionable, actionable, mode + opposite)
                XCTAssertTrue(result.operations.isEmpty, mode + opposite)
                XCTAssertEqual(result.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) },
                    Set(SourceUnitLedger(opposite).words.indices), mode + opposite)
            }
        }
    }
}


extension IntentConsolidationTests {
    func testWeakRetailHeaderCannotDeclareUnknownDefiniteReferents() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        defer { SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10)))
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            for header in ["At Costco: these people and those friends.",
                           "At Costco: the qavren and this zental."] {
                let source = "Wash the car. " + header
                let mode = "taggerDisabled=\(disabled): " + source
                XCTAssertNil(ShoppingGroupParser.declaredShoppingRun(in: header), mode)
                XCTAssertFalse(ShoppingGroupParser.certifiesImplicitProducts(
                    String(header.dropFirst("At Costco: ".count))), mode)
                let reading = ThoughtExtractionEngine.extractWithRules(source, referenceDate: anchor, calendar: calendar)
                XCTAssertFalse(reading.items.contains { $0.organization.itemType == .shopping }, mode)
                XCTAssertTrue(reading.items.contains { $0.organization.itemType.isActionable
                    && $0.sourceQuote.contains("Wash the car") }, mode)
                XCTAssertEqual(reading.items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) },
                    Set(SourceUnitLedger(source).words.indices), mode)
                XCTAssertTrue(reading.operations.isEmpty, mode)
            }
            let known = "At Costco: those granola bars and that oat milk."
            let retained = ThoughtExtractionEngine.extractWithRules(known, referenceDate: anchor, calendar: calendar)
            XCTAssertEqual(retained.items.count, 2, known)
            XCTAssertTrue(retained.items.allSatisfy { $0.organization.itemType == .shopping
                && $0.shoppingGroup == "Costco" && !$0.needsReview }, known)
            for opposed in [
                "Grocery run at Costco: these qavren and zental.",
                "Grocery run at Costco: these qavren and call Mom.",
                "Grocery run at Costco: a roll of qavren for the cedars and the hedge."
            ] {
                XCTAssertNil(ShoppingGroupParser.declaredShoppingRun(in: opposed), opposed)
            }
            for (source, entries) in [
                ("At Costco: qavren and a zental.", ["qavren", "a zental"]),
                ("Grocery run at Costco: these qavren and those zental.", ["these qavren", "those zental"]),
                ("Grocery run at Costco: these qavren, and those zental.", ["these qavren", "those zental"])
            ] {
                let mode = "taggerDisabled=\(disabled): " + source
                let proof = try XCTUnwrap(ShoppingGroupParser.declaredShoppingRun(in: source), mode)
                XCTAssertEqual(proof.entries.map { String(source[$0.range]) }, entries, mode)
                let reading = ThoughtExtractionEngine.extractWithRules(source, referenceDate: anchor, calendar: calendar)
                XCTAssertEqual(reading.items.map(\.sourceQuote), entries, mode)
                XCTAssertTrue(reading.items.allSatisfy { $0.rawQuote == source
                    && $0.organization.itemType == .shopping && $0.shoppingGroup == "Costco"
                    && $0.organization.state == .resolved && !$0.needsReview
                    && !$0.organization.needsClarification && $0.organization.temporalIntent == .none
                    && $0.organization.personName == nil && $0.organization.dueDate == nil
                    && $0.organization.reminderDate == nil && $0.organization.reminderDelivery == .none
                    && $0.organization.locationIntent == nil && $0.organization.recurrenceRule == nil }, mode)
                var used = Set<Int>()
                for row in reading.items {
                    XCTAssertTrue(used.isDisjoint(with: row.sourceUnitIDs), mode)
                    used.formUnion(row.sourceUnitIDs)
                }
                XCTAssertEqual(used, Set(SourceUnitLedger(source).words.indices), mode)
                XCTAssertTrue(reading.operations.isEmpty, mode)
            }
        }
    }
}


extension IntentConsolidationTests {
    func testOwnedQuestionRetainsLiteralCoordinatorWithoutWideningOtherFrames() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation, oldZone = NSTimeZone.default
        defer {
            SentenceContext.taggerDisabledForEvaluation = previous; SentenceContextCache.invalidate()
            NSTimeZone.default = oldZone
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        NSTimeZone.default = calendar.timeZone
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9)))
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled; SentenceContextCache.invalidate()
            let mode = "taggerDisabled=\(disabled): "
            for source in [
                "Text Sam to say the train leaves at ten on Friday and ask whether he can meet me at the other end. I have not picked a time to send that text. Ten is the departure time inside the message.",
                "Text Noor about the ferry and ask whether she can meet me at the pier."] {
                var trace: RuntimeRuleTrace?
                let result = RuleBasedThoughtExtractor.process(source, referenceDate: anchor, calendar: calendar,
                    traceObserver: { trace = $0 })
                let proof = try XCTUnwrap(trace, mode + source)
                let ledger = SourceUnitLedger(proof.creating)
                let andRange = try XCTUnwrap(proof.creating.range(of: #"(?i)\band\s+(?=ask\b)"#,
                    options: .regularExpression), mode + source)
                let andIDs = ledger.ids(in: andRange)
                XCTAssertEqual(andIDs.count, 1, mode + source)
                let row = try XCTUnwrap(result.items.first { $0.analysisText.contains("ask whether") }, mode + source)
                XCTAssertTrue(andIDs.isSubset(of: row.sourceUnitIDs), mode + source)
                XCTAssertTrue(row.sourceQuote.contains("and ask whether"), mode + source)
                XCTAssertTrue(row.rawQuote.contains("and ask whether"), mode + source)
                XCTAssertFalse(row.needsReview, mode + source)
                XCTAssertTrue(row.organization.itemType.isActionable, mode + source)
                XCTAssertNil(row.organization.dueDate, mode + source)
                XCTAssertNil(row.organization.reminderDate, mode + source)
                XCTAssertEqual(row.organization.reminderDelivery, .none, mode + source)
                XCTAssertTrue(result.operations.isEmpty, mode + source)
                XCTAssertEqual(proof.output, result.items, mode + source)
                XCTAssertTrue(proof.unassignedWordIDs.isDisjoint(with: andIDs), mode + source)
                for edge in proof.group?.edges.filter({ $0.kind == "communicationQuestion" }) ?? [] {
                    let questionIDs = try XCTUnwrap(edge.sourceWordIDs, mode + source)
                    let ownerIDs = try XCTUnwrap(edge.targetWordIDs, mode + source)
                    XCTAssertTrue(andIDs.isSubset(of: questionIDs), mode + source)
                    XCTAssertTrue(questionIDs.isDisjoint(with: ownerIDs), mode + source)
                    let question = try XCTUnwrap(proof.propositions.first {
                        edge.sourceSegments.contains($0.segment)
                    }, mode + source)
                    let span = try XCTUnwrap(Range(question.range, in: proof.creating), mode + source)
                    XCTAssertTrue(String(proof.creating[span]).hasPrefix("and ask"), mode + source)
                    XCTAssertEqual(question.wordIDs, ledger.ids(in: span), mode + source)
                    XCTAssertEqual(edge.targetSegments, [question.segment - 1], mode + source)
                }
            }
            // Full-capture uniqueness matters: a separate earlier contact is
            // not discarded merely because the final sentence has one owner.
            let ambiguous = "Call Vera. Text Noor about the ferry and ask whether she can meet me at the pier."
            var ambiguousTrace: RuntimeRuleTrace?
            _ = RuleBasedThoughtExtractor.process(ambiguous, referenceDate: anchor, calendar: calendar,
                traceObserver: { ambiguousTrace = $0 })
            let ambiguousProof = try XCTUnwrap(ambiguousTrace, mode + ambiguous)
            XCTAssertFalse(ambiguousProof.group?.edges.contains { $0.kind == "communicationQuestion" } == true,
                mode + ambiguous)
            XCTAssertFalse(ambiguousProof.segmentQuotes.contains { $0.lowercased().hasPrefix("and ask") },
                mode + ambiguous)
            // Adding a raw lead must not disable an existing anchored purpose
            // certificate. The semantic matrix remains the exact Call source.
            let protected = "Buy a first aid kit. I mean a basic kit to keep with the event supplies, and Call Marco to confirm he's coming at eight."
            let protectedResult = RuleBasedThoughtExtractor.process(protected, referenceDate: anchor, calendar: calendar)
            let call = try XCTUnwrap(protectedResult.items.first { $0.analysisText.hasPrefix("Call Marco") },
                mode + protected)
            XCTAssertTrue(call.sourceQuote.hasPrefix("Call Marco"), mode + protected)
            XCTAssertNotNil(ClauseScope.finiteContactPurpose(in: call.sourceQuote), mode + protected)
            XCTAssertNil(call.organization.dueDate, mode + protected)
            XCTAssertNil(call.organization.reminderDate, mode + protected)
            for source in [
                "Mina said, \"Text Noor about the ferry and ask whether she can meet me at the pier.\"",
                "Text Noor about the ferry but ask whether she can meet me at the pier."] {
                var trace: RuntimeRuleTrace?
                _ = RuleBasedThoughtExtractor.process(source, referenceDate: anchor, calendar: calendar,
                    traceObserver: { trace = $0 })
                XCTAssertFalse(trace?.segmentQuotes.contains { $0.lowercased().hasPrefix("and ask") } == true,
                    mode + source)
            }
        }
    }
}
