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
}
