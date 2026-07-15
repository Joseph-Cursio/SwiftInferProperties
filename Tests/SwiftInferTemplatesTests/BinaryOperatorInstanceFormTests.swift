import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The 2026-07 instance-op recall widening — `binaryOperatorTypeSymmetrySignal`
/// now also accepts a one-parameter instance method over its OWN type
/// (`x.union(y)`), not just the free `union(x, y)`. Commutativity, associativity,
/// and binary-idempotence all ride the widened signal; the verify path already
/// speaks it via the `{ $0.method($1) }` receiver trampoline.
@Suite("Binary-operator signal — instance form (x.union(y))")
struct BinaryOperatorInstanceFormTests {

    private func method(
        _ name: String,
        operand: String,
        returns: String,
        type: String?,
        isStatic: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "other", typeText: operand, isInout: false)],
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: type,
            bodySignals: .empty
        )
    }

    @Test("a one-param instance method over its own type is a binary operator")
    func instanceUnionFires() throws {
        let union = method("union", operand: "Bag", returns: "Bag", type: "Bag")
        let comm = try #require(CommutativityTemplate.suggest(for: union))
        #expect(comm.templateName == "commutativity")
        // union is a curated semilattice verb → binary-idempotence fires too.
        #expect(BinaryIdempotenceTemplate.suggest(for: union) != nil)
    }

    @Test("a Self-typed operand also counts as the same type as the receiver")
    func selfTypedOperandFires() {
        // `combine` is a curated commutativity verb; `Self` == the receiver type.
        let combine = method("combine", operand: "Self", returns: "Self", type: "Bag")
        #expect(CommutativityTemplate.suggest(for: combine) != nil)
    }

    @Test("a different-typed operand is NOT a binary operator")
    func differentTypedOperandRejected() {
        // `scale(by: Int) -> Bag`: the operand is `Int`, not the receiver `Bag`.
        let scaled = method("combine", operand: "Int", returns: "Bag", type: "Bag")
        #expect(CommutativityTemplate.suggest(for: scaled) == nil)
    }

    @Test("a static one-param method is unary, not a binary operator (no receiver)")
    func staticOneParamRejected() {
        let union = method("union", operand: "Bag", returns: "Bag", type: "Bag", isStatic: true)
        #expect(BinaryIdempotenceTemplate.suggest(for: union) == nil)
        #expect(CommutativityTemplate.suggest(for: union) == nil)
    }

    @Test("a participle anti-commutativity verb suppresses the widened instance form")
    func subtractingSuppressed() {
        // `Set.subtracting(_:)` has the instance binary shape but is anti-commutative;
        // the widened veto (`subtracting`) lands it below the visible floor.
        let subtracting = method("subtracting", operand: "Bag", returns: "Bag", type: "Bag")
        #expect(CommutativityTemplate.suggest(for: subtracting) == nil)
    }
}
