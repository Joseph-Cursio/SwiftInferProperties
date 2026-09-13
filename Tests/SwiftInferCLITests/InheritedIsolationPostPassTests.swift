import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The post-pass that fills in `Evidence.globalActor` from a conformance the per-file scan could
/// not resolve (SwiftInferProperties#440).
///
/// **Isolation arrives two ways and the scanner only ever saw one.** An `@MainActor` attribute on
/// the enclosing type is lexically present in the file being scanned, so
/// `FunctionScannerVisitor+AccessRestriction` reads it off the declaration stack. Isolation
/// *inherited* from a protocol is not in that file at all — `struct SearchResultRow: View` says
/// `View`, and what makes it main-actor is a declaration in SwiftUI. Resolving it needs the whole
/// project's type graph, which exists only after every file has been scanned, so this runs as a
/// pass over assembled suggestions rather than inside the visitor.
///
/// Measured on SwiftMarkdownWiki: stubs carrying an actor hop went **3 → 6**. The three it found
/// are `SearchResultRow` and `PluginLogPanelView` (both `: View`) and `KaTeXSchemeHandler`
/// (`: NSObject, WKURLSchemeHandler`); the pre-existing three carry the attribute directly.
@Suite("Discover — isolation inherited through a conformance")
struct InheritedIsolationPostPassTests {

    private static func decl(_ name: String, _ kind: TypeDecl.Kind, _ inherits: [String]) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: kind,
            inheritedTypes: inherits,
            location: SourceLocation(file: "F.swift", line: 1, column: 1)
        )
    }

    private static func suggestion(
        carrier: String?,
        globalActor: String? = nil
    ) -> Suggestion {
        Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "stripMarkTags(_:)",
                    signature: "(String) -> String",
                    location: SourceLocation(file: "F.swift", line: 4, column: 1),
                    qualifiedTypeName: carrier,
                    globalActor: globalActor
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "F.swift::stripMarkTags")
        )
    }

    private static func actor(of suggestion: Suggestion) -> String? {
        suggestion.evidence.first?.globalActor
    }

    /// The measured shape, reduced: a `View` conformer whose file names no actor anywhere.
    @Test("A View conformer gains MainActor the scanner could not see")
    func viewConformerGainsTheActor() {
        let result = SwiftInferCommand.Discover.withInheritedIsolation(
            [Self.suggestion(carrier: "SearchResultRow")],
            typeDecls: [Self.decl("SearchResultRow", .struct, ["View"])]
        )
        #expect(Self.actor(of: result[0]) == "MainActor")
    }

    /// **The load-bearing negative.** A pass that stamped `MainActor` on everything would satisfy
    /// the test above and emit `await MainActor.run { … }` around calls into types that are not
    /// isolated — breaking stubs that compile today. That is the expensive direction, so an
    /// unrelated carrier must come back untouched.
    @Test("A carrier with no route to a main-actor protocol is left alone")
    func unrelatedCarrierIsUntouched() {
        let result = SwiftInferCommand.Discover.withInheritedIsolation(
            [Self.suggestion(carrier: "FrontMatter")],
            typeDecls: [Self.decl("FrontMatter", .struct, ["Equatable", "Sendable"])]
        )
        #expect(Self.actor(of: result[0]) == nil)
    }

    /// An actor already read off an attribute is knowledge from the file itself. This pass has
    /// strictly less context, so it must not overwrite what the scanner established.
    @Test("An actor the scanner already recorded is preserved")
    func existingActorIsNotOverwritten() {
        let result = SwiftInferCommand.Discover.withInheritedIsolation(
            [Self.suggestion(carrier: "Formatter", globalActor: "DataActor")],
            typeDecls: [Self.decl("Formatter", .struct, ["View"])]
        )
        #expect(Self.actor(of: result[0]) == "DataActor")
    }

    /// Free functions and lifted tests carry no carrier at all. There is nothing to resolve and
    /// nothing to blame, so the row passes through.
    @Test("Evidence with no carrier passes through")
    func noCarrierPassesThrough() {
        let result = SwiftInferCommand.Discover.withInheritedIsolation(
            [Self.suggestion(carrier: nil)],
            typeDecls: [Self.decl("SearchResultRow", .struct, ["View"])]
        )
        #expect(Self.actor(of: result[0]) == nil)
    }

    /// Evidence records the full lexical path; `TypeDecl` records the declaration's own name. A
    /// pass comparing them verbatim would resolve nothing for any nested type.
    @Test("A nested carrier resolves on its leaf name")
    func nestedCarrierResolvesOnItsLeaf() {
        let result = SwiftInferCommand.Discover.withInheritedIsolation(
            [Self.suggestion(carrier: "SearchPane.ResultRow")],
            typeDecls: [Self.decl("ResultRow", .struct, ["View"])]
        )
        #expect(Self.actor(of: result[0]) == "MainActor")
    }

    /// Isolation reaching a carrier through a project-declared refinement — the case the fixed
    /// point exists for, exercised end-to-end through the pass rather than only at the unit.
    @Test("Isolation reaches a carrier through a project-declared protocol")
    func projectProtocolCarriesIsolationThrough() {
        let result = SwiftInferCommand.Discover.withInheritedIsolation(
            [Self.suggestion(carrier: "EditorPane")],
            typeDecls: [
                Self.decl("Pane", .protocol, ["View"]),
                Self.decl("EditorPane", .struct, ["Pane"])
            ]
        )
        #expect(Self.actor(of: result[0]) == "MainActor")
    }

    /// **Every other test in this suite calls the pass directly, so deleting the call from
    /// `makePipelineResult` would leave all of them green.** The corpus measurement that
    /// justified this change (3 → 6 hops) ran the whole pipeline, and nothing but this assertion
    /// keeps that wiring from being quietly removed. Source-level because the alternative —
    /// `makePipelineResult`'s five fixture types — is a great deal of scaffolding to state one
    /// fact, and the fact is a property of the source text.
    @Test("The pass is wired into the pipeline")
    func thePassIsWiredIntoThePipeline() throws {
        let assembly = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SwiftInferCLI/Discover+PipelineAssembly.swift")
        let source = try String(contentsOf: assembly, encoding: .utf8)
        #expect(source.contains("withInheritedIsolation("))
    }

    @Test("An empty project changes nothing")
    func emptyProjectChangesNothing() {
        let input = [Self.suggestion(carrier: "SearchResultRow")]
        #expect(Self.actor(of: SwiftInferCommand.Discover.withInheritedIsolation(input, typeDecls: [])[0]) == nil)
    }
}
