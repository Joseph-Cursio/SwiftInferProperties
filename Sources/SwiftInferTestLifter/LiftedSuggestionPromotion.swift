import SwiftInferCore

/// TestLifter M3.0 — `LiftedSuggestion → Suggestion` promotion adapter.
/// Bridges TestLifter's detector-side record into TemplateEngine's
/// `Suggestion` shape so the existing renderer / tier filter /
/// `GeneratorSelection` pass / accept-flow / drift / baseline consumers
/// can treat lifted records uniformly with TemplateEngine-originated
/// records (M3 plan open decision #1 default `(a)` — single suggestion
/// stream, not parallel renderer arms).
///
/// **Promotion produces a `Suggestion`** whose `templateName` matches
/// the lifted record, `evidence` carries per-callee synthetic Evidence,
/// `score` adds one `+50 testBodyPattern` signal (PRD §4.1), `generator`
/// defaults to `.m1Placeholder` (later overwritten by GeneratorSelection
/// or kept as `.todo` per PRD §16 #4), `identity` uses
/// `lifted|<template>|<sortedCalleeNames>` to namespace away from
/// TemplateEngine, and `liftedOrigin` is the caller-supplied origin.
///
/// **Type-recovery contract.** M3.0 does not perform recovery itself;
/// callers supply `typeName` / `returnType` from a FunctionSummary
/// lookup. `nil` parameters produce a `?` sentinel that flows through
/// `GeneratorSelection` to `.todo` (PRD §16 #4 — never silently compiles).
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
            return [
                Evidence(
                    displayName: "\(detection.calleeName)(_:)",
                    signature: "(\(typeT)) -> ?",
                    location: detection.assertionLocation
                )
            ]

        case .countInvariance(let detection):
            return [unaryEvidence(callee: detection.calleeName, typeT: typeT, location: detection.assertionLocation)]

        case .reduceEquivalence(let detection):
            return [reduceEquivalenceEvidence(detection: detection, typeT: typeT)]

        case .equivalenceClass(let hint):
            // M11.2 — synthesize a single Evidence carrying the predicate's
            // signature `(T) -> Bool`. Location is a placeholder (the M11
            // detector aggregates across many test sites; no single
            // assertion location is canonical).
            return [
                Evidence(
                    displayName: "\(hint.predicateName)(_:)",
                    signature: "(\(hint.argTypeName)) -> Bool",
                    location: SourceLocation(file: "<corpus>", line: 0, column: 0)
                )
            ]

        case .nClassEquivalenceClass(let hint):
            // M13.3 — same shape as two-class equivalence-class evidence
            // but the signature names the predicate's actual return type.
            return [
                Evidence(
                    displayName: "\(hint.predicateName)(_:)",
                    signature: "(\(hint.argTypeName)) -> \(hint.returnTypeName)",
                    location: SourceLocation(file: "<corpus>", line: 0, column: 0)
                )
            ]

        case .consumerProducerChain(let hint):
            // M16.2 — synthesize a single Evidence carrying the
            // consumer's signature `(domainTypeName) -> ?`. Like the
            // equivalence-class case the location is a placeholder —
            // the chain is a corpus-wide finding, not anchored at a
            // single test-body assertion.
            return [
                Evidence(
                    displayName: "\(hint.reverseName)(_:)",
                    signature: "(\(hint.domainTypeName)) -> ?",
                    location: SourceLocation(file: "<corpus>", line: 0, column: 0)
                )
            ]
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
            let counts = hint.markers
                .map { marker in
                    "\(marker)=\(hint.siteCountsByMarker[marker] ?? 0)"
                }
                .joined(separator: ", ")
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

}
