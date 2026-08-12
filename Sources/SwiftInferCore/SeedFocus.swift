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
    public static func filter(
        _ suggestions: [Suggestion],
        to manifest: SeedManifest,
        declaredSubjects: Set<String> = []
    ) -> [Suggestion] {
        let focusing = manifest.analysableSeeds
        guard !focusing.isEmpty else { return suggestions }

        let functionSeeds = focusing.filter { $0.kind != .carrier }
        let keys = Set(functionSeeds.map { key(file: $0.file, symbol: $0.symbol) })
        let carriers = Set(focusing.filter { $0.kind == .carrier }.map(\.symbol))

        return suggestions.filter { suggestion in
            if seedIndependentTemplates.contains(suggestion.templateName) { return true }
            if isUnseedableLifted(suggestion, declaredSubjects: declaredSubjects) { return true }
            if let carrier = suggestion.carrierTypeName, carriers.contains(carrier) { return true }
            return suggestion.evidence.contains { evidence in
                keys.contains(key(file: evidence.location.file, symbol: functionBaseName(evidence.displayName)))
            }
        }
    }

    /// A law read out of a test whose subject **the scan never declared** — so no manifest
    /// over those sources could name it, and the focus does not get to discard it.
    ///
    /// The same rule as `seedIndependentTemplates`, applied per row instead of per template
    /// because liftedness is not a property of the template: `idempotence` arises both from
    /// source and from a test body, and only the second kind can be unnameable.
    ///
    /// **Why the check is "did the scan declare it" rather than "is it in a test file".**
    /// A lifted suggestion records `location` as the literal placeholder `<test-body>:0` —
    /// it carries no path at all, which is *also* the mechanical reason every lifted row is
    /// dropped today: the join key is `(file basename, symbol)` and `<test-body>` matches no
    /// seed's file, ever. So a path predicate cannot be written, and one keyed on liftedness
    /// alone would be wrong in the other direction — a law lifted from
    /// `#expect(mySort(input) == input.sorted())` has a subject the manifest can and SHOULD
    /// name, and `SeedFocus`'s standing rule sends that case to the linter, not here.
    ///
    /// Asking the scan closes both: a subject the run's own sources declare is seedable and
    /// stays subject to the focus; one they do not declare is out of the manifest's reach by
    /// construction. Note this is scoped to THIS run — a production function declared in a
    /// target you did not scan is correctly unnameable by a manifest for the target you did.
    ///
    /// Measured (#240): a `normalized(_:)` idempotence law lifted from a property suite,
    /// Strong tier, dropped by a manifest that named nothing in the scanned package — and
    /// dropped silently, unlike the role-entailed rescue which announces itself.
    static func isUnseedableLifted(
        _ suggestion: Suggestion,
        declaredSubjects: Set<String>
    ) -> Bool {
        guard suggestion.liftedOrigin != nil else { return false }
        // An empty set means the caller did not supply the scan's declarations. Answering
        // "unseedable" for every lifted row then would exempt them wholesale on no evidence,
        // so the conservative reading is that nothing is exempt.
        guard !declaredSubjects.isEmpty else { return false }
        let subjects = suggestion.evidence.map { functionBaseName($0.displayName) }
        guard !subjects.isEmpty else { return false }
        return !subjects.contains { declaredSubjects.contains($0) }
    }

    /// The lifted laws the focus kept because the scan never declared their subject — so the
    /// CLI can say so, the way it already does for `seedIndependentTemplates`. A row kept for
    /// a reason the reader cannot see is indistinguishable from a lucky seed match.
    public static func unseedableLifted(
        in suggestions: [Suggestion],
        declaredSubjects: Set<String>
    ) -> [Suggestion] {
        suggestions.filter { isUnseedableLifted($0, declaredSubjects: declaredSubjects) }
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
