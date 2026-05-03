import Foundation
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("TemplateRegistry — GeneratorSelection (M4.2)")
struct TemplateRegistryGeneratorTests {

    @Test("GeneratorSelection populates derivedMemberwise from corpus TypeShapes")
    func generatorSelectionPopulatesDerivedMemberwise() throws {
        // End-to-end: discover sees a Money struct with stdlib members
        // plus a normalize idempotence candidate over Money. The
        // generator-selection pass calls DerivationStrategist on the
        // Money TypeShape and rebuilds the suggestion with
        // .derivedMemberwise / .medium.
        let directory = try writeRegistryFixture(named: "GenSelectMemberwise", contents: """
        struct Money {
            let amount: Int
            let currency: String
        }
        struct Sanitizer {
            func normalize(_ value: Money) -> Money {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let idempotence = try #require(suggestions.first { $0.templateName == "idempotence" })
        #expect(idempotence.generator.source == .derivedMemberwise)
        #expect(idempotence.generator.confidence == .medium)
        #expect(idempotence.generator.sampling == .notRun)
    }

    @Test("GeneratorSelection skips stdlib-typed properties — open decision #2 default")
    func generatorSelectionSkipsStdlibTypedProperties() throws {
        // String isn't in the corpus's TypeShape index — selection
        // skips, generator stays .notYetComputed.
        let directory = try writeRegistryFixture(named: "GenSelectSkipStdlib", contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let idempotence = try #require(suggestions.first { $0.templateName == "idempotence" })
        #expect(idempotence.generator.source == .notYetComputed)
        #expect(idempotence.generator.confidence == nil)
    }

    @Test("GeneratorSelection populates registered for static gen() corpus types")
    func generatorSelectionPopulatesRegisteredForUserGen() throws {
        // Widget declares a static gen() in its primary body — strategist
        // returns .userGen → .registered with .high confidence.
        let directory = try writeRegistryFixture(named: "GenSelectUserGen", contents: """
        struct Widget {
            let id: Int
            static func gen() -> Int { 0 }
        }
        struct Sanitizer {
            func normalize(_ value: Widget) -> Widget {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let idempotence = try #require(suggestions.first { $0.templateName == "idempotence" })
        #expect(idempotence.generator.source == .registered)
        #expect(idempotence.generator.confidence == .high)
    }
}

@Suite("TemplateRegistry — cross-validation seam (M3.5)")
struct TemplateRegistryCrossValidationTests {

    @Test("Cross-validation seam adds +20 signal to matching identities")
    func crossValidationLiftsScoreOnMatchingIdentity() throws {
        let normalize = makeRegistryIdempotentSummary(file: "A.swift", line: 1)
        let baseline = TemplateRegistry.discover(in: [normalize])
        let target = try #require(baseline.first { $0.templateName == "idempotence" })
        let baselineTotal = target.score.total

        let crossValidated = TemplateRegistry.discover(
            in: [normalize],
            crossValidationFromTestLifter: [target.identity]
        )
        let lifted = try #require(crossValidated.first { $0.templateName == "idempotence" })
        #expect(lifted.score.total == baselineTotal + 20)
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(lifted.identity == target.identity)
        #expect(lifted.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") })
    }

    @Test("Cross-validation set with no matches leaves suggestions byte-stable")
    func crossValidationNoMatchIsByteStable() {
        let normalize = makeRegistryIdempotentSummary(file: "A.swift", line: 1)
        let baseline = TemplateRegistry.discover(in: [normalize])
        let unrelated = SuggestionIdentity(canonicalInput: "irrelevant|never-matches")
        let withCrossValidation = TemplateRegistry.discover(
            in: [normalize],
            crossValidationFromTestLifter: [unrelated]
        )
        #expect(baseline == withCrossValidation)
    }

    @Test("Cross-validation does not resurrect a contradiction-dropped suggestion")
    func crossValidationDoesNotResurrectDroppedSuggestion() {
        // Commutativity over Any → dropped by the §5.6 #2 detector.
        // Even with the suggestion's identity in the cross-validation
        // set, it stays gone — drops happen before cross-validation.
        let merge = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Any", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "Any", isInout: false)
            ],
            returnTypeText: "Any",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Mixer.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let droppedSuggestion = CommutativityTemplate.suggest(for: merge)
        let crossValidated = TemplateRegistry.discover(
            in: [merge],
            crossValidationFromTestLifter: droppedSuggestion.map { [$0.identity] } ?? []
        )
        #expect(crossValidated.allSatisfy { $0.templateName != "commutativity" })
    }
}
