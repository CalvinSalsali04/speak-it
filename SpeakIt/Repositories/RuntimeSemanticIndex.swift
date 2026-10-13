import Foundation
import NaturalLanguage
import Accelerate

/// A small, immutable routing index over real examples from the full bank.
/// Similarity proposes example families; it never supplies a current fact,
/// destination, operation or permission. The owning library actor must serialize
/// access: Apple's NLEmbedding instances are not safe for concurrent queries.
final class RuntimeSemanticIndex {
    enum Failure: Error, Equatable {
        case assetTooLarge, malformedAsset, incompatibleBank, unsupportedSchema
    }
    struct Prototype: Codable {
        let id: String
        let blueprint: String
        let sourceSHA256: String
        let vector: [Float]
    }
    struct Asset: Codable {
        let schemaVersion: Int
        let bankSHA256: String
        let language: String
        let embeddingRevision: Int
        let dimension: Int
        let normalization: String
        let prototypes: [Prototype]
    }
    private struct Encoder {
        let dimension: Int
        let vector: (String) -> [Double]?
    }
    static let maximumAssetBytes = 20_000_000
    static let maximumPrototypes = 4_096
    static let maximumSourceBytes = 8_192
    private let prototypes: [Prototype]
    private let encoder: Encoder?

    convenience init(indexURL: URL, bankSHA: String) throws {
        try self.init(indexURL: indexURL, bankSHA: bankSHA) { asset in
            // Do not silently use the OS's current revision against vectors
            // produced by a different model revision on the build machine.
            guard asset.language == NLLanguage.english.rawValue,
                  NLEmbedding.supportedSentenceEmbeddingRevisions(for: .english).contains(asset.embeddingRevision),
                  let model = NLEmbedding.sentenceEmbedding(for: .english, revision: asset.embeddingRevision),
                  model.revision == asset.embeddingRevision,
                  model.dimension == asset.dimension else { return nil }
            return Encoder(dimension: model.dimension, vector: { source in
                asset.schemaVersion == 2
                    ? Self.chunkedVector(source,dimension:model.dimension,encode:{model.vector(for:$0)})
                    : model.vector(for:source)
            })
        }
    }

    private init(indexURL: URL, bankSHA: String, provider: (Asset) -> Encoder?) throws {
        let file = try FileHandle(forReadingFrom: indexURL)
        defer { try? file.close() }
        guard let bytes = try file.read(upToCount: Self.maximumAssetBytes + 1),
              bytes.count <= Self.maximumAssetBytes else { throw Failure.assetTooLarge }
        let asset: Asset
        do { asset = try JSONDecoder().decode(Asset.self, from: bytes) }
        catch { throw Failure.malformedAsset }
        guard asset.schemaVersion == 1 || asset.schemaVersion == 2 else { throw Failure.unsupportedSchema }
        guard Self.isDigest(bankSHA), asset.bankSHA256 == bankSHA else { throw Failure.incompatibleBank }
        guard asset.language == "en", asset.embeddingRevision > 0,
              asset.dimension > 0, asset.dimension <= 2_048,
              asset.normalization == (asset.schemaVersion == 2 ? "l2-float32-token384-mean-v2" : "l2-float32-v1"),
              !asset.prototypes.isEmpty, asset.prototypes.count <= Self.maximumPrototypes else {
            throw Failure.malformedAsset
        }
        var ids = Set<String>()
        var familyCounts: [String: Int] = [:]
        for row in asset.prototypes {
            guard !Task.isCancelled else { throw CancellationError() }
            guard !row.id.isEmpty, row.id.utf8.count <= 128,
                  !row.blueprint.isEmpty, row.blueprint.utf8.count <= 128,
                  Self.isDigest(row.sourceSHA256), ids.insert(row.id).inserted,
                  row.vector.count == asset.dimension, row.vector.allSatisfy(\.isFinite) else {
                throw Failure.malformedAsset
            }
            let norm = row.vector.reduce(0.0) { $0 + Double($1) * Double($1) }
            guard norm.isFinite, abs(norm - 1) <= 0.005 else { throw Failure.malformedAsset }
            familyCounts[row.blueprint, default: 0] += 1
            guard familyCounts[row.blueprint, default: 0] <= 16 else { throw Failure.malformedAsset }
        }
        prototypes = asset.prototypes
        encoder = provider(asset)
    }

    /// nil declines semantic routing; the caller keeps the complete lexical
    /// search. Results are identifiers and similarities, never interpreted acts.
    func ranked(source: String, excludedBlueprints: Set<String>, excludedIDs: Set<String> = [], limit: Int)
        -> [(id: String, blueprint: String, score: Double)]? {
        scored(source: source, excludedBlueprints: excludedBlueprints, excludedIDs: excludedIDs,
               limit: limit, collapseBlueprints: true)
    }

    /// The store needs alternative prototypes until its complete payload
    /// approval/alias guards admit a family. Similarity alone cannot admit it.
    func rankedPrototypes(source: String, excludedBlueprints: Set<String>, excludedIDs: Set<String> = [])
        -> [(id: String, blueprint: String, score: Double)]? {
        scored(source: source, excludedBlueprints: excludedBlueprints, excludedIDs: excludedIDs,
               limit: Self.maximumPrototypes, collapseBlueprints: false)
    }

    private func scored(source: String, excludedBlueprints: Set<String>, excludedIDs: Set<String>,
                        limit: Int, collapseBlueprints: Bool)
        -> [(id: String, blueprint: String, score: Double)]? {
        guard !Task.isCancelled, source.utf8.count <= Self.maximumSourceBytes,
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let encoder else { return nil }
        guard limit > 0 else { return [] }
#if DEBUG
        let encodingStart = ProcessInfo.processInfo.systemUptime
#endif
        guard let raw = encoder.vector(source), raw.count == encoder.dimension,
              let vector = Self.normalized(raw), !Task.isCancelled else { return nil }
#if DEBUG
        RuntimeExampleLibrary.developmentObserver?("reference semantic-phase=encode seconds=\(ProcessInfo.processInfo.systemUptime - encodingStart)")
#endif
        var winners: [String: (id: String, blueprint: String, score: Double)] = [:]
        var candidates: [(id: String, blueprint: String, score: Double)] = []
        for (offset, row) in prototypes.enumerated()
            where !excludedBlueprints.contains(row.blueprint) && !excludedIDs.contains(row.id) {
            if offset % 32 == 0, Task.isCancelled { return nil }
            var dot: Float = 0
            vDSP_dotpr(row.vector, 1, vector, 1, &dot, vDSP_Length(vector.count))
            guard dot.isFinite else { return nil }
            let value = (id: row.id, blueprint: row.blueprint, score: min(1, max(-1, Double(dot))))
            if !collapseBlueprints {
                candidates.append(value)
                continue
            }
            if let existing = winners[row.blueprint],
               existing.score > value.score || (existing.score == value.score && existing.id < value.id) {
                continue
            }
            winners[row.blueprint] = value
        }
        guard !Task.isCancelled else { return nil }
        if collapseBlueprints { candidates = Array(winners.values) }
        return Array(candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.blueprint != $1.blueprint { return $0.blueprint < $1.blueprint }
            return $0.id < $1.id
        }.prefix(min(limit, Self.maximumPrototypes)))
    }

    static func normalized(_ values: [Double]) -> [Float]? {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else { return nil }
        let squared = values.reduce(0.0) { $0 + $1 * $1 }
        guard squared.isFinite, squared > 0 else { return nil }
        let divisor = sqrt(squared)
        let result = values.map { Float($0 / divisor) }
        guard result.allSatisfy(\.isFinite) else { return nil }
        return result
    }
    /// Bounded, complete lexical coverage for optional semantic routing. Every
    /// whitespace-delimited source token is encoded exactly once, in order.
    /// This does not shorten the capture used by interpretation or persistence.
    static func chunkedVector(_ source:String,dimension:Int,encode:(String)->[Double]?)->[Double]? {
        guard !Task.isCancelled,source.utf8.count <= maximumSourceBytes,dimension > 0 else { return nil }
        let tokens=source.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        guard !tokens.isEmpty else { return nil }
        var chunks:[([String],Int)]=[]
        var words:[String]=[],bytes=0
        for token in tokens {
            let length=token.utf8.count
            guard length <= 384 else { return nil }
            if !words.isEmpty,bytes+1+length > 384 {
                chunks.append((words,words.count));words=[];bytes=0
            }
            bytes += (words.isEmpty ? 0 : 1)+length;words.append(token)
        }
        if !words.isEmpty { chunks.append((words,words.count)) }
        var mean=Array(repeating:0.0,count:dimension)
        for (words,weight) in chunks {
            guard !Task.isCancelled,let raw=encode(words.joined(separator:" ")),raw.count == dimension,
                  let unit=normalized(raw) else { return nil }
            for i in mean.indices { mean[i] += Double(unit[i])*Double(weight) }
        }
        guard !Task.isCancelled,let vector=normalized(mean) else { return nil }
        return vector.map(Double.init)
    }
    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

#if DEBUG
    struct TestEncoder {
        let language: String
        let revision: Int
        let dimension: Int
        let vector: (String) -> [Double]?
    }
    convenience init(indexURL: URL, bankSHA: String, testEncoder: TestEncoder?) throws {
        try self.init(indexURL: indexURL, bankSHA: bankSHA) { asset in
            guard let supplied = testEncoder, supplied.language == asset.language,
                  supplied.revision == asset.embeddingRevision,
                  supplied.dimension == asset.dimension else { return nil }
            return Encoder(dimension: supplied.dimension, vector: { source in
                asset.schemaVersion == 2
                    ? Self.chunkedVector(source, dimension: supplied.dimension, encode: supplied.vector)
                    : supplied.vector(source)
            })
        }
    }
#endif
}
