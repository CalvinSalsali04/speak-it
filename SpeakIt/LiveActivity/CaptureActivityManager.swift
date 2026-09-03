import ActivityKit
import Foundation

enum CaptureActivityManager {
    @discardableResult
    static func beginListening(preparing: Bool = false) async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }

        let state = CaptureActivityAttributes.ContentState(
            phase: .listening,
            title: preparing ? "Starting…" : "Listening",
            detail: preparing ? "Getting the microphone ready." : "Say what you don’t want to forget."
        )
        let content = ActivityContent(
            state: state,
            staleDate: .now.addingTimeInterval(60),
            relevanceScore: 100
        )

        let activity: Activity<CaptureActivityAttributes>
        if let current = Activity<CaptureActivityAttributes>.activities.first {
            activity = current
            await activity.update(content)
        } else {
            do {
                activity = try Activity<CaptureActivityAttributes>.request(
                    attributes: CaptureActivityAttributes(source: "Speak It"),
                    content: content,
                    pushType: nil
                )
            } catch {
                return false
            }
        }

        // On iPhones without Dynamic Island, an alerted update presents the
        // Lock Screen Live Activity as a banner over the Home Screen. The
        // activity already exists before this update, which satisfies the
        // AudioRecordingIntent background-recording contract.
        // The preparing state exists to satisfy AudioRecordingIntent's Live
        // Activity contract before the audio engine starts. Do not alert yet:
        // the visible banner should say Listening only after the microphone is
        // truly running, never leave a stale "Preparing mic" promise onscreen.
        if !preparing {
            let alert = AlertConfiguration(
                title: "Listening",
                body: "Say what you don’t want to forget.",
                sound: .default
            )
            await activity.update(content, alertConfiguration: alert)
        }
        return true
    }

    static func showListeningReady(alertsUser: Bool = false) async {
        guard let activity = Activity<CaptureActivityAttributes>.activities.first else { return }

        let state = CaptureActivityAttributes.ContentState(
            phase: .listening,
            title: "Listening",
            detail: "Say what you don’t want to forget."
        )
        let content = ActivityContent(
            state: state,
            staleDate: .now.addingTimeInterval(60),
            relevanceScore: 100
        )
        if alertsUser {
            let alert = AlertConfiguration(
                title: "Listening",
                body: "Say what you don’t want to forget.",
                sound: .default
            )
            await activity.update(content, alertConfiguration: alert)
        } else {
            await activity.update(content)
        }
    }

    static func showOrganizing(_ thought: String) async {
        guard let activity = Activity<CaptureActivityAttributes>.activities.first else { return }

        let state = CaptureActivityAttributes.ContentState(
            phase: .organizing,
            title: "Adding…",
            detail: compactDetail(for: thought)
        )
        let content = ActivityContent(
            state: state,
            staleDate: .now.addingTimeInterval(20),
            relevanceScore: 100
        )
        await activity.update(content)
    }

    static func showRemembered(_ thought: String, context: String? = nil) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Built from whichever halves survive the Lock Screen privacy gate, so
        // a hidden thought leaves "Saved · Tomorrow 9:00 AM" rather than a
        // dangling separator or a bare "Saved · ".
        let parts = ["Saved", context, compactDetail(for: thought)]
            .compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let detail = parts.joined(separator: " · ")
        let state = CaptureActivityAttributes.ContentState(
            phase: .remembered,
            title: "Remembered",
            detail: detail
        )
        let content = ActivityContent(
            state: state,
            staleDate: .now.addingTimeInterval(12),
            relevanceScore: 100
        )

        let activity: Activity<CaptureActivityAttributes>
        if let current = Activity<CaptureActivityAttributes>.activities.first {
            activity = current
        } else {
            do {
                activity = try Activity.request(
                    attributes: CaptureActivityAttributes(source: "Speak It"),
                    content: content,
                    pushType: nil
                )
            } catch {
                return
            }
        }

        let alert = AlertConfiguration(
            title: "✓ Remembered",
            // `detail` already leads with "Saved"; this used to prefix it a
            // second time. The alert body is delivered like a notification, so
            // it carries the same Lock Screen privacy gate the detail does.
            body: LocalizedStringResource(stringLiteral: detail),
            sound: .default
        )
        await activity.update(content, alertConfiguration: alert)

        // Keep the confirmation visible without holding the capture pipeline
        // open for four seconds. A new Back Tap may begin while this receipt
        // remains onscreen, so the delayed cleanup verifies that the same
        // activity is still showing the remembered state before ending it.
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            guard let current = Activity<CaptureActivityAttributes>.activities.first(where: {
                $0.id == activity.id
            }), current.content.state.phase == .remembered else {
                return
            }

            await activity.end(
                content,
                dismissalPolicy: .after(.now.addingTimeInterval(6))
            )
        }
    }

    static func updateTranscript(_ transcript: String) async {
        guard let activity = Activity<CaptureActivityAttributes>.activities.first else { return }

        let detail = compactDetail(for: transcript)
        let state = CaptureActivityAttributes.ContentState(
            phase: .listening,
            title: "Listening",
            detail: detail
        )
        let content = ActivityContent(
            state: state,
            staleDate: .now.addingTimeInterval(60),
            relevanceScore: 100
        )
        await activity.update(content)
    }

    static func showProblem(title: String, detail: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = CaptureActivityAttributes.ContentState(
            phase: .problem,
            title: title,
            detail: detail
        )
        let content = ActivityContent(
            state: state,
            staleDate: .now.addingTimeInterval(12),
            relevanceScore: 100
        )

        let activity: Activity<CaptureActivityAttributes>
        if let current = Activity<CaptureActivityAttributes>.activities.first {
            activity = current
        } else {
            do {
                activity = try Activity.request(
                    attributes: CaptureActivityAttributes(source: "Speak It"),
                    content: content,
                    pushType: nil
                )
            } catch {
                return
            }
        }

        let alert = AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: title),
            body: LocalizedStringResource(stringLiteral: detail),
            sound: .default
        )
        await activity.update(content, alertConfiguration: alert)
        await activity.end(
            content,
            dismissalPolicy: .after(.now.addingTimeInterval(8))
        )
    }

    static func cancelListening() async {
        await endAll(dismissalPolicy: .immediate)
    }

    private static func endAll(
        dismissalPolicy: ActivityUIDismissalPolicy
    ) async {
        for activity in Activity<CaptureActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: dismissalPolicy)
        }
    }

    /// The thought text, shortened — or nothing at all when the person has not
    /// turned on Lock Screen task names.
    ///
    /// A Live Activity draws on the Lock Screen and its alert body is delivered
    /// like a notification, so this is exactly the content the widget's privacy
    /// gate already governs. Settings promises that "a locked iPhone never
    /// reveals what they are", and printing 72 characters of the thought here
    /// broke that promise on every capture — including background saves from
    /// Siri and Shortcuts, where the phone is usually locked and in a pocket.
    /// A receipt stranded by a crash or a jetsam could sit there for hours.
    private static func compactDetail(for thought: String) -> String {
        guard LockScreenTodayVisibility.showsTaskNames else { return "" }
        let normalized = thought
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count > 72 else { return normalized }
        let endIndex = normalized.index(normalized.startIndex, offsetBy: 71)
        return String(normalized[..<endIndex]).trimmingCharacters(in: .whitespaces) + "…"
    }
}
