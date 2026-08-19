import Foundation
import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// **Do commutativity and associativity fire on operands that cannot be swapped?**
///
/// `docs/measurements/refutation-hand-check.md` found that **3 of 3** `Likely` refutations
/// were laws over operands with distinct roles — `pairShrinkPhase(carrier:oracle:)`
/// interpolates `carrier` into a *type* position and `oracle` into an *expression*
/// position, so a swap would not compile. This asks how large that class is.
///
/// ## This is NOT a reopen of the same-name decline
///
/// `docs/measurements/same-name-differential-pairing.md` declined a rule whose dominant
/// false positive it called *"undeclared role interfaces"*. **That is a different
/// mechanism**: a shared *function name* naming a role across types, where the false
/// positive is pairing two functions. This is two *parameters of one function*, where the
/// false positive is a law over non-interchangeable operands. The two were briefly written
/// up as one cause on 2026-08-19 and corrected the same day — so this measurement stands
/// on its own bar rather than inheriting that document's ≥50%.
///
/// ## The candidate signal, stated before the count
///
/// **A `(T, T) -> T` whose two parameters carry DIFFERENT external labels, neither `_`,
/// is role-distinct.** `carrier:oracle:` and `functionCall:carrier:` qualify;
/// `merge(_:)` and `merge(_:_:)` do not. It reads labels, not bodies — which is what makes
/// it cheap and also what bounds it: a function can have symmetric labels and asymmetric
/// roles, and this would miss that.
@Suite("Census — how many binary-operator laws rest on role-distinct operands?", .serialized)
struct ParameterRoleCensusMeasuredTests {

    /// Templates whose law quantifies over interchangeable operands.
    static let binaryOperatorTemplates: Set<String> = [
        "commutativity", "associativity"
    ]

    @Test("control — the corpora produced binary-operator suggestions at all")
    func theCensusReaches() {
        #expect(!Self.readings.isEmpty, "no corpus scanned")
        #expect(Self.readings.contains { $0.total > 0 }, """
        No corpus produced a commutativity or associativity suggestion, so every split \
        below is the instrument's rather than the corpus's.
        """)
    }

    @Test("census — role-distinct operands under a binary-operator law")
    func census() {
        for reading in Self.readings {
            print("""
            \(reading.corpus): \(reading.total) commutativity/associativity suggestions
              role-distinct (labels differ, neither `_`): \(reading.roleDistinct)
              symmetric:                                  \(reading.total - reading.roleDistinct)
            """)
            for row in reading.roleRows.prefix(8) { print("    ROLE \(row)") }
        }
    }
}
