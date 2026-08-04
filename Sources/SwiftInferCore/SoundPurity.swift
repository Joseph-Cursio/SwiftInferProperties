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

    /// The full three-state verdict, kept sound the same way `inferredEffect`
    /// is: `ReducerPurityAnalyzer` refutes first, and only then does the
    /// syntactic inferrer get to distinguish partial from refuted.
    ///
    /// **Nothing consumes `.pureButPartial` yet, and that is deliberate.**
    /// Measured on this repo 2026-08-04: of 2,500 functions, 2,206 are `.pure`,
    /// **35 are `.pureButPartial`**, 259 refuted. The single consumer of the
    /// purity signal is the `/// @lint.effect pure` advisory, and a partial
    /// function cannot honestly take that annotation — SEI defines the tier as
    /// "no side effects, deterministic, **and total**", and the lattice has no
    /// tier for deterministic-but-partial. Advising those 35 anything today
    /// would mean inventing a claim or telling 35 functions something false.
    ///
    /// So this exists to stop the distinction being **discarded at the scan
    /// boundary**, which is where it was being lost: `isPure` collapses three
    /// states to two and the third is unrecoverable downstream. A consumer that
    /// can narrow a law's domain to the non-throwing inputs — which is exactly
    /// what `PurityVerdict`'s own doc says the method is for — now has
    /// something to read.
    ///
    /// The soundness argument is unchanged and worth restating, because
    /// admitting `throws` sounds like relaxing the gate this project warns
    /// about ("removing the `throws` gate once re-admitted `Process`/`Pipe`/
    /// `FileHandle`/SQLite at once"). It is not: `.pureButPartial` requires the
    /// body contain **no `try` at all**, so a throw propagated from a dependency
    /// still refutes. Only a function raising its own errors qualifies.
    public static func verdict(for function: FunctionDeclSyntax) -> PurityVerdict {
        guard ReducerPurityAnalyzer.analyze(function) == .pure else { return .refuted }
        return PurityInferrer().verdict(for: function)
    }
}
