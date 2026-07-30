import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `distance(to:)` × `advanced(by:)` on a `Strideable` carrier is a law PropertyLawKit
/// already runs — `"Strideable.distanceRoundTrip"`,
/// `first.advanced(by: first.distance(to: second)) == second` (`StrideableLaws.swift:72`).
///
/// Found by `KitCoverageDriftTests` while classifying all 44 kit suites: `discover`
/// independently proposed the same pair on `stdlib/public/core`. Re-reporting another tool's
/// finding is what `protocolCoveredProperty` exists to prevent — *"teaches people the tools
/// disagree."*
@Suite("Round-trip — the Strideable distance/advanced law belongs to the kit")
struct StrideableCoverageVetoTests {

    private func member(
        _ name: String,
        _ param: String,
        _ ret: String,
        on carrier: String = "Tick"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "x", typeText: param, isInout: false)],
            returnTypeText: ret,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Tick.swift", line: 1, column: 1),
            containingTypeName: carrier, bodySignals: .empty
        )
    }

    private func stridePair(on carrier: String = "Tick") -> FunctionPair {
        FunctionPair(
            forward: member("distance", carrier, "Int", on: carrier),
            reverse: member("advanced", "Int", carrier, on: carrier)
        )
    }

    @Test("a Strideable conformer's distance/advanced pair is vetoed")
    func strideableConformerIsVetoed() {
        #expect(
            RoundTripTemplate.suggest(
                for: stridePair(), inheritedTypesByName: ["Tick": ["Strideable"]]
            ) == nil
        )
    }

    @Test("WITHOUT the conformance it is still proposed — the kit does not run it there")
    func nonConformerIsStillProposed() throws {
        // The conformance check is not redundant with the names. A type may define its own
        // `distance(to:)` / `advanced(by:)` without conforming to `Strideable`, and then
        // nothing else runs the law and we should say so.
        let suggestion = try #require(
            RoundTripTemplate.suggest(for: stridePair(), inheritedTypesByName: [:])
        )
        #expect(suggestion.templateName == "round-trip")
    }

    @Test("the veto is PAIR-scoped: other round-trips on a Strideable carrier survive")
    func vetoDoesNotSwallowUnrelatedRoundTrips() throws {
        // The load-bearing scoping decision. `BinaryInteger` refines `Strideable`
        // (`Integers.swift:533`), so a carrier-only check would veto every round-trip
        // proposed on any integer type — including the genuine ones this catalog exists to
        // surface. Mirrors the Codable veto, which calls `codableRoundTrippedType` first so
        // it suppresses only codec-shaped pairs.
        let unrelated = FunctionPair(
            forward: member("encode", "Tick", "Data"),
            reverse: member("decode", "Data", "Tick")
        )
        let suggestion = try #require(
            RoundTripTemplate.suggest(
                for: unrelated, inheritedTypesByName: ["Tick": ["Strideable"]]
            )
        )
        #expect(suggestion.templateName == "round-trip")
    }

    @Test("only the exact name pair triggers it")
    func onlyTheExactNamesTrigger() {
        let nearMiss = FunctionPair(
            forward: member("distance", "Tick", "Int"),
            reverse: member("offset", "Int", "Tick")   // not `advanced`
        )
        #expect(
            RoundTripTemplate.suggest(
                for: nearMiss, inheritedTypesByName: ["Tick": ["Strideable"]]
            ) != nil
        )
    }

    /// The residual, **closed 2026-07-30** — this test is the inversion its predecessor asked
    /// for (*"If this starts vetoing, the scanner learned protocol inheritance — invert this
    /// test"*).
    ///
    /// The veto was correct from the day it was written and simply never consulted on
    /// `stdlib/public/core`, because the carrier there is the **protocol** `BinaryInteger` and
    /// the scanner skipped protocol declarations outright — so `ProtocolCoverageMap` could not
    /// see that `BinaryInteger` refines `Strideable` (`Integers.swift:533`). The scanner now
    /// records protocol decls for their inheritance clause, and the double-report is gone:
    /// `stdlib/public/core` went 740 → 739 suggestions, the single removed row being exactly
    /// `distance(to:)` × `advanced(by:)` at `Integers.swift:1843/1882`.
    @Test("a protocol carrier is now reachable — the scanner records protocol inheritance")
    func protocolCarrierIsVetoed() {
        #expect(
            RoundTripTemplate.suggest(
                for: stridePair(on: "BinaryInteger"),
                inheritedTypesByName: ["BinaryInteger": ["Strideable", "Numeric", "Hashable"]]
            ) == nil
        )
    }

    /// The end-to-end version of the above: the index comes from the *scanner* rather than
    /// being hand-written, so this fails if protocol recording regresses even when the veto
    /// itself is intact. That split is the whole lesson of this defect — a correct veto that
    /// nothing ever calls looks identical to a missing veto from the outside.
    @Test("scanner → coverage map → veto, end to end on a refining protocol")
    func scannerSuppliedInheritanceReachesTheVeto() {
        let source = """
        protocol Tickable: Strideable {}
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Tick.swift")
        var index: [String: Set<String>] = [:]
        for decl in corpus.typeDecls {
            index[decl.name, default: []].formUnion(decl.inheritedTypes)
        }
        #expect(index["Tickable"] == ["Strideable"])
        #expect(
            RoundTripTemplate.suggest(
                for: stridePair(on: "Tickable"), inheritedTypesByName: index
            ) == nil
        )
    }
}
