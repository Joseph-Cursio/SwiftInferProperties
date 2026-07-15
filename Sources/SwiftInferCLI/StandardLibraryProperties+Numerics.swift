import Foundation

/// swift-numerics (`apple/swift-numerics`) laws — the first external Apple
/// package in the catalog. `Complex<Double>` is a commutative field under `+`
/// and `×` for finite inputs, and `conjugate` is an involution. Associativity is
/// deliberately absent: like `Double`, complex `+`/`×` inherit floating-point
/// non-associativity, so the whole structure is not a `Monoid` (mirrors the
/// `Double` rows + caveat).
///
/// These carry `imports: ["ComplexModule"]`, so `--verify` builds them against
/// the real swift-numerics release (`KnownPropertiesPackageVerify`) rather than
/// the stdlib interpreter.
extension StandardLibraryProperties {

    static let numericsLaws: [KnownProperty] = [
        law(
            "Complex", "commutative under + (finite inputs)", "a + b == b + a",
            "let a = Complex(randDouble(), randDouble()), b = Complex(randDouble(), randDouble()); "
                + "return a + b == b + a",
            witnesses: "CommutativeMonoid", template: "commutativity",
            note: "Finite inputs only. NOT a Monoid — complex `+` inherits Double's non-associativity.",
            imports: ["ComplexModule"]
        ),
        law(
            "Complex", "commutative under * (finite inputs)", "a * b == b * a",
            "let a = Complex(randDouble(), randDouble()), b = Complex(randDouble(), randDouble()); "
                + "return a * b == b * a",
            template: "commutativity",
            note: "Finite inputs only.",
            imports: ["ComplexModule"]
        ),
        law(
            "Complex", "additive identity", "a + .zero == a",
            "let a = Complex(randDouble(), randDouble()); return a + .zero == a",
            imports: ["ComplexModule"]
        ),
        law(
            "Complex", "conjugate is an involution", "z.conjugate.conjugate == z",
            "let z = Complex(randDouble(), randDouble()); return z.conjugate.conjugate == z",
            template: "involution",
            imports: ["ComplexModule"]
        )
    ]
}
