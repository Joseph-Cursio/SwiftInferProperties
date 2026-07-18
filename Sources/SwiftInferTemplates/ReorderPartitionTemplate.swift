import SwiftInferCore

/// The **reorder-partition** law — the *other* sense of the word "partition".
///
/// The catalogue already has a `partition` template, but it means **tiling**: a
/// `(Int) -> Range<Int>` / `(C, Int) -> C` shape whose parts reassemble a whole
/// (paging, chunking). The standard library and swift-algorithms use "partition"
/// for something disjoint — an **in-place reorder by a predicate**:
///
///     mutating func partition(by belongsInSecondPartition: (Element) -> Bool) -> Index
///     mutating func stablePartition(subrange: Range<Index>, by: (Element) -> Bool) -> Index
///
/// It rearranges the elements so that everything failing the predicate comes
/// before the returned pivot and everything satisfying it comes at or after it,
/// and it returns that pivot. Same English word, a completely different law — and
/// one the tiling template could not state. This template owns it.
///
/// The law is *free from the role*, which is the whole point of the catalogue:
///  1. **Two-sided split** — `a[..<pivot]` all fail the predicate, `a[pivot...]`
///     all satisfy it (mind the convention: Swift's returns the first index of
///     the group that satisfies `belongsInSecondPartition`).
///  2. **Permutation** — the result is a rearrangement of the input: the multiset
///     of elements is unchanged, nothing added, lost, or duplicated.
///  3. **Stability** (only when the name says `stable`) — relative order within
///     each group is preserved.
///
/// Motivated by the swift-algorithms `stablePartition(subrange:by:)` count bug
/// (`0dba0e5`): it partitioned the whole collection's count instead of the
/// subrange's, violating (1) on the sub-slice — a partition-property bug the
/// tiling template was structurally blind to.
public enum ReorderPartitionTemplate {

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "reorder-partition",
            appliesTo: Self.isReorderPartition,
            // One signal at 70 — Likely. Name-gated ("partition") *and* a
            // distinctive shape (mutating + a `-> Bool` predicate + a pivot
            // return), so it is specific enough to clear the visible tier, but
            // not Strong: without the body the pivot convention and the
            // predicate's direction are unconfirmed, and stability is
            // name-dependent.
            signals: { summary in
                [
                    Signal(
                        kind: .reorderPartitionSignature,
                        weight: 70,
                        detail: "`\(summary.name)` reorders its elements in place around a "
                            + "predicate and returns the pivot — the two sides of the pivot must "
                            + "split cleanly by that predicate, and the result must stay a "
                            + "permutation of the input"
                    )
                ]
            },
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "reorder-partition|\(summary.containingTypeName ?? "")|"
                        + summary.name
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { $0.containingTypeName },
            caveats: { Self.makeCaveats(for: $0) },
            generators: { _ in [] }
        )
    }

    /// The predicate half of the shape: a closure parameter returning `Bool`.
    /// Robust to `(Element) -> Bool`, `(Self.Element) throws -> Bool`, and the
    /// `@escaping` spelling — all compact to a string ending in `->Bool`.
    static func isPredicateClosure(_ parameter: Parameter) -> Bool {
        let compact = parameter.typeText.replacingOccurrences(of: " ", with: "")
        return compact.contains("->") && compact.hasSuffix("->Bool")
    }

    /// A `mutating` method named like a partition, taking exactly one predicate
    /// closure (optionally alongside a subrange), and returning a pivot.
    ///
    /// Name-gated on `partition` deliberately: the mutating-plus-closure shape
    /// alone is far too common (every `mutating func forEach(_:)`-alike would
    /// match), so the name is what makes the claim "this is a partition" legible
    /// — the same discipline the involution and comparator templates use.
    static func isReorderPartition(_ summary: FunctionSummary) -> Bool {
        guard summary.isMutating,
              !summary.isAsync,
              summary.name.lowercased().contains("partition"),
              let returnType = summary.returnTypeText,
              returnType != "Bool",
              returnType != "Void",
              returnType != "()",
              summary.parameters.filter(Self.isPredicateClosure).count == 1,
              // predicate + at most one companion (a subrange / index bound).
              summary.parameters.count <= 2 else {
            return false
        }
        return true
    }

    /// `true` when the name promises a *stable* partition — only then may the
    /// reader assert within-group order preservation.
    static func isStable(_ summary: FunctionSummary) -> Bool {
        summary.name.lowercased().contains("stable")
    }

    /// `true` when a subrange / index-bound companion parameter is present.
    static func hasSubrange(_ summary: FunctionSummary) -> Bool {
        summary.parameters.contains { !Self.isPredicateClosure($0) }
    }

    static func makeCaveats(for summary: FunctionSummary) -> [String] {
        var caveats = [
            "PIN THE CONVENTION FIRST. Swift returns the index of the first element of the group "
                + "that SATISFIES the predicate (`belongsInSecondPartition`): everything BEFORE the "
                + "pivot must FAIL it, everything AT OR AFTER must SATISFY it. If your predicate "
                + "reads the other way, the whole law inverts — write the two-sided split against "
                + "the convention this function actually uses, not the one you assumed.",
            "IT IS A PERMUTATION — this is the load-bearing invariant. The multiset of elements is "
                + "unchanged; only their order moves. A partition that drops, adds, or duplicates an "
                + "element sails through a naive \"both sides look right\" check and fails this one. "
                + "Generate arrays WITH DUPLICATES and a small alphabet, then assert the sorted "
                + "result equals the sorted input."
        ]
        if Self.isStable(summary) {
            caveats.append(
                "STABILITY is promised by the name — assert it. Within each group the elements must "
                    + "keep their original relative order; that is exactly the property separating a "
                    + "stable partition from a plain one, and the only reason to pay for it. Tag each "
                    + "input with its original position and check the tags rise within each side."
            )
        } else {
            caveats.append(
                "This partition is NOT guaranteed STABLE. Do not assert that relative order within "
                    + "each group is preserved — you would be testing a property the function never "
                    + "promised, and watching it fail for a reason that is not a bug. Only the "
                    + "two-sided split and the permutation law are free here."
            )
        }
        if Self.hasSubrange(summary) {
            caveats.append(
                "THE SUBRANGE IS A FENCE. Only the elements inside the subrange may move, and the "
                    + "pivot must land inside it; every element outside must be exactly where it "
                    + "started. This is the precise failure mode of computing the split over the "
                    + "whole collection's count instead of the subrange's — partition a proper "
                    + "sub-slice and assert the untouched prefix and suffix are identical."
            )
        }
        return caveats
    }
}
