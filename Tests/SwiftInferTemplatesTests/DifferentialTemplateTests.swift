import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The differential / oracle family — `docs/parsing-catalog-gap.md` §6.
///
/// Two implementations of one specification must agree on every input. Built
/// first among the survey's holes because it had **two independent witnesses**:
/// swift-syntax states the law in its own test utilities
/// (`IncrementalParseTestUtils.swift:26`) as an example harness, and TestLifter
/// cannot see `mySort(x) == x.sorted()` for the same reason — no template
/// claimed the shape.
///
/// Reach measured *before* building: 12 marker pairs across ~5,900 distinct
/// function names in seven corpora. The template fires on **one**, and the
/// eleven rejections are all correct — pinned below, because "it only fires
/// once" is a claim that needs its denominator explained.
@Suite("DifferentialTemplate — reference vs variant implementation")
struct DifferentialTemplateTests {

    private func fn(
        _ name: String,
        params: [(String, String)] = [],
        returns: String?,
        carrier: String = "Parser",
        isMutating: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params.map {
                Parameter(label: $0.0, internalName: $0.0, typeText: $0.1, isInout: false)
            },
            returnTypeText: returns,
            isThrows: false, isAsync: false, isMutating: isMutating, isStatic: true,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    /// `IncrementalParseResult { let tree: SourceFileSyntax; … }`
    private var incrementalResult: TypeDecl {
        TypeDecl(
            name: "IncrementalParseResult",
            kind: .struct,
            inheritedTypes: [],
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            storedMembers: [
                StoredMember(name: "tree", typeName: "SourceFileSyntax"),
                StoredMember(name: "lookaheadRanges", typeName: "LookaheadRanges")
            ]
        )
    }

    private var swiftSyntaxPair: [FunctionSummary] {
        [
            fn("parse", params: [("source", "String")], returns: "SourceFileSyntax"),
            fn(
                "parseIncrementally",
                params: [("source", "String"), ("parseTransition", "IncrementalParseTransition?")],
                returns: "IncrementalParseResult"
            )
        ]
    }

    // MARK: - The motivating case

    @Test("the swift-syntax incremental-parse pair is found, with the right projection")
    func incrementalParsePairFound() throws {
        let pairs = VariantPairing.candidates(in: swiftSyntaxPair, typeDecls: [incrementalResult])
        let pair = try #require(pairs.first)
        #expect(pairs.count == 1)
        // The unmarked name is the reference — the direction the law runs in.
        #expect(pair.reference.name == "parse")
        #expect(pair.variant.name == "parseIncrementally")
        #expect(pair.naming.marker == "Incrementally")
        // `parseIncrementally` returns a wrapper; the law compares `.tree`.
        #expect(pair.projection == "tree")
    }

    @Test("it scores Likely and says where the property actually lives")
    func incrementalParseScoresAndExplains() throws {
        let pair = try #require(
            VariantPairing.candidates(in: swiftSyntaxPair, typeDecls: [incrementalResult]).first
        )
        let suggestion = try #require(DifferentialTemplate.suggest(for: pair))
        #expect(suggestion.score.total == 65)
        #expect(suggestion.score.tier == .likely)
        // The caveat that matters most: swift-syntax already has this as an
        // example test. What makes it a property is generating the transition.
        #expect(
            suggestion.explainability.whyMightBeWrong
                .contains { $0.contains("EXTRA ARGUMENT") && $0.contains("EVERY valid value") }
        )
        // And the direction, because a counterexample blames the variant.
        #expect(
            suggestion.explainability.whyMightBeWrong
                .contains { $0.contains("LAW RUNS IN ONE DIRECTION") }
        )
    }

    // MARK: - Naming

    @Test("all four measured marker forms relate correctly, reference first")
    func markerFormsFromRealCode() throws {
        let cases: [(names: (String, String), marker: String)] = [
            (("parse", "parseIncrementally"), "Incrementally"),                  // swift-syntax
            (("_ensureFreeCapacity", "_ensureFreeCapacitySlow"), "Slow"),        // swift-collections
            (("_addHTTPClientHandlers", "_addHTTPClientHandlersFallback"), "Fallback"),  // swift-nio
            (("append", "uncheckedAppend"), "unchecked")                         // swift-collections
        ]
        for (names, marker) in cases {
            let (reference, variant) = names
            let related = try #require(
                VariantMarkers.relateEitherOrder(reference, variant),
                "expected \(reference)/\(variant) related"
            )
            #expect(related.reference == reference, "the UNMARKED name is the reference")
            #expect(related.variant == variant)
            #expect(related.marker == marker)
        }
    }

    @Test("relate is order-insensitive but the reference is not")
    func relationIsOrderInsensitive() throws {
        let forward = try #require(VariantMarkers.relateEitherOrder("parse", "parseIncrementally"))
        let backward = try #require(VariantMarkers.relateEitherOrder("parseIncrementally", "parse"))
        #expect(forward == backward)
        #expect(backward.reference == "parse")
    }

    @Test("unrelated names do not relate")
    func unrelatedNames() {
        for (lhs, rhs) in [
            ("parse", "format"), ("append", "insert"), ("parse", "parse"),
            ("fastPath", "slowPath"), ("sort", "sorted")
        ] {
            #expect(VariantMarkers.relateEitherOrder(lhs, rhs) == nil, "\(lhs)/\(rhs)")
        }
    }

    @Test("precondition-eliding markers are flagged as such")
    func preconditionElidingFlagged() throws {
        let unchecked = try #require(VariantMarkers.relateEitherOrder("append", "uncheckedAppend"))
        #expect(unchecked.elidesPrecondition)
        let incremental = try #require(VariantMarkers.relateEitherOrder("parse", "parseIncrementally"))
        #expect(!incremental.elidesPrecondition)
    }

    /// This used to assert that a precondition-eliding pair SHIPPED, carrying a
    /// caveat saying the trap is not a refutation. It is now vetoed instead, and
    /// the corpus is what changed the verdict.
    ///
    /// The old test's own comment recorded that the shape was "unexercised on the
    /// measured corpora" — every real `unchecked*` pair was `mutating`/`Void` on
    /// an unsafe-handle carrier, so other gates caught them. `stdlib/public/core`
    /// exercises it: same shape, but returning a value on a resolvable carrier,
    /// so nothing incidental fires and **57 Likely-tier claims** land on the
    /// default surface — 32 `loadUnaligned`/`unsafeLoadUnaligned`, 24
    /// `load`/`unsafeLoad`, 1 `bitCast`/`unsafeBitCast`, and not one of them the
    /// law this family exists for.
    ///
    /// A caveat is the wrong instrument for a law that cannot be executed. See
    /// `Signal.Kind.preconditionElidingVariant`.
    @Test("a precondition-eliding variant is vetoed, not caveated")
    func preconditionElidingIsVetoed() throws {
        let pairs = VariantPairing.candidates(in: [
            fn("append", params: [("x", "Element")], returns: "Buffer", carrier: "Buf"),
            fn("uncheckedAppend", params: [("x", "Element")], returns: "Buffer", carrier: "Buf")
        ])
        let pair = try #require(pairs.first)
        // The pair still FORMS — the veto is a scoring verdict, not a pairing one,
        // so `metrics` can count what it suppressed.
        #expect(DifferentialTemplate.suggest(for: pair) == nil)

        let signals = DifferentialTemplate.signals(for: pair)
        #expect(signals.count == 1, "the veto must be the sole signal, not one of three")
        let veto = try #require(signals.first)
        #expect(veto.kind == .preconditionElidingVariant)
        #expect(veto.isVeto)
        #expect(Score(signals: signals).tier == .suppressed)
        // The detail has to say WHY it cannot be run, not merely that it was dropped.
        #expect(veto.detail.contains("cannot be RUN"))
        #expect(veto.detail.contains("trap is not a refutation"))
    }

    /// The `unsafe` prefix is the form that actually fired on stdlib, so it gets
    /// its own case rather than riding on `unchecked`'s.
    @Test("the unsafe prefix is vetoed on a value-returning stdlib-shaped pair")
    func unsafePrefixIsVetoed() throws {
        let pairs = VariantPairing.candidates(in: [
            fn("load", params: [("fromByteOffset", "Int")], returns: "T", carrier: "MutableRawSpan"),
            fn(
                "unsafeLoad",
                params: [("fromByteOffset", "Int")],
                returns: "T",
                carrier: "MutableRawSpan"
            )
        ])
        let pair = try #require(pairs.first)
        #expect(pair.naming.marker == "unsafe")
        #expect(pair.naming.elidesPrecondition)
        #expect(DifferentialTemplate.suggest(for: pair) == nil)
    }

    @Test("every pair is warned about the guard-and-delegate shape")
    func delegationHazardIsNamed() throws {
        // Measured on swift-collections: `_ensureFreeCapacity` guards and calls
        // `_ensureFreeCapacitySlow`, so the marked half is the COLD BRANCH of
        // one function, not a second implementation — and they deliberately
        // differ wherever the guard short-circuits. Only the Void-return gate
        // rejected that pair, by luck rather than by design, so the hazard is
        // named in prose for the shapes that do get through.
        let pair = try #require(
            VariantPairing.candidates(in: swiftSyntaxPair, typeDecls: [incrementalResult]).first
        )
        let suggestion = try #require(DifferentialTemplate.suggest(for: pair))
        #expect(
            suggestion.explainability.whyMightBeWrong
                .contains { $0.contains("simply CALLS") && $0.contains("COLD BRANCH") }
        )
    }

    // MARK: - The signature filter

    @Test("the variant must accept everything the reference does, in order")
    func leadingParametersMustMatch() {
        // Extra TRAILING parameters are the point; different leading ones mean
        // these are not two implementations of one call.
        let mismatched = [
            fn("parse", params: [("source", "String")], returns: "Tree"),
            fn("parseIncrementally", params: [("data", "Data"), ("t", "T?")], returns: "Tree")
        ]
        #expect(VariantPairing.candidates(in: mismatched).isEmpty)
    }

    @Test("Void-returning and mutating variants are out of scope")
    func voidReturnsRejected() {
        // This is why the nine swift-collections `unchecked*` pairs do not
        // fire: `mutating func append(_:)` returns Void. Comparing them would
        // need the lifted shadows, and their carriers are unsafe handle types
        // (`_UnsafeDequeHandle`) that the carrier resolver correctly refuses —
        // so a lifted path would buy nothing on the measured corpora.
        let voidPair = [
            fn("append", params: [("x", "Element")], returns: "Void", isMutating: true),
            fn("uncheckedAppend", params: [("x", "Element")], returns: "Void", isMutating: true)
        ]
        #expect(VariantPairing.candidates(in: voidPair).isEmpty)
    }

    @Test("an ambiguous projection is declined rather than guessed")
    func ambiguousProjectionRejected() {
        // Two members of the reference's return type — which one the law means
        // is a guess, and guessing is worse than silence.
        let ambiguous = TypeDecl(
            name: "PairResult", kind: .struct, inheritedTypes: [],
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            storedMembers: [
                StoredMember(name: "before", typeName: "Tree"),
                StoredMember(name: "after", typeName: "Tree")
            ]
        )
        let pair = [
            fn("parse", params: [("source", "String")], returns: "Tree"),
            fn("parseIncrementally", params: [("source", "String")], returns: "PairResult")
        ]
        #expect(VariantPairing.candidates(in: pair, typeDecls: [ambiguous]).isEmpty)
    }

    @Test("an unresolvable wrapper type is declined")
    func unresolvedProjectionRejected() {
        #expect(VariantPairing.candidates(in: swiftSyntaxPair, typeDecls: []).isEmpty)
    }

    @Test("equal return types need no projection")
    func equalReturnsNeedNoProjection() throws {
        let pairs = VariantPairing.candidates(in: [
            fn("sort", params: [("xs", "[Int]")], returns: "[Int]"),
            fn("naiveSort", params: [("xs", "[Int]")], returns: "[Int]")
        ])
        let pair = try #require(pairs.first)
        #expect(pair.projection == nil)
        #expect(pair.reference.name == "sort")
    }
}
