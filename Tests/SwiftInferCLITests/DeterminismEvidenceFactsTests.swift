@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// A synthesized determinism law carries the same facts about its subject as every template's (#465).
///
/// `Discover+GenericLaws` built its evidence row by hand, because the templates' shared
/// `inferenceEvidence` was not visible from this module — and the copy kept the display name, the
/// signature and the location and nothing else. With no declaring type, no receiver flag and no
/// isolation, `CalleeReference` had nothing to qualify a call with, and **not one determinism stub
/// for a type member compiled across the corpus funnel census: 33 of 33 that built were free
/// functions.**
@Suite("Determinism evidence keeps its subject's facts")
struct DeterminismEvidenceFactsTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    private static let location = SourceLocation(file: "Tokenizer.swift", line: 54, column: 5)

    private static func summary(isStatic: Bool, globalActor: String? = nil) -> FunctionSummary {
        FunctionSummary(
            name: "tokenizeLine",
            parameters: [Parameter(label: nil, internalName: "line", typeText: "String", isInout: false)],
            returnTypeText: "[Token]",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: location,
            containingTypeName: "Tokenizer",
            bodySignals: .empty,
            qualifiedContainingTypeName: "Editor.Tokenizer",
            globalActor: globalActor
        )
    }

    private static func determinism(for summary: FunctionSummary) throws -> Suggestion {
        let manifest = SeedManifest(seeds: [
            SeedManifest.Seed(file: "Tokenizer.swift", line: 54, symbol: "tokenizeLine", kind: .pureFunction)
        ])
        let laws = SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest,
            summaries: [summary],
            covered: [],
            diagnostics: SilentDiagnostics()
        )
        return try #require(laws.first { $0.templateName == "determinism" })
    }

    /// **The load-bearing assertion.** The row is exactly the one every template builds.
    @Test func theRowIsTheTemplatesOwnEvidence() throws {
        let summary = Self.summary(isStatic: true)
        #expect(try Self.determinism(for: summary).evidence == [summary.inferenceEvidence])
    }

    @Test func aStaticMemberKeepsItsQualifiedDeclaringType() throws {
        let row = try #require(try Self.determinism(for: Self.summary(isStatic: true)).evidence.first)
        #expect(row.qualifiedTypeName == "Editor.Tokenizer")
        #expect(row.isInstanceMethod == false)
    }

    @Test func anInstanceMethodIsMarkedAsOne() throws {
        let row = try #require(try Self.determinism(for: Self.summary(isStatic: false)).evidence.first)
        #expect(row.isInstanceMethod)
    }

    @Test func aDeclaredGlobalActorSurvives() throws {
        let row = try #require(
            try Self.determinism(for: Self.summary(isStatic: true, globalActor: "MainActor")).evidence.first
        )
        #expect(row.globalActor == "MainActor")
    }

    /// **The identity must not move.** The hand-built row's display name and signature were
    /// byte-identical to `inferenceEvidence`'s, so every recorded decision and baseline keyed on a
    /// determinism identity still matches. Pinned to the literal the old copy produced.
    @Test func theIdentityIsUnchanged() throws {
        let law = try Self.determinism(for: Self.summary(isStatic: true))
        #expect(law.identity == SuggestionIdentity(
            canonicalInput: "determinism|Tokenizer.tokenizeLine(_:)|(String) -> [Token]"
        ))
    }
}
