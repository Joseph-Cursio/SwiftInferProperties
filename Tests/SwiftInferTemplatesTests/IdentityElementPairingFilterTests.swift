import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// V1.6.1 — pair-formation skip-list filter for known cross-product
// mismatches. Complementary to v1.5's coverage veto: v1.5 suppresses
// pairs the kit already verifies; v1.6 suppresses pairs whose
// (kit-blessed-constant, stdlib-operator) combo doesn't bind to a
// kit-published identity law.

@Suite("IdentityElementPairing — V1.6.1 (constant, op) skip-list filter")
struct IdentityElementPairingFilterTests {

    // MARK: - (a) Cross-product mismatch on stdlib operators is skipped

    @Test("(zero, *) is filtered at pair-formation")
    func zeroTimesIsFiltered() {
        let pairs = makePairs(opName: "*", typeText: "T", identityName: "zero")
        #expect(pairs.isEmpty)
    }

    @Test("(zero, /) is filtered at pair-formation")
    func zeroDivIsFiltered() {
        let pairs = makePairs(opName: "/", typeText: "T", identityName: "zero")
        #expect(pairs.isEmpty)
    }

    @Test("(zero, -) is filtered at pair-formation")
    func zeroMinusIsFiltered() {
        let pairs = makePairs(opName: "-", typeText: "T", identityName: "zero")
        #expect(pairs.isEmpty)
    }

    @Test("(one, +) is filtered at pair-formation")
    func onePlusIsFiltered() {
        let pairs = makePairs(opName: "+", typeText: "T", identityName: "one")
        #expect(pairs.isEmpty)
    }

    @Test("(empty, *) is filtered at pair-formation")
    func emptyTimesIsFiltered() {
        let pairs = makePairs(opName: "*", typeText: "T", identityName: "empty")
        #expect(pairs.isEmpty)
    }

    @Test("(zero, pow) is filtered (V1.6.1 patch — math-library op-name gate)")
    func zeroPowIsFiltered() {
        // V1.6.1 maintenance patch added `pow` to `stdlibBinaryOperators`.
        // `pow(x, 0) == 1` (not `x`), so `.zero` is not pow's identity —
        // structurally the same kind of cross-product mismatch as
        // `(zero, *)`. Closes the cycle-3 ComplexModule survivor that
        // V1.6.1 originally couldn't reach.
        let pairs = makePairs(opName: "pow", typeText: "T", identityName: "zero")
        #expect(pairs.isEmpty)
    }

    @Test("(zero, **) is filtered (V1.6.1 patch — `**` exponent alternative spelling)")
    func zeroExponentIsFiltered() {
        let pairs = makePairs(opName: "**", typeText: "T", identityName: "zero")
        #expect(pairs.isEmpty)
    }

    // MARK: - (b) Kit-blessed combos still emit (v1.5 veto handles coverage)

    @Test("(zero, +) emits — kit-blessed combo, v1.5 veto handles coverage downstream")
    func zeroPlusEmits() {
        let pairs = makePairs(opName: "+", typeText: "T", identityName: "zero")
        #expect(pairs.count == 1)
    }

    @Test("(one, *) emits")
    func oneTimesEmits() {
        let pairs = makePairs(opName: "*", typeText: "T", identityName: "one")
        #expect(pairs.count == 1)
    }

    @Test("(empty, +) emits — kit-blessed for set-union semantics")
    func emptyPlusEmits() {
        let pairs = makePairs(opName: "+", typeText: "T", identityName: "empty")
        #expect(pairs.count == 1)
    }

    // MARK: - (c) Constants outside kit-blessed set always emit

    @Test("(none, +) emits — `none` not in kit-blessed set, no opinion")
    func noneOnAnyOpEmits() {
        let pairs = makePairs(opName: "+", typeText: "T", identityName: "none")
        #expect(pairs.count == 1)
    }

    @Test("(default, *) emits — `default` not in kit-blessed set")
    func defaultOnAnyOpEmits() {
        let pairs = makePairs(opName: "*", typeText: "T", identityName: "default")
        #expect(pairs.count == 1)
    }

    @Test("(none, /) emits — `none` not blessed, even for stdlib ops with no identity")
    func noneOnDivEmits() {
        let pairs = makePairs(opName: "/", typeText: "T", identityName: "none")
        #expect(pairs.count == 1)
    }

    // MARK: - (d) User-named ops always emit (kit-blessed constants pass through)

    @Test("(zero, merge) emits — user-named op, can't filter syntactically")
    func zeroMergeEmits() {
        let pairs = makePairs(opName: "merge", typeText: "T", identityName: "zero")
        #expect(pairs.count == 1)
    }

    @Test("(empty, intersect) emits — user-named op, deferred to v1.5 veto / cycle-4")
    func emptyIntersectEmits() {
        let pairs = makePairs(opName: "intersect", typeText: "T", identityName: "empty")
        #expect(pairs.count == 1)
    }

    @Test("(identity, combine) emits — kit-monoid posture, _ matches in v1.5 mapping")
    func identityCombineEmits() {
        // `(identity, _)` maps to `monoidIdentity` for any op-name. The
        // filter's stdlib-operator gate doesn't fire on `combine`, so
        // we'd pass through anyway — but this also documents the
        // expected emit-behavior on the kit's intended monoid carrier.
        let pairs = makePairs(opName: "combine", typeText: "T", identityName: "identity")
        #expect(pairs.count == 1)
    }

    // MARK: - (e) Type-shape filter still gates non-(T, T) -> T ops

    @Test("Existing type-shape filter still rejects non-binary ops (single-arg)")
    func nonBinaryOpStillRejected() {
        // Even with `(zero, +)` kit-blessed, the type-shape filter
        // (single-arg `T -> T` doesn't satisfy `(T, T) -> T`) keeps
        // pair-formation from emitting.
        let unaryPlus = FunctionSummary(
            name: "+",
            parameters: [Parameter(label: nil, internalName: "x", typeText: "T", isInout: false)],
            returnTypeText: "T",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: "T",
            bodySignals: .empty
        )
        let zero = IdentityCandidate(
            name: "zero",
            typeText: "T",
            containingTypeName: "T",
            location: SourceLocation(file: "T.swift", line: 5, column: 1)
        )
        let pairs = IdentityElementPairing.candidates(
            in: [unaryPlus],
            identities: [zero]
        )
        #expect(pairs.isEmpty, "Type-shape filter should reject unary op even with kit-blessed combo")
    }

    @Test("Existing type-shape filter still rejects mismatched-typed binary op")
    func mismatchedTypedBinaryOpStillRejected() {
        // `(Int, Int) -> Bool` doesn't satisfy `(T, T) -> T`.
        let cmp = FunctionSummary(
            name: "+",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Int", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "Int", isInout: false)
            ],
            returnTypeText: "Bool",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let zero = IdentityCandidate(
            name: "zero",
            typeText: "Int",
            containingTypeName: "Int",
            location: SourceLocation(file: "T.swift", line: 5, column: 1)
        )
        let pairs = IdentityElementPairing.candidates(
            in: [cmp],
            identities: [zero]
        )
        #expect(pairs.isEmpty)
    }
}

// MARK: - Shared helpers

/// V1.6.1 — convenience: build a binary op + same-typed identity
/// candidate and return the result of `IdentityElementPairing.candidates`.
/// Used by `IdentityElementPairingFilterTests` to assert pair-formation
/// emit/skip behaviour without rebuilding the same fixture each time.
func makePairs(
    opName: String,
    typeText: String,
    identityName: String
) -> [IdentityElementPair] {
    let operation = FunctionSummary(
        name: opName,
        parameters: [
            Parameter(label: nil, internalName: "lhs", typeText: typeText, isInout: false),
            Parameter(label: nil, internalName: "rhs", typeText: typeText, isInout: false)
        ],
        returnTypeText: typeText,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "T.swift", line: 1, column: 1),
        containingTypeName: typeText,
        bodySignals: .empty
    )
    let identity = IdentityCandidate(
        name: identityName,
        typeText: typeText,
        containingTypeName: typeText,
        location: SourceLocation(file: "T.swift", line: 5, column: 1)
    )
    return IdentityElementPairing.candidates(
        in: [operation],
        identities: [identity]
    )
}
