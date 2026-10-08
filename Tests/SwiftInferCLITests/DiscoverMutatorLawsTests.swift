@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A seeded **pure mutator** earns two laws over what it leaves behind, and `accept` writes them as
/// calls on copies — `f(&copy)` for an `inout` argument, `copy.m()` for a `mutating` method.
///
/// The determinism floor needs a returned value and refused every mutator, so SwiftLintRuleStudio's
/// `applyMigration(_:to:)` — which writes a config through `inout` and owes idempotence — earned
/// nothing. Measured on a fixture: all six stubs these laws produce compile against the kit, both
/// determinism laws pass, and idempotence fails exactly for the mutator that is not idempotent
/// (`bump()`), which is why that law is a conjecture.
@Suite("Discover — laws over a seeded pure mutator")
struct DiscoverMutatorLawsTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    private static func summary(
        name: String,
        parameters: [Parameter],
        returnType: String? = nil,
        isMutating: Bool = false,
        isStatic: Bool = true,
        containingType: String? = "Migrations",
        isAsync: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnType,
            isThrows: false,
            isAsync: isAsync,
            isMutating: isMutating,
            isStatic: isStatic,
            location: SourceLocation(file: "Migrations.swift", line: 4, column: 5),
            containingTypeName: containingType,
            bodySignals: .empty
        )
    }

    private static let addToConfig = summary(name: "add", parameters: [
        Parameter(label: nil, internalName: "name", typeText: "String", isInout: false),
        Parameter(label: "to", internalName: "config", typeText: "Config", isInout: true)
    ])

    private static let bump = summary(
        name: "bump", parameters: [], isMutating: true, isStatic: false, containingType: "Counter"
    )

    private static func laws(
        for summary: FunctionSummary,
        requires: SeedRequirement? = nil,
        covered: [Suggestion] = []
    ) -> [Suggestion] {
        let manifest = SeedManifest(seeds: [
            SeedManifest.Seed(
                file: "Migrations.swift", line: 4, symbol: summary.name, kind: .pureMutator,
                requires: requires, mutates: summary.isMutating ? "self" : "config"
            )
        ])
        return SwiftInferCommand.Discover.synthesizeMutatorLaws(
            for: manifest, summaries: [summary], covered: covered, diagnostics: SilentDiagnostics()
        )
    }

    // MARK: - Synthesis

    @Test("an inout mutator and a mutating method each earn both laws")
    func bothShapesEarnBothLaws() {
        for summary in [Self.addToConfig, Self.bump] {
            let names = Self.laws(for: summary).map(\.templateName)
            #expect(names == ["mutator-determinism", "mutator-idempotence"], "\(summary.name)")
        }
    }

    @Test("determinism is the advisory floor; idempotence is a Possible-tier conjecture")
    func tiers() throws {
        let laws = Self.laws(for: Self.addToConfig)
        let determinism = try #require(laws.first { $0.templateName == "mutator-determinism" })
        let idempotence = try #require(laws.first { $0.templateName == "mutator-idempotence" })
        #expect(determinism.score.tier == .advisory)
        #expect(idempotence.score.tier == .possible)
        #expect(idempotence.explainability.whyMightBeWrong.contains { $0.contains("A conjecture") })
    }

    private static let inoutC = Parameter(label: nil, internalName: "c", typeText: "C", isInout: true)
    private static let plainC = Parameter(label: nil, internalName: "c", typeText: "C", isInout: false)

    /// A returned value, `async`, two values written, and none written.
    private static let notMutators = [
        summary(name: "f", parameters: [inoutC], returnType: "Int"),
        summary(name: "f", parameters: [inoutC], isAsync: true),
        summary(name: "f", parameters: [inoutC, inoutC]),
        summary(name: "f", parameters: [plainC])
    ]

    @Test("not a mutator: a returned value, async, or two values written", arguments: notMutators)
    func notAMutator(summary: FunctionSummary) {
        #expect(Self.laws(for: summary).isEmpty)
    }

    @Test("a seed's requires leads the caveats")
    func requiresLeadsTheCaveats() throws {
        let law = try #require(Self.laws(for: Self.addToConfig, requires: SeedRequirement(equatable: ["Config"])).first)
        #expect(law.explainability.whyMightBeWrong.first?.hasPrefix("Declare `Equatable` on `Config` first") == true)
    }

    @Test("a mutator a focused law already covers is not doubled")
    func coveredIsSkipped() {
        let covering = Self.laws(for: Self.bump)
        #expect(Self.laws(for: Self.bump, covered: covering).isEmpty)
    }

    // MARK: - The stub

    @Test("an inout mutator's stub passes copies with &")
    func inoutStub() throws {
        let law = try #require(Self.laws(for: Self.addToConfig).first { $0.templateName == "mutator-determinism" })
        let stub = try #require(InteractiveTriage.mutatorStub(for: law))
        #expect(stub.contains("var first = args.1; Migrations.add(args.0, to: &first)"))
        #expect(stub.contains("return first == second"))
        #expect(stub.contains("func add_isDeterministicOnWhatItMutates()"))
    }

    @Test("a mutating method's stub calls it on copies of the drawn receiver")
    func mutatingStub() throws {
        let law = try #require(Self.laws(for: Self.bump).first { $0.templateName == "mutator-idempotence" })
        let stub = try #require(InteractiveTriage.mutatorStub(for: law))
        #expect(stub.contains("var once = value; once.bump(); var twice = once; twice.bump(); return once == twice"))
        #expect(stub.contains("func bump_isIdempotent()"))
    }

    @Test("the determinism floor leads with a seed's requires, in place of the generic sentence")
    func determinismFloorCarriesRequires() throws {
        let wrap = Self.summary(name: "wrap", parameters: [
            Parameter(label: nil, internalName: "items", typeText: "[String]", isInout: false)
        ], returnType: "Wrapper")
        let manifest = SeedManifest(seeds: [
            SeedManifest.Seed(
                file: "Migrations.swift", line: 4, symbol: "wrap",
                requires: SeedRequirement(equatable: ["Wrapper"])
            )
        ])
        let law = try #require(SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest, summaries: [wrap], covered: [], diagnostics: SilentDiagnostics()
        ).first)
        let caveats = law.explainability.whyMightBeWrong
        #expect(caveats.contains { $0.hasPrefix("Declare `Equatable` on `Wrapper` first") })
        #expect(caveats.contains("The return type must be Equatable for the law to compile.") == false)
    }
}
