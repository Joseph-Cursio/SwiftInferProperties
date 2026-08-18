import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **`verdict(forGetter:)` analyses the getter, not every accessor beside it.**
///
/// Open item 50's second half. `ReducerPurityAnalyzer` walks whatever syntax it is handed,
/// so passing the whole `AccessorBlockSyntax` let it read a `_read` or `unsafeAddress`
/// body it was never asked about — a true statement about the *property* and a false one
/// about its *getter*.
///
/// ## The narrowing is inert today, and that is measured rather than assumed
///
/// `PurityInferrer.isPure(_ accessor:)` returns `false` on the **presence** of any
/// non-`get` accessor; it never reads that accessor's body. So the meet stays `.refuted`
/// whatever `ReducerPurityAnalyzer` says, and no verdict moves. The narrowing matters only
/// if SEI relaxes that rule — which is a decision in another repository, so the reopen
/// condition is pinned here rather than left implicit.
///
/// Kept on item 40's precedent: an oracle pointed at the right node, closing a latent
/// misreading at zero measured cost.
@Suite("SoundPurity — the getter verdict reads the getter")
struct GetterOnlyVerdictTests {

    static func block(_ source: String) throws -> AccessorBlockSyntax {
        final class Finder: SyntaxVisitor {
            var found: AccessorBlockSyntax?

            override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
                if found == nil { found = node }
                return .skipChildren
            }
        }
        let finder = Finder(viewMode: .sourceAccurate)
        finder.walk(Parser.parse(source: source))
        return try #require(finder.found, "no accessor block parsed")
    }

    /// A pure getter beside a `_read` that writes static state.
    static let mixed = """
    struct S {
        static var cache = 0
        var projection: Int {
            get { 1 }
            _read { S.cache = 9; yield 1 }
        }
    }
    """

    /// **The narrowing, observed directly.** Before it, the analyzer answered
    /// `hiddenMutability` on this block — a fact about the `_read` body.
    @Test("the reducer analyzer no longer sees a sibling accessor's body")
    func theAnalyzerSeesOnlyTheGetter() throws {
        let block = try Self.block(Self.mixed)
        #expect(ReducerPurityAnalyzer.analyze(SoundPurity.getterOnly(of: block)) == .pure, """
        The getter's own statements are `1`. A non-pure answer means the narrowing is \
        still handing the analyzer a sibling accessor.
        """)
        #expect(ReducerPurityAnalyzer.analyze(Syntax(block)) != .pure, """
        The whole block no longer reads as impure, so this test has stopped demonstrating \
        the difference it exists to demonstrate — pick a sharper fixture.
        """)
    }

    /// **The inertness, pinned.** If this flips, SEI has relaxed its accessor rule and the
    /// narrowing above starts moving verdicts — at which point
    /// `docs/measurements/modify-accessor-misclassification.md` needs re-reading before
    /// anything is built on it.
    @Test("the narrowing is inert while SEI refuses any non-get accessor")
    func narrowingIsInertWhileSEIRefusesNonGetAccessors() throws {
        let block = try Self.block(Self.mixed)

        #expect(PurityInferrer().isPure(block) == false, """
        SEI's accessor oracle now admits a block containing a non-`get` accessor. The \
        narrowing in `verdict(forGetter:)` stops being inert the moment that happens.
        """)
        #expect(SoundPurity.verdict(forGetter: block) == .refuted, """
        The verdict moved. That is the outcome the inertness claim rules out, so re-take \
        the A/B before trusting item 50's "no population" close.
        """)
    }

    /// The shorthand form has no siblings to exclude; narrowing must not change it.
    @Test("an implicit getter is unaffected")
    func implicitGetterIsUnchanged() throws {
        let block = try Self.block("struct S { var projection: Int { 1 } }")
        #expect(SoundPurity.verdict(forGetter: block) == .pure)
    }

    /// The impurity that IS the getter's own must still refute — the narrowing must not
    /// have made the oracle blind rather than precise.
    @Test("an impure getter still refutes")
    func impureGetterStillRefutes() throws {
        let block = try Self.block("""
        struct S {
            static var cache = 0
            var projection: Int { get { S.cache = 9; return 1 } }
        }
        """)
        #expect(SoundPurity.verdict(forGetter: block) == .refuted, """
        A getter writing static state read as pure. The narrowing has made the oracle \
        blind rather than precise, which is worse than the misreading it replaced.
        """)
    }
}
