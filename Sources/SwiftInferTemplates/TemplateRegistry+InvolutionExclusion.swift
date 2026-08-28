import Foundation
import SwiftInferCore

public extension TemplateRegistry {

    /// Drop `idempotence` where `involution` was proposed for the **same declaration**.
    ///
    /// The two laws are mutually exclusive except for the identity function:
    ///
    /// - `involution`  — `f(f(x)) == x`
    /// - `idempotence` — `f(f(x)) == f(x)`
    ///
    /// Both hold only where `f(x) == x`, and a function that is the identity is not worth a law
    /// under either template. So when both fire on one declaration, **at most one can be true and
    /// `involution` is the one that named the shape**.
    ///
    /// **This needs no new analysis.** The contradiction is already present in the tool's own
    /// output: two templates proposed for one `(file, line)`. Nothing is inferred here that was
    /// not already computed.
    ///
    /// **Measured on `nicklockwood/Euclid` @ `0b00927`** (`docs/measurements/subject-euclid.md`),
    /// where both templates fired on `inverted()` for five carriers. The outcomes are the argument
    /// for removing rather than demoting:
    ///
    /// | carrier | `involution` | `idempotence` |
    /// |---|---|---|
    /// | `LineSegment` | `bothPass` | `defaultFails` |
    /// | `Vertex` | `bothPass` | `defaultFails` |
    /// | **`Mesh`** | `bothPass` | **`bothPass`** |
    ///
    /// **`Mesh.inverted()` reported BOTH as verified.** That is only possible where the generated
    /// meshes are fixed points of `inverted()`, so a mathematically false law came back green —
    /// which is worse than the two that refuted, because `measured-bothPass` is believed. It is
    /// the standing caution in CLAUDE.md arriving with a witness: *"no counterexample in the
    /// generated domain" is not "the property holds."*
    ///
    /// **Removed, not demoted.** The purity veto beside this one *marks* its subjects, because
    /// impurity is a claim about whether a law may safely be executed and the law itself might
    /// still be true. Here the law is **false whenever the sibling proposal is true**, and a
    /// scored-but-present false law still reaches the index, still gets verified, and — as `Mesh`
    /// shows — can still come back green. The availability gate is the precedent: a law that
    /// cannot be true is withdrawn rather than annotated.
    ///
    /// **Keyed on `(file, line)`, not on the function's name.** A name key would join two
    /// same-named declarations on different types, which is the `SymbolJoinKey` collision this
    /// project has already paid for once — and the location is exact and already in hand.
    ///
    /// ⚠ **Directional by construction.** Only `idempotence` is dropped; `involution` is never
    /// touched. If a future template pair needs symmetric resolution it needs its own rule and its
    /// own evidence, because *which one survives* is the whole content of this decision.
    static func applyInvolutionIdempotenceExclusion(to suggestions: [Suggestion]) -> [Suggestion] {
        let involutionSubjects = Set(
            suggestions
                .filter { $0.templateName == TemplateName.involution.rawValue }
                .compactMap { $0.evidence.first?.location }
        )
        guard !involutionSubjects.isEmpty else { return suggestions }

        return suggestions.filter { suggestion in
            guard suggestion.templateName == TemplateName.idempotence.rawValue,
                  let subject = suggestion.evidence.first?.location,
                  involutionSubjects.contains(subject)
            else { return true }
            return false
        }
    }
}
