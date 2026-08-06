import Foundation

/// Filters discovered suggestions down to those that touch a seeded function.
public enum SeedFocus {

    /// Keep only suggestions whose evidence references a seeded function.
    ///
    /// The join key is `(file basename, function base name)`. The linter and
    /// `swift-infer` scan the same files but may spell paths differently
    /// (a linter often reports a relative path or bare filename, while the
    /// scanner records an absolute path), so the **basename** is the reliable
    /// common denominator. The **function base name** strips parameter labels
    /// from the evidence display name — `add(_:_:)` → `add` — to match the
    /// bare symbol the linter emits.
    ///
    /// A pair suggestion (e.g. round-trip) is kept when *either* half is
    /// seeded: a property over a seeded function is relevant even if its
    /// partner wasn't independently flagged.
    ///
    /// **An empty manifest does not focus.** It used to: "focus on these zero functions" was read
    /// as "keep zero suggestions". That is defensible in isolation and ruinous in a pipeline,
    /// because the manifest is not authored by hand — it is whatever the linter happened to find.
    /// A linter with a blind spot emits an empty manifest, the filter throws away every genuine
    /// suggestion, and the reader is told "0 suggestions" by a tool that found several. Running
    /// the documented `lint → infer` pipeline was then *strictly worse* than running `swift-infer`
    /// alone. Focusing on nothing is not a request anyone makes; it is what a producer that found
    /// nothing looks like, and the honest response is to say so and not filter.
    /// Templates whose subject a seed manifest **cannot contain**, and which the focus must therefore
    /// never filter.
    ///
    /// The manifest holds what the linter's *pure-function* rule found. A state machine's moves are
    /// `Void`-returning **impure** mutators — `navigateToFolder(_:)`, `navigateUp()` — which that rule
    /// will never seed and never could. Join a state-machine suggestion against a pure-function
    /// manifest and it misses, every time, by construction.
    ///
    /// **Left unguarded, that is A1's disease in a new organ.** On the road-test fixture, discovery
    /// found exactly one suggestion that could ever fail — the state-machine law — and the focus threw
    /// it away, then synthesised six determinism laws that cannot fail. The reader was handed six
    /// suggestions, all tautologies, with the only refutable claim in the run in the bin. The
    /// documented `lint → infer` pipeline was once again *strictly worse* than running `swift-infer`
    /// alone, which is the precise sentence A1 was raised to delete.
    ///
    /// **The fix is not to make seeding additive.** That was considered and declined: focus exists to
    /// narrow a large codebase, and gutting it would cost more than it buys. The insight is narrower
    /// and truer — **the seed focus was designed to narrow a search for *pure functions***, and a
    /// template whose subject is impure by nature was never in that search to begin with. It is not
    /// being *narrowed out*; it was never in scope for narrowing.
    ///
    /// Adding a template here is a deliberate, reviewable act: state why a seed manifest could never
    /// name its subject. If the answer is "it could, the linter just doesn't yet," the fix belongs in
    /// the linter, not here.
    public static let seedIndependentTemplates: Set<String> = [
        // Subject: two impure `Void` mutators. A pure-function manifest cannot name them.
        "state-machine"
    ]

    /// **Only *analysable* seeds focus.** A kernel seed's symbol names the impure method the kernel
    /// is trapped inside, so joining on it would narrow the run to a function this tool must then
    /// refuse — a confident zero by a new route. Those seeds are reported to the reader instead; see
    /// `SeedKind`.
    ///
    /// **And a seed-independent suggestion is never filtered** — see `seedIndependentTemplates`.
    ///
    /// **A `carrier` seed joins on the type name alone, deliberately unscoped by file.** The two
    /// halves of the join disagree about which file is meaningful, so including it would be worse
    /// than useless:
    ///
    /// - the seed's `file` is where the linter's rule *fired* — the use site of a raw primitive;
    /// - a carrier suggestion's evidence sits wherever the type's members are declared.
    ///
    /// Measured on the producer's own fixture: `Percentage` is declared in `Domain.swift` and the
    /// seed points at `Report.swift`. That is the normal case, not a contrived one, so a
    /// `(file, symbol)` join would miss almost every carrier and the focus would quietly drop the
    /// laws these seeds exist to surface — the confident zero this whole file is written against.
    ///
    /// A type name is a far more distinctive key than a bare function name, which is what makes
    /// dropping the file scope tolerable here and not for functions: `add` collides across a
    /// codebase, `Percentage` rarely does.
    public static func filter(_ suggestions: [Suggestion], to manifest: SeedManifest) -> [Suggestion] {
        let focusing = manifest.analysableSeeds
        guard !focusing.isEmpty else { return suggestions }

        let functionSeeds = focusing.filter { $0.kind != .carrier }
        let keys = Set(functionSeeds.map { key(file: $0.file, symbol: $0.symbol) })
        let carriers = Set(focusing.filter { $0.kind == .carrier }.map(\.symbol))

        return suggestions.filter { suggestion in
            if seedIndependentTemplates.contains(suggestion.templateName) { return true }
            if let carrier = suggestion.carrierTypeName, carriers.contains(carrier) { return true }
            return suggestion.evidence.contains { evidence in
                keys.contains(key(file: evidence.location.file, symbol: functionBaseName(evidence.displayName)))
            }
        }
    }

    /// The suggestions the focus kept *because no manifest could ever have named them* — so the CLI
    /// can say so, rather than letting them look like a lucky seed match.
    public static func seedIndependent(in suggestions: [Suggestion]) -> [Suggestion] {
        suggestions.filter { seedIndependentTemplates.contains($0.templateName) }
    }

    /// The bare function name from an evidence display name: everything before
    /// the first `(`. `add(_:_:)` → `add`; a name with no parens is returned
    /// unchanged.
    static func functionBaseName(_ displayName: String) -> String {
        guard let paren = displayName.firstIndex(of: "(") else { return displayName }
        return String(displayName[..<paren])
    }

    private static func key(file: String, symbol: String) -> String {
        let base = URL(fileURLWithPath: file).lastPathComponent
        return "\(base)::\(symbol)"
    }
}
