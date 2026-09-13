@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// Reading the sub-domain a function's first statement carves out.
///
/// The one law shape this walk found that is written **in the code** rather than guessed from a
/// signature — `docs/measurements/s3-characterisation.md`.
@Suite("GuardDomainReader")
struct GuardDomainReaderTests {

    private func read(_ source: String) -> GuardDomain? {
        let tree = Parser.parse(source: source)
        let finder = Finder(viewMode: .sourceAccurate)
        finder.walk(tree)
        return finder.found.flatMap(GuardDomainReader.read)
    }

    /// The walk's motivating case, verbatim from `SwiftMarkdownWiki/Editor/FrontMatter.swift`.
    @Test func theMotivatingCase() throws {
        let domain = try #require(read("""
        func parse(from source: String) -> (FrontMatter, String) {
            guard source.hasPrefix("---") else {
                return (Self(), source)
            }
            return (Self(), "")
        }
        """))
        #expect(domain.condition == #"source.hasPrefix("---")"#)
        #expect(domain.returnedExpression == "(Self(), source)")
        #expect(domain.parameterName == "source")
        #expect(domain.firesWhenConditionHolds == false)
    }

    /// **`guard` and `if` state OPPOSITE sub-domains**, and an inverted law would be checked over
    /// exactly the inputs it does not describe.
    @Test func anIfStatesTheOppositeDomain() throws {
        let domain = try #require(read("""
        func f(_ value: String) -> Bool {
            if value.isEmpty { return true }
            return false
        }
        """))
        #expect(domain.firesWhenConditionHolds)
        #expect(domain.condition == "value.isEmpty")
    }

    // MARK: - What is refused

    /// **An optional binding is not a domain claim** — it propagates a `nil`. 537 of 3 358
    /// functions open with an early return and only 121 carry a predicate; admitting bindings
    /// would make four fifths of the population noise.
    @Test("a binding condition is not a predicate", arguments: [
        "func f(_ v: String?) -> Int? { guard let v else { return nil }\n return v.count }",
        "func f(_ v: Any) -> Bool { guard case let s as String = v else { return false }\n return !s.isEmpty }"
    ])
    func bindingsAreRefused(source: String) {
        #expect(read(source) == nil)
    }

    /// **A condition the caller cannot evaluate is not a law.** A helper call is refused however
    /// inviting: the emitted test cannot be assumed to reach `isValidValue`.
    @Test func aFreeIdentifierIsRefused() {
        #expect(read("""
        func f(_ value: String) -> String {
            guard isValidValue(value) else { return value }
            return value.uppercased()
        }
        """) == nil)
    }

    /// Instance state is the same refusal for the same reason — the condition is true of the
    /// object, not of the argument, so no generated value can state it.
    @Test func instanceStateIsRefused() {
        #expect(read("""
        func f(_ value: String) -> Bool {
            guard searchQuery.isEmpty else { return true }
            return false
        }
        """) == nil)
    }

    /// Members of the parameter are free to appear — `value.isEmpty` has one free identifier.
    @Test func membersOfTheParameterAreFine() throws {
        let domain = try #require(read("""
        func f(_ graph: Graph) -> Graph {
            guard !graph.nodes.isEmpty else { return graph }
            return graph.laidOut()
        }
        """))
        #expect(domain.condition == "!graph.nodes.isEmpty")
        #expect(domain.returnedExpression == "graph")
    }

    /// Multi-parameter is out of scope: the law is about one axis of a product and the emitter
    /// would have to generate the others.
    @Test func multipleParametersAreRefused() {
        #expect(read("""
        func f(_ value: String, _ width: Int) -> String {
            guard value.count < width else { return value }
            return value.padding(toLength: width, withPad: " ", startingAt: 0)
        }
        """) == nil)
    }

    /// An `if` with an `else` is a branch, not an early return.
    @Test func anIfElseIsNotAnEarlyReturn() {
        #expect(read("""
        func f(_ value: String) -> String {
            if value.isEmpty { return "" } else { return value }
        }
        """) == nil)
    }

    final class Finder: SyntaxVisitor {
        var found: FunctionDeclSyntax?

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            if found == nil { found = node }
            return .visitChildren
        }
    }
}
