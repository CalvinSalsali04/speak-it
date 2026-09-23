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

    /// A transport verb carries a person as readily as a parcel, and the
    /// parcel is the common case, so the object counts as a person only with
    /// kinship or the tagger's personal-name reading behind it.
    func testTransportVerbsCarryPeopleNotParcels() {
        XCTAssertEqual(person("Pick up Alex from school"), "Alex")
        XCTAssertEqual(person("pick up mom at the airport"), "Mom")
        XCTAssertEqual(person("Drop off Sam at practice"), "Sam")
        XCTAssertEqual(person("Collect Dad from the station"), "Dad")
        XCTAssertEqual(person("Get Sam from the airport"), "Sam")
        XCTAssertNil(person("pick up milk"))
        XCTAssertNil(person("Pick up Tylenol at Shoppers"))
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

    // MARK: - Entity context: what the words around a name say it is

    /// A motion or arrival frame reaches a **destination**, and reading its
    /// object as a human is how "when I get to <shop>" filed a person.
    ///
    /// The discriminator is the particle and nothing else: these verbs do
    /// address people, but through one ("get back to", "reach out to", "walk
    /// over to"), and a bare "to" after them is a place. No list of shops is
    /// consulted, so a destination nobody has heard of is read the same way a
    /// famous one is — which is the point, because the previous answer came
    /// from whether Apple's name tagger happened to carry an entry.
    func testAMotionFrameReachesAPlaceAndNeverAPerson() {
        let destinations = [
            "when I get to Sobeys",
            "remind me to buy stamps when I get to Shoppers",
            "walk to Riverdale after dinner",
        ]
        for utterance in destinations {
            XCTAssertNil(
                PersonMentionResolver.primary(in: utterance),
                "\(utterance) named \(PersonMentionResolver.mentions(in: utterance).map(\.label))"
            )
            XCTAssertEqual(PersonMentionResolver.entityKind(in: utterance), .place, utterance)
        }
    }

    /// The other half of the same rule, which is what keeps it from being a
    /// deletion: with a particle these verbs still reach the person behind it.
    func testAParticleStillCarriesAMotionVerbToAPerson() {
        XCTAssertEqual(
            PersonMentionResolver.primary(in: "get back to Alex about the quote")?.label, "Alex"
        )
        XCTAssertEqual(
            PersonMentionResolver.primary(in: "reach out to Priya tomorrow")?.label, "Priya"
        )
        XCTAssertEqual(
            PersonMentionResolver.primary(in: "walk over to Sam and ask")?.label, "Sam"
        )
        // Unchanged control: the verbs that were never motion verbs.
        XCTAssertEqual(
            PersonMentionResolver.primary(in: "follow up with Dana on Friday")?.label, "Dana"
        )
    }

    /// Three rules can produce a person — the object of an address verb, the
    /// subject of a fact, and the owner of something — and only the first
    /// consulted any non-person evidence. So the identical phrase was refused
    /// in one frame and filed in another, one function away.
    func testTheSameEntityEvidenceAppliesWhereverANameCanArrive() {
        // The address rule, which already refused these. The control.
        XCTAssertNil(PersonMentionResolver.primary(in: "Call Sterling Bank about the transfer"))
        // The fact subject, which did not.
        XCTAssertNil(
            PersonMentionResolver.primary(in: "Sterling Bank needs my signature by Friday"),
            "a bank is not somebody, in whichever slot it is said"
        )
        // The owner of something, which did not either.
        XCTAssertNil(
            PersonMentionResolver.primary(in: "Lakeshore Dental's policy is twenty-four hours")
        )
        // And a person in the same two shapes, so this is evidence and not a
        // rule that has stopped reading subjects and owners at all.
        XCTAssertEqual(
            PersonMentionResolver.primary(in: "Marguerite needs my signature by Friday")?.label,
            "Marguerite"
        )
        XCTAssertEqual(
            PersonMentionResolver.primary(in: "Marguerite's flight is at six")?.label,
            "Marguerite"
        )
    }

    /// A department written as an acronym collides with an ordinary word once
    /// its case is folded away, and the collision threw the target out twice:
    /// the name rules refused "IT" correctly, and the *described* reader then
    /// refused it too — so a perfectly clear errand was held for review asking
    /// who to message.
    ///
    /// Paired with the shape that really does name nobody, so the assertion
    /// cannot pass by the frame simply not being a follow-up.
    func testADepartmentAcronymIsATargetAndNotAPronoun() throws {
        XCTAssertEqual(
            PersonMentionResolver.followUpTarget(in: "message IT support about the printer"),
            .described("IT support")
        )
        XCTAssertNil(PersonMentionResolver.primary(in: "message IT support about the printer"))
        XCTAssertEqual(
            PersonMentionResolver.entityKind(in: "message IT support about the printer"), .role
        )

        let named = try repository.createCapture(text: "message IT support about the printer")
        XCTAssertNotEqual(
            named.clarificationRequirement, .person,
            "the capture says who to message"
        )

        XCTAssertEqual(
            PersonMentionResolver.followUpTarget(in: "message them about the printer"), .missing
        )
        let unnamed = try repository.createCapture(text: "message them about the printer")
        XCTAssertEqual(
            unnamed.clarificationRequirement, .person,
            "control: the same frame with nobody in it still asks who"
        )
    }

    /// An overdraft, a premium or a prescription refill is a relationship held
    /// with an institution, and a human is not on the other end of one. The
    /// evidence is the complement, not the name, so an unfamiliar company is
    /// read the same way a famous one is.
    ///
    /// The cost of a wrong call is bounded and chosen: the target stays on the
    /// row as words and nothing is asked — only the filing under People is
    /// withheld. That is why this fires without asking the name tagger, which
    /// reads most companies as surnames because most of them are.
    func testAnAccountIsHeldWithAnInstitutionAndNotWithAPerson() throws {
        try XCTSkipUnless(
            PersonMentionResolver.primary(in: "call Vestara about the overdraft")?.label == "Vestara",
            "control: the recognizer already refuses this name in this process, "
                + "so the contrast between the two complements cannot be read here"
        )
        XCTAssertNil(
            PersonMentionResolver.primary(in: "call Vestara about my overdraft"),
            "an overdraft is held with an institution"
        )
        // Kinship is exempt, and it is exempt before any of this is read.
        XCTAssertEqual(
            PersonMentionResolver.primary(in: "call Mom about my prescription")?.label, "Mom"
        )
        // A noun a person can own just as easily keeps its person.
        XCTAssertEqual(
            PersonMentionResolver.primary(in: "text Jess about my card")?.label, "Jess"
        )
    }

    /// The whole contrast, on one invented name, in four frames. If any of
    /// these answers came from a list of companies or places the name would
    /// have to be in it, and it is in nothing.
    func testTheSameNameChangesKindWithTheFrameAroundIt() throws {
        try XCTSkipIf(
            PersonMentionResolver.nameEvidence(for: "Marlowe").organization,
            "control: the name tagger reads this name as an organization in this "
                + "process, so the person row cannot be read here"
        )
        XCTAssertEqual(PersonMentionResolver.entityKind(in: "call Marlowe on Friday"), .person)
        XCTAssertEqual(
            PersonMentionResolver.entityKind(in: "when I get to Marlowe pick up the order"), .place
        )
        XCTAssertEqual(
            PersonMentionResolver.entityKind(in: "call Marlowe Dental on Friday"), .organization
        )
        XCTAssertEqual(
            PersonMentionResolver.entityKind(in: "message Marlowe support about the outage"), .role
        )
    }

    /// `walk` is a motion verb and a social noun in the same file — "a walk
    /// with Priya tomorrow" is how people record who they are seeing — and the
    /// first version of the motion rule vetoed its connector rather than its
    /// destination, so "walk with Sam" named nobody.
    ///
    /// The second assertion is why that mattered more than a missing name.
    /// `ThoughtExtractor`'s boundary rules ask the person layer whether the
    /// left conjunct names somebody, so losing Sam collapsed a two-errand
    /// capture into one row and **the Friday errand was gone**. Losing a
    /// thought the person just spoke is the failure this app cannot have.
    func testAccompanimentIsNotADestination() {
        XCTAssertEqual(PersonMentionResolver.primary(in: "walk with Sam tomorrow")?.label, "Sam")
        XCTAssertEqual(PersonMentionResolver.primary(in: "a walk with Priya tomorrow")?.label, "Priya")
        // The destination reading is unchanged: "to" is what the veto is
        // written against, and "with" never marks one.
        XCTAssertNil(PersonMentionResolver.primary(in: "walk to Riverdale after dinner"))

        XCTAssertEqual(
            ThoughtExtractionEngine.extractWithRules(
                "Walk with Sam tomorrow and Priya Friday",
                referenceDate: referenceDate,
                calendar: calendar
            ).items.count,
            2,
            "the Friday errand is a second thought and must survive"
        )
    }

    /// A head noun beside a name belongs to the target — "Northwind
    /// accounting" — but behind a possessive it is the thing possessed, and it
    /// belongs to nobody but the owner. Reading it as the owner's head took
    /// the person off the row in every shape where somebody owns a thing with
    /// an institutional word in its name.
    ///
    /// Nothing caught this. The suite's other possessive case is
    /// "Marguerite's flight is at six", and `flight` is in none of the head
    /// lists, so it passed and read as assurance.
    func testAPossessedNounIsNotTheOwnersHead() {
        XCTAssertEqual(PersonMentionResolver.primary(in: "Return Sam's library book")?.label, "Sam")
        XCTAssertEqual(PersonMentionResolver.primary(in: "Sign Alex's school forms")?.label, "Alex")
        XCTAssertEqual(
            PersonMentionResolver.primary(in: "Grab Priya's medical records")?.label, "Priya"
        )
        XCTAssertEqual(
            PersonMentionResolver.primary(in: "Email Dana's team about the change")?.label, "Dana"
        )
        // The control, so the scan is not simply switched off: a head noun
        // that is *not* behind a possessive still types the phrase.
        XCTAssertNil(PersonMentionResolver.primary(in: "Call Sterling Bank about the transfer"))
    }

    /// The frames the name tagger is asked in are not supposed to contain the
    /// answer, and the two this file used to build did: "I spoke with <name>"
    /// and "<name> said hello" are constructions only a human is grammatical
    /// in. For a bare company name that tag is the *only* evidence there is —
    /// there is no head noun beside it to read — so a leading question there
    /// decides the whole case.
    ///
    /// **This test measures consistency, not correctness.** It pins the one
    /// property that must hold, that the replacement frames do not lose a real
    /// person, and prints the organization comparison rather than asserting
    /// it: whether the frame was what decided those is a measurement, and
    /// pinning an expectation to it here would be writing the answer down
    /// before reading it. If the printed pairs are identical, the frame was
    /// not the cause and only a model can type those words.
    func testTheTaggerFrameIsNotALeadingQuestion() throws {
        let controls = ["Sarah", "Priya", "Catherine"]
        try XCTSkipUnless(
            controls.contains { PersonMentionResolver.leadingFrameEvidence(for: $0).personal },
            "NLTagger produced no personal-name tag for any control name in this "
                + "process, so nothing here can answer either way"
        )
        for name in controls where PersonMentionResolver.leadingFrameEvidence(for: name).personal {
            XCTAssertTrue(
                PersonMentionResolver.nameEvidence(for: name).personal,
                "the neutral frames must not cost a real person their tag: \(name)"
            )
        }
        for name in ["Costco", "Shopify", "Loblaws", "Telus", "Lululemon", "Amex"] {
            let leading = PersonMentionResolver.leadingFrameEvidence(for: name)
            let neutral = PersonMentionResolver.nameEvidence(for: name)
            print(
                "entity-frame-comparison \(name) leading(personal:\(leading.personal),"
                    + "organization:\(leading.organization)) "
                    + "neutral(personal:\(neutral.personal),organization:\(neutral.organization))"
            )
        }
    }
}
