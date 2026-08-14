import ActivityKit
import Foundation

struct CaptureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Sendable {
            case listening
            case organizing
            case remembered
            case problem
        }

        var phase: Phase
        var title: String
        var detail: String
    }

    var source: String
}
