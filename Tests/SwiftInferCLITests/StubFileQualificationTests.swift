import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A member's stub file is named for its declaring type, so namesakes on different types do not
/// overwrite one another (#467).
///
/// The name was unique per function and template, not per type, and the write replaces silently.
/// Measured on SwiftProjectLintRules: `predicate/matches_predicate.swift` was written five times —
/// `RegistrationVerb`, `InteractiveView`, `ServiceTypeSuffix`, `AnimationFactory`, `MockTypeName` —
/// and one file survived. The corpus funnel census counted 149 stubs lost that way.
@Suite("Stub file names carry the declaring type")
struct StubFileQualificationTests {

    private static func suggestion(
        _ displayName: String,
        template: String = "predicate",
        owner: String?,
        pairedWith reverse: String? = nil
    ) -> Suggestion {
        let row = { (name: String) in
            Evidence(
                displayName: name,
                signature: "(String) -> Bool",
                location: SourceLocation(file: "F.swift", line: 1, column: 1),
                qualifiedTypeName: owner
            )
        }
        return Suggestion(
            templateName: template,
            evidence: [row(displayName)] + (reverse.map { [row($0)] } ?? []),
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "\(owner ?? "")::\(displayName)::\(template)")
        )
    }

    /// **The measured case.** Five types, one method name, one template: five files.
    @Test func namesakesOnDifferentTypesGetDistinctFiles() throws {
        let owners = ["RegistrationVerb", "InteractiveView", "ServiceTypeSuffix", "AnimationFactory", "MockTypeName"]
        let names = try owners.map { owner in
            try #require(InteractiveTriage.stubFileName(for: Self.suggestion("matches(_:)", owner: owner)))
        }
        #expect(Set(names).count == 5)
        #expect(names.first == "RegistrationVerb_matches_predicate.swift")
    }

    /// And the suites those files get are distinct, so the shared test name is declared once per suite.
    @Test func theirSuitesAreDistinctToo() throws {
        let suites = try ["Sum", "Rotation", "Peak"].map { owner in
            InteractiveTriage.suiteName(forStubFileName: try #require(InteractiveTriage.stubFileName(
                for: Self.suggestion("combine(_:_:)", template: "associativity", owner: owner)
            )))
        }
        #expect(suites == [
            "Sum_combine_associativityTests", "Rotation_combine_associativityTests", "Peak_combine_associativityTests"
        ])
    }

    @Test func aNestedTypeIsFlattened() {
        let suggestion = Self.suggestion("tokenizeLine(_:)", template: "determinism", owner: "Editor.Tokenizer")
        let name = InteractiveTriage.stubFileName(for: suggestion)
        #expect(name == "Editor_Tokenizer_tokenizeLine_determinism.swift")
    }

    /// **The control.** A free function has no declaring type and keeps the name it always had, so
    /// no existing golden or previously accepted file is renamed.
    @Test func aFreeFunctionKeepsItsName() {
        let suggestion = Self.suggestion("normalize(_:)", template: "idempotence", owner: nil)
        #expect(InteractiveTriage.stubFileName(for: suggestion) == "normalize_idempotence.swift")
    }

    /// The template-specific arms keep their shape and gain the owner in front.
    @Test func aPairedTemplateKeepsItsShape() {
        let name = InteractiveTriage.stubFileName(
            for: Self.suggestion("encode(_:)", template: "round-trip", owner: "Codec", pairedWith: "decode(_:)")
        )
        #expect(name == "Codec_encode_decode_round-trip.swift")
    }
}
