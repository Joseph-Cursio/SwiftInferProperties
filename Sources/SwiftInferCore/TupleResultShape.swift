import SwiftParser
import SwiftSyntax

/// What a result type's **spelling** says about comparing two of its values with `==`, as far as
/// tuples go.
///
/// ## Why tuples need their own answer
///
/// A tuple is not a nominal type and cannot conform to `Equatable` — this repository measured that
/// on 2026-08-08 (`KitSuiteEmitter+GeneratorShaping.swift`) and it still holds on Swift 6.4. What
/// the standard library offers instead is a family of `==` overloads over tuples of **two to six**
/// `Equatable` elements. So `f(x) == f(x)` over a `(text: String, didTruncate: Bool)` compiles,
/// and every shape that needs the tuple itself to conform does not. Measured with `swiftc` on
/// Swift 6.4 (`swiftlang-6.4.0.34.1`), each of these fails with *binary operator '==' cannot be
/// applied*:
///
/// - a tuple of seven or more elements,
/// - a tuple with a tuple element, `(Int, (Int, Int))`,
/// - a tuple inside an `Optional` or a collection — `(Int, Int)?`, `[(Int, Int)]`,
///   `[String: (Int, Int)]` — each of which is `Equatable` only when its payload conforms,
/// - and `(try? f(x)) == (try? f(x))` over a tuple, the same `Optional` case reached through `try?`.
///
/// ## What it deliberately does not do
///
/// It reads the spelling, never conformances: whether each element of a 2…6 tuple is `Equatable`
/// is the producer's per-element check, as it is for a nominal result. A **function-typed** result
/// is not a tuple even when both its parameter list and its own result are parenthesised —
/// `(Int, Int) -> (Int, Int)` split at its first comma reads as two "components", which is why
/// this parses with `SwiftParser` rather than splitting text.
public enum TupleResultShape: Equatable, Sendable {

    /// Not a tuple and wraps none — nothing about `==` follows from the spelling. Also the answer
    /// for a spelling that does not parse, so an unreadable result declines nothing.
    case notATuple

    /// A tuple of two to six elements, none of which is or wraps a tuple: `==` resolves when every
    /// element is `Equatable`.
    case tuple(arity: Int)

    /// A tuple of more elements than the standard library's six `==` overloads cover.
    case tooManyElements(arity: Int)

    /// A tuple with an element that is itself a tuple, or wraps one.
    case nestedTuple

    /// Not a tuple, but one sits inside an `Optional`, `Array`, `Set` or `Dictionary`.
    case wrappedTuple

    /// The shape of the type spelled `typeText`, e.g. `(text: String, didTruncate: Bool)`.
    public init(typeText: String) {
        guard let type = Self.parsedType(typeText) else {
            self = .notATuple
            return
        }
        self = Self.shape(of: type)
    }

    /// The shape of the RESULT of a function type spelled `signature`, the form an `Evidence` row
    /// carries: `(String, Int) async throws -> (json: String, prompt: String)`.
    ///
    /// Parsed as a whole rather than split at the first `->`, so a closure-typed parameter
    /// (`((Int) -> Int, [Int]) -> (Int, Int)`) cannot be mistaken for the result.
    public init(signature: String) {
        guard let function = Self.parsedType(signature)?.as(FunctionTypeSyntax.self) else {
            self = .notATuple
            return
        }
        self = Self.shape(of: function.returnClause.type)
    }

    /// True for every shape that is or wraps a tuple.
    public var involvesTuple: Bool {
        self != .notATuple
    }

    /// Why no `==` between two values of this type can compile, phrased to follow "returns", or
    /// `nil` when the spelling alone does not rule it out.
    public var equalityObstacle: String? {
        switch self {
        case .notATuple, .tuple:
            return nil

        case .tooManyElements(let arity):
            return "a \(arity)-element tuple, and Swift defines `==` on tuples of at most six elements"

        case .nestedTuple:
            return "a tuple with an element that is itself a tuple (or wraps one), and a tuple cannot "
                + "conform to Equatable, so the outer tuple has no `==`"

        case .wrappedTuple:
            return "a tuple inside an Optional or a collection, which has `==` only when its element "
                + "conforms to Equatable — and a tuple cannot"
        }
    }

    /// What a comparable tuple needs, for a caveat or a note that would otherwise say the return
    /// type "must be Equatable" — which no tuple can be. Begins mid-sentence, after "for … to
    /// compile", so each caller supplies its own subject.
    public static let elementwiseEqualityClause = "Swift defines `==` on tuples of two to six "
        + "Equatable elements, though a tuple itself never conforms to Equatable"

    // MARK: - Reading the spelling

    private static func parsedType(_ text: String) -> TypeSyntax? {
        var parser = Parser(text)
        let type = TypeSyntax.parse(from: &parser)
        return type.hasError ? nil : type
    }

    private static func shape(of type: TypeSyntax) -> Self {
        if let elements = tupleElements(of: type) {
            if elements.count > 6 {
                return .tooManyElements(arity: elements.count)
            }
            if elements.contains(where: isOrWrapsTuple) {
                return .nestedTuple
            }
            return .tuple(arity: elements.count)
        }
        if let parenthesised = parenthesisedType(type) {
            return shape(of: parenthesised)
        }
        return wrappedTypes(of: type).contains(where: isOrWrapsTuple) ? .wrappedTuple : .notATuple
    }

    /// The element types of a tuple of two or more, or `nil` when `type` is not one.
    private static func tupleElements(of type: TypeSyntax) -> [TypeSyntax]? {
        guard let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count >= 2 else { return nil }
        return tuple.elements.map(\.type)
    }

    /// `(T)` is `T` in parentheses, not a tuple.
    private static func parenthesisedType(_ type: TypeSyntax) -> TypeSyntax? {
        guard let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
              let only = tuple.elements.first, only.firstName == nil else { return nil }
        return only.type
    }

    private static func isOrWrapsTuple(_ type: TypeSyntax) -> Bool {
        if tupleElements(of: type) != nil { return true }
        if let parenthesised = parenthesisedType(type) { return isOrWrapsTuple(parenthesised) }
        return wrappedTypes(of: type).contains(where: isOrWrapsTuple)
    }

    /// The payload types of the standard containers whose `Equatable` conformance is conditional
    /// on them — sugar and long form alike. A function type wraps nothing: its parameters and
    /// result are not values the comparison reaches.
    private static func wrappedTypes(of type: TypeSyntax) -> [TypeSyntax] {
        if let optional = type.as(OptionalTypeSyntax.self) { return [optional.wrappedType] }
        if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return [unwrapped.wrappedType] }
        if let array = type.as(ArrayTypeSyntax.self) { return [array.element] }
        if let dictionary = type.as(DictionaryTypeSyntax.self) { return [dictionary.key, dictionary.value] }
        guard let identifier = type.as(IdentifierTypeSyntax.self),
              containerNames.contains(identifier.name.text),
              let arguments = identifier.genericArgumentClause?.arguments else { return [] }
        return arguments.compactMap { generic in
            guard case .type(let argument) = generic.argument else { return nil }
            return argument
        }
    }

    private static let containerNames: Set<String> = [
        "Optional", "Array", "ArraySlice", "ContiguousArray", "Set", "Dictionary"
    ]
}
