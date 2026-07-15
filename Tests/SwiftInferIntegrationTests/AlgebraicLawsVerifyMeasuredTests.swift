import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Measured verify for the three algebraic-law templates added alongside the
/// catalogue work — involution (`f(f(x)) == x`), binary-idempotence
/// (`op(x, x) == x`), and the additive-measure homomorphism
/// (`h(a + b) == h(a) + h(b)`). Packages `Tests/Fixtures/algebraic-laws-corpus/`
/// (three genuine true positives over `Int` / `[Int]`), reindexes, and runs the
/// `verify --all-from-index --corpus-module` survey so each law's emitted stub is
/// built + run for real.
///
/// Asserts the three new templates each produce a `measured-bothPass` record
/// (not a total count — the corpus's endomorphisms also fire idempotence /
/// round-trip / commutativity picks, and coupling to that total would be
/// brittle). This is the promotion path: a `.likely` involution /
/// binary-idempotence / homomorphism pick, once verified here, folds to
/// `.verified`.
///
/// Spawns real `swift build`s resolving the algebraic deps; tagged `.subprocess`.
@Suite("Algebraic-law templates — measured verify", .tags(.subprocess))
struct AlgebraicLawsVerifyMeasuredTests {

    @Test("involution / binary-idempotence / homomorphism each verify bothPass")
    func measuredLawsVerifyBothPass() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("algebraic-laws-corpus")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "AlgebraicLawsCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        try await SwiftInferCommand.Verify.runAllFromIndex(
            indexPathOverride: nil,
            budgetString: "small",
            workingDirectory: root,
            maxParallel: 4,
            templateFilter: nil,
            corpusModuleName: "AlgebraicLawsCorpus"
        )

        let records = VerifyEvidenceStore.load(startingFrom: root).log.records
        for template in ["involution", "binary-idempotence", "homomorphism"] {
            #expect(
                records.contains { $0.template == template && $0.outcome == .measuredBothPass },
                "\(template) did not produce a measured-bothPass record"
            )
        }
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("algebraic-laws-corpus")
    }()
}
