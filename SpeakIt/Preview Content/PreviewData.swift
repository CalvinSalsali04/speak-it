import Foundation
import SwiftData

@MainActor
struct PreviewEnvironment {
    let container: ModelContainer
    let repository: SwiftDataThoughtRepository
}

@MainActor
enum PreviewData {
    static func make(seed: Bool = true) -> PreviewEnvironment {
        let schema = Schema([
            CaptureSession.self,
            CapturedItem.self,
            UserPreferences.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let repository = SwiftDataThoughtRepository(modelContext: container.mainContext)
            let environment = PreviewEnvironment(container: container, repository: repository)
            if seed { try addSamples(to: repository) }
            return environment
        } catch {
            fatalError("Unable to create preview data: \(error.localizedDescription)")
        }
    }

    private static func addSamples(to repository: SwiftDataThoughtRepository) throws {
        let calendar = Calendar.current

        let assignment = try repository.createCapture(
            text: "Submit ethics assignment before midnight",
            source: .inAppText,
            createdAt: calendar.date(byAdding: .minute, value: -20, to: .now) ?? .now
        )
        try repository.update(
            assignment,
            with: ItemEdits(
                title: "Submit ethics assignment",
                itemType: .task,
                category: .school,
                dueDate: calendar.date(bySettingHour: 23, minute: 59, second: 0, of: .now),
                reminderDate: nil,
                priority: .urgent,
                personName: nil,
                needsClarification: false
            )
        )

        let dentist = try repository.createCapture(
            text: "Call dentist before noon",
            source: .inAppText,
            createdAt: calendar.date(byAdding: .hour, value: -2, to: .now) ?? .now
        )
        try repository.update(
            dentist,
            with: ItemEdits(
                title: "Call dentist",
                itemType: .task,
                category: .personal,
                dueDate: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now),
                reminderDate: nil,
                priority: .high,
                personName: nil,
                needsClarification: false
            )
        )

        let idea = try repository.createCapture(
            text: "Save my idea for a basketball statistics app",
            source: .inAppText,
            createdAt: calendar.date(byAdding: .day, value: -2, to: .now) ?? .now
        )
        try repository.update(
            idea,
            with: ItemEdits(
                title: "Basketball statistics app",
                itemType: .idea,
                category: .ideas,
                dueDate: nil,
                reminderDate: nil,
                priority: .normal,
                personName: nil,
                needsClarification: false
            )
        )

        _ = try repository.createCapture(
            text: "Ask Alex about Sunday",
            source: .inAppText,
            createdAt: calendar.date(byAdding: .minute, value: -5, to: .now) ?? .now
        )
    }
}
