import Foundation

struct SampleDataLoadResult: Equatable, Sendable {
    let addedCaptureCount: Int
    let addedItemCount: Int
    let totalCaptureCount: Int
    let totalItemCount: Int

    var addedAnything: Bool { addedCaptureCount > 0 }
}

/// A compact, deterministic product tour for development builds. Each entry is
/// sent through the same rule engine as voice and typed captures, so the sample
/// library doubles as an honest end-to-end test instead of handcrafted UI data.
enum SampleDataLibrary {
    /// Reminder-free examples used by automated visual QA. They intentionally
    /// cover every Memory destination without producing system permission UI.
    static let memoryExamples = [
        "Idea: build a voice journal for workouts.",
        "Idea: let people compare two versions of a plan.",
        "Remember that Daniel prefers oat milk.",
        "Remember that Alex's birthday is October 12.",
        "The cabin Wi-Fi password is BirchLake27.",
        "We chose linen curtains for the guest room."
    ]

    /// Action-only fixtures used to verify long, expanded Today layouts without
    /// asking the simulator for notification permission.
    static let todayExamples = [
        "Tomorrow at 9 AM, call Sarah.",
        "Tomorrow at 10 AM, call Alex about getting the car keys.",
        "Friday at 4 PM, send the weekly report.",
        "Water the plants every three days after I complete it.",
        "Pack gym clothes.",
        "Buy milk after work."
    ]

    static let examples = [
        "Remember that Daniel prefers oat milk.",
        "Pick up the dry cleaning.",
        "Remind me in 10 seconds to get the laundry.",
        "Every Monday and Thursday at 8 AM, remind me to go to the gym.",
        "Water the plants every three days after I complete it.",
        "Tomorrow at 9, call Sarah. Buy milk after work. Remember Daniel prefers oat milk.",
        "Remind me tomorrow at 4—actually, make that 5—to call Alex.",
        "I already sent the invoice.",
        "Don't remind me to buy milk.",
        "Idea: build a voice journal for workouts."
    ]
}
