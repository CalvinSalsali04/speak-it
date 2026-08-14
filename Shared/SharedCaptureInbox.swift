import Foundation

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
