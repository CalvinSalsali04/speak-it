import Foundation

// Deterministic checks that need no model: decoding refuses what it must, the
// arbiter can only take capability away, production's policy is decomposed
// without drift, and records survive a round trip. Runs in the `language` CI
// job after the build, which is dispatch-only (`ci.yml`), so treat it as
// dispatch coverage rather than per-PR coverage.
//
// Where a check depends on what the parser does with a sentence, it is written
// as an invariant over whatever the parser returned ("nothing executable was
// created"), never as an expected row, so a legitimate parser change cannot
// turn it red and an illegitimate arbiter change cannot keep it green.

enum SelfCheck {
    static var failures: [String] = []

    static func expect(_ condition: Bool, _ what: String) {
        if !condition { failures.append(what) }
    }

    static func thought(
        _ quote: String,
        type: ItemType = .note,
        reminder: Date? = nil,
        person: String? = nil,
        review: Bool = false,
        state: SemanticState = .resolved
    ) -> ExtractedThought {
        ExtractedThought(
            sourceQuote: quote,
            rawQuote: quote,
            wasRepaired: false,
            analysisText: quote,
            suggestedTitle: nil,
            organization: OrganizedThought(
                itemType: type,
                category: person == nil ? .general : .people,
                priority: .normal,
                personName: person,
                dueDate: nil,
                reminderDate: reminder,
                reminderDelivery: reminder == nil ? .none : .notification,
                recurrenceRule: nil,
                needsClarification: review,
                state: state
            ),
            confidence: 1,
            needsReview: review
        )
    }

    static func map(
        atoms: Int,
        units: [AtomSpan]?,
        source: UnitSource = .model,
        relations: [UnitRelation]? = nil,
        entities: [EntityEvidence]? = nil
    ) -> SemanticMap {
        SemanticMap(
            atomCount: atoms, units: units, unitSource: source, relations: relations, entities: entities,
            unitsJob: JobRecord(outcome: units == nil ? .skipped : .accepted),
            relationsJob: JobRecord(outcome: relations == nil ? .skipped : .accepted),
            entitiesJob: JobRecord(outcome: entities == nil ? .skipped : .accepted)
        )
    }

    static func span(_ first: Int, _ last: Int) -> AtomSpan { AtomSpan(first: first, last: last)! }

    static func run() -> Bool {
        atoms()
        decoding()
        arbiter()
        productionPolicy()
        fingerprints()
        records()
        if failures.isEmpty {
            print("semantic-map selfcheck ok")
            return true
        }
        for failure in failures { print("semantic-map selfcheck FAILED: \(failure)") }
        return false
    }

    // MARK: Atoms

    static func atoms() {
        let text = "  call   the dentist, then\tbuy milk "
        let atoms = Atoms.atomize(text)
        expect(atoms.count == 6, "whitespace runs of any kind separate atoms")
        expect(Atoms.slice(text, atoms, span(0, 2)) == "call   the dentist,", "a slice is the original text, spacing and punctuation kept")
        expect(Atoms.slice(text, atoms, span(4, 6)) == nil, "a span past the capture slices to nothing")
        expect(Atoms.unitCap(atomCount: 1) == 1 && Atoms.unitCap(atomCount: 3) == 2
               && Atoms.unitCap(atomCount: 30) == 12 && Atoms.unitCap(atomCount: 0) == 1,
               "the unit cap is min(12, max(1, ceil(n/2)))")
        expect(Atoms.units(atomCount: 6, splitsAfter: [2]) == [span(0, 2), span(3, 5)], "units cover every atom")
        expect(RowLocator.span(of: "Then buy milk.", in: text, atoms: atoms) == span(3, 5),
               "a row is located through case and punctuation differences")
        expect(RowLocator.spans(of: ["buy milk", "call the dentist"], in: text, atoms: atoms) == [span(4, 5), span(0, 2)],
               "rows are located whatever order the parser returned them in")
        expect(RowLocator.spans(of: ["call the dentist", "walk the dog"], in: text, atoms: atoms) == nil,
               "a row that is not in the capture makes the segmentation incomparable")
        expect(RowLocator.spans(of: ["the dentist", "call the dentist"], in: text, atoms: atoms) == nil,
               "two rows claiming the same words are refused")
    }

    // MARK: Decoding

    static func decoding() {
        func units(_ splits: [Int], _ n: Int) -> JobRefusal? {
            if case let .failure(refusal) = SemanticDecoding.units(RawUnitsProposal(splitsAfter: splits), atomCount: n) {
                return refusal
            }
            return nil
        }
        expect(units([2, 5], 10) == nil, "increasing splits inside the capture are accepted")
        expect(units([], 10) == nil, "no split is one thought, and is accepted")
        expect(units([9], 10) == .splitAfterFinalAtom, "a split after the last atom is refused")
        expect(units([5, 5], 10) == .duplicateSplit, "a repeated split is refused, not deduplicated")
        expect(units([5, 2], 10) == .splitsNotStrictlyIncreasing, "out-of-order splits are refused, not sorted")
        expect(units([10], 10) == .frameworkSplitOutOfBounds, "an atom id outside the capture is a framework finding")
        expect(units([0, 1, 2], 4) == .frameworkTooManySplits, "more splits than the cap is a framework finding")

        func relations(_ links: [(String, Int, Int)], _ n: Int) -> Result<[UnitRelation], JobRefusal> {
            SemanticDecoding.relations(
                RawRelationsProposal(links: links.map { .init(kind: $0.0, from: $0.1, to: $0.2) }), unitCount: n
            )
        }
        expect((try? relations([("replaces", 1, 0)], 2).get()) == [UnitRelation(kind: .replaces, from: 1, to: 0)],
               "a correction pointing back is accepted")
        if case .failure(.relationPointsForward) = relations([("cancels", 0, 1)], 2) {} else {
            failures.append("a withdrawal of something not yet said is refused")
        }
        expect((try? relations([("continues", 0, 1)], 2).get()) == [UnitRelation(kind: .continues, from: 1, to: 0)],
               "a symmetric relation is canonicalised, which loses nothing")
        if case .failure(.duplicateRelation) = relations([("continues", 0, 1), ("continues", 1, 0)], 2) {} else {
            failures.append("the same symmetric relation twice is a duplicate")
        }
        if case .failure(.selfRelation) = relations([("givesContextTo", 1, 1)], 2) {} else {
            failures.append("a thought related to itself is refused")
        }
        if case .failure(.unknownRelationToken) = relations([("causes", 1, 0)], 2) {} else {
            failures.append("a relation outside the vocabulary is refused")
        }

        func entities(_ spans: [(Int, Int, String)], _ n: Int) -> Result<[EntityEvidence], JobRefusal> {
            SemanticDecoding.entities(
                RawEntitiesProposal(spans: spans.map { .init(first: $0.0, last: $0.1, kind: $0.2) }), atomCount: n
            )
        }
        expect((try? entities([(1, 2, "organization"), (4, 4, "person")], 6).get())?.count == 2,
               "disjoint entities are accepted")
        if case .failure(.overlappingEntities) = entities([(1, 2, "organization"), (2, 3, "person")], 6) {} else {
            failures.append("two readings of the same words are refused, not picked between")
        }
        if case .failure(.entityEndsBeforeItStarts) = entities([(3, 1, "place")], 6) {} else {
            failures.append("an entity that ends before it starts is refused")
        }
        if case .failure(.unknownEntityToken) = entities([(1, 1, "brand")], 6) {} else {
            failures.append("an entity kind outside the vocabulary is refused")
        }
    }

    // MARK: Arbiter

    static func arbiter() {
        let reminder = calendar.date(byAdding: .hour, value: 5, to: referenceDate)!

        // No map: the rules reading, untouched.
        let lone = [thought("buy milk", type: .shopping)]
        let untouched = Arbiter.arbitrate(
            transcript: "buy milk", rules: (lone, []), map: nil, referenceDate: referenceDate, calendar: calendar
        )
        expect(untouched.items == lone && !untouched.mapChangedOutput, "with no map the rules reading is the answer")
        expect(untouched.decisions.first?.reason == .noMap, "the missing map is recorded")

        // A withdrawal the rules missed: execution is taken away, nothing added.
        let withdrawal = "remind me to call the bank at three actually never mind that"
        let rows = [thought("remind me to call the bank at three", type: .task, reminder: reminder),
                    thought("actually never mind that")]
        let withdrawMap = map(
            atoms: 12, units: [span(0, 7), span(8, 11)],
            relations: [UnitRelation(kind: .cancels, from: 1, to: 0)]
        )
        let withdrawn = Arbiter.arbitrate(
            transcript: withdrawal, rules: (rows, []), map: withdrawMap, referenceDate: referenceDate, calendar: calendar
        )
        expect(withdrawn.items.first?.organization.reminderDate == nil, "a withdrawn row loses its reminder")
        expect(withdrawn.items.first?.needsReview == true, "a withdrawn row is shown for review, not deleted")
        expect(withdrawn.items.count == rows.count, "withdrawal never deletes a row")
        expect(withdrawn.decisions.contains { $0.reason == .withdrawnRowStillExecutes && $0.effect == .withdrewExecution },
               "the withdrawal is recorded with its reason")
        let observed = Arbiter.arbitrate(
            transcript: withdrawal, rules: (rows, []), map: withdrawMap, policy: .observeOnly,
            referenceDate: referenceDate, calendar: calendar
        )
        expect(observed.items == rows && !observed.mapChangedOutput, "the observe-only policy changes nothing")

        // A capture with an operation belongs to the rules.
        let operation = CaptureOperationRequest(
            operation: .cancel, target: "the bank call", sourceQuote: "cancel the bank call", needsReview: false
        )
        let owned = Arbiter.arbitrate(
            transcript: withdrawal, rules: (rows, [operation]), map: withdrawMap,
            referenceDate: referenceDate, calendar: calendar
        )
        expect(owned.items == rows && owned.operations == [operation], "an operation capture is not arbitrated")
        expect(owned.decisions.contains { $0.reason == .operationOwnedByRules }, "and says why")

        // A cut inside quotation is a safety conflict, refused before anything is read.
        let quoted = "he said \"buy milk and call mom\" yesterday"
        let quotedRow = [thought(quoted)]
        let quotedCut = Arbiter.arbitrate(
            transcript: quoted, rules: (quotedRow, []), map: map(atoms: 8, units: [span(0, 3), span(4, 7)]),
            referenceDate: referenceDate, calendar: calendar
        )
        expect(quotedCut.items == quotedRow, "a split inside quotation is refused")
        expect(quotedCut.decisions.contains { $0.reason == .cutInsideQuotation && $0.verdict == .modelConflictsSafety },
               "as a safety conflict")

        // A cut after a word that needs its complement is a grammar fact.
        let dangling = "buy balloons for the party tomorrow"
        let danglingRow = [thought(dangling, type: .shopping)]
        let danglingCut = Arbiter.arbitrate(
            transcript: dangling, rules: (danglingRow, []), map: map(atoms: 6, units: [span(0, 3), span(4, 5)]),
            referenceDate: referenceDate, calendar: calendar
        )
        expect(danglingCut.items == danglingRow, "a cut after a determiner is refused")
        expect(danglingCut.decisions.contains { $0.reason == .cutAfterDanglingWord && $0.verdict == .rulesStronger },
               "with the rules holding the stronger evidence")

        // Two actions are never merged: that could hide one.
        let two = "call the vet email the landlord"
        let twoRows = [thought("call the vet", type: .task), thought("email the landlord", type: .task)]
        let merged = Arbiter.arbitrate(
            transcript: two, rules: (twoRows, []), map: map(atoms: 6, units: [span(0, 5)]),
            referenceDate: referenceDate, calendar: calendar
        )
        expect(merged.items == twoRows, "two actions stay two rows")
        expect(merged.decisions.contains { $0.reason == .mergeWouldHideAction }, "and the refusal names why")

        // A person the model confirms is kept; a person it does not see is
        // never added.
        let named = "ask Priya about the lease"
        let personRow = [thought(named, type: .personFollowUp, person: "Priya")]
        let confirmed = Arbiter.arbitrate(
            transcript: named, rules: (personRow, []),
            map: map(atoms: 5, units: nil, entities: [EntityEvidence(span: span(1, 1), kind: .person)]),
            referenceDate: referenceDate, calendar: calendar
        )
        expect(confirmed.items == personRow, "a confirmed person is kept")
        let unnamed = [thought(named, type: .task)]
        let added = Arbiter.arbitrate(
            transcript: named, rules: (unnamed, []),
            map: map(atoms: 5, units: nil, entities: [EntityEvidence(span: span(1, 1), kind: .person)]),
            referenceDate: referenceDate, calendar: calendar
        )
        expect(added.items.allSatisfy { $0.organization.personName == nil }, "the model never adds a person")
        expect(added.decisions.contains { $0.reason == .modelOnlyPerson && $0.verdict == .unresolved },
               "a person only the model saw is unresolved, not accepted")

        // A non-person reading of the rules' person: whatever the deterministic
        // resolver says, the result either keeps the rules or clears the
        // person, and never moves anything else.
        let bank = "call TD Bank about the fee"
        let bankRow = [thought(bank, type: .personFollowUp, reminder: reminder, person: "TD Bank")]
        let organization = Arbiter.arbitrate(
            transcript: bank, rules: (bankRow, []),
            map: map(atoms: 6, units: nil, entities: [EntityEvidence(span: span(1, 2), kind: .organization)]),
            referenceDate: referenceDate, calendar: calendar
        )
        let after = organization.items.first?.organization
        expect(after?.reminderDate == reminder, "clearing a person keeps the reminder")
        expect(after?.personName == nil || after?.personName == "TD Bank", "a person is kept or cleared, never replaced")
        if after?.personName == nil {
            expect(after?.itemType != .personFollowUp, "a cleared person no longer types the row as a follow-up")
        }

        // The structural guarantee, directly.
        expect(Arbiter.executablesAreSubset(rows, of: rows), "the rules reading is a subset of itself")
        let invented = [thought("call the bank", type: .task, reminder: reminder.addingTimeInterval(60))]
        expect(!Arbiter.executablesAreSubset(invented, of: rows), "a reminder the rules never produced is caught")

        // Every path above: nothing executable outside the rules reading.
        for (result, source) in [(withdrawn, rows), (quotedCut, quotedRow), (danglingCut, danglingRow),
                                 (merged, twoRows), (organization, bankRow)] {
            expect(Arbiter.executablesAreSubset(result.items, of: source), "arbitration created nothing executable")
            expect(result.decisions.last?.reason == .structuralGuaranteeHeld
                   || result.decisions.contains { $0.reason == .operationOwnedByRules },
                   "every arbitrated capture ends with the guarantee checked")
        }
    }

    // MARK: Production policy

    static func productionPolicy() {
        let unsupported = SemanticState.unsupported(.unsupportedCondition)
        let cases: [(String, [ExtractedThought], RoutePolicyReason)] = [
            ("", [], .emptyTranscript),
            (String(repeating: "a", count: 1_501), [thought("a", review: true)], .overCharacterCap),
            (String(repeating: "a", count: 1_500), [thought("a", review: true)], .eligible),
            ("buy milk", [thought("buy milk")], .noRowNeedsReview),
            ("if it rains", [thought("if it rains", review: true, state: unsupported)], .onlyUnsupportedRowsNeedReview),
            ("x y", [thought("x", review: true, state: unsupported), thought("y", review: true)], .eligible),
        ]
        for (transcript, items, expected) in cases {
            let decision = ProductionRoute.policy(transcript, rules: (items, []))
            expect(decision.reason == expected, "policy reason \(expected.rawValue)")
            expect(!decision.drift, "the decomposed reason agrees with RefinementPolicy for \(expected.rawValue)")
        }
        let operation = CaptureOperationRequest(operation: .cancel, target: nil, sourceQuote: "cancel it", needsReview: true)
        expect(ProductionRoute.policy("cancel it", rules: ([], [operation])).reason == .operationPresent,
               "an operation returns before the policy")

        var trace = ProductionTrace(
            characters: 10, policy: .eligible, shouldRefine: true, policyDrift: false, availability: nil,
            outcome: .notInvoked, unbudgeted: .accepted, latencyMilliseconds: 2_400, generationError: nil,
            validation: nil, validatorDrift: false, modelItems: 1, rulesItems: 1, instructionsFingerprint: ""
        )
        let late = ProductionRoute.decide(judged: [thought("x")], eligible: true, into: &trace)
        expect(late == nil && trace.outcome == .budgetExpired, "an answer after the budget is production's rules reading")
        trace.latencyMilliseconds = 1_200
        let prompt = ProductionRoute.decide(judged: [thought("x")], eligible: true, into: &trace)
        expect(prompt?.count == 1 && trace.outcome == .accepted, "an answer inside the budget is used")
        let shadowed = ProductionRoute.decide(judged: [thought("x")], eligible: false, into: &trace)
        expect(shadowed == nil && trace.outcome == .notInvoked, "a shadow answer never becomes the result")
    }

    // MARK: Fingerprints and records

    static func fingerprints() {
        // Published FNV-1a 32-bit vectors, never a value recomputed from our code.
        expect(SemanticJobPrompts.fingerprint(of: "") == "811c9dc5", "FNV-1a offset basis")
        expect(SemanticJobPrompts.fingerprint(of: "a") == "e40c292c", "FNV-1a one byte")
        expect(SemanticJobPrompts.fingerprint(of: "foobar") == "bf9cf968", "FNV-1a multi-byte")
        expect(SemanticJobPrompts.unitsFingerprint != SemanticJobPrompts.fingerprint(of: SemanticJobPrompts.units + " "),
               "a changed prompt changes its fingerprint")
        expect(!ProductionRefinementPrompt.instructions.isEmpty
               && !ProductionRefinementPrompt.instructions.hasPrefix(" "),
               "the production instructions were cut out whole, with production's indentation")
        for prompt in [SemanticJobPrompts.units, SemanticJobPrompts.relations, SemanticJobPrompts.entities] {
            // Both device runs showed the model copying example values back.
            expect(!prompt.contains("\"") && !prompt.contains("e.g."), "a job prompt carries no example values")
        }
    }

    static func records() {
        let original = map(
            atoms: 6, units: [span(0, 2), span(3, 5)],
            relations: [UnitRelation(kind: .givesContextTo, from: 0, to: 1)],
            entities: [EntityEvidence(span: span(1, 1), kind: .place)]
        )
        let data = try? recordEncoder.encode(original)
        let decoded = data.flatMap { try? JSONDecoder().decode(SemanticMap.self, from: $0) }
        expect(decoded == original, "a semantic map survives a round trip")

        let features = ComplexityReader.read(
            "call the vet, then buy milk", rules: ([thought("call the vet", type: .task), thought("buy milk", type: .shopping)], []),
            referenceDate: referenceDate, calendar: calendar
        )
        expect(features.atoms == 6 && features.rulesItems == 2 && features.rulesActionable == 2,
               "features count what they say they count")
        let encoded = try? recordEncoder.encode(features)
        let text = encoded.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        expect(!text.contains("vet") && !text.contains("milk"), "a feature record carries no capture text")
    }
}
