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
}
