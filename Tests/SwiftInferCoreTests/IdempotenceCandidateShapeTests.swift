import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// The gate that decides whether `idempotenceReturnShape` is computed at all.
///
/// **The failure this suite exists for is an absence.** `returnShapeVeto` returns
/// `nil` both when the shape was never computed and when it was computed and
/// found not to extend its input, so a candidate the scanner declines to classify
/// looks *exactly* like a candidate the classifier cleared. Nothing downstream can
/// tell those apart, which is how `T? -> T` went unvetoed while the template
/// proposed laws for it.
@Suite("IdempotenceCandidateShape — the veto's gate")
struct IdempotenceCandidateShapeTests {

    @Test("the exact endomorphism shape is admitted, as it always was")
    func exactEndomorphismAdmitted() {
        #expect(IdempotenceCandidateShape.admitsIdempotenceLaw(
            parameterType: "String", returnType: "String"
        ))
    }

    /// The regression this whole change is about.
    @Test("the optional-narrowing shape the template proposes for is admitted")
    func optionalNarrowingAdmitted() {
        #expect(IdempotenceCandidateShape.admitsIdempotenceLaw(
            parameterType: "URL?", returnType: "URL"
        ))
        #expect(IdempotenceCandidateShape.admitsIdempotenceLaw(
            parameterType: "Optional<URL>", returnType: "URL"
        ))
    }

    /// Widening the gate must not admit shapes the template cannot propose for —
    /// the classifier would then pay for bodies nothing asks about, and any veto
    /// it produced would suppress a law no one proposed.
    @Test("unrelated and reversed shapes stay out")
    func unrelatedShapesRejected() {
        #expect(!IdempotenceCandidateShape.admitsIdempotenceLaw(
            parameterType: "String", returnType: "Int"
        ))
        // The REVERSE narrowing: `T -> T?` is not what the template admits.
        #expect(!IdempotenceCandidateShape.admitsIdempotenceLaw(
            parameterType: "URL", returnType: "URL?"
        ))
        // Not a suffix-match: `Foo` is not the Optional of `oo`.
        #expect(!IdempotenceCandidateShape.admitsIdempotenceLaw(
            parameterType: "Foo", returnType: "oo"
        ))
    }

    /// End to end through the real scanner, on the shape of the measured witness:
    /// `(URL?) -> URL` whose body appends a path component. Before this change the
    /// shape was `nil` and the law was proposed unvetoed; it ran and refuted.
    @Test("an optional-narrowing body that extends its input is now classified")
    func optionalNarrowingBodyIsClassified() throws {
        let source = """
        struct Fixture {
            static func defaultOutputURL(packageRoot: URL?) -> URL {
                (packageRoot ?? URL(fileURLWithPath: "/tmp"))
                    .appendingPathComponent("Generated/Output.swift")
            }
        }
        """
        let summary = try #require(Self.summarize(source, named: "defaultOutputURL"))
        let shape = try #require(
            summary.bodySignals.idempotenceReturnShape,
            "the gate must compute a shape for T? -> T, or the veto cannot fire"
        )
        guard case let .extendsInput(via) = shape else {
            Issue.record("expected .extendsInput, got \(shape)")
            return
        }
        #expect(via.contains("appendingPathComponent"))
    }

    /// The control: a narrowing body that does NOT extend its input must still
    /// classify as `.notExtending`. Widening the gate is only safe if it does not
    /// turn coalesce-with-default shapes into vetoes.
    @Test("an optional-narrowing body that projects is not vetoed")
    func optionalNarrowingProjectionNotVetoed() throws {
        let source = """
        struct Fixture {
            static func normalized(name: String?) -> String {
                (name ?? "").trimmingCharacters(in: .whitespaces)
            }
        }
        """
        let summary = try #require(Self.summarize(source, named: "normalized"))
        #expect(summary.bodySignals.idempotenceReturnShape == .notExtending)
    }

    private static func summarize(_ source: String, named: String) -> FunctionSummary? {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "Fixture.swift", tree: tree)
        let visitor = FunctionScannerVisitor(file: "Fixture.swift", converter: converter)
        visitor.walk(tree)
        return visitor.summaries.first { $0.name == named }
    }
}
