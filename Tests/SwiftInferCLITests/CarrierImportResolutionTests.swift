import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **A stub must import every module its carrier reaches, not only the subject's own** (#492).
///
/// `@testable import` does not re-export, so a derived generator that names a stored member's
/// type declared in a sibling target produces `cannot find type 'X' in scope` — an error naming a
/// TYPE, which does not read as an import problem.
///
/// The corpus funnel re-run measured **666 stubs failing exactly this way**, against the 308 the
/// 2026-09-14 census recorded as a floor, and `predicate` (338) outnumbers `determinism` (304) —
/// so it was never determinism-only. This covers the share that needs no manifest change: a type
/// declared in another target of the SAME package.
@Suite("Discover stubs — carrier imports")
struct CarrierImportResolutionTests {

    /// A real package layout on disk, because `VerifyTargetInference` confirms a module name
    /// against the filesystem rather than trusting the path — *"a name parsed out of a path is a
    /// guess until something on disk agrees with it."* A synthetic `/pkg` resolves to nothing, so
    /// a fixture that used one would assert the resolver's silence rather than its answer.
    private static let packageRoot: URL = {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("carrier-imports-" + UUID().uuidString)
        let layout = [
            "Models": ["Report.swift", "Issue.swift"],
            "Engine": ["Checker.swift"]
        ]
        for (module, files) in layout {
            let directory = root.appendingPathComponent("Sources/\(module)")
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            for file in files {
                try? Data().write(to: directory.appendingPathComponent(file))
            }
        }
        return root
    }()

    /// `Report` lives in `Models`; the subject lives in `Engine`. A generator for `Report` names
    /// `Issue`, which is in `Models` too, so one import answers both.
    private static func shapes() -> [String: TypeShape] {
        [
            "Report": TypeShape(
                name: "Report",
                kind: .struct,
                inheritedTypes: [],
                hasUserGen: false,
                storedMembers: [StoredMember(name: "issue", typeName: "Issue")]
            ),
            "Issue": TypeShape(
                name: "Issue",
                kind: .struct,
                inheritedTypes: [],
                hasUserGen: false,
                storedMembers: [StoredMember(name: "text", typeName: "String")]
            )
        ]
    }

    private static var sourceFiles: [String: String] {
        [
            "Report": packageRoot.appendingPathComponent("Sources/Models/Report.swift").path,
            "Issue": packageRoot.appendingPathComponent("Sources/Models/Issue.swift").path
        ]
    }

    private func suggestion(carrier: String) -> Suggestion {
        Suggestion(
            templateName: "predicate",
            evidence: [
                Evidence(
                    displayName: "isClean(_:)",
                    signature: "isClean(_ report: Report) -> Bool",
                    location: SourceLocation(
                        file: Self.packageRoot
                            .appendingPathComponent("Sources/Engine/Checker.swift").path,
                        line: 3,
                        column: 1
                    )
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "predicate|Checker|isClean"),
            carrier: carrier,
            carrierTypeName: carrier
        )
    }

    private func imports(carrier: String, entry: String?) -> String {
        InteractiveTriage.carrierImportLines(
            for: suggestion(carrier: carrier),
            entryModule: entry,
            resolving: InteractiveTriage.CarrierImports(
                typeShapesByName: Self.shapes(),
                sourceFileByTypeName: Self.sourceFiles,
                packageRoot: Self.packageRoot
            )
        )
    }

    @Test("a carrier declared in a sibling target is imported")
    func siblingTargetIsImported() {
        #expect(imports(carrier: "Report", entry: "Engine") == "@testable import Models\n")
    }

    @Test("the entry module is not imported twice")
    func entryModuleIsNotRepeated() {
        // `moduleImport` already emits the subject's own module on its own line, so repeating it
        // here would put two identical `@testable import` lines in the file.
        #expect(!imports(carrier: "Report", entry: "Models").contains("import Models"))
    }

    @Test("a carrier reaching nothing outside its own module adds no import")
    func noExtraImportWhenEverythingIsLocal() {
        #expect(imports(carrier: "Issue", entry: "Models").isEmpty)
    }

    /// ⚠ **The share this change deliberately does not claim.** 507 of the 666 name a type from a
    /// package DEPENDENCY — `Syntax`, `ExprSyntax`, `FunctionCallExprSyntax` — which resolves to
    /// no scanned file and so to no module. Importing it would need a `.package` and product edge
    /// the stub's manifest does not have, so emitting the import would trade one build failure
    /// for another. It stays skipped, exactly as in verify.
    @Test("a dependency's type resolves to no module and is left alone")
    func dependencyTypeIsNotImported() {
        let withDependency = Self.shapes().merging([
            "Node": TypeShape(
                name: "Node",
                kind: .struct,
                inheritedTypes: [],
                hasUserGen: false,
                storedMembers: [StoredMember(name: "syntax", typeName: "ExprSyntax")]
            )
        ]) { first, _ in first }
        let line = InteractiveTriage.carrierImportLines(
            for: suggestion(carrier: "Node"),
            entryModule: "Engine",
            resolving: InteractiveTriage.CarrierImports(
                typeShapesByName: withDependency,
                // `ExprSyntax` is in a checkout, so no scanned declaration claims it.
                sourceFileByTypeName: Self.sourceFiles,
                packageRoot: Self.packageRoot
            )
        )
        #expect(!line.contains("ExprSyntax"))
        #expect(!line.contains("SwiftSyntax"))
    }

    @Test("no resolution context means the stub emits what it always did")
    func noContextIsUnchanged() {
        #expect(InteractiveTriage.carrierImportLines(
            for: suggestion(carrier: "Report"), entryModule: "Engine", resolving: nil
        ).isEmpty)
    }
}
