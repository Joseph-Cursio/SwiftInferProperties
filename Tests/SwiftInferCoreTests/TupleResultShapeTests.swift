import SwiftInferCore
import Testing

/// `TupleResultShape` reads a result type's spelling for the one fact about `==` that spelling
/// settles: whether it is, or wraps, a tuple — the type that never conforms to `Equatable`.
///
/// **Every row that is or wraps a tuple was checked against the compiler, not reasoned about**:
/// on Swift 6.4 (`swiftlang-6.4.0.34.1`), with each spelling as the result of
/// `func t(_ x: Int) -> <row>` and the property `{ value in t(value) == t(value) }`, every
/// `.tuple` row compiles and every other tuple-involving row fails with *binary operator '=='
/// cannot be applied* — except `Set<(Int, Int)>`, which the compiler rejects as a type before any
/// `==` (*type '(Int, Int)' does not conform to protocol 'Hashable'*). The implicitly unwrapped
/// rows are where reasoning went wrong once: `(Int, Int)!` was pinned as wrapped, and the compiler
/// force-unwraps it and compares the tuple.
@Suite("TupleResultShape — what a result's spelling says about `==`")
struct TupleResultShapeTests {

    /// `T!` and `sending T` compare as `T`: an implicitly unwrapped result is force-unwrapped once
    /// `Optional`'s `==` fails to type-check, and `sending` is an ownership specifier, not a type.
    @Test("a tuple of two to six elements has tuple `==`", arguments: [
        ("(text: String, didTruncate: Bool)", 2),
        ("(Double, Double)", 2),
        ("(String?, [Int], Set<String>)", 3),
        ("(Int, Int, Int, Int, Int, Int)", 6),
        ("((Int, Int))", 2),
        ("(Int, Int)!", 2),
        ("((Int, Int))!", 2),
        ("sending (Int, Int)", 2)
    ])
    func comparableTuples(typeText: String, arity: Int) {
        #expect(TupleResultShape(typeText: typeText) == .tuple(arity: arity))
    }

    @Test("seven elements is beyond the overloads", arguments: [
        "(Int, Int, Int, Int, Int, Int, Int)",
        "(Int, Int, Int, Int, Int, Int, Int)!"
    ])
    func sevenElementsIsBeyondTheOverloads(typeText: String) {
        let shape = TupleResultShape(typeText: typeText)
        #expect(shape == .tooManyElements(arity: 7))
        #expect(shape.equalityObstacle?.contains("at most six") == true)
    }

    @Test("an element that is, or wraps, a tuple", arguments: [
        "(Int, (Int, Int))",
        "(label: String, pair: (Int, Int))",
        "([(Int, Int)], Int)",
        "(Int, (Int, Int)?)",
        "(Int, (Int, Int))!",
        "sending (Int, (Int, Int))",
        "(Int, Swift.Optional<(Int, Int)>)"
    ])
    func nestedTuples(typeText: String) {
        let shape = TupleResultShape(typeText: typeText)
        #expect(shape == .nestedTuple)
        #expect(shape.equalityObstacle?.contains("itself a tuple") == true)
    }

    /// Sugar, long form, and the long form qualified by its module — `Swift.Optional<(Int, Int)>`
    /// is a member type, not an identifier, and was read as no tuple at all until it was named.
    @Test("a tuple inside an Optional or a collection", arguments: [
        "(Int, Int)?",
        "[(Int, Int)]",
        "[String: (Int, Int)]",
        "Optional<(Int, Int)>",
        "Array<(String, Bool)>",
        "Dictionary<String, (Int, Int)>",
        "[[(Int, Int)]]",
        "[(Int, Int)]!",
        "Swift.Optional<(Int, Int)>",
        "Swift.Array<(Int, Int)>",
        "Swift.Dictionary<String, (Int, Int)>",
        "ArraySlice<(Int, Int)>",
        "ContiguousArray<(Int, Int)>",
        "Swift.ContiguousArray<(Int, Int)>",
        "Set<(Int, Int)>",
        "sending [(Int, Int)]"
    ])
    func wrappedTuples(typeText: String) {
        let shape = TupleResultShape(typeText: typeText)
        #expect(shape == .wrappedTuple)
        #expect(shape.equalityObstacle?.contains("Optional or a collection") == true)
    }

    /// `(T)` is `T` in parentheses, `()` is `Void`, and a function type is not a tuple however
    /// its parameters and result are spelled — `(Int, Int) -> (Int, Int)` split at its first
    /// comma would read as two components. A container is the standard library's only when it
    /// is spelled bare or `Swift.`-qualified: another module's `Array` may define its own `==`.
    @Test("not a tuple", arguments: [
        "String",
        "[Token]",
        "(Int)",
        "()",
        "Int?",
        "Int!",
        "sending String",
        "[String: [Int]]",
        "(Int, Int) -> (Int, Int)",
        "(Int) -> (Int, Int)",
        "Result<Int, Error>",
        "Geometry.Array<(Int, Int)>",
        "not a type ((("
    ])
    func notTuples(typeText: String) {
        let shape = TupleResultShape(typeText: typeText)
        #expect(shape == .notATuple)
        #expect(shape.involvesTuple == false)
        #expect(shape.equalityObstacle == nil)
    }

    /// **A known limit, pinned so it is not mistaken for coverage.** The classifier reads the
    /// spelling, and `typealias Pair = (Int, Int)` spells `Pair` — so a throwing `-> Pair`
    /// reads as no tuple, and its `(try? f(x)) == (try? f(x))` stub is still written and does not
    /// compile (*'Pair?' (aka 'Optional<(Int, Int)>')*). Resolving it needs the scanned alias
    /// table and the declaring scope, which an accept-time gate has and this does not.
    @Test("a name for a tuple reads as the name it spells", arguments: ["Pair", "Geometry.Pair"])
    func anAliasIsReadAsSpelled(typeText: String) {
        #expect(TupleResultShape(typeText: typeText) == .notATuple)
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

    /// **Each spelling below would read as a tuple if the parse error were ignored** — the parser
    /// recovers `(Int, Int)` and leaves the rest as unexpected tokens. So these, unlike a
    /// non-tuple spelling that also fails to parse, show the guard is there.
    @Test func aSpellingThatDoesNotParseDeclinesNothing() {
        #expect(TupleResultShape(typeText: "(Int, Int) junk") == .notATuple)
        #expect(TupleResultShape(signature: "(Int) -> (Int, Int) preserving \\.isValid") == .notATuple)
        #expect(TupleResultShape(signature: "(Int, Int)") == .notATuple)
    }
}
