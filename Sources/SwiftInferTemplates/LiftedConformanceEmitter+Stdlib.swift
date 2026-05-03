import SwiftInferCore

/// Stdlib protocol arms for `LiftedConformanceEmitter` — the
/// secondary / Ring writeouts that target stdlib protocols rather
/// than kit-defined ones (`SetAlgebra` from M8.4.b.1, `Numeric` from
/// M8.4.b.2).
extension LiftedConformanceEmitter {

    /// Emit a stdlib `SetAlgebra` conformance extension for `typeName`.
    /// **Secondary arm** to a primary Semilattice claim per PRD §5.4
    /// row 4's "suggest SetAlgebra if applicable" + M8 plan open
    /// decision #3 default `(a)`. Surfaces alongside Semilattice in
    /// the `[A/B/B'/s/n/?]` extended prompt when the type's binary op
    /// has a curated set-shaped name (`union` / `intersect` /
    /// `subtract` / etc.).
    ///
    /// Stdlib `SetAlgebra` requires far more than the bounded-join-
    /// semilattice signals on their own provide (`insert`, `remove`,
    /// `contains`, four `is*Subset(of:)` / `is*Superset(of:)` /
    /// `isDisjoint(with:)` predicates). The emitted extension is
    /// **bare** — `extension TypeName: SetAlgebra {}` — relying on the
    /// user's existing implementation of those requirements. The §4.5
    /// caveat (added by M8.4.b.1's orchestrator) lists the unmet
    /// requirements explicitly so the user knows what to fill in or
    /// drop the conformance over.
    ///
    /// No witness aliasing — SetAlgebra's required identifiers don't
    /// have a single canonical-rename pattern like Semigroup's
    /// `combine` / Monoid's `identity`. The user satisfies SetAlgebra
    /// directly through their own type's declared methods.
    public static func setAlgebra(
        typeName: String,
        explainability: ExplainabilityBlock
    ) -> String {
        LiftedConformanceTemplate.makeExtension(
            typeName: typeName,
            protocolName: "SetAlgebra",
            body: nil,
            explainability: explainability
        )
    }

    /// Emit a stdlib `Numeric` conformance extension for `typeName`.
    /// **Ring arm** (M8.4.b.2) — the orchestrator emits a Ring claim
    /// when the type has two Monoid-shaped binary ops, one with a
    /// curated additive name (`+` / `add` / `plus` / `sum`) and one
    /// multiplicative (`*` / `multiply` / `times` / `mul` / `product`).
    /// PRD §5.4 row 5: "two monoids on same type, distributive →
    /// Ring → suggest Numeric (with caveats)".
    ///
    /// Like the M8.4.b.1 SetAlgebra arm, the emitted extension is
    /// **bare** — `extension TypeName: Numeric {}` — relying on the
    /// user's existing `+` / `*` / `-` operator implementations and
    /// `Numeric.init?(exactly:)` / `Magnitude` associated type.
    /// stdlib `Numeric` is a substantial protocol surface; the §4.5
    /// caveat (added by the orchestrator) lists what's not implied
    /// by the two-monoid signals so the user knows what to fill in
    /// or drop the conformance over. Includes the IEEE-754 caveat
    /// for floating-point types where exact-equality algebraic laws
    /// don't hold.
    ///
    /// No witness aliasing — `Numeric`'s required operators have
    /// canonical names (`+`, `-`, `*`) the user's type either provides
    /// or doesn't. Aliasing would conflict with operator overload
    /// resolution.
    public static func numeric(
        typeName: String,
        explainability: ExplainabilityBlock
    ) -> String {
        LiftedConformanceTemplate.makeExtension(
            typeName: typeName,
            protocolName: "Numeric",
            body: nil,
            explainability: explainability
        )
    }
}
