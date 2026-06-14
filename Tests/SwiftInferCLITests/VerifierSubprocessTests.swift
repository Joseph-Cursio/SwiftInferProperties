import Foundation
import Testing

@testable import SwiftInferCLI

/// V1.42.C.3 — VerifierSubprocess smoke tests.
///
/// These exercise the `Process` wrapper itself (stdout / stderr / exit
/// code capture) using cheap, deterministic external commands so they
/// can run on CI without depending on a SwiftPM build. The actual
/// `swift build` + verifier-binary integration is covered by
/// V1.42.D.2 / D.3.
@Suite("VerifierSubprocess — V1.42.C.3 process smoke")
struct VerifierSubprocessTests {

    private func makeTempDirectory() throws -> URL {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("verifier-subprocess-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    @Test("runVerifierBinary errors with .runnerCrashed when binary absent")
    func runVerifierBinaryMissingFile() throws {
        let workdir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: workdir) }
        do {
            _ = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
            Issue.record("expected .runnerCrashed")
        } catch let error as VerifyError {
            switch error {
            case let .runnerCrashed(reason):
                #expect(reason.contains("verifier binary"))

            default:
                Issue.record("expected .runnerCrashed; got \(error)")
            }
        }
    }

    @Test("Output struct round-trips through Equatable")
    func outputEquatable() {
        let first = VerifierSubprocess.Output(exitCode: 0, stdout: "x", stderr: "")
        let second = VerifierSubprocess.Output(exitCode: 0, stdout: "x", stderr: "")
        let third = VerifierSubprocess.Output(exitCode: 1, stdout: "x", stderr: "")
        #expect(first == second)
        #expect(first != third)
    }

    @Test("cachedTestingFrameworkDirectory, when detected, contains Testing.framework (Blocker B)")
    func testingFrameworkLocatorPointsAtTheFramework() {
        // Degrades to nil on hosts without the expected Xcode layout
        // (e.g. Linux CI) — that's correct, not a failure. When non-nil it
        // must actually contain Testing.framework so DYLD_FRAMEWORK_PATH
        // resolves the verifier's `@rpath/Testing.framework` link.
        guard let dir = VerifierSubprocess.cachedTestingFrameworkDirectory else { return }
        let framework = URL(fileURLWithPath: dir).appendingPathComponent("Testing.framework")
        #expect(FileManager.default.fileExists(atPath: framework.path))
    }

    @Test("runVerifierBinary still errors on missing binary even with extraEnvironment (M8.D.2)")
    func runVerifierBinaryMissingFileWithExtraEnv() throws {
        let workdir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: workdir) }
        do {
            _ = try VerifierSubprocess.runVerifierBinary(
                workdir: workdir,
                extraEnvironment: ["SWIFT_INFER_PIN_SEQUENCE": "42"]
            )
            Issue.record("expected .runnerCrashed")
        } catch let error as VerifyError {
            switch error {
            case .runnerCrashed:
                break

            default:
                Issue.record("expected .runnerCrashed; got \(error)")
            }
        }
    }
}
