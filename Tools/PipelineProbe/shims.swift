import Foundation

// Host-side stand-ins for symbols whose real homes import iOS-only frameworks.
// These are inert: signposts are pure instrumentation and contribute nothing to
// extraction output.
enum CapturePerformanceSignposts {
    static func begin(_ name: StaticString) -> Int { 0 }
    static func end(_ name: StaticString, _ state: Int?) {}
    static func event(_ name: StaticString) {}
    static func measureTemporalResolution<T>(_ operation: () throws -> T) rethrows -> T {
        try operation()
    }
}
