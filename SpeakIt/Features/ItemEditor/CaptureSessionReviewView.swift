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
    @State private var editTarget: CapturedItem?
    @State private var editTargetID: UUID?
    @State private var editTargetModifiedAt: Date?
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

    private var savedChange: CaptureOperationState? {
        let state = CaptureOperationState.read(from: session.operationStateData)
        return state?.phase == .performed ? state : nil
    }

    private var hasPendingChange: Bool {
        CaptureOperationState.read(from: session.operationStateData)?.phase == .pendingChoice
            || items.contains { PendingOperationStore.record(for: $0.id) != nil }
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

            if let change = savedChange {
                Section("Saved change") {
                    if let receipt = change.atomicRevision {
                        LabeledContent("Before", value: receipt.before.title)
                        LabeledContent("After", value: receipt.after.title)
                        if receipt.before.person != receipt.after.person {
                            LabeledContent("Previous person", value: receipt.before.person ?? "None")
                            LabeledContent("Current person", value: receipt.after.person ?? "None")
                        }
                        if receipt.before.due != receipt.after.due {
                            LabeledContent("Previous due date", value: receipt.before.due?.formatted(date: .abbreviated, time: TemporalKind(rawValue: receipt.before.temporalKind ?? "")?.carriesTimeOfDay == true ? .shortened : .omitted) ?? "None")
                            LabeledContent("Current due date", value: receipt.after.due?.formatted(date: .abbreviated, time: TemporalKind(rawValue: receipt.after.temporalKind ?? "")?.carriesTimeOfDay == true ? .shortened : .omitted) ?? "None")
                        }
                        if let before = receipt.before.reminder {
                            LabeledContent("Previous reminder", value: before.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let after = receipt.after.reminder {
                            LabeledContent("Current reminder", value: after.formatted(date: .abbreviated, time: .shortened))
                        }
                        if change.reminderSynchronizationPending == true {
                            Text("The change is saved. Reminder delivery still needs to be confirmed.")
                                .foregroundStyle(.secondary)
                        } else if change.reminderSynchronizationStatus == "superseded" {
                            Text("A later edit replaced this reminder request.")
                                .foregroundStyle(.secondary)
                        } else if change.reminderSynchronizationStatus == "expired" {
                            Text("The saved reminder time has passed. Delivery was not confirmed.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(change.newTitle ?? change.targetTitle ?? "Saved change completed")
                    }
                }
            }

            if !items.isEmpty { Section("Organized into \(items.count)") {
                ForEach(items, id: \.id) { item in
                    CaptureReviewItemRow(
                        item: item,
                        canMerge: nextItem(after: item) != nil,
                        editAction: { beginEditing(item) },
                        splitAction: { beginSplitting(item) },
                        keepAsOneAction: item.clarificationRequirement == .splitDecision && !hasPendingChange
                            ? { keepAsOne(item) } : nil,
                        mergeAction: { mergeWithNext(item) }
                    )
                }
            } }

            if savedChange == nil, !hasPendingChange { Section {
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
                Text("Undo keeps the complete original capture as one item. You can then choose Task or Note without splitting it again. Nothing you said is deleted.")
            } }
        }
        .accessibilityIdentifier("capture.review.content")
        .navigationTitle("Capture details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editTarget, onDismiss: finishEditing) { item in
            ItemEditorView(item: item)
        }
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
                perform {
                    try repository?.undoOrganization(session)
                    onStructuralChange()
                }
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

    private func keepAsOne(_ item: CapturedItem) {
        perform {
            try repository?.keepAsOneThought(item)
            onStructuralChange()
        }
    }

    private func beginEditing(_ item: CapturedItem) {
        editTargetID = item.id
        editTargetModifiedAt = item.lastModifiedAt
        editTarget = item
    }

    private func finishEditing() {
        defer {
            editTargetID = nil
            editTargetModifiedAt = nil
        }
        guard let editTargetID, let editTargetModifiedAt else { return }
        let current = session.items.first { $0.id == editTargetID }
        if current == nil || current?.lastModifiedAt != editTargetModifiedAt {
            onStructuralChange()
        }
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
    let editAction: () -> Void
    let splitAction: () -> Void
    let keepAsOneAction: (() -> Void)?
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

            Button(action: editAction) {
                Label("Edit this item", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
                .buttonStyle(.speakIt)
                .accessibilityHint("Change only this saved item; the original capture stays available")
                .accessibilityIdentifier("capture.review.editItem")

            HStack(spacing: 18) {
                Button("Split", action: splitAction)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("capture.review.splitItem")

                if canMerge {
                    Button("Merge with next", action: mergeAction)
                        .frame(minHeight: 44)
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.speakIt)

            if let keepAsOneAction {
                Button("Keep as one thought", action: keepAsOneAction)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .buttonStyle(.speakIt)
                    .accessibilityHint("Keeps this item's words together without changing the original capture or other items")
                    .accessibilityIdentifier("capture.review.keepAsOneThought")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SplitThoughtView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.thoughtRepository) private var repository

    let item: CapturedItem
    private let recipientRepairParts: [String]?

    @State private var parts: [String]
    @State private var errorMessage: String?

    init(item: CapturedItem) {
        self.item = item
        let repairParts = item.semanticState == .contested(.uncertainClauseBoundary)
            ? RuleBasedThoughtExtractor.recipientRevisionEditingParts(in: item.originalTextSegment) : nil
        recipientRepairParts = repairParts
        _parts = State(initialValue: repairParts ?? Self.suggestedParts(for: item.originalTextSegment))
    }

    var body: some View {
        NavigationStack {
            Form {
                if recipientRepairParts != nil {
                    Section("Original wording") {
                        Text(item.originalTextSegment)
                            .textSelection(.enabled)
                    }
                }
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
                        .accessibilityIdentifier("capture.split.part.\(index)")
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
                    if recipientRepairParts != nil {
                        Text("Change the recipient on the intended message. The other message is already filled in, and the full original capture stays attached.")
                    } else {
                        Text("Each line becomes its own Today or Memory item. The full original capture remains attached to all of them.")
                    }
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
                        .disabled(nonemptyParts.count < 2 || requiresRecipientEdit)
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

    private var requiresRecipientEdit: Bool {
        guard let recipientRepairParts else { return false }
        return nonemptyParts.map { SourceUnitLedger($0).words.map(\.text) }
            == recipientRepairParts.map { SourceUnitLedger($0).words.map(\.text) }
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
