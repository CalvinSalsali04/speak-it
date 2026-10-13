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
    private static let learnedPhrasesKey = "SpeakIt.learnedSpeechContext"
    private static let confirmedPhrasesKey = "SpeakIt.confirmedSpeechContext"
    private static let maximumEntries = 60
    private static let maximumLearnedPhrases = 80
    private static let maximumRecognitionPhrases = 100

    static var corrections: [SpeechCorrection] { corrections(in: .standard) }

    private static func corrections(in defaults: UserDefaults) -> [SpeechCorrection] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SpeechCorrection].self, from: data) else {
            return []
        }
        return Array(decoded.prefix(maximumEntries))
    }

    static var contextualPhrases: [String] {
        recognitionContext()
    }

    static func recognitionContext(additional: [String] = [], defaults: UserDefaults = .standard) -> [String] {
        let ranked = uniquePhrases(
            additional
                // A correction means the heard form is known-wrong. Boosting
                // it alongside the preferred form teaches the recognizer both
                // spellings and can increase the very error the person fixed.
                + corrections(in: defaults).map(\.preferredPhrase)
                + confirmedRecognitionPhrases(in: defaults)
                + learnedPhrases(in: defaults)
        )
        // Apple's contextual-strings contract accepts at most 100 phrases in
        // total. Screen-specific phrases rank first, followed by explicit user
        // corrections, confirmed hints and then names learned from captures.
        return Array(ranked.prefix(maximumRecognitionPhrases))
    }

    static func rememberContextualPhrases(_ phrases: [String], defaults: UserDefaults = .standard) {
        let merged = uniquePhrases(phrases + learnedPhrases(in: defaults))
        let retained = Array(merged.prefix(maximumLearnedPhrases))
        if retained.isEmpty {
            defaults.removeObject(forKey: learnedPhrasesKey)
        } else {
            defaults.set(retained, forKey: learnedPhrasesKey)
        }
    }

    static func clearLearnedContextualPhrases(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: learnedPhrasesKey)
    }

    static func confirmedRecognitionPhrases(in defaults: UserDefaults = .standard) -> [String] {
        Array(uniquePhrases((defaults.stringArray(forKey: confirmedPhrasesKey) ?? [])
            .compactMap(normalizedRecognitionHint)).prefix(maximumLearnedPhrases))
    }

    /// Hints bias recognition only. They never supply transcript replacements.
    @discardableResult
    static func confirmRecognitionPhrase(_ phrase: String, defaults: UserDefaults = .standard) -> Bool {
        guard let value = normalizedRecognitionHint(phrase) else { return false }
        let values = uniquePhrases([value] + confirmedRecognitionPhrases(in: defaults))
        defaults.set(Array(values.prefix(maximumLearnedPhrases)), forKey: confirmedPhrasesKey)
        return true
    }

    static func removeRecognitionPhrase(_ phrase: String, defaults: UserDefaults = .standard) {
        let retained = confirmedRecognitionPhrases(in: defaults).filter { $0 != phrase }
        if retained.isEmpty { defaults.removeObject(forKey: confirmedPhrasesKey) }
        else { defaults.set(retained, forKey: confirmedPhrasesKey) }
    }

    static func clearConfirmedRecognitionPhrases(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: confirmedPhrasesKey)
    }

    static func normalizedRecognitionHint(_ phrase: String) -> String? {
        let value = phrase.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(value.count),
              value.range(of: #"^[\p{L}\p{N}][\p{L}\p{N} '&’/-]*$"#, options: .regularExpression) != nil else { return nil }
        let words = value.lowercased().split(whereSeparator: {
            !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’"
        }).map(String.init)
        // A hint is a name/term, never authority over negation or commands.
        let reserved: Set<String> = ["no", "not", "never", "don't", "don’t", "dont", "do", "cannot", "can't", "can’t",
            "won't", "won’t", "wont", "without", "except", "excluding", "cancel",
            "delete", "remove", "complete", "done", "stop", "yes", "and", "or", "but", "if", "unless", "then"]
        guard words.count <= 6, words.allSatisfy({ !reserved.contains($0) }),
              value.contains(where: \.isLetter) else { return nil }
        return value
    }

    static func save(_ corrections: [SpeechCorrection], defaults: UserDefaults = .standard) {
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
            defaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(Array(normalized.prefix(maximumEntries))) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    static func apply(to transcript: String) -> String {
        apply(corrections, to: transcript)
    }

    static func apply(_ corrections: [SpeechCorrection], to transcript: String) -> String {
        corrections
            .compactMap(normalize)
            .sorted { $0.heardPhrase.count > $1.heardPhrase.count }
            .reduce(transcript) { result, correction in
                replaceWholePhrase(in: result, using: correction)
            }
    }

    private static func learnedPhrases(in defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: learnedPhrasesKey) ?? []
    }

    private static func uniquePhrases(_ phrases: [String]) -> [String] {
        var seen = Set<String>()
        return phrases.compactMap { phrase in
            let normalized = phrase
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.count >= 2, normalized.count <= 80 else { return nil }
            let key = normalized.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
    }

    private static func replaceWholePhrase(
        in transcript: String,
        using correction: SpeechCorrection
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: correction.heardPhrase)
        let pattern = "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
        guard let expression = NSRegularExpression.speakItCached(
            pattern,
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
    @State private var recognitionHints = SpeechVocabularyStore.confirmedRecognitionPhrases()

    var body: some View {
        NavigationStack {
            List {
                if !recognitionHints.isEmpty {
                    Section {
                        ForEach(recognitionHints, id: \.self) { phrase in
                            Text(phrase).accessibilityIdentifier("speechHint." + phrase)
                        }
                        .onDelete { offsets in
                            for index in offsets { SpeechVocabularyStore.removeRecognitionPhrase(recognitionHints[index]) }
                            recognitionHints = SpeechVocabularyStore.confirmedRecognitionPhrases()
                        }
                    } header: { Text("Voice hints") }
                    footer: { Text("These words can influence similar-sounding names. Swipe to remove a hint. Hints stay on this iPhone and never automatically replace words.") }
                }
                Section {
                    if corrections.isEmpty && !recognitionHints.isEmpty {
                        Text("No automatic replacements.")
                            .foregroundStyle(Color.speakMuted)
                    } else if corrections.isEmpty {
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
                } header: {
                    Text("Automatic replacements")
                } footer: {
                    Text("These explicit corrections stay on this iPhone and replace the heard phrase before a thought is organized.")
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


/// Confirmation stays in the item editor until its persistence succeeds.
struct RecognitionHintView: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (String) -> Void
    @State private var phrase = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name or term", text: $phrase)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .accessibilityIdentifier("speechHint.phrase")
                } footer: {
                    Text("Enter one name or term that voice capture misheard. This is a recognition hint, so it can influence similar-sounding words. It stays on this iPhone and can be removed in Settings → Names & phrases. Your original capture stays unchanged.")
                }
                if !phrase.isEmpty, SpeechVocabularyStore.normalizedRecognitionHint(phrase) == nil {
                    Text("Use a short name or term, without commands or negation words.")
                        .foregroundStyle(Color.speakMuted)
                }
            }
            .navigationTitle("Voice hint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use hint") {
                        guard let normalized = SpeechVocabularyStore.normalizedRecognitionHint(phrase) else { return }
                        onConfirm(normalized)
                        dismiss()
                    }
                    .disabled(SpeechVocabularyStore.normalizedRecognitionHint(phrase) == nil)
                    .accessibilityIdentifier("speechHint.confirm")
                }
            }
            .task { isFocused = true }
        }
    }
}
