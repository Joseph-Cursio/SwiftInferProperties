import Foundation
import Testing

@testable import SwiftInferCore

/// Why the scanner sets a function aside — the *reason*, not the fact.
///
/// Every shape here lands in `restricted` with a reason (and, since 2026-08-07, also surfaces into
/// `summaries` — privacy no longer gates discovery). The reason is not decoration:
/// `SpeculativeWidening` filters on it to decide whether to spend a package snapshot proposing a
/// patch, and `AccessRestriction.remedy` is what the reader is told to do. A wrong reason buys a
/// no-op patch and false advice, so this suite pins the reason for each shape independently of the
/// visibility change.
@Suite("FunctionScanner — why a function is set aside")
struct AccessRestrictionScannerTests {

    private func restriction(of name: String, in source: String) -> AccessRestriction? {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "F.swift")
        return corpus.restricted.first { $0.summary.name == name }?.restriction
    }

    // MARK: - The defect

    /// The declaration's own `private` used to win, and it is the one **widenable** answer.
    ///
    /// Deleting `private` from `trim` compiles and exposes nothing, because `Helper` is what blocks
    /// it. The binding constraint has to be the reported one.
    @Test("a private member of a private type reports the enclosing type, not its own modifier")
    func privateMemberOfPrivateType() {
        let source = """
        private struct Helper {
            private func trim(_ text: String) -> String { text }
        }
        """
        #expect(restriction(of: "trim", in: source) == .enclosingTypeNotVisibleToTests)
    }

    /// Same for a member carrying no modifier at all.
    ///
    /// This one was already non-widenable — it classified as `.internalOrSPI` — so no patch was
    /// ever emitted for it. The **advice** was still wrong, and specifically wrong in the confident
    /// direction: `.internalOrSPI.remedy` says *"a same-package test target using `@testable
    /// import` can [call it]"*, which is false. `@testable` raises `internal` and stops there; it
    /// does not reach into a `private` type.
    @Test("an unmarked member of a private type is not internal-or-SPI")
    func unmarkedMemberOfPrivateType() {
        let source = """
        fileprivate enum Helper {
            static func trim(_ text: String) -> String { text }
        }
        """
        #expect(restriction(of: "trim", in: source) == .enclosingTypeNotVisibleToTests)
    }

    /// `SpeculativeWidening.candidates` filters `RestrictedFunction` on the restriction alone and
    /// never asks whether the summary came from a `func` or a computed property, so the property
    /// arm is the same no-op patch by a second route.
    @Test("a private computed property inside a private type reports the enclosing type")
    func privateComputedPropertyOfPrivateType() {
        let source = """
        private struct Helper {
            private var trimmed: String { "" }
        }
        """
        #expect(restriction(of: "trimmed", in: source) == .enclosingTypeNotVisibleToTests)
    }

    /// A `private extension` makes its members fileprivate, so the same rule applies to the
    /// extension arm of the enclosing-type stack.
    @Test("a member of a private extension reports the enclosing type")
    func memberOfPrivateExtension() {
        let source = """
        private extension String {
            func trim() -> String { self }
        }
        """
        #expect(restriction(of: "trim", in: source) == .enclosingTypeNotVisibleToTests)
    }

    // MARK: - Controls, so the fix cannot be a blanket demotion

    /// The case widening is *for*. If this moved, the fix would have bought correctness by
    /// switching the feature off, which is the failure mode `restricted-function` already had once
    /// on the seed side (319 seeds suppressed by answering the verification question with the
    /// analysis flag).
    @Test("a private member of a public type still reports its own modifier")
    func privateMemberOfPublicType() {
        let source = """
        public struct Exposed {
            private func trim(_ text: String) -> String { text }
        }
        """
        #expect(restriction(of: "trim", in: source) == .notVisibleToTests)
        #expect(SpeculativeWidening.isWidenable(.notVisibleToTests))
    }

    /// A top-level private function has no enclosing type at all.
    @Test("a top-level private function still reports its own modifier")
    func topLevelPrivateFunction() {
        let source = "private func trim(_ text: String) -> String { text }"
        #expect(restriction(of: "trim", in: source) == .notVisibleToTests)
    }

    /// An **unmarked** type stays public-eligible — Lever A's "the modifier, not the absence, is
    /// the signal" rule. An internal-by-default type must not start suppressing its members.
    @Test("an unmarked enclosing type does not restrict a public member")
    func unmarkedEnclosingType() {
        let source = """
        struct Plain {
            public func trim(_ text: String) -> String { text }
        }
        """
        #expect(restriction(of: "trim", in: source) == nil)
    }

    /// Explicit `internal` on the enclosing type keeps its members `.internalOrSPI`, whose remedy
    /// (`@testable import` reaches it) is true for that case and only that case.
    @Test("an explicitly internal enclosing type still reports internal-or-SPI")
    func explicitlyInternalEnclosingType() {
        let source = """
        internal struct Plain {
            public func trim(_ text: String) -> String { text }
        }
        """
        #expect(restriction(of: "trim", in: source) == .internalOrSPI)
    }

    /// Nesting: the outer type is what blocks, and `contains` has to see through an unmarked inner
    /// one. Swift caps a nested type's access at its parent's, so `Inner` is unreachable too.
    @Test("a private outer type restricts a member of an unmarked inner type")
    func privateOuterTypeWithUnmarkedInner() {
        let source = """
        private enum Outer {
            struct Inner {
                public func trim(_ text: String) -> String { text }
            }
        }
        """
        #expect(restriction(of: "trim", in: source) == .enclosingTypeNotVisibleToTests)
    }

    /// The stack must pop. A second, unrelated type declared after a private one must not inherit
    /// its restriction — the failure mode of any push/pop pairing, and the reason the two questions
    /// share one stack rather than two.
    @Test("the enclosing-type stack pops")
    func stackPops() {
        let source = """
        private struct Helper {
            private func trim(_ text: String) -> String { text }
        }
        public struct Exposed {
            private func clean(_ text: String) -> String { text }
        }
        """
        #expect(restriction(of: "trim", in: source) == .enclosingTypeNotVisibleToTests)
        #expect(restriction(of: "clean", in: source) == .notVisibleToTests)
    }

    // MARK: - Every set-aside function is also surfaced

    /// **The reason is still recorded; the function is no longer withheld.** Every shape here is
    /// classified in `restricted` (that reason becomes its caveat) AND now also reaches `summaries`
    /// so a template can propose its law. The classification the rest of this suite pins is exactly
    /// what survives — it just no longer decides visibility, only which remedy the caveat leads with.
    @Test("every shape is classified in `restricted` and also surfaces in `summaries`")
    func restrictedShapesAlsoSurface() {
        let source = """
        private struct Helper {
            private func a(_ text: String) -> String { text }
            static func b(_ text: String) -> String { text }
        }
        private extension String {
            func c() -> String { self }
        }
        internal struct Plain {
            public func d(_ text: String) -> String { text }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "F.swift")
        let restrictedNames = Set(corpus.restricted.map(\.summary.name))
        #expect(restrictedNames == ["a", "b", "c", "d"])
        // The same four now appear in discovery, each carrying its restriction downstream.
        #expect(restrictedNames.isSubset(of: Set(corpus.summaries.map(\.name))))
    }
}
