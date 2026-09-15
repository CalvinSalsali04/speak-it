import XCTest
@testable import SpeakIt

/// The safety argument for putting a generative model in the capture path,
/// stated as tests that need no model.
///
/// Every case here is a property of a `CaptureInterpretation` and the
/// transcript it claims to interpret, so the whole contract runs on a machine
/// where Apple Intelligence does not exist — which is every machine this
/// project has had so far. A guard that can only be checked on hardware nobody
/// owns is not a guard.
final class InterpretationPolicyTests: XCTestCase {

    private let transcript = "remind me to email the landlord tomorrow and priya said she'd drop off the keys"

    private func accepted(_ interpretation: CaptureInterpretation, _ text: String? = nil) -> Bool {
        if case .success = InterpretationPolicy.check(interpretation, against: text ?? transcript) {
            return true
        }
        return false
    }

    private func rejection(
        _ interpretation: CaptureInterpretation,
        _ text: String? = nil
    ) -> InterpretationPolicy.Rejection? {
        if case let .failure(reason) = InterpretationPolicy.check(interpretation, against: text ?? transcript) {
            return reason
        }
        return nil
    }

    // MARK: Grounding

    func testAGroundedReadingIsAccepted() {
        let interpretation = CaptureInterpretation(segments: [
            InterpretedSegment(
                quote: "email the landlord",
                carriedContext: "remind me to",
                obligation: .speakerOwes,
                temporalText: "tomorrow",
                temporalRole: .reminderRequest,
                suggestedTitle: "Email the landlord"
            ),
            InterpretedSegment(
                quote: "she'd drop off the keys",
                disposition: .reported,
                obligation: .otherOwes,
                attributedTo: "priya",
                suggestedTitle: "Priya dropping off the keys"
            ),
        ])
        XCTAssertTrue(accepted(interpretation))
    }

    func testAQuoteThatIsNotInTheTranscriptIsRejected() {
        let interpretation = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "book the ferry crossing")
        ])
        XCTAssertEqual(rejection(interpretation), .ungroundedSpan)
    }

    /// Plain substring containment accepts "art" as grounded by "start", which
    /// is how an invented target survives a grounding check that looks like it
    /// works. Here "land" sits inside "landlord" and is not a span of the
    /// capture.
    func testGroundingIsByWholeWord() {
        let interpretation = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "land")
        ])
        XCTAssertEqual(rejection(interpretation), .ungroundedSpan)
    }

    func testAnInventedPersonIsRejected() {
        let interpretation = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "email the landlord", personNamed: "Dmitri")
        ])
        XCTAssertEqual(rejection(interpretation), .inventedPerson)
    }

    func testAnInventedTimeSpanIsRejected() {
        let interpretation = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "email the landlord", temporalText: "on Friday", temporalRole: .deadline)
        ])
        XCTAssertEqual(rejection(interpretation), .ungroundedSpan)
    }

    // MARK: Titles

    /// A title is the one field allowed to be the model's own wording. It is
    /// not allowed to be its own facts: a name or a number in a title that the
    /// person never said is an invention the person will read as their own.
    func testATitleMayParaphraseButMayNotInventAName() {
        let paraphrase = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "email the landlord", suggestedTitle: "Message the building manager")
        ])
        XCTAssertTrue(accepted(paraphrase))

        let inventedName = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "email the landlord", suggestedTitle: "Email Mr Okafor")
        ])
        XCTAssertEqual(rejection(inventedName), .inventedTitleDetail)

        let inventedNumber = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "email the landlord", suggestedTitle: "Email the landlord at 3pm")
        ])
        XCTAssertEqual(rejection(inventedNumber), .inventedTitleDetail)
    }

    // MARK: Structure

    func testTwoSegmentsCoveringTheSameWordsAreRejected() {
        let interpretation = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "email the landlord"),
            InterpretedSegment(quote: "Email the landlord"),
        ])
        XCTAssertEqual(rejection(interpretation), .duplicateSegment)
    }

    /// A correction has to name the span that replaced it, and that span has to
    /// be another segment. Without this, `.corrected` is a way to delete a
    /// thought by naming nothing — which is the failure mode the disposition
    /// exists to prevent.
    func testACorrectionMustPointAtAnotherSegment() {
        let dangling = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "email the landlord", disposition: .corrected, supersededBy: "drop off the keys")
        ])
        XCTAssertEqual(rejection(dangling), .danglingCorrection)

        let paired = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "email the landlord", disposition: .corrected, supersededBy: "she'd drop off the keys"),
            InterpretedSegment(quote: "she'd drop off the keys", disposition: .reported, obligation: .otherOwes),
        ])
        XCTAssertTrue(accepted(paired))
    }

    func testACorrectionSpanOnAnUncorrectedSegmentIsRejected() {
        let interpretation = CaptureInterpretation(segments: [
            InterpretedSegment(quote: "email the landlord", supersededBy: "she'd drop off the keys"),
            InterpretedSegment(quote: "she'd drop off the keys"),
        ])
        XCTAssertEqual(rejection(interpretation), .impossibleCombination)
    }

    /// The reported-speech failure in the shape the policy can actually catch:
    /// somebody else's words arriving as something the speaker owes.
    func testQuotedWordsMayNotArriveAsTheSpeakersObligation() {
        let interpretation = CaptureInterpretation(segments: [
            InterpretedSegment(
                quote: "she'd drop off the keys",
                disposition: .reported,
                obligation: .speakerOwes,
                attributedTo: "priya"
            )
        ])
        XCTAssertEqual(rejection(interpretation), .impossibleCombination)
    }

    func testAnUnfinishedThoughtMayNotAskForAReminder() {
        let interpretation = CaptureInterpretation(segments: [
            InterpretedSegment(
                quote: "email the landlord",
                disposition: .abandoned,
                temporalText: "tomorrow",
                temporalRole: .reminderRequest
            )
        ])
        XCTAssertEqual(rejection(interpretation), .impossibleCombination)
    }

    func testAnEmptyReadingIsRejected() {
        XCTAssertEqual(rejection(CaptureInterpretation()), .empty)
    }

    func testMoreSegmentsThanTheCapAreRejected() {
        let text = (1...15).map { "item \($0)" }.joined(separator: " and ")
        let interpretation = CaptureInterpretation(
            segments: (1...15).map { InterpretedSegment(quote: "item \($0)") }
        )
        XCTAssertEqual(rejection(interpretation, text), .tooManySegments)
    }

    // MARK: Operations

    func testARescheduleWithoutANewMomentIsRejected() {
        let text = "move the roof inspection"
        let interpretation = CaptureInterpretation(operations: [
            InterpretedOperation(kind: .reschedule, quote: "move the roof inspection", targetText: "the roof inspection")
        ])
        XCTAssertEqual(rejection(interpretation, text), .untargetedOperation)
    }

    func testASpecificCancellationWithNoTargetIsRejected() {
        let text = "cancel the thing"
        let interpretation = CaptureInterpretation(operations: [
            InterpretedOperation(kind: .cancel, quote: "cancel the thing", scope: .specific)
        ])
        XCTAssertEqual(rejection(interpretation, text), .untargetedOperation)
    }

    /// "Cancel that" is a legitimate reading with nothing to act on. It has to
    /// survive the check so the deterministic layer can be the thing that
    /// refuses it, rather than the reading being thrown away and the person
    /// silently getting a task called "cancel that booking".
    func testAnUnstatedTargetIsAValidReading() {
        let text = "actually cancel that booking booking"
        let interpretation = CaptureInterpretation(operations: [
            InterpretedOperation(kind: .cancel, quote: "cancel that booking", scope: .unstated)
        ])
        XCTAssertTrue(accepted(interpretation, text))
    }

    // MARK: What may actually be executed

    /// The rule that lets a generative path near destructive requests at all:
    /// the model may describe a cancellation, and may not be the only reading
    /// that saw one.
    func testAnOperationOnlyTheModelSawIsNeverExecutable() {
        let reported = [InterpretedOperation(kind: .cancel, quote: "cancel the roof inspection", targetText: "the roof inspection")]
        let verdict = InterpretationPolicy.executableOperations(reported: reported, rulesRead: [])
        XCTAssertTrue(verdict.executable.isEmpty)
        XCTAssertEqual(verdict.refused.count, 1)
    }

    func testAnOperationBothReadingsFoundIsExecutable() {
        let reported = [InterpretedOperation(kind: .cancel, quote: "cancel the roof inspection", targetText: "the roof inspection")]
        let verdict = InterpretationPolicy.executableOperations(reported: reported, rulesRead: [.cancel])
        XCTAssertEqual(verdict.executable.count, 1)
        XCTAssertTrue(verdict.refused.isEmpty)
    }

    func testAgreementOnADifferentOperationIsNotAgreement() {
        let reported = [InterpretedOperation(kind: .cancel, quote: "cancel the roof inspection", targetText: "the roof inspection")]
        let verdict = InterpretationPolicy.executableOperations(reported: reported, rulesRead: [.complete])
        XCTAssertTrue(verdict.executable.isEmpty)
    }

    /// Breadth is refused before agreement is considered. Both readings
    /// agreeing that the person said "scrap every single reminder" is not a reason to
    /// scrap every single reminder.
    func testABroadRequestIsRefusedEvenWhenBothReadingsAgree() {
        let reported = [InterpretedOperation(
            kind: .cancel, quote: "scrap all my reminders", targetText: "all my reminders", scope: .broad
        )]
        let verdict = InterpretationPolicy.executableOperations(reported: reported, rulesRead: [.cancel])
        XCTAssertTrue(verdict.executable.isEmpty)
        XCTAssertEqual(verdict.refused.count, 1)
    }
}
