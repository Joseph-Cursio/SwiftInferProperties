import Foundation
import Testing
import SwiftInferCore
import SwiftInferTemplates

/// PRD v0.3 §11 / M4.5 acceptance-bar (a) integration suite for
/// `GeneratorSelection`. Closes the bar by exercising every
/// `DerivationStrategy` arm via real on-disk fixture corpora —
/// scanner → `TypeShapeBuilder` → `DerivationStrategist` → renderer
/// end-to-end, with each suggestion's full explainability block
/// asserted byte-for-byte (file path normalised to `<FIXTURE>` and
/// the §16 #6 sampling seed computed from the actual identity at
/// test time so the golden tracks the M4.3 derivation formula).
@Suite("GeneratorSelection — fixture-corpus integration (M4.5)")
struct GeneratorSelectionIntegrationTests {

    @Test("derivedMemberwise — struct with stdlib raw-type members")
    func derivedMemberwiseGolden() throws {
        let directory = try writeFixture(named: "GenSelectMemberwise", file: "Source.swift", contents: """
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
        let suggestion = try discoverIdempotenceSuggestion(in: directory)
        let rendered = SuggestionRenderer.render(suggestion)
        let expected = expectedRender(
            generatorLine: "Generator: .derivedMemberwise, confidence: .medium",
            type: "Money",
            suggestion: suggestion
        )
        #expect(rendered == expected)
    }

    @Test("derivedCaseIterable — enum: CaseIterable")
    func derivedCaseIterableGolden() throws {
        let directory = try writeFixture(named: "GenSelectCaseIter", file: "Source.swift", contents: """
        enum Side: CaseIterable {
            case left, right
        }
        struct Helpers {
            func normalize(_ value: Side) -> Side {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = try discoverIdempotenceSuggestion(in: directory)
        let rendered = SuggestionRenderer.render(suggestion)
        let expected = expectedRender(
            generatorLine: "Generator: .derivedCaseIterable, confidence: .high",
            type: "Side",
            suggestion: suggestion
        )
        #expect(rendered == expected)
    }

    @Test("derivedRawRepresentable — enum: Int")
    func derivedRawRepresentableGolden() throws {
        let directory = try writeFixture(named: "GenSelectRawRep", file: "Source.swift", contents: """
        enum StatusCode: Int {
            case ok = 200, notFound = 404
        }
        struct Helpers {
            func normalize(_ value: StatusCode) -> StatusCode {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = try discoverIdempotenceSuggestion(in: directory)
        let rendered = SuggestionRenderer.render(suggestion)
        let expected = expectedRender(
            generatorLine: "Generator: .derivedRawRepresentable, confidence: .high",
            type: "StatusCode",
            suggestion: suggestion
        )
        #expect(rendered == expected)
    }

    @Test("registered — struct with static gen()")
    func registeredFromUserGenGolden() throws {
        let directory = try writeFixture(named: "GenSelectUserGen", file: "Source.swift", contents: """
        struct Widget {
            let id: Int
            static func gen() -> Int { 0 }
        }
        struct Helpers {
            func normalize(_ value: Widget) -> Widget {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = try discoverIdempotenceSuggestion(in: directory)
        let rendered = SuggestionRenderer.render(suggestion)
        let expected = expectedRender(
            generatorLine: "Generator: .registered, confidence: .high",
            type: "Widget",
            suggestion: suggestion
        )
        #expect(rendered == expected)
    }

    @Test("todo — class fallthrough (no memberwise, no CaseIterable, no raw type)")
    func todoFallthroughGolden() throws {
        let directory = try writeFixture(named: "GenSelectTodo", file: "Source.swift", contents: """
        class Logger {
            let prefix: String = ""
        }
        struct Helpers {
            func normalize(_ value: Logger) -> Logger {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = try discoverIdempotenceSuggestion(in: directory)
        let rendered = SuggestionRenderer.render(suggestion)
        let expected = expectedRender(
            generatorLine: "Generator: .todo",
            type: "Logger",
            suggestion: suggestion
        )
        #expect(rendered == expected)
    }

    // MARK: - Helpers

    /// Run the discover pipeline and pull out the single idempotence
    /// suggestion the fixture produces. Each fixture is constructed so
    /// `normalize(_:)` is a Strong-tier candidate (T -> T + curated
    /// name + self-composition body signal = 90).
    private func discoverIdempotenceSuggestion(in directory: URL) throws -> Suggestion {
        let suggestions = try TemplateRegistry.discover(in: directory)
        return try #require(suggestions.first { $0.templateName == "idempotence" })
    }

    /// Build the byte-stable expected block. Identity hash, §16 #6
    /// seed, file path, and line number all derive from the actual
    /// suggestion that ran through the real pipeline so the golden
    /// tracks future changes to any of those derivations automatically
    /// — and the macOS `/private/var` symlink canonicalisation that
    /// FileManager applies during scan doesn't desync the path.
    private func expectedRender(
        generatorLine: String,
        type: String,
        suggestion: Suggestion
    ) -> String {
        let evidence = suggestion.evidence[0]
        let seedHex = SamplingSeed.renderHex(SamplingSeed.derive(from: suggestion.identity))
        return """
[Suggestion]
Template: idempotence
Score:    90 (Strong)

Why suggested:
  ✓ normalize(_:) (\(type)) -> \(type) — \(evidence.location.file):\(evidence.location.line)
  ✓ Type-symmetry signature: T -> T (T = \(type)) (+30)
  ✓ Curated idempotence verb match: 'normalize' (+40)
  ✓ Self-composition detected in body: normalize(normalize(x)) (+20)

Why this might be wrong:
  ⚠ T must conform to Equatable for the emitted property to compile. \
SwiftInfer M1 does not verify protocol conformance — confirm before applying.
  ⚠ If T is a class with a custom ==, the property is over value equality as T.== defines it.

\(generatorLine)
Sampling:  not run; lifted test seed: \(seedHex)
Identity:  \(suggestion.identity.display)
Suppress:  // swiftinfer: skip \(suggestion.identity.display)
"""
    }

    private func writeFixture(named name: String, file: String, contents: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferGenSelectIT-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try contents.write(
            to: base.appendingPathComponent(file),
            atomically: true,
            encoding: .utf8
        )
        return base
    }
}
