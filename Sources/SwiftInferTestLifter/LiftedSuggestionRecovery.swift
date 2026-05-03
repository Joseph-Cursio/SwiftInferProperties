import SwiftInferCore

/// TestLifter M3.1 — type recovery + promotion in one pass; widened
/// in M4.2 with a setup-region annotation tier.
///
/// Looks up each lifted suggestion's callee name(s) in a
/// `[FunctionSummary]` index (the same index `TemplateEngine`
/// consumes via `TypeShapeBuilder.shapes(from:)`) and derives the
/// `(typeName, returnType)` pair to feed into
/// `LiftedSuggestion.toSuggestion(typeName:returnType:origin:)`.
///
/// **Three-tier recovery ladder (M4.2):**
/// 1. **FunctionSummary match.** Strict callee-name lookup against the
///    production-side scanner index. When matched, parameter / return /
///    receiver types come from the summary directly.
/// 2. **Setup-region annotation.** When the FunctionSummary tier
///    misses, look up the *binding name* the detection referred to
///    (round-trip's `inputBindingName`, idempotence's
///    `inputBindingName`, commutativity's `leftArgName`/`rightArgName`)
///    in a `[bindingName: typeName]` map produced by
///    `SetupRegionTypeAnnotationScanner.annotations(in: slice)`. The
///    map covers `let x: T = ...` typed bindings + `let x = T(...)`
///    bare-constructor bindings. M4.2 plan default — strict FunctionSummary
///    is preferred, annotation is the fallback.
/// 3. **`nil` → `?`-sentinel evidence.** When neither tier matches,
///    promotion synthesizes `?` sentinel evidence and the downstream
///    `GeneratorSelection` pass (M3.2 in `Discover+Pipeline`) leaves
///    the generator at `.notYetComputed`, which the M3.3 accept-flow
///    renders as `.todo<?>()`. M4.3's `MockGeneratorSynthesizer`
///    extends this last rung with mock-inferred `Gen<T>` synthesis
///    when the type's construction record meets the §13 ≥3-site
///    threshold.
///
/// **Per-pattern type derivation:**
/// - **Idempotence** (`f: (T) -> T`):
///   - Free / static `f`: `typeName = parameters[0].typeText`
///   - Instance method on `T` with no args (`a.normalize()`):
///     `typeName = containingTypeName`
/// - **Commutativity** (`f: (T, T) -> T`):
///   - Free / static `f`: `typeName = parameters[0].typeText`
///   - Instance method on `T` with one arg (`a.merge(b)`):
///     `typeName = containingTypeName`
/// - **Round-trip** (`forward: (T) -> U`, `backward: (U) -> T`):
///   - Forward must be a one-arg unary function. `typeName = forward.
///     parameters[0].typeText` (or `containingTypeName` for the
///     instance-method `a.encode()` shape), `returnType = forward.
///     returnTypeText`. Backward's signature is the inverse —
///     `LiftedSuggestion.toSuggestion(...)` synthesizes that from
///     `(typeName, returnType)` swap.
///
/// **Receiver-type recovery via `containingTypeName`** — no detector
/// extension needed. The plan note about extending `DetectedX` with a
/// `receiverTypeName` field was over-eager: `FunctionSummary` already
/// carries the containing type name for instance methods, so a single
/// FunctionSummary lookup recovers both free-function param types and
/// instance-method receiver types from the same source. Detection
/// stays purely syntactic per its M1+M2 contract.
public enum LiftedSuggestionRecovery {

    /// Promote `lifted` to a `Suggestion`, recovering callee types from
    /// `summariesByName` (a name → first-match `FunctionSummary` map),
    /// falling back to `setupAnnotations` (M4.2's binding-name → typeName
    /// map produced by `SetupRegionTypeAnnotationScanner`) when the
    /// FunctionSummary lookup misses. Returns the promoted Suggestion
    /// regardless of whether recovery succeeded — when neither tier
    /// matches, `?`-sentinel evidence + `.notYetComputed` generator
    /// metadata flow through.
    ///
    /// - Parameters:
    ///   - lifted: The TestLifter-side detection record.
    ///   - summariesByName: First-match index by `FunctionSummary.name`.
    ///     Multiple summaries with the same name (overloads, methods on
    ///     different types) collide; the map's value is whichever
    ///     `summariesByName.merge` policy the caller chose. The
    ///     `Discover+Pipeline` builder (M3.2) keeps the first occurrence
    ///     because TestLifter's callee-name match is itself ambiguous —
    ///     we can't tell which overload the test body referred to
    ///     without semantic resolution, so the conservative choice is
    ///     to recover *some* type rather than no type.
    ///   - setupAnnotations: M4.2 second-tier fallback — the per-test-method
    ///     `[bindingName: typeName]` map from
    ///     `SetupRegionTypeAnnotationScanner.annotations(in:)`. Consulted
    ///     only when FunctionSummary lookup fails. Defaulted empty for
    ///     callers that don't compute the map (unit tests with hand-built
    ///     LiftedSuggestions).
    ///   - origin: Optional override for the originating test method's
    ///     `LiftedOrigin`. Defaults to `lifted.origin` (populated by
    ///     `TestLifter.discover` during the M3.2 plumbing pass); unit
    ///     tests with hand-built `LiftedSuggestion`s without origin can
    ///     pass an explicit value here.
    public static func recover(
        _ lifted: LiftedSuggestion,
        summariesByName: [String: FunctionSummary],
        setupAnnotations: [String: String] = [:],
        origin: LiftedOrigin? = nil
    ) -> Suggestion {
        let (typeName, returnType) = recoverTypes(
            for: lifted.pattern,
            summariesByName: summariesByName,
            setupAnnotations: setupAnnotations
        )
        return lifted.toSuggestion(
            typeName: typeName,
            returnType: returnType,
            origin: origin ?? lifted.origin
        )
    }

    /// Returns just the recovered `typeName` (the generator-relevant
    /// T) for `lifted` per the per-pattern derivation rules. `nil`
    /// when neither FunctionSummary lookup nor `setupAnnotations`
    /// fallback yields a type (or the matched summary's shape doesn't
    /// fit the expected per-pattern arity).
    ///
    /// M3.2's `Discover+Pipeline` calls this to build the
    /// `[SuggestionIdentity: String]` index `GeneratorSelection`
    /// requires — same `T` the promoted Suggestion's evidence already
    /// carries, just exposed as a structured value rather than parsed
    /// back out of a signature string.
    public static func recoveredTypeName(
        for lifted: LiftedSuggestion,
        summariesByName: [String: FunctionSummary],
        setupAnnotations: [String: String] = [:]
    ) -> String? {
        let (typeName, _) = recoverTypes(
            for: lifted.pattern,
            summariesByName: summariesByName,
            setupAnnotations: setupAnnotations
        )
        return typeName
    }

    // MARK: - Per-pattern type recovery

    private static func recoverTypes(
        for pattern: DetectedPattern,
        summariesByName: [String: FunctionSummary],
        setupAnnotations: [String: String]
    ) -> (typeName: String?, returnType: String?) {
        switch pattern {
        case .roundTrip(let detection):
            let summaryTypes = roundTripTypes(
                forward: detection.forwardCallee,
                summariesByName: summariesByName
            )
            if summaryTypes.typeName != nil {
                return summaryTypes
            }
            // Fallback: annotation lookup on the input binding name.
            // Round-trip carries no return-type info on the binding side
            // (the binding holds T, not U), so annotation-only recovery
            // returns (T, nil) — the promotion adapter synthesizes a
            // backward-side `?` sentinel for the return type and the
            // accept-flow renders `.todo` for the round-trip's U side.
            // The forward-side T is recoverable; that's M4.2's bar.
            if let annotated = setupAnnotations[detection.inputBindingName] {
                return (annotated, nil)
            }
            return (nil, nil)
        case .idempotence(let detection):
            let summaryType = unaryShapeType(
                for: detection.calleeName,
                summariesByName: summariesByName
            )
            if let summaryType {
                return (summaryType, summaryType)
            }
            if let annotated = setupAnnotations[detection.inputBindingName] {
                return (annotated, annotated)
            }
            return (nil, nil)
        case .commutativity(let detection):
            let summaryType = binaryShapeType(
                for: detection.calleeName,
                summariesByName: summariesByName
            )
            if let summaryType {
                return (summaryType, summaryType)
            }
            // For commutativity both operands share T. Try the leftArg
            // first; if that misses, try rightArg. Either annotation
            // hit recovers T.
            if let annotated = setupAnnotations[detection.leftArgName] {
                return (annotated, annotated)
            }
            if let annotated = setupAnnotations[detection.rightArgName] {
                return (annotated, annotated)
            }
            return (nil, nil)
        }
    }

    /// Round-trip: forward callee carries `(T) -> U`. Recover both
    /// halves from the forward summary; the toSuggestion adapter
    /// synthesizes the backward signature `(U) -> T` by swapping.
    private static func roundTripTypes(
        forward: String,
        summariesByName: [String: FunctionSummary]
    ) -> (typeName: String?, returnType: String?) {
        guard let summary = summariesByName[forward] else {
            return (nil, nil)
        }
        if summary.containingTypeName != nil, summary.parameters.isEmpty {
            // Instance-method round-trip shape (`a.encode()` returning U).
            // Receiver is T; return is U.
            return (summary.containingTypeName, summary.returnTypeText)
        }
        if summary.parameters.count == 1 {
            return (summary.parameters[0].typeText, summary.returnTypeText)
        }
        return (nil, nil)
    }

    /// Idempotence shape: `(T) -> T`. Either free `func f(_ x: T) -> T`
    /// or instance `extension T { func f() -> T }`.
    private static func unaryShapeType(
        for calleeName: String,
        summariesByName: [String: FunctionSummary]
    ) -> String? {
        guard let summary = summariesByName[calleeName] else {
            return nil
        }
        if summary.containingTypeName != nil, summary.parameters.isEmpty {
            return summary.containingTypeName
        }
        if summary.parameters.count == 1 {
            return summary.parameters[0].typeText
        }
        return nil
    }

    /// Commutativity shape: `(T, T) -> T`. Either free
    /// `func f(_ a: T, _ b: T) -> T` or instance
    /// `extension T { func f(_ b: T) -> T }`.
    private static func binaryShapeType(
        for calleeName: String,
        summariesByName: [String: FunctionSummary]
    ) -> String? {
        guard let summary = summariesByName[calleeName] else {
            return nil
        }
        if summary.containingTypeName != nil, summary.parameters.count == 1 {
            return summary.containingTypeName
        }
        if summary.parameters.count == 2 {
            return summary.parameters[0].typeText
        }
        return nil
    }

    // MARK: - Index construction

    /// First-match index from `[FunctionSummary]` for callers that have
    /// a flat summary list (e.g. `FunctionScannerCorpus.summaries`).
    /// Overloads + methods sharing a name collide; the *first* summary
    /// in source order wins — see the rationale on `recover(_:summariesByName:origin:)`.
    public static func summariesByName(_ summaries: [FunctionSummary]) -> [String: FunctionSummary] {
        var map: [String: FunctionSummary] = [:]
        for summary in summaries where map[summary.name] == nil {
            map[summary.name] = summary
        }
        return map
    }
}
