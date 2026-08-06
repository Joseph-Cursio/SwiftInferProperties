import Foundation
import Testing

@testable import SwiftInferCore

/// Does this build read every field the producer writes?
///
/// **The failure this exists for is silence.** `Codable` ignores unknown keys, so a producer adding
/// a field is invisible on this side: no error, no warning, no changed output. `restriction`
/// shipped upstream on 2026-08-03 carrying the answer to a question this repo was simultaneously
/// getting wrong, and arrived in every manifest for three days while nothing looked at it. There
/// was no test that could have failed.
///
/// It is deliberately **not** the mirror-image check. A field this build knows and the producer
/// never sends is fine — that is forward compatibility, and `role`/`restriction`/`effect` are all
/// optional precisely so a thinner producer still parses. Only the addition direction is a defect,
/// and only that direction is asserted.
///
/// Two arms, because neither is sufficient alone:
///
/// - **The fixture arm always runs** and is real producer output (`fixtures/seed-manifest-parity/`),
///   reduced to one seed per shape. It cannot catch a field added *after* the fixture was captured.
/// - **The source arm cannot go stale** — it reads `PBTSeed`'s stored properties out of a sibling
///   `../SwiftProjectLint` checkout — but only runs where that checkout exists, which is a
///   developer machine and not necessarily CI.
///
/// This is the same shape as `KitCoverageLawLevelTests`, which checks its table against the kit's
/// own source for the same reason: a guard that restates what it guards only proves two copies
/// agree.
@Suite("Seed manifest — producer/consumer field parity")
struct SeedFieldParityTests {

    private func fixtureSeeds() throws -> [[String: Any]] {
        let url = repoRoot.appendingPathComponent("fixtures/seed-manifest-parity/seeds.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try #require((object as? [String: Any])?["seeds"] as? [[String: Any]])
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftInferCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    // MARK: - The fixture arm

    /// Every key in a real manifest is one this build decodes.
    @Test("no field in real producer output goes unread")
    func fixtureFieldsAreAllKnown() throws {
        let seeds = try fixtureSeeds()
        #expect(!seeds.isEmpty, "an empty fixture would pass this test while checking nothing")

        let emitted = Set(seeds.flatMap(\.keys))
        let unread = emitted.subtracting(SeedFieldParity.knownFields)
        #expect(
            unread.isEmpty,
            """
            the producer emits field(s) this build does not decode: \(unread.sorted()). \
            They are being silently dropped. Add them to SeedManifest.Seed (and its CodingKeys), \
            or record here why they are deliberately ignored.
            """
        )
    }

    /// **The same question one level down, and the level the first version of this guard missed.**
    ///
    /// `effect` is a single key at the top level, so the test above is satisfied by decoding it at
    /// all — it says nothing about the object inside. SwiftProjectLint added `anchor` to
    /// `PBTSeedEffect` hours after that guard shipped, and no test here could have reported it. A
    /// guard that stops at the first level of a nested document guards only the first level.
    @Test("no field inside a nested object goes unread")
    func nestedFieldsAreAllKnown() throws {
        let seeds = try fixtureSeeds()
        var checked = 0
        for seed in seeds {
            for (holder, value) in seed {
                guard let nested = value as? [String: Any] else { continue }
                checked += 1
                let unread = SeedFieldParity.unreadFields(under: holder, emitted: Set(nested.keys))
                #expect(
                    unread.isEmpty,
                    """
                    the producer emits field(s) this build does not decode inside `\(holder)`: \
                    \(unread.sorted()). They are being silently dropped — add them to the \
                    corresponding *Field enum.
                    """
                )
            }
        }
        #expect(checked > 0, "no seed in the fixture carries a nested object; the arm is vacuous")
    }

    /// The fixture has to actually exercise the fields, or the arm above is vacuous — a sample
    /// carrying only the required four would pass while saying nothing about `role`, `restriction`
    /// or `effect`, which are exactly the fields that arrive late and get dropped.
    @Test("the fixture covers every field this build knows")
    func fixtureCoversKnownFields() throws {
        let seeds = try fixtureSeeds()

        let emitted = Set(seeds.flatMap(\.keys))
        let uncovered = SeedFieldParity.knownFields.subtracting(emitted)
        #expect(
            uncovered.isEmpty,
            "the parity fixture exercises no seed carrying \(uncovered.sorted()); regenerate it"
        )
    }

    /// And it must decode — parity of *names* is not parity of *shapes*.
    @Test("the real manifest decodes, with its fields populated")
    func fixtureDecodes() throws {
        let url = repoRoot
            .appendingPathComponent("fixtures/seed-manifest-parity/seeds.json")
        let manifest = try JSONDecoder().decode(SeedManifest.self, from: Data(contentsOf: url))

        #expect(manifest.version == SeedManifest.supportedVersion)
        #expect(manifest.seeds.allSatisfy { !$0.rule.isEmpty })
        #expect(manifest.seeds.contains { $0.restriction == .enclosingType })
        #expect(manifest.seeds.contains { $0.restriction == .declaration })
        #expect(manifest.seeds.contains { $0.effect != nil })
        #expect(manifest.seeds.contains { $0.role != nil })

        // Nothing unrecognised: the fixture is from a producer this build claims to understand, so
        // an `unrecognised` case here is a version skew the other tests would report as success.
        #expect(manifest.seeds.allSatisfy { seed in
            if case .unrecognised = seed.kind { return false }
            if case .unrecognised = seed.restriction { return false }
            if case .unrecognised = seed.role { return false }
            return true
        })
    }

    // MARK: - The source arm

    /// Read `PBTSeed`'s stored properties out of the producer's own source.
    ///
    /// Skipped rather than failed when no sibling checkout exists: a missing optional cross-repo
    /// input is not a defect in this repo, and failing on it would make the suite depend on a
    /// developer's directory layout. The fixture arm is what always runs.
    @Test("this build decodes every stored property of the producer's PBTSeed")
    func producerSourceFieldsAreAllKnown() throws {
        let source = repoRoot
            .deletingLastPathComponent()
            .appendingPathComponent("SwiftProjectLint/Sources/Core/Export/PBTSeedsFormatter.swift")
        guard let text = try? String(contentsOf: source, encoding: .utf8) else { return }

        let fields = Self.storedProperties(ofStruct: "PBTSeed", in: text)
        #expect(
            !fields.isEmpty,
            """
            the producer's source was found but no stored properties were parsed out of \
            `struct PBTSeed` — the declaration moved or was reshaped, so this arm is now checking \
            nothing. Fix the parse rather than deleting the test.
            """
        )

        let unread = fields.subtracting(SeedFieldParity.knownFields)
        #expect(
            unread.isEmpty,
            """
            the producer's PBTSeed declares field(s) this build does not decode: \
            \(unread.sorted()). Regenerate fixtures/seed-manifest-parity/seeds.json and add them.
            """
        )

        // Non-vacuity, cross-checked against the *other* producer-derived source rather than a
        // hand-copied list. Every key in the fixture came out of a real run, so it must be a stored
        // property of the struct that wrote it; a parse that missed some would pass the subset
        // assertion above while checking almost nothing.
        let missed = Set(try fixtureSeeds().flatMap(\.keys)).subtracting(fields)
        #expect(
            missed.isEmpty,
            "the PBTSeed parse missed \(missed.sorted()), which real output demonstrably carries"
        )
    }

    /// **The arm that would have caught `anchor` on the day it landed**, and the reason the nested
    /// check needs a source arm of its own.
    ///
    /// The fixture arm can only report a nested field that was present when the fixture was
    /// captured. `anchor` was added upstream *after* the last capture, so only a read of the
    /// producer's live declaration reports it — which is exactly the split the top-level guard
    /// already documents, applied one level down.
    @Test("this build decodes every stored property of the producer's PBTSeedEffect")
    func producerNestedSourceFieldsAreAllKnown() {
        let source = repoRoot
            .deletingLastPathComponent()
            .appendingPathComponent(
                "SwiftProjectLint/Packages/SwiftProjectLintModels/Sources"
                    + "/SwiftProjectLintModels/PBTSeedEffect.swift"
            )
        guard let text = try? String(contentsOf: source, encoding: .utf8) else { return }

        let fields = Self.storedProperties(ofStruct: "PBTSeedEffect", in: text)
        #expect(
            !fields.isEmpty,
            """
            the producer's PBTSeedEffect was found but no stored properties were parsed out of it — \
            the declaration moved or was reshaped, so this arm is now checking nothing. Fix the \
            parse rather than deleting the test.
            """
        )

        let known = SeedFieldParity.knownNestedFields[SeedField.effect.stringValue] ?? []
        let unread = fields.subtracting(known)
        #expect(
            unread.isEmpty,
            """
            the producer's PBTSeedEffect declares field(s) this build does not decode: \
            \(unread.sorted()). Add them to SeedEffect and SeedEffectField, decide whether they \
            change carriesEnoughEvidenceToDemote, and regenerate the parity fixture.
            """
        )
    }

    /// `public let <name>:` lines between `struct <name>` and the next top-level `}`.
    ///
    /// A regex over the producer's source, which is the point — the alternative is a hand-copied
    /// list on this side, and a hand-copied list agreeing with itself is what
    /// `KitCoverageDriftTests` did while passing green through thirteen false claims. The parse is
    /// asserted non-empty above so a reshaped declaration fails loudly instead of vacuously.
    ///
    /// The declaration is matched with its trailing punctuation (`public struct PBTSeed:`) rather
    /// than by name alone: `PBTSeed` is a prefix of `PBTSeedManifest`, which is declared in the same
    /// file, so a bare name match would silently parse the wrong type if their order ever swapped.
    static func storedProperties(ofStruct name: String, in source: String) -> Set<String> {
        let start = ["public struct \(name):", "public struct \(name) {"]
            .compactMap { source.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
        guard let start else { return [] }
        let body = source[start.upperBound...]
        // Stop at the first line that closes a top-level declaration.
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        var fields: Set<String> = []
        for line in lines {
            if line == "}" { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("public let ") else { continue }
            let afterLet = trimmed.dropFirst("public let ".count)
            guard let colon = afterLet.firstIndex(of: ":") else { continue }
            fields.insert(String(afterLet[..<colon]).trimmingCharacters(in: .whitespaces))
        }
        return fields
    }
}
