import SwiftEffectInference
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **A seed does not outrank the scan's own witness.** The `--seeds` fallbacks write laws for a
/// seeded function no template covers: `determinism`, `f(x) == f(x)`, and for a pure mutator
/// `mutator-determinism` and `mutator-idempotence`. The impure-subject veto suppresses every
/// template law over a subject refuted with a witness, which made that subject *uncovered*, so a
/// seeded one earned a fallback that calls the impurity at least twice per trial. Found
/// 2026-11-12, tracing why a law over an `NSWorkspace.open` wrapper ran.
///
/// The controls are the veto's own (a pure seed, and a throwing seed refuted only because the
/// analyzer cannot see past a `try`) plus the one the fallback adds: an `async` function carrying
/// the `@ClockDeterministic` claim, which SEI refutes on its signature alone.
@Suite("A seeded function judged impure with a witness earns no fallback law")
struct ImpureSeedDeterminismTests {

    private final class Recorded: DiagnosticOutput, @unchecked Sendable {
        private(set) var lines: [String] = []

        func writeDiagnostic(_ line: String) { lines.append(line) }

        var withheldNotes: [String] { lines.filter { $0.contains("impure with a witness") } }
    }

    private static func summary(
        verdict: PurityVerdict,
        line: Int = 4,
        isThrows: Bool = false,
        isAsync: Bool = false,
        isClockDeterministic: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: "open",
            parameters: [Parameter(label: nil, internalName: "url", typeText: "URL", isInout: false)],
            returnTypeText: "Bool",
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Launcher.swift", line: line, column: 5),
            containingTypeName: "SystemXcodeLauncher",
            bodySignals: .empty,
            isInferredPure: verdict == .pure,
            isClockDeterministic: isClockDeterministic,
            purityVerdict: verdict,
            bodyFingerprint: "FEEDFACE"
        )
    }

    private static func mutator(verdict: PurityVerdict) -> FunctionSummary {
        FunctionSummary(
            name: "record",
            parameters: [Parameter(label: nil, internalName: "event", typeText: "Event", isInout: false)],
            returnTypeText: nil,
            isThrows: false,
            isAsync: false,
            isMutating: true,
            isStatic: false,
            location: SourceLocation(file: "Log.swift", line: 9, column: 5),
            containingTypeName: "EventLog",
            bodySignals: .empty,
            isInferredPure: verdict == .pure,
            purityVerdict: verdict,
            bodyFingerprint: "FEEDFACE"
        )
    }

    private static let manifest = SeedManifest(seeds: [
        SeedManifest.Seed(file: "Launcher.swift", line: 4, symbol: "open", kind: .pureFunction),
    ])

    private static let mutatorManifest = SeedManifest(seeds: [
        SeedManifest.Seed(file: "Log.swift", line: 9, symbol: "record", kind: .pureMutator),
    ])

    private static func synthesize(
        _ summaries: [FunctionSummary],
        diagnostics: any DiagnosticOutput,
        restricted: [FunctionSummary] = []
    ) -> [Suggestion] {
        SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest,
            summaries: summaries,
            covered: [],
            diagnostics: diagnostics,
            restrictedFunctions: restricted.map { RestrictedFunction(summary: $0, restriction: .notVisibleToTests) }
        )
    }

    // MARK: - determinism

    @Test("a witness-refuted seed gets no determinism law, and the reader is told why")
    func witnessRefutedSeedIsWithheld() {
        let diagnostics = Recorded()
        let laws = Self.synthesize([Self.summary(verdict: .refuted)], diagnostics: diagnostics)
        #expect(laws.isEmpty)
        #expect(diagnostics.withheldNotes.count == 1)
        #expect(diagnostics.withheldNotes.first?.contains("`open`") == true)
    }

    @Test("a witness-refuted seed reached only as a restricted function is withheld")
    func witnessRefutedRestrictedSeedIsWithheld() {
        let diagnostics = Recorded()
        let laws = Self.synthesize([], diagnostics: diagnostics, restricted: [Self.summary(verdict: .refuted)])
        #expect(laws.isEmpty)
        #expect(diagnostics.withheldNotes.count == 1)
    }

    @Test("a restricted function met in both loops is noted once")
    func restrictedSeedInBothLoopsIsNotedOnce() {
        let diagnostics = Recorded()
        let impure = Self.summary(verdict: .refuted)
        #expect(Self.synthesize([impure], diagnostics: diagnostics, restricted: [impure]).isEmpty)
        #expect(diagnostics.withheldNotes.count == 1)
    }

    @Test("a pure namesake in the same file still earns the law the impure one is denied")
    func pureNamesakeStillEarnsTheLaw() throws {
        let diagnostics = Recorded()
        let laws = Self.synthesize(
            [Self.summary(verdict: .refuted, line: 4), Self.summary(verdict: .pure, line: 30)],
            diagnostics: diagnostics
        )
        let law = try #require(laws.first)
        #expect(laws.count == 1)
        #expect(law.evidence.first?.location.line == 30)
        #expect(diagnostics.withheldNotes.count == 1)
    }

    @Test("control: a pure seed still earns the determinism law")
    func pureSeedEarnsTheLaw() {
        let laws = Self.synthesize([Self.summary(verdict: .pure)], diagnostics: Recorded())
        #expect(laws.map(\.templateName) == ["determinism"])
    }

    @Test("control: a throwing seed refuted only by its propagated try still earns the law")
    func ignoranceOnlyRefutationEarnsTheLaw() {
        let laws = Self.synthesize([Self.summary(verdict: .refuted, isThrows: true)], diagnostics: Recorded())
        #expect(laws.map(\.templateName) == ["determinism"])
    }

    @Test("control: an async @ClockDeterministic seed, refuted by its signature, keeps its law")
    func clockDeterministicAsyncSeedKeepsItsLaw() {
        let diagnostics = Recorded()
        let laws = Self.synthesize(
            [Self.summary(verdict: .refuted, isAsync: true, isClockDeterministic: true)],
            diagnostics: diagnostics
        )
        #expect(laws.map(\.templateName) == ["determinism"])
        #expect(diagnostics.withheldNotes.isEmpty)
    }

    // MARK: - mutator laws

    @Test("a witness-refuted seeded mutator gets neither mutator law, and the reader is told why")
    func witnessRefutedMutatorIsWithheld() {
        let diagnostics = Recorded()
        let laws = SwiftInferCommand.Discover.synthesizeMutatorLaws(
            for: Self.mutatorManifest,
            summaries: [Self.mutator(verdict: .refuted)],
            covered: [],
            diagnostics: diagnostics
        )
        #expect(laws.isEmpty)
        #expect(diagnostics.withheldNotes.count == 1)
        #expect(diagnostics.withheldNotes.first?.contains("no mutator law") == true)
    }

    @Test("control: a pure seeded mutator still earns both mutator laws")
    func pureMutatorEarnsItsLaws() {
        let laws = SwiftInferCommand.Discover.synthesizeMutatorLaws(
            for: Self.mutatorManifest,
            summaries: [Self.mutator(verdict: .pure)],
            covered: [],
            diagnostics: Recorded()
        )
        #expect(laws.map(\.templateName) == ["mutator-determinism", "mutator-idempotence"])
    }
}
