import Foundation

/// V1.42.C.3 — wraps `Process` invocations of `swift build` and the
/// verifier binary that V1.42.C.2 / `VerifierWorkdir` synthesize.
///
/// Two distinct calls:
///   1. `swift build --package-path <workdir>` — produces the binary
///      at `<workdir>/.build/debug/SwiftInferVerifier`. Build failures
///      surface via the captured stderr.
///   2. The compiled binary itself — runs the property-check loop,
///      prints `VERIFY_*` markers V1.42.C.4 will parse, exits 0/1.
///
/// **Why two calls.** A single `swift run` would intermix build
/// chatter with the verifier's stdout, which breaks the `VERIFY_*`
/// parsing in C.4. Spawning the binary directly after `swift build`
/// keeps the verifier's stdout clean.
///
/// **`swift` resolution.** The harness uses `/usr/bin/env swift` so
/// the user's PATH-resolved Swift toolchain is what runs — usually
/// fine on macOS where the Xcode-managed toolchain symlinks `swift`
/// into `/usr/bin/`. Users with non-standard toolchain layouts can
/// set `SWIFT_PATH` env-var (V1.42.C.3.future hook; not yet wired).
public enum VerifierSubprocess {

    /// Raw subprocess result. V1.42.C.4 parses `stdout` for the
    /// `VERIFY_*` markers and renders the user-facing outcome.
    public struct Output: Equatable, Sendable {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String

        public init(exitCode: Int32, stdout: String, stderr: String) {
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    /// Run `swift build` in the given workdir. Returns the
    /// captured output and exit code.
    public static func runSwiftBuild(workdir: URL) throws -> Output {
        try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["swift", "build", "--package-path", workdir.path],
            workingDirectory: workdir
        )
    }

    /// Run the compiled `SwiftInferVerifier` binary at the
    /// canonical SwiftPM debug-build path. Caller is expected to
    /// have already invoked `runSwiftBuild` to produce the binary;
    /// if the path doesn't exist, this throws
    /// `VerifyError.runnerCrashed` with a load-bearing message.
    public static func runVerifierBinary(workdir: URL) throws -> Output {
        let binaryPath = workdir
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
            .appendingPathComponent("SwiftInferVerifier")
        guard FileManager.default.fileExists(atPath: binaryPath.path) else {
            throw VerifyError.runnerCrashed(
                reason: "verifier binary not found at \(binaryPath.path); "
                    + "did `swift build` succeed in the workdir?"
            )
        }
        return try runProcess(
            executable: binaryPath,
            arguments: [],
            workingDirectory: workdir
        )
    }

    // MARK: - Process helper

    private static func runProcess(
        executable: URL,
        arguments: [String],
        workingDirectory: URL
    ) throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return Output(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
