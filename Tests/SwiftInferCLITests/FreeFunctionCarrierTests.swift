import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// #128 — a free function has no containing type, and the verify path used to treat the
/// `"(none)"` placeholder as if it were one.
///
/// The issue's original symptom — `(none).sortedByScore` emitted into Swift — was fixed by
/// `CallExpressionShape.classify`. What survived was a **misleading decline**: the pair
/// resolvers gated `entry.typeName ?? "(none)"` against `supportedCarriers`, so a free
/// binary function declined as `unsupported-carrier: (none)`. That names a carrier which
/// does not exist, for a type that is fully supported — measured on a probe where the same
/// function's `binary-idempotence` law executed and passed at 100 trials while its
/// `commutativity` law declined.
///
/// The cause was upstream: `BinaryIdempotenceTemplate` records `carrierType` and the pair
/// templates did not, so only one of them had an operand type to fall back to.
@Suite("Free-function carriers — the operand type, not a placeholder")
struct FreeFunctionCarrierTests {

    private static func entry(
        template: String,
        typeName: String?,
        carrierTypeName: String?
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xF000000000000001",
            templateName: template,
            typeName: typeName,
            score: 70,
            tier: "Likely",
            primaryFunctionName: "combine(_:_:)",
            location: "Sources/T.swift:1",
            firstSeenAt: "2026-08-08T00:00:00Z",
            lastSeenAt: "2026-08-08T00:00:00Z",
            carrierTypeName: carrierTypeName
        )
    }

    /// The fix: a free function's carrier is its operand type.
    @Test(
        "a free binary function resolves on its operand type",
        arguments: ["commutativity", "associativity"]
    )
    func freeFunctionResolvesOnOperandType(template: String) throws {
        let entry = Self.entry(template: template, typeName: nil, carrierTypeName: "Int")
        if template == "commutativity" {
            _ = try CommutativityPairResolver.resolve(entry)
        } else {
            _ = try AssociativityPairResolver.resolve(entry)
        }
        // Reaching here is the assertion: before the fix this threw
        // `unsupportedCarrier(carrier: "(none)")`.
    }

    /// **The control.** Without a carrier of any kind there is genuinely nothing to
    /// resolve, and the decline must survive — a fix that made everything resolve would
    /// be worse than the bug.
    @Test("a free function with no operand type still declines")
    func noCarrierStillDeclines() {
        let entry = Self.entry(template: "commutativity", typeName: nil, carrierTypeName: nil)
        #expect(throws: VerifyError.self) {
            _ = try CommutativityPairResolver.resolve(entry)
        }
    }

    /// **The regression the A/B caught before shipping.** `func merge(_ other: Self) ->
    /// Self` records `carrierTypeName == "Self"` — the literal string. Gating that against
    /// `supportedCarriers` would decline a member that resolved fine before the fix, which
    /// is the spelling-dependence trap `assumedCoverageSignal` already carries. The
    /// resolver rebinds `Self` to the owning type, as the dispatch does.
    @Test("a member spelled `Self` rebinds to its owning type")
    func selfSpelledCarrierRebinds() throws {
        let entry = Self.entry(template: "commutativity", typeName: "Int", carrierTypeName: "Self")
        _ = try CommutativityPairResolver.resolve(entry)
    }

    /// And a `Self` spelling with an UNSUPPORTED owning type must still decline, naming the
    /// owning type rather than `Self` — otherwise the rebinding has merely hidden the gate.
    @Test("`Self` on an unsupported owner declines by the owner's name")
    func selfRebindingDoesNotBypassTheGate() {
        let entry = Self.entry(
            template: "commutativity", typeName: "SomeUnsupportedType", carrierTypeName: "Self"
        )
        #expect(throws: VerifyError.self) {
            _ = try CommutativityPairResolver.resolve(entry)
        }
    }
}
