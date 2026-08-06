import SwiftEffectInference
import SwiftInferCore

/// Reads the author's own idempotency claim, in SwiftIdempotency's vocabulary,
/// and lets it corroborate or veto the shape-matched candidate.
///
/// **Why this did not exist until 2026-08-04.** `EffectAnnotationParser` has been
/// a dependency of this package for some time and was called for exactly one
/// thing — `isClockDeterministic`. `@Idempotent`, `@NonIdempotent` and
/// `@ExternallyIdempotent(by:)` were parsed by linked code and read by nothing,
/// while the tool simultaneously *emitted advice* in the same vocabulary
/// (`discover --effect-annotations` recommends `/// @lint.effect pure` lines).
/// One tool talking to itself in English.
///
/// **What this can and cannot see.** Only what is written on the declaration.
/// SwiftProjectLint computes strictly more from the same vocabulary — an
/// `EffectSymbolTable` resolving cross-file, multi-hop upward inference through
/// the call graph, and a heuristic inferrer for unannotated callees — and none
/// of that crosses into `.pbt/seeds.json`, which carries the idempotency
/// *violation* but not the *tier*. So this is the weaker half of an available
/// signal, taken because it is the half that needs no lint run: `discover
/// --target X` sees the annotation with no seed manifest in existence.
extension IdempotenceTemplate {

    /// The declared-effect signal for `summary`, or `nil` when the author made no
    /// claim — overwhelmingly the common case, and the reason this is cheap.
    ///
    /// Both directions live in one function because they read one field and the
    /// exhaustive `switch` is the point: adding a tier to `Effect` upstream should
    /// be a compile error here, not a silently-unhandled case.
    /// The body-resolved counterpart, from `EffectResolver` (opt-in). Separate
    /// from the declared signal because the treatments differ: a declaration
    /// vetoes, an inference demotes. See `Signal.Kind.inferredRetryHostileCallee`.
    ///
    /// From `EffectResolver` this never fires alongside a declaration — that
    /// resolver only fills `inferredEffect` where `declaredEffect` is absent, so
    /// a weaker signal can never dilute a stronger one.
    ///
    /// **`SeedEffectResolver` deliberately breaks that pairing**, and the case it
    /// creates is the one worth having. A linter's `idempotency` seed names a
    /// function that annotated itself and whose body a cross-file walk found to
    /// reach non-idempotent work — so `declaredEffectSignal` corroborates at +15
    /// while this refutes at -45, on the same function, from different evidence.
    /// That is not a signal colliding with itself; it is a claim and its
    /// contradiction, and the reader should see both lines.
    static func inferredEffectSignal(for summary: FunctionSummary) -> Signal? {
        guard let inferred = summary.inferredEffect else { return nil }
        let what: String
        switch inferred {
        case .nonIdempotent:
            what = "non-idempotent"

        case .externallyIdempotent:
            what = "idempotent only through a dedup key"

        case .pure, .observational, .idempotent:
            // `EffectResolver.carriesInformationUpward` filters these out before
            // they reach a summary; the arm exists so that widening the resolver
            // is a compile error here rather than a silent new signal.
            return nil
        }
        return Signal(
            kind: .inferredRetryHostileCallee,
            weight: -45,
            detail: "Calls something declared \(what) — the effect was resolved from "
                + "this function's body, not from its own declaration, so it is "
                + "evidence about a callee rather than a refutation of the law"
        )
    }

    static func declaredEffectSignal(for summary: FunctionSummary) -> Signal? {
        guard let declared = summary.declaredEffect else { return nil }
        switch declared {
        case .idempotent:
            return Signal(
                kind: .declaredIdempotentEffect,
                weight: 15,
                detail: "Author-declared idempotent (`@Idempotent` / "
                    + "`@lint.effect idempotent`). NOTE the annotation claims "
                    + "RE-INVOCATION stability — calling it twice with the same "
                    + "argument gives the same result — which is weaker than the "
                    + "law here, `\(summary.name)(\(summary.name)(x)) == "
                    + "\(summary.name)(x)`, where the second call is fed the FIRST "
                    + "call's output"
            )

        case .nonIdempotent:
            return Signal(
                kind: .declaredNonIdempotentEffect,
                weight: Signal.vetoWeight,
                detail: "Author-declared NON-idempotent (`@NonIdempotent` / "
                    + "`@lint.effect non_idempotent`) — the declaration denies this "
                    + "exact law, so proposing it restates a claim the author "
                    + "already rejected"
            )

        case let .externallyIdempotent(keyParameter):
            let key = keyParameter.map { "`\($0)`" } ?? "a caller-supplied key"
            return Signal(
                kind: .declaredNonIdempotentEffect,
                weight: Signal.vetoWeight,
                detail: "Author-declared externally idempotent (dedup key: \(key)) — "
                    + "idempotent ONLY when routed through that key, so the "
                    + "unconditional `f(f(x)) == f(x)` this template emits is false "
                    + "as written"
            )

        case .observational, .pure:
            // Neither implies idempotence and neither denies it. `observational`
            // is retry-safe by definition; `pure` is orthogonal (`x + 1` is pure
            // and not idempotent). Staying silent is the claim: this template
            // scores on shape and on evidence about THIS law, and a tier that
            // says nothing about it must not move the score in either direction.
            return nil
        }
    }
}
