import Foundation
import Testing

@testable import SwiftInferCore

/// Tier 1 of speculative refactoring: the patch itself.
///
/// The law-running half is measured elsewhere; this pins the part that must be
/// exactly right before a diff is put in front of anyone, because a wrong patch is
/// worse than no patch — it fails verification for a reason unrelated to the law
/// and reads as the law being false.
@Suite("SpeculativeWidening — the patch")
struct SpeculativeWideningTests {

    private func summary(line: Int, file: String = "F.swift") -> FunctionSummary {
        FunctionSummary(
            name: "normalize",
            parameters: [],
            returnTypeText: "String",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    // MARK: - Which restrictions are candidates

    /// The narrowness is the design, not an oversight. Widening a member nested in
    /// a private type is a **no-op** — the patch would unblock nothing and then
    /// fail verification for a reason that has nothing to do with the law.
    ///
    /// **`.enclosingTypeNotVisibleToTests` is the row that was missing**, and the
    /// gap was invisible from here because this suite and `SpeculativeWidening`'s
    /// doc both *described* the private-enclosing-type trap while asserting
    /// `.nestedLocal`, a different shape. Nothing ever produced the case being
    /// described, so the assertion passed green over an unguarded trap. Asserting a
    /// classification the scanner cannot emit is the same defect as a coverage
    /// claim about a law the kit does not ship — hence `scannerClassifies…` below,
    /// which drives the real scanner rather than hand-building the enum.
    @Test("only notVisibleToTests is widenable")
    func onlyNotVisibleToTestsIsWidenable() {
        #expect(SpeculativeWidening.isWidenable(.notVisibleToTests))
        #expect(!SpeculativeWidening.isWidenable(.nestedLocal))
        #expect(!SpeculativeWidening.isWidenable(.internalOrSPI))
        #expect(!SpeculativeWidening.isWidenable(.enclosingTypeNotVisibleToTests))
    }

    /// End to end: real source in, no candidate out.
    ///
    /// The unit assertion above can only say the classification is not widenable. This says the
    /// **scanner produces that classification** for the shape in question — which is the half that
    /// was actually broken, and the half a hand-built `RestrictedFunction` cannot reach.
    @Test("a private member of a private type yields no widening candidate")
    func privateMemberOfPrivateTypeIsNotACandidate() {
        let source = """
        private struct Helper {
            private func trim(_ text: String) -> String { text }
        }
        public struct Exposed {
            private func trim(_ text: String) -> String { text }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "F.swift")
        let candidates = SpeculativeWidening.candidates(
            from: corpus.restricted,
            in: ["F.swift": source]
        )

        // Exactly one: the member of the public type. Widening it genuinely exposes something.
        #expect(candidates.count == 1)
        #expect(candidates.first?.line == 5)
        #expect(candidates.first?.modifier == "private")
    }

    // MARK: - Finding the modifier

    @Test("finds private and fileprivate on the declaration line")
    func findsModifiers() {
        #expect(SpeculativeWidening.leadingAccessModifier(in: "    private func f() {") == "private")
        #expect(
            SpeculativeWidening.leadingAccessModifier(in: "fileprivate static func f() {")
                == "fileprivate"
        )
        #expect(SpeculativeWidening.leadingAccessModifier(in: "    func f() {") == nil)
    }

    /// Word-boundary matching, not `contains`. A function named `privateKeyFor`
    /// must not read as a `private` declaration — and that is a real shape in any
    /// crypto-adjacent codebase, not a contrived one.
    @Test("a name containing the modifier is not mistaken for the modifier")
    func nameContainingModifierIsNotMatched() {
        #expect(SpeculativeWidening.leadingAccessModifier(in: "    func privateKeyFor() {") == nil)
        #expect(SpeculativeWidening.leadingAccessModifier(in: "    func fileprivateish() {") == nil)
    }

    // MARK: - Applying it

    @Test("widening deletes the modifier and leaves everything else alone")
    func wideningPreservesTheRestOfTheLine() {
        let source = """
        struct S {
            private static func normalize(_ text: String) -> String { text }
        }
        """
        let candidate = SpeculativeWidening.Candidate(
            summary: summary(line: 2), modifier: "private", line: 2
        )
        let widened = SpeculativeWidening.widened(source: source, candidate: candidate)
        #expect(widened?.contains("    static func normalize") == true)
        #expect(widened?.contains("private") == false)
        // Indentation and the other modifier survive — `staticfunc` would compile
        // to nothing and read as the tool being broken.
        #expect(widened?.contains("staticfunc") == false)
    }

    /// The guard against a stale candidate. If the file moved underneath the run,
    /// the modifier is no longer on that line and the patch must refuse rather
    /// than mangle whatever is there now.
    @Test("a candidate whose line no longer carries the modifier is refused")
    func staleCandidateIsRefused() {
        let source = """
        struct S {
            static func normalize(_ text: String) -> String { text }
        }
        """
        let candidate = SpeculativeWidening.Candidate(
            summary: summary(line: 2), modifier: "private", line: 2
        )
        #expect(SpeculativeWidening.widened(source: source, candidate: candidate) == nil)
    }

    @Test("a line beyond the end of the file is refused")
    func outOfRangeLineIsRefused() {
        let candidate = SpeculativeWidening.Candidate(
            summary: summary(line: 99), modifier: "private", line: 99
        )
        #expect(SpeculativeWidening.widened(source: "let x = 1", candidate: candidate) == nil)
    }

    // MARK: - The diff

    /// Prose would not transfer: the reader would write a different edit from the
    /// one that was compiled, and the verdict would be about code nobody has.
    @Test("the diff names the file and shows exactly the changed line")
    func diffShowsTheChangedLine() {
        let original = "struct S {\n    private func f() {}\n}"
        let widened = "struct S {\n    func f() {}\n}"
        let diff = SpeculativeWidening.unifiedDiff(
            path: "Sources/S.swift", original: original, widened: widened, line: 2
        )
        #expect(diff.contains("--- a/Sources/S.swift"))
        #expect(diff.contains("+++ b/Sources/S.swift"))
        #expect(diff.contains("-    private func f() {}"))
        #expect(diff.contains("+    func f() {}"))
    }

    // MARK: - Candidate selection end to end

    @Test("candidates are filtered by restriction and ordered by file then line")
    func candidatesAreFilteredAndOrdered() {
        let sources = [
            "B.swift": "private func b() {}",
            "A.swift": "private func a() {}\nprivate func a2() {}"
        ]
        let restricted = [
            RestrictedFunction(summary: summary(line: 1, file: "B.swift"), restriction: .notVisibleToTests),
            RestrictedFunction(summary: summary(line: 2, file: "A.swift"), restriction: .notVisibleToTests),
            RestrictedFunction(summary: summary(line: 1, file: "A.swift"), restriction: .notVisibleToTests),
            // Excluded: widening a nested local is a no-op.
            RestrictedFunction(summary: summary(line: 1, file: "C.swift"), restriction: .nestedLocal)
        ]
        let candidates = SpeculativeWidening.candidates(from: restricted, in: sources)
        #expect(candidates.count == 3)
        #expect(candidates.map(\.summary.location.file) == ["A.swift", "A.swift", "B.swift"])
        #expect(candidates.map(\.line) == [1, 2, 1])
    }
}
