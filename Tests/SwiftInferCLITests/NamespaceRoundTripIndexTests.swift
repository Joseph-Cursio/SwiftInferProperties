import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A `(T) -> T` round trip on a caseless-enum namespace is indexed over `T`, not declined.
///
/// **The reproduction** (`Tests/Fixtures/namespace-round-trip-corpus/Codec.swift`, the toy
/// `Slug.encode` / `Slug.decode` over `String`): `verify --suggestion` measured the pair over
/// `String` and found its planted bug, while `verify --all-from-index` filed it as
/// `not-a-candidate: carrier Slug is a caseless enum`, because the index stamped that
/// `structuralBlocker` and only the survey reads it. The survey arm, through a real build, is
/// `NamespaceRoundTripVerifyMeasuredTests`; this one pins the index entry, which is where the two
/// modes parted.
///
/// **The control is the general case**, which must keep declining: a `String -> Data` /
/// `Data -> String` pair on a namespace has two candidate carriers (`StructuralBlocker`).
@Suite("Namespace round trips — (T) -> T is indexed over T; the general case still declines")
struct NamespaceRoundTripIndexTests {

    private final class SilentDiagnostics: DiagnosticOutput, @unchecked Sendable {
        func writeDiagnostic(_: String) { /* discarded */ }
    }

    private static let fixtureSource = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // SwiftInferCLITests/
        .deletingLastPathComponent()  // Tests/
        .appendingPathComponent("Fixtures/namespace-round-trip-corpus/Codec.swift")

    private static let crossTypeSource = """
        import Foundation

        public enum Wire {
            /// Encode a string as UTF-8 bytes.
            public static func encode(_ text: String) -> Data { Data(text.utf8) }

            /// Decode bytes produced by `encode`.
            public static func decode(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
        }
        """

    /// `(T) -> T` over a scanned project type: the entry must carry `T`'s own shape, which is
    /// what the generator is synthesized from. (`String` above has no scanned shape, so the
    /// Slug arm cannot tell `T`'s shape from none.)
    private static let structDomainSource = """
        public struct Token: Equatable {
            public var text: String
            public init(text: String) { self.text = text }
        }

        public enum TokenCodec {
            /// Escape a token.
            public static func encode(_ token: Token) -> Token { Token(text: "<" + token.text + ">") }

            /// Undo `encode`.
            public static func decode(_ token: Token) -> Token {
                Token(text: String(token.text.dropFirst().dropLast()))
            }
        }
        """

    private static func indexEntries() throws -> [SemanticIndexEntry] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("namespace-round-trip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("Sources").appendingPathComponent("Toy")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.2\n".utf8).write(to: root.appendingPathComponent("Package.swift"))
        try FileManager.default.copyItem(at: fixtureSource, to: sources.appendingPathComponent("Codec.swift"))
        try crossTypeSource.write(to: sources.appendingPathComponent("Wire.swift"), atomically: true, encoding: .utf8)
        try structDomainSource.write(
            to: sources.appendingPathComponent("TokenCodec.swift"), atomically: true, encoding: .utf8
        )
        let (index, _) = try SwiftInferCommand.Index.performIndex(
            IndexInputs(
                scanDirectory: root.appendingPathComponent("Sources"),
                includePossible: true,
                explicitVocabularyPath: nil,
                explicitConfigPath: nil,
                explicitTestDirPath: nil,
                packsOverride: nil,
                dryRun: true
            ),
            diagnostics: SilentDiagnostics()
        )
        return index.entries
    }

    private static func roundTrip(on owner: String, in entries: [SemanticIndexEntry]) throws -> SemanticIndexEntry {
        try #require(entries.first { $0.templateName == "round-trip" && $0.typeName == owner })
    }

    @Test("Slug.encode/decode over String is not blocked, and its carrier is String")
    func endomorphicNamespacePairIsACandidate() throws {
        let entry = try Self.roundTrip(on: "Slug", in: Self.indexEntries())
        #expect(entry.structuralBlocker == nil, "\(entry.structuralBlocker ?? "")")
        #expect(entry.carrierTypeName == "String")
        // The call-site owner is unchanged: the stub still calls `Slug.encode` / `Slug.decode`.
        #expect(entry.typeName == "Slug")
        #expect(entry.parameterTypeNames == ["String"])
        // `String` is not a scanned type, so no shape — and certainly not the namespace's.
        #expect(entry.typeShape == nil)
    }

    @Test("TokenCodec.encode/decode over a scanned struct carries the struct's own shape")
    func endomorphicPairOverAStructCarriesItsShape() throws {
        let entry = try Self.roundTrip(on: "TokenCodec", in: Self.indexEntries())
        #expect(entry.structuralBlocker == nil, "\(entry.structuralBlocker ?? "")")
        #expect(entry.carrierTypeName == "Token")
        #expect(entry.typeName == "TokenCodec")
        #expect(entry.typeShape?.name == "Token")
    }

    @Test("Wire.encode/decode (String -> Data -> String) still declines as a caseless enum")
    func crossTypeNamespacePairStillDeclines() throws {
        let entry = try Self.roundTrip(on: "Wire", in: Self.indexEntries())
        let blocker = try #require(entry.structuralBlocker)
        #expect(blocker.contains("caseless enum"))
        #expect(blocker.contains("Wire"))
        #expect(entry.carrierTypeName == nil)
    }
}
