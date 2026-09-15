import Foundation
import SwiftInferCore

/// Every emitted stub lives in its own namespace, so two stubs can share a test function's name.
///
/// ## The collision this closes (#467)
///
/// Each emitter names its test from the bare function name — `@Test func matches_isTotal()` — at
/// the top level of the file. A module holding five `matches(_:)` predicates on five types would
/// therefore declare `matches_isTotal()` five times, and one `invalid redeclaration` fails the whole
/// test target, taking every other stub with it. Until now that never surfaced, because the five
/// *files* were written to one path and overwrote each other: four laws were lost silently instead.
///
/// Giving each file a distinct name, which #467 asked for, would have turned the silent loss into
/// the broken build. So the test functions move inside a type first. **The type is named from the
/// file's base name**, which SwiftPM already requires to be unique within a module (it names object
/// files per base name — #431), so one key keeps the path, the object file and the test namespace
/// unique together.
///
/// ## Why a wrapper here and not a rename in each emitter
///
/// A dozen emitters set `testFunctionName:` independently. Renaming each would leave the next arm
/// to get it wrong; wrapping in the one place every accepted stub passes through cannot be missed.
/// A `struct` rather than an `enum`, because Swift Testing runs a non-`static` `@Test` only in a
/// type it can initialise. Verified under Swift 6.3: two suites each declaring `matches_isTotal()`
/// build and run, the same pair unwrapped fails with `invalid redeclaration`, and the emitted
/// `private func approximatelyEqual` helper still resolves as a method from the `@Sendable`
/// property closure.
extension InteractiveTriage {

    /// The suite type a stub file's tests live in: its base name as a Swift identifier, plus `Tests`.
    ///
    /// `normalize_idempotence.swift` → `normalize_idempotenceTests`;
    /// `parse_input-totality.swift` → `parse_input_totalityTests`.
    static func suiteName(forStubFileName fileName: String) -> String {
        let base = fileName.hasSuffix(".swift") ? String(fileName.dropLast(".swift".count)) : fileName
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        var identifier = String(base.map { allowed.contains($0) ? $0 : "_" })
        if identifier.first.map(\.isNumber) ?? true { identifier = "_" + identifier }
        return identifier + "Tests"
    }

    /// `stub` inside `struct <suiteName> { … }`.
    ///
    /// The body is indented for the reader — **unless it holds a multi-line string literal**, whose
    /// value indentation would change. No stub in the corpus funnel census does (0 of 3,279 files),
    /// so today this always indents; the check keeps a future emitter from being silently altered.
    static func namespaced(_ stub: String, suiteName: String) -> String {
        let body = stub.hasSuffix("\n") ? String(stub.dropLast()) : stub
        let indented = body.contains("\"\"\"")
            ? body
            : body.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? "" : "    " + $0 }
                .joined(separator: "\n")
        return "struct \(suiteName) {\n\(indented)\n}\n"
    }

    /// Where an accepted stub is written: `SwiftInfer/<template>/<name>`, the name made collision-free
    /// by `collisionFreeStubFileName`, with a note when it had to be.
    static func stubDestination(for suggestion: Suggestion, context: Context) -> URL {
        let directory = context.generatedRoot.appendingPathComponent("SwiftInfer/\(suggestion.templateName)")
        let preferred = stubFileName(for: suggestion) ?? "\(suggestion.identity.normalized).swift"
        let (fileName, displaced) = collisionFreeStubFileName(preferred: preferred, for: suggestion, in: directory)
        if let displaced {
            context.diagnostics.writeDiagnostic(
                "note: \(suggestion.templateName)/\(preferred) already holds the stub for suggestion "
                    + "\(displaced); writing \(fileName) instead, so neither is lost"
            )
        }
        return directory.appendingPathComponent(fileName)
    }

    /// The file name to write `suggestion`'s stub under in `directory`: `preferred`, unless a file
    /// already there belongs to a **different** suggestion — then `preferred` with the identity's
    /// first eight hex digits appended, and the name of the stub it would have replaced.
    ///
    /// ## What the declaring-type prefix cannot separate
    ///
    /// Two overloads on one type (`matches(_: String)` and `matches(_: Int)` share a display name),
    /// a sanitiser clash (`A.B_c` and `A_B.c`), and a file an earlier run left for a suggestion this
    /// run does not re-offer. None was measured in the census sample; all end the same way if they
    /// happen — `Data.write(options: .atomic)` replaces the file without a word, which is the defect
    /// #467 is about. So the write asks first.
    ///
    /// **Keyed on the stub's own `// Suggestion identity:` line, not on existence.** Re-accepting the
    /// same suggestion must regenerate its file in place, and triage only re-offers a suggestion
    /// whose decision was cleared — so an existing file with the *same* identity is this stub, and
    /// one with a different identity is someone else's. One check covers a collision within a run
    /// (the earlier stub is already on disk) and against a previous run alike.
    static func collisionFreeStubFileName(
        preferred: String,
        for suggestion: Suggestion,
        in directory: URL
    ) -> (fileName: String, displaced: String?) {
        let existing = directory.appendingPathComponent(preferred)
        guard let contents = try? String(contentsOf: existing, encoding: .utf8) else {
            return (preferred, nil)
        }
        // A file with no identity line is not provably this stub — hand-written, or its header
        // edited away — and is treated as someone else's, never overwritten.
        let occupant = recordedIdentity(in: contents)
        guard occupant != suggestion.identity.display else { return (preferred, nil) }
        let base = preferred.hasSuffix(".swift") ? String(preferred.dropLast(".swift".count)) : preferred
        return ("\(base)_\(suggestion.identity.normalized.prefix(8)).swift", occupant ?? "with no identity line")
    }

    /// The `// Suggestion identity: 0x…` a generated stub records in its header, or `nil`.
    static func recordedIdentity(in contents: String) -> String? {
        let marker = "// Suggestion identity: "
        guard let line = contents.split(separator: "\n").first(where: { $0.hasPrefix(marker) }) else { return nil }
        return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
    }
}
