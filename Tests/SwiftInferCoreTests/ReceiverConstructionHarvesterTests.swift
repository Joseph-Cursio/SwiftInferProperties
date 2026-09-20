@testable import SwiftInferCore
import Testing

/// How a package's tests construct a class the tool cannot derive.
@Suite("Receiver constructions — copied from the tests, never derived")
struct ReceiverConstructionHarvesterTests {

    private static let source = """
    @Test func lawOfDemeter() {
        let visitor = LawOfDemeterVisitor(patternCategory: .architecture)
        let other = RetroactiveConformanceVisitor(pattern: RetroactiveConformance().pattern)
        let pattern = makePattern()
        let local = TooManyEnvironmentObjectsVisitor(pattern: pattern)
        let chained = ChainedVisitor(pattern: pattern.category)
        let literal = Budget(limit: 10, name: "x")
        let closure = WalkingVisitor(viewMode: .sourceAccurate) { $0 }
        _ = (visitor, other, local, chained, literal, closure)
    }
    """

    private static func constructions(_ wanted: Set<String>) -> [String: String] {
        Dictionary(ReceiverConstructionHarvester.constructions(in: source, wanted: wanted)) { first, _ in
            first
        }
    }

    @Test("a construction of only literals, enum cases and types is kept")
    func selfContained() {
        let found = Self.constructions(["LawOfDemeterVisitor", "RetroactiveConformanceVisitor", "Budget"])
        #expect(found["LawOfDemeterVisitor"] == "LawOfDemeterVisitor(patternCategory: .architecture)")
        #expect(found["RetroactiveConformanceVisitor"]
            == "RetroactiveConformanceVisitor(pattern: RetroactiveConformance().pattern)")
        #expect(found["Budget"] == #"Budget(limit: 10, name: "x")"#)
    }

    /// ⚠ **The common shape, and it must be refused.** `Visitor(pattern: pattern)` names a local
    /// the generated file has no binding for; copying it emits `cannot find 'pattern' in scope`.
    @Test("a construction naming a test-local is refused")
    func localsRefused() {
        #expect(Self.constructions(["TooManyEnvironmentObjectsVisitor"]).isEmpty)
    }

    /// ⚠ **Both halves of `pattern.category` hang off one `MemberAccessExprSyntax`**, so a check
    /// asking only whether the parent is one waved the BASE through as if it were the member of
    /// `Rule().pattern`.
    @Test("a member chain rooted at a test-local is refused")
    func localRootedChainRefused() {
        #expect(Self.constructions(["ChainedVisitor"]).isEmpty)
    }

    /// A trailing closure is a body the tool would be inventing semantics for.
    @Test("a construction taking a closure is refused")
    func closuresRefused() {
        #expect(Self.constructions(["WalkingVisitor"]).isEmpty)
    }

    @Test("only the wanted types are collected")
    func onlyWanted() {
        #expect(Self.constructions(["Budget"]).keys.sorted() == ["Budget"])
    }
}
