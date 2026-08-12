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
/// `score` adds one `+80 testBodyPattern` signal (PRD §4.1), `generator`
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
        let evidence = makeEvidence(typeT: typeT, typeU: typeU, fallback: origin?.sourceLocation)
        // **A HUMAN ALREADY ASSERTED THIS LAW.** Weight 75 — enough to reach
        // `.strong` alone — because a lifted law is evidence of a different
        // KIND from anything the signature side produces, and the tier is the
        // trust bar a reader reads.
        //
        // Measured inversion this replaces. On one probe:
        //
        //     normalize(normalize(d)) == normalize(d)   75 Strong   ← a GUESS
        //         (read off the curated verb `normalize`; PRD §4.1's own
        //          counterexample is a one-shot suffix strip, which is
        //          correct code that fails this)
        //     mySort(x) == x.sorted()                   50 Likely   ← ASSERTED
        //         (a human wrote it, decided it holds for all inputs, and ran
        //          it 10,000 times)
        //
        // A name-derived conjecture outranking an executed, human-authored law
        // by a full tier is backwards. The ceiling on the signature side is 75
        // (30 type-symmetry + 40 curated verb + 5 value-semantic carrier), and
        // the lifted path scores exactly ONE signal — so 75 would merely TIE,
        // leaving `query`'s score-descending order arbitrary between a guess
        // and an assertion. 80 makes the assertion sort first, which is the
        // actual behaviour wanted.
        //
        // Deliberately unqualified by test quality: the lift detects the shape,
        // not how thorough the test is. A one-example test still means a human
        // decided the law holds — which a curated verb never does.
        //
        // Not a visibility change: `.likely` (>= 40) was already shown by
        // default. What changes is the CONFIDENCE LABEL, which is the point —
        // `docc` gates on tier, `query` sorts by it, and a reader trusts it.
        let signal = Signal(
            kind: .testBodyPattern,
            weight: 80,
            detail: "Lifted from test body — \(detailLabel())"
        )
        // M11.2 / M13.3 / M16.2 — corpus-wide advisory findings surface
        // with `.advisory` tier per PRD §7.8 (documentation, not a
        // runnable property). All other patterns flow through the
        // standard score-to-tier mapping with +80 testBodyPattern.
        let score: Score
        switch pattern {
        case .equivalenceClass, .nClassEquivalenceClass, .consumerProducerChain:
            score = Score(advisorySignals: [signal])

        case .roundTrip, .idempotence, .commutativity,
                .monotonicity, .countInvariance, .reduceEquivalence,
                .referenceEquivalence:
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

    /// The location an evidence record should carry: the detector's, when it has one, else
    /// the enclosing test method's.
    ///
    /// `Slicer.location(of:)` carries no `SourceLocationConverter` and emits `<test-body>:0`.
    /// The recorded decision is not to thread a converter through six detectors but to fall
    /// back to `LiftedOrigin`, which already holds the test method's real file and line — and
    /// that fallback was applied to RENDERING only. So `provenanceLine()` printed a real path
    /// while `evidence.location`, the field that reaches the SemanticIndex, `query` and every
    /// downstream join, kept the placeholder: lifted entries indexed as `<test-body>:0`.
    ///
    /// Less precise than the assertion's own line, and auditable, which the placeholder was
    /// not — it names a file a reader can open and a method they can read. That is CLAUDE.md
    /// §7.4's complaint, and the reason a package-wide lifting defect could hide: a row citing
    /// `render(suggestion)` on the wrong target is only obviously wrong if it says where it
    /// came from.
    ///
    /// Chosen at CONSTRUCTION rather than patched afterwards. Rebuilding an `Evidence` to
    /// swap one field means restating the other nine, and the day a tenth is added the copy
    /// drops it silently — the `EveryColumn` failure this repo already keeps a designated
    /// initializer to prevent.
    ///
    /// **This does not make `SeedFocus`'s lifted exemption unnecessary**, which #244
    /// speculated it might. The focus joins `(file basename, symbol)` against a manifest of
    /// PRODUCTION functions, and a test file's basename is not in one — so a lifted row still
    /// cannot join, and is still kept by the rule that asks whether the scan declares its
    /// subject. What changes is that the row now says where it came from.
    private func site(_ detected: SourceLocation, _ fallback: SourceLocation?) -> SourceLocation {
        // A wrong location is worse than an honest placeholder, so an unresolvable fallback
        // leaves the placeholder in place — `isResolvable` already tells consumers which of
        // the two they are holding.
        guard !detected.isResolvable, let fallback, fallback.isResolvable else { return detected }
        return fallback
    }

    /// Two populations, and the split is the point rather than a length remedy.
    ///
    /// A **corpus-level** finding is aggregated across many test bodies and anchored at none,
    /// so it carries `<corpus>` and must keep it. A **per-assertion** law comes from one
    /// assertion whose line the slicer could not compute, so it carries `<test-body>` and the
    /// origin is a strictly better answer. Resolving the first kind the way we resolve the
    /// second would name a site the finding is not anchored at, and `isResolvable` would then
    /// report that lie as trustworthy provenance.
    ///
    /// Keeping them in one switch made that distinction a comment. Here it is the signature:
    /// `corpusLevelEvidence` takes no `fallback` and so cannot apply one.
    private func makeEvidence(typeT: String, typeU: String, fallback: SourceLocation?) -> [Evidence] {
        if let corpus = corpusLevelEvidence(typeT: typeT) { return corpus }
        return assertionEvidence(typeT: typeT, typeU: typeU, fallback: fallback)
    }

    /// Findings with no canonical site. Returns `nil` for every per-assertion pattern, which
    /// `makeEvidence` then routes to `assertionEvidence`.
    private func corpusLevelEvidence(typeT: String) -> [Evidence]? {
        switch pattern {
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

        default:
            _ = typeT
            return nil
        }
    }

    /// Laws anchored at one assertion. Every location here goes through ``site(_:_:)``.
    private func assertionEvidence(
        typeT: String, typeU: String, fallback: SourceLocation?
    ) -> [Evidence] {
        switch pattern {
        case .roundTrip(let detection):
            return roundTripEvidence(
                detection: detection, typeT: typeT, typeU: typeU, fallback: fallback
            )

        case .referenceEquivalence(let detection):
            // Evidence names the SUBJECT: the law runs in one direction and a
            // counterexample is the subject's bug, not the reference's.
            return [
                unaryEvidence(
                    callee: detection.subjectCallee,
                    typeT: typeT,
                    location: site(detection.location, fallback)
                )
            ]

        case .idempotence(let detection):
            return [
                unaryEvidence(
                    callee: detection.calleeName,
                    typeT: typeT,
                    location: site(detection.assertionLocation, fallback)
                )
            ]

        case .commutativity(let detection):
            return [
                binaryEvidence(
                    callee: detection.calleeName,
                    typeT: typeT,
                    location: site(detection.assertionLocation, fallback)
                )
            ]

        case .monotonicity(let detection):
            return [monotonicityEvidence(detection: detection, typeT: typeT, fallback: fallback)]

        case .countInvariance(let detection):
            return [
                unaryEvidence(
                    callee: detection.calleeName,
                    typeT: typeT,
                    location: site(detection.assertionLocation, fallback)
                )
            ]

        case .reduceEquivalence(let detection):
            return [
                reduceEquivalenceEvidence(detection: detection, typeT: typeT, fallback: fallback)
            ]

        default:
            return []
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
        typeT: String,
        fallback: SourceLocation?
    ) -> Evidence {
        Evidence(
            displayName: "\(detection.opCalleeName)(_:_:)",
            signature: "(\(typeT), \(typeT)) -> \(typeT) seed \(detection.seedSource)",
            location: site(detection.assertionLocation, fallback)
        )
    }

    private func roundTripEvidence(
        detection: DetectedRoundTrip, typeT: String, typeU: String, fallback: SourceLocation?
    ) -> [Evidence] {
        [
            Evidence(
                displayName: "\(detection.forwardCallee)(_:)",
                signature: "(\(typeT)) -> \(typeU)",
                location: site(detection.assertionLocation, fallback)
            ),
            Evidence(
                displayName: "\(detection.backwardCallee)(_:)",
                signature: "(\(typeU)) -> \(typeT)",
                location: site(detection.assertionLocation, fallback)
            )
        ]
    }

    /// `(T) -> Comparable`; the codomain is unknown at promotion time until M5.5 widens
    /// `recoverTypes` to split domain from codomain.
    private func monotonicityEvidence(
        detection: DetectedMonotonicity, typeT: String, fallback: SourceLocation?
    ) -> Evidence {
        Evidence(
            displayName: "\(detection.calleeName)(_:)",
            signature: "(\(typeT)) -> ?",
            location: site(detection.assertionLocation, fallback)
        )
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

        case .referenceEquivalence(let detection):
            return "\(detection.subjectCallee)(x) == \(detection.referenceCallee)(x)"

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
