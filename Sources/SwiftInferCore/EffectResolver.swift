import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax

/// Resolves each function's idempotency effect **across files**, including the
/// effects nothing wrote down — a function that calls a `@NonIdempotent` one is
/// itself non-idempotent, and no amount of reading its declaration will say so.
///
/// **Opt-in, and the opt-in is the design.** `FunctionScanner` parses one file at
/// a time and throws the tree away, and its own comment says the one-pass shape
/// exists to keep the §13 budget intact. `EffectSymbolTable.applyBodyInference`
/// needs every tree at once and carries a 30-second default wall-clock budget
/// against §13's 2-second discover budget. So this is a **separate pass that
/// re-parses**, rather than a change to the scan: the default path stays
/// byte-identical and cannot regress, and only a caller that asked pays.
///
/// **What it does NOT do, and why the asymmetry is not laziness.** Upward
/// inference takes the *least upper bound* of a body's callee effects, so an
/// inferred `pure` / `idempotent` means only "nothing this calls is worse than
/// that" — which does not make the caller idempotent. `f(x) = g(x) + 1` with a
/// pure `g` infers pure and is plainly not idempotent. **Only the
/// retry-hostile direction carries information upward**, so this resolver
/// surfaces `nonIdempotent` / `externallyIdempotent` and deliberately discards
/// an inferred `idempotent`. Reporting the latter would manufacture
/// corroboration out of an absence.
public enum EffectResolver {

    /// Fills `inferredEffect` on every summary whose effect can be resolved from
    /// a body rather than a declaration. Returns the summaries in input order.
    ///
    /// Declared effects are left where they are: `FunctionSummary.declaredEffect`
    /// is already populated at scan time and outranks this by construction
    /// (`lookupWithProvenance` orders declared > upward-inferred), so a function
    /// that annotates itself never has its own claim overwritten by a weaker one
    /// derived from what it happens to call.
    public static func resolve(
        summaries: [FunctionSummary],
        in directory: URL,
        diagnostic: (String) -> Void = { _ in /* no-op */ }
    ) -> [FunctionSummary] {
        let sources = parseSources(in: directory)
        guard !sources.isEmpty else { return summaries }

        var table = EffectSymbolTable()
        for source in sources {
            table.merge(source: source)
        }
        // `{ _, _ in nil }` disables the heuristic-downward classifier on
        // purpose. It guesses effects for unannotated callees from their NAMES
        // — the shape of inference this repo has repeatedly measured as a
        // precision cost — and a veto built on a name guess would suppress a
        // true law because a callee was called `save`. Only effects a human
        // actually declared propagate upward here.
        table.applyBodyInference(to: sources, multiHop: false) { _, _ in nil }

        var resolvedCount = 0
        let updated = summaries.map { summary -> FunctionSummary in
            guard summary.declaredEffect == nil,
                  let inference = table.upwardInference(for: signature(of: summary)),
                  carriesInformationUpward(inference.effect)
            else { return summary }
            resolvedCount += 1
            return summary.withInferredEffect(inference.effect)
        }
        if resolvedCount > 0 {
            diagnostic(
                "resolved \(resolvedCount) retry-hostile effect(s) from function bodies "
                    + "across \(sources.count) file(s) — these were declared on a CALLEE, "
                    + "not on the function itself"
            )
        }
        return updated
    }

    /// Only the retry-hostile tiers survive the trip upward. See the type doc:
    /// an inferred `pure` / `idempotent` / `observational` is a statement about
    /// a function's callees, not about the function.
    public static func carriesInformationUpward(_ effect: Effect) -> Bool {
        switch effect {
        case .nonIdempotent, .externallyIdempotent:
            return true

        case .pure, .observational, .idempotent:
            return false
        }
    }

    /// The signature key, matching `DeclarationShape.from(declaration:)`'s
    /// convention exactly — `firstName.text`, with `"_"` for a suppressed label.
    /// Getting this wrong is silent: every lookup misses, the pass resolves
    /// nothing, and the result is indistinguishable from a codebase with no
    /// annotations. `EffectResolverTests` pins it against a real parse for that
    /// reason rather than asserting the mapping in isolation.
    static func signature(of summary: FunctionSummary) -> FunctionSignature {
        FunctionSignature(
            name: summary.name,
            argumentLabels: summary.parameters.map { $0.label ?? "_" }
        )
    }

    /// Internal rather than private so `EffectResolverTests` can build the same
    /// table the pass builds and assert the signature key finds it. A test that
    /// re-implemented this would only prove two copies of the assumption agree.
    static func parseSources(in directory: URL) -> [SourceFileSyntax] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        // Sorted so the table's collision policy sees files in a deterministic
        // order — two runs over the same tree must resolve the same way.
        let paths = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map(\.path)
            .sorted()

        return paths.compactMap { path in
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
            return Parser.parse(source: text)
        }
    }
}
