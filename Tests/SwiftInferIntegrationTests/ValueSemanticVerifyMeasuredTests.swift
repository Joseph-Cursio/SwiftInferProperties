import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — end-to-end measured proof for the ValueSemantic feature, now
/// driven through the production `ValueSemanticVerifier` (slice 5a). Discovers
/// candidates in a real corpus, packages it, and builds+runs a verifier per
/// candidate, returning the polarity-correct result taxonomy:
///
///   - `SafeStore` (correct copy-on-write) → `.verifiedSafe` (no false positive)
///   - `LeakyStore` (shared reference, non-`mutating` leak) → `.confirmedLeak`
///   - `ClosureCounter` (stored closure capturing a heap `var`) → `.confirmedLeak`,
///     caught only by the kit v3.5.0 multi-step interleaving law
///
/// Spawns real `swift build`s resolving the path-dependency + the kit; tagged
/// `.subprocess` (runs under `make batch*`, skipped by `make test-fast`).
@Suite("ValueSemantic verify corpus — measured (slice 3–5a)", .tags(.subprocess))
struct ValueSemanticVerifyMeasuredTests {

    @Test("the production verifier reports correct-CoW safe and both leak shapes as confirmed leaks")
    func measuredValueSemanticVerify() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("vs-verify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let results = try ValueSemanticVerifier.verify(
            targetDirectory: Self.fixtureDirectory,
            moduleName: "ValueSemanticCorpus",
            workParent: parent
        )

        func status(_ typeName: String) -> ValueSemanticVerifyResult.Status? {
            results.first { $0.typeName == typeName }?.status
        }

        if case .verifiedSafe = status("SafeStore") {
            // Correct CoW: mutation on a copy clones storage; original untouched.
        } else {
            Issue.record("SafeStore expected verifiedSafe; got \(String(describing: status("SafeStore")))")
        }
        if case .confirmedLeak = status("LeakyStore") {
            // Shared reference: the copy's append leaks into the original.
        } else {
            Issue.record("LeakyStore expected confirmedLeak; got \(String(describing: status("LeakyStore")))")
        }
        if case .confirmedLeak = status("ClosureCounter") {
            // Closure capture: caught only by the multi-step interleaving law.
        } else {
            Issue.record("ClosureCounter expected confirmedLeak; got \(String(describing: status("ClosureCounter")))")
        }
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("valuesemantic-verify-corpus")
    }()
}
