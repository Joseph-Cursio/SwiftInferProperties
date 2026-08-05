import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore

/// Open item 4's **cross-repo half**: do the names this repo recognises equal the
/// annotations SwiftIdempotency actually ships?
///
/// `EffectVocabularyContractTests` pins the spellings swift-infer's behaviour is
/// keyed to, so changing one here is a test failure here. It cannot assert those
/// spellings match the other package, because swift-infer deliberately does not
/// depend on SwiftIdempotency — the doc-comment form needs no dependency and the
/// attribute is matched by **name**, not by type. The two vocabularies are joined
/// by nothing a compiler can see.
///
/// That was tolerable while swift-infer only *read* one word. It stopped being
/// tolerable when `IdempotenceTemplate` began to **veto** on `@NonIdempotent` and
/// `@ExternallyIdempotent`: a rename upstream no longer fails loudly, it silently
/// stops suppressing a false law — and a suggestion that was suppressed and now is
/// not is indistinguishable from a codebase that never annotated anything.
///
/// See `fixtures/effect-vocabulary/README.md` for why the manifest's rule
/// (`@attached(peer)`) is derivable rather than curated, and for the honest limit:
/// without the sibling checkout the freshness half cannot run.
@Suite("Effect vocabulary — the cross-repo join with SwiftIdempotency")
struct EffectVocabularyCrossRepoTests {

    private struct Manifest: Decodable {
        let repo: String
        let sha: String
        let peerMacros: [String]
    }

    /// Annotations SwiftIdempotency ships that swift-infer deliberately does not
    /// recognise through `AttributeRecognition`, each with the reason.
    ///
    /// Being an explicit list is the point: an upstream annotation that nobody
    /// reads should require a decision, not go unnoticed. **Item 20 is that case
    /// having already happened** — `@EffectUnknown` shipped and no tool
    /// distinguishes it from an unannotated declaration.
    private static let deliberateExclusions: [String: String] = [
        "ClockDeterministic":
            "Matched by name at three hardcoded call sites (`isClockDeterministic`), not through "
            + "AttributeRecognition — see item 17. It is not an effect tier.",
        "EffectUnknown":
            "Item 20: nothing reads it yet. SEI must learn the marker first, since re-implementing "
            + "the `@lint.effect` grammar here is what SEI exists to prevent."
    ]

    private static func loadManifest() throws -> Manifest {
        let url = packageRoot()
            .appendingPathComponent("fixtures/effect-vocabulary/swiftidempotency-peer-macros.json")
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }

    private static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SwiftInferCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
    }

    /// The join itself, as an **equality** rather than a subset.
    ///
    /// The two directions fail differently and both matter: a name disappearing
    /// upstream is the rename that silently disarms the veto; a name appearing is
    /// a vocabulary swift-infer does not read. Subset checking would catch only
    /// the first.
    @Test("recognised names == shipped peer macros, minus the documented exclusions")
    func recognisedNamesMatchShippedVocabulary() throws {
        let manifest = try Self.loadManifest()
        let recognition = EffectAnnotationParser.AttributeRecognition.default
        // Accumulated rather than a single `+` chain: CLAUDE.md records a 12-arm
        // chain that compiled locally and tripped the CI type-check timeout, and a
        // 5-arm one already trips it here.
        var recognised: Set<String> = []
        recognised.formUnion(recognition.idempotent)
        recognised.formUnion(recognition.nonIdempotent)
        recognised.formUnion(recognition.observational)
        recognised.formUnion(recognition.externallyIdempotent)
        recognised.formUnion(recognition.pure)
        let expected = Set(manifest.peerMacros).subtracting(Self.deliberateExclusions.keys)

        #expect(
            recognised == expected,
            """
            The effect vocabulary has drifted from \(manifest.repo) @ \(manifest.sha).
            Only in swift-infer: \(recognised.subtracting(expected).sorted())
            Only upstream:       \(expected.subtracting(recognised).sorted())
            An upstream name swift-infer does not read is a DECISION to record in
            `deliberateExclusions`, not a test to relax.
            """
        )
    }

    /// Every exclusion carries a reason, and no exclusion names something the
    /// manifest does not ship — a stale exclusion would silently widen the gap the
    /// equality above is meant to close.
    @Test("each deliberate exclusion is real and carries a reason")
    func exclusionsAreRealAndExplained() throws {
        let shipped = Set(try Self.loadManifest().peerMacros)
        for (name, reason) in Self.deliberateExclusions {
            #expect(shipped.contains(name), "\(name) is excluded but no longer shipped upstream")
            #expect(reason.count > 40, "\(name)'s exclusion needs a reason, not a label")
        }
    }

    /// **Freshness.** Re-derives the vocabulary from the sibling checkout and fails
    /// if the manifest disagrees.
    ///
    /// This is the half that catches an upstream rename, and it can only run where
    /// `../SwiftIdempotency` exists. When it does not, the test records that the
    /// check was **skipped** rather than passing quietly — a skipped check that
    /// looks like a passed one is the failure this repo keeps writing down.
    @Test("the manifest still matches the sibling checkout, when there is one")
    func manifestMatchesSiblingCheckout() throws {
        let sources = Self.packageRoot()
            .deletingLastPathComponent()
            .appendingPathComponent("SwiftIdempotency/Sources")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            // Not a pass. The standing detector for sibling movement is
            // `make docs-drift`, which reports commits since a recorded SHA.
            print("SKIPPED: ../SwiftIdempotency not checked out — freshness unverified")
            return
        }
        let derived = Self.derivePeerMacros(under: sources)
        let manifest = try Self.loadManifest()
        #expect(
            derived == Set(manifest.peerMacros),
            """
            `fixtures/effect-vocabulary/swiftidempotency-peer-macros.json` is STALE against the \
            checkout at \(sources.path).
            Derived now:   \(derived.sorted())
            In manifest:   \(manifest.peerMacros.sorted())
            Regenerate it (see that fixture's README) and decide what the change means before \
            updating this test.
            """
        )
    }

    /// `@attached(peer) public macro <Name>` — the structural rule the manifest
    /// records. Deliberately textual: this reads another package's source without
    /// depending on it, which is the whole constraint item 4 operates under.
    private static func derivePeerMacros(under root: URL) -> Set<String> {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        var found: Set<String> = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in matches(of: text) { found.insert(line) }
        }
        return found
    }

    private static func matches(of text: String) -> [String] {
        let pattern = "@attached\\(peer\\)\\s*\\n\\s*public macro (\\w+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
