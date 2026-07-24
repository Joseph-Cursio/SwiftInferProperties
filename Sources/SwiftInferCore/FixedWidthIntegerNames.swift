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

    /// The five signed fixed-width integer types. Some callers want only these —
    /// a law about negative representability (`MeasureTemplate`), or a generator
    /// whose edge values include `-1` (`LiftedTestEmitter`) — so the signed and
    /// unsigned halves are the primitives and `names` is their union, rather than
    /// the halves being re-listed wherever one is needed.
    public static let signed: Set<String> = ["Int", "Int8", "Int16", "Int32", "Int64"]

    /// The five unsigned fixed-width integer types.
    public static let unsigned: Set<String> = ["UInt", "UInt8", "UInt16", "UInt32", "UInt64"]

    /// The ten fixed-width integer types in the standard library.
    public static let names: Set<String> = signed.union(unsigned)

    /// The `Swift.`-qualified spellings (`Swift.Int`, …). Source that names types
    /// module-qualified is matched against these; several recognisers accept both
    /// spellings and had each written the qualified ten out a second time.
    public static let swiftQualified: Set<String> = Set(names.map { "Swift." + $0 })

    /// The two binary floating-point types, for lists that admit floats alongside
    /// the integers (`shrink(towards: 0)` is well-defined on both).
    public static let binaryFloatNames: Set<String> = ["Double", "Float"]

    /// The fixed-width integers plus the binary floats — the shrinkable scalars.
    public static let withBinaryFloats: Set<String> = names.union(binaryFloatNames)
}
