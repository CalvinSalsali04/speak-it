import Foundation

/// Crash checkpoints for every capture surface. A voice draft may point at a
/// temporary, protected local recording so a recognizer or process failure
/// cannot erase words that never made it into a partial transcript. Successful
/// saves and intentional discards remove that recording immediately.
@MainActor
enum CaptureDraftStore {
    enum RecoveryStatus: String, Codable, Sendable {
        case capturing
        case processing
        case failed
    }

    struct Draft: Codable, Equatable, Sendable {
        let id: UUID
        let startedAt: Date
        var updatedAt: Date
        var transcript: String
        // Optional keeps drafts written by earlier builds decodable.
        var captureSourceRawValue: String?
        var recoveryAudioFilename: String?
        var recoveryStatusRawValue: String?
        var recoveryFailureMessage: String?
        var recoveryFailureKindRawValue: String?

        var captureSource: CaptureSource {
            CaptureSource(rawValue: captureSourceRawValue ?? "") ?? .shortcut
        }

        var recoveryStatus: RecoveryStatus {
            RecoveryStatus(rawValue: recoveryStatusRawValue ?? "") ?? .capturing
        }

        var recoveryFailureKind: CaptureRecoveryFailureKind {
            CaptureRecoveryFailureKind(rawValue: recoveryFailureKindRawValue ?? "") ?? .unknown
        }
    }

    /// A deliberately deleted recording, remembered only long enough that a
    /// checkpoint written before the deletion cannot reintroduce it.
    private struct Tombstone: Codable, Equatable, Sendable {
        let id: UUID
        let deletedAt: Date
    }

    static let recoveryDidChangeNotification = Notification.Name(
        "SpeakIt.captureRecoveryDidChange"
    )

    private static let storageKey = "SpeakIt.activeCaptureDraft"
    private static let deletedIDsKey = "SpeakIt.deletedCaptureRecoveryIDs"
    private static let deletedIDsLimit = 50
    /// Long enough that any checkpoint written before a deletion has certainly
    /// been replayed and rejected by now.
    nonisolated static let tombstoneRetention: TimeInterval = 60 * 60 * 24 * 30
    private static let recoveryFolderName = "CaptureRecovery"

    @discardableResult
    static func begin(
        source: CaptureSource = .shortcut,
        at date: Date = .now
    ) -> Draft {
        let id = UUID()
        let draft = Draft(
            id: id,
            startedAt: date,
            updatedAt: date,
            transcript: "",
            captureSourceRawValue: source.rawValue,
            recoveryAudioFilename: source == .inAppText
                ? nil
                : "\(id.uuidString).caf",
            recoveryStatusRawValue: RecoveryStatus.capturing.rawValue,
            recoveryFailureMessage: nil,
            recoveryFailureKindRawValue: nil
        )
        var drafts = allDrafts()
        drafts.append(draft)
        persist(drafts, notifiesRecoveryChange: true)
        return draft
    }

    static func update(id: UUID, transcript: String, at date: Date = .now) {
        var drafts = allDrafts()
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        let normalized = transcript
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        drafts[index].transcript = normalized
        drafts[index].updatedAt = date
        persist(drafts)
    }

    /// Removes abandoned empty checkpoints while preserving any draft that has
    /// recovery audio. An empty checkpoint must never resurrect text the person
    /// deliberately erased, but its protected audio can still be recoverable.
    static func pruneEmptyTextDrafts() {
        let drafts = allDrafts()
        let retained = drafts.filter { !$0.transcript.isEmpty || hasRecoveryAudio(for: $0) }
        guard retained.count != drafts.count else { return }
        persist(retained, notifiesRecoveryChange: true)
    }

    static func updateSource(id: UUID, source: CaptureSource) {
        var drafts = allDrafts()
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].captureSourceRawValue = source.rawValue
        drafts[index].updatedAt = .now
        persist(drafts)
    }

    static func markProcessing(id: UUID) {
        updateRecoveryState(id: id, status: .processing, failureMessage: nil, failureKind: nil)
    }

    static func markFailed(
        id: UUID,
        message: String,
        kind: CaptureRecoveryFailureKind = .unknown
    ) {
        updateRecoveryState(id: id, status: .failed, failureMessage: message, failureKind: kind)
    }

    static func markFailed(id: UUID, error: Error) {
        markFailed(
            id: id,
            message: error.localizedDescription,
            kind: CaptureRecoveryFailureKind(error: error)
        )
    }

    static func audioURL(for draft: Draft) -> URL? {
        guard let filename = draft.recoveryAudioFilename else { return nil }
        return recoveryDirectoryURL.appendingPathComponent(filename, isDirectory: false)
    }

    static func prepareAudioURL(for draft: Draft) throws -> URL? {
        guard let url = audioURL(for: draft) else { return nil }
        try FileManager.default.createDirectory(
            at: recoveryDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        var directoryURL = recoveryDirectoryURL
        try? directoryURL.setResourceValues(directoryValues)
        return url
    }

    static func protectAudio(at url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = url
        try? protectedURL.setResourceValues(values)
    }

    static func hasRecoveryAudio(for draft: Draft) -> Bool {
        guard let url = audioURL(for: draft),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let byteCount = attributes[.size] as? NSNumber else {
            return false
        }
        return byteCount.intValue > 512
    }

    static func recoverableAudioDrafts(
        now: Date = .now,
        minimumAge: TimeInterval = 3
    ) -> [Draft] {
        allDrafts()
            .filter {
                now.timeIntervalSince($0.updatedAt) >= minimumAge && hasRecoveryAudio(for: $0)
            }
            .sorted { $0.startedAt < $1.startedAt }
    }

    static func current() -> Draft? {
        allDrafts().last
    }

    static func draft(id: UUID) -> Draft? {
        allDrafts().first { $0.id == id }
    }

    static func recoverable(now: Date = .now, minimumAge: TimeInterval = 12) -> Draft? {
        allDrafts()
            .filter {
                !$0.transcript.isEmpty &&
                    !hasRecoveryAudio(for: $0) &&
                    now.timeIntervalSince($0.updatedAt) >= minimumAge
            }
            .min { $0.startedAt < $1.startedAt }
    }

    static func clear(id: UUID? = nil) {
        guard let id else {
            allDrafts().compactMap(audioURL(for:)).forEach(removeAudio)
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: deletedIDsKey)
            NotificationCenter.default.post(name: recoveryDidChangeNotification, object: nil)
            return
        }
        let drafts = allDrafts()
        if let draft = drafts.first(where: { $0.id == id }),
           let url = audioURL(for: draft) {
            removeAudio(at: url)
        }
        let remaining = drafts.filter { $0.id != id }
        persist(remaining, notifiesRecoveryChange: true)
    }

    /// The person's explicit "delete this recording" escape hatch. Unlike
    /// `clear(id:)`, which retires a draft the app itself finished with, this
    /// records a tombstone so a checkpoint written by another surface can never
    /// bring a deliberately deleted recording back on the next launch. It has
    /// to succeed even when the recognizer just failed and even when the audio
    /// file is already missing or refuses to unlink.
    @discardableResult
    static func deleteRecording(id: UUID) -> Bool {
        let drafts = allDrafts()
        // Delete by record when there is one, and by the deterministic name
        // regardless, so an orphaned file is not left behind.
        if let draft = drafts.first(where: { $0.id == id }), let url = audioURL(for: draft) {
            removeAudio(at: url)
        }
        removeAudio(at: derivedAudioURL(for: id))

        tombstone(id)
        let remaining = drafts.filter { $0.id != id }
        persist(remaining, notifiesRecoveryChange: true)
        return draft(id: id) == nil
    }

    static func isDeleted(_ id: UUID) -> Bool {
        deletedIDs().contains(id)
    }

    /// A tombstone only has to outlive the thing it suppresses. Once no
    /// checkpoint and no audio file remain for a deleted recording, nothing can
    /// reintroduce it and the entry is dead weight — but it is kept for a
    /// generous window first, because the write it exists to defeat is a stale
    /// one that has not landed yet.
    static func pruneResolvedTombstones(
        now: Date = .now,
        retention: TimeInterval = tombstoneRetention
    ) {
        let stones = tombstones()
        guard !stones.isEmpty else { return }
        let liveIDs = Set(allDrafts().map(\.id))
        let retained = stones.filter { stone in
            if liveIDs.contains(stone.id) { return true }
            if now.timeIntervalSince(stone.deletedAt) < retention { return true }
            return FileManager.default.fileExists(atPath: derivedAudioURL(for: stone.id).path)
        }
        guard retained.count != stones.count else { return }
        persistTombstones(retained)
    }

    static func tombstoneCount() -> Int {
        tombstones().count
    }

    /// Every checkpoint currently visible, tombstones already applied.
    static func snapshot() -> [Draft] {
        allDrafts()
    }

    /// Writes a snapshot back. Deleted recordings stay deleted: tombstones are
    /// applied on read, so replaying a checkpoint captured before a deletion
    /// cannot bring that recording back.
    static func restore(_ drafts: [Draft]) {
        persist(drafts, notifiesRecoveryChange: true)
    }

    private static func deletedIDs() -> Set<UUID> {
        Set(tombstones().map(\.id))
    }

    private static func tombstones() -> [Tombstone] {
        guard let data = UserDefaults.standard.data(forKey: deletedIDsKey) else { return [] }
        return (try? JSONDecoder().decode([Tombstone].self, from: data)) ?? []
    }

    private static func tombstone(_ id: UUID, at date: Date = .now) {
        var stones = tombstones()
        guard !stones.contains(where: { $0.id == id }) else { return }
        stones.append(Tombstone(id: id, deletedAt: date))
        // A backstop for the pathological case. Pruning drops resolved entries
        // first; this only ever trims the oldest, which are the safest to lose.
        if stones.count > deletedIDsLimit {
            stones.removeFirst(stones.count - deletedIDsLimit)
        }
        persistTombstones(stones)
    }

    private static func persistTombstones(_ stones: [Tombstone]) {
        guard !stones.isEmpty else {
            UserDefaults.standard.removeObject(forKey: deletedIDsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(stones) else { return }
        UserDefaults.standard.set(data, forKey: deletedIDsKey)
    }

    private static func derivedAudioURL(for id: UUID) -> URL {
        recoveryDirectoryURL.appendingPathComponent("\(id.uuidString).caf", isDirectory: false)
    }

    private static var recoveryDirectoryURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent(recoveryFolderName, isDirectory: true)
    }

    private static func updateRecoveryState(
        id: UUID,
        status: RecoveryStatus,
        failureMessage: String?,
        failureKind: CaptureRecoveryFailureKind?
    ) {
        var drafts = allDrafts()
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].recoveryStatusRawValue = status.rawValue
        drafts[index].recoveryFailureMessage = failureMessage
        drafts[index].recoveryFailureKindRawValue = failureKind?.rawValue
        drafts[index].updatedAt = .now
        persist(drafts, notifiesRecoveryChange: true)
    }

    private static func removeAudio(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func allDrafts() -> [Draft] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        let decoded: [Draft]
        if let drafts = try? JSONDecoder().decode([Draft].self, from: data) {
            decoded = drafts
        } else if let legacyDraft = try? JSONDecoder().decode(Draft.self, from: data) {
            // Migrate the original single-draft encoding in place.
            decoded = [legacyDraft]
        } else {
            return []
        }
        let deleted = deletedIDs()
        guard !deleted.isEmpty else { return decoded }
        return decoded.filter { !deleted.contains($0.id) }
    }

    private static func persist(
        _ drafts: [Draft],
        notifiesRecoveryChange: Bool = false
    ) {
        guard !drafts.isEmpty else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            if notifiesRecoveryChange {
                NotificationCenter.default.post(name: recoveryDidChangeNotification, object: nil)
            }
            return
        }
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        if notifiesRecoveryChange {
            NotificationCenter.default.post(name: recoveryDidChangeNotification, object: nil)
        }
    }
}

/// Why a recovery attempt stopped. The recognizer's own message is kept as
/// well, but the kind is what the interface reasons about: a recording the
/// recognizer found no words in is a different situation from one it could not
/// reach, and telling a person "Something went wrong" for either is what turned
/// a failed recovery into a dead end.
enum CaptureRecoveryFailureKind: String, Codable, Sendable {
    case noSpeechDetected
    case missingRecording
    case permissionRequired
    case recognizerUnavailable
    /// The current language has no on-device speech model. Recovering would
    /// send the recording to Apple's speech service, which every string that
    /// names a protected recording promises never happens.
    case onDeviceRecognitionUnavailable
    case timedOut
    case cancelled
    case storageUnavailable
    case unknown
}

/// Lets the speech layer name its own failures without exporting its error type.
protocol CaptureRecoveryFailureDescribing {
    var captureRecoveryFailureKind: CaptureRecoveryFailureKind { get }
}

extension CaptureRecoveryFailureKind {
    /// Speech Recognition reports "no speech detected" as an opaque assistant
    /// error, so it is matched by code and, as a fallback, by wording.
    private static let assistantErrorDomain = "kAFAssistantErrorDomain"
    private static let noSpeechAssistantCode = 1110

    init(error: Error) {
        if let described = error as? CaptureRecoveryFailureDescribing {
            self = described.captureRecoveryFailureKind
            return
        }
        if error is CancellationError {
            self = .cancelled
            return
        }
        let nsError = error as NSError
        if nsError.domain == Self.assistantErrorDomain,
           nsError.code == Self.noSpeechAssistantCode {
            self = .noSpeechDetected
            return
        }
        if nsError.localizedDescription.lowercased().contains("no speech") {
            self = .noSpeechDetected
            return
        }
        self = .unknown
    }

    /// A recording the recognizer read but found no words in is not "ready to
    /// recover" — retrying is allowed, but the interface must stop implying it
    /// is expected to work.
    var stopsPromisingRecovery: Bool {
        switch self {
        case .noSpeechDetected, .missingRecording, .onDeviceRecognitionUnavailable:
            true
        default:
            false
        }
    }
}

/// The words shown for a protected recording. Kept out of the views so the
/// failure copy is testable and identical everywhere it appears.
@MainActor
enum CaptureRecoveryPresentation {
    struct Row: Equatable, Sendable {
        var title: String
        var detail: String
        /// True once the recognizer has specifically told us this recording has
        /// nothing to recover.
        var stopsPromisingRecovery: Bool
    }

    static func row(for draft: CaptureDraftStore.Draft) -> Row {
        guard draft.recoveryStatus == .failed else {
            return Row(
                title: "Interrupted voice capture",
                detail: "Your words are safe in a recording on this iPhone.",
                stopsPromisingRecovery: false
            )
        }
        let kind = draft.recoveryFailureKind
        return Row(
            title: kind.stopsPromisingRecovery ? "Couldn’t recover" : "Needs attention",
            detail: detail(for: kind),
            stopsPromisingRecovery: kind.stopsPromisingRecovery
        )
    }

    /// The recognizer's own message is never shown. Strings like "The operation
    /// could not be completed" are the generic wording this fix exists to
    /// remove; the kind is what actually tells a person where they stand.
    static func detail(for kind: CaptureRecoveryFailureKind) -> String {
        switch kind {
        case .noSpeechDetected:
            "Speech Recognition didn’t find any words in this recording."
        case .missingRecording:
            "The recording is no longer on this iPhone."
        case .permissionRequired:
            "Speech Recognition access is needed to read this recording."
        case .recognizerUnavailable:
            "Speech Recognition is unavailable right now. The recording is still safe."
        case .onDeviceRecognitionUnavailable:
            "This language can’t be read on this iPhone, and Speak It won’t send the recording to Apple. It stays safe here."
        case .timedOut:
            "Recovery took too long to finish. The recording is still safe."
        case .cancelled:
            "Recovery stopped before it finished. The recording is still safe."
        case .storageUnavailable:
            "Local storage is unavailable, so nothing could be saved. The recording is still safe."
        case .unknown:
            "Recovery didn’t finish. The recording is still safe."
        }
    }

    static func alertTitle(for kind: CaptureRecoveryFailureKind) -> String {
        switch kind {
        case .noSpeechDetected:
            "Couldn’t recover this recording"
        case .missingRecording:
            "This recording is gone"
        case .permissionRequired:
            "Speech Recognition is off"
        case .recognizerUnavailable:
            "Speech Recognition is unavailable"
        case .onDeviceRecognitionUnavailable:
            "Recovery would leave this iPhone"
        case .timedOut:
            "Recovery took too long"
        case .cancelled:
            "Recovery stopped"
        case .storageUnavailable:
            "Storage is unavailable"
        case .unknown:
            "Recovery didn’t finish"
        }
    }

    /// The message says what the title does not, and always names a way
    /// forward. Restating the title here is what makes an alert feel like it
    /// told you nothing.
    static func alertMessage(for kind: CaptureRecoveryFailureKind) -> String {
        switch kind {
        case .noSpeechDetected:
            "Speech Recognition didn’t find any words in it. Try again, type the thought yourself, or delete the recording."
        case .missingRecording:
            "It is no longer on this iPhone. You can type the thought yourself, or delete this entry."
        case .permissionRequired:
            "Speak It needs Speech Recognition access to read this recording. Turn it on in Settings and try again, or type the thought yourself."
        case .recognizerUnavailable:
            "The recording is still safe. Try again in a moment, or type the thought yourself."
        case .onDeviceRecognitionUnavailable:
            "This language has no on-device speech model, so recovering the recording would send it to Apple’s speech service. It stays safe here instead. You can type the thought yourself, or delete the recording."
        case .storageUnavailable:
            "Nothing could be saved just now, and the recording is still safe. Try again in a moment."
        case .timedOut, .cancelled, .unknown:
            "The recording is still safe. Try again, or type the thought yourself."
        }
    }

    /// Any failed attempt retires "Ready to recover". A header that keeps
    /// promising recovery over a row that says the opposite is how the dead end
    /// read on TestFlight.
    static func sectionTitle(for drafts: [CaptureDraftStore.Draft]) -> String {
        drafts.contains { $0.recoveryStatus == .failed }
            ? "Needs attention"
            : "Ready to recover"
    }

    static let sectionFooter = "These recordings stay only on this iPhone. A successful recovery deletes the recording, and deleting one removes it for good."

    static func attentionDetail(for audioDrafts: [CaptureDraftStore.Draft]) -> String {
        guard !audioDrafts.isEmpty else {
            return "Your original words are safe. Tap to organize again or keep them untouched."
        }
        guard audioDrafts.contains(where: { $0.recoveryStatus == .failed }) else {
            return audioDrafts.count == 1
                ? "A protected recording is safe on this iPhone. Tap to recover it."
                : "Protected recordings are safe on this iPhone. Tap to recover them."
        }
        return audioDrafts.count == 1
            ? "A recording couldn’t be recovered. Tap to try again, type it, or delete it."
            : "Some recordings couldn’t be recovered. Tap to try again, type them, or delete them."
    }
}
