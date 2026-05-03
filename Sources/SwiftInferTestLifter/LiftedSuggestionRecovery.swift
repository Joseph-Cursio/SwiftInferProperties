import SwiftInferCore

/// TestLifter M3.1 — type recovery + promotion in one pass.
///
/// Looks up each lifted suggestion's callee name(s) in a
/// `[FunctionSummary]` index (the same index `TemplateEngine`
/// consumes via `TypeShapeBuilder.shapes(from:)`) and derives the
/// `(typeName, returnType)` pair to feed into
/// `LiftedSuggestion.toSuggestion(typeName:returnType:origin:)`.
///
/// **Strict FunctionSummary lookup only.** When the callee isn't in
/// the index, recovery returns `nil` for the missing types and the
/// promotion adapter synthesizes `?` sentinel evidence. The downstream
/// `GeneratorSelection` pass (M3.2 in `Discover+Pipeline`) sees no
/// `TypeShape` for `?` and leaves the generator at `.notYetComputed`,
/// which the M3.3 accept-flow renders as `.todo<?>()`. M3 plan open
/// decision #2 default `(a)` — setup-region annotation walking is
/// deferred to TestLifter M4 alongside mock-based generator synthesis.
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
    /// `summariesByName` (a name → first-match `FunctionSummary` map).
    /// Returns the promoted Suggestion regardless of whether recovery
    /// succeeded — failed lookups produce `?`-sentinel evidence and
    /// `.notYetComputed` generator metadata.
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
    ///   - origin: The originating test method's name + source location.
    ///     Threaded through to `Suggestion.liftedOrigin` per M3.3's
    ///     accept-flow file-naming + provenance contract.
    public static func recover(
        _ lifted: LiftedSuggestion,
        summariesByName: [String: FunctionSummary],
        origin: LiftedOrigin? = nil
    ) -> Suggestion {
        let (typeName, returnType) = recoverTypes(for: lifted.pattern, summariesByName: summariesByName)
        return lifted.toSuggestion(
            typeName: typeName,
            returnType: returnType,
            origin: origin
        )
    }

    // MARK: - Per-pattern type recovery

    private static func recoverTypes(
        for pattern: DetectedPattern,
        summariesByName: [String: FunctionSummary]
    ) -> (typeName: String?, returnType: String?) {
        switch pattern {
        case .roundTrip(let detection):
            return roundTripTypes(forward: detection.forwardCallee, summariesByName: summariesByName)
        case .idempotence(let detection):
            let typeName = unaryShapeType(for: detection.calleeName, summariesByName: summariesByName)
            return (typeName, typeName)
        case .commutativity(let detection):
            let typeName = binaryShapeType(for: detection.calleeName, summariesByName: summariesByName)
            return (typeName, typeName)
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
