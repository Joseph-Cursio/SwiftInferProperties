import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **A nested name and its flattened spelling must not get one id.** #674's census found emitters
/// in this repository that turn a dotted type name into an identifier by dropping or replacing the
/// dot, so `Diagram.Node` and `DiagramNode` (or `Outer.Inner` and `Outer_Inner`) collide. Filed as
/// #715 (`KitSuiteEmitter`) and #716 (`InteractionTraceEmitter`).
@Suite("Dotted-name id collisions")
struct DottedNameIdCollisionTests {

    private func finding(_ typeName: String) -> ProtocolCoverageAudit.Finding {
        ProtocolCoverageAudit.Finding(
            typeName: typeName,
            coveringConformance: "Equatable",
            standing: .assumed,
            coveredLaws: [.equatableReflexive],
            declaredCoveringConformances: ["Equatable"]
        )
    }

    private func shape(_ name: String) -> TypeShape {
        TypeShape(name: name, kind: .enum, inheritedTypes: ["CaseIterable"], hasUserGen: false, storedMembers: [])
    }

    private func candidate(_ enclosing: String) -> ReducerCandidate {
        ReducerCandidate(
            location: "F.swift:1",
            enclosingTypeName: enclosing,
            functionName: "body",
            signatureShape: .stateActionReturnsState,
            stateTypeName: "\(enclosing).State",
            actionTypeName: "\(enclosing).Action"
        )
    }

    /// The function names `func NAME(` declared in a source text.
    private func declaredFunctions(_ source: String) -> [String] {
        source.components(separatedBy: "\n").compactMap { line in
            let code = line.trimmingCharacters(in: .whitespaces)
            guard code.hasPrefix("func ") else { return nil }
            return code.dropFirst("func ".count).prefix { $0 != "(" }.description
        }
    }

    /// `extension Diagram.Node: Equatable {}` beside a type `DiagramNode` gave two
    /// `func diagramNodeEquatable()` in one scaffolded suite, which does not compile.
    @Test("a nested carrier and its concatenation get distinct test functions")
    func kitSuiteFunctionNamesAreUnique() {
        let emission = KitSuiteEmitter.emit(
            findings: [finding("Diagram.Node"), finding("DiagramNode")],
            shapes: ["Diagram.Node": shape("Diagram.Node"), "DiagramNode": shape("DiagramNode")],
            moduleName: "MyModule"
        )
        #expect(emission.liveCarriers == 2)
        let names = declaredFunctions(emission.source)
        #expect(names.count == 2, "declared: \(names)")
        #expect(Set(names).count == names.count, "duplicate test functions: \(names)")
    }

    /// The first carrier in the emitter's order keeps the plain spelling, so the common case,
    /// with no collision, is unchanged.
    @Test("the first carrier keeps the plain function name")
    func kitSuiteFirstNameUnchanged() {
        let emission = KitSuiteEmitter.emit(
            findings: [finding("Diagram.Node"), finding("DiagramNode")],
            shapes: ["Diagram.Node": shape("Diagram.Node"), "DiagramNode": shape("DiagramNode")],
            moduleName: "MyModule"
        )
        #expect(declaredFunctions(emission.source).first == "diagramNodeEquatable")
    }

    /// A run on `Outer_Inner.body` overwrote the trace a run on `Outer.Inner.body` persisted.
    @Test("a nested reducer and its underscored spelling get distinct trace files")
    func traceFilePathsAreDistinct() {
        let root = URL(fileURLWithPath: "/tmp/pkg")
        let nested = InteractionTraceEmitter.traceFilePath(packageRoot: root, candidate: candidate("Outer.Inner"))
        let flat = InteractionTraceEmitter.traceFilePath(packageRoot: root, candidate: candidate("Outer_Inner"))
        #expect(nested != flat)
    }

    /// Once the two traces live side by side in one test target, their suite structs must not
    /// redeclare one name.
    @Test("a nested reducer and its underscored spelling get distinct trace suites")
    func traceSuiteIdentifiersAreDistinct() {
        #expect(
            InteractionTraceEmitter.suiteIdentifier(for: candidate("Outer.Inner"))
                != InteractionTraceEmitter.suiteIdentifier(for: candidate("Outer_Inner"))
        )
        #expect(
            InteractionTraceEmitter.suiteIdentifier(for: candidate("Outer-Inner"))
                != InteractionTraceEmitter.suiteIdentifier(for: candidate("Outer_Inner"))
        )
    }

    /// The reducer-only segment for a name with no underscore stays byte-for-byte what it was,
    /// so existing workdirs and trace paths do not move.
    @Test("a name without an underscore keeps its segment")
    func segmentUnchangedWithoutUnderscore() {
        #expect(VerifyInteractionPipeline.workdirSegment(for: candidate("Inbox")) == "Inbox_body")
    }
}
