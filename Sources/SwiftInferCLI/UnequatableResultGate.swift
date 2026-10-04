import Foundation
import PropertyLawCore
import SwiftInferCore

/// **Do not write a law that compares two RESULTS with `==` over a project type nothing makes
/// `Equatable`.**
///
/// ```swift
/// // static func fix(_ source: String) -> FixResult   — struct, no conformance
/// property: { value in SkillLinterFixer.fix(value) == SkillLinterFixer.fix(value) }
/// // error: referencing operator function '==' on 'Equatable' requires that 'FixResult' conform to 'Equatable'
/// ```
///
/// `UnequatableCarrierGate` asks this of the subject's PARAMETER, for the laws that compare the
/// carrier with itself (`idempotence`, `involution`, `normal-form`). The determinism law compares
/// what the subject RETURNS, and so does the docstring advisory's reference oracle, and neither
/// had a gate: `TupleResultShape` answered for tuples and nothing answered for a nominal result.
/// On SwiftAssist, `SkillLinterFixer.fix(…)` returning `FixResult` was one of the scaffolds that
/// still failed once its call was repaired.
///
/// ## It declines only on positive evidence
///
/// Each identifier in the result spelling is looked up among the scanned types — after `Self` is
/// read as the declaring type and nested names are qualified the way a test file must write them.
/// A scanned declaration is let through when:
///
/// - it is an enum whose cases all have no payload, which Swift makes `Equatable` without being
///   asked (`UnequatableCarrierGate`'s header predates this and does not say so); or
/// - its own inheritance clause, or the cross-file conformance index under its qualified or its
///   bare name, reaches `Equatable` or a protocol refining it. Both names are needed because
///   `inheritedTypesByName` is keyed by `TypeDecl.name`, which is bare for a nested declaration,
///   while `typeShapesByName` is keyed by the qualified one; or
/// - a chain leaves what the scan can see — a superclass or protocol from another module that is
///   not known to stop short of `Equatable`. `NSObject` is `Equatable`, and so is anything
///   conforming to `AdditiveArithmetic`, and neither is on `UnequatableCarrierGate`'s refiner
///   list; reading such a name as *not Equatable* would withdraw stubs that compile, which is the
///   one thing this gate must not do (both checked with `swiftc`, Swift 6.4).
///
/// Anything else that was scanned declines. A type the scan never saw — the standard library,
/// another module, a protocol — never does: *not in the index* is not *not Equatable*.
enum UnequatableResultGate {

    /// Why the determinism stub for this suggestion cannot compare its results, or `nil`.
    ///
    /// Only `determinism`; and only when `SubjectCallPlan` would write a call, since a declined
    /// plan has its own, earlier reason.
    static func declineReason(
        for suggestion: Suggestion,
        typeShapesByName: [String: TypeShape],
        inheritedTypesByName: [String: Set<String>]
    ) -> String? {
        guard suggestion.templateName == "determinism",
              let evidence = suggestion.evidence.first,
              case let .plan(plan) = SubjectCallPlan.outcome(for: evidence)
        else { return nil }
        return declineReason(
            display: evidence.displayName,
            returnTypeText: plan.returnTypeText,
            owner: evidence.qualifiedTypeName,
            typeShapesByName: typeShapesByName,
            inheritedTypesByName: inheritedTypesByName
        )
    }

    /// Why `display`'s result, spelled `returnTypeText` inside `owner`, has no `==`, or `nil`.
    ///
    /// - Parameter typeUniverse: the qualified names nested spellings are resolved against;
    ///   `nil` means the scanned types' own keys.
    static func declineReason(
        display: String,
        returnTypeText: String,
        owner: String?,
        typeShapesByName: [String: TypeShape],
        inheritedTypesByName: [String: Set<String>],
        typeUniverse: Set<String>? = nil
    ) -> String? {
        let scanned = Set(typeShapesByName.keys)
        let selfless = owner.map { SubjectCallPlan.replacingSelf(in: returnTypeText, with: $0) } ?? returnTypeText
        let spelled = TypeShapeBuilder.resolvedSpelling(
            selfless, enclosing: owner ?? "", universe: typeUniverse ?? scanned
        )
        let unequatable = identifiers(in: spelled).first { name in
            guard let shape = typeShapesByName[name], shape.hasPrimaryDeclaration else { return false }
            if isImplicitlyEquatable(shape) { return false }
            return declaresEquatable(name, shape: shape, scanned: scanned, inheritedTypesByName: inheritedTypesByName)
                == false
        }
        guard let unequatable else { return nil }
        return "\(display) returns \(returnTypeText), and no scanned declaration makes \(unequatable) "
            + "Equatable, so `==` cannot compare two results"
    }

    /// An enum whose every case is payload-free: Swift synthesises `Equatable` (and `Hashable`)
    /// for it without a declaration. An enum whose cases were not captured counts too, which
    /// errs toward writing the stub.
    static func isImplicitlyEquatable(_ shape: TypeShape) -> Bool {
        shape.kind == .enum && shape.enumCases.allSatisfy(\.associatedValues.isEmpty)
    }

    /// Standard-library protocols that do NOT make a conformer `Equatable` — the only foreign names
    /// a chain may stop at and still count as evidence. Any other foreign name might refine
    /// `Equatable` (`AdditiveArithmetic`, `SIMD`, `NSObject`'s conformance), so it ends the walk
    /// as *may be Equatable*.
    static let knownNotEquatable: Set<String> = [
        "Sendable", "Codable", "Encodable", "Decodable", "Identifiable", "CodingKey",
        "CustomStringConvertible", "CustomDebugStringConvertible", "LosslessStringConvertible",
        "CustomReflectable", "TextOutputStreamable", "AnyObject", "Copyable", "Escapable", "BitwiseCopyable"
    ]

    /// Whether some declaration the scan saw makes `name` `Equatable`, or a chain of its
    /// conformances leaves what the scan can see.
    ///
    /// Walks every inheritance chain from the shape's own clause and from the conformance index
    /// under both spellings of its name, stepping through any name the index holds.
    private static func declaresEquatable(
        _ name: String,
        shape: TypeShape,
        scanned: Set<String>,
        inheritedTypesByName: [String: Set<String>]
    ) -> Bool {
        let bare = name.split(separator: ".").last.map(String.init) ?? name
        var pending = shape.inheritedTypes
            + Array(inheritedTypesByName[name] ?? []) + Array(inheritedTypesByName[bare] ?? [])
        var seen: Set<String> = [name, bare]
        while let next = pending.popLast() {
            let names = conformanceNames(next)
            if names.count > 1 {
                pending.append(contentsOf: names)
                continue
            }
            let current = names.first ?? next
            guard seen.insert(current).inserted else { continue }
            if UnequatableCarrierGate.equatableRefiners.contains(current) { return true }
            if knownNotEquatable.contains(current) { continue }
            if let inherited = inheritedTypesByName[current] {
                pending.append(contentsOf: inherited)
            } else if scanned.contains(current) == false {
                return true
            }
        }
        return false
    }

    /// The protocol or class names an inheritance entry spells: `Swift.Hashable` → `Hashable`,
    /// `@unchecked Sendable` → `Sendable`, `Codable & Hashable` → both.
    private static func conformanceNames(_ inherited: String) -> [String] {
        inherited.split(separator: "&").map { part in
            let words = part.split(whereSeparator: \.isWhitespace)
            let last = words.last.map(String.init) ?? String(part)
            return last.hasPrefix("Swift.") ? String(last.dropFirst("Swift.".count)) : last
        }
    }

    /// The type names in a spelling, dotted paths kept whole, in order of first appearance.
    private static func identifiers(in spelling: String) -> [String] {
        let identifier = /[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*/
        var seen: Set<String> = []
        return spelling.matches(of: identifier)
            .map { String($0.output) }
            .filter { seen.insert($0).inserted }
    }
}
