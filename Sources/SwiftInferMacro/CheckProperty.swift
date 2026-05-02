// `@CheckProperty(...)` peer macro — user-facing declaration. The macro
// implementation lives in `SwiftInferMacroImpl`; this file is the only
// surface library callers import. Re-exports `ProtocolLawKit` so the
// macro-emitted test stub's `SwiftPropertyBasedBackend` + `Seed`
// references resolve in the user's test target without a second
// `import` line.
@_exported import ProtocolLawKit

/// Property the `@CheckProperty(...)` macro should generate a test
/// stub for. Each case maps to one M5/M7 sub-milestone:
///
/// - `.idempotent` (M5.2) — `f(f(x)) == f(x)` for an `f: T -> T`.
/// - `.roundTrip(pairedWith:)` (M5.3) — `g(f(x)) == x` for `f: T -> U`
///   paired with `g: U -> T`.
/// - `.preservesInvariant(_:)` (M7.2) — `inv(f(x))` whenever `inv(x)`,
///   for an `f: T -> T` (or `T -> U` where the predicate is on the
///   shared root). Recognize-only in M7.2 — the scanner picks the
///   annotation up via `FunctionScanner` and surfaces a Strong-tier
///   suggestion through `swift-infer discover`. Macro expansion of
///   the case into a peer `@Test func` lands as the M7.2.a addendum
///   per the M7 plan's "Out of scope" §; for now the macro impl
///   recognises the case and emits no peer (no diagnostic, no
///   generated code).
///
/// `@unchecked Sendable`: `AnyKeyPath` is not `Sendable` in Swift 6.1,
/// but `CheckPropertyKind` values never cross actor isolation at
/// runtime — the macro impl consumes them as `AttributeSyntax` AST
/// text in a separate compiler-plugin process; the user's program
/// never instantiates the enum. Marking unchecked here keeps the
/// existing cases' Sendable guarantee for type-system consumers
/// without rejecting the keypath-bearing case.
public enum CheckPropertyKind: @unchecked Sendable {
    case idempotent
    case roundTrip(pairedWith: String)
    case preservesInvariant(_ predicate: AnyKeyPath)
}

/// Attach to a function declaration to expand a peer `@Test` stub
/// running the named property under the M4.3 sampling seed (PRD v0.4
/// §16 #6) and `SwiftPropertyBasedBackend`. PRD §5.7 + §5.8 M5.
///
/// The macro expands at *the user's* compile time (it's a peer macro
/// in the user's source), not at SwiftInferProperties build time.
/// Counterexamples are reported via Swift Testing's `Issue.record`,
/// matching the kit's `@ProtoLawSuite` convention.
@attached(peer, names: arbitrary)
public macro CheckProperty(_ kind: CheckPropertyKind) =
    #externalMacro(module: "SwiftInferMacroImpl", type: "CheckPropertyMacro")
