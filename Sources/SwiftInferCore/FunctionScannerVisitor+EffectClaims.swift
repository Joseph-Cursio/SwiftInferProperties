import PropertyLawCore
import SwiftEffectInference
import SwiftSyntax

/// The author's own effect claims, read off a declaration's annotations.
///
/// **Three readings of one annotation vocabulary by one parser, grouped into a named value.**
/// They were three local `let`s inside `makeSummary` until #482 added a line to that function and
/// pushed it past the body-length cap; grouping them is the extraction that file wanted anyway,
/// since nothing between them reads the others.
///
/// **A struct rather than a tuple, and a file rather than a nested type**, for two reasons the
/// linter states and one it does not: tuples are capped at two members, `FunctionScannerVisitor+Summary.swift`
/// is at its 400-line ceiling, and a named field reads better than `.2` at the call site.
///
/// They are three AXES, not one fact in three forms. `@lint.determinism` says the result does not
/// vary with time; `@lint.effect` says what re-running costs; `declaresUnknown` is the explicit
/// *I do not know* that both vocabularies admit. Until the effect line was added the parser was
/// called for determinism alone, so `@Idempotent` / `@NonIdempotent` / `@ExternallyIdempotent`
/// were parsed by a linked dependency and read by nothing.
struct EffectClaims {

    /// `@lint.determinism` — the result does not vary with the clock.
    let isClockDeterministic: Bool

    /// The explicit *unknown* claim, which is not the same as making no claim.
    let declaresUnknown: Bool

    /// `@lint.effect` — what re-running this costs. `nil` when the author claims nothing.
    let declared: Effect?
}

extension FunctionScannerVisitor {

    /// Read every effect claim off `node`.
    ///
    /// Same scan-time posture as the purity verdict: computed where the live
    /// `FunctionDeclSyntax` exists, and carried on the summary rather than recomputed.
    func effectClaims(of node: FunctionDeclSyntax) -> EffectClaims {
        EffectClaims(
            isClockDeterministic: EffectAnnotationParser.isClockDeterministic(declaration: node),
            declaresUnknown: EffectAnnotationParser.declaresUnknownEffect(declaration: node),
            declared: EffectAnnotationParser.parseEffect(declaration: node)
        )
    }
}
