import Foundation
@testable import SwiftInferCLI
import Testing

/// `swift-infer scaffold` pipeline: partially-derivable types get a `gen()`
/// stub with derivable slots filled and the rest as placeholders; fully-
/// derivable / non-scaffoldable corpora yield no file.
struct ScaffoldPipelineTests {

    @Test func scaffoldsPartiallyDerivableType() throws {
        let dir = try makeFixtureDir([
            "Models.swift": """
                struct Doc: Equatable {
                    let id: Int
                    let url: URL
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let outcome = try SwiftInferCommand.Scaffold.scaffold(
            directory: URL(fileURLWithPath: dir),
            diagnostics: SilentDiagnostics()
        )
        let text = try #require(outcome.fileText)
        #expect(outcome.scaffoldedTypeNames.contains("Doc"))
        #expect(text.contains("extension Doc {"))
        #expect(text.contains("Gen<Int>.int()"))            // id derived
        #expect(text.contains("<#Generator<URL>#>"))         // url placeholder
        #expect(text.contains("Doc(id: $0.0, url: $0.1)"))
        #expect(text.contains("import PropertyLawKit"))
    }

    @Test func nestedDerivableTypeIsInlined() throws {
        let dir = try makeFixtureDir([
            "Models.swift": """
                struct Customer: Equatable { let name: String }
                struct Order: Equatable {
                    let id: Int
                    let customer: Customer
                    let token: URL
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let outcome = try SwiftInferCommand.Scaffold.scaffold(
            directory: URL(fileURLWithPath: dir),
            diagnostics: SilentDiagnostics()
        )
        let text = try #require(outcome.fileText)
        // Order is the partial type; Customer resolves and is inlined.
        #expect(text.contains("Customer(name: $0)"))
        #expect(text.contains("<#Generator<URL>#>"))
        // Customer fully derives → not itself scaffolded.
        #expect(outcome.scaffoldedTypeNames.contains("Customer") == false)
    }

    @Test func nothingScaffoldableReturnsNil() throws {
        let dir = try makeFixtureDir([
            "Plain.swift": "struct Point: Equatable { let x: Int; let y: Int }"
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let outcome = try SwiftInferCommand.Scaffold.scaffold(
            directory: URL(fileURLWithPath: dir),
            diagnostics: SilentDiagnostics()
        )
        #expect(outcome.fileText == nil)
    }

    // MARK: - Helpers

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* swallow */ }
    }

    private func makeFixtureDir(_ files: [String: String]) throws -> String {
        let dir = NSTemporaryDirectory().appending("SwiftInferScaffold-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, contents) in files {
            try contents.write(toFile: dir + name, atomically: true, encoding: .utf8)
        }
        return dir
    }
}
