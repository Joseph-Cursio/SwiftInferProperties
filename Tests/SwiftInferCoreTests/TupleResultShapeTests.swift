import SwiftInferCore
import Testing

/// `TupleResultShape` reads a result type's spelling for the one fact about `==` that spelling
/// settles: whether it is, or wraps, a tuple — the type that never conforms to `Equatable`.
///
/// Every row below was checked against the compiler, not reasoned about: on Swift 6.4
/// (`swiftlang-6.4.0.34.1`) `f(x) == f(x)` compiles for the `.tuple` rows and fails with
/// *binary operator '==' cannot be applied* for the 7-tuple, the nested tuple, `(Int, Int)?`,
/// `[(Int, Int)]` and `[String: (Int, Int)]`.
@Suite("TupleResultShape — what a result's spelling says about `==`")
struct TupleResultShapeTests {

    @Test("a tuple of two to six elements has tuple `==`", arguments: [
        ("(text: String, didTruncate: Bool)", 2),
        ("(Double, Double)", 2),
        ("(String?, [Int], Set<String>)", 3),
        ("(Int, Int, Int, Int, Int, Int)", 6),
        ("((Int, Int))", 2)
    ])
    func comparableTuples(typeText: String, arity: Int) {
        #expect(TupleResultShape(typeText: typeText) == .tuple(arity: arity))
    }

    @Test func sevenElementsIsBeyondTheOverloads() {
        let shape = TupleResultShape(typeText: "(Int, Int, Int, Int, Int, Int, Int)")
        #expect(shape == .tooManyElements(arity: 7))
        #expect(shape.equalityObstacle?.contains("at most six") == true)
    }

    @Test("an element that is, or wraps, a tuple", arguments: [
        "(Int, (Int, Int))",
        "(label: String, pair: (Int, Int))",
        "([(Int, Int)], Int)",
        "(Int, (Int, Int)?)"
    ])
    func nestedTuples(typeText: String) {
        #expect(TupleResultShape(typeText: typeText) == .nestedTuple)
    }

    @Test("a tuple inside an Optional or a collection", arguments: [
        "(Int, Int)?",
        "(Int, Int)!",
        "[(Int, Int)]",
        "[String: (Int, Int)]",
        "Optional<(Int, Int)>",
        "Array<(String, Bool)>",
        "Dictionary<String, (Int, Int)>",
        "[[(Int, Int)]]"
    ])
    func wrappedTuples(typeText: String) {
        let shape = TupleResultShape(typeText: typeText)
        #expect(shape == .wrappedTuple)
        #expect(shape.equalityObstacle?.contains("Optional or a collection") == true)
    }

    /// `(T)` is `T` in parentheses, `()` is `Void`, and a function type is not a tuple however
    /// its parameters and result are spelled — `(Int, Int) -> (Int, Int)` split at its first
    /// comma would read as two components.
    @Test("not a tuple", arguments: [
        "String",
        "[Token]",
        "(Int)",
        "()",
        "Int?",
        "[String: [Int]]",
        "(Int, Int) -> (Int, Int)",
        "(Int) -> (Int, Int)",
        "Result<Int, Error>",
        "not a type ((("
    ])
    func notTuples(typeText: String) {
        let shape = TupleResultShape(typeText: typeText)
        #expect(shape == .notATuple)
        #expect(shape.involvesTuple == false)
        #expect(shape.equalityObstacle == nil)
    }

    // MARK: - Reading the result out of a whole signature

    @Test func theSignaturesResultIsRead() {
        let shape = TupleResultShape(signature: "(String, Int) async throws -> (json: String, prompt: String)")
        #expect(shape == .tuple(arity: 2))
    }

    /// The first `->` belongs to the closure parameter, not the function.
    @Test func aClosureParameterIsNotTheResult() {
        #expect(TupleResultShape(signature: "((Int) -> (Int, Int), [Int]) -> Int") == .notATuple)
        #expect(TupleResultShape(signature: "((Int) -> Int, [Int]) -> (Int, Int)") == .tuple(arity: 2))
    }

    /// A function returning a function: the result is the inner function type, not its tuple.
    @Test func aCurriedResultIsAFunctionNotATuple() {
        #expect(TupleResultShape(signature: "(Int) throws -> (Int, Int) -> (Int, Int)") == .notATuple)
    }

    @Test func aSignatureThatDoesNotParseDeclinesNothing() {
        #expect(TupleResultShape(signature: "(Widget) -> Widget preserving \\.isValid") == .notATuple)
        #expect(TupleResultShape(signature: "(Int, Int)") == .notATuple)
    }
}
