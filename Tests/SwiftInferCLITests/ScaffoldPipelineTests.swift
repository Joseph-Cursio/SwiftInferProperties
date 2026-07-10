import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
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
                    let widget: Widget
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
        #expect(text.contains("<#Generator<Widget>#>"))      // widget placeholder
        #expect(text.contains("Doc(id: $0.0, widget: $0.1)"))
        #expect(text.contains("import PropertyLawKit"))
    }

    @Test func nestedDerivableTypeIsInlined() throws {
        let dir = try makeFixtureDir([
            "Models.swift": """
                struct Customer: Equatable { let name: String }
                struct Order: Equatable {
                    let id: Int
                    let customer: Customer
                    let token: Widget
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
        #expect(text.contains("<#Generator<Widget>#>"))
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

    // MARK: - Increment C: user-init structs + payload enums scaffold

    @Test func userInitStructScaffoldsThroughItsInitializer() throws {
        let dir = try makeFixtureDir([
            "Money.swift": """
                struct Money: Equatable {
                    let amount: Int
                    let ref: Widget
                    init(amount: Int, ref: Widget) {
                        self.amount = amount
                        self.ref = ref
                    }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let outcome = try SwiftInferCommand.Scaffold.scaffold(
            directory: URL(fileURLWithPath: dir),
            diagnostics: SilentDiagnostics()
        )
        let text = try #require(outcome.fileText)
        // Lifted through the user init (was non-scaffoldable before Increment C).
        #expect(text.contains("Money(amount: $0.0, ref: $0.1)"))
        #expect(text.contains("Gen<Int>.int()"))
        #expect(text.contains("<#Generator<Widget>#>"))
    }

    @Test func payloadEnumScaffoldsViaOneOf() throws {
        let dir = try makeFixtureDir([
            "Shape.swift": """
                enum Shape: Equatable {
                    case empty
                    case circle(radius: Int)
                    case tagged(Widget)
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let outcome = try SwiftInferCommand.Scaffold.scaffold(
            directory: URL(fileURLWithPath: dir),
            diagnostics: SilentDiagnostics()
        )
        let text = try #require(outcome.fileText)
        #expect(text.contains("Gen.oneOf("))
        #expect(text.contains("Gen.always(Shape.empty)"))
        #expect(text.contains("Shape.circle(radius: $0)"))
        #expect(text.contains("<#Generator<Widget>#>"))   // tagged(Widget) hole
    }

    // MARK: - Evidence-based hole-filling (renderer)

    @Test func evidenceGeneratorRendersSingleArgConstruction() {
        let mock = MockGenerator(
            typeName: "Customer",
            argumentSpec: [.init(label: "name", swiftTypeName: "String", observedLiterals: [])],
            siteCount: 3
        )
        #expect(
            SwiftInferCommand.Scaffold.evidenceGenerator(for: mock)
                == "Gen<Character>.letterOrNumber.string(of: 0...8).map { Customer(name: $0) }"
        )
    }

    @Test func evidenceGeneratorAppliesPreconditionRefinement() {
        let mock = MockGenerator(
            typeName: "Page",
            argumentSpec: [.init(label: "index", swiftTypeName: "Int", observedLiterals: [])],
            siteCount: 3,
            preconditionHints: [
                PreconditionHint(
                    position: 0, argumentLabel: "index",
                    pattern: .intRange(low: 1, high: 10),
                    siteCount: 3, suggestedGenerator: "Gen.int(in: 1...10)"
                )
            ]
        )
        // The observed bound refines the leaf instead of the default int gen.
        #expect(
            SwiftInferCommand.Scaffold.evidenceGenerator(for: mock)
                == "Gen.int(in: 1...10).map { Page(index: $0) }"
        )
    }

    @Test func evidenceGeneratorZipsMultipleArguments() {
        let mock = MockGenerator(
            typeName: "Pair",
            argumentSpec: [
                .init(label: "a", swiftTypeName: "Int", observedLiterals: []),
                .init(label: "b", swiftTypeName: "Bool", observedLiterals: [])
            ],
            siteCount: 3
        )
        #expect(
            SwiftInferCommand.Scaffold.evidenceGenerator(for: mock)
                == "zip(Gen<Int>.int(), Gen<Bool>.bool()).map { Pair(a: $0.0, b: $0.1) }"
        )
    }

    // MARK: - Broader evidence reach (no suggestion required)

    @Test func evidenceFromTestsFillsHoleForNonSuggestionType() throws {
        let root = NSTemporaryDirectory().appending("SIScaffoldEvidence-\(UUID().uuidString)/")
        let sources = root + "Sources/"
        let tests = root + "Tests/"
        try FileManager.default.createDirectory(atPath: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: tests, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        // Box is a class (structurally non-derivable) with no property
        // suggestion — only test evidence knows how to build it.
        try """
            final class Box: Equatable {
                let value: Int
                init(value: Int) { self.value = value }
                static func == (lhs: Box, rhs: Box) -> Bool { lhs.value == rhs.value }
            }
            struct Order: Equatable {
                let id: Int
                let box: Box
                let ref: Widget
            }
            """.write(toFile: sources + "Models.swift", atomically: true, encoding: .utf8)
        try """
            import Testing
            struct BoxTests {
                @Test func a() { _ = Box(value: 1) }
                @Test func b() { _ = Box(value: 2) }
                @Test func c() { _ = Box(value: 3) }
            }
            """.write(toFile: tests + "BoxTests.swift", atomically: true, encoding: .utf8)

        let outcome = try SwiftInferCommand.Scaffold.scaffold(
            directory: URL(fileURLWithPath: sources),
            testDirectory: URL(fileURLWithPath: tests),
            diagnostics: SilentDiagnostics()
        )
        let text = try #require(outcome.fileText)
        #expect(outcome.scaffoldedTypeNames.contains("Order"))
        #expect(text.contains("Box(value: $0)"))         // hole filled from test evidence
        #expect(text.contains("<#Generator<Widget>#>"))  // ref remains a placeholder
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
