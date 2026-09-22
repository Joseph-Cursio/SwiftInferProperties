import Foundation
import SwiftInferCore

/// **Do not write a stub whose law compares results with `==` over a project type nothing makes
/// `Equatable`.**
///
/// ```swift
/// // private func fallbackLayout(_ graph: LayoutGraph) -> LayoutGraph   — struct, no conformance
/// property: { (value: LayoutGraph) in fallbackLayout(fallbackLayout(value)) == fallbackLayout(value) }
/// // error: referencing operator function '==' on 'Equatable' requires that 'LayoutGraph' conform to 'Equatable'
/// ```
///
/// ## Why this gate did not already exist
///
/// `UnverifiableCause.carrierNotEquatable` has existed since `inverse-pair-identity-element-composers-scope.md`
/// shipped it — **in the VERIFY path only** (`VerifyCommand+TemplateDispatch`). The accept path,
/// which is what writes these stubs, had no equivalent, so a law needing `==` over a carrier with
/// no `==` was written and handed to the compiler. `UnorderedCarrierGate` is the same rule for
/// `Comparable` and `monotonicity`; this is its `Equatable` half, which was missing.
///
/// Measured on `SwiftUMLStudio`: `DagreLayoutEngine.fallbackLayout` was one of the two rows the
/// widening rule freed into a further error rather than into a compile — **invisible until access
/// stopped hiding it**, #499's mechanism at a fifth site.
///
/// ## It declines only on positive evidence, and `Equatable` is NOT inferred from members
///
/// A type is declined when it is a **scanned project type** and no chain of its inheritance
/// clauses reaches `Equatable` or a protocol refining it. A type the scan never saw is left alone,
/// because *not in the index* is not *not Equatable* — the `EquatableResolver` posture of
/// `.unknown` rather than `.notEquatable`, which CLAUDE.md records as the reason that component
/// could not carry this.
///
/// ⚠ **Swift synthesises `Equatable` only where it is DECLARED.** A struct whose every member is
/// `Equatable` is not itself `Equatable` until it says so, so there is no member walk here and
/// adding one would make the gate wrong in the direction that costs laws.
enum UnequatableCarrierGate {

    /// `Equatable` and the standard protocols that refine it.
    ///
    /// `Hashable` and `Comparable` both refine `Equatable`, so either is enough. The numeric and
    /// string protocols are listed for the same reason `UnorderedCarrierGate` lists them: a type
    /// whose inheritance clause names one has `==`.
    static let equatableRefiners: Set<String> = [
        "Equatable", "Hashable", "Comparable", "Strideable",
        "BinaryInteger", "FixedWidthInteger", "SignedInteger", "UnsignedInteger",
        "FloatingPoint", "BinaryFloatingPoint", "StringProtocol", "Real",
        "CaseIterable", "RawRepresentable", "Error", "OptionSet", "SetAlgebra"
    ]

    /// Templates whose emitted law states itself with `==` over the subject's own type.
    ///
    /// Listed rather than inferred: *does the stub text contain `==`* is a text check over
    /// generated code, and an arm comparing something OTHER than the carrier — `predicate` returns
    /// `Bool`, whatever it takes — must not be gated on the carrier's equality.
    static let armsComparingTheCarrier: Set<String> = [
        "idempotence", "involution", "normal-form"
    ]

    /// Why no stub can be written, or `nil` when the carrier may have `==`.
    ///
    /// Named parameters rather than a `Context`, as its two sibling gates are, so the rule is
    /// testable without building one.
    static func declineReason(
        for suggestion: Suggestion,
        scannedTypeNames: Set<String>,
        inheritedTypesByName: [String: Set<String>]
    ) -> String? {
        guard armsComparingTheCarrier.contains(suggestion.templateName),
              let evidence = suggestion.evidence.first,
              let carrier = InteractiveTriage.paramType(from: evidence.signature)
        else { return nil }
        let name = ProtocolCoverageMap.strippingGenericParameters(
            carrier.trimmingCharacters(in: .whitespaces)
        )
        let equatable = reachesEquatable(
            name,
            scannedTypeNames: scannedTypeNames,
            inheritedTypesByName: inheritedTypesByName
        )
        guard scannedTypeNames.contains(name), !equatable else { return nil }
        return "\(evidence.displayName) takes \(carrier), which no scanned declaration makes "
            + "Equatable, and '\(suggestion.templateName)' compares its results with `==`"
    }

    /// Whether any chain of inheritance clauses from `name` reaches an `Equatable` refiner,
    /// stepping only through scanned names — the same walk `UnorderedCarrierGate` makes, and the
    /// same raw-type caution: `enum Level: Int` names `Int` and is not thereby `Equatable`.
    static func reachesEquatable(
        _ name: String,
        scannedTypeNames: Set<String>,
        inheritedTypesByName: [String: Set<String>]
    ) -> Bool {
        var seen: Set<String> = []
        var pending = [name]
        while let current = pending.popLast() {
            guard seen.insert(current).inserted else { continue }
            let inherited = inheritedTypesByName[current] ?? []
            if !inherited.isDisjoint(with: equatableRefiners) { return true }
            pending.append(contentsOf: inherited.filter {
                scannedTypeNames.contains($0)
                    || (inheritedTypesByName[$0] != nil && ProtocolCoverageMap.stdlibConformances[$0] == nil)
            })
        }
        return false
    }
}
