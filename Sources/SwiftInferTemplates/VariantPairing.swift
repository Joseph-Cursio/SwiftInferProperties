import SwiftInferCore

/// A reference implementation paired with a second implementation of the same
/// specification — the input to `DifferentialTemplate`.
public struct VariantPair: Sendable, Equatable {

    /// The unmarked half: the specification.
    public let reference: FunctionSummary
    /// The marked half: the optimisation, fast path, or precondition-eliding
    /// variant that must agree with it.
    public let variant: FunctionSummary
    /// How the two names related.
    public let naming: VariantMarkers.VariantPair
    /// When the variant's return type is not the reference's, the stored
    /// member of the variant's return that holds it —
    /// `IncrementalParseResult.tree` is a `SourceFileSyntax`, so the law
    /// compares `variant(...).tree` against `reference(...)`.
    public let projection: String?

    public init(
        reference: FunctionSummary,
        variant: FunctionSummary,
        naming: VariantMarkers.VariantPair,
        projection: String?
    ) {
        self.reference = reference
        self.variant = variant
        self.naming = naming
        self.projection = projection
    }
}

/// Finds reference/variant implementation pairs.
///
/// **Named first, shaped second — and that order is the whole safety story.**
/// A shape-first pass ("two functions with compatible signatures") is exactly
/// the flood the cross-type counter exists to stop: type symmetry alone
/// produced 1,380 candidate pairs on the reference corpora, of which
/// essentially all were noise. The variant marker is the evidence; the
/// signature check only confirms the pair could actually be compared.
public enum VariantPairing {

    /// Every `(reference, variant)` pair in `summaries` whose names are related
    /// by a `VariantMarkers` marker AND whose signatures admit the comparison.
    ///
    /// `typeDecls` supplies the stored-member lookup for the projection case.
    public static func candidates(
        in summaries: [FunctionSummary],
        typeDecls: [TypeDecl] = []
    ) -> [VariantPair] {
        var pairs: [VariantPair] = []
        for (index, lhs) in summaries.enumerated() {
            for rhs in summaries.dropFirst(index + 1) {
                guard let naming = VariantMarkers.relateEitherOrder(lhs.name, rhs.name) else {
                    continue
                }
                let reference = lhs.name == naming.reference ? lhs : rhs
                let variant = lhs.name == naming.reference ? rhs : lhs
                guard let projection = comparableProjection(
                    reference: reference, variant: variant, typeDecls: typeDecls
                ) else {
                    continue
                }
                guard sharesLeadingParameters(reference: reference, variant: variant) else {
                    continue
                }
                pairs.append(
                    VariantPair(
                        reference: reference,
                        variant: variant,
                        naming: naming,
                        projection: projection.isEmpty ? nil : projection
                    )
                )
            }
        }
        return pairs.sorted { lessThan($0, $1) }
    }

    /// How the two results are compared, or `nil` when they cannot be.
    ///
    /// Returns `""` when the return types are equal (compare directly), or the
    /// name of the stored member of the variant's return type that holds the
    /// reference's return type. The projection case is not a convenience: it
    /// is the motivating shape.
    /// `parseIncrementally` returns `IncrementalParseResult`, whose `tree` is
    /// the `SourceFileSyntax` that `parse` returns, and the law compares those.
    static func comparableProjection(
        reference: FunctionSummary,
        variant: FunctionSummary,
        typeDecls: [TypeDecl]
    ) -> String? {
        guard let referenceReturn = reference.returnTypeText,
              let variantReturn = variant.returnTypeText,
              referenceReturn != "Void", referenceReturn != "()",
              variantReturn != "Void", variantReturn != "()" else {
            return nil
        }
        if referenceReturn == variantReturn { return "" }
        guard let decl = typeDecls.first(where: { $0.name == variantReturn }) else {
            return nil
        }
        // Exactly one member of the right type, or the projection is ambiguous
        // and guessing which one the law means would be worse than silence.
        let matches = decl.storedMembers.filter { $0.typeName == referenceReturn }
        guard matches.count == 1, let member = matches.first else { return nil }
        return member.name
    }

    /// The variant must accept everything the reference does, in the same
    /// order, so the two can be called on the same input. Extra trailing
    /// parameters are the point — `parseTransition:` is what makes the fast
    /// path fast — but they must be *additional*, not different.
    static func sharesLeadingParameters(
        reference: FunctionSummary,
        variant: FunctionSummary
    ) -> Bool {
        guard variant.parameters.count >= reference.parameters.count else { return false }
        for (index, referenceParameter) in reference.parameters.enumerated()
        where variant.parameters[index].typeText != referenceParameter.typeText {
            return false
        }
        return true
    }

    /// Byte-stable ordering so output does not depend on scan order (PRD §16 #6).
    private static func lessThan(_ lhs: VariantPair, _ rhs: VariantPair) -> Bool {
        if lhs.reference.name != rhs.reference.name {
            return lhs.reference.name < rhs.reference.name
        }
        return lhs.variant.name < rhs.variant.name
    }
}
