/// V1.4.3 — curated lists of type names whose underlying storage is
/// IEEE 754 floating-point. Operations on these types are not bit-
/// exactly associative / commutative / invertible under random
/// sampling, so the associativity / commutativity / inverse-pair
/// templates emit a `-10 .floatingPointStorage` counter-signal when
/// the candidate type appears here.
///
/// **Two-list split.** PropertyLawKit's `checkFloatingPointPropertyLaws`
/// is the kit's canonical entry point for FP-typed property checks
/// (kit `FloatingPointLaws.swift`'s load-bearing comment: "A type
/// spelled `: FloatingPoint` emits only `checkFloatingPointPropertyLaws`").
/// SwiftInfer's cycle-1 calibration patch aligns with that posture by
/// splitting the curated list into two:
///
/// - `kitSupportedFloatingPoint` — types that **conform to FloatingPoint**
///   in stdlib / Foundation. The explainability pointer for these names
///   `checkFloatingPointPropertyLaws(for: T.self, using: gen)` as the
///   kit-supported alternative.
/// - `nonKitSupportedFloatingPoint` — types whose **storage** is IEEE
///   754 but which **don't conform to FloatingPoint** (notably
///   `Complex<RealType>` and `Decimal`). The explainability pointer
///   here flags the cycle-2-deferred approximate-equality template
///   arm; users are pointed at PropertyLawKit's tolerance posture for
///   manual authoring in the meantime.
///
/// **Identity-element exempt.** `x + 0.0 == x` modulo NaN is reliably
/// true on FP types — the kit explicitly relies on this in
/// `checkRoundedZeroIdentity`. Identity-element template doesn't emit
/// the counter-signal even when T is FP-storage.
///
/// **Round-trip exempt for cycle 1.** Codable round-trip on `Double` IS
/// bit-exact via `JSONEncoder` (the kit's recommended path). Round-trip
/// is also the highest-volume Possible-tier template (990 hits in the
/// cycle-1 baseline) — blanket-suppressing it would be a much larger
/// calibration claim than cycle 1 supports. Deferred to cycle 2.
///
/// **Generic stripping.** `Complex<Double>` / `Complex<Float>` strip to
/// `Complex` before lookup (textual `firstIndex(of: "<")` strip).
///
/// **List freshness.** Hand-curated. New FP types in stdlib (e.g.
/// `BFloat16`) won't suppress until added here. Cycle 2 may lift to
/// `Vocabulary.floatingPointTypes` per the M13.3 marker-table pattern.
public enum FloatingPointStorageNames {

    /// Types that conform to `FloatingPoint` in stdlib / Foundation.
    /// PropertyLawKit's `checkFloatingPointPropertyLaws` accepts any
    /// `Value: FloatingPoint`, so these are the names where the
    /// explainability pointer can name a real kit alternative.
    public static let kitSupportedFloatingPoint: Set<String> = [
        "Float",
        "Double",
        "Float16",
        "Float32",
        "Float64",
        "Float80",
        "CGFloat"
    ]

    /// Types with IEEE 754-derived storage that don't conform to
    /// `FloatingPoint`. Kit's pre-built check doesn't apply; the user
    /// would need to write a custom approximate-equality law. Cycle 1
    /// suppresses; cycle 2 plans an approximate-equality template arm.
    public static let nonKitSupportedFloatingPoint: Set<String> = [
        "Complex",
        "Decimal"
    ]

    /// Returns `true` when `typeText` matches a curated FP-storage
    /// type name (kit-supported OR not). Generic parameters are
    /// stripped textually before lookup.
    public static func contains(_ typeText: String) -> Bool {
        let stripped = strippingGenericParameters(typeText)
        return kitSupportedFloatingPoint.contains(stripped)
            || nonKitSupportedFloatingPoint.contains(stripped)
    }

    /// Returns `true` when `typeText` matches a kit-supported FP type
    /// (Float / Double / etc — anything that conforms to `FloatingPoint`).
    /// Used by the explainability annotation to decide whether to point
    /// at `checkFloatingPointPropertyLaws` (kit-supported) or the
    /// cycle-2-deferred approximate-equality template arm (non-kit-
    /// supported).
    public static func isKitSupported(_ typeText: String) -> Bool {
        kitSupportedFloatingPoint.contains(strippingGenericParameters(typeText))
    }

    /// Strip a single generic-parameter list from a textual type name.
    /// `Complex<Double>` → `Complex`, `Array<Int>` → `Array`,
    /// `Foo` → `Foo`. Pure textual operation — does not handle nested
    /// generics or type aliases (V1.4.3 limitation; cycle-2 vocabulary
    /// extension can address richer matching).
    public static func strippingGenericParameters(_ name: String) -> String {
        guard let openAngle = name.firstIndex(of: "<") else { return name }
        return String(name[..<openAngle])
    }
}
