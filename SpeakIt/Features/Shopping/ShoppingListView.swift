import SwiftUI

/// The single, in-memory definition of what belongs behind the Shopping entry.
/// It intentionally projects the records already loaded by SwiftData instead
/// of introducing a second model or a nested query for every row.
enum ShoppingListProjection {
    struct GroupSummary: Identifiable {
        let name: String
        let count: Int
        let timingItem: CapturedItem?
        var id: String { name }
    }

    /// One card per open list, timed by its earliest reminder or due date.
    /// Shared with the morning brief so its counts match Today.
    @MainActor
    static func groupSummaries(in items: [CapturedItem]) -> [GroupSummary] {
        var order: [String] = []
        var buckets: [String: [CapturedItem]] = [:]
        for item in openItems(in: items) {
            let name = ShoppingGroupStore.group(for: item.id) ?? ShoppingGroupStore.fallbackGroup
            if buckets[name] == nil { order.append(name) }
            buckets[name, default: []].append(item)
        }
        return order.map { name in
            let items = buckets[name] ?? []
            let timed = items
                .compactMap { item -> (item: CapturedItem, date: Date)? in
                    guard let date = item.reminderDate ?? item.dueDate else { return nil }
                    return (item, date)
                }
                .min { $0.date < $1.date }
            return GroupSummary(name: name, count: items.count, timingItem: timed?.item)
        }
    }

    static func contains(_ item: CapturedItem) -> Bool {
        item.itemType == .shopping && !item.isArchived && !item.isCompleted
    }

    static func openItems(in items: [CapturedItem]) -> [CapturedItem] {
        items.filter(contains)
    }

    @MainActor
    static func belongsOnTopLevelToday(
        _ item: CapturedItem,
        authorization: LocationAuthorization,
        relativeTo now: Date
    ) -> Bool {
        !contains(item) && item.belongsOnTodaySurface(
            authorization: authorization,
            relativeTo: now
        )
    }

    @MainActor
    static func belongsInTopLevelReview(
        _ item: CapturedItem,
        authorization: LocationAuthorization
    ) -> Bool {
        !contains(item) && item.requiresReview(authorization: authorization)
    }

}

/// A deliberately small projection of the existing captured items. Shopping
/// remains part of Speak It's capture-first model: there are no named lists,
/// folders, manual ordering rules, or parallel persistence system here. The
/// group headers are derived from `ShoppingGroupStore` at render time — an
/// in-memory dictionary lookup per row, never a parse.
struct ShoppingListView: View {
    /// One named list and its open items, in a stable order.
    private struct GroupedList: Identifiable {
        let name: String
        let items: [CapturedItem]
        var id: String { name }
    }

    /// Which list a sheet is adding to. A struct so `.sheet(item:)` gets the
    /// identity it needs.
    private struct AddTarget: Identifiable {
        let group: String
        var id: String { group }
    }

    @Environment(\.thoughtRepository) private var repository
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    let items: [CapturedItem]
    /// The list a Today card asked to land on. Consumed on arrival: that list
    /// opens, the others close, and the binding resets so a later visit
    /// through a different card can focus differently.
    @Binding var focusedGroup: String?
    let onCapture: () -> Void

    @State private var selectedItem: CapturedItem?
    @State private var errorMessage: String?
    @State private var collapsedGroups: Set<String> = []
    @State private var addTarget: AddTarget?
    @State private var newEntryText = ""
    @State private var showsProGate = false
    @State private var hasInitializedCollapse = false

    /// Grouping is a single pass over the already-loaded items plus a cached
    /// dictionary read per item. Named lists come first in the order the
    /// person created them (newest activity first); the fallback bucket stays
    /// last so real names never sort below "Other".
    private var groupedLists: [GroupedList] {
        var order: [String] = []
        var buckets: [String: [CapturedItem]] = [:]
        for item in items {
            let name = ShoppingGroupStore.group(for: item.id) ?? ShoppingGroupStore.fallbackGroup
            if buckets[name] == nil { order.append(name) }
            buckets[name, default: []].append(item)
        }
        let named = order.filter { $0 != ShoppingGroupStore.fallbackGroup }
        let ordered = named + (buckets[ShoppingGroupStore.fallbackGroup] == nil
            ? []
            : [ShoppingGroupStore.fallbackGroup])
        return ordered.map { GroupedList(name: $0, items: buckets[$0] ?? []) }
    }

    var body: some View {
        List {
            if items.isEmpty {
                emptyState
                    .listRowInsets(EdgeInsets(top: 36, leading: 22, bottom: 24, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(groupedLists) { group in
                    groupHeaderRow(group)
                    if !collapsedGroups.contains(group.name) {
                        ForEach(group.items) { item in
                            shoppingRow(item)
                        }
                        addEntryRow(group.name)
                    }
                }
            }
        }
        .listStyle(.plain)
        // The same clearance Today and Memory reserve. Without it the floating
        // dock sits on top of the last row of the list — and the last row is
        // the "Add items" field, so the control for adding to a list was the
        // one thing the dock covered.
        .contentMargins(.bottom, DockScroll.clearance, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .navigationTitle("List")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onCapture) {
                    Label("Add items", systemImage: "mic.fill")
                }
                .accessibilityHint("Opens capture so you can speak or type shopping items")
                .accessibilityIdentifier("shopping.add")
            }
        }
        .sheet(item: $selectedItem) { item in
            ItemEditorView(item: item)
        }
        .sheet(item: $addTarget) { target in
            addItemsSheet(for: target.group)
        }
        // The paywall itself, not a one-button alert that names Pro and then
        // offers no way to reach it. Every other free-limit gate in the app
        // presents this sheet.
        .sheet(isPresented: $showsProGate) {
            SpeakItProView(context: .freeLimit)
        }
        .repositoryErrorAlert($errorMessage)
        .speakScreenStyle()
        .onAppear {
            initializeCollapseState()
            applyFocus()
        }
        .onChange(of: focusedGroup) {
            applyFocus()
        }
    }

    /// Lists open closed — the header is the summary, tapping it reveals the
    /// items — except when there is only one list, where a closed header would
    /// just be a second tap between the person and their milk.
    private func initializeCollapseState() {
        guard !hasInitializedCollapse else { return }
        hasInitializedCollapse = true
        let groups = groupedLists
        guard groups.count > 1 else { return }
        collapsedGroups = Set(groups.map(\.name))
    }

    /// A Today card names the list the person tapped; land on it opened with
    /// the rest closed, then consume the request.
    private func applyFocus() {
        guard let focus = focusedGroup else { return }
        hasInitializedCollapse = true
        collapsedGroups = Set(groupedLists.map(\.name)).subtracting([focus])
        focusedGroup = nil
    }

    // MARK: - Group rows

    private func groupHeaderRow(_ group: GroupedList) -> some View {
        let isCollapsed = collapsedGroups.contains(group.name)
        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                if isCollapsed {
                    collapsedGroups.remove(group.name)
                } else {
                    collapsedGroups.insert(group.name)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.speakMuted)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))

                Text(group.name)
                    .font(SpeakItTypography.itemTitle.weight(.semibold))
                    .foregroundStyle(Color.speakInk)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(itemCountLabel(group.items.count))
                    .font(SpeakItTypography.metadata)
                    .foregroundStyle(Color.speakMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.speakIt)
        .accessibilityLabel(
            "\(group.name), \(itemCountLabel(group.items.count)), \(isCollapsed ? "collapsed" : "expanded")"
        )
        .accessibilityHint("Double tap to \(isCollapsed ? "show" : "hide") its items. Touch and hold to add items.")
        .accessibilityIdentifier("list.group.\(group.name)")
        .contextMenu {
            Button {
                beginAdding(to: group.name)
            } label: {
                Label("Add items", systemImage: "plus")
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 18))
        .listRowSeparatorTint(Color.speakDivider)
        .listRowBackground(Color.speakBackground)
    }

    private func addEntryRow(_ group: String) -> some View {
        Button {
            beginAdding(to: group)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.speakMuted)
                    .frame(width: 44, height: 44)

                Text("Add items")
                    .font(SpeakItTypography.metadata)
                    .foregroundStyle(Color.speakMuted)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.speakIt)
        .accessibilityLabel("Add items to \(group)")
        .accessibilityIdentifier("list.addEntry.\(group)")
        .listRowInsets(EdgeInsets(top: 0, leading: 26, bottom: 0, trailing: 18))
        .listRowSeparatorTint(Color.speakDivider)
        .listRowBackground(Color.speakBackground)
    }

    // MARK: - Adding

    private func beginAdding(to group: String) {
        guard subscriptionStore.canCreateCapture else {
            showsProGate = true
            return
        }
        newEntryText = ""
        addTarget = AddTarget(group: group)
    }

    private func addItemsSheet(for group: String) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Milk, eggs, cheese", text: $newEntryText, axis: .vertical)
                        .font(SpeakItTypography.itemTitle)
                        .submitLabel(.done)
                        .accessibilityIdentifier("list.addField")
                } footer: {
                    Text("Separate items with commas. Tap the microphone on the keyboard to speak them.")
                }
            }
            .navigationTitle("Add to \(group)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { addTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { commitNewEntries(to: group) }
                        .disabled(parsedEntries.isEmpty)
                        .accessibilityIdentifier("list.addConfirm")
                }
            }
        }
        .presentationDetents([.height(230), .medium])
    }

    private var parsedEntries: [String] {
        newEntryText
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func commitNewEntries(to group: String) {
        guard let repository else {
            errorMessage = "Local storage is unavailable."
            return
        }
        let entries = parsedEntries
        guard !entries.isEmpty else { return }

        do {
            try repository.addShoppingItems(entries, group: group)
            subscriptionStore.recordSuccessfulCapture()
            SpeakItAnalytics.track(.captureSaved(
                source: .text,
                itemCount: entries.count,
                needsReviewCount: 0,
                plan: subscriptionStore.hasProAccess ? .pro : .free
            ))
            addTarget = nil
            collapsedGroups.remove(group)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func itemCountLabel(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.speakMuted)

            Text("Your list is clear")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.speakInk)

            Text("Say “Buy milk, eggs, and toothpaste” to add three checkable items.")
                .font(.body)
                .foregroundStyle(Color.speakMuted)

            Button(action: onCapture) {
                Label("Add an item", systemImage: "mic.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.speakInverseInk)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color.speakInverseSurface, in: Capsule())
            }
            .buttonStyle(.speakIt)
            .accessibilityIdentifier("shopping.empty.add")
            .padding(.top, 4)
        }
    }

    private func shoppingRow(_ item: CapturedItem) -> some View {
        HStack(spacing: 12) {
            Button { complete(item) } label: {
                Image(systemName: "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Color.speakMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.speakIt)
            .accessibilityLabel("Complete \(item.displayTitle)")
            .accessibilityIdentifier("list.complete.\(item.displayTitle)")

            Button { selectedItem = item } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.displayTitle)
                        .font(SpeakItTypography.itemTitle)
                        .foregroundStyle(Color.speakInk)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // A timed entry ("remind me to get eggs in an hour") keeps
                    // its trigger visible here, the same reading Today's rows
                    // use — memoized, so this costs a cache lookup per row.
                    reminderDetail(for: item)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.speakIt)
            .accessibilityLabel("Edit \(item.displayTitle)")
            .accessibilityIdentifier("list.item.\(item.displayTitle)")
        }
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 18))
        .listRowSeparatorTint(Color.speakDivider)
        .listRowBackground(Color.speakBackground)
    }

    @ViewBuilder
    private func reminderDetail(for item: CapturedItem) -> some View {
        let presentation = ItemPresentation.make(
            for: item,
            authorization: LocationReminderMonitor.shared.authorization
        )
        if let timing = presentation.primaryTimingText {
            HStack(spacing: 3) {
                if presentation.reminderState.alertGlyph == .notification {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .accessibilityHidden(true)
                } else if presentation.reminderState.alertGlyph == .alarm {
                    Image(systemName: "alarm.fill")
                        .font(.caption2)
                        .accessibilityHidden(true)
                }
                Text(timing)
                    .lineLimit(1)
            }
            .font(SpeakItTypography.metadata)
            .foregroundStyle(Color.speakMuted)
        }
    }

    private func complete(_ item: CapturedItem) {
        guard let repository else {
            errorMessage = "Local storage is unavailable."
            return
        }

        do {
            try repository.setCompleted(item, completed: true)
            SpeakItAnalytics.track(.taskCompletionChanged(completed: true))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
