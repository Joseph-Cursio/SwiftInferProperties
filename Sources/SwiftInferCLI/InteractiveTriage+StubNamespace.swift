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
}
