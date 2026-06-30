import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Idea #4 step-2 follow-up #2 — `SoundPurity` wired into the discover
/// pipeline as a separate advisory channel. `discoverArtifacts` emits one
/// `EffectAnnotationAdvice` per function inferred referentially transparent,
/// kept entirely out of the property-test `suggestions` stream.
@Suite("EffectAnnotationAdvice — pure-effect advisory channel")
struct EffectAnnotationAdviceTests {

    @Test("A pure function earns pure-effect advice; an impure one does not")
    func pureFunctionEarnsAdvice() throws {
        let directory = try writeRegistryFixture(named: "EffectAnnotationMix", contents: """
        struct Math {
            func add(_ a: Int, _ b: Int) -> Int { a + b }
            func logged(_ a: Int) -> Int {
                print("a = \\(a)")
                return a
            }
            func stamped(_ a: Int) -> Double { Date().timeIntervalSince1970 + Double(a) }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifacts = try TemplateRegistry.discoverArtifacts(in: directory)
        let advisedNames = artifacts.effectAnnotations.map(\.displayName)

        #expect(advisedNames == ["add(_:_:)"])           // only the pure one
        let advice = try #require(artifacts.effectAnnotations.first)
        #expect(advice.recommendedAnnotation == "/// @lint.effect pure")
        #expect(advice.signature == "(Int, Int) -> Int")
        #expect(advice.rationale.isEmpty == false)
    }

    @Test("Advice never leaks into the property-test suggestion stream")
    func adviceIsSeparateFromSuggestions() throws {
        // `add` is a pure binary Int op, so it legitimately earns property-test
        // suggestions (commutativity / associativity) AND pure-effect advice.
        // The "separate channel" guarantee is that the advice is NOT itself
        // represented as a Suggestion — no fabricated `pure`/`effect`
        // templateName enters the stream that drives accept / verify / decisions.
        let directory = try writeRegistryFixture(named: "EffectAnnotationSeparate", contents: """
        enum Arithmetic {
            static func add(_ a: Int, _ b: Int) -> Int { a + b }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifacts = try TemplateRegistry.discoverArtifacts(in: directory)
        #expect(artifacts.effectAnnotations.map(\.displayName) == ["add(_:_:)"])
        #expect(
            artifacts.suggestions.contains {
                $0.templateName.contains("effect") || $0.templateName.contains("pure")
            } == false
        )
    }

    @Test("No pure functions → no advice")
    func noPureFunctionsNoAdvice() throws {
        let directory = try writeRegistryFixture(named: "EffectAnnotationNone", contents: """
        struct Clock {
            func now() -> Double { Date().timeIntervalSince1970 }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifacts = try TemplateRegistry.discoverArtifacts(in: directory)
        #expect(artifacts.effectAnnotations.isEmpty)
    }
}
