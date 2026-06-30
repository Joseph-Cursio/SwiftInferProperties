import SwiftEffectInference
import SwiftSyntax

/// Soundly maps a function's purity onto SwiftEffectInference's `Effect`
/// lattice by taking the **meet of two independent refutations**:
///
/// - `ReducerPurityAnalyzer` refutes purity on TCA / concurrency effects
///   (`Effect` / `Task` / `await` / `.run` / `.send` / …) and hidden mutation
///   (static / `Self` writes).
/// - `SwiftEffectInference.PurityInferrer` refutes purity on I/O, logging,
///   nondeterminism, and partiality (totality — traps / force-unwraps).
///
/// `.pure` is claimed **only when neither refutes**. This is the crux of the
/// soundness argument (Idea #4, step 2): purity is *conjunctive* — a function
/// is `Effect.pure` only when none of the refuters fire — and each analyzer is
/// blind to the other's refuters. Mapping `ReducerPurity.pure` to `Effect.pure`
/// *alone* would be **unsound**, because `ReducerPurityAnalyzer` never inspects
/// I/O or totality: a reducer can be `ReducerPurity.pure` while still calling
/// `print()` or `Date()` or force-unwrapping. `Effect.pure` is the lattice
/// bottom and is *trusted* by every downstream consumer (a generated property
/// test runs a `.pure` function in-process and asserts a law over random
/// inputs), so a false `.pure` is the most dangerous claim the tool can make.
///
/// On the effect lattice a sound inference only ever over-approximates (never
/// claims an effect below the true one); when in doubt this returns `nil`
/// (refuted) rather than risk an unsound `.pure`.
public enum SoundPurity {

    /// Returns `.pure` iff **both** analyzers agree the function is pure;
    /// otherwise `nil` (purity refuted — the caller must not emit a `pure`
    /// claim, e.g. a `/// @lint.effect pure` suggestion).
    public static func inferredEffect(for function: FunctionDeclSyntax) -> Effect? {
        // First refuter: TCA effects / hidden mutation. Cheap, and the common
        // reason a reducer is not pure.
        guard ReducerPurityAnalyzer.analyze(function) == .pure else { return nil }
        // Second refuter: I/O / nondeterminism / partiality. Catches exactly
        // what ReducerPurity is blind to — this is what makes the mapping sound.
        return PurityInferrer().inferredEffect(for: function)
    }

    /// Convenience boolean form of `inferredEffect(for:)`.
    public static func isPure(_ function: FunctionDeclSyntax) -> Bool {
        inferredEffect(for: function) == .pure
    }
}
