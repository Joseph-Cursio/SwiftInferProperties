@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A construction reaching a type through an import the stub cannot make gets the import of the
/// module that declares it — when the destination can import that module, and it is unambiguous.
@Suite("Declaring-module imports for copied constructions")
struct DeclaringModuleImportTests {

    private static let harvested = ReceiverConstructionHarvester.Harvested(
        expression: "UIVisitor(pattern: SyntaxPattern(category: PatternCategory.uiPatterns))",
        imports: ["@testable import Core", "import SwiftSyntax"]
    )

    private static let declaring: [String: Set<String>] = [
        "SyntaxPattern": ["SwiftProjectLintVisitors"],
        "PatternCategory": ["SwiftProjectLintModels"],
        "UIVisitor": ["SwiftProjectLintRules"],
        "Ambiguous": ["A", "B"]
    ]

    @Test("each named type's resolvable declaring module is imported, and the rest survive the filter")
    func declaringModulesAreImported() {
        let resolvable: Set<String> = ["SwiftProjectLintVisitors", "SwiftProjectLintModels", "SwiftSyntax"]
        let widened = ReceiverConstructionSource.addingDeclaringImports(
            Self.harvested, declaring: Self.declaring, in: resolvable
        )
        let kept = ReceiverConstructionSource.keepingResolvable(widened, in: resolvable)
        #expect(kept.imports == [
            "import SwiftSyntax", "import SwiftProjectLintModels", "import SwiftProjectLintVisitors"
        ])
    }

    @Test("a name declared in two modules gets no import")
    func ambiguousNameIsLeftAlone() {
        let harvested = ReceiverConstructionHarvester.Harvested(expression: "Ambiguous()", imports: [])
        let widened = ReceiverConstructionSource.addingDeclaringImports(
            harvested, declaring: Self.declaring, in: ["A", "B"]
        )
        #expect(widened.imports.isEmpty)
    }

    @Test("declarations are read by keyword, capitalised names only")
    func declaredNamesAreRead() {
        let text = "public struct SyntaxPattern {}\nenum PatternCategory { case a }\nlet value = 1\n"
        #expect(DeclaringModuleIndex.declaredNames(in: text) == ["SyntaxPattern", "PatternCategory"])
        #expect(DeclaringModuleIndex.typeNames(in: "UIVisitor(category: .ui, count: 2)") == ["UIVisitor"])
    }
}
