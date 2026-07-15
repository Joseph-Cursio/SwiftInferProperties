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

    @Test("involution / binary-idempotence / (multiplicative-)homomorphism each verify bothPass")
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
        for template in [
            "involution", "binary-idempotence", "homomorphism", "multiplicative-homomorphism",
            // `magnitude` also fires measure non-negativity (a 1-parameter measure
            // over `Int`): `magnitude(value) >= 0` holds, so it bothPasses too.
            "measure-non-negativity"
        ] {
            #expect(
                records.contains { $0.template == template && $0.outcome == .measuredBothPass },
                "\(template) did not produce a measured-bothPass record"
            )
        }
        // `Flag.union` (an INSTANCE binary operator) rides the same survey; its
        // stub is synthesized/built/run through the `{ $0.union($1) }` receiver
        // trampoline, so a broken instance path would sink the survey. Its
        // `commutativity`/`associativity`/`binary-idempotence` picks fold into the
        // template assertions above. (`VerifyEvidence` carries no carrier column,
        // so the instance form can't be isolated here; the discovery half is
        // pinned by `BinaryOperatorInstanceFormTests`.)
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("algebraic-laws-corpus")
    }()
}
