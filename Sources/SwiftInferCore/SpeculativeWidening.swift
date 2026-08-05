import Foundation

/// Access widening as a **proposable patch** rather than advice — tier 1 of the
/// speculative-refactoring design.
///
/// The tool copies the tree, removes one access modifier, derives the laws that
/// become visible, verifies them, and surfaces the refactor **only if a law ran**.
/// Output stops being *"extract this"* and becomes *a patch, a law, and a verdict*.
///
/// ## Why access widening is tier 1, and what that buys
///
/// The design ranks the tiers by **how much the patch needs proving**, not by how
/// valuable the law is:
///
/// | tier | what makes the PATCH safe | what the law proves |
/// |---|---|---|
/// | access widening | the **compiler** — visibility cannot alter behaviour | the law holds |
/// | kernel extraction | **nothing yet** — extraction may not preserve behaviour | it holds *of that extraction* |
///
/// Extraction ambiguity here is **zero**: same symbol, same body, one keyword. So a
/// verdict on the copy is a verdict on the reader's code, which is exactly what the
/// later tiers cannot claim without differential testing.
///
/// ## Only one restriction is a candidate
///
/// `.nestedLocal` is excluded deliberately, and it is the design's named trap:
/// widening a member nested inside a private type is a **no-op**, so the patch
/// would unblock nothing and then fail verification for a reason unrelated to the
/// law. `.internalOrSPI` is excluded because a same-package test target with
/// `@testable import` already reaches it — there is nothing to unblock.
///
/// That distinction is why `AccessRestriction` carries a *reason* rather than a
/// single "restricted" kind: the remedies differ, and a generator that ignored the
/// difference would emit patches that cannot work.
///
/// ## The measured yield, stated up front
///
/// Re-measured 2026-08-04 over 20 widened functions: 6 gained a proposed law,
/// **3 ran, 1 held, 2 were refuted as false laws**. So this surfaces roughly one
/// durable regression guard per twenty widenings, and the two refutations are
/// `idempotence` firing on a `T -> T` shape that is not idempotent — noise at
/// `Possible`, not bugs. Build cost is one SwiftPM workdir per candidate, which is
/// why the command is opt-in and candidate-capped.
public enum SpeculativeWidening {

    /// A function whose access can be widened, with the patch that does it.
    public struct Candidate: Sendable, Equatable {
        public let summary: FunctionSummary
        /// The modifier to delete — `private` or `fileprivate`.
        public let modifier: String
        /// 1-based line the modifier sits on, as recorded by the scanner.
        public let line: Int

        public init(summary: FunctionSummary, modifier: String, line: Int) {
            self.summary = summary
            self.modifier = modifier
            self.line = line
        }
    }

    /// The restrictions widening can actually fix.
    ///
    /// Exactly one case, and the narrowness is the point — see the type doc for why
    /// `.nestedLocal` and `.internalOrSPI` are not candidates.
    public static func isWidenable(_ restriction: AccessRestriction) -> Bool {
        restriction == .notVisibleToTests
    }

    /// Candidates from a scan's set-aside functions, in file order so a run is
    /// reproducible and `--max-candidates` takes a stable prefix rather than
    /// whatever the scan happened to yield first.
    public static func candidates(
        from restricted: [RestrictedFunction],
        in sourcesByFile: [String: String]
    ) -> [Candidate] {
        restricted
            .filter { isWidenable($0.restriction) }
            .sorted {
                ($0.summary.location.file, $0.summary.location.line)
                    < ($1.summary.location.file, $1.summary.location.line)
            }
            .compactMap { candidate(for: $0.summary, source: sourcesByFile[$0.summary.location.file]) }
    }

    static func candidate(for summary: FunctionSummary, source: String?) -> Candidate? {
        guard let source else { return nil }
        let lines = source.components(separatedBy: "\n")
        let index = summary.location.line - 1
        guard lines.indices.contains(index) else { return nil }
        guard let modifier = leadingAccessModifier(in: lines[index]) else { return nil }
        return Candidate(summary: summary, modifier: modifier, line: summary.location.line)
    }

    /// The access modifier a widening would delete, or `nil` when the declaration
    /// line carries none.
    ///
    /// Word-boundary matched rather than `contains`: a function named
    /// `privateKeyFor(_:)` must not read as a `private` declaration, and that is a
    /// live shape in any crypto-adjacent codebase.
    static func leadingAccessModifier(in line: String) -> String? {
        for modifier in ["private", "fileprivate"] where containsWord(modifier, in: line) {
            return modifier
        }
        return nil
    }

    private static func containsWord(_ word: String, in line: String) -> Bool {
        var searchStart = line.startIndex
        while let range = line.range(of: word, range: searchStart..<line.endIndex) {
            let beforeOK = range.lowerBound == line.startIndex
                || !isIdentifierCharacter(line[line.index(before: range.lowerBound)])
            let afterOK = range.upperBound == line.endIndex
                || !isIdentifierCharacter(line[range.upperBound])
            if beforeOK, afterOK { return true }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isIdentifierCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_"
    }

    /// Apply the widening to `source`, returning the mutated text.
    ///
    /// Deletes the modifier and the single space after it, leaving indentation and
    /// every other modifier in place — `private static func` becomes
    /// `static func`, not `staticfunc` and not a re-indented line. Returns `nil`
    /// when the line no longer carries the modifier, which is the guard against
    /// applying a stale candidate to a file that moved underneath it.
    public static func widened(source: String, candidate: Candidate) -> String? {
        var lines = source.components(separatedBy: "\n")
        let index = candidate.line - 1
        guard lines.indices.contains(index) else { return nil }
        guard containsWord(candidate.modifier, in: lines[index]) else { return nil }
        guard let range = lines[index].range(of: candidate.modifier + " ")
            ?? lines[index].range(of: candidate.modifier) else { return nil }
        lines[index].removeSubrange(range)
        return lines.joined(separator: "\n")
    }

    /// A unified diff for the one changed line.
    ///
    /// **The output is a diff, not prose, deliberately.** If it were prose the
    /// verdict would not transfer — the reader would write a different edit from
    /// the one that was compiled, and the claim *"this law held over 100 trials"*
    /// would be about code nobody has. A diff is the exact text that was verified.
    public static func unifiedDiff(
        path: String,
        original: String,
        widened: String,
        line: Int
    ) -> String {
        let before = original.components(separatedBy: "\n")
        let after = widened.components(separatedBy: "\n")
        let index = line - 1
        guard before.indices.contains(index), after.indices.contains(index) else { return "" }
        return """
        --- a/\(path)
        +++ b/\(path)
        @@ -\(line),1 +\(line),1 @@
        -\(before[index])
        +\(after[index])
        """
    }
}
