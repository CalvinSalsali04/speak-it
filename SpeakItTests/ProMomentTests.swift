import XCTest
@testable import SpeakIt

/// When Speak It may raise Pro on its own.
///
/// The rule these cover exists because the free-limit wall is the worst moment
/// to make the case — the person has already been stopped, and the thought they
/// were trying to save is what they are thinking about. `ProMoment` moves the
/// ask to two points where the allowance still has room, so "not now" remains a
/// real answer.
///
/// Everything here runs against the pure rule. `SubscriptionStore` reaches the
/// Keychain-backed capture ledger and a live StoreKit session, and a test that
/// built one would write to the developer's own allowance.
final class ProMomentTests: XCTestCase {

    // MARK: - The boundaries

    func testNoMomentBeforeTheFirstCaptureIsSpent() {
        XCTAssertNil(
            ProMoment.due(forCaptureCount: 0),
            "Somebody who has not captured anything has not seen the product work yet"
        )
    }

    func testFirstCaptureMomentIsDueAsSoonAsOneCaptureIsSpent() {
        XCTAssertEqual(ProMoment.due(forCaptureCount: 1), .firstCapture)
    }

    func testFirstCaptureMomentHoldsUntilTheAllowanceRunsLow() {
        let lastComfortableCount = FreePlanAllowance.lifetimeCaptureLimit
            - ProMoment.runningLowThreshold
            - 1
        for spent in 1...lastComfortableCount {
            XCTAssertEqual(
                ProMoment.due(forCaptureCount: spent),
                .firstCapture,
                "\(spent) spent should still read as the first-capture moment"
            )
        }
    }

    func testRunningLowMomentIsDueOnceThreeCapturesRemain() {
        let firstWarningCount = FreePlanAllowance.lifetimeCaptureLimit - ProMoment.runningLowThreshold
        for spent in firstWarningCount..<FreePlanAllowance.lifetimeCaptureLimit {
            XCTAssertEqual(
                ProMoment.due(forCaptureCount: spent),
                .runningLow,
                "\(spent) spent leaves \(FreePlanAllowance.remainingCaptures(after: spent)) and should warn"
            )
        }
    }

    /// The wall has its own screen, and it blocks rather than invites. An
    /// uninvited sheet on top of it would be the second paywall in one tap.
    func testExhaustedAllowanceRaisesNoUninvitedMoment() {
        XCTAssertNil(ProMoment.due(forCaptureCount: FreePlanAllowance.lifetimeCaptureLimit))
        XCTAssertNil(ProMoment.due(forCaptureCount: FreePlanAllowance.lifetimeCaptureLimit + 40))
    }

    /// A clock moved backwards, a restored backup, or a corrupt defaults value
    /// cannot mint a moment out of a negative count.
    func testNegativeCountIsTreatedAsNothingSpent() {
        XCTAssertNil(ProMoment.due(forCaptureCount: -1))
        XCTAssertNil(ProMoment.due(forCaptureCount: Int.min))
    }

    func testEveryCountFromEmptyToExhaustedResolves() {
        // Guards the arithmetic itself: no count in range may trap, and the
        // sequence has to be nil → firstCapture → runningLow → nil, in order.
        var seen: [ProMoment?] = []
        for spent in 0...FreePlanAllowance.lifetimeCaptureLimit {
            seen.append(ProMoment.due(forCaptureCount: spent))
        }
        XCTAssertEqual(seen.first ?? .some(.firstCapture), nil)
        XCTAssertEqual(seen.last ?? .some(.firstCapture), nil)
        XCTAssertEqual(
            seen.compactMap { $0 }.reduce(into: [ProMoment]()) { unique, moment in
                if unique.last != moment { unique.append(moment) }
            },
            [.firstCapture, .runningLow],
            "The two moments must arrive in order and never alternate"
        )
    }

    // MARK: - Delivered once, for the life of the install

    func testADeliveredMomentIsNeverOfferedAgain() {
        XCTAssertNil(
            ProMoment.due(forCaptureCount: 1, alreadyDelivered: [.firstCapture])
        )
        XCTAssertNil(
            ProMoment.due(
                forCaptureCount: FreePlanAllowance.lifetimeCaptureLimit - 1,
                alreadyDelivered: [.runningLow]
            )
        )
    }

    func testDeliveringOneMomentDoesNotSuppressTheOther() {
        XCTAssertEqual(
            ProMoment.due(
                forCaptureCount: FreePlanAllowance.lifetimeCaptureLimit - 1,
                alreadyDelivered: [.firstCapture]
            ),
            .runningLow,
            "Running low is a different thing to say and is still worth saying"
        )
    }

    func testBothDeliveredLeavesNothingToShow() {
        for spent in 0...FreePlanAllowance.lifetimeCaptureLimit {
            XCTAssertNil(
                ProMoment.due(forCaptureCount: spent, alreadyDelivered: Set(ProMoment.allCases)),
                "\(spent) spent should stay silent once both moments have been seen"
            )
        }
    }

    /// A ledger that jumps — a reinstall restoring the Keychain count, or a
    /// batch of shared captures imported in one activation — must not offer a
    /// first-capture greeting to somebody who is nearly out.
    func testACountThatSkipsPastBothBoundariesOffersTheLaterMoment() {
        XCTAssertEqual(
            ProMoment.due(forCaptureCount: FreePlanAllowance.lifetimeCaptureLimit - 1),
            .runningLow
        )
    }

    /// And the skipped moment is not owed afterwards. Each is a chance to speak
    /// at the right time, not a quota.
    func testTheSkippedMomentIsNotDeliveredLate() {
        let delivered: Set<ProMoment> = [.runningLow]
        XCTAssertNil(
            ProMoment.due(
                forCaptureCount: FreePlanAllowance.lifetimeCaptureLimit - 1,
                alreadyDelivered: delivered
            )
        )
    }

    // MARK: - Wiring

    func testEachMomentMapsToItsOwnPaywallContext() {
        XCTAssertEqual(ProMoment.firstCapture.presentationContext, .firstCapture)
        XCTAssertEqual(ProMoment.runningLow.presentationContext, .runningLow)
    }

    /// `.sheet(item:)` keys off this. Two moments sharing an id would let the
    /// first one presented suppress the second.
    func testMomentIdentifiersAreDistinctAndStable() {
        XCTAssertEqual(Set(ProMoment.allCases.map(\.id)).count, ProMoment.allCases.count)
        XCTAssertEqual(ProMoment.firstCapture.id, "firstCapture")
        XCTAssertEqual(ProMoment.runningLow.id, "runningLow")
    }

    /// The analytics vocabulary is closed and content-free by policy. These
    /// contexts carry no user text, and their raw values are what
    /// `PrivacyInfo.xcprivacy` is written against.
    func testPaywallContextsAreContentFreeAndDistinct() {
        let contexts: [AnalyticsPaywallContext] = [.account, .freeLimit, .firstCapture, .runningLow]
        XCTAssertEqual(Set(contexts.map(\.rawValue)).count, contexts.count)
        XCTAssertEqual(ProPresentationContext.firstCapture.analyticsContext, .firstCapture)
        XCTAssertEqual(ProPresentationContext.runningLow.analyticsContext, .runningLow)
        XCTAssertEqual(ProPresentationContext.freeLimit.analyticsContext, .freeLimit)
        XCTAssertEqual(ProPresentationContext.account.analyticsContext, .account)
    }

    /// The threshold has to leave room for the moment to mean anything. At or
    /// above the whole allowance it would fire on the first capture; at zero it
    /// would never fire before the wall.
    func testRunningLowThresholdSitsInsideTheAllowance() {
        XCTAssertGreaterThan(ProMoment.runningLowThreshold, 0)
        XCTAssertLessThan(ProMoment.runningLowThreshold, FreePlanAllowance.lifetimeCaptureLimit - 1)
    }
}
