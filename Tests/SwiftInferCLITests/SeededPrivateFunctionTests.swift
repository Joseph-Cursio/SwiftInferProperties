import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A seed naming an access-restricted function is a request, not a mistake.
///
/// ## Access level is not evidence about whether a function deserves a property test
///
/// It is evidence about *where the test can live* and *what must change before the law can be
/// verified*. Those are different questions, and the scanner's access rule answered the first with
/// the second: an external verifier compiles in another module and genuinely cannot call a
/// `private` function, which is true — and says nothing about whether that function has a law.
///
/// This docstring used to defend the default as "right", on the grounds that the rule was
/// calibrated against swift-numerics, swift-collections and swift-algorithms, and that apps merely
/// invert it. That framing is wrong twice over. It treats a structural fact as a statistical one,
/// and it implies the remedy is re-tuning per project type. There is nothing to recalibrate: how
/// often a `private` function is interesting is a fact about a **codebase**, not about
/// **privateness**, so privateness is a proxy for the wrong thing and no threshold fixes that.
///
/// The reason it looked statistical is that in library corpora `private` helpers skew toward
/// trivial glue, so skipping them read as precision. An app has no public API at all — its pure
/// logic lives almost entirely in `private` helpers inside views and view models,
/// `private func isValidFolderName`, `private func getFileIcon` — and there the same rule hides
/// the best candidates in the project.
///
/// So: **purity, shape and role decide whether a law is worth proposing; access level decides what
/// must happen before it can be verified.** Access belongs in the advice, never in the gate.
///
/// ## The gate is gone (2026-08-07)
///
/// This suite once required a *seed* to pull a `private` function into discovery, on the theory
/// that unseeded private output was noise. That was the argument above stopping one step short: if
/// access is not evidence about testworthiness, then it cannot gate *unsolicited* output either.
/// Property-based tests are refactoring-safe, so proposing a private function's law costs nothing
/// even when the code later moves — you widen it or lift it, and the law still holds. Every
/// access-restricted function now surfaces on its own, each carrying the access caveat that names
/// the one refactor unlocking verification.
///
/// A seed is therefore no longer what makes a private function *visible*. It still carries the
/// manifest `restriction` field, which *corrects* a remedy this single-pass scan gets wrong (the
/// enclosing-type blind spot) — the tests at the bottom pin that, and it is the seed's remaining job.
@Suite("Discover pipeline — an access-restricted function surfaces with its caveat")
struct SeededPrivateFunctionTests {

    private static let privateHelper = """
    struct FolderNamer {
        private func isValidFolderName(_ name: String) -> Bool {
            !name.isEmpty
        }
    }
    """

    @Test("a private function surfaces without a seed, carrying its caveat")
    func privateFunctionSurfacesWhenUnseeded() throws {
        let directory = try writeDPFixture(name: "PrivateUnseeded", contents: Self.privateHelper)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(directory: directory, includePossible: false, output: recording)

        // Privacy no longer gates discovery — no seed required. The law appears with the access
        // caveat naming the refactor that would let a test run it.
        #expect(recording.text.contains("isValidFolderName"))
        #expect(recording.text.contains("NO TEST CAN RUN THIS LAW AS WRITTEN"))
    }

    /// A surfaced private function earns its REAL law, not the `f(x) == f(x)` tautology.
    ///
    /// When restricted functions reached only `synthesizeGenericLaws` they were handed the one law
    /// that cannot fail, while every refutable law their shape and name entailed was withheld —
    /// they never entered the template pipeline at all. Now they enter it like any function, so
    /// `isValidFolderName(_ String) -> Bool`, a **predicate**, earns the role-entailed totality law.
    /// No seed needed; `determinism` remains the fallback only for a function no template matches.
    @Test("a private function earns its REAL template law, not the determinism fallback")
    func privateFunctionEarnsItsTemplateLaw() throws {
        let directory = try writeDPFixture(name: "PrivateSeeded", contents: Self.privateHelper)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )

        #expect(recording.text.contains("Template: predicate"))
        #expect(recording.text.contains("isValidFolderName"))
        // The tautology must not ALSO appear — a real law plus `f(x) == f(x)` about the same
        // function is the substitution `guardFinalAnswer` exists to prevent, arriving by a new route.
        #expect(recording.text.contains("Template: determinism") == false)
    }

    /// A rescued function that NO template matches still gets the floor law, so the rescue never
    /// regresses to silence. `(Int, Int) -> Int` named `combine` matches no template gate here —
    /// `associativity` and `commutativity` need a curated name or reduce-fold corroboration — so
    /// this is the determinism path the test above deliberately no longer covers.
    @Test("a rescued function no template matches still earns the determinism floor")
    func rescuedFunctionKeepsTheDeterminismFloor() throws {
        let source = """
        struct Math {
            private func combine(_ lhs: Int, _ rhs: Int) -> Int { lhs - rhs }
        }
        """
        let directory = try writeDPFixture(name: "PrivateFloor", contents: source)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = SeedManifest(seeds: [.init(file: "Source.swift", line: 2, symbol: "combine")])
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )

        #expect(recording.text.contains("combine"))
        #expect(recording.text.contains("NO TEST CAN RUN THIS LAW AS WRITTEN"))
    }

    @Test("the surfaced law leads with the refactor that would let it run")
    func restrictedLawLeadsWithTheRemedy() throws {
        let directory = try writeDPFixture(name: "PrivateRemedy", contents: Self.privateHelper)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )

        // Stating the law without saying it cannot be run would be a different kind of lie. The
        // remedy rides on the actual law's caveat — no seed, no detached diagnostic line.
        #expect(recording.text.contains("NO TEST CAN RUN THIS LAW AS WRITTEN"))
        #expect(recording.text.contains("Widen it to `internal`"))
        // The remedy must LEAD: it is the first caveat, not the fourth.
        let caveatBlock = recording.text.components(separatedBy: "Why this might be wrong:")
        let firstCaveat = try #require(caveatBlock.dropFirst().first)
            .split(separator: "⚠").dropFirst().first
        #expect(try #require(firstCaveat).contains("NO TEST CAN RUN THIS LAW AS WRITTEN"))
    }

    @Test("both private functions surface — visibility is not scoped to a seed")
    func everyPrivateFunctionSurfaces() throws {
        let source = """
        struct Namer {
            private func alpha(_ name: String) -> Bool { !name.isEmpty }
            private func bravo(_ name: String) -> Bool { name.isEmpty }
        }
        """
        let directory = try writeDPFixture(name: "PrivateScoped", contents: source)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )

        // No manifest, and both private predicates appear — the seed no longer gates visibility.
        #expect(recording.text.contains("alpha"))
        #expect(recording.text.contains("bravo"))
    }

    // MARK: - The manifest's `restriction`, and the blind spot it covers

    /// **The case the field is carried for**, end to end.
    ///
    /// `Helper` is `private`; the member is written in an *unmarked* extension of it. This scan's
    /// enclosing-type stack is same-declaration only — the extension carries no modifier and the
    /// type's own declaration is a different decl — so locally this reads as blocked by the
    /// member's own `private`, which is the one **widenable** answer. The linter resolved the type
    /// and said `enclosing-type`.
    ///
    /// Without the manifest field, the tool tells the reader to delete a keyword. They do it, it
    /// compiles, nothing changes, and the law is still unrunnable — which is the failure mode the
    /// whole `restricted-function` design exists to prevent, arriving by the one route the local
    /// analysis cannot close.
    @Test("the manifest's enclosing-type restriction corrects a remedy this scan gets wrong")
    func manifestCorrectsTheRemedy() throws {
        let source = """
        private struct Helper {
            let base: String
        }
        extension Helper {
            private func isValidFolderName(_ name: String) -> Bool {
                !name.isEmpty
            }
        }
        """
        let directory = try writeDPFixture(name: "PrivateEnclosing", contents: source)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = SeedManifest(seeds: [
            .init(
                file: "Source.swift",
                line: 5,
                symbol: "isValidFolderName",
                rule: "Pure Function Property-Test Candidate",
                kind: .restrictedFunction,
                restriction: .enclosingType
            )
        ])
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )

        #expect(recording.text.contains("NO TEST CAN RUN THIS LAW AS WRITTEN"))
        #expect(recording.text.contains("its enclosing type is `private` or `fileprivate`"))
        #expect(recording.text.contains("would be a no-op"))
        // The correction is announced, not applied silently: a remedy that changed because another
        // tool knew better is exactly the kind of thing a reader should be able to trace.
        #expect(diagnostics.joined.contains("corrected 1 access remedy"))

        // The advice this scan would have given alone, and the effort claim that goes with it, are
        // both gone. "One keyword" is the sentence that makes a reader act now, so leaving it on a
        // refactor that is not one keyword is worse than saying nothing about effort.
        #expect(recording.text.contains("Widen it to `internal`") == false)
        #expect(recording.text.contains("it is one keyword") == false)
    }

    /// The control. Same law, same shape, enclosing type **not** private — so this scan is right,
    /// the manifest agrees, and both the widening advice and the effort claim stand.
    ///
    /// Without this, the test above could be passed by a change that simply stopped saying "one
    /// keyword" to anyone.
    @Test("a declaration-blocked function keeps the widening advice and the effort claim")
    func declarationBlockedKeepsWideningAdvice() throws {
        let directory = try writeDPFixture(name: "PrivateDeclOnly", contents: Self.privateHelper)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = SeedManifest(seeds: [
            .init(
                file: "Source.swift",
                line: 2,
                symbol: "isValidFolderName",
                rule: "Pure Function Property-Test Candidate",
                kind: .restrictedFunction,
                restriction: .declaration
            )
        ])
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )

        #expect(recording.text.contains("Widen it to `internal`"))
        #expect(recording.text.contains("it is one keyword"))
        #expect(diagnostics.joined.contains("corrected") == false)
    }
}
