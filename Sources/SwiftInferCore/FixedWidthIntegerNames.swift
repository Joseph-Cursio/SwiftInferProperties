/// The standard library's ten fixed-width integer type names, as the single
/// source for the several curated lists that each need "the integer types" for
/// their own reason.
///
/// **Why one list.** Three constants had each hand-copied the same ten names for
/// three *different* predicates that happen to coincide:
///
/// - `HomomorphismTemplate.integerCodomains` — integer `+` is exact, so a measure
///   homomorphism holds under `==` (unlike `Double`/`Float`, where rounding
///   breaks associativity).
/// - `StrategistDispatchEmitter.shrinkableScalarCarriers` — carriers whose values
///   can be shrunk via `shrink(towards: 0)`.
/// - `StrategistDispatchEmitter.shrinkableMonotonicityCarriers` — the same ten
///   plus the binary floats.
///
/// The *predicates* stay distinct — each keeps its own name, doc, and rationale —
/// and only the **membership** is shared, because "the fixed-width integer types"
/// is a closed fact about the language rather than a per-template judgement. A
/// drifted copy (one list quietly missing `UInt8`, say) would change which
/// carriers a template accepts with no compile error and no test necessarily
/// covering it. Deriving them all from here makes that impossible.
///
/// If one of those predicates ever genuinely needs to diverge, it should stop
/// deriving from this list and state why, rather than editing a private copy.
public enum FixedWidthIntegerNames {

    /// The ten fixed-width integer types in the standard library.
    public static let names: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64"
    ]

    /// The two binary floating-point types, for lists that admit floats alongside
    /// the integers (`shrink(towards: 0)` is well-defined on both).
    public static let binaryFloatNames: Set<String> = ["Double", "Float"]

    /// The fixed-width integers plus the binary floats — the shrinkable scalars.
    public static let withBinaryFloats: Set<String> = names.union(binaryFloatNames)
}
