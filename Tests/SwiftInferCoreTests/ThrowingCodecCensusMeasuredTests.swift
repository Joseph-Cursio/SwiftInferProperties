import Foundation
import SwiftInferTemplates
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **How often does the shape behind the only surviving real defects actually occur?**
///
/// `refutation-hand-check.md` split `codable-round-trip`'s refutations into two mechanisms with
/// opposite track records:
///
/// | mechanism | survived scrutiny |
/// |---|---|
/// | **value promotion** — `Equatable` finer than the wire | **0** — one ruled INTENDED, one contested, nine false |
/// | **throwing** — a codec fails on a value the type's own API produces | **2 of 2** |
///
/// Both survivors are throws: `UserDetectionStatus`'s `encode(to:)` throws an `EncodingError`
/// on a value reachable through its declared `OptionSet` API, and `CatalogFeatureFlags`'s
/// `init(from:)` throws on the JSON `null` its own `encode(to:)` writes.
///
/// **This census sizes that shape before anything is proposed.** ⚠ **2 of 2 is a sample of two**
/// and is not a rate; the question here is only whether the shape has a population worth
/// separating from the value-promotion one it is currently pooled with.
///
/// ## The sharp signal is a THROWING ENCODER, and the asymmetry is the point
///
/// A **decoder** throws on malformed input by design — that is its contract, and an explicit
/// `throw` in `init(from:)` is ordinary validation. An **encoder** receives a value that already
/// exists. **An encoder that can throw is a type admitting values it cannot serialise**, which is
/// exactly `UserDetectionStatus`. So `throw` in `encode(to:)` is counted and `throw` in
/// `init(from:)` is not — not an oversight, a claim.
///
/// ## Shape B is the key-level asymmetry
///
/// `encodeIfPresent` on a key that `init(from:)` reads with a non-optional `decode` means the
/// encoder may omit what the decoder demands. That is `CatalogFeatureFlags`'s family — its
/// encoder writes a null the decoder rejects — reached by the nearest structural proxy, since
/// "writes null" needs the property's optionality and "omits" does not.
///
/// ⚠ **Both are FLOORS.** Neither reaches a codec that throws through a helper, and Shape B's
/// proxy misses the `encode`-writes-null form its own exhibit uses. Stated so the numbers are not
/// read as the population of the mechanism.
@Suite("Census — throwing codecs across the manifest corpora", .serialized)
struct ThrowingCodecCensusMeasuredTests {

    static let excludedDirectories = [".build", ".git", "checkouts", "Tests", ".swiftinfer"]

    static func isExcluded(_ url: URL) -> Bool {
        let components = url.pathComponents
        return excludedDirectories.contains { components.contains($0) }
    }

    struct Finding {
        let corpus: String
        let type: String
        let file: String
    }

    struct Census {
        var handWrittenEncoders = 0
        var handWrittenDecoders = 0
        var throwingEncoders: [Finding] = []
        var asymmetricKeys: [Finding] = []
        var filesScanned = 0
        var filesWithCodec = 0
    }

    /// The type name enclosing a node, or `nil` at file scope.
    static func enclosingTypeName(of node: some SyntaxProtocol) -> String? {
        var current: Syntax? = Syntax(node).parent
        while let node = current {
            if let decl = node.as(StructDeclSyntax.self) { return decl.name.text }
            if let decl = node.as(ClassDeclSyntax.self) { return decl.name.text }
            if let decl = node.as(EnumDeclSyntax.self) { return decl.name.text }
            if let decl = node.as(ActorDeclSyntax.self) { return decl.name.text }
            if let decl = node.as(ExtensionDeclSyntax.self) {
                return decl.extendedType.trimmedDescription
            }
            current = node.parent
        }
        return nil
    }

    static func containsThrowStatement(_ node: some SyntaxProtocol) -> Bool {
        if node.is(ThrowStmtSyntax.self) { return true }
        for child in node.children(viewMode: .sourceAccurate)
        where containsThrowStatement(child) { return true }
        return false
    }

    /// Coding keys named in calls of the given member names — `encodeIfPresent(_:forKey: .foo)`
    /// yields `foo`.
    static func keys(in node: some SyntaxProtocol, members: Set<String>) -> Set<String> {
        var found: Set<String> = []
        func walk(_ node: Syntax) {
            if let call = node.as(FunctionCallExprSyntax.self),
               let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               members.contains(member.declName.baseName.text) {
                for argument in call.arguments where argument.label?.text == "forKey" {
                    if let key = argument.expression.as(MemberAccessExprSyntax.self) {
                        found.insert(key.declName.baseName.text)
                    }
                }
            }
            for child in node.children(viewMode: .sourceAccurate) { walk(child) }
        }
        walk(Syntax(node))
        return found
    }

    /// Scan one file, folding its hand-written codecs into `census`.
    static func scan(source: String, corpus: String, file: String, into census: inout Census) {
        let tree = Parser.parse(source: source)
        let finder = CodecFinder(viewMode: .sourceAccurate)
        finder.walk(tree)

        for encoder in finder.encoders {
            census.handWrittenEncoders += 1
            let type = enclosingTypeName(of: encoder) ?? "(file scope)"
            guard let body = encoder.body else { continue }
            if containsThrowStatement(body) {
                census.throwingEncoders.append(Finding(corpus: corpus, type: type, file: file))
            }
        }

        // Shape B needs both halves on the SAME type, so index the decoders by their
        // enclosing type and join. A type with only one half cannot be asymmetric.
        var decoderBodies: [String: CodeBlockSyntax] = [:]
        for decoder in finder.decoders {
            census.handWrittenDecoders += 1
            if let body = decoder.body {
                decoderBodies[enclosingTypeName(of: decoder) ?? "(file scope)"] = body
            }
        }
        for encoder in finder.encoders {
            let type = enclosingTypeName(of: encoder) ?? "(file scope)"
            guard let encoderBody = encoder.body, let decoderBody = decoderBodies[type] else { continue }
            let optionallyWritten = keys(in: encoderBody, members: ["encodeIfPresent"])
            let requiredOnRead = keys(in: decoderBody, members: ["decode"])
            if !optionallyWritten.isDisjoint(with: requiredOnRead) {
                census.asymmetricKeys.append(Finding(corpus: corpus, type: type, file: file))
            }
        }
    }

    /// **The positive control, and Shape B needs it more than Shape A does.**
    ///
    /// Shape A came back **1** and Shape B came back **0**. A detector that finds nothing and a
    /// population that holds nothing print the same number, and this repo has shipped that
    /// mistake before — `module-state-base-rate.md`'s home arm reported a zero from a detector
    /// that could not see the syntax it was looking for. **Shape B's zero is worthless without
    /// this.**
    ///
    /// The two synthetic types are the exhibits reduced: an encoder that refuses one of its own
    /// values (`UserDetectionStatus`), and a key the encoder may omit while the decoder demands
    /// it (`CatalogFeatureFlags`'s family).
    @Test("the detector finds both shapes when they are present")
    func detectorFindsBothShapes() {
        var census = Census()
        Self.scan(source: """
        struct Refuses: Codable {
            let raw: Int
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                guard raw < 2 else {
                    throw EncodingError.invalidValue(raw, .init(codingPath: [], debugDescription: ""))
                }
                try container.encode(raw)
            }
        }

        struct Asymmetric: Codable {
            let name: String?
            enum CodingKeys: String, CodingKey { case name }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(name, forKey: .name)
            }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
            }
        }
        """, corpus: "control", file: "Control.swift", into: &census)

        #expect(census.handWrittenEncoders == 2, "the encoder finder missed one")
        #expect(census.handWrittenDecoders == 1, "the decoder finder missed one")
        #expect(
            census.throwingEncoders.map(\.type) == ["Refuses"],
            "Shape A must find an explicit `throw` in an encoder, and must NOT fire on `try`"
        )
        #expect(
            census.asymmetricKeys.map(\.type) == ["Asymmetric"],
            "Shape B must join encodeIfPresent to a required decode ON THE SAME TYPE"
        )
    }

    @Test("census — codecs that can fail on a value the type itself produces")
    func throwingCodecCensus() {
        var census = Census()
        for corpus in CorpusManifest.available {
            let enumerator = FileManager.default.enumerator(
                at: corpus.primaryRoot, includingPropertiesForKeys: nil
            )
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift", !Self.isExcluded(url) else { continue }
                guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
                census.filesScanned += 1
                guard source.contains("Encoder") || source.contains("Decoder") else { continue }
                census.filesWithCodec += 1
                Self.scan(
                    source: source, corpus: corpus.id, file: url.lastPathComponent, into: &census
                )
            }
        }

        var lines = ["", "THROWING CODECS — ALL MANIFEST CORPORA", ""]
        lines.append("swift files scanned \(census.filesScanned)"
            + " · mentioning Encoder/Decoder \(census.filesWithCodec)")
        lines.append("hand-written encode(to:) \(census.handWrittenEncoders)"
            + " · hand-written init(from:) \(census.handWrittenDecoders)")
        lines.append("")
        lines.append("SHAPE A — an encoder that can THROW: \(census.throwingEncoders.count)")
        lines += Self.breakdown(census.throwingEncoders)
        lines.append("")
        lines.append("SHAPE B — encodeIfPresent on a key decode() requires:"
            + " \(census.asymmetricKeys.count)")
        lines += Self.breakdown(census.asymmetricKeys)
        print(lines.joined(separator: "\n"))

        // The denominator, not the finding — a zero from a broken walk is
        // indistinguishable from a zero from a clean population.
        #expect(census.filesScanned > 1_000, "the walk found only \(census.filesScanned) files")
        #expect(census.handWrittenEncoders > 0, "no hand-written encoder found — the finder is broken")
    }

    static func breakdown(_ findings: [Finding]) -> [String] {
        guard !findings.isEmpty else { return ["  (none)"] }
        var lines: [String] = []
        let byCorpus = Dictionary(grouping: findings) { $0.corpus }.mapValues(\.count)
        for (corpus, count) in byCorpus.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
            lines.append("  \(count)  \(corpus)")
        }
        lines.append("  types: " + findings.map(\.type).sorted().prefix(18).joined(separator: ", "))
        return lines
    }
}

/// Hand-written `Codable` halves: `func encode(to:) throws` and `init(from:) throws`.
final class CodecFinder: SyntaxVisitor {
    private(set) var encoders: [FunctionDeclSyntax] = []
    private(set) var decoders: [InitializerDeclSyntax] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == "encode",
           node.signature.parameterClause.parameters.contains(where: {
               $0.type.trimmedDescription.hasSuffix("Encoder")
           }) {
            encoders.append(node)
        }
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.signature.parameterClause.parameters.contains(where: {
            $0.type.trimmedDescription.hasSuffix("Decoder")
        }) {
            decoders.append(node)
        }
        return .visitChildren
    }
}
