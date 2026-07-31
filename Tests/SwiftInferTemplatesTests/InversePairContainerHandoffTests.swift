import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The `[T]` / `T?` payload rewrite, seen from the template gate.
///
/// `EquatableResolver` now gives a container its payload's verdict, so an
/// array- or optional-carrier pair defers to `RoundTripTemplate` the way a bare
/// `Int` carrier always did. The deferral is only an improvement if the pair is
/// actually picked up on the other side — otherwise the rewrite trades a weak
/// suggestion for no suggestion, which is a silent recall loss rather than the
/// intended promotion. That handoff is what this suite pins.
///
/// Split from `InversePairTemplateTests` on the 250-line type-body cap.
@Suite("InversePairTemplate — Array / Optional payload handoff")
struct InversePairContainerHandoffTests {

    /// `[T]` and `T?` now inherit their payload's verdict, so an array- or
    /// optional-carrier pair defers to `RoundTripTemplate` exactly as a bare
    /// `Int` carrier does. Before the rewrite these classified `.unknown` and
    /// were demoted here — the same failure mode that put `Data` in
    /// `curatedEquatableStdlib` by hand.
    @Test("Array and Optional carriers of an Equatable payload defer to RoundTripTemplate")
    func containerOfEquatablePayloadDefers() {
        let resolver = EquatableResolver(typeDecls: [])
        for carrier in ["[String]", "String?", "[Int]", "URL?"] {
            let pair = makePair(
                forwardName: "encode",
                reverseName: "decode",
                forwardParam: carrier,
                forwardReturn: "Data"
            )
            #expect(
                InversePairTemplate.suggest(for: pair, equatableResolver: resolver) == nil,
                "\(carrier) should defer to RoundTripTemplate"
            )
        }
    }

    /// The deferral is only useful if the pair is actually picked up on the
    /// other side. Without this, the rewrite would trade a weak suggestion for
    /// no suggestion at all — a silent recall loss rather than a promotion.
    @Test("RoundTripTemplate picks up the array-carrier pair the gate handed off")
    func roundTripClaimsTheHandedOffPair() {
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "[String]",
            forwardReturn: "Data"
        )
        #expect(InversePairTemplate.suggest(for: pair, equatableResolver: EquatableResolver(typeDecls: [])) == nil)
        #expect(RoundTripTemplate.suggest(for: pair) != nil, "the pair must not vanish between templates")
    }

    /// An array of a payload that is itself unknown is still unknown, so the
    /// pair stays here rather than being handed to a template that needs `==`.
    @Test("Array of an unknown payload still fires inverse-pair")
    func containerOfUnknownPayloadStillFires() {
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "[Mystery]",
            forwardReturn: "Data"
        )
        #expect(InversePairTemplate.suggest(for: pair, equatableResolver: EquatableResolver(typeDecls: [])) != nil)
    }

    private func makePair(
        forwardName: String,
        reverseName: String,
        forwardParam: String,
        forwardReturn: String
    ) -> FunctionPair {
        func summary(_ name: String, _ param: String, _ returns: String, line: Int) -> FunctionSummary {
            FunctionSummary(
                name: name,
                parameters: [Parameter(label: nil, internalName: "x", typeText: param, isInout: false)],
                returnTypeText: returns,
                isThrows: false,
                isAsync: false,
                isMutating: false,
                isStatic: false,
                location: SourceLocation(file: "Test.swift", line: line, column: 1),
                containingTypeName: nil,
                bodySignals: .empty
            )
        }
        return FunctionPair(
            forward: summary(forwardName, forwardParam, forwardReturn, line: 1),
            reverse: summary(reverseName, forwardReturn, forwardParam, line: 5)
        )
    }
}
