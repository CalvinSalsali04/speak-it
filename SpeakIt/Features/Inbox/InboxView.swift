import SwiftData
import SwiftUI

private enum InboxScope: String, CaseIterable, Identifiable {
    case inbox = "Inbox"
    case archived = "Archived"

    var id: String { rawValue }
}

struct InboxView: View {
    @Environment(\.thoughtRepository) private var repository
    @Query(sort: \CapturedItem.createdAt, order: .reverse) private var allItems: [CapturedItem]

    let onCapture: () -> Void

    @State private var scope: InboxScope = .inbox
    @State private var selectedItem: CapturedItem?
    @State private var errorMessage: String?

    private var visibleItems: [CapturedItem] {
        switch scope {
        case .inbox:
            allItems.filter { item in
                !item.isArchived && (
                    !item.isReviewed ||
                    item.needsClarification ||
                    item.dueDate == nil ||
                    item.isCompleted
                )
            }
        case .archived:
            allItems.filter(\.isArchived)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inbox view", selection: $scope) {
                ForEach(InboxScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .accessibilityHint("Switch between active and archived thoughts")

            if visibleItems.isEmpty {
                EmptyStateView(
                    title: scope == .inbox ? "Nothing in your Inbox" : "No archived thoughts",
                    systemImage: scope == .inbox ? "tray" : "archivebox",
                    description: scope == .inbox
                        ? "Recent and unscheduled thoughts appear here until you review them."
                        : "Thoughts you archive will stay safely available here.",
                    actionTitle: scope == .inbox ? "Capture a thought" : nil,
                    action: scope == .inbox ? onCapture : nil
                )
            } else {
                List {
                    ForEach(visibleItems) { item in
                        CapturedItemRow(
                            item: item,
                            onToggleCompleted: { toggleCompleted(item) },
                            onEdit: { selectedItem = item }
                        )
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                toggleArchived(item)
                            } label: {
                                Label(
                                    item.isArchived ? "Restore" : "Archive",
                                    systemImage: item.isArchived ? "tray.and.arrow.up" : "archivebox"
                                )
                            }
                            .tint(.speakInk)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Inbox")
        .sheet(item: $selectedItem) { item in
            ItemEditorView(item: item)
        }
        .repositoryErrorAlert($errorMessage)
        .speakScreenStyle()
    }

    private func toggleCompleted(_ item: CapturedItem) {
        perform {
            try repository?.setCompleted(item, completed: !item.isCompleted)
        }
    }

    private func toggleArchived(_ item: CapturedItem) {
        perform {
            try repository?.setArchived(item, archived: !item.isArchived)
        }
    }

    private func perform(_ action: () throws -> Void) {
        guard repository != nil else {
            errorMessage = "Local storage is unavailable."
            return
        }

        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct InboxView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        let preview = PreviewData.make()
        return NavigationStack {
            InboxView(onCapture: {})
        }
        .modelContainer(preview.container)
        .environment(\.thoughtRepository, preview.repository)
    }
}
