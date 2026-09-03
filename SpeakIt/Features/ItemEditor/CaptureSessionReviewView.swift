import SwiftUI

struct CaptureSessionReviewView: View {
    @Environment(\.thoughtRepository) private var repository

    let session: CaptureSession
    /// Called after an operation that changes which items this session has, or
    /// what the item the caller is holding contains.
    ///
    /// `ItemEditorView` pushes this screen from inside its own form and keeps
    /// `@State` copies of the item's title, type and dates taken in `init`.
    /// Split, Merge, Undo and Organize again all rewrite or delete that exact
    /// item, and SwiftUI preserves `@State` across the pop — so returning to
    /// the form and tapping Save wrote the pre-operation values straight back
    /// over the result. The editor closes instead.
    var onStructuralChange: () -> Void = {}

    @State private var splitTarget: CapturedItem?
    @State private var errorMessage: String?
    @State private var showsUndoConfirmation = false
    @State private var showsReorganizeConfirmation = false
    @State private var itemCountBeforeSplit = 0

    private var items: [CapturedItem] {
        session.items.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var body: some View {
        List {
            if session.processingStatus != .complete {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your original words are safe")
                                .font(.body.weight(.semibold))
                            Text("Speak It can try organizing them again without replacing or deleting the capture.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.shield")
                    }
                }
            }

            Section("Original capture") {
                Text(session.originalTranscription)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Organized into \(items.count)") {
                ForEach(items, id: \.id) { item in
                    CaptureReviewItemRow(
                        item: item,
                        canMerge: nextItem(after: item) != nil,
                        splitAction: { beginSplitting(item) },
                        mergeAction: { mergeWithNext(item) }
                    )
                }
            }

            Section {
                Button {
                    // Re-reading the transcript rewrites every field on every
                    // row in this capture — title, type, category, priority,
                    // person, dates — so any correction made by hand is gone.
                    // It used to run on the first tap, directly above an Undo
                    // that does ask, which had the two backwards.
                    showsReorganizeConfirmation = true
                } label: {
                    Label("Organize again", systemImage: "arrow.clockwise")
                }

                Button {
                    showsUndoConfirmation = true
                } label: {
                    Label("Undo organization", systemImage: "arrow.uturn.backward")
                }
            } header: {
                Text("Recovery")
            } footer: {
                Text("Undo keeps the complete original capture as one reviewable item. Nothing you said is deleted.")
            }
        }
        .navigationTitle("Capture details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(
            item: $splitTarget,
            onDismiss: {
                // A split rewrites the first part in place and inserts the
                // rest, so the count is the reliable signal that one happened.
                // Cancelling the sheet leaves it unchanged and the editor stays
                // where it is.
                if session.items.count != itemCountBeforeSplit {
                    onStructuralChange()
                }
            }
        ) { item in
            SplitThoughtView(item: item)
        }
        .confirmationDialog(
            "Organize again?",
            isPresented: $showsReorganizeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Organize again", role: .destructive) {
                perform { try repository?.reorganize(session) }
                onStructuralChange()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Speak It will read your original words again from scratch. Any changes you made to these items by hand will be replaced. Your original capture is not touched.")
        }
        .confirmationDialog(
            "Undo organization?",
            isPresented: $showsUndoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep as one original thought") {
                perform { try repository?.undoOrganization(session) }
                onStructuralChange()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The extracted items will be replaced by the untouched original capture.")
        }
        .repositoryErrorAlert($errorMessage)
    }

    private func beginSplitting(_ item: CapturedItem) {
        itemCountBeforeSplit = session.items.count
        splitTarget = item
    }

    private func nextItem(after item: CapturedItem) -> CapturedItem? {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        let nextIndex = items.index(after: index)
        guard nextIndex < items.endIndex else { return nil }
        return items[nextIndex]
    }

    private func mergeWithNext(_ item: CapturedItem) {
        guard let next = nextItem(after: item) else { return }
        perform { try repository?.merge([item, next]) }
        onStructuralChange()
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

private struct CaptureReviewItemRow: View {
    let item: CapturedItem
    let canMerge: Bool
    let splitAction: () -> Void
    let mergeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.itemType.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayTitle)
                        .font(.body.weight(.medium))
                    Text("\(item.category.displayName) · \(item.itemType.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if item.needsClarification {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Needs review")
                }
            }

            HStack(spacing: 18) {
                Button("Split", action: splitAction)
                .buttonStyle(.speakIt)

                if canMerge {
                    Button("Merge with next", action: mergeAction)
                .buttonStyle(.speakIt)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

private struct SplitThoughtView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.thoughtRepository) private var repository

    let item: CapturedItem

    @State private var parts: [String]
    @State private var errorMessage: String?

    init(item: CapturedItem) {
        self.item = item
        _parts = State(initialValue: Self.suggestedParts(for: item.originalTextSegment))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(parts.indices, id: \.self) { index in
                        TextField(
                            "Thought \(index + 1)",
                            text: Binding(
                                get: { parts[index] },
                                set: { parts[index] = $0 }
                            ),
                            axis: .vertical
                        )
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                    }

                    if parts.count < 12 {
                        Button {
                            parts.append("")
                        } label: {
                            Label("Add another thought", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("Separate thoughts")
                } footer: {
                    Text("Each line becomes its own Today or Memory item. The full original capture remains attached to all of them.")
                }
            }
            .navigationTitle("Split Thought")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split", action: save)
                        .disabled(nonemptyParts.count < 2)
                }
            }
            .repositoryErrorAlert($errorMessage)
        }
    }

    private var nonemptyParts: [String] {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func save() {
        guard let repository else {
            errorMessage = "Local storage is unavailable."
            return
        }
        do {
            try repository.split(item, into: nonemptyParts)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func suggestedParts(for text: String) -> [String] {
        if let range = text.range(of: #"(?i)\s+and\s+"#, options: .regularExpression) {
            let first = String(text[..<range.lowerBound])
            let second = String(text[range.upperBound...])
            if !first.isEmpty, !second.isEmpty { return [first, second] }
        }
        return [text, ""]
    }
}
