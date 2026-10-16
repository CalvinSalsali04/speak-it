import SwiftData
import XCTest
@testable import SpeakIt

/// Proves the person layer by its **consequence**, not by its field.
///
/// The semantic corpus scored `person` as metadata, so nine disagreements sat
/// green under a release gate of "0 CRITICAL, 0 BEHAVIORAL" while Memory's
/// People collection was quietly empty for every one of them. A field was
/// wrong; what was actually wrong was that a person the user had told Speak It
/// about could not be found again. These tests assert the second thing:
/// capture a sentence, then look under People for the human it named.
@MainActor
final class PersonMentionTests: XCTestCase {
    func testDeterminedCausativeObjectSuppliesBeneficiaryRoleWithoutNameVocabulary() throws {
        let source = "Get Willa a spare key cut."
        let mention = try XCTUnwrap(PersonMentionResolver.primary(in: source))
        XCTAssertEqual(mention.label, "Willa")
        XCTAssertEqual(String(source[mention.sourceRange]), "Willa")
        XCTAssertEqual(mention.role, .participant)
        let result = ThoughtExtractionEngine.extractWithRules(source,
            referenceDate: referenceDate, calendar: calendar)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.organization.itemType, .task)
        XCTAssertEqual(result.items.first?.organization.personName, "Willa")
        XCTAssertNil(result.items.first?.shoppingGroup)
        for combined in ["Get Willa a spare key cut and buy milk.",
                         "Buy milk and get Willa a spare key cut."] {
            let split = ThoughtExtractionEngine.extractWithRules(combined,
                referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(split.items.count, 2, combined)
            let service = split.items.first { $0.analysisText.localizedCaseInsensitiveContains("spare key") }
            XCTAssertEqual(service?.organization.itemType, .task, combined)
            XCTAssertEqual(service?.organization.personName, "Willa", combined)
            XCTAssertNil(service?.shoppingGroup, combined)
            let purchase = split.items.first { $0.organization.itemType == .shopping }
            XCTAssertNotNil(purchase, combined)
            XCTAssertNil(purchase?.organization.personName, combined)
        }
        for opposed in ["Get a spare key cut.", "Get Willa ready.",
                        "Get Willa. A spare key cut.",
                        "Get Willa a spare key cut if she agrees.",
                        "Never get Willa a spare key cut.",
                        "Have Willa get a spare key cut.",
                        "Get Willa washed.",
                        "Get Willa a box of doughnuts.",
                        "The phrase ‘Get Willa a spare key cut’ is printed on the poster."] {
            XCTAssertFalse(PersonMentionResolver.mentions(in: opposed).contains { $0.role == .participant && $0.label == "Willa" }, opposed)
        }
    }

    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
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

    override func tearDownWithError() throws {
        repository = nil
        container = nil
    }

    // MARK: Frame of reference

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    private var referenceDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10, minute: 0))!
    }

    /// The person the whole capture pipeline ends up storing — speech repair,
    /// splitting and organizing included, because that is the path a real
    /// capture takes and every one of these failures lived in it.
    private func person(_ utterance: String) -> String? {
        ThoughtExtractionEngine.extractWithRules(
            utterance,
            referenceDate: referenceDate,
            calendar: calendar
        ).items.first?.organization.personName
    }

    private func people(_ utterance: String) -> [String?] {
        ThoughtExtractionEngine.extractWithRules(
            utterance,
            referenceDate: referenceDate,
            calendar: calendar
        ).items.map(\.organization.personName)
    }

    static let withdrawnSendSource = "I said I would send the draft to Marcus on Monday, but ignore that timing. "
            + "The final plan is to send him the reviewed version on Wednesday after Clara comments. "
            + "Also I was going to print it, no, that makes no sense because it is a shared document. "
            + "Save the revised send, and preserve my correction in the source, but do not create "
            + "a Monday draft send or a print job."

    func testUniqueWithdrawnAntecedentIsVisibleInSurvivingActionTitle() {
        let previousTaggerMode = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previousTaggerMode
            SentenceContextCache.invalidate()
        }
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            let source = Self.withdrawnSendSource
            let items = ThoughtExtractionEngine.extractWithRules(
                source, referenceDate: referenceDate, calendar: calendar
            ).items
            XCTAssertEqual(items.count, 1, items.map { "\($0.analysisText) / \($0.organization.personName ?? "nil") / \($0.suggestedTitle ?? "nil")" }.joined(separator: " | "))
            XCTAssertEqual(items[0].organization.personName, "Marcus")
            XCTAssertTrue(items[0].suggestedTitle?.contains("send Marcus") == true,
                          "title=\(items[0].suggestedTitle ?? "nil") analysis=\(items[0].analysisText)")
            XCTAssertTrue(items[0].rawQuote.contains("send the draft to Marcus"))

            let short = ThoughtExtractionEngine.extractWithRules(
                "Call Marcus tomorrow", referenceDate: referenceDate, calendar: calendar
            ).items
            XCTAssertEqual(short.count, 1)
            XCTAssertEqual(short[0].organization.personName, "Marcus")
            XCTAssertFalse(short[0].needsReview)

            let embedded = ThoughtExtractionEngine.extractWithRules(
                "Ask Marcus to email her tomorrow", referenceDate: referenceDate,
                calendar: calendar
            ).items
            XCTAssertEqual(embedded.count, 1)
            XCTAssertTrue(embedded[0].analysisText.contains("email her"))
        }
    }

    func testCurrentPlanRevisionDoesNotConsumeIndependentActsOrReportedPlans() {
        let previousTaggerMode = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previousTaggerMode
            SentenceContextCache.invalidate()
        }
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            func rows(_ text: String) -> [ExtractedThought] {
                ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar).items
            }
            let unrelated = rows("I said I would call Marcus on Monday, but ignore that timing. The final plan is to send Nora the reviewed version on Wednesday.")
            XCTAssertEqual(unrelated.count, 2)
            XCTAssertTrue(unrelated.contains { $0.sourceQuote.contains("call Marcus") })
            XCTAssertTrue(unrelated.contains { $0.organization.personName == "Nora" && $0.organization.itemType.isActionable })
            let report = rows("Asha said, 'My final plan is to send Ben the document on Wednesday.'")
            XCTAssertTrue(report.allSatisfy { !$0.organization.itemType.isActionable && $0.organization.reminderDate == nil })
            let physical = rows("Save the revised document in the shared folder.")
            XCTAssertEqual(physical.count, 1)
            XCTAssertTrue(physical[0].organization.itemType.isActionable)
            let independent = rows("I was going to print the document, no, that makes no sense because it is shared. Buy eggs tomorrow.")
            XCTAssertEqual(independent.filter { $0.organization.itemType.isActionable }.count, 1)
            XCTAssertTrue(independent.contains { $0.analysisText.lowercased().contains("buy eggs") })
            let fact = rows("I was going to print the document, no, that makes no sense, and the printer is broken.")
            XCTAssertTrue(fact.contains { $0.sourceQuote.contains("printer is broken") })
            let competing = rows("I said I would send the draft to Marcus and Ben on Monday, but ignore that timing. The final plan is to send him the reviewed version on Wednesday.")
            XCTAssertFalse(competing.contains { $0.organization.itemType.isActionable && ["Marcus", "Ben"].contains($0.organization.personName ?? "") })
            let revision = "I said I would send the draft to Marcus on Monday, but ignore that timing. The final plan is to send him the reviewed version on Wednesday. "
            let twoSends = rows(revision + "Send Nora the receipt. Save the revised send.")
            XCTAssertTrue(twoSends.contains { $0.sourceQuote.contains("Save the revised send")
                && !$0.sourceQuote.contains("final plan") })
            XCTAssertTrue(twoSends.contains { $0.organization.itemType.isActionable
                && $0.organization.personName == "Nora" })
            let extra = rows(revision + "Save the revised send and buy eggs tomorrow.")
            XCTAssertTrue(extra.contains { $0.organization.itemType == .shopping
                && $0.analysisText.localizedCaseInsensitiveContains("buy eggs") })
            let unowned = rows("Save the revised send, and preserve my correction in the source, but do not create a Monday draft send or a print job.")
            XCTAssertTrue(unowned.contains { $0.sourceQuote.contains("preserve my correction") })
        }
    }

    func testNamedGroupPurposeOwnsLaterPronounOnlyWithinThatGroup() {
        let shared = ThoughtExtractionEngine.extractWithRules(
            "For Amira's visit next Tuesday, wash the guest towels, put fresh sheets "
                + "on the bed, and check the lamp. She is allergic to lavender, so "
                + "remember that about her. Pick up unscented soap before she arrives.",
            referenceDate: referenceDate, calendar: calendar
        ).items
        let allergy = shared.first { $0.analysisText.contains("allergic to lavender") }
        XCTAssertEqual(allergy?.organization.personName, "Amira")
        XCTAssertTrue(allergy?.suggestedTitle?.contains("Amira is allergic") == true)
        XCTAssertTrue(allergy?.sourceQuote.contains("She is allergic") == true)
        let soap = shared.first { $0.analysisText.contains("unscented soap") }
        XCTAssertTrue(soap?.suggestedTitle?.contains("before Amira arrives") == true)
        XCTAssertNil(soap?.organization.dueDate)

        let unrelated = ThoughtExtractionEngine.extractWithRules(
            "Call Amira. Buy soap. She likes lavender.",
            referenceDate: referenceDate, calendar: calendar
        ).items
        let unrelatedFact = unrelated.first { $0.analysisText.contains("likes lavender") }
        XCTAssertNil(unrelatedFact?.organization.personName)

        let explicit = ThoughtExtractionEngine.extractWithRules(
            "For Amira's visit, wash the towels and change the sheets. "
                + "Nora is allergic to lavender.",
            referenceDate: referenceDate, calendar: calendar
        ).items
        let nora = explicit.first { $0.analysisText.contains("allergic to lavender") }
        XCTAssertEqual(nora?.organization.personName, "Nora")
    }

    func testVisiblePersonNameDoesNotChangeChoiceOwnershipAnalysis() {
        let source = "For Maya's present, I had been weighing a scarf against a sketchbook. "
            + "She told me she has enough scarves, so I have settled on the sketchbook. "
            + "Buy it by Friday and wrap it before the party on Saturday. "
            + "Remember that Maya already has enough scarves; it will help with gifts later. "
            + "There should be no scarf purchase hiding in the list because I spoke about "
            + "that option first."
        let items = ThoughtExtractionEngine.extractWithRules(
            source, referenceDate: referenceDate, calendar: calendar
        ).items
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.filter { $0.organization.itemType.isActionable }.count, 2)
        XCTAssertFalse(items.contains { $0.organization.itemType.isActionable
            && $0.analysisText.lowercased().contains("scarf") })
        XCTAssertTrue(items.contains { $0.sourceQuote.contains("She told me")
            && $0.sourceQuote.contains("weighing a scarf") })
    }

    func testNegatedNominalPurchaseCannotBecomeAnActionOrHideIndependentDadCall() {
        let exclusion = "There should be no emerald purchase hiding in my list because I mentioned that option first."
        let source = exclusion + " Call Dad tomorrow."
        let items = ThoughtExtractionEngine.extractWithRules(source,referenceDate:referenceDate,calendar:calendar).items
        let actions = items.filter { $0.organization.itemType.isActionable }
        XCTAssertEqual(actions.count,1,items.map(\.analysisText).joined(separator:" | "))
        XCTAssertEqual(actions.first?.organization.personName,"Dad")
        XCTAssertTrue(actions.first?.analysisText.lowercased().contains("call dad") == true)
        XCTAssertFalse(actions.contains { $0.analysisText.lowercased().contains("emerald") })
        XCTAssertTrue(items.contains { $0.sourceQuote.contains("no emerald purchase") })
        XCTAssertTrue(RuntimeProposalGuard.covers(source,quotes:items.map(\.rawQuote)))
        XCTAssertFalse(ActionabilityReader.read(exclusion).belongsOnToday)
        let standalone = ThoughtExtractionEngine.extractWithRules(exclusion,referenceDate:referenceDate,calendar:calendar).items
        XCTAssertFalse(standalone.contains { $0.organization.itemType.isActionable })
        XCTAssertTrue(standalone.contains { $0.sourceQuote.contains("no emerald purchase") })
        XCTAssertFalse(ActionabilityReader.isExcludedListEntry("There should be no emerald purchase in my list because I will buy the lamp tomorrow."))
        let juxtaposed = ThoughtExtractionEngine.extractWithRules("There is no problem call Dad tomorrow",referenceDate:referenceDate,calendar:calendar).items
        XCTAssertEqual(juxtaposed.filter { $0.organization.itemType.isActionable }.count,1)
        XCTAssertTrue(juxtaposed.contains { $0.organization.itemType.isActionable && $0.analysisText.lowercased().hasPrefix("call dad") })
        XCTAssertFalse(ActionabilityReader.isExcludedListEntry("There should be no emerald purchase in my list because I have promised to buy the lamp tomorrow."))
        XCTAssertFalse(ActionabilityReader.isExcludedListEntry("There should be no emerald purchase in my list because I'll buy the lamp tomorrow."))
    }

    // MARK: - The families a person can arrive in

    func testEveryWayAHumanIsNamedResolvesToTheSamePerson() {
        let expected: [(String, String)] = [
            ("Catherine called me at five", "Catherine"),
            ("I met Alex yesterday", "Alex"),
            ("Meet Priya at the office", "Priya"),
            ("Call, uh, call Mom", "Mom"),
            ("Send Catherine that thing tomorrow morning", "Catherine"),
            ("Call Dr. Okonkwo", "Dr. Okonkwo"),
            ("Don't forget Catherine called me", "Catherine"),
            ("Alex's brother is visiting", "Alex"),
            ("Email Professor Chen about the deadline", "Professor Chen"),
            ("Remember Jean-Luc prefers email", "Jean-Luc"),
        ]

        for (utterance, name) in expected {
            XCTAssertEqual(person(utterance), name, utterance)
        }
    }

    /// The recipient of a transfer is who the errand is with, whoever owns the
    /// thing handed over; reported speech that carries an obligation names the
    /// person inside it; "is called" names somebody and phones nobody; and a
    /// thing rescheduled to a clock is not a person who moved.
    func testRecipientsReportedObligationsAndNamingResolveTheRightPerson() {
        let expected: [(String, String?)] = [
            ("Give Mom's recipe to Catherine", "Catherine"),
            ("Send Alex's invoice to Priya", "Priya"),
            ("Return Priya's book to Sam", "Sam"),
            ("Bring the laptop to work", nil),
            ("Remember Catherine said I need to call Alex Friday", "Alex"),
            ("Mom told me to call Dr. Okonkwo", "Dr. Okonkwo"),
            ("Priya said I should call the landlord", "Priya"),
            ("Remember Catherine's husband is called David", "Catherine"),
            ("Standup moved from 9 to 9:30", nil),
            ("Sarah moved to Boston", "Sarah"),
        ]
        for (utterance, name) in expected {
            XCTAssertEqual(person(utterance), name, utterance)
        }
    }

    /// Today and Memory read one resolver, so the same sentence cannot name
    /// somebody on one surface and nobody on the other.
    func testTodayAndMemoryReadTheSameResolver() {
        for utterance in ["Call Catherine at five", "Catherine called me at five"] {
            let mention = PersonMentionResolver.primary(in: utterance)
            XCTAssertEqual(mention?.label, "Catherine", utterance)
            XCTAssertEqual(
                mention.map { String(utterance[$0.sourceRange]) },
                "Catherine",
                "the source range must point at the words the label came from"
            )
        }

        XCTAssertEqual(
            PersonMentionResolver.primary(in: "Call Catherine at five")?.role,
            .followUpTarget
        )
        XCTAssertEqual(
            PersonMentionResolver.primary(in: "Catherine called me at five")?.role,
            .participant
        )
        XCTAssertEqual(
            PersonMentionResolver.primary(in: "Alex likes golf")?.role,
            .subject
        )
    }

    // MARK: - A wrong name is worse than no name

    /// "Call Sam, no wait, Sam's assistant" used to file a person called
    /// *Wait Sam* — displayed on the row, and used to address a message. The
    /// correction layer reduces the target first; person inference then keeps
    /// the relationship label rather than inventing a name from the repair.
    func testAStackedSelfCorrectionKeepsTheCorrectedTarget() {
        XCTAssertEqual(
            SelfCorrectionResolver.resolved("Call Sam, no wait, Sam's assistant"),
            "Call Sam's assistant"
        )
        XCTAssertEqual(person("Call Sam, no wait, Sam's assistant"), "Sam's assistant")
    }

    func testANameNeverAbsorbsATemporalOrRepairWord() {
        let forbidden = [
            "Wait", "Friday", "Tomorrow", "Five", "In", "Actually", "Sorry", "No",
        ]
        let utterances = [
            "Call Sam, no wait, Sam's assistant",
            "Call Mom tomorrow and Alex Friday",
            "Message Catherine in one hour",
            "Call Mom at five",
            "Call mum tomorrow",
            "Text Alex later today",
            "Remind me tomorrow to call Sam—no, actually call Alex",
        ]

        for utterance in utterances {
            for name in people(utterance).compactMap({ $0 }) {
                for word in forbidden {
                    XCTAssertFalse(
                        name.split(separator: " ").contains(Substring(word)),
                        "\"\(utterance)\" produced a person called \"\(name)\""
                    )
                }
            }
        }

        XCTAssertEqual(people("Call Mom tomorrow and Alex Friday"), ["Mom", "Alex"])
        XCTAssertEqual(person("Message Catherine in one hour"), "Catherine")
        XCTAssertEqual(person("Call mum tomorrow"), "Mum")
    }

    // MARK: - Evidence, not capitalization

    /// A capitalized word is not a person. Every sentence here contains one and
    /// none of them is about a human participant, so an eager resolver would
    /// fill Memory's People collection with brands, book subjects and reports.
    func testQuantifiedTransferObjectsAreNotPeopleButRecipientsRemainNamed() {
        for source in ["send any files", "send some files", "send each file", "send either version", "send both drafts"] {
            XCTAssertTrue(PersonMentionResolver.mentions(in: source).isEmpty, source)
        }
        for source in ["send any files to Amy", "send some files to Jo", "Send Amy the files"] {
            let mentions = PersonMentionResolver.mentions(in: source)
            XCTAssertEqual(mentions.count, 1, source)
            XCTAssertEqual(mentions.first?.label, source.contains("Jo") ? "Jo" : "Amy", source)
        }
    }

    func testCapitalizationAloneNeverInventsAPerson() {
        let utterances = [
            "Buy milk at Walmart",
            "Finish the Alex report",
            "Read about Ada Lovelace",
            "Apple announced something",
            "Meet the deadline Friday",
            "Toronto is cold in February",
            "The parking spot is level three",
            "Book the flight to Vancouver",
            "Professor said Chapter 7 is excluded",
        ]

        for utterance in utterances {
            XCTAssertNil(person(utterance), utterance)
            XCTAssertTrue(
                PersonMentionResolver.mentions(in: utterance).isEmpty,
                "\(utterance) named \(PersonMentionResolver.mentions(in: utterance).map(\.label))"
            )
        }
    }

    // MARK: - A missing target is not the same as an unnamed one

    /// A follow-up Speak It is sure about but cannot attribute is a real
    /// question to ask, not a healthy task to file silently.
    func testAFollowUpWithNobodyOnTheOtherEndAsksWho() throws {
        XCTAssertEqual(PersonMentionResolver.followUpTarget(in: "Call them tomorrow"), .missing)

        let organized = ThoughtOrganizer.organize(
            "Call them tomorrow",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(organized.itemType, .personFollowUp)
        XCTAssertNil(organized.personName)
        XCTAssertTrue(organized.needsClarification)

        let item = try repository.createCapture(text: "Call them tomorrow")
        XCTAssertEqual(item.clarificationRequirement, .person)
        XCTAssertFalse(item.belongsInToday)
    }

    /// "The dentist" is not a name and needs no help. Asking who the dentist is
    /// would be Speak It failing to understand a sentence it understood.
    func testANonNamedTargetIsAlreadyEnough() throws {
        let described: [(String, String)] = [
            ("Call the dentist tomorrow", "the dentist"),
            ("Call my sister", "my sister"),
            ("Follow up with the O'Brien family", "the O'Brien family"),
        ]

        for (utterance, target) in described {
            XCTAssertEqual(
                PersonMentionResolver.followUpTarget(in: utterance),
                .described(target),
                utterance
            )
            let item = try repository.createCapture(text: utterance)
            XCTAssertNotEqual(
                item.clarificationRequirement,
                .person,
                "\(utterance) must not be held for a person it already describes"
            )
        }

        let item = try repository.createCapture(text: "Call the dentist tomorrow at 9 AM")
        XCTAssertNotEqual(item.clarificationRequirement, .person)
    }

    func testDirectDescribedTaskTargetDoesNotBecomeItsPossessiveOwner() throws {
        let previousTaggerMode = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previousTaggerMode
            SentenceContextCache.invalidate()
        }
        let observed = "Call the fire marshal's office to book the venue inspection, it has to happen before tech week."
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            for source in [observed, "Call the fire marshal’s office."] {
                XCTAssertEqual(PersonMentionResolver.followUpTarget(in: source),
                               .described("the fire marshal's office"), source)
                let reading = ThoughtExtractionEngine.extractWithRules(
                    source, referenceDate: referenceDate, calendar: calendar)
                XCTAssertTrue(reading.operations.isEmpty)
                XCTAssertEqual(reading.items.count, 1, String(reflecting: reading))
                let item = try XCTUnwrap(reading.items.first)
                XCTAssertEqual(item.organization.itemType, .task, source)
                XCTAssertNil(item.organization.personName, source)
                XCTAssertEqual(item.rawQuote, source)
                XCTAssertTrue(item.analysisText.localizedCaseInsensitiveContains("office"))
            }
            let titleCased = "Call The Fire Marshal’s Office."
            let titleCasedReading = ThoughtExtractionEngine.extractWithRules(
                titleCased, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(titleCasedReading.items.count, 1, titleCased)
            XCTAssertEqual(titleCasedReading.items.first?.organization.itemType, .task)
            XCTAssertNil(titleCasedReading.items.first?.organization.personName)
            let compounds: [(String, [String?])] = [
                ("Call the fire marshal’s office. Text Marshal.", [nil, "Marshal"]),
                ("Text Dave. Call the fire marshal’s office.", ["Dave", nil]),
                ("Call the fire marshal’s office, then text Marshal the time.", [nil, "Marshal"]),
                ("Text Dave the address; call the fire marshal’s office.", ["Dave", nil])
            ]
            for (source, expectedPeople) in compounds {
                let reading = ThoughtExtractionEngine.extractWithRules(
                    source, referenceDate: referenceDate, calendar: calendar)
                XCTAssertTrue(reading.operations.isEmpty)
                XCTAssertEqual(reading.items.count, 2, String(reflecting: reading))
                XCTAssertEqual(reading.items.map(\.organization.personName), expectedPeople, source)
                let officeItems = reading.items.filter {
                    $0.analysisText.localizedCaseInsensitiveContains("office")
                }
                XCTAssertEqual(officeItems.count, 1, source)
                XCTAssertEqual(officeItems.first?.organization.itemType, .task)
                XCTAssertNil(officeItems.first?.organization.personName)
            }
            for (source, name) in [
                ("Call Marshal", "Marshal"),
                ("Call Dr. Patel", "Dr. Patel"),
                ("Call Dave's mom", "Dave's mom")
            ] {
                let reading = ThoughtExtractionEngine.extractWithRules(
                    source, referenceDate: referenceDate, calendar: calendar)
                XCTAssertEqual(reading.items.count, 1, source)
                XCTAssertEqual(reading.items.first?.organization.personName, name, source)
                let legacyNil = CapturedItem(originalTextSegment: source,
                    displayTitle: source, itemType: .task)
                XCTAssertEqual(MemoryPersonNameResolver.name(for: legacyNil), name, source)
            }
            let namedOffice = "Call Alex's office"
            XCTAssertEqual(PersonMentionResolver.followUpTarget(in: namedOffice), .described("Alex's office"))
            XCTAssertNil(person(namedOffice))
            let embedded = "Summarize Alex's instructions to call the dentist"
            let embeddedReading = ThoughtExtractionEngine.extractWithRules(
                embedded, referenceDate: referenceDate, calendar: calendar)
            XCTAssertEqual(embeddedReading.items.count, 1)
            XCTAssertEqual(embeddedReading.items.first?.organization.personName, "Alex")
            let embeddedNil = CapturedItem(originalTextSegment: embedded,
                displayTitle: embedded, itemType: .task)
            XCTAssertEqual(MemoryPersonNameResolver.name(for: embeddedNil), "Alex")
        }
    }

    func testPersistedDescribedTaskDoesNotReappearAsAMarshalMemoryPerson() throws {
        let previousTaggerMode = SentenceContext.taggerDisabledForEvaluation
        defer {
            SentenceContext.taggerDisabledForEvaluation = previousTaggerMode
            SentenceContextCache.invalidate()
        }
        let source = "Call the fire marshal’s office."
        for disabled in [false, true] {
            SentenceContext.taggerDisabledForEvaluation = disabled
            SentenceContextCache.invalidate()
            // Separate stores prevent the duplicate-capture shortcut from
            // making the second tagger mode reuse the first mode's reading.
            let localContainer = try ModelContainer(for: PersistenceController.schema,
                migrationPlan: SpeakItMigrationPlan.self,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            let localRepository = SwiftDataThoughtRepository(modelContext: localContainer.mainContext,
                requestsReminderAuthorization: false)
            let saved = try localRepository.createCapture(text: source, source: .inAppText,
                createdAt: referenceDate, schedulesReminder: false)
            XCTAssertEqual(saved.itemType, .task)
            XCTAssertTrue(saved.belongsInToday)
            XCTAssertNotEqual(saved.clarificationRequirement, .person)
            XCTAssertNil(saved.personName)
            let freshContext = ModelContext(localContainer)
            let reloaded = try XCTUnwrap(freshContext.fetch(FetchDescriptor<CapturedItem>())
                .first { $0.id == saved.id })
            XCTAssertEqual(reloaded.originalTextSegment, source)
            XCTAssertEqual(reloaded.captureSession?.originalTranscription, source)
            XCTAssertNil(reloaded.personName)
            XCTAssertTrue(reloaded.displayTitle.localizedCaseInsensitiveContains("office"))
            XCTAssertNil(MemoryPersonNameResolver.name(for: reloaded))
            XCTAssertFalse(MemoryGroup.people.contains(reloaded))
            XCTAssertTrue(MemoryGroup.notes.contains(reloaded))
            // Existing explicit metadata is authoritative and is not migrated
            // or silently corrected by this read-time fallback.
            let explicitLegacy = CapturedItem(originalTextSegment: source,
                displayTitle: source, itemType: .task, personName: "Marshal")
            XCTAssertEqual(MemoryPersonNameResolver.name(for: explicitLegacy), "Marshal")
            XCTAssertEqual(explicitLegacy.personName, "Marshal")
        }
    }

    // MARK: - The consequence: does the person appear under People?

    private var memoryPeopleItems: [CapturedItem] {
        let items = (try? container.mainContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
        return items.filter { $0.belongsInMemory && MemoryGroup.people.contains($0) }
    }

    func testAPastEventAboutSomebodyIsFiledUnderThemInMemoryPeople() throws {
        let item = try repository.createCapture(text: "Catherine called me at five")

        XCTAssertTrue(item.belongsInMemory, "a past event is a memory")
        XCTAssertTrue(MemoryGroup.people.contains(item), "it is a memory about a person")
        XCTAssertEqual(MemoryPersonNameResolver.name(for: item), "Catherine")

        let profiles = MemoryPeopleIndex.grouped(memoryPeopleItems)
        XCTAssertEqual(Set(profiles.keys), ["catherine"])
        XCTAssertEqual(MemoryPeopleIndex.resolvedName(in: profiles["catherine"] ?? []), "Catherine")
        XCTAssertTrue(
            MemoryPeopleIndex.items(named: "Catherine", in: memoryPeopleItems)
                .contains { $0.id == item.id },
            "the thought must appear under Catherine, not merely carry her name"
        )
    }

    func testMeetingSomebodyPutsThemInPeople() throws {
        let item = try repository.createCapture(text: "I met Alex yesterday")

        XCTAssertTrue(item.belongsInMemory)
        XCTAssertTrue(MemoryGroup.people.contains(item))
        XCTAssertEqual(MemoryPersonNameResolver.name(for: item), "Alex")
        XCTAssertTrue(
            MemoryPeopleIndex.items(named: "Alex", in: memoryPeopleItems)
                .contains { $0.id == item.id }
        )
    }

    /// The resolver memoizes per item because Memory asks for every row's name
    /// several times per render. The memo must follow the fields it was derived
    /// from: renaming the person in the editor, or re-organizing the words,
    /// has to change the answer on the very next read.
    func testResolvedNameFollowsTheFieldsItWasDerivedFrom() throws {
        let item = try repository.createCapture(text: "I met Alex yesterday")
        XCTAssertEqual(MemoryPersonNameResolver.name(for: item), "Alex")
        XCTAssertEqual(MemoryPersonNameResolver.name(for: item), "Alex", "a cached read agrees")

        item.personName = "Alexandra"
        XCTAssertEqual(MemoryPersonNameResolver.name(for: item), "Alexandra",
                       "an explicit name set after the first read wins immediately")

        item.personName = nil
        item.originalTextSegment = "I met Priya yesterday"
        item.displayTitle = "Met Priya"
        XCTAssertEqual(MemoryPersonNameResolver.name(for: item), "Priya",
                       "new words are re-read rather than served from the memo")

        let twin = CapturedItem(
            id: item.id,
            originalTextSegment: "I met Sam yesterday",
            displayTitle: "Met Sam"
        )
        XCTAssertEqual(MemoryPersonNameResolver.name(for: twin), "Sam",
                       "a different object with a reused ID is keyed by its own fields")
    }

    func testSeveralMemoriesAboutOnePersonCollapseIntoOneProfile() throws {
        _ = try repository.createCapture(text: "Catherine called me at five")
        _ = try repository.createCapture(text: "Remember Catherine's birthday is in March")
        _ = try repository.createCapture(text: "Remember Catherine likes sushi")

        let profiles = MemoryPeopleIndex.grouped(memoryPeopleItems)
        XCTAssertEqual(Set(profiles.keys), ["catherine"])
        XCTAssertEqual(profiles["catherine"]?.count, 3)
    }

    /// Negation and auxiliaries change the content of a fact, never its owner.
    /// These assertions pin both the stored taxonomy and the collection the
    /// Memory UI actually reads.
    func testNegativePreferencesAndAllergiesStayUnderThePerson() throws {
        let statements = [
            "Sarah likes sushi",
            "Sarah doesn't like sushi",
            "Sarah dislikes sushi",
            "Sarah prefers window seats",
            "Sarah does not eat shellfish",
            "Sarah is allergic to peanuts",
            "Sarah is not allergic to shellfish",
            "Sarah has never tried sushi",
            "Sarah lives in Toronto",
            "Sarah doesn't live in Toronto",
        ]

        for statement in statements {
            let item = try repository.createCapture(text: statement)
            XCTAssertEqual(item.itemType, .note, statement)
            XCTAssertEqual(item.category, .people, statement)
            XCTAssertEqual(item.personName, "Sarah", statement)
            XCTAssertTrue(item.belongsInMemory, statement)
            XCTAssertTrue(MemoryGroup.people.contains(item), statement)
        }

        let profiles = MemoryPeopleIndex.grouped(memoryPeopleItems)
        XCTAssertEqual(Set(profiles.keys), ["sarah"])
        XCTAssertEqual(profiles["sarah"]?.count, statements.count)
    }

    /// The other direction: a memory that names nobody must stay in Reference,
    /// or People fills with rows nobody can find again.
    func testMemoriesThatNameNobodyStayOutOfPeople() throws {
        for text in [
            "The wifi password is maple syrup",
            "Toronto is cold in February",
            "The storage room code is 4821",
        ] {
            let item = try repository.createCapture(text: text)
            XCTAssertFalse(MemoryGroup.people.contains(item), text)
            XCTAssertTrue(MemoryGroup.notes.contains(item), text)
        }

        XCTAssertTrue(memoryPeopleItems.isEmpty)
    }

    // MARK: - Plurals of things that are not people

    /// `neverName` is written in the singular and was looked up exactly, so
    /// every plural walked past it and became a person. The singular/plural
    /// pair is the whole proof: the same sentence with "note" filed nobody and
    /// with "notes" filed a person called Notes.
    func testAPluralCommonNounIsNotAPerson() {
        let pairs = [
            ("call note about the thing", "call notes about the thing"),
            ("tell report to the team", "tell reports to the team"),
            ("email invoice to the client", "email invoices to the client"),
            ("text reminder to the group", "text reminders to the group"),
            ("message package to her", "message packages to her"),
            ("call deadline about it", "call deadlines about it"),
        ]
        for (singular, plural) in pairs {
            XCTAssertNil(person(singular), "control: \(singular)")
            XCTAssertNil(person(plural), "plural must be read the same way: \(plural)")
        }
    }

    /// "meeting notes" and "meeting agenda" sit exactly where "meeting Sarah"
    /// sits, so they read as somebody being met. Both were filed under People.
    func testMeetingFurnitureIsNotSomebodyBeingMet() {
        XCTAssertNil(person("meeting notes from the sync with design"))
        XCTAssertNil(person("meeting agenda for Monday"))
        XCTAssertNil(person("send me the deck before the review"))
    }

    /// The guard on the plural fold. Only a trailing "s" is stripped, and only
    /// when what is left is itself in the stoplist — so real names that end in
    /// "s" are untouched. This is the assertion that fails first if anybody
    /// widens the fold to "es" or a stemmer.
    func testRealNamesEndingInSStillResolve() {
        XCTAssertEqual(person("call Chris about the invoice"), "Chris")
        XCTAssertEqual(person("tell James the meeting moved"), "James")
        XCTAssertEqual(person("remind me to call Miles tomorrow"), "Miles")
        XCTAssertEqual(person("ask Agnes about the booking"), "Agnes")
        XCTAssertEqual(person("text Jess about dinner"), "Jess")
    }

    /// A transport verb carries a person as readily as a parcel, and the
    /// parcel is the common case, so the object counts as a person only with
    /// kinship or the tagger's personal-name reading behind it.
    func testTransportVerbsCarryPeopleNotParcels() {
        XCTAssertEqual(person("Pick up Alex from school"), "Alex")
        XCTAssertEqual(person("pick up mom at the airport"), "Mom")
        XCTAssertEqual(person("Drop off Sam at practice"), "Sam")
        XCTAssertEqual(person("Collect Dad from the station"), "Dad")
        XCTAssertEqual(person("Get Sam from the airport"), "Sam")
        XCTAssertEqual(person("Collect Priya from daycare"), "Priya")
        XCTAssertNil(person("pick up milk"))
        XCTAssertNil(person("Pick up Tylenol at Shoppers"))
        XCTAssertNil(person("Pick up the supplies from school"))
        XCTAssertNil(person("Get milk from the store"))
        XCTAssertNil(person("pick up the dry cleaning"))
    }

    /// "Let Priya know" is anchored on its "know", and the anchor is where the
    /// name stops. Dictation writes the name in lowercase, the lowercase path
    /// lets a second lowercase word join the name, and "know" was that word:
    /// "let priya know the meeting moved" filed a person called Priya Know.
    func testTheAnchorOfLetSomebodyKnowIsNotPartOfTheName() {
        XCTAssertEqual(person("let priya know the meeting moved"), "Priya")
        XCTAssertEqual(person("Let Priya know the trip is cancelled"), "Priya")
        XCTAssertNil(person("let me know when you land"))
    }
}
