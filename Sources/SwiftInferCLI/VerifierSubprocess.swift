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
    ///
    /// V1.149 — `-Xswiftc -enable-testing` compiles every target (including
    /// the path-dependency user module) with testing enabled, so a stub's
    /// `@testable import <UserModule>` resolves `internal` symbols. Harmless
    /// for stdlib-carrier stubs that don't `@testable`-import anything.
    public static func runSwiftBuild(workdir: URL) throws -> Output {
        try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "swift", "build", "--package-path", workdir.path,
                "-Xswiftc", "-enable-testing"
            ],
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
    /// Wall-clock ceiling for a single verifier run.
    ///
    /// **A generated property can hang, and until now that wedged the survey.**
    /// The strategist's `.rawRepresentable` recipe for a `String`-raw enum emits
    /// `Gen<Character>.letterOrNumber.string(of: 0...8).compactMap { T(rawValue: $0) }`
    /// — random strings filtered for ones that happen to be a valid raw value.
    /// For any real enum the odds are effectively zero, so `compactMap` retries
    /// forever. Two such binaries spun at 100% CPU for over an hour during the
    /// self-dogfood road test while the survey reported nothing at all.
    ///
    /// This class of failure is nastier than the compile errors beside it. A
    /// stub that fails to build is loud and lands as `measured-error`; a stub
    /// that compiles, runs, and never terminates produces no verdict, no error,
    /// and no output — the survey simply stops. A bounded wait converts it into
    /// an honest `measured-error: timed-out`.
    ///
    /// 300s is deliberately generous: the slowest legitimate run measured in
    /// this repo (a full TCA corpus verify) is well under a minute, so anything
    /// past five minutes is a hang rather than a slow property.
    public static let defaultRunTimeout: TimeInterval = 300

    public static func runVerifierBinary(
        workdir: URL,
        extraEnvironment: [String: String] = [:],
        timeout: TimeInterval? = defaultRunTimeout
    ) throws -> Output {
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
        // V2.0 M8.D.2 — extraEnvironment merges over the testing-
        // library-path environment (caller's entries win). Used by
        // the shrinker (M8.D.3) to set SWIFT_INFER_PIN_SEQUENCE /
        // SWIFT_INFER_PIN_PREFIX_LENGTH per re-invocation.
        var env = environmentWithTestingRuntimePaths()
        for (key, value) in extraEnvironment {
            env[key] = value
        }
        return try runProcess(
            executable: binaryPath,
            arguments: [],
            workingDirectory: workdir,
            environment: env,
            timeout: timeout
        )
    }

    // MARK: - V1.53.A — libTesting.dylib runtime path

    /// Cached toolchain testing-library directory (e.g.
    /// `<toolchain>/usr/lib/swift/macosx/testing`). Computed once on
    /// first access via `swift -print-target-info`; nil if the
    /// invocation fails, the JSON lacks `paths.runtimeResourcePath`,
    /// or the `macosx/testing` subdirectory doesn't exist. The cache
    /// matters at survey scale — without it, a 109-pick survey
    /// would shell out to `swift` 109 times.
    static let cachedTestingLibraryDirectory: String? = computeTestingLibraryDirectory()

    /// Cycle 110 (Blocker B) — toolchain directory containing
    /// `Testing.framework`. swift-testing migrated from `libTesting.dylib`
    /// (resolved via `DYLD_LIBRARY_PATH`, see `cachedTestingLibraryDirectory`)
    /// to a framework bundle, so `cachedTestingLibraryDirectory` is now
    /// `nil` on current toolchains and the verifier links
    /// `@rpath/Testing.framework`. A framework is found via
    /// `DYLD_FRAMEWORK_PATH`, not `DYLD_LIBRARY_PATH`. Cached like its
    /// sibling so a survey doesn't shell out per pick.
    static let cachedTestingFrameworkDirectory: String? = computeTestingFrameworkDirectory()

    /// Build a fresh subprocess environment with the toolchain's
    /// swift-testing runtime on the dynamic-loader search paths. Sets
    /// `DYLD_LIBRARY_PATH` (the `libTesting.dylib` form, V1.53.A) and
    /// `DYLD_FRAMEWORK_PATH` (the `Testing.framework` form, cycle-110
    /// Blocker B) — whichever the active toolchain ships. Existing
    /// entries are preserved (our entry first so it resolves missing
    /// libraries; the user's value still wins via later position).
    ///
    /// Returns the parent's full environment unchanged if neither dir is
    /// detectable, preserving graceful degradation on machines without
    /// the expected toolchain layout.
    private static func environmentWithTestingRuntimePaths() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let libDir = cachedTestingLibraryDirectory {
            env["DYLD_LIBRARY_PATH"] = prepend(libDir, onto: env["DYLD_LIBRARY_PATH"])
        }
        if let frameworkDir = cachedTestingFrameworkDirectory {
            env["DYLD_FRAMEWORK_PATH"] = prepend(frameworkDir, onto: env["DYLD_FRAMEWORK_PATH"])
        }
        return env
    }

    /// Prepend `dir` to a colon-separated DYLD path, preserving any
    /// existing entries after it.
    private static func prepend(_ dir: String, onto existing: String?) -> String {
        if let existing, !existing.isEmpty { return "\(dir):\(existing)" }
        return dir
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

    /// Cycle 110 (Blocker B) — locate the directory containing
    /// `Testing.framework` for the active developer dir. `xcode-select -p`
    /// → `<Xcode>/Contents/Developer`; the framework ships under the macOS
    /// platform's framework dir (canonical) with a `Contents/SharedFrameworks`
    /// fallback. Returns the first candidate that actually contains
    /// `Testing.framework`, or `nil` (caller degrades to the inherited
    /// environment). Same "ask the active toolchain, don't hard-code"
    /// posture as `computeTestingLibraryDirectory`, for the framework form
    /// swift-testing migrated to.
    private static func computeTestingFrameworkDirectory() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["xcode-select", "-p"]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let developerDir = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !developerDir.isEmpty else {
            return nil
        }
        let developerURL = URL(fileURLWithPath: developerDir)
        let candidates = [
            developerURL
                .appendingPathComponent("Platforms/MacOSX.platform/Developer/Library/Frameworks"),
            // `<Xcode>/Contents/Developer` → `<Xcode>/Contents/SharedFrameworks`
            developerURL.deletingLastPathComponent().appendingPathComponent("SharedFrameworks")
        ]
        for dir in candidates
        where FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("Testing.framework").path
        ) {
            return dir.path
        }
        return nil
    }

    // MARK: - Process helper

    /// Thread-safe accumulator for a drained pipe.
    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()

        func append(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            storage.append(data)
        }

        var value: Data {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
    }

    /// Test seam for `VerifierTimeoutTests`. The timeout's interesting behaviour
    /// is all real-process behaviour — SIGTERM escalation, pipe-buffer
    /// backpressure — so the tests drive actual subprocesses rather than a fake.
    static func runProcessForTesting(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        timeout: TimeInterval?
    ) throws -> Output {
        try runProcess(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeout: timeout
        )
    }

    private static func runProcess(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
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

        // Drain both pipes on background queues rather than after
        // `waitUntilExit`. Reading only after the wait deadlocks whenever the
        // child outfills a 64 KB pipe buffer — the child blocks writing, we
        // block waiting — and that deadlock is indistinguishable from the hang
        // this timeout exists to catch. Draining concurrently also means a
        // timed-out run still returns whatever the child managed to print.
        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let drained = DispatchGroup()
        for (handle, box) in [
            (stdoutPipe.fileHandleForReading, stdoutBox),
            (stderrPipe.fileHandleForReading, stderrBox)
        ] {
            DispatchQueue.global(qos: .userInitiated).async(group: drained) {
                box.append(handle.readDataToEndOfFile())
            }
        }

        try process.run()
        let timedOut = waitForExit(process, timeout: timeout)
        // Bounded: both handles hit EOF once the child is gone.
        _ = drained.wait(timeout: .now() + 30)

        let stdout = String(data: stdoutBox.value, encoding: .utf8) ?? ""
        let stderr = String(data: stderrBox.value, encoding: .utf8) ?? ""
        if timedOut {
            throw VerifyError.runnerCrashed(
                reason: "timed-out: the verifier ran longer than "
                    + "\(Int(timeout ?? 0))s and was killed. The generated property did not "
                    + "terminate — most often a filtering generator "
                    + "(`.compactMap { T(rawValue:) }` over random strings) that can "
                    + "essentially never produce a value."
                    + (stdout.isEmpty ? "" : " Partial stdout: \(stdout.prefix(400))")
            )
        }
        return Output(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    /// Wait for `process`, returning `true` if the deadline passed first (in
    /// which case the process has been killed). A `nil` timeout waits forever,
    /// preserving the previous behaviour for callers that want it.
    ///
    /// **Event-driven, not a poll loop.** The first version of this read
    /// `Date()` in a `while` condition and slept 50ms per iteration. That is
    /// two defects at once, and SwiftProjectLint flagged both within hours —
    /// four `Non-Injected Nondeterminism` hits and two `Thread Sleep` hits, in
    /// code whose entire purpose is to make a *timing* behaviour testable
    /// (`docs/roadtest-self-dogfood.md` §14.4). `Process.terminationHandler`
    /// plus a semaphore waits on the actual event and takes its deadline from a
    /// monotonic source, so nothing reads the wall clock and nothing spins.
    private static func waitForExit(_ process: Process, timeout: TimeInterval?) -> Bool {
        guard let timeout else {
            process.waitUntilExit()
            return false
        }
        // `terminationHandler` fires once the child is reaped. Signalling a
        // semaphore from it turns "has it exited yet?" from a question we ask
        // repeatedly into one the OS answers once.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        // A child that exited between `run()` and the handler being installed
        // would never signal, so check once explicitly.
        if !process.isRunning { exited.signal() }

        if exited.wait(timeout: .now() + timeout) == .success {
            process.waitUntilExit()
            return false
        }
        // SIGTERM first so a well-behaved child can flush; SIGKILL if it won't
        // go. A hung generator loop ignores SIGTERM, so the escalation matters.
        process.terminate()
        if exited.wait(timeout: .now() + 2) != .success {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        return true
    }
}
