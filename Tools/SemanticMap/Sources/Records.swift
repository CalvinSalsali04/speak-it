import Foundation

// What one run writes per capture. Two kinds of record, kept apart on purpose:
//
//   CensusRecord   content-free: an id, counts and closed-vocabulary reasons.
//                  Safe to paste into a thread or a pull request.
//   CaptureRecord  local debug evidence: carries the capture and the model's
//                  raw answer, because replay needs both. It stays on the
//                  machine that made it and is never analytics. `score.py`
//                  reads it and prints only census-shaped output.
//
// Every record carries the commit and the settings that produced it, so two
// runs are compared only when they are comparable, and a run whose rules
// reading no longer matches the current tree says so on replay.

struct RunSettings: Codable, Equatable, Sendable {
    var commit: String
    var treeDirty: Bool
    var operatingSystem: String
    var locale: String
    var timeZone: String
    /// The frame every date is resolved in: `rowreport.swift`'s fixed
    /// 2026-08-03 10:00 America/Toronto, so reports are comparable with every
    /// other host-side tool. Not named `referenceDate`: inside `current` that
    /// name would resolve to this property rather than the shared global.
    var frame: String
    var atomFormat: AtomFormat
    /// Production's model was asked about ineligible captures too.
    var shadow: Bool
    /// The three semantic-map jobs ran.
    var jobs: Bool
    var unitsPromptFingerprint: String
    var relationsPromptFingerprint: String
    var entitiesPromptFingerprint: String
    var productionInstructionsFingerprint: String

    static func current(atomFormat: AtomFormat, shadow: Bool, jobs: Bool) -> RunSettings {
        RunSettings(
            commit: buildCommit,
            treeDirty: buildTreeDirty,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            frame: ISO8601DateFormatter().string(from: referenceDate),
            atomFormat: atomFormat,
            shadow: shadow,
            jobs: jobs,
            unitsPromptFingerprint: SemanticJobPrompts.unitsFingerprint,
            relationsPromptFingerprint: SemanticJobPrompts.relationsFingerprint,
            entitiesPromptFingerprint: SemanticJobPrompts.entitiesFingerprint,
            productionInstructionsFingerprint: SemanticJobPrompts.fingerprint(of: ProductionRefinementPrompt.instructions)
        )
    }
}

struct CensusRecord: Codable, Equatable, Sendable {
    var id: String?
    var commit: String
    var features: ComplexityFeatures
    var policy: RoutePolicyReason
    var shouldRefine: Bool
    var policyDrift: Bool
    var rulesDigest: String
}

struct CaptureRecord: Codable, Equatable, Sendable {
    var id: String?
    var utterance: String
    var settings: RunSettings
    var features: ComplexityFeatures
    /// Fingerprint of the rules reading at run time. Replay recomputes the
    /// rules on the current tree; a different digest means the deterministic
    /// half changed since the run, which is the point of replaying, and is
    /// counted rather than hidden.
    var rulesDigest: String
    var production: ProductionTrace
    var map: SemanticMap?
    /// The standard policy's decisions at run time. Replay recomputes them for
    /// whatever policy it is given.
    var decisions: [ArbitrationDecision]
    var mapChangedOutput: Bool
}

enum RulesDigest {
    /// Content-derived but not content-revealing: FNV-1a over every field a
    /// scorer reads. Equal digests mean the scorers would see the same rows.
    static func of(_ items: [ExtractedThought], _ operations: [CaptureOperationRequest]) -> String {
        var parts: [String] = operations.map { "op|\($0.operation.rawValue)|\($0.target ?? "")|\($0.isScoped)" }
        for item in items {
            let organization = item.organization
            parts.append([
                item.sourceQuote,
                organization.itemType.rawValue,
                organization.category.rawValue,
                organization.personName ?? "",
                organization.dueDate.map { String($0.timeIntervalSince1970) } ?? "",
                organization.reminderDate.map { String($0.timeIntervalSince1970) } ?? "",
                organization.reminderDelivery.rawValue,
                organization.recurrenceRule.map { "\($0)" } ?? "",
                organization.locationIntent.map { "\($0)" } ?? "",
                organization.state.kind.rawValue,
                String(item.needsReview),
            ].joined(separator: "|"))
        }
        return SemanticJobPrompts.fingerprint(of: parts.joined(separator: "\n"))
    }
}

// MARK: - Input and output

/// One input line. A bare line is the capture; `id<TAB>capture` names it, which
/// is the form for any set whose text must not appear in a report. Same rules
/// as `Tools/InterpretationProbe`, including refusing a multi-column corpus
/// TSV rather than handing its label columns to a model as speech.
struct Input: Sendable {
    var id: String?
    var text: String
}

func readInputs(fromPath path: String) -> [Input] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write(Data("semantic-map: cannot read \(path)\n".utf8))
        exit(2)
    }
    var inputs: [Input] = []
    for (offset, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }
        let fields = line.components(separatedBy: "\t")
        switch fields.count {
        case 1:
            inputs.append(Input(id: nil, text: line))
        case 2:
            let id = fields[0].trimmingCharacters(in: .whitespaces)
            let body = fields[1].trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !body.isEmpty else {
                refuseInput(path: path, line: offset + 1, saying: "an id line needs an id and a capture on either side of the tab")
            }
            inputs.append(Input(id: id, text: body))
        default:
            refuseInput(
                path: path, line: offset + 1,
                saying: "\(fields.count) tab-separated fields; cut a corpus TSV down to `id<TAB>capture` first"
            )
        }
    }
    return inputs
}

/// Refuses by line number without echoing the line, which may be sealed.
func refuseInput(path: String, line: Int, saying reason: String) -> Never {
    FileHandle.standardError.write(Data("semantic-map: \(path):\(line): \(reason)\n".utf8))
    exit(2)
}

func readRecords<Record: Decodable>(_ type: Record.Type, fromPath path: String) -> [Record] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write(Data("semantic-map: cannot read \(path)\n".utf8))
        exit(2)
    }
    let decoder = JSONDecoder()
    var records: [Record] = []
    var unreadable = 0
    for line in text.split(separator: "\n") where !line.isEmpty {
        if let record = try? decoder.decode(Record.self, from: Data(line.utf8)) {
            records.append(record)
        } else {
            unreadable += 1
        }
    }
    // A record that no longer decodes is a schema change, not an empty
    // capture. Counted loudly, never skipped silently.
    if unreadable > 0 {
        FileHandle.standardError.write(Data("semantic-map: \(unreadable) unreadable line(s) in \(path)\n".utf8))
    }
    return records
}

let recordEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}()

func jsonLine<Value: Encodable>(_ value: Value) -> String? {
    guard let data = try? recordEncoder.encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

func writeLines(_ lines: [String], to path: String?) {
    let output = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    if let path {
        do {
            try output.write(toFile: path, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("semantic-map: wrote \(lines.count) records to \(path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("semantic-map: cannot write \(path)\n".utf8))
            exit(2)
        }
    } else {
        print(output, terminator: "")
    }
}
