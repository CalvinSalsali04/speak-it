import Foundation
import SwiftData

enum SpeakItMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            SpeakItSchemaV1.self,
            SpeakItSchemaV2.self,
            SpeakItSchemaV3.self,
            SpeakItSchemaV4.self
        ]
    }

    static var stages: [MigrationStage] {
        // Every stage is lightweight because every one of them only adds
        // optional attributes. No existing value is read, rewritten, or at risk.
        //
        // What version 2's new columns *mean* for pre-existing rows is filled in
        // after the store opens, by an idempotent backfill that can safely run
        // again if it is interrupted. Versions 3 and 4 need no such pass, for
        // the same reason and in opposite directions: a row that predates place
        // reminders has no region to recover and is re-read from its wording on
        // demand, and a row that predates recorded semantics has no verdict to
        // recover at all. Reconstructing one from the fields the old build left
        // behind is exactly the guess version 4 exists to replace, so those rows
        // stay empty and keep the derivation they already had.
        [
            .lightweight(
                fromVersion: SpeakItSchemaV1.self,
                toVersion: SpeakItSchemaV2.self
            ),
            .lightweight(
                fromVersion: SpeakItSchemaV2.self,
                toVersion: SpeakItSchemaV3.self
            ),
            .lightweight(
                fromVersion: SpeakItSchemaV3.self,
                toVersion: SpeakItSchemaV4.self
            )
        ]
    }
}

@MainActor
enum PersistenceController {
    private static let applicationGroupIdentifier = "group.com.calvinwak.SpeakIt"

    private struct StoreBootstrap {
        let container: ModelContainer
        let initializationError: String?
    }

    /// The live model shape, never a frozen snapshot.
    ///
    /// `SpeakItMigrationPlan` above is the history the store might be arriving
    /// as; this is the shape the app addresses once it is open. They are the
    /// same schema today and must not be the same *declaration* — see
    /// `SpeakItSchemaCurrent`.
    static let schema = Schema(versionedSchema: SpeakItSchemaCurrent.self)

    private static let bootstrap: StoreBootstrap = {
        do {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                let configuration = ModelConfiguration(
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                let container = try ModelContainer(
                    for: schema,
                    configurations: [configuration]
                )
                return StoreBootstrap(container: container, initializationError: nil)
            }
#endif
            // On the first launch after a true uninstall, iOS has created the
            // app-group container but may not yet have created its nested
            // Application Support directory. SwiftData chooses that shared
            // container for this target. Preparing the parent explicitly keeps
            // the first store open on the normal path instead of relying on
            // Core Data's noisy recovery attempt.
            try preparePersistentStoreDirectory()

            // Speak It syncs encoded library snapshots through
            // `ICloudSyncService`. Keep SwiftData local-only so the presence
            // of the Release iCloud entitlement does not also opt this schema
            // into SwiftData's incompatible CloudKit integration.
            let configuration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan: SpeakItMigrationPlan.self,
                configurations: [configuration]
            )
            return StoreBootstrap(container: container, initializationError: nil)
        } catch {
            let initializationError = error.localizedDescription
            let fallbackConfiguration = ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )

            do {
                let fallbackContainer = try ModelContainer(
                    for: schema,
                    configurations: [fallbackConfiguration]
                )
                return StoreBootstrap(
                    container: fallbackContainer,
                    initializationError: initializationError
                )
            } catch {
                preconditionFailure("Unable to initialize safe fallback storage: \(error.localizedDescription)")
            }
        }
    }()

    private static func preparePersistentStoreDirectory() throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: applicationGroupIdentifier
        ) else {
            return
        }
        try FileManager.default.createDirectory(
            at: containerURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    static var shared: ModelContainer { bootstrap.container }
    static var initializationError: String? { bootstrap.initializationError }
}
