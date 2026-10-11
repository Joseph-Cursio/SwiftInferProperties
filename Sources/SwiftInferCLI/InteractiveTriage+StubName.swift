import Foundation
import SwiftInferCore

/// What an accepted stub's file is called.
extension InteractiveTriage {
    static func stubFileName(for suggestion: Suggestion) -> String? {
        // TestLifter M3.3 — lifted-origin suggestions get
        // `<TestMethodName>_lifted_<TemplateName>.swift` to disambiguate
        // from TemplateEngine writeouts in the same `<template>/` dir.
        if let origin = suggestion.liftedOrigin {
            let sanitizedMethod = sanitizeForFileName(origin.testMethodName)
            let sanitizedTemplate = sanitizeForFileName(suggestion.templateName)
            return "\(sanitizedMethod)_lifted_\(sanitizedTemplate).swift"
        }
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName) else {
            return nil
        }
        // **The template belongs in the file NAME, not only in the directory.**
        //
        // The writeout is `<root>/SwiftInfer/<template>/<name>.swift`, which is unique by path
        // and not by basename — and SwiftPM names object files per basename within a module, so
        // two same-named sources in one test target collide:
        //
        //     error: couldn't build …/union.swift.o because of multiple producers
        //
        // A function that matches two templates produces exactly that. Measured on
        // SwiftMarkdownWiki: 19 stubs, two collisions — `union` (associativity + commutativity)
        // and `modificationDate` (idempotence + monotonicity) — and the target does not build at
        // all, so the other seventeen are lost with them.
        //
        // Invisible until #414 and #415, because before those the files went somewhere nothing
        // compiled and could not have named the module anyway. The lifted-origin arm above has
        // carried the template since M3.3 for the neighbouring reason (disambiguating from
        // TemplateEngine writeouts *in the same directory*); this applies the same convention to
        // the arm that reaches a build.
        let template = sanitizeForFileName(suggestion.templateName)
        let unqualified: String = {
            switch suggestion.templateName {
            case "round-trip":
                guard let reverse = suggestion.evidence.dropFirst().first,
                      let reverseName = functionName(from: reverse.displayName) else {
                    return "\(funcName)_\(template).swift"
                }
                return "\(funcName)_\(reverseName)_\(template).swift"

            case "invariant-preservation":
                // File name carries the keypath suffix so distinct invariants
                // on the same function don't overwrite each other.
                guard let keyPath = invariantKeypath(from: evidence.signature) else {
                    return "\(funcName)_\(template).swift"
                }
                let suffix = keyPath
                    .replacingOccurrences(of: "\\.", with: "")
                    .replacingOccurrences(of: ".", with: "_")
                return "\(funcName)_\(suffix)_\(template).swift"

            default:
                return "\(funcName)_\(template).swift"
            }
        }()
        // **The declaring type belongs in the name too (#467).** The name above is unique per
        // function and template, not per *type*, and `Data.write(options: .atomic)` replaces
        // silently — so five `matches(_:)` predicates on five types wrote one file, and the census
        // counted 149 stubs lost that way. Every one sampled was a protocol-shaped family: `describes(_:)`
        // on three enums in one file, `combine(_:_:)` on `Sum`, `Rotation` and `Peak`. A free
        // function has no declaring type, keeps its name, and so every existing golden is unchanged.
        guard let owner = evidence.qualifiedTypeName else { return unqualified }
        return "\(sanitizeForFileName(owner))_\(unqualified)"
    }

    /// Replace `/`, whitespace, and other path-hostile characters with
    /// `_` so file-name components from `LiftedOrigin.testMethodName`
    /// or `Suggestion.templateName` (e.g. `"round-trip"` → `"round-trip"`,
    /// `"identity-element"` → `"identity-element"`) don't introduce
    /// path separators or shell-special characters into writeout paths.
    /// Hyphens are preserved — they're safe and they're the natural
    /// shape of `Suggestion.templateName` values.
    private static func sanitizeForFileName(_ raw: String) -> String {
        let allowed: Set<Character> = Set(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
        )
        return String(raw.map { allowed.contains($0) ? $0 : "_" })
    }
}
