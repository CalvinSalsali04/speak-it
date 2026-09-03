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

    /// The List fixtures, and the frame they are read in.
    ///
    /// `todayExamples` cannot serve the List tests. "After work" is a
    /// conventional anchor for 5 PM, so read against the device clock the same
    /// sentence lands in *Now* before 5 PM and rolls to tomorrow after it,
    /// which moves its card into the collapsed *Coming up* disclosure. A
    /// collapsed disclosure keeps its rows in the tree but takes their hit
    /// testing away, so the card stayed findable and stopped being tappable:
    /// the two tests that open the List from it could only pass in the first
    /// half of the day, on code that had not changed.
    ///
    /// So this fixture pins its own frame the way `Tools/PipelineProbe` fixes
    /// its own, rather than borrowing the wall clock. Read at 10:00 on the
    /// previous local day, every time it resolves to is already in the past at
    /// whatever hour the suite runs, so the list is overdue — and *Now*, where
    /// overdue lists sit, is the one Today section that is never collapsed.
    enum Shopping {
        /// One undated action and one shopping line, so the Today root still
        /// carries a real list card next to ordinary work rather than a
        /// screen with nothing else on it.
        static let captures = [
            "Pack gym clothes.",
            "Buy milk after work."
        ]

        /// Yesterday at 10:00 local. Fixed against the calendar day rather
        /// than the clock, which is what makes it unconditionally in the past.
        static func referenceDate(
            relativeTo now: Date = .now,
            calendar: Calendar = .autoupdatingCurrent
        ) -> Date {
            let startOfToday = calendar.startOfDay(for: now)
            guard let yesterday = calendar.date(
                byAdding: .day,
                value: -1,
                to: startOfToday
            ), let morning = calendar.date(
                bySettingHour: 10,
                minute: 0,
                second: 0,
                of: yesterday
            ) else {
                return startOfToday.addingTimeInterval(-14 * 60 * 60)
            }
            return morning
        }
    }

    /// The fixtures behind `Website/assets/img/01-Today.png` and
    /// `02-Memory.png` — the only place the marketing site shows the real app at
    /// size, so what is on these two screens is a product claim.
    ///
    /// Deliberately short. An earlier pair was shot from `examples` above, which
    /// is a rule-engine torture test: it contains a negation the app parks in
    /// *Needs review*, two rows about milk, an errand sitting in Memory, and
    /// three rows sharing a time. All of that is the right thing to develop
    /// against and the wrong thing to put on a landing page — the screenshots
    /// read as debug data and, in one case, showed the app failing to understand
    /// a sentence.
    ///
    /// Every line here is unambiguous, so nothing lands in *Needs review*; no two
    /// rows share a noun or a time; and nothing actionable is phrased so that it
    /// could land in Memory, because the whole page is built on that split.
    enum Marketing {
        /// Two scheduled today, one place-triggered, two later in the week — a
        /// *Now* section of three and a *Coming up* count of two.
        static let today = [
            "Take the bins out when I get home.",
            "Today at 5 PM, call Mum.",
            "Today at 6:30 PM, pick up the dry cleaning.",
            "Friday at 9 AM, send the quarterly report.",
            "Saturday at 11 AM, book the dentist."
        ]

        /// Spread across every Memory collection so none of the four reads zero,
        /// with more than one person so the count is plural.
        ///
        /// Ordered oldest first, and the order is doing work: *Recently added*
        /// shows the tail of this list, so the last two entries are the rows the
        /// screenshot ends on. They are people facts because a categorised row
        /// reads `People · Note`, which is exactly the row the site's *What
        /// happens* section draws two screens earlier — an uncategorised note
        /// reads a bare `Note` and quietly contradicts it.
        static let memory = [
            "The parking spot is level 3, row H.",
            "We chose linen curtains for the guest room.",
            "The cabin Wi-Fi password is BirchLake27.",
            "Idea: a weekly review that reads itself back to you.",
            "Idea: let people search by the words they actually said.",
            "Idea: build a voice journal for workouts.",
            "Remember that Sam's partner is called Nadia.",
            "Remember that Priya's birthday is October 12.",
            "Remember that Tom has the spare key.",
            "Remember that Daniel prefers oat milk."
        ]

        /// Pinned is a collection like any other, and a hero screenshot with an
        /// empty one argues against the feature. These two are pinned after the
        /// captures land.
        static let pinned = [
            "The cabin Wi-Fi password is BirchLake27.",
            "Remember that Tom has the spare key."
        ]
    }

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
