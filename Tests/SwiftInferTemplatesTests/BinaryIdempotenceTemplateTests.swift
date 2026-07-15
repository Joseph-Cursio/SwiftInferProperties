import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The third semilattice leg — `op(x, x) == x`. Commutativity and associativity
/// already fire on the `(T, T) -> T` shape; this is the law that separates a
/// join/meet from an ordinary associative operator, and it requires a curated
/// verb because idempotence is a *rare* property of a binary operator.
@Suite("Binary idempotence — the semilattice's idempotent leg")
struct BinaryIdempotenceTemplateTests {

    private static let loc = SourceLocation(file: "Ops.swift", line: 1, column: 1)

    private func op(
        _ name: String,
        _ parameters: [Parameter],
        returns: String?,
        type: String? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: type != nil,
            location: Self.loc,
            containingTypeName: type,
            bodySignals: .empty
        )
    }

    private func param(_ type: String) -> Parameter {
        Parameter(label: nil, internalName: "value", typeText: type, isInout: false)
    }

    @Test("a curated join/meet over (T, T) -> T owes op(x, x) == x")
    func semilatticeVerbFires() throws {
        let maximum = op("max", [param("Int"), param("Int")], returns: "Int")
        #expect(BinaryIdempotenceTemplate.isSemilatticeOp(maximum))

        let suggestion = try #require(BinaryIdempotenceTemplate.suggest(for: maximum))
        #expect(suggestion.templateName == "binary-idempotence")
        // Shape (30) + name (40) — name required, so it always clears the visible tier.
        #expect(suggestion.score.total == 70)
        #expect(suggestion.score.tier == .likely)
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("op(x, x) == x"))
        // The confusion that makes this template worth having: it is not additive.
        #expect(caveats.contains("NOT true of additive"))
    }

    @Test("an additive op of the same shape is NOT idempotent — stays silent")
    func additiveOpIsRejected() {
        // `add` is `(Int, Int) -> Int` exactly like `max`, and it IS commutative
        // and associative — but `add(x, x) == 2x`, not `x`. The curated-verb gate
        // is what keeps this template from flooding on every binary operator.
        let add = op("add", [param("Int"), param("Int")], returns: "Int")
        #expect(BinaryIdempotenceTemplate.isSemilatticeOp(add) == false)
        #expect(BinaryIdempotenceTemplate.suggest(for: add) == nil)
    }

    @Test("a semilattice verb on the wrong shape does not fire")
    func wrongShapeIsRejected() {
        // Not (T, T) -> T: return type differs from the operands.
        let predicateMax = op("max", [param("Int"), param("Int")], returns: "Bool")
        #expect(BinaryIdempotenceTemplate.isSemilatticeOp(predicateMax) == false)
        // Unary: only one operand, so `op(x, x)` doesn't even type-check.
        let unaryMax = op("max", [param("Int")], returns: "Int")
        #expect(BinaryIdempotenceTemplate.isSemilatticeOp(unaryMax) == false)
    }
}
