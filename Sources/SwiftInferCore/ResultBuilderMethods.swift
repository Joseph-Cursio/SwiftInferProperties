/// The closed, compiler-defined set of `@resultBuilder` method names — the
/// plumbing a result builder must supply for the compiler to call, and which
/// no property template should propose a law about.
///
/// ## What this fixes
///
/// `docs/parsing-catalog-gap.md` §8. Every result-builder method has the shape
/// `(Component) -> Component`, so type-symmetry pairing turns one builder into
/// a clique. On swift-syntax's `SwiftSyntaxBuilder` — 23 suggestions total,
/// **21 of them from one file**, `ListBuilder.swift`:
///
///     round-trip:   buildBlock ↔ buildEither(first:)
///     round-trip:   buildEither(first:) ↔ buildEither(second:)
///     inverse-pair: (the same pairs again)
///     idempotence:  buildEither(first:), buildOptional, buildLimitedAvailability, …
///
/// `buildEither(first:)` and `buildEither(second:)` are the two arms of an
/// `if`/`else`. Proposing them as inverses of each other is the least
/// meaningful claim in the catalog.
///
/// The idempotence rows are not false — they are **unrefutable**, which is
/// worse. Several of these methods are literally the identity
/// (`buildEither(first component: Component) -> Component { component }`), so
/// `f(f(x)) == f(x)` holds by construction and no implementation could fail
/// it. That is the `f(x) == f(x)` shape PRD §3.5 and the Appendix C rule
/// "score refutability, not suggestion count" exist to keep out.
///
/// ## Why the NAME and not the attribute
///
/// The obvious gate is `@resultBuilder` on the declaring type. Measured
/// against the motivating case, it does not work: swift-syntax declares
///
///     public protocol ListBuilder { … }
///
/// with **no `@resultBuilder` attribute** — the attribute goes on the
/// conforming types elsewhere, while the methods and their default
/// implementations live on the bare protocol. An attribute gate would reach
/// none of the 21 rows.
///
/// The names are the better gate anyway, because they are not a heuristic:
/// the compiler defines exactly this list (SE-0289, extended by SE-0348's
/// `buildPartialBlock`), and a type that spells one of them means the
/// result-builder method or it means nothing the compiler will call.
///
/// Matched **exactly**, never by a `build` prefix — `buildRequest`,
/// `buildURL`, `buildIndex` are ordinary functions that may own real laws.
public enum ResultBuilderMethods {

    /// Every method name the result-builder transform recognises. Bare names
    /// as the scanner records them: `buildEither(first:)` is stored with
    /// `name == "buildEither"` and the label kept separately.
    public static let curated: Set<String> = [
        "buildBlock",
        "buildOptional",
        "buildEither",
        "buildArray",
        "buildExpression",
        "buildFinalResult",
        "buildLimitedAvailability",
        "buildPartialBlock"
    ]

    /// Whether `methodName` is one of the compiler-called builder methods.
    public static func isBuilderMethod(_ methodName: String) -> Bool {
        curated.contains(methodName)
    }
}
