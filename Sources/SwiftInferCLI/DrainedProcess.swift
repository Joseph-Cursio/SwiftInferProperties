import Foundation

/// Run a short-lived helper subprocess and capture stdout without deadlocking.
///
/// **The shape this exists to replace** is `waitUntilExit()` first,
/// `readDataToEndOfFile()` second. That hangs forever whenever the child writes
/// more than a pipe buffer (~64 KB): the child blocks on the full pipe, so it
/// can never exit, so the wait never returns. It is not a slow path — it is a
/// permanent 0% CPU stall with no output, which reads from outside exactly like
/// a slow `swift build`.
///
/// Measured (#170): `swift package dump-package` on swift-collections emits
/// **133,341 bytes**, and `verify --all-from-index` produced 0 of 98 rows,
/// twice, before being killed. The same command in a terminal takes 0.16s,
/// because a tty is not a pipe — so every manual reproduction succeeds and the
/// natural diagnosis is anything but the real one.
///
/// **Both pipes are drained, not just stdout.** An undrained `standardError`
/// deadlocks identically, and it is the one nobody notices, because the tools
/// these callers run are usually quiet — right up until one is not.
///
/// `VerifierSubprocess.runProcess` solves the same problem and deliberately
/// keeps its own implementation: it adds timeout escalation and returns
/// whatever the child managed to print when it times out, neither of which the
/// callers here want. Its comment is where this failure was first written down;
/// this type is what makes it reusable, since the knowledge existing in one
/// call site did not stop three others from shipping the broken shape.
enum DrainedProcess {

    /// stdout of `executable arguments`, or `nil` if the process could not be
    /// launched or exited non-zero.
    ///
    /// Deliberately collapses every failure to `nil`: all three callers degrade
    /// to a documented fallback rather than propagating, and none of them can
    /// act on *why* the helper failed. stderr is captured and discarded — it is
    /// read to keep the child unblocked, not to be reported.
    static func standardOutput(of executable: URL, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Start draining BEFORE `run()`. Both reads block until EOF, which
        // arrives when the child's handles close — so the child is never
        // holding a full pipe while we are waiting for it to exit.
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

        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        // Bounded: both handles hit EOF once the child is gone. The wait is a
        // backstop against an inherited handle held open by a grandchild, not
        // the normal path — mirrors `VerifierSubprocess.runProcess`.
        _ = drained.wait(timeout: .now() + 30)

        guard process.terminationStatus == 0 else { return nil }
        return stdoutBox.value
    }

    /// stdout of `/usr/bin/env <arguments>`, the PATH-resolving form all three
    /// callers use so the toolchain that runs `swift build` is the one that
    /// answers these questions too.
    static func standardOutputViaEnv(_ arguments: [String]) -> Data? {
        standardOutput(of: URL(fileURLWithPath: "/usr/bin/env"), arguments: arguments)
    }

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
}
