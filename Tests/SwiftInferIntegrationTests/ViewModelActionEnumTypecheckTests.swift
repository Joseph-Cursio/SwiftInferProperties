import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// #693, end to end: recognize a view model, emit its action enum and dispatcher, and typecheck the class
/// and the emitted source together. Before the fix the `Counter` below emitted `case `add`` beside
/// `case add(x: Int)` and `swiftc` failed with `invalid redeclaration of 'add(x:)'`.
///
/// Tagged `.subprocess` because it runs `swiftc -typecheck` on one file — about a second, no `.build`.
/// `SubprocessBatchCoverageTests.deliberatelyInTheFastPath` records why it runs in the fast path.
@Suite("View model action enum — the emitted source typechecks (#693)", .tags(.subprocess))
struct ViewModelActionEnumTypecheckTests {

    /// A backticked method beside its overload, a keyword method, and one keyword from each family the
    /// hand-written list missed: an access modifier, a declaration modifier, and a metatype member.
    static let source = """
    import Observation

    @Observable
    final class Counter {
        var count = 0
        func `add`() { count += 1 }
        func add(x: Int) { count += x }
        func add(_ x: Int) { count -= x }
        func `repeat`() { count *= 2 }
        func `public`() { count = 0 }
        func `static`() { count = 1 }
        func `Type`() { count = 2 }
    }
    """

    @Test("the recognizer's actions emit an enum and dispatcher swiftc accepts")
    func emittedSourceTypechecks() throws {
        let candidate = try #require(ViewModelDiscoverer.discover(source: Self.source, file: "Counter.swift").first)
        #expect(candidate.actions.count == 7)
        let emitted = ViewModelActionEnumEmitter.emit(typeName: candidate.typeName, actions: candidate.actions)
        #expect(emitted.skipped.isEmpty)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftinfer-693-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Counter.swift")
        try (Self.source + "\n\n" + emitted.source + "\n").write(to: file, atomically: true, encoding: .utf8)

        let (status, output) = try Self.typecheck(file)
        #expect(status == 0, "swiftc rejected the emitted source:\n\(output)\n\n\(emitted.source)")
    }

    static func typecheck(_ file: URL) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swiftc", "-typecheck", file.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }
}
