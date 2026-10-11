import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `==` the scan can SEE, but that no inheritance clause declares, lets a determinism stub through
/// — end to end, through `discover --interactive --dry-run` with a seed and a scripted accept, so
/// the evidence travels the way a real run carries it (scan → `PipelineResult` → accept context).
///
/// Both exhibits compile (`swiftc`, Swift 6.4): a type with a hand-written `static func ==` and no
/// `Equatable`, which operator lookup finds; and a SwiftData `@Model` class, whose macro conforms
/// it to `PersistentModel`, which refines `Hashable`. The gate used to decline both, because no
/// inheritance clause in the scan reaches `Equatable`.
@Suite("Determinism — `==` outside an inheritance clause, through discover")
struct DeterminismResultEqualityDiscoverTests {

    struct Run {
        let output: String
        let diagnostics: [String]
    }

    /// Accept the seeded determinism law for `symbol`, declared on `line` of `source`, in a dry run.
    static func accept(_ source: String, symbol: String, line: Int) throws -> Run {
        let directory = try writeDPFixture(name: "ResultEquality-\(symbol)", contents: source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = TriageRecordingOutput()
        let diagnostics = TriageRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            dryRun: true,
            interactive: true,
            seedManifest: SeedManifest(seeds: [
                SeedManifest.Seed(file: "Source.swift", line: line, symbol: symbol, kind: .pureFunction)
            ]),
            promptInput: TriageRecordingPromptInput(scriptedLines: ["A"]),
            output: output,
            diagnostics: diagnostics
        )
        return Run(output: output.text, diagnostics: diagnostics.lines)
    }

    static let handWritten = """
        struct Reading {
            let value: Int

            static func == (lhs: Reading, rhs: Reading) -> Bool { lhs.value == rhs.value }
        }

        enum Meter {
            static func read(_ raw: Int) -> Reading { Reading(value: raw) }
        }
        """

    static let macroAttached = """
        @Model
        final class Item {
            var name: String
            init(name: String) { self.name = name }
        }

        enum Factory {
            static func make(_ name: String) -> Item { Item(name: name) }
        }
        """

    @Test func aHandWrittenEqualityOperatorLetsTheStubThrough() throws {
        let run = try Self.accept(Self.handWritten, symbol: "read", line: 8)
        #expect(run.output.contains("would write"), "accept wrote nothing:\n\(run.diagnostics.joined(separator: "\n"))")
        #expect(run.output.contains("SwiftInfer/determinism/MeterReadDeterminismTests.swift"))
        #expect(run.diagnostics.contains { $0.contains("no stub written") } == false)
    }

    @Test func anAttachedMacroLetsTheStubThrough() throws {
        let run = try Self.accept(Self.macroAttached, symbol: "make", line: 8)
        #expect(run.output.contains("would write"), "accept wrote nothing:\n\(run.diagnostics.joined(separator: "\n"))")
        #expect(run.output.contains("SwiftInfer/determinism/FactoryMakeDeterminismTests.swift"))
        #expect(run.diagnostics.contains { $0.contains("no stub written") } == false)
    }

    /// The controls: the same run reaches the gate, and an attribute that adds no conformance is
    /// not read as one.
    @Test("a result with no == anywhere is still declined", arguments: [
        "", "@MainActor\n", "@available(macOS 14, *)\n"
    ])
    func aResultWithNoEqualityIsStillDeclined(attribute: String) throws {
        let source = """
            \(attribute)struct Plain {
                let value: Int
            }

            enum Maker {
                static func make(_ raw: Int) -> Plain { Plain(value: raw) }
            }
            """
        let line = attribute.isEmpty ? 6 : 7
        let run = try Self.accept(source, symbol: "make", line: line)
        #expect(run.output.contains("would write") == false)
        #expect(run.diagnostics.contains {
            $0.contains("make(_:) returns Plain, and no scanned declaration makes Plain Equatable")
        })
    }
}
