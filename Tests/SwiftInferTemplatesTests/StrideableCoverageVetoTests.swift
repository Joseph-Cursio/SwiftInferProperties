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

    /// The residual, pinned so it is not mistaken for fixed.
    ///
    /// On `stdlib/public/core` the pair's carrier is the **protocol** `BinaryInteger`, and
    /// `FunctionScanner.swift:362` skips protocol declarations outright — so their inheritance
    /// clause is never recorded and `ProtocolCoverageMap` cannot see that `BinaryInteger`
    /// refines `Strideable`. The veto below is correct and simply never consulted there.
    /// Fixing that is a scanner change with a much wider blast radius.
    @Test("a protocol carrier is still unreachable — the scanner records no protocol inheritance")
    func protocolCarrierResidual() {
        // Empty index = what the scanner actually produces for `BinaryInteger` today
        // (measured: 6 typeDecls named BinaryInteger, every one with `inheritedTypes == []`).
        #expect(
            RoundTripTemplate.suggest(
                for: stridePair(on: "BinaryInteger"), inheritedTypesByName: [:]
            ) != nil,
            "If this starts vetoing, the scanner learned protocol inheritance — invert this test"
        )
    }
}
