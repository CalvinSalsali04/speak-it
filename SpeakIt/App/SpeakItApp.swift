import AppIntents
import Foundation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

enum SpeakItQuickAction {
    static let speakThought = "com.calvinwak.SpeakIt.speakThought"
    static let typeThought = "com.calvinwak.SpeakIt.typeThought"
}

@MainActor
final class QuickActionRouter: ObservableObject {
    struct Request: Equatable, Identifiable {
        let id = UUID()
        let initialMode: CaptureInitialMode
        let autoStartsVoiceCapture: Bool
        let activatedAt: Date
        let activationInstant: CapturePerformanceClock.Instant
    }

    static let shared = QuickActionRouter()

    @Published private(set) var pendingRequest: Request?
    @Published private(set) var pendingTodayRequest: UUID?

    func handleBriefResponse(identifier: String, actionIdentifier: String) {
        guard HabitNotificationScheduler.isHabitIdentifier(identifier),
              actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        pendingTodayRequest = UUID()
        // A direct tap is an answer even after the inferred twelve-hour window.
        HabitDefaults.unansweredBriefCount = 0
        HabitDefaults.pendingBriefFireDates = HabitDefaults.pendingBriefFireDates.filter { $0 > .now }
    }

    func consumeTodayRequest(_ id: UUID) {
        guard pendingTodayRequest == id else { return }
        pendingTodayRequest = nil
    }

    func requestTypedCapture(
        activatedAt: Date = .now,
        activationInstant: CapturePerformanceClock.Instant = CapturePerformanceClock.now
    ) {
        guard pendingRequest?.initialMode != .text else { return }
        pendingRequest = Request(
            initialMode: .text,
            autoStartsVoiceCapture: false,
            activatedAt: activatedAt,
            activationInstant: activationInstant
        )
    }

    func requestVoiceCapture(
        activatedAt: Date = .now,
        activationInstant: CapturePerformanceClock.Instant = CapturePerformanceClock.now
    ) {
        guard pendingRequest?.initialMode != .voice else { return }
        pendingRequest = Request(
            initialMode: .voice,
            autoStartsVoiceCapture: true,
            activatedAt: activatedAt,
            activationInstant: activationInstant
        )
    }

    func consume(_ request: Request) {
        guard pendingRequest?.id == request.id else { return }
        pendingRequest = nil
    }
}

@MainActor
private enum AppShortcutMetadataPublisher {
    private static let publishedBuildKey = "SpeakIt.publishedAppShortcutBuild"

    static func updateIfNeeded() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        guard UserDefaults.standard.string(forKey: publishedBuildKey) != build else { return }
        SpeakItAppShortcuts.updateAppShortcutParameters()
        UserDefaults.standard.set(build, forKey: publishedBuildKey)
    }
}

@MainActor
final class SpeakItSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        _ = handle(shortcutItem)
    }

    /// The window exists by now and has not drawn yet, so a Light or Dark
    /// choice lands before the first frame instead of one frame after it.
    func sceneWillEnterForeground(_ scene: UIScene) {
        SpeakItAppearance.stored.applyToWindows()
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(handle(shortcutItem))
    }

    private func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        let activatedAt = Date.now
        let activationInstant = CapturePerformanceClock.now
        switch shortcutItem.type {
        case SpeakItQuickAction.speakThought:
            CaptureActivationStore.markInvoked(at: activatedAt)
            QuickActionRouter.shared.requestVoiceCapture(
                activatedAt: activatedAt,
                activationInstant: activationInstant
            )
            return true
        case SpeakItQuickAction.typeThought:
            CaptureActivationStore.markInvoked(at: activatedAt)
            QuickActionRouter.shared.requestTypedCapture(
                activatedAt: activatedAt,
                activationInstant: activationInstant
            )
            return true
        default:
            return false
        }
    }
}

final class SpeakItApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = SpeakItSceneDelegate.self
        }
        return configuration
    }
}

@main
struct SpeakItApp: App {
    @UIApplicationDelegateAdaptor(SpeakItApplicationDelegate.self) private var appDelegate
    @StateObject private var subscriptionStore = SubscriptionStore()

    private let modelContainer: ModelContainer
    private let repository: SwiftDataThoughtRepository
    private let storageInitializationError: String?

    @MainActor
    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-reset") {
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("SpeakIt.") {
                defaults.removeObject(forKey: key)
            }
            HabitDefaults.reset()
        }
        if arguments.contains("--ui-testing-skip-welcome") {
            UserDefaults.standard.set(true, forKey: "SpeakIt.hasCompletedWelcome")
        }
#endif
        let container = PersistenceController.shared
        modelContainer = container
        repository = SwiftDataThoughtRepository(modelContext: container.mainContext)
        storageInitializationError = PersistenceController.initializationError

        let notificationDelegate = NotificationPresentationDelegate.shared
        notificationDelegate.configure(repository: repository)
        UNUserNotificationCenter.current().delegate = notificationDelegate
        ReminderScheduler.registerNotificationCategories()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if storageInitializationError != nil {
                    StorageUnavailableView()
                } else {
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--demo-video") {
                        DemoVideoRoot()
                    } else {
                        RootView()
                            .environment(\.thoughtRepository, repository)
                            .environmentObject(subscriptionStore)
                    }
#else
                    RootView()
                        .environment(\.thoughtRepository, repository)
                        .environmentObject(subscriptionStore)
#endif
                }
            }
            .task {
                // Static shortcut metadata is already embedded in the app.
                // Re-publish only once per installed build instead of asking
                // AppIntents to do background registration on every launch.
                AppShortcutMetadataPublisher.updateIfNeeded()
                try? await Task.sleep(for: .milliseconds(450))
                SpeakItAnalytics.recordAppOpen(
                    plan: subscriptionStore.hasProAccess ? .pro : .free
                )
#if DEBUG
                guard ProcessInfo.processInfo.arguments.contains("--notification-diagnostics") else {
                    return
                }
                let center = UNUserNotificationCenter.current()
                if ProcessInfo.processInfo.arguments.contains("--notification-test") {
                    let content = UNMutableNotificationContent()
                    content.title = "Speak It test"
                    content.body = "Notifications are working."
                    content.sound = .default
                    let request = UNNotificationRequest(
                        identifier: "SpeakIt.notification-diagnostic",
                        content: content,
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 12, repeats: false)
                    )
                    do {
                        try await center.add(request)
                        print("SPEAKIT_NOTIFICATION_TEST=scheduled")
                    } catch {
                        print("SPEAKIT_NOTIFICATION_TEST_ERROR=\(error.localizedDescription)")
                    }
                }
                let settings = await center.notificationSettings()
                let pending = await center.pendingNotificationRequests()
                let delivered = await center.deliveredNotifications()
                print("SPEAKIT_NOTIFICATION_AUTH=\(settings.authorizationStatus.rawValue)")
                print("SPEAKIT_NOTIFICATION_ALERT=\(settings.alertSetting.rawValue)")
                print("SPEAKIT_NOTIFICATION_SOUND=\(settings.soundSetting.rawValue)")
                print("SPEAKIT_NOTIFICATION_TIME_SENSITIVE=\(settings.timeSensitiveSetting.rawValue)")
                print("SPEAKIT_NOTIFICATION_SCHEDULED_DELIVERY=\(settings.scheduledDeliverySetting.rawValue)")
                print("SPEAKIT_NOTIFICATION_PENDING=\(pending.count)")
                for request in pending {
                    print("SPEAKIT_NOTIFICATION_REQUEST=\(request.identifier)|\(request.trigger?.description ?? "no-trigger")")
                }
                print("SPEAKIT_NOTIFICATION_DELIVERED=\(delivered.count)")
                for notification in delivered {
                    print("SPEAKIT_NOTIFICATION_DELIVERY=\(notification.request.identifier)|\(notification.date)|\(notification.request.content.body)")
                }
#endif
            }
        }
        .modelContainer(modelContainer)
    }
}

private final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationPresentationDelegate()
    private let handlerLock = NSLock()
    private var reminderActionHandler: (@MainActor @Sendable ([UUID], ReminderAction) -> Void)?

    @MainActor
    func configure(repository: any ThoughtRepository) {
        handlerLock.lock()
        reminderActionHandler = { itemIDs, action in
            try? repository.performReminderAction(itemIDs: itemIDs, action: action)
        }
        handlerLock.unlock()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // A brief that arrives while the person is already looking at Speak
        // It has nothing to add; reminders still present as before.
        if HabitNotificationScheduler.isHabitIdentifier(notification.request.identifier) {
            completionHandler([])
            return
        }
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if HabitNotificationScheduler.isHabitIdentifier(response.notification.request.identifier) {
            Task { @MainActor in
                QuickActionRouter.shared.handleBriefResponse(
                    identifier: response.notification.request.identifier,
                    actionIdentifier: response.actionIdentifier
                )
                completionHandler()
            }
            return
        }
        let action: ReminderAction?
        switch response.actionIdentifier {
        case ReminderScheduler.completeActionIdentifier:
            action = .complete
        case ReminderScheduler.snoozeActionIdentifier:
            action = .snoozeTenMinutes
        case ReminderScheduler.tomorrowActionIdentifier:
            action = .tomorrow
        default:
            action = nil
        }

        guard let action,
              let values = response.notification.request.content.userInfo["itemIDs"] as? [String] else {
            completionHandler()
            return
        }
        let itemIDs = values.compactMap(UUID.init(uuidString:))
        handlerLock.lock()
        let handler = reminderActionHandler
        handlerLock.unlock()
        Task { @MainActor in
            handler?(itemIDs, action)
            completionHandler()
        }
    }
}

private struct StorageUnavailableView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 38, weight: .light))

                Text("Your memories are protected")
                    .font(.title2.weight(.semibold))

                Text("Speak It couldn’t open local storage, so it stopped instead of creating a temporary empty library. Close and reopen the app to try again.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)
            }
            .foregroundStyle(.white)
            .padding(28)
        }
        .preferredColorScheme(.dark)
    }
}
