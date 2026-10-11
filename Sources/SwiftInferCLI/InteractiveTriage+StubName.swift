import Foundation
import SwiftInferCore

/// What an accepted stub's file is called — and, since that name changed, what it used to be.
///
/// ## The file is named for the suite it declares (2026-10-10)
///
/// The words are unchanged: the declaring type, the function (two for a round trip, a key path
/// for an invariant), and the template. They used to be joined with `_` and the template kept its
/// hyphen — `AnalysisProgress_progress_documented-range.swift` — and the suite type was derived
/// from that, `AnalysisProgress_progress_documented_rangeTests`. So every stub tripped two
/// SwiftLint rules in the target it was written into: `type_name` (an error, for the underscores)
/// and `file_name` (no type in the file matches the file's name). Now the words are joined in
/// UpperCamelCase with `Tests` after them, and the file and the suite carry the same name —
/// `AnalysisProgressProgressDocumentedRangeTests.swift` declaring
/// `struct AnalysisProgressProgressDocumentedRangeTests`.
///
/// One name still keys the path, the object file and the test namespace, as #467 arranged:
/// SwiftPM requires a file's base name to be unique within a module, and the suite's name *is*
/// that base name. Joining without a separator can make two names that used to differ the same
/// (`Foo.barBaz` and `FooBar.baz`); `collisionFreeStubFileName` catches that exactly as it catches
/// any other clash, by the identity recorded in the file already there.
extension InteractiveTriage {

    static func stubFileName(for suggestion: Suggestion) -> String? {
        stubNameWords(for: suggestion).map { upperCamelIdentifier($0) + "Tests.swift" }
    }

    /// The file for a suggestion `stubFileName` has no words for: named for its identity.
    static func fallbackStubFileName(for suggestion: Suggestion) -> String {
        "Suggestion\(suggestion.identity.normalized)Tests.swift"
    }

    /// The words a stub's name is built from, in order.
    ///
    /// **The template belongs in the name, not only in the directory.** The writeout is
    /// `<root>/SwiftInfer/<template>/<name>.swift`, unique by path and not by base name — and
    /// SwiftPM names object files per base name within a module, so a function matching two
    /// templates broke the whole test target (`multiple producers`; measured on
    /// SwiftMarkdownWiki, `union` under associativity and commutativity).
    ///
    /// **The declaring type belongs in it too (#467).** Unique per function and template is not
    /// unique per *type*: five `matches(_:)` predicates on five types wrote one file, and the
    /// census counted 149 stubs lost that way. A free function has no declaring type.
    ///
    /// A lifted suggestion (TestLifter M3.3) is named for the test method it was lifted from.
    static func stubNameWords(for suggestion: Suggestion) -> [String]? {
        if let origin = suggestion.liftedOrigin {
            return [origin.testMethodName, "lifted", suggestion.templateName]
        }
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName) else {
            return nil
        }
        var words = evidence.qualifiedTypeName.map { [$0] } ?? []
        words.append(CalleeReference(bareName: funcName).identifierName)
        switch suggestion.templateName {
        case "round-trip":
            if let reverse = suggestion.evidence.dropFirst().first,
               let reverseName = functionName(from: reverse.displayName) {
                words.append(CalleeReference(bareName: reverseName).identifierName)
            }

        case "invariant-preservation":
            // Distinct invariants on one function must not overwrite each other.
            if let keyPath = invariantKeypath(from: evidence.signature) { words.append(keyPath) }

        default:
            break
        }
        words.append(suggestion.templateName)
        return words
    }

    /// `["AnalysisProgress", "progress", "documented-range"]` → `AnalysisProgressProgressDocumentedRange`.
    ///
    /// Every run of ASCII letters and digits is a word, capitalised and kept as written after its
    /// first letter, so `tokenizeLine` stays `TokenizeLine`. A name that would start with a digit
    /// gets `Stub` in front, since a type name cannot.
    static func upperCamelIdentifier(_ words: [String]) -> String {
        let joined = words.map { upperCamel($0, spellingOperators: false) }.joined()
        guard let first = joined.first, first.isLetter else { return "Stub" + joined }
        return joined
    }

    /// `raw`'s ASCII letter-and-digit runs, each capitalised, joined. With `spellingOperators`,
    /// an operator character becomes its word (`+` → `Plus`) instead of a break — except `-`,
    /// which is what separates a kebab-case template name.
    static func upperCamel(_ raw: String, spellingOperators: Bool) -> String {
        var words: [String] = []
        var current = ""
        for char in raw {
            if char.isASCII, char.isLetter || char.isNumber {
                current.append(char)
                continue
            }
            if !current.isEmpty { words.append(current) }
            current = ""
            if spellingOperators, char != "-", let word = CalleeReference.operatorCharacterWords[char] {
                words.append(word)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.map(CalleeReference.capitalized).joined()
    }

    // MARK: - The name before 2026-10-10

    /// The file name `stubFileName` gave before stubs were named for their suite —
    /// `AnalysisProgress_progress_documented-range.swift` — so a re-accept can find the file an
    /// older run wrote for the same suggestion (`supersededStubFiles`).
    static func legacyStubFileName(for suggestion: Suggestion) -> String? {
        if let origin = suggestion.liftedOrigin {
            let method = sanitizeForFileName(origin.testMethodName)
            return "\(method)_lifted_\(sanitizeForFileName(suggestion.templateName)).swift"
        }
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName) else {
            return nil
        }
        let template = sanitizeForFileName(suggestion.templateName)
        var middle = funcName
        if suggestion.templateName == "round-trip",
           let reverse = suggestion.evidence.dropFirst().first,
           let reverseName = functionName(from: reverse.displayName) {
            middle += "_\(reverseName)"
        }
        if suggestion.templateName == "invariant-preservation",
           let keyPath = invariantKeypath(from: evidence.signature) {
            middle += "_" + keyPath.replacingOccurrences(of: "\\.", with: "").replacingOccurrences(of: ".", with: "_")
        }
        let unqualified = "\(middle)_\(template).swift"
        guard let owner = evidence.qualifiedTypeName else { return unqualified }
        return "\(sanitizeForFileName(owner))_\(unqualified)"
    }

    /// Files in `directory` an older run wrote for `suggestion` under the name it used then — the
    /// legacy name, or that name with the identity suffix a clash gave it — identified by the
    /// `// Suggestion identity:` line they record.
    ///
    /// Without this, re-accepting a suggestion whose stub predates the rename would write the new
    /// file beside the old one: both would build (their suites differ in name), and the law would
    /// run twice, the old copy keeping every lint violation the rename was for.
    static func supersededStubFiles(for suggestion: Suggestion, in directory: URL) -> [URL] {
        guard let legacy = legacyStubFileName(for: suggestion) else { return [] }
        let base = String(legacy.dropLast(".swift".count))
        let candidates = [legacy, "\(base)_\(suggestion.identity.normalized.prefix(8)).swift"]
        return candidates.map { directory.appendingPathComponent($0) }.filter { url in
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return recordedIdentity(in: contents) == suggestion.identity.display
        }
    }

    /// Replace `/`, whitespace, and other path-hostile characters with `_`. Hyphens are kept —
    /// they are the natural shape of `Suggestion.templateName`.
    private static func sanitizeForFileName(_ raw: String) -> String {
        let allowed: Set<Character> = Set(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
        )
        return String(raw.map { allowed.contains($0) ? $0 : "_" })
    }
}
