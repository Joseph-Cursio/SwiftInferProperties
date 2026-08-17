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
    /// **What is in the `.refuted` third is now measured, and it is mostly not
    /// evidence.** Re-taken 2026-08-17 over `Sources/`: 284 refutations, of which
    /// **132 carry a witness and 152 name nothing in the source at all** — a
    /// `throws` whose `try` reaches a callee this leaf cannot resolve.
    /// `docs/measurements/purity-refuted-bucket-census.md` has the split, and
    /// one thing a caller reading this should know before counting it: the
    /// *"could not be inspected at all"* half of `PurityVerdict.refuted`'s own
    /// doc is **unreachable** through `FunctionScanner`, which skips protocol
    /// bodies — so every refutation here has a callee to name. (The census also
    /// found 180 computed-property summaries reaching `.refuted` by an
    /// initialiser default; that is fixed below, in `verdict(forGetter:)`.)
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

    /// The same verdict for a **read-only computed property's getter**, which
    /// the templates model as a nullary `self -> T` map.
    ///
    /// This exists because the scan had no oracle for that shape and answered
    /// with a constant. `makeSummary(fromComputedProperty:)` passed
    /// `isInferredPure: true` unconditionally and no `purityVerdict` at all, so
    /// every computed property simultaneously claimed purity and took
    /// `FunctionSummary.init`'s `.refuted` default — the one combination that
    /// field's own doc says cannot occur. Measured 2026-08-17: 180 of them under
    /// `Sources/`, which is **39% of the `.refuted` bucket a consumer reads**,
    /// none of it a verdict. See `docs/measurements/purity-refuted-bucket-census.md`.
    ///
    /// **The meet is taken here for the same reason it is taken above**, not as
    /// belt-and-braces: `PurityInferrer.isPure(_ accessor:)` answers the effect
    /// question — markers and totality — and says so in its own doc, while
    /// `ReducerPurityAnalyzer` owns the TCA/concurrency surface and static
    /// writes. A getter can return a `Task` or write to `Self.cache` as readily
    /// as a function can. Claiming `.pure` on one refuter is the lattice-bottom
    /// mistake, whichever shape it is claimed about.
    ///
    /// **Never `.pureButPartial`, and the reason is a filter rather than a
    /// property.** `isReadOnlyGetter` rejects `async` and `throws` accessors
    /// before this is reached, so no partial getter arrives; SEI's accessor
    /// oracle is a `Bool` and offers no third state anyway. If that filter is
    /// ever widened to admit a throwing getter, this method — not the filter —
    /// is what has to learn the distinction, or the partial case will silently
    /// read as fully pure.
    ///
    /// **A/B when this replaced the constant: 0 advisory rows moved.** Neither
    /// refuter fires on any of the 180 (measured separately, both at zero), so
    /// the unchecked `true` had been accidentally correct on this corpus the
    /// whole time. That is the measurement that keeps this a repair of an
    /// unasked question rather than a bug fix with a victim — and it is exactly
    /// why the shape it admits (`var now: Date { Date() }`, advised `pure`) is
    /// pinned by a test rather than left to the next corpus to discover.
    public static func verdict(forGetter accessor: AccessorBlockSyntax) -> PurityVerdict {
        guard ReducerPurityAnalyzer.analyze(Syntax(accessor)) == .pure else { return .refuted }
        return PurityInferrer().isPure(accessor) ? .pure : .refuted
    }
}
