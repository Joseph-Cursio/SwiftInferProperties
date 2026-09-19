import Foundation
import SwiftInferCore

/// **Do not write a `monotonicity` stub over a project type nothing makes `Comparable`.**
///
/// The stub draws two values and sorts them with `<` so the law can read `f(lo) <= f(hi)`. Over
/// a type with no ordering there is no law to state, and the file cannot compile:
///
/// ```swift
/// // public func area(_ shape: Shape) -> Double      — `enum Shape`, not Comparable
/// return lhs < rhs ? (lhs, rhs) : (rhs, lhs)
/// // error: referencing operator function '<' on 'Comparable' requires that 'Shape' conform to 'Comparable'
/// ```
///
/// Measured on the 2026-09-19 corpus funnel re-run: `Shape` (pbt-book), `CIRunResult`
/// (SwiftAssist) and `CloneClass` (SwiftCloneDetector) each emitted one. Collections and tuples
/// are declined by their spelling in `FloatingPointEquatableTypes.isOrderableCarrier`; this gate
/// is the half that needs conformances, which is why it reads the index rather than the text.
///
/// ## It declines only on positive evidence
///
/// A type is declined when it is a **scanned project type** and no chain of its inheritance
/// clauses — across every scanned file, extensions included — reaches `Comparable` or a
/// protocol refining it. A type the scan never saw (a framework type, a dependency's type) is
/// left alone, because *not in the index* is not *not Comparable*; that is the
/// `EquatableResolver` posture of `.unknown` rather than `.notEquatable`.
///
/// ⚠ **A raw type is not a conformance.** `enum Level: Int` lists `Int` in its inheritance
/// clause and is not `Comparable` — only a declared `Comparable` synthesises `<` for an enum. So
/// the walk steps through scanned names only, never into a stdlib concrete type's conformances.
enum UnorderedCarrierGate {

    /// `Comparable` and the standard protocols that refine it. `Real` is swift-numerics', listed
    /// because it is the one dependency protocol this toolchain's corpora are known to adopt.
    static let comparableRefiners: Set<String> = [
        "Comparable", "Strideable",
        "BinaryInteger", "FixedWidthInteger", "SignedInteger", "UnsignedInteger",
        "FloatingPoint", "BinaryFloatingPoint", "StringProtocol", "Real"
    ]

    /// Why no `monotonicity` stub can be written, or `nil` when the carrier may be ordered.
    ///
    /// Named parameters rather than a `Context`, as `GenericSubjectGate.declineReason` is, so the
    /// rule is testable without building one.
    static func declineReason(
        for suggestion: Suggestion,
        scannedTypeNames: Set<String>,
        inheritedTypesByName: [String: Set<String>]
    ) -> String? {
        guard suggestion.templateName == "monotonicity",
              let evidence = suggestion.evidence.first,
              let carrier = InteractiveTriage.paramType(from: evidence.signature)
        else { return nil }
        let name = ProtocolCoverageMap.strippingGenericParameters(
            carrier.trimmingCharacters(in: .whitespaces)
        )
        guard scannedTypeNames.contains(name),
              !reachesComparable(name, scannedTypeNames: scannedTypeNames, inheritedTypesByName: inheritedTypesByName)
        else { return nil }
        return "\(evidence.displayName) takes \(carrier), which no scanned declaration makes "
            + "Comparable, and 'monotonicity' orders its drawn pair with `<`"
    }

    /// Whether any chain of inheritance clauses from `name` reaches a `Comparable` refiner,
    /// stepping only through scanned names (see the raw-type note on the type).
    static func reachesComparable(
        _ name: String,
        scannedTypeNames: Set<String>,
        inheritedTypesByName: [String: Set<String>]
    ) -> Bool {
        var seen: Set<String> = []
        var pending = [name]
        while let current = pending.popLast() {
            guard seen.insert(current).inserted else { continue }
            let inherited = inheritedTypesByName[current] ?? []
            if !inherited.isDisjoint(with: comparableRefiners) { return true }
            pending.append(contentsOf: inherited.filter {
                scannedTypeNames.contains($0)
                    || (inheritedTypesByName[$0] != nil && ProtocolCoverageMap.stdlibConformances[$0] == nil)
            })
        }
        return false
    }
}
