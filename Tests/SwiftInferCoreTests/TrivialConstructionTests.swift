@testable import SwiftInferCore
import Testing

/// A class receiver built from an initializer — its own or inherited — whose every argument has an
/// obvious empty value.
@Suite("Trivial receiver construction — an inherited initializer with empty arguments")
struct TrivialConstructionTests {

    private static let classes = TrivialConstruction.classes(in: [
        """
        open class CrossFileVisitorBase: BasePatternVisitor {
            public required init(fileCache: [String: SourceFileSyntax]) {}
            public required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {}
        }
        final class DuplicateShapeVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {}
        final class Walker: SyntaxVisitor {}
        final class Configured { init(limit: Int) {} }
        final class Defaulted { init(limit: Int = 3, names: [String], parent: Defaulted?) {} }
        final class Hidden { private init(values: [Int]) {} }
        final class Plain { var count = 0 }
        """
    ])

    private func build(_ name: String) -> String? {
        TrivialConstruction.expression(for: name, classes: Self.classes)?.0
    }

    @Test("an initializer inherited from a superclass is used with empty arguments")
    func inheritedInitializer() {
        #expect(build("DuplicateShapeVisitor") == "DuplicateShapeVisitor(fileCache: [:])")
    }

    @Test("a SyntaxVisitor subclass with no initializer of its own gets viewMode, and asks for SwiftSyntax")
    func syntaxVisitor() {
        let built = TrivialConstruction.expression(for: "Walker", classes: Self.classes)
        #expect(built?.0 == "Walker(viewMode: .sourceAccurate)")
        #expect(built?.1 == true)
    }

    @Test("defaults are omitted, collections and optionals are emptied")
    func defaultsAndEmpties() {
        #expect(build("Defaulted") == "Defaulted(names: [], parent: nil)")
        #expect(build("Plain") == "Plain()")
    }

    @Test("an argument with no empty value, or a private initializer, gives nothing")
    func nothingToBuild() {
        #expect(build("Configured") == nil)
        #expect(build("Hidden") == nil)
        #expect(build("Unknown") == nil)
    }
}
