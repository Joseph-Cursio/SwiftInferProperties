import Foundation
import PropertyLawKit
@testable import SwiftInferCore
import Testing

// Self-dogfood road test, 2026-08-08 — `swift-infer discover --target
// SwiftInferCore` proposed this one directly, at `Likely` (70):
//
//     homomorphism  lawTotal(for:)  ([Finding]) -> Int
//       ✓ Additive-measure shape: [Finding] -> Int (integer measure over an array)
//       ✓ Curated measure verb match: 'lawTotal' — an additive quantity over the
//         elements, so it owes `h(a + b) == h(a) + h(b)`
//       ✓ Proven analog: `Array` satisfies `(a + b).count == a.count + b.count`
//
// It is worth landing rather than waving through, because the docstring on
// `lawTotal` makes a claim the shape alone does not: the sum is taken **after**
// each carrier's own union and is *deliberately not deduplicated across
// carriers* — "`Equatable.reflexivity` on `Foo` and on `Bar` are two checks, two
// suites, two opportunities to fail. This counts work, not distinct law names."
//
// That sentence is exactly what the homomorphism law tests. A future
// "improvement" that deduplicated law names across carriers would look tidier,
// would keep every existing example test green, and would break additivity —
// because `lawTotal(a + b)` would then be *less* than `lawTotal(a) + lawTotal(b)`
// whenever two carriers share a law. The law is the docstring, executable.
//
// `ProtocolCoverageAudit` itself is the subject of `docs/measurements/
// protocol-coverage-law-drift.md`, where an audit that "counts carriers whose
// conformances the kit covers, not laws actually suppressed" already shipped a
// wrong total once. This pins the counting rule.
@Suite("Road test — lawTotal is a monoid homomorphism over finding concatenation")
struct LawTotalHomomorphismPropertyTests {

    /// The law pool the generator draws from. Deliberately small so that distinct
    /// carriers end up with **overlapping** law sets — the only population in
    /// which `lawTotal`'s non-deduplication rule is observable at all.
    private static let lawPool: [KnownProperty] = [
        .additiveAssociative, .additiveCommutative, .additiveIdentityZero, .additiveInverse
    ]

    // MARK: - Generator
    //
    // Findings are built with real `KnownProperty` values rather than a stub
    // count, because the law is about `coveredLaws.count` and `coveredLaws` is a
    // `Set` — a generator that handed each finding a distinct integer would test
    // addition, not the function. Drawing from a small shared pool guarantees
    // carriers whose law sets *overlap*, which is the only population where the
    // non-deduplication rule is observable.

    private static let findingGen = zip(
        Gen.element(of: ["Foo", "Bar", "Baz", "Qux"]).map { $0! },
        Gen.int(in: 0...4)
    ).map { typeName, lawCount in
        ProtocolCoverageAudit.Finding(
            typeName: typeName,
            coveringConformance: "Equatable",
            standing: .assumed,
            coveredLaws: Set(Self.lawPool.prefix(lawCount))
        )
    }

    private static let findingsGen = findingGen.array(of: 0...3)

    // MARK: - Laws

    /// **The homomorphism.** `h(a + b) == h(a) + h(b)` over array concatenation.
    ///
    /// This is the law that catches cross-carrier deduplication: it fails the
    /// moment `lawTotal` stops counting a shared law twice.
    @Test("lawTotal is additive over concatenation")
    func lawTotalIsAdditive() async {
        await propertyCheck(input: Self.findingsGen, Self.findingsGen) { left, right in
            #expect(
                ProtocolCoverageAudit.lawTotal(for: left + right)
                    == ProtocolCoverageAudit.lawTotal(for: left)
                        + ProtocolCoverageAudit.lawTotal(for: right),
                "lawTotal is not additive over \(left.count) + \(right.count) findings"
            )
        }
    }

    /// **The identity.** The empty finding list contributes nothing.
    ///
    /// Half of what makes the previous law a *monoid* homomorphism rather than
    /// merely an additive one, and the half a wrong implementation is likeliest
    /// to satisfy by accident — stated anyway, because together they pin
    /// `reduce(0, +)` and exclude `reduce(1, +)`.
    @Test("lawTotal of no findings is zero")
    func lawTotalOfEmptyIsZero() {
        #expect(ProtocolCoverageAudit.lawTotal(for: []) == 0)
    }

    /// **Order independence.** A count is a property of the multiset, not of the
    /// order the audit happened to walk the conformance index in.
    ///
    /// Not implied by additivity: `h(a + b) == h(a) + h(b)` says nothing about
    /// `h` being blind to the arrangement *inside* a list.
    @Test("lawTotal does not depend on finding order")
    func lawTotalIsOrderIndependent() async {
        await propertyCheck(input: Self.findingsGen) { findings in
            #expect(
                ProtocolCoverageAudit.lawTotal(for: findings)
                    == ProtocolCoverageAudit.lawTotal(for: findings.reversed())
            )
        }
    }

    /// **Monotonicity.** Appending findings can never lower the total.
    ///
    /// The cheap sanity law that a signed-arithmetic slip would fail while
    /// additivity still held on the non-negative inputs a generator usually draws.
    @Test("appending findings never lowers the total")
    func lawTotalIsMonotone() async {
        await propertyCheck(input: Self.findingsGen, Self.findingsGen) { left, right in
            #expect(
                ProtocolCoverageAudit.lawTotal(for: left + right)
                    >= ProtocolCoverageAudit.lawTotal(for: left)
            )
        }
    }
}
