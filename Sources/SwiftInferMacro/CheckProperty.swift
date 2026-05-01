// `@CheckProperty(...)` peer macro — user-facing declaration. The macro
// implementation lives in `SwiftInferMacroImpl`; this file is the only
// surface library callers import. Re-exports `ProtocolLawKit` so the
// macro-emitted test stub's `SwiftPropertyBasedBackend` + `Seed`
// references resolve in the user's test target without a second
// `import` line.
@_exported import ProtocolLawKit

/// Property the `@CheckProperty(...)` macro should generate a test
/// stub for. Each case maps to one M5 sub-milestone:
///
/// - `.idempotent` (M5.2) — `f(f(x)) == f(x)` for an `f: T -> T`.
/// - `.roundTrip(pairedWith:)` (M5.3) — `g(f(x)) == x` for `f: T -> U`
///   paired with `g: U -> T`.
public enum CheckPropertyKind: Sendable {
    case idempotent
    case roundTrip(pairedWith: String)
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
