import Foundation

// The grounded semantic map: what Apple's model may say about a capture, and
// the deterministic decoding that decides whether it said it well-formed.
//
// Three separate jobs, each its own small generation with its own runtime
// schema, because the one-shot combined contract of Phase B died on a
// cross-array coupling (`things.count == splits.count + 1`, 59 of 85 refused)
// before it could show whether the model segments well. Here no array's length
// depends on another array's length, and no job's output is a string:
//
//   units      where the capture divides into thoughts   split points
//   relations  how those thoughts bear on each other     (kind, from, to)
//   entities   what the named spans are                   (first, last, kind)
//
// What the model is never given a field for: user-visible text, names, dates,
// reminder wording, operations, notifications, geofences, stored mutations.
// Every one of those is produced, if at all, by the existing deterministic
// pipeline reading grounded slices of the original transcript.
//
// Decoding refuses a whole job on any malformation and repairs nothing: no
// sorting, clamping, deduplicating or re-pointing. A refused job leaves the
// capture on the deterministic reading for that question and is recorded with
// its reason and with the raw proposal, so "Apple proposed something useful
// that a policy rejected" and "Apple proposed nothing useful" stay separable,
// which Phase B could not do.

// MARK: - Relations

/// How one thought bears on another. The raw values are what the model is
/// offered as `anyOf` choices, so they are written as plain descriptions of a
/// relation rather than as this project's internal vocabulary.
enum UnitRelationKind: String, Codable, CaseIterable, Sendable {
    /// `from` is a later correction that replaces `to`.
    case replaces
    /// `from` takes back `to`: the earlier thought is withdrawn.
    case cancels
    /// `from` is the condition under which `to` should happen.
    case isConditionFor
    /// `from` is quoted or reported content belonging to `to` (the message
    /// body of a "text Sam that...", somebody else's words).
    case isMessageContentOf
    /// `from` gives shared context (a day, a place, a recipient) to `to`.
    case givesContextTo
    /// `from` and `to` are one coherent thought.
    case continues
    /// They are related and the relation is not clear.
    case unclear

    /// Relations that only make sense pointing backwards in time: a correction
    /// or a withdrawal refers to something already said.
    var mustPointBackwards: Bool { self == .replaces || self == .cancels }

    /// Relations with no direction. Their order is canonicalised, which loses
    /// nothing, rather than refused.
    var isSymmetric: Bool { self == .continues || self == .unclear }
}

struct UnitRelation: Codable, Equatable, Hashable, Sendable {
    let kind: UnitRelationKind
    let from: Int
    let to: Int
}

// MARK: - Entities

/// Mirrors `EntityKind` in `PersonMention.swift` (PR #117) case for case, so
/// the arbiter compares like with like. Kept as its own type because the model
/// half must not depend on anything but raw values: the decoder maps a model
/// token to this, and the arbiter maps this to `EntityKind` by raw value.
enum EntityEvidenceKind: String, Codable, CaseIterable, Sendable {
    case person
    case organization
    case place
    case topic
    case role
    case unknown
}

struct EntityEvidence: Codable, Equatable, Sendable {
    let span: AtomSpan
    let kind: EntityEvidenceKind
}

// MARK: - Raw proposals, kept verbatim

/// Exactly what the model returned for one job, integers and schema tokens
/// only, retained on refused readings as well as accepted ones.
struct RawUnitsProposal: Codable, Equatable, Sendable {
    var splitsAfter: [Int]
}

struct RawRelationsProposal: Codable, Equatable, Sendable {
    struct Link: Codable, Equatable, Sendable {
        var kind: String
        var from: Int
        var to: Int
    }
    var links: [Link]
}

struct RawEntitiesProposal: Codable, Equatable, Sendable {
    struct Span: Codable, Equatable, Sendable {
        var first: Int
        var last: Int
        var kind: String
    }
    var spans: [Span]
}

// MARK: - Refusals

/// Why a job's output was refused whole. One case per rule, so a refusal names
/// the rule that fired. The `framework*` cases would mean Apple generated a
/// value outside a bound its own schema declared; they are kept apart because
/// that is a finding about the framework, not about the model's judgement.
enum JobRefusal: String, Codable, Equatable, Sendable {
    // units
    case frameworkSplitOutOfBounds
    case splitAfterFinalAtom
    case splitsNotStrictlyIncreasing
    case duplicateSplit
    case frameworkTooManySplits
    // relations
    case frameworkUnitOutOfBounds
    case unknownRelationToken
    case selfRelation
    case relationPointsForward
    case duplicateRelation
    case frameworkTooManyRelations
    // entities
    case frameworkAtomOutOfBounds
    case unknownEntityToken
    case entityEndsBeforeItStarts
    case overlappingEntities
    case frameworkTooManyEntities
}

// MARK: - Decoding

enum SemanticDecoding {

    static func units(_ raw: RawUnitsProposal, atomCount: Int) -> Result<[AtomSpan], JobRefusal> {
        guard raw.splitsAfter.count <= Atoms.splitCap(atomCount: atomCount) else {
            return .failure(.frameworkTooManySplits)
        }
        var previous = -1
        for split in raw.splitsAfter {
            guard split >= 0, split < atomCount else { return .failure(.frameworkSplitOutOfBounds) }
            guard split != atomCount - 1 else { return .failure(.splitAfterFinalAtom) }
            guard split != previous else { return .failure(.duplicateSplit) }
            guard split > previous else { return .failure(.splitsNotStrictlyIncreasing) }
            previous = split
        }
        return .success(Atoms.units(atomCount: atomCount, splitsAfter: raw.splitsAfter))
    }

    static func relationCap(unitCount: Int) -> Int { min(12, max(0, 2 * unitCount)) }

    static func relations(_ raw: RawRelationsProposal, unitCount: Int) -> Result<[UnitRelation], JobRefusal> {
        guard raw.links.count <= relationCap(unitCount: unitCount) else {
            return .failure(.frameworkTooManyRelations)
        }
        var seen = Set<UnitRelation>()
        var decoded: [UnitRelation] = []
        for link in raw.links {
            guard let kind = UnitRelationKind(rawValue: link.kind) else { return .failure(.unknownRelationToken) }
            guard (0 ..< unitCount).contains(link.from), (0 ..< unitCount).contains(link.to) else {
                return .failure(.frameworkUnitOutOfBounds)
            }
            guard link.from != link.to else { return .failure(.selfRelation) }
            if kind.mustPointBackwards, link.from < link.to { return .failure(.relationPointsForward) }
            let relation = kind.isSymmetric
                ? UnitRelation(kind: kind, from: max(link.from, link.to), to: min(link.from, link.to))
                : UnitRelation(kind: kind, from: link.from, to: link.to)
            guard seen.insert(relation).inserted else { return .failure(.duplicateRelation) }
            decoded.append(relation)
        }
        return .success(decoded)
    }

    static func entityCap(atomCount: Int) -> Int { min(12, max(0, atomCount)) }

    static func entities(_ raw: RawEntitiesProposal, atomCount: Int) -> Result<[EntityEvidence], JobRefusal> {
        guard raw.spans.count <= entityCap(atomCount: atomCount) else {
            return .failure(.frameworkTooManyEntities)
        }
        var decoded: [EntityEvidence] = []
        for item in raw.spans {
            guard let kind = EntityEvidenceKind(rawValue: item.kind) else { return .failure(.unknownEntityToken) }
            guard (0 ..< atomCount).contains(item.first), (0 ..< atomCount).contains(item.last) else {
                return .failure(.frameworkAtomOutOfBounds)
            }
            guard let span = AtomSpan(first: item.first, last: item.last) else {
                return .failure(.entityEndsBeforeItStarts)
            }
            // Overlap covers exact duplicates too: two readings of the same
            // words are two answers, and picking one is repair.
            guard !decoded.contains(where: { $0.span.overlaps(span) }) else {
                return .failure(.overlappingEntities)
            }
            decoded.append(EntityEvidence(span: span, kind: kind))
        }
        return .success(decoded)
    }
}

// MARK: - The map, and how each job went

/// Why a job did not produce an accepted reading. Distinct from a refusal: a
/// job that never ran says nothing about the model.
enum JobSkip: String, Codable, Equatable, Sendable {
    case notRequested
    case routerDeclined
    case tooShortToSplit
    case needsAtLeastTwoUnits
    case modelUnavailable
    case osTooOld
    case frameworkMissing
}

/// One job's full record: what it cost, what came back, what was decided.
struct JobRecord: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Equatable, Sendable {
        case skipped
        case generationFailed
        case refused
        case accepted
    }

    var outcome: Outcome
    var skip: JobSkip?
    /// The `GenerationError` case name, never its description: the case name
    /// is content-free and the description may not be.
    var generationError: String?
    var refusal: JobRefusal?
    var latencyMilliseconds: Int?
    /// Apple's own count for the prompt text this job sent, from
    /// `SystemLanguageModel.tokenCount(for:)` (iOS/macOS 26.4+). Nil when the
    /// API is unavailable, never estimated from characters.
    var promptTokens: Int?
    var instructionTokens: Int?
    var schemaTokens: Int?
    var contextSize: Int?
    var rawUnits: RawUnitsProposal?
    var rawRelations: RawRelationsProposal?
    var rawEntities: RawEntitiesProposal?

    static func skipped(_ reason: JobSkip) -> JobRecord {
        JobRecord(outcome: .skipped, skip: reason)
    }
}

/// Where the units the relations job was asked about came from. Recorded
/// because a relation measured over the parser's rows answers a different
/// question from one measured over the model's own units.
enum UnitSource: String, Codable, Equatable, Sendable {
    case model
    case rules
    case wholeCapture
}

struct SemanticMap: Codable, Equatable, Sendable {
    var atomCount: Int
    var units: [AtomSpan]?
    var unitSource: UnitSource
    var relations: [UnitRelation]?
    var entities: [EntityEvidence]?
    var unitsJob: JobRecord
    var relationsJob: JobRecord
    var entitiesJob: JobRecord
}
