import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The strict weak ordering `InverseLiftedPairing.candidates(in:vocabulary:)` hands to
/// `sorted(by:)`.
///
/// Its comparator was the sixth hand-rolled `(file, line)` ladder in this package, and the pass
/// that made `SourceLocation` `Comparable` over `(file, line, column)` reached the other five.
/// Two mutating methods declared on one line therefore compared **equal**, and the order of the
/// pairs they produce fell to whatever `sorted(by:)` happened to do — which Swift does not promise
/// is stable, in output people read as a diff.
///
/// `SourceLocationOrderingTests` states these laws for the conformance; this states them for the
/// comparator that now defers to it, because deferring to a total order is not the same as being
/// one — the reverse half is only consulted on a forward tie, and that fallback has to hold too.
@Suite("Lifted inverse pairs are strictly weakly ordered")
struct LiftedInversePairOrderingTests {

    private func valueSemanticResolver(carrier: String = "Bag") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "items", typeName: "[Int]")]
            )
        ])
    }

    private func lift(_ name: String, line: Int, column: Int) -> LiftedTransformation {
        LiftedTransformation.lift(
            FunctionSummary(
                name: name,
                parameters: [
                    Parameter(label: nil, internalName: "x", typeText: "Int", isInout: false)
                ],
                returnTypeText: "Void",
                isThrows: false,
                isAsync: false,
                isMutating: true,
                isStatic: false,
                location: SourceLocation(file: "Test.swift", line: line, column: column),
                containingTypeName: "Bag",
                bodySignals: .empty
            ),
            carrierKindResolver: valueSemanticResolver()
        )!
    }

    private func pair(
        forwardLine: Int,
        forwardColumn: Int = 1,
        reverseLine: Int,
        reverseColumn: Int = 1
    ) -> LiftedInversePair {
        LiftedInversePair(
            forward: lift("add", line: forwardLine, column: forwardColumn),
            reverse: lift("remove", line: reverseLine, column: reverseColumn),
            pairName: LiftedInversePair.NamePair(lhs: "add", rhs: "remove")
        )
    }

    /// Two pairs whose forward halves share a line and differ only in column — the case the old
    /// ladder called equivalent — plus enough neighbours to exercise the reverse-half fallback.
    private var pairs: [LiftedInversePair] {
        [
            pair(forwardLine: 1, forwardColumn: 5, reverseLine: 9),
            pair(forwardLine: 1, forwardColumn: 17, reverseLine: 9),
            pair(forwardLine: 1, forwardColumn: 5, reverseLine: 4),
            pair(forwardLine: 2, reverseLine: 9),
            pair(forwardLine: 10, reverseLine: 1)
        ]
    }

    @Test("distinct pairs are never equivalent")
    func distinctPairsAreOrdered() {
        // The defect, stated directly: the first two differ only in the forward half's column, and
        // the old comparator answered false in both directions — equivalent, order unpinned.
        let pairs = pairs
        for (lhsIndex, lhs) in pairs.enumerated() {
            for rhs in pairs.dropFirst(lhsIndex + 1) {
                let forward = InverseLiftedPairing.lessThan(lhs, rhs)
                let backward = InverseLiftedPairing.lessThan(rhs, lhs)
                #expect(forward != backward, "distinct pairs compared equivalent")
            }
        }
    }

    @Test("irreflexive — no pair precedes itself")
    func irreflexive() {
        for candidate in pairs {
            #expect(!InverseLiftedPairing.lessThan(candidate, candidate))
        }
    }

    @Test("asymmetric — at most one direction holds")
    func asymmetric() {
        for lhs in pairs {
            for rhs in pairs {
                let forward = InverseLiftedPairing.lessThan(lhs, rhs)
                let backward = InverseLiftedPairing.lessThan(rhs, lhs)
                #expect(!(forward && backward))
            }
        }
    }

    @Test("transitive")
    func transitive() {
        for first in pairs {
            for second in pairs where InverseLiftedPairing.lessThan(first, second) {
                for third in pairs where InverseLiftedPairing.lessThan(second, third) {
                    #expect(InverseLiftedPairing.lessThan(first, third))
                }
            }
        }
    }

    @Test("the forward half's column decides a same-line tie")
    func columnDecidesSameLineTie() {
        let earlier = pair(forwardLine: 1, forwardColumn: 5, reverseLine: 9)
        let later = pair(forwardLine: 1, forwardColumn: 17, reverseLine: 9)
        #expect(InverseLiftedPairing.lessThan(earlier, later))
        #expect(!InverseLiftedPairing.lessThan(later, earlier))
    }

    @Test("the reverse half decides when the forward halves are identical")
    func reverseHalfBreaksAForwardTie() {
        let earlier = pair(forwardLine: 1, forwardColumn: 5, reverseLine: 4)
        let later = pair(forwardLine: 1, forwardColumn: 5, reverseLine: 9)
        #expect(InverseLiftedPairing.lessThan(earlier, later))
        #expect(!InverseLiftedPairing.lessThan(later, earlier))
    }
}
