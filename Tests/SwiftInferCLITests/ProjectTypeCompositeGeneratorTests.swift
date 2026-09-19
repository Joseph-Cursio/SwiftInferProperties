import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferTemplates
import Testing

/// **A collection of a derivable project type gets a generator, composed from the element's.**
///
/// `GeneratorResolver.customTypeGenerator` answers for a named type only, so a parameter of
/// `[LineItem]` rendered `[LineItem].gen()` with *not among the scanned types* — a deliberate
/// compile error — while `LineItem` itself derived. Measured on the 2026-09-19 corpus re-run,
/// `[LineItem]` and `[CloneClass]` blocked 7 stubs that way.
@Suite("Discover stubs — collections of project types")
struct ProjectTypeCompositeGeneratorTests {

    private static func generator(_ typeName: String) -> String? {
        InteractiveTriage.projectTypeGenerator(types: [
            TypeShape(
                name: "LineItem",
                kind: .struct,
                inheritedTypes: [],
                hasUserGen: false,
                storedMembers: [StoredMember(name: "cents", typeName: "Int")]
            ),
            TypeShape(name: "Session", kind: .class, inheritedTypes: [], hasUserGen: false)
        ])(typeName)
    }

    @Test("an array of a derivable struct composes from the element's generator")
    func arrayOfStruct() throws {
        let expression = try #require(Self.generator("[LineItem]"))
        #expect(!expression.contains(".gen()"), "still the `.todo` fallback: \(expression)")
        #expect(expression.contains("LineItem("), "does not build the element: \(expression)")
    }

    @Test("an optional of a derivable struct composes too")
    func optionalOfStruct() throws {
        let expression = try #require(Self.generator("LineItem?"))
        #expect(!expression.contains(".gen()"))
        #expect(expression.contains("LineItem("))
    }

    /// The control that keeps the composite arm honest: an element that does NOT derive must
    /// still fall through to the explained `.todo`, not to a generator that silently drops it.
    @Test("an array of an underivable element still reports why")
    func arrayOfUnderivable() throws {
        let expression = try #require(Self.generator("[Session]"))
        #expect(expression.contains("no generator derived"))
    }

    /// ⚠ **The composite arm runs BEFORE the stdlib arms**, so answering for `String` there
    /// would replace `RawType`'s edge-biased generator with the kit's plain one. Every type those
    /// arms already answer must come out exactly as `defaultGenerator` renders it.
    @Test("stdlib types keep the generator the stdlib arms give them", arguments: [
        "String", "Int", "[String]", "String?", "Data"
    ])
    func stdlibUntouched(typeName: String) {
        #expect(Self.generator(typeName) == LiftedTestEmitter.defaultGenerator(for: typeName))
    }
}
