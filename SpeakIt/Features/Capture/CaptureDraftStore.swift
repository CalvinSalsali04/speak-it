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

        var captureSource: CaptureSource {
            CaptureSource(rawValue: captureSourceRawValue ?? "") ?? .shortcut
        }

        var recoveryStatus: RecoveryStatus {
            RecoveryStatus(rawValue: recoveryStatusRawValue ?? "") ?? .capturing
        }
    }

    static let recoveryDidChangeNotification = Notification.Name(
        "SpeakIt.captureRecoveryDidChange"
    )

    private static let storageKey = "SpeakIt.activeCaptureDraft"
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
            recoveryFailureMessage: nil
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
        updateRecoveryState(id: id, status: .processing, failureMessage: nil)
    }

    static func markFailed(id: UUID, message: String) {
        updateRecoveryState(id: id, status: .failed, failureMessage: message)
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
        failureMessage: String?
    ) {
        var drafts = allDrafts()
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].recoveryStatusRawValue = status.rawValue
        drafts[index].recoveryFailureMessage = failureMessage
        drafts[index].updatedAt = .now
        persist(drafts, notifiesRecoveryChange: true)
    }

    private static func removeAudio(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func allDrafts() -> [Draft] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        if let drafts = try? JSONDecoder().decode([Draft].self, from: data) {
            return drafts
        }
        // Migrate the original single-draft encoding in place.
        if let legacyDraft = try? JSONDecoder().decode(Draft.self, from: data) {
            return [legacyDraft]
        }
        return []
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
