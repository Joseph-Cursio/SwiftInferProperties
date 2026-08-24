import Foundation
import Testing

@testable import SwiftInferCore

/// **A module-qualified stdlib spelling is the type it names.**
///
/// `RawType(typeName:)` matches exactly, and nothing in the kit strips a module qualifier, so
/// `Swift.String` resolved to no generator and took its whole enclosing type down with it. Every
/// row then reported `unsupported-carrier` — a label claiming the carrier is exotic, about a
/// `String`.
///
/// Measured on `MacPaw/OpenAI` @ `a532be8`: **0 → 16 of 28** `codable-round-trip` rows have a
/// fully-resolvable member tree once the spelling is canonical. Across the 20 resolving manifest
/// corpora the population is **1** — this is a generated-code shape, and the manifest holds no
/// generated-code subject.
///
/// **The negative cases are the load-bearing ones.** Rewriting too eagerly is the real hazard: a
/// last-component rule would map `Components.Schemas.Response` onto `Response` and
/// `MyModule.String` onto `String`, inventing a generator for a type that has none. Each is
/// asserted below.
@Suite("Stdlib type spelling — canonicalise Swift.String, and nothing else")
struct StdlibTypeSpellingTests {

    @Test("a qualified stdlib leaf loses its module")
    func stripsKnownModules() {
        #expect(StdlibTypeSpelling.canonical("Swift.String") == "String")
        #expect(StdlibTypeSpelling.canonical("Swift.Int") == "Int")
        #expect(StdlibTypeSpelling.canonical("Foundation.Date") == "Date")
        #expect(StdlibTypeSpelling.canonical("Foundation.URL") == "URL")
    }

    /// The spellings that actually appear: the generator writes them inside containers.
    @Test("composed spellings are rewritten in place")
    func rewritesInsideContainers() {
        #expect(StdlibTypeSpelling.canonical("[String: Swift.String]") == "[String: String]")
        #expect(StdlibTypeSpelling.canonical("Swift.String?") == "String?")
        #expect(StdlibTypeSpelling.canonical("[Swift.Int]") == "[Int]")
        #expect(StdlibTypeSpelling.canonical("Set<Swift.String>") == "Set<String>")
        #expect(StdlibTypeSpelling.canonical("[Swift.String: Swift.Int]") == "[String: Int]")
    }

    /// A custom type must reach the resolver under its own key, untouched.
    @Test("a qualified CUSTOM type is left exactly as written")
    func leavesCustomTypesAlone() {
        #expect(
            StdlibTypeSpelling.canonical("Components.Schemas.Response")
                == "Components.Schemas.Response"
        )
        #expect(
            StdlibTypeSpelling.canonical("OpenAPIRuntime.OpenAPIObjectContainer")
                == "OpenAPIRuntime.OpenAPIObjectContainer"
        )
        #expect(StdlibTypeSpelling.canonical("String") == "String")
    }

    /// The hazard a last-component rule would create. `MyModule` is not strippable, so the
    /// remainder is never consulted — even though it spells a stdlib name.
    @Test("an unknown module is not stripped, even before a stdlib name")
    func doesNotStripUnknownModules() {
        #expect(StdlibTypeSpelling.canonical("MyModule.String") == "MyModule.String")
        #expect(StdlibTypeSpelling.canonical("Schemas.Int") == "Schemas.Int")
    }

    /// A strippable module before a name the kit cannot generate for is left alone: rewriting it
    /// would change one `.todo` reason into another while risking a collision with a user type.
    @Test("a strippable module before an unknown leaf is left alone")
    func doesNotStripUnknownLeaves() {
        #expect(StdlibTypeSpelling.canonical("Swift.Duration") == "Swift.Duration")
        #expect(StdlibTypeSpelling.canonical("Foundation.Locale") == "Foundation.Locale")
    }

    /// Three components is a nested type, not a module qualifier.
    @Test("a deeper path is never collapsed")
    func doesNotCollapseDeepPaths() {
        #expect(StdlibTypeSpelling.canonical("Swift.Foo.String") == "Swift.Foo.String")
    }

    /// The seam this exists for: every type spelling crossing into the kit goes through
    /// `toKitShape()`, so a member, an init parameter and an enum payload must all be covered.
    /// Fixing only the arm that motivated the change is the mistake `EqualityBodyClassifier`
    /// already made once.
    @Test("toKitShape canonicalises members, init parameters and enum payloads")
    func toKitShapeCoversEveryPosition() {
        let shape = IndexedTypeShape(
            name: "Carrier",
            kind: .struct,
            inheritedTypes: ["Codable"],
            hasUserGen: false,
            storedMembers: [.init(name: "a", typeName: "Swift.String")],
            hasUserInit: true,
            initializers: [
                .init(
                    parameters: [.init(label: "a", typeName: "[String: Swift.String]")],
                    isFailable: false,
                    isThrowing: false
                )
            ],
            enumCases: [
                .init(name: "one", associatedValues: [.init(label: nil, typeName: "Swift.Int")])
            ]
        )

        let kit = shape.toKitShape()
        #expect(kit.storedMembers.first?.typeName == "String")
        #expect(kit.initializers.first?.parameters.first?.typeName == "[String: String]")
        #expect(kit.enumCases.first?.associatedValues.first?.typeName == "Int")
    }
}
