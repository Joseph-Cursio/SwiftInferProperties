import PropertyLawCore
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

/// The generated `Sendable` shim: which types it may name, and how the one file per test target
/// is merged. A shim naming a type the test target cannot see breaks the WHOLE target, so the
/// visibility filter is the part that must not be wrong.
@Suite("Sendable shims — what may be named, and one file per target")
struct SendableShimTests {

    private static let source = """
        public struct Rec { public let key: Int }
        public final class Counter { public var count = 0 }
        public struct AlreadySafe: Sendable { let x: Int }
        public actor Store {}
        private struct Hidden { let x: Int }
        public struct Outer {
            private struct Inner { let x: Int }
            public struct Open { let x: Int }
        }
        """

    private let corpus = FunctionScanner.scanCorpus(source: source, file: "Types.swift")

    private var visible: Set<String> { SendableShim.testVisibleTypeNames(from: corpus.typeDecls) }

    private var shapes: [String: TypeShape] {
        Dictionary(uniqueKeysWithValues: TypeShapeBuilder.shapes(from: corpus.typeDecls).map { ($0.name, $0) })
    }

    private func shimmable(_ spelling: String) -> Set<String> {
        SendableShim.types(in: spelling, visible: visible, shapes: shapes, inheritedTypes: [:])
    }

    @Test("private types, and types inside private types, are never named")
    func privateTypesAreNotVisible() {
        #expect(visible.contains("Rec"))
        #expect(visible.contains("Outer.Open"))
        #expect(!visible.contains("Hidden"))
        #expect(!visible.contains("Outer.Inner"))
    }

    @Test("a drawn project type that is not Sendable is shimmed, inside any spelling")
    func drawnTypesAreFoundInsideSpellings() {
        #expect(shimmable("Rec") == ["Rec"])
        #expect(shimmable("[Rec]") == ["Rec"])
        #expect(shimmable("[String: Counter]?") == ["Counter"])
        #expect(shimmable("Outer.Open") == ["Outer.Open"])
    }

    @Test("stdlib types, explicitly Sendable types, actors and hidden types are skipped")
    func whatIsNotShimmed() {
        #expect(shimmable("Int").isEmpty)
        #expect(shimmable("AlreadySafe").isEmpty)
        #expect(shimmable("Store").isEmpty)
        #expect(shimmable("Hidden").isEmpty)
    }

    @Test("a Sendable conformance declared in another file's extension counts")
    func crossFileConformanceCounts() {
        let found = SendableShim.types(
            in: "Rec", visible: visible, shapes: shapes, inheritedTypes: ["Rec": ["Equatable", "Sendable"]]
        )
        #expect(found.isEmpty)
    }

    @Test("merging dedupes, sorts, and keeps every module's import")
    func mergingIsIdempotent() {
        let first = SendableShim.merged(existing: nil, adding: ["Rec"], module: "LawFix")
        let second = SendableShim.merged(existing: first, adding: ["Counter", "Rec"], module: "Other")
        #expect(second.contains("@testable import LawFix\n@testable import Other"))
        #expect(second.contains("extension Counter: @unchecked Sendable {}\nextension Rec: @unchecked Sendable {}"))
        #expect(second.components(separatedBy: "extension Rec:").count == 2, "declared once")
        #expect(SendableShim.merged(existing: second, adding: ["Rec"], module: "LawFix") == second)
    }

    @Test("a visible non-Sendable class is presented to the kit as @unchecked Sendable")
    func classesArePresentedAsSendable() {
        let presented = SendableShim.presentingShimmableClasses(Array(shapes.values), visible: visible)
        #expect(presented.first { $0.name == "Counter" }?.isSendableClass == true)
        #expect(presented.first { $0.name == "Rec" }?.inheritedTypes.contains("@unchecked Sendable") == false)
    }
}
