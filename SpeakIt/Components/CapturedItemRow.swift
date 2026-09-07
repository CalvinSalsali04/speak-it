import SwiftUI
import UIKit

struct CapturedItemRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Badge lettering follows Dynamic Type instead of staying 9 pt while the
    /// rest of the row grows.
    @ScaledMetric(relativeTo: .caption2) private var badgeFontSize: CGFloat = 9
    let item: CapturedItem
    let showsCompletionControl: Bool
    let showsPinnedIndicator: Bool
    let showsPriorityIndicator: Bool
    let showsCreatedDate: Bool
    let trailingDetail: String?
    let onTrailingDetailTap: (() -> Void)?
    let onToggleCompleted: () -> Void
    let onEdit: () -> Void

    init(
        item: CapturedItem,
        showsCompletionControl: Bool = true,
        showsPinnedIndicator: Bool = false,
        showsPriorityIndicator: Bool = false,
        showsCreatedDate: Bool = true,
        trailingDetail: String? = nil,
        onTrailingDetailTap: (() -> Void)? = nil,
        onToggleCompleted: @escaping () -> Void,
        onEdit: @escaping () -> Void
    ) {
        self.item = item
        self.showsCompletionControl = showsCompletionControl
        self.showsPinnedIndicator = showsPinnedIndicator
        self.showsPriorityIndicator = showsPriorityIndicator
        self.showsCreatedDate = showsCreatedDate
        self.trailingDetail = trailingDetail
        self.onTrailingDetailTap = onTrailingDetailTap
        self.onToggleCompleted = onToggleCompleted
        self.onEdit = onEdit
    }

    var body: some View {
        // A row consults the live device state once per render. Several child
        // labels need the same answer, and rebuilding ItemPresentation for each
        // of them multiplied Core Location and recurrence work on long lists.
        let presentation = ItemPresentation.make(
            for: item,
            authorization: LocationReminderMonitor.shared.authorization
        )

        HStack(alignment: .top, spacing: 13) {
            if showsCompletionControl {
                Button(action: onToggleCompleted) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(item.isCompleted ? Color.speakInk : Color.speakMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.speakIt)
                .accessibilityLabel(item.isCompleted ? "Mark \(item.displayTitle) incomplete" : "Complete \(item.displayTitle)")
                .accessibilityIdentifier("item.complete.\(item.displayTitle)")
            }

            Button(action: onEdit) {
                HStack(alignment: .top, spacing: 13) {
                    if !showsCompletionControl {
                        Image(systemName: item.itemType.systemImage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.speakInk)
                            .frame(width: 31, height: 31)
                            .background(Color.speakSurface, in: Circle())
                            .overlay {
                                Circle().stroke(Color.speakDivider, lineWidth: 1)
                            }
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayTitle)
                            .font(SpeakItTypography.itemTitle)
                            .foregroundStyle(Color.speakInk)
                            .strikethrough(item.isCompleted)
                            .multilineTextAlignment(.leading)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .lineSpacing(1)

                        Text(secondaryText)
                            .font(SpeakItTypography.metadata)
                            .foregroundStyle(Color.speakMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if onTrailingDetailTap == nil {
                        passiveTrailingContent(presentation)
                    } else {
                        memoryIndicators
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.speakIt)
            // Composed, not replaced.
            //
            // A Button is one accessibility element and an explicit label
            // overrides everything its subtree would have contributed — so
            // "Edit <title>" silently discarded the type line, the due time or
            // place, and the pin and priority glyphs, both of which carry
            // careful labels of their own that were never spoken. This is the
            // most-instantiated view in the product: every Today section, every
            // Memory row, and the saved-capture card. Leading with the person's
            // own words rather than the verb is also the better reading order.
            .accessibilityLabel(spokenLabel(for: presentation))
            .accessibilityHint(
                [alertAccessibilityHint(for: presentation), "Double tap to edit"]
                    .compactMap { $0 }
                    .joined(separator: ". ")
            )
            .accessibilityIdentifier("item.edit.\(item.displayTitle)")

            if let trailingDetail, let onTrailingDetailTap {
                Button(action: onTrailingDetailTap) {
                    HStack(spacing: 3) {
                        Text(trailingDetail)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(SpeakItTypography.metadata)
                    .foregroundStyle(Color.speakMuted)
                    .lineLimit(1)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.speakIt)
                .accessibilityLabel("Change \(item.displayTitle) stage, currently \(trailingDetail)")
            }
        }
        .padding(.vertical, 4)
    }

    private func passiveTrailingContent(_ presentation: ItemPresentation) -> some View {
        HStack(spacing: 6) {
            memoryIndicators

            if let trailingText = trailingText(for: presentation) {
                HStack(spacing: 3) {
                    // A place reminder gets a glyph because its trailing text is
                    // a place name, and "Home" alone reads like a category. The
                    // pin is what makes it legible as a trigger.
                    if isPlaceTriggered(presentation) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2)
                            .accessibilityHidden(true)
                    }
                    // A dated task and an armed reminder used to render as the
                    // identical row — same section, same date, same time, no
                    // way to tell which one will actually alert. This glyph is
                    // the persistent distinction; the receipt word that used to
                    // carry it auto-dismissed in 3.6 seconds. See
                    // Docs/FINAL_RELEASE_AUDIT.md B-1/C-1/H-1.
                    if let alertGlyph = alertGlyph(for: presentation) {
                        Image(systemName: alertGlyph)
                            .font(.caption2)
                            .accessibilityHidden(true)
                    }
                    Text(trailingText)
                        .lineLimit(1)
                }
            }
        }
        .font(SpeakItTypography.metadata)
        .foregroundStyle(Color.speakMuted)
        .multilineTextAlignment(.trailing)
        .padding(.top, 2)
    }

    private func isPlaceTriggered(_ presentation: ItemPresentation) -> Bool {
        presentation.reminderState.locationIntent != nil
    }

    /// SF Symbol name for the row's persistent alert glyph, or `nil` for a
    /// date with nothing armed on it. A bell for a notification, an alarm
    /// clock for AlarmKit — the two things Speak It can actually deliver.
    private func alertGlyph(for presentation: ItemPresentation) -> String? {
        switch presentation.reminderState.alertGlyph {
        case .some(.notification): "bell.fill"
        case .some(.alarm): "alarm.fill"
        default: nil
        }
    }

    /// VoiceOver has no way to see the glyph above, so it needs the same
    /// distinction in words.
    private func alertAccessibilityHint(for presentation: ItemPresentation) -> String? {
        switch presentation.reminderState.alertGlyph {
        case .some(.notification): "Will send a reminder"
        case .some(.alarm): "Will sound an alarm"
        default: nil
        }
    }

    @ViewBuilder
    private var memoryIndicators: some View {
        if showsPinnedIndicator {
            Image(systemName: "pin.fill")
                .font(.caption2.weight(.semibold))
                .accessibilityLabel("Pinned")
        }

        if showsPriorityIndicator, item.priority >= .high {
            Text(item.priority.displayName.uppercased())
                .font(.system(size: badgeFontSize, weight: .bold))
                .tracking(0.5)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.speakSurface, in: Capsule())
                .overlay { Capsule().stroke(Color.speakDivider, lineWidth: 1) }
                .accessibilityLabel("\(item.priority.displayName) priority")
        }
    }

    /// Everything the row shows, in the order it is read.
    ///
    /// Built from the same values the view has already computed, so the spoken
    /// row and the drawn row cannot drift apart.
    private func spokenLabel(for presentation: ItemPresentation) -> String {
        [
            item.displayTitle,
            secondaryText,
            trailingText(for: presentation),
            showsPinnedIndicator ? "Pinned" : nil,
            (showsPriorityIndicator && item.priority >= .high)
                ? "\(item.priority.displayName) priority"
                : nil
        ]
        .compactMap { $0 }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .joined(separator: ", ")
    }

    private func trailingText(for presentation: ItemPresentation) -> String? {
        if let trailingDetail { return trailingDetail }

        // The shared reading answers this now. It is what puts the hour back on
        // a future timed reminder — this used to drop the time for any date that
        // was not today, so "call mom tomorrow at 5pm" and a date-only item
        // rendered the same string — and what puts the place on a place
        // reminder instead of leaving the slot empty.
        if let timing = presentation.primaryTimingText { return timing }

        guard showsCreatedDate else { return nil }

        if Calendar.autoupdatingCurrent.isDateInToday(item.createdAt) {
            return item.createdAt.formatted(date: .omitted, time: .shortened)
        }

        return item.createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var secondaryText: String {
        if let recurrence = RecurrenceStore.rule(for: item.id) {
            return item.category == .general
                ? recurrence.displayName
                : "\(item.category.displayName) · \(recurrence.displayName)"
        }

        let category = item.category.displayName
        let type = item.itemType.displayName
        if item.category == .general { return type }
        if category.caseInsensitiveCompare(type) == .orderedSame { return type }
        return "\(category) · \(type)"
    }
}

/// Rows used to carry a horizontal swipe-to-complete gesture. A SwiftUI
/// `DragGesture` layered on scrolling content wins the touch outright: a
/// vertical swipe that started on a row simply did not scroll the list, and
/// since rows cover most of the screen, most swipes started on one. Raising
/// the activation distance only made the failure intermittent, which is worse.
///
/// The row keeps its visible completion control, so nothing is unreachable —
/// the swipe was a shortcut for a button that is already on screen. Restoring
/// it means a native implementation (a `List` with `.swipeActions`, or a UIKit
/// pan recognizer that refuses to begin on vertical movement), not another
/// gesture over the scroll view.
/// A quick action on a row that lives inside a scroll view rather than a `List`.
///
/// This was named `SwipeActionRow` and took an action title, an icon, a label,
/// an enabled flag and a closure — then rendered `content` alone and used none
/// of them. Today's five section call sites all routed through it, so the code
/// read as though Today's rows carried a "Done" action when nothing was wired
/// to anything.
///
/// A swipe genuinely is not available here. `.swipeActions` needs a `List`, and
/// the hand-rolled `DragGesture` that preceded this won the touch outright and
/// stopped vertical scrolling — the reason it was removed in the first place,
/// recorded in `Docs/KNOWN_ISSUES.md`. A context menu is the affordance that works
/// inside a scroll view without competing for the drag, and it is the one
/// Memory's rows already offer, so the two screens now teach the same gesture.
struct RowQuickAction<Content: View>: View {
    let actionTitle: String
    let systemImage: String
    let accessibilityLabel: String
    let isEnabled: Bool
    let action: () -> Void
    private let content: Content

    init(
        actionTitle: String,
        systemImage: String,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.actionTitle = actionTitle
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.isEnabled = isEnabled
        self.action = action
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if isEnabled {
            content
                .frame(maxWidth: .infinity)
                .contextMenu {
                    Button(action: action) {
                        Label(actionTitle, systemImage: systemImage)
                    }
                    .accessibilityLabel(accessibilityLabel)
                }
        } else {
            // A collapsed section still builds its rows. Installing a long
            // press on something the person cannot see would put a menu behind
            // the section header.
            content.frame(maxWidth: .infinity)
        }
    }
}

struct UndoToast: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .frame(width: 25, height: 25)
                .background(Color.speakInverseInk.opacity(0.14), in: Circle())

            Text(message)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Undo", action: undo)
                .font(.subheadline.bold())
                .buttonStyle(.speakIt)
        }
        .foregroundStyle(Color.speakInverseInk)
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background(
            Color.speakInverseSurface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }
}
