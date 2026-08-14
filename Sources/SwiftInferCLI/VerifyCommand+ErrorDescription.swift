import Foundation

/// `VerifyError`'s user-facing text, split out of `VerifyCommand.swift`.
///
/// Mechanical: the enum's cases and its `description` grow together and the file hit the
/// 400-line cap. The rationale for each case lives with the case, in the declaration; what
/// moved here is only the rendering.
///
/// **Every message names a remedy, or says there is none.** That distinction is the point of
/// several of these strings — `monotonicityDomainNotComparable` exists precisely to stop a
/// reader being sent to write a `gen()` that cannot help.
extension VerifyError {

    public var description: String {
        switch self {
        case let .suggestionNotFound(prefix, closest):
            let suffix = closest.isEmpty
                ? ""
                : ". Nearest known hashes: \(closest.joined(separator: ", "))"
            return "swift-infer verify: no suggestion found with identity-hash prefix '\(prefix)'\(suffix)"

        case let .ambiguousPrefix(prefix, matches):
            return "swift-infer verify: identity-hash prefix '\(prefix)' is ambiguous — "
                + "matches \(matches.count) entries: \(matches.joined(separator: ", ")). "
                + "Lengthen the prefix to disambiguate."

        case let .indexMissing(path):
            return "swift-infer verify: SemanticIndex not found at \(path.path). "
                + "An explicit --index-path is used as-is. Run `swift-infer index "
                + "--target <X>` to build it (reindex-on-demand covers only the default path)."

        case let .indexEmpty(path):
            let location = path.map { "at \($0.path)" } ?? "(default path)"
            return "swift-infer verify: SemanticIndex \(location) has zero entries. "
                + "Run `swift-infer index --target <X>` to populate it."

        case let .unsupportedCarrier(carrier, expected):
            let expectedList = expected.joined(separator: ", ")
            return "swift-infer verify: no generator could be derived for carrier type "
                + "'\(carrier)', so there is no domain to quantify over. Carriers reachable "
                + "today: \(expectedList). The gate is a generator, not a release: this clears "
                + "when `DerivationStrategist` derives one for the type, or when the kit ships "
                + "it. A SwiftSyntax node needs no flag — the kit's PropertyLawSyntax is linked "
                + "into the verifier automatically when your own package depends on "
                + "swift-syntax. One declining anyway means either your package does not (an "
                + "Xcode project or a --sources run has no manifest to read), or the carrier is "
                + "generic or collection-shaped and takes the composite path instead."

        case let .buildFailed(exitCode, diagnostics):
            // `diagnostics` is already the extracted cause — see
            // `BuildDiagnostics`, and note that `swift build` puts compile
            // errors on *stdout*, which is why this used to print nothing.
            let snippet = diagnostics.isEmpty ? "(none captured)" : diagnostics
            return "swift-infer verify: `swift build` in the verifier workdir failed with "
                + "exit code \(exitCode). Compiler diagnosis:\n\(snippet)"

        case let .runnerCrashed(reason):
            return "swift-infer verify: verifier subprocess could not run: \(reason)"

        case let .unsupportedTemplate(template, expected):
            let expectedList = expected.joined(separator: ", ")
            return "swift-infer verify: template '\(template)' has no verify composer, so its "
                + "law is proposed but never executed. Templates that execute: \(expectedList). "
                + "The gate is a composer arm, not a release: a template becomes verifiable once "
                + "it is named in all of `TemplateName.verifiable`, the composer switch, "
                + "`resolveFunctionCalls` and `RenderShape.byTemplateName` — missing one is "
                + "silent, and differently silent each time."

        case let .unsupportedPair(forward, supported):
            let supportedList = supported.joined(separator: ", ")
            return "swift-infer verify: forward-side function '\(forward)' is not in the curated "
                + "round-trip pair list, so nothing names its inverse. Curated forwards: "
                + "\(supportedList). The list is curated because a round-trip pair cannot be "
                + "recovered from one entry — contrast `.missingPairedFunction`, where the pair "
                + "IS reconstructible and the remedy is re-indexing."

        case let .missingPairedFunction(template, primary):
            return "swift-infer verify: the '\(template)' entry for '\(primary)' records no "
                + "second function, so its law has nothing to compare against. This template "
                + "reconstructs its pair from the index rather than a curated list, and the "
                + "index persisted second-half names for round-trip only before 2026-08-08. "
                + "Re-run `swift-infer index` to repopulate the entry."

        case let .invalidArguments(reason):
            return "swift-infer verify: \(reason)"

        case let .monotonicityDomainNotComparable(domain):
            return "swift-infer verify: monotonicity domain '\(domain)' is not Comparable, so "
                + "`a ≤ b ⟹ f(a) ≤ f(b)` has no input ordering to quantify over. The "
                + "monotonicity stub orders the domain with `min`/`max`; a non-Comparable "
                + "domain is architecturally inapplicable, not a measurement gap."
        }
    }}
