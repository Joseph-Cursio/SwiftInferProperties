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
    ///
    /// **V1.53.A** — injects `DYLD_LIBRARY_PATH` pointing at the
    /// active toolchain's swift-testing runtime directory. The
    /// verifier binary transitively links `libTesting.dylib` (via
    /// `swift-property-based`'s `import Testing`) but SwiftPM's
    /// linker bakes an rpath that doesn't match libTesting's actual
    /// install location on macOS. Cycle-49 (`docs/calibration-
    /// cycle-49-findings.md`) traced the 12 parse-error picks to
    /// `dyld: Library not loaded: @rpath/libTesting.dylib`; this
    /// env-var injection closes that gap at run-time without
    /// requiring workdir-synthesis changes.
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
            workingDirectory: workdir,
            environment: environmentWithTestingLibraryPath()
        )
    }

    // MARK: - V1.53.A — libTesting.dylib runtime path

    /// Cached toolchain testing-library directory (e.g.
    /// `<toolchain>/usr/lib/swift/macosx/testing`). Computed once on
    /// first access via `xcrun --find swift`; nil if xcrun fails,
    /// produces an unexpected path, or the testing directory doesn't
    /// exist. The 109-pick cycle-49 survey paid the xcrun cost 109
    /// times before this cache existed; v1.53 pays it once.
    static let cachedTestingLibraryDirectory: String? = computeTestingLibraryDirectory()

    /// Build a fresh subprocess environment with `DYLD_LIBRARY_PATH`
    /// prepended by the cached testing-library directory (when
    /// detected). Existing `DYLD_LIBRARY_PATH` entries are preserved
    /// — appended after the new entry so the user's value wins on
    /// conflict but our entry resolves missing libraries.
    ///
    /// Returns the parent's full environment if the testing dir
    /// isn't detectable, preserving v1.52 behavior so the fix
    /// degrades gracefully on machines without xcrun / without the
    /// expected toolchain layout.
    private static func environmentWithTestingLibraryPath() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        guard let testingDir = cachedTestingLibraryDirectory else { return env }
        if let existing = env["DYLD_LIBRARY_PATH"], !existing.isEmpty {
            env["DYLD_LIBRARY_PATH"] = "\(testingDir):\(existing)"
        } else {
            env["DYLD_LIBRARY_PATH"] = testingDir
        }
        return env
    }

    /// Locate the active Swift toolchain's testing-library directory.
    /// Implementation: shell out to `swift -print-target-info` (via
    /// `/usr/bin/env`) and parse the JSON for `paths.runtimeResourcePath`,
    /// then append `macosx/testing`. **Why not `xcrun --find swift`**:
    /// xcrun returns Xcode's default toolchain, which is *not* the
    /// toolchain `swift build` actually uses when the user has a
    /// custom toolchain installed via `swiftly` or `TOOLCHAINS`. The
    /// `swift -print-target-info` path reports the real runtime
    /// location, matching what the verifier binary was built against.
    /// Returns `nil` on any failure — caller falls back to inherited
    /// environment.
    private static func computeTestingLibraryDirectory() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "-print-target-info"]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paths = json["paths"] as? [String: Any],
              let runtimeResourcePath = paths["runtimeResourcePath"] as? String,
              !runtimeResourcePath.isEmpty else { return nil }
        let testingDir = URL(fileURLWithPath: runtimeResourcePath)
            .appendingPathComponent("macosx")
            .appendingPathComponent("testing")
        guard FileManager.default.fileExists(atPath: testingDir.path) else { return nil }
        return testingDir.path
    }

    // MARK: - Process helper

    private static func runProcess(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]? = nil
    ) throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        if let environment {
            process.environment = environment
        }
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
