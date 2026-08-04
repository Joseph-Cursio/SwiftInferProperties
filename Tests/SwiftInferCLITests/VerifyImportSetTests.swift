import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// **Which modules the verify stub must import**, and the two properties that make the answer
/// safe: the walk terminates, and over-collecting cannot invent an import.
///
/// The stub `@testable`-imports the module the *function* lives in, which is necessary and not
/// sufficient — a derived generator names the carrier's members and their members in turn.
/// Measured 2026-08-03: **37 of 126** `predicate` entries failed to build on exactly that, 31 on
/// `FunctionSummary` alone.
@Suite("Verify import set — the modules a law's carrier reaches")
struct VerifyImportSetTests {

    private func shape(
        _ name: String,
        members: [(String, String)] = [],
        initParams: [String] = [],
        enumCase: (String, [String])? = nil
    ) -> IndexedTypeShape {
        IndexedTypeShape(
            name: name,
            kind: enumCase == nil ? .struct : .enum,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: members.map {
                IndexedTypeShape.StoredMember(name: $0.0, typeName: $0.1)
            },
            hasUserInit: false,
            initializers: initParams.isEmpty ? [] : [
                makeInitializer(initParams)
            ],
            enumCases: enumCase.map { makeCase(name: $0.0, payload: $0.1) } ?? []
        )
    }

    private func makeInitializer(_ types: [String]) -> IndexedTypeShape.InitializerSignature {
        IndexedTypeShape.InitializerSignature(
            parameters: types.enumerated().map {
                IndexedTypeShape.InitializerParameter(label: "p\($0.offset)", typeName: $0.element)
            },
            isFailable: false,
            isThrowing: false
        )
    }

    private func makeCase(name: String, payload: [String]) -> [IndexedTypeShape.EnumCase] {
        let values = payload.map {
            IndexedTypeShape.InitializerParameter(label: nil, typeName: $0)
        }
        return [IndexedTypeShape.EnumCase(name: name, associatedValues: values)]
    }

    // MARK: - The closure

    @Test func theCarrierItselfIsAlwaysIncluded() {
        let names = VerifyImportSet.referencedTypeNames(carrier: "Widget", shapes: [:])
        #expect(names.contains("Widget"))
    }

    @Test func storedMembersAreReached() {
        let shapes = ["Outer": shape("Outer", members: [("inner", "Inner")])]
        let names = VerifyImportSet.referencedTypeNames(carrier: "Outer", shapes: shapes)
        #expect(names.contains("Inner"))
    }

    @Test func initializerParametersAndEnumPayloadsAreReached() {
        let shapes = [
            "ByInit": shape("ByInit", initParams: ["FromInit"]),
            "ByCase": shape("ByCase", enumCase: ("one", ["FromCase"]))
        ]
        #expect(VerifyImportSet.referencedTypeNames(carrier: "ByInit", shapes: shapes)
            .contains("FromInit"))
        #expect(VerifyImportSet.referencedTypeNames(carrier: "ByCase", shapes: shapes)
            .contains("FromCase"))
    }

    /// Transitively — the failure this exists for is two hops deep as often as one.
    @Test func theWalkIsTransitive() {
        let shapes = [
            "A": shape("A", members: [("b", "B")]),
            "B": shape("B", members: [("c", "C")])
        ]
        let names = VerifyImportSet.referencedTypeNames(carrier: "A", shapes: shapes)
        #expect(names.isSuperset(of: ["A", "B", "C"]))
    }

    /// **Termination.** `IndexedTypeShape` carries no depth limit and the corpus contains genuine
    /// cycles — an `indirect enum Tree` refers to itself. Without the visited set this hangs, and
    /// a hang inside a survey looks like a slow build rather than a defect.
    @Test func aCycleTerminates() {
        let shapes = [
            "Ping": shape("Ping", members: [("pong", "Pong")]),
            "Pong": shape("Pong", members: [("ping", "Ping")])
        ]
        let names = VerifyImportSet.referencedTypeNames(carrier: "Ping", shapes: shapes)
        #expect(names.isSuperset(of: ["Ping", "Pong"]))
    }

    @Test func aSelfReferentialTypeTerminates() {
        let shapes = ["Tree": shape("Tree", members: [("children", "[Tree]")])]
        #expect(VerifyImportSet.referencedTypeNames(carrier: "Tree", shapes: shapes)
            .contains("Tree"))
    }

    // MARK: - Identifier extraction

    /// Type text is scanned, not parsed, so a nested generic yields every name inside it.
    @Test func everyIdentifierInATypeTextIsFound() {
        #expect(VerifyImportSet.identifiers(in: "[String: Foo]?") == ["String", "Foo"])
        #expect(VerifyImportSet.identifiers(in: "Dictionary<Key, Value>") == ["Dictionary", "Key", "Value"])
        #expect(VerifyImportSet.identifiers(in: "Set<Foo>") == ["Set", "Foo"])
    }

    @Test func aWrappedMemberReachesItsElement() {
        let shapes = ["Holder": shape("Holder", members: [("items", "[Payload]")])]
        #expect(VerifyImportSet.referencedTypeNames(carrier: "Holder", shapes: shapes)
            .contains("Payload"))
    }

    // MARK: - Resolution

    /// **The map is the filter, and that is why over-collecting is safe.** `identifiers` yields
    /// `Array`, `String`, generic parameter names and anything else word-shaped; none of them is
    /// a scanned declaration, so none produces an import. A denylist would have to be maintained;
    /// this cannot go stale.
    @Test func anUnknownIdentifierProducesNoImport() {
        let root = URL(fileURLWithPath: "/pkg")
        let modules = VerifyImportSet.modules(
            forTypes: ["String", "Array", "Int", "T"],
            entryModule: nil,
            sourceFileByTypeName: [:],
            packageRoot: root
        )
        #expect(modules.isEmpty)
    }

    /// A type whose declaration site cannot resolve to a module is skipped rather than raised —
    /// `VerifyTargetInference` declines nested packages and dependency checkouts, and each of
    /// those is genuinely unreachable by importing anything.
    @Test func anUnresolvableDeclarationSiteIsSkipped() {
        let root = URL(fileURLWithPath: "/pkg")
        let modules = VerifyImportSet.modules(
            forTypes: ["Vendored"],
            entryModule: nil,
            sourceFileByTypeName: ["Vendored": "/pkg/.build/checkouts/dep/Sources/Dep/V.swift"],
            packageRoot: root
        )
        #expect(modules.isEmpty)
    }

    @Test func theEntryModuleComesFirstAndIsNotDuplicated() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("import-set-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for module in ["Core", "Templates"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Sources").appendingPathComponent(module),
                withIntermediateDirectories: true
            )
        }
        let modules = VerifyImportSet.modules(
            forTypes: ["Summary", "Rule"],
            entryModule: "Templates",
            sourceFileByTypeName: [
                "Summary": root.appendingPathComponent("Sources/Core/Summary.swift").path,
                "Rule": root.appendingPathComponent("Sources/Templates/Rule.swift").path
            ],
            packageRoot: root
        )
        #expect(modules == ["Templates", "Core"], "entry module first, remainder sorted")
    }
}
