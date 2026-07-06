import Foundation

/// Recognizes defensive-copy candidates from a scanned corpus — the reference-
/// type companion to `ValueSemanticDiscoverer` (pbt-book Ch. 9 §9.3). A textual
/// corpus fold over `TypeDecl`s + `FunctionSummary`s (no new AST pass).
///
/// A `class` is a candidate iff it declares a **copy method** — a curated
/// copy-verb name (`copy` / `clone` / `duplicate` / …), non-`static`, returning
/// its own type (or `Self`). High-precision: only classes that explicitly vend a
/// copy are surfaced. Constructibility / `Equatable` are carried for the
/// verify-readiness gate, not required for recognition.
public enum DefensiveCopyDiscoverer {

    /// Curated copy-method verbs. A `class` method with one of these names
    /// returning the class type is treated as its defensive copy.
    static let copyVerbs: Set<String> = [
        "copy", "copied", "clone", "cloned",
        "duplicate", "duplicated", "mutableCopy", "deepCopy"
    ]

    public static func discover(
        typeDecls: [TypeDecl],
        functions: [FunctionSummary]
    ) -> [DefensiveCopyCandidate] {
        let equatable = EquatableResolver(typeDecls: typeDecls)
        var candidates: [DefensiveCopyCandidate] = []
        var seen: Set<String> = []
        for decl in typeDecls where decl.kind == .class {
            guard !seen.contains(decl.name) else { continue }
            seen.insert(decl.name)

            guard let copyMethod = copyMethod(of: decl.name, functions: functions) else { continue }
            candidates.append(DefensiveCopyCandidate(
                typeName: decl.name,
                location: decl.location,
                copyMethodName: copyMethod,
                mutationSurface: mutationSurface(of: decl.name, functions: functions),
                equatability: equatable.classify(typeText: decl.name)
            ))
        }
        return candidates.sorted { lhs, rhs in
            (lhs.location.file, lhs.location.line, lhs.typeName)
                < (rhs.location.file, rhs.location.line, rhs.typeName)
        }
    }

    /// Convenience: scan a source directory and discover candidates.
    public static func discover(directory: URL) throws -> [DefensiveCopyCandidate] {
        let corpus = try FunctionScanner.scanCorpus(directory: directory)
        return discover(typeDecls: corpus.typeDecls, functions: corpus.summaries)
    }

    // MARK: - Signals

    /// The name of the class's copy method: a non-`static` curated copy-verb
    /// method returning the class's own type (or `Self`). First match wins.
    static func copyMethod(of typeName: String, functions: [FunctionSummary]) -> String? {
        functions
            .filter { summary in
                summary.containingTypeName == typeName
                    && !summary.isStatic
                    && copyVerbs.contains(summary.name)
                    && returnsOwnType(summary.returnTypeText, typeName: typeName)
            }
            .map(\.name)
            .min()
    }

    /// The mutation surface of a class: non-`static`, `Void`-returning instance
    /// methods (classes don't mark mutators `mutating`, so a `Void` return is
    /// the mutation signal; the copy method returns the class type and is
    /// excluded). Sorted by name for deterministic output.
    static func mutationSurface(
        of typeName: String,
        functions: [FunctionSummary]
    ) -> [MutationMethod] {
        functions
            .filter { summary in
                summary.containingTypeName == typeName
                    && !summary.isStatic
                    && returnsVoid(summary.returnTypeText)
            }
            .map { summary in
                MutationMethod(name: summary.name, isMutating: false, parameterCount: summary.parameters.count)
            }
            .sorted { ($0.name, $0.parameterCount) < ($1.name, $1.parameterCount) }
    }

    // MARK: - Text helpers

    private static func returnsOwnType(_ returnTypeText: String?, typeName: String) -> Bool {
        guard let text = returnTypeText?.trimmingCharacters(in: .whitespaces) else { return false }
        return text == typeName || text == "Self"
    }

    private static func returnsVoid(_ returnTypeText: String?) -> Bool {
        guard let text = returnTypeText else { return true }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed == "Void" || trimmed == "()"
    }
}
