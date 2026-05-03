import Foundation
import Testing
@testable import SwiftInferCLI

@Suite("Discover pipeline — contradiction detection (M3.4)")
struct DiscoverPipelineContradictionTests {

    @Test("Commutativity contradiction emits byte-stable stderr diagnostic")
    func commutativityContradictionEmitsByteStableDiagnostic() throws {
        // Single fixture line so the column/line positions are pinned.
        let directory = try writeDPFixture(name: "ContradictionCommGolden", contents: """
        struct AnyMixer {
            func merge(_ first: Any, _ second: Any) -> Any { return first }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording,
            diagnostics: diagnostics
        )
        let normalized = normalizeDPDiagnostics(diagnostics.lines, fixture: directory)
        let expected = [
            "contradiction: dropped commutativity suggestion for merge(_:_:)"
                + " at <FIXTURE>/Source.swift:2 — type 'Any' is not Equatable (PRD §5.6 #2)"
        ]
        #expect(normalized == expected)
    }

    @Test("Round-trip contradiction emits byte-stable stderr diagnostic")
    func roundTripContradictionEmitsByteStableDiagnostic() throws {
        // wrap on line 2, unwrap on line 3 — wrap is the canonical
        // forward (sorted by file/line), so the diagnostic anchors there.
        let directory = try writeDPFixture(name: "ContradictionRTGolden", contents: """
        struct Wrapper {
            func wrap(_ closure: (Int) -> Int) -> Data { return Data() }
            func unwrap(_ raw: Data) -> (Int) -> Int { return { value in value } }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording,
            diagnostics: diagnostics
        )
        let normalized = normalizeDPDiagnostics(diagnostics.lines, fixture: directory)
        let expected = [
            "contradiction: dropped round-trip suggestion for wrap(_:)"
                + " at <FIXTURE>/Source.swift:2 — type '(Int) -> Int' is not Equatable (PRD §5.6 #3)"
        ]
        #expect(normalized == expected)
    }

    @Test("Contradiction-dropped commutativity suggestion is elided from stdout")
    func contradictionDroppedSuggestionIsElidedFromStdout() throws {
        // `combineAny` isn't in any curated naming list — both
        // commutativity and associativity score 30 (just type-symmetry)
        // → Possible. Default flags hide Possible-tier output.
        let directory = try writeDPFixture(name: "ContradictionElide", contents: """
        struct AnyMixer {
            func combineAny(_ first: Any, _ second: Any) -> Any { return first }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text == "0 suggestions.")
        #expect(diagnostics.lines.count == 1)
        #expect(diagnostics.lines.first?.contains("commutativity") == true)
    }

    @Test("Contradiction drop only elides the offending template — sibling templates over the same function survive")
    func contradictionDropPreservesUnrelatedSiblingTemplates() throws {
        // `merge` matches both commutativity and associativity. The
        // §5.6 #2 contradiction layer drops *only* commutativity.
        let directory = try writeDPFixture(name: "ContradictionMixed", contents: """
        struct Mix {
            func normalize(_ value: String) -> String { return normalize(normalize(value)) }
            func merge(_ first: Any, _ second: Any) -> Any { return first }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(recording.text.contains("2 suggestions."))
        #expect(recording.text.contains("Template: idempotence"))
        #expect(recording.text.contains("Template: associativity"))
        #expect(!recording.text.contains("Template: commutativity"))
        #expect(diagnostics.lines.count == 1)
        #expect(diagnostics.lines.first?.contains("commutativity") == true)
    }
}

@Suite("Discover pipeline — generator selection (M4.2) CLI integration")
struct DiscoverPipelineGeneratorTests {

    @Test("CLI surfaces .derivedMemberwise generator line for struct-typed property")
    func cliRendersDerivedMemberwiseGenerator() throws {
        let directory = try writeDPFixture(name: "GenSelectMemberwiseCLI", contents: """
        struct Money {
            let amount: Int
            let currency: String
        }
        struct Sanitizer {
            func normalize(_ value: Money) -> Money {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording
        )
        #expect(recording.text.contains("Generator: .derivedMemberwise, confidence: .medium"))
        #expect(recording.text.contains("Sampling:  not run; lifted test seed: 0x"))
    }

    @Test("CLI surfaces .derivedCaseIterable generator line for enum: CaseIterable property")
    func cliRendersDerivedCaseIterableGenerator() throws {
        let directory = try writeDPFixture(name: "GenSelectCaseIterCLI", contents: """
        enum Side: CaseIterable {
            case left, right
        }
        struct Helpers {
            func normalize(_ value: Side) -> Side {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording
        )
        #expect(recording.text.contains("Generator: .derivedCaseIterable, confidence: .high"))
    }

    @Test("CLI surfaces .derivedRawRepresentable generator line for raw-value enum property")
    func cliRendersDerivedRawRepresentableGenerator() throws {
        let directory = try writeDPFixture(name: "GenSelectRawRepCLI", contents: """
        enum StatusCode: Int {
            case ok = 200, notFound = 404
        }
        struct Helpers {
            func normalize(_ value: StatusCode) -> StatusCode {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording
        )
        #expect(recording.text.contains("Generator: .derivedRawRepresentable, confidence: .high"))
    }

    @Test("CLI surfaces .registered generator line for static gen() property")
    func cliRendersRegisteredGenerator() throws {
        let directory = try writeDPFixture(name: "GenSelectUserGenCLI", contents: """
        struct Widget {
            let id: Int
            static func gen() -> Int { 0 }
        }
        struct Helpers {
            func normalize(_ value: Widget) -> Widget {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording
        )
        #expect(recording.text.contains("Generator: .registered, confidence: .high"))
    }

    @Test("CLI surfaces .todo generator line (no confidence) for class-typed property")
    func cliRendersTodoGenerator() throws {
        let directory = try writeDPFixture(name: "GenSelectTodoCLI", contents: """
        class Logger {
            let prefix: String = ""
        }
        struct Helpers {
            func normalize(_ value: Logger) -> Logger {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: recording
        )
        #expect(recording.text.contains("Generator: .todo"))
        // .todo carries nil confidence — the renderer omits the
        // confidence fragment in that case.
        #expect(!recording.text.contains("Generator: .todo, confidence:"))
    }
}
