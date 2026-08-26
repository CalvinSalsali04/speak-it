import Foundation
import SwiftData

/// A frozen copy of the models exactly as version 1 stored them.
///
/// The live model classes keep evolving, so they cannot also describe the past.
/// Without a snapshot, every schema version would silently redefine every
/// earlier one and the migration plan would compare a version against itself.
/// These types are never instantiated by the app; they exist so version 2 has a
/// real predecessor to migrate from.
///
/// Nothing here may change. Editing a field in this file rewrites history and
/// would make the store on an existing device unreachable.
enum SpeakItSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [CaptureSession.self, CapturedItem.self, UserPreferences.self]
    }

    @Model
    final class CaptureSession {
        @Attribute(.unique) var id: UUID
        var originalTranscription: String
        var createdAt: Date
        var captureSourceRawValue: String
        var processingStatusRawValue: String
        var processingError: String?

        @Relationship(deleteRule: .cascade, inverse: \CapturedItem.captureSession)
        var items: [CapturedItem]

        init(
            id: UUID = UUID(),
            originalTranscription: String,
            createdAt: Date = .now,
            captureSourceRawValue: String = "inAppText",
            processingStatusRawValue: String = "complete",
            processingError: String? = nil,
            items: [CapturedItem] = []
        ) {
            self.id = id
            self.originalTranscription = originalTranscription
            self.createdAt = createdAt
            self.captureSourceRawValue = captureSourceRawValue
            self.processingStatusRawValue = processingStatusRawValue
            self.processingError = processingError
            self.items = items
        }
    }

    @Model
    final class CapturedItem {
        @Attribute(.unique) var id: UUID
        var originalTextSegment: String
        var displayTitle: String
        var itemTypeRawValue: String
        var categoryRawValue: String
        var createdAt: Date
        var dueDate: Date?
        var reminderDate: Date?
        var priorityRawValue: Int
        var personName: String?
        var completedAt: Date?
        var isArchived: Bool
        var archivedAt: Date?
        var processingConfidence: Double
        var needsClarification: Bool
        var isReviewed: Bool
        var lastModifiedAt: Date

        var captureSession: CaptureSession?

        init(
            id: UUID = UUID(),
            originalTextSegment: String,
            displayTitle: String,
            itemTypeRawValue: String = "unclear",
            categoryRawValue: String = "general",
            createdAt: Date = .now,
            dueDate: Date? = nil,
            reminderDate: Date? = nil,
            priorityRawValue: Int = 1,
            personName: String? = nil,
            completedAt: Date? = nil,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            processingConfidence: Double = 1,
            needsClarification: Bool = false,
            isReviewed: Bool = false,
            lastModifiedAt: Date = .now,
            captureSession: CaptureSession? = nil
        ) {
            self.id = id
            self.originalTextSegment = originalTextSegment
            self.displayTitle = displayTitle
            self.itemTypeRawValue = itemTypeRawValue
            self.categoryRawValue = categoryRawValue
            self.createdAt = createdAt
            self.dueDate = dueDate
            self.reminderDate = reminderDate
            self.priorityRawValue = priorityRawValue
            self.personName = personName
            self.completedAt = completedAt
            self.isArchived = isArchived
            self.archivedAt = archivedAt
            self.processingConfidence = processingConfidence
            self.needsClarification = needsClarification
            self.isReviewed = isReviewed
            self.lastModifiedAt = lastModifiedAt
            self.captureSession = captureSession
        }
    }

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
            preferredCaptureMethodRawValue: String = "inAppText"
        ) {
            self.id = id
            self.morningBriefingEnabled = morningBriefingEnabled
            self.morningBriefingTime = morningBriefingTime
            self.notificationPermissionState = notificationPermissionState
            self.speechPermissionState = speechPermissionState
            self.microphonePermissionState = microphonePermissionState
            self.shortcutSetupCompleted = shortcutSetupCompleted
            self.preferredCaptureMethodRawValue = preferredCaptureMethodRawValue
        }
    }
}

/// Version 2 adds the persisted temporal intent to `CapturedItem`.
///
/// Both new attributes are optional, so this is a lightweight migration: no row
/// is rewritten and no existing value is touched. What the new columns *mean*
/// for old rows is filled in afterwards by `backfillTemporalIntents()`, which
/// reparses each item's preserved original wording. That work deliberately does
/// not happen inside the migration — it is idempotent, resumable, and safe to
/// run again, which a migration stage is not.
/// Version 2 is frozen here for exactly the reason version 1 is.
///
/// It was originally declared in terms of the *live* model classes, which was
/// invisible while version 2 was the newest version — the live shape and the
/// version 2 shape were the same object. The moment version 3 added an
/// attribute to the live `CapturedItem`, version 2 silently redefined itself to
/// include that attribute too, both versions in the migration plan described the
/// same schema, and opening an existing store aborted inside CoreData.
///
/// A version can only describe the past if it has its own copy of the past.
/// Nothing in this enum may change.
enum SpeakItSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [CaptureSession.self, CapturedItem.self, UserPreferences.self]
    }

    @Model
    final class CaptureSession {
        @Attribute(.unique) var id: UUID
        var originalTranscription: String
        var createdAt: Date
        var captureSourceRawValue: String
        var processingStatusRawValue: String
        var processingError: String?

        @Relationship(deleteRule: .cascade, inverse: \CapturedItem.captureSession)
        var items: [CapturedItem]

        init(
            id: UUID = UUID(),
            originalTranscription: String,
            createdAt: Date = .now,
            captureSourceRawValue: String = "inAppText",
            processingStatusRawValue: String = "complete",
            processingError: String? = nil,
            items: [CapturedItem] = []
        ) {
            self.id = id
            self.originalTranscription = originalTranscription
            self.createdAt = createdAt
            self.captureSourceRawValue = captureSourceRawValue
            self.processingStatusRawValue = processingStatusRawValue
            self.processingError = processingError
            self.items = items
        }
    }

    @Model
    final class CapturedItem {
        @Attribute(.unique) var id: UUID
        var originalTextSegment: String
        var displayTitle: String
        var itemTypeRawValue: String
        var categoryRawValue: String
        var createdAt: Date
        var dueDate: Date?
        var reminderDate: Date?
        var priorityRawValue: Int
        var personName: String?
        var completedAt: Date?
        var isArchived: Bool
        var archivedAt: Date?
        var processingConfidence: Double
        var needsClarification: Bool
        var isReviewed: Bool
        var lastModifiedAt: Date

        /// The two attributes version 2 added.
        var temporalIntentData: Data?
        var temporalKindRawValue: String?

        var captureSession: CaptureSession?

        init(
            id: UUID = UUID(),
            originalTextSegment: String,
            displayTitle: String,
            itemTypeRawValue: String = "unclear",
            categoryRawValue: String = "general",
            createdAt: Date = .now,
            dueDate: Date? = nil,
            reminderDate: Date? = nil,
            priorityRawValue: Int = 1,
            personName: String? = nil,
            completedAt: Date? = nil,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            processingConfidence: Double = 1,
            needsClarification: Bool = false,
            isReviewed: Bool = false,
            lastModifiedAt: Date = .now,
            temporalIntentData: Data? = nil,
            temporalKindRawValue: String? = nil,
            captureSession: CaptureSession? = nil
        ) {
            self.id = id
            self.originalTextSegment = originalTextSegment
            self.displayTitle = displayTitle
            self.itemTypeRawValue = itemTypeRawValue
            self.categoryRawValue = categoryRawValue
            self.createdAt = createdAt
            self.dueDate = dueDate
            self.reminderDate = reminderDate
            self.priorityRawValue = priorityRawValue
            self.personName = personName
            self.completedAt = completedAt
            self.isArchived = isArchived
            self.archivedAt = archivedAt
            self.processingConfidence = processingConfidence
            self.needsClarification = needsClarification
            self.isReviewed = isReviewed
            self.lastModifiedAt = lastModifiedAt
            self.temporalIntentData = temporalIntentData
            self.temporalKindRawValue = temporalKindRawValue
            self.captureSession = captureSession
        }
    }

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
            preferredCaptureMethodRawValue: String = "inAppText"
        ) {
            self.id = id
            self.morningBriefingEnabled = morningBriefingEnabled
            self.morningBriefingTime = morningBriefingTime
            self.notificationPermissionState = notificationPermissionState
            self.speechPermissionState = speechPermissionState
            self.microphonePermissionState = microphonePermissionState
            self.shortcutSetupCompleted = shortcutSetupCompleted
            self.preferredCaptureMethodRawValue = preferredCaptureMethodRawValue
        }
    }
}

/// Version 3 adds the persisted location intent to `CapturedItem`.
///
/// Place reminders are a second kind of trigger, not a new kind of time, so they
/// arrive as their own attribute rather than as more fields on the encoded
/// `TemporalIntent`. Both new attributes are optional, which keeps this
/// lightweight for the same reason version 2 was: no existing row is read or
/// rewritten, and an install that never captures a place reminder stores
/// nothing new.
///
/// There is deliberately no backfill counterpart to
/// `backfillTemporalIntents()`. Version 2 could reconstruct temporal intent
/// because the resolved dates it was recovering already existed on every row.
/// Nothing equivalent is true here: a row captured before place reminders
/// existed was flagged as an unsupported trigger and has no region, no
/// coordinates, and no resolution to recover. Those rows are re-read from their
/// preserved wording on demand instead, which is honest about the fact that
/// this is new capability rather than recovered data.
///
/// Version 3 is frozen here for exactly the reason versions 1 and 2 are, and it
/// was frozen *before* the first version 4 attribute existed rather than after.
/// It originally nested nothing: its `models` array named the live global
/// classes, so version 3 read as "whatever the models happen to be right now".
/// That is invisible while version 3 is the newest version and becomes a
/// launch-time abort the moment a version 4 is added — the live `CapturedItem`
/// gains an attribute, version 3 silently gains it too, both versions in the
/// migration plan describe the same schema, and every existing store fails to
/// open. The live shape now lives in `SpeakItSchemaCurrent` instead.
///
/// The snapshot below is not a reconstruction. It is pinned to the recorded
/// Core Data version hashes of a real store written by the last build that
/// shipped an unfrozen version 3, which `SchemaFreezeTests` re-derives on every
/// run. Nothing in this enum may change.
enum SpeakItSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [CaptureSession.self, CapturedItem.self, UserPreferences.self]
    }

    @Model
    final class CaptureSession {
        @Attribute(.unique) var id: UUID
        var originalTranscription: String
        var createdAt: Date
        var captureSourceRawValue: String
        var processingStatusRawValue: String
        var processingError: String?

        @Relationship(deleteRule: .cascade, inverse: \CapturedItem.captureSession)
        var items: [CapturedItem]

        init(
            id: UUID = UUID(),
            originalTranscription: String,
            createdAt: Date = .now,
            captureSourceRawValue: String = "inAppText",
            processingStatusRawValue: String = "complete",
            processingError: String? = nil,
            items: [CapturedItem] = []
        ) {
            self.id = id
            self.originalTranscription = originalTranscription
            self.createdAt = createdAt
            self.captureSourceRawValue = captureSourceRawValue
            self.processingStatusRawValue = processingStatusRawValue
            self.processingError = processingError
            self.items = items
        }
    }

    @Model
    final class CapturedItem {
        @Attribute(.unique) var id: UUID
        var originalTextSegment: String
        var displayTitle: String
        var itemTypeRawValue: String
        var categoryRawValue: String
        var createdAt: Date
        var dueDate: Date?
        var reminderDate: Date?
        var priorityRawValue: Int
        var personName: String?
        var completedAt: Date?
        var isArchived: Bool
        var archivedAt: Date?
        var processingConfidence: Double
        var needsClarification: Bool
        var isReviewed: Bool
        var lastModifiedAt: Date

        /// The two attributes version 2 added.
        var temporalIntentData: Data?
        var temporalKindRawValue: String?

        /// The two attributes version 3 added.
        var locationIntentData: Data?
        var reminderTriggerKindRawValue: String?

        var captureSession: CaptureSession?

        init(
            id: UUID = UUID(),
            originalTextSegment: String,
            displayTitle: String,
            itemTypeRawValue: String = "unclear",
            categoryRawValue: String = "general",
            createdAt: Date = .now,
            dueDate: Date? = nil,
            reminderDate: Date? = nil,
            priorityRawValue: Int = 1,
            personName: String? = nil,
            completedAt: Date? = nil,
            isArchived: Bool = false,
            archivedAt: Date? = nil,
            processingConfidence: Double = 1,
            needsClarification: Bool = false,
            isReviewed: Bool = false,
            lastModifiedAt: Date = .now,
            temporalIntentData: Data? = nil,
            temporalKindRawValue: String? = nil,
            locationIntentData: Data? = nil,
            reminderTriggerKindRawValue: String? = nil,
            captureSession: CaptureSession? = nil
        ) {
            self.id = id
            self.originalTextSegment = originalTextSegment
            self.displayTitle = displayTitle
            self.itemTypeRawValue = itemTypeRawValue
            self.categoryRawValue = categoryRawValue
            self.createdAt = createdAt
            self.dueDate = dueDate
            self.reminderDate = reminderDate
            self.priorityRawValue = priorityRawValue
            self.personName = personName
            self.completedAt = completedAt
            self.isArchived = isArchived
            self.archivedAt = archivedAt
            self.processingConfidence = processingConfidence
            self.needsClarification = needsClarification
            self.isReviewed = isReviewed
            self.lastModifiedAt = lastModifiedAt
            self.temporalIntentData = temporalIntentData
            self.temporalKindRawValue = temporalKindRawValue
            self.locationIntentData = locationIntentData
            self.reminderTriggerKindRawValue = reminderTriggerKindRawValue
            self.captureSession = captureSession
        }
    }

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
            preferredCaptureMethodRawValue: String = "inAppText"
        ) {
            self.id = id
            self.morningBriefingEnabled = morningBriefingEnabled
            self.morningBriefingTime = morningBriefingTime
            self.notificationPermissionState = notificationPermissionState
            self.speechPermissionState = speechPermissionState
            self.microphonePermissionState = microphonePermissionState
            self.shortcutSetupCompleted = shortcutSetupCompleted
            self.preferredCaptureMethodRawValue = preferredCaptureMethodRawValue
        }
    }
}

/// The shape the running app opens, which is always the live model classes.
///
/// Every numbered version above is history: a fixed record of what some
/// person's phone already holds. This is the opposite — it is deliberately
/// whatever `CaptureSession`, `CapturedItem` and `UserPreferences` are right
/// now, because those are the classes the repository fetches, inserts and
/// saves. A container built from a frozen snapshot would hold entities the app
/// has no way to address.
///
/// The two roles used to be filled by the same declaration, and that is the bug
/// this file keeps re-learning: the newest numbered version pointed at the live
/// classes, so it moved every time a model gained a field, and the moment a
/// newer version was added it no longer described anything real. Separating
/// "what the app runs on" from "what the store might be arriving as" is what
/// stops the newest version from being redefined by the next edit.
///
/// It carries version 3.0.0 because that is the version existing stores are
/// stamped with and the live shape is still exactly frozen version 3 —
/// `SchemaFreezeTests` fails if that ever stops being true without a new
/// version being added. When version 4 arrives it takes over this role: add
/// `SpeakItSchemaV4` with the live classes and its own identifier, point this
/// alias at it, and leave version 3 frozen where it is.
typealias SpeakItSchemaCurrent = SpeakItSchemaV3Live

/// The live-model schema `SpeakItSchemaCurrent` names. Declared separately only
/// so the alias above can move to `SpeakItSchemaV4` in one line.
enum SpeakItSchemaV3Live: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    /// Live global classes, on purpose. See `SpeakItSchemaCurrent`.
    static var models: [any PersistentModel.Type] {
        [CaptureSession.self, CapturedItem.self, UserPreferences.self]
    }
}
