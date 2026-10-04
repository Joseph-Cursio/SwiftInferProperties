import SwiftSyntax

/// The effects a function-type spelling declares for the function **itself** — `async` and
/// `throws` before its own `->`, not those of a closure among its parameters or of a function it
/// returns.
///
/// ## Why not `signature.contains(" throws")`
///
/// That substring cannot tell `(Int) throws -> (Int, Int)` from
/// `(@Sendable (Int) throws -> Int, Int) -> (Int, Int)`, whose function does not throw. The
/// determinism accept path used it to decide the subject throws and returns a tuple, and so said
/// exactly that of a function that does neither of the first — while the law's own caveats, read
/// from the scanner's `isThrows`, said the opposite. Parsed with the same reader as
/// `TupleResultShape(signature:)`, so the result and the effects come from one reading of one
/// spelling.
public struct FunctionTypeEffects: Equatable, Sendable {

    /// The function is declared `async`.
    public let isAsync: Bool

    /// The function is declared `throws` (typed or untyped).
    public let isThrows: Bool

    /// The effects of the function type spelled `signature`, or `nil` when it does not parse as
    /// one — a trailing `preserving \.x` clause, a bare tuple — so a caller keeps whatever reading
    /// it had for a spelling this cannot read.
    public init?(signature: String) {
        guard let function = TupleResultShape.parsedType(signature)?.as(FunctionTypeSyntax.self) else {
            return nil
        }
        isAsync = function.effectSpecifiers?.asyncSpecifier != nil
        isThrows = function.effectSpecifiers?.throwsClause != nil
    }
}
