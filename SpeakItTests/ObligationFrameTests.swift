import XCTest
@testable import SpeakIt

/// The title reducer, asserted as a contract rather than as a corpus family.
///
/// A corpus `title` disagreement grades `.cosmetic` (`CorpusSeverity.forField`),
/// so it reports and never gates. The four properties in the last section are
/// the ones that must actually fail a build: they are what stops a widened
/// vocabulary from inverting a prohibition, inventing a word, or making launch
/// maintenance re-shorten its own output on every launch.
@MainActor
final class ObligationFrameTests: XCTestCase {

    func testHadBetterRequiresAClearActionComplement() {
        for (source, expected) in [
            ("I had better drop the car off on Thursday", "Drop the car off on Thursday"),
            ("I had better call the bank tomorrow", "Call the bank tomorrow"),
            ("We had better pay the rent", "Pay the rent"),
            ("I had better just book the dentist", "Book the dentist"),
            ("I think I had better call the bank", "Call the bank"),
        ] {
            XCTAssertEqual(title(source), expected, source)
            XCTAssertEqual(title(expected), expected, "Reduction must be idempotent")
        }
        for source in [
            "I had better luck last time",
            "I had better service at that hotel",
            "I had better call quality on that phone",
            "I had better pay last year",
            "I had better not call the bank",
            "I had better never call the bank",
            "I had better call the last time",
            "I had better",
        ] {
            XCTAssertEqual(title(source), source, source)
        }
        let source = "I had better call the bank"
        XCTAssertEqual(ThoughtTitleFormatter.polished(source, itemType: .task, reduceFrames: false), source)
    }

    private func title(_ text: String, _ type: ItemType = .task) -> String {
        ThoughtTitleFormatter.polished(text, itemType: type)
    }

    func testHadBetterCaptureKeepsItsWordsAndDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 10))!
        let source = "I had better drop the car off on Thursday"
        let items = ThoughtExtractionEngine.extractWithRules(
            source, referenceDate: reference, calendar: calendar
        ).items
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.analysisText, source)
        XCTAssertEqual(item.organization.itemType, .task)
        XCTAssertEqual(item.organization.dueDate,
                       calendar.date(from: DateComponents(year: 2026, month: 8, day: 6)))
        XCTAssertNil(item.organization.reminderDate)
        XCTAssertEqual(title(item.analysisText), "Drop the car off on Thursday")
    }

    // MARK: - The frames people actually speak

    /// One assertion per obligation frame English has. Each is the *same*
    /// construction — a matrix clause whose only job is to introduce the task —
    /// and the point of listing them is that they are one rule, not thirty.
    func testAnObligationFrameIsNotPartOfTheTask() {
        let expected: [(String, String)] = [
            // The measured defect set. Every one of these was shipping with the
            // person's own throat-clearing as the row title.
            ("I've got to pick up the dry cleaning before six", "Pick up the dry cleaning before six"),
            ("I have got to get the snow tires swapped before November", "Get the snow tires swapped before November"),
            ("I keep meaning to get the car washed", "Get the car washed"),
            ("I've been meaning to bring the drill back to Dave", "Bring the drill back to Dave"),
            ("I keep forgetting to water the plants", "Water the plants"),
            ("I'm going to need to call the dentist to reschedule my cleaning", "Call the dentist to reschedule my cleaning"),
            ("I'm going to have to rewrite the onboarding sequence", "Rewrite the onboarding sequence"),
            ("I gotta ping Alex about the design review", "Ping Alex about the design review"),
            ("I ought to send the deposit to the landlord tomorrow", "Send the deposit to the landlord tomorrow"),
            ("I'm supposed to bring snacks to the game on Saturday", "Bring snacks to the game on Saturday"),
            ("I plan to leave at six", "Leave at six"),
            ("I want to see the doctor about my knee", "See the doctor about my knee"),

            // First person plural. The old formatter knew only "I", so every
            // household and every team lost its title.
            ("We need to talk to the landlord about the leak in the bathroom", "Talk to the landlord about the leak in the bathroom"),
            ("We have to call the airline and change our seats", "Call the airline and change our seats"),
            ("We need to book a babysitter for Saturday night", "Book a babysitter for Saturday night"),
            ("We should probably get the oil changed before the trip", "Get the oil changed before the trip"),
            ("We have to renew the lease", "Renew the lease"),

            // A wrapper taking a finite clause. The obligation inside it is
            // optional, which is why "Make sure I have the tickets" keeps its
            // verb instead of being cut back to the noun phrase.
            ("Make sure I stop at the bank before it closes today", "Stop at the bank before it closes today"),
            ("Make sure that I call the school in the morning", "Call the school in the morning"),
            ("Make sure I have the tickets", "Have the tickets"),
            ("Please make sure I lock the door", "Lock the door"),

            // A record wrapper around a live obligation. The obligation link is
            // required here — see the control for the bare form.
            ("Remember that I have to renew my passport before we travel", "Renew my passport before we travel"),
            ("Remember I have to buy milk", "Buy milk"),
            ("Note that I have to renew the lease", "Renew the lease"),

            // Hedges, in both positions. A hedge in front of a frame used to
            // shield it, because the two were stripped by separate ordered
            // passes and the frame went first.
            ("Actually I need to cancel the gym membership", "Cancel the gym membership"),
            ("Probably I need to book the flight to Vancouver", "Book the flight to Vancouver"),
            ("Still I need to file the expense report", "File the expense report"),
            ("Finally I need to sort out the insurance", "Sort out the insurance"),
            ("I really should call my sister back", "Call my sister back"),
            ("I really really really need to call the dentist", "Call the dentist"),
            ("I probably definitely should maybe call the dentist", "Call the dentist"),

            // Stacked links are one frame, not several half-stripped ones.
            ("I am going to need to have to call the dentist", "Call the dentist"),
            ("I need to remember to bring the charger", "Bring the charger"),

            // A cognitive matrix, and a complementizer left behind by a clause
            // cut upstream. "That I should probably email Marcus" was a shipping
            // row title.
            ("I think I should call the dentist tomorrow", "Call the dentist tomorrow"),
            ("I thought I should call the dentist", "Call the dentist"),
            ("I guess I have to file the expense report", "File the expense report"),
            ("That I should call the dentist", "Call the dentist"),

            // The founder's own sentence, and its realistic sibling. Both
            // already worked; both must keep working.
            ("I need to go to friend to do this", "Go to friend to do this"),
            ("I need to go to my friend's house to drop off the drill", "Go to my friend's house to drop off the drill")
        ]

        for (utterance, want) in expected {
            XCTAssertEqual(title(utterance), want, "framing survived in: \(utterance)")
        }
    }

    // MARK: - What must never move

    /// The controls, and they are the point of the whole design.
    ///
    /// Each one contains a word the reducer watches for, in a position where
    /// deleting it would change what the person is being told to do. A widened
    /// `ObligationFrame.link` shows up here first.
    func testWordingThatOnlyLooksLikeAFrameIsLeftAlone() {
        let unchanged: [(String, String)] = [
            // Object control. The infinitive belongs to somebody else, and
            // reducing it hands their errand to the phone's owner.
            ("I told Alex to get the wrench", "someone else's errand"),
            ("I asked Marcus to send the invoice", "someone else's errand"),
            ("I want Priya to review the contract", "someone else's errand"),
            ("I promised Sam to bring the drill", "someone else's errand"),

            // Purpose adjuncts. The `to` opens a reason, not the task.
            ("I need some time to think about the offer", "purpose adjunct"),
            ("I need a wrench to fix the gate", "purpose adjunct"),
            ("I have a form to fill out", "purpose adjunct"),

            // The past. A report is not an instruction, and every one of these
            // forms is absent from `link` on purpose.
            ("I had to cancel the appointment", "past obligation, already discharged"),
            ("I refused to cancel the insurance policy", "past, and reducing it inverts it"),
            ("I managed to cancel the insurance policy", "past, already done"),
            ("I got to see the house before the offer closed", "past reading of got to"),

            // Negation. Reducing any of these tells the person to do the exact
            // thing they asked to be warned off.
            ("I no longer need to renew the membership", "released obligation"),
            ("I should not sign the lease until Dana looks at it", "prohibition"),
            ("I must not forget the passport", "prohibition"),
            ("We should not tell Mom about the party yet", "prohibition"),
            ("I need to not forget the passport", "prohibition"),
            ("I have to never let that happen again", "prohibition"),
            ("I should never call that number again", "prohibition"),

            // The tail cancels the head, and no head-anchored pattern can see
            // it. The retraction veto is what covers these.
            ("I was going to call Catherine but I didn't", "retracted"),
            ("I keep meaning to but I never do", "retracted, and the frame has no complement"),
            ("I need to and I will", "frame with no complement"),
            ("I should but I probably won't", "frame with no complement"),

            // Deliberation and non-factive matrices. None of these is a
            // decision, and deleting the matrix would make it one.
            ("I wonder if I should call the vet about the dog", "no decision made"),
            ("It would be good if I could clear out the garage", "no decision made"),
            ("I hope I remember the milk", "non-factive"),
            ("I doubt I need to call the dentist", "non-factive"),

            // Modals that carry no obligation at all.
            ("I would rather go on Saturday", "preference"),
            ("I can pick up the milk on the way", "ability"),
            ("I like to call my mother on Sundays", "habitual"),

            // A record, not an instruction. This is why the `remember`/`note`
            // layer requires an obligation link.
            ("Remember I parked on level three", "a record"),
            ("Note I owe Marcus forty dollars", "a record"),

            // First person in the middle of a title is content: it says who,
            // why, or which one.
            ("Tell the bank I'm travelling so my card works", "first person is the message"),
            ("Pack Ellie's lunch tonight so I'm not rushing", "first person is the motive"),
            ("Stretch before I run from now on", "first person is the timing"),
            ("Track my headaches so I can tell the doctor", "first person is the purpose"),
            ("Cancel that subscription I'm not using", "first person identifies the object"),

            // Already short. Any strip would empty the row.
            ("Water the plants", "already imperative"),
            ("Get ink", "already imperative"),
            ("Renew my passport", "already imperative"),

            // A hedge that can head a verb phrase is not a hedge.
            ("Look into whether refinancing makes sense", "look is a verb here")
        ]

        for (utterance, why) in unchanged {
            XCTAssertEqual(title(utterance), utterance, "reduced a title it must not touch (\(why))")
        }
    }

    /// Memory keeps its declarative voice. The obligation layers are
    /// unreachable for a non-actionable type, which is what stops a remembered
    /// fact from being rewritten as an order.
    func testMemoryRowsAreNotTurnedIntoInstructions() {
        for fact in [
            "My blood type is O negative",
            "The best time to call my sister is after eight her time",
            "Sarah is allergic to shellfish so no seafood at the dinner",
            "The garage code is 1972"
        ] {
            XCTAssertEqual(title(fact, .note), fact)
        }
    }

    /// A person's own keyboard outranks the reducer. Without this there is no
    /// way to type your way out of a reduction you disagree with, because
    /// `update(_:with:)` re-polishes what you typed.
    func testAHandTypedTitleKeepsItsFraming() {
        let typed = "We need to talk to the landlord"
        XCTAssertEqual(
            ThoughtTitleFormatter.polished(typed, itemType: .task, reduceFrames: false),
            typed
        )
        // The presentation tidying still runs on a hand-typed title.
        XCTAssertEqual(
            ThoughtTitleFormatter.polished("  call   mom .", itemType: .task, reduceFrames: false),
            "Call mom"
        )
    }

    // MARK: - Properties that must gate

    /// Every utterance the regression net already contains. The properties
    /// below are asserted over all of it, so a rule that misfires anywhere in
    /// the corpus fails here even though a corpus `title` disagreement on its
    /// own only reports.
    private var corpusUtterances: [String] {
        CorpusEvaluator.allFamilies.flatMap(\.1).map(\.utterance)
    }

    private var everyLayerSet: [(String, ObligationFrame.Layers)] {
        [
            ("actionable", ObligationFrame.actionable),
            ("idea", ObligationFrame.idea),
            ("recording", ObligationFrame.recording),
            ("handEdited", ObligationFrame.handEdited)
        ]
    }

    private func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}']"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
    }

    /// **Deletion only.** The reducer may remove words and may remove nothing;
    /// it may never substitute, reorder or invent. This is the property that
    /// makes it safe to run over text nobody reviewed, and it is asserted
    /// directly on `ObligationFrame` rather than through `polished`, because
    /// `ReminderCopy` upstream has its own declared substitutions ("Alarm",
    /// "Your reminder", the supplied "Don't" of a prohibition) and folding the
    /// two together would make this assertion unable to fail for the right
    /// reason.
    func testTheReducerOnlyEverDeletes() {
        for utterance in corpusUtterances {
            let source = words(utterance)
            for (name, layers) in everyLayerSet {
                let peeled = ObligationFrame.peeled(utterance, using: layers)
                let produced = words(peeled)
                // Asserted separately: `isSubsequence` returns true for an empty
                // needle, so without this a reducer that deleted everything
                // would satisfy the deletion-only property vacuously.
                XCTAssertFalse(
                    peeled.trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(name) layer emptied the thought: \(utterance)"
                )
                XCTAssertTrue(
                    isSubsequence(produced, of: source),
                    "\(name) layer did not delete-only: \(utterance) -> \(produced.joined(separator: " "))"
                )
            }
        }
    }

    /// A contiguous subsequence, not merely a subset: a reduction that
    /// reordered the person's words would still be a subset of them.
    private func isSubsequence(_ needle: [String], of haystack: [String]) -> Bool {
        guard !needle.isEmpty else { return true }
        guard needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }

    /// Idempotence. Launch maintenance re-feeds the formatter its own output,
    /// so a reducer that keeps shortening would eat a title one launch at a
    /// time.
    func testTheReducerIsIdempotent() {
        for utterance in corpusUtterances {
            for (name, layers) in everyLayerSet {
                let once = ObligationFrame.peeled(utterance, using: layers)
                XCTAssertEqual(
                    ObligationFrame.peeled(once, using: layers),
                    once,
                    "\(name) layer is not idempotent: \(utterance)"
                )
            }
        }
    }

    /// Rendering invariance. What the recognizer did with capitals and commas
    /// must not change which words the reducer removes — the contract
    /// `RenderingInvarianceTests` states for the parse, stated here for the
    /// title, where that suite deliberately only reports.
    ///
    /// Colons are left in place: stripping one turns "9:15" into "915" and
    /// changes the sentence rather than its rendering.
    func testTheReducerSurvivesLowercasingAndCommaLossAndFullStops() {
        for utterance in corpusUtterances {
            let renderings = [
                utterance.lowercased(),
                utterance.replacingOccurrences(of: #"[,;]"#, with: "", options: .regularExpression),
                utterance.replacingOccurrences(of: #"[,;.!?]"#, with: "", options: .regularExpression).lowercased()
            ]
            for (name, layers) in everyLayerSet {
                let base = removedWordCount(utterance, layers)
                for rendering in renderings {
                    XCTAssertEqual(
                        removedWordCount(rendering, layers),
                        base,
                        "\(name) layer removed a different amount under a rendering: \(utterance)"
                    )
                }
            }
        }
    }

    private func removedWordCount(_ text: String, _ layers: ObligationFrame.Layers) -> Int {
        words(text).count - words(ObligationFrame.peeled(text, using: layers)).count
    }

    /// The post-condition. A reduction that leaves the first-person subject in
    /// place did not finish, and a half-finished cut is worse than none.
    private static let opensOnFirstPerson = #"^(?i)(?:i|we)(?:\b|['\#u{2019}])"#

    func testAReducedTitleNeverOpensOnAFirstPersonSubject() {
        for utterance in corpusUtterances {
            let produced = ObligationFrame.peeled(utterance, using: ObligationFrame.actionable)
            guard produced != utterance else { continue }
            // The escape must be `\#u`, not `\u`: inside a raw string `\u{2019}`
            // is literal text, the pattern then fails to compile, `range(of:)`
            // returns nil, and this assertion passes for every input. It did.
            XCTAssertNotNil(
                try? NSRegularExpression(pattern: Self.opensOnFirstPerson),
                "the post-condition pattern must compile, or this test asserts nothing"
            )
            XCTAssertNil(
                produced.range(of: Self.opensOnFirstPerson, options: [.regularExpression]),
                "half-finished reduction: \(utterance) -> \(produced)"
            )
        }
    }

    /// End to end, through the real formatter: a row title may still contain
    /// only words the speaker said, once `ReminderCopy`'s own declared
    /// substitutions are excepted. Those are the supplied auxiliary of a
    /// prohibition and the three placeholder titles for a bare reminder, an
    /// alarm and an unreadable capture; they predate this change and are
    /// asserted elsewhere.
    func testAFinishedTitleAddsNothingBeyondTheDeclaredReminderVocabulary() {
        let declared: Set<String> = [
            "don't", "dont", "alarm", "timer", "wake", "up",
            "your", "reminder", "review", "captured", "thought"
        ]
        for utterance in corpusUtterances {
            for type in [ItemType.task, .note, .idea] {
                let extra = Set(words(title(utterance, type))).subtracting(words(utterance))
                XCTAssertTrue(
                    extra.subtracting(declared).isEmpty,
                    "title invented \(extra.subtracting(declared)): \(utterance)"
                )
            }
        }
    }

    // MARK: - Names keep the resolver's casing

    /// The title keeps the speaker's words, and dictation writes names in
    /// lowercase, so a row that resolved its person as Dave still read "Don't
    /// text dave". The resolver already decided the word is a name; the title
    /// writes it the way the resolver did, and touches nothing else.
    func testAResolvedNameIsWrittenAsANameInTheTitle() {
        XCTAssertEqual(
            ThoughtTitleFormatter.polished("Don't text dave", itemType: .task, personName: "Dave"),
            "Don't text Dave"
        )
        XCTAssertEqual(
            ThoughtTitleFormatter.polished("call dave o'brien about the invoice", itemType: .task, personName: "Dave O'Brien"),
            "Call Dave O'Brien about the invoice"
        )
        // A name the speaker cased themselves is never flattened.
        XCTAssertEqual(
            ThoughtTitleFormatter.restoringNameCasing(in: "Ask McKenzie about the report", person: "Mckenzie"),
            "Ask McKenzie about the report"
        )
        // Only whole words: "dave" inside "davenport" is not the name.
        XCTAssertEqual(
            ThoughtTitleFormatter.restoringNameCasing(in: "Move the davenport", person: "Dave"),
            "Move the davenport"
        )
        // No person, no change.
        XCTAssertEqual(
            ThoughtTitleFormatter.polished("Don't text dave", itemType: .task),
            "Don't text dave"
        )
    }
}
