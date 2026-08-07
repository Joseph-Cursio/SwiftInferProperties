import Foundation
import PropertyLawCore

/// A real Pass 2 for strategist-routed carriers, replacing the zero-trial
/// sentinel.
///
/// ## What was there before
///
/// `edgeSentinelSection()` emitted a hardcoded `print("VERIFY_EDGE_RESULT:
/// PASS")` with `TRIALS: 0`, justified as *"integral or `String` — no NaN/Inf
/// semantic, no edge pass needed."* That conflates *floating-point* edge cases
/// with edge cases. `Int.min` is the canonical arithmetic boundary — negation,
/// `abs` and magnitude fail there and nowhere else — and
/// `fixtures/verify-refutability` contains `mergedBound(_:)`, wrong *only* at
/// `Int.min`, which the verifier reported as holding.
///
/// ## Why this is a separate pass and not generator bias
///
/// The obvious fix — mix the boundary values into the default generator, as
/// V1.150 does for `String` — was built, measured, and reverted. It refutes
/// `mergedBound` at trial 6, but it also breaks integer verification generally:
/// `x + 1` traps at `Int.max`, and the repo *depends* on that being
/// unreachable. `VerifyPipelineLiftedIntegrationTests` says so outright —
/// *"`x + 1` overflow-traps only at `x == Int.max` — probability ~100/2⁶⁴ over
/// 100 trials, effectively zero."* At a 40% draw weight it is certain, and
/// three integration tests turned into `measured-error: trapped`.
///
/// So boundary values must live where a failure is **advisory** rather than a
/// verdict — which is exactly what `VerifyOutcome.edgeCaseAdvisory` is for, and
/// exactly how the floating-point path already treats `NaN`/`Infinity` (those
/// break real laws too). The default pass keeps its clean domain and its
/// verdict; the edge pass reports separately and cannot retract it.
///
/// ## How the body is produced
///
/// The composers are pure `(Inputs, GeneratorRecipe) -> String` functions that
/// read the generator solely from `recipe.expression`. So the edge body is the
/// **same composer** called with an edge recipe — no per-template duplication,
/// and the law can never drift between the two passes because there is only one
/// definition of it.
///
/// Two mechanical adjustments follow, both narrow and both asserted:
///
///  1. Marker rename `VERIFY_DEFAULT_*` → `VERIFY_EDGE_*`, so the existing
///     parser reads the second pass as the edge pass. The marker vocabulary is
///     a closed, documented contract (`VerifyResultParser`), which is what
///     makes a textual rename safe here.
///  2. The body is wrapped in `do { … }`. Both passes declare top-level
///     bindings with the same names (`defaultGenerator`, `applyOnce`, …); a
///     nested scope turns what would be redeclaration errors into ordinary
///     shadowing, without renaming anything.
extension StrategistDispatchEmitter {

    /// Curated boundary values for `carrier`, as Swift source, or `nil` when
    /// the carrier has no meaningful finite boundary set. A carrier answering
    /// `nil` here may still get an edge pass through its *members* — see
    /// `edgeMemberSpecs` — and only a carrier that fails both keeps the
    /// sentinel, with the renderer saying no edge pass ran.
    ///
    /// Unsigned types omit the negatives — `-1` does not compile as a `UInt`,
    /// and `min` is `0`.
    static func edgeDomainValues(for carrier: String) -> [String]? {
        guard let rawType = RawType(typeName: carrier) else { return nil }
        let signed: Set<RawType> = [.int, .int8, .int16, .int32, .int64]
        let unsigned: Set<RawType> = [.uint, .uint8, .uint16, .uint32, .uint64]
        if signed.contains(rawType) {
            return ["\(carrier).min", "\(carrier).max", "0", "-1", "1"]
        }
        if unsigned.contains(rawType) {
            return ["\(carrier).max", "0", "1"]
        }
        if rawType == .string {
            return Self.stringEdgeLiterals
        }
        return nil
    }

    /// String boundaries, as Swift literals. Deliberately a local copy: the
    /// kit's `RawType.stringEdgeCases` is internal to `PropertyLawCore`, and
    /// the *default* `String` generator is already edge-biased with that set
    /// (V1.150), so this pass exists to draw them **exclusively** rather than
    /// at a 2-in-5 weight — the difference between "reachable" and "checked".
    static let stringEdgeLiterals: [String] = [
        #""""#, #"" ""#, #""  ""#, #""\n""#, #""\t""#, #""-""#, #""- ""#, #""a\n- b""#
    ]

    /// A generator drawing **only** from `carrier`'s curated boundary set, or
    /// `nil` when it has none.
    static func edgeDomainGenerator(for carrier: String) -> String? {
        guard let values = edgeDomainValues(for: carrier), !values.isEmpty else {
            return nil
        }
        let list = values.joined(separator: ", ")
        return "Gen<\(carrier)?>.element(of: [\(list)] as [\(carrier)]).map { $0! }"
    }

    /// The kit's raw-type generator expressions, each paired with the
    /// boundary-only generator that replaces it.
    ///
    /// `RawType.generatorExpression` is a **closed, kit-owned vocabulary** of
    /// exact literals (`Gen<Int>.int()`, `Gen<Character>.letterOrNumber.string(of:
    /// 0...8)`, …), which is what makes matching them by string safe — the same
    /// argument the marker relabel below rests on. Raw types with no curated
    /// boundary set (`Bool`, `Double`, `Float`) are absent, so their leaves stay
    /// on the generator Pass 1 uses.
    static var boundarySubstitutions: [(defaultGenerator: String, boundaryGenerator: String)] {
        RawType.allCases.compactMap { rawType in
            guard let boundary = edgeDomainGenerator(for: rawType.rawValue) else { return nil }
            return (rawType.generatorExpression, boundary)
        }
    }

    /// Rewrite every raw-type generator inside a composed expression onto its
    /// boundary set, or `nil` when the expression contains none.
    ///
    /// ## Why the leaves and not the carrier
    ///
    /// A composed carrier — a struct, an enum with payloads, a tuple — is not a
    /// `RawType`, so `edgeDomainValues` answers `nil` for it and the whole
    /// carrier fell to the sentinel: **35 of the 130 `measured-bothPass`
    /// verdicts** in the frozen whole-corpus survey, 27% of the passing verdicts,
    /// reported with a boundary domain nothing had checked. But a composed
    /// carrier's boundary set is not a property of the carrier; it is the product
    /// of its leaves', and those *are* curated. `ReducerPin(moduleName: "",
    /// typeName: "", functionName: "")` is reachable from the leaf domains alone.
    ///
    /// ## Why textual, and not by threading each strategy's payload through
    ///
    /// The obvious alternative is to carry `[MemberSpec]` on the recipe and
    /// recompose with boundary member generators. It was built first, and
    /// **measured to reach nothing**: an A/B over the 37 sentinel entries moved
    /// **zero** of them, because every struct in that population declares a user
    /// `init` and so takes Tier 6 `.initializerBased`, not `.memberwiseArbitrary`
    /// — and `InitArgument` carries no `rawType` to key on. Threading each
    /// strategy's payload separately would mean a new branch per strategy, and a
    /// silent gap every time the kit adds one.
    ///
    /// Every strategy renders the *same* closed set of leaf generator literals,
    /// so substituting at that level reaches memberwise, initializer-based,
    /// enum-payload, tuple and composite carriers at once — and reaches a
    /// strategy added later without being told about it.
    ///
    /// A recursive carrier is excluded for free: its expression is
    /// `__genNode(3)`, which contains no leaf generator, so this returns `nil`
    /// and the sentinel stands. The helper *declaration* does contain them and is
    /// deliberately not swept — it is emitted once and shared with Pass 1.
    ///
    /// ## Every eligible leaf at once, not one at a time
    ///
    /// The alternative is per-slot rotation — n variants, leaf `k` at its
    /// boundary and the rest ordinary, combined with `Gen.oneOf`. Not chosen, for
    /// two reasons. The `Gen.oneOf` overload admitting heterogeneous sequence
    /// types is `@available(swift 6.2)` and delegates to `Gen.frequency`, which
    /// `GeneratorRecipeCompileSafetyTests` bans outright as a construct that does
    /// not compile in an older language mode; and n variants of an n-leaf `zip`
    /// is n² inlined generator expressions, in a repo whose CI has already lost a
    /// release to a type-check timeout on a 12-arm expression.
    ///
    /// The cost is real and worth stating: a law that breaks on *one* leaf at its
    /// boundary **with the others ordinary** is not reached. The boundary sets
    /// are not degenerate — `0`, `1`, `-1` for integers, `"-"` and `"a\n- b"` for
    /// strings — so mixed-magnitude combinations do occur, but that is
    /// mitigation, not coverage. Rotation is the open follow-up.
    static func boundarySweep(_ expression: String) -> String? {
        var swept = expression
        var substituted = false
        for (defaultGenerator, boundaryGenerator) in boundarySubstitutions
        where swept.contains(defaultGenerator) {
            swept = swept.replacingOccurrences(of: defaultGenerator, with: boundaryGenerator)
            substituted = true
        }
        return substituted ? swept : nil
    }

    /// A recipe drawing **only** from the curated boundary set. Same
    /// `Generator` shape as the default recipe, so every composer consumes it
    /// unchanged.
    static func edgeRecipe(from recipe: GeneratorRecipe) -> GeneratorRecipe? {
        let carrier = recipe.carrierTypeName
        // The carrier's own boundary set first: the precise answer when the
        // carrier IS a raw type, and it also covers the top-level `String`
        // carrier, whose default generator is already edge-biased (V1.150) and so
        // matches no entry in the substitution table.
        if let generator = edgeDomainGenerator(for: carrier) {
            return GeneratorRecipe(
                expression: generator,
                carrierTypeName: carrier,
                imports: recipe.imports,
                declarations: []
            )
        }
        guard let swept = boundarySweep(recipe.expression) else { return nil }
        return GeneratorRecipe(
            expression: swept,
            carrierTypeName: carrier,
            // The default recipe's imports verbatim: a leaf this sweep leaves
            // alone may name a module (`Foundation` for a `Date`) that a
            // recomposed import list would not carry.
            imports: recipe.imports,
            declarations: []
        )
    }

    /// Pass 2 for `inputs`, or the zero-trial sentinel when this carrier has no
    /// curated boundary set (or the composer emitted a shape the relabel does
    /// not understand).
    static func edgePassSection(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) throws -> String {
        guard let edge = edgeRecipe(from: recipe) else {
            return edgeSentinelSection()
        }
        let body = try defaultPassSection(inputs: inputs, recipe: edge)
        return edgePassBody(fromDefaultBody: body) ?? edgeSentinelSection()
    }

    /// Rewrite a composed default-pass body into the edge pass.
    ///
    /// Returns `nil` when the body carries no `VERIFY_DEFAULT_` marker at all —
    /// a composer shape this rewrite does not understand. Failing closed keeps
    /// a silently-markerless edge pass from being emitted, which would report
    /// PASS while asserting nothing: the exact defect this file exists to fix.
    static func edgePassBody(fromDefaultBody body: String) -> String? {
        guard body.contains("VERIFY_DEFAULT_") else { return nil }
        // The composers open with `// --- Pass 1: default … ---`. Reusing the
        // body verbatim carried that header inside Pass 2, so the emitted
        // workdir told a reader the boundary pass was the default one. Only the
        // banner is rewritten; the markers below are the parser's contract.
        let renamed = body
            .replacingOccurrences(of: "VERIFY_DEFAULT_", with: "VERIFY_EDGE_")
            .replacingOccurrences(of: "// --- Pass 1: default", with: "// --- Pass 2: boundary")
        let indented = renamed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "    \($0)" }
            .joined(separator: "\n")
        return """
        // --- Pass 2: curated boundary values (advisory) ---
        // Same law as Pass 1, drawn only from the carrier's boundary set. A
        // failure here is an ADVISORY: Pass 1 already returned a verdict over
        // the ordinary domain, and this pass cannot retract it.
        do {
        \(indented)
        }
        exit(0)
        """
    }
}
