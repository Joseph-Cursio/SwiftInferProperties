import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The `LosslessStringConvertible` coverage veto — a guard on a door that is currently locked,
/// and the record of a **corrected verdict** rather than a fixed defect.
///
/// The swift.org study twice filed `initializerPairAdmissible`'s `guard label != "init"` as a
/// reach gap blocking the float parse/print round-trip — once in the `roundtrip` population,
/// once at `PrintFloat.swift.gyb:795/908` — and called the second a *"second independent
/// witness"* for a blocker to fix. Relaxing it would have made `discover` propose
/// `"LosslessStringConvertible.roundTrip"` (`LosslessStringConvertibleLaws.swift:40`),
/// `Value(String(describing: x)) == x`, which PropertyLawKit already runs for every conformer
/// — the exact `Strideable` double-report found and fixed the same day.
@Suite("Round-trip — the LosslessStringConvertible round-trip belongs to the kit")
struct LosslessCoverageVetoTests {

    private func member(
        _ name: String, _ param: String, _ ret: String, on carrier: String = "Meters"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "x", typeText: param, isInout: false)],
            returnTypeText: ret,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Meters.swift", line: 1, column: 1),
            containingTypeName: carrier, bodySignals: .empty
        )
    }

    private func parsePrintPair(on carrier: String = "Meters") -> FunctionPair {
        FunctionPair(
            forward: member("init", "String", carrier, on: carrier),
            reverse: member("description", carrier, "String", on: carrier)
        )
    }

    @Test("a conformer's init/description pair is vetoed")
    func conformerIsVetoed() {
        #expect(
            RoundTripTemplate.losslessStringCoverageVeto(
                for: parsePrintPair(),
                inheritedTypesByName: ["Meters": ["LosslessStringConvertible"]]
            ) != nil
        )
    }

    @Test("WITHOUT the conformance nothing runs the law, so it is not vetoed")
    func nonConformerIsNotVetoed() {
        // The conformance is not redundant with the names. A type may define `init(_ text:
        // String)` and `description` without conforming, and then no other tool states the
        // law and this catalog should.
        #expect(
            RoundTripTemplate.losslessStringCoverageVeto(
                for: parsePrintPair(), inheritedTypesByName: [:]
            ) == nil
        )
    }

    @Test("the veto is PAIR-scoped: other round-trips on a conforming carrier survive")
    func vetoDoesNotSwallowUnrelatedRoundTrips() {
        // `Int`, `Double` and `String` all conform to `LosslessStringConvertible` and all
        // carry genuine unrelated round-trips. A carrier-only check would swallow every one.
        let unrelated = FunctionPair(
            forward: member("encode", "Meters", "Data"),
            reverse: member("decode", "Data", "Meters")
        )
        #expect(
            RoundTripTemplate.losslessStringCoverageVeto(
                for: unrelated,
                inheritedTypesByName: ["Meters": ["LosslessStringConvertible"]]
            ) == nil
        )
    }

    @Test("`debugDescription` is a different member and is not matched")
    func debugDescriptionIsNotMatched() {
        // `LosslessStringConvertible` refines `CustomStringConvertible`, so the kit's law is
        // stated against `description`. Nothing requires `debugDescription` to round-trip —
        // and on `Double` it is deliberately the *shortest* form, a stronger claim.
        let debugPair = FunctionPair(
            forward: member("init", "String", "Meters"),
            reverse: member("debugDescription", "Meters", "String")
        )
        #expect(
            RoundTripTemplate.losslessStringCoverageVeto(
                for: debugPair,
                inheritedTypesByName: ["Meters": ["LosslessStringConvertible"]]
            ) == nil
        )
    }

    /// The reason this veto has no end-to-end counterpart, pinned so it is not mistaken for a
    /// gap. `initializerPairAdmissible` rejects the pair upstream, because pairing evidence for
    /// `round-trip` is name-stem overlap and an unlabelled `init` synthesizes to the bare name
    /// `"init"` with no stem. If this starts producing a suggestion, the gate was relaxed —
    /// and the veto above is what should then fire instead of a double-report.
    @Test("the pair is still rejected upstream, so nothing reaches scoring today")
    func pairIsRejectedUpstream() {
        #expect(
            !FunctionPairing.initializerLabelStemMatches(label: "init", encodeName: "description"),
            "If this flips, the init-label gate changed — confirm the veto above now fires"
        )
    }
}
