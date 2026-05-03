import Foundation
import Testing
import SwiftInferCore
import SwiftInferTemplates

/// PRD v0.4 §16 #4 hard guarantee — "SwiftInfer never emits silently-
/// wrong code. When generator inference fails, the stub is emitted
/// with `.todo`, which does not compile. There is no 'approximately
/// correct' generator fallback."
///
/// The contract was implicitly covered by the
/// `GeneratorSelectionIntegrationTests.todoFallthroughGolden` byte-
/// for-byte goldens, but had no explicit release-gate test pinning
/// the contract under multiple inference-fallthrough types.
///
/// R1.1.f — closes the §16 #4 gap before the v0.1.0 cut.
@Suite("Generator inference — PRD §16 #4 .todo fallback (R1.1.f)")
struct TodoFallbackHardGuaranteeTests {

    /// Multi-fallthrough fixture — three distinct fallthrough types
    /// (class without `.userGen`, opaque struct without public init,
    /// reference type with no derivable members) so the contract
    /// holds across the breadth of the PRD §16 #4 surface, not just
    /// for the single class case the existing golden covers.
    @Test("Generator-inference fallthroughs always emit .todo, never an approximate fallback (PRD §16 #4)")
    func todoFallbackFiresForEveryFallthroughType() throws {
        let directory = try writeFixture()
        defer { try? FileManager.default.removeItem(at: directory) }

        let suggestions = try TemplateRegistry.discover(in: directory)

        let idempotence = suggestions.filter { $0.templateName == "idempotence" }
        #expect(
            idempotence.count >= 3,
            "Fixture should produce one idempotence suggestion per fallthrough type — got \(idempotence.count)"
        )

        for suggestion in idempotence {
            let source = suggestion.generator.source
            #expect(
                source == .todo,
                "Suggestion for \(suggestion.evidence[0].displayName) used generator source \(source) instead of .todo — §16 #4 forbids approximate fallbacks"
            )
            #expect(
                suggestion.generator.confidence == nil,
                ".todo suggestions must carry confidence == nil (the explainability block renders the no-confidence case); got \(String(describing: suggestion.generator.confidence))"
            )
            let rendered = SuggestionRenderer.render(suggestion)
            #expect(
                rendered.contains("Generator: .todo"),
                "Rendered output for \(suggestion.evidence[0].displayName) does not surface .todo to the developer:\n\(rendered)"
            )
            for forbidden in [
                "Generator: .derivedMemberwise",
                "Generator: .derivedCaseIterable",
                "Generator: .derivedRawRepresentable",
                "Generator: .registered"
            ] {
                #expect(
                    !rendered.contains(forbidden),
                    "Rendered output for \(suggestion.evidence[0].displayName) used a non-todo generator alongside the fallthrough path: \(forbidden)"
                )
            }
        }
    }

    // MARK: - Fixture

    private func writeFixture() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferTodoFallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try """
        // Reference type with no .userGen path → DerivationStrategist
        // must return .todo per PRD §16 #4.
        class Logger {
            let prefix: String = ""
        }

        // Reference type wrapping mutable state — no derivable
        // generator path; PRD §16 #4 mandates .todo not approximation.
        final class Cache {
            var stored: [String: Int] = [:]
        }

        // Struct whose only stored member is a non-stdlib reference
        // type — memberwise derivation has nothing to lean on, so
        // strategist falls through to .todo.
        struct Wrapper {
            let logger: Logger
        }

        struct Helpers {
            func normalizeLogger(_ value: Logger) -> Logger {
                return normalizeLogger(normalizeLogger(value))
            }
            func normalizeCache(_ value: Cache) -> Cache {
                return normalizeCache(normalizeCache(value))
            }
            func normalizeWrapper(_ value: Wrapper) -> Wrapper {
                return normalizeWrapper(normalizeWrapper(value))
            }
        }
        """.write(
            to: base.appendingPathComponent("Source.swift"),
            atomically: true,
            encoding: .utf8
        )
        return base
    }
}
