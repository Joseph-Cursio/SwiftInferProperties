import ArgumentParser
import Foundation
@testable import SwiftInferCLI
import Testing

/// V1.42.B — `swift-infer verify` subcommand surface tests.
///
/// **Scope.** v1.42.B ships only the argument-parsing shell and a
/// `.harnessNotYetWired` placeholder error; the actual subprocess
/// harness lands in V1.42.C. These tests pin the argument surface
/// (option presence, default values, prefix-matching at the
/// ArgumentParser layer) so V1.42.C's wiring can't accidentally drop
/// or rename a public CLI flag.
@Suite("VerifyCommand — V1.42.B argument surface")
struct VerifyCommandTests {

    @Test("--suggestion is optional at parse time; the run-time validator rejects empty")
    func suggestionOptionalAtParseTime() throws {
        // V1.50.B made --suggestion optional at parse time (mutually
        // exclusive with --all-from-index). The empty-args case
        // therefore parses successfully; the run-time check in
        // Verify.run() throws VerifyError.invalidArguments. This test
        // pins the parse-time success — the run-time rejection is
        // covered by V1.50.E's VerifyAllFromIndexTests.
        let command = try SwiftInferCommand.Verify.parse([])
        #expect(command.suggestion == nil)
        #expect(command.allFromIndex == false)
    }

    @Test("--suggestion <hash> parses with all other options at defaults")
    func suggestionParsesWithDefaults() throws {
        let command = try SwiftInferCommand.Verify.parse(["--suggestion", "abc123"])
        #expect(command.suggestion == "abc123")
        #expect(command.target == nil)
        #expect(command.budget == "small")
        #expect(command.indexPath == nil)
    }

    @Test("--budget standard parses without falling back to small")
    func budgetStandardOverridesDefault() throws {
        let command = try SwiftInferCommand.Verify.parse([
            "--suggestion", "abc123",
            "--budget", "standard"
        ])
        #expect(command.budget == "standard")
    }

    @Test("--target overrides the package-root walkup resolution")
    func targetOverrideParses() throws {
        let command = try SwiftInferCommand.Verify.parse([
            "--suggestion", "abc123",
            "--target", "MyLib"
        ])
        #expect(command.target == "MyLib")
    }

    @Test("--index-path overrides the .swiftinfer/index.json default")
    func indexPathOverrideParses() throws {
        let command = try SwiftInferCommand.Verify.parse([
            "--suggestion", "abc123",
            "--index-path", "/tmp/custom-index.json"
        ])
        #expect(command.indexPath == "/tmp/custom-index.json")
    }

    @Test("runPipeline against a directory without Package.swift / index → .indexMissing")
    func runPipelineSurfacesIndexMissingWithoutSetup() throws {
        // V1.42.C.6 rewires run() through the full pipeline; the
        // earliest failure point against a bare temp directory is
        // VerifyHarness.resolveIndex returning .indexMissing.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-no-index-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            _ = try SwiftInferCommand.Verify.runPipeline(
                suggestionPrefix: "0xBC43",
                indexPathOverride: nil,
                budgetString: "small",
                workingDirectory: temp
            )
            Issue.record("expected .indexMissing")
        } catch let error as VerifyError {
            switch error {
            case .indexMissing:
                break
            default:
                Issue.record("expected .indexMissing; got \(error)")
            }
        }
    }

    @Test("placeholder .harnessNotYetWired description still load-bearing")
    func harnessNotYetWiredDescriptionMentionsV142C() {
        // V1.42.C.6 no longer raises this from run(), but the case
        // remains in the VerifyError enum for potential v1.43 use.
        let error = VerifyError.harnessNotYetWired
        let description = String(describing: error)
        #expect(description.contains("V1.42"))
        #expect(description.contains("harness"))
    }
}
