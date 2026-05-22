import Foundation
import Testing
@testable import SwiftInferCLI
@testable import SwiftInferCore

/// V1.68 — `Discover.run`-level integration coverage for the verify
/// evidence wiring. `DiscoverPipelineVerifyEvidenceTests` exercises the
/// pure `collectVisibleSuggestions` function with an in-memory evidence
/// map; these tests exercise the CLI `run()` entry point end-to-end:
/// the `VerifyEvidenceStore.load` disk read of
/// `.swiftinfer/verify-evidence.json`, the map hand-off into the
/// pipeline, and the rendered output. Closes the cycle-64 gap where the
/// `run()` wiring was only smoke-tested.
@Suite("Discover CLI — verify-evidence suppression wiring (V1.68)")
struct DiscoverCLIVerifySuppressionTests {

    /// A recursive-idempotence function — produces a Strong-tier
    /// `idempotence` pick, visible by default.
    private let strongIdempotenceSource = """
    struct Sanitizer {
        func normalize(_ value: String) -> String {
            return normalize(normalize(value))
        }
    }
    """

    /// `wrangle(_:Int) -> Int` produces a sub-threshold `.possible`
    /// `idempotence` pick (typeSymmetrySignature +30) — hidden by
    /// default, the natural target for the bothPass rescue path.
    private let possibleIdempotenceSource =
        "public func wrangle(_ value: Int) -> Int { value &+ 1 }\n"

    /// Build a minimal SwiftPM package fixture: a `Package.swift`
    /// sentinel at the root (so `VerifyEvidenceStore.load`'s walk-up
    /// resolves the package root) and one source file under
    /// `Sources/Lib/`. Returns both the root and the target directory.
    private func makePackageFixture(
        name: String,
        source: String
    ) throws -> (root: URL, target: URL) {
        let root = try makeDPFixtureDirectory(name: name)
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: root.appendingPathComponent("Package.swift"))
        let target = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Lib")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try source.write(
            to: target.appendingPathComponent("Source.swift"),
            atomically: true,
            encoding: .utf8
        )
        return (root, target)
    }

    /// Persist a `.swiftinfer/verify-evidence.json` at the package root.
    private func writeEvidence(_ records: [VerifyEvidence], toRoot root: URL) throws {
        try VerifyEvidenceStore.write(
            VerifyEvidenceLog(records: records),
            to: root.appendingPathComponent(".swiftinfer/verify-evidence.json")
        )
    }

    private func evidence(
        for suggestion: Suggestion,
        outcome: VerifyEvidenceOutcome,
        detail: String?
    ) -> VerifyEvidence {
        VerifyEvidence(
            identityHash: suggestion.identity.normalized,
            template: suggestion.templateName,
            outcome: outcome,
            detail: detail,
            capturedAt: Date(timeIntervalSince1970: 0),
            swiftInferVersion: "test"
        )
    }

    @Test("defaultFails evidence on disk suppresses a Strong pick from Discover.run output")
    func defaultFailsOnDiskSuppressesStrongPick() throws {
        let (root, target) = try makePackageFixture(
            name: "CLIVerifyVeto",
            source: strongIdempotenceSource
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let strong = try #require(
            try SwiftInferCommand.Discover.collectVisibleSuggestions(
                directory: target,
                diagnostics: DPRecordingDiagnosticOutput()
            )
            .suggestions.first { $0.score.tier == .strong }
        )

        // Control — no evidence file yet, so the Strong pick renders.
        let control = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: target,
            output: control,
            diagnostics: DPRecordingDiagnosticOutput()
        )
        #expect(control.text.contains(strong.identity.display))

        // Persist a defaultFails veto and re-run: the pipeline loads the
        // file, grades the pick to `.suppressed`, and drops it before
        // the visibility cut — the CLI output no longer carries it.
        try writeEvidence(
            [evidence(for: strong, outcome: .measuredDefaultFails, detail: "trial=4")],
            toRoot: root
        )
        let vetoed = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: target,
            output: vetoed,
            diagnostics: DPRecordingDiagnosticOutput()
        )
        #expect(!vetoed.text.contains(strong.identity.display))
    }

    @Test("defaultFails veto holds through Discover.run even with --include-possible")
    func defaultFailsOnDiskHoldsUnderIncludePossible() throws {
        let (root, target) = try makePackageFixture(
            name: "CLIVerifyVetoIncludePossible",
            source: strongIdempotenceSource
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let strong = try #require(
            try SwiftInferCommand.Discover.collectVisibleSuggestions(
                directory: target,
                diagnostics: DPRecordingDiagnosticOutput()
            )
            .suggestions.first { $0.score.tier == .strong }
        )
        try writeEvidence(
            [evidence(for: strong, outcome: .measuredDefaultFails, detail: "trial=4")],
            toRoot: root
        )

        let vetoed = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: target,
            includePossible: true,
            output: vetoed,
            diagnostics: DPRecordingDiagnosticOutput()
        )
        // `.suppressed` is dropped unconditionally — `--include-possible`
        // must not leak a verify-disproven pick (the V1.67.A
        // `combineAndFilter` guard, exercised through the CLI here).
        #expect(!vetoed.text.contains(strong.identity.display))
    }

    @Test("bothPass evidence on disk rescues a sub-threshold pick into Discover.run output")
    func bothPassOnDiskRescuesSubThresholdPick() throws {
        let (root, target) = try makePackageFixture(
            name: "CLIVerifyRescue",
            source: possibleIdempotenceSource
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let possible = try #require(
            try SwiftInferCommand.Discover.collectVisibleSuggestions(
                directory: target,
                includePossible: true,
                diagnostics: DPRecordingDiagnosticOutput()
            )
            .suggestions.first { $0.templateName == "idempotence" }
        )
        #expect(possible.score.tier == .possible)

        // Control — no evidence file, no `--include-possible`: the
        // `.possible` pick is hidden.
        let control = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: target,
            output: control,
            diagnostics: DPRecordingDiagnosticOutput()
        )
        #expect(!control.text.contains(possible.identity.display))

        // Persist bothPass and re-run with no `--include-possible`: the
        // +50 signal grades the pick to `.strong` before the visibility
        // cut, lifting it into the default CLI output.
        try writeEvidence(
            [evidence(for: possible, outcome: .measuredBothPass, detail: "defaultTrials=100 edgeTrials=100")],
            toRoot: root
        )
        let rescued = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: target,
            output: rescued,
            diagnostics: DPRecordingDiagnosticOutput()
        )
        #expect(rescued.text.contains(possible.identity.display))
    }
}
