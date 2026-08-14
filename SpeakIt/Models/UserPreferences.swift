import Foundation
import SwiftData

@Model
final class UserPreferences {
    @Attribute(.unique) var id: UUID
    var morningBriefingEnabled: Bool
    var morningBriefingTime: Date
    var notificationPermissionState: String
    var speechPermissionState: String
    var microphonePermissionState: String
    var shortcutSetupCompleted: Bool
    var preferredCaptureMethodRawValue: String

    init(
        id: UUID = UUID(),
        morningBriefingEnabled: Bool = false,
        morningBriefingTime: Date = .now,
        notificationPermissionState: String = "notDetermined",
        speechPermissionState: String = "notDetermined",
        microphonePermissionState: String = "notDetermined",
        shortcutSetupCompleted: Bool = false,
        preferredCaptureMethod: CaptureSource = .inAppText
    ) {
        self.id = id
        self.morningBriefingEnabled = morningBriefingEnabled
        self.morningBriefingTime = morningBriefingTime
        self.notificationPermissionState = notificationPermissionState
        self.speechPermissionState = speechPermissionState
        self.microphonePermissionState = microphonePermissionState
        self.shortcutSetupCompleted = shortcutSetupCompleted
        self.preferredCaptureMethodRawValue = preferredCaptureMethod.rawValue
    }

    var preferredCaptureMethod: CaptureSource {
        get { CaptureSource(rawValue: preferredCaptureMethodRawValue) ?? .inAppText }
        set { preferredCaptureMethodRawValue = newValue.rawValue }
    }
}
