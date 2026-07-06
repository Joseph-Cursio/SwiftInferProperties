import Foundation

/// Recognizes identity-stability candidates from a scanned corpus (pbt-book
/// Ch. 9 §9.3.3) — a textual corpus fold over `TypeDecl`s + `FunctionSummary`s.
///
/// A candidate is a **`class`** that (1) conforms to `Hashable` (folded across
/// its decls' inheritance clauses) and (2) has a mutation surface (non-`static`
/// `Void` instance methods — classes don't mark mutators `mutating`). The signal
/// is intentionally broad; the verifier confirms whether a mutation actually
/// disturbs the hash / equality. An all-immutable `Hashable` class (no mutation
/// surface) can't drift and is not surfaced.
public enum StableIdentityDiscoverer {

    public static func discover(
        typeDecls: [TypeDecl],
        functions: [FunctionSummary]
    ) -> [StableIdentityCandidate] {
        let hashableClasses = foldHashableClasses(typeDecls)
        var candidates: [StableIdentityCandidate] = []
        var seen: Set<String> = []
        for decl in typeDecls where decl.kind == .class {
            guard !seen.contains(decl.name), hashableClasses.contains(decl.name) else { continue }
            seen.insert(decl.name)

            let surface = mutationSurface(of: decl.name, functions: functions)
            guard !surface.isEmpty else { continue }   // immutable identity → can't drift

            candidates.append(StableIdentityCandidate(
                typeName: decl.name,
                location: decl.location,
                mutationSurface: surface
            ))
        }
        return candidates.sorted { lhs, rhs in
            (lhs.location.file, lhs.location.line, lhs.typeName)
                < (rhs.location.file, rhs.location.line, rhs.typeName)
        }
    }

    /// Convenience: scan a source directory and discover candidates.
    public static func discover(directory: URL) throws -> [StableIdentityCandidate] {
        let corpus = try FunctionScanner.scanCorpus(directory: directory)
        return discover(typeDecls: corpus.typeDecls, functions: corpus.summaries)
    }

    // MARK: - Signals

    /// Class names that list `Hashable` in some decl's inheritance clause
    /// (primary or extension).
    static func foldHashableClasses(_ typeDecls: [TypeDecl]) -> Set<String> {
        var classes: Set<String> = []
        var names: Set<String> = []
        for decl in typeDecls where decl.kind == .class {
            names.insert(decl.name)
        }
        for decl in typeDecls where names.contains(decl.name) {
            if decl.inheritedTypes.contains("Hashable") {
                classes.insert(decl.name)
            }
        }
        return classes
    }

    /// Non-`static`, `Void`-returning instance methods — the mutation surface
    /// (a class's mutators aren't marked `mutating`, so a `Void` return is the
    /// signal). Sorted by name.
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

    private static func returnsVoid(_ returnTypeText: String?) -> Bool {
        guard let text = returnTypeText else { return true }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed == "Void" || trimmed == "()"
    }
}
