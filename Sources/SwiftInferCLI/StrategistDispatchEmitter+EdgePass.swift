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
    /// the carrier has no meaningful finite boundary set (in which case the
    /// sentinel is still emitted and the renderer says no edge pass ran).
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

    /// A recipe drawing **only** from the curated boundary set. Same
    /// `Generator` shape as the default recipe, so every composer consumes it
    /// unchanged.
    static func edgeRecipe(from recipe: GeneratorRecipe) -> GeneratorRecipe? {
        let carrier = recipe.carrierTypeName
        guard let values = edgeDomainValues(for: carrier), !values.isEmpty else {
            return nil
        }
        let list = values.joined(separator: ", ")
        return GeneratorRecipe(
            expression: "Gen<\(carrier)?>.element(of: [\(list)] as [\(carrier)]).map { $0! }",
            carrierTypeName: carrier,
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
        let renamed = body.replacingOccurrences(of: "VERIFY_DEFAULT_", with: "VERIFY_EDGE_")
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
