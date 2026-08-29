import Foundation
import SwiftInferCore

public extension TemplateRegistry {

    /// Drop `monotonicity` where the subject's name says the property cannot hold — a hash,
    /// or a non-order-preserving mathematical function. See `NonMonotonicSubjects` for the
    /// set and for why it is narrower than `MathForwardFunctions.curated`.
    ///
    /// **Measured: 26 rows of 339 across the 20 manifest corpora** — trigonometric 4
    /// (`_cos(_:)`, `_sin(_:)`, twice each), hash 22 (`_rawHashValue(seed:)` 9,
    /// `_rawHashValue(_seed:)` 5, `_hashValue(for:)` 2, `hashValue(at:)` 2,
    /// `hashValue(for:)` 2, `_hashValue(at:)` 1, `Hashable_hashValue_indirect(_:)` 1) —
    /// `docs/measurements/monotonicity-subject-census.md`. **Costs no laws**: the same
    /// stdlib shims contribute `_exp`, `_exp2`, `_log`, `_log2`, `_log10` and `_nearbyint`,
    /// all genuinely monotonic and all untouched.
    ///
    /// ⚠ **THIS RESTS ON A NAME, WHICH IS THE WEAKER BASIS, AND THAT IS THE HONEST
    /// DIFFERENCE FROM ITS NEIGHBOURS.** `applyInvolutionIdempotenceExclusion` needs no new
    /// analysis at all — the contradiction is already in the tool's own output, two
    /// templates proposed for one `(file, line)`. The availability gate reads an attribute
    /// out of the syntax tree. This one reads a name and reasons about what the function
    /// must be, so it can be wrong in a way neither of those can.
    ///
    /// **Keyed on the name and NOT on `(file, line)`**, which inverts the involution gate's
    /// rule for a stated reason: there the join was between two suggestions and a name key
    /// would have collided same-named declarations on different types. Here there is no
    /// join — the name IS the evidence — so a location key would buy nothing and cost the
    /// generality that makes the rule worth having.
    ///
    /// ⚠ **REMOVED, not demoted, and the value is author-facing output rather than verdict
    /// prevention.** Measured (`monotonicity-verify-reach.md`): **zero of these rows can
    /// reach a verdict.** ~22 are in `swiftlang-swift`, which the verifier cannot
    /// path-depend on; 2 are behind `#if UnstableHashedContainers`, an off-by-default trait
    /// (row 74); 1 dies at `unsupported-carrier`. So the `involution` gate's argument — *a
    /// passing false law is believed* — **cannot apply here**, and nobody should cite this
    /// gate as having prevented a false `bothPass`. What it prevents is 26 false suggestions
    /// in `discover` output and the index, which `insights` and authors read. The
    /// availability gate is the precedent for that being worth doing: 24 rows of 4,161,
    /// withdrawn because they cost no laws.
    static func applyNonMonotonicSubjectExclusion(to suggestions: [Suggestion]) -> [Suggestion] {
        suggestions.filter { suggestion in
            guard suggestion.templateName == TemplateName.monotonicity.rawValue,
                  let subject = suggestion.evidence.first?.displayName
            else { return true }
            return !NonMonotonicSubjects.isDefinitionallyNonMonotonic(subject)
        }
    }
}
