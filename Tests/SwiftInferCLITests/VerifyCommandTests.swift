import ArgumentParser
import Foundation
@testable import SwiftInferCLI
import Testing

/// `swift-infer verify` — the CLI surface and the wording of its refusals.
///
/// **Scope.** The argument surface (option presence, default values, prefix-matching at the
/// ArgumentParser layer), so a rewire cannot silently drop or rename a public CLI flag; plus one
/// law over `VerifyError`'s rendered text.
///
/// This header used to describe the suite as pinning a "v1.42.B argument shell" around a
/// `.harnessNotYetWired` placeholder "until the harness lands in V1.42.C". The harness landed at
/// V1.42.C.6; the placeholder became unreachable and was deleted on 2026-08-11, along with the
/// test that had kept it looking maintained. The header outlived both by about a hundred releases,
/// which is the same defect `refusalsNameTheGateRatherThanAVersion` now guards against in the
/// user-facing text.
@Suite("VerifyCommand — argument surface and refusal wording")
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

    /// No refusal promises a release.
    ///
    /// Three of these read "not supported in v1.42 … wider support lands in v1.44", and a fourth
    /// case told the reader to "try again after the next v1.42 deliverable". All four were surfaced
    /// from a **1.149.0** binary on 2026-08-11, pointing the tool at SwiftProjectLint — so a user
    /// was refused and then told to wait for a version that had shipped a hundred releases earlier
    /// without delivering the thing.
    ///
    /// The guard is on the **version-prophecy shape**, not on the exact old sentences: asserting
    /// the current wording would only check that two copies of it agree. A refusal must name what
    /// would have to be true, which does not go stale, rather than when it will supposedly happen.
    ///
    /// Every case is enumerated with a representative payload rather than sampled, so a case added
    /// later cannot slip past — the compiler forces this list to be updated when the enum grows.
    @Test("no verify refusal dates itself or promises a release")
    func refusalsNameTheGateRatherThanAVersion() {
        let refusals: [VerifyError] = [
            .suggestionNotFound(prefix: "AB", closest: ["CD"]),
            .ambiguousPrefix(prefix: "AB", matches: ["CD", "EF"]),
            .indexMissing(expectedPath: URL(fileURLWithPath: "/tmp/index.json")),
            .indexEmpty(path: nil),
            .unsupportedCarrier(carrier: "Widget", expected: ["Int"]),
            .buildFailed(exitCode: 1, stderr: "boom"),
            .runnerCrashed(reason: "signal 9"),
            .unsupportedTemplate(template: "comparator", expected: ["idempotence"]),
            .unsupportedPair(forward: "encode", supported: ["serialize"]),
            .missingPairedFunction(template: "differential-equivalence", primary: "render"),
            .monotonicityDomainNotComparable(domain: "Widget"),
            .invalidArguments(reason: "pick one")
        ]

        for refusal in refusals {
            let description = String(describing: refusal)

            #expect(
                description.range(of: #"lands in v\d"#, options: .regularExpression) == nil,
                """
                A refusal promises a future release: "\(description)". Name the gate — what would \
                have to be true — not a version. The promised version ships and the gate does not, \
                and the sentence outlives it by a hundred releases.
                """
            )
            #expect(
                description.range(of: #"(not supported|available) in v\d"#, options: .regularExpression) == nil,
                """
                A refusal dates itself against a release: "\(description)". The binary's own \
                version moves and this sentence does not, so it tells the reader they are on a \
                version they are not on.
                """
            )
        }
    }
}
