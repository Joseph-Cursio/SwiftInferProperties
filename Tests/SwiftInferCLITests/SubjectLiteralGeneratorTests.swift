import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// A stub's `String` generator draws the subject's own literals — and nothing moves where there are none.
///
/// Measured before it was built (`docs/plans/subject-literal-generation-scope.md`): these literals
/// refuted 7 of 52 passing behaviour laws as false, and hung a totality law on a real defect.
@Suite("Stub generators draw the subject's own literals")
struct SubjectLiteralGeneratorTests {

    /// A one-function source file, and the directory to remove afterwards.
    private func subjectFile(_ source: String) throws -> (path: String, directory: URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("subject-literals-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Escape.swift")
        try source.write(to: file, atomically: true, encoding: .utf8)
        return (file.path, directory)
    }

    @Test("a String carrier's generator carries the subject's literals")
    func stringCarrierDrawsLiterals() throws {
        let subject = try subjectFile(
            #"func escape(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;") }"#
        )
        defer { try? FileManager.default.removeItem(at: subject.directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "escape", typeName: "String", file: subject.path)
        let generator = InteractiveTriage.chooseGenerator(for: suggestion, typeName: "String")
        #expect(generator == RawType.string.edgeBiasedGeneratorExpression(subjectTokens: ["&", "&amp;"]))
        #expect(generator.contains(#"["&", "&amp;"] as [String]"#))
    }

    /// **Through the closure the accept path always supplies.** The test above passed while the census
    /// moved nothing: the resolver answers `String` with `.notInUniverse`, and the closure rendered the
    /// generator itself — without literals — before `chooseGenerator` could.
    @Test("the literals survive the accept path's own custom-generator closure")
    func literalsSurviveTheCustomGeneratorClosure() throws {
        let subject = try subjectFile(
            #"func escape(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;") }"#
        )
        defer { try? FileManager.default.removeItem(at: subject.directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "escape", typeName: "String", file: subject.path)
        let generator = InteractiveTriage.chooseGenerator(
            for: suggestion,
            typeName: "String",
            customGenerator: InteractiveTriage.projectTypeGenerator(types: [])
        )
        #expect(generator == RawType.string.edgeBiasedGeneratorExpression(subjectTokens: ["&", "&amp;"]))
    }

    /// **The control.** No readable subject — every unit-test fixture — and the generator is exactly
    /// the one every stub emitted before, so no golden moves.
    @Test("with no readable subject the generator is unchanged")
    func unreadableSubjectIsUnchanged() {
        let suggestion = makeIdempotentSuggestion(funcName: "escape", typeName: "String")
        #expect(InteractiveTriage.chooseGenerator(for: suggestion, typeName: "String")
            == RawType.string.edgeBiasedGeneratorExpression)
    }

    @Test("a non-String carrier is not given literals, and its file is not read for them")
    func nonStringCarrierIsUnchanged() throws {
        let subject = try subjectFile(#"func bump(_ n: Int) -> Int { n + "&".count }"#)
        defer { try? FileManager.default.removeItem(at: subject.directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "bump", typeName: "Int", file: subject.path)
        #expect(InteractiveTriage.chooseGenerator(for: suggestion, typeName: "Int")
            == LiftedTestEmitter.defaultGenerator(for: "Int"))
    }

    /// The totality path: the hostile generator with the subject's delimiters. `"#"` is the literal
    /// that hung `RuleDocView.parseBlocks`.
    @Test("the totality generator takes the subject's literals too")
    func hostileDrawsLiterals() {
        #expect(LiftedTestEmitter.hostileGenerator(for: "String", subjectLiterals: ["#"])
            == RawType.string.hostileGeneratorExpression(subjectTokens: ["#"]))
        #expect(LiftedTestEmitter.hostileGenerator(for: "String") == RawType.string.hostileGeneratorExpression)
    }
}
