import Foundation
import SwiftEffectInference
@testable import SwiftInferCore
import SwiftSyntax
import Testing

/// `EffectResolver` — cross-file, body-derived effects (`--resolve-effects`).
@Suite("EffectResolver — effects nothing wrote on the declaration")
struct EffectResolverTests {

    /// The signature key must match `DeclarationShape.from(declaration:)`'s
    /// convention exactly. Getting it wrong is **silent**: every lookup misses,
    /// the pass resolves nothing, and the output is indistinguishable from a
    /// codebase with no annotations — a confident zero. So this is asserted
    /// against a real parse of a real declaration rather than by restating the
    /// mapping, which would only prove the two copies of my assumption agree.
    @Test("The signature key round-trips against a real parse — the silent-miss guard")
    func signatureKeyMatchesTheParse() throws {
        try withTemporaryPackage(files: [
            "A.swift": """
            enum Host {
                /// @lint.effect non_idempotent
                static func labelled(first alpha: String, second beta: String) -> String { alpha }
                /// @lint.effect non_idempotent
                static func unlabelled(_ alpha: String) -> String { alpha }
            }
            """
        ]) { directory in
            let scanned = try FunctionScanner.scanCorpus(directory: directory).summaries
            var table = EffectSymbolTable()
            for source in EffectResolver.parseSources(in: directory) { table.merge(source: source) }

            for summary in scanned {
                // Recorded by SEI from the syntax; looked up by us from a summary.
                // If the two conventions ever diverge, this fails here rather than
                // as an unexplained absence of behaviour in a survey.
                #expect(
                    table.effect(for: EffectResolver.signature(of: summary)) == .nonIdempotent,
                    "no table entry for \(summary.name) — signature convention drifted"
                )
            }
        }
    }

    @Test("A caller of a NON-IDEMPOTENT function in another file resolves it")
    func crossFileUpwardInference() throws {
        try withTemporaryPackage(files: [
            "Callee.swift": """
            enum Callee {
                /// @lint.effect non_idempotent
                static func audit(_ text: String) -> String { text }
            }
            """,
            "Caller.swift": """
            enum Caller {
                static func normalize(_ text: String) -> String {
                    _ = Callee.audit(text)
                    return text
                }
                static func canonical(_ text: String) -> String { text }
            }
            """
        ]) { directory in
            let scanned = try FunctionScanner.scanCorpus(directory: directory).summaries
            let resolved = EffectResolver.resolve(summaries: scanned, in: directory)

            let normalize = try #require(resolved.first { $0.name == "normalize" })
            #expect(normalize.inferredEffect == .nonIdempotent)

            // The control matters as much as the subject: without it, a resolver
            // that marked EVERYTHING retry-hostile would pass the line above.
            let canonical = try #require(resolved.first { $0.name == "canonical" })
            #expect(canonical.inferredEffect == nil)
        }
    }

    /// The asymmetry that makes upward inference sound to use at all.
    @Test("An inferred pure/idempotent is DISCARDED — it says nothing about the caller")
    func retrySafeDirectionIsNotPropagated() throws {
        try withTemporaryPackage(files: [
            "A.swift": """
            enum Host {
                /// @lint.effect pure
                static func helper(_ value: Int) -> Int { value }
                // Infers `pure` upward — and is plainly NOT idempotent. Propagating
                // the retry-safe direction would manufacture corroboration from an
                // absence, which is the whole reason the filter exists.
                static func increment(_ value: Int) -> Int { helper(value) + 1 }
            }
            """
        ]) { directory in
            let scanned = try FunctionScanner.scanCorpus(directory: directory).summaries
            let resolved = EffectResolver.resolve(summaries: scanned, in: directory)
            let increment = try #require(resolved.first { $0.name == "increment" })
            #expect(increment.inferredEffect == nil)
        }
    }

    @Test("A function's OWN declaration outranks anything inferred from its body")
    func declarationWins() throws {
        try withTemporaryPackage(files: [
            "A.swift": """
            enum Host {
                /// @lint.effect non_idempotent
                static func audit(_ text: String) -> String { text }
                /// @lint.effect idempotent
                static func squash(_ text: String) -> String {
                    _ = audit(text)
                    return text
                }
            }
            """
        ]) { directory in
            let scanned = try FunctionScanner.scanCorpus(directory: directory).summaries
            let resolved = EffectResolver.resolve(summaries: scanned, in: directory)
            let squash = try #require(resolved.first { $0.name == "squash" })
            // The author claimed idempotent while calling something they declared
            // non-idempotent. That is their call to make: the two signals must not
            // both fire, or a -45 would silently dilute a +40 the author asked for.
            #expect(squash.declaredEffect == .idempotent)
            #expect(squash.inferredEffect == nil)
        }
    }

    @Test("Resolving an unannotated corpus changes nothing at all")
    func unannotatedCorpusIsUntouched() throws {
        try withTemporaryPackage(files: [
            "A.swift": """
            enum Host {
                static func alpha(_ text: String) -> String { beta(text) }
                static func beta(_ text: String) -> String { text }
            }
            """
        ]) { directory in
            let scanned = try FunctionScanner.scanCorpus(directory: directory).summaries
            let resolved = EffectResolver.resolve(summaries: scanned, in: directory)
            #expect(resolved == scanned)
        }
    }
}

// MARK: - Helpers

private func withTemporaryPackage(
    files: [String: String],
    _ body: (URL) throws -> Void
) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("effect-resolver-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for (name, contents) in files {
        try contents.write(
            to: root.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }
    try body(root)
}
