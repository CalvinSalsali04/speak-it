import SwiftData
import SwiftUI
import UIKit

extension Notification.Name {
    static let speakItMemoryMetadataDidChange = Notification.Name(
        "SpeakIt.memoryMetadataDidChange"
    )
}

struct MemoryPinRecord: Codable, Equatable, Sendable {
    let itemID: UUID
    let isPinned: Bool
    let modifiedAt: Date
}

enum MemoryPinStore {
    static let key = "SpeakIt.pinnedMemoryIDs"
    private static let recordsKey = "SpeakIt.pinnedMemoryRecords.v1"

    static func decode(_ rawValue: String) -> Set<UUID> {
        Set(rawValue.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    static func encode(_ ids: Set<UUID>) -> String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    static func records() -> [UUID: MemoryPinRecord] {
        if let data = UserDefaults.standard.data(forKey: recordsKey),
           let values = try? JSONDecoder().decode([MemoryPinRecord].self, from: data) {
            return Dictionary(uniqueKeysWithValues: values.map { ($0.itemID, $0) })
        }
        return Dictionary(uniqueKeysWithValues: decode(
            UserDefaults.standard.string(forKey: key) ?? ""
        ).map {
            ($0, MemoryPinRecord(itemID: $0, isPinned: true, modifiedAt: .distantPast))
        })
    }

    static func setPinned(_ isPinned: Bool, for itemID: UUID, at date: Date = .now) {
        var values = records()
        values[itemID] = MemoryPinRecord(itemID: itemID, isPinned: isPinned, modifiedAt: date)
        persist(values, notifiesChange: true)
    }

    static func apply(_ incoming: [MemoryPinRecord]) {
        var values = records()
        for record in incoming {
            if let existing = values[record.itemID], existing.modifiedAt > record.modifiedAt {
                continue
            }
            values[record.itemID] = record
        }
        persist(values)
    }

    static func restore(_ records: [MemoryPinRecord]) {
        persist(Dictionary(uniqueKeysWithValues: records.map { ($0.itemID, $0) }))
    }

    static func removeMetadata(for itemIDs: some Sequence<UUID>) {
        var values = records()
        itemIDs.forEach { values.removeValue(forKey: $0) }
        persist(values)
    }

    private static func persist(
        _ records: [UUID: MemoryPinRecord],
        notifiesChange: Bool = false
    ) {
        let ordered = records.values.sorted { $0.itemID.uuidString < $1.itemID.uuidString }
        if let data = try? JSONEncoder().encode(ordered) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
        let pinned = Set(ordered.filter(\.isPinned).map(\.itemID))
        UserDefaults.standard.set(encode(pinned), forKey: key)
        if notifiesChange {
            NotificationCenter.default.post(name: .speakItMemoryMetadataDidChange, object: nil)
        }
    }
}

enum IdeaStage: String, CaseIterable, Codable, Identifiable, Sendable {
    case new
    case promising
    case exploring
    case parked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new: "New"
        case .promising: "Promising"
        case .exploring: "Exploring"
        case .parked: "Parked"
        }
    }

    var systemImage: String {
        switch self {
        case .new: "sparkles"
        case .promising: "star.fill"
        case .exploring: "hammer"
        case .parked: "pause"
        }
    }

    var detail: String {
        switch self {
        case .new: "Just captured and not reviewed yet"
        case .promising: "Worth returning to soon"
        case .exploring: "Actively developing or testing"
        case .parked: "Useful to keep, but not for now"
        }
    }

    var sortRank: Int {
        switch self {
        case .promising: 0
        case .exploring: 1
        case .new: 2
        case .parked: 3
        }
    }
}

struct IdeaStageRecord: Codable, Equatable, Sendable {
    let itemID: UUID
    let stage: IdeaStage
    let modifiedAt: Date
}

enum IdeaStageStore {
    static let key = "SpeakIt.ideaStages"
    private static let recordsKey = "SpeakIt.ideaStageRecords.v1"

    static func decode(_ rawValue: String) -> [UUID: IdeaStage] {
        rawValue.split(separator: ";").reduce(into: [:]) { result, entry in
            let pair = entry.split(separator: ":", maxSplits: 1)
            guard pair.count == 2,
                  let id = UUID(uuidString: String(pair[0])),
                  let stage = IdeaStage(rawValue: String(pair[1])) else { return }
            result[id] = stage
        }
    }

    static func encode(_ stages: [UUID: IdeaStage]) -> String {
        stages
            .filter { $0.value != .new }
            .map { "\($0.key.uuidString):\($0.value.rawValue)" }
            .sorted()
            .joined(separator: ";")
    }

    static func stage(for id: UUID, in rawValue: String) -> IdeaStage {
        decode(rawValue)[id] ?? .new
    }

    static func records() -> [UUID: IdeaStageRecord] {
        if let data = UserDefaults.standard.data(forKey: recordsKey),
           let values = try? JSONDecoder().decode([IdeaStageRecord].self, from: data) {
            return Dictionary(uniqueKeysWithValues: values.map { ($0.itemID, $0) })
        }
        return Dictionary(uniqueKeysWithValues: decode(
            UserDefaults.standard.string(forKey: key) ?? ""
        ).map {
            ($0.key, IdeaStageRecord(itemID: $0.key, stage: $0.value, modifiedAt: .distantPast))
        })
    }

    static func setStage(_ stage: IdeaStage, for itemID: UUID, at date: Date = .now) {
        var values = records()
        values[itemID] = IdeaStageRecord(itemID: itemID, stage: stage, modifiedAt: date)
        persist(values, notifiesChange: true)
    }

    static func apply(_ incoming: [IdeaStageRecord]) {
        var values = records()
        for record in incoming {
            if let existing = values[record.itemID], existing.modifiedAt > record.modifiedAt {
                continue
            }
            values[record.itemID] = record
        }
        persist(values)
    }

    static func restore(_ records: [IdeaStageRecord]) {
        persist(Dictionary(uniqueKeysWithValues: records.map { ($0.itemID, $0) }))
    }

    static func removeMetadata(for itemIDs: some Sequence<UUID>) {
        var values = records()
        itemIDs.forEach { values.removeValue(forKey: $0) }
        persist(values)
    }

    private static func persist(
        _ records: [UUID: IdeaStageRecord],
        notifiesChange: Bool = false
    ) {
        let ordered = records.values.sorted { $0.itemID.uuidString < $1.itemID.uuidString }
        if let data = try? JSONEncoder().encode(ordered) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
        let staged = Dictionary(uniqueKeysWithValues: ordered.compactMap { record in
            record.stage == .new ? nil : (record.itemID, record.stage)
        })
        UserDefaults.standard.set(encode(staged), forKey: key)
        if notifiesChange {
            NotificationCenter.default.post(name: .speakItMemoryMetadataDidChange, object: nil)
        }
    }
}

enum MemoryItemOrdering {
    static let homePreviewLimit = 3

    static func relevance(
        _ items: [CapturedItem],
        pinnedIDs: Set<UUID> = []
    ) -> [CapturedItem] {
        items.sorted { lhs, rhs in
            let lhsPinned = pinnedIDs.contains(lhs.id)
            let rhsPinned = pinnedIDs.contains(rhs.id)
            if lhsPinned != rhsPinned { return lhsPinned }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            if lhs.lastModifiedAt != rhs.lastModifiedAt {
                return lhs.lastModifiedAt > rhs.lastModifiedAt
            }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

enum MemoryRecencyGroup: String, CaseIterable, Identifiable {
    case today
    case recent
    case earlier

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .recent: "Last 7 days"
        case .earlier: "Earlier"
        }
    }

    static func group(
        for date: Date,
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> MemoryRecencyGroup {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWindow = calendar.date(byAdding: .day, value: -6, to: startOfToday)
            ?? startOfToday
        return date >= startOfWindow ? .recent : .earlier
    }
}

enum MemoryGroup: String, CaseIterable, Identifiable {
    case ideas
    case people
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: "Reference"
        case .ideas: "Ideas"
        case .people: "People"
        }
    }

    var systemImage: String {
        switch self {
        case .notes: "books.vertical"
        case .ideas: "lightbulb"
        case .people: "person.2"
        }
    }

    func contains(_ item: CapturedItem) -> Bool {
        switch self {
        case .ideas:
            item.itemType == .idea
        case .people:
            item.itemType != .idea && MemoryPersonNameResolver.name(for: item) != nil
        case .notes:
            item.itemType != .idea && MemoryPersonNameResolver.name(for: item) == nil
        }
    }
}

enum MemoryCollection: String, CaseIterable, Identifiable, Hashable {
    case pinned
    case ideas
    case people
    case reference
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pinned: "Pinned"
        case .ideas: "Ideas"
        case .people: "People"
        case .reference: "Reference"
        case .archive: "Archive"
        }
    }

    var systemImage: String {
        switch self {
        case .pinned: "pin.fill"
        case .ideas: "lightbulb"
        case .people: "person.2"
        case .reference: "books.vertical"
        case .archive: "archivebox"
        }
    }

    /// `@MainActor` because Memory membership depends on live location
    /// authorization: an item blocked on a place belongs in review, not here.
    @MainActor
    func contains(_ item: CapturedItem, pinnedIDs: Set<UUID>) -> Bool {
        let authorization = LocationReminderMonitor.shared.authorization
        let belongsInMemory = item.belongsInMemory(authorization: authorization)
        switch self {
        case .pinned:
            return belongsInMemory && pinnedIDs.contains(item.id)
        case .ideas:
            return belongsInMemory && MemoryGroup.ideas.contains(item)
        case .people:
            return belongsInMemory && MemoryGroup.people.contains(item)
        case .reference:
            return belongsInMemory && MemoryGroup.notes.contains(item)
        case .archive:
            return item.isArchived
        }
    }
}

enum MemoryPersonNameResolver {
    static func name(for item: CapturedItem) -> String? {
        if let explicit = item.personName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        return PersonNameInference.memoryName(in: item.originalTextSegment)
            ?? PersonNameInference.memoryName(in: item.displayTitle)
    }

    static func containsWholeName(_ name: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?i)(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}

private struct LibraryUndo: Identifiable {
    let id = UUID()
    let item: CapturedItem
    let wasArchived: Bool
}

private struct MemoryPersonProfile: Identifiable {
    let id: String
    let name: String
    let resolvedName: String?
    let items: [CapturedItem]

    var latestItem: CapturedItem? {
        items.max { $0.lastModifiedAt < $1.lastModifiedAt }
    }
}

/// Dock visibility is driven by the scroll view's own position, never by a
/// gesture layered on top of it. A custom drag recognizer covering a scroll
/// surface competes with the scroll itself, which is what made ordinary
/// swipes feel like they had been ignored.
struct DockScrollPolicy: Equatable {
    /// Within this distance of the top the dock always belongs on screen.
    static let restZone: CGFloat = 24
    /// Continuous downward scrolling needed before the dock gets out of the way.
    static let hideAfter: CGFloat = 56
    /// Upward scrolling needed to bring it back.
    static let revealAfter: CGFloat = 36

    private var deepest: CGFloat = 0
    private var shallowest: CGFloat = 0

    /// `scrolled` is 0 when the content rests at the top and grows as the
    /// content scrolls down. Content that cannot move never reports a change,
    /// so a screen with nothing to scroll can never hide the dock.
    mutating func update(scrolled: CGFloat) -> Bool? {
        if scrolled <= Self.restZone {
            deepest = scrolled
            shallowest = scrolled
            return true
        }

        deepest = max(deepest, scrolled)
        shallowest = min(shallowest, scrolled)

        if scrolled - shallowest >= Self.hideAfter { return settle(at: scrolled, visible: false) }
        if deepest - scrolled >= Self.revealAfter { return settle(at: scrolled, visible: true) }
        return nil
    }

    private mutating func settle(at scrolled: CGFloat, visible: Bool) -> Bool {
        deepest = scrolled
        shallowest = scrolled
        return visible
    }
}

/// Distance between the first row of a dock-aware scroll container and the top
/// of that container. `nil` means the row is no longer in the view hierarchy,
/// which only happens once the content has scrolled well past the top.
struct DockScrollTopAnchorKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}

enum DockScroll {
    static let coordinateSpace = "speakIt.dockScroll"

    /// How much scroll content must reserve above the bottom safe area for the
    /// floating dock and its offset.
    ///
    /// This belongs on the scroll containers themselves. An inset outside a
    /// `NavigationStack` changes the region offered to the stack, but does not
    /// reliably extend a nested `ScrollView` or `List`'s scrollable content.
    /// That left the final row at the physical safe-area edge, underneath the
    /// overlay, even though `RootView` appeared to reserve the same number.
    static let clearance: CGFloat = 86

    /// iOS 18 reports scroll geometry directly. On iOS 17 the only continuous
    /// signal is the first row's position, and once that row is recycled the
    /// list is unambiguously deep enough for the dock to be out of the way.
    static var readsScrollGeometry: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    static func scrolled(topAnchor: CGFloat?) -> CGFloat {
        guard let topAnchor else { return .greatestFiniteMagnitude }
        return -topAnchor
    }
}

/// Reports how far the scroll content has moved from its resting position.
struct DockScrollObserver: ViewModifier {
    let onScroll: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, scrolled in
                onScroll(scrolled)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Marks the first row of a dock-aware scroll container.
    func dockScrollTopAnchor() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DockScrollTopAnchorKey.self,
                    value: proxy.frame(in: .named(DockScroll.coordinateSpace)).minY
                )
            }
        )
    }
}

struct LibraryView: View {
    @Environment(\.thoughtRepository) private var repository
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Query(
        filter: #Predicate<CapturedItem> { $0.isArchived == false },
        sort: \CapturedItem.createdAt,
        order: .reverse
    ) private var activeItems: [CapturedItem]
    @Query(
        filter: #Predicate<CapturedItem> { $0.isArchived == true }
    ) private var archivedItems: [CapturedItem]

    let onCapture: () -> Void
    let onDockVisibilityChange: (Bool) -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedItem: CapturedItem?
    @State private var errorMessage: String?
    @State private var libraryUndo: LibraryUndo?
    @State private var selectedCollection: MemoryCollection? = LibraryView.initialCollection
    @State private var dockScrollPolicy = DockScrollPolicy()
    @State private var reportsDockVisible = true
    @State private var showsAccountSettings = false
    @AppStorage(MemoryPinStore.key) private var pinnedMemoryIDsRawValue = ""
    @AppStorage(IdeaStageStore.key) private var ideaStagesRawValue = ""

    init(
        onCapture: @escaping () -> Void,
        onDockVisibilityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onCapture = onCapture
        self.onDockVisibilityChange = onDockVisibilityChange
    }

    private static var initialCollection: MemoryCollection? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--show-memory-ideas") { return .ideas }
        if arguments.contains("--show-memory-people") { return .people }
        if arguments.contains("--show-memory-reference") { return .reference }
#endif
        return nil
    }

    private var memoryItems: [CapturedItem] {
        let authorization = LocationReminderMonitor.shared.authorization
        return activeItems.filter { $0.belongsInMemory(authorization: authorization) }
    }

    private var pinnedMemoryIDs: Set<UUID> {
        MemoryPinStore.decode(pinnedMemoryIDsRawValue)
    }

    private var ideaStages: [UUID: IdeaStage] {
        IdeaStageStore.decode(ideaStagesRawValue)
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResults: [CapturedItem] {
        guard !query.isEmpty else { return [] }
        let matches = memoryItems.filter { matchesSearch($0, query: query) }
        return MemoryItemOrdering.relevance(matches, pinnedIDs: pinnedMemoryIDs)
    }

    private var recentItems: [CapturedItem] {
        Array(
            MemoryItemOrdering.relevance(
                memoryItems.filter { !pinnedMemoryIDs.contains($0.id) },
                pinnedIDs: pinnedMemoryIDs
            )
            .prefix(MemoryItemOrdering.homePreviewLimit)
        )
    }

    private var archivedCount: Int {
        archivedItems.count
    }

    var body: some View {
        List {
            chromeRow(header, top: 18, bottom: 20)
                .dockScrollTopAnchor()
            chromeRow(searchField, bottom: 18)

            if query.isEmpty {
                chromeRow(memoryPurpose, bottom: 16)
                chromeRow(collectionGrid, bottom: 22)

                if memoryItems.isEmpty {
                    chromeRow(emptyState, bottom: 24)
                } else if !recentItems.isEmpty {
                    chromeRow(sectionHeader("Recently added", detail: "The latest things worth remembering"), bottom: 2)
                    ForEach(recentItems) { item in
                        memoryRow(item)
                    }
                }

                if archivedCount > 0 {
                    chromeRow(archiveLink, top: 20, bottom: 20)
                }
            } else {
                searchContent
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, DockScroll.clearance, for: .scrollContent)
        .coordinateSpace(name: DockScroll.coordinateSpace)
        .scrollBounceBehavior(.basedOnSize)
        .modifier(DockScrollObserver(onScroll: handleDockScroll))
        .onPreferenceChange(DockScrollTopAnchorKey.self) { anchor in
            guard !DockScroll.readsScrollGeometry else { return }
            handleDockScroll(DockScroll.scrolled(topAnchor: anchor))
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedCollection) { collection in
            MemoryCollectionView(
                collection: collection,
                onDockVisibilityChange: onDockVisibilityChange
            )
        }
        .sheet(item: $selectedItem) { item in
            ItemEditorView(item: item)
        }
        .sheet(isPresented: $showsAccountSettings) {
            AccountSettingsView()
        }
        .repositoryErrorAlert($errorMessage)
        .speakScreenStyle()
        .overlay(alignment: .bottom) {
            if let libraryUndo {
                UndoToast(message: libraryUndo.wasArchived ? "Restored" : "Moved to Archive") {
                    undoLibraryChange(libraryUndo)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, reportsDockVisible ? 92 : 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .onAppear {
            reportsDockVisible = true
            onDockVisibilityChange(true)
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--focus-memory-search") {
                isSearchFocused = true
            }
#endif
        }
        .onChange(of: isSearchFocused) { _, isFocused in
            reportsDockVisible = !isFocused
            onDockVisibilityChange(!isFocused)
            if !isFocused, !query.isEmpty {
                SpeakItAnalytics.track(.memorySearchPerformed(
                    results: AnalyticsSearchResultBucket(resultCount: searchResults.count)
                ))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Find · Recognize · Reuse")
                    .font(SpeakItTypography.eyebrow)
                    .foregroundStyle(Color.speakMuted)

                Text("Memory")
                    .font(SpeakItTypography.screenTitle)
                    .foregroundStyle(Color.speakInk)
            }

            Spacer()

            Button {
                showsAccountSettings = true
            } label: {
                Image(systemName: subscriptionStore.hasProAccess
                      ? "person.crop.circle.fill.badge.checkmark"
                      : "person.crop.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.speakInk)
                    .frame(width: 44, height: 44)
                    .background(Color.speakSurface, in: Circle())
                    .overlay { Circle().stroke(Color.speakDivider, lineWidth: 1) }
            }
            .buttonStyle(.speakIt)
            .accessibilityLabel("Account and settings. \(memoryItems.count) saved memories")
            .accessibilityIdentifier("memory.account")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.speakMuted)

            TextField("Search people, ideas, or facts", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(false)
                .focused($isSearchFocused)
                .submitLabel(.done)
                .onSubmit { isSearchFocused = false }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.speakMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.speakIt)
                .accessibilityLabel("Clear search")
            }

            if isSearchFocused {
                Button("Done") {
                    isSearchFocused = false
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.speakIt)
                .accessibilityLabel("Finish searching")
            }
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 50)
        .background(
            Color.speakSurface,
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
    }

    private var memoryPurpose: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What do you want to remember?")
                .font(.headline)
                .foregroundStyle(Color.speakInk)
            Text("Tasks stay in Today. Memory keeps the ideas, people, and facts you may need later.")
                .font(.subheadline)
                .foregroundStyle(Color.speakMuted)
        }
    }

    private var collectionGrid: some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
            spacing: 12
        ) {
            ForEach([MemoryCollection.pinned, .ideas, .people, .reference]) { collection in
                Button {
                    SpeakItAnalytics.track(.memoryCollectionOpened(collection: collection.rawValue))
                    selectedCollection = collection
                } label: {
                    MemoryDestinationCard(
                        collection: collection,
                        count: count(for: collection),
                        detail: detail(for: collection),
                        isEmphasized: collection == .pinned && count(for: collection) > 0
                    )
                }
                .buttonStyle(.speakIt)
                .accessibilityIdentifier("memory.collection.\(collection.rawValue)")
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if searchResults.isEmpty {
            chromeRow(
                VStack(alignment: .leading, spacing: 8) {
                    Text("No memories found")
                        .font(.title3.weight(.semibold))
                    Text("Try a person, project, place, or phrase you remember saying.")
                        .foregroundStyle(Color.speakMuted)
                },
                top: 28,
                bottom: 24
            )
        } else {
            ForEach(MemoryGroup.allCases) { group in
                let items = searchResults.filter(group.contains)
                if !items.isEmpty {
                    chromeRow(sectionHeader(group.title, detail: "\(items.count) matching"), top: 12, bottom: 2)
                    ForEach(items) { item in
                        memoryRow(item)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing to look up yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.speakInk)
            Text("Capture naturally. Speak It will keep actions in Today and place lasting details here.")
                .foregroundStyle(Color.speakMuted)
            Text("Try saying “Remember Catherine’s birthday is May 3.”")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.speakInk)
        }
        .padding(.top, 8)
    }

    private var archiveLink: some View {
        Button {
            SpeakItAnalytics.track(.memoryCollectionOpened(collection: MemoryCollection.archive.rawValue))
            selectedCollection = .archive
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "archivebox")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Color.speakSurface, in: Circle())
                    .overlay { Circle().stroke(Color.speakDivider, lineWidth: 1) }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Archive")
                        .font(.body.weight(.medium))
                    Text("\(archivedCount) saved out of sight")
                        .font(.caption)
                        .foregroundStyle(Color.speakMuted)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.speakMuted)
            }
            .foregroundStyle(Color.speakInk)
            .padding(14)
            .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.speakDivider, lineWidth: 1) }
        }
        .buttonStyle(.speakIt)
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SpeakItTypography.sectionTitle)
                Text(detail)
                    .font(SpeakItTypography.sectionDetail)
            }
            Spacer()
        }
        .foregroundStyle(Color.speakMuted)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Divider().overlay(Color.speakDivider) }
        .accessibilityAddTraits(.isHeader)
    }

    private func count(for collection: MemoryCollection) -> Int {
        memoryItems.filter { collection.contains($0, pinnedIDs: pinnedMemoryIDs) }.count
    }

    private func detail(for collection: MemoryCollection) -> String {
        let items = MemoryItemOrdering.relevance(
            memoryItems.filter { collection.contains($0, pinnedIDs: pinnedMemoryIDs) },
            pinnedIDs: pinnedMemoryIDs
        )
        switch collection {
        case .pinned:
            return items.first?.displayTitle ?? "Keep essentials close"
        case .ideas:
            let promising = items.filter { ideaStages[$0.id] == .promising }.count
            return promising > 0 ? "\(promising) promising" : (items.first?.displayTitle ?? "Capture sparks")
        case .people:
            let names = Set(items.compactMap(MemoryPersonNameResolver.name).map { $0.lowercased() })
            if names.isEmpty {
                return items.first?.displayTitle ?? "Remember the details"
            }
            return names.count == 1 ? "1 person remembered" : "\(names.count) people remembered"
        case .reference:
            return items.first?.displayTitle ?? "Facts and context"
        case .archive:
            return "Saved out of sight"
        }
    }

    private func chromeRow<Content: View>(
        _ content: Content,
        top: CGFloat = 0,
        bottom: CGFloat = 0
    ) -> some View {
        content
            .padding(.top, top)
            .padding(.bottom, bottom)
            .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func memoryRow(_ item: CapturedItem) -> some View {
        CapturedItemRow(
            item: item,
            showsCompletionControl: false,
            showsPinnedIndicator: pinnedMemoryIDs.contains(item.id),
            showsPriorityIndicator: true,
            onToggleCompleted: {},
            onEdit: { selectedItem = item }
        )
        .padding(.vertical, 12)
        .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
        .listRowSeparator(.visible, edges: .bottom)
        .listRowSeparatorTint(Color.speakDivider)
        .listRowBackground(Color.speakBackground)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { toggleArchived(item) } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(Color.speakInverseSurface)
        }
        .contextMenu {
            Button { togglePinned(item) } label: {
                Label(
                    pinnedMemoryIDs.contains(item.id) ? "Unpin" : "Pin",
                    systemImage: pinnedMemoryIDs.contains(item.id) ? "pin.slash" : "pin"
                )
            }
            Button { toggleArchived(item) } label: {
                Label("Move to Archive", systemImage: "archivebox")
            }
        }
    }

    private func matchesSearch(_ item: CapturedItem, query: String) -> Bool {
        item.displayTitle.localizedStandardContains(query)
            || item.originalTextSegment.localizedStandardContains(query)
            || item.personName?.localizedStandardContains(query) == true
            || item.category.displayName.localizedStandardContains(query)
            || item.itemType.displayName.localizedStandardContains(query)
    }

    private func toggleArchived(_ item: CapturedItem) {
        guard let repository else {
            errorMessage = "Local storage is unavailable."
            return
        }
        let wasArchived = item.isArchived
        do {
            try repository.setArchived(item, archived: !wasArchived)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showLibraryUndo(item: item, wasArchived: wasArchived)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func togglePinned(_ item: CapturedItem) {
        setPinned(item, pinned: !pinnedMemoryIDs.contains(item.id))
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func setPinned(_ item: CapturedItem, pinned: Bool) {
        MemoryPinStore.setPinned(pinned, for: item.id)
    }

    private func showLibraryUndo(item: CapturedItem, wasArchived: Bool) {
        let notice = LibraryUndo(item: item, wasArchived: wasArchived)
        withAnimation(.snappy(duration: 0.24)) { libraryUndo = notice }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard libraryUndo?.id == notice.id else { return }
            withAnimation(.easeOut(duration: 0.2)) { libraryUndo = nil }
        }
    }

    private func undoLibraryChange(_ notice: LibraryUndo) {
        guard let repository else {
            errorMessage = "Local storage is unavailable."
            return
        }
        do {
            try repository.setArchived(notice.item, archived: notice.wasArchived)
            withAnimation(.easeOut(duration: 0.18)) { libraryUndo = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleDockScroll(_ scrolled: CGFloat) {
        guard let visibility = dockScrollPolicy.update(scrolled: scrolled) else { return }
        // Searching hides the dock on purpose; do not undo that here.
        guard !visibility || !isSearchFocused else { return }
        updateDockVisibility(visibility)
    }

    private func updateDockVisibility(_ visible: Bool) {
        guard reportsDockVisible != visible else { return }
        reportsDockVisible = visible
        onDockVisibilityChange(visible)
    }
}

private struct MemoryDestinationCard: View {
    let collection: MemoryCollection
    let count: Int
    let detail: String
    let isEmphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: collection.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isEmphasized ? Color.speakInverseInk.opacity(0.56) : Color.speakMuted)
            }

            Spacer(minLength: 2)

            Text(collection.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.caption)
                .foregroundStyle(isEmphasized ? Color.speakInverseInk.opacity(0.66) : Color.speakMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
        }
        .foregroundStyle(isEmphasized ? Color.speakInverseInk : Color.speakInk)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 134, alignment: .leading)
        .background(
            isEmphasized ? Color.speakInverseSurface : Color.speakSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            if !isEmphasized {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.speakDivider, lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(collection.title), \(count)")
        .accessibilityHint(detail)
    }
}

private enum MemorySortOption: String, CaseIterable, Identifiable {
    case relevant
    case updated
    case added
    case title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relevant: "Pinned & recent"
        case .updated: "Recently updated"
        case .added: "Recently added"
        case .title: "Title"
        }
    }
}

private struct IdeaStagePickerSheet: View {
    let item: CapturedItem
    let selectedStage: IdeaStage
    let onSelect: (IdeaStage) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(IdeaStage.allCases) { stage in
                        Button {
                            onSelect(stage)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: stage.systemImage)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.speakInk)
                                    .frame(width: 34, height: 34)
                                    .background(Color.speakSurface, in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(stage.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color.speakInk)
                                    Text(stage.detail)
                                        .font(.caption)
                                        .foregroundStyle(Color.speakMuted)
                                }

                                Spacer(minLength: 8)

                                if stage == selectedStage {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color.speakInk)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.speakIt)
                    }
                } header: {
                    Text(item.displayTitle)
                        .lineLimit(1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Idea stage")
            .navigationBarTitleDisplayMode(.inline)
        }
        .speakScreenStyle()
    }
}

private struct MemoryCollectionView: View {
    @Environment(\.thoughtRepository) private var repository
    @Query(sort: \CapturedItem.createdAt, order: .reverse) private var allItems: [CapturedItem]

    let collection: MemoryCollection
    let onDockVisibilityChange: (Bool) -> Void

    @State private var searchText = ""
    @State private var isSearchPresented = false
    @FocusState private var isCollectionSearchFocused: Bool
    @State private var selectedIdeaStage: IdeaStage?
    @State private var selectedSort = MemorySortOption.relevant
    @State private var selectedItem: CapturedItem?
    @State private var stagePickerItem: CapturedItem?
    @State private var errorMessage: String?
    @State private var libraryUndo: LibraryUndo?
    @AppStorage("SpeakIt.memoryCompactRows") private var usesCompactRows = false
    @AppStorage(MemoryPinStore.key) private var pinnedMemoryIDsRawValue = ""
    @AppStorage(IdeaStageStore.key) private var ideaStagesRawValue = ""

    private var pinnedMemoryIDs: Set<UUID> {
        MemoryPinStore.decode(pinnedMemoryIDsRawValue)
    }

    private var ideaStages: [UUID: IdeaStage] {
        IdeaStageStore.decode(ideaStagesRawValue)
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var collectionItems: [CapturedItem] {
        var items = allItems.filter { collection.contains($0, pinnedIDs: pinnedMemoryIDs) }
        if let selectedIdeaStage, collection == .ideas {
            items = items.filter { stage(for: $0) == selectedIdeaStage }
        }
        if !query.isEmpty {
            items = items.filter { matchesSearch($0, query: query) }
        }
        return sorted(items)
    }

    private var personProfiles: [MemoryPersonProfile] {
        let grouped = Dictionary(grouping: collectionItems) { item in
            MemoryPersonNameResolver.name(for: item)?.lowercased() ?? "__people_notes__"
        }
        return grouped.map { key, items in
            let resolvedName = items.compactMap(MemoryPersonNameResolver.name).first
            return MemoryPersonProfile(
                id: key,
                name: resolvedName ?? "People notes",
                resolvedName: resolvedName,
                items: MemoryItemOrdering.relevance(items, pinnedIDs: pinnedMemoryIDs)
            )
        }
        .sorted { lhs, rhs in
            switch selectedSort {
            case .relevant:
                let leftPinned = lhs.items.contains { pinnedMemoryIDs.contains($0.id) }
                let rightPinned = rhs.items.contains { pinnedMemoryIDs.contains($0.id) }
                if leftPinned != rightPinned { return leftPinned }
                let leftDate = lhs.latestItem?.lastModifiedAt ?? .distantPast
                let rightDate = rhs.latestItem?.lastModifiedAt ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
            case .updated:
                let leftDate = lhs.latestItem?.lastModifiedAt ?? .distantPast
                let rightDate = rhs.latestItem?.lastModifiedAt ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
            case .added:
                let leftDate = lhs.items.map(\.createdAt).max() ?? .distantPast
                let rightDate = rhs.items.map(\.createdAt).max() ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
            case .title:
                break
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if isSearchPresented {
                collectionSearchField
            } else if !query.isEmpty {
                activeSearchSummary
            }

            if collection == .ideas {
                ideaStageControls
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if collection == .people {
                peopleContent
            } else if collectionItems.isEmpty {
                collectionEmptyState
            } else {
                ForEach(collectionItems) { item in
                    collectionRow(item)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    presentCollectionSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search \(collection.title)")

                sortMenu

                Button {
                    usesCompactRows.toggle()
                } label: {
                    Image(systemName: usesCompactRows ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                }
                .accessibilityLabel(usesCompactRows ? "Use comfortable rows" : "Use compact rows")
            }
        }
        .sheet(item: $selectedItem) { item in
            ItemEditorView(item: item)
        }
        .sheet(item: $stagePickerItem) { item in
            IdeaStagePickerSheet(
                item: item,
                selectedStage: stage(for: item)
            ) { stage in
                setStage(stage, for: item)
                stagePickerItem = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCompactAdaptation(.sheet)
        }
        .repositoryErrorAlert($errorMessage)
        .speakScreenStyle()
        .overlay(alignment: .bottom) {
            if let libraryUndo {
                UndoToast(message: libraryUndo.wasArchived ? "Restored" : "Moved to Archive") {
                    undoLibraryChange(libraryUndo)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            onDockVisibilityChange(false)
#if DEBUG
            if collection == .ideas,
               ProcessInfo.processInfo.arguments.contains("--show-idea-stage-picker"),
               stagePickerItem == nil {
                stagePickerItem = collectionItems.first
            }
#endif
        }
        .onChange(of: isCollectionSearchFocused) { _, isFocused in
            guard !isFocused, isSearchPresented else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isSearchPresented = false
            }
        }
    }

    private var collectionSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.speakMuted)

            TextField("Search \(collection.title.lowercased())", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(false)
                .focused($isCollectionSearchFocused)
                .submitLabel(.done)
                .onSubmit { finishCollectionSearch() }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.speakMuted)
                }
                .buttonStyle(.speakIt)
                .accessibilityLabel("Clear search")
            }

            Button("Done", action: finishCollectionSearch)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.speakIt)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var activeSearchSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.speakMuted)
            Text("Results for “\(query)”")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
            Button {
                searchText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.speakMuted)
            }
            .buttonStyle(.speakIt)
            .accessibilityLabel("Clear search")
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func presentCollectionSearch() {
        withAnimation(.easeOut(duration: 0.18)) {
            isSearchPresented = true
        }
        Task { @MainActor in
            await Task.yield()
            isCollectionSearchFocused = true
        }
    }

    private func finishCollectionSearch() {
        isCollectionSearchFocused = false
        withAnimation(.easeOut(duration: 0.18)) {
            isSearchPresented = false
        }
    }

    private var ideaStageControls: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                stageButton(title: "All", systemImage: "square.grid.2x2", stage: nil)
                ForEach(IdeaStage.allCases) { stage in
                    stageButton(title: stage.title, systemImage: stage.systemImage, stage: stage)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func stageButton(title: String, systemImage: String, stage: IdeaStage?) -> some View {
        let isSelected = selectedIdeaStage == stage
        return Button {
            selectedIdeaStage = stage
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isSelected ? Color.speakInverseInk : Color.speakInk)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(isSelected ? Color.speakInverseSurface : Color.speakSurface, in: Capsule())
                .overlay {
                    if !isSelected { Capsule().stroke(Color.speakDivider, lineWidth: 1) }
                }
        }
        .buttonStyle(.speakIt)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var peopleContent: some View {
        if personProfiles.isEmpty {
            collectionEmptyState
        } else {
            ForEach(personProfiles) { profile in
                NavigationLink {
                    MemoryPersonDetailView(
                        displayName: profile.name,
                        resolvedName: profile.resolvedName,
                        onDockVisibilityChange: onDockVisibilityChange
                    )
                } label: {
                    MemoryPersonProfileRow(profile: profile)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 16))
                .listRowSeparatorTint(Color.speakDivider)
                .listRowBackground(Color.speakBackground)
            }
        }
    }

    private var collectionEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: collection.systemImage)
                .font(.title2)
                .foregroundStyle(Color.speakMuted)
            Text(emptyTitle)
                .font(.title3.weight(.semibold))
            Text(emptyDetail)
                .foregroundStyle(Color.speakMuted)
        }
        .padding(.vertical, 36)
        .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var emptyTitle: String {
        if !query.isEmpty { return "No matches" }
        if collection == .ideas, selectedIdeaStage != nil { return "No ideas at this stage" }
        return "Nothing here yet"
    }

    private var emptyDetail: String {
        if !query.isEmpty { return "Try another person, project, or phrase." }
        switch collection {
        case .pinned: return "Hold any memory and pin what you want kept close."
        case .ideas: return "Ideas you capture will begin in New."
        case .people: return "Details about people will be collected into profiles."
        case .reference: return "Useful facts, decisions, and context will appear here."
        case .archive: return "Archived items stay safe without cluttering Memory."
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $selectedSort) {
                ForEach(MemorySortOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort \(collection.title)")
    }

    private func collectionRow(_ item: CapturedItem) -> some View {
        CapturedItemRow(
            item: item,
            showsCompletionControl: false,
            showsPinnedIndicator: pinnedMemoryIDs.contains(item.id),
            showsPriorityIndicator: true,
            trailingDetail: collection == .ideas ? stage(for: item).title : nil,
            onTrailingDetailTap: collection == .ideas ? { stagePickerItem = item } : nil,
            onToggleCompleted: {},
            onEdit: { selectedItem = item }
        )
        .padding(.vertical, usesCompactRows ? 6 : 12)
        .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 16))
        .listRowSeparatorTint(Color.speakDivider)
        .listRowBackground(Color.speakBackground)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if collection != .archive {
                Button { togglePinned(item) } label: {
                    Label(pinnedMemoryIDs.contains(item.id) ? "Unpin" : "Pin", systemImage: "pin")
                }
                .tint(Color.speakMuted)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { toggleArchived(item) } label: {
                Label(
                    item.isArchived ? "Restore" : "Archive",
                    systemImage: item.isArchived ? "arrow.uturn.backward" : "archivebox"
                )
            }
            .tint(Color.speakInverseSurface)
        }
        .contextMenu {
            if !item.isArchived {
                Button { togglePinned(item) } label: {
                    Label(
                        pinnedMemoryIDs.contains(item.id) ? "Unpin" : "Pin",
                        systemImage: pinnedMemoryIDs.contains(item.id) ? "pin.slash" : "pin"
                    )
                }
            }
            if collection == .ideas {
                Menu("Idea stage", systemImage: "point.3.connected.trianglepath.dotted") {
                    ForEach(IdeaStage.allCases) { stage in
                        Button { setStage(stage, for: item) } label: {
                            Label(stage.title, systemImage: stage.systemImage)
                        }
                    }
                }
            }
            Button { toggleArchived(item) } label: {
                Label(
                    item.isArchived ? "Restore" : "Move to Archive",
                    systemImage: item.isArchived ? "arrow.uturn.backward" : "archivebox"
                )
            }
        }
    }

    private func sorted(_ items: [CapturedItem]) -> [CapturedItem] {
        if collection == .ideas, selectedSort == .relevant {
            return items.sorted { lhs, rhs in
                let lhsPinned = pinnedMemoryIDs.contains(lhs.id)
                let rhsPinned = pinnedMemoryIDs.contains(rhs.id)
                if lhsPinned != rhsPinned { return lhsPinned }
                let lhsStage = stage(for: lhs)
                let rhsStage = stage(for: rhs)
                if lhsStage.sortRank != rhsStage.sortRank {
                    return lhsStage.sortRank < rhsStage.sortRank
                }
                return lhs.lastModifiedAt > rhs.lastModifiedAt
            }
        }

        switch selectedSort {
        case .relevant:
            return MemoryItemOrdering.relevance(items, pinnedIDs: pinnedMemoryIDs)
        case .updated:
            return items.sorted { $0.lastModifiedAt > $1.lastModifiedAt }
        case .added:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return items.sorted {
                $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
        }
    }

    private func stage(for item: CapturedItem) -> IdeaStage {
        ideaStages[item.id] ?? .new
    }

    private func setStage(_ stage: IdeaStage, for item: CapturedItem) {
        IdeaStageStore.setStage(stage, for: item.id)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func matchesSearch(_ item: CapturedItem, query: String) -> Bool {
        item.displayTitle.localizedStandardContains(query)
            || item.originalTextSegment.localizedStandardContains(query)
            || item.personName?.localizedStandardContains(query) == true
            || item.category.displayName.localizedStandardContains(query)
    }

    private func togglePinned(_ item: CapturedItem) {
        MemoryPinStore.setPinned(!pinnedMemoryIDs.contains(item.id), for: item.id)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func toggleArchived(_ item: CapturedItem) {
        guard let repository else {
            errorMessage = "Local storage is unavailable."
            return
        }
        let wasArchived = item.isArchived
        do {
            try repository.setArchived(item, archived: !wasArchived)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showLibraryUndo(item: item, wasArchived: wasArchived)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func showLibraryUndo(item: CapturedItem, wasArchived: Bool) {
        let notice = LibraryUndo(item: item, wasArchived: wasArchived)
        withAnimation(.snappy(duration: 0.24)) { libraryUndo = notice }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard libraryUndo?.id == notice.id else { return }
            withAnimation(.easeOut(duration: 0.2)) { libraryUndo = nil }
        }
    }

    private func undoLibraryChange(_ notice: LibraryUndo) {
        guard let repository else { return }
        do {
            try repository.setArchived(notice.item, archived: notice.wasArchived)
            withAnimation(.easeOut(duration: 0.18)) { libraryUndo = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MemoryPersonProfileRow: View {
    let profile: MemoryPersonProfile

    var body: some View {
        HStack(spacing: 14) {
            Text(initials)
                .font(.subheadline.weight(.semibold))
                .frame(width: 42, height: 42)
                .background(Color.speakSurface, in: Circle())
                .overlay { Circle().stroke(Color.speakDivider, lineWidth: 1) }

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.speakInk)
                Text(profile.latestItem?.displayTitle ?? "No details yet")
                    .font(.caption)
                    .foregroundStyle(Color.speakMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            Text("\(profile.items.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.speakMuted)
        }
        .padding(.vertical, 12)
    }

    private var initials: String {
        let letters = profile.name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

private struct MemoryPersonDetailView: View {
    @Environment(\.thoughtRepository) private var repository
    @Query(
        filter: #Predicate<CapturedItem> { $0.isArchived == false },
        sort: \CapturedItem.createdAt,
        order: .reverse
    ) private var allItems: [CapturedItem]

    let displayName: String
    let resolvedName: String?
    let onDockVisibilityChange: (Bool) -> Void

    @State private var selectedItem: CapturedItem?
    @State private var errorMessage: String?
    @AppStorage(MemoryPinStore.key) private var pinnedMemoryIDsRawValue = ""

    private var pinnedMemoryIDs: Set<UUID> {
        MemoryPinStore.decode(pinnedMemoryIDsRawValue)
    }

    private var memories: [CapturedItem] {
        let matches = allItems.filter { item in
            let authorization = LocationReminderMonitor.shared.authorization
            guard item.belongsInMemory(authorization: authorization),
                  MemoryGroup.people.contains(item) else { return false }
            if let resolvedName {
                return MemoryPersonNameResolver.name(for: item)?.localizedCaseInsensitiveCompare(resolvedName) == .orderedSame
            }
            return MemoryPersonNameResolver.name(for: item) == nil
        }
        return MemoryItemOrdering.relevance(matches, pinnedIDs: pinnedMemoryIDs)
    }

    private var relatedActions: [CapturedItem] {
        guard let resolvedName else { return [] }
        return allItems.filter { item in
            guard item.belongsInToday else { return false }
            return item.personName?.localizedCaseInsensitiveCompare(resolvedName) == .orderedSame
                || MemoryPersonNameResolver.containsWholeName(resolvedName, in: item.displayTitle)
                || MemoryPersonNameResolver.containsWholeName(resolvedName, in: item.originalTextSegment)
        }
        .sorted { lhs, rhs in
            let leftDate = lhs.dueDate ?? .distantFuture
            let rightDate = rhs.dueDate ?? .distantFuture
            if leftDate != rightDate { return leftDate < rightDate }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var body: some View {
        List {
            Section {
                if memories.isEmpty {
                    Text("No remembered details yet.")
                        .foregroundStyle(Color.speakMuted)
                } else {
                    ForEach(memories) { item in
                        CapturedItemRow(
                            item: item,
                            showsCompletionControl: false,
                            showsPinnedIndicator: pinnedMemoryIDs.contains(item.id),
                            onToggleCompleted: {},
                            onEdit: { selectedItem = item }
                        )
                        .padding(.vertical, 8)
                    }
                }
            } header: {
                Text("Remembered")
            } footer: {
                Text("Facts stay in Memory. Actions stay in Today.")
            }

            if !relatedActions.isEmpty {
                Section("Related in Today") {
                    ForEach(relatedActions) { item in
                        CapturedItemRow(
                            item: item,
                            onToggleCompleted: { complete(item) },
                            onEdit: { selectedItem = item }
                        )
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $selectedItem) { item in
            ItemEditorView(item: item)
        }
        .repositoryErrorAlert($errorMessage)
        .speakScreenStyle()
        .onAppear { onDockVisibilityChange(false) }
    }

    private func complete(_ item: CapturedItem) {
        guard let repository else {
            errorMessage = "Local storage is unavailable."
            return
        }
        do {
            try repository.setCompleted(item, completed: true)
            SpeakItAnalytics.track(.taskCompletionChanged(completed: true))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LibraryView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        let preview = PreviewData.make()
        return NavigationStack {
            LibraryView(onCapture: {})
        }
        .modelContainer(preview.container)
        .environment(\.thoughtRepository, preview.repository)
        .environmentObject(SubscriptionStore())
    }
}
