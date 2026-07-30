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
/// ## What a seed means here
///
/// The producer has looked at the function and asked for it. Silently overruling an explicit
/// request is not precision — it is a confident zero, the same defect as an empty manifest focusing
/// to nothing. The law is surfaced with the access caveat leading, naming the one refactor that
/// unlocks verification, rather than leaving the reader to discover at verify time that their best
/// candidate was never considered.
///
/// Unseeded private functions stay hidden. That is a defensible default for *unsolicited* output —
/// but it is a default about noise, not a judgement about testworthiness, and a seed overrides it.
@Suite("Discover pipeline — a seed rescues an access-restricted function")
struct SeededPrivateFunctionTests {

    private static let privateHelper = """
    struct FolderNamer {
        private func isValidFolderName(_ name: String) -> Bool {
            !name.isEmpty
        }
    }
    """

    @Test("a private function is not surfaced without a seed")
    func privateFunctionStaysHiddenWhenUnseeded() throws {
        let directory = try writeDPFixture(name: "PrivateUnseeded", contents: Self.privateHelper)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(directory: directory, includePossible: true, output: recording)

        // Unseeded discovery is unchanged: the precision the access rules bought is intact.
        #expect(recording.text.contains("isValidFolderName") == false)
    }

    /// This used to assert `Template: determinism`, and that was the bug rather than the contract.
    ///
    /// The rescue reached only `synthesizeGenericLaws`, so a seeded private function was handed
    /// `f(x) == f(x)` — the one law that cannot fail — while every refutable law its shape and name
    /// entailed was withheld, because restricted functions never entered the template pipeline at
    /// all. That inverts "score refutability, not suggestion count" exactly: the reader got the
    /// tautology and lost the real law.
    ///
    /// `isValidFolderName(_ String) -> Bool` is a **predicate**, which is role-entailed — a correct
    /// implementation cannot fail totality. That is the law worth stating, and it is now the one
    /// emitted. `determinism` remains the fallback for a rescued function no template matches.
    @Test("a seeded private function earns its REAL law, not the determinism fallback")
    func seededPrivateFunctionEarnsItsTemplateLaw() throws {
        let directory = try writeDPFixture(name: "PrivateSeeded", contents: Self.privateHelper)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = SeedManifest(seeds: [
            .init(file: "Source.swift", line: 2, symbol: "isValidFolderName")
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

        #expect(recording.text.contains("Template: predicate"))
        #expect(recording.text.contains("isValidFolderName"))
        // The tautology must not ALSO appear — a real law plus `f(x) == f(x)` about the same
        // function is the substitution `guardFinalAnswer` exists to prevent, arriving by a new route.
        #expect(recording.text.contains("Template: determinism") == false)
        #expect(diagnostics.joined.contains("rescued 1 seeded access-restricted function(s)"))
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

    @Test("the rescued law leads with the refactor that would let it run")
    func rescuedLawCarriesTheRemedy() throws {
        let directory = try writeDPFixture(name: "PrivateRemedy", contents: Self.privateHelper)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = SeedManifest(seeds: [
            .init(file: "Source.swift", line: 2, symbol: "isValidFolderName")
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

        // Stating the law without saying it cannot be run would be a different kind of lie.
        //
        // Two assertions here changed with the template rescue, and neither weakened. The remedy is
        // now spelled in caps by BOTH the template path and the determinism fallback (they used to
        // differ in case, so a reader grepping for it found one and not the other). And the
        // stderr note this used to require came from `synthesizeGenericLaws`, which no longer runs
        // for a function a template covered — the remedy moved onto the actual law's caveat, which
        // is where it belongs and is strictly better placement than a detached diagnostic line.
        #expect(recording.text.contains("NO TEST CAN RUN THIS LAW AS WRITTEN"))
        #expect(recording.text.contains("Widen it to `internal`"))
        #expect(diagnostics.joined.contains("rescued 1 seeded access-restricted function(s)"))
        // The remedy must LEAD: it is the first caveat, not the fourth.
        let caveatBlock = recording.text.components(separatedBy: "Why this might be wrong:")
        let firstCaveat = try #require(caveatBlock.dropFirst().first)
            .split(separator: "⚠").dropFirst().first
        #expect(try #require(firstCaveat).contains("NO TEST CAN RUN THIS LAW AS WRITTEN"))
    }

    @Test("an unseeded private function is still absent even when another is seeded")
    func rescueIsScopedToTheSeed() throws {
        let source = """
        struct Namer {
            private func seeded(_ name: String) -> Bool { !name.isEmpty }
            private func unseeded(_ name: String) -> Bool { name.isEmpty }
        }
        """
        let directory = try writeDPFixture(name: "PrivateScoped", contents: source)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = SeedManifest(seeds: [.init(file: "Source.swift", line: 2, symbol: "seeded")])
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )

        // The rescue is a response to a request, not a general amnesty.
        #expect(recording.text.contains("seeded(_:)"))
        #expect(recording.text.contains("unseeded") == false)
    }
}
