import PropertyLawCore
import SwiftInferCore

/// The **diff** role — a function named like a difference (`generateDiff`,
/// `diffBetween`, `compare…`) whose return type carries a *complementary* pair of
/// `[T]` members (`addedRules` / `removedRules`, `inserted` / `deleted`,
/// `onlyInFirst` / `onlyInSecond`). Those two lists are **disjoint** in any
/// correctly computed diff — an element is added or removed, never both.
///
/// This is the structural, refutable law `generateDiff` owes. It is NOT a
/// round-trip (there is no `apply(diff)` and `ConfigDiff` is lossy — the road-test
/// says so); disjointness is what a diff owes *by virtue of being a diff*, and a
/// diff whose `added` and `removed` overlap has double-counted a key. Shapes-aware
/// (it reads the return type's members), so it gets its own collection pass.
public enum DiffDisjointnessTemplate {

    /// Diff verbs matched as a lower-cased *substring* of the name (so
    /// `generateDiff` matches `diff`, not just a prefix).
    public static let diffVerbs: [String] = ["diff", "delta", "compare", "changes"]

    /// Complementary member-name marker pairs. Two `[T]` members whose names
    /// contain opposite markers are the disjoint pair.
    public static let complementaryMarkers: [(String, String)] = [
        ("added", "removed"), ("insert", "delete"), ("insert", "remove"),
        ("addition", "removal"), ("onlyinfirst", "onlyinsecond"),
        ("gained", "lost"), ("new", "old")
    ]

    struct Match: Sendable, Equatable {
        let diffType: String
        let memberA: String
        let memberB: String
        let elementType: String
    }

    public static func suggest(
        for summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> Suggestion? {
        guard let match = disjointMatch(for: summary, shapesByName: shapesByName) else { return nil }
        return ConstraintRunner.suggest(constraint: makeConstraint(match: match), subject: summary)
    }

    static func disjointMatch(
        for summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> Match? {
        guard hasDiffName(summary.name),
              !summary.isMutating,
              !summary.isAsync,
              !summary.isThrows,
              let returnType = summary.returnTypeText,
              let shape = shapesByName[lastComponent(returnType)],
              let pair = disjointPair(in: shape) else {
            return nil
        }
        return Match(diffType: shape.name, memberA: pair.0, memberB: pair.1, elementType: pair.2)
    }

    /// The complementary `[T]` member pair `(memberA, memberB, element)` in
    /// `shape`, or nil.
    static func disjointPair(in shape: TypeShape) -> (String, String, String)? {
        let arrayMembers: [(name: String, element: String)] = shape.storedMembers.compactMap { member in
            FilterSubsetTemplate.arrayElement(of: member.typeName).map { (member.name, $0) }
        }
        for (leftMarker, rightMarker) in complementaryMarkers {
            guard let left = arrayMembers.first(where: { $0.name.lowercased().contains(leftMarker) }),
                  let right = arrayMembers.first(where: { $0.name.lowercased().contains(rightMarker) }),
                  left.element == right.element,
                  left.name != right.name else {
                continue
            }
            return (left.name, right.name, left.element)
        }
        return nil
    }

    static func makeConstraint(match: Match) -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "diff-disjointness",
            appliesTo: { _ in true },
            signals: { _ in Self.signals(match: match) },
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "diff-disjointness|" + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { $0.parameters.first?.typeText ?? $0.containingTypeName },
            caveats: { _ in Self.makeCaveats(match: match) }
        )
    }

    static func signals(match: Match) -> [Signal] {
        [
            Signal(
                kind: .orderedCodomainSignature,
                weight: 20,
                detail: "Diff shape: returns \(match.diffType) with complementary lists "
                    + "`\(match.memberA)` / `\(match.memberB)`"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 15,
                detail: "Curated diff verb match — the added and removed lists of a diff are disjoint"
            )
        ]
    }

    private static func hasDiffName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return diffVerbs.contains { lowered.contains($0) }
    }

    /// The last dotted component of a type spelling: `YAMLConfigurationEngine.ConfigDiff`
    /// → `ConfigDiff`, `ConfigDiff` → `ConfigDiff`.
    static func lastComponent(_ type: String) -> String {
        String(type.split(separator: ".").last ?? Substring(type))
    }

    static func makeCaveats(match: Match) -> [String] {
        [
            "THE LAW IS `Set(result.\(match.memberA)).isDisjoint(with: Set(result.\(match.memberB)))` — "
                + "in a correct diff an element is added OR removed, never both. Overlap means a key was "
                + "double-counted (a `\\` that should be `subtracting` computed the wrong way, say).",
            "IT IS A CHARACTERISATION, not a round-trip: `\(match.diffType)` records membership changes, "
                + "not the values needed to reconstruct one side from the other. Disjointness is what it "
                + "owes by virtue of being a diff; the round-trip `apply(diff(a,b), a) == b` would need an "
                + "`apply` that does not exist (and richer diff values).",
            "The element type must be Hashable for `Set` / `isDisjoint`; SwiftInfer M1 does not verify "
                + "conformance — confirm before applying."
        ]
    }
}
