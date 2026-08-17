import Foundation
import os

/// Content-free performance labels. These are deliberately coarse: they say
/// which path ran, never what somebody said or what title Speak It produced.
enum CapturePerformanceKind: String, Sendable {
    case action
    case memory
    case multiIntent = "multi_intent"
    case needsReview = "needs_review"
    case reminder
}

struct CaptureLatencySample: Equatable, Sendable {
    let source: AnalyticsCaptureSource
    let kind: CapturePerformanceKind
    let captureReadyMilliseconds: Int?
    let speechEndDetectionMilliseconds: Int?
    let transcriptionMilliseconds: Int?
    let semanticParsingMilliseconds: Int
    let temporalResolutionMilliseconds: Int
    let persistenceMilliseconds: Int
    let renderMilliseconds: Int
    let captureToOrganizedMilliseconds: Int
    let pipelineCompleted: Bool
    let requiresReview: Bool
}

/// The only clock used for elapsed capture measurements. `ContinuousClock`
/// advances monotonically, so changing the wall clock, time zone, or daylight
/// saving settings cannot create a negative or wildly inflated latency.
enum CapturePerformanceClock {
    typealias Instant = ContinuousClock.Instant

    private static let clock = ContinuousClock()

    static var now: Instant { clock.now }

    static func milliseconds(from start: Instant, to end: Instant) -> Int {
        milliseconds(start.duration(to: end))
    }

    static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        let value = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return max(0, Int(value.rounded()))
    }
}

/// Accumulates nested temporal parses without putting user-authored text into
/// logs. A multi-intent capture can invoke the deterministic parser more than
/// once, so the stage is a sum rather than a single timestamp.
final class CaptureStageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var temporalDuration = Duration.zero

    func recordTemporalResolution(_ duration: Duration) {
        lock.lock()
        temporalDuration += duration
        lock.unlock()
    }

    var recordedTemporalDuration: Duration {
        lock.lock()
        defer { lock.unlock() }
        return temporalDuration
    }
}

enum CapturePerformanceContext {
    @TaskLocal static var stageRecorder: CaptureStageRecorder?
}

/// Stable names shared by Instruments and XCTOSSignpostMetric. Keeping them in
/// one place prevents a spelling change from silently emptying a benchmark.
enum CapturePerformanceSignposts {
    static let subsystem = "com.calvinwak.SpeakIt"
    static let category = "CapturePipeline"

    private static let signposter = OSSignposter(
        subsystem: subsystem,
        category: category
    )
    private static let clock = ContinuousClock()

    static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: signposter.makeSignpostID())
    }

    static func end(_ name: StaticString, _ state: OSSignpostIntervalState?) {
        guard let state else { return }
        signposter.endInterval(name, state)
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name, id: signposter.makeSignpostID())
    }

    static func beginSpeechEndpointCandidate() -> OSSignpostIntervalState {
        begin("SpeechEndpointDetection")
    }

    static func endSpeechEndpointCandidate(_ state: OSSignpostIntervalState?) {
        end("SpeechEndpointDetection", state)
    }

    static func measureTemporalResolution<T>(_ operation: () throws -> T) rethrows -> T {
        let startedAt = clock.now
        defer {
            CapturePerformanceContext.stageRecorder?.recordTemporalResolution(
                startedAt.duration(to: clock.now)
            )
        }
        return try signposter.withIntervalSignpost(
            "TemporalResolution",
            id: signposter.makeSignpostID(),
            around: operation
        )
    }
}

/// One trace follows one capture from activation to the first rendered row
/// built from the final persisted model. It retains only timestamps and closed
/// enums; transcripts, titles, names, and dates are never retained or logged.
@MainActor
final class CapturePerformanceTrace {
    typealias Instant = CapturePerformanceClock.Instant

    let stageRecorder = CaptureStageRecorder()
    private(set) var reportedSample: CaptureLatencySample?

    private var source: AnalyticsCaptureSource
    private let activationAt: Instant
    private let recordsExternalActivation: Bool
    private var microphoneReadyAt: Instant?
    private var lastSpeechAt: Instant?
    private var endOfSpeechDetectedAt: Instant?
    private var transcriptFinalizedAt: Instant?
    private var semanticParsingStartedAt: Instant?
    private var semanticParsingMilliseconds = 0
    private var temporalResolutionMilliseconds = 0
    private var persistenceStartedAt: Instant?
    private var persistenceMilliseconds = 0
    private var persistedAt: Instant?
    private var notificationSchedulingFinishedAt: Instant?
    private var notificationWasAccepted = false
    private var didReport = false

    private var captureReadyState: OSSignpostIntervalState?
    private var transcriptFinalizationState: OSSignpostIntervalState?
    private var persistenceState: OSSignpostIntervalState?
    private var captureToOrganizedState: OSSignpostIntervalState?
    private var rowToNotificationState: OSSignpostIntervalState?

    init(
        source: AnalyticsCaptureSource,
        activatedAt: Instant = CapturePerformanceClock.now,
        recordsExternalActivation: Bool = false
    ) {
        self.source = source
        activationAt = activatedAt
        self.recordsExternalActivation = recordsExternalActivation
        if source == .voice {
            captureReadyState = CapturePerformanceSignposts.begin("CaptureReadyLatency")
        }
        CapturePerformanceSignposts.event("CaptureActivated")
    }

    func updateSource(_ source: AnalyticsCaptureSource) {
        self.source = source
    }

    func markMicrophoneReady(
        at instant: Instant = CapturePerformanceClock.now,
        wallDate: Date = .now
    ) {
        guard microphoneReadyAt == nil else { return }
        microphoneReadyAt = instant
        if recordsExternalActivation {
            CaptureActivationStore.markMicrophoneReady(
                at: wallDate,
                startupDuration: activationAt.duration(to: instant)
            )
        }
        CapturePerformanceSignposts.end("CaptureReadyLatency", captureReadyState)
        captureReadyState = nil
        CapturePerformanceSignposts.event("MicrophoneReady")
    }

    func markEndOfSpeechDetected(
        lastSpeechAt: Instant?,
        at instant: Instant = CapturePerformanceClock.now
    ) {
        guard endOfSpeechDetectedAt == nil else { return }
        self.lastSpeechAt = lastSpeechAt ?? instant
        endOfSpeechDetectedAt = instant
        transcriptFinalizationState = CapturePerformanceSignposts.begin(
            "TranscriptFinalization"
        )
        captureToOrganizedState = CapturePerformanceSignposts.begin(
            "EndDetectionToOrganizedLatency"
        )
        CapturePerformanceSignposts.event("EndOfSpeechDetected")
    }

    func markTranscriptFinalized(at instant: Instant = CapturePerformanceClock.now) {
        if endOfSpeechDetectedAt == nil {
            markEndOfSpeechDetected(lastSpeechAt: instant, at: instant)
        }
        guard transcriptFinalizedAt == nil else { return }
        transcriptFinalizedAt = instant
        CapturePerformanceSignposts.end(
            "TranscriptFinalization",
            transcriptFinalizationState
        )
        transcriptFinalizationState = nil
        CapturePerformanceSignposts.event("FinalTranscriptAvailable")
    }

    func beginTextSave(at instant: Instant = CapturePerformanceClock.now) {
        updateSource(.text)
        lastSpeechAt = instant
        endOfSpeechDetectedAt = instant
        transcriptFinalizedAt = instant
        captureToOrganizedState = CapturePerformanceSignposts.begin(
            "EndDetectionToOrganizedLatency"
        )
        CapturePerformanceSignposts.event("FinalTranscriptAvailable")
    }

    func beginSemanticParsing(at instant: Instant = CapturePerformanceClock.now) {
        guard semanticParsingStartedAt == nil else { return }
        semanticParsingStartedAt = instant
    }

    func finishSemanticParsing(at instant: Instant = CapturePerformanceClock.now) {
        guard let semanticParsingStartedAt else { return }
        let total = CapturePerformanceClock.milliseconds(
            from: semanticParsingStartedAt,
            to: instant
        )
        temporalResolutionMilliseconds = CapturePerformanceClock.milliseconds(
            stageRecorder.recordedTemporalDuration
        )
        semanticParsingMilliseconds = max(0, total - temporalResolutionMilliseconds)
        self.semanticParsingStartedAt = nil
        CapturePerformanceSignposts.event("SemanticParsingComplete")
        CapturePerformanceSignposts.event("TemporalResolutionComplete")
    }

    func beginPersistence(at instant: Instant = CapturePerformanceClock.now) {
        guard persistenceStartedAt == nil else { return }
        persistenceStartedAt = instant
        persistenceState = CapturePerformanceSignposts.begin("OrganizedPersistence")
    }

    func finishPersistence(at instant: Instant = CapturePerformanceClock.now) {
        guard let persistenceStartedAt else { return }
        persistenceMilliseconds = CapturePerformanceClock.milliseconds(
            from: persistenceStartedAt,
            to: instant
        )
        persistedAt = instant
        self.persistenceStartedAt = nil
        CapturePerformanceSignposts.end("OrganizedPersistence", persistenceState)
        persistenceState = nil
        CapturePerformanceSignposts.event("SwiftDataSaveComplete")
    }

    func markNotificationSchedulingFinished(
        accepted: Bool,
        at instant: Instant = CapturePerformanceClock.now
    ) {
        guard notificationSchedulingFinishedAt == nil else { return }
        notificationSchedulingFinishedAt = instant
        notificationWasAccepted = accepted
        CapturePerformanceSignposts.end(
            "RowToNotificationScheduling",
            rowToNotificationState
        )
        rowToNotificationState = nil
        CapturePerformanceSignposts.event("NotificationSchedulingFinished")
        if accepted {
            CapturePerformanceSignposts.event("NotificationAcceptedBySystem")
        }
    }

    func markOrganizedRowVisible(
        result: CaptureCreationResult,
        at instant: Instant = CapturePerformanceClock.now
    ) {
        guard !didReport, let persistedAt else { return }
        didReport = true
        CapturePerformanceSignposts.end(
            "EndDetectionToOrganizedLatency",
            captureToOrganizedState
        )
        captureToOrganizedState = nil
        CapturePerformanceSignposts.event("OrganizedRowVisible")

        // A failed/pending session may still be recovered and reorganized, and
        // an unresolved current-location snapshot is intentionally enriched in
        // the background. Neither is a stable final row, so neither is allowed
        // into the headline latency distribution.
        guard Self.isStableFinalResult(result) else {
            CapturePerformanceSignposts.event("OrganizedRowExcludedAsUnstable")
            return
        }

        if notificationSchedulingFinishedAt == nil, result.reminderCount > 0 {
            rowToNotificationState = CapturePerformanceSignposts.begin(
                "RowToNotificationScheduling"
            )
        } else if notificationWasAccepted {
            CapturePerformanceSignposts.event("NotificationAcceptedBeforeRowVisible")
        }

        let origin = lastSpeechAt ?? transcriptFinalizedAt ?? activationAt
        let sample = CaptureLatencySample(
            source: source,
            kind: Self.kind(for: result),
            captureReadyMilliseconds: microphoneReadyAt.map {
                CapturePerformanceClock.milliseconds(from: activationAt, to: $0)
            },
            speechEndDetectionMilliseconds: Self.optionalMilliseconds(
                from: lastSpeechAt,
                to: endOfSpeechDetectedAt
            ),
            transcriptionMilliseconds: Self.optionalMilliseconds(
                from: endOfSpeechDetectedAt,
                to: transcriptFinalizedAt
            ),
            semanticParsingMilliseconds: semanticParsingMilliseconds,
            temporalResolutionMilliseconds: temporalResolutionMilliseconds,
            persistenceMilliseconds: persistenceMilliseconds,
            renderMilliseconds: CapturePerformanceClock.milliseconds(
                from: persistedAt,
                to: instant
            ),
            captureToOrganizedMilliseconds: CapturePerformanceClock.milliseconds(
                from: origin,
                to: instant
            ),
            pipelineCompleted: true,
            requiresReview: result.needsReviewCount > 0
        )
        reportedSample = sample
        SpeakItAnalytics.track(.capturePerformance(sample))
    }

    private static func isStableFinalResult(_ result: CaptureCreationResult) -> Bool {
        guard result.session.processingStatus == .complete else { return false }
        return !result.items.contains { item in
            guard let location = item.locationIntent else { return false }
            return location.place == .currentLocation
                && location.resolvedPlace == nil
                && !location.isUserEdited
        }
    }

    private static func kind(for result: CaptureCreationResult) -> CapturePerformanceKind {
        if result.itemCount > 1 { return .multiIntent }
        if result.needsReviewCount > 0 { return .needsReview }
        let item = result.primaryItem
        if item.reminderDate != nil || item.locationIntent != nil { return .reminder }
        return item.itemType.isActionable ? .action : .memory
    }

    private static func optionalMilliseconds(from start: Instant?, to end: Instant?) -> Int? {
        guard let start, let end else { return nil }
        return CapturePerformanceClock.milliseconds(from: start, to: end)
    }
}
