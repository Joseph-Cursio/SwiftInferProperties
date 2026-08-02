@testable import SwiftInferCore
import Testing

/// `scaffold-kit-suites` wrote `Deque.self` and `PersistentSet.self` into generated suites.
/// Neither typechecks — `generic parameter 'Element' could not be inferred` — so no generic
/// carrier could produce a compiling suite whether or not a generator existed. Measured on
/// swift-collections `899809d3` and on the 2022 `876177db^` tree; see
/// `docs/kit-suite-backtest-plan.md` §3b and §Arm 1.
struct ConcreteInstantiationTests {

    private func parameter(_ name: String, _ constraint: String?) -> TypeDecl.GenericParameter {
        TypeDecl.GenericParameter(name: name, constraint: constraint)
    }

    @Test("a non-generic carrier is returned unchanged")
    func concreteCarrierPassesThrough() {
        #expect(ConcreteInstantiation.rendered(typeName: "Plain", genericParameters: []) == "Plain")
        #expect(ConcreteInstantiation.declineReason(typeName: "Plain", genericParameters: []) == nil)
    }

    @Test("one constrained parameter instantiates to Int")
    func singleParameter() {
        let rendered = ConcreteInstantiation.rendered(
            typeName: "Deque", genericParameters: [parameter("Element", "Hashable")]
        )
        #expect(rendered == "Deque<Int>")
    }

    @Test("an unconstrained parameter is always satisfiable")
    func unconstrainedParameter() {
        let rendered = ConcreteInstantiation.rendered(
            typeName: "Boxy", genericParameters: [parameter("T", nil)]
        )
        #expect(rendered == "Boxy<Int>")
    }

    @Test("arity is preserved — a two-parameter carrier gets two arguments")
    func twoParameters() {
        let rendered = ConcreteInstantiation.rendered(
            typeName: "OrderedDictionary",
            genericParameters: [parameter("Key", "Hashable"), parameter("Value", nil)]
        )
        #expect(rendered == "OrderedDictionary<Int, Int>")
    }

    @Test("a composed constraint is satisfied only if EVERY side is")
    func composedConstraint() {
        #expect(ConcreteInstantiation.rendered(
            typeName: "Both", genericParameters: [parameter("T", "Hashable & Codable")]
        ) == "Both<Int>")
        #expect(ConcreteInstantiation.rendered(
            typeName: "Mixed", genericParameters: [parameter("T", "Hashable & Collection")]
        ) == nil)
    }

    /// **It declines rather than guessing, and this is the load-bearing test.** Emitting
    /// `Nested<Int>` for `Nested<T: Collection>` would trade one compile error for another
    /// while looking like progress — the conservative-inference posture applied to codegen.
    @Test("a constraint Int does not satisfy declines, and the reason names it")
    func declinesUnsatisfiableConstraint() throws {
        let generics = [parameter("T", "Collection")]
        #expect(ConcreteInstantiation.rendered(typeName: "Nested", genericParameters: generics) == nil)
        let reason = try #require(
            ConcreteInstantiation.declineReason(typeName: "Nested", genericParameters: generics)
        )
        #expect(reason.contains("T: Collection"))
        #expect(reason.contains("Nested"))
    }

    /// The allowlist is closed on purpose: "anything unrecognised is fine" would emit code
    /// that does not compile, which is the defect this type exists to remove.
    @Test("an unrecognised user protocol declines rather than being assumed satisfiable")
    func unknownProtocolDeclines() {
        #expect(ConcreteInstantiation.rendered(
            typeName: "Custom", genericParameters: [parameter("T", "MyProjectProtocol")]
        ) == nil)
    }

    /// `Int` really does conform to every protocol in the allowlist. Pinned because the set
    /// is hand-written, and a wrong entry there produces emitted code that does not compile —
    /// silently, on somebody else's corpus.
    ///
    /// **It earned itself on the first run.** The allowlist's first draft included
    /// `CustomDebugStringConvertible`; `Int` does not conform, and this test caught it before
    /// the entry could reach a generated suite.
    @Test("every allowlisted constraint is one Int actually satisfies")
    func allowlistIsTrue() {
        let int: Any.Type = Int.self
        #expect(int is any Equatable.Type)
        #expect(int is any Hashable.Type)
        #expect(int is any Comparable.Type)
        #expect(int is any Codable.Type)
        #expect(int is any Sendable.Type)
        #expect(int is any AdditiveArithmetic.Type)
        #expect(int is any Numeric.Type)
        #expect(int is any SignedNumeric.Type)
        #expect(int is any BinaryInteger.Type)
        #expect(int is any FixedWidthInteger.Type)
        #expect(int is any SignedInteger.Type)
        #expect(int is any Strideable.Type)
        #expect(int is any CustomStringConvertible.Type)
        #expect(int is any LosslessStringConvertible.Type)
        #expect(int is any ExpressibleByIntegerLiteral.Type)
    }
}
