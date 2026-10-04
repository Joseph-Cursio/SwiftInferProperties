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
/// The result is spelled the way a test file must write it — `Self` read as the declaring type,
/// nested names qualified — and only the types its `==` actually compares are judged
/// (`operandTypeNames(in:)`): the result itself, and the arguments of the standard wrappers whose
/// `==` needs theirs (`T?`, `[T]`, `[K: V]`, `Set`, `Result`, a tuple's members). Any other generic
/// is judged by its own name: `KeyPath<Row, String>` is `Hashable` whatever `Row` is, and so is a
/// phantom-tagged `Tagged<User, Int>`. A judged type is let through when it was never scanned, or:
///
/// - it is an enum the scan shows no payload for (`isImplicitlyEquatable`); or
/// - a chain of its conformances reaches `Equatable` or a protocol refining it — its own clause,
///   and the conformance index under its qualified AND its bare name, at every link. Both are
///   needed because `inheritedTypesByName` is keyed by `TypeDecl.name`, bare for a nested
///   declaration, while `typeShapesByName` and a clause naming `Ledger.Entry` use the qualified
///   one; or
/// - a chain leaves what the scan can see — a superclass or protocol from another module that is
///   not known to stop short of `Equatable`. `NSObject` is `Equatable`, and so is anything
///   conforming to `AdditiveArithmetic`, and neither is on `UnequatableCarrierGate`'s refiner
///   list (both checked with `swiftc`, Swift 6.4); or
/// - the scan saw `==` arrive without a clause (`equalityOutsideInheritance(typeDecls:summaries:)`):
///   a hand-written `static func ==`, which operator lookup finds with no conformance at all, or
///   an attribute that may be a macro — SwiftData's `@Model` conforms a class to `PersistentModel`,
///   which refines `Hashable`.
///
/// ⚠ **What it cannot see.** Only the scanned target is indexed, so an
/// `extension FixResult: Equatable {}` written in the TEST target the stub lands in is invisible,
/// and the stub is withdrawn although it would compile there. `UnequatableCarrierGate` and
/// `UnorderedCarrierGate` share that blind spot; reading the destination target is one change for
/// all three. A conditional conformance (`extension Box: Equatable where T: Equatable`) is read as
/// unconditional, which errs toward writing the stub.
enum UnequatableResultGate {

    /// Why the determinism stub for this suggestion cannot compare its results, or `nil`.
    ///
    /// Only `determinism`; and only when `SubjectCallPlan` would write a call, since a declined
    /// plan has its own, earlier reason.
    static func declineReason(
        for suggestion: Suggestion,
        typeShapesByName: [String: TypeShape],
        inheritedTypesByName: [String: Set<String>],
        equalityOutsideInheritance: Set<String> = []
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
            inheritedTypesByName: inheritedTypesByName,
            equalityOutsideInheritance: equalityOutsideInheritance
        )
    }

    /// Why `display`'s result, spelled `returnTypeText` inside `owner`, has no `==`, or `nil`.
    ///
    /// - Parameters:
    ///   - typeUniverse: the qualified names nested spellings are resolved against; `nil` means
    ///     the scanned types' own keys.
    ///   - equalityOutsideInheritance: the names the scan saw get `==` without an inheritance
    ///     clause saying so; empty for a caller that has no scan to read it from.
    static func declineReason(
        display: String,
        returnTypeText: String,
        owner: String?,
        typeShapesByName: [String: TypeShape],
        inheritedTypesByName: [String: Set<String>],
        typeUniverse: Set<String>? = nil,
        equalityOutsideInheritance: Set<String> = []
    ) -> String? {
        let scan = EqualityScan(
            shapes: typeShapesByName, inherited: inheritedTypesByName, outside: equalityOutsideInheritance
        )
        let selfless = owner.map { SubjectCallPlan.replacingSelf(in: returnTypeText, with: $0) } ?? returnTypeText
        let spelled = TypeShapeBuilder.resolvedSpelling(
            selfless, enclosing: owner ?? "", universe: typeUniverse ?? Set(typeShapesByName.keys)
        )
        guard let unequatable = operandTypeNames(in: spelled).first(where: scan.lacksEquality) else { return nil }
        return "\(display) returns \(returnTypeText), and no scanned declaration makes \(unequatable) "
            + "Equatable, so `==` cannot compare two results"
    }

    /// An enum the scan shows no payload for: Swift synthesises `Equatable` (and `Hashable`) for an
    /// enum whose cases are all payload-free, without a declaration.
    ///
    /// ⚠ **A caseless enum counts too, though Swift gives it no `==`.** The scan reads an enum's
    /// direct members only (`MemberBlockInspector.enumCases`), so an enum whose cases all sit inside
    /// `#if` shows none — and that one IS `Equatable`. The two cannot be told apart here, and
    /// declining both would withdraw a stub that compiles; letting both through costs nothing real,
    /// because a function returning an uninhabited type never returns. A payload case inside `#if`
    /// is missed the same way, and errs the same way.
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

    /// What the scan knows about where a type's `==` comes from.
    struct EqualityScan {
        let shapes: [String: TypeShape]
        let inherited: [String: Set<String>]
        let outside: Set<String>

        /// Whether `name` is a scanned declaration with no `==` the scan can see.
        func lacksEquality(_ name: String) -> Bool {
            guard let shape = shapes[name], shape.hasPrimaryDeclaration else { return false }
            return UnequatableResultGate.isImplicitlyEquatable(shape) == false && mayBeEquatable(name) == false
        }

        /// Whether some chain of conformances from `name` reaches `Equatable`, or reaches a link
        /// the scan cannot rule `==` out for. Every link is read the same way, the first included.
        func mayBeEquatable(_ name: String) -> Bool {
            var pending = [name]
            var seen: Set<String> = []
            while let entry = pending.popLast() {
                let names = UnequatableResultGate.conformanceNames(entry)
                guard names.count == 1, let current = names.first else {
                    pending.append(contentsOf: names)
                    continue
                }
                guard seen.insert(current).inserted,
                      UnequatableResultGate.knownNotEquatable.contains(current) == false
                else { continue }
                if UnequatableCarrierGate.equatableRefiners.contains(current) { return true }
                guard let onward = conformances(of: current) else { return true }
                pending.append(contentsOf: onward)
            }
            return false
        }

        /// The conformances to walk on from `name`, or `nil` when the scan cannot rule `==` out:
        /// the scan saw `==` arrive without a clause, or `name` left the scan (neither scanned nor
        /// indexed under its own spelling).
        ///
        /// A scanned name is read under its qualified AND its bare spelling, plus its shape's own
        /// clause. An unscanned one is read under its own spelling only: its last component may be
        /// an unrelated scanned type (`SomeKit.Item` beside a project `Item`), and reading through
        /// that would turn *left the scan* into evidence of no `==`.
        func conformances(of name: String) -> [String]? {
            guard let shape = shapes[name] else {
                return outside.contains(name) ? nil : inherited[name].map(Array.init)
            }
            let bare = name.split(separator: ".").last.map(String.init) ?? name
            guard outside.isDisjoint(with: [name, bare]) else { return nil }
            return shape.inheritedTypes + Array(inherited[name] ?? []) + Array(inherited[bare] ?? [])
        }
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
}
