import Foundation
import SwiftUI

struct SpeechCorrection: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var heardPhrase: String
    var preferredPhrase: String

    init(
        id: UUID = UUID(),
        heardPhrase: String,
        preferredPhrase: String
    ) {
        self.id = id
        self.heardPhrase = heardPhrase
        self.preferredPhrase = preferredPhrase
    }
}

enum SpeechVocabularyStore {
    private static let storageKey = "SpeakIt.speechCorrections"
    private static let maximumEntries = 60

    static var corrections: [SpeechCorrection] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SpeechCorrection].self, from: data) else {
            return []
        }
        return Array(decoded.prefix(maximumEntries))
    }

    static var contextualPhrases: [String] {
        corrections.flatMap { [$0.heardPhrase, $0.preferredPhrase] }
    }

    static func save(_ corrections: [SpeechCorrection]) {
        let normalized = corrections
            .compactMap(normalize)
            .reduce(into: [SpeechCorrection]()) { result, correction in
                let alreadyExists = result.contains {
                    $0.heardPhrase.compare(
                        correction.heardPhrase,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) == .orderedSame
                }
                if !alreadyExists { result.append(correction) }
            }
        guard !normalized.isEmpty else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(Array(normalized.prefix(maximumEntries))) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func apply(to transcript: String) -> String {
        corrections
            .sorted { $0.heardPhrase.count > $1.heardPhrase.count }
            .reduce(transcript) { result, correction in
                replaceWholePhrase(in: result, using: correction)
            }
    }

    private static func replaceWholePhrase(
        in transcript: String,
        using correction: SpeechCorrection
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: correction.heardPhrase)
        let pattern = "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return transcript
        }

        let mutable = NSMutableString(string: transcript)
        let matches = expression.matches(
            in: transcript,
            range: NSRange(location: 0, length: (transcript as NSString).length)
        )
        for match in matches.reversed() {
            mutable.replaceCharacters(in: match.range, with: correction.preferredPhrase)
        }
        return mutable as String
    }

    private static func normalize(_ correction: SpeechCorrection) -> SpeechCorrection? {
        let heard = correction.heardPhrase
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = correction.preferredPhrase
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard heard.count >= 2,
              preferred.count >= 2,
              heard.count <= 80,
              preferred.count <= 80 else {
            return nil
        }
        return SpeechCorrection(
            id: correction.id,
            heardPhrase: heard,
            preferredPhrase: preferred
        )
    }
}

struct SpeechVocabularyView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var corrections = SpeechVocabularyStore.corrections
    @State private var showsAddCorrection = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if corrections.isEmpty {
                        ContentUnavailableView {
                            Label("No corrections yet", systemImage: "textformat.abc")
                        } description: {
                            Text("Teach Speak It a name or phrase once and it will use your preferred spelling in future captures.")
                        }
                    } else {
                        ForEach(corrections) { correction in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(correction.preferredPhrase)
                                    .font(.body.weight(.medium))
                                Text("When it hears “\(correction.heardPhrase)”")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                        .onDelete(perform: delete)
                    }
                } footer: {
                    Text("Corrections stay on this iPhone and are applied before a thought is organized.")
                }
            }
            .navigationTitle("Names & phrases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsAddCorrection = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add speech correction")
                }
            }
            .sheet(isPresented: $showsAddCorrection) {
                AddSpeechCorrectionView { correction in
                    corrections.append(correction)
                    persist()
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        corrections.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        SpeechVocabularyStore.save(corrections)
        corrections = SpeechVocabularyStore.corrections
    }
}

private struct AddSpeechCorrectionView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (SpeechCorrection) -> Void

    @State private var heardPhrase = ""
    @State private var preferredPhrase = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case heard
        case preferred
    }

    private var canSave: Bool {
        heardPhrase.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
            preferredPhrase.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What Speak It hears", text: $heardPhrase)
                        .focused($focusedField, equals: .heard)
                    TextField("What it should write", text: $preferredPhrase)
                        .focused($focusedField, equals: .preferred)
                } header: {
                    Text("Correction")
                } footer: {
                    Text("Example: “calvin walk” → “Calvin Wak”")
                }
            }
            .navigationTitle("Add correction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .task { focusedField = .heard }
        }
    }

    private func save() {
        onSave(
            SpeechCorrection(
                heardPhrase: heardPhrase,
                preferredPhrase: preferredPhrase
            )
        )
        dismiss()
    }
}
