import SwiftInferCore

/// V1.18.C — pair finder for the dual-style consistency template.
/// Detects canonical Swift pairs of `mutating func op(...)` and
/// non-mutating `func op'(...) -> Self` on the same containing type.
///
/// The shape is the "sweet spot" pattern from the
/// `_2_Designing APIs Around Transformations.md` value-semantics
/// conversation referenced in `docs/v1.18 Calibration Plan.md`. Stdlib
/// follows it across `SetAlgebra` (`formUnion` / `union`), `Sequence`
/// (`sort` / `sorted`), `Collection` (`reverse` / `reversed`), and
/// `RangeReplaceableCollection` (`append` / `appending`).
///
/// Pairs surface only when both halves are members of the same containing
/// type — a top-level `mutating func` is impossible in Swift, and the
/// non-mutating partner conventionally lives next to its mutating sibling.
public struct DualStylePair: Sendable, Equatable {

    /// `mutating func op(...)`. Returns `Void` (or `@discardableResult`
    /// non-Void) by convention; the template renders the property body
    /// against this method's signature.
    public let mutatingMember: FunctionSummary

    /// `func op'(...) -> Self` (or the containing type spelled by name).
    /// Same parameter list as `mutatingMember`; same containing type.
    public let nonMutatingMember: FunctionSummary

    /// The canonical name pairing rule that matched. Rendered in the
    /// `whySuggested` block so the user can audit which convention this
    /// pair satisfied.
    public let rule: PairingRule

    public init(
        mutatingMember: FunctionSummary,
        nonMutatingMember: FunctionSummary,
        rule: PairingRule
    ) {
        self.mutatingMember = mutatingMember
        self.nonMutatingMember = nonMutatingMember
        self.rule = rule
    }

    /// Canonical naming-pair conventions per Swift API Design Guidelines
    /// "Strive for fluent usage" + "Use imperative for mutating, past-
    /// participle/-ing for non-mutating."
    public enum PairingRule: String, Sendable, Equatable {
        /// `add` ↔ `adding`, `append` ↔ `appending`, `insert` ↔ `inserting`.
        case activeToPresentParticiple
        /// `sort` ↔ `sorted`, `reverse` ↔ `reversed`, `normalize` ↔ `normalized`.
        case activeToPastParticiple
        /// `formUnion` ↔ `union`, `formIntersection` ↔ `intersection`,
        /// `formSymmetricDifference` ↔ `symmetricDifference`.
        case formPrefixToBare
        /// Project-vocabulary literal pair (per the `dualStylePairs` schema
        /// extension, v1.18 plan open decision #6 lean: literal pairs only).
        case projectVocabulary
    }
}

/// Type- and naming-driven pair finder. Mirrors `FunctionPairing` /
/// `IdentityElementPairing` shape: a single static `candidates(in:)`
/// entry-point that returns a sorted `[DualStylePair]` for deterministic
/// output (PRD §16 #6 byte-stability).
///
/// **Curated rules (v1.18):**
/// - `X` ↔ `Xing` — `add`/`adding`, `append`/`appending`, `insert`/`inserting`
/// - `X` ↔ `Xed` — `sort`/`sorted`, `reverse`/`reversed`, `normalize`/`normalized`
/// - `formX` ↔ `X` — `formUnion`/`union`, `formIntersection`/`intersection`,
///   `formSymmetricDifference`/`symmetricDifference`
///
/// **Project extension** lands via `Vocabulary.dualStyleNamePairs` —
/// literal `(mutating, nonMutating)` pairs only per the v1.18 plan open
/// decision #6 lean. Regex-pattern extension is a v1.21+ candidate.
public enum DualStylePairing {

    /// Every `(mutatingMember, nonMutatingMember)` pair in `summaries`
    /// such that:
    ///   - `mutatingMember.isMutating == true`,
    ///   - `nonMutatingMember.isMutating == false`,
    ///   - both have a non-nil `containingTypeName` and they match,
    ///   - the (mutating, non-mutating) name pair satisfies one of the
    ///     curated rules or `vocabulary.dualStyleNamePairs`,
    ///   - both have the same parameter list (label + type),
    ///   - `nonMutatingMember.returnTypeText` is `Self` or the containing
    ///     type name (the non-mutating partner returns the new value).
    /// Pairs are returned sorted by `(mutating.file, mutating.line,
    /// nonMutating.file, nonMutating.line)` so the list is deterministic.
    public static func candidates(
        in summaries: [FunctionSummary],
        vocabulary: Vocabulary = .empty
    ) -> [DualStylePair] {
        let mutatingMembers = summaries.filter { $0.isMutating && $0.containingTypeName != nil }
        guard !mutatingMembers.isEmpty else { return [] }
        // Group non-mutating members by containing type for O(N+M) pairing.
        var nonMutatingByContainer: [String: [FunctionSummary]] = [:]
        for summary in summaries
        where !summary.isMutating && summary.containingTypeName != nil {
            nonMutatingByContainer[summary.containingTypeName!, default: []].append(summary)
        }
        var pairs: [DualStylePair] = []
        for mutatingMember in mutatingMembers {
            guard let container = mutatingMember.containingTypeName,
                  let candidates = nonMutatingByContainer[container] else { continue }
            for nonMutating in candidates {
                guard let rule = matchRule(
                    mutating: mutatingMember.name,
                    nonMutating: nonMutating.name,
                    vocabulary: vocabulary
                ) else { continue }
                guard hasMatchingShape(
                    mutating: mutatingMember,
                    nonMutating: nonMutating,
                    container: container
                ) else { continue }
                pairs.append(DualStylePair(
                    mutatingMember: mutatingMember,
                    nonMutatingMember: nonMutating,
                    rule: rule
                ))
            }
        }
        return pairs.sorted(by: lessThan)
    }

    // MARK: - Naming rules

    /// Resolve `(mutatingName, nonMutatingName)` against the curated rule
    /// set + project vocabulary. Returns `nil` when no rule matches —
    /// pair-formation is name-gated; the type-shape check downstream
    /// applies only after this filter.
    static func matchRule(
        mutating mutatingName: String,
        nonMutating nonMutatingName: String,
        vocabulary: Vocabulary
    ) -> DualStylePair.PairingRule? {
        if curatedActiveToPresentParticiple(mutatingName, nonMutatingName) {
            return .activeToPresentParticiple
        }
        if curatedActiveToPastParticiple(mutatingName, nonMutatingName) {
            return .activeToPastParticiple
        }
        if curatedFormPrefixToBare(mutatingName, nonMutatingName) {
            return .formPrefixToBare
        }
        for pair in vocabulary.dualStyleNamePairs
        where pair.mutating == mutatingName && pair.nonMutating == nonMutatingName {
            return .projectVocabulary
        }
        return nil
    }

    /// `add` ↔ `adding` — append "ing" to the mutating verb.
    private static func curatedActiveToPresentParticiple(_ active: String, _ ing: String) -> Bool {
        guard ing.count > active.count else { return false }
        // "add" + "ing" = "adding" is the simple suffix case. Drops a
        // trailing "e" before "ing" (e.g. "complete" + "ing" = "completing").
        if ing == active + "ing" { return true }
        if active.hasSuffix("e"), ing == String(active.dropLast()) + "ing" { return true }
        return false
    }

    /// `sort` ↔ `sorted` — append "ed" or "d" (when active ends in "e").
    private static func curatedActiveToPastParticiple(_ active: String, _ past: String) -> Bool {
        guard past.count > active.count else { return false }
        if past == active + "ed" { return true }
        if active.hasSuffix("e"), past == active + "d" { return true }
        // Past-participle of irregular verbs is not modelled; stdlib
        // doesn't use any irregulars in its dual-style pairs. Project
        // vocabulary covers exotic cases.
        return false
    }

    /// `formUnion` ↔ `union` — strip the `form` prefix and lowercase the
    /// next letter. Convention: the form-prefixed name is the mutating
    /// half; the bare name is the non-mutating partner.
    private static func curatedFormPrefixToBare(_ formed: String, _ bare: String) -> Bool {
        guard formed.hasPrefix("form"), formed.count > 4 else { return false }
        let stripped = String(formed.dropFirst(4))
        guard let firstChar = stripped.first else { return false }
        let lowercased = firstChar.lowercased() + stripped.dropFirst()
        return bare == lowercased
    }

    // MARK: - Shape match

    /// Both members have the same parameter list (label + type) and the
    /// non-mutating member returns the containing type. Mutating member's
    /// return type is unconstrained — `Void` is the convention but stdlib
    /// has `@discardableResult` mutators (e.g. `Array.popLast()` returns
    /// the popped element). For v1.18 we accept both — the consistency
    /// property doesn't depend on the mutating member's return value.
    private static func hasMatchingShape(
        mutating mutatingMember: FunctionSummary,
        nonMutating: FunctionSummary,
        container: String
    ) -> Bool {
        guard mutatingMember.parameters.count == nonMutating.parameters.count else { return false }
        for (lhs, rhs) in zip(mutatingMember.parameters, nonMutating.parameters) {
            if lhs.label != rhs.label { return false }
            if lhs.typeText != rhs.typeText { return false }
            if lhs.isInout != rhs.isInout { return false }
        }
        guard let returnType = nonMutating.returnTypeText,
              returnType != "Void", returnType != "()" else { return false }
        // Either spelled `Self` or matches the container name (post-strip
        // of any generic-parameter list).
        if returnType == "Self" { return true }
        let strippedReturn = CarrierKindResolver.strippingGenericParameters(returnType)
        return strippedReturn == container
    }

    // MARK: - Sorting

    private static func lessThan(_ lhs: DualStylePair, _ rhs: DualStylePair) -> Bool {
        if lhs.mutatingMember.location.file != rhs.mutatingMember.location.file {
            return lhs.mutatingMember.location.file < rhs.mutatingMember.location.file
        }
        if lhs.mutatingMember.location.line != rhs.mutatingMember.location.line {
            return lhs.mutatingMember.location.line < rhs.mutatingMember.location.line
        }
        if lhs.nonMutatingMember.location.file != rhs.nonMutatingMember.location.file {
            return lhs.nonMutatingMember.location.file < rhs.nonMutatingMember.location.file
        }
        return lhs.nonMutatingMember.location.line < rhs.nonMutatingMember.location.line
    }
}
