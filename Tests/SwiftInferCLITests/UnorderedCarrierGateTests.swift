@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **A `monotonicity` stub over a project type nothing makes `Comparable` is withdrawn.**
///
/// Measured on the 2026-09-19 corpus funnel re-run: `area(_: Shape)`, `occurrenceTime(of:
/// CIRunResult)` and `lineSpan(of: CloneClass)` each emitted a stub that sorts its drawn pair with
/// `<` over a type with no ordering, and failed with `requires that 'Shape' conform to
/// 'Comparable'`. There is no law to state over an unordered domain.
@Suite("Discover stubs — monotonicity over an unordered project type")
struct UnorderedCarrierGateTests {

    private static func suggestion(template: String = "monotonicity", signature: String) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: "area(_:)",
                    signature: signature,
                    location: SourceLocation(file: "F.swift", line: 1, column: 1)
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "F.swift::area")
        )
    }

    private static func reason(
        signature: String,
        scanned: Set<String>,
        inherited: [String: Set<String>] = [:],
        template: String = "monotonicity"
    ) -> String? {
        UnorderedCarrierGate.declineReason(
            for: suggestion(template: template, signature: signature),
            scannedTypeNames: scanned,
            inheritedTypesByName: inherited
        )
    }

    @Test("a scanned type with no Comparable conformance is declined, and says why")
    func unorderedProjectType() throws {
        let why = try #require(Self.reason(
            signature: "(Shape) -> Double",
            scanned: ["Shape"],
            inherited: ["Shape": ["Equatable", "Sendable"]]
        ))
        #expect(why.contains("Shape"))
        #expect(why.contains("Comparable"))
    }

    @Test("a type declared Comparable is kept")
    func comparableProjectType() {
        #expect(Self.reason(
            signature: "(Level) -> Int",
            scanned: ["Level"],
            inherited: ["Level": ["Comparable"]]
        ) == nil)
    }

    /// A conformance through a project protocol that refines `Comparable` counts — the index
    /// holds the protocol's own clause, and the walk follows it.
    @Test("Comparable reached through a project protocol is kept")
    func comparableThroughProtocol() {
        #expect(Self.reason(
            signature: "(Rank) -> Int",
            scanned: ["Rank"],
            inherited: ["Rank": ["Rankable"], "Rankable": ["Comparable"]]
        ) == nil)
    }

    /// ⚠ **A raw type is not a conformance.** `enum Level: Int` is not `Comparable`; the walk must
    /// not step into `Int`'s stdlib conformances and conclude it is.
    @Test("a raw-value enum does not inherit its raw type's ordering")
    func rawTypeIsNotAConformance() throws {
        let stdlibInt = ProtocolCoverageMap.stdlibConformances["Int"] ?? []
        #expect(stdlibInt.contains("Comparable"), "precondition: the index knows Int is Comparable")
        _ = try #require(Self.reason(
            signature: "(Level) -> Int",
            scanned: ["Level"],
            inherited: ["Level": ["Int"], "Int": stdlibInt]
        ))
    }

    /// The posture that keeps this from removing real laws: a type the scan never saw is
    /// *unknown*, not *unordered* — framework and dependency types pass through.
    @Test("an unscanned type is left alone", arguments: ["Date", "Decimal", "SomeFrameworkType"])
    func unscannedTypeIsKept(typeName: String) {
        #expect(Self.reason(signature: "(\(typeName)) -> Int", scanned: ["Shape"]) == nil)
    }

    @Test("other templates are untouched")
    func otherTemplates() {
        #expect(Self.reason(signature: "(Shape) -> Shape", scanned: ["Shape"], template: "idempotence") == nil)
    }
}
