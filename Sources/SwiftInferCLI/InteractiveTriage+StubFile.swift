import Foundation
import SwiftInferCore

extension InteractiveTriage {

    /// Wrap the bare `@Test func` block from `LiftedTestEmitter` with
    /// the file-level imports + provenance header for the
    /// `Tests/Generated/SwiftInfer/` writeout. Lifted-origin suggestions
    /// get an extra "Lifted from" line (TestLifter M3.3) distinct from
    /// the `// Source:` assertion-site pointer.
    static func wrappedFileContents(
        stub: String,
        suggestion: Suggestion,
        moduleUnderTest: String? = nil
    ) -> String {
        let location = suggestion.evidence.first?.location
        let sourceLine = location.map { loc in "// Source: \(loc)" } ?? ""
        // Import the module under test so the generated file compiles drop-in.
        // `@testable` reaches internal functions (the common case for the free /
        // internal helpers seeds point at).
        //
        // **Two sources, and the second one is why any of this compiles for an app.** The
        // per-file `Sources/<Module>/` layout answers for a conventional package. It cannot
        // answer for `SwiftMarkdownWiki/Editor/EditorFormatter.swift`, which has no `Sources/`
        // component — and that is the layout `--sources` exists to serve, not a synthetic
        // fixture. The run's manifest-resolved module is consulted next.
        //
        // When neither answers, the file says so on the line that will fail. Emitting nothing
        // was the defect: 0 of 19 stubs named the module under test and nothing reported it, so
        // the failure arrived as an unresolved-symbol error in code the reader did not write
        // (#415).
        let resolvedModule = location.flatMap { Self.moduleName(fromSourceFile: $0.file) }
            ?? moduleUnderTest
        let moduleImport = resolvedModule
            .map { "@testable import \($0)\n" }
            ?? "// TODO: no module resolved for this subject — add `@testable import <YourModule>`"
                + " (this file will not compile until you do)\n"
        let liftedLine = suggestion.liftedOrigin.map { origin in
            "// Lifted from \(origin.sourceLocation)"
                + " \(origin.testMethodName)()"
        } ?? ""
        // TestLifter M4.4 — mock-inferred suggestions get a provenance
        // line surfacing construction-site count + .low confidence.
        let mockLine: String = {
            guard suggestion.generator.source == .inferredFromTests,
                  let mock = suggestion.mockGenerator else {
                return ""
            }
            return "// Mock-inferred from \(mock.siteCount) construction"
                + " site\(mock.siteCount == 1 ? "" : "s") in test bodies — low confidence"
                + " (verify the generator covers your domain)"
        }()
        // TestLifter M5.4 — Codable round-trip suggestions get a
        // provenance line surfacing the .medium confidence and the
        // user-action requirement (replacing the placeholder fixture
        // before the generator buys you a real round-trip property).
        let codableLine: String = {
            guard suggestion.generator.source == .derivedCodableRoundTrip else {
                return ""
            }
            return "// Codable round-trip generator scaffold — medium confidence"
                + " (replace the fixture inside the generator body before this"
                + " property exercises real values)"
        }()
        // The access caveat the reader was shown at triage, carried into the file that cannot
        // compile without it.
        //
        // A `private` subject surfaces ON PURPOSE — `SeededPrivateFunctionTests` records the
        // decision and the reasoning: *"purity, shape and role decide whether a law is worth
        // proposing; access level decides what must happen before it can be verified. Access
        // belongs in the advice, never in the gate."* The advice was shown, was correct, and was
        // then dropped at exactly the moment it became actionable — accept wrote a file whose
        // only diagnostic is `'trimmed' is inaccessible due to 'private' protection level`, in
        // code the reader did not write (#428).
        //
        // Read from the `.subjectNotVisibleToTests` signal rather than re-derived, so the remedy
        // has one author: `AccessRestriction.remedy`, the same sentence triage printed.
        let accessLine = Self.accessCaveat(for: suggestion)

        // Foundation, unconditionally. It used to be added only for the Codable round-trip
        // generator scaffold, which needs `JSONEncoder`. That is not the only thing that
        // needs it: a package enabling the `MemberImportVisibility` upcoming feature — this
        // one does — requires every file touching a Foundation member to import it, and a
        // subject like `mimeType` or `bucketURL` reaches Foundation through its own types.
        // An unused import is a no-op; a missing one is a build failure in generated code.
        let foundationImport = "import Foundation\n"
        return """
        // Auto-generated by `swift-infer discover --interactive` — do not edit.
        \(sourceLine)
        \(liftedLine)
        \(mockLine)
        \(codableLine)
        // Suggestion identity: \(suggestion.identity.display)
        // Template: \(suggestion.templateName)
        \(Self.lawClassLine(for: suggestion))\(accessLine)
        \(foundationImport)import Testing
        import PropertyBased
        import PropertyLawKit
        \(moduleImport)\(stub)
        """
    }

    /// What a **pass** of this test is allowed to mean.
    ///
    /// ## The two are byte-indistinguishable today, and one of them is a guess
    ///
    /// An emitted `idempotence` test and an emitted `input-totality` test differ only in the
    /// template name in the header. One is a law a correct implementation **cannot** fail; the
    /// other is read off a type shape and a verb, and a correct implementation can fail it. A
    /// green tick reports both identically.
    ///
    /// **Measured across two subjects: entailed laws 3 run, 0 false; conjectures 5 run, 3 false**
    /// (`roadtest-swiftmarkdownwiki.md`, `roadtest-swift-argument-parser.md`). The class
    /// predicted every outcome.
    ///
    /// The sharp case is #453. `mimeType_idempotence` was emitted, compiled, ran 100 trials and
    /// **passed**, and the law is false — its counterexamples are the three literals `css`, `js`
    /// and `woff2`, which the generator cannot produce. Nothing in the emitted file, and nothing
    /// in any count the pipeline reports, separates that from the three totality laws that
    /// genuinely passed beside it.
    ///
    /// ## Why the class and not the tier
    ///
    /// Carrying the **tier** was the obvious cheap fix and was measured not to work: `parse` and
    /// `parseQuery` are Possible 30 and true, `mimeType` is Possible 20 and false — the same tier
    /// with opposite verdicts. `Refutability.isRoleEntailed` is the distinction that separated
    /// every outcome, and it already reaches the CLI and gates `isWorthSurfacingBelowCut`. It
    /// simply never reached the test target.
    ///
    /// ## What this does not do
    ///
    /// It does not make a conjecture true, catch a false pass, or change which laws are emitted.
    /// It tells the reader which kind of claim a green tick is, which is the whole of the fix —
    /// #453's other two directions were measured and declined on population.
    static func lawClassLine(for suggestion: Suggestion) -> String {
        if Refutability.isRoleEntailed(suggestion) {
            return """
            // Law class: ENTAILED — a correct implementation cannot fail this, so a pass is a
            //            statement about the code.

            """
        }
        return """
        // Law class: CONJECTURE — read from the signature and the name, not entailed by either,
        //            so a CORRECT implementation can fail it. A pass means no counterexample was
        //            found in the trials drawn, NOT that the law holds: a law whose
        //            counterexamples lie outside the generator's reach passes while being false.

        """
    }

    /// The access caveat block, or empty for a subject a test can reach.
    static func accessCaveat(for suggestion: Suggestion) -> String {
        guard let signal = suggestion.score.signals.first(where: { $0.kind == .subjectNotVisibleToTests })
        else { return "" }
        let edit = widenTarget(for: suggestion).map { "// \($0)\n" } ?? ""
        return "// Access: \(signal.detail)\n\(edit)// This file will not compile until that is done.\n"
    }

    /// The exact edit that unblocks a restricted subject — `Delete `private` at Foo.swift:42` —
    /// or `nil` when the declaration line carries no modifier to delete.
    ///
    /// **`nil` is an answer, not a shortfall.** The line carrying no `private` is the
    /// enclosing-type case: a member of a `private` type is unreachable *whatever its own
    /// modifier says*, so naming a word to delete would propose a patch that compiles and
    /// changes nothing. `SpeculativeWidening`'s own doc calls that the design's named trap, and
    /// records that it was live for a while because a doc asserted a guard nothing implemented.
    /// The general remedy sentence above still prints; only the specific edit is withheld.
    ///
    /// Reuses `SpeculativeWidening.leadingAccessModifier` rather than re-deriving: the
    /// word-boundary rule there exists because a function named `privateKeyFor(_:)` must not read
    /// as a `private` declaration, and a second copy of that rule is exactly the kind that drifts.
    static func widenTarget(for suggestion: Suggestion) -> String? {
        guard let location = suggestion.evidence.first?.location,
              location.line > 0,
              let source = try? String(contentsOfFile: location.file, encoding: .utf8) else {
            return nil
        }
        let lines = source.components(separatedBy: "\n")
        let index = location.line - 1
        guard lines.indices.contains(index),
              let modifier = SpeculativeWidening.leadingAccessModifier(in: lines[index]) else {
            return nil
        }
        let name = URL(fileURLWithPath: location.file).lastPathComponent
        return "Delete `\(modifier)` at \(name):\(location.line), or lift the logic out."
    }

    /// The module under test, derived from a source file path laid out the SPM
    /// way (`.../Sources/<Module>/<File>.swift`). Returns `nil` for paths with no
    /// `Sources/` component (e.g. unit-test fixtures), so the `@testable import`
    /// is added only when it can be inferred — keeping generated tests drop-in
    /// compilable for real packages without guessing for synthetic ones.
    static func moduleName(fromSourceFile path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        guard let sourcesIndex = components.lastIndex(of: "Sources"),
              sourcesIndex + 1 < components.count else {
            return nil
        }
        let candidate = components[sourcesIndex + 1]
        return candidate.hasSuffix(".swift") ? nil : moduleIdentifier(from: candidate)
    }

    /// The Swift module name SwiftPM synthesizes for a target directory. SwiftPM
    /// replaces every character that isn't valid in a Swift identifier with `_`,
    /// so the directory `swift-clone-detector` is imported as
    /// `swift_clone_detector`. Emitting the raw directory name produced
    /// `@testable import swift-clone-detector`, which is a syntax error and broke
    /// every generated stub for a hyphen- or dot-named target.
    static func moduleIdentifier(from targetDirectory: String) -> String {
        let allowed: Set<Character> = Set(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
        )
        return String(targetDirectory.map { allowed.contains($0) ? $0 : "_" })
    }

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
