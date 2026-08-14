import Foundation
import SwiftData

@Model
final class CaptureSession: Identifiable {
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
        captureSource: CaptureSource = .inAppText,
        processingStatus: ProcessingStatus = .complete,
        processingError: String? = nil,
        items: [CapturedItem] = []
    ) {
        self.id = id
        self.originalTranscription = originalTranscription
        self.createdAt = createdAt
        self.captureSourceRawValue = captureSource.rawValue
        self.processingStatusRawValue = processingStatus.rawValue
        self.processingError = processingError
        self.items = items
    }

    var captureSource: CaptureSource {
        get { CaptureSource(rawValue: captureSourceRawValue) ?? .inAppText }
        set { captureSourceRawValue = newValue.rawValue }
    }

    var processingStatus: ProcessingStatus {
        get { ProcessingStatus(rawValue: processingStatusRawValue) ?? .pending }
        set { processingStatusRawValue = newValue.rawValue }
    }

    var extractedItemCount: Int { items.count }
}
