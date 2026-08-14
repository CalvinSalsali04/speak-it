import Foundation
import SwiftData

enum SpeakItMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SpeakItSchemaV1.self, SpeakItSchemaV2.self, SpeakItSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        // Both stages are lightweight because both only add optional
        // attributes. No existing value is read, rewritten, or at risk.
        //
        // What version 2's new columns *mean* for pre-existing rows is filled in
        // after the store opens, by an idempotent backfill that can safely run
        // again if it is interrupted. Version 3 needs no such pass: a row that
        // predates place reminders has no region to recover, so its wording is
        // re-read on demand instead of being invented at migration time.
        [
            .lightweight(
                fromVersion: SpeakItSchemaV1.self,
                toVersion: SpeakItSchemaV2.self
            ),
            .lightweight(
                fromVersion: SpeakItSchemaV2.self,
                toVersion: SpeakItSchemaV3.self
            )
        ]
    }
}

@MainActor
enum PersistenceController {
    private struct StoreBootstrap {
        let container: ModelContainer
        let initializationError: String?
    }

    static let schema = Schema(versionedSchema: SpeakItSchemaV3.self)

    private static let bootstrap: StoreBootstrap = {
        do {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(
                    for: schema,
                    configurations: [configuration]
                )
                return StoreBootstrap(container: container, initializationError: nil)
            }
#endif
            let container = try ModelContainer(
                for: schema,
                migrationPlan: SpeakItMigrationPlan.self
            )
            return StoreBootstrap(container: container, initializationError: nil)
        } catch {
            let initializationError = error.localizedDescription
            let fallbackConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)

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

    static var shared: ModelContainer { bootstrap.container }
    static var initializationError: String? { bootstrap.initializationError }
}
