import SwiftInferCore

extension FunctionSummary {
    /// Veto signal raised when the body calls a non-deterministic API: such a
    /// function cannot satisfy a deterministic algebraic property, so the
    /// suggestion is suppressed. `nil` when the body is clean.
    ///
    /// Previously copy-pasted as `nonDeterministicVeto(for summary:)` across
    /// five templates (and delegated to by the IdentityElement and Composition
    /// single-member forms).
    var nonDeterministicVetoSignal: Signal? {
        guard bodySignals.hasNonDeterministicCall else {
            return nil
        }
        let calls = bodySignals.nonDeterministicAPIsDetected.joined(separator: ", ")
        return Signal(
            kind: .nonDeterministicBody,
            weight: Signal.vetoWeight,
            detail: "Non-deterministic API in body: \(calls)"
        )
    }

    /// `+30` signal when the function is a binary operator over one type — either
    /// the free/static form `(T, T) -> T` or the instance form `self: T`,
    /// `func op(_ other: T) -> T` (the receiver is the first operand). `nil`
    /// otherwise.
    ///
    /// Shared by the associativity, commutativity, and binary-idempotence
    /// templates. The instance form is the recall-widening epic (2026-07):
    /// idiomatic Swift writes `x.union(y)`, not a free `union(x, y)`, and the
    /// verify path already speaks it (the `{ $0.method($1) }` receiver
    /// trampoline), so widening the *signal* is all that was missing.
    var binaryOperatorTypeSymmetrySignal: Signal? {
        freeBinaryOperatorTypeSymmetrySignal ?? instanceBinaryOperatorTypeSymmetrySignal
    }

    /// The free/static form: `(T, T) -> T`.
    private var freeBinaryOperatorTypeSymmetrySignal: Signal? {
        guard parameters.count == 2,
              !isMutating else {
            return nil
        }
        // Cycle 149 (Lever B) — exclude the stdlib Collection index-traversal
        // requirements. On a Collection whose `Index == Int` (e.g.
        // `OrderedSet`), `distance(from:to:)` and `index(_:offsetBy:)` are
        // literally `(Int, Int) -> Int`, so they spuriously match the
        // `(T, T) -> T` binary-operator shape — but they are never algebraic
        // binary operators (`distance` is antisymmetric, not commutative;
        // index/offset arithmetic over indices is neither commutative nor
        // associative). Matched by base name + argument labels so a same-named
        // user method with different labels is unaffected.
        if isCollectionIndexTraversal {
            return nil
        }
        let first = parameters[0]
        let second = parameters[1]
        guard !first.isInout,
              !second.isInout,
              first.typeText == second.typeText,
              let returnType = returnTypeText,
              returnType == first.typeText,
              returnType != "Void",
              returnType != "()" else {
            return nil
        }
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Type-symmetry signature: (T, T) -> T (T = \(returnType))"
        )
    }

    /// The instance form: a non-`static`, non-`mutating` method taking one
    /// operand of the receiver's own type and returning that type — `self: T`,
    /// `func op(_ other: T) -> T`, so `self` is the first operand. The operand is
    /// matched as `Self` or the containing type's own name (both mean "same type
    /// as the receiver"), which keeps `func scaled(by factor: Double) -> Self`
    /// (a different-typed operand) out. `distance`/`index(after:)`-style
    /// traversals don't reach here: their operand is `Index`, not the collection.
    private var instanceBinaryOperatorTypeSymmetrySignal: Signal? {
        guard parameters.count == 1,
              !isMutating,
              !isStatic,
              let containing = containingTypeName,
              let param = parameters.first,
              !param.isInout,
              let returnType = returnTypeText,
              param.typeText == returnType,
              param.typeText == "Self" || param.typeText == containing,
              returnType != "Void",
              returnType != "()" else {
            return nil
        }
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Type-symmetry signature: (self: T, other: T) -> T (T = \(returnType))"
        )
    }

    /// Cycle 149 (Lever B) — is this one of the stdlib `Collection` /
    /// `BidirectionalCollection` index-traversal requirements that, on an
    /// `Index == Int` collection, masquerade as `(Int, Int) -> Int` binary
    /// operators? Matched by base name + argument labels (not the full
    /// signature string) so an unrelated user method named `distance` /
    /// `index` with different labels still qualifies as a real candidate.
    var isCollectionIndexTraversal: Bool {
        let labels = parameters.map(\.label)
        return (name == "distance" && labels == ["from", "to"])
            || (name == "index" && labels == [nil, "offsetBy"])
    }
}
