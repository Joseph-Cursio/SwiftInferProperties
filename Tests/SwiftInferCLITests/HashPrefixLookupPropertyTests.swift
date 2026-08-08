import Foundation
import PropertyLawKit
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// Self-dogfood road test, 2026-08-08 — **the private-subject case, done the way
// it should be done.**
//
// `discover --target SwiftInferCLI` proposed two Strong-tier `idempotence` rows
// against `VerifyHarness.normalize(prefix:)` (`:145`) and `normalize(hash:)`
// (`:156`). Both are `private static`, so neither can be called from a test —
// `@testable` promotes `internal`, not `private`.
//
// **The right response is not to widen access, and not to gate the tool.** A
// property stated at the public boundary survives the private helper being
// renamed, inlined, split, or replaced; a test bound to the helper breaks on
// every one of those. Keeping `normalize` private is correct design, and the
// law belongs on `lookupSuggestion(hashPrefix:in:)` — the internal entry point
// the helper exists to serve — where it is refactor-proof.
//
// **The lifted law is strictly stronger than the one that was proposed**, which
// is the finding worth carrying. `normalize` is idempotent — true, and it stays
// true under a real bug this repo could plausibly ship: normalizing the *query*
// prefix but not the *entry* hashes (or the reverse). `lookupSuggestion` calls
// `normalize` on both sides (`:77` and `:79`), and a refactor that drops one
// call leaves the helper perfectly idempotent while `0xBC43` stops matching an
// entry stored as `BC43`. The helper-level law is blind to it. The law below
// fails at the first spelling pair.
//
// Stated as a **metamorphic** law: one index, four spellings of one prefix, one
// answer. That is the user-visible contract — `swift-infer verify 0xBC43`,
// `verify BC43` and `verify bc43` must all resolve to the same suggestion — and
// it is what the private helper's own docstring claims (*"`0xBC43` and `BC43`
// both normalize to `bc43`"*) restated where a test can reach it.
@Suite("Road test — hash-prefix lookup is insensitive to 0x and to case")
struct HashPrefixLookupPropertyTests {

    // MARK: - Fixtures

    private static func entry(_ hash: String) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: hash,
            templateName: "round-trip",
            typeName: "Complex<Double>",
            score: 50,
            tier: "Strong",
            primaryFunctionName: "exp(_:)",
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-11T00:00:00Z",
            lastSeenAt: "2026-05-11T00:00:00Z"
        )
    }

    private static func index(_ entries: [SemanticIndexEntry]) -> IndexStore.Index {
        IndexStore.Index(updatedAt: "2026-05-11T00:00:00Z", entries: entries)
    }

    // MARK: - Generator
    //
    // Hashes are drawn so that the **stored** spelling varies too, not just the
    // query spelling. A generator that only varied the query would leave the
    // entry side of the normalization unexercised — and the entry side is
    // exactly where the bug this law targets lives.

    private static let hashBodies = [
        "BC43359C0574816B", "AA11223344556677", "0123456789ABCDEF", "F", "DEADBEEF"
    ]

    /// The four ways one hash can be written: with or without `0x`, upper or
    /// lower case. `spelling(of:)` below maps an index in `0...3` onto them.
    private static func spelling(of body: String, style: Int) -> String {
        switch style {
        case 0: return "0x" + body.uppercased()
        case 1: return "0x" + body.lowercased()
        case 2: return body.uppercased()
        default: return body.lowercased()
        }
    }

    private static let bodyGen = Gen.element(of: hashBodies).map { $0! }
    private static let styleGen = Gen.int(in: 0...3)

    // MARK: - Laws

    /// **The metamorphic law.** All four spellings of a full hash resolve to the
    /// same entry, whichever spelling the index happens to store.
    ///
    /// Sixteen spelling pairs per body. This is the law that fails the moment
    /// normalization is applied to one side and not the other.
    @Test("every spelling of a hash finds the same entry, however the index spells it")
    func lookupIsSpellingInsensitive() async {
        await propertyCheck(input: Self.bodyGen, Self.styleGen, Self.styleGen) { body, stored, queried in
            let target = Self.entry(Self.spelling(of: body, style: stored))
            let distractor = Self.entry("0x9999999999999999")
            let index = Self.index([target, distractor])
            let query = Self.spelling(of: body, style: queried)

            let result = try? VerifyHarness.lookupSuggestion(hashPrefix: query, in: index)
            #expect(
                result?.entry == target,
                """
                index stored "\(target.identityHash)" but query "\(query)" \
                resolved to \(result?.entry.identityHash ?? "nothing")
                """
            )
        }
    }

    /// **Every prefix of a hash resolves to it.** Truncating the query must not
    /// change which entry is found, only how ambiguous the search is — and with
    /// one distractor that shares no prefix, it stays unambiguous.
    ///
    /// Not implied by the law above: spelling-insensitivity is about *how* the
    /// characters are written, this is about *how many* of them are supplied.
    /// Together they pin both axes the lookup varies over.
    @Test("any non-empty prefix of a hash resolves to that hash")
    func everyPrefixResolves() async {
        await propertyCheck(input: Self.bodyGen, Self.styleGen, Gen.int(in: 1...8)) { body, style, take in
            let target = Self.entry(Self.spelling(of: body, style: style))
            let distractor = Self.entry("0x9999999999999999")
            let index = Self.index([target, distractor])
            let query = String(body.prefix(take))
            guard !query.isEmpty else { return }

            let result = try? VerifyHarness.lookupSuggestion(hashPrefix: query, in: index)
            #expect(
                result?.entry == target,
                "prefix \"\(query)\" of \"\(body)\" did not resolve"
            )
        }
    }

    /// **The empty index throws rather than matching.** The degenerate case that
    /// a prefix-matching implementation gets wrong by returning "everything" —
    /// and `""` is a prefix of every string, so this is the one input where a
    /// missing guard is invisible to the laws above.
    @Test("an empty index throws indexEmpty for every spelling")
    func emptyIndexThrows() async {
        await propertyCheck(input: Self.bodyGen, Self.styleGen) { body, style in
            #expect(throws: VerifyError.self) {
                _ = try VerifyHarness.lookupSuggestion(
                    hashPrefix: Self.spelling(of: body, style: style),
                    in: Self.index([])
                )
            }
        }
    }
}
