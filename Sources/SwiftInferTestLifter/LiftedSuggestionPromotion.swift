import SwiftInferCore

/// TestLifter M3.0 — `LiftedSuggestion → Suggestion` promotion adapter.
/// Bridges TestLifter's detector-side record into TemplateEngine's
/// `Suggestion` shape so the existing renderer / tier filter /
/// `GeneratorSelection` pass / accept-flow / drift / baseline consumers
/// can treat lifted records uniformly with TemplateEngine-originated
/// records (M3 plan open decision #1 default `(a)` — single suggestion
/// stream, not parallel renderer arms).
///
/// **Promotion produces a `Suggestion` whose:**
/// - `templateName` matches the lifted suggestion's (`"round-trip"` /
///   `"idempotence"` / `"commutativity"`).
/// - `evidence` array carries one synthetic `Evidence` per detection
///   callee with the recovered (or `?`-sentinel) types. Round-trip
///   produces two-element evidence (forward + backward); idempotence and
///   commutativity produce one-element evidence.
/// - `score` carries one `Signal(kind: .testBodyPattern, weight: 50)`
///   per PRD §4.1's "+50 test-body pattern" row. No structural-base
///   signal is synthesized (M3 plan open decision #5 default `(a)` —
///   honest about what TestLifter actually saw; tier lands at `~ Likely`
///   without TemplateEngine corroboration).
/// - `generator` defaults to `.m1Placeholder` (`.notYetComputed` source).
///   The downstream `GeneratorSelection` pass (M3.1) overwrites this with
///   the inferred metadata when the recovered type appears in the
///   corpus's `TypeShape` index; otherwise the `.todo` source survives
///   into the accept-flow stub (PRD §16 #4 — `.todo` never silently
///   compiles).
/// - `identity` uses a `lifted|<template>|<sortedCalleeNames>` canonical
///   input that namespaces lifted identities away from TemplateEngine
///   identities (which use `<template>|<canonicalSignature>`). M6
///   (TestLifter persistence) will extend identity to include test
///   method name to disambiguate same-template-same-callees lifted
///   suggestions across multiple test methods; M3 doesn't need that
///   because lifted suggestions don't enter `.swiftinfer/decisions.json`
///   in M3.
/// - `liftedOrigin` is the caller-supplied `LiftedOrigin?` (M3.0 plumbs
///   the parameter; M3.1's `Discover+Pipeline` caller populates it from
///   the originating `TestMethodSummary`).
///
/// **Type-recovery contract.** M3.0's adapter does not perform recovery
/// itself — callers (M3.1's `Discover+Pipeline.collectVisibleSuggestions`)
/// supply the `typeName` / `returnType` from a `[FunctionSummary]`
/// lookup. M3.0 accepts `nil` for either parameter and synthesizes a
/// `?` sentinel in the evidence signature; the resulting suggestion
/// flows through `GeneratorSelection` and gets `.todo` because the `?`
/// type isn't in the corpus's `TypeShape` index. This honors the M3
/// plan's open decision #2 default `(a)` — strict FunctionSummary
/// lookup, no setup-region annotation walking (deferred to M4 with the
/// PRD-row mock-based generator synthesis).
public extension LiftedSuggestion {

    /// Promote this lifted suggestion to a `Suggestion` for stream
    /// entry. See the type-level docstring for the per-field contract.
    ///
    /// - Parameters:
    ///   - typeName: Recovered parameter type for the lifted callee
    ///     (e.g. `"String"` for `func normalize(_ s: String) -> String`).
    ///     Pass `nil` when FunctionSummary lookup failed; the synthetic
    ///     evidence uses `"?"` and `GeneratorSelection` produces `.todo`.
    ///   - returnType: Recovered return type. For idempotence and
    ///     commutativity this is conventionally the same as `typeName`
    ///     (`(T) -> T` and `(T, T) -> T` shapes); pass nil to default to
    ///     `typeName` (or `"?"` when both are nil). Round-trip uses both
    ///     parameters distinctly: forward is `(typeName) -> returnType`,
    ///     backward is `(returnType) -> typeName`.
    ///   - origin: The originating test method's name + source location.
    ///     `nil` defaults are accepted for M3.0 unit tests; M3.1's
    ///     `Discover+Pipeline` caller always supplies a non-nil origin.
    func toSuggestion(
        typeName: String?,
        returnType: String? = nil,
        origin: LiftedOrigin? = nil
    ) -> Suggestion {
        let typeT = typeName ?? "?"
        let typeU = returnType ?? typeName ?? "?"
        let evidence = makeEvidence(typeT: typeT, typeU: typeU)
        let signal = Signal(
            kind: .testBodyPattern,
            weight: 50,
            detail: "Lifted from test body — \(detailLabel())"
        )
        // M11.2 / M13.3 / M16.2 — corpus-wide advisory findings surface
        // with `.advisory` tier per PRD §7.8 (documentation, not a
        // runnable property). All other patterns flow through the
        // standard score-to-tier mapping with +50 testBodyPattern.
        let score: Score
        switch pattern {
        case .equivalenceClass, .nClassEquivalenceClass, .consumerProducerChain:
            score = Score(advisorySignals: [signal])
        case .roundTrip, .idempotence, .commutativity,
                .monotonicity, .countInvariance, .reduceEquivalence:
            score = Score(signals: [signal])
        }
        return Suggestion(
            templateName: templateName,
            evidence: evidence,
            score: score,
            generator: .m1Placeholder,
            explainability: makeExplainability(),
            identity: makeIdentity(),
            liftedOrigin: origin,
            // V1.34.B — TestLifter-promoted carrier defaults to the
            // domain type recovered from the test body (typeT). For
            // round-trip / idempotence / commutativity / monotonicity
            // this is the type the property is parameterized over.
            // `typeName == nil` falls through as `"?"` and we pass nil
            // so query --type filters skip these (matching free-
            // function semantics).
            carrier: typeName
        )
    }

    // MARK: - Per-pattern evidence shape

    private func makeEvidence(typeT: String, typeU: String) -> [Evidence] {
        switch pattern {
        case .roundTrip(let detection):
            return roundTripEvidence(detection: detection, typeT: typeT, typeU: typeU)
        case .idempotence(let detection):
            return [unaryEvidence(callee: detection.calleeName, typeT: typeT, location: detection.assertionLocation)]
        case .commutativity(let detection):
            return [binaryEvidence(callee: detection.calleeName, typeT: typeT, location: detection.assertionLocation)]
        case .monotonicity(let detection):
            // (T) -> Comparable; codomain is unknown at promotion time
            // until M5.5 widens recoverTypes to split domain/codomain.
            return [Evidence(
                displayName: "\(detection.calleeName)(_:)",
                signature: "(\(typeT)) -> ?",
                location: detection.assertionLocation
            )]
        case .countInvariance(let detection):
            return [unaryEvidence(callee: detection.calleeName, typeT: typeT, location: detection.assertionLocation)]
        case .reduceEquivalence(let detection):
            return [reduceEquivalenceEvidence(detection: detection, typeT: typeT)]
        case .equivalenceClass(let hint):
            // M11.2 — synthesize a single Evidence carrying the predicate's
            // signature `(T) -> Bool`. Location is a placeholder (the M11
            // detector aggregates across many test sites; no single
            // assertion location is canonical).
            return [Evidence(
                displayName: "\(hint.predicateName)(_:)",
                signature: "(\(hint.argTypeName)) -> Bool",
                location: SourceLocation(file: "<corpus>", line: 0, column: 0)
            )]
        case .nClassEquivalenceClass(let hint):
            // M13.3 — same shape as two-class equivalence-class evidence
            // but the signature names the predicate's actual return type.
            return [Evidence(
                displayName: "\(hint.predicateName)(_:)",
                signature: "(\(hint.argTypeName)) -> \(hint.returnTypeName)",
                location: SourceLocation(file: "<corpus>", line: 0, column: 0)
            )]
        case .consumerProducerChain(let hint):
            // M16.2 — synthesize a single Evidence carrying the
            // consumer's signature `(domainTypeName) -> ?`. Like the
            // equivalence-class case the location is a placeholder —
            // the chain is a corpus-wide finding, not anchored at a
            // single test-body assertion.
            return [Evidence(
                displayName: "\(hint.reverseName)(_:)",
                signature: "(\(hint.domainTypeName)) -> ?",
                location: SourceLocation(file: "<corpus>", line: 0, column: 0)
            )]
        }
    }

    /// Reduce-equivalence evidence carries the seed expression in the
    /// signature so the M5.5 `liftedReduceEquivalenceStub` accept-flow
    /// dispatcher can extract it (mirrors how
    /// `InvariantPreservationTemplate` encodes its keypath via
    /// `" preserving \\.foo"` on the signature). Without the seed in the
    /// signature, the lifted reduce-equivalence stub would have to
    /// hard-code a placeholder seed (losing the test-body fidelity
    /// PRD §3.5 prescribes).
    private func reduceEquivalenceEvidence(
        detection: DetectedReduceEquivalence,
        typeT: String
    ) -> Evidence {
        Evidence(
            displayName: "\(detection.opCalleeName)(_:_:)",
            signature: "(\(typeT), \(typeT)) -> \(typeT) seed \(detection.seedSource)",
            location: detection.assertionLocation
        )
    }

    private func roundTripEvidence(detection: DetectedRoundTrip, typeT: String, typeU: String) -> [Evidence] {
        [
            Evidence(
                displayName: "\(detection.forwardCallee)(_:)",
                signature: "(\(typeT)) -> \(typeU)",
                location: detection.assertionLocation
            ),
            Evidence(
                displayName: "\(detection.backwardCallee)(_:)",
                signature: "(\(typeU)) -> \(typeT)",
                location: detection.assertionLocation
            )
        ]
    }

    private func unaryEvidence(callee: String, typeT: String, location: SourceLocation) -> Evidence {
        Evidence(
            displayName: "\(callee)(_:)",
            signature: "(\(typeT)) -> \(typeT)",
            location: location
        )
    }

    private func binaryEvidence(callee: String, typeT: String, location: SourceLocation) -> Evidence {
        Evidence(
            displayName: "\(callee)(_:_:)",
            signature: "(\(typeT), \(typeT)) -> \(typeT)",
            location: location
        )
    }

    private func detailLabel() -> String {
        switch pattern {
        case .roundTrip(let detection):
            return "\(detection.backwardCallee)(\(detection.forwardCallee)(x)) == x"
        case .idempotence(let detection):
            return "\(detection.calleeName)(\(detection.calleeName)(x)) == \(detection.calleeName)(x)"
        case .commutativity(let detection):
            return "\(detection.calleeName)(a, b) == \(detection.calleeName)(b, a)"
        case .monotonicity(let detection):
            return "a < b ⇒ \(detection.calleeName)(a) <= \(detection.calleeName)(b)"
        case .countInvariance(let detection):
            return "\(detection.calleeName)(xs).count == xs.count"
        case .reduceEquivalence(let detection):
            return "xs.reduce(_, \(detection.opCalleeName)) == xs.reversed().reduce(_, \(detection.opCalleeName))"
        case .equivalenceClass(let hint):
            return "\(hint.predicateName) partitions \(hint.positiveMarker)/\(hint.negativeMarker)"
                + " (\(hint.positiveSiteCount)+\(hint.negativeSiteCount) sites)"
        case .nClassEquivalenceClass(let hint):
            let counts = hint.markers.map { marker in
                "\(marker)=\(hint.siteCountsByMarker[marker] ?? 0)"
            }.joined(separator: ", ")
            return "\(hint.predicateName) partitions \(hint.markerSetName) [\(counts)]"
        case .consumerProducerChain(let hint):
            return "\(hint.reverseName)'s argument was always \(hint.producerName)'s output"
                + " across \(hint.siteCount) sites"
        }
    }

    // MARK: - Identity

    /// `lifted|<template>|<sortedCalleeNames>` — namespaced away from
    /// TemplateEngine identities (`<template>|<canonicalSignature>`) so
    /// a lifted Suggestion never collides hash-wise with a TemplateEngine
    /// Suggestion. The M3.2 suppression filter uses `crossValidationKey`
    /// (the pattern-key, not identity) for the dedup pass, so identity
    /// uniqueness here is independent of suppression — it matters only
    /// for the renderer's stable-key per-suggestion display and (later,
    /// M6) for `.swiftinfer/decisions.json` keys.
    private func makeIdentity() -> SuggestionIdentity {
        let callees = crossValidationKey.calleeNames.joined(separator: ",")
        return SuggestionIdentity(canonicalInput: "lifted|\(templateName)|\(callees)")
    }

    // MARK: - Explainability

    private func makeExplainability() -> ExplainabilityBlock {
        if case .equivalenceClass(let hint) = pattern {
            return equivalenceClassExplainability(hint: hint)
        }
        if case .nClassEquivalenceClass(let hint) = pattern {
            return nClassEquivalenceClassExplainability(hint: hint)
        }
        if case .consumerProducerChain(let hint) = pattern {
            return consumerProducerChainExplainability(hint: hint)
        }
        let assertionLine: String
        switch pattern {
        case .roundTrip(let detection):
            assertionLine = "Test body asserts \(detection.backwardCallee)"
                + "(\(detection.forwardCallee)(\(detection.inputBindingName)))"
                + " == \(detection.inputBindingName)"
        case .idempotence(let detection):
            assertionLine = "Test body asserts \(detection.calleeName)"
                + "(\(detection.calleeName)(\(detection.inputBindingName)))"
                + " == \(detection.calleeName)(\(detection.inputBindingName))"
        case .commutativity(let detection):
            assertionLine = "Test body asserts \(detection.calleeName)"
                + "(\(detection.leftArgName), \(detection.rightArgName))"
                + " == \(detection.calleeName)(\(detection.rightArgName), \(detection.leftArgName))"
        case .monotonicity(let detection):
            assertionLine = "Test body asserts \(detection.leftArgName)"
                + " < \(detection.rightArgName) implies "
                + "\(detection.calleeName)(\(detection.leftArgName))"
                + " <= \(detection.calleeName)(\(detection.rightArgName))"
        case .countInvariance(let detection):
            assertionLine = "Test body asserts \(detection.calleeName)"
                + "(\(detection.inputBindingName)).count"
                + " == \(detection.inputBindingName).count"
        case .reduceEquivalence(let detection):
            assertionLine = "Test body asserts \(detection.collectionBindingName)"
                + ".reduce(\(detection.seedSource), \(detection.opCalleeName))"
                + " == \(detection.collectionBindingName).reversed()"
                + ".reduce(\(detection.seedSource), \(detection.opCalleeName))"
        case .equivalenceClass, .nClassEquivalenceClass, .consumerProducerChain:
            // Handled by the early-return above.
            assertionLine = ""
        }
        let location = assertionLocation()
        let provenance = "Lifted from \(location.file):\(location.line)"
        return ExplainabilityBlock(
            whySuggested: [assertionLine, provenance],
            whyMightBeWrong: []
        )
    }

    /// M11.2 — equivalence-class explainability surfaces the corpus
    /// observation (predicate, marker pair, bucket counts) plus either
    /// the suggested filter generators or the predicate-shape veto
    /// reason. Distinct from the assertion-line shape used for the
    /// other six patterns because equivalence-class findings aren't
    /// anchored on a single test-body assertion.
    private func equivalenceClassExplainability(hint: EquivalenceClassHint) -> ExplainabilityBlock {
        let header = "Predicate \(hint.predicateName)(_: \(hint.argTypeName)) -> Bool"
            + " partitions Valid/Invalid across the test corpus:"
        let positiveLine = "  • \(hint.positiveSiteCount) sites named \(hint.positiveMarker)*"
            + " assert \(hint.predicateName)(x) is true"
        let negativeLine = "  • \(hint.negativeSiteCount) sites named \(hint.negativeMarker)*"
            + " assert \(hint.predicateName)(x) is false"
        var why = [header, positiveLine, negativeLine]
        if let veto = hint.predicateVeto {
            why.append("Generator narrowing skipped: \(veto.advisoryReason).")
        } else {
            why.append("Suggested generator for \(hint.positiveMarker) class: "
                + hint.suggestedPositiveGenerator)
            why.append("Suggested generator for \(hint.negativeMarker) class: "
                + hint.suggestedNegativeGenerator)
        }
        let advisoryCaveat = "Advisory only — the equivalence class is documentation,"
            + " not a runnable property. Author per-class properties"
            + " manually using the suggested filter generators."
        let rejectionCaveat = "Filter rejection rate: \(hint.predicateName) may reject most"
            + " random \(hint.argTypeName)s; if so, prefer constructing"
            + " a custom Gen for the \(hint.positiveMarker) class instead"
            + " of relying on filter."
        return ExplainabilityBlock(whySuggested: why, whyMightBeWrong: [advisoryCaveat, rejectionCaveat])
    }

    private func assertionLocation() -> SourceLocation {
        switch pattern {
        case .roundTrip(let detection):
            return detection.assertionLocation
        case .idempotence(let detection):
            return detection.assertionLocation
        case .commutativity(let detection):
            return detection.assertionLocation
        case .monotonicity(let detection):
            return detection.assertionLocation
        case .countInvariance(let detection):
            return detection.assertionLocation
        case .reduceEquivalence(let detection):
            return detection.assertionLocation
        case .equivalenceClass, .nClassEquivalenceClass, .consumerProducerChain:
            // M11.2 / M13.3 / M16.2 — corpus-level finding; no single
            // assertion location.
            return SourceLocation(file: "<corpus>", line: 0, column: 0)
        }
    }

    /// M13.3 — explainability for N-class equivalence-class advisory.
    /// Mirrors `equivalenceClassExplainability(hint:)` for the two-class
    /// case but lists per-bucket marker counts and per-bucket suggested
    /// generators (or the predicate-shape veto reason).
    private func nClassEquivalenceClassExplainability(hint: NClassEquivalenceClassHint) -> ExplainabilityBlock {
        let header = "Predicate \(hint.predicateName)(_: \(hint.argTypeName))"
            + " -> \(hint.returnTypeName) partitions \(hint.markerSetName)"
            + " across the test corpus:"
        var why = [header]
        for marker in hint.markers {
            let count = hint.siteCountsByMarker[marker] ?? 0
            why.append("  • \(count) sites named \(marker)*"
                + " assert \(hint.predicateName)(x) == .\(marker.lowercasedFirst())")
        }
        if let veto = hint.predicateVeto {
            why.append("Generator narrowing skipped: \(veto.advisoryReason).")
        } else {
            for marker in hint.markers {
                if let generator = hint.suggestedGeneratorsByMarker[marker] {
                    why.append("Suggested generator for \(marker) class: \(generator)")
                }
            }
        }
        if hint.coversDomain {
            why.append("Exhaustiveness: forAll x: \(hint.argTypeName)."
                + " disjunction over \(hint.markers.count) buckets covers"
                + " every case of \(hint.returnTypeName).")
        }
        let advisoryCaveat = "Advisory only — the equivalence class is documentation,"
            + " not a runnable property. Author per-class properties manually using"
            + " the suggested filter generators."
        return ExplainabilityBlock(whySuggested: why, whyMightBeWrong: [advisoryCaveat])
    }
}

private extension String {
    /// Marker text in vocabulary is conventionally Title-cased; Swift
    /// enum cases are lowercase-first. Used in renderer output.
    func lowercasedFirst() -> String {
        guard let first = self.first else { return self }
        return first.lowercased() + self.dropFirst()
    }
}
