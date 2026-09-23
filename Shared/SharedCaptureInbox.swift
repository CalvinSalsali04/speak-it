import Foundation
import UIKit

/// Upper bound on capture text that arrives from outside the app.
///
/// The Share sheet and the Save Thought App Intent both accept text supplied by
/// another process, so neither can assume a sane length. A Shortcut can pass a
/// whole file and a share can carry an entire article. Extensions run under
/// tight memory limits, so the text is clamped at the boundary rather than
/// after it has been parsed, organized, and persisted.
///
/// This is not a correctness limit on what a person can say — 20,000 characters
/// is far longer than any spoken or typed thought.
enum CaptureTextLimit {
    static let maximumCharacters = 20_000

    static func clamp(_ text: String) -> String {
        guard text.count > maximumCharacters else { return text }
        return String(text.prefix(maximumCharacters))
    }
}

struct SharedCapturePayload: Codable, Equatable, Identifiable, Sendable {
    /// Minted once per share and never reused for other text: the import
    /// commits under this id as the capture's session id, so a replay after
    /// a kill returns the session it already made. Reusing an id for new
    /// text would make that import return the old session and drop the text.
    let id: UUID
    let text: String
    let sourceURL: URL?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        sourceURL: URL? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.sourceURL = sourceURL
        self.createdAt = createdAt
    }

    var captureText: String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sourceURL else { return normalized }
        let source = sourceURL.absoluteString
        guard !normalized.contains(source) else { return normalized }
        return normalized.isEmpty ? source : "\(normalized)\n\(source)"
    }
}

enum SharedCaptureInbox {
    static let appGroupIdentifier = "group.com.calvinwak.SpeakIt"
    private static let directoryName = "PendingSharedCaptures"

    @discardableResult
    static func enqueue(_ payload: SharedCapturePayload) throws -> URL {
        let directory = try inboxDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(payload)
        let destination = directory
            .appendingPathComponent(payload.id.uuidString)
            .appendingPathExtension("json")
        // Pending shares hold the user's own words. Protect them at rest like
        // the other shared-container writers do. `UnlessOpen` rather than
        // `complete` because the share extension can run on a locked device.
        try data.write(
            to: destination,
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
        return destination
    }

    static func pending() -> [(url: URL, payload: SharedCapturePayload)] {
        guard let directory = try? inboxDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(SharedCapturePayload.self, from: data) else {
                return nil
            }
            return (url, payload)
        }
        .sorted { $0.payload.createdAt < $1.payload.createdAt }
    }

    static func remove(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func inboxDirectory() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw SharedCaptureInboxError.appGroupUnavailable
        }
        return container.appendingPathComponent(directoryName, isDirectory: true)
    }
}

private enum SharedCaptureInboxError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        "Speak It’s shared inbox is unavailable. Open Speak It once, then try again."
    }
}

// MARK: - What Speak It says to VoiceOver

/// Every announcement Speak It asks VoiceOver to speak goes through here, so
/// the one rule about them lives in one place: **nothing Speak It asks
/// VoiceOver to say is spoken while a microphone is open.**
///
/// The production audio session is `.playAndRecord` in `.spokenAudio` mode
/// with no voice processing, so nothing cancels the speaker's output out of
/// the microphone's input. An announcement spoken into an open microphone can
/// be transcribed into the immutable original words of a `CaptureSession`,
/// and the endpointing audio check reads it as speech. (Audit
/// `v1/audits/accessibility.md`, A11Y-3.)
///
/// The rule has two halves, and either one alone leaks:
///
/// - **Nothing is posted while a microphone is open.** `announce` withholds
///   the message and says so. It is not queued for later: a message that
///   arrives while the microphone is open describes a moment that is over by
///   the time it closes, and the screen still shows it.
/// - **A microphone does not open while something already posted may still
///   be being spoken.** `SpeechTranscriber.start` awaits
///   `waitUntilMicrophoneMayOpen` immediately before `AVAudioEngine.start()`,
///   with no suspension between the two, and VoiceOver reports the end of each
///   announcement through `announcementDidFinishNotification`. That is also
///   how "Listening" is said: posted as the cue, and finished, before the
///   engine starts rather than after its first buffer.
///
/// With VoiceOver off nothing is posted and nothing is waited for, so the
/// microphone opens with no added latency.
///
/// The one bound on the wait is `allowance(for:)`, which matters only if
/// VoiceOver never reports an announcement finished. It is sized for a slow
/// speaking rate, and past it the announcement is assumed spoken. That
/// assumption is the one way this could still leak, and it is a device check
/// (D-3), not a guarantee.
///
/// It lives in `SharedCaptureInbox.swift` because this is the one source file
/// compiled into both the app and the Share extension, and the extension
/// needs the second half too: it stays on screen until its confirmation has
/// been spoken. The decisions are `nonisolated static` functions the tests
/// ask directly; the instance only holds what they read.
@MainActor
final class VoiceOverAnnouncer {
    enum Decision: Equatable {
        case speak
        /// VoiceOver is off. Nothing is posted and nothing is waited for.
        case voiceOverOff
        /// A microphone is open. Speaking now could put these words into the
        /// person's original words.
        case microphoneOpen
    }

    static let shared = VoiceOverAnnouncer(
        isVoiceOverRunning: { UIAccessibility.isVoiceOverRunning },
        speak: { VoiceOverAnnouncer.postQueuedAnnouncement($0) },
        allowance: { VoiceOverAnnouncer.allowance(for: $0) },
        observesVoiceOver: true
    )

    nonisolated static func decision(voiceOverRunning: Bool, openMicrophones: Int) -> Decision {
        guard voiceOverRunning else { return .voiceOverOff }
        guard openMicrophones == 0 else { return .microphoneOpen }
        return .speak
    }

    /// Whether a microphone may open now. Always true with VoiceOver off,
    /// which is what keeps this free for everybody who does not use it.
    nonisolated static func mayOpenMicrophone(
        voiceOverRunning: Bool,
        unfinishedAnnouncements: Int
    ) -> Bool {
        !voiceOverRunning || unfinishedAnnouncements == 0
    }

    /// How long one announcement may take before a missing finish report is
    /// assumed lost: a second and a half plus 0.12 s a character, which is
    /// roughly half VoiceOver's default rate, and never more than twelve
    /// seconds, so a lost report cannot keep the microphone shut for long.
    nonisolated static func allowance(for message: String) -> Duration {
        let seconds = min(12, 1.5 + 0.12 * Double(message.count))
        return .milliseconds(Int(seconds * 1_000))
    }

    /// Joins a title and its detail into one announcement, so "Can you
    /// clarify?" is not followed by a stray full stop and a detail written on
    /// two lines is not read as one run-on sentence.
    nonisolated static func sentence(_ parts: [String]) -> String {
        parts
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { part in
                guard let last = part.last, !".?!…".contains(last) else { return part }
                return part + "."
            }
            .joined(separator: " ")
    }

    private struct Pending {
        let text: String
        /// When a missing finish report stops being waited for. Queued
        /// announcements are spoken one after another, so each one's
        /// allowance starts where the one before it ends.
        let assumedSpokenBy: ContinuousClock.Instant
    }

    private let isVoiceOverRunning: @MainActor () -> Bool
    private let speak: @MainActor (String) -> Void
    private let allowance: @MainActor (String) -> Duration
    private var observers: [NSObjectProtocol] = []
    private var pending: [Pending] = []
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Microphones open right now, counted rather than flagged so two
    /// transcribers cannot close each other's.
    private(set) var openMicrophones = 0

    /// Posted and not yet reported finished, in the order they were posted.
    var unfinished: [String] { pending.map(\.text) }

    /// How many callers are waiting for silence. Test support.
    var waitingCount: Int { waiters.count }

    init(
        isVoiceOverRunning: @escaping @MainActor () -> Bool,
        speak: @escaping @MainActor (String) -> Void,
        allowance: @escaping @MainActor (String) -> Duration,
        observesVoiceOver: Bool = false
    ) {
        self.isVoiceOverRunning = isVoiceOverRunning
        self.speak = speak
        self.allowance = allowance
        guard observesVoiceOver else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIAccessibility.announcementDidFinishNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let spoken = notification.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String
            Task { @MainActor [weak self] in
                self?.announcementDidFinish(spoken)
            }
        })
        observers.append(center.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.wakeWaiters()
            }
        })
    }

    /// Asks VoiceOver to say `message`, unless the rule forbids it, and
    /// returns what was decided so a caller can tell withheld from spoken.
    @discardableResult
    func announce(_ message: String) -> Decision {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let decision = Self.decision(
            voiceOverRunning: isVoiceOverRunning(),
            openMicrophones: openMicrophones
        )
        guard decision == .speak, !text.isEmpty else { return decision }
        let now = ContinuousClock.now
        pending.removeAll { $0.assumedSpokenBy <= now }
        let start = max(now, pending.last?.assumedSpokenBy ?? now)
        pending.append(Pending(text: text, assumedSpokenBy: start + allowance(text)))
        speak(text)
        return .speak
    }

    /// Returns once nothing this announcer posted is still being spoken, or
    /// at once when VoiceOver is off.
    ///
    /// Every wake re-checks rather than trusting whoever woke it: resuming a
    /// continuation is not the same frame as this code running again, and an
    /// announcement posted in between must hold the microphone shut too.
    func untilSilent() async {
        while true {
            let now = ContinuousClock.now
            pending.removeAll { $0.assumedSpokenBy <= now }
            guard !Self.mayOpenMicrophone(
                voiceOverRunning: isVoiceOverRunning(),
                unfinishedAnnouncements: pending.count
            ), let latest = pending.map(\.assumedSpokenBy).max() else { return }

            let id = UUID()
            let timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(until: latest, clock: .continuous)
                guard !Task.isCancelled else { return }
                self?.wakeWaiters()
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters[id] = continuation
            }
            timeout.cancel()
        }
    }

    /// Speaks `cue`, if there is one, and returns once it and everything
    /// posted before it has been spoken. The caller opens the microphone with
    /// no suspension after this returns, calling `microphoneWillOpen` first;
    /// `SpeechTranscriber.start` is that caller.
    func waitUntilMicrophoneMayOpen(cue: String?) async {
        if let cue {
            announce(cue)
        }
        await untilSilent()
    }

    func microphoneWillOpen() {
        openMicrophones += 1
    }

    func microphoneDidClose() {
        openMicrophones = max(0, openMicrophones - 1)
    }

    /// VoiceOver finished speaking `spoken`, or was interrupted.
    ///
    /// Only an exact match counts. A report about some other string must not
    /// release a microphone that is waiting on this one, so an unmatched
    /// report is ignored and that wait falls back to its allowance.
    func announcementDidFinish(_ spoken: String?) {
        guard let spoken,
              let index = pending.firstIndex(where: {
                  $0.text == spoken.trimmingCharacters(in: .whitespacesAndNewlines)
              })
        else { return }
        pending.remove(at: index)
        wakeWaiters()
    }

    /// Wakes every waiter to re-check. Called when a report arrives, when an
    /// allowance runs out and when VoiceOver is turned on or off; the loop in
    /// `untilSilent` decides whether each may go.
    func wakeWaiters() {
        let woken = waiters
        waiters = [:]
        for continuation in woken.values {
            continuation.resume()
        }
    }

    private static func postQueuedAnnouncement(_ message: String) {
        // Queued behind whatever VoiceOver is already saying rather than
        // interrupting it, so a focus change that lands at the same moment
        // (the receipt replacing the orb, say) does not cut the result off.
        let queued = NSAttributedString(
            string: message,
            attributes: [.accessibilitySpeechQueueAnnouncement: true]
        )
        UIAccessibility.post(notification: .announcement, argument: queued)
    }
}
