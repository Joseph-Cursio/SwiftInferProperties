import Foundation
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

    /// The shape the corpus is made of: a test helper that binds the argument, then constructs.
    /// Two helpers bind the same name `pattern` to different expressions, so a resolution that
    /// ignored scope would answer one of them with the other's.
    private static let helpers = """
    private func makeVisitor() -> TooManyEnvironmentObjectsVisitor {
        let pattern = TooManyEnvironmentObjects().pattern
        return TooManyEnvironmentObjectsVisitor(pattern: pattern)
    }

    private func makeChained() -> UIVisitor {
        let category = PatternCategory.uiPatterns
        let pattern = SyntaxPattern(category: category)
        return UIVisitor(pattern: pattern)
    }

    private func makeRooted() -> ActorReentrancyVisitor {
        let rule = ActorReentrancy()
        return ActorReentrancyVisitor(pattern: rule.pattern)
    }

    private func makeUnresolved() -> MysteryVisitor {
        let pattern = makePattern()
        return MysteryVisitor(pattern: pattern)
    }

    private func makeShadowed() -> [ShadowVisitor] {
        let pattern = Shadow().pattern
        _ = pattern
        return categories.map { pattern in ShadowVisitor(pattern: pattern) }
    }

    private func makeParameterised(pattern: SyntaxPattern) -> ParameterVisitor {
        return ParameterVisitor(pattern: pattern)
    }

    private func makeRankedEarly() -> RankedVisitor {
        let pattern = Recovered().pattern
        return RankedVisitor(pattern: pattern)
    }

    private func makeRankedLate() -> RankedVisitor {
        return RankedVisitor(pattern: Verbatim().pattern)
    }
    """

    /// Through `harvest`, not through `constructions` — the ranking these tests are about lives
    /// in `harvest`, and a mirror of it here would be free to drift from the one that ships.
    private static func resolved(_ wanted: Set<String>) -> [String: String] {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("receiver-constructions-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try? helpers.write(to: directory.appendingPathComponent("Helpers.swift"), atomically: true, encoding: .utf8)
        return ReceiverConstructionHarvester.harvest(roots: [directory], wanted: wanted)
    }

    private static func constructions(_ wanted: Set<String>) -> [String: String] {
        map(ReceiverConstructionHarvester.constructions(in: source, wanted: wanted))
    }

    /// `harvest`'s ranking, over one file: a verbatim construction beats a recovered one, and
    /// within each kind the first in source order wins.
    private static func map(
        _ found: [ReceiverConstructionHarvester.Construction]
    ) -> [String: String] {
        var verbatim: [String: String] = [:]
        var inlined: [String: String] = [:]
        for construction in found {
            if construction.substituted {
                if inlined[construction.type] == nil { inlined[construction.type] = construction.expression }
            } else if verbatim[construction.type] == nil {
                verbatim[construction.type] = construction.expression
            }
        }
        return inlined.merging(verbatim) { _, written in written }
    }

    @Test("a construction of only literals, enum cases and types is kept")
    func selfContained() {
        let found = Self.constructions(["LawOfDemeterVisitor", "RetroactiveConformanceVisitor", "Budget"])
        #expect(found["LawOfDemeterVisitor"] == "LawOfDemeterVisitor(patternCategory: .architecture)")
        #expect(found["RetroactiveConformanceVisitor"]
            == "RetroactiveConformanceVisitor(pattern: RetroactiveConformance().pattern)")
        #expect(found["Budget"] == #"Budget(limit: 10, name: "x")"#)
    }

    /// ⚠ **A local is only as good as what it is bound to.** Copying `Visitor(pattern: pattern)`
    /// emits `cannot find 'pattern' in scope`, and here the binding — `makePattern()` — is no
    /// more callable from a generated file, so the whole construction is still refused.
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

    /// The shape `localsRefused` pins, once the binding beside it is read.
    @Test("a test-local is replaced by the expression it is bound to")
    func localInlined() {
        #expect(Self.resolved(["TooManyEnvironmentObjectsVisitor"])["TooManyEnvironmentObjectsVisitor"]
            == "TooManyEnvironmentObjectsVisitor(pattern: TooManyEnvironmentObjects().pattern)")
    }

    /// ⚠ **One pass is not enough**: substituting `pattern` inserts `category`, which is another
    /// local, and the inserted subtree is not re-visited by the pass that inserted it.
    @Test("a local bound to another local resolves to a fixed point")
    func chainedBindingsInlined() {
        #expect(Self.resolved(["UIVisitor"])["UIVisitor"]
            == "UIVisitor(pattern: SyntaxPattern(category: PatternCategory.uiPatterns))")
    }

    /// The base of `rule.pattern` is a local and the member is not — rewriting both would ask a
    /// type for a member named after whatever the test happened to call its variable.
    @Test("a local at the root of a member chain is replaced, and the member is not")
    func memberChainRootInlined() {
        #expect(Self.resolved(["ActorReentrancyVisitor"])["ActorReentrancyVisitor"]
            == "ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)")
    }

    /// Substitution moves the question rather than answering it: `makePattern()` is no more
    /// callable from a generated file than `pattern` was.
    @Test("a local whose own binding does not resolve is still refused")
    func unresolvableBindingRefused() {
        #expect(Self.resolved(["MysteryVisitor"]).isEmpty)
    }

    /// ⚠ **The shadow is what inlining newly makes dangerous.** `{ pattern in … }` means the
    /// closure's own `pattern`, and answering it with the outer `let` a few lines up would copy a
    /// construction the test never wrote.
    @Test("a name an enclosing closure parameter binds is not resolved to an outer let")
    func closureParameterNotInlined() {
        #expect(Self.resolved(["ShadowVisitor"]).isEmpty)
    }

    /// A parameter resolves nowhere in a generated file, whether or not a `let` shares its name.
    @Test("a name bound by the enclosing function's parameter is refused")
    func functionParameterRefused() {
        #expect(Self.resolved(["ParameterVisitor"]).isEmpty)
    }

    /// ⚠ **The regression this ranking exists for, measured**: following a local makes EARLIER
    /// sites eligible, so first-in-source-order handed a type a recovered expression in place of
    /// the verbatim one it already had, and a stub that compiled stopped compiling.
    @Test("a verbatim construction outranks a recovered one written later")
    func verbatimOutranksRecovered() {
        #expect(Self.resolved(["RankedVisitor"])["RankedVisitor"] == "RankedVisitor(pattern: Verbatim().pattern)")
    }

    @Test("only the wanted types are collected")
    func onlyWanted() {
        #expect(Self.constructions(["Budget"]).keys.sorted() == ["Budget"])
    }

    /// A test that declares its own `Collector` constructs THAT type, which shares only a name
    /// with the production one — 11 census stubs were handed its initializer.
    @Test("a type the test file declares itself is not harvested")
    func testLocalTypeIsNotHarvested() {
        let source = """
        final class Collector: SyntaxVisitor {}
        @Test func walks() {
            let collector = Collector(viewMode: .sourceAccurate)
            let visitor = LawOfDemeterVisitor(patternCategory: .architecture)
            _ = (collector, visitor)
        }
        """
        let found = ReceiverConstructionHarvester.constructions(
            in: source, wanted: ["Collector", "LawOfDemeterVisitor"]
        )
        #expect(found.map(\.type) == ["LawOfDemeterVisitor"])
    }
}
