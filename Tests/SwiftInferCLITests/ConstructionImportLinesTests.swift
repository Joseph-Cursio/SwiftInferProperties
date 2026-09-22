@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Which harvested imports a stub gets: only a used construction's, and never a module it already has.
@Suite("Construction imports — what a stub adds")
struct ConstructionImportLinesTests {

    private static let visitor = ReceiverConstructionHarvester.Harvested(
        expression: "UnsafeMemoryAPIVisitor(pattern: SyntaxPattern(name: .unsafe))",
        imports: [
            "import SwiftParser",
            "import SwiftProjectLintVisitors",
            "import SwiftProjectLintRules",
            "import Testing",
            "import XCTest"
        ]
    )
    private static let unused = ReceiverConstructionHarvester.Harvested(
        expression: "OtherVisitor()",
        imports: ["import SomethingElse"]
    )

    @Test("a used construction's imports are added, skipping modules the stub already imports")
    func usedConstructionAddsItsImports() {
        let stub = "property: { value in _ = UnsafeMemoryAPIVisitor(pattern: SyntaxPattern(name: .unsafe)) }"
        let lines = InteractiveTriage.constructionImportLines(
            usedIn: stub,
            constructions: [Self.visitor, Self.unused],
            alreadyImported: ["Foundation", "PropertyLawKit", "SwiftProjectLintRules"]
        )
        // `SwiftProjectLintRules` is already `@testable` imported by the stub, and the test
        // frameworks are excluded; the unused construction contributes nothing.
        #expect(lines == "import SwiftParser\nimport SwiftProjectLintVisitors\n")
    }

    @Test("a stub that uses no construction gets nothing")
    func noConstructionNoImports() {
        #expect(InteractiveTriage.constructionImportLines(
            usedIn: "property: { value in f(value) }",
            constructions: [Self.visitor],
            alreadyImported: []
        ).isEmpty)
    }

    /// **The guard the first census A/B made necessary.** A test file imports what only a test
    /// target can see — the root package's `Core`, `ViewInspector` — and carrying those into a stub
    /// took one package from 230 compiles to 0. Only modules the package builds with survive.
    @Test("only imports of modules the package builds with survive")
    func testOnlyImportsAreDropped() {
        let harvested = ReceiverConstructionHarvester.Harvested(
            expression: "Visitor()",
            imports: [
                "@testable import Core",
                "import ViewInspector",
                "import SwiftProjectLintVisitors",
                "@testable import SwiftLintRuleStudioCoreTestSupport"
            ]
        )
        let kept = ReceiverConstructionSource.keepingResolvable(
            harvested,
            in: ["SwiftProjectLintVisitors", "SwiftLintRuleStudioCoreTestSupport", "SwiftSyntax"]
        )
        #expect(kept.imports == [
            "import SwiftProjectLintVisitors",
            "@testable import SwiftLintRuleStudioCoreTestSupport"
        ])
        #expect(ReceiverConstructionSource.keepingResolvable(harvested, in: []).imports.isEmpty)
    }

    @Test("the module is read past attributes and import kinds")
    func moduleNames() {
        #expect(InteractiveTriage.importedModule(in: "import SwiftParser") == "SwiftParser")
        #expect(InteractiveTriage.importedModule(in: "@testable import MyKit") == "MyKit")
        #expect(InteractiveTriage.importedModule(in: "@_spi(Test) @testable import MyKit") == "MyKit")
        #expect(InteractiveTriage.importedModule(in: "import struct SwiftParser.Parser") == "SwiftParser")
        #expect(InteractiveTriage.importedModule(in: "// import Nothing") == nil)
    }
}
