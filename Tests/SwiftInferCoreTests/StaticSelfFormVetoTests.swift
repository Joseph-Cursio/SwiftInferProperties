import Foundation
import SwiftInferTemplates
import Testing

@testable import SwiftInferCore

/// **A `static` member returning `Self` is a constant, not an endomorphism.**
///
/// The type-symmetry signal accepts *zero parameters, returns the containing type* as
/// the instance form `self -> Self` — `func normalized() -> Doc`, where `self` is the
/// operand. A `static` member has no receiver, so there is nothing to apply twice.
///
/// Measured on `swift-http-types` @ `5b99e00`
/// (`docs/measurements/criterion-a-unmet-subject.md`): `public static var badGateway:
/// Self` matched the gate, and the emitter rendered
/// `let applyOnce: (Status) -> Status = Status.badGateway` — a constant bound to a
/// function type. **49 of 163 laws failed to build on this alone.**
@Suite("Idempotence — a static Self-returning member is not the instance self-form")
struct StaticSelfFormVetoTests {

    static func rows(in source: String) throws -> [Suggestion] {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("static-self-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try source.write(
            to: directory.appendingPathComponent("S.swift"), atomically: true, encoding: .utf8
        )
        let scanned = try FunctionScanner.scanCorpus(directory: directory)
        return TemplateRegistry.discover(
            in: scanned.summaries, identities: scanned.identities, typeDecls: scanned.typeDecls
        )
    }

    /// The measured case, reduced: a static constant must not become an idempotence law.
    @Test("a static Self-returning property yields no idempotence law")
    func staticConstantIsNotIdempotent() throws {
        let rows = try Self.rows(in: """
        public struct Status: Hashable {
            public let code: Int
            public init(code: Int) { self.code = code }
            public static var badGateway: Self { .init(code: 502) }
            public static var notFound: Self { .init(code: 404) }
        }
        """)
        let idempotence = rows.filter { $0.templateName == "idempotence" }
        #expect(
            idempotence.isEmpty,
            "a static constant was admitted as self -> Self: \(idempotence.map(\.carrier))"
        )
    }

    /// **The instance form must still fire.** Without this the fix could be a blanket
    /// suppression that looks like a fix — the shape the veto exists to preserve is
    /// `func normalized() -> Self`, where `self` genuinely is the operand.
    @Test("an instance Self-returning method still yields an idempotence law")
    func instanceSelfFormSurvives() throws {
        let rows = try Self.rows(in: """
        public struct Doc: Hashable {
            public let text: String
            public init(text: String) { self.text = text }
            public func normalized() -> Self { Doc(text: text.lowercased()) }
        }
        """)
        let idempotence = rows.filter { $0.templateName == "idempotence" }
        #expect(!idempotence.isEmpty, "the instance self-form stopped firing — the fix is too wide")
    }
}
