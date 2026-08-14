import AppIntents
import SwiftUI
import WidgetKit

private struct QuickCaptureEntry: TimelineEntry {
    let date: Date
}

private struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedTodaySnapshot
}

private struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(
            date: .now,
            snapshot: SharedTodaySnapshot(
                generatedAt: .now,
                openCount: 3,
                items: [
                    SharedTodayItem(id: UUID(), title: "Send the proposal", dueDate: .now, isUrgent: true),
                    SharedTodayItem(id: UUID(), title: "Pick up laundry", dueDate: nil, isUrgent: false)
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, snapshot: SharedTodayStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: .now, snapshot: SharedTodayStore.load())
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct CompleteTodayItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Speak It task"
    static let openAppWhenRun = false

    @Parameter(title: "Task") var itemID: String

    init() {}

    init(itemID: UUID) {
        self.itemID = itemID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID),
              SharedTodayStore.enqueueCompletion(itemID: id) != nil else {
            return .result()
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "SpeakItToday")
        return .result()
    }
}

struct SpeakItTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpeakItToday", provider: TodayProvider()) { entry in
            TodayWidgetEntryView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Speak It Today")
        .description("See what matters and finish tasks without opening the app.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

private struct TodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: SharedTodaySnapshot

    var body: some View {
        Group {
            switch family {
            case .accessoryInline, .accessoryCircular, .accessoryRectangular:
                // Lock Screen: glance and tap through, never complete in place.
                // A pocket mistap must not silently finish a task.
                TodayAccessoryView(
                    summary: LockScreenTodayVisibility.summary(
                        for: snapshot,
                        titleLimit: family == .accessoryRectangular ? 2 : 1
                    )
                )
                .widgetURL(URL(string: "speakit://today"))
            default:
                TodayWidgetView(snapshot: snapshot)
            }
        }
        .containerBackground(for: .widget) {
            // The Lock Screen renders accessory widgets over the wallpaper and
            // supplies its own vibrancy, so it must not receive a solid fill.
            switch family {
            case .accessoryInline, .accessoryCircular, .accessoryRectangular:
                Color.clear
            default:
                Color.black
            }
        }
    }
}

private struct QuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickCaptureEntry {
        QuickCaptureEntry(date: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (QuickCaptureEntry) -> Void
    ) {
        completion(QuickCaptureEntry(date: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<QuickCaptureEntry>) -> Void
    ) {
        completion(Timeline(entries: [QuickCaptureEntry(date: .now)], policy: .never))
    }
}

struct SpeakItQuickCaptureWidget: Widget {
    private let kind = "SpeakItQuickCapture"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickCaptureProvider()) { _ in
            QuickCaptureWidgetView()
                .widgetURL(URL(string: "speakit://capture/voice"))
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Speak It Capture")
        .description("Tap once to open Speak It already listening.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

@available(iOS 18.0, *)
struct SpeakItControlWidget: ControlWidget {
    private let kind = "com.calvinwak.SpeakIt.control.capture"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(
                action: OpenURLIntent(URL(string: "speakit://capture/voice")!)
            ) {
                Label("Speak It", systemImage: "waveform")
            }
        }
        .displayName("Speak It")
        .description("Start capturing a thought.")
    }
}

private struct QuickCaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                pulseMark
            case .accessoryRectangular:
                HStack(spacing: 10) {
                    pulseMark
                        .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("SPEAK IT")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.2)
                        Text("Tap to speak")
                            .font(.caption)
                            .opacity(0.68)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 0) {
                    Text("SPEAK IT")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer()

                    pulseMark
                        .frame(width: 68, height: 68)

                    Spacer()

                    Text("Tap to speak")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Speak It. Tap to start listening.")
    }

    private var pulseMark: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.20), lineWidth: 1)
            Circle()
                .stroke(.white.opacity(0.42), lineWidth: 1)
                .padding(7)
            Circle()
                .fill(.white)
                .padding(14)
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black)
        }
        .widgetAccentable()
    }
}

private struct TodayAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let summary: LockScreenTodaySummary

    var body: some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summary.accessibilityText)
            .accessibilityHint("Opens Speak It")
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            // Inline sits beside the clock and only renders one symbol plus text.
            Label(
                summary.inlineText,
                systemImage: summary.isEmpty ? "checkmark" : "checklist"
            )
        case .accessoryCircular:
            circular
        default:
            rectangular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()

            if summary.isEmpty {
                Image(systemName: "checkmark")
                    .font(.system(size: 19, weight: .semibold))
            } else {
                VStack(spacing: 0) {
                    Text(summary.countText)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("TODAY")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.4)
                        .opacity(0.7)
                }
                .padding(.horizontal, 4)
            }
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.caption2)
                Text("TODAY")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                Spacer(minLength: 0)
                if !summary.isEmpty {
                    Text(summary.countText)
                        .font(.caption2.weight(.bold))
                }
            }
            .widgetAccentable()

            if summary.titles.isEmpty {
                Text(summary.openLine)
                    .font(.headline)
                    .lineLimit(1)
                Text(summary.placeholderLine)
                    .font(.caption2)
                    .opacity(0.7)
                    .lineLimit(1)
            } else {
                // Two lines is what the rectangular slot fits under the header;
                // the header count already carries anything beyond that.
                ForEach(Array(summary.titles.enumerated()), id: \.offset) { _, title in
                    Text(title)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: SharedTodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY")
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
                Text("\(snapshot.openCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(.white, in: Capsule())
            }

            if snapshot.items.isEmpty {
                Spacer()
                Label("All clear", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Nothing waiting on you")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                Spacer()
            } else {
                Spacer(minLength: 8)
                ForEach(snapshot.items.prefix(family == .systemSmall ? 1 : 3)) { item in
                    Button(intent: CompleteTodayItemIntent(itemID: item.id)) {
                        HStack(spacing: 9) {
                            Image(systemName: "circle")
                                .font(.system(size: 15, weight: .medium))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                if let dueDate = item.dueDate {
                                    Text(dueText(dueDate))
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 6)
            }

            Link(destination: URL(string: "speakit://capture/voice")!) {
                Label("Capture", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func dueText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}
