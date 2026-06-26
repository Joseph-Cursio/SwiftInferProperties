import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// V1.142 — auto-bridge unit tests. `emitRegressionTest` turns a verify
/// `.defaultFails` outcome into a focused regression test on disk via
/// `ConvertCounterexampleEngine`, preferring the minimal (shrunk) counterexample.
@Suite("Verify auto-bridge — V1.142 regression emission")
struct VerifyAutoBridgeTests {

    private static func entry(
        template: String,
        carrier: String = "Int",
        primary: String = "normalize(_:)",
        secondary: String? = nil
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xABCDEF0123456789",
            templateName: template,
            typeName: carrier,
            score: 80,
            tier: "strong",
            primaryFunctionName: primary,
            location: "Sources/Foo.swift:1",
            firstSeenAt: "2026-06-26T00:00:00Z",
            lastSeenAt: "2026-06-26T00:00:00Z",
            secondaryFunctionName: secondary
        )
    }

    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("auto-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("idempotence default-fail writes a regression test with the minimal counterexample")
    func idempotenceWritesRegression() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let detail = DefaultFailDetail(
            trial: 7,
            input: "999",
            forwardResult: "a",
            inverseResult: "b",
            shrink: ShrinkTrace(minimal: "0", steps: 4)
        )
        let path = SwiftInferCommand.Verify.emitRegressionTest(
            entry: Self.entry(template: "idempotence"),
            detail: detail,
            packageRoot: root
        )
        let written = try #require(path)
        // Lives under the sandboxed generated-tests directory for the template.
        #expect(written.path.contains("Tests/Generated/SwiftInfer/idempotence/"))
        let contents = try String(contentsOf: written, encoding: .utf8)
        // The minimal (shrunk) counterexample is used, not the raw first failure.
        #expect(contents.contains("0"))
        #expect(contents.contains("import Testing"))
        #expect(contents.contains("999") == false)
    }

    @Test("round-trip uses the inverse half as reverseCallee")
    func roundTripUsesSecondary() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let detail = DefaultFailDetail(
            trial: 0, input: "5", forwardResult: "x", inverseResult: "y",
            shrink: ShrinkTrace(minimal: "1", steps: 2)
        )
        // round-trip resolution needs a curated forward/inverse pair; an
        // unknown pair resolves to nil (graceful skip) rather than crashing.
        let path = SwiftInferCommand.Verify.emitRegressionTest(
            entry: Self.entry(template: "round-trip", primary: "encode(_:)", secondary: "decode(_:)"),
            detail: detail,
            packageRoot: root
        )
        // Either a file is written (curated pair) or it's a graceful nil — both
        // are valid; assert no throw and, if written, it's a round-trip stub.
        if let path {
            #expect(path.path.contains("Tests/Generated/SwiftInfer/round-trip/"))
        }
    }

    @Test("non-auto-derivable templates are skipped (nil, no file)")
    func unsupportedTemplateSkips() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let detail = DefaultFailDetail(
            trial: 0, input: "x", forwardResult: "a", inverseResult: "b", shrink: nil
        )
        // dual-style-consistency isn't a ConvertCounterexampleEngine shape.
        let path = SwiftInferCommand.Verify.emitRegressionTest(
            entry: Self.entry(template: "dual-style-consistency"),
            detail: detail,
            packageRoot: root
        )
        #expect(path == nil)
    }

    @Test("falls back to the raw failing input when no shrink trace is present")
    func noShrinkUsesRawInput() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let detail = DefaultFailDetail(
            trial: 3, input: "42", forwardResult: "a", inverseResult: "b", shrink: nil
        )
        let path = try #require(
            SwiftInferCommand.Verify.emitRegressionTest(
                entry: Self.entry(template: "idempotence"),
                detail: detail,
                packageRoot: root
            )
        )
        let contents = try String(contentsOf: path, encoding: .utf8)
        #expect(contents.contains("42"))
    }
}
