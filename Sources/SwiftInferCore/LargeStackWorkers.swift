import Foundation

/// Work that recurses as deep as the source it reads, run on threads whose stack is sized for it.
///
/// swift-syntax's parser burns roughly ten frames per nesting level
/// (`parseExpression → parseSequenceExpression → … → parseArgumentListElements`), and ordinary
/// Swift — a closure in an `if` in a `for` in a closure — nests a dozen levels and more. The main
/// thread's 8 MB holds that easily. **A GCD worker's and a Swift-concurrency thread's ~512 KB do
/// not**, and overflowing it is not an error a caller can catch: it is `SIGBUS` on the guard page,
/// and it kills the whole process. `docs/measurements/parsing-catalog-gap.md` § *The stack-depth
/// trap* recorded this for a test that parsed a deep corpus, and named the remedy: a `Thread`
/// with an explicit `stackSize`.
///
/// **Measured again when the construction universe was wired in (2026-10-06)**, this time against
/// the product's own code path: the first parallel parse used `DispatchQueue.concurrentPerform`,
/// and the batch-2 census died with `SIGBUS` — 184 frames of recursive descent on a
/// `com.apple.root.default-qos` worker, parsing a manifest corpus's universe. So the universe is
/// parsed — and its table built, which walks every tree — only on threads made here.
///
/// **The CLI never had the main thread's 8 MB.** Every `AsyncParsableCommand`'s `run()` is
/// `async` and runs on a Swift-concurrency cooperative thread (~512 KB) — measured: a judged file
/// of `f({ g(…) })` nested 26 times (52 levels) `SIGBUS`es `discover` at the same depth on main and
/// on this branch, on `Task 1`'s cooperative queue, with the main thread idle in `CFMainExecutor`.
/// What moved here is the universe parse and the table build, the out-of-universe re-parse in
/// `FunctionScanner.scanCorpus(file:purity:)`, and the declarations-only scan
/// (`scanTypeDecls(directory:)`). **TestLifter's parse of the test directory still runs on the
/// cooperative stack**, so default `discover` over such a file still crashes as it did on main;
/// with `--test-dir` pointed at an empty folder it does not.
enum LargeStackWorkers {

    /// Twice the main thread's 8 MB. Virtual, not committed: a thread touches only the pages it
    /// recurses into.
    static let stackSize = 16 << 20

    /// `body(index)` for every index in `0..<count`, across up to one thread per active core, each
    /// with `stackSize`. Indices are handed out in order; completion order is the scheduler's, so
    /// a caller that needs a result per index must store it per index.
    static func forEach(_ count: Int, _ body: @escaping @Sendable (Int) -> Void) {
        guard count > 0 else { return }
        let next = Counter()
        let group = DispatchGroup()
        for _ in 0..<max(1, min(ProcessInfo.processInfo.activeProcessorCount, count)) {
            group.enter()
            let thread = Thread {
                while let index = next.take(below: count) { body(index) }
                group.leave()
            }
            thread.stackSize = stackSize
            thread.start()
        }
        group.wait()
    }

    /// `body`'s result, computed on one thread with `stackSize`.
    static func run<Result: Sendable>(_ body: @escaping @Sendable () -> Result) -> Result {
        let box = Box<Result>()
        forEach(1) { _ in box.value = body() }
        guard let value = box.value else { preconditionFailure("a large-stack worker returned without running") }
        return value
    }

    /// The next unclaimed index, under a lock.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func take(below limit: Int) -> Int? {
            lock.lock()
            defer { lock.unlock() }
            guard value < limit else { return nil }
            value += 1
            return value - 1
        }
    }

    /// One result, written by the worker and read after `group.wait()` — the group's
    /// happens-before is what makes the unlocked read safe.
    private final class Box<Value>: @unchecked Sendable {
        var value: Value?
    }
}
