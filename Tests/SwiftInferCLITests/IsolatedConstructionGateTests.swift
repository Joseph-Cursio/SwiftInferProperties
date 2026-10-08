import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A stub is not written when its generator would call an initializer a generator cannot reach —
/// one isolated to a global actor — and the seed-synthesized laws are isolated as the template
/// laws already were.
///
/// Measured on SwiftLintRuleStudioCore, a `.defaultIsolation(MainActor.self)` package, with a
/// manifest seeding `MigrationAssistant`. Of 36 accepted stubs, every seed-synthesized law called
/// its subject with no hop, because those laws are built after the pipeline's isolation passes, and
/// the `applyMigration` mutator stubs built a `MigrationPlan` in the nonisolated `sample:` closure.
/// After the fix, the synthesized laws hop, those two stubs are withdrawn with the reason, and every
/// stub that still fails to compile fails on a generator gap — never on isolation.
@Suite("Accept — an isolated construction in a generator withdraws the stub")
struct IsolatedConstructionGateTests {

    // MARK: - Reading the stub

    @Test("constructions are read as initializer calls, not cases, statics or generators")
    func constructedTypeNames() {
        let sample = """
        { rng in zip(a, b).map { MigrationPlan(fromVersion: $0.0, steps: $0.1) }
            .map { MigrationStep.renameRule(from: $0, newName: $0) }
            Gen.always(Engine.Config()) Gen<Int>.int(in: 0...1) Widget.gen() Seed(stateA: 1) }
        """
        let names = IsolatedConstructionGate.constructedTypeNames(in: sample)
        #expect(names == ["MigrationPlan", "Engine.Config", "Seed"])
    }

    @Test("only the sample closure is read: the property closure is hopped")
    func sampleClosureOnly() {
        let stub = "sample: { rng in Gen.always(Plain()) }, property: { value in await MainActor.run { Plan() } }"
        #expect(IsolatedConstructionGate.sampleClosure(in: stub)?.contains("Plan()") == false)
    }

    // MARK: - The decision

    private static let isolatedFile = "/pkg/Sources/App/Plan.swift"

    private static func fact(
        isNonisolated: Bool = false,
        nonisolatedInit: Bool = false,
        attribute: String? = nil
    ) -> IsolatedConstructionGate.Fact {
        IsolatedConstructionGate.Fact(
            file: isolatedFile,
            declaredGlobalActor: attribute,
            isNonisolated: isNonisolated,
            declaresNonisolatedInitializer: nonisolatedInit
        )
    }

    private static func reason(
        _ fact: IsolatedConstructionGate.Fact,
        targetIsolation: String? = "MainActor"
    ) -> String? {
        let stub = "sample: { rng in zip(a, b).map { MigrationPlan(fromVersion: $0.0, steps: $0.1) } }, property: {}"
        return IsolatedConstructionGate.declineReason(stub: stub, facts: ["MigrationPlan": fact]) { _ in
            targetIsolation
        }
    }

    @Test("a MainActor-default type that opts out nowhere withdraws the stub, naming the remedy")
    func isolatedConstructionDeclines() throws {
        let reason = try #require(Self.reason(Self.fact()))
        #expect(reason.contains("builds a `MigrationPlan`"))
        #expect(reason.contains("`.defaultIsolation(MainActor.self)`"))
        #expect(reason.contains("declare `MigrationPlan` `nonisolated`"))
    }

    @Test("an explicit @MainActor on the type declines in a target with no default")
    func attributeDeclines() throws {
        let reason = try #require(Self.reason(Self.fact(attribute: "MainActor"), targetIsolation: nil))
        #expect(reason.contains("by its `@MainActor` attribute"))
    }

    /// The type or an initializer opts out, the target is not isolated, or the type is not scanned.
    @Test("otherwise the stub is written as before")
    func writtenAsBefore() {
        #expect(Self.reason(Self.fact(isNonisolated: true)) == nil)
        #expect(Self.reason(Self.fact(nonisolatedInit: true)) == nil)
        #expect(Self.reason(Self.fact(), targetIsolation: nil) == nil)
        #expect(Self.reason(Self.fact(), targetIsolation: "nonisolated") == nil)
        let unscanned = IsolatedConstructionGate.declineReason(
            stub: "sample: { rng in Gen.always(Unscanned()) }, property: {}",
            facts: ["MigrationPlan": Self.fact()]
        ) { _ in "MainActor" }
        #expect(unscanned == nil)
    }

    // MARK: - What the scanner records

    @Test("the scanner records a nonisolated type and a nonisolated initializer, on a type or an extension")
    func scannerRecordsOptOuts() {
        let corpus = FunctionScanner.scanCorpus(source: """
        nonisolated public struct Plan: Sendable { let steps: [String] }
        public struct Config: Sendable {
            let keys: [String]
            nonisolated public init(keys: [String]) { self.keys = keys }
        }
        public struct Isolated { let keys: [String] }
        public struct Extended { let keys: [String] }
        extension Extended { nonisolated init(one key: String) { self.keys = [key] } }
        """, file: "Probe.swift")
        let decls = Dictionary(grouping: corpus.typeDecls, by: \.name)
        #expect(decls["Plan"]?.first?.isNonisolated == true)
        #expect(decls["Config"]?.first?.isNonisolated == false)
        #expect(decls["Config"]?.first?.declaresNonisolatedInitializer == true)
        #expect(decls["Isolated"]?.first.map { $0.isNonisolated || $0.declaresNonisolatedInitializer } == false)

        let facts = IsolatedConstructionGate.facts(from: corpus.typeDecls)
        #expect(facts["Plan"]?.optsOut == true)
        #expect(facts["Config"]?.optsOut == true)
        #expect(facts["Isolated"]?.optsOut == false)
        #expect(facts["Extended"]?.optsOut == true)
    }

    // MARK: - The synthesized laws hop

    @Test("a seed-synthesized law takes its subject's target default isolation, as a template law does")
    func synthesizedLawsAreIsolated() throws {
        let root = try TargetIsolationGateTests.makePackage(named: "Floor", targets: [("Isolated", "MainActor")])
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Sources/Isolated/Placeholder.swift").path
        let summary = FunctionSummary(
            name: "describe",
            parameters: [Parameter(label: nil, internalName: "n", typeText: "Int", isInout: false)],
            returnTypeText: "String",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: file, line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let pipeline = SwiftInferCommand.Discover.PipelineResult(
            suggestions: [], packageRoot: root, summaries: [summary], docstringAdvice: false
        )
        let manifest = SeedManifest(seeds: [.init(file: file, line: 1, symbol: "describe")])
        let laws = SwiftInferCommand.Discover.seededFloorLaws(
            for: manifest, pipeline: pipeline, covered: [], diagnostics: Silent()
        )
        let law = try #require(laws.first)
        #expect(law.templateName == "determinism")
        #expect(law.evidence.first?.globalActor == "MainActor")
    }

    private struct Silent: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }
}
